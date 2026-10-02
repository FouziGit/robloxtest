--!strict
-- What the game tells Roblox's analytics, and in which words. AnalyticsService reads it, and refuses a custom
-- event it does not name or custom fields Roblox would not read.
--
-- Lives under src/server, like DeveloperConfig: events leave from the server only, and no client needs to know
-- how the dashboards are cut. Pure on purpose: no Roblox global and no require, so the tests load it by path.
--
-- Roblox's limits, from its analytics pages read on 30/09/2026 (docs/ROADMAP.md, sources): 100 custom event
-- names per experience; three custom fields per event, whose keys are CustomField01 to CustomField03 and whose
-- values are text, anything else being ignored; past 8,000 combinations of those values, the rest is grouped
-- as "Other"; past 20 transaction types, the same; 10 currencies.

local AnalyticsConfig = {}

AnalyticsConfig.Limits = {
	CustomEventNames = 100,
	FieldCombinations = 8000,
	TransactionTypes = 20,
	Currencies = 10,
}

-- What the server may send, twice bounded. An event past either bound is dropped, never queued: analytics is
-- best-effort telemetry.
--
-- The server: Roblox takes 120 + 20 per player requests a minute from a whole server, every family of event
-- together (the event-types page). The server never sends past that minute, for the players in it now: past it,
-- Roblox would throttle the rest, and a throttled call is not a broken transport.
--
-- Each player: a burst, then a trickle, so nobody spends the minute of a whole server alone. Three times a
-- player's own 20, because play pays out faster than one Folio event every three seconds -- the hub's six
-- dummies at 150 health each come back three seconds after they fall -- and a share cut to exactly 20 dropped
-- the Folios of the players who play most, and after them their queue, their match and their purchases. The
-- burst holds the end of a match -- MatchEnded, a GlyphMatch for each of the ten slots at most, the Folios of the
-- result, of the first win and of the tiers they cross -- and the GlyphPick of the queue a rematch joins.
AnalyticsConfig.Budget = {
	ServerPerMinute = 120,
	ServerPerPlayerPerMinute = 20,
	Burst = 32,
	PerMinute = 60,
}

----------------------------------------------------------------
-- Economy
----------------------------------------------------------------

-- Roblox's own transaction types (Enum.AnalyticsEconomyTransactionType), the ones its Economy dashboards file
-- every source and sink under.
AnalyticsConfig.TransactionTypes =
	{ "IAP", "TimedReward", "Onboarding", "Shop", "Gameplay", "ContextualPurchase" } :: { string }

-- Every reason CurrencyService is handed, and the transaction type the movement is filed under. Its item is the
-- reason itself.
AnalyticsConfig.Transactions = {
	-- Earned by playing.
	MatchWin = "Gameplay",
	MatchLoss = "Gameplay",
	MatchDraw = "Gameplay",
	PlayerKill = "Gameplay",
	DummyKill = "Gameplay",
	BossParticipation = "Gameplay",
	BossKillBonus = "Gameplay",
	BotSmudger = "Gameplay",
	BotQuill = "Gameplay",
	BotOverwriter = "Gameplay",
	-- A victory on the Flyleaf, under its own daily cap (FlyleafService, D-267).
	FlyleafKill = "Gameplay",
	-- A practice duel against a Forger, under its daily allowance (SparService, D-272).
	Spar = "Gameplay",
	QuestDaily = "Gameplay",
	QuestWeekly = "Gameplay",
	Battlepass = "Gameplay",
	SeasonReward = "Gameplay",
	-- Paid on a schedule.
	DailyStreak = "TimedReward",
	FirstWinOfDay = "TimedReward",
	PremiumBonus = "TimedReward",
} :: { [string]: string }

-- A reason "<Family><id>" pays one of many rewards the game's config lists: a milestone of the level road
-- ("Milestone45", HonoursService), a plate of the Ex-libris ("ExLibrisBreath4", HonoursService), a grade of a
-- Lectern drill ("DrillBrandFairCopy", DrillService). The family says the transaction type and the whole reason is
-- the item, so each milestone, plate and grade is read apart. The drills teach the kit, the first minutes' lesson:
-- Onboarding.
AnalyticsConfig.FamilyTransactions = {
	Milestone = "Gameplay",
	ExLibris = "Gameplay",
	Drill = "Onboarding",
} :: { [string]: string }

-- A reason "<Kind>:<item>" (and anything after) names what was bought, and its item is that key: a Robux product
-- ("Product:FolioSmall", or the Folios paid for what one could no longer deliver, "Product:TierSkip5:Compensation")
-- or an article of the shop ("Shop:<cosmetic id>", bought, or paid back when it could not be granted).
AnalyticsConfig.ItemTransactions = {
	Product = "IAP",
	Shop = "Shop",
} :: { [string]: string }

-- What an unlisted reason is filed under. It is still sent, and AnalyticsService warns once per reason.
AnalyticsConfig.FallbackTransaction = "Gameplay"

-- The transaction type and the item a currency movement of `reason` is filed under, and whether the reason is
-- listed above.
function AnalyticsConfig.economyOf(reason: string): (string, string, boolean)
	local kind, item = string.match(reason, "^([^:]+):([^:]+)")
	if kind ~= nil and item ~= nil then
		local transaction = AnalyticsConfig.ItemTransactions[kind]
		if transaction ~= nil then
			return transaction, item, true
		end
	end
	local transaction = AnalyticsConfig.Transactions[reason]
	if transaction ~= nil then
		return transaction, reason, true
	end
	for family, filed in pairs(AnalyticsConfig.FamilyTransactions) do
		if #reason > #family and string.sub(reason, 1, #family) == family then
			return filed, reason, true
		end
	end
	return AnalyticsConfig.FallbackTransaction, reason, false
end

----------------------------------------------------------------
-- Custom events
----------------------------------------------------------------

-- The only custom field keys Roblox reads (Enum.AnalyticsCustomFieldKeys.CustomField01.Name to 03), in order.
AnalyticsConfig.FieldKeys = { "CustomField01", "CustomField02", "CustomField03" } :: { string }

-- The words a custom field may hold, where the game's own config does not already list them.
AnalyticsConfig.Vocabulary = {
	PurchaseKind = { "Pass", "Product" },
	MatchOutcome = { "Win", "Loss", "Draw" },
	-- A glyph's side of a match: it won, or it did not (a draw is not a win).
	GlyphOutcome = { "Win", "Loss" },
	-- Why a match ended with no result: every participant left, the server closed, its mode could not say, the
	-- server cancelled it when its tick kept failing (MatchService.cancel, D-220), or a side walked out before it
	-- was really played (the void forfeit, D-255).
	VoidCause = { "Empty", "Closing", "Error", "Cancelled", "Unplayed" },
	BossKind = { "Event", "Practice" },
	BossOutcome = { "Defeated", "Expired" },
} :: { [string]: { string } }

-- Every custom event the game sends, by name, with what each of its custom fields holds, CustomField01 first.
-- A field names a list of Vocabulary above, or one the game's config owns: "Pass" and "Product" (the keys of
-- MonetizationConfig.Passes and .Products), "PurchaseKey" (either of them), "Mode" (MatchConfig.ModeOrder),
-- "Glyph" (the ids of GlyphConfig.Glyphs). An event says beside it what its value counts; one that says nothing
-- counts 1.
AnalyticsConfig.Events = {
	-- A Robux dialog closed with a purchase, or without one.
	PromptAccepted = { "PurchaseKind", "PurchaseKey" },
	PromptDeclined = { "PurchaseKind", "PurchaseKey" },
	-- A developer product delivered. Value: its price in Robux.
	ProductPurchased = { "Product" },
	-- A game pass bought in the game. Value: its price in Robux.
	PassPurchased = { "Pass" },
	-- A match formed from the queue, for each of its players. Value: the seconds they waited.
	MatchFormed = { "Mode" },
	-- A wait the queue gave up on, for each player it let go. Value: the seconds they waited.
	QueueTimedOut = { "Mode" },
	-- A match played to its result, for each of its players still in the server. Value: the seconds it lasted.
	MatchEnded = { "Mode", "MatchOutcome" },
	-- A match that ended with no result, once for the match. Value: the seconds it had lasted.
	MatchVoided = { "Mode", "VoidCause" },
	-- A fight against the Erasure over, for each participant still in the server. Value: the seconds it lasted.
	BossEnded = { "BossKind", "BossOutcome" },
	-- The balance of the glyphs, in two events and no more. Each glyph a player cast in a match, at its result.
	-- Value: the damage it dealt them there.
	GlyphMatch = { "Glyph", "Mode", "GlyphOutcome" },
	-- Each glyph a player takes into a queue, once per wait (a leave and a join again count nothing more).
	GlyphPick = { "Glyph", "Mode" },
} :: { [string]: { string } }

return AnalyticsConfig
