--!strict
-- LoadoutService: the single writer of ProfileData.Loadout and ProfileData.Unlocks. Grants the glyphs
-- a profile has earned (level gates of GlyphConfig.Unlock, every glyph of an owned pigment), unlocks
-- Orpiment at ProgressionConfig.OrpimentUnlockLevel and validates every SetLoadout.
--
-- The client only names glyph ids: the slot budget, the duplicates and what is unlocked are decided
-- here. A refusal is replicated too, so the client never stays on a loadout the server did not accept.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeveloperConfig = require(script.Parent.Parent.Config.DeveloperConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)

local log = Log.new("LoadoutService")

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
type ProgressionApi = { LevelUp: LevelSignal }
-- CosmeticService owns Cosmetics: it takes back what the developer list paid for when the list lets go.
type CosmeticApi = { revokeWaived: (player: Player) -> () }
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Progression: ProgressionApi,
	Cosmetic: CosmeticApi,
}

local LOADOUT = ProgressionConfig.Loadout
local ORPIMENT_PIGMENT = "Orpiment"
local ORPIMENT_LEVEL = ProgressionConfig.OrpimentUnlockLevel
-- The MonetizationConfig.Passes key of the pass that sells the Orpiment pigment, as ProfileData.Passes caches it.
local ORPIMENT_PASS = "Orpiment"
local PIGMENT_NAME_KEYS = (PigmentConfig.NameKeys :: any) :: { [string]: string? }
-- Strings has no dedicated unlock key; "{name} unlocked!" is the closest fit (see notes).
local UNLOCKED_KEY = "purchase.passGranted"
-- The one line a catch-up grant sends at login, with how many glyphs it handed over.
local CAUGHT_UP_KEY = "loadout.caughtUp"

local LoadoutService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local progression: ProgressionApi
local cosmetic: CosmeticApi

-- Adds `glyphId` to the unlocks when it is missing and tells the player. Returns true when it was just
-- granted (the caller pushes "Unlocks" once for the whole batch).
local function grantGlyph(player: Player, data: ProfileData, glyphId: string, quiet: boolean?): boolean
	if table.find(data.Unlocks.Glyphs, glyphId) ~= nil then
		return false
	end
	local def = GlyphConfig.ById[glyphId]
	if def == nil then
		log.error("unknown glyph %s for %s", glyphId, player.Name)
		return false
	end
	table.insert(data.Unlocks.Glyphs, glyphId)
	if not quiet then
		-- `quiet` is for a bulk grant: twenty toasts at once would bury everything else on screen.
		notify.send(player, UNLOCKED_KEY, { name = def.NameKey }, "Success", "LevelUp")
	end
	return true
end

-- Grants every glyph the profile has already earned: the level gates up to its current level and the
-- glyphs of every owned pigment. Catches up a profile that predates a roster change or comes from V1.
-- Quietly: a roster that grows by eight hands a veteran all eight at once, and the caller says so in one line.
local function grantEarned(player: Player, data: ProfileData): number
	local granted = 0
	for level = 1, data.Progression.Level do
		for _, glyphId in ipairs(GlyphConfig.unlocksForLevel(level)) do
			if grantGlyph(player, data, glyphId, true) then
				granted += 1
			end
		end
	end
	for _, pigment in ipairs(data.Unlocks.Pigments) do
		for _, glyphId in ipairs(GlyphConfig.unlocksForPigment(pigment)) do
			if grantGlyph(player, data, glyphId, true) then
				granted += 1
			end
		end
	end
	return granted
end

local function isDeveloper(player: Player): boolean
	return DeveloperConfig.isDeveloper(player.UserId, player.Name)
end

-- The slots a player owns: the base slots plus what the pass bought, capped.
local function ownedSlots(data: ProfileData): number
	return math.clamp(LOADOUT.BaseSlots + math.max(0, data.Loadout.ExtraSlots), LOADOUT.BaseSlots, LOADOUT.MaxSlots)
end

-- The pigments the profile holds on its own: the base ones, and Orpiment once reached by level or bought.
local function earnedPigments(data: ProfileData): { string }
	local pigments: { string } = {}
	for _, pigment in ipairs(PigmentConfig.Base) do
		table.insert(pigments, pigment)
	end
	if data.Progression.Level >= ORPIMENT_LEVEL or data.Passes[ORPIMENT_PASS] == true then
		table.insert(pigments, ORPIMENT_PIGMENT)
	end
	return pigments
end

-- The glyphs the profile holds on its own: the defaults, every level gate up to its level, and the glyphs of
-- the pigments it earned.
local function earnedGlyphs(data: ProfileData): { string }
	local glyphs = GlyphConfig.defaultUnlocks()
	for level = 1, data.Progression.Level do
		for _, glyphId in ipairs(GlyphConfig.unlocksForLevel(level)) do
			table.insert(glyphs, glyphId)
		end
	end
	for _, pigment in ipairs(earnedPigments(data)) do
		for _, glyphId in ipairs(GlyphConfig.unlocksForPigment(pigment)) do
			table.insert(glyphs, glyphId)
		end
	end
	return glyphs
end

-- What `data` fields with the developer list set aside: the glyphs it earned, and the loadout a player with
-- the same level, passes and slots could equip -- its earned glyphs, in slot order, cut to the slots it owns.
-- Wherever play pays out, GlyphService checks a developer's cast against this rather than against the whole
-- roster, in as many slots, that the list hands out (DeveloperConfig.UnlimitedSlots is the hub's).
function LoadoutService.fielded(data: ProfileData): ({ string }, { string })
	local unlocked = earnedGlyphs(data)
	local budget = ownedSlots(data)
	local slots: { string } = {}
	for _, glyphId in ipairs(data.Loadout.Slots) do
		if #slots >= budget then
			break
		end
		if table.find(unlocked, glyphId) ~= nil then
			table.insert(slots, glyphId)
		end
	end
	return unlocked, slots
end

-- Slots this player may fill, written into the profile so the client reads the number instead of
-- recomputing the rule. A developer with UnlimitedSlots holds the whole roster; everybody else gets the
-- base slots plus what the pass bought, capped.
local function refreshSlotLimit(player: Player, data: ProfileData): boolean
	local limit = ownedSlots(data)
	if isDeveloper(player) and DeveloperConfig.UnlimitedSlots then
		limit = #GlyphConfig.Glyphs
	end
	-- Anything already equipped beyond the new budget is dropped here. A limit that shrinks below the
	-- equipped count (an account leaving the developer list, a refunded pass) would otherwise leave a
	-- profile whose own loadout every future setLoadout refuses, while the extra glyphs stayed castable.
	local trimmed = false
	while #data.Loadout.Slots > limit do
		table.remove(data.Loadout.Slots)
		trimmed = true
	end
	if data.Loadout.SlotLimit == limit and not trimmed then
		return false
	end
	data.Loadout.SlotLimit = limit
	dataService.push(player, "Loadout")
	return true
end

-- Hands a developer account the whole roster: every pigment, every glyph, every loadout slot. Runs on
-- each join because in Studio the profile is a fresh template every session.
local function grantEverything(player: Player, data: ProfileData)
	for _, pigmentId in ipairs(PigmentConfig.Unlockable) do
		LoadoutService.grantPigment(player, pigmentId)
	end
	local granted = 0
	for _, def in ipairs(GlyphConfig.Glyphs) do
		if grantGlyph(player, data, def.Id, true) then
			granted += 1
		end
	end
	if granted > 0 then
		dataService.push(player, "Unlocks")
	end
	if not data.Meta.DevGranted then
		-- Recorded so the grant can be undone if the account ever leaves the list.
		data.Meta.DevGranted = true
		dataService.push(player, "Meta")
	end
	refreshSlotLimit(player, data)
	log.info(
		"%s (id %d) is a developer: %d glyph(s) granted, %d slots, free casting %s",
		player.Name,
		player.UserId,
		granted,
		data.Loadout.SlotLimit,
		tostring(DeveloperConfig.FreeCasting)
	)
end

-- Grants `pigmentId` and every glyph it gates (the Orpiment game pass, the level gate). Idempotent:
-- false when the pigment is already owned or unknown.
function LoadoutService.grantPigment(player: Player, pigmentId: string): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("grantPigment skipped for %s: profile not loaded", player.Name)
		return false
	end
	if not PigmentConfig.isPigment(pigmentId) then
		log.error("unknown pigment %s for %s", pigmentId, player.Name)
		return false
	end
	if table.find(data.Unlocks.Pigments, pigmentId) ~= nil then
		return false
	end
	table.insert(data.Unlocks.Pigments, pigmentId)
	local nameKey = PIGMENT_NAME_KEYS[pigmentId]
	if nameKey ~= nil then
		notify.send(player, UNLOCKED_KEY, { name = nameKey }, "Success", "LevelUp")
	end
	for _, glyphId in ipairs(GlyphConfig.unlocksForPigment(pigmentId)) do
		grantGlyph(player, data, glyphId)
	end
	dataService.push(player, "Unlocks")
	log.info("%s unlocked the %s pigment", player.Name, pigmentId)
	return true
end

-- Sets how many extra loadout slots the profile owns (the LoadoutSlots game pass grants them). Lives here
-- so ProfileData.Loadout keeps a single writer. Idempotent: false when the count is already stored, so
-- re-applying an owned pass on every profile load writes and replicates nothing.
function LoadoutService.setExtraSlots(player: Player, count: number): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("setExtraSlots skipped for %s: profile not loaded", player.Name)
		return false
	end
	if count < 0 or count % 1 ~= 0 or LOADOUT.BaseSlots + count > LOADOUT.MaxSlots then
		log.error("rejected %s extra slot(s) for %s", tostring(count), player.Name)
		return false
	end
	if data.Loadout.ExtraSlots == count then
		return false
	end
	data.Loadout.ExtraSlots = count
	-- Refreshes and pushes: without it the purchased slots stayed inert for the whole session, because
	-- the budget the client reads and the one setLoadout validates against both live in SlotLimit.
	if not refreshSlotLimit(player, data) then
		dataService.push(player, "Loadout")
	end
	log.info("%s now owns %d extra loadout slot(s)", player.Name, count)
	return true
end

-- Validates and stores a loadout: at most the slots the profile owns, no duplicate, nothing locked.
function LoadoutService.setLoadout(player: Player, slots: { string }): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("setLoadout skipped for %s: profile not loaded", player.Name)
		return false
	end
	-- The limit the profile carries, refreshed whenever anything that decides it changes. Recomputing it
	-- here would be a second copy of the rule and would miss the developer exception.
	refreshSlotLimit(player, data)
	local limit = data.Loadout.SlotLimit

	local function reject(reason: string): boolean
		log.warn("setLoadout rejected for %s: %s", player.Name, reason)
		notify.send(player, "loadout.invalid", nil, "Error", "Error")
		dataService.push(player, "Loadout")
		return false
	end

	if #slots > limit then
		return reject(string.format("%d ids for %d slots", #slots, limit))
	end
	local seen: { [string]: boolean } = {}
	for _, glyphId in ipairs(slots) do
		if seen[glyphId] then
			return reject("duplicate " .. glyphId)
		end
		seen[glyphId] = true
		if GlyphConfig.ById[glyphId] == nil then
			return reject("unknown glyph " .. glyphId)
		end
		if table.find(data.Unlocks.Glyphs, glyphId) == nil then
			return reject(glyphId .. " is not unlocked")
		end
	end

	data.Loadout.Slots = table.clone(slots)
	dataService.push(player, "Loadout")
	notify.send(player, "loadout.saved", nil, "Success", "UiClick")
	log.info("%s saved a loadout of %d glyph(s)", player.Name, #slots)
	return true
end

local function onLevelUp(player: Player, level: number)
	local data = dataService.get(player)
	if data == nil then
		return
	end
	local granted = 0
	for _, glyphId in ipairs(GlyphConfig.unlocksForLevel(level)) do
		if grantGlyph(player, data, glyphId) then
			granted += 1
		end
	end
	if granted > 0 then
		dataService.push(player, "Unlocks")
		log.info("%s unlocked %d glyph(s) at level %d", player.Name, granted, level)
	end
	if level >= ORPIMENT_LEVEL then
		LoadoutService.grantPigment(player, ORPIMENT_PIGMENT)
	end
end

-- Puts back what the developer list handed out, for an account that is no longer on it. Without this the
-- grant was irrevocable: removing the id left the profile holding the whole roster and the Orpiment
-- pigment that other players pay for, with the whole set still castable.
--
-- The unlocks are rebuilt rather than subtracted, because there is no record of which ones were earned: the
-- profile becomes exactly what it fields with the list set aside (LoadoutService.fielded), its loadout
-- included, and refreshSlotLimit then writes the real budget. The cosmetics the list paid for leave too.
local function revokeDeveloperGrants(player: Player, data: ProfileData)
	local unlocked, slots = LoadoutService.fielded(data)
	data.Unlocks.Pigments = earnedPigments(data)
	data.Unlocks.Glyphs = unlocked
	data.Loadout.Slots = slots
	data.Meta.DevGranted = false
	dataService.push(player, "Unlocks")
	dataService.push(player, "Loadout")
	log.try("revokeWaived " .. player.Name, cosmetic.revokeWaived, player)
	log.info("%s is no longer a developer: unlocks rebuilt from what the profile earned", player.Name)
end

local function onProfileLoaded(player: Player, data: ProfileData)
	if isDeveloper(player) then
		grantEverything(player, data)
		return
	end
	if data.Meta.DevGranted then
		revokeDeveloperGrants(player, data)
	end
	if data.Progression.Level >= ORPIMENT_LEVEL then
		LoadoutService.grantPigment(player, ORPIMENT_PIGMENT)
	end
	local caughtUp = grantEarned(player, data)
	if caughtUp > 0 then
		dataService.push(player, "Unlocks")
		notify.send(player, CAUGHT_UP_KEY, { count = caughtUp }, "Success", "LevelUp")
	end
	refreshSlotLimit(player, data)
end

function LoadoutService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	progression = deps.Progression
	cosmetic = deps.Cosmetic
end

function LoadoutService.Start()
	dataService.ProfileLoaded:Connect(onProfileLoaded)
	progression.LevelUp:Connect(onLevelUp)
	registry.on("SetLoadout", function(player: Player, slots: { string })
		LoadoutService.setLoadout(player, slots)
	end)
	log.info("started (%d base slots, %d max)", LOADOUT.BaseSlots, LOADOUT.MaxSlots)
end

return LoadoutService
