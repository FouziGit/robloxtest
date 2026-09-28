--!strict
-- Shelves: the Shop's tabs other than today's rotation (D-147) -- what the player buys with Robux, and what
-- they already own.
--
--   Folios   three packs, the amount and a stack of coins, bought with Robux
--   Passes   the game passes and the other Robux products, each with what it gives; one owned says so
--   Locker   every cosmetic the player owns, by slot, to wear or take off
--
-- Everything is offered, never pushed: a Robux button opens the platform's own dialog for the entry the
-- player tapped, only when that entry exists on Roblox (a non-zero id), and the server's prompt rules
-- (docs/ECONOMY.md §5) stay the authority. Each shelf is built into the screen's content by its screen and
-- torn down with the tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Icon = require(script.Parent.Parent.Parent.components.Icon)
local ItemPreview = require(script.Parent.Parent.Parent.components.ItemPreview)
local ListRow = require(script.Parent.Parent.Parent.components.ListRow)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Seal = require(script.Parent.Parent.Parent.components.Seal)
local Sticker = require(script.Parent.Parent.Parent.components.Sticker)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Context = {
	Localize: Localizer,
	ClientData: { get: () -> Types.ProfileData? },
	RemoteClient: { fire: (name: string, ...any) -> () },
	-- Where the shelf is built, and what tears it down.
	Content: ScrollingFrame,
	Trove: typeof(Trove.new()),
	-- The Shop's own rule for a Robux product: it is configured and exists on Roblox.
	RobuxOffered: (productKey: string) -> boolean,
	-- An equip the server never answers is said on the HUD's toast column, as a purchase's is.
	HudController: { showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> () },
}

export type Shelf = {
	-- The profile changed: what is owned, worn or affordable.
	Refresh: () -> (),
	-- The first thing a gamepad can press on the shelf.
	Focus: () -> GuiObject?,
	-- The server answered an equip (it pushes Cosmetics on every path, a refusal too): what waited on it is
	-- let go. Only the locker equips.
	Settle: (() -> ())?,
}

type Offer = { Key: string, Kind: "Pass" | "Product", Button: Button.Button, Owned: Frame }
type LockerCard = { Id: string, SlotKey: string, Button: Button.Button }

local Shelves = {}

local CHAPTER = "Shop"
local SEASON = GameConfig.SeasonId
-- The packs, smallest first, and the game passes and products the Passes tab offers, in that order.
local FOLIO_PACKS = { "FolioSmall", "FolioMedium", "FolioLarge" }
local PASSES = { "Vip", "LoadoutSlots", "Orpiment", "SkinPack" }
local PRODUCTS = { "PremiumPass", "TierSkip5", "XpBoost1h" }
-- A pack card with a pointer; on a phone it keeps its width and takes the height the card has.
local PACK_WIDTH = 260
local PACK_HEIGHT = 330
local PACK_PADDING = 16
local AMOUNT_SIZE = 30
local MIN_SCALED_TEXT = 14
-- The stack of coins on a pack: three, each this big and this far over the last.
local COIN_SIZE = 48
local COIN_STEP = 18
local COINS = 3
-- An offer row: the name and what it gives, and its button or the owned seal.
local OFFER_HEIGHT = 96
local OFFER_DESC_SIZE = 16
-- What an offer's description names: the level Orpiment is free at (pass.orpiment.desc). Without it the shop
-- printed "{level}".
local DESC_PARAMS = { level = ProgressionConfig.OrpimentUnlockLevel }
local OWNED_SEAL = 28
-- A locker card: its preview, its name, and the one button.
local LOCKER_CELL = Vector2.new(200, 140)
local LOCKER_PREVIEW = 48
local LOCKER_NAME_SIZE = 18

local function blank(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function list(frame: Frame, direction: Enum.FillDirection, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
	return layout
end

local function pad(frame: Frame, amount: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, amount)
	padding.PaddingBottom = UDim.new(0, amount)
	padding.PaddingLeft = UDim.new(0, amount)
	padding.PaddingRight = UDim.new(0, amount)
	padding.Parent = frame
end

local function scaledText(name: string, font: Font, size: number, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.FontFace = font
	label.TextScaled = true
	label.TextColor3 = Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = MIN_SCALED_TEXT
	cap.MaxTextSize = size
	cap.Parent = label
	label.Parent = parent
	return label
end

local function own(context: Context, object: { Destroy: (self: any) -> () })
	context.Trove:Add(function()
		object:Destroy()
	end)
end

local function robuxLine(context: Context, price: number): string
	return context.Localize.t("shop.robuxPrice", { price = price })
end

----------------------------------------------------------------
-- Folios
----------------------------------------------------------------

-- Three packs of Folios, each a card: how many, a stack of coins, what they are for, and the Robux price.
function Shelves.folios(context: Context): Shelf
	local t = context.Localize.t
	local buttons: { Button.Button } = {}
	for index, key in ipairs(FOLIO_PACKS) do
		local product = MonetizationConfig.Products[key]
		if product == nil then
			continue
		end
		local holder = blank(key, context.Content)
		holder.LayoutOrder = index
		holder.Size = if Theme.touchOnly()
			then UDim2.new(0, PACK_WIDTH, 1, -Theme.Sizes.PaddingSmall)
			else UDim2.fromOffset(PACK_WIDTH, PACK_HEIGHT)
		context.Trove:Add(holder)
		local sticker = Sticker.new({ Kind = "Card", Fill = Theme.Colors.PanelRaised, Parent = holder })
		own(context, sticker)
		local body = blank("Body", sticker.Face)
		body.Size = UDim2.fromScale(1, 1)
		pad(body, PACK_PADDING)
		list(body, Enum.FillDirection.Vertical, Theme.Sizes.Gap)

		scaledText("Amount", Theme.Fonts.Title, AMOUNT_SIZE, 1, body).Text = t(product.NameKey)
		local stack = blank("Coins", body)
		stack.Size = UDim2.fromScale(1, 0)
		stack.LayoutOrder = 2
		local stackFlex = Instance.new("UIFlexItem")
		stackFlex.FlexMode = Enum.UIFlexMode.Fill
		stackFlex.Parent = stack
		for coinIndex = 1, COINS do
			local coin = Icon.new("Coin", COIN_SIZE)
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.Position = UDim2.new(0.5, (coinIndex - (COINS + 1) / 2) * COIN_STEP, 0.5, -(coinIndex - 1) * 6)
			coin.ZIndex = coinIndex
			coin.Parent = stack
		end
		local desc = scaledText("Desc", Theme.Fonts.Body, OFFER_DESC_SIZE, 3, body)
		desc.TextScaled = false
		desc.TextSize = OFFER_DESC_SIZE
		desc.TextWrapped = true
		desc.TextColor3 = Theme.Colors.TextMuted
		desc.AutomaticSize = Enum.AutomaticSize.Y
		desc.Text = t(product.DescKey, DESC_PARAMS)

		local button = Button.new({
			Text = t("shop.buy"),
			Sublabel = robuxLine(context, product.PriceRobux),
			Variant = "Premium",
			Wide = true,
			LayoutOrder = 4,
			Parent = body,
			OnClick = function()
				context.RemoteClient.fire("PromptPurchase", "Product", key)
			end,
		})
		own(context, button)
		button:SetDisabled(not context.RobuxOffered(key))
		table.insert(buttons, button)
	end

	return {
		Refresh = function() end,
		Focus = function(): GuiObject?
			for _, button in ipairs(buttons) do
				if not button:IsDisabled() then
					return button.Instance
				end
			end
			return nil
		end,
	}
end

----------------------------------------------------------------
-- Passes and products
----------------------------------------------------------------

-- Whether the profile already holds what an offer gives: a pass it owns, this season's premium track. The
-- consumables are never "owned".
local function offerOwned(data: Types.ProfileData?, offer: Offer): boolean
	if data == nil then
		return false
	end
	if offer.Kind == "Pass" then
		return data.Passes[offer.Key] == true
	end
	if offer.Key == "PremiumPass" then
		local season = data.Battlepass[SEASON]
		return season ~= nil and season.Premium
	end
	return false
end

-- Whether an offer can be bought now: it exists on Roblox, and a tier skip still has tiers to skip.
local function offerOpen(context: Context, data: Types.ProfileData?, offer: Offer): boolean
	if offer.Kind == "Pass" then
		local pass = MonetizationConfig.Passes[offer.Key]
		return pass ~= nil and pass.Id ~= 0
	end
	if offer.Key == "TierSkip5" and data ~= nil then
		local season = data.Battlepass[SEASON]
		if season ~= nil and season.Tier >= BattlepassConfig.MaxTier then
			return false
		end
	end
	return context.RobuxOffered(offer.Key)
end

-- Every game pass and every other Robux product, one row each: its name and what it gives, then the
-- price -- or, once owned, a √ seal.
function Shelves.passes(context: Context): Shelf
	local t = context.Localize.t
	local offers: { Offer } = {}

	local function row(key: string, kind: "Pass" | "Product", nameKey: string, descKey: string, price: number)
		local texts = blank("Texts")
		texts.Size = UDim2.fromScale(1, 1)
		local textsLayout = list(texts, Enum.FillDirection.Vertical, 2)
		textsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		scaledText("Name", Theme.Fonts.Bold, Theme.Sizes.TextButton, 1, texts).Text = t(nameKey)
		local desc = scaledText("Desc", Theme.Fonts.Body, OFFER_DESC_SIZE, 2, texts)
		desc.TextScaled = false
		desc.TextSize = OFFER_DESC_SIZE
		desc.TextWrapped = true
		desc.TextColor3 = Theme.Colors.TextMuted
		desc.Size = UDim2.new(1, 0, 0, (OFFER_DESC_SIZE + 4) * 2)
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Text = t(descKey, DESC_PARAMS)

		local right = blank("Offer")
		right.AutomaticSize = Enum.AutomaticSize.X
		right.Size = UDim2.fromScale(0, 1)
		local rightLayout = list(right, Enum.FillDirection.Horizontal, Theme.Sizes.PaddingSmall)
		rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		local button = Button.new({
			Text = t("shop.buy"),
			Sublabel = robuxLine(context, price),
			Variant = "Premium",
			LayoutOrder = 1,
			Parent = right,
			OnClick = function()
				context.RemoteClient.fire("PromptPurchase", kind, key)
			end,
		})
		own(context, button)
		local owned = blank("Owned", right)
		owned.AutomaticSize = Enum.AutomaticSize.X
		owned.Size = UDim2.fromScale(0, 1)
		owned.LayoutOrder = 2
		owned.Visible = false
		local ownedLayout = list(owned, Enum.FillDirection.Horizontal, Theme.Sizes.PaddingSmall)
		ownedLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		local seal = Seal.new({
			Text = Theme.Glyphs.Check,
			Fill = Theme.Colors.SuccessFill,
			Size = OWNED_SEAL,
			LayoutOrder = 1,
			Parent = owned,
		})
		own(context, seal)
		local word = Instance.new("TextLabel")
		word.Name = "Word"
		word.BackgroundTransparency = 1
		word.AutomaticSize = Enum.AutomaticSize.X
		word.Size = UDim2.fromScale(0, 1)
		word.FontFace = Theme.Fonts.Bold
		word.TextSize = Theme.Sizes.TextBody
		word.TextColor3 = Theme.Colors.Success
		word.Text = t("shop.owned")
		word.LayoutOrder = 2
		word.Parent = owned

		local listRow = ListRow.new({
			Left = texts,
			Right = right,
			Height = OFFER_HEIGHT,
			LayoutOrder = #offers + 1,
			Tint = Theme.Colors.Primary,
			Parent = context.Content,
		})
		own(context, listRow)
		table.insert(offers, { Key = key, Kind = kind, Button = button, Owned = owned })
	end

	for _, key in ipairs(PASSES) do
		local pass = MonetizationConfig.Passes[key]
		if pass ~= nil then
			row(key, "Pass", pass.NameKey, pass.DescKey, pass.PriceRobux)
		end
	end
	for _, key in ipairs(PRODUCTS) do
		local product = MonetizationConfig.Products[key]
		if product ~= nil then
			row(key, "Product", product.NameKey, product.DescKey, product.PriceRobux)
		end
	end

	local function refresh()
		local data = context.ClientData.get()
		for _, offer in ipairs(offers) do
			local owned = offerOwned(data, offer)
			offer.Owned.Visible = owned
			offer.Button.Instance.Visible = not owned
			offer.Button:SetDisabled(not offerOpen(context, data, offer))
		end
	end
	refresh()

	return {
		Refresh = refresh,
		Focus = function(): GuiObject?
			for _, offer in ipairs(offers) do
				if offer.Button.Instance.Visible and not offer.Button:IsDisabled() then
					return offer.Button.Instance
				end
			end
			return nil
		end,
	}
end

----------------------------------------------------------------
-- Locker
----------------------------------------------------------------

-- Every cosmetic the player owns, under its slot's heading, each a small card to wear or to take off. The
-- shelf is rebuilt when what is owned changes, and only its buttons when what is worn does.
function Shelves.locker(context: Context): Shelf
	local t = context.Localize.t
	local shelfTrove = context.Trove:Extend()
	local cards: { LockerCard } = {}
	local signature: string? = nil

	local function equipped(data: Types.ProfileData, card: LockerCard): boolean
		return data.Cosmetics.Equipped[card.SlotKey] == card.Id
	end

	local function card(item: CosmeticConfig.CosmeticDef, order: number, parent: Instance): LockerCard
		local holder = blank(item.Id, parent)
		holder.LayoutOrder = order
		local sticker = Sticker.new({
			Kind = "Card",
			Fill = Theme.Colors.PanelRaised,
			Stroke = Theme.Sizes.StrokeThin,
			Parent = holder,
		})
		shelfTrove:Add(function()
			sticker:Destroy()
		end)
		local body = blank("Body", sticker.Face)
		body.Size = UDim2.fromScale(1, 1)
		pad(body, Theme.Sizes.PaddingSmall)
		list(body, Enum.FillDirection.Vertical, Theme.Sizes.PaddingSmall)
		local top = blank("Item", body)
		top.Size = UDim2.new(1, 0, 0, LOCKER_PREVIEW)
		top.LayoutOrder = 1
		local topLayout = list(top, Enum.FillDirection.Horizontal, Theme.Sizes.PaddingSmall)
		topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		local previewFrame = blank("Preview", top)
		previewFrame.Size = UDim2.fromOffset(LOCKER_PREVIEW, LOCKER_PREVIEW)
		previewFrame.LayoutOrder = 1
		ItemPreview.new(item, previewFrame, context.Localize)
		local name = scaledText("Name", Theme.Fonts.Bold, LOCKER_NAME_SIZE, 2, top)
		name.Size = UDim2.new(1, -LOCKER_PREVIEW - Theme.Sizes.PaddingSmall, 1, 0)
		name.TextWrapped = true
		name.Text = t(item.NameKey)

		local slotKey = CosmeticConfig.slotKey(item)
		local entry: LockerCard
		local button = Button.new({
			Text = t("shop.equip"),
			Variant = "Owner",
			Chapter = CHAPTER,
			LayoutOrder = 2,
			Parent = body,
			-- Waits for the server's answer: a second tap before it sent the same equip twice, or, once the
			-- push had landed, took off what the player had just put on.
			OnClick = function()
				local data = context.ClientData.get()
				local wearing = data ~= nil and equipped(data, entry)
				entry.Button:SetPending(true)
				context.RemoteClient.fire("EquipCosmetic", slotKey, if wearing then "" else item.Id)
			end,
			OnTimeout = function()
				context.HudController.showLocalToast("common.pendingTimeout", nil, "Error")
			end,
		})
		shelfTrove:Add(function()
			button:Destroy()
		end)
		entry = { Id = item.Id, SlotKey = slotKey, Button = button }
		return entry
	end

	local function build(data: Types.ProfileData?)
		shelfTrove:Clean()
		table.clear(cards)
		local owned: { [string]: { CosmeticConfig.CosmeticDef } } = {}
		if data ~= nil then
			for _, id in ipairs(data.Cosmetics.Owned) do
				local item = CosmeticConfig.ById[id]
				if item ~= nil then
					local group = owned[item.Slot] or {}
					table.insert(group, item)
					owned[item.Slot] = group
				end
			end
		end
		local order = 0
		for _, slot in ipairs(CosmeticConfig.Slots) do
			local group = owned[slot]
			if group == nil then
				continue
			end
			table.sort(group, function(a, b)
				return t(a.NameKey) < t(b.NameKey)
			end)
			order += 1
			local header = ListRow.new({
				Left = t("cosmetics.slot." .. slot),
				Variant = "Header",
				Chapter = CHAPTER,
				LayoutOrder = order,
				Parent = context.Content,
			})
			shelfTrove:Add(function()
				header:Destroy()
			end)
			order += 1
			local grid = blank(slot, context.Content)
			grid.AutomaticSize = Enum.AutomaticSize.Y
			grid.Size = UDim2.fromScale(1, 0)
			grid.LayoutOrder = order
			shelfTrove:Add(grid)
			local gridLayout = Instance.new("UIGridLayout")
			gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
			-- The card's button carries the touch minimum, which a phone makes taller than designed.
			gridLayout.CellSize = UDim2.fromOffset(
				LOCKER_CELL.X,
				LOCKER_CELL.Y + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight) - Theme.Sizes.ButtonHeight
			)
			gridLayout.CellPadding = UDim2.fromOffset(Theme.Sizes.Gap, Theme.Sizes.Gap)
			gridLayout.Parent = grid
			for index, item in ipairs(group) do
				table.insert(cards, card(item, index, grid))
			end
		end
		if order == 0 then
			local empty = ListRow.new({
				Left = t("shop.locker.empty"),
				Variant = "Empty",
				LayoutOrder = 1,
				Parent = context.Content,
			})
			shelfTrove:Add(function()
				empty:Destroy()
			end)
		end
	end

	local function refresh()
		local data = context.ClientData.get()
		local owned = if data ~= nil then table.concat(data.Cosmetics.Owned, "|") else ""
		if owned ~= signature then
			signature = owned
			build(data)
		end
		if data == nil then
			return
		end
		for _, entry in ipairs(cards) do
			local wearing = equipped(data, entry)
			entry.Button:SetVariant(if wearing then "Secondary" else "Owner")
			entry.Button:SetText(if wearing then t("shop.unequip") else t("shop.equip"))
		end
	end
	refresh()

	return {
		Refresh = refresh,
		Focus = function(): GuiObject?
			local first = cards[1]
			return if first ~= nil then first.Button.Instance else nil
		end,
		Settle = function()
			for _, entry in ipairs(cards) do
				entry.Button:SetPending(false)
			end
		end,
	}
end

return Shelves
