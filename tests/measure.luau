--!strict
-- What Lune cannot lay out, measured the conservative way: how wide a Button's word makes it, and how tall a
-- frame built on tests/engine.luau is drawn on a given screen.
--
-- Widths: a word is drawn at most CHAR_SHARE of its text size a character in the interface's faces, so a
-- width from here is an upper bound, never the engine's own figure. Heights: down the chain of parents, each
-- frame's scale of what its parent leaves (less the parent's UIPadding, and for a ScrollingFrame its canvas
-- less a horizontal bar's inset) plus its offset, floored and capped by its UISizeConstraint. List layouts
-- and automatic sizes are not modelled: measure the frames they do not size.
local fs = require("@lune/fs")

local Measure = {}

Measure.CHAR_SHARE = 0.7

local BUTTON = "src/ui/components/Button.luau"

local function number(path: string, name: string): number
	local value = tonumber(string.match(fs.readFile(path), "\nlocal " .. name .. " = ([%d%.]+)\n"))
	assert(value ~= nil, ("%s has no number %s: this measure would measure nothing"):format(path, name))
	return value :: number
end

-- How many characters `text` draws.
local function length(text: string): number
	return utf8.len(text) or #text
end

-- The widest a word `text` in `textSize` is drawn.
function Measure.textWidth(text: string, textSize: number): number
	return length(text) * Measure.CHAR_SHARE * textSize
end

-- The widest a Button saying `text` at `textSize` is drawn, with an icon before its word when `icon`.
function Measure.buttonWidth(text: string, textSize: number, icon: boolean): number
	local lead = if icon then number(BUTTON, "ICON_SIZE") + number(BUTTON, "GAP") else 0
	local drawn = number(BUTTON, "PADDING_X") * 2 + lead + Measure.textWidth(text, textSize)
	return math.max(number(BUTTON, "MIN_WIDTH"), drawn)
end

-- The height `object` (an engine instance) is drawn at, on a ScreenGui `screenHeight` design units tall.
function Measure.heightOf(object: any, screenHeight: number): number
	if object:IsA("LayerCollector") then
		return screenHeight
	end
	local parent = object.Parent
	assert(parent ~= nil, object:GetFullName() .. " is not on a screen")
	local available = Measure.heightOf(parent, screenHeight)
	if parent:IsA("ScrollingFrame") then
		local canvas = parent.CanvasSize
		available = available * canvas.Y.Scale + canvas.Y.Offset
		local inset = parent.HorizontalScrollBarInset
		if inset ~= nil and inset.Name == "ScrollBar" then
			available -= parent.ScrollBarThickness or 0
		end
	end
	local padding = parent:FindFirstChildOfClass("UIPadding")
	if padding ~= nil then
		local top, bottom = padding.PaddingTop, padding.PaddingBottom
		available -= available * (top.Scale + bottom.Scale) + top.Offset + bottom.Offset
	end
	local height = available * object.Size.Y.Scale + object.Size.Y.Offset
	local constraint = object:FindFirstChildOfClass("UISizeConstraint")
	if constraint ~= nil then
		height = math.clamp(height, constraint.MinSize.Y, math.max(constraint.MinSize.Y, constraint.MaxSize.Y))
	end
	return height
end

return Measure
