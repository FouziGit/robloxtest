--!strict
-- A glyph's body survives a fight (D-281).
--
-- Reported from a play of the place: after a few minutes of casting, the Stipple showed only its trail and the
-- Caret no body at all. The pools were never the limit; the layer budget was (QualityConfig Layers). It retired
-- the oldest layer that was not a warning, a carrier or a riding body, and a Caret's strike-out or an Emboss's
-- relief is often the oldest thing on screen: in this fight, oldest-first cut 2.4 % of the body volumes short
-- on High, 12.9 % on Medium, 30.6 % on Low and 50.2 % on Performance, and every later link of a cut chain was
-- then never drawn. Bodies now go last, and whole: none on High or Medium, 1.2 % on Low, 16.8 % on Performance.
--
-- The fight: six casters on a circle of fifteen studs, facing its centre, each casting a glyph drawn from a
-- seeded generator every 1.2 to 1.8 s for a minute -- the packets its GlyphEffects function emits, a charge's
-- release its Windup after the press -- seen on one of the six screens, through the real runtime
-- (tests/glyphpackets.luau), on each quality tier.
local Engine = require("./engine")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local GlyphPackets = require("./glyphpackets")
local Harness = require("./harness")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local FRAME = 1 / 60
local SECONDS = 60
local CASTERS = 6
local SEED = 7
local CENTRE = roblox.Vector3.new(0, 3, 0)

-- The body volumes a play of `id` begins: each Mesh layer with no Chain, and each Chain's first link.
local beginsOf: { [string]: number } = {}
local function volumesOf(id: string): number
	local known = beginsOf[id]
	if known ~= nil then
		return known
	end
	local count = 0
	local timeline = VfxTimelineConfig.Timelines[id]
	local begun: { [string]: boolean } = {}
	for _, phase in ipairs(if timeline ~= nil then timeline.Phases else {}) do
		for _, layer in ipairs(phase.Layers) do
			local chain = layer.Chain
			if layer.Kind == "Mesh" and (chain == nil or not begun[chain]) then
				count += 1
			end
			if chain ~= nil then
				begun[chain] = true
			end
		end
	end
	beginsOf[id] = count
	return count
end

type Fight = {
	Volumes: number,
	Lost: number,
	PeakLayers: number,
	Refused: { [string]: number },
	Warnings: { string },
}

local function fight(tier: string): Fight
	local runtime = GlyphPackets.runtime(tier)
	local client, world, timeline = runtime.Client, runtime.World, runtime.Timeline
	local state = SEED
	local function draw(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
	local result: Fight = { Volumes = 0, Lost = 0, PeakLayers = 0, Refused = runtime.Refused, Warnings = {} }
	local bodies: { [number]: any } = {}
	local casters: { number } = {}
	local nextCast: { [number]: number } = {}
	for index = 1, CASTERS do
		local angle = (index - 1) / CASTERS * 2 * math.pi
		local at = roblox.Vector3.new(math.cos(angle) * 15, 3, math.sin(angle) * 15)
		local userId = if index == 1 then GlyphPackets.Caster else 100 + index
		local body = client.CasterBody
		if index > 1 then
			body = Engine.instance("Model")
			body.Name = "Caster" .. index
			local root = Engine.instance("Part", body)
			root.Name = "HumanoidRootPart"
			local hand = Engine.instance("Part", body)
			hand.Name = VfxConfig.Hand
			hand.Position = at + roblox.Vector3.new(1, 0, 0)
			client.Others[userId] = { UserId = userId, Character = body }
		end
		body:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.lookAt(at, CENTRE)
		bodies[userId] = body
		table.insert(casters, userId)
		nextCast[userId] = draw() * 1.5
	end
	local api = {
		Sound = { play = function() end, duck = function() end },
		PigmentColor = function(_pigment: string): any
			return roblox.Color3.new(0.5, 0.2, 0.1)
		end,
		LocalCharacter = function(): any
			return client.CasterBody
		end,
		Feel = { fovPunch = function() end, haptic = function() end, shake = function() end },
		Timeline = {
			play = function(id: string, context: any): (boolean, number?)
				result.Volumes += volumesOf(id)
				return timeline.play(id, context)
			end,
			land = timeline.land,
			cancel = timeline.cancel,
			grant = timeline.grant,
		},
		LocalUserId = GlyphPackets.Caster,
		CharacterOf = function(userId: number): any
			return bodies[userId]
		end,
	}
	type Queued = { At: number, Packet: any }
	local queue: { Queued } = {}
	local now = 0
	while now < SECONDS do
		for _, userId in ipairs(casters) do
			if now >= nextCast[userId] then
				local def = GlyphConfig.Glyphs[1 + math.floor(draw() * #GlyphConfig.Glyphs)]
				local origin = bodies[userId]:FindFirstChild("HumanoidRootPart").Position
				local aim = (CENTRE - origin).Unit
				local windup = (def.Params :: any).Windup or 0
				for index, source in ipairs(GlyphPackets.written(def)) do
					local packet = GlyphPackets.packetOf(def, source, client.VictimBody)
					packet.Origin = origin
					packet.Direction = aim
					packet.Caster = userId
					if packet.Targets ~= nil then
						packet.Targets = { origin + aim * 6, origin + aim * 12 }
					end
					table.insert(queue, { At = now + (index - 1) * windup, Packet = packet })
				end
				nextCast[userId] = now + 1.2 + draw() * 0.6
			end
		end
		local index = 1
		while index <= #queue do
			local queued = queue[index]
			if queued.At <= now then
				table.remove(queue, index)
				if queued.Packet.Id == "Margin" then
					-- The Margin's slab, raised by the server where its packet says.
					client.Slab.CFrame = roblox.CFrame.new(queued.Packet.Origin)
				end
				client.VfxLibrary[queued.Packet.Id](queued.Packet, {
					Add = function(_self: any, item: any): any
						return item
					end,
				}, api)
			else
				index += 1
			end
		end
		world:frames(1, FRAME)
		now += FRAME
		result.PeakLayers = math.max(result.PeakLayers, timeline.stats().Live)
	end
	result.Lost = timeline.stats().BodiesLost
	for _, line in ipairs(world.warnings) do
		if line:find("budget", 1, true) then
			table.insert(result.Warnings, line)
		end
	end
	return result
end

local fights: { [string]: Fight } = {}
local function fightOn(tier: string): Fight
	local known = fights[tier]
	if known == nil then
		known = fight(tier)
		fights[tier] = known
	end
	return known :: Fight
end

-- The share of a fight's body volumes each tier may cut short: none where the budget has room for the fight's
-- marks, sparks and lights to go first; on the two lowest, where six casters' bodies alone outgrow 36 and 24
-- layers, a share well under what oldest-first cut (30.6 % and 50.2 %).
local ALLOWED: { [string]: number } = { High = 0, Medium = 0, Low = 0.05, Performance = 0.25 }

describe("a fight of six casters, on every tier", function()
	it("cuts no body short where the budget has room, and few on the lowest tiers", function()
		local failures: { string } = {}
		for _, tier in ipairs(QualityConfig.Order) do
			local result = fightOn(tier)
			-- Non-vacuous: a minute of bodies, and the budget really met.
			expect(result.Volumes).toBeGreaterThan(1000)
			expect(result.PeakLayers).toBe(QualityConfig.Tiers[tier].Layers)
			local share = result.Lost / result.Volumes
			if share > ALLOWED[tier] then
				table.insert(
					failures,
					("%s cut %d of %d body volumes short (%.1f %%, at most %.0f %%)"):format(
						tier,
						result.Lost,
						result.Volumes,
						share * 100,
						ALLOWED[tier] * 100
					)
				)
			end
		end
		if #failures > 0 then
			error("\n" .. table.concat(failures, "\n"))
		end
	end)

	it("meets the layer budget, never a pool's ceiling", function()
		for _, tier in ipairs(QualityConfig.Order) do
			for className, count in pairs(fightOn(tier).Refused) do
				error(("%s: the %s pool refused %d borrows"):format(tier, className, count))
			end
		end
	end)

	it("names each glyph whose body it cuts short, once", function()
		local named: { [string]: number } = {}
		local said = 0
		for _, line in ipairs(fightOn("Performance").Warnings) do
			local id = line:match("a body of (%S+) was cut short")
			if id ~= nil then
				named[id] = (named[id] or 0) + 1
				said += 1
			end
		end
		expect(said).toBeGreaterThan(0)
		for id, count in pairs(named) do
			expect(VfxTimelineConfig.Timelines[id]).never.toBeNil()
			if count > 1 then
				error(("%s is named %d times"):format(id, count))
			end
		end
	end)
end)
