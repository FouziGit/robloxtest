--!strict
-- Which ratings may reach a season ladder, and which ladder rows are players (D-203). Pure module: no
-- requires, no Roblox globals.
--
-- Studio's multi-client tests hand their local players ids of zero and below. With API access those ids
-- were written into the real season ladders, where they had no name to resolve and showed as raw numbers
-- (docs/QA.md R5). A Roblox account id is a positive integer: anything else is a test player, never written,
-- and a row that holds one, written before this gate, is never shown.

export type Refusal = "TestId" | "Studio"

local LadderGate = {}

-- True when `userId` can be a Roblox account.
function LadderGate.isPlayerId(userId: number): boolean
	return userId > 0 and userId == math.floor(userId) and userId ~= math.huge
end

-- Nil when a rating of `userId` may be written to the ladders; otherwise why not. A test id is refused first,
-- whatever the switch says; a Studio session writes only when `studioWrites` (StudioConfig.WriteLadders).
function LadderGate.refusal(userId: number, isStudio: boolean, studioWrites: boolean): Refusal?
	if not LadderGate.isPlayerId(userId) then
		return "TestId"
	end
	if isStudio and not studioWrites then
		return "Studio"
	end
	return nil
end

return LadderGate
