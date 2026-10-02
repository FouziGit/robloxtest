--!strict
-- The particles a screen keeps alive, against its tier's budget (E11-S4): every emitter asks before it
-- emits (VfxParticles, on Pure/ParticleBudget), and gets what fits. Three parts: the ledger's arithmetic, pure;
-- the scene each budget has to hold, played frame by frame as the renderers ask (scripts/effect-cost's scene),
-- with what is alive counted apart; and the renderers' own sources, where every emission has to be one the
-- budget granted -- an emitter without its brake fails here, at the source and in the scene.
local EffectCost = require("../scripts/effect-cost")
local Harness = require("./harness")
local ParticleBudget = require("../src/shared/Pure/ParticleBudget")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SETTINGS = QualityConfig.ParticleLedger
local PARTICLES = "src/client/Controllers/VfxParticles.luau"
local TIMELINE = "src/client/Controllers/VfxTimeline.luau"
local COSMETIC = "src/client/Controllers/CosmeticController.luau"
local LIBRARY = "src/client/Controllers/VfxLibrary.luau"

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

-- One top-level function of a file, flattened, or an error: a gate that found nothing would pass.
local function functionIn(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(header .. " is not in " .. path .. ": this gate would check nothing")
	end
	local finish = source:find("\nend\n", start, true)
	if finish == nil then
		error(header .. " has no end in " .. path)
	end
	return (source:sub(start, finish + 4):gsub("%s+", " "))
end

local function has(text: string, needle: string, what: string)
	if text:find(needle, 1, true) == nil then
		error(("%s: %s is missing"):format(what, needle))
	end
end

local function sources(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			sources(path, out)
		elseif entry:match("%.luau$") then
			table.insert(out, path)
		end
	end
end

-- Every emission in `source` (comments stripped, whitespace folded) that the budget did not grant: an Emit of
-- anything but a granted count -- a worn flow emits its granted particles one at a time, each at its place --
-- and a Rate that is neither nothing nor the rate the budget reserved.
local function unbraked(source: string): { string }
	local found: { string } = {}
	local flat = (strip(source):gsub("%s+", " "))
	for call in flat:gmatch("[%w_%.]+:Emit%(([^%)]*)%)") do
		if call ~= "granted" and call ~= "1" then
			table.insert(found, ":Emit(" .. call .. ")")
		end
	end
	-- A single particle is only ever emitted inside the loop over what grantWorn granted.
	local _, singles = flat:gsub(":Emit%(1%)", "")
	local _, loops = flat:gsub("for _ = 1, VfxParticles%.grantWorn%(", "")
	if singles > loops then
		table.insert(found, ":Emit(1) outside a granted loop")
	end
	for value in flat:gmatch("[%w_]+%.Rate = ([^%s]+)") do
		if value ~= "0" and value ~= "rate" then
			table.insert(found, ".Rate = " .. value)
		end
	end
	local _, rates = flat:gsub("[%w_]+%.Rate = rate%f[^%w_]", "")
	local _, reserved = flat:gsub("local rate = VfxParticles%.reserve%(", "")
	if rates > reserved then
		table.insert(found, ".Rate = rate without a reserve")
	end
	return found
end

describe("a particle ledger", function()
	it("counts a batch until the top of its life, rounded up to its step, then forgets it", function()
		local ledger = ParticleBudget.ledger(0.05)
		ParticleBudget.count(ledger, 1, 10, 0.32)
		expect(ledger.Live).toBe(10)
		-- 1.32 is rounded up to 1.35: alive until then, never a step early.
		ParticleBudget.sweep(ledger, 1.31)
		expect(ledger.Live).toBe(10)
		ParticleBudget.sweep(ledger, 1.349)
		expect(ledger.Live).toBe(10)
		ParticleBudget.sweep(ledger, 1.35)
		expect(ledger.Live).toBe(0)
		-- Batches dying in the same step share one entry, whatever their number.
		for frame = 0, 59 do
			ParticleBudget.count(ledger, 2 + frame / 600, 1, 0.5)
		end
		local entries = 0
		for _ in pairs(ledger.Deaths) do
			entries += 1
		end
		expect(ledger.Live).toBe(60)
		expect(entries).toBeLessThanOrEqual(3)
		-- Nothing, a negative count or a NaN is not counted.
		ParticleBudget.count(ledger, 3, 0, 1)
		ParticleBudget.count(ledger, 3, -4, 1)
		ParticleBudget.count(ledger, 3, 0 / 0, 1)
		expect(ledger.Live).toBe(60)
	end)

	it("is never under what is really alive", function()
		-- Batches of varied size and life at uneven times, against an exact count kept apart.
		local ledger = ParticleBudget.ledger(SETTINGS.Step)
		local exact: { { Count: number, Dies: number } } = {}
		local seed = 7
		local now = 0
		for _ = 1, 600 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			now += (seed % 37) / 1000
			local count = seed % 9
			local life = 0.05 + (seed % 170) / 100
			ParticleBudget.count(ledger, now, count, life)
			if count > 0 then
				table.insert(exact, { Count = count, Dies = now + life })
			end
			ParticleBudget.sweep(ledger, now)
			local alive = 0
			for _, batch in ipairs(exact) do
				if batch.Dies > now then
					alive += batch.Count
				end
			end
			if ledger.Live < alive then
				error(("at %.3f the ledger counts %d and %d are alive"):format(now, ledger.Live, alive))
			end
			-- And never more than one step of deaths over it.
			local late = 0
			for _, batch in ipairs(exact) do
				if batch.Dies > now - ledger.Step then
					late += batch.Count
				end
			end
			expect(ledger.Live).toBeLessThanOrEqual(late)
		end
	end)

	it("grants whole particles, never more than asked nor than the room left", function()
		expect(ParticleBudget.room(100, 30)).toBe(70)
		expect(ParticleBudget.room(100, 130)).toBe(0)
		expect(ParticleBudget.grant(12, 70)).toBe(12)
		expect(ParticleBudget.grant(12, 7.9)).toBe(7)
		expect(ParticleBudget.grant(3.6, 70)).toBe(3)
		expect(ParticleBudget.grant(12, 0)).toBe(0)
		expect(ParticleBudget.grant(-2, 70)).toBe(0)
		expect(ParticleBudget.grant(0 / 0, 70)).toBe(0)
		expect(ParticleBudget.grant(12, 0 / 0)).toBe(0)
	end)

	it("slows an engine's emitter to what its life keeps alive within the room", function()
		-- 40 a second for half a second each keeps 20 alive, and one more on the boundary of a life.
		expect(ParticleBudget.held(40, 0.5)).toBe(21)
		expect(ParticleBudget.held(0, 0.5)).toBe(0)
		expect(ParticleBudget.held(0 / 0, 0.5)).toBe(0)
		expect(ParticleBudget.rate(40, 0.5, 100)).toBe(40)
		-- Eleven of room holds ten a life and the one on its boundary: twenty a second.
		expect(ParticleBudget.rate(40, 0.5, 11)).toBe(20)
		expect(ParticleBudget.held(ParticleBudget.rate(40, 0.5, 11), 0.5)).toBe(11)
		expect(ParticleBudget.rate(40, 0.5, 0.9)).toBe(0)
		expect(ParticleBudget.rate(40, 0.5, 0)).toBe(0)
		expect(ParticleBudget.rate(0, 0.5, 100)).toBe(0)
		expect(ParticleBudget.rate(-5, 0.5, 100)).toBe(0)
		expect(ParticleBudget.rate(0 / 0, 0.5, 100)).toBe(0)
		-- Whatever the room, what the granted rate keeps alive fits it.
		for room = 1, 60 do
			for _, life in ipairs({ 0.12, 0.5, 0.73, 1.5 }) do
				expect(ParticleBudget.held(ParticleBudget.rate(90, life, room), life)).toBeLessThanOrEqual(room)
			end
		end
	end)

	it("keeps what bodies wear within their share, and within what the effects left", function()
		expect(SETTINGS.WornShare > 0 and SETTINGS.WornShare < 1).toBe(true)
		expect(SETTINGS.Step > 0 and SETTINGS.Step <= 0.1).toBe(true)
		expect(ParticleBudget.wornRoom(1000, 0.5, 100, 100)).toBe(400)
		expect(ParticleBudget.wornRoom(1000, 0.5, 900, 100)).toBe(100)
		expect(ParticleBudget.wornRoom(1000, 0.5, 500, 500)).toBe(0)
		expect(ParticleBudget.wornRoom(1000, 0.5, 1200, 0)).toBe(0)
	end)
end)

describe("the screen's particle budget", function()
	local scene = EffectCost.Scene

	it("holds six Scorches among six worn bodies at every tier, in a fight and out of it", function()
		expect(#scene.Plays).toBe(6)
		expect(scene.Bodies).toBe(6)
		for _, id in ipairs(scene.Plays) do
			expect(id).toBe("Scorch")
		end
		local saturated = 0
		local braked = 0
		for _, name in ipairs(QualityConfig.Order) do
			for _, fighting in ipairs({ true, false }) do
				local result =
					EffectCost.scene({ Plays = scene.Plays, Bodies = scene.Bodies, Tier = name, Fighting = fighting })
				expect(result.Budget).toBe(QualityConfig.Tiers[name].Particles)
				if result.Peak > result.Budget then
					error(
						("%s%s: %d particles alive at once for a budget of %d"):format(
							name,
							if fighting then " in a fight" else "",
							result.Peak,
							result.Budget
						)
					)
				end
				expect(result.Peak).toBeGreaterThan(0)
				local free = EffectCost.scene({
					Plays = scene.Plays,
					Bodies = scene.Bodies,
					Tier = name,
					Fighting = fighting,
					Budget = math.huge,
				})
				if free.Peak > result.Budget then
					saturated += 1
					-- Thinned, never emptied: the budget is spent to its last particle, not refused whole.
					expect(result.Peak).toBeGreaterThanOrEqual(result.Budget * 0.9)
				else
					-- Under its budget, the scene peaks where it is written. The ledger counts each batch to the top
					-- of its life and a flow the engine runs for all of it, never under what is alive: near its
					-- budget, a scene that still fits may lose a little, never more.
					expect(result.Peak).toBe(free.Peak)
					expect(result.Drawn).toBeGreaterThanOrEqual(result.Asked * 0.95)
				end
				if result.Drawn < result.Asked then
					braked += 1
				end
			end
		end
		-- The brake is exercised: at some tier the scene asks for more than its budget, and at more than one the
		-- budget takes something. Since a Driven flow owes only its tier's share (D-229), the lowest tiers ask for
		-- less than their budget in this scene.
		expect(saturated).toBeGreaterThanOrEqual(1)
		expect(braked).toBeGreaterThanOrEqual(2)
	end)

	it("draws the scene whole at the best tier", function()
		for _, fighting in ipairs({ true, false }) do
			local result =
				EffectCost.scene({ Plays = scene.Plays, Bodies = scene.Bodies, Tier = "High", Fighting = fighting })
			expect(result.Drawn).toBe(result.Asked)
		end
	end)

	it("draws the local player's own look whole in a crowd, and thins the others", function()
		-- The local player's own look asks only what is left of the budget, never the crowd's share
		-- (VfxParticles.grantWorn): a crowd of the heaviest looks thins everybody else's, never the one he put on, on
		-- his own screen. Held to the share like the crowd's, it was drawn at about half of itself among twenty-four.
		local thinned = 0
		for _, name in ipairs(QualityConfig.Order) do
			for _, fighting in ipairs({ true, false }) do
				local crowd = EffectCost.scene({ Plays = {}, Bodies = 24, Tier = name, Fighting = fighting })
				expect(crowd.Peak).toBeLessThanOrEqual(crowd.Budget)
				expect(crowd.LocalAsked).toBeGreaterThan(0)
				if crowd.LocalDrawn ~= crowd.LocalAsked then
					error(
						("%s%s: the local player's own look drew %d of %d particles in a crowd"):format(
							name,
							if fighting then " in a fight" else "",
							crowd.LocalDrawn,
							crowd.LocalAsked
						)
					)
				end
				if crowd.Drawn < crowd.Asked then
					thinned += 1
				end
			end
		end
		-- A crowd the worn share cannot hold whole: over one that fits, the local look is whole however it asks.
		expect(thinned).toBeGreaterThanOrEqual(2)
	end)

	it("fails when a single kind of emitter skips its brake", function()
		-- A burst, a driven flow and a worn look that emit without asking each push the scene past a budget. The
		-- scene's engine-run emitter (the Scorch's smoke) starts once its fire is out, so the engine's own brake is
		-- proven where one runs under a full screen: six Bleeds, whose pool steams from their first frame.
		local cases = {
			{ Kind = "Burst", Plays = scene.Plays },
			{ Kind = "Driven", Plays = scene.Plays },
			{ Kind = "Worn", Plays = scene.Plays },
			{
				Kind = "Rate",
				Plays = {
					"Scorch",
					"Scorch",
					"Scorch",
					"Scorch",
					"Scorch",
					"Scorch",
					"Bleed",
					"Bleed",
					"Bleed",
					"Bleed",
					"Bleed",
					"Bleed",
				},
			},
		}
		for _, case in ipairs(cases) do
			local broken = false
			for _, name in ipairs(QualityConfig.Order) do
				for _, fighting in ipairs({ true, false }) do
					local braked = EffectCost.scene({
						Plays = case.Plays,
						Bodies = scene.Bodies,
						Tier = name,
						Fighting = fighting,
					})
					expect(braked.Peak).toBeLessThanOrEqual(braked.Budget)
					local result = EffectCost.scene({
						Plays = case.Plays,
						Bodies = scene.Bodies,
						Tier = name,
						Fighting = fighting,
						Unbraked = case.Kind,
					})
					broken = broken or result.Peak > result.Budget
				end
			end
			if not broken then
				error(
					("a %s emitter without its brake never breaks a budget: this gate would catch nothing"):format(
						case.Kind
					)
				)
			end
		end
	end)
end)

describe("every emitter on the screen", function()
	it("emits only what the budget granted", function()
		-- The gate itself, on emitters without their brake: each is caught.
		expect(#unbraked("emitter:Emit(count)")).toBe(1)
		expect(#unbraked("emitter:Emit(math.max(1, math.floor(layer.Burst * density)))")).toBe(1)
		expect(#unbraked("emitter.Rate = layer.Rate * density")).toBe(1)
		expect(#unbraked("flow.Emitter:Emit(1)")).toBe(1)
		expect(#unbraked("emitter.Rate = rate")).toBe(1)
		expect(#unbraked("local granted = 3 emitter:Emit(granted) emitter.Rate = 0")).toBe(0)
		-- And every client and interface source passes it.
		local files: { string } = {}
		sources("src/client", files)
		sources("src/ui", files)
		local emitting = 0
		for _, path in ipairs(files) do
			local source = fs.readFile(path)
			local found = unbraked(source)
			if #found > 0 then
				error(("%s emits without asking the particle budget: %s"):format(path, table.concat(found, ", ")))
			end
			if strip(source):find(":Emit(", 1, true) ~= nil then
				emitting += 1
			end
		end
		-- The timeline runtime, what bodies wear and the guard break: a gate over no emitter would pass.
		expect(emitting).toBe(3)
	end)

	it("asks the budget of its tier, on the clock its particles age on", function()
		local emitter = functionIn(TIMELINE, "local function buildEmitter(")
		has(emitter, 'local clock: VfxParticles.Clock = if entry.Steady then "Steady" else "Held"', "buildEmitter")
		has(
			emitter,
			"local granted = VfxParticles.grant(clock, math.max(1, math.floor(layer.Burst * density)), life, tier.Particles) if granted > 0 then emitter:Emit(granted) end",
			"buildEmitter"
		)
		local step = functionIn(TIMELINE, "local function stepEmitter(")
		has(step, 'local clock: VfxParticles.Clock = if entry.Steady then "Steady" else "Held"', "stepEmitter")
		local worn = functionIn(COSMETIC, "local function emitFlow(")
		has(worn, "local tier: QualityConfig.TierDef = quality.def()", "emitFlow")
		has(worn, "for _ = 1, VfxParticles.grantWorn(count, flow.Life, tier.Particles, entry.IsLocal) do", "emitFlow")
		has(functionIn(COSMETIC, "local function buildEmission("), "Life = spec.Lifetime[2],", "buildEmission")
		has(
			functionIn(LIBRARY, "local function burst("),
			"local granted = api.Timeline.grant(math.min(count, MAX_PARTICLE_BURST), emitter.Lifetime.Max)",
			"burst"
		)
		has(
			functionIn(TIMELINE, "function VfxTimeline.grant("),
			'return VfxParticles.grant("Steady", wanted, lifetime, quality.def().Particles)',
			"VfxTimeline.grant"
		)
		-- The ledgers: each grant counts what it granted, on its own clock; worn looks within their share.
		has(
			functionIn(PARTICLES, "function VfxParticles.grant("),
			"local granted = ParticleBudget.grant(wanted, ParticleBudget.room(budget, alive())) local ledger, now = ledgerOf(clock) ParticleBudget.count(ledger, now, granted, lifetime) return granted",
			"VfxParticles.grant"
		)
		has(
			functionIn(PARTICLES, "function VfxParticles.reserve("),
			"local allowed = ParticleBudget.rate(rate, lifetime, ParticleBudget.room(budget, alive())) local ledger, now = ledgerOf(clock) ParticleBudget.count(ledger, now, ParticleBudget.held(allowed, lifetime), seconds + lifetime) return allowed",
			"VfxParticles.reserve"
		)
		-- The crowd's looks within their share; the local player's own within what is left, counted in that share
		-- (the scene asks the same way, and its crowd test holds what that is for).
		has(
			functionIn(PARTICLES, "function VfxParticles.grantWorn("),
			"function VfxParticles.grantWorn(wanted: number, lifetime: number, budget: number, own: boolean): number local live = alive() local room = if own then ParticleBudget.room(budget, live) else ParticleBudget.wornRoom(budget, SETTINGS.WornShare, live, worn.Live) local granted = ParticleBudget.grant(wanted, room) ParticleBudget.count(worn, os.clock(), granted, lifetime) return granted",
			"VfxParticles.grantWorn"
		)
		local clockOf = functionIn(PARTICLES, "local function ledgerOf(")
		has(
			clockOf,
			'if clock == "Held" then return held, VfxClock.now() end return steady, VfxClock.steady()',
			"ledgerOf"
		)
		local sweep = functionIn(PARTICLES, "local function alive(")
		has(sweep, "ParticleBudget.sweep(held, heldNow)", "alive")
		has(sweep, "ParticleBudget.sweep(steady, steadyNow)", "alive")
		-- What bodies wear ages in real time, never on the lab's clock (CosmeticController sets no TimeScale).
		has(
			sweep,
			"local realNow = os.clock() if realNow - wornSwept >= SETTINGS.Step then ParticleBudget.sweep(worn, realNow)",
			"alive"
		)
		has(sweep, "return held.Live + steady.Live + worn.Live", "alive")
	end)
end)
