--!strict
-- The posture: the only thing in this game that moves a body. Until it existed a character landed a
-- four-hit combo with its arms down, so these gates are mostly about the poses being real, distinct and
-- all reachable -- a pose nobody plays is a pose that is wrong and nobody finds out.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Harness = require("./harness")
local PostureConfig = require("../src/shared/Config/PostureConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CONTROLLER = "src/client/Controllers/Posture.luau"
local RIGS = { "R6", "R15" }

local function jointSet(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, joint in ipairs(PostureConfig.JointOrder) do
		set[joint] = true
	end
	return set
end

-- Sum of |angle| over every joint of a pose: how much of the body it commits.
local function commitment(angles: { [string]: { number } }): number
	local total = 0
	for _, triple in pairs(angles) do
		for _, value in ipairs(triple) do
			total += math.abs(value)
		end
	end
	return total
end

describe("the joints", function()
	it("are named once and carried by a real motor on both rigs", function()
		expect(#PostureConfig.JointOrder).toBeGreaterThanOrEqual(3)
		local seen: { [string]: boolean } = {}
		for _, joint in ipairs(PostureConfig.JointOrder) do
			if seen[joint] then
				error(("joint %s is declared twice"):format(joint))
			end
			seen[joint] = true
		end
		for _, rig in ipairs(RIGS) do
			local motors = PostureConfig.Motors[rig]
			if motors == nil then
				error(("no motor map for rig %s"):format(rig))
			end
			for _, joint in ipairs(PostureConfig.JointOrder) do
				local name = motors[joint]
				if type(name) ~= "string" or name == "" then
					error(("rig %s has no motor for %s"):format(rig, joint))
				end
			end
			-- And nothing else: a motor named here for a joint no pose can reach is dead config.
			for joint in pairs(motors) do
				if not seen[joint] then
					error(("rig %s names a motor for %s, which is not a declared joint"):format(rig, joint))
				end
			end
		end
	end)

	it("are taken at different motors on the two rigs, because the two rigs are different", function()
		-- R6 has no waist and R15 spells its shoulders without a space. A map that happened to be
		-- identical for both would mean one of them was copied and never checked against a real rig.
		local same = 0
		for _, joint in ipairs(PostureConfig.JointOrder) do
			if PostureConfig.Motors.R6[joint] == PostureConfig.Motors.R15[joint] then
				same += 1
			end
		end
		expect(same).toBeLessThan(#PostureConfig.JointOrder)
	end)
end)

describe("the poses", function()
	it("name only declared joints, in three finite angles each", function()
		local joints = jointSet()
		local count = 0
		for id, def in pairs(PostureConfig.Poses) do
			count += 1
			for joint, triple in pairs(def.Angles) do
				if not joints[joint] then
					error(("pose %s poses %s, which is not a declared joint"):format(id, joint))
				end
				expect(#triple).toBe(3)
				for axis, value in ipairs(triple) do
					if value ~= value or math.abs(value) > 180 then
						error(("pose %s, %s, axis %d: %s is not an angle"):format(id, joint, axis, tostring(value)))
					end
				end
			end
		end
		-- Non-vacuous: this whole file passes trivially against an empty table.
		expect(count).toBeGreaterThanOrEqual(6)
	end)

	it("each move a body, and none of them is a rounding error", function()
		for id, def in pairs(PostureConfig.Poses) do
			-- 30 degrees summed across the whole body is about the smallest displacement that reads at
			-- gameplay distance. Below it the pose exists in the config and nowhere on screen.
			if commitment(def.Angles) < 30 then
				error(("pose %s barely moves: %.1f degrees over the whole body"):format(id, commitment(def.Angles)))
			end
		end
		expect(commitment(PostureConfig.Guard.Angles)).toBeGreaterThanOrEqual(30)
	end)

	it("have three phases, none shorter than the envelope can carry", function()
		local minimum = PostureConfig.Envelope.MinPhaseSeconds
		expect(minimum).toBeGreaterThan(0)
		for id, def in pairs(PostureConfig.Poses) do
			for _, phase in ipairs({ "AttackSeconds", "HoldSeconds", "ReleaseSeconds" }) do
				local value = (def :: any)[phase]
				if type(value) ~= "number" or value ~= value or value < 0 then
					error(("pose %s has no %s"):format(id, phase))
				end
			end
			if def.AttackSeconds < minimum or def.ReleaseSeconds < minimum then
				error(("pose %s has a phase the spring conversion cannot carry"):format(id))
			end
			-- A pose that leaves as fast as it arrives reads as a dropped frame, which is the reason
			-- the envelope has three phases instead of one duration.
			if def.ReleaseSeconds <= def.AttackSeconds then
				error(("pose %s leaves at least as fast as it arrives"):format(id))
			end
		end
	end)
end)

describe("the melee chain", function()
	it("has exactly one pose per hit the combo can throw", function()
		local chain = PostureConfig.MeleeChain
		expect(#chain).toBe(#CombatConfig.Melee.Damage)
		for index, id in ipairs(chain) do
			if PostureConfig.Poses[id] == nil then
				error(("melee hit %d names pose %s, which does not exist"):format(index, id))
			end
		end
	end)

	it("escalates, so the finisher does not look like the jab", function()
		local chain = PostureConfig.MeleeChain
		local first = PostureConfig.Poses[chain[1]]
		local last = PostureConfig.Poses[chain[#chain]]
		-- The last hit launches the opponent (CombatConfig.Melee.FinisherLift). A body that commits no
		-- more to it than to the first jab is the tell that the four poses were written as one.
		expect(commitment(last.Angles)).toBeGreaterThan(commitment(first.Angles) * 1.3)
		expect(last.AttackSeconds).toBeGreaterThan(first.AttackSeconds)
		expect(last.ReleaseSeconds).toBeGreaterThan(first.ReleaseSeconds)
	end)

	it("alternates arms, so the chain is a combination and not one arm four times", function()
		local chain = PostureConfig.MeleeChain
		local leadingRight: { boolean } = {}
		for _, id in ipairs(chain) do
			local angles = PostureConfig.Poses[id].Angles
			local right = angles.RightArm ~= nil and angles.RightArm[1] or 0
			local left = angles.LeftArm ~= nil and angles.LeftArm[1] or 0
			table.insert(leadingRight, right > left)
		end
		local alternations = 0
		for index = 2, #leadingRight do
			if leadingRight[index] ~= leadingRight[index - 1] then
				alternations += 1
			end
		end
		expect(alternations).toBeGreaterThanOrEqual(1)
	end)

	it("does not look like a cast", function()
		-- An opponent reads which one is coming off the body alone. If a swing and a glyph put the arms
		-- in the same place there is nothing to read, and the counter-play written into
		-- docs/GAME_DESIGN.md section 5 bis stops existing.
		local cast = PostureConfig.Poses.Cast
		for _, id in ipairs(PostureConfig.MeleeChain) do
			local melee = PostureConfig.Poses[id]
			local difference = 0
			for _, joint in ipairs(PostureConfig.JointOrder) do
				local a = cast.Angles[joint] or { 0, 0, 0 }
				local b = melee.Angles[joint] or { 0, 0, 0 }
				for axis = 1, 3 do
					difference += math.abs(a[axis] - b[axis])
				end
			end
			if difference < 40 then
				error(("the cast and %s put the body in the same place (%.1f degrees apart)"):format(id, difference))
			end
		end
	end)
end)

describe("the guard", function()
	it("is a state, not a pulse: it has no timer of its own anywhere", function()
		-- The guard used to drop after four seconds while the key was still held. Nothing in the posture
		-- may reintroduce that: it rises, it falls, and what ends it lives in CombatConfig.
		expect(PostureConfig.Guard.RiseSeconds).toBeGreaterThan(0)
		expect(PostureConfig.Guard.FallSeconds).toBeGreaterThan(0)
		expect((PostureConfig.Guard :: any).HoldSeconds).toBe(nil)
		expect((PostureConfig.Poses :: any).Guard).toBe(nil)
		expect((PostureConfig.Poses :: any).Block).toBe(nil)
	end)

	it("raises both arms, which is the one thing that says 'guard' without a word", function()
		local angles = PostureConfig.Guard.Angles
		expect(angles.RightArm).never.toBe(nil)
		expect(angles.LeftArm).never.toBe(nil)
		expect(angles.RightArm[1]).toBeGreaterThan(40)
		expect(angles.LeftArm[1]).toBeGreaterThan(40)
	end)
end)

describe("the controller", function()
	local source = fs.readFile(CONTROLLER)
	-- Comments describe poses by name; a mention inside one is not a call.
	local code = source:gsub("%-%-[^\n]*", "")

	it("plays every pose the config declares", function()
		for id in pairs(PostureConfig.Poses) do
			if not code:find('"' .. id .. '"', 1, true) then
				-- The melee poses are reached through MeleeChain rather than by name.
				local viaChain = false
				for _, chained in ipairs(PostureConfig.MeleeChain) do
					if chained == id then
						viaChain = true
						break
					end
				end
				if not viaChain then
					error(("pose %s is declared and never played: dead config"):format(id))
				end
			end
		end
		expect(code:find("MeleeChain", 1, true)).never.toBe(nil)
	end)

	it("animates with the spring this project already has, not with a tween", function()
		expect(code:find("TweenService", 1, true)).toBe(nil)
		expect(code:find("TweenInfo", 1, true)).toBe(nil)
		expect(code:find("Spring", 1, true)).never.toBe(nil)
	end)

	it("adds to the engine's own animation instead of replacing it", function()
		-- C0 is the additive channel; Transform is what an animation track writes. Writing Transform
		-- here would fight the idle and the walk every frame and win half of them.
		expect(code:find("%.C0%s*=")).never.toBe(nil)
		expect(code:find("%.Transform%s*=")).toBe(nil)
		expect(code:find("LoadAnimation", 1, true)).toBe(nil)
		expect(code:find("Animator", 1, true)).toBe(nil)
	end)

	it("puts every joint back exactly as it found it", function()
		-- Without this a character that stops being posed keeps the last offset for the rest of its
		-- life, and the engine's idle plays on top of a body that is already mid-swing.
		expect(code:find("Originals", 1, true)).never.toBe(nil)
		expect(code:find("local function restore", 1, true)).never.toBe(nil)
		expect(code:find("restore(entry)", 1, true)).never.toBe(nil)
	end)
end)
