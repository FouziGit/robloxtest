--!strict
-- Accounts that may test the whole roster without earning it. Lives under src/server, which Rojo maps
-- to ServerScriptService, so no client can read it: src/shared is replicated and six client modules
-- require GameConfig, so a list kept there would have shipped the owner's user id to every player.
--
-- Pure on purpose: no Roblox global and no require, so tests/Config.spec.luau can load it.

local DeveloperConfig = {}

-- User ids are the real list. A Roblox username can be changed by its owner and the freed name can then
-- be taken by somebody else, while an id never changes. Names exist only for an account that has never
-- joined yet, and are matched exactly, case included.
DeveloperConfig.UserIds = { 3721321390 } :: { number } -- BakuyaraTZ
DeveloperConfig.Names = {} :: { string }

-- Every glyph equipped at once instead of the purchased slot budget.
DeveloperConfig.UnlimitedSlots = true

-- No ink cost, and cooldowns collapsed to MinRecastSeconds. Deliberately NOT a free-for-all: see
-- MinRecastSeconds below, and note that LoadoutService and GlyphService only honour this in the hub.
DeveloperConfig.FreeCasting = true

-- The floor a cooldown collapses to under FreeCasting. It is not zero because zero lets a glyph overlap
-- itself: every damage cap, hit tracker and duration in GlyphEffects is per cast, so two live casts of
-- the same glyph double their damage, stack their stuns and pile up their world geometry. 0.35 s is
-- longer than the longest zone tick interval, so a cast always ends before its successor begins.
DeveloperConfig.MinRecastSeconds = 0.35

-- True when this account is on the list. Id first, then the exact name.
function DeveloperConfig.isDeveloper(userId: number, name: string): boolean
	for _, id in ipairs(DeveloperConfig.UserIds) do
		if id == userId then
			return true
		end
	end
	for _, allowed in ipairs(DeveloperConfig.Names) do
		if allowed == name then
			return true
		end
	end
	return false
end

return DeveloperConfig
