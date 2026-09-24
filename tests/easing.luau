--!strict
-- Roblox's easing curves, as TweenService:GetValue draws them, for the gates that must measure a layer on
-- the curve it declares rather than on one they assume (a crown gate that took every ease for a square
-- passed a crown standing high for 0.35 s: review).
--
-- Measured in Studio (TweenService:GetValue at 0.001, 0.1, 0.25, 0.37, 0.5, 0.7, 0.9 and 0.999 for every
-- style and direction, 2026-09-24): Out is the In curve turned over, InOut is the In curve at twice the
-- speed then turned over for its second half -- Back's included, with the plain 1.70158 -- and every curve
-- is exactly 0 at 0 and 1 at 1, Exponential's too.
local Easing = {}

local BACK = 1.70158

local IN: { [string]: (number) -> number } = {
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t * t * t * t
	end,
	Quint = function(t)
		return t * t * t * t * t
	end,
	Sine = function(t)
		return 1 - math.cos(t * math.pi / 2)
	end,
	Back = function(t)
		return (BACK + 1) * t * t * t - BACK * t * t
	end,
	Exponential = function(t)
		return 2 ^ (10 * (t - 1))
	end,
	Circular = function(t)
		return 1 - math.sqrt(1 - t * t)
	end,
}

-- The eased value of `t` (0 to 1) on `style` and `direction` ("Out" when absent, as the runtime reads
-- it). Errors on a style it does not know, so a gate can never measure an unknown curve as some other.
function Easing.value(style: string, direction: string?, t: number): number
	local curve = IN[style]
	if curve == nil then
		error("no easing curve named " .. tostring(style))
	end
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	local towards = direction or "Out"
	if towards == "In" then
		return curve(t)
	elseif towards == "Out" then
		return 1 - curve(1 - t)
	elseif towards == "InOut" then
		if t < 0.5 then
			return curve(2 * t) / 2
		end
		return 1 - curve(2 - 2 * t) / 2
	end
	error("no easing direction named " .. tostring(direction))
end

return Easing
