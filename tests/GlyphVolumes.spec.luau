--!strict
-- Every body a glyph's timelines draw is built, on the screen of the player who cast it, by the runtime itself.
--
-- Reported from a play of the place: the Stipple and the Caret drew no volume. Their timelines were right, and
-- no gate ran what draws them: tests/GlyphLengths.spec.luau stops at Timeline.play, tests/Volumes.spec.luau reads
-- the timelines and the runtime's lines. This gate runs the whole client path in the pretend engine
-- (tests/engine.luau): the packets each glyph's GlyphEffects function emits (tests/glyphpackets.luau), through
-- its VfxLibrary handler, into the real VfxTimeline, VfxVolumes and VfxPool, frame by frame on the engine's
-- clock, on the High tier, over a floor; and it looks at what is in the Workspace each frame -- the parts that
-- carry a SpecialMesh, as Roblox would draw them.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local GlyphPackets = require("./glyphpackets")
local Harness = require("./harness")
local MeshConfig = require("../src/shared/Config/MeshConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local FRAME = 1 / 60
-- Long enough for the longest glyph to have drawn and released everything (the Margin's wall stands five).
local LONGEST_SECONDS = 8

local Runtime = GlyphPackets.runtime("High")
local Client = Runtime.Client
local world = Runtime.World
local Timeline = Runtime.Timeline

-- Which mesh a SpecialMesh draws, by its id; and the Role each mesh is drawn in.
local keyOf: { [string]: string } = {}
for key, mesh in pairs(MeshConfig.Meshes) do
	if mesh.Id ~= "" then
		keyOf[mesh.Id] = key
	end
end
local roleOf: { [string]: string } = {}
for _, timeline in pairs(VfxTimelineConfig.Timelines) do
	for _, phase in ipairs(timeline.Phases) do
		for _, layer in ipairs(phase.Layers) do
			if layer.Kind == "Mesh" then
				roleOf[layer.Mesh :: string] = layer.Role or "Pigment"
			end
		end
	end
end

type Seen = { Key: string, Part: any }

-- The volumes on screen now: parts in the Workspace that carry a SpecialMesh.
local function onScreen(): { Seen }
	local out: { Seen } = {}
	for _, part in ipairs(world.workspace:GetChildren()) do
		local special = part:FindFirstChildOfClass("SpecialMesh")
		if special ~= nil then
			table.insert(out, { Key = keyOf[special.MeshId] or tostring(special.MeshId), Part = part })
		end
	end
	return out
end

type Run = {
	Played: { [string]: boolean },
	Built: { [string]: boolean },
	Drawn: { [string]: boolean },
	Covered: { string },
}

-- Plays every packet of `def` on the caster's screen, each to its end, and notes what was on screen.
local function run(def: any): Run
	local result: Run = { Played = {}, Built = {}, Drawn = {}, Covered = {} }
	for _, source in ipairs(GlyphPackets.written(def)) do
		local packet = GlyphPackets.packetOf(def, source, Client.VictimBody)
		local api = {
			Sound = { play = function() end, duck = function() end },
			PigmentColor = function(_pigment: string): any
				return roblox.Color3.new(0.5, 0.2, 0.1)
			end,
			LocalCharacter = function(): any
				return Client.CasterBody
			end,
			Feel = { fovPunch = function() end, haptic = function() end, shake = function() end },
			Timeline = {
				play = function(id: string, context: any): (boolean, number?)
					result.Played[id] = true
					return Timeline.play(id, context)
				end,
				land = Timeline.land,
				cancel = Timeline.cancel,
				grant = Timeline.grant,
			},
			LocalUserId = GlyphPackets.Caster,
			CharacterOf = function(userId: number): any
				return if userId == GlyphPackets.Caster then Client.CasterBody else nil
			end,
		}
		Client.VfxLibrary[packet.Id](packet, {
			Add = function(_self: any, item: any): any
				return item
			end,
		}, api)
		local frames = 0
		repeat
			world:frames(1, FRAME)
			frames += 1
			local seen = onScreen()
			for _, volume in ipairs(seen) do
				result.Built[volume.Key] = true
				if volume.Part.Transparency < 0.98 then
					result.Drawn[volume.Key] = true
				end
				-- An ink contour drawn at its body's centre while no body of its family there is opaque (D-280).
				-- Another play's body may share the centre -- a Colophon link starts where the bolt struck --, and
				-- an opaque one is what the contour is then drawn around.
				if roleOf[volume.Key] == "Ink" and volume.Part.Transparency < 0.98 then
					local family = volume.Key:gsub("Ink$", "")
					local under: Seen? = nil
					local opaque = false
					for _, other in ipairs(seen) do
						if
							roleOf[other.Key] == "Pigment"
							and other.Key:sub(1, #family) == family
							and (other.Part.Position - volume.Part.Position).Magnitude < 1e-3
						then
							under = other
							opaque = opaque or other.Part.Transparency <= 0.02
						end
					end
					if under ~= nil and not opaque then
						table.insert(
							result.Covered,
							("%s drawn at %.2f over %s at %.2f"):format(
								volume.Key,
								volume.Part.Transparency,
								under.Key,
								under.Part.Transparency
							)
						)
					end
				end
			end
			local stats = Timeline.stats()
		until (stats.Pending == 0 and stats.Live == 0) or frames * FRAME >= LONGEST_SECONDS
	end
	return result
end

local runs: { [string]: Run } = {}
local function runOf(def: any): Run
	local known = runs[def.Id]
	if known == nil then
		known = run(def)
		runs[def.Id] = known
	end
	return known :: Run
end

describe("a glyph's bodies, drawn by the runtime", function()
	it("are built for every volume its timelines draw, and every pigment is seen", function()
		local failures: { string } = {}
		local built = 0
		for _, def in ipairs(GlyphConfig.Glyphs) do
			local result = runOf(def)
			local missing: { string } = {}
			local unseen: { string } = {}
			for id in pairs(result.Played) do
				local timeline = VfxTimelineConfig.Timelines[id]
				for _, phase in ipairs(if timeline ~= nil then timeline.Phases else {}) do
					for _, layer in ipairs(phase.Layers) do
						local key = layer.Mesh
						if layer.Kind == "Mesh" and key ~= nil then
							if not result.Built[key] then
								if not table.find(missing, key) then
									table.insert(missing, key)
								end
							elseif (layer.Role or "Pigment") == "Pigment" and not result.Drawn[key] then
								if not table.find(unseen, key) then
									table.insert(unseen, key)
								end
							end
						end
					end
				end
			end
			for _ in pairs(result.Built) do
				built += 1
			end
			table.sort(missing)
			table.sort(unseen)
			if #missing > 0 then
				table.insert(failures, ("%s builds no %s"):format(def.Id, table.concat(missing, ", ")))
			end
			if #unseen > 0 then
				table.insert(failures, ("%s never shows %s"):format(def.Id, table.concat(unseen, ", ")))
			end
		end
		if #failures > 0 then
			error("\n" .. table.concat(failures, "\n"))
		end
		-- Non-vacuous: the runtime really drew, a body and more for every glyph.
		expect(built).toBeGreaterThanOrEqual(3 * #GlyphConfig.Glyphs)
	end)

	it("never draw an ink contour over a body that is not opaque", function()
		local failures: { string } = {}
		for _, def in ipairs(GlyphConfig.Glyphs) do
			local covered = runOf(def).Covered
			if #covered > 0 then
				table.insert(failures, ("%s: %s (%d frames)"):format(def.Id, covered[1], #covered))
			end
		end
		if #failures > 0 then
			error("\n" .. table.concat(failures, "\n"))
		end
	end)
end)
