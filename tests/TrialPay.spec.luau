--!strict
-- The hub's Trials, capped (E10-S3). A proof never dodges and never hits back, so an uncapped proof was the
-- best-paid thing in the game for the least play: ECONOMY §2 put it near 19 000 XP an hour, above a match.
-- Now a day of Trials pays its Folios up to a cap, its full XP for a number of kills and a share after, none of
-- it to the pass, and nothing to a player who has not cast or dashed in the last minute. The rule is TrialPay's,
-- run here; EnemyService, ProgressionService and GlyphService are read as text, since Lune cannot run them.
local DailyCap = require("../src/server/Pure/DailyCap")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local Strings = require("../src/shared/Strings")
local TrialPay = require("../src/server/Pure/TrialPay")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PAY = GameConfig.Enemy.Pay
local XP = ProgressionConfig.XP.DummyKill
local FOLIOS = ProgressionConfig.Folios.DummyKill
local TODAY = 20400

local function fresh(): TrialPay.Ledger
	return { Day = 0, Kills = 0, Folios = 0 }
end

-- `kills` kills in a row on `ledger`, today: what they paid in all, the ledger after them, and on which kill
-- the day's full pay ended (nil if it did not).
local function play(ledger: TrialPay.Ledger, kills: number): (number, number, TrialPay.Ledger, number?)
	local xp, folios, cappedOn = 0, 0, nil
	for kill = 1, kills do
		local pay = TrialPay.kill(ledger, TODAY, PAY, XP, FOLIOS, DailyCap.take)
		xp += pay.Xp
		folios += pay.Folios
		ledger = pay.Ledger
		if pay.Capped then
			assert(cappedOn == nil, "the day's full pay ended twice")
			cappedOn = kill
		end
	end
	return xp, folios, ledger, cappedOn
end

local function strip(path: string): string
	return (fs.readFile(path):gsub("%-%-[^\n]*", ""))
end

local function body(source: string, header: string): string
	local start = source:find(header, 1, true)
	if start == nil then
		error(("no %s: this gate would check nothing"):format(header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "))
end

local function has(text: string, needle: string): boolean
	return text:find(needle, 1, true) ~= nil
end

describe("a day of Trials", function()
	it("ships the caps E10-S3 set: 40 Folios, 25 kills in full, a minute to stay active", function()
		expect(PAY.DailyFolioCap).toBe(40)
		expect(PAY.FullXpKills).toBe(25)
		expect(PAY.ActiveWindowSeconds).toBe(60)
		expect(PAY.TailXpShare).toBeGreaterThan(0)
		expect(PAY.TailXpShare).toBeLessThan(1)
	end)

	it("pays full XP for the first kills of the day, then its share, and Folios up to the cap", function()
		local xp, folios, ledger = play(fresh(), PAY.FullXpKills)
		expect(xp).toBe(PAY.FullXpKills * XP)
		expect(folios).toBe(math.min(PAY.FullXpKills * FOLIOS, PAY.DailyFolioCap))
		local tailXp, tailFolios, after = play(ledger, 100)
		expect(tailXp).toBe(100 * math.floor(XP * PAY.TailXpShare))
		expect(tailFolios + folios).toBe(PAY.DailyFolioCap)
		expect(after).toEqual({ Day = TODAY, Kills = PAY.FullXpKills, Folios = PAY.DailyFolioCap })
	end)

	it("never pays more Folios in a day than the cap, however many kills and whatever a proof is worth", function()
		for _, worth in ipairs({ 1, 2, 3, 7, 40, 100 }) do
			local paid, ledger = 0, fresh()
			for _ = 1, 500 do
				local pay = TrialPay.kill(ledger, TODAY, PAY, XP, worth, DailyCap.take)
				paid += pay.Folios
				ledger = pay.Ledger
			end
			expect(paid).toBe(PAY.DailyFolioCap)
		end
	end)

	it("says the day's full pay has ended on exactly one kill: the first that ran out of an allowance", function()
		local _, _, _, cappedOn = play(fresh(), 200)
		local foliosLast = math.ceil(PAY.DailyFolioCap / FOLIOS)
		expect(cappedOn).toBe(math.min(foliosLast, PAY.FullXpKills))
		-- A day that already ran out says nothing more, on this server or another (the ledger is the profile's).
		local _, _, spent = play(fresh(), 200)
		local _, _, _, again = play(spent, 50)
		expect(again).toBeNil()
	end)

	it("starts every day afresh, whatever the day before left", function()
		local _, _, spent = play(fresh(), 200)
		local pay = TrialPay.kill(spent, TODAY + 1, PAY, XP, FOLIOS, DailyCap.take)
		expect(pay.Xp).toBe(XP)
		expect(pay.Folios).toBe(FOLIOS)
		expect(pay.Ledger).toEqual({ Day = TODAY + 1, Kills = 1, Folios = FOLIOS })
		expect(pay.Capped).toBe(false)
	end)

	it("reads yesterday's spent ledger as a fresh day when it says the day's pay has ended", function()
		-- One kill in full a day: every day's first kill is the one that ends its full pay.
		local tight: TrialPay.Rules = table.clone(PAY)
		tight.FullXpKills = 1
		local first = TrialPay.kill(fresh(), TODAY, tight, XP, FOLIOS, DailyCap.take)
		expect(first.Capped).toBe(true)
		local spent = TrialPay.kill(first.Ledger, TODAY, tight, XP, FOLIOS, DailyCap.take)
		expect(spent.Capped).toBe(false)
		local tomorrow = TrialPay.kill(spent.Ledger, TODAY + 1, tight, XP, FOLIOS, DailyCap.take)
		expect(tomorrow.Xp).toBe(XP)
		expect(tomorrow.Capped).toBe(true)
	end)

	it("pays only a player who cast a glyph or dashed in the last minute", function()
		expect(TrialPay.active(nil, 100, PAY)).toBe(false)
		expect(TrialPay.active(100, 100, PAY)).toBe(true)
		expect(TrialPay.active(100, 100 + PAY.ActiveWindowSeconds, PAY)).toBe(true)
		expect(TrialPay.active(100, 100 + PAY.ActiveWindowSeconds + 0.01, PAY)).toBe(false)
		-- A stamp from a clock ahead of this one is no activity.
		expect(TrialPay.active(200, 100, PAY)).toBe(false)
	end)
end)

describe("the Trials, on the server", function()
	it("pay every kill through TrialPay, on the profile's ledger, and nothing to an idle player", function()
		local enemy = strip("src/server/Services/EnemyService.luau")
		local credit = body(enemy, "local function creditKiller(")
		local ordered = {
			"data.Stats.Kills += 1",
			"if not TrialPay.active(lastActiveAt[killer], os.clock(), PAY) then",
			-- Said once a session, however many kills go unpaid.
			'if not toldIdle[killer] then toldIdle[killer] = true notify.send(killer, "trials.idle", nil, "Info") end return end',
			"local today = DailyStreak.dayIndex(os.time())",
			"local ledger = { Day = daily.TrialDay, Kills = daily.TrialKills, Folios = daily.TrialFolios }",
			"local pay = TrialPay.kill( ledger, today, PAY, ProgressionConfig.XP.DummyKill, ProgressionConfig.Folios.DummyKill, DailyCap.take )",
			"daily.TrialDay = pay.Ledger.Day daily.TrialKills = pay.Ledger.Kills daily.TrialFolios = pay.Ledger.Folios",
			'dataService.push(killer, "Daily")',
			'local xp = if pay.Xp >= 1 then progression.addXp(killer, pay.Xp, "DummyKill") else 0',
			'if pay.Folios >= 1 then currency.add(killer, pay.Folios, "DummyKill") end',
			'if pay.Capped then notify.send(killer, "trials.capped", nil, "Info") end',
		}
		local from = 1
		for _, line in ipairs(ordered) do
			local at = credit:find(line, from, true)
			if at == nil then
				error(("EnemyService.creditKiller lost, or reordered, %q"):format(line))
			end
			from = at + #line
		end
		-- The proof's worth is paid through the ledger alone: no other grant of it anywhere in the service.
		local _, grants = enemy:gsub("ProgressionConfig%.XP%.DummyKill", "")
		expect(grants).toBe(1)
		expect(has(enemy, "local PAY = GameConfig.Enemy.Pay")).toBe(true)
		local start = body(enemy, "function EnemyService.Start(")
		expect(has(start, "glyph.Cast:Connect(function(player: Player) markActive(player) end)")).toBe(true)
		expect(has(start, "combat.Dashed:Connect(function(player: Player) markActive(player) end)")).toBe(true)
		expect(has(start, "lastActiveAt[player] = nil toldIdle[player] = nil")).toBe(true)
		expect(has(body(enemy, "local function markActive("), "lastActiveAt[player] = os.clock()")).toBe(true)
	end)

	it("keep the Trials' XP out of the pass", function()
		expect(ProgressionConfig.PassExcluded).toEqual({ DummyKill = true })
		local progression = strip("src/server/Services/ProgressionService.luau")
		local addXp = body(progression, "function ProgressionService.addXp(")
		expect(has(addXp, "if passXp > 0 and not PASS_EXCLUDED[reason] then battlepass.addXp(player, passXp) end")).toBe(
			true
		)
		expect(has(progression, "local PASS_EXCLUDED = ProgressionConfig.PassExcluded")).toBe(true)
	end)

	it("pay a glyph's XP for what it struck other than a proof", function()
		local glyph = strip("src/server/Services/GlyphService.luau")
		local run = body(glyph, "local function runEffect(")
		expect(has(run, "Landed = landed,")).toBe(true)
		expect(has(run, "for _, proof in pairs(landed) do if not proof then paying += 1 end end")).toBe(true)
		expect(has(run, "return hits, paying")).toBe(true)
		-- The service never reads the tag itself: by the time a zone stops ticking, a proof it felled has lost it
		-- (EnemyService takes it on the death), and a proof read then paid its killer a hit.
		expect(has(glyph, "HasTag")).toBe(false)
		local record = body(glyph, "local function recordCast(")
		expect(
			has(
				record,
				'if paying > 0 then progression.addXp(player, ProgressionConfig.XP.GlyphHit * math.min(paying, MAX_REWARDED_HITS), "GlyphHit") end'
			)
		).toBe(true)
		-- Every landed hit is recorded where damage lands, whatever the glyph, and whether it struck a proof is read
		-- before the hit, which may fell the proof and take its tag.
		local effects = strip("src/server/Effects/GlyphEffects.luau")
		expect(has(effects, "local PROOF_TAG = GameConfig.Enemy.Tag")).toBe(true)
		local damage = body(effects, "local function damageModel(")
		local ordered = {
			"local landed = ctx.Landed local proof = landed ~= nil and CollectionService:HasTag(model, PROOF_TAG)",
			'local result = ctx.Combat.ApplyDamage(ctx.Caster, model, tracker.Amount, "Glyph", tracker.Tags, ctx.Def.Pigment)',
			"tracker.Hits[model] = (hits or 0) + 1 if landed ~= nil and landed[model] == nil then landed[model] = proof end return true",
		}
		local from = 1
		for _, line in ipairs(ordered) do
			local at = damage:find(line, from, true)
			if at == nil then
				error(("GlyphEffects.damageModel lost, or reordered, %q"):format(line))
			end
			from = at + #line
		end
		local _, reads = damage:gsub("HasTag", "")
		expect(reads).toBe(1)
	end)

	it("tell the player, in both languages", function()
		for _, key in ipairs({ "trials.capped", "trials.idle" }) do
			expect(Strings.has(key)).toBe(true)
			local entry = (Strings.Table :: any)[key]
			expect(#entry.en).toBeGreaterThan(0)
			expect(#entry.fr).toBeGreaterThan(0)
		end
	end)
end)
