--!strict
-- The game pass cache (ProfileData.Passes) brought in line with what Roblox answered (D-211). Pure module: no
-- requires, no Roblox globals.
--
-- The cache used to only ever grow: a pass once cached stayed for good, so a Studio test purchase, a refund
-- or a pass deleted from the inventory kept its perks for ever (docs/QA.md R9). It now follows Roblox's
-- definite answers both ways, and only those: a check that failed says nothing, and must never take a pass
-- away while Roblox is down.

local PassCache = {}

-- Applies `answers` to `cache`, in place. `answers` holds a pass only when Roblox gave a definite answer for
-- it: owned enters the cache, not owned leaves it, and a pass left out (no id yet, or every check failed)
-- keeps what the cache said. `held` is the cache as it stood when the questions were asked: "not owned" only
-- takes out a pass it held, so a pass bought while Roblox was being asked, which the answer predates, stays.
-- Returns the passes that entered and the ones that left, each sorted.
function PassCache.reconcile(
	cache: { [string]: boolean },
	answers: { [string]: boolean },
	held: { [string]: boolean }
): ({ string }, { string })
	local added: { string } = {}
	local removed: { string } = {}
	for passKey, owned in pairs(answers) do
		local cached = cache[passKey] == true
		if owned and not cached then
			cache[passKey] = true
			table.insert(added, passKey)
		elseif not owned and cached and held[passKey] == true then
			cache[passKey] = nil
			table.insert(removed, passKey)
		end
	end
	table.sort(added)
	table.sort(removed)
	return added, removed
end

return PassCache
