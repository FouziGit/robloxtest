--!strict
-- ProgressionService: player XP and levels. Cascades level-ups, mirrors Level / Ryo into leaderstats
-- and forwards battle pass XP. The single writer of Progression.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Signal = require(Packages.Signal)
local Types = require(Shared.Types)

local log = Log.new("ProgressionService")

type ProfileData = Types.ProfileData
type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	ProfileLoaded: ProfileSignal,
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type BattlepassApi = { addXp: (player: Player, amount: number) -> () }
type Deps = { DataService: DataApi, Notify: NotifyApi, Battlepass: BattlepassApi }

-- leaderstats names are read by the engine's player list, not shown through Strings.
local LEADERSTATS_FOLDER = "leaderstats"
local LEADERSTAT_LEVEL = "Level"
local LEADERSTAT_RYO = "Ryo"
-- Pass key in ProfileData.Passes granting the XP multiplier (see MonetizationConfig.Passes).
local VIP_PASS_KEY = "Vip"

local ProgressionService = {}

ProgressionService.LevelUp = Signal.new() -- (player: Player, level: number)

local dataService: DataApi
local notify: NotifyApi
local battlepass: BattlepassApi

-- Multiplier applied to earned XP: VIP pass and any live timed boost, rounded down at the end so a
-- reward is never silently lost to floating point.
local function xpMultiplier(data: ProfileData): number
	local multiplier = 1
	if data.Passes[VIP_PASS_KEY] == true then
		multiplier *= ProgressionConfig.VipXpMultiplier
	end
	local boosts = data.Boosts
	if boosts.XpUntil > os.time() and boosts.XpMultiplier > 1 then
		multiplier *= boosts.XpMultiplier
	end
	return multiplier
end

local function isPositiveInteger(value: number): boolean
	return value == value and value ~= math.huge and value == math.floor(value) and value > 0
end

local function setLeaderstat(player: Player, name: string, value: number)
	local folder = player:FindFirstChild(LEADERSTATS_FOLDER)
	if folder == nil then
		return
	end
	local stat = folder:FindFirstChild(name)
	if stat ~= nil and stat:IsA("IntValue") then
		stat.Value = value
	end
end

local function createLeaderstats(player: Player, data: ProfileData)
	if player.Parent ~= Players then
		return
	end
	local existing = player:FindFirstChild(LEADERSTATS_FOLDER)
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = LEADERSTATS_FOLDER

	local level = Instance.new("IntValue")
	level.Name = LEADERSTAT_LEVEL
	level.Value = data.Progression.Level
	level.Parent = folder

	local ryo = Instance.new("IntValue")
	ryo.Name = LEADERSTAT_RYO
	ryo.Value = data.Currency.Ryo
	ryo.Parent = folder

	folder.Parent = player
end

-- Converts XP inside the current level into levels. Terminates because Level strictly increases
-- towards MaxLevel and every step costs a positive amount. Returns the number of levels gained.
local function cascade(progression: Types.ProgressionData): number
	local gained = 0
	local maxLevel = ProgressionConfig.MaxLevel
	while progression.Level < maxLevel do
		local needed = ProgressionConfig.xpForLevel(progression.Level)
		if needed <= 0 then
			log.error("xpForLevel(%d) = %d, cascade stopped", progression.Level, needed)
			break
		end
		if progression.XP < needed then
			break
		end
		progression.XP -= needed
		progression.Level += 1
		gained += 1
	end
	if progression.Level >= maxLevel then
		progression.Level = maxLevel
		progression.XP = 0
	end
	return gained
end

function ProgressionService.addXp(player: Player, amount: number, reason: string)
	if not isPositiveInteger(amount) then
		log.warn("addXp rejected for %s (%s): invalid amount %s", player.Name, reason, tostring(amount))
		return
	end
	local data = dataService.get(player)
	if data == nil then
		log.warn("addXp skipped for %s (%s): profile not loaded", player.Name, reason)
		return
	end

	local granted = math.max(1, math.floor(amount * xpMultiplier(data)))
	amount = granted

	local progression = data.Progression
	local previousLevel = progression.Level
	progression.TotalXP += amount
	if progression.Level < ProgressionConfig.MaxLevel then
		progression.XP += amount
	end
	local gained = cascade(progression)
	dataService.push(player, "Progression")

	if gained > 0 then
		setLeaderstat(player, LEADERSTAT_LEVEL, progression.Level)
		for level = previousLevel + 1, progression.Level do
			ProgressionService.LevelUp:Fire(player, level)
		end
		notify.send(player, "hud.levelUp", { level = progression.Level }, "Success", "LevelUp")
		log.info("%s reached level %d (%s)", player.Name, progression.Level, reason)
	end

	local passXp = math.floor(amount * ProgressionConfig.BattlepassXpMultiplier)
	if passXp > 0 then
		battlepass.addXp(player, passXp)
	end
end

-- Current level, 0 while the profile is not loaded (so level gates stay closed).
function ProgressionService.getLevel(player: Player): number
	local data = dataService.get(player)
	if data == nil then
		return 0
	end
	return data.Progression.Level
end

function ProgressionService.Init(deps: Deps)
	dataService = deps.DataService
	notify = deps.Notify
	battlepass = deps.Battlepass
end

function ProgressionService.Start()
	dataService.ProfileLoaded:Connect(createLeaderstats)
	log.info("started")
end

return ProgressionService
