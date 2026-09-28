--!strict
-- Pips: a row of ♦, filled up to a count (D-147). Colour is never the only cue: a rarity shows its pips
-- beside its colour and its word, and two rarities never show the same number of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Pips = {
	Instance: Frame,
	Set: (self: Pips, count: number) -> (),
	Destroy: (self: Pips) -> (),
}

local Pips = {}

local DEFAULT_MAX = 4
local PIP_SIZE = 12

-- `count` of `max` pips filled in `color`, the rest in chalk.
function Pips.new(count: number, max: number?, color: Color3?): Pips
	local trove = Trove.new()
	local total = max or DEFAULT_MAX
	local fill = color or Theme.Colors.Text

	local row = Instance.new("Frame")
	row.Name = "Pips"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.new()
	trove:Add(row)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	local pips: { TextLabel } = {}
	for index = 1, total do
		local pip = Instance.new("TextLabel")
		pip.Name = "Pip"
		pip.BackgroundTransparency = 1
		pip.AutomaticSize = Enum.AutomaticSize.XY
		pip.Size = UDim2.new()
		pip.LayoutOrder = index
		pip.FontFace = Theme.Fonts.Bold
		pip.TextSize = PIP_SIZE
		pip.Text = Theme.Glyphs.Pip
		pip.Parent = row
		pips[index] = pip
	end

	local function set(_self: Pips?, next: number)
		for index, pip in ipairs(pips) do
			pip.TextColor3 = if index <= next then fill else Theme.Colors.Chalk
		end
	end
	set(nil, count)

	local function destroy(_self: Pips)
		trove:Destroy()
	end

	local object: Pips = {
		Instance = row,
		Set = set,
		Destroy = destroy,
	}
	return object
end

return Pips
