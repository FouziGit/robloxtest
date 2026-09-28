--!strict
-- ShopScreen: the shop (D-147), in the green Shop chapter, in four tabs: today's rotation, the Folios
-- packs, the passes and packs, and the locker of what the player owns (the last three are shop/Shelves).
-- Today is a track of item cards, the Legendary first and twice as wide: each wears its rarity (colour,
-- pips and word, since colour is never the only cue), a preview of what it looks like, its name, a Folios
-- price and a Robux one. The Folios price asks first, in a sheet (shop/Purchase): nothing is bought on one
-- tap. The band holds the live Folios count; under Today's tab a line counts down to the next rotation.
-- Opened with { Tab = "Folios" } (the Menu's "+", the sheet of a player short of Folios), it opens there.
--
-- The rotation comes from the server's ShopChanged snapshot; until one arrives (screens are built on
-- their first Open, after the join-time push) the same deterministic rotation is derived locally from
-- ShopRotation over the sellable CosmeticConfig items, so the card list is never empty. Prices and
-- product keys of a server snapshot win over the local fallback.
--
-- Ownership and the equipped slot are always read from the profile, which the server pushes: buying or
-- equipping updates the cards through ProfileChanged, never from a local guess. The screen only names
-- catalog entries: BuyCosmetic for the Folios path, PromptPurchase for the Robux one, EquipCosmetic to
-- wear what is already owned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local FoliosPill = require(script.Parent.Parent.components.FoliosPill)
local Icon = require(script.Parent.Parent.components.Icon)
local ItemPreview = require(script.Parent.Parent.components.ItemPreview)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Panel = require(script.Parent.Parent.components.Panel)
local Purchase = require(script.Parent.shop.Purchase)
local RarityRibbon = require(script.Parent.Parent.components.RarityRibbon)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Shelves = require(script.Parent.shop.Shelves)
local ShopConfig = require(Shared.Config.ShopConfig)
local ShopRotation = require(Shared.Pure.ShopRotation)
local Sticker = require(script.Parent.Parent.components.Sticker)
local Tabs = require(script.Parent.Parent.components.Tabs)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: {
		fire: (name: string, ...any) -> (),
		on: (name: string, handler: (...any) -> ()) -> RBXScriptConnection,
	},
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	-- A purchase's refusal arrives as a server message (Notified); a purchase that never hears back says
	-- so on the HUD's toast column.
	HudController: {
		Notified: any,
		showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> (),
	},
	OnClose: () -> (),
	OnNavigate: (id: string, args: any?) -> (),
	OnBack: () -> (),
	CanGoBack: () -> boolean,
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen, args: any?) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type Destroyable = { Destroy: (self: any) -> () }
type Entry = Types.ShopEntry
type Card = { Entry: Entry, SlotKey: string, Buy: Button.Button, Action: Button.Button }
type TabId = "Today" | "Folios" | "Passes" | "Locker"

local ShopScreen = {}

local CHAPTER = "Shop"
-- An item card with a pointer; a Legendary is two of them wide. On a phone the card takes the height the
-- track has, which leaves no room for its two prices one over the other (they took the whole preview, and
-- the Robux one hung under the card): it is as wide as the two side by side need, the longest price
-- included (tests/ShopEquip.spec.luau), and its preview keeps at least PREVIEW_MIN.
local CARD_WIDTH = 260
local CARD_WIDTH_TOUCH = 400
local CARD_HEIGHT = 330
local PREVIEW_MIN = 32
local CARD_PADDING = 12
local CARD_ELEVATION = 5
local NAME_SIZE = 20
local MIN_SCALED_TEXT = 14
local LEGENDARY_RIM = 3
local LINE_HEIGHT = 32
local CLOCK_SIZE = 22
local PILL_HEIGHT = 40
local TABS_HEIGHT = 48
-- The tabs, in order, and the way each lays its content out: the cards scroll sideways, the lists down.
local TAB_ORDER: { TabId } = { "Today", "Folios", "Passes", "Locker" }
local TAB_KEYS: { [string]: string } = {
	Today = "shop.tab.today",
	Folios = "shop.tab.folios",
	Passes = "shop.tab.passes",
	Locker = "shop.tab.locker",
}
local TAB_MODES: { [string]: Panel.ContentMode } =
	{ Today = "Track", Folios = "Track", Passes = "List", Locker = "List" }
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 3600

-- Whether a Robux product can be bought: it is configured, and it exists on Roblox (a non-zero id).
local function robuxOffered(productKey: string): boolean
	local product = MonetizationConfig.Products[productKey]
	return product ~= nil and product.Id ~= 0
end

-- Rotation candidates: the pure selector only needs the id, rarity and sellable flag of each item.
local CANDIDATES: { ShopRotation.Item } = {}
for _, item in ipairs(CosmeticConfig.Items) do
	table.insert(CANDIDATES, { Id = item.Id, Rarity = item.Rarity :: string, Sellable = item.Sellable })
end

-- Where each rarity stands in the track: the Legendary first.
local RARITY_RANK: { [string]: number } = {}
for index, rarity in ipairs(ShopConfig.RarityOrder) do
	RARITY_RANK[rarity] = index
end

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

local function finite(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.floor(value)
end

local function entryFor(
	item: CosmeticConfig.CosmeticDef,
	priceFolios: number,
	productKey: string,
	owned: boolean
): Entry
	return {
		CosmeticId = item.Id,
		NameKey = item.NameKey,
		Slot = item.Slot,
		Rarity = item.Rarity,
		PriceFolios = priceFolios,
		ProductKey = productKey,
		Owned = owned,
	}
end

-- Same inputs as the server's rotation: the day key of the UTC day and the ShopConfig slot counts.
local function localSnapshot(): Types.ShopSnapshot
	local dayKey = ShopRotation.dayKey(os.time())
	local entries: { Entry } = {}
	local ids = ShopRotation.select(CANDIDATES, dayKey, ShopConfig.Rotation, ShopConfig.RarityOrder)
	for _, id in ipairs(ids) do
		local item = CosmeticConfig.ById[id]
		if item ~= nil then
			-- Same rule as the server: a rarity without a price or without a Robux product is not offered.
			local price = ShopConfig.PriceFolios[item.Rarity]
			local productKey = ShopConfig.RobuxProduct[item.Rarity]
			if price ~= nil and productKey ~= nil then
				table.insert(entries, entryFor(item, price, productKey, false))
			end
		end
	end
	return { DayKey = dayKey, Entries = entries }
end

-- Server payloads are sanitized: the catalog resolves the display data, the payload only carries the
-- ids, the prices and the product keys.
local function readSnapshot(payload: any): Types.ShopSnapshot?
	if type(payload) ~= "table" or type(payload.DayKey) ~= "string" or type(payload.Entries) ~= "table" then
		return nil
	end
	local entries: { Entry } = {}
	for _, raw in ipairs(payload.Entries) do
		if type(raw) == "table" and type(raw.CosmeticId) == "string" then
			local item = CosmeticConfig.ById[raw.CosmeticId]
			if item ~= nil then
				local price = math.max(0, finite(raw.PriceFolios, ShopConfig.PriceFolios[item.Rarity] or 0))
				local product = if type(raw.ProductKey) == "string"
					then raw.ProductKey
					else ShopConfig.RobuxProduct[item.Rarity] or ""
				table.insert(entries, entryFor(item, price, product, raw.Owned == true))
			end
		end
	end
	return { DayKey = payload.DayKey, Entries = entries }
end

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
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
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

local function textLabel(name: string, font: Font, size: number, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, size + 6)
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Text = ""
	label.Parent = parent
	return label
end

function ShopScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local pageTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen
	local cards: { Card } = {}
	local snapshot: Types.ShopSnapshot = localSnapshot()
	local signature = ""
	local firstButton: GuiObject? = nil
	local tab: TabId = "Today"
	local shelf: Shelves.Shelf? = nil
	-- Bumped at every Open and Close, so a countdown scheduled for an earlier visit stops.
	local visit = 0

	local root = ScreenRoot.new({
		Name = "ShopScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("shop.title"),
		Chapter = CHAPTER,
		ContentMode = "Track",
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		OnBack = deps.OnBack,
		ShowBack = deps.CanGoBack,
		Localize = deps.Localize,
		Parent = root.Content,
	})
	own(trove, panel)
	root:SetCard(panel)
	local content = panel.Content

	----------------------------------------------------------------
	-- The band's Folios, the tabs, and the countdown to the next rotation
	----------------------------------------------------------------

	local pill = FoliosPill.new({ Height = PILL_HEIGHT, Parent = panel.Right })
	own(trove, pill)

	-- The tabs, and under Today's the countdown; the tabs carry the touch minimum, which follows the viewport.
	local function headerHeight(): number
		local height = Theme.Sizes.PaddingSmall * 2 + Theme.touchTargetHeight(TABS_HEIGHT)
		if tab == "Today" then
			height += Theme.Sizes.PaddingSmall + LINE_HEIGHT
		end
		return height
	end
	list(panel.Header, Enum.FillDirection.Vertical, Theme.Sizes.PaddingSmall)

	local rotationLine = blank("Rotation", panel.Header)
	rotationLine.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
	rotationLine.LayoutOrder = 2
	list(rotationLine, Enum.FillDirection.Horizontal, Theme.Sizes.PaddingSmall)
	local clock = Icon.new("Clock", CLOCK_SIZE, Theme.Colors.TextMuted)
	clock.LayoutOrder = 1
	clock.Parent = rotationLine
	local rotationText = textLabel("Text", Theme.Fonts.Bold, Theme.Sizes.TextBody, 2, rotationLine)
	rotationText.TextColor3 = Theme.Colors.TextMuted

	local function refreshCountdown()
		local now = workspace:GetServerTimeNow()
		local left = math.max(0, ShopRotation.nextRotationAt(now) - now)
		local time = t("time.hoursMinutes", {
			hours = math.floor(left / SECONDS_PER_HOUR),
			minutes = math.floor(left % SECONDS_PER_HOUR / SECONDS_PER_MINUTE),
		})
		rotationText.Text = t("shop.nextRotation", { time = time })
	end

	-- Once a minute, on the minute, while the screen is up.
	local function scheduleCountdown(token: number)
		local now = workspace:GetServerTimeNow()
		task.delay(SECONDS_PER_MINUTE - now % SECONDS_PER_MINUTE, function()
			if token ~= visit or not screen.Visible then
				return
			end
			refreshCountdown()
			scheduleCountdown(token)
		end)
	end

	----------------------------------------------------------------
	-- Profile reads
	----------------------------------------------------------------

	local function isOwned(entry: Entry): boolean
		if entry.Owned then
			return true
		end
		local data = deps.ClientData.get()
		if data == nil then
			return false
		end
		return table.find(data.Cosmetics.Owned, entry.CosmeticId) ~= nil
	end

	local function isEquipped(card: Card): boolean
		local data = deps.ClientData.get()
		if data == nil then
			return false
		end
		return data.Cosmetics.Equipped[card.SlotKey] == card.Entry.CosmeticId
	end

	----------------------------------------------------------------
	-- Intent
	----------------------------------------------------------------

	local tabs: Tabs.Tabs
	-- A tab the player picks clicks, like every tab strip; a switch the screen makes itself (Open's Tab, the
	-- sheet's Get Folios, whose button has already clicked) is quiet.
	local switching = false
	local purchases = Purchase.new({
		Localize = deps.Localize,
		ClientData = deps.ClientData,
		RemoteClient = deps.RemoteClient,
		HudController = deps.HudController,
		Card = panel.Instance,
		ShowFolios = function()
			switching = true
			tabs:Select("Folios")
			switching = false
		end,
	})
	own(trove, purchases)

	-- The client never sends a Roblox asset id: it names the developer product of the entry's rarity.
	local function buyWithRobux(entry: Entry)
		deps.RemoteClient.fire("PromptPurchase", "Cosmetic", entry.CosmeticId)
	end

	-- Waits for the server's answer, which it pushes on every path (a refusal too): a second tap before it
	-- sent the same equip twice.
	local function equip(card: Card)
		card.Buy:SetPending(true)
		deps.RemoteClient.fire("EquipCosmetic", card.SlotKey, card.Entry.CosmeticId)
	end

	-- The Cosmetics push that answers an equip: every button waiting on one is let go.
	local function settleEquips()
		for _, card in ipairs(cards) do
			card.Buy:SetPending(false)
		end
		local current = shelf
		local settle = if current ~= nil then current.Settle else nil
		if settle ~= nil then
			settle()
		end
	end

	----------------------------------------------------------------
	-- Today's cards
	----------------------------------------------------------------

	local function buildCard(entry: Entry, item: CosmeticConfig.CosmeticDef, layoutOrder: number): Card
		local legendary = entry.Rarity == "Legendary"
		local touch = Theme.touchOnly()
		local single = if touch then CARD_WIDTH_TOUCH else CARD_WIDTH
		local width = if legendary then single * 2 + Theme.Sizes.Gap else single
		local holder = blank(entry.CosmeticId, content)
		holder.LayoutOrder = layoutOrder
		-- A phone gives the card the height it has; a pointer the designed one.
		holder.Size = if touch
			then UDim2.new(0, width, 1, -Theme.Sizes.PaddingSmall)
			else UDim2.fromOffset(width, CARD_HEIGHT)
		pageTrove:Add(holder)
		local sticker = Sticker.new({
			Kind = "Card",
			Fill = Theme.Colors.PanelRaised,
			Elevation = CARD_ELEVATION,
			Parent = holder,
		})
		own(pageTrove, sticker)
		local face = sticker.Face
		if legendary then
			-- Full gold leaf: the rim of the one legendary in the rotation.
			local rim = blank("Rim", face)
			rim.Size = UDim2.fromScale(1, 1)
			rim.ZIndex = 6
			Theme.corner(rim, UDim.new(0, Theme.Sizes.CornerCard))
			Theme.stroke(rim, "Primary", LEGENDARY_RIM)
		end

		local body = blank("Body", face)
		body.Size = UDim2.fromScale(1, 1)
		pad(body, CARD_PADDING)
		list(body, Enum.FillDirection.Vertical, Theme.Sizes.PaddingSmall)

		local well = blank("Preview", body)
		well.BackgroundTransparency = 0
		well.BackgroundColor3 = Theme.Colors.Panel
		well.Size = UDim2.fromScale(1, 0)
		well.LayoutOrder = 1
		Theme.corner(well, UDim.new(0, Theme.Sizes.CornerChip))
		local wellFlex = Instance.new("UIFlexItem")
		wellFlex.FlexMode = Enum.UIFlexMode.Fill
		wellFlex.Parent = well
		local wellFloor = Instance.new("UISizeConstraint")
		wellFloor.MinSize = Vector2.new(0, PREVIEW_MIN)
		wellFloor.Parent = well
		ItemPreview.new(item, well, deps.Localize)
		local ribbon = RarityRibbon.new(entry.Rarity, t(Theme.rarity(entry.Rarity).WordKey), face)
		own(pageTrove, ribbon)

		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0, NAME_SIZE + 6)
		name.LayoutOrder = 2
		name.FontFace = Theme.Fonts.Title
		name.TextScaled = true
		name.TextColor3 = Theme.Colors.Text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = t(entry.NameKey)
		local cap = Instance.new("UITextSizeConstraint")
		cap.MinTextSize = MIN_SCALED_TEXT
		cap.MaxTextSize = NAME_SIZE
		cap.Parent = name
		name.Parent = body

		-- The two prices side by side where they fit, one over the other where they do not.
		local actions = blank("Actions", body)
		actions.AutomaticSize = Enum.AutomaticSize.Y
		actions.Size = UDim2.fromScale(1, 0)
		actions.LayoutOrder = 3
		local actionsLayout = list(actions, Enum.FillDirection.Horizontal, Theme.Sizes.PaddingSmall)
		actionsLayout.Wraps = true
		actionsLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill

		local card: Card
		local buyButton = Button.new({
			Text = "",
			Variant = "Primary",
			Chapter = CHAPTER,
			Icon = "Coin",
			LayoutOrder = 1,
			Parent = actions,
			OnClick = function()
				if isOwned(card.Entry) then
					equip(card)
				else
					purchases:Ask(card.Entry)
				end
			end,
			OnTimeout = function()
				deps.HudController.showLocalToast("common.pendingTimeout", nil, "Error")
			end,
		})
		own(pageTrove, buyButton)

		local product = MonetizationConfig.Products[entry.ProductKey]
		local action = Button.new({
			Text = t("shop.robuxPrice", { price = if product ~= nil then product.PriceRobux else 0 }),
			Variant = "Secondary",
			LayoutOrder = 2,
			Parent = actions,
			OnClick = function()
				buyWithRobux(card.Entry)
			end,
		})
		own(pageTrove, action)

		card = { Entry = entry, SlotKey = CosmeticConfig.slotKey(item), Buy = buyButton, Action = action }
		return card
	end

	local function updateCard(card: Card)
		local entry = card.Entry
		if isOwned(entry) then
			-- Owned: the price becomes the way to wear it, and wearing it is the end of the road.
			card.Buy:SetVariant("Owner")
			card.Buy:SetText(t("shop.equip"))
			card.Buy:SetDisabled(isEquipped(card), "Owned", t("shop.equipped"))
			card.Action.Instance.Visible = false
			return
		end
		card.Buy:SetVariant("Primary")
		card.Buy:SetText(t("shop.buyFolios", { price = entry.PriceFolios }))
		card.Buy:SetDisabled(false)
		card.Action.Instance.Visible = true
		-- The Robux path is offered only for a product that exists on Roblox (D-128): an id of 0 is one nobody
		-- has created yet, and buying it can only fail -- which, in Studio, is every one of them.
		card.Action:SetDisabled(not robuxOffered(entry.ProductKey))
	end

	local function signatureOf(current: Types.ShopSnapshot): string
		local parts = { current.DayKey }
		for _, entry in ipairs(current.Entries) do
			table.insert(parts, entry.CosmeticId)
		end
		return table.concat(parts, "|")
	end

	local function buildToday()
		cards = {}
		local entries = table.clone(snapshot.Entries)
		table.sort(entries, function(a: Entry, b: Entry): boolean
			return (RARITY_RANK[a.Rarity] or math.huge) < (RARITY_RANK[b.Rarity] or math.huge)
		end)
		for index, entry in ipairs(entries) do
			local item = CosmeticConfig.ById[entry.CosmeticId]
			if item ~= nil then
				table.insert(cards, buildCard(entry, item, index))
			end
		end
	end

	----------------------------------------------------------------
	-- Tabs
	----------------------------------------------------------------

	-- Tears the page down and builds `next` in its place, in its own layout.
	local function show(next: TabId)
		tab = next
		pageTrove:Clean()
		cards = {}
		shelf = nil
		signature = ""
		panel:SetContentMode(TAB_MODES[next])
		if TAB_MODES[next] == "Track" then
			-- A track's canvas is as tall as its window: a card takes that height, and only scrolls sideways.
			content.CanvasSize = UDim2.fromScale(0, 1)
		end
		rotationLine.Visible = next == "Today"
		-- The header's height follows the countdown line in or out.
		panel:SetHeaderHeight(headerHeight)
		if next == "Today" then
			return
		end
		local context: Shelves.Context = {
			Localize = deps.Localize,
			ClientData = deps.ClientData,
			RemoteClient = deps.RemoteClient,
			Content = content,
			Trove = pageTrove,
			RobuxOffered = robuxOffered,
			HudController = deps.HudController,
		}
		if next == "Folios" then
			shelf = Shelves.folios(context)
		elseif next == "Passes" then
			shelf = Shelves.passes(context)
		else
			shelf = Shelves.locker(context)
		end
	end

	local items: { Tabs.Item } = {}
	for _, id in ipairs(TAB_ORDER) do
		table.insert(items, { Id = id, Text = t(TAB_KEYS[id]) })
	end

	----------------------------------------------------------------
	-- Refresh
	----------------------------------------------------------------

	local function refresh()
		local data = deps.ClientData.get()
		if data ~= nil then
			pill:Set(data.Currency.Folios, screen.Visible)
		end
		purchases:Refresh()
		local current = shelf
		if current ~= nil then
			current.Refresh()
			firstButton = current.Focus()
			return
		end
		local wanted = signatureOf(snapshot)
		if wanted ~= signature then
			signature = wanted
			pageTrove:Clean()
			buildToday()
		end
		firstButton = nil
		for _, card in ipairs(cards) do
			updateCard(card)
			-- Gamepad focus goes to the first button the player can actually press.
			if firstButton == nil then
				if not card.Buy:IsDisabled() then
					firstButton = card.Buy.Instance
				elseif card.Action.Instance.Visible and not card.Action:IsDisabled() then
					firstButton = card.Action.Instance
				end
			end
		end
	end

	tabs = Tabs.new({
		Items = items,
		Selected = tab,
		Chapter = CHAPTER,
		LayoutOrder = 1,
		Parent = panel.Header,
		OnSelect = function(id: string)
			if not switching then
				deps.SoundController.play("UiClick")
			end
			show(id :: TabId)
			refresh()
		end,
	})
	own(trove, tabs)

	-- A rotation from another day (the screen stayed alive across the UTC rollover) is replaced by the
	-- one of the current day until the server pushes its own.
	local function adoptSnapshot()
		if snapshot.DayKey ~= ShopRotation.dayKey(os.time()) then
			snapshot = localSnapshot()
		end
		refresh()
	end

	trove:Add(deps.RemoteClient.on("ShopChanged", function(payload: any)
		local received = readSnapshot(payload)
		if received == nil or #received.Entries == 0 then
			return -- a malformed or empty push leaves the rotation on screen untouched
		end
		snapshot = received
		refresh()
	end))

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Cosmetics" then
			settleEquips()
		end
		if
			section == "*"
			or section == "Cosmetics"
			or section == "Currency"
			or section == "Passes"
			or section == "Battlepass"
		then
			refresh()
		end
	end)

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen, args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		visit += 1
		local wanted: TabId = "Today"
		if type(args) == "table" and TAB_KEYS[args.Tab] ~= nil then
			wanted = args.Tab
		end
		if wanted ~= tab then
			switching = true
			tabs:Select(wanted)
			switching = false
		end
		adoptSnapshot()
		refreshCountdown()
		scheduleCountdown(visit)
		root:PlayEnter()
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		visit += 1
		purchases:Close()
		panel:ReleaseGamepadFocus()
		root:PlayExit()
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		visit += 1
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = close,
		Destroy = destroy,
	}
	show(tab)
	refresh()
	return screen
end

return ShopScreen
