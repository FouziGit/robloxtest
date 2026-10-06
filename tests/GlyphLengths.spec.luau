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
local Engine = require("./engine")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local EFFECTS = (fs.readFile("src/server/Effects/GlyphEffects.luau"):gsub("%-%-[^\n]*", ""))
local MEASURED = { "SizeFrom", "SpanFrom", "OffsetFrom", "TravelFrom" }
local CASTER, BYSTANDER = 41, 42

----------------------------------------------------------------
-- The packets, as GlyphEffects writes them
----------------------------------------------------------------

-- The index of the bracket that closes the one opened at `open`.
local function closing(source: string, open: number): number
	local depth = 0
	local index = open
	while index <= #source do
		local char = source:sub(index, index)
		if char == "{" or char == "(" then
			depth += 1
		elseif char == "}" or char == ")" then
			depth -= 1
			if depth == 0 then
				return index
			end
		elseif char == '"' then
			index = source:find('"', index + 1, true) or #source
		end
		index += 1
	end
	error("unbalanced brackets in GlyphEffects: this gate would read nothing")
end

-- The top-level, comma-separated items of a bracketed list, its brackets dropped.
local function items(bracketed: string): { string }
	local inner = bracketed:sub(2, -2)
	local out: { string } = {}
	local depth, last = 0, 1
	local function push(piece: string)
		local trimmed = piece:match("^%s*(.-)%s*$") or ""
		if trimmed ~= "" then
			table.insert(out, trimmed)
		end
	end
	for index = 1, #inner do
		local char = inner:sub(index, index)
		if char == "{" or char == "(" then
			depth += 1
		elseif char == "}" or char == ")" then
			depth -= 1
		elseif char == "," and depth == 0 then
			push(inner:sub(last, index - 1))
			last = index + 1
		end
	end
	push(inner:sub(last))
	return out
end

-- A table constructor's named fields, as source: { Key = expression }.
local function fields(constructor: string): { [string]: string }
	local out: { [string]: string } = {}
	for _, item in ipairs(items(constructor)) do
		local key, value = item:match("^([%a_][%w_]*)%s*=%s*(.+)$")
		if key ~= nil and value ~= nil then
			out[key] = value
		end
	end
	return out
end

-- A top-level function of GlyphEffects, by its header, down to its own closing `end`.
local function functionBody(header: string): string
	local start = EFFECTS:find(header, 1, true)
	if start == nil then
		error(header .. " is not in GlyphEffects: this gate would check nothing")
	end
	local finish = EFFECTS:find("\nend\n", start, true) or #EFFECTS
	return EFFECTS:sub(start, finish + 4)
end

-- The table argument of every ctx.Vfx.emit in `body`.
local function emitted(body: string): { { [string]: string } }
	local out: { { [string]: string } } = {}
	local from = 1
	while true do
		local call = body:find("ctx.Vfx.emit(", from, true)
		if call == nil then
			return out
		end
		local open = body:find("{", call, true) :: number
		local close = closing(body, open)
		table.insert(out, fields(body:sub(open, close)))
		from = close
	end
end

type Written = { Id: string, Params: { [string]: string }, Targets: boolean }

-- The local functions that emit on an effect's behalf (explode, charge, retract): their parameter names, and
-- their emits. An emit names its Id and Params either in place or through the helper's own parameters and
-- locals, which a call site resolves.
type Helper = { Args: { string }, Body: string }
local helpers: { [string]: Helper } = {}
for name, args in EFFECTS:gmatch("\nlocal function ([%a_][%w_]*)(%b())") do
	local body = functionBody("\nlocal function " .. name .. "(")
	if body:find("ctx.Vfx.emit(", 1, true) then
		local names: { string } = {}
		for _, arg in ipairs(items(args)) do
			table.insert(names, arg:match("^([%a_][%w_]*)") :: string)
		end
		helpers[name] = { Args = names, Body = body }
	end
end

local function written(def: any): { Written }
	local body = functionBody("function GlyphEffects." .. def.Effect .. "(")
	local out: { Written } = {}
	local function add(packet: { [string]: string }, params: { [string]: string })
		if params.Cancel == nil then
			table.insert(out, { Id = packet.Id, Params = params, Targets = packet.Targets ~= nil })
		end
	end
	for _, packet in ipairs(emitted(body)) do
		add(packet, if packet.Params ~= nil then fields(packet.Params) else {})
	end
	for name, helper in pairs(helpers) do
		for call in body:gmatch("[^%w_.:]" .. name .. "(%b())") do
			local args = items(call)
			local bound: { [string]: string } = {}
			for index, arg in ipairs(helper.Args) do
				bound[arg] = args[index]
			end
			for _, packet in ipairs(emitted(helper.Body)) do
				local id = bound[packet.Id] or packet.Id
				local params: { [string]: string } = {}
				local source = packet.Params or "{}"
				if source:sub(1, 1) ~= "{" then
					-- A table the helper builds first, then adds the call site's own numbers to (charge's extra).
					local start = helper.Body:find("local " .. source .. "[^=\n]*=%s*{")
					if start == nil then
						error(name .. " emits Params = " .. source .. ", which this gate cannot find")
					end
					local open = helper.Body:find("{", start, true) :: number
					source = helper.Body:sub(open, closing(helper.Body, open))
					for _, arg in ipairs(args) do
						if arg:sub(1, 1) == "{" then
							for key, value in pairs(fields(arg)) do
								params[key] = value
							end
						end
					end
				end
				for key, value in pairs(fields(source)) do
					params[key] = bound[value] or value
				end
				add({ Id = id, Targets = packet.Targets }, params)
			end
		end
	end
	return out
end

----------------------------------------------------------------
-- A client that sees them
----------------------------------------------------------------

local function body(name: string): any
	local model = Engine.instance("Model")
	model.Name = name
	local root = Engine.instance("Part", model)
	root.Name = "HumanoidRootPart"
	root.CFrame = roblox.CFrame.new(0, 3, 0)
	root.Position = roblox.Vector3.new(0, 3, 0)
	local hand = Engine.instance("Part", model)
	hand.Name = VfxConfig.Hand
	hand.Position = roblox.Vector3.new(1, 3, 0)
	return model
end

local casterBody = body("Caster")
local victimBody = body("Victim")
-- The Margin's slab, already replicated where the packet says: its handler paints the one it finds.
local slab = Engine.instance("Part")
slab.Name = WorldConfig.Glyphs.WallName
slab.Position = roblox.Vector3.new(0, 3, 0)
slab.CFrame = roblox.CFrame.new(0, 3, 0)
slab.Size = roblox.Vector3.new(12, 8, 1)
local casterPlayer = {
	UserId = CASTER,
	Name = "Caster",
	Character = casterBody,
	CharacterAdded = Engine.signal(),
	CharacterRemoving = Engine.signal(),
}
local world = Engine.world({
	Services = {
		Players = {
			LocalPlayer = casterPlayer,
			GetPlayers = function(_self: any): { any }
				return { casterPlayer }
			end,
			GetPlayerByUserId = function(_self: any, userId: number): any
				return if userId == CASTER then casterPlayer else nil
			end,
			PlayerAdded = Engine.signal(),
			PlayerRemoving = Engine.signal(),
		},
		CollectionService = {
			GetTagged = function(_self: any, tag: string): { any }
				return if tag == WorldConfig.Glyphs.CollisionTag then { slab } else {}
			end,
		},
		TweenService = {},
	},
})
local VfxLibrary = world.require("src/client/Controllers/VfxLibrary")

type Play = { Id: string, Context: { [string]: any } }

-- The value a packet carries for `key`, written `expression` in GlyphEffects: the glyph's own config when the
-- expression reads it, else what the server measures on the cast (a fuse, a reach, a shot number), stood in for.
local function valueOf(def: any, key: string, expression: string): any
	local chunk = luau.load("return " .. expression, {
		environment = { params = def.Params, ctx = { Def = def }, math = math },
	})
	local ok, value = pcall(chunk)
	if ok and value ~= nil then
		return value
	end
	if key == "Victim" then
		return victimBody
	elseif key == "Shot" then
		return 1
	end
	return 10
end

local function packetOf(def: any, source: Written): any
	local params: { [string]: any } = {}
	for key, expression in pairs(source.Params) do
		params[key] = valueOf(def, key, expression)
	end
	local origin = roblox.Vector3.new(0, 3, 0)
	local aim = roblox.Vector3.new(0, 0, -1)
	return {
		Id = if source.Id == "ctx.Def.VfxId" then def.VfxId else (source.Id:match('^"(.*)"$') or source.Id),
		Origin = origin,
		Direction = aim,
		Caster = CASTER,
		Targets = if source.Targets then { origin + aim * 6, origin + aim * 12 } else nil,
		Params = params,
	}
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
