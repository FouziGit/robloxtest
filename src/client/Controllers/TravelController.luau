--!strict
-- TravelController: what the portals and the Battleground tell the local player (D-130, D-131). The server
-- moves whoever it trusts to be standing in a circle and asks the client nothing (PortalService), so all this
-- controller does is say what the server is doing:
--   * the portal band, while the player stands in a circle that is about to take them: "Stay in the circle:
--     {place}", over a bar that fills in exactly the seconds the server waits (PortalChanged). No band while a
--     trip has just ended: the server does not send one, and a circle then takes nobody;
--   * the place band, while the player is a member of the Battleground: how many Forgers stand on the page and
--     how many this player helped defeat, with the match's loop in their ears (BattlegroundChanged). A death
--     inside keeps it up: the camp takes the next body back, and the server says nothing until it lets go;
--   * Travelled, fired once a portal has moved the player: MenuController closes whatever screen was open, so
--     nobody arrives somewhere new with their input suspended.
-- Both bands are ink plates in the HUD's top-centre column (HudController.topStack, D-147) and grow into place like
-- the match and boss bands. The fill is one tween, started and cancelled by the packets that say so: no loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local HudPlate = require(UI.components.HudPlate)
local Log = require(Shared.Util.Log)
local Motion = require(UI.Motion)
local PortalConfig = require(Shared.Config.PortalConfig)
local Signal = require(Packages.Signal)
local Theme = require(UI.Theme)
local Types = require(Shared.Types)

local log = Log.new("TravelController")

type Band = "Boss" | "Place" | "Portal"
type HudApi = {
	topStack: (band: Band?) -> (Frame?, number),
	setPlace: (zoneId: string) -> (),
	leftPlace: (zoneId: string) -> (),
}
type Deps = { RemoteClient: any, Localize: any, HudController: HudApi?, SoundController: any }

local BAND_WIDTH = 360
-- A band that is shown grows into place: rule 3 of docs/ART_BIBLE.md, nothing appears.
local BAND_ENTER_SCALE = 0.9
local PORTAL_TEXT = 18
local PLACE_TEXT = 20
local STATUS_TEXT = 18
local TITLE_HEIGHT = PLACE_TEXT + Theme.Sizes.PaddingSmall
local LINE_HEIGHT = STATUS_TEXT + Theme.Sizes.PaddingSmall
-- The dwell bar: the vivid Indigo filling an inkwell ringed with the sheet, under the title.
local FILL_HEIGHT = 18
-- Eased at both ends (rule 4: nothing moves linearly) and symmetric, so the bar is still half full at half the
-- dwell: it is a clock the player reads, and a clock that ran fast then slow would lie about what is left.
local FILL_STYLE = Enum.EasingStyle.Sine
local FILL_DIRECTION = Enum.EasingDirection.InOut
-- The loop a member hears (SoundController.wantMusic): the fight's, under the source this controller owns.
local MUSIC_SOURCE = "Battleground"
local MUSIC_ID = "Match"
-- The zone (PortalConfig.Zones) the Battleground's membership is the place of.
local BATTLEGROUND_ZONE = "Battleground"

local TravelController = {}

-- Fired once a portal has moved the local player, with where it took them (a PortalConfig.PortalId).
TravelController.Travelled = Signal.new() -- (id: string)

local remoteClient: any
local localize: any
local hudController: HudApi?
local soundController: any

local portalBand: Frame
local portalScale: UIScale
local portalTitle: TextLabel
local portalFill: Frame
local fillTween: Tween? = nil
local placeBand: Frame
local placeScale: UIScale
local placeTitle: TextLabel
local placeLine: TextLabel
local placeLineScale: UIScale
-- The Forgers this member had defeated at the last packet: the count punches when it moves.
local lastDefeated: number? = nil
local member = false
local malformedWarned: { [string]: boolean } = {}

local function warnMalformed(remote: string, payload: any)
	if malformedWarned[remote] then
		return
	end
	malformedWarned[remote] = true
	log.warn("malformed %s dropped (%s); further ones are dropped silently", remote, typeof(payload))
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- An ink plate in the column, hidden until the server says there is something to show; its content stacks
-- down the middle.
local function makeBand(name: string, order: number, stack: Frame): (Frame, UIScale, Frame)
	local plate = HudPlate.new({
		Name = name,
		Width = BAND_WIDTH,
		Gap = Theme.Sizes.PaddingSmall,
		LayoutOrder = order,
		Parent = stack,
	})
	return plate.Instance, plate.Scale, plate.Content
end

local function makeLabel(
	name: string,
	height: number,
	size: number,
	color: Color3,
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
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- The dwell bar: an inkwell ringed with the sheet (a well is 1.23 against the ink plate: the ring shapes it),
-- and the vivid Indigo inside it, empty.
local function makeFill(parent: Instance): Frame
	local track = Instance.new("Frame")
	track.Name = "Dwell"
	track.BackgroundColor3 = Theme.Colors.Well
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Size = UDim2.new(1, 0, 0, FILL_HEIGHT)
	track.LayoutOrder = 2
	Theme.corner(track, Theme.Pill)
	Theme.stroke(track, "PanelRaised", Theme.Sizes.StrokeThin)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Colors.InfoFill
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Theme.corner(fill, Theme.Pill)
	fill.Parent = track
	track.Parent = parent
	return fill
end

-- Both bands, in the HUD's column: false when there is no HUD to draw into, in which case no packet may be
-- handled, because each would dereference a label that does not exist.
local function build(): boolean
	local hud = hudController
	if hud == nil then
		log.warn("HudController is missing: the portal and Battleground bands cannot be shown")
		return false
	end
	local stack, portalOrder = hud.topStack("Portal")
	local _, placeOrder = hud.topStack("Place")
	if stack == nil then
		log.warn("the HUD has no top stack: the portal and Battleground bands cannot be shown")
		return false
	end
	local portalContent, placeContent
	portalBand, portalScale, portalContent = makeBand("Portal", portalOrder, stack)
	portalTitle = makeLabel("Title", TITLE_HEIGHT, PORTAL_TEXT, Theme.Colors.TextInverse, 1, portalContent)
	portalFill = makeFill(portalContent)
	placeBand, placeScale, placeContent = makeBand("Place", placeOrder, stack)
	placeTitle = makeLabel("Title", TITLE_HEIGHT, PLACE_TEXT, Theme.Colors.TextInverse, 1, placeContent)
	placeTitle.FontFace = Theme.Fonts.Title
	placeLine = makeLabel("Status", LINE_HEIGHT, STATUS_TEXT, Theme.Colors.TextInverse, 2, placeContent)
	placeLine.FontFace = Theme.Fonts.Numeric
	placeLineScale = Instance.new("UIScale")
	placeLineScale.Parent = placeLine
	return true
end

local function grow(band: Frame, scale: UIScale)
	if band.Visible then
		return
	end
	band.Visible = true
	Motion.set(scale, { Scale = BAND_ENTER_SCALE })
	Motion.to(scale, { Scale = 1 }, "UiSnappy")
end

local function stopFill()
	local tween = fillTween
	if tween ~= nil then
		tween:Cancel()
		fillTween = nil
	end
end

-- From empty to full over `seconds`, the dwell the server is counting from the moment it sent this.
local function startFill(seconds: number)
	stopFill()
	portalFill.Size = UDim2.fromScale(0, 1)
	local tween = TweenService:Create(
		portalFill,
		TweenInfo.new(seconds, FILL_STYLE, FILL_DIRECTION),
		{ Size = UDim2.fromScale(1, 1) }
	)
	fillTween = tween
	tween:Play()
end

-- The circle the player stands in and how long they must stay (Types.PortalSnapshot), or nil once they step
-- out or set off.
local function onPortalChanged(payload: any)
	if payload == nil then
		stopFill()
		portalBand.Visible = false
		return
	end
	local zone = if type(payload) == "table" and type(payload.Id) == "string"
		then PortalConfig.Zones[payload.Id]
		else nil
	if zone == nil then
		warnMalformed("PortalChanged", payload)
		return
	end
	local snapshot = payload :: Types.PortalSnapshot
	local seconds = if finite(snapshot.Seconds) and snapshot.Seconds > 0 then snapshot.Seconds else zone.DwellSeconds
	portalTitle.Text = localize.t("portal.entering", { place = localize.t(zone.NameKey) })
	startFill(seconds)
	grow(portalBand, portalScale)
end

-- The Battleground as this member sees it (Types.BattlegroundSnapshot), or nil once they are no longer one.
local function onBattlegroundChanged(payload: any)
	if payload == nil then
		placeBand.Visible = false
		if member then
			member = false
			soundController.wantMusic(MUSIC_SOURCE, nil)
		end
		-- No longer a member: out of the Battleground, whether or not a portal took them (a match, a respawn
		-- the camp could not take back).
		local hud = hudController
		if hud ~= nil then
			hud.leftPlace(BATTLEGROUND_ZONE)
		end
		return
	end
	if type(payload) ~= "table" or not finite(payload.Standing) or not finite(payload.Defeated) then
		warnMalformed("BattlegroundChanged", payload)
		return
	end
	local snapshot = payload :: Types.BattlegroundSnapshot
	placeTitle.Text = localize.t("portal.battleground.name")
	placeLine.Text = localize.t("battleground.status", {
		standing = math.max(0, math.floor(snapshot.Standing)),
		defeated = math.max(0, math.floor(snapshot.Defeated)),
	})
	-- A Forger this member helped take down: the count punches. Not on the band's first packet.
	local defeated = math.max(0, math.floor(snapshot.Defeated))
	if not placeBand.Visible then
		lastDefeated = nil
	end
	if lastDefeated ~= nil and defeated ~= lastDefeated then
		Motion.punch(placeLineScale)
	end
	lastDefeated = defeated
	grow(placeBand, placeScale)
	if not member then
		member = true
		soundController.wantMusic(MUSIC_SOURCE, MUSIC_ID)
	end
end

local function onTravelled(id: any)
	if type(id) ~= "string" or PortalConfig.Zones[id] == nil then
		warnMalformed("Travelled", id)
		return
	end
	TravelController.Travelled:Fire(id)
	-- The HUD knows a fight from the hub by where the player is: an arena holds back its value colours.
	local hud = hudController
	if hud ~= nil then
		hud.setPlace(id)
	end
end

function TravelController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
	localize = deps.Localize
	hudController = deps.HudController
	soundController = deps.SoundController
end

-- The bands are built here rather than in Init: the HUD's column exists once every Init has run.
function TravelController.Start()
	-- Travelled closes a menu whether or not the bands could be built: arriving with input suspended is the
	-- worse failure.
	remoteClient.on("Travelled", onTravelled)
	if not build() then
		return
	end
	remoteClient.on("PortalChanged", onPortalChanged)
	remoteClient.on("BattlegroundChanged", onBattlegroundChanged)
	log.info("started")
end

return TravelController
