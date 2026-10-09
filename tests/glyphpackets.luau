--!strict
-- The packets each glyph's GlyphEffects function emits, read from its source with the values its Params name,
-- and a client in the pretend engine (tests/engine.luau) to play them on: the caster's and a victim's bodies,
-- the Margin's slab, the players. Shared by tests/GlyphLengths.spec.luau (the lengths each layer measures) and
-- tests/GlyphVolumes.spec.luau (the volumes each glyph's bodies are drawn as).
local Easing = require("./easing")
local Engine = require("./engine")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local GlyphPackets = {}

-- The caster's UserId in every packet.
GlyphPackets.Caster = 41

local EFFECTS = (fs.readFile("src/server/Effects/GlyphEffects.luau"):gsub("%-%-[^\n]*", ""))

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

export type Written = { Id: string, Params: { [string]: string }, Targets: boolean }

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

function GlyphPackets.written(def: any): { Written }
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

-- The local functions of GlyphEffects that emit on an effect's behalf, by name: a reader that found none
-- would read every packet a helper emits as no packet.
GlyphPackets.helpers = helpers

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

export type Client = {
	World: any,
	Caster: any,
	CasterBody: any,
	VictimBody: any,
	Slab: any,
	Others: { [number]: any },
	VfxLibrary: any,
}

-- A fresh engine with the caster's client in it, its VfxLibrary loaded. TweenService eases as Roblox does
-- (tests/easing.luau), for a spec that runs the effects runtime itself.
function GlyphPackets.client(): Client
	local casterBody = body("Caster")
	local victimBody = body("Victim")
	-- The Margin's slab, already replicated where the packet says: its handler paints the one it finds.
	local slab = Engine.instance("Part")
	slab.Name = WorldConfig.Glyphs.WallName
	slab.Position = roblox.Vector3.new(0, 3, 0)
	slab.CFrame = roblox.CFrame.new(0, 3, 0)
	slab.Size = roblox.Vector3.new(12, 8, 1)
	-- Other players a spec adds (Client.Others, by UserId): their casts follow their own bodies.
	local others: { [number]: any } = {}
	local casterPlayer = {
		UserId = GlyphPackets.Caster,
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
					return if userId == GlyphPackets.Caster then casterPlayer else others[userId]
				end,
				PlayerAdded = Engine.signal(),
				PlayerRemoving = Engine.signal(),
			},
			CollectionService = {
				GetTagged = function(_self: any, tag: string): { any }
					return if tag == WorldConfig.Glyphs.CollisionTag then { slab } else {}
				end,
			},
			TweenService = {
				GetValue = function(_self: any, alpha: number, style: any, direction: any): number
					return Easing.value(style.Name, direction.Name, alpha)
				end,
			},
		},
	})
	return {
		World = world,
		Caster = casterPlayer,
		CasterBody = casterBody,
		VictimBody = victimBody,
		Slab = slab,
		Others = others,
		VfxLibrary = world.require("src/client/Controllers/VfxLibrary"),
	}
end

export type Runtime = { Client: Client, World: any, Pool: any, Timeline: any, Refused: { [string]: number } }

-- The effects runtime itself -- VfxTimeline, VfxVolumes, VfxPool -- started on a fresh client, on the quality
-- tier `tier`, over a floor at y = 0, with a camera, as the client bootstrap starts it; Refused counts the
-- borrows the pool refuses, by class.
function GlyphPackets.runtime(tier: string): Runtime
	local Client = GlyphPackets.client()
	local world = Client.World
	-- A floor under everything, as the ground probe finds it; a camera; one call that moves many parts.
	local floor = Engine.instance("Part", world.workspace)
	floor.Name = "Floor"
	world.workspace.Raycast = function(_self: any, from: any, toward: any, _params: any): any
		if from.Y >= 0 and from.Y + toward.Y <= 0 then
			return { Position = roblox.Vector3.new(from.X, 0, from.Z), Normal = roblox.Vector3.yAxis, Instance = floor }
		end
		return nil
	end
	world.workspace.BulkMoveTo = function(_self: any, parts: { any }, frames: { any }, _mode: any)
		for index, part in ipairs(parts) do
			part.CFrame = frames[index]
		end
	end
	world.workspace.CurrentCamera.CFrame =
		roblox.CFrame.lookAt(roblox.Vector3.new(0, 10, 25), roblox.Vector3.new(0, 3, 0))

	local Pool = world.require("src/client/Controllers/VfxPool")
	local Timeline = world.require("src/client/Controllers/VfxTimeline")
	-- Every borrow the pool refuses, by class: a ceiling a scene meets.
	local refused: { [string]: number } = {}
	local lender = setmetatable({
		acquire = function(className: string): any
			local instance = Pool.acquire(className)
			if instance == nil then
				refused[className] = (refused[className] or 0) + 1
			end
			return instance
		end,
	}, { __index = Pool })
	Pool.Init()
	Timeline.Init({
		VfxPool = lender,
		Feel = {
			motionAllowed = function(): boolean
				return true
			end,
			shakeAt = function() end,
		},
		QualityController = {
			def = function(): any
				return QualityConfig.Tiers[tier]
			end,
		},
		WorldLighting = { pulse = function() end },
		SoundController = {
			play = function(): any
				return nil
			end,
			duck = function() end,
		},
	})
	Pool.Start()
	Timeline.Start()
	return { Client = Client, World = world, Pool = Pool, Timeline = Timeline, Refused = refused }
end

-- The value a packet carries for `key`, written `expression` in GlyphEffects: the glyph's own config when the
-- expression reads it, else what the server measures on the cast (a fuse, a reach, a shot number), stood in for.
local function valueOf(def: any, key: string, expression: string, victim: any): any
	local chunk = luau.load("return " .. expression, {
		environment = { params = def.Params, ctx = { Def = def }, math = math },
	})
	local ok, value = pcall(chunk)
	if ok and value ~= nil then
		return value
	end
	if key == "Victim" then
		return victim
	elseif key == "Shot" then
		return 1
	end
	return 10
end

function GlyphPackets.packetOf(def: any, source: Written, victim: any): any
	local params: { [string]: any } = {}
	for key, expression in pairs(source.Params) do
		params[key] = valueOf(def, key, expression, victim)
	end
	local origin = roblox.Vector3.new(0, 3, 0)
	local aim = roblox.Vector3.new(0, 0, -1)
	return {
		Id = if source.Id == "ctx.Def.VfxId" then def.VfxId else (source.Id:match('^"(.*)"$') or source.Id),
		Origin = origin,
		Direction = aim,
		Caster = GlyphPackets.Caster,
		Targets = if source.Targets then { origin + aim * 6, origin + aim * 12 } else nil,
		Params = params,
	}
end

return GlyphPackets
