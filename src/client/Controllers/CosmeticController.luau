--!strict
-- CosmeticController: draws what every character wears -- aura, trail and title -- from the attributes
-- CosmeticService publishes on it ("Cosmetic<Slot>" = a CosmeticConfig id). Kill effects and glyph skins
-- are events inside Vfx packets and are drawn by VfxLibrary; this file owns only what a body carries.
--
-- What an aura or a trail looks like is data (CosmeticConfig.AuraStyles and TrailStyles, D-148): coloured, in
-- the materials of the book, one layer for a Rare, two for an Epic, three with a small light core for a
-- Legendary. This file turns that data into instances and drives it. Every particle is EMITTED here, on the
-- one Heartbeat, by an accumulator per emitter (Pure/AuraMath.owed): the engine thins a Rate about nine
-- times at its automatic graphics quality (D-124), and an aura is exactly the effect whose density is its
-- meaning -- a legendary drawn at a ninth of itself was a few dots nobody saw.
--
-- Rule 8 still holds: every flow follows the quality tier and the lowest tier draws only the local player's
-- own. And while the local player fights -- a ranked match, the Battleground, the Erasure's arena -- every
-- aura and trail on this screen steps back (CosmeticConfig.Fight: fewer, fainter, unlit), so the glyphs keep
-- the colour of the fight.
--
-- One Heartbeat for everything that moves (paths, flows); no connection per character beyond the attribute
-- signals, and every instance lives in the Trove of the slot that built it, so a change of cosmetic, a
-- respawn or a departure leaves nothing behind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local AssetIds = require(Shared.Config.AssetIds)
local AuraMath = require(Shared.Pure.AuraMath)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Util.Palette)
local QualityConfig = require(Shared.Config.QualityConfig)
local Theme = require(UI.Theme)
local Trove = require(Packages.Trove)

local log = Log.new("CosmeticController")

type Deps = { QualityController: any, Localize: any, MatchController: any, TravelController: any }
type TroveType = typeof(Trove.new())
type Style = CosmeticConfig.Style

-- One stream of particles: its emitter, the attachment it is moved to before each particle, and what it owes.
type Flow = {
	Emitter: ParticleEmitter,
	Anchor: Attachment,
	Place: CosmeticConfig.Place,
	Emit: string,
	Owed: AuraMath.Flow,
	-- A trail's particles are laid by walking: they are owed only while the body moves.
	Moving: boolean,
	-- The hand the last drop fell from.
	Side: number,
}
-- One stroke of a ribbon on a moving path: the two attachments its Trail is drawn between.
type Runner = {
	Path: CosmeticConfig.Place,
	Stroke: number,
	Count: number,
	Upper: Attachment,
	Lower: Attachment,
	HalfWidth: number,
}
-- What one slot built on one character.
type Worn = {
	Trove: TroveType,
	Flows: { Flow },
	Runners: { Runner },
	-- Every ribbon, so a teleport can wipe what it would otherwise draw across the jump.
	Ribbons: { Trail },
}
type Tracked = {
	Character: Model,
	Root: BasePart,
	IsLocal: boolean,
	-- Where the ground is under the root, in root space (negative).
	Floor: number,
	Slots: { [string]: Worn },
	Trove: TroveType,
	-- Where the root was last frame; nil until the first frame is seen.
	Last: Vector3?,
}

local ATTRIBUTE_PREFIX = "Cosmetic"
local SLOTS = { "Aura", "Trail", "Title" }
-- Below this horizontal speed a character is standing, and a trail's particles are not laid.
local MOVING_STUDS_PER_SECOND = 1.5
-- How far a title is read from: past this it is noise over a crowd.
local TITLE_DISTANCE = 45
-- A body that moves further than this in one frame was teleported (the end of a match, the boss pads, a
-- Caret blink), and a ribbon would draw a stroke across the whole jump.
local TELEPORT_STUDS = 40
-- A ribbon narrows to this share of its width at its tail: a bare tapered wedge, which reads as a stroke.
local RIBBON_TAPER = 0.2
-- How far toward the camera a style's Front particles are drawn: a core's heart over its own halo.
local FRONT_Z = 0.2
local FIGHT = CosmeticConfig.Fight
local FLOW = CosmeticConfig.Flow
local INK = CosmeticConfig.Tones.Ink

local EMISSION: { [string]: Enum.NormalId } = {
	Up = Enum.NormalId.Top,
	Down = Enum.NormalId.Bottom,
	-- In and Out turn the attachment itself toward or away from the body's axis, and emit along its facing.
	In = Enum.NormalId.Front,
	Out = Enum.NormalId.Front,
}

local CosmeticController = {}

local quality: any
local localize: any
local matchController: any
local travelController: any
local tracked: { [Model]: Tracked } = {}
local random = Random.new()
-- Whether the local player is in a fight, as the match and the portals last said.
local fighting = false

local function toneRgb(tone: string?): { number }
	return CosmeticConfig.Tones[tone or "Ink"] or INK
end

local function textureId(key: string): string
	local asset = AssetIds.Textures[key]
	return if asset ~= nil then asset.Id else ""
end

-- A curve of values evenly spaced over a life (or a length).
local function evenly(values: { number }): NumberSequence
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local keypoints = table.create(#values)
	for index, value in ipairs(values) do
		keypoints[index] = NumberSequenceKeypoint.new((index - 1) / (#values - 1), value)
	end
	return NumberSequence.new(keypoints)
end

local function colorSequence(rgb: { number }, ramp: AuraMath.Ramp): ColorSequence
	local keypoints = {}
	for _, stop in ipairs(AuraMath.colors(rgb, ramp, INK, FLOW.HoldShare)) do
		table.insert(keypoints, ColorSequenceKeypoint.new(stop.Time, Palette.rgb(stop.Rgb)))
	end
	return ColorSequence.new(keypoints)
end

-- How much of a flow this client draws for this body: the tier's particle scale, nothing at all for somebody
-- else's on the floor tier, and the fight's share while the local player fights.
local function densityFor(entry: Tracked): number
	local tier: QualityConfig.TierDef = quality.def()
	local floorTier = quality.get() == QualityConfig.Order[#QualityConfig.Order]
	return AuraMath.density(tier.ParticleScale, entry.IsLocal, floorTier, fighting, FIGHT.Density)
end

local function newWorn(): Worn
	return { Trove = Trove.new(), Flows = {}, Runners = {}, Ribbons = {} }
end

local function attachment(worn: Worn, root: BasePart): Attachment
	local a = Instance.new("Attachment")
	a.Parent = root
	worn.Trove:Add(a)
	return a
end

-- A stream of particles: an emitter that never emits by itself (Rate 0, disabled), and the flow the Heartbeat
-- emits it by.
local function buildEmission(
	worn: Worn,
	entry: Tracked,
	spec: CosmeticConfig.Emission,
	rgb: { number },
	density: number,
	moving: boolean
)
	local anchor = attachment(worn, entry.Root)
	local e = Instance.new("ParticleEmitter")
	e.Texture = textureId(spec.Texture)
	e.Color = colorSequence(rgb, spec)
	e.LightEmission = AuraMath.glow(spec.Glow, fighting, FIGHT.Glow)
	e.LightInfluence = 0
	e.Brightness = 1
	e.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
	e.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	e.Size = evenly(spec.Size)
	e.Transparency = evenly(AuraMath.lifted(spec.Transparency, if fighting then FIGHT.Transparency else 0))
	e.SpreadAngle = Vector2.new(spec.Spread or 0, spec.Spread or 0)
	e.Acceleration = Vector3.new(0, spec.Rise or 0, 0)
	e.Drag = spec.Drag or 0
	-- A drop drawn long stays upright: turned at random it would be a streak flying sideways.
	e.Rotation = if spec.Stretch ~= nil then NumberRange.new(0) else NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(spec.Spin or 0), spec.Spin or 0)
	e.Squash = NumberSequence.new(spec.Stretch or 0)
	-- Flat: faces along its (upward) velocity, so it lies on the floor like the ink it is.
	e.Orientation = if spec.Flat == true
		then Enum.ParticleOrientation.VelocityPerpendicular
		elseif spec.Stretch ~= nil then Enum.ParticleOrientation.FacingCameraWorldUp
		else Enum.ParticleOrientation.FacingCamera
	e.ZOffset = if spec.Front == true then FRONT_Z else 0
	e.EmissionDirection = EMISSION[spec.Emit]
	e.Rate = 0
	e.Enabled = false
	e.Parent = anchor
	worn.Trove:Add(e)
	table.insert(worn.Flows, {
		Emitter = e,
		Anchor = anchor,
		Place = spec.Place,
		Emit = spec.Emit,
		Owed = { Rate = spec.Rate * density, Carry = 0 },
		Moving = moving,
		Side = 1,
	})
end

local function run(runner: Runner, now: number)
	local x, y, z = AuraMath.path(runner.Path, runner.Stroke, runner.Count, now)
	runner.Upper.Position = Vector3.new(x, y + runner.HalfWidth, z)
	runner.Lower.Position = Vector3.new(x, y - runner.HalfWidth, z)
end

-- Its strokes: a bare Trail each, between two attachments on its path. A still path is placed once; a
-- moving one is run by the Heartbeat.
local function buildRibbon(worn: Worn, entry: Tracked, spec: CosmeticConfig.Ribbon, rgb: { number })
	local now = os.clock()
	local head = math.min(spec.Transparency + (if fighting then FIGHT.Transparency else 0), 1)
	for stroke = 1, spec.Count do
		local runner: Runner = {
			Path = spec.Path,
			Stroke = stroke,
			Count = spec.Count,
			Upper = attachment(worn, entry.Root),
			Lower = attachment(worn, entry.Root),
			HalfWidth = spec.Width / 2,
		}
		run(runner, now)
		local trail = Instance.new("Trail")
		trail.Attachment0 = runner.Upper
		trail.Attachment1 = runner.Lower
		trail.Color = colorSequence(rgb, { Dries = spec.Dries })
		trail.LightEmission = 0
		trail.LightInfluence = 0
		trail.Lifetime = spec.Lifetime
		trail.MinLength = 0.1
		trail.FaceCamera = spec.FaceCamera == true
		trail.Transparency = NumberSequence.new(head, 1)
		trail.WidthScale = NumberSequence.new(1, RIBBON_TAPER)
		trail.Parent = entry.Root
		worn.Trove:Add(trail)
		table.insert(worn.Ribbons, trail)
		if spec.Path.Seconds ~= nil then
			table.insert(worn.Runners, runner)
		end
	end
end

local function buildStyles(
	styles: { [string]: Style },
	look: CosmeticConfig.Look,
	entry: Tracked,
	moving: boolean
): Worn
	local worn = newWorn()
	local density = densityFor(entry)
	-- Nothing at all rather than the ribbons alone: rule 8, an effect that cannot be shown is not played.
	if density <= 0 then
		return worn
	end
	for index, name in ipairs(look.Styles or {}) do
		local style = styles[name]
		if style == nil then
			log.warn("no style %s", name)
			continue
		end
		local rgb = toneRgb(if look.Tones ~= nil then look.Tones[index] else look.Tone)
		for _, emission in ipairs(style.Emissions or {}) do
			buildEmission(worn, entry, emission, rgb, density, moving)
		end
		for _, ribbon in ipairs(style.Ribbons or {}) do
			buildRibbon(worn, entry, ribbon, rgb)
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
	-- The interface's text colour, charcoal: Theme.Colors.Ink is the ink BAR, a pigment blue, and a title
	-- in a school's colour over a head is a colour that belongs to no glyph (rule 1).
	label.TextColor3 = Theme.Colors.Text
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
		worn = buildStyles(CosmeticConfig.AuraStyles, item.Look, entry, false)
	elseif slot == "Trail" then
		worn = buildStyles(CosmeticConfig.TrailStyles, item.Look, entry, true)
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

-- The ground under a root, in its own space: a Humanoid stands its root HipHeight plus half the root above
-- the floor; a body without one (or an R6 body, whose HipHeight is 0) is given the usual depth.
local function floorOf(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.HipHeight > 0 then
		return -(humanoid.HipHeight + root.Size.Y / 2)
	end
	return -CosmeticConfig.FloorDepth
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
		Floor = floorOf(character, root),
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

-- What a flow owes since the last frame, each particle born where its place says: the attachment is moved
-- there, turned toward or away from the body's axis for In and Out, and the emitter asked for one.
local function emitFlow(entry: Tracked, flow: Flow, dt: number, now: number)
	local count = AuraMath.owed(flow.Owed, dt, FLOW.MaxStepSeconds)
	for _ = 1, count do
		flow.Side = -flow.Side
		local x, y, z =
			AuraMath.point(flow.Place, entry.Floor, now, random:NextNumber(), random:NextNumber(), flow.Side)
		local at = Vector3.new(x, y, z)
		local axis = Vector3.new(0, y, 0)
		if (flow.Emit == "In" or flow.Emit == "Out") and (at - axis).Magnitude > 1e-3 then
			flow.Anchor.CFrame = if flow.Emit == "In" then CFrame.lookAt(at, axis) else CFrame.lookAt(at, at * 2 - axis)
		else
			flow.Anchor.Position = at
		end
		flow.Emitter:Emit(1)
	end
end

-- Every tracked body: its paths advance, and every flow emits what it owes -- a trail's only while its
-- wearer moves.
local function onHeartbeat(dt: number)
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
			for _, runner in ipairs(worn.Runners) do
				run(runner, now)
			end
			for _, flow in ipairs(worn.Flows) do
				if moving or not flow.Moving then
					emitFlow(entry, flow, dt, now)
				end
			end
		end
	end
end

-- A tier change or a fight redraws everything: the density, the fading and the light are set at build.
local function rebuildAll()
	for _, entry in pairs(tracked) do
		for _, slot in ipairs(SLOTS) do
			wear(entry, slot)
		end
	end
end

-- The local player is fighting while a match holds them or a portal has put them where others fight.
local function refreshFight()
	local now = matchController.getMatch() ~= nil or travelController.inFight()
	if now == fighting then
		return
	end
	fighting = now
	rebuildAll()
end

function CosmeticController.Init(deps: Deps)
	quality = deps.QualityController
	localize = deps.Localize
	matchController = deps.MatchController
	travelController = deps.TravelController
end

function CosmeticController.Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	quality.Changed:Connect(rebuildAll)
	matchController.MatchChanged:Connect(refreshFight)
	travelController.FightChanged:Connect(refreshFight)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (%d cosmetics)", #CosmeticConfig.Items)
end

return CosmeticController
