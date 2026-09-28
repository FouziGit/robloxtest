--!strict
-- FoliosPill: the player's Folios as a pill of the sheet (D-147) -- the coin, and the count in the number
-- face. A balance that changes while the pill is on screen counts to its new value with a tick at every
-- tenth of the way (Motion.countTo), so a purchase or a reward is seen leaving or arriving; one that changes
-- out of sight is simply written. On paper and on a chapter band alike, the ink outline detaches it (rule 11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Icon = require(script.Parent.Icon)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Height: number?,
	LayoutOrder: number?,
	Parent: Instance?,
}

export type FoliosPill = {
	Instance: Frame,
	-- The count to show; `animate` counts to it from the one shown, when there is one.
	Set: (self: FoliosPill, amount: number, animate: boolean) -> (),
	Destroy: (self: FoliosPill) -> (),
}

local FoliosPill = {}

local HEIGHT = 44
local PADDING = 12
local COIN_SIZE = 26

function FoliosPill.new(props: Props): FoliosPill
	local trove = Trove.new()
	local height = props.Height or HEIGHT
	local shown: number? = nil

	local pill = Instance.new("Frame")
	pill.Name = "Folios"
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = Theme.Colors.PanelRaised
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, height)
	pill.LayoutOrder = props.LayoutOrder or 0
	Theme.corner(pill, Theme.Pill)
	Theme.stroke(pill, "Accent", Theme.Sizes.StrokeThin)
	trove:Add(pill)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = pill
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = pill

	local coin = Icon.new("Coin", COIN_SIZE)
	coin.LayoutOrder = 1
	coin.Parent = pill

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Size = UDim2.fromScale(0, 1)
	count.FontFace = Theme.Fonts.Numeric
	count.TextSize = Theme.Sizes.Num
	count.TextColor3 = Theme.Colors.Text
	count.LayoutOrder = 2
	count.Text = ""
	count.Parent = pill

	pill.Parent = props.Parent

	local function set(_self: FoliosPill, amount: number, animate: boolean)
		local whole = math.floor(amount)
		local previous = shown
		shown = whole
		if animate and previous ~= nil and previous ~= whole then
			Motion.countTo(count, previous, whole, tostring)
		elseif count:FindFirstChildOfClass("NumberValue") ~= nil then
			-- A count still on its way lands on the new balance instead of the old one.
			Motion.countTo(count, whole, whole, tostring)
		else
			count.Text = tostring(whole)
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
