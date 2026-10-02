--!strict
-- DrillService: the single writer of ProfileData.Drills. The Drills at the Lectern (docs/GAME_DESIGN.md §9 bis): a
-- player picks a drill at the hub's Lectern (StartDrill), does it on the training dummies, and the server counts
-- it -- a repetition or a miss per event GlyphService and CombatService fired on what they accepted
-- (Pure/DrillLogic) -- then grades the finished set and pays each grade of each drill once (DrillConfig).
--
-- The client names a drill and nothing else: which glyph landed, how many bodies a swing struck, whether a dash
-- cancelled a recovery and how long the set took are all the server's own. A drill counts in the hub only: a
-- player a match, the Battleground or the Erasure takes away has theirs put down, and so has one who lets a set sit
-- for DrillConfig.IdleSeconds; both are checked on one accumulator (tests/Loops.spec.luau). The running set is told
-- to its player (DrillChanged) so the Lectern can show it, and every repetition, miss and grade is a toast.
--
-- A grade is written into the profile before anything is paid for it, as HonoursService writes a milestone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CombatConfig = require(Shared.Config.CombatConfig)
local DrillCatalog = require(Shared.DrillCatalog)
local DrillConfig = require(Shared.Config.DrillConfig)
local DrillLogic = require(Shared.Pure.DrillLogic)
local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)

local log = Log.new("DrillService")

type ProfileData = Types.ProfileData
type Drill = DrillLogic.Drill
type Run = DrillLogic.Run
type Event = DrillLogic.Event
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type Registry = {
	on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
	fire: (name: string, player: Player, ...any) -> (),
}
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> number }
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> number }
type Signal<T...> = { Connect: (self: any, fn: (T...) -> ()) -> any }
type GlyphApi = {
	Cast: Signal<Player, string, number>,
	CastLanded: Signal<Player, string, number>,
}
type CombatApi = {
	Damaged: Signal<number, Model, number, string>,
	Swung: Signal<Player, number>,
	Dashed: Signal<Player, boolean>,
}
type MatchApi = { isInMatch: (player: Player) -> boolean }
type WorldBossApi = { isEngaged: (player: Player) -> boolean }
type BattlegroundApi = { isInside: (player: Player) -> boolean }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
	Glyph: GlyphApi,
	Combat: CombatApi,
	Match: MatchApi,
	WorldBoss: WorldBossApi,
	Battleground: BattlegroundApi,
}

-- What the Lectern is told of the set its player is doing, or nil when there is none.
export type Snapshot = { Drill: string, Reps: number, Target: number, Misses: number }

local DRILLS_SECTION = "Drills"
local MELEE_KIND = "Melee"
local FINISHER_INDEX = #CombatConfig.Melee.Damage
local GRADES = DrillConfig.Grades

local DrillService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local progression: ProgressionApi
local currency: CurrencyApi
local glyph: GlyphApi
local combat: CombatApi
local match: MatchApi
local worldBoss: WorldBossApi
local battleground: BattlegroundApi

local runs: { [Player]: Run } = {}
-- Bodies each player's melee struck since their last swing was told (CombatService fires Damaged before Swung).
local struck: { [Player]: number } = {}
local accumulator = 0

-- In the hub: in no match, not on the Battleground's page, not before the Erasure.
local function inHub(player: Player): boolean
	return not match.isInMatch(player) and not battleground.isInside(player) and not worldBoss.isEngaged(player)
end

local function snapshot(run: Run): Snapshot
	return { Drill = run.Drill.Id, Reps = run.Reps, Target = run.Drill.Reps, Misses = run.Misses }
end

local function tell(player: Player)
	local run = runs[player]
	registry.fire("DrillChanged", player, if run ~= nil then snapshot(run) else nil)
end

-- Puts the running set down, saying `key` when there is one.
local function putDown(player: Player, key: string?)
	if runs[player] == nil then
		return
	end
	runs[player] = nil
	tell(player)
	if key ~= nil then
		notify.send(player, key, nil, "Info")
	end
end

-- The finished set: its grade, written, then every grade it newly reached paid, lowest first.
local function finish(player: Player, run: Run)
	runs[player] = nil
	tell(player)
	local drill = run.Drill
	local grade = DrillLogic.grade(run, DrillConfig.Slips)
	local gradeDef = GRADES[grade]
	local data = dataService.get(player)
	if data == nil or gradeDef == nil then
		return
	end
	local best = data.Drills[drill.Id] or 0
	local owed = DrillLogic.toPay(best, grade)
	if #owed == 0 then
		notify.send(player, "drills.gradedAgain", { name = drill.NameKey, grade = gradeDef.NameKey }, "Info")
		log.info("%s drew %s again at %s", player.Name, drill.Id, gradeDef.Id)
		return
	end
	data.Drills[drill.Id] = grade
	dataService.push(player, DRILLS_SECTION)
	local folios, xp = 0, 0
	for _, value in ipairs(owed) do
		local def = GRADES[value]
		local reason = "Drill" .. drill.Id .. def.Id
		folios += currency.add(player, def.Folios, reason)
		xp += progression.addXp(player, def.Xp, reason)
	end
	notify.send(
		player,
		"drills.graded",
		{ name = drill.NameKey, grade = gradeDef.NameKey, folios = folios, xp = xp },
		"Success",
		"Claim"
	)
	log.info("%s drew %s at %s: +%d Folios, +%d XP", player.Name, drill.Id, gradeDef.Id, folios, xp)
end

-- One event of `player`'s, to their running set.
local function feed(player: Player, event: Event)
	local run = runs[player]
	if run == nil then
		return
	end
	if not inHub(player) then
		putDown(player, "drills.left")
		return
	end
	local outcome = DrillLogic.feed(run, event, os.clock())
	if outcome == nil then
		return
	end
	if DrillLogic.done(run) then
		finish(player, run)
		return
	end
	tell(player)
	local drill = run.Drill
	if outcome == "Rep" then
		notify.send(player, "drills.rep", { name = drill.NameKey, count = run.Reps, reps = drill.Reps }, "Info")
	else
		notify.send(player, "drills.miss", { name = drill.NameKey, misses = run.Misses }, "Info")
	end
end

-- Begins `drillId` for `player`, in place of any set already running. A recipe drill needs its glyph unlocked and
-- in the loadout, or no cast of it could ever count.
function DrillService.start(player: Player, drillId: string): boolean
	local data = dataService.get(player)
	local drill = DrillCatalog.ById[drillId]
	if data == nil or drill == nil then
		return false
	end
	if not inHub(player) then
		notify.send(player, "drills.notInHub", nil, "Error")
		return false
	end
	local glyphId = drill.Glyph
	if glyphId ~= nil then
		if table.find(data.Unlocks.Glyphs, glyphId) == nil then
			notify.send(player, "hud.cast.locked", { name = drill.NameKey }, "Error")
			return false
		end
		if table.find(data.Loadout.Slots, glyphId) == nil then
			notify.send(player, "hud.cast.notEquipped", { name = drill.NameKey }, "Error")
			return false
		end
	end
	runs[player] = DrillLogic.start(drill, os.clock())
	struck[player] = nil
	tell(player)
	notify.send(player, "drills.started", { name = drill.NameKey, hint = drill.HintKey, reps = drill.Reps }, "Info")
	log.info("%s began the drill %s", player.Name, drill.Id)
	return true
end

function DrillService.stop(player: Player)
	putDown(player, "drills.stopped")
end

-- The set `player` is doing, or nil.
function DrillService.getRun(player: Player): Snapshot?
	local run = runs[player]
	return if run ~= nil then snapshot(run) else nil
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < DrillConfig.CheckSeconds then
		return
	end
	accumulator = math.min(accumulator - DrillConfig.CheckSeconds, DrillConfig.CheckSeconds)
	local now = os.clock()
	for player, run in pairs(runs) do
		if not inHub(player) then
			putDown(player, "drills.left")
		elseif now - run.LastAt > DrillConfig.IdleSeconds then
			putDown(player, "drills.lapsed")
		end
	end
end

local function onDamaged(sourceUserId: number, _target: Model, applied: number, kind: string)
	if kind ~= MELEE_KIND or applied <= 0 or sourceUserId == 0 then
		return
	end
	local source = Players:GetPlayerByUserId(sourceUserId)
	if source ~= nil and runs[source] ~= nil then
		struck[source] = (struck[source] or 0) + 1
	end
end

function DrillService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	progression = deps.Progression
	currency = deps.Currency
	glyph = deps.Glyph
	combat = deps.Combat
	match = deps.Match
	worldBoss = deps.WorldBoss
	battleground = deps.Battleground
end

function DrillService.Start()
	glyph.Cast:Connect(function(player: Player, glyphId: string, chain: number)
		feed(player, { Kind = "Cast", Glyph = glyphId, Chain = chain })
	end)
	glyph.CastLanded:Connect(function(player: Player, glyphId: string, hits: number)
		feed(player, { Kind = "Landed", Glyph = glyphId, Hits = hits })
	end)
	combat.Damaged:Connect(onDamaged)
	combat.Swung:Connect(function(player: Player, index: number)
		local hits = struck[player] or 0
		struck[player] = nil
		feed(player, { Kind = "Swing", Index = index, Last = index >= FINISHER_INDEX, Hits = hits })
	end)
	combat.Dashed:Connect(function(player: Player, cancelled: boolean)
		feed(player, { Kind = "Dash", Cancelled = cancelled })
	end)
	registry.on("StartDrill", function(player: Player, drillId: string)
		DrillService.start(player, drillId)
	end)
	registry.on("StopDrill", function(player: Player)
		DrillService.stop(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		runs[player] = nil
		struck[player] = nil
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (%d drills)", #DrillCatalog.List)
end

return DrillService
