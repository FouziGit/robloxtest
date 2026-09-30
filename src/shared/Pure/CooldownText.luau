--!strict
-- CooldownText: the seconds a cooling glyph shows on its hotbar slot (D-147, the board's "3,2"). Pure: no Roblox
-- global, no require; tested under Lune (tests/CooldownText.spec.luau). Under ten seconds it counts in tenths,
-- from ten up in whole seconds, both rounded up: a glyph never reads ready before the server says it is. The
-- locale writes the mark between the seconds and the tenth (hud.hotbar.seconds).

local CooldownText = {}

-- From this many seconds up, whole seconds.
CooldownText.TenthsBelow = 10

-- The server's seconds carry a float's noise ("3.2" is 3.2000000000000002): what is under this much past a
-- tenth is the tenth itself.
local EPSILON = 1e-6

-- What `remaining` seconds show: the whole seconds, and the tenth under TenthsBelow (nil from there up).
function CooldownText.split(remaining: number): (number, number?)
	local tenths = math.ceil(remaining * 10 - EPSILON)
	if tenths >= CooldownText.TenthsBelow * 10 then
		return math.ceil(remaining - EPSILON), nil
	end
	return tenths // 10, tenths % 10
end

return CooldownText
