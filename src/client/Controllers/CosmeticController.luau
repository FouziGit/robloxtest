--!strict
-- CosmeticController: draws what every character wears -- aura, trail and title -- from the attributes
-- CosmeticService publishes on it ("Cosmetic<Slot>" = a CosmeticConfig id). Kill effects and glyph skins
-- are events inside Vfx packets and are drawn by VfxLibrary; this file owns only what a body carries.
--
-- What a cosmetic may look like is decided by docs/ART_BIBLE.md and written in CosmeticConfig's header:
-- the page's inks only (never a pigment, never white), rarity carried by craft rather than colour. And
-- rule 8, particle density is capped: an aura is the first thing a crowded fight gives up, so every rate
-- follows the quality tier and the lowest tier draws only the local player's own.
--
-- One Heartbeat for everything that moves (orbiting strokes, emitters that only run while walking); no
-- connection per character beyond the attribute signals, and every instance lives in the Trove of the
-- slot that built it, so a change of cosmetic, a respawn or a departure leaves nothing behind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local AssetIds = require(Shared.Config.AssetIds)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Util.Palette)
local QualityConfig = require(Shared.Config.QualityConfig)
local Theme = require(UI.Theme)
local Trove = require(Packages.Trove)

local log = Log.new("CosmeticController")

type Deps = { QualityController: any, Localize: any }
type TroveType = typeof(Trove.new())
type Tone = CosmeticConfig.Tone

-- One orbiting stroke: an attachment pair circling the root, which a Trail draws between.
type Orbit = { Upper: Attachment, Lower: Attachment, Phase: number, Radius: number }
-- What one slot built on one character.
type Worn = {
	Trove: TroveType,
	Orbits: { Orbit },
	-- Emitters that only run while the character is moving: a trail's dust is left by walking.
	Movers: { ParticleEmitter },
	-- Every ribbon, so a teleport can wipe what it would otherwise draw across the jump.
	Ribbons: { Trail },
}
type Tracked = {
	Character: Model,
	Root: BasePart,
	IsLocal: boolean,
	Slots: { [string]: Worn },
	Trove: TroveType,
	-- Where the root was last frame; nil until the first frame is seen.
	Last: Vector3?,
}

local ATTRIBUTE_PREFIX = "Cosmetic"
local SLOTS = { "Aura", "Trail", "Title" }
-- Below this horizontal speed a character is standing, and a trail's dust is not laid.
local MOVING_STUDS_PER_SECOND = 1.5
-- One turn of an orbiting stroke, in seconds, and how far it rises and falls while it goes round.
local ORBIT_SECONDS = 2.6
local ORBIT_BOB = 0.8
-- How far a title is read from: past this it is noise over a crowd.
local TITLE_DISTANCE = 45
-- A body that moves further than this in one frame was teleported (the end of a match, the boss pads, a
-- Caret blink), and a ribbon would draw a stroke across the whole jump.
local TELEPORT_STUDS = 40
-- Auras are born on a ring round the body, never inside it: a particle born in the torso is hidden by
-- the torso until it has drifted clear, which for a slow mote is most of its life (found by review).
local AURA_RING_RADIUS = 1.7
local AURA_RING_HEIGHTS = { 1.2, 0, -1.2 }

local CosmeticController = {}

local quality: any
local localize: any
local tracked: { [Model]: Tracked } = {}

local function toneColor(tone: Tone?): Color3
	local rgb = CosmeticConfig.Tones[(tone or "Ink") :: string] or CosmeticConfig.Tones.Ink
	return Palette.rgb(rgb)
end

local function textureId(key: string): string
	local asset = AssetIds.Textures[key]
	return if asset ~= nil then asset.Id else ""
end

-- How much of a style this client may draw for this character: the tier's particle scale, and nothing
-- at all for somebody else's aura on the floor tier.
local function density(isLocal: boolean): number
	local tier: QualityConfig.TierDef = quality.def()
	if not isLocal and quality.get() == QualityConfig.Order[#QualityConfig.Order] then
		return 0
	end
	return tier.ParticleScale
end

local function newWorn(): Worn
	return { Trove = Trove.new(), Orbits = {}, Movers = {}, Ribbons = {} }
end

type EmitterSpec = {
	Texture: string,
	Rate: number,
	Lifetime: { number },
	Speed: { number },
	Size: { number },
	Transparency: { number },
	Spread: number?,
	Acceleration: Vector3?,
	Drag: number?,
	RotSpeed: number?,
	Up: boolean?, -- emit along the parent's +Y rather than all round
}

local function emitter(worn: Worn, parent: Instance, color: Color3, spec: EmitterSpec, scale: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = textureId(spec.Texture)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0
	e.LightInfluence = 0
	e.Rate = spec.Rate * scale
	e.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
	e.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	e.Size = NumberSequence.new(spec.Size[1], spec.Size[2])
	e.Transparency = NumberSequence.new(spec.Transparency[1], spec.Transparency[2])
	e.SpreadAngle = Vector2.new(spec.Spread or 180, spec.Spread or 180)
	e.Acceleration = spec.Acceleration or Vector3.zero
	e.Drag = spec.Drag or 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(spec.RotSpeed or 0), spec.RotSpeed or 0)
	e.EmissionDirection = if spec.Up == true then Enum.NormalId.Top else Enum.NormalId.Front
	e.Enabled = scale > 0
	e.Parent = parent
	worn.Trove:Add(e)
	return e
end

local function attachment(worn: Worn, root: BasePart, position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Position = position
	a.Parent = root
	worn.Trove:Add(a)
	return a
end

-- A ribbon between two attachments. `faceCamera` for a thin stroke, which must read from every angle;
-- false for a band worn on the body, which stays the standing curtain it was drawn as (D-108).
local function ribbon(
	worn: Worn,
	a0: Attachment,
	a1: Attachment,
	color: Color3,
	lifetime: number,
	from: number,
	faceCamera: boolean
): Trail
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Texture = textureId("BrushStroke")
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 0
	trail.LightInfluence = 0
	trail.Lifetime = lifetime
	trail.MinLength = 0.1
	trail.FaceCamera = faceCamera
	trail.Transparency = NumberSequence.new(from, 1)
	trail.WidthScale = NumberSequence.new(1, 0.25)
	trail.Parent = a0.Parent
	worn.Trove:Add(trail)
	table.insert(worn.Ribbons, trail)
	return trail
end

-- The same emitter at points round the body, each carrying its share of the rate.
local function aroundBody(worn: Worn, root: BasePart, color: Color3, spec: EmitterSpec, scale: number)
	local points = #AURA_RING_HEIGHTS * 2
	local share = table.clone(spec)
	share.Rate = spec.Rate / points
	for index, height in ipairs(AURA_RING_HEIGHTS) do
		for side = 0, 1 do
			local angle = (index / #AURA_RING_HEIGHTS + side * 0.5) * 2 * math.pi
			local point = Vector3.new(math.cos(angle) * AURA_RING_RADIUS, height, math.sin(angle) * AURA_RING_RADIUS)
			emitter(worn, attachment(worn, root, point), color, share, scale)
		end
	end
end

-- Aura styles: what hangs around a body at rest. Rates are per second at the High tier.
local AURA: { [string]: (worn: Worn, root: BasePart, color: Color3, scale: number) -> () } = {
	Motes = function(worn, root, color, scale)
		aroundBody(worn, root, color, {
			Texture = "DustMote",
			Rate = 5,
			Lifetime = { 1.6, 2.6 },
			Speed = { 0.3, 1 },
			Size = { 0.2, 0 },
			Transparency = { 0.2, 1 },
			Acceleration = Vector3.new(0, 0.7, 0),
		}, scale)
	end,
	Wisps = function(worn, root, color, scale)
		local feet = attachment(worn, root, Vector3.new(0, -2.6, 0))
		emitter(worn, feet, color, {
			Texture = "SmokeSoft",
			Rate = 3,
			Lifetime = { 1.6, 2.4 },
			Speed = { 0.8, 1.6 },
			Size = { 0.8, 2.6 },
			Transparency = { 0.6, 1 },
			Spread = 25,
			Drag = 0.6,
			RotSpeed = 30,
			Up = true,
		}, scale)
	end,
	Drips = function(worn, root, color, scale)
		for _, side in ipairs({ -1, 1 }) do
			local hand = attachment(worn, root, Vector3.new(side * 1.3, -0.9, 0))
			emitter(worn, hand, color, {
				Texture = "InkBlot",
				Rate = 1.4,
				Lifetime = { 0.55, 0.8 },
				Speed = { 0, 0.2 },
				Size = { 0.22, 0.12 },
				Transparency = { 0.05, 1 },
				Acceleration = Vector3.new(0, -16, 0),
			}, scale)
		end
	end,
	Pages = function(worn, root, color, scale)
		aroundBody(worn, root, color, {
			Texture = "PaperScrap",
			Rate = 1.3,
			Lifetime = { 2.5, 3.5 },
			Speed = { 0.3, 0.8 },
			Size = { 0.38, 0.3 },
			Transparency = { 0.15, 1 },
			Acceleration = Vector3.new(0, 0.35, 0),
			RotSpeed = 70,
		}, scale)
	end,
	Soot = function(worn, root, color, scale)
		local feet = attachment(worn, root, Vector3.new(0, -2.4, 0))
		emitter(worn, feet, color, {
			Texture = "SmokeSoft",
			Rate = 6,
			Lifetime = { 0.8, 1.2 },
			Speed = { 2, 4 },
			Size = { 0.25, 0.6 },
			Transparency = { 0.35, 1 },
			Spread = 35,
			Up = true,
		}, scale)
	end,
	-- Two strokes traced round the wearer, a glyph being drawn in the air forever.
	Orbit = function(worn, root, color, scale)
		if scale <= 0 then
			return
		end
		for index = 1, 2 do
			local upper = attachment(worn, root, Vector3.zero)
			local lower = attachment(worn, root, Vector3.zero)
			ribbon(worn, upper, lower, color, 0.5, 0.15, true)
			table.insert(worn.Orbits, { Upper = upper, Lower = lower, Phase = (index - 1) * math.pi, Radius = 2.2 })
		end
	end,
}

-- Trail styles: what a body leaves when it moves.
local TRAIL: { [string]: (worn: Worn, root: BasePart, color: Color3, scale: number) -> () } = {
	Stroke = function(worn, root, color, _scale)
		local a0 = attachment(worn, root, Vector3.new(0, 0.9, 0.4))
		local a1 = attachment(worn, root, Vector3.new(0, -0.9, 0.4))
		ribbon(worn, a0, a1, color, 0.35, 0.3, false)
	end,
	Hairline = function(worn, root, color, _scale)
		local a0 = attachment(worn, root, Vector3.new(0, 0.28, 0.45))
		local a1 = attachment(worn, root, Vector3.new(0, 0.12, 0.45))
		ribbon(worn, a0, a1, color, 0.5, 0.15, true)
	end,
	Scrawl = function(worn, root, color, _scale)
		for _, height in ipairs({ 0.7, -0.5 }) do
			local a0 = attachment(worn, root, Vector3.new(0, height + 0.08, 0.45))
			local a1 = attachment(worn, root, Vector3.new(0, height - 0.08, 0.45))
			ribbon(worn, a0, a1, color, 0.45, 0.2, true)
		end
	end,
	Soot = function(worn, root, color, scale)
		local feet = attachment(worn, root, Vector3.new(0, -2.6, 0.3))
		table.insert(
			worn.Movers,
			emitter(worn, feet, color, {
				Texture = "SmokeSoft",
				Rate = 12,
				Lifetime = { 0.5, 0.9 },
				Speed = { 0.5, 1.5 },
				Size = { 0.5, 1.4 },
				Transparency = { 0.45, 1 },
				Spread = 40,
				Up = true,
			}, scale)
		)
	end,
	Scraps = function(worn, root, color, scale)
		local feet = attachment(worn, root, Vector3.new(0, -2.4, 0.3))
		table.insert(
			worn.Movers,
			emitter(worn, feet, color, {
				Texture = "PaperScrap",
				Rate = 4,
				Lifetime = { 0.9, 1.4 },
				Speed = { 1, 2.5 },
				Size = { 0.35, 0.25 },
				Transparency = { 0.1, 1 },
				Drag = 1.2,
				RotSpeed = 120,
				Up = true,
			}, scale)
		)
	end,
	Dust = function(worn, root, color, scale)
		local feet = attachment(worn, root, Vector3.new(0, -2.8, 0.3))
		table.insert(
			worn.Movers,
			emitter(worn, feet, color, {
				Texture = "DustMote",
				Rate = 16,
				Lifetime = { 0.6, 1 },
				Speed = { 0.4, 1.4 },
				Size = { 0.22, 0 },
				Transparency = { 0.2, 1 },
				Spread = 60,
				Up = true,
			}, scale)
		)
	end,
}

local function buildStyles(styles: { [string]: any }, look: CosmeticConfig.Look, entry: Tracked): Worn
	local worn = newWorn()
	local color = toneColor(look.Tone)
	local scale = density(entry.IsLocal)
	-- Nothing at all rather than the ribbons alone: rule 8, an effect that cannot be shown is not played.
	if scale <= 0 then
		return worn
	end
	for _, style in ipairs(look.Styles or {}) do
		local build = styles[style]
		if build ~= nil then
			build(worn, entry.Root, color, scale)
		else
			log.warn("no renderer for style %s", style)
		end
	end
	return worn
end

local function buildTitle(look: CosmeticConfig.Look, entry: Tracked): Worn?
	local head = entry.Character:FindFirstChild("Head")
	if look.TextKey == nil or head == nil or not head:IsA("BasePart") then
		return nil
	end
	local worn = newWorn()
	local board = Instance.new("BillboardGui")
	board.Name = "CosmeticTitle"
	board.Size = UDim2.fromOffset(240, 24)
	board.StudsOffset = Vector3.new(0, 2.1, 0)
	board.MaxDistance = TITLE_DISTANCE
	board.LightInfluence = 0
	board.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Title
	label.TextSize = Theme.Sizes.TextBody
	label.TextColor3 = Theme.Colors.Ink
	label.Text = localize.t(look.TextKey)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Panel
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = label
	label.Parent = board
	board.Parent = head
	worn.Trove:Add(board)
	return worn
end

local function wear(entry: Tracked, slot: string)
	local previous = entry.Slots[slot]
	if previous ~= nil then
		previous.Trove:Destroy()
		entry.Slots[slot] = nil
	end
	local id = entry.Character:GetAttribute(ATTRIBUTE_PREFIX .. slot)
	local item = if type(id) == "string" then CosmeticConfig.ById[id] else nil
	if item == nil or item.Slot ~= slot then
		return
	end
	local worn: Worn? = nil
	if slot == "Aura" then
		worn = buildStyles(AURA, item.Look, entry)
	elseif slot == "Trail" then
		worn = buildStyles(TRAIL, item.Look, entry)
	elseif slot == "Title" then
		worn = buildTitle(item.Look, entry)
	end
	if worn ~= nil then
		entry.Slots[slot] = worn
	end
end

local function untrack(character: Model)
	local entry = tracked[character]
	if entry == nil then
		return
	end
	tracked[character] = nil
	for _, worn in pairs(entry.Slots) do
		worn.Trove:Destroy()
	end
	entry.Trove:Destroy()
end

local function track(player: Player, character: Model)
	if tracked[character] ~= nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") or character.Parent == nil then
		return
	end
	local entry: Tracked = {
		Character = character,
		Root = root,
		IsLocal = player == Players.LocalPlayer,
		Slots = {},
		Trove = Trove.new(),
	}
	tracked[character] = entry
	for _, slot in ipairs(SLOTS) do
		entry.Trove:Connect(character:GetAttributeChangedSignal(ATTRIBUTE_PREFIX .. slot), function()
			wear(entry, slot)
		end)
		wear(entry, slot)
	end
	entry.Trove:Connect(character.AncestryChanged, function(_, parent: Instance?)
		if parent == nil then
			untrack(character)
		end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(track, player, character)
	end)
	if player.Character ~= nil then
		task.spawn(track, player, player.Character)
	end
end

-- A body that jumped: every ribbon forgets the path it would have drawn across the jump. Trail:Clear
-- wipes the segments; toggling Enabled stops the next one joining the new position to the old.
local function wipeRibbons(entry: Tracked)
	for _, worn in pairs(entry.Slots) do
		for _, trail in ipairs(worn.Ribbons) do
			trail.Enabled = false
			trail:Clear()
			trail.Enabled = true
		end
	end
end

-- Every tracked body: orbiting strokes advance, and a trail's dust runs only while its wearer moves.
local function onHeartbeat()
	local now = os.clock()
	for _, entry in pairs(tracked) do
		local position = entry.Root.Position
		local last = entry.Last
		if last ~= nil and (position - last).Magnitude > TELEPORT_STUDS then
			wipeRibbons(entry)
		end
		entry.Last = position
		local moving = (entry.Root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > MOVING_STUDS_PER_SECOND
		for _, worn in pairs(entry.Slots) do
			for _, mover in ipairs(worn.Movers) do
				mover.Enabled = moving and mover.Rate > 0
			end
			for _, orbit in ipairs(worn.Orbits) do
				local angle = now * (2 * math.pi / ORBIT_SECONDS) + orbit.Phase
				local center = Vector3.new(
					math.cos(angle) * orbit.Radius,
					math.sin(angle * 1.7) * ORBIT_BOB,
					math.sin(angle) * orbit.Radius
				)
				orbit.Upper.Position = center + Vector3.new(0, 0.12, 0)
				orbit.Lower.Position = center - Vector3.new(0, 0.12, 0)
			end
		end
	end
end

-- A tier change redraws everything: a rate set at build time is the only rate an emitter has.
local function rebuildAll()
	for _, entry in pairs(tracked) do
		for _, slot in ipairs(SLOTS) do
			wear(entry, slot)
		end
	end
end

function CosmeticController.Init(deps: Deps)
	quality = deps.QualityController
	localize = deps.Localize
end

function CosmeticController.Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	quality.Changed:Connect(rebuildAll)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (%d cosmetics)", #CosmeticConfig.Items)
end

return CosmeticController
