--!strict
-- ChannelHold: the hold a charged glyph or a rush keeps on its caster (D-142), and whose hold it is. Pure: no
-- Roblox global, no require, so it is unit-tested under Lune (tests/Channel.spec.luau).
--
-- A player has one hold at a time, and every hold opened is numbered. The effect that opened one asks about its
-- own number, never about "a hold": a dash that broke it and a later glyph that opened another are then never
-- read as its own, and it can end only its own. The deadline is the gate -- no M1 and no other glyph until it
-- passes -- and the gate's safety net: a hold whose effect died still lets go. It is not how an effect learns
-- that its hold is over, or a server frame running late past it would cancel a charge that nothing broke.
-- CombatService keeps one per player and does the Roblox parts: the clock, and who is asking.

local ChannelHold = {}

export type Hold = {
	-- The clock time the gate opens again.
	Until: number,
	-- The number of the hold being kept, or of the last one that ended: never reused.
	Token: number,
}

function ChannelHold.new(): Hold
	return { Until = 0, Token = 0 }
end

-- Opens a hold of `seconds` from `now` over whatever was held before, and returns its number.
function ChannelHold.open(hold: Hold, now: number, seconds: number): number
	hold.Token += 1
	hold.Until = now + seconds
	return hold.Token
end

-- Whether the M1 and every other glyph are refused at `now`: a hold is kept, whoever opened it.
function ChannelHold.refuses(hold: Hold, now: number): boolean
	return now < hold.Until
end

-- Whether hold `token` is still the one kept: nothing broke it, ended it or opened another since.
function ChannelHold.owns(hold: Hold, token: number): boolean
	return token > 0 and hold.Token == token
end

-- Ends hold `token`, and only it: an effect that finishes never lets go of a hold a later cast opened.
function ChannelHold.close(hold: Hold, token: number)
	if ChannelHold.owns(hold, token) then
		hold.Token += 1
		hold.Until = 0
	end
end

-- Breaks whatever is held (a dash, a new body): the effect that kept it finds out the next time it asks.
function ChannelHold.breaks(hold: Hold)
	hold.Token += 1
	hold.Until = 0
end

return ChannelHold
