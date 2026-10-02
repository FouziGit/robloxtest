--!strict
-- The Forgers' brain (D-131), on the shipped BotConfig. A Forger is an opponent that must never cheat: it
-- announces every blow for at least its minimum tell and lands it on the aim it showed, one chain at a time
-- per player with a rest after, never reaches into the camp, never hovers out of every answer, and never
-- pays a kill it could not have answered. Each case below is one of those promises, broken on purpose once
-- to watch it fail.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BotBrain = require("../src/server/Pure/BotBrain")
local BotConfig = require("../src/shared/Config/BotConfig")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local RULES: BotBrain.Rules = {
	Targeting = BotConfig.Targeting,
	Reach = BotConfig.Reach,
	Stagger = BotConfig.Stagger,
	ArrivalGraceSeconds = BotConfig.ArrivalGraceSeconds,
	MinWindupSeconds = BotConfig.MinWindupSeconds,
	MinChainGapSeconds = BotConfig.MinChainGapSeconds,
	StunMaxSeconds = CombatConfig.Hit.StunMaxSeconds,
}
local SMUDGER = BotConfig.Tiers.Smudger
local QUILL = BotConfig.Tiers.Quill
local OVERWRITER = BotConfig.Tiers.Overwriter
local TARGETING = BotConfig.Targeting
local REACH = BotConfig.Reach
local STAGGER = BotConfig.Stagger
-- Every root stands at the same height unless a case lifts one.
local STANDING = BattlegroundConfig.StandingRootStuds
local TICK = 1 / GameConfig.Server.TickRate
local NOW = 100

local function target(userId: number, x: number, z: number, fields: { [string]: any }?): BotBrain.Target
	local made: BotBrain.Target = {
		UserId = userId,
		X = x,
		Y = STANDING,
		Z = z,
		Visible = true,
		InCamp = false,
		Down = false,
		ArrivedAt = 0,
		Load = 0,
	}
	for key, value in pairs(fields or {}) do
		(made :: any)[key] = value
	end
	return made
end

-- What the Forger in slot 1, standing at (x, z), perceives at `now`: its home and the page's centre at the
-- origin, every target free to swing at, and nobody else on them.
local function sees(
	now: number,
	x: number,
	z: number,
	targets: { BotBrain.Target },
	fields: { [string]: any }?
): BotBrain.Perception
	local free: { [number]: boolean } = {}
	for _, each in ipairs(targets) do
		free[each.UserId] = true
	end
	local made: BotBrain.Perception = {
		Now = now,
		Index = 1,
		X = x,
		Y = STANDING,
		Z = z,
		HomeX = 0,
		HomeZ = 0,
		CenterX = 0,
		CenterZ = 0,
		Targets = targets,
		RankFor = {},
		TokenFreeFor = free,
	}
	for key, value in pairs(fields or {}) do
		(made :: any)[key] = value
	end
	return made
end

local function chosen(tier: BotBrain.TierDef, memory: BotBrain.Memory, perception: BotBrain.Perception): number?
	local picked = BotBrain.selectTarget(tier, RULES, memory, perception)
	return if picked ~= nil then picked.UserId else nil
end

local function firstWindup(tier: BotBrain.TierDef): number
	return math.max(tier.Melee.WindupSeconds, BotConfig.MinWindupSeconds)
end

describe("BotBrain: whom a Forger chases", function()
	it("chases the nearest valid player, whatever order they are listed in, ties to the lower UserId", function()
		local near, far = target(1, 10, 0), target(2, 30, 0)
		for _, order in ipairs({ { near, far }, { far, near } }) do
			expect(chosen(SMUDGER, BotBrain.newMemory(), sees(NOW, 0, 0, order))).toBe(1)
		end
		local east, west = target(5, 10, 0), target(3, -10, 0)
		for _, order in ipairs({ { east, west }, { west, east } }) do
			expect(chosen(SMUDGER, BotBrain.newMemory(), sees(NOW, 0, 0, order))).toBe(3)
		end
	end)

	it("leaves a player alone through their arrival grace, and not a moment longer", function()
		local grace = BotConfig.ArrivalGraceSeconds
		local memory = BotBrain.newMemory()
		local fresh = target(1, 10, 0, { ArrivedAt = NOW - grace + TICK })
		expect(BotBrain.isValidTarget(RULES, memory, fresh, NOW)).toBe(false)
		expect(chosen(SMUDGER, memory, sees(NOW, 0, 0, { fresh }))).toBeNil()
		local settled = target(1, 10, 0, { ArrivedAt = NOW - grace })
		expect(BotBrain.isValidTarget(RULES, memory, settled, NOW)).toBe(true)
		expect(chosen(SMUDGER, memory, sees(NOW, 0, 0, { settled }))).toBe(1)
	end)

	it("never takes a player in the camp, not even the one who just hit it from there", function()
		local memory = BotBrain.newMemory()
		memory.Mode, memory.TargetUserId, memory.TargetSince, memory.LastSeenAt = "Engage", 7, NOW - 1, NOW
		BotBrain.noteHit(memory, 7, NOW - 0.2)
		local camper = target(7, 5, 0, { InCamp = true })
		expect(BotBrain.isValidTarget(RULES, memory, camper, NOW)).toBe(false)
		local decision = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 0, 0, { camper }))
		expect(decision.Start).toBeNil()
		expect(memory.TargetUserId).toBeNil()
	end)

	it("turns on whoever hit it, over a nearer player, for AggroMemorySeconds", function()
		local near, attacker = target(1, 10, 0), target(2, 25, 0)
		local memory = BotBrain.newMemory()
		BotBrain.noteHit(memory, 2, NOW - 1)
		local perception = sees(NOW, 0, 0, { near, attacker })
		expect(BotBrain.score(SMUDGER, RULES, memory, perception, attacker)).toBe(25 - TARGETING.RetaliationStuds)
		expect(chosen(SMUDGER, memory, perception)).toBe(2)
		local forgotten = BotBrain.newMemory()
		BotBrain.noteHit(forgotten, 2, NOW - SMUDGER.AggroMemorySeconds - TICK)
		expect(chosen(SMUDGER, forgotten, sees(NOW, 0, 0, { near, attacker }))).toBe(1)
	end)

	it("spreads out: each chaser costs LoadPenaltyStuds, and a full player is skipped while another is free", function()
		local crowded, alone = target(1, 10, 0, { Load = 1 }), target(2, 20, 0)
		expect(chosen(SMUDGER, BotBrain.newMemory(), sees(NOW, 0, 0, { crowded, alone }))).toBe(2)
		-- Nearer even with its load counted (5 + 3 * 15 = 50 < 55), and still skipped for the free one.
		local full = target(1, 5, 0, { Load = TARGETING.MaxAttackersPerTarget })
		local free = target(2, 55, 0)
		expect(chosen(SMUDGER, BotBrain.newMemory(), sees(NOW, 0, 0, { full, free }))).toBe(2)
		-- With nobody less crowded, the full one is still better than no one.
		expect(chosen(SMUDGER, BotBrain.newMemory(), sees(NOW, 0, 0, { full }))).toBe(1)
	end)

	it("keeps its target while committed, then only for one better by SwitchMarginStuds", function()
		local function holding(since: number): BotBrain.Memory
			local memory = BotBrain.newMemory()
			memory.Mode, memory.TargetUserId, memory.TargetSince, memory.LastSeenAt = "Engage", 1, since, NOW
			return memory
		end
		local current, closer = target(1, 30, 0), target(2, 5, 0)
		expect(chosen(SMUDGER, holding(NOW - 1), sees(NOW, 0, 0, { current, closer }))).toBe(1)
		local free = holding(NOW - SMUDGER.CommitSeconds)
		expect(chosen(SMUDGER, free, sees(NOW, 0, 0, { current, closer }))).toBe(2)
		expect(free.TargetSince).toBe(NOW)
		local margin = SMUDGER.SwitchMarginStuds
		local barely = target(2, 30 - margin + 0.5, 0)
		expect(chosen(SMUDGER, holding(NOW - 10), sees(NOW, 0, 0, { current, barely }))).toBe(1)
		local clearly = target(2, 30 - margin - 0.5, 0)
		expect(chosen(SMUDGER, holding(NOW - 10), sees(NOW, 0, 0, { current, clearly }))).toBe(2)
	end)

	it("gives up a player held out of reach overhead for UnreachableSeconds, and not one level with it", function()
		local memory = BotBrain.newMemory()
		local above = target(1, 30, 0, { Y = STANDING + REACH.UnreachableHeightStuds + 0.1 })
		local first = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 10, 0, { above }))
		expect(first.Goal ~= nil).toBe(true)
		expect(memory.TargetUserId).toBe(1)
		local later = NOW + REACH.UnreachableSeconds - TICK
		BotBrain.decide(SMUDGER, RULES, memory, sees(later, 10, 0, { above }))
		expect(memory.TargetUserId).toBe(1)
		local due = NOW + REACH.UnreachableSeconds
		local gaveUp = BotBrain.decide(SMUDGER, RULES, memory, sees(due, 10, 0, { above }))
		expect(memory.TargetUserId).toBeNil()
		expect(memory.IgnoreUntil[1]).toBe(due + REACH.IgnoreSeconds)
		expect(BotBrain.isValidTarget(RULES, memory, above, due)).toBe(false)
		expect(gaveUp.Goal).toEqual({ X = 0, Z = 0 })
		-- Exactly UnreachableHeightStuds above is within reach, however long it lasts.
		local level = target(1, 30, 0, { Y = STANDING + REACH.UnreachableHeightStuds })
		local patient = BotBrain.newMemory()
		for _, at in ipairs({ NOW, NOW + REACH.UnreachableSeconds, NOW + 10 * REACH.UnreachableSeconds }) do
			BotBrain.decide(SMUDGER, RULES, patient, sees(at, 10, 0, { level }))
			expect(patient.TargetUserId).toBe(1)
		end
		expect(patient.IgnoreUntil[1]).toBeNil()
	end)

	it("gives up a player sunk under it just as one held overhead, and not one level with it", function()
		local memory = BotBrain.newMemory()
		local sunk = target(1, 30, 0, { Y = STANDING - REACH.UnreachableHeightStuds - 0.1 })
		BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 10, 0, { sunk }))
		expect(memory.TargetUserId).toBe(1)
		BotBrain.decide(SMUDGER, RULES, memory, sees(NOW + REACH.UnreachableSeconds - TICK, 10, 0, { sunk }))
		expect(memory.TargetUserId).toBe(1)
		local due = NOW + REACH.UnreachableSeconds
		BotBrain.decide(SMUDGER, RULES, memory, sees(due, 10, 0, { sunk }))
		expect(memory.TargetUserId).toBeNil()
		expect(memory.IgnoreUntil[1]).toBe(due + REACH.IgnoreSeconds)
		-- Exactly UnreachableHeightStuds under it is within reach, however long it lasts.
		local low = target(1, 30, 0, { Y = STANDING - REACH.UnreachableHeightStuds })
		local patient = BotBrain.newMemory()
		for _, at in ipairs({ NOW, NOW + REACH.UnreachableSeconds, NOW + 10 * REACH.UnreachableSeconds }) do
			BotBrain.decide(SMUDGER, RULES, patient, sees(at, 10, 0, { low }))
			expect(patient.TargetUserId).toBe(1)
		end
		-- The same rule the roster times a member off the floor by (Roster.observe), either way.
		expect(BotBrain.outOfReach(RULES, REACH.UnreachableHeightStuds + 0.1)).toBe(true)
		expect(BotBrain.outOfReach(RULES, -REACH.UnreachableHeightStuds - 0.1)).toBe(true)
		expect(BotBrain.outOfReach(RULES, REACH.UnreachableHeightStuds)).toBe(false)
		expect(BotBrain.outOfReach(RULES, -REACH.UnreachableHeightStuds)).toBe(false)
	end)

	it("keeps every member in reach of every tier's swing, however deep the page lets them stand", function()
		-- The page lets a member go once their root is BoundsDepthStuds under the floor's top face: above that,
		-- every tier's swing, measured from its own standing root, still reaches them.
		local lowest = -BattlegroundConfig.BoundsDepthStuds
		for tierId, tier in pairs(BotConfig.Tiers) do
			local root = STANDING * tier.Scale
			if root - tier.Melee.HalfHeight > lowest then
				error(
					("a %s's swing stops %.2f studs over a member the page still holds"):format(
						tierId,
						root - tier.Melee.HalfHeight - lowest
					)
				)
			end
		end
	end)
end)

describe("BotBrain: how a Forger attacks", function()
	it("swings only once the player is inside its reach and nobody else is swinging at them", function()
		local reach = SMUDGER.Melee.Range - TARGETING.MeleeStartInsetStuds
		local outside =
			BotBrain.decide(SMUDGER, RULES, BotBrain.newMemory(), sees(NOW, 0, 0, { target(1, reach + 0.1, 0) }))
		expect(outside.Start).toBeNil()
		expect(outside.Goal ~= nil).toBe(true)
		local inside = BotBrain.decide(SMUDGER, RULES, BotBrain.newMemory(), sees(NOW, 0, 0, { target(1, reach, 0) }))
		expect(inside.Start ~= nil and inside.Start.Kind).toBe("Melee")
		local taken = sees(NOW, 0, 0, { target(1, 3, 0) }, { TokenFreeFor = {} })
		expect(BotBrain.decide(SMUDGER, RULES, BotBrain.newMemory(), taken).Start).toBeNil()
	end)

	it("lands exactly when its tell ends, not a tick earlier, on the aim the tell showed", function()
		local memory = BotBrain.newMemory()
		local start = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 0, 0, { target(1, 5, 0) })).Start
		assert(start ~= nil, "the Forger did not swing")
		local windup = firstWindup(SMUDGER)
		expect(start.ResolveAt).toBe(NOW + windup)
		expect(start.AimX).toBe(1)
		expect(start.AimZ).toBe(0)
		-- The player steps aside during the tell. A tick before its end nothing lands, and the Forger holds its
		-- aim, facing where it showed.
		local stepped = { target(1, 0, 5) }
		local early = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW + windup - TICK, 0, 0, stepped))
		expect(early.Resolve).toBeNil()
		expect(early.Stand).toBe(true)
		expect(early.FaceX).toBe(1)
		expect(early.FaceZ).toBe(0)
		local due = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW + windup, 0, 0, stepped))
		expect(due.Resolve).toEqual({ Kind = "Melee", Step = 1, AimX = 1, AimZ = 0, Final = false, TargetUserId = 1 })
		-- The next step is a new tell, aimed where the player is now.
		assert(due.Continue ~= nil, "the chain did not go on")
		expect(due.Continue.AimX).toBeCloseTo(0, 9)
		expect(due.Continue.AimZ).toBeCloseTo(1, 9)
	end)

	it("chains with ChainGapSeconds, then the finisher with FinisherGapSeconds, then recovers", function()
		local melee = OVERWRITER.Melee
		local memory = BotBrain.newMemory()
		local near = { target(1, 5, 0) }
		BotBrain.decide(OVERWRITER, RULES, memory, sees(NOW, 0, 0, near))
		local first = NOW + firstWindup(OVERWRITER)
		local one = BotBrain.decide(OVERWRITER, RULES, memory, sees(first, 0, 0, near))
		assert(one.Resolve ~= nil and one.Continue ~= nil, "step one did not resolve and go on")
		expect(one.Resolve.Final).toBe(false)
		expect(one.Continue.Step).toBe(2)
		expect(one.Continue.ResolveAt).toBe(first + math.max(melee.ChainGapSeconds, BotConfig.MinChainGapSeconds))
		local second = one.Continue.ResolveAt
		local two = BotBrain.decide(OVERWRITER, RULES, memory, sees(second, 0, 0, near))
		assert(two.Resolve ~= nil and two.Continue ~= nil, "step two did not resolve and go on")
		expect(two.Resolve.Final).toBe(false)
		expect(two.Continue.Step).toBe(#melee.Damage)
		expect(two.Continue.ResolveAt).toBe(second + math.max(melee.FinisherGapSeconds, BotConfig.MinChainGapSeconds))
		local third = two.Continue.ResolveAt
		local last = BotBrain.decide(OVERWRITER, RULES, memory, sees(third, 0, 0, near))
		assert(last.Resolve ~= nil, "the finisher did not resolve")
		expect(last.Resolve.Final).toBe(true)
		expect(last.Continue).toBeNil()
		-- A finisher's rest comes from its Resolve (Final), never from a second order that could shorten it.
		expect(last.Ended).toBeNil()
		expect(memory.RecoverUntil).toBe(third + melee.RecoverySeconds)
	end)

	it("starts nothing while it recovers, neither a swing nor a bolt", function()
		local memory = BotBrain.newMemory()
		memory.RecoverUntil = NOW + OVERWRITER.Melee.RecoverySeconds
		local near, far = { target(1, 5, 0) }, { target(1, 20, 0) }
		local tired = NOW + OVERWRITER.Melee.RecoverySeconds - TICK
		expect(BotBrain.decide(OVERWRITER, RULES, memory, sees(tired, 0, 0, near)).Start).toBeNil()
		expect(BotBrain.decide(OVERWRITER, RULES, memory, sees(tired, 0, 0, far)).Start).toBeNil()
		local rested = BotBrain.decide(OVERWRITER, RULES, memory, sees(memory.RecoverUntil, 0, 0, far)).Start
		expect(rested ~= nil and rested.Kind).toBe("Bolt")
	end)

	it("ends a chain the player stepped out of, says so, and recovers", function()
		local melee = SMUDGER.Melee
		local memory = BotBrain.newMemory()
		BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 0, 0, { target(1, 5, 0) }))
		local due = NOW + firstWindup(SMUDGER)
		local gone = BotBrain.decide(
			SMUDGER,
			RULES,
			memory,
			sees(due, 0, 0, { target(1, melee.Range + melee.ChainSlackStuds + 0.1, 0) })
		)
		assert(gone.Resolve ~= nil, "the step did not resolve")
		expect(gone.Continue).toBeNil()
		expect(gone.Ended).toEqual({ TargetUserId = 1 })
		expect(memory.RecoverUntil).toBe(due + melee.RecoverySeconds)
		-- At the edge of the slack the chain goes on.
		local held = BotBrain.newMemory()
		BotBrain.decide(SMUDGER, RULES, held, sees(NOW, 0, 0, { target(1, 5, 0) }))
		local edge = BotBrain.decide(
			SMUDGER,
			RULES,
			held,
			sees(due, 0, 0, { target(1, melee.Range + melee.ChainSlackStuds, 0) })
		)
		expect(edge.Continue ~= nil).toBe(true)
		expect(edge.Ended).toBeNil()
	end)

	it("never gives a tell shorter than the minimums, whatever a tier asks for", function()
		local hasty: BotBrain.TierDef = table.clone(SMUDGER)
		local melee = table.clone(SMUDGER.Melee)
		melee.WindupSeconds, melee.ChainGapSeconds, melee.FinisherGapSeconds = 0.1, 0.05, 0.05
		hasty.Melee = melee
		local memory = BotBrain.newMemory()
		local near = { target(1, 5, 0) }
		local start = BotBrain.decide(hasty, RULES, memory, sees(NOW, 0, 0, near)).Start
		expect(start ~= nil and start.ResolveAt).toBe(NOW + BotConfig.MinWindupSeconds)
		local first = NOW + BotConfig.MinWindupSeconds
		local one = BotBrain.decide(hasty, RULES, memory, sees(first, 0, 0, near)).Continue
		expect(one ~= nil and one.ResolveAt).toBe(first + BotConfig.MinChainGapSeconds)
		local caster: BotBrain.TierDef = table.clone(QUILL)
		local bolt = table.clone(QUILL.Bolt :: BotBrain.BoltDef)
		bolt.WindupSeconds = 0.1
		caster.Bolt = bolt
		local thrown = BotBrain.decide(caster, RULES, BotBrain.newMemory(), sees(NOW, 0, 0, { target(1, 20, 0) })).Start
		expect(thrown ~= nil and thrown.ResolveAt).toBe(NOW + BotConfig.MinWindupSeconds)
	end)

	it("throws a bolt only at a player it sees, inside [MinRange, Range], off cooldown", function()
		local bolt = QUILL.Bolt :: BotBrain.BoltDef
		local function throws(distance: number, fields: { [string]: any }?, memory: BotBrain.Memory?): boolean
			local start = BotBrain.decide(
				QUILL,
				RULES,
				memory or BotBrain.newMemory(),
				sees(NOW, 0, 0, { target(1, distance, 0, fields) })
			).Start
			return start ~= nil and start.Kind == "Bolt"
		end
		expect(throws(bolt.MinRange)).toBe(true)
		expect(throws(bolt.MinRange - 0.1)).toBe(false)
		expect(throws(bolt.Range)).toBe(true)
		expect(throws(bolt.Range + 0.1)).toBe(false)
		local watching = BotBrain.newMemory()
		watching.Mode, watching.TargetUserId, watching.TargetSince, watching.LastSeenAt = "Engage", 1, NOW - 1, NOW
		expect(throws(20, { Visible = false }, watching)).toBe(false)
		local memory = BotBrain.newMemory()
		expect(throws(20, nil, memory)).toBe(true)
		local windup = math.max(bolt.WindupSeconds, BotConfig.MinWindupSeconds)
		expect(memory.BoltReadyAt).toBe(NOW + windup + bolt.CooldownSeconds)
		local cooling = BotBrain.newMemory()
		cooling.BoltReadyAt = NOW + TICK
		expect(throws(20, nil, cooling)).toBe(false)
	end)
end)

describe("BotBrain: where a Forger walks", function()
	it("closes in first, flanks second, and circles out of reach past MaxEngagedPerTarget", function()
		local standoff = SMUDGER.KeepRange[2]
		local function goal(rank: number, distance: number): BotBrain.Decision
			local ranks = { [1] = rank }
			return BotBrain.decide(
				SMUDGER,
				RULES,
				BotBrain.newMemory(),
				sees(NOW, 0, 0, { target(1, distance, 0) }, { RankFor = ranks })
			)
		end
		expect(goal(1, 20).Goal).toEqual({ X = 20 - standoff, Z = 0 })
		expect(goal(2, 20).Goal).toEqual({ X = 20 - standoff, Z = -TARGETING.FlankStuds })
		local third = TARGETING.MaxEngagedPerTarget + 1
		-- At NOW the first slot strafes to its right: floor((100 + 0.7) / 2.5) is even.
		expect(goal(third, 20).Goal).toEqual({ X = 20 - TARGETING.CircleStuds, Z = -TARGETING.StrafeStuds })
		-- Within reach it still waits its place rather than swinging.
		local close = goal(third, 5)
		expect(close.Start).toBeNil()
		expect(close.Goal ~= nil).toBe(true)
		-- Its strafe turns every StrafeSeconds.
		local later = BotBrain.decide(
			SMUDGER,
			RULES,
			BotBrain.newMemory(),
			sees(NOW + TARGETING.StrafeSeconds, 0, 0, { target(1, 20, 0) }, { RankFor = { [1] = third } })
		)
		expect(later.Goal).toEqual({ X = 20 - TARGETING.CircleStuds, Z = TARGETING.StrafeStuds })
	end)

	it("keeps a caster inside its band, and closes on a player it cannot see", function()
		local band = QUILL.KeepRange
		local function goal(distance: number, visible: boolean): BotBrain.Point?
			local memory = BotBrain.newMemory()
			memory.Mode, memory.TargetUserId, memory.TargetSince, memory.LastSeenAt = "Engage", 1, NOW - 10, NOW - 1
			memory.BoltReadyAt = NOW + 60
			local seen = sees(NOW, 0, 0, { target(1, distance, 0, { Visible = visible }) })
			return BotBrain.decide(QUILL, RULES, memory, seen).Goal
		end
		expect(goal(10, true)).toEqual({ X = 10 - band[1], Z = 0 })
		expect(goal(40, true)).toEqual({ X = 40 - band[2], Z = 0 })
		expect(goal(25, true)).toEqual({ X = 0, Z = -TARGETING.StrafeStuds })
		expect(goal(25, false)).toEqual({ X = 25, Z = 0 })
	end)

	it("walks home with nobody to chase, and heals once when it gets there", function()
		local memory = BotBrain.newMemory()
		memory.Mode = "Engage"
		local home = { HomeX = 40, HomeZ = 0 }
		local away = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 60, 0, {}, home))
		expect(away.Goal).toEqual({ X = 40, Z = 0 })
		expect(away.Heal).toBe(false)
		expect(memory.Mode).toBe("Return")
		local arrived = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW + 1, 41, 0, {}, home))
		expect(arrived.Heal).toBe(true)
		expect(arrived.Goal).toBeNil()
		expect(arrived.FaceX).toBe(0)
		expect(arrived.FaceZ).toBe(0)
		expect(memory.Mode).toBe("Idle")
		expect(BotBrain.decide(SMUDGER, RULES, memory, sees(NOW + 2, 41, 0, {}, home)).Heal).toBe(false)
	end)

	it("waits over a player it knocked down, never walking home to heal in the middle of a fight", function()
		local memory = BotBrain.newMemory()
		memory.Mode, memory.TargetUserId, memory.TargetSince, memory.LastSeenAt = "Engage", 1, NOW - 1, NOW
		local down = target(1, 3, 0, { Down = true })
		-- At its own home, where a Forger with nobody to chase would heal.
		local waiting = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 0, 0, { down }))
		expect(BotBrain.isValidTarget(RULES, memory, down, NOW)).toBe(false)
		expect(waiting.Heal).toBe(false)
		expect(waiting.Start).toBeNil()
		expect(waiting.Goal).toBeNil()
		expect(waiting.FaceX).toBe(3)
		expect(memory.TargetUserId).toBe(1)
		local risen = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW + 1, 0, 0, { target(1, 3, 0) }))
		expect(risen.Start ~= nil).toBe(true)
	end)

	it("decides the same way twice from the same memory and the same perception", function()
		local function scene(): (BotBrain.Memory, { BotBrain.Target })
			local memory = BotBrain.newMemory()
			memory.Mode, memory.TargetUserId, memory.TargetSince, memory.LastSeenAt = "Engage", 2, NOW - 3, NOW
			BotBrain.noteHit(memory, 3, NOW - 1)
			return memory,
				{
					target(1, 21, 5),
					target(2, 13, -9, { Load = 1 }),
					target(3, 30, 30, { Visible = false }),
				}
		end
		for _, tier in ipairs({ SMUDGER, QUILL, OVERWRITER }) do
			local first, seenFirst = scene()
			local second, seenSecond = scene()
			for think = 0, 60 do
				local at = NOW + think * TICK * 2
				local ranks = { [1] = 1 + think % 4, [2] = 1 + think % 4, [3] = 1 }
				local a = BotBrain.decide(tier, RULES, first, sees(at, 4, -2, seenFirst, { RankFor = ranks }))
				local b =
					BotBrain.decide(tier, RULES, second, sees(at, 4, -2, seenSecond, { RankFor = table.clone(ranks) }))
				expect(a).toEqual(b)
				expect(first).toEqual(second)
			end
		end
	end)
end)

describe("BotBrain: staggers", function()
	it("stands the Forger still and hands back the wind-up it cancelled", function()
		local memory = BotBrain.newMemory()
		local start = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW, 0, 0, { target(1, 5, 0) })).Start
		local applied, cancelled = BotBrain.stagger(SMUDGER, RULES, memory, NOW + TICK, "Hit")
		expect(applied).toBe(true)
		expect(cancelled).toBe(start)
		expect(memory.Attack).toBeNil()
		expect(memory.StaggerUntil).toBe(NOW + TICK + STAGGER.HitSeconds)
		local during = BotBrain.decide(SMUDGER, RULES, memory, sees(NOW + 2 * TICK, 0, 0, { target(1, 5, 0) }))
		expect(during.Stand).toBe(true)
		expect(during.Start).toBeNil()
		expect(during.Resolve).toBeNil()
	end)

	it("takes MaxPerWindow hit staggers per window, then shrugs hits off for ImmuneSeconds", function()
		local memory = BotBrain.newMemory()
		for index = 1, STAGGER.MaxPerWindow do
			expect((BotBrain.stagger(SMUDGER, RULES, memory, NOW + (index - 1) * 0.5, "Hit"))).toBe(true)
		end
		local refusedAt = NOW + STAGGER.MaxPerWindow * 0.5
		expect((BotBrain.stagger(SMUDGER, RULES, memory, refusedAt, "Hit"))).toBe(false)
		expect(memory.ImmuneUntil).toBe(refusedAt + STAGGER.ImmuneSeconds)
		expect((BotBrain.stagger(SMUDGER, RULES, memory, refusedAt + STAGGER.ImmuneSeconds - TICK, "Hit"))).toBe(false)
		expect((BotBrain.stagger(SMUDGER, RULES, memory, refusedAt + STAGGER.ImmuneSeconds, "Hit"))).toBe(true)
		-- Hits older than the window no longer count toward it.
		local spaced = BotBrain.newMemory()
		for index = 1, STAGGER.MaxPerWindow do
			BotBrain.stagger(SMUDGER, RULES, spaced, NOW + (index - 1) * STAGGER.WindowSeconds, "Hit")
		end
		expect((BotBrain.stagger(SMUDGER, RULES, spaced, NOW + STAGGER.MaxPerWindow * STAGGER.WindowSeconds, "Hit"))).toBe(
			true
		)
	end)

	it("lets an Overwriter shrug off hits, never a knockback or a glyph's stun", function()
		local memory = BotBrain.newMemory()
		expect((BotBrain.stagger(OVERWRITER, RULES, memory, NOW, "Hit"))).toBe(false)
		expect(memory.StaggerUntil).toBe(0)
		expect((BotBrain.stagger(OVERWRITER, RULES, memory, NOW, "Knockback"))).toBe(true)
		expect(memory.StaggerUntil).toBe(NOW + STAGGER.KnockbackSeconds)
		expect((BotBrain.stagger(OVERWRITER, RULES, memory, NOW, "Control", 1))).toBe(true)
		expect(memory.StaggerUntil).toBe(NOW + 1)
	end)

	it("holds a glyph's stun no longer than StunMaxSeconds, and ignores one of no length", function()
		local memory = BotBrain.newMemory()
		expect((BotBrain.stagger(SMUDGER, RULES, memory, NOW, "Control", 0))).toBe(false)
		expect((BotBrain.stagger(SMUDGER, RULES, memory, NOW, "Control", 10))).toBe(true)
		expect(memory.StaggerUntil).toBe(NOW + CombatConfig.Hit.StunMaxSeconds)
	end)
end)

describe("BotBrain: slows", function()
	it("ends a root on its own time, whatever weaker slow came after it", function()
		local slows: { [string]: BotBrain.Slow } = {}
		BotBrain.addSlow(slows, "Binding", 0, 1.5, NOW)
		BotBrain.addSlow(slows, "Bleed", 0.4, 2.5, NOW + 0.5)
		expect(BotBrain.slowFactor(slows, NOW + 1.5 - TICK)).toBe(0)
		-- The root is over: the Bleed alone holds it, until its own end.
		expect(BotBrain.slowFactor(slows, NOW + 1.5)).toBe(0.4)
		expect(slows.Binding).toBeNil()
		expect(BotBrain.slowFactor(slows, NOW + 3 - TICK)).toBe(0.4)
		expect(BotBrain.slowFactor(slows, NOW + 3)).toBe(1)
		expect(next(slows)).toBeNil()
	end)

	it("keeps one glyph's slow as a player's: its strongest factor and its latest end", function()
		local slows: { [string]: BotBrain.Slow } = {}
		BotBrain.addSlow(slows, "Pounce", 0.7, 1.5, NOW)
		BotBrain.addSlow(slows, "Pounce", 0.8, 1.5, NOW + 1)
		expect(BotBrain.slowFactor(slows, NOW + 2.5 - TICK)).toBe(0.7)
		expect(BotBrain.slowFactor(slows, NOW + 2.5)).toBe(1)
		-- One that ran out starts over from the new one alone.
		BotBrain.addSlow(slows, "Pounce", 0.9, 1, NOW + 3)
		expect(BotBrain.slowFactor(slows, NOW + 3)).toBe(0.9)
	end)
end)

describe("BotBrain: one chain at a time per player", function()
	it("keeps a player whom one Forger is winding up a swing on to that Forger, then rests them", function()
		local swing: BotBrain.Attack =
			{ Kind = "Melee", Step = 1, ResolveAt = NOW + 0.5, AimX = 1, AimZ = 0, TargetUserId = 1 }
		local bolt: BotBrain.Attack =
			{ Kind = "Bolt", Step = 1, ResolveAt = NOW + 0.5, AimX = 1, AimZ = 0, TargetUserId = 2 }
		expect(BotBrain.tokenFree({ swing, bolt }, 0, 1, NOW)).toBe(false)
		-- A bolt holds no token: it is not a chain.
		expect(BotBrain.tokenFree({ swing, bolt }, 0, 2, NOW)).toBe(true)
		expect(BotBrain.tokenFree({}, NOW + TICK, 3, NOW)).toBe(false)
		expect(BotBrain.tokenFree({}, NOW, 3, NOW)).toBe(true)
	end)

	it(
		"rests a player TargetRestSeconds after a chain, and through a finisher's stun plus PostFinisherRestSeconds",
		function()
			local rest, after = TARGETING.TargetRestSeconds, TARGETING.PostFinisherRestSeconds
			expect(BotBrain.restAfter(RULES, NOW, false, 1)).toBe(NOW + rest)
			expect(BotBrain.restAfter(RULES, NOW, true, 0)).toBe(NOW + math.max(rest, after))
			expect(BotBrain.restAfter(RULES, NOW, true, 1)).toBe(NOW + math.max(rest, 1 + after))
			expect(BotBrain.restAfter(RULES, NOW, true, 50)).toBe(NOW + CombatConfig.Hit.StunMaxSeconds + after)
		end
	)

	it("rests everyone a finisher held after their own hold, bystanders as much as its target", function()
		local held = { [2] = 1.1, [5] = 0.3 }
		local rests = BotBrain.finisherRests(RULES, NOW, 2, held)
		expect(rests[2]).toBe(BotBrain.restAfter(RULES, NOW, true, 1.1))
		-- A bystander the same finisher knocked down rests out their own hold too.
		expect(rests[5]).toBe(BotBrain.restAfter(RULES, NOW, true, 0.3))
		expect(rests[5]).toBeGreaterThan(NOW + 0.3)
		-- Its target rests even when the finisher missed them, and nobody it never touched rests at all.
		local missed = BotBrain.finisherRests(RULES, NOW, 7, { [5] = 1.1 })
		expect(missed[7]).toBe(BotBrain.restAfter(RULES, NOW, true, 0))
		expect(missed[5]).toBe(BotBrain.restAfter(RULES, NOW, true, 1.1))
		expect(missed[2]).toBeNil()
	end)

	it("ranks the Forgers on a player by distance, ties to the lower slot", function()
		expect(BotBrain.engagedRank(3, 5, { { Index = 1, Distance = 8 }, { Index = 2, Distance = 4 } })).toBe(2)
		expect(BotBrain.engagedRank(3, 5, { { Index = 1, Distance = 5 } })).toBe(2)
		expect(BotBrain.engagedRank(1, 5, { { Index = 3, Distance = 5 } })).toBe(1)
	end)
end)

describe("BotBrain: geometry and timing", function()
	it("times a clip so its impact lands on the resolve, inside the speed bounds", function()
		local low, high = BotConfig.ClipSpeed.Min, BotConfig.ClipSpeed.Max
		local speed, delay = BotBrain.clipTiming(0.55, 0.4, low, high)
		expect(speed).toBeCloseTo(0.4 / 0.55, 9)
		expect(delay).toBeCloseTo(0, 9)
		-- Too slow a fit is held at the floor and started late, its impact still on the resolve.
		speed, delay = BotBrain.clipTiming(1, 0.2, low, high)
		expect(speed).toBe(low)
		expect(delay + 0.2 / speed).toBeCloseTo(1, 9)
		-- Too fast a fit is held at the ceiling and started at once.
		speed, delay = BotBrain.clipTiming(0.1, 0.9, low, high)
		expect(speed).toBe(high)
		expect(delay).toBe(0)
		speed, delay = BotBrain.clipTiming(0.6, 0, low, high)
		expect(speed).toBe(1)
		expect(delay).toBe(0)
	end)

	it("measures the melee box from the root along the aim, edges included", function()
		local melee = SMUDGER.Melee
		local inBox = BotBrain.inMeleeBox
		expect(inBox(melee.Range, 0, 0, 1, 0, melee)).toBe(true)
		expect(inBox(melee.Range + 0.1, 0, 0, 1, 0, melee)).toBe(false)
		expect(inBox(-0.1, 0, 0, 1, 0, melee)).toBe(false)
		expect(inBox(3, 0, melee.HalfWidth, 1, 0, melee)).toBe(true)
		expect(inBox(3, 0, -melee.HalfWidth - 0.1, 1, 0, melee)).toBe(false)
		expect(inBox(3, melee.HalfHeight, 0, 1, 0, melee)).toBe(true)
		expect(inBox(3, -melee.HalfHeight - 0.1, 0, 1, 0, melee)).toBe(false)
		-- Turned to face +Z, the box turns with it.
		expect(inBox(0, 0, melee.Range, 0, 1, melee)).toBe(true)
		expect(inBox(melee.Range, 0, 0, 0, 1, melee)).toBe(false)
	end)

	it("measures a point's distance to a bolt's segment, past either end too", function()
		expect(BotBrain.segmentDistance(0, 0, 10, 0, 5, 3)).toBeCloseTo(3, 9)
		expect(BotBrain.segmentDistance(0, 0, 10, 0, -3, 4)).toBeCloseTo(5, 9)
		expect(BotBrain.segmentDistance(0, 0, 10, 0, 13, 4)).toBeCloseTo(5, 9)
		expect(BotBrain.segmentDistance(2, 2, 2, 2, 5, 6)).toBeCloseTo(5, 9)
	end)

	it("spawns a Forger furthest from the nearest player, ties to the lower index", function()
		local spawns = { { X = 0, Z = 0 }, { X = 10, Z = 0 }, { X = -10, Z = 0 } }
		expect(BotBrain.pickSpawn(spawns, { { X = 0, Z = 0 } }, 1)).toBe(2)
		expect(BotBrain.pickSpawn(spawns, { { X = 8, Z = 0 } }, 1)).toBe(3)
		expect(BotBrain.pickSpawn(spawns, {}, 3)).toBe(3)
	end)
end)

describe("BotBrain: who a kill pays", function()
	it("pays nobody who fought from the camp, while ignored, or after UnreachableSeconds in the air", function()
		local creditable = BotBrain.creditable
		expect(creditable(false, 0, nil, NOW, RULES)).toBe(true)
		expect(creditable(true, 0, nil, NOW, RULES)).toBe(false)
		expect(creditable(false, NOW + TICK, nil, NOW, RULES)).toBe(false)
		expect(creditable(false, NOW, nil, NOW, RULES)).toBe(true)
		expect(creditable(false, 0, NOW - REACH.UnreachableSeconds + TICK, NOW, RULES)).toBe(true)
		expect(creditable(false, 0, NOW - REACH.UnreachableSeconds, NOW, RULES)).toBe(false)
	end)

	it("pays nothing for Forgers whittled from the camp and finished outside it", function()
		local maxHealth = QUILL.Health
		local share = BotConfig.Credit.AssistShare
		local ledger: { [number]: number } = {}
		local health = maxHealth
		-- One hit, as the service applies it: the points go, and whatever the camp gives back returns.
		local function hit(userId: number, amount: number, fromCamp: boolean)
			health -= amount
			health = math.min(health + BotBrain.creditHit(ledger, userId, amount, fromCamp), maxHealth)
		end
		-- Player 7 shoots it from the camp all the way down to its last point: none of it sticks or counts.
		for _ = 1, maxHealth - 1 do
			hit(7, 1, true)
			expect(health).toBe(maxHealth)
		end
		expect(next(ledger)).toBeNil()
		-- One step outside, their last hit is only a hit: the Forger still stands.
		hit(7, 12, false)
		expect(health).toBe(maxHealth - 12)
		expect(ledger[7]).toBe(12)
		-- Player 3 finishes it from outside: the camp's damage earned player 7 no share of the kill.
		hit(3, maxHealth - 12, false)
		expect(health).toBe(0)
		expect(12 < share * maxHealth).toBe(true)
		expect(BotBrain.creditedUsers(3, ledger, maxHealth, share)).toEqual({ 3 })
		-- Killing it takes its whole health dealt from outside, whoever deals it.
		local dealt = 0
		for _, points in pairs(ledger) do
			dealt += points
		end
		expect(dealt).toBe(maxHealth)
	end)

	it("pays the killer and everyone who removed AssistShare of its health, once each, in order", function()
		local health = SMUDGER.Health
		local share = BotConfig.Credit.AssistShare
		local ledger = { [5] = 60, [3] = share * health, [9] = share * health - 0.1, [1] = 50 }
		expect(BotBrain.creditedUsers(5, ledger, health, share)).toEqual({ 1, 3, 5 })
		expect(BotBrain.creditedUsers(9, {}, health, share)).toEqual({ 9 })
	end)
end)

describe("BotBrain: how full the page is", function()
	it("holds BaseCount for one active member, one more per other, never past MaxBots, nobody when idle", function()
		local base, extra, most = BotConfig.BaseCount, BotConfig.PerExtraMember, BotConfig.MaxBots
		expect(BotBrain.population(0, base, extra, most)).toBe(0)
		expect(BotBrain.population(1, base, extra, most)).toBe(base)
		expect(BotBrain.population(2, base, extra, most)).toBe(base + extra)
		expect(BotBrain.population(BattlegroundConfig.MaxMembers, base, extra, most)).toBe(most)
		-- Never fewer than one Forger for somebody there, whatever the base.
		expect(BotBrain.population(1, 0, extra, most)).toBe(1)
	end)

	it("refills a slot faster the more members are active, never under the minimum", function()
		local respawn = BotConfig.Respawn
		local function delay(active: number): number
			return BotBrain.respawnSeconds(active, respawn.BaseSeconds, respawn.StepSeconds, respawn.MinSeconds)
		end
		expect(delay(1)).toBe(respawn.BaseSeconds)
		expect(delay(2)).toBe(respawn.BaseSeconds - respawn.StepSeconds)
		expect(delay(BattlegroundConfig.MaxMembers)).toBe(
			math.max(
				respawn.MinSeconds,
				respawn.BaseSeconds - respawn.StepSeconds * (BattlegroundConfig.MaxMembers - 1)
			)
		)
		expect(delay(1000)).toBe(respawn.MinSeconds)
		-- An idle page counts as one member: the delay never grows past the base.
		expect(delay(0)).toBe(respawn.BaseSeconds)
	end)
end)
