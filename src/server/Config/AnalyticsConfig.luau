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
-- as "Other".

local AnalyticsConfig = {}

AnalyticsConfig.Limits = {
	CustomEventNames = 100,
	FieldCombinations = 8000,
}

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
