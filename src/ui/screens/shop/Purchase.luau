--!strict
-- Purchase: a Folios purchase in the Shop (D-147). Nothing is bought on one tap: a card's price asks first,
-- in a sheet that slides up over the card -- the item again, and the balance before and after. Short of
-- Folios, the balance line turns the red only large text may wear, Buy says why it waits, and the way to
-- more Folios sits under it. Buy then waits for the server: the item turning up in the profile flashes the
-- button, stamps the item "Acquired!" and bursts, and the sheet goes; a refusal (the server's toast says
-- which) shakes the button; no answer at all says so. Only the sheet's own confirmation sends BuyCosmetic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Burst = require(script.Parent.Parent.Parent.components.Burst)
local Button = require(script.Parent.Parent.Parent.components.Button)
local ConfirmSheet = require(script.Parent.Parent.Parent.components.ConfirmSheet)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ItemPreview = require(script.Parent.Parent.Parent.components.ItemPreview)
local Seal = require(script.Parent.Parent.Parent.components.Seal)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Context = {
	Localize: Localizer,
	ClientData: { get: () -> Types.ProfileData? },
	RemoteClient: { fire: (name: string, ...any) -> () },
	HudController: {
		Notified: any,
		showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> (),
	},
	-- The screen's card: the sheet rises over it.
	Card: GuiObject,
	-- Where the sheet sends a player short of Folios: the Shop's Folios tab.
	ShowFolios: () -> (),
}

export type Purchases = {
	-- Opens the sheet for `entry`, unless one is already open.
	Ask: (self: Purchases, entry: Types.ShopEntry) -> (),
	-- The profile changed: the item waited for may have arrived.
	Refresh: (self: Purchases) -> (),
	-- Takes the sheet away, whatever it was doing.
	Close: (self: Purchases) -> (),
	Destroy: (self: Purchases) -> (),
}

-- A purchase on its way: the sheet that asked, where its item is drawn, and the item the profile has to show.
type Pending = { Sheet: ConfirmSheet.ConfirmSheet, Preview: Frame, CosmeticId: string, Waiting: boolean }

local Purchase = {}

local SWATCH = 56
local BALANCE_SIZE = 22
local STAMP_SIZE = 96
-- How long the stamp shows before the sheet goes.
local ACQUIRED_SECONDS = 1.2

local function blank(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function list(frame: Frame, direction: Enum.FillDirection)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = frame
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
	label.Parent = parent
	return label
end

function Purchase.new(context: Context): Purchases
	local trove = Trove.new()
	local t = context.Localize.t
	local current: Pending? = nil

	local function balance(): number
		local data = context.ClientData.get()
		return if data ~= nil then math.floor(data.Currency.Folios) else 0
	end

	local function close()
		local open = current
		current = nil
		if open ~= nil then
			open.Sheet:Close()
		end
	end
	trove:Add(function()
		local open = current
		current = nil
		if open ~= nil then
			open.Sheet:Destroy()
		end
	end)

	local function settle(pending: Pending)
		pending.Waiting = false
		pending.Sheet.ConfirmButton:SetPending(false)
	end

	-- The item is in the profile: the button flashes, the stamp comes down, the blots burst, the sheet goes.
	local function acquired(pending: Pending)
		settle(pending)
		pending.Sheet.ConfirmButton:Flash("Success")
		Seal.new({
			Text = t("shop.acquired"),
			Fill = Theme.Colors.SuccessFill,
			Size = STAMP_SIZE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Stamp = true,
			Parent = pending.Preview,
		})
		Burst.play(pending.Preview, { Theme.Colors.SuccessFill, Theme.Colors.Primary, Theme.Colors.SuccessFill })
		task.delay(ACQUIRED_SECONDS, function()
			if current == pending then
				close()
			end
		end)
	end

	local function buy(pending: Pending)
		if pending.Waiting then
			return
		end
		pending.Waiting = true
		pending.Sheet.ConfirmButton:SetPending(true)
		context.RemoteClient.fire("BuyCosmetic", pending.CosmeticId)
		-- No answer in time: the button gives up by itself, and the player is told why.
		task.delay(Theme.Timing.PendingTimeoutSeconds, function()
			if current == pending and pending.Waiting then
				settle(pending)
				context.HudController.showLocalToast("common.pendingTimeout", nil, "Error")
			end
		end)
	end

	local function ask(_self: Purchases, entry: Types.ShopEntry)
		if current ~= nil then
			return
		end
		local item = CosmeticConfig.ById[entry.CosmeticId]
		if item == nil then
			return
		end
		local before = balance()
		local after = before - entry.PriceFolios
		local short = after < 0

		-- The item again, and what the purchase does to the balance.
		local body = blank("Preview")
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.fromScale(1, 0)
		list(body, Enum.FillDirection.Vertical)
		local itemRow = blank("Item", body)
		itemRow.Size = UDim2.new(1, 0, 0, SWATCH)
		itemRow.LayoutOrder = 1
		list(itemRow, Enum.FillDirection.Horizontal)
		local swatch = blank("Swatch", itemRow)
		swatch.Size = UDim2.fromOffset(SWATCH, SWATCH)
		swatch.LayoutOrder = 1
		ItemPreview.new(item, swatch, context.Localize)
		local name = textLabel("Name", Theme.Fonts.Bold, Theme.Sizes.TextButton, 2, itemRow)
		name.Text = t(entry.NameKey)
		local line = textLabel("Balance", Theme.Fonts.Numeric, BALANCE_SIZE, 2, body)
		line.Text = t("shop.confirm.balance", { before = before, after = after })
		line.TextColor3 = if short then Theme.Colors.Danger else Theme.Colors.Text
		if short then
			local more = Button.new({
				Text = t("shop.getFolios"),
				Variant = "Secondary",
				Icon = "Coin",
				LayoutOrder = 3,
				Parent = body,
				OnClick = function()
					close()
					context.ShowFolios()
				end,
			})
			more.Instance.Destroying:Once(function()
				more:Destroy()
			end)
		end

		local pending: Pending
		local sheet = ConfirmSheet.new({
			Title = t("shop.confirm.title", { name = t(entry.NameKey) }),
			Body = t(Theme.rarity(entry.Rarity).WordKey),
			Preview = body,
			Confirm = { Text = t("shop.buy") },
			Cancel = { Text = t("common.cancel") },
			OnConfirm = function()
				buy(pending)
			end,
			OnCancel = function()
				if current == pending and not pending.Waiting then
					close()
				end
			end,
			Parent = context.Card,
		})
		pending = { Sheet = sheet, Preview = swatch, CosmeticId = entry.CosmeticId, Waiting = false }
		current = pending
		if short then
			sheet.ConfirmButton:SetDisabled(true, "Locked", t("shop.notEnoughFolios"))
		end
	end

	-- A refusal (not enough Folios, gone from the rotation, already owned) ends the wait with a shake.
	trove:Connect(context.HudController.Notified, function(key: string, _params: any, kind: string)
		local pending = current
		if pending == nil or not pending.Waiting then
			return
		end
		if kind == "Error" or key == "purchase.alreadyOwned" then
			settle(pending)
			pending.Sheet.ConfirmButton:Flash("Error")
		end
	end)

	local function refresh(_self: Purchases)
		local pending = current
		local data = context.ClientData.get()
		if pending ~= nil and pending.Waiting and data ~= nil then
			if table.find(data.Cosmetics.Owned, pending.CosmeticId) ~= nil then
				acquired(pending)
			end
		end
	end

	local function closeSheet(_self: Purchases)
		close()
	end

	local function destroy(_self: Purchases)
		trove:Destroy()
	end

	local object: Purchases = {
		Ask = ask,
		Refresh = refresh,
		Close = closeSheet,
		Destroy = destroy,
	}
	return object
end

return Purchase
