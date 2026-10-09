--!strict
-- Every glyph's body is drawn: each layer of every timeline a glyph's packets play gets the lengths it measures
-- itself against (SizeFrom, SpanFrom, OffsetFrom, TravelFrom), and the body it follows.
--
-- Found playing the place: the Serif's body never drew. Its layers measure themselves against Radius, its server
-- packet carried Count, Spacing, StartOffset, StepDelay and Pigment, and VfxLibrary.playGlyph passes Radius only
-- from Params.Radius -- so the runtime skipped every layer and said "measures a layer against a length the
-- renderer did not pass" once, in a log no gate reads.
--
-- The path is the real one, from the server's side to the runtime's: the packets each glyph's GlyphEffects
-- function emits (read from its source, with the values its Params name), run through the real VfxLibrary
-- handler in the pretend engine (tests/engine.luau), and every Timeline.play it makes checked against the
-- timeline's layers by the runtime's own rule (VfxTimeline's geometryScale: "Radius" reads Context.Radius, any
-- other measure Context.Reach, and a length that is absent, zero, negative or NaN is no length).
-- The packet reader and the client are tests/glyphpackets.luau's, shared with tests/GlyphVolumes.spec.luau.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local GlyphPackets = require("./glyphpackets")
local Harness = require("./harness")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MEASURED = { "SizeFrom", "SpanFrom", "OffsetFrom", "TravelFrom" }
local CASTER, BYSTANDER = GlyphPackets.Caster, 42

local Client = GlyphPackets.client()
local VfxLibrary = Client.VfxLibrary
local casterBody = Client.CasterBody
local written = GlyphPackets.written
local helpers = GlyphPackets.helpers

type Written = GlyphPackets.Written
type Play = { Id: string, Context: { [string]: any } }

local function packetOf(def: any, source: Written): any
	return GlyphPackets.packetOf(def, source, Client.VictimBody)
end

-- Every Timeline.play the handler makes for `packet`, on the caster's own screen and on a bystander's.
local function plays(packet: any): { Play }
	local out: { Play } = {}
	local handler = VfxLibrary[packet.Id]
	if handler == nil then
		error("VfxLibrary has no handler for " .. packet.Id)
	end
	for _, viewer in ipairs({ CASTER, BYSTANDER }) do
		local count = 0
		local api = {
			Sound = { play = function() end, duck = function() end },
			PigmentColor = function(_pigment: string): any
				return roblox.Color3.new(0.5, 0.2, 0.1)
			end,
			LocalCharacter = function(): any
				return if viewer == CASTER then casterBody else nil
			end,
			Feel = { fovPunch = function() end, haptic = function() end, shake = function() end },
			Timeline = {
				play = function(id: string, context: { [string]: any }): (any, number)
					table.insert(out, { Id = id, Context = context })
					count += 1
					return nil, count
				end,
				land = function() end,
				cancel = function() end,
				grant = function() end,
			},
			LocalUserId = viewer,
			CharacterOf = function(userId: number): any
				return if userId == CASTER then casterBody else nil
			end,
		}
		handler(packet, {
			Add = function(_self: any, item: any): any
				return item
			end,
		}, api)
	end
	return out
end

-- What is wrong with `play`: each layer naming a length its context did not get, and each layer following a
-- body it was not given (the caster always has one here).
local function holes(play: Play): { string }
	local timeline = VfxTimelineConfig.Timelines[play.Id]
	if timeline == nil then
		return { ("plays timeline %s, which VfxTimelineConfig does not have"):format(play.Id) }
	end
	local out: { string } = {}
	local function note(line: string)
		table.insert(out, line)
	end
	for _, phase in ipairs(timeline.Phases) do
		for index, layer in ipairs(phase.Layers) do
			local where = ("%s.%s[%d] (%s)"):format(play.Id, phase.Name, index, layer.Kind)
			for _, field in ipairs(MEASURED) do
				local name = (layer :: any)[field]
				if name ~= nil then
					local studs = if name == "Radius" then play.Context.Radius else play.Context.Reach
					if type(studs) ~= "number" or studs ~= studs or studs <= 0 then
						note(("%s %s = %s, and the play passed no %s"):format(where, field, name, name))
					end
				end
			end
			if layer.Follow == true and play.Context.Follow == nil then
				note(where .. " follows the caster, and the play passed no body")
			end
		end
	end
	return out
end

describe("a glyph's packets", function()
	it("are read from GlyphEffects, at least one per glyph with the glyph's own id", function()
		-- Non-vacuous: a parser that found nothing would pass every check below.
		expect(helpers.explode).never.toBeNil()
		expect(helpers.charge).never.toBeNil()
		for _, def in ipairs(GlyphConfig.Glyphs) do
			local own = 0
			for _, packet in ipairs(written(def)) do
				if packetOf(def, packet).Id == def.VfxId then
					own += 1
				end
			end
			if own == 0 then
				error(def.Id .. " emits no packet under its VfxId that this gate can read")
			end
		end
	end)

	it("give every layer of every timeline they play the lengths it measures, and the body it follows", function()
		local failures: { string } = {}
		local listed: { [string]: boolean } = {}
		local played = 0
		for _, def in ipairs(GlyphConfig.Glyphs) do
			for _, packet in ipairs(written(def)) do
				for _, play in ipairs(plays(packetOf(def, packet))) do
					played += 1
					for _, hole in ipairs(holes(play)) do
						local line = ("%s: %s"):format(def.Id, hole)
						if not listed[line] then
							listed[line] = true
							table.insert(failures, line)
						end
					end
				end
			end
		end
		-- Every glyph plays its own timeline, on both screens: the handlers really ran.
		expect(played).toBeGreaterThanOrEqual(2 * #GlyphConfig.Glyphs)
		if #failures > 0 then
			table.sort(failures)
			error("\n" .. table.concat(failures, "\n"))
		end
	end)
end)
