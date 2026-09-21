--!strict
-- ShopScreen: today's cosmetic rotation, one card per entry (name, rarity, Folios price, Robux action).
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
local Panel = require(script.Parent.Parent.components.Panel)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local ShopConfig = require(Shared.Config.ShopConfig)
local ShopRotation = require(Shared.Pure.ShopRotation)
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
	OnClose: () -> (),
	OnNavigate: (id: string) -> (),
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type Destroyable = { Destroy: (self: any) -> () }
type Entry = Types.ShopEntry
type Card = { Entry: Entry, SlotKey: string, Buy: Button.Button, Action: Button.Button }

local ShopScreen = {}

local OVERLAY_TRANSPARENCY = 0.45
local NAME_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local RARITY_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local STATUS_HEIGHT = Theme.Sizes.TextBody + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2 + STATUS_HEIGHT
local RARITY_KEY_PREFIX = "shop.rarity."

-- Rotation candidates: the pure selector only needs the id, rarity and sellable flag of each item.
local CANDIDATES: { ShopRotation.Item } = {}
for _, item in ipairs(CosmeticConfig.Items) do
	table.insert(CANDIDATES, { Id = item.Id, Rarity = item.Rarity :: string, Sellable = item.Sellable })
end

-- Dimmed backdrop that also swallows clicks so the world under the menu is not interacted with.
local function makeOverlay(parent: Instance): Frame
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = Theme.Colors.Overlay
	overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Active = true
	overlay.Parent = parent
	return overlay
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

local function makeLine(
	name: string,
	height: number,
	size: number,
	bold: boolean,
	color: Color3,
	order: number,
	parent: Instance
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.LayoutOrder = order
	label.FontFace = if bold then Theme.Fonts.Bold else Theme.Fonts.Body
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

function ShopScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local cardsTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen
	local cards: { Card } = {}
	local snapshot: Types.ShopSnapshot = localSnapshot()
	local signature = ""
	local firstButton: GuiObject? = nil

	local root = ScreenRoot.new({ Name = "ShopScreen", DisplayOrder = Theme.Layers.Screen })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("shop.title"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	panel:SetHeaderHeight(HEADER_HEIGHT)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	-- The two header columns share the width: the rotation title on the left, the Folios balance on the right.
	local rotationLabel =
		makeLine("Rotation", STATUS_HEIGHT, Theme.Sizes.TextBody, true, Theme.Colors.TextMuted, 1, panel.Header)
	rotationLabel.Text = t("shop.rotation")
	local balanceLabel =
		makeLine("Balance", STATUS_HEIGHT, Theme.Sizes.TextBody, true, Theme.Colors.Accent, 2, panel.Header)
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
	for _, label in ipairs({ rotationLabel, balanceLabel }) do
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = label
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

	local function buyWithFolios(entry: Entry)
		deps.SoundController.play("UiClick")
		deps.RemoteClient.fire("BuyCosmetic", entry.CosmeticId)
	end

	-- The client never sends a Roblox asset id: it names the developer product of the entry's rarity.
	local function buyWithRobux(entry: Entry)
		deps.SoundController.play("UiClick")
		deps.RemoteClient.fire("PromptPurchase", "Cosmetic", entry.CosmeticId)
	end

	local function equip(card: Card)
		deps.SoundController.play("UiClick")
		deps.RemoteClient.fire("EquipCosmetic", card.SlotKey, card.Entry.CosmeticId)
	end

	----------------------------------------------------------------
	-- Cards
	----------------------------------------------------------------

	local function buildCard(entry: Entry, slotKey: string, layoutOrder: number): Card
		local frame = Instance.new("Frame")
		frame.Name = entry.CosmeticId
		frame.BackgroundColor3 = Theme.Colors.PanelRaised
		frame.BorderSizePixel = 0
		-- Grown from its rows: the two action buttons carry the touch minimum and are taller than their
		-- design height on a phone, and the card has to follow instead of clipping them.
		frame.Size = UDim2.fromScale(1, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.LayoutOrder = layoutOrder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
		corner.Parent = frame

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
		padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
		padding.PaddingTop = UDim.new(0, Theme.Sizes.PaddingSmall)
		padding.PaddingBottom = UDim.new(0, Theme.Sizes.PaddingSmall)
		padding.Parent = frame

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame

		local name = makeLine("Name", NAME_HEIGHT, Theme.Sizes.TextLarge, true, Theme.Colors.Text, 1, frame)
		name.Text = t(entry.NameKey)
		local rarity = makeLine("Rarity", RARITY_HEIGHT, Theme.Sizes.TextSmall, false, Theme.Colors.TextMuted, 2, frame)
		rarity.Text = t(RARITY_KEY_PREFIX .. entry.Rarity)

		local actions = Instance.new("Frame")
		actions.Name = "Actions"
		actions.BackgroundTransparency = 1
		actions.Size = UDim2.fromScale(1, 0)
		actions.AutomaticSize = Enum.AutomaticSize.Y
		actions.LayoutOrder = 3
		local actionsLayout = Instance.new("UIListLayout")
		actionsLayout.FillDirection = Enum.FillDirection.Horizontal
		actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		actionsLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
		actionsLayout.Parent = actions
		local actionsPadding = Instance.new("UIPadding")
		actionsPadding.PaddingTop = UDim.new(0, Theme.Sizes.Gap)
		actionsPadding.Parent = actions
		actions.Parent = frame

		local card: Card
		-- Width comes from the flex item, height from the button itself: the Actions frame is sized by its
		-- children, so a button asking for the frame's height would make the pair circular.
		local buy = Button.new({
			Text = "",
			Variant = "Primary",
			Size = UDim2.fromOffset(0, Theme.Sizes.RowHeight),
			LayoutOrder = 1,
			Parent = actions,
			OnClick = function()
				buyWithFolios(entry)
			end,
		})
		own(cardsTrove, buy)
		local buyFlex = Instance.new("UIFlexItem")
		buyFlex.FlexMode = Enum.UIFlexMode.Fill
		buyFlex.Parent = buy.Instance

		local action = Button.new({
			Text = "",
			Variant = "Secondary",
			Size = UDim2.fromOffset(0, Theme.Sizes.RowHeight),
			LayoutOrder = 2,
			Parent = actions,
			OnClick = function()
				if isOwned(card.Entry) then
					equip(card)
				else
					buyWithRobux(card.Entry)
				end
			end,
		})
		own(cardsTrove, action)
		local actionFlex = Instance.new("UIFlexItem")
		actionFlex.FlexMode = Enum.UIFlexMode.Fill
		actionFlex.Parent = action.Instance

		frame.Parent = panel.Content
		cardsTrove:Add(frame)
		card = { Entry = entry, SlotKey = slotKey, Buy = buy, Action = action }
		return card
	end

	local function updateCard(card: Card)
		local entry = card.Entry
		if isOwned(entry) then
			card.Buy:SetText(t("shop.owned"))
			card.Buy:SetVariant("Secondary")
			card.Buy:SetDisabled(true)
			if isEquipped(card) then
				card.Action:SetText(t("shop.equipped"))
				card.Action:SetVariant("Secondary")
				card.Action:SetDisabled(true)
			else
				card.Action:SetText(t("shop.equip"))
				card.Action:SetVariant("Primary")
				card.Action:SetDisabled(false)
			end
			return
		end
		card.Buy:SetText(t("shop.buyFolios", { price = entry.PriceFolios }))
		card.Buy:SetVariant("Primary")
		card.Buy:SetDisabled(false)
		card.Action:SetText(t("shop.buyRobux"))
		card.Action:SetVariant("Secondary")
		-- No product configured for that rarity: the Robux path is simply not offered.
		card.Action:SetDisabled(entry.ProductKey == "")
	end

	local function signatureOf(current: Types.ShopSnapshot): string
		local parts = { current.DayKey }
		for _, entry in ipairs(current.Entries) do
			table.insert(parts, entry.CosmeticId)
		end
		return table.concat(parts, "|")
	end

	local function rebuild()
		cardsTrove:Clean()
		cards = {}
		for index, entry in ipairs(snapshot.Entries) do
			local item = CosmeticConfig.ById[entry.CosmeticId]
			if item == nil then
				continue
			end
			table.insert(cards, buildCard(entry, CosmeticConfig.slotKey(item), index))
		end
	end

	local function refresh()
		local data = deps.ClientData.get()
		balanceLabel.Text = if data ~= nil
			then t("shop.buyFolios", { price = math.floor(data.Currency.Folios) })
			else ""
		local wanted = signatureOf(snapshot)
		if wanted ~= signature then
			signature = wanted
			rebuild()
		end
		firstButton = nil
		for _, card in ipairs(cards) do
			updateCard(card)
			-- Gamepad focus goes to the first button the player can actually press.
			if firstButton == nil then
				if not card.Buy:IsDisabled() then
					firstButton = card.Buy.Instance
				elseif not card.Action:IsDisabled() then
					firstButton = card.Action.Instance
				end
			end
		end
	end

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
		if section == "*" or section == "Cosmetics" or section == "Currency" then
			refresh()
		end
	end)

	refresh()

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		adoptSnapshot()
		root.Instance.Enabled = true
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		panel:ReleaseGamepadFocus()
		root.Instance.Enabled = false
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = close,
		Destroy = destroy,
	}
	return screen
end

return ShopScreen
