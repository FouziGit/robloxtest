--!strict
-- Practice against the Erasure and joining a fight in progress (D-132), held to the promises no Lune test can
-- run: WorldBossService needs an engine, so its sources are read. A practice shares the event's one encounter
-- slot, and each case here is one way it could otherwise take the event away from a server -- freeze ranked,
-- move the schedule, borrow the PvP rule, pull players out of where they went -- or pay what the event pays.
-- The rules themselves (verdicts, growth, grace, penalty, caps) are BossPractice's and DailyCap's, and are run
-- in their own specs.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DIR = "src/server/Services/WorldBossService/"
local MODULES = { "init", "Context", "Encounter", "Audience", "Admission", "Policy", "Rewards" }
local MODE = "src/server/GameModes/WorldBossMode.luau"
local GLYPHS = "src/server/Services/GlyphService.luau"

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

-- Every module of the folder, comments stripped, and the folder must hold exactly these: a new module is a new
-- place for a teleport, a policy or a payout to hide, and it has to be named here to be read.
local function folder(): { [string]: string }
	local found: { [string]: string } = {}
	for _, entry in ipairs(fs.readDir(DIR)) do
		local name = string.match(entry, "^(.+)%.luau$")
		if name == nil then
			error(("%s holds %s, which is not a module"):format(DIR, entry))
		end
		found[name] = code(DIR .. entry)
	end
	for _, name in ipairs(MODULES) do
		if found[name] == nil then
			error(("%s has no %s: this gate would check nothing"):format(DIR, name))
		end
	end
	for name in pairs(found) do
		if table.find(MODULES, name) == nil then
			error(("%s%s.luau is new: add it to MODULES so these gates read it"):format(DIR, name))
		end
	end
	return found
end

local read: { [string]: string }? = nil

-- The folder's modules, read once, the first time a case asks.
local function modules(): { [string]: string }
	local found = read or folder()
	read = found
	return found
end

local function module(name: string): string
	return modules()[name]
end

-- One function's source, from its header to the first `end` at column 0, whitespace folded.
local function body(source: string, header: string, where: string): string
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(where, header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "))
end

local function has(text: string, needle: string): boolean
	return text:find(needle, 1, true) ~= nil
end

-- Whether `first` appears in `text`, and `later` after it.
local function ordered(text: string, first: string, later: string): boolean
	local at = text:find(first, 1, true)
	return at ~= nil and text:find(later, at + #first, true) ~= nil
end

local function count(text: string, needle: string): number
	local found, from = 0, 1
	while true do
		local at = text:find(needle, from, true)
		if at == nil then
			return found
		end
		found += 1
		from = at + #needle
	end
end

local function requireAll(text: string, needles: { string }, what: string)
	for _, needle in ipairs(needles) do
		if not has(text, needle) then
			error(("%s no longer holds: %s"):format(what, needle))
		end
	end
end

describe("the WorldBossService folder", function()
	it("holds exactly the modules these gates read", function()
		expect(#MODULES).toBe(7)
		for _, name in ipairs(MODULES) do
			expect(#modules()[name] > 0).toBe(true)
		end
	end)
end)

describe("a practice leaves the server's event alone", function()
	it("is never live: ranked keeps pairing while one player practises", function()
		local live = body(module("init"), "function WorldBossService.isLive(", "init")
		expect(live).toBe(
			'function WorldBossService.isLive(): boolean return slot.State ~= nil and slot.Kind == "Event" '
		)
	end)

	it("moves the schedule only when the event ends, and asks before the kind is reset", function()
		local reset = body(module("init"), "local function reset(", "init")
		expect(count(reset, "slot.NextEventAt =")).toBe(1)
		expect(
			ordered(
				reset,
				'if slot.Kind == "Event" then slot.NextEventAt = now + SCHEDULE.IntervalSeconds end',
				'slot.Kind = "Event"'
			)
		).toBe(true)
		-- Everything the fight in the slot carried goes with it.
		requireAll(reset, {
			"Policy.release()",
			"slot.Participants = {}",
			"slot.Departed = {}",
			"slot.Reentries = {}",
			"slot.GrowthOwed = {}",
			"slot.Starter = nil",
			"slot.EmptySince = nil",
			'deps.Registry.fireAll("BossChanged", nil)',
		}, "reset")
	end)

	it("never borrows the event's PvP rule", function()
		-- Policy.luau defines it; everywhere else, it is taken once, by the event's spawn.
		local total = 0
		for name, source in pairs(modules()) do
			if name ~= "Policy" then
				total += count(source, "Policy.take(")
			end
		end
		expect(total).toBe(1)
		local spawn = body(module("init"), "local function spawnBoss(", "init")
		expect(ordered(spawn, "Policy.take()", "openFight(eligible,")).toBe(true)
		expect(has(body(module("init"), "local function openFight(", "init"), "Policy.")).toBe(false)
		expect(has(body(module("init"), "function WorldBossService.enterFromPortal(", "init"), "Policy.")).toBe(false)
		expect(has(module("Admission"), "Policy")).toBe(false)
	end)

	it("sends back to the hub only whoever still stands in the arena", function()
		local finish = body(module("init"), "local function finish(", "init")
		expect(
			ordered(
				finish,
				"if live ~= nil and Context.inArena(player, live.Center) then",
				'log.try("teleportToHub " .. player.Name, deps.Hub.teleportToHub, player)'
			)
		).toBe(true)
		expect(count(module("init"), "deps.Hub.teleportToHub")).toBe(1)
		local context = module("Context")
		local reach = body(context, "local function rootInArena(", "Context")
		expect(has(reach, "(root.Position - center).Magnitude <= Context.ArenaReachStuds")).toBe(true)
		expect(has(body(context, "function Context.inArena(", "Context"), "return rootInArena(player, center) ~= nil")).toBe(
			true
		)
		expect(has(body(context, "function Context.arenaRoots(", "Context"), "rootInArena(player, center)")).toBe(true)
	end)
end)

describe("a practice speaks to its own participants", function()
	it("is heard only by participants still here, not let go, not in a match", function()
		local audience = module("Audience")
		local recipients = body(audience, "function Audience.recipients(", "Audience")
		expect(has(recipients, 'if slot.Kind == "Event" then return Players:GetPlayers() end')).toBe(true)
		expect(has(recipients, "not slot.Departed[player.UserId] and not deps.Match.isInMatch(player)")).toBe(true)
		local tell = body(audience, "function Audience.tell(", "Audience")
		expect(ordered(tell, 'if slot.Kind == "Event" then deps.Notify.sendAll(', "Audience.recipients()")).toBe(true)
		local push = body(audience, "function Audience.push(", "Audience")
		expect(has(push, 'slot.Kind == "Practice")')).toBe(true)
		expect(has(push, "for _, player in ipairs(Audience.recipients()) do")).toBe(true)
		-- Only the event's announce is server-wide by construction; every other word goes through the audience.
		local init = module("init")
		expect(count(init, "Notify.sendAll(")).toBe(1)
		expect(has(body(init, "local function announce(", "init"), 'deps.Notify.sendAll("boss.announced"')).toBe(true)
		expect(has(init, "Players:GetPlayers()")).toBe(false)
		expect(has(init, 'Registry.fire("BossChanged"')).toBe(false)
	end)

	it("lets a participant go through a gate, or a ranked match, and clears a practice's band", function()
		local audience = module("Audience")
		local release = body(audience, "function Audience.release(", "Audience")
		expect(
			ordered(
				release,
				"slot.Departed[player.UserId] = how",
				'if slot.Kind == "Practice" then deps.Registry.fire("BossChanged", player, nil) end'
			)
		).toBe(true)
		local matched = body(audience, "function Audience.releaseMatched(", "Audience")
		expect(has(matched, 'if slot.Kind ~= "Practice" then return end')).toBe(true)
		expect(has(matched, 'deps.Match.isInMatch(player) then Audience.release(player, "Match")')).toBe(true)
		local init = module("init")
		expect(ordered(body(init, "local function tickFight(", "init"), "Audience.releaseMatched()", "Encounter.step")).toBe(
			true
		)
		expect(has(body(init, "function WorldBossService.leave(", "init"), 'Audience.release(player, "Gate")')).toBe(
			true
		)
		local engaged = body(init, "function WorldBossService.isEngaged(", "init")
		expect(has(engaged, "table.find(slot.Participants, userId) ~= nil and not slot.Departed[userId]")).toBe(true)
	end)
end)

describe("the hub's gate", function()
	it("opens a practice only when allowed, and records its starter only once it has opened", function()
		local enter = body(module("init"), "function WorldBossService.enterFromPortal(", "init")
		local steps = {
			'if deps.Match.isInMatch(player) then return false, "queue.inMatch" end',
			"if slot.State ~= nil then return Admission.join(player, now) end",
			"Admission.startRefusal(player, now)",
			'slot.Kind = "Practice"',
			"openFight,",
			'if not opened then reset(now) return false, "boss.portal.busy" end',
			"Admission.opened(player, now)",
		}
		for index = 2, #steps do
			if not ordered(enter, steps[index - 1], steps[index]) then
				error(("enterFromPortal no longer does %q before %q"):format(steps[index - 1], steps[index]))
			end
		end
		local opened = body(module("Admission"), "function Admission.opened(", "Admission")
		requireAll(opened, {
			"slot.Starter = player.UserId",
			"slot.StartedAt = now",
			"startCooldownUntil[player.UserId] = now + PRACTICE.StartCooldownSeconds",
		}, "Admission.opened")
		local refusal = body(module("Admission"), "function Admission.startRefusal(", "Admission")
		expect(ordered(refusal, "startCooldownUntil[userId] = nil", "BossPractice.startVerdict(")).toBe(true)
		requireAll(refusal, {
			"NextEventAt = slot.NextEventAt,",
			"Eligible = #Context.eligiblePlayers(deps.Match),",
			"CooldownUntil = startCooldownUntil[player.UserId] or 0,",
		}, "Admission.startRefusal")
	end)

	it(
		"reports the event's participation quest only for a player it adds, and books growth only in a practice",
		function()
			local admission = module("Admission")
			expect(count(admission, '"BossParticipation"')).toBe(1)
			local admit = body(admission, "local function admit(", "Admission")
			expect(
				has(
					admit,
					'if verdict == "Join" and table.find(slot.Participants, userId) == nil then '
						.. "table.insert(slot.Participants, userId) "
						.. 'if slot.Kind == "Event" then Rewards.reportQuest(deps, player, "BossParticipation") '
						.. "else slot.GrowthOwed[userId] = true end"
				)
			).toBe(true)
			expect(
				has(admit, 'elseif verdict == "Rejoin" then slot.Reentries[userId] = (slot.Reentries[userId] or 0) + 1')
			).toBe(true)
			expect(ordered(admit, "slot.Departed[userId] = nil", "Encounter.placeOne(live.Arena, player, pad")).toBe(
				true
			)
			local join = body(admission, "function Admission.join(", "Admission")
			expect(has(join, 'slot.Reentries[userId] or 0, PRACTICE.MaxReentries, slot.Kind == "Practice" )')).toBe(
				true
			)
			-- The event credits its participation when a fight opens, never for one that could not.
			local spawn = body(module("init"), "local function spawnBoss(", "init")
			expect(ordered(spawn, "if not openFight(", 'Rewards.reportQuest(deps, player, "BossParticipation")')).toBe(
				true
			)
		end
	)

	it("grows a practice's humanoid, its credited health and its rules together", function()
		local grow = body(module("Admission"), "local function grow(", "Admission")
		requireAll(grow, {
			"if added <= 0 then return end",
			"WorldBossMode.grow(current, added)",
			"live.LastHealth += added",
		}, "grow")
		expect(
			ordered(
				grow,
				"live.Humanoid.MaxHealth += added",
				"live.Humanoid.Health = math.clamp(live.Humanoid.Health + added, STANDING_HEALTH, live.Humanoid.MaxHealth)"
			)
		).toBe(true)
		expect(has(module("Admission"), "local STANDING_HEALTH = 1")).toBe(true)
		-- A joiner is dropped where the server says, and trust follows them there.
		local place = body(module("Encounter"), "function Encounter.placeOne(", "Encounter")
		expect(
			has(
				place,
				"Teleport.place(deps.Combat, player, character, CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))"
			)
		).toBe(true)
		expect(has(body(module("Encounter"), "function Encounter.place(", "Encounter"), "Encounter.placeOne(")).toBe(
			true
		)
	end)

	-- A griefer walking in and straight back out of somebody's practice used to leave it HealthPerJoiner stronger
	-- for good. The gate now only books the growth; the joiner's first hit that leaves the Erasure standing pays it.
	it("grows a practice for a joiner's first hit, never for walking in or out", function()
		local admission = module("Admission")
		-- Nothing on the way in: the gate books, and grows nothing.
		local admit = body(admission, "local function admit(", "Admission")
		expect(has(admit, "grow(")).toBe(false)
		expect(has(admit, "Health")).toBe(false)
		-- Nothing on the way out: a gate, a match or the end of the fight lets a joiner go without touching it.
		expect(has(body(module("init"), "function WorldBossService.leave(", "init"), "Health")).toBe(false)
		expect(has(body(module("Audience"), "function Audience.release(", "Audience"), "Health")).toBe(false)
		expect(has(body(module("Audience"), "function Audience.releaseMatched(", "Audience"), "Health")).toBe(false)
		-- One place writes the boss's health after it is built, and one place calls it: the first hit.
		local writes, calls = 0, 0
		for _, source in pairs(modules()) do
			local folded = source:gsub("%s+", " ")
			writes += count(folded, "Humanoid.MaxHealth +=") + count(folded, "Humanoid.Health =")
			calls += count(folded, "grow( live, current,")
		end
		expect(writes).toBe(2)
		expect(calls).toBe(1)
		local struck = body(admission, "function Admission.struck(", "Admission")
		local steps = {
			'if live == nil or current == nil or current.Phase ~= "Fighting" or not slot.GrowthOwed[userId] then return end',
			"slot.GrowthOwed[userId] = nil",
			"grow( live, current, BossPractice.growthOnHit(live.Humanoid.Health, current.MaxHealth, "
				.. "PRACTICE.HealthPerJoiner, PRACTICE.HealthCap) )",
		}
		for index = 2, #steps do
			if not ordered(struck, steps[index - 1], steps[index]) then
				error(("Admission.struck no longer does %q before %q"):format(steps[index - 1], steps[index]))
			end
		end
		-- Every hit on the boss is credited against the health it found, then offered to the growth.
		local init = module("init")
		expect(count(init, "Admission.struck(")).toBe(1)
		expect(
			ordered(
				body(init, "local function openFight(", "init"),
				"Encounter.recordDamage(live, current, sourceUserId, applied)",
				"Admission.struck(sourceUserId)"
			)
		).toBe(true)
		expect(has(body(module("Context"), "function Context.newSlot(", "Context"), "GrowthOwed = {},")).toBe(true)
		-- The growth a joiner owes outlives their walk-out: a gate, a match or a death keeps it booked, so a joiner
		-- who steps out and walks back in still grows the Erasure with the first hit they land. Only that hit and the
		-- end of the fight let go of it; were a way out to clear it, a return would fight a boss never grown for them.
		local mentions = 0
		for _, source in pairs(modules()) do
			mentions += count(source, "GrowthOwed")
		end
		expect(mentions).toBe(6)
		expect(count(struck, "slot.GrowthOwed[userId] = nil")).toBe(1)
		expect(count(body(module("init"), "local function reset(", "init"), "slot.GrowthOwed = {}")).toBe(1)
	end)

	-- The killing blow lands between two of the fight's ticks; a player let in during those frames was dropped
	-- into a fight already won, and a practice grew back a dead Erasure.
	it("closes on a boss already down, before the fight's next tick records it", function()
		local join = body(module("Admission"), "function Admission.join(", "Admission")
		expect(
			has(
				join,
				"BossPractice.entryVerdict( "
					.. "BossPractice.gatePhase(current.Phase, if live ~= nil then live.Humanoid.Health else nil),"
			)
		).toBe(true)
		expect(ordered(join, "local live = slot.Boss", "BossPractice.gatePhase(")).toBe(true)
		expect(has(join, 'elseif verdict == "Closing" then return false, "boss.portal.closing"')).toBe(true)
	end)
end)

describe("an emptied practice", function()
	it("drops the pending blow, waits for returners, and penalises whoever walked out early", function()
		local init = module("init")
		local empty = body(init, "local function closeEmpty(", "init")
		expect(ordered(empty, 'if slot.Kind == "Event" then', "expire(current, now) return end")).toBe(true)
		local steps = {
			"WorldBossMode.endAttack(current)",
			"BossPractice.keepAlive(false, #Audience.recipients() > 0, since, now, PRACTICE.EmptyGraceSeconds)",
			"expire(current, now)",
			"Admission.closedEmpty(now)",
		}
		local practice = empty:sub((empty:find("return end", 1, true) or 1) + 1)
		for index = 2, #steps do
			if not ordered(practice, steps[index - 1], steps[index]) then
				error(("closeEmpty no longer does %q before %q"):format(steps[index - 1], steps[index]))
			end
		end
		local tick = body(init, "local function tickFight(", "init")
		expect(has(tick, 'elseif outcome == "Empty" then closeEmpty(current, now)')).toBe(true)
		expect(has(tick, "else slot.EmptySince = nil")).toBe(true)
		local closed = body(module("Admission"), "function Admission.closedEmpty(", "Admission")
		expect(has(closed, 'BossPractice.startPenalty( slot.Departed[starter] == "Gate", slot.StartedAt, now,')).toBe(
			true
		)
	end)

	-- A starter a ranked match took, or who died and did not make it back, was charged the walk-out's five
	-- minutes. Only the gate is a walk-out, so only the gate says so.
	it("penalises only a starter who walked out through a gate", function()
		expect(has(module("Context"), 'export type Release = "Gate" | "Match"')).toBe(true)
		expect(has(module("Context"), "Departed: { [number]: Release },")).toBe(true)
		local gate, match, written = 0, 0, 0
		for _, source in pairs(modules()) do
			gate += count(source, 'Audience.release(player, "Gate")')
			match += count(source, 'Audience.release(player, "Match")')
			written += count(source, "slot.Departed[player.UserId] =")
		end
		expect(gate).toBe(1)
		expect(match).toBe(1)
		expect(written).toBe(1)
		expect(
			has(body(module("init"), "function WorldBossService.leave(", "init"), 'Audience.release(player, "Gate")')
		).toBe(true)
		local release = body(module("Audience"), "function Audience.release(", "Audience")
		expect(has(release, "function Audience.release(player: Player, how: Context.Release)")).toBe(true)
		-- The penalty asks how the starter left, not merely whether the practice emptied.
		local closed = body(module("Admission"), "function Admission.closedEmpty(", "Admission")
		expect(count(closed, 'slot.Departed[starter] == "Gate"')).toBe(1)
		expect(has(closed, "startPenalty( true,")).toBe(false)
	end)
end)

describe("what a fight pays", function()
	it("pays a practice a fraction, under the profile's daily count and the profile's gap", function()
		local rewards = module("Rewards")
		local pay = body(rewards, "function Rewards.pay(", "Rewards")
		expect(has(pay, 'if ctx.Kind == "Practice" then payPractice(ctx) else payEvent(ctx)')).toBe(true)
		local practice = body(rewards, "local function payPractice(", "Rewards")
		expect(ordered(practice, "local reward = practicePay(ctx, player, today)", "credit(deps, player, reward)")).toBe(
			true
		)
		local each = body(rewards, "local function practicePay(", "Rewards")
		expect(has(each, "WorldBossMode.rewardFor(share, PRACTICE.RewardFactor)")).toBe(true)
		expect(has(each, "if not practiceAllowed(ctx, player, today) then return nil end return reward")).toBe(true)
		-- A practice counts no boss kill and advances no "BossKill" quest: both are the event's.
		for _, text in ipairs({ practice, each }) do
			expect(has(text, "bumpBossKills")).toBe(false)
			expect(has(text, "BossKill")).toBe(false)
		end
		local event = body(rewards, "local function payEvent(", "Rewards")
		expect(has(event, "bumpBossKills(deps, player)")).toBe(true)
		expect(has(event, 'Rewards.reportQuest(deps, player, "BossKill")')).toBe(true)
		expect(count(rewards, '"BossKill"')).toBe(1)

		local allowed = body(rewards, "local function practiceAllowed(", "Rewards")
		local steps = {
			"local now = os.time() local last = daily.PracticeLastPaidAt if now - last < PRACTICE.RewardGapSeconds then",
			'"boss.practice.noReward"',
			"DailyCap.take(daily.PracticeDay, daily.PracticePaid, today, PRACTICE.RewardsPerDay, 1)",
			"daily.PracticePaid = used",
			"if granted >= 1 then daily.PracticeLastPaidAt = now",
			'deps.DataService.push(player, "Daily")',
			'"boss.practice.dailyDone"',
		}
		for index = 2, #steps do
			if not ordered(allowed, steps[index - 1], steps[index]) then
				error(("practiceAllowed no longer does %q before %q"):format(steps[index - 1], steps[index]))
			end
		end
	end)

	-- A late joiner's 1 % share pays 1 XP and 0 Folios, and it used to spend one of the day's paid practices and
	-- start the server's 20-minute gap: the reward is now worked out first, and only a pay worth it is charged.
	it("charges the caps only for a pay worth a paid practice, and pays a sliver its XP free", function()
		local rewards = module("Rewards")
		local pay = body(rewards, "local function practicePay(", "Rewards")
		local steps = {
			"local reward = WorldBossMode.rewardFor(share, PRACTICE.RewardFactor)",
			"if reward == nil then return nil end",
			-- Under the floor: the XP alone, before either cap is asked.
			"if not BossPractice.charged(reward.Folios + reward.BonusFolios, PRACTICE.MinPaidFolios) then "
				.. "return { Xp = reward.Xp, Folios = 0, BonusXp = reward.BonusXp, BonusFolios = 0 } end",
			-- At or over it: a paid practice, under both caps.
			"if not practiceAllowed(ctx, player, today) then return nil end",
			"return reward",
		}
		for index = 2, #steps do
			if not ordered(pay, steps[index - 1], steps[index]) then
				error(("practicePay no longer does %q before %q"):format(steps[index - 1], steps[index]))
			end
		end
		-- The caps are charged in that one place, and nowhere else.
		expect(count(rewards, "practiceAllowed(ctx, player, today)")).toBe(1)
		expect(count(rewards, "PracticeLastPaidAt = now")).toBe(1)
		expect(count(rewards, "LastPaidAt[")).toBe(0)
		expect(count(rewards, "DailyCap.take(")).toBe(1)
	end)

	it("credits no line a practice's factor rounded to nothing", function()
		local credit = body(module("Rewards"), "local function credit(", "Rewards")
		for _, guard in ipairs({
			'if reward.Xp >= MIN_AMOUNT then xp += deps.Progression.addXp(player, reward.Xp, "BossParticipation")',
			'if reward.Folios >= MIN_AMOUNT then folios += deps.Currency.add(player, reward.Folios, "BossParticipation")',
			'if reward.BonusXp >= MIN_AMOUNT then xp += deps.Progression.addXp(player, reward.BonusXp, "BossKillBonus")',
			"if reward.BonusFolios >= MIN_AMOUNT then folios += deps.Currency.add(",
		}) do
			if not has(credit, guard) then
				error("credit no longer guards: " .. guard)
			end
		end
		expect(has(module("Rewards"), "local MIN_AMOUNT = 1")).toBe(true)
	end)
end)

describe("the rules of a practice (WorldBossMode)", function()
	it("scales every reward line once, keeps phases entered, grows both healths and flags the snapshot", function()
		local mode = code(MODE)
		local reward = body(mode, "function WorldBossMode.rewardFor(", "WorldBossMode")
		expect(has(reward, "if share < REWARDS.MinShareToReward or scale <= 0 then return nil end")).toBe(true)
		expect(count(reward, "BossPractice.scaled(")).toBe(4)
		local health = body(mode, "function WorldBossMode.setHealth(", "WorldBossMode")
		expect(has(health, "math.max(state.PhaseIndex, WorldBossConfig.phaseFor(fraction))")).toBe(true)
		local grow = body(mode, "function WorldBossMode.grow(", "WorldBossMode")
		expect(ordered(grow, "state.MaxHealth += added", "state.Health += added")).toBe(true)
		local fresh = body(mode, "function WorldBossMode.newState(", "WorldBossMode")
		expect(has(fresh, "local health = maxHealth or WorldBossConfig.healthFor(participants)")).toBe(true)
		expect(has(body(mode, "function WorldBossMode.snapshot(", "WorldBossMode"), "Practice = practice,")).toBe(true)
	end)
end)

describe("free casting", function()
	it("is refused to a developer in any fight against the Erasure, practice included", function()
		local free = body(code(GLYPHS), "local function freeCasting(", "GlyphService")
		requireAll(free, {
			"not match.isInMatch(player)",
			"and not worldBoss.isLive()",
			"and not worldBoss.isEngaged(player)",
			"and not battleground.isInside(player)",
		}, "freeCasting")
	end)
end)
