--!strict
-- A scrap of paper thrown off a blast (Pure/Scatter, D-114), held to how paper falls: it rises, stops,
-- rocks from side to side on the way down at a speed it settles into, and lands where the floor is.
local Harness = require("./harness")
local Scatter = require("../src/shared/Pure/Scatter")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function piece(vx: number, vy: number, vz: number): Scatter.Piece
	return { VX = vx, VY = vy, VZ = vz, Drag = 3, Fall = 7, Rock = 0.5, RockRate = 8, Phase = 0.3, Tumble = 10 }
end

local function height(p: Scatter.Piece, t: number): number
	local _, y = Scatter.offset(p, t)
	return y
end

describe("a thrown scrap", function()
	it("rises until its apex and falls after it", function()
		local p = piece(6, 18, 2)
		local apex = Scatter.apex(p)
		expect(apex).toBeGreaterThan(0)
		-- At the apex it has stopped rising: a hair either side is lower.
		expect(height(p, apex) >= height(p, apex - 1e-3)).toBe(true)
		expect(height(p, apex) >= height(p, apex + 1e-3)).toBe(true)
		expect(height(p, apex)).toBeGreaterThan(0)
		for step = 1, 20 do
			local t = apex + step * 0.05
			expect(height(p, t) < height(p, t - 0.05)).toBe(true)
		end
	end)

	it("settles into a gentle fall instead of accelerating like a stone", function()
		local p = piece(0, 10, 0)
		local speed = (height(p, 4) - height(p, 4.01)) / 0.01
		expect(math.abs(speed - p.Fall)).toBeLessThan(0.05)
	end)

	it("has no apex to wait for when it was thrown down", function()
		expect(Scatter.apex(piece(3, -2, 0))).toBe(0)
	end)

	it("rocks only after its apex, and only across its own flight", function()
		local p = piece(10, 15, 0)
		local apex = Scatter.apex(p)
		-- Before the apex its horizontal path is its throw's alone: nothing across it.
		local _, _, z = Scatter.offset(p, apex * 0.5)
		expect(math.abs(z)).toBeLessThan(1e-9)
		-- After it, the rock moves it across (z, for a throw along x), never along.
		local _, _, zLater = Scatter.offset(p, apex + 0.5)
		expect(math.abs(zLater)).toBeGreaterThan(0.05)
		expect(math.abs(zLater)).toBeLessThanOrEqual(p.Rock + 1e-9)
	end)

	it("rocks in gently: no jump sideways at the apex, where the rock begins", function()
		-- Without the ease-in a scrap jumped across by Rock * sin(Phase), up to 0.6 stud, in one frame.
		for _, phase in ipairs({ 0.3, 1.2, 2.5, 4 }) do
			local p = piece(8, 14, -5)
			p.Phase = phase
			local apex = Scatter.apex(p)
			local x1, y1, z1 = Scatter.offset(p, apex - 1e-3)
			local x2, y2, z2 = Scatter.offset(p, apex + 1e-3)
			local step = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2)
			-- Two milliseconds at the speed it has there, and no more.
			expect(step).toBeLessThan(0.02)
		end
	end)

	it("lands exactly where the floor is, after its apex, and not at all when it cannot reach it", function()
		local p = piece(4, 16, -3)
		local landing = Scatter.landing(p, 0.5, 5) :: number
		expect(landing).never.toBe(nil)
		expect(landing).toBeGreaterThan(Scatter.apex(p))
		expect(math.abs(height(p, landing) + 0.5)).toBeLessThan(1e-4)
		-- A floor thirty studs down is not reached in a second.
		expect(Scatter.landing(p, 30, 1)).toBe(nil)
	end)

	it("tumbles further the longer it flies, and flies the same way every time", function()
		local p = piece(5, 12, 5)
		local last = -1
		for step = 0, 30 do
			local angle = Scatter.tumble(p, step * 0.05)
			expect(angle > last).toBe(true)
			last = angle
		end
		local x1, y1, z1 = Scatter.offset(p, 0.73)
		local x2, y2, z2 = Scatter.offset(piece(5, 12, 5), 0.73)
		expect(x1).toBe(x2)
		expect(y1).toBe(y2)
		expect(z1).toBe(z2)
	end)
end)
