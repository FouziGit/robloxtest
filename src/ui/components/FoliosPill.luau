--!strict
-- FoliosPill: the player's Folios as a pill of ink (D-147, the board's summary strip) -- a gold coin drawn in
-- the pill, and the count in the number face, in the sheet, grouped by thousands in the player's language
-- (folios.balance: "2 480" in French, "2,480" in English, as the board writes it). A balance that changes
-- while the pill is on screen counts to its new value with a tick at every tenth of the way (Motion.countTo),
-- so a purchase or a reward is seen leaving or arriving; one that changes out of sight is simply written.
-- Given the way to more of them (OnMore), the pill ends on a "+" disc of the sheet and the whole pill is the
-- button that takes it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiSound = require(script.Parent.Parent.UiSound)

export type Props = {
	-- Writes the count in the player's language.
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	Height: number?,
	LayoutOrder: number?,
	Parent: Instance?,
	-- The way to more Folios: a "+" at the pill's right end, and the pill a button that takes it.
	OnMore: (() -> ())?,
}

export type FoliosPill = {
	Instance: GuiObject,
	-- The count to show; `animate` counts to it from the one shown, when there is one.
	Set: (self: FoliosPill, amount: number, animate: boolean) -> (),
	Destroy: (self: FoliosPill) -> (),
}

local FoliosPill = {}

local HEIGHT = 44
-- The count's words: the amount alone, grouped by thousands.
local BALANCE_KEY = "folios.balance"
-- Inside the pill: off its left end, off its right end (closer when the "+" disc ends it), and between parts.
local PADDING = 12
local PADDING_MORE = 6
-- The coin: gold, rimmed in the sheet, a ring of its own lip inside the rim (the board's `.coin`).
local COIN_SIZE = 26
local COIN_RIM = Theme.Sizes.Stroke
local COIN_RING = Theme.Sizes.Stroke
-- The "+" disc of the sheet, a little larger than the coin (the board's 2.6cqw to its 2.4).
local MORE_SIZE = 28

-- The coin, drawn here rather than as the Coin icon: a gold disc in a sheet rim, the lip's ring inside it. The
-- hub's Folios (MetaCluster) draw the same coin, so the balance is one picture wherever it is shown.
local function coin(parent: Instance, layoutOrder: number?): Frame
	local disc = Instance.new("Frame")
	disc.Name = "Coin"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = Theme.Colors.Primary
	disc.Size = UDim2.fromOffset(COIN_SIZE, COIN_SIZE)
	disc.LayoutOrder = layoutOrder or 1
	Theme.corner(disc, Theme.Pill)
	Theme.stroke(disc, "PanelRaised", COIN_RIM)
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, -COIN_RIM * 2, 1, -COIN_RIM * 2)
	Theme.corner(ring, Theme.Pill)
	Theme.stroke(ring, Theme.lip("Primary"), COIN_RING)
	ring.Parent = disc
	disc.Parent = parent
	return disc
end

FoliosPill.coin = coin

function FoliosPill.new(props: Props): FoliosPill
	local trove = Trove.new()
	local height = props.Height or HEIGHT
	local shown: number? = nil
	local onMore = props.OnMore
	local localize = props.Localize
	local function written(value: number): string
		return localize.t(BALANCE_KEY, { folios = value })
	end

	local pill: GuiObject
	if onMore ~= nil then
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.Text = ""
		button.Selectable = true
		button.SelectionImageObject = trove:Add(Theme.focusRing(nil, Theme.Pill))
		-- A thumb's worth whatever the UIScale.
		Theme.minPixelSize(button, Theme.MinTouchTarget)
		trove:Connect(button.Activated, function()
			UiSound.play("UiClick")
			onMore()
		end)
		pill = button
	else
		pill = Instance.new("Frame")
	end
	pill.Name = "Folios"
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = Theme.Colors.Plate
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, height)
	pill.LayoutOrder = props.LayoutOrder or 0
	Theme.corner(pill, Theme.Pill)
	trove:Add(pill)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, if onMore ~= nil then PADDING_MORE else PADDING)
	padding.Parent = pill
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = pill

	coin(pill)

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Size = UDim2.fromScale(0, 1)
	count.FontFace = Theme.Fonts.Numeric
	count.TextSize = Theme.Sizes.Num
	count.TextColor3 = Theme.Colors.PanelRaised
	count.LayoutOrder = 2
	count.Text = ""
	count.Parent = pill

	if onMore ~= nil then
		local more = Instance.new("TextLabel")
		more.Name = "More"
		more.BorderSizePixel = 0
		more.BackgroundColor3 = Theme.Colors.PanelRaised
		more.Size = UDim2.fromOffset(MORE_SIZE, MORE_SIZE)
		more.FontFace = Theme.Fonts.Label
		more.TextSize = Theme.Sizes.TextBody
		more.TextColor3 = Theme.Colors.Text
		more.Text = Theme.Glyphs.Plus
		more.LayoutOrder = 3
		Theme.corner(more, Theme.Pill)
		more.Parent = pill
	end

	pill.Parent = props.Parent

	local function set(_self: FoliosPill, amount: number, animate: boolean)
		local whole = math.floor(amount)
		local previous = shown
		shown = whole
		if animate and previous ~= nil and previous ~= whole then
			Motion.countTo(count, previous, whole, written)
		elseif count:FindFirstChildOfClass("NumberValue") ~= nil then
			-- A count still on its way lands on the new balance instead of the old one.
			Motion.countTo(count, whole, whole, written)
		else
			count.Text = written(whole)
		end
	end

	local function destroy(_self: FoliosPill)
		trove:Destroy()
	end

	local object: FoliosPill = {
		Instance = pill,
		Set = set,
		Destroy = destroy,
	}
	return object
end

return FoliosPill
