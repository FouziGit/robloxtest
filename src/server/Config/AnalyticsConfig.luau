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

-- Each player's share of what the server may send: a burst, then a steady trickle. An event past it is dropped,
-- never queued: analytics is best-effort telemetry.
AnalyticsConfig.Budget = {
	Burst = 8,
	PerMinute = 240,
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
	QuestDaily = "Gameplay",
	QuestWeekly = "Gameplay",
	Battlepass = "Gameplay",
	SeasonReward = "Gameplay",
	-- Paid on a schedule.
	DailyStreak = "TimedReward",
	FirstWinOfDay = "TimedReward",
	PremiumBonus = "TimedReward",
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
} :: { [string]: { string } }

-- Every custom event the game sends, by name, with what each of its custom fields holds, CustomField01 first.
-- A field names a list of Vocabulary above, or one the game's config owns: "Pass" and "Product" (the keys of
-- MonetizationConfig.Passes and .Products), "PurchaseKey" (either of them). An event says beside it what its
-- value counts; one that says nothing counts 1.
AnalyticsConfig.Events = {
	-- A Robux dialog closed with a purchase, or without one.
	PromptAccepted = { "PurchaseKind", "PurchaseKey" },
	PromptDeclined = { "PurchaseKind", "PurchaseKey" },
	-- A developer product delivered. Value: its price in Robux.
	ProductPurchased = { "Product" },
	-- A game pass bought in the game. Value: its price in Robux.
	PassPurchased = { "Pass" },
} :: { [string]: { string } }

return AnalyticsConfig
