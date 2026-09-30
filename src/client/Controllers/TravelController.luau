--!strict
-- TravelController: what the portals and the Battleground tell the local player (D-130, D-131). The server
-- moves whoever it trusts to be standing in a circle and asks the client nothing (PortalService), so all this
-- controller does is say what the server is doing:
--   * the portal band, while the player stands in a circle that is about to take them: "Stay in the circle:
--     {place}", over a bar that fills in exactly the seconds the server waits (PortalChanged). No band while a
--     trip has just ended: the server does not send one, and a circle then takes nobody;
--   * the place band, while the player is a member of the Battleground: how many Forgers stand on the page and
--     how many this player helped defeat, with the match's loop in their ears (BattlegroundChanged). A death
--     inside keeps it up: the camp takes the next body back, and the server says nothing until it lets go. The
--     Flyleaf's members see the same band (FlyleafChanged): how many rivals, how many they took down, their run;
--   * Travelled, fired once a portal has moved the player: MenuController closes whatever screen was open, so
--     nobody arrives somewhere new with their input suspended;
--   * FightChanged, whether the player stands where others fight: the Battleground while the server keeps them
--     a member; the Erasure's arena from its gate, or from the moment a scheduled event starts fighting and
--     pulls in everybody not in a match (WorldBossService, no portal), until they walk back out, die (a body
--     is reborn in the hub) or the fight closes (BossChanged nil: its end sends whoever stands in the arena
--     home). CosmeticController quiets every aura on this screen while it holds, with a ranked match (D-148), and
--     the HUD takes its fight mode from it when no portal said where the player went.
-- Both bands are ink plates in the HUD's top-centre column (HudController.topStack, D-147) and grow into place like
-- the match and boss bands. The fill is one tween, started and cancelled by the packets that say so: no loop. Their
-- words are written from the last packet, again when the player's language changes (Localize.Changed).

local Players = game:GetService("Players")
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
type Deps = { RemoteClient: any, Localize: any, HudController: HudApi?, SoundController: any, MatchController: any }

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
-- The zone (PortalConfig.Zones) the Battleground's membership is the place of, and the Flyleaf's.
local BATTLEGROUND_ZONE = "Battleground"
local FLYLEAF_ZONE = "Flyleaf"
-- The portal whose trip puts the player in the Erasure's arena (PortalConfig.Ids).
local ARENA_PORTAL = "WorldBoss"
-- The scheduled event's phases (Types.BossPhaseSnapshot) between which it pulls its players in.
local ANNOUNCED_PHASE = "Announced"
local PULL_PHASE = "Fighting"

local TravelController = {}

-- Fired once a portal has moved the local player, with where it took them (a PortalConfig.PortalId).
TravelController.Travelled = Signal.new() -- (id: string)
-- Fired when the local player enters or leaves a place where others fight (see the header).
TravelController.FightChanged = Signal.new() -- (fighting: boolean)

local remoteClient: any
local localize: any
local hudController: HudApi?
local soundController: any
local matchController: any

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
-- What the bands say, from the last packets: where the circle leads, and the Battleground's two counts.
local portalZone: PortalConfig.ZoneDef? = nil
local standingCount = 0
local defeatedCount = 0
local member = false
-- A member of the Flyleaf, as its last packet said, and the takedowns it counted: the count punches when it moves.
local flyleafMember = false
local lastKills: number? = nil
-- What the Flyleaf's band says, from its last packet: the rivals on the page, the takedowns, the run.
local flyleafRivals = 0
local flyleafKills = 0
local flyleafStreak = 0
-- In the Erasure's arena, as far as its gate and its fight say, and the fight's last phase heard.
local inArena = false
local bossPhase: string? = nil
local fighting = false
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

local function refreshFight()
	local now = member or flyleafMember or inArena
	if now == fighting then
		return
	end
	fighting = now
	TravelController.FightChanged:Fire(now)
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

-- The words of the portal band: where the circle the player stands in leads.
local function wordPortal()
	local zone = portalZone
	if zone ~= nil then
		portalTitle.Text = localize.t("portal.entering", { place = localize.t(zone.NameKey) })
	end
end

-- The words of the place band, the Flyleaf's for one of its members, the Battleground's otherwise: nobody is a member
-- of both. Each count in its own words: "1 Forger standing", "2 vaincus".
local function wordPlace()
	if flyleafMember then
		placeTitle.Text = localize.t("portal.flyleaf.name")
		placeLine.Text = localize.t("flyleaf.status", {
			members = flyleafRivals,
			kills = flyleafKills,
			streak = flyleafStreak,
		})
		return
	end
	placeTitle.Text = localize.t("portal.battleground.name")
	placeLine.Text = localize.t("battleground.status", {
		standing = localize.t("battleground.standing", { standing = standingCount }),
		defeated = localize.t("battleground.defeated", { defeated = defeatedCount }),
	})
end

local function relabel()
	wordPortal()
	wordPlace()
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
	portalZone = zone
	wordPortal()
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
			refreshFight()
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
	local defeated = math.max(0, math.floor(snapshot.Defeated))
	standingCount = math.max(0, math.floor(snapshot.Standing))
	defeatedCount = defeated
	wordPlace()
	-- A Forger this member helped take down: the count punches. Not on the band's first packet.
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
		refreshFight()
	end
end

-- The Flyleaf as this member sees it (Types.FlyleafSnapshot), or nil once they are no longer one. It writes the
-- place band the Battleground writes: nobody is a member of both.
local function onFlyleafChanged(payload: any)
	if payload == nil then
		if flyleafMember then
			flyleafMember = false
			placeBand.Visible = false
			soundController.wantMusic(MUSIC_SOURCE, nil)
			refreshFight()
		end
		local hud = hudController
		if hud ~= nil then
			hud.leftPlace(FLYLEAF_ZONE)
		end
		return
	end
	if
		type(payload) ~= "table"
		or not finite(payload.Members)
		or not finite(payload.Kills)
		or not finite(payload.Streak)
	then
		warnMalformed("FlyleafChanged", payload)
		return
	end
	local snapshot = payload :: Types.FlyleafSnapshot
	local kills = math.max(0, math.floor(snapshot.Kills))
	-- Everyone else on the page.
	flyleafRivals = math.max(0, math.floor(snapshot.Members) - 1)
	flyleafKills = kills
	flyleafStreak = math.max(0, math.floor(snapshot.Streak))
	local joined = not flyleafMember
	flyleafMember = true
	wordPlace()
	if not placeBand.Visible then
		lastKills = nil
	end
	if lastKills ~= nil and kills ~= lastKills then
		Motion.punch(placeLineScale)
	end
	lastKills = kills
	grow(placeBand, placeScale)
	if joined then
		soundController.wantMusic(MUSIC_SOURCE, MUSIC_ID)
		refreshFight()
	end
end

local function onTravelled(id: any)
	if type(id) ~= "string" or PortalConfig.Zones[id] == nil then
		warnMalformed("Travelled", id)
		return
	end
	inArena = id == ARENA_PORTAL
	refreshFight()
	TravelController.Travelled:Fire(id)
	-- The HUD knows a fight from the hub by where the player is: an arena holds back its value colours.
	local hud = hudController
	if hud ~= nil then
		hud.setPlace(id)
	end
end

-- The Erasure's fight as the server tells it. Its close (nil) sends whoever stands in the arena home, and a
-- practice's nil is its own participant let go (a ranked match took them). A scheduled event that turns from
-- announced to fighting has just pulled in everybody alive and in no match; a practice is only ever entered
-- by its gate, and a player who arrives in the middle of an event was never pulled.
local function onBossChanged(payload: any)
	if payload == nil then
		bossPhase = nil
		if inArena then
			inArena = false
			refreshFight()
		end
		return
	end
	if type(payload) ~= "table" then
		return
	end
	local phase = payload.Phase
	if phase == PULL_PHASE and bossPhase == ANNOUNCED_PHASE and payload.Practice ~= true then
		if matchController.getMatch() == nil then
			inArena = true
			refreshFight()
		end
	end
	bossPhase = if type(phase) == "string" then phase else nil
end

-- A new body is born in the hub, wherever the last one fell: a death in the arena is a way out of it. (The
-- Battleground takes its member's next body back itself, and says so through BattlegroundChanged.)
local function onRespawn()
	if inArena then
		inArena = false
		refreshFight()
	end
end

function TravelController.inFight(): boolean
	return fighting
end

function TravelController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
	localize = deps.Localize
	hudController = deps.HudController
	soundController = deps.SoundController
	matchController = deps.MatchController
end

-- The bands are built here rather than in Init: the HUD's column exists once every Init has run.
function TravelController.Start()
	-- Travelled closes a menu whether or not the bands could be built: arriving with input suspended is the
	-- worse failure. The arena is followed the same way: it draws no band.
	remoteClient.on("Travelled", onTravelled)
	remoteClient.on("BossChanged", onBossChanged)
	Players.LocalPlayer.CharacterAdded:Connect(onRespawn)
	if not build() then
		return
	end
	remoteClient.on("PortalChanged", onPortalChanged)
	remoteClient.on("FlyleafChanged", onFlyleafChanged)
	remoteClient.on("BattlegroundChanged", onBattlegroundChanged)
	localize.Changed:Connect(relabel)
	log.info("started")
end

return TravelController
