--!strict
-- The animation clips: CC0 motion retargeted onto R15 (tools/animations/), played by Moves, with
-- Posture standing aside wherever a clip exists. Three layers can drift apart -- the committed files,
-- the config that names them, and the two controllers that must agree on who moves a body -- and every
-- drift shows up in a live game as a character that does nothing, or does two things at once.
local AnimationConfig = require("../src/shared/Config/AnimationConfig")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Harness = require("./harness")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DIR = "assets/animations/"
local PRIORITIES = { Idle = true, Movement = true, Action = true, Action2 = true, Action3 = true, Action4 = true }

-- The last keyframe time of a committed KeyframeSequence, and whether it is marked as looping.
local function readSequence(path: string): (number, boolean)
	local xml = fs.readFile(path)
	local last = 0
	for time in xml:gmatch('<float name="Time">([%d%.]+)</float>') do
		last = math.max(last, tonumber(time) :: number)
	end
	local loop = xml:find('<bool name="Loop">true</bool>', 1, true) ~= nil
	return last, loop
end

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

describe("the clips", function()
	it("each name a committed file whose length and loop flag they state truthfully", function()
		local count = 0
		for name, clip in pairs(AnimationConfig.Clips) do
			count += 1
			if not fs.isFile(clip.Source) then
				error(("clip %s names %s, which does not exist"):format(name, clip.Source))
			end
			local last, loop = readSequence(clip.Source)
			-- One frame of slack at 24 fps: the config states a length rounded to the hundredth.
			if math.abs(last - clip.Seconds) > 1 / 24 then
				error(("clip %s says %.2f s, its file ends at %.3f s"):format(name, clip.Seconds, last))
			end
			if loop ~= clip.Looped then
				error(
					("clip %s says Looped = %s, its file says %s"):format(name, tostring(clip.Looped), tostring(loop))
				)
			end
			expect(clip.Speed).toBeGreaterThan(0)
			expect(clip.Speed).toBeLessThanOrEqual(2)
			if clip.Impact < 0 or clip.Impact > clip.Seconds then
				error(("clip %s lands its blow at %.3f s, outside its %.2f s"):format(name, clip.Impact, clip.Seconds))
			end
			if not PRIORITIES[clip.Priority] then
				error(("clip %s has priority %s, which is not an AnimationPriority name"):format(name, clip.Priority))
			end
		end
		expect(count).toBeGreaterThanOrEqual(5)
	end)

	it("are the only files in the folder, and the generator's manifest names the same ones", function()
		-- An .rbxmx nobody reads is an upload nobody plays; a manifest entry with no clip is a
		-- conversion that is re-run for nothing.
		local declared: { [string]: boolean } = {}
		for _, clip in pairs(AnimationConfig.Clips) do
			declared[clip.Source] = true
		end
		for _, file in ipairs(fs.readDir(DIR)) do
			if file:match("%.rbxmx$") and not declared[DIR .. file] then
				error(("%s%s is committed and no clip reads it"):format(DIR, file))
			end
		end
		local manifest = serde.decode("json", fs.readFile("tools/animations/clips.json"))
		local generated: { [string]: boolean } = {}
		for _, entry in ipairs(manifest.clips) do
			generated[DIR .. entry.file] = true
		end
		for source in pairs(declared) do
			if not generated[source] then
				error(("%s is not produced by tools/animations/clips.json"):format(source))
			end
		end
		for source in pairs(generated) do
			if not declared[source] then
				error(("tools/animations/clips.json produces %s, which no clip reads"):format(source))
			end
		end
	end)

	it("loop only where the action is a held state", function()
		for name, clip in pairs(AnimationConfig.Clips) do
			local isGuard = AnimationConfig.Actions.Guard[1] == name
			expect(clip.Looped).toBe(isGuard)
		end
	end)
end)

describe("the actions", function()
	it("name clips that exist, and give the melee chain one clip per hit", function()
		for action, names in pairs(AnimationConfig.Actions) do
			for _, name in ipairs(names) do
				if AnimationConfig.Clips[name] == nil then
					error(("action %s names clip %s, which does not exist"):format(action, name))
				end
			end
		end
		expect(#AnimationConfig.Actions.Melee).toBe(#CombatConfig.Melee.Damage)
	end)

	it("escalate: every strike lands a blow, and the finisher commits longest", function()
		local chain = AnimationConfig.Actions.Melee
		for _, name in ipairs(chain) do
			expect(AnimationConfig.Clips[name].Impact).toBeGreaterThan(0)
		end
		local first = AnimationConfig.Clips[chain[1]]
		local last = AnimationConfig.Clips[chain[#chain]]
		expect(last.Seconds / last.Speed).toBeGreaterThan(first.Seconds / first.Speed)
	end)

	it("answer clipFor with an uploaded clip, and with nothing for what does not exist", function()
		for action, names in pairs(AnimationConfig.Actions) do
			for index, name in ipairs(names) do
				local clip = AnimationConfig.Clips[name]
				local found = AnimationConfig.clipFor(action, index)
				if clip.Id ~= "" then
					expect(found).toBe(clip)
				else
					expect(found).toBe(nil)
				end
			end
		end
		expect(AnimationConfig.clipFor("NoSuchAction")).toBe(nil)
		expect(AnimationConfig.clipFor("Melee", #AnimationConfig.Actions.Melee + 1)).toBe(nil)
	end)
end)

describe("the two animation systems", function()
	local moves = strip(fs.readFile("src/client/Controllers/Moves.luau"))
	local posture = strip(fs.readFile("src/client/Controllers/Posture.luau"))

	it("have Moves animate only the local character, from what it did or what was done to it", function()
		-- A client animating another player's character is seen by nobody but itself: only an animation
		-- a client plays on its OWN character replicates.
		expect(moves:find("player.UserId", 1, true)).never.toBe(nil)
		expect(moves:find("GetPlayerByUserId", 1, true)).toBe(nil)
		expect(moves:find("LoadAnimation", 1, true)).never.toBe(nil)
	end)

	it("start a strike just before its blow, because the damage is already on screen", function()
		expect(moves:find("ImpactLeadSeconds", 1, true)).never.toBe(nil)
		expect(moves:find("TimePosition", 1, true)).never.toBe(nil)
		expect(AnimationConfig.ImpactLeadSeconds).toBeGreaterThan(0)
		expect(AnimationConfig.ImpactLeadSeconds).toBeLessThan(0.15)
	end)

	it("hold the guard exactly as long as its attribute", function()
		expect(moves:find("GetAttributeChangedSignal", 1, true)).never.toBe(nil)
	end)

	it("never both move a body for the same action: Posture asks clipFor before every pose", function()
		for _, action in ipairs({ "Melee", "Cast", "Flinch", "GuardBreak", "Guard" }) do
			if not posture:find('clipFor("' .. action .. '"', 1, true) then
				error(("Posture poses %s without asking whether a clip already plays it"):format(action))
			end
		end
	end)
end)
