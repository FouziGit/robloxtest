--!strict
-- Combo resolver: turns a sequence of element presses into a cast / wait / reset decision.
-- Pure module (no requires, no Roblox globals). Used by the client controller and by the server
-- to validate that a submitted sequence is a real recipe. Tested under Lune.
--
-- Rules (preserved from V1):
--   * sequence is a recipe AND no longer recipe starts with it → Cast immediately
--   * sequence is a prefix of at least one recipe → Wait (next press or timeout); Castable = true when
--     the sequence is already a recipe, so the client may use the short extend window instead of the
--     full timeout (docs/GAME_DESIGN.md §4)
--   * otherwise → Reset (NoMatch)
--   * on timeout: Cast if the pending sequence is a recipe, else Reset (Dissipated)

export type Recipe = { Id: string, Combo: { string } }

export type Resolver = {
	byKey: { [string]: string }, -- combo key -> jutsu id
	prefixes: { [string]: boolean }, -- keys that are strict prefixes of some recipe
	maxLength: number,
	duplicates: { string }, -- combo keys defined by more than one recipe (first wins)
}

export type Decision =
	{ Action: "Cast", JutsuId: string }
	| { Action: "Wait", Castable: boolean }
	| { Action: "Reset", Reason: "NoMatch" | "TooLong" | "Dissipated" | "Empty" }

local ComboResolver = {}

function ComboResolver.keyFor(sequence: { string }): string
	return table.concat(sequence, "-")
end

function ComboResolver.new(recipes: { Recipe }, maxLength: number): Resolver
	local resolver: Resolver = { byKey = {}, prefixes = {}, maxLength = maxLength, duplicates = {} }
	for _, recipe in ipairs(recipes) do
		local key = ComboResolver.keyFor(recipe.Combo)
		if resolver.byKey[key] ~= nil then
			table.insert(resolver.duplicates, key)
		else
			resolver.byKey[key] = recipe.Id
		end
		for length = 1, #recipe.Combo - 1 do
			resolver.prefixes[table.concat(recipe.Combo, "-", 1, length)] = true
		end
	end
	return resolver
end

-- Returns the updated sequence and the decision for it.
function ComboResolver.push(resolver: Resolver, sequence: { string }, element: string): ({ string }, Decision)
	local next = table.clone(sequence)
	table.insert(next, element)

	if #next > resolver.maxLength then
		return {}, { Action = "Reset", Reason = "TooLong" }
	end

	local key = ComboResolver.keyFor(next)
	local jutsuId = resolver.byKey[key]
	local isPrefix = resolver.prefixes[key] == true

	if jutsuId ~= nil and not isPrefix then
		return {}, { Action = "Cast", JutsuId = jutsuId }
	end
	if jutsuId == nil and not isPrefix then
		return {}, { Action = "Reset", Reason = "NoMatch" }
	end
	return next, { Action = "Wait", Castable = jutsuId ~= nil }
end

-- Called when the inactivity timeout elapses with `sequence` still pending.
function ComboResolver.timeout(resolver: Resolver, sequence: { string }): Decision
	if #sequence == 0 then
		return { Action = "Reset", Reason = "Empty" }
	end
	local jutsuId = resolver.byKey[ComboResolver.keyFor(sequence)]
	if jutsuId ~= nil then
		return { Action = "Cast", JutsuId = jutsuId }
	end
	return { Action = "Reset", Reason = "Dissipated" }
end

-- Server-side check: does this exact sequence map to a recipe?
function ComboResolver.resolve(resolver: Resolver, sequence: { string }): string?
	if #sequence == 0 or #sequence > resolver.maxLength then
		return nil
	end
	return resolver.byKey[ComboResolver.keyFor(sequence)]
end

return ComboResolver
