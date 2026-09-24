--!strict
-- The animation clips: CC0 motion retargeted onto R15 (tools/animations/), played by Moves, with
-- Posture standing aside wherever a clip exists. Three layers can drift apart -- the committed files,
-- the config that names them, and the two controllers that must agree on who moves a body -- and every
-- drift shows up in a live game as a character that does nothing, or does two things at once.
local AnimationConfig = require("../src/shared/Config/AnimationConfig")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DIR = "assets/animations/"
local KEYED = "tools/animations/keyed/"
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

-- Every hand-keyed clip (tools/animations/keyed.py), decoded.
local function keyedClips(): { { [string]: any } }
	local out = {}
	for _, file in ipairs(fs.readDir(KEYED)) do
		if file:match("%.json$") then
			table.insert(out, serde.decode("json", fs.readFile(KEYED .. file)))
		end
	end
	return out
end

-- The parts a committed KeyframeSequence moves: every Pose with a weight, by name.
local function weightedParts(path: string): { [string]: boolean }
	local parts = {}
	local xml = fs.readFile(path)
	local pattern = '<Item class="Pose"[^>]*><Properties><string name="Name">(%w+)</string>'
		.. '.-<float name="Weight">([%d%.]+)</float>'
	for name, weight in xml:gmatch(pattern) do
		if tonumber(weight) ~= 0 then
			parts[name] = true
		end
	end
	return parts
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

	it("are the only files in the folder, and the generators name the same ones", function()
		-- An .rbxmx nobody reads is an upload nobody plays; a manifest entry with no clip is a
		-- conversion that is re-run for nothing. A clip comes from the retargeting manifest or from a
		-- hand-keyed clip file, never from both.
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
		for _, keyed in ipairs(keyedClips()) do
			if generated[DIR .. keyed.file] then
				error(("%s%s is produced twice"):format(DIR, keyed.file))
			end
			generated[DIR .. keyed.file] = true
		end
		for source in pairs(declared) do
			if not generated[source] then
				error(("%s is not produced by tools/animations/clips.json"):format(source))
			end
		end
		for source in pairs(generated) do
			if not declared[source] then
				error(("the generators produce %s, which no clip reads"):format(source))
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
		for _, action in ipairs({ "Melee", "Flinch", "GuardBreak", "Guard" }) do
			if not posture:find('clipFor("' .. action .. '"', 1, true) then
				error(("Posture poses %s without asking whether a clip already plays it"):format(action))
			end
		end
		-- A cast asks the glyph's question, the one Moves answers: the generic cast's alone would pose a
		-- Brand whose own clip is playing, or leave bare a glyph whose clip is not.
		expect(posture:find("castClip(glyphOf(params))", 1, true)).never.toBe(nil)
		expect(moves:find("castClip(glyphId)", 1, true)).never.toBe(nil)
		expect(moves:find("cast(glyphOf(params))", 1, true)).never.toBe(nil)
	end)
end)

describe("the hand-keyed casts", function()
	it("each belong to a glyph, which plays it, from the file its clip names", function()
		local count = 0
		for _, keyed in ipairs(keyedClips()) do
			count += 1
			local name = AnimationConfig.CastByGlyph[keyed.glyph]
			if name == nil then
				error(("%s is keyed for %s, which CastByGlyph does not play"):format(keyed.name, keyed.glyph))
			end
			expect(name).toBe(keyed.name)
			expect(AnimationConfig.Clips[name].Source).toBe(DIR .. keyed.file)
		end
		expect(count).toBeGreaterThanOrEqual(1)
		for glyphId, name in pairs(AnimationConfig.CastByGlyph) do
			if GlyphConfig.byId(glyphId) == nil then
				error(("CastByGlyph names %s, which is not a glyph"):format(glyphId))
			end
			if AnimationConfig.Clips[name] == nil then
				error(("CastByGlyph gives %s the clip %s, which does not exist"):format(glyphId, name))
			end
		end
	end)

	it("reach their release exactly when the glyph leaves the hand", function()
		-- The timing contract (D-114, D-117): the server decides when a glyph leaves; the drawn glyph
		-- leaves with it (its timeline's Travel starts there, and tests/Flight.spec.luau holds a held
		-- throw's Windup to it); the animation is keyed on that moment, never the other way round.
		for _, keyed in ipairs(keyedClips()) do
			local def = GlyphConfig.byId(keyed.glyph)
			local timeline = if def ~= nil then VfxTimelineConfig.Timelines[def.VfxId] else nil
			if def == nil or timeline == nil then
				error(("%s is keyed for %s, which has no timeline to release on"):format(keyed.name, keyed.glyph))
			end
			local leaves = 0
			for _, phase in ipairs(timeline.Phases) do
				if phase.Name == "Travel" then
					break
				end
				leaves += phase.Duration
			end
			expect(math.abs(keyed.release - leaves)).toBeLessThan(1e-9)
			local windup = def.Params.Windup
			if windup ~= nil then
				expect(keyed.release).toBe(windup)
			end
			local keyedRelease = false
			for _, key in ipairs(keyed.keys) do
				if key.t == keyed.release then
					keyedRelease = true
				end
			end
			if not keyedRelease then
				error(("%s has no key pose at its release, %.3f s"):format(keyed.name, keyed.release))
			end
		end
	end)

	it("move only the upper body, so the legs keep walking under them", function()
		local lower = { "HumanoidRootPart", "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" }
		table.move({ "RightUpperLeg", "RightLowerLeg", "RightFoot" }, 1, 3, #lower + 1, lower)
		for _, keyed in ipairs(keyedClips()) do
			local parts = weightedParts(DIR .. keyed.file)
			expect(parts.UpperTorso).toBe(true)
			for _, part in ipairs(lower) do
				if parts[part] then
					error(("%s moves %s: a cast thrown on the run would slide its feet"):format(keyed.name, part))
				end
			end
		end
	end)

	it("fall back to the generic cast until uploaded, and play their own once it is", function()
		local generic = AnimationConfig.Actions.Cast[1]
		for glyphId, name in pairs(AnimationConfig.CastByGlyph) do
			local clip = AnimationConfig.Clips[name]
			local saved = clip.Id
			clip.Id = ""
			local fallback, fallbackClip = AnimationConfig.castClip(glyphId)
			clip.Id = "rbxassetid://1"
			local own, ownClip = AnimationConfig.castClip(glyphId)
			clip.Id = saved
			expect(fallback).toBe(generic)
			expect(fallbackClip).toBe(AnimationConfig.clipFor("Cast"))
			expect(own).toBe(name)
			expect(ownClip).toBe(clip)
		end
		local unkeyed, unkeyedClip = AnimationConfig.castClip("Wash")
		expect(unkeyed).toBe(generic)
		expect(unkeyedClip).toBe(AnimationConfig.clipFor("Cast"))
		expect((AnimationConfig.castClip(nil))).toBe(generic)
	end)
end)
