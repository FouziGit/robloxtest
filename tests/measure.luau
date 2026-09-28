--!strict
-- What Lune cannot lay out, measured the conservative way: how wide a Button's word makes it, and how tall a
-- frame built on tests/engine.luau is drawn on a given screen.
--
-- Widths: a word is drawn at most CHAR_SHARE of its text size a character in the interface's faces, so a
-- width from here is an upper bound, never the engine's own figure. Heights: down the chain of parents, each
-- frame's scale of what its parent leaves (less the parent's UIPadding, and for a ScrollingFrame its canvas
-- less a horizontal bar's inset) plus its offset, floored and capped by its UISizeConstraint. A canvas is
-- never shorter than its window, and its scale is of the ScrollingFrame's own parent, as the engine resolves
-- it (measured in Studio, D-171). List layouts and automatic sizes are not modelled: measure the frames they
-- do not size. One exception, listHeight: the height a vertical list lays out, where every row it places has a
-- fixed height or is a list itself.
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

-- The height `frame` leaves its children, on a ScreenGui `screenHeight` design units tall.
local function room(frame: any, screenHeight: number): number
	if frame:IsA("LayerCollector") then
		return screenHeight
	end
	local available = Measure.heightOf(frame, screenHeight)
	if frame:IsA("ScrollingFrame") then
		local canvas = frame.CanvasSize
		available = math.max(available, room(frame.Parent, screenHeight) * canvas.Y.Scale + canvas.Y.Offset)
		local inset = frame.HorizontalScrollBarInset
		if inset ~= nil and inset.Name == "ScrollBar" then
			available -= frame.ScrollBarThickness or 0
		end
	end
	local padding = frame:FindFirstChildOfClass("UIPadding")
	if padding ~= nil then
		local top, bottom = padding.PaddingTop, padding.PaddingBottom
		available -= available * (top.Scale + bottom.Scale) + top.Offset + bottom.Offset
	end
	return available
end

-- The height `object` (an engine instance) is drawn at, on a ScreenGui `screenHeight` design units tall.
function Measure.heightOf(object: any, screenHeight: number): number
	if object:IsA("LayerCollector") then
		return screenHeight
	end
	local parent = object.Parent
	assert(parent ~= nil, object:GetFullName() .. " is not on a screen")
	local height = room(parent, screenHeight) * object.Size.Y.Scale + object.Size.Y.Offset
	local constraint = object:FindFirstChildOfClass("UISizeConstraint")
	if constraint ~= nil then
		height = math.clamp(height, constraint.MinSize.Y, math.max(constraint.MinSize.Y, constraint.MaxSize.Y))
	end
	return height
end

-- The height the vertical UIListLayout of `frame` lays its visible children out to, with the frame's own
-- padding: each child's fixed height, or for a child that sizes itself on Y the list inside it, and the list's
-- gap between two. A child sized by scale is an error: that is the engine's to lay out, not this.
function Measure.listHeight(frame: any): number
	local layout = frame:FindFirstChildOfClass("UIListLayout")
	assert(layout ~= nil, frame:GetFullName() .. " lays out no list")
	assert(
		layout.FillDirection == nil or layout.FillDirection.Name == "Vertical",
		frame:GetFullName() .. " lays its list across"
	)
	local total, count = 0, 0
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible ~= false then
			local automatic = child.AutomaticSize
			if automatic ~= nil and (automatic.Name == "Y" or automatic.Name == "XY") then
				total += Measure.listHeight(child)
			else
				assert(child.Size.Y.Scale == 0, child:GetFullName() .. " takes its height from its list's frame")
				total += child.Size.Y.Offset
			end
			count += 1
		end
	end
	local padding = frame:FindFirstChildOfClass("UIPadding")
	local inset = if padding ~= nil then padding.PaddingTop.Offset + padding.PaddingBottom.Offset else 0
	return inset + total + math.max(0, count - 1) * layout.Padding.Offset
end

return Measure
