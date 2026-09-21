--!strict
-- BossController: the World Boss band. While the server holds an event (BossChanged snapshots) a
-- compact band sits at the top of the screen: the boss name, its health bar, the current phase, the
-- time left, the share of the damage the local player dealt, and a prominent warning while an attack
-- is telegraphed. The band disappears as soon as the snapshot is nil.
--
-- Phase transitions are announced through the HUD toasts (announced / started / defeated / expired),
-- once per transition: the server pushes the same phase many times per event.
--
-- The band is a child of the HUD's top-centre column (HudController.topStack), not a ScreenGui of its
-- own: three overlays pinned to the same rectangle drew over each other. It still lives and dies with
-- the event, by its Visible flag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local Log = require(Shared.Util.Log)
local ProgressBar = require(UI.components.ProgressBar)
local Theme = require(UI.Theme)
local Types = require(Shared.Types)

local log = Log.new("BossController")

-- The band needs a real contract from the HUD: it parents itself into the shared top-centre column and
-- announces phase changes through the HUD toasts.
type HudApi = {
	topStack: () -> (Frame?, number),
	showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> (),
}
type Deps = {
	Localize: any,
	HudController: HudApi,
	RemoteClient: any,
	WorldLighting: any,
	SoundController: any,
}

type Announcement = { Key: string, Kind: string }

local BAND_WIDTH = 420
local TITLE_HEIGHT = Theme.Sizes.TextTitle + Theme.Sizes.PaddingSmall
local BAR_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local INFO_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
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

local band: Frame
local titleLabel: TextLabel
local healthBar: ProgressBar.ProgressBar
local phaseLabel: TextLabel
local timeLabel: TextLabel
local shareLabel: TextLabel
local warningLabel: TextLabel

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
	label.Font = Theme.Fonts.Bold
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.6
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

	local phase =
		makeLabel("Phase", INFO_HEIGHT, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, Enum.TextXAlignment.Left, 1, row)
	local time =
		makeLabel("Time", INFO_HEIGHT, Theme.Sizes.TextSmall, Theme.Colors.Text, Enum.TextXAlignment.Center, 2, row)
	local share =
		makeLabel("Share", INFO_HEIGHT, Theme.Sizes.TextSmall, Theme.Colors.Accent, Enum.TextXAlignment.Right, 3, row)
	for _, label in ipairs({ phase, time, share }) do
		label.Size = UDim2.fromScale(0, 1)
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = label
	end

	row.Parent = parent
	return phase, time, share
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

	band = Instance.new("Frame")
	band.Name = "Boss"
	band.BackgroundTransparency = 1
	band.LayoutOrder = layoutOrder
	band.Size = UDim2.fromOffset(BAND_WIDTH, 0)
	band.AutomaticSize = Enum.AutomaticSize.Y
	band.Visible = false -- refresh shows it while a snapshot is held

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = band

	titleLabel = makeLabel(
		"Title",
		TITLE_HEIGHT,
		Theme.Sizes.TextTitle,
		Theme.Colors.Accent,
		Enum.TextXAlignment.Center,
		1,
		band
	)
	healthBar = ProgressBar.new({
		Name = "Health",
		Color = Theme.Colors.Danger,
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		LayoutOrder = 2,
		Parent = band,
	})
	phaseLabel, timeLabel, shareLabel = makeInfoRow(band)
	warningLabel = makeLabel(
		"Warning",
		TITLE_HEIGHT,
		Theme.Sizes.TextTitle,
		Theme.Colors.Danger,
		Enum.TextXAlignment.Center,
		4,
		band
	)
	warningLabel.Visible = false

	band.Parent = stack
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
	}
end

local function refresh()
	if not built then
		return
	end
	local current = snapshot
	if current == nil then
		band.Visible = false
		warningLabel.Visible = false
		return
	end
	titleLabel.Text = localize.t("boss.name")
	healthBar:SetProgress(if current.MaxHealth > 0 then current.Health / current.MaxHealth else 0)
	healthBar:SetLabel(localize.t("boss.health", {
		health = math.floor(current.Health + 0.5),
		max = math.floor(current.MaxHealth + 0.5),
	}))
	phaseLabel.Text = localize.t("boss.phase", { phase = current.PhaseIndex })
	timeLabel.Text = localize.t("boss.timeLeft", { seconds = math.ceil(current.SecondsLeft) })
	shareLabel.Text = localize.t("boss.share", { percent = math.floor(current.MyShare * 100 + 0.5) })

	local telegraph = current.TelegraphKey
	if telegraph ~= nil then
		-- The payload carries a Strings key: resolveParams turns it into the localized attack name.
		warningLabel.Text = localize.t("boss.incoming", localize.resolveParams({ attack = telegraph }))
		warningLabel.Visible = true
	else
		warningLabel.Visible = false
	end
	band.Visible = true
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
