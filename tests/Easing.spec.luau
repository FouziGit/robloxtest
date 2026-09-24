--!strict
-- The test port of Roblox's easing curves (tests/easing.luau) held to TweenService:GetValue itself: every
-- style and direction the timelines may declare, at five points, as Studio returned them on 2026-09-24.
-- A gate that measures a layer on its declared curve is only as good as this port.
local Easing = require("./easing")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local POINTS = { 0.1, 0.25, 0.5, 0.7, 0.9 }

-- style/direction -> TweenService:GetValue at POINTS.
local MEASURED: { [string]: { number } } = {
	["Quad/In"] = { 0.010000001, 0.0625, 0.25, 0.48999998, 0.809999943 },
	["Quad/Out"] = { 0.190000057, 0.4375, 0.75, 0.909999967, 0.99000001 },
	["Quad/InOut"] = { 0.020000001, 0.125, 0.5, 0.819999993, 0.980000019 },
	["Cubic/In"] = { 0.001, 0.015625, 0.125, 0.342999995, 0.728999913 },
	["Cubic/Out"] = { 0.271000087, 0.578125, 0.875, 0.97299999, 0.999000013 },
	["Cubic/InOut"] = { 0.004, 0.0625, 0.5, 0.89199996, 0.995999992 },
	["Quart/In"] = { 0.0001, 0.00390625, 0.0625, 0.240099981, 0.656099916 },
	["Quart/Out"] = { 0.343900084, 0.68359375, 0.9375, 0.991900027, 0.999899983 },
	["Quart/InOut"] = { 0.0008, 0.03125, 0.5, 0.935199976, 0.999199986 },
	["Quint/In"] = { 0.00001, 0.000976562, 0.03125, 0.168069988, 0.590489924 },
	["Quint/Out"] = { 0.409510076, 0.762695312, 0.96875, 0.997569978, 0.999989986 },
	["Quint/InOut"] = { 0.00016, 0.015625, 0.5, 0.961120009, 0.999840021 },
	["Sine/In"] = { 0.01231166, 0.076120466, 0.292893231, 0.546009481, 0.843565524 },
	["Sine/Out"] = { 0.156434476, 0.382683456, 0.707106769, 0.891006529, 0.987688363 },
	["Sine/InOut"] = { 0.024471743, 0.146446615, 0.5, 0.793892622, 0.97552824 },
	["Back/In"] = { -0.014314221, -0.064136565, -0.087697506, 0.092867717, 0.59117192 },
	["Back/Out"] = { 0.40882808, 0.817409694, 1.087697506, 1.080199599, 1.014314175 },
	["Back/InOut"] = { -0.023225281, -0.043848753, 0.5, 1.014513731, 1.023225307 },
	["Exponential/In"] = { 0.001953125, 0.005524272, 0.03125, 0.125, 0.499999911 },
	["Exponential/Out"] = { 0.500000119, 0.823223293, 0.96875, 0.9921875, 0.998046875 },
	["Exponential/InOut"] = { 0.001953125, 0.015625, 0.5, 0.96875, 0.998046875 },
	["Circular/In"] = { 0.005012572, 0.031754136, 0.133974612, 0.285857141, 0.564110041 },
	["Circular/Out"] = { 0.435889959, 0.661437809, 0.866025388, 0.953939199, 0.994987428 },
	["Circular/InOut"] = { 0.010102063, 0.066987306, 0.5, 0.899999976, 0.989897966 },
}

describe("the easing port", function()
	it("draws every curve as TweenService does", function()
		local checked = 0
		for key, values in pairs(MEASURED) do
			local style, direction = key:match("^(%a+)/(%a+)$")
			for index, t in ipairs(POINTS) do
				local value = Easing.value(style :: string, direction, t)
				-- Studio's values are single precision.
				if math.abs(value - values[index]) > 1e-6 then
					error(("%s at %.2f: %.9f, Studio %.9f"):format(key, t, value, values[index]))
				end
				checked += 1
			end
		end
		expect(checked).toBe(24 * #POINTS)
	end)

	it("is exactly 0 at the start and 1 at the end, reads Out when no direction is given", function()
		for key in pairs(MEASURED) do
			local style, direction = key:match("^(%a+)/(%a+)$")
			expect(Easing.value(style :: string, direction, 0)).toBe(0)
			expect(Easing.value(style :: string, direction, 1)).toBe(1)
		end
		expect(Easing.value("Quad", nil, 0.3)).toBe(Easing.value("Quad", "Out", 0.3))
	end)

	it("refuses a curve it does not know rather than measuring it as another", function()
		expect(pcall(Easing.value, "Linear", "Out", 0.5)).toBe(false)
		expect(pcall(Easing.value, "Quad", "Sideways", 0.5)).toBe(false)
	end)
end)
