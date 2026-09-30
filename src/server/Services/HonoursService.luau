--!strict
-- HonoursService: the single writer of ProfileData.Milestones. What a veteran climbs for once the glyphs and the
-- pigment are all unlocked (docs/GAME_DESIGN.md §9): the milestones of the level road, from 45 to the last level
-- (ProgressionConfig.Milestones, Pure/LevelRoad), each paid once, its Folios and, three times, a title.
--
-- A level-up pays the milestone of that level. A profile that loads past milestones it was never paid -- one that
-- climbed before they existed, or a session that ended between the level and its payment -- is paid them then,
-- lowest first. A milestone is written into the profile before anything is paid for it, so no second path to
-- the same level (a level-up racing a load) can pay it twice; the player earns nothing by asking, and nothing
-- here listens to a client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local LevelRoad = require(Shared.Pure.LevelRoad)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)

local log = Log.new("HonoursService")

type ProfileData = Types.ProfileData
type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
type LevelSignal = { Connect: (self: LevelSignal, fn: (player: Player, level: number) -> ()) -> any }
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	ProfileLoaded: ProfileSignal,
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> number }
type CosmeticApi = { grant: (player: Player, cosmeticId: string) -> boolean }
type ProgressionApi = { LevelUp: LevelSignal }
type Deps = {
	DataService: DataApi,
	Notify: NotifyApi,
	Currency: CurrencyApi,
	Cosmetic: CosmeticApi,
	Progression: ProgressionApi,
}

local ROAD =
	LevelRoad.build(GlyphConfig.levelUnlocks(), ProgressionConfig.OrpimentUnlockLevel, ProgressionConfig.Milestones)
local MILESTONES_SECTION = "Milestones"

local HonoursService = {}

local dataService: DataApi
local notify: NotifyApi
local currency: CurrencyApi
local cosmetic: CosmeticApi
local progression: ProgressionApi

-- Pays `step` to `player` unless the profile already holds it, and returns the Folios it paid (0 when it did
-- not). Marked and replicated first: whatever pays after it, a second call for the same level finds it paid.
-- `quiet` is for a load that owes several at once: twelve toasts would bury everything else, and the caller says
-- it in one line.
local function payMilestone(player: Player, data: ProfileData, step: LevelRoad.Step, quiet: boolean): number
	if data.Milestones[step.Id] == true then
		return 0
	end
	data.Milestones[step.Id] = true
	dataService.push(player, MILESTONES_SECTION)
	local folios = currency.add(player, step.Folios, "Milestone" .. step.Id)
	local title = step.Title
	local item = if title ~= nil then CosmeticConfig.ById[title] else nil
	local titled = title ~= nil and item ~= nil and cosmetic.grant(player, title)
	log.info(
		"%s reached the milestone of level %d: +%d Folios%s",
		player.Name,
		step.Level,
		folios,
		if titled then ", " .. tostring(title) else ""
	)
	if quiet then
		return folios
	end
	if titled and item ~= nil then
		local params = { level = step.Level, amount = folios, title = item.Look.TextKey }
		notify.send(player, "milestone.reachedTitle", params, "Success", "LevelUp")
	else
		notify.send(player, "milestone.reached", { level = step.Level, amount = folios }, "Success", "LevelUp")
	end
	return folios
end

local function onLevelUp(player: Player, level: number)
	local data = dataService.get(player)
	if data == nil then
		return
	end
	local step = LevelRoad.milestoneAt(ROAD, level)
	if step ~= nil then
		payMilestone(player, data, step, false)
	end
end

local function onProfileLoaded(player: Player, data: ProfileData)
	local count, folios = 0, 0
	for _, step in ipairs(LevelRoad.dueMilestones(ROAD, data.Progression.Level, data.Milestones)) do
		count += 1
		folios += payMilestone(player, data, step, true)
	end
	if count > 0 then
		notify.send(player, "milestone.caughtUp", { count = count, amount = folios }, "Success", "LevelUp")
	end
end

function HonoursService.Init(deps: Deps)
	dataService = deps.DataService
	notify = deps.Notify
	currency = deps.Currency
	cosmetic = deps.Cosmetic
	progression = deps.Progression
	for _, milestone in ipairs(ProgressionConfig.Milestones) do
		local title = milestone.Title
		if title ~= nil and CosmeticConfig.ById[title] == nil then
			log.warn(
				"the milestone of level %d names %s, which is no cosmetic: it pays Folios only",
				milestone.Level,
				title
			)
		end
	end
end

function HonoursService.Start()
	dataService.ProfileLoaded:Connect(onProfileLoaded)
	progression.LevelUp:Connect(onLevelUp)
	log.info("started (%d milestones)", #ProgressionConfig.Milestones)
end

return HonoursService
