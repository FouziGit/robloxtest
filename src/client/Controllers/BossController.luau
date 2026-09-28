--!strict
-- BossController: the World Boss band. While the server holds an event (BossChanged snapshots) a
-- compact band sits at the top of the screen on an ink plate (D-147): the boss name, its health bar -- red,
-- since the boss is the danger, with the player's own hits left behind it in cyan and a mark at each phase --
-- the current phase, the time left, and the share of the damage the local player dealt, in cyan: ours. The
-- band disappears as soon as the snapshot is nil.
--
-- While an attack is telegraphed, a warning plate stands at two thirds of the screen's height: a red "!",
-- the attack's name, and a chevron turned, once, toward where the boss is. The floor's telegraph stays the
-- warning that counts (docs/ART_BIBLE.md rule 9); the plate is for a player looking at the boss rather than
-- the floor. While it is up the HUD holds its messages back.
--
-- Phase transitions are announced through the HUD toasts (announced / started / defeated / expired),
-- once per transition: the server pushes the same phase many times per event.
--
-- A practice (D-132) is the same Erasure in the same band, titled as a practice, and sent to its own
-- participants only. It opens straight into its fight -- it is never Announced -- so it never pulses the
-- page's lighting, which is the scheduled event's arrival and nobody else's.
--
-- The band is a child of the HUD's top-centre column (HudController.topStack), not a ScreenGui of its
-- own: three overlays pinned to the same rectangle drew over each other. It still lives and dies with
-- the event, by its Visible flag.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local HudPlate = require(UI.components.HudPlate)
local Log = require(Shared.Util.Log)
local Motion = require(UI.Motion)
local ProgressBar = require(UI.components.ProgressBar)
local Theme = require(UI.Theme)
local Types = require(Shared.Types)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)

local log = Log.new("BossController")

-- The band needs a real contract from the HUD: it parents itself into the shared top-centre column and
-- announces phase changes through the HUD toasts.
type HudApi = {
	topStack: () -> (Frame?, number),
	overlay: () -> Frame?,
	setWarning: (active: boolean) -> (),
	showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> (),
	leftPlace: (zoneId: string) -> (),
}
type Deps = {
	Localize: any,
	HudController: HudApi,
	RemoteClient: any,
	WorldLighting: any,
	SoundController: any,
}

type Announcement = { Key: string, Kind: string }

local BAND_WIDTH = 440
-- The band grows into place when the event starts: rule 3 of docs/ART_BIBLE.md, nothing appears.
local BAND_ENTER_SCALE = 0.9
local PADDING = 10
local TITLE_TEXT = 24
local TITLE_HEIGHT = TITLE_TEXT + Theme.Sizes.PaddingSmall
local BAR_HEIGHT = 18
local INFO_TEXT = 16
local SHARE_TEXT = 22
local INFO_HEIGHT = SHARE_TEXT + Theme.Sizes.PaddingSmall
-- The warning: a plate at this share of the screen's height, a medallion, the attack's name and a chevron.
local WARNING_WIDTH = 380
local WARNING_HEIGHT = 64
local WARNING_HEIGHT_SHARE = 0.65
local WARNING_ENTER = 0.8
local MEDALLION = 40
local WARNING_TEXT = 28
local CHEVRON = 24
local WARNING_SIGN = "!"
-- The zone (PortalConfig.Zones) of the Erasure's arena.
local ERASURE_ZONE = "WorldBoss"
local PHASES: { [string]: boolean } = { Announced = true, Fighting = true, Defeated = true, Expired = true }
-- One toast per phase, fired on the transition into it.
local ANNOUNCEMENTS: { [string]: Announcement } = {
	Announced = { Key = "boss.announced", Kind = "Info" },
	Fighting = { Key = "boss.started", Kind = "Info" },
	Defeated = { Key = "boss.defeated", Kind = "Success" },
	Expired = { Key = "boss.expired", Kind = "Info" },
}

local BossController = {}

local localize: any
local hudController: HudApi?
local remoteClient: any

-- False until build() has the HUD column and every label exists. The band is a child of the HUD's own
-- column, so a HUD that failed to build leaves this controller with nothing to draw into, and each
-- BossChanged would dereference a nil label.
local built = false

local band: HudPlate.HudPlate
local titleLabel: TextLabel
local healthBar: ProgressBar.ProgressBar
local phaseLabel: TextLabel
local timeLabel: TextLabel
local shareLabel: TextLabel
local warning: HudPlate.HudPlate?
local warningLabel: TextLabel
local warningChevron: TextLabel
local warningUp = false

local soundController: any
local snapshot: Types.BossSnapshot? = nil
local lastPhase: string? = nil
local worldLighting: any
local malformedWarned = false

local function makeLabel(
	name: string,
	height: number,
	size: number,
	color: Color3,
	alignment: Enum.TextXAlignment,
	order: number,
	parent: Instance
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.LayoutOrder = order
	label.FontFace = Theme.Fonts.Bold
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = alignment
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- Phase, time left and damage share share one line: three equal columns.
local function makeInfoRow(parent: Instance): (TextLabel, TextLabel, TextLabel)
	local row = Instance.new("Frame")
	row.Name = "Info"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, INFO_HEIGHT)
	row.LayoutOrder = 3

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = row

	local phase = makeLabel("Phase", INFO_HEIGHT, INFO_TEXT, Theme.Colors.Chalk, Enum.TextXAlignment.Left, 1, row)
	local time = makeLabel("Time", INFO_HEIGHT, INFO_TEXT, Theme.Colors.TextInverse, Enum.TextXAlignment.Center, 2, row)
	-- The player's own share, in cyan: it is ours.
	local share = makeLabel("Share", INFO_HEIGHT, SHARE_TEXT, Theme.Colors.Ally, Enum.TextXAlignment.Right, 3, row)
	share.FontFace = Theme.Fonts.Numeric
	for _, label in ipairs({ phase, time, share }) do
		label.Size = UDim2.fromScale(0, 1)
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = label
	end

	row.Parent = parent
	return phase, time, share
end

-- The warning plate, at two thirds of the screen's height in the HUD: a red medallion (the one red here: the
-- attack is about to land), the attack's name, and the chevron toward the boss.
local function buildWarning(hud: HudApi)
	local overlay = hud.overlay()
	if overlay == nil then
		log.warn("the HUD has no overlay: the boss's warnings stay on the floor only")
		return
	end
	local plate = HudPlate.new({
		Name = "BossWarning",
		Width = WARNING_WIDTH,
		Height = WARNING_HEIGHT,
		Direction = "Horizontal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, WARNING_HEIGHT_SHARE),
		Parent = overlay,
	})
	local medallion = Instance.new("Frame")
	medallion.Name = "Medallion"
	medallion.BorderSizePixel = 0
	medallion.BackgroundColor3 = Theme.Colors.DangerFill
	medallion.Size = UDim2.fromOffset(MEDALLION, MEDALLION)
	medallion.LayoutOrder = 1
	Theme.corner(medallion, Theme.Pill)
	Theme.stroke(medallion, "Accent", Theme.Sizes.StrokeThin)
	local sign = makeLabel(
		"Sign",
		MEDALLION,
		WARNING_TEXT,
		Theme.inkOn(Theme.Colors.DangerFill),
		Enum.TextXAlignment.Center,
		1,
		medallion
	)
	sign.FontFace = Theme.Fonts.Title
	sign.Size = UDim2.fromScale(1, 1)
	sign.Text = WARNING_SIGN
	medallion.Parent = plate.Content
	warningLabel = makeLabel(
		"Attack",
		MEDALLION,
		WARNING_TEXT,
		Theme.Colors.TextInverse,
		Enum.TextXAlignment.Center,
		2,
		plate.Content
	)
	warningLabel.FontFace = Theme.Fonts.Title
	warningLabel.Size = UDim2.fromScale(0, 1)
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = warningLabel
	warningChevron =
		makeLabel("Chevron", CHEVRON, CHEVRON, Theme.Colors.PanelRaised, Enum.TextXAlignment.Center, 3, plate.Content)
	warningChevron.Size = UDim2.fromOffset(CHEVRON, CHEVRON)
	warningChevron.Text = Theme.Glyphs.Play
	warning = plate
end

-- Where the boss stands from the camera, as the rotation of a "▶" on the screen: straight up when it is ahead,
-- right when it is to the right. Nil when no boss body is in the world. Read once, when a warning shows.
local function chevronRotation(): number?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local eye = camera.CFrame
	local nearest: Vector3? = nil
	for _, model in ipairs(CollectionService:GetTagged(WorldBossConfig.Boss.Tag)) do
		local body = if model:IsA("Model") then model.PrimaryPart else nil
		if
			body ~= nil
			and (nearest == nil or (body.Position - eye.Position).Magnitude < (nearest - eye.Position).Magnitude)
		then
			nearest = body.Position
		end
	end
	if nearest == nil then
		return nil
	end
	local toward = nearest - eye.Position
	local ahead = toward:Dot(Vector3.new(eye.LookVector.X, 0, eye.LookVector.Z))
	local aside = toward:Dot(Vector3.new(eye.RightVector.X, 0, eye.RightVector.Z))
	-- The glyph points right at rotation 0; ahead is a quarter turn back from it.
	return math.deg(math.atan2(aside, ahead)) - 90
end

-- The warning comes up while an attack is telegraphed and goes when it lands; the HUD holds its messages
-- meanwhile.
local function showWarning(telegraph: string?)
	local plate = warning
	if plate == nil then
		return
	end
	local up = telegraph ~= nil
	if up then
		-- The payload carries the attack's Strings key.
		warningLabel.Text = localize.t(telegraph :: string)
	end
	if up == warningUp then
		return
	end
	warningUp = up
	local hud = hudController
	if hud ~= nil then
		hud.setWarning(up)
	end
	if up then
		local rotation = chevronRotation()
		warningChevron.Visible = rotation ~= nil
		warningChevron.Rotation = rotation or 0
		plate.Instance.Visible = true
		Motion.set(plate.Scale, { Scale = WARNING_ENTER })
		Motion.to(plate.Scale, { Scale = 1 }, "UiPop")
	else
		Motion.to(plate.Scale, { Scale = 0 }, "UiExit", function()
			if not warningUp then
				plate.Instance.Visible = false
			end
		end)
	end
end

-- The band lives inside the HUD's top-centre column rather than in a ScreenGui of its own. Two
-- ScreenGuis at the same DisplayOrder have no defined draw order, and this 420-wide band simply covered
-- the 360-wide match band: boss title over the round line, boss health bar over the score.
local function build()
	-- The HUD may be absent entirely: the client bootstrap wraps each controller's Init in a pcall, so a
	-- HudController that failed to load simply does not appear in the dependency table.
	local hud = hudController
	if hud == nil then
		log.warn("HudController is missing: the World Boss band cannot be shown")
		return
	end
	local stack, layoutOrder = hud.topStack()
	if stack == nil then
		log.warn("the HUD has no top stack: the World Boss band cannot be shown")
		return
	end
	built = true

	-- Shown by refresh while a snapshot is held.
	band = HudPlate.new({
		Name = "Boss",
		Width = BAND_WIDTH,
		Padding = PADDING,
		Gap = Theme.Sizes.PaddingSmall,
		LayoutOrder = layoutOrder,
		Parent = stack,
	})
	local content = band.Content

	titleLabel =
		makeLabel("Title", TITLE_HEIGHT, TITLE_TEXT, Theme.Colors.TextInverse, Enum.TextXAlignment.Center, 1, content)
	titleLabel.FontFace = Theme.Fonts.Title
	-- The boss is the danger: its health is red. What the player's hits take off it stays behind in cyan, ours,
	-- and a mark stands at each phase it will change at.
	local phases: { number } = {}
	for index = 2, #WorldBossConfig.Phases do
		table.insert(phases, WorldBossConfig.Phases[index].Threshold)
	end
	healthBar = ProgressBar.new({
		Name = "Health",
		Color = Theme.Colors.DangerFill,
		Ghost = Theme.Colors.Ally,
		OnPlate = true,
		Ticks = phases,
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		LayoutOrder = 2,
		Parent = content,
	})
	phaseLabel, timeLabel, shareLabel = makeInfoRow(content)
	buildWarning(hud)
end

local function finite(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- Server-authored payload: anything missing or out of range falls back to a value that renders.
local function read(payload: any): Types.BossSnapshot?
	if type(payload) ~= "table" or not PHASES[payload.Phase] then
		return nil
	end
	local maxHealth = math.max(0, finite(payload.MaxHealth, 0))
	return {
		Phase = (payload.Phase :: any) :: Types.BossPhaseSnapshot,
		SecondsLeft = math.max(0, finite(payload.SecondsLeft, 0)),
		Health = math.clamp(finite(payload.Health, 0), 0, maxHealth),
		MaxHealth = maxHealth,
		PhaseIndex = math.max(1, math.floor(finite(payload.PhaseIndex, 1))),
		Participants = math.max(0, math.floor(finite(payload.Participants, 0))),
		TelegraphKey = if type(payload.TelegraphKey) == "string" then payload.TelegraphKey else nil,
		MyShare = math.clamp(finite(payload.MyShare, 0), 0, 1),
		Practice = payload.Practice == true,
	}
end

local function refresh()
	if not built then
		return
	end
	local current = snapshot
	if current == nil then
		band.Instance.Visible = false
		showWarning(nil)
		return
	end
	-- A practice is the same Erasure, and says it is one: its band must not read as the server-wide event.
	titleLabel.Text = localize.t(if current.Practice then "boss.practice.title" else "boss.name")
	healthBar:SetProgress(if current.MaxHealth > 0 then current.Health / current.MaxHealth else 0)
	healthBar:SetLabel(localize.t("boss.health", {
		health = math.floor(current.Health + 0.5),
		max = math.floor(current.MaxHealth + 0.5),
	}))
	phaseLabel.Text = localize.t("boss.phase", { phase = current.PhaseIndex })
	timeLabel.Text = localize.t("boss.timeLeft", { seconds = math.ceil(current.SecondsLeft) })
	shareLabel.Text = localize.t("boss.share", { percent = math.floor(current.MyShare * 100 + 0.5) })

	showWarning(current.TelegraphKey)
	band:Grow(BAND_ENTER_SCALE)
end

local function announce(current: Types.BossSnapshot)
	if current.Phase == lastPhase then
		return
	end
	lastPhase = current.Phase
	local announcement = ANNOUNCEMENTS[current.Phase]
	if announcement == nil then
		return
	end
	local params: { [string]: any }? = nil
	if current.Phase == "Announced" then
		params = { seconds = math.ceil(current.SecondsLeft) }
	end
	local hud = hudController
	if hud ~= nil then
		hud.showLocalToast(announcement.Key, params, announcement.Kind)
	end

	-- The Erasure arriving is the one moment in the game the whole page is supposed to be affected, and
	-- LightingConfig has a pulse named for it. A toast alone is a line of text for an event the world is
	-- meant to feel; without this the three heaviest post-processing effects exist and are driven by
	-- nothing at all.
	if current.Phase == "Announced" and worldLighting ~= nil then
		worldLighting.pulse("Erasure")
	end

	-- The event asks for its loop for everyone on the server -- the boss is server-wide and the hub is
	-- where the announcement is heard -- and SoundController decides: a player inside a ranked match
	-- keeps the match's loop, because Match outranks Boss there.
	if current.Phase == "Announced" or current.Phase == "Fighting" then
		soundController.wantMusic("Boss", "Boss")
	else
		soundController.wantMusic("Boss", nil)
	end
end

local function onBossChanged(payload: any)
	if payload == nil then
		snapshot = nil
		lastPhase = nil -- the next event announces itself from its first phase again
		soundController.wantMusic("Boss", nil)
		refresh()
		-- The fight is over, and whoever still stood in its arena was sent home with it (WorldBossService).
		local hud = hudController
		if hud ~= nil then
			hud.leftPlace(ERASURE_ZONE)
		end
		return
	end
	local received = read(payload)
	if received == nil then
		if not malformedWarned then
			malformedWarned = true
			log.warn("malformed BossChanged dropped (%s)", typeof(payload))
		end
		return
	end
	snapshot = received
	announce(received)
	refresh()
end

function BossController.Init(deps: Deps)
	soundController = deps.SoundController
	localize = deps.Localize
	hudController = deps.HudController
	remoteClient = deps.RemoteClient
	worldLighting = deps.WorldLighting
	build()
end

function BossController.Start()
	if not built then
		-- Without the band there is nothing to drive, and every label is nil: registering the handler would
		-- turn each snapshot the server pushes into an error. The phase toasts go through the HUD, which is
		-- the very thing that is missing, so there is nothing worth keeping either.
		log.warn("not started: the band was never built")
		return
	end
	remoteClient.on("BossChanged", onBossChanged)
	log.info("started")
end

return BossController
