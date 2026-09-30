--!strict
-- RarityBand: how rare an item is, written across the top of its card (D-147) -- the board's band, in the
-- rarity's colour, with its word on the left and its pips on the right, over a rule of ink. Colour is never
-- the only cue: the word and the pips say it too. The band sits inside the card's own outline, inset by it
-- from the top and the sides, its top corners following the inner curve of the card's; what the card draws
-- under it starts at `Bottom`.
--
--   Full      37 of colour and 3 of rule, the word in the label face at 14 and the pips at 14
--   Compact   22 and 3, for a card a touch screen draws at its height
--   Word-less Compact without the word, 13 and 3: the colour and the pips, for the pass's small cells
--
-- No seal ring and no shimmer of its own: a Legendary card lays the shimmer over its whole face.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Pips = require(script.Parent.Pips)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	-- A ThemeConfig.Rarity key.
	Rarity: string,
	-- The player's word for it (`Theme.rarity(rarity).WordKey`, translated by the caller).
	Word: string,
	-- The card's face: the band is laid across its top.
	Parent: Instance?,
	Compact: boolean?,
	-- False for the word-less band; the word is shown unless told otherwise.
	ShowWord: boolean?,
	-- The thickness of the card's outline, which the band sits inside (Theme.Sizes.Stroke unless told otherwise).
	Inset: number?,
	ZIndex: number?,
}

export type RarityBand = {
	Instance: Frame,
	-- The colour and the rule, in design units.
	Height: number,
	-- How far under the top of the card what it draws below the band starts.
	Bottom: number,
	Destroy: (self: RarityBand) -> (),
}

local RarityBand = {}

local FILL = 37
local FILL_COMPACT = 22
local FILL_WORDLESS = 13
local PAD_X = 12
local PAD_Y = 8
local PAD_Y_COMPACT = 4
local WORD_SIZE = 14
local PIP_SIZE = 14
local PIP_SIZE_WORDLESS = 12

local function fillHeight(compact: boolean?, showWord: boolean?): number
	if showWord == false and compact == true then
		return FILL_WORDLESS
	end
	return if compact == true then FILL_COMPACT else FILL
end

-- The height of a band drawn `compact` and with or without its word: its colour and its rule.
function RarityBand.height(compact: boolean?, showWord: boolean?): number
	return fillHeight(compact, showWord) + Theme.Sizes.Stroke
end

-- Where what a card draws under such a band starts, from the card's top, inside an outline of `inset`.
function RarityBand.bottom(compact: boolean?, showWord: boolean?, inset: number?): number
	return (inset or Theme.Sizes.Stroke) + RarityBand.height(compact, showWord)
end

function RarityBand.new(props: Props): RarityBand
	local trove = Trove.new()
	local look = Theme.rarity(props.Rarity)
	local compact = props.Compact == true
	local showWord = props.ShowWord ~= false
	local inset = props.Inset or Theme.Sizes.Stroke
	local zIndex = props.ZIndex or 1
	local fill = fillHeight(compact, showWord)
	local height = RarityBand.height(compact, showWord)

	local band = Instance.new("Frame")
	band.Name = "RarityBand"
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.Position = UDim2.fromOffset(inset, inset)
	band.Size = UDim2.new(1, -inset * 2, 0, height)
	band.ZIndex = zIndex
	trove:Add(band)

	-- The colour, its top corners on the inner curve of the card's, its bottom square on the rule.
	local colour = Instance.new("Frame")
	colour.Name = "Fill"
	colour.BorderSizePixel = 0
	colour.BackgroundColor3 = look.Fill
	colour.Size = UDim2.new(1, 0, 0, fill)
	colour.ZIndex = zIndex
	local round = math.min(Theme.Sizes.CornerCard - inset, fill / 2)
	Theme.corner(colour, round)
	local square = Instance.new("Frame")
	square.Name = "Square"
	square.BorderSizePixel = 0
	square.BackgroundColor3 = look.Fill
	square.Position = UDim2.new(0, 0, 1, -round)
	square.Size = UDim2.new(1, 0, 0, round)
	square.ZIndex = zIndex
	square.Parent = colour
	colour.Parent = band

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = Theme.Colors.Accent
	rule.Position = UDim2.fromOffset(0, fill)
	rule.Size = UDim2.new(1, 0, 0, Theme.Sizes.Stroke)
	rule.ZIndex = zIndex
	rule.Parent = band

	-- The word on the left, the pips on the right, a spacer taking what they leave.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = zIndex + 1
	local padY = if not showWord and compact then 0 elseif compact then PAD_Y_COMPACT else PAD_Y
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, padY)
	padding.PaddingBottom = UDim.new(0, padY)
	padding.PaddingLeft = UDim.new(0, PAD_X)
	padding.PaddingRight = UDim.new(0, PAD_X)
	padding.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = content
	content.Parent = colour

	if showWord then
		local label = Instance.new("TextLabel")
		label.Name = "Word"
		label.BackgroundTransparency = 1
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.FontFace = Theme.Fonts.Label
		label.TextSize = WORD_SIZE
		label.TextColor3 = look.Ink
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = props.Word
		label.LayoutOrder = 1
		label.ZIndex = zIndex + 1
		label.Parent = content
	end

	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.fromScale(0, 1)
	spacer.LayoutOrder = 2
	local grow = Instance.new("UIFlexItem")
	grow.FlexMode = Enum.UIFlexMode.Fill
	grow.Parent = spacer
	spacer.Parent = content

	-- Only the pips it has: a Common band shows one, a Legendary four.
	local pips = Pips.new(look.Pips, look.Pips, look.Ink, if showWord then PIP_SIZE else PIP_SIZE_WORDLESS)
	pips.Instance.LayoutOrder = 3
	pips.Instance.ZIndex = zIndex + 1
	pips.Instance.Parent = content
	trove:Add(function()
		pips:Destroy()
	end)

	band.Parent = props.Parent

	local function destroy(_self: RarityBand)
		trove:Destroy()
	end

	local object: RarityBand = {
		Instance = band,
		Height = height,
		Bottom = inset + height,
		Destroy = destroy,
	}
	return object
end

return RarityBand
