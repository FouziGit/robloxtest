--!strict
-- What the engine does with a layout that tests/engine.luau does not lay out, measured in Studio on the colour
-- pass (D-170) and checked here on the instances a module builds. Each check returns what breaks the rule, one
-- line per instance, so a spec can print them all.
--
--   Automatic sizes  A frame that sizes itself on an axis (AutomaticSize) resolves a child sized by scale on
--                    that axis against the size its content gives it, but a grandchild sized by scale through
--                    that child against the nearest ancestor of a fixed size, and grows to hold it: a sticker
--                    filling a button from a frame of its own made the button as wide as the screen. With a
--                    scale on that axis, it also drops a negative offset beside it.
--   Truncation       A label that sizes itself and may truncate, shorter than its words, cuts them to nothing
--                    and sizes itself to that.
--   Shared rows      An offset is a whole number of pixels: cells that share a row by scale, each less its
--                    share of the gaps, overrun the row by every fraction the engine drops.
--   Canvases         A ScrollingFrame's CanvasSize scale is of the ScrollingFrame's parent, as a Size is, not of
--                    its window (D-171): a canvas of fromScale(1, 1) in a window its parent's header and footer
--                    shorten is taller than the window, and it scrolls onto nothing.
--   Least sizes      A frame that sizes itself on an axis holds its content to its UISizeConstraint's least size,
--                    then adds its own padding on that axis outside it: a badge's disc of least 32, padded 8 either
--                    side, drew a lone figure as a pill of 48 (seen in Studio, Encre vive pass). A touch floor
--                    (Theme.minPixelSize, "TouchFloor") is exempt: padding outside it only makes a larger target.
local Measure = require("./measure")

local Layout = {}

type Axis = "X" | "Y"

local AXES: { Axis } = { "X", "Y" }

local function autoOn(object: any, axis: Axis): boolean
	local automatic = object.AutomaticSize
	if automatic == nil then
		return false
	end
	return automatic.Name == "XY" or automatic.Name == axis
end

local function scaleOn(object: any, axis: Axis): boolean
	return object:IsA("GuiObject") and (object.Size :: any)[axis].Scale ~= 0
end

-- The frame automatically sized on `axis` that `object`'s size on it is taken from through a child of it
-- sized by scale, or nil: the engine resolves `object` against the screen then.
local function measuredAgainstScreen(object: any, axis: Axis): any
	if not scaleOn(object, axis) or autoOn(object, axis) then
		return nil
	end
	local parent = object.Parent
	local depth = 0
	while parent ~= nil and parent:IsA("GuiObject") do
		if autoOn(parent, axis) then
			return if depth >= 1 then parent else nil
		end
		if not scaleOn(parent, axis) then
			return nil
		end
		depth += 1
		parent = parent.Parent
	end
	return nil
end

function Layout.automaticSizes(root: any): { string }
	local found: { string } = {}
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("GuiObject") then
			for _, axis in ipairs(AXES) do
				local frame = measuredAgainstScreen(object, axis)
				if frame ~= nil then
					table.insert(
						found,
						("%s takes its %s from %s, which sizes itself"):format(
							object:GetFullName(),
							axis,
							frame:GetFullName()
						)
					)
				end
				local size = (object.Size :: any)[axis]
				if autoOn(object, axis) and size.Scale ~= 0 and size.Offset < 0 then
					table.insert(
						found,
						("%s sizes itself on %s with a scale and a negative offset"):format(object:GetFullName(), axis)
					)
				end
			end
		end
	end
	return found
end

function Layout.truncation(root: any, screenHeight: number): { string }
	local found: { string } = {}
	for _, object in ipairs(root:GetDescendants()) do
		local text = object:IsA("TextLabel") or object:IsA("TextButton")
		local truncate = object.TextTruncate
		if text and object.Text ~= "" and truncate ~= nil and truncate.Name ~= "None" and autoOn(object, "X") then
			if not autoOn(object, "Y") then
				local ok, height = pcall(Measure.heightOf, object, screenHeight)
				if ok and height < object.TextSize then
					table.insert(
						found,
						("%s sizes itself, may truncate, and is %.1f tall for words of %d"):format(
							object:GetFullName(),
							height,
							object.TextSize
						)
					)
				end
			end
		end
	end
	return found
end

-- The GuiObjects a layout under `parent` places.
local function placed(parent: any): { any }
	local objects = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible ~= false then
			table.insert(objects, child)
		end
	end
	return objects
end

function Layout.sharedRows(root: any): { string }
	local found: { string } = {}
	for _, layout in ipairs(root:GetDescendants()) do
		if layout.ClassName == "UIGridLayout" then
			local columns = layout.FillDirectionMaxCells or 0
			local cell = layout.CellSize.X
			if columns > 1 and math.abs(cell.Scale * columns - 1) < 1e-4 then
				local over = columns * cell.Offset + (columns - 1) * layout.CellPadding.X.Offset
				if over > 0 then
					table.insert(
						found,
						("%s: a row of %d cells overruns its grid by %d"):format(layout:GetFullName(), columns, over)
					)
				end
			end
		elseif
			layout.ClassName == "UIListLayout"
			and layout.FillDirection ~= nil
			and layout.FillDirection.Name == "Horizontal"
		then
			local objects = placed(layout.Parent)
			local scale, offset = 0, 0
			local shared = #objects >= 2
			for _, object in ipairs(objects) do
				shared = shared and object.Size.X.Scale > 0
				scale += object.Size.X.Scale
				offset += object.Size.X.Offset
			end
			if shared and math.abs(scale - 1) < 1e-4 then
				local over = offset + (#objects - 1) * layout.Padding.Offset
				if over > 0 then
					table.insert(
						found,
						("%s: %d frames sharing the row overrun it by %d"):format(layout:GetFullName(), #objects, over)
					)
				end
			end
		end
	end
	return found
end

function Layout.canvases(root: any): { string }
	local found: { string } = {}
	for _, frame in ipairs(root:GetDescendants()) do
		if frame.ClassName == "ScrollingFrame" then
			local canvas, size = frame.CanvasSize, frame.Size
			for _, axis in ipairs(AXES) do
				local scale = (canvas :: any)[axis].Scale
				local own = (size :: any)[axis]
				if scale ~= 0 and (own.Scale ~= 1 or own.Offset ~= 0) then
					table.insert(
						found,
						("%s takes its canvas's %s from its parent, which is not its window"):format(
							frame:GetFullName(),
							axis
						)
					)
				end
			end
		end
	end
	return found
end

function Layout.leastSizes(root: any): { string }
	local found: { string } = {}
	for _, object in ipairs(root:GetDescendants()) do
		local padding = object:FindFirstChildOfClass("UIPadding")
		if object:IsA("GuiObject") and padding ~= nil then
			local pads = {
				X = padding.PaddingLeft.Offset + padding.PaddingRight.Offset,
				Y = padding.PaddingTop.Offset + padding.PaddingBottom.Offset,
			}
			for _, least in ipairs(object:GetChildren()) do
				if least.ClassName == "UISizeConstraint" and least.Name ~= "TouchFloor" then
					for _, axis in ipairs(AXES) do
						if autoOn(object, axis) and (least.MinSize :: any)[axis] > 0 and pads[axis] ~= 0 then
							table.insert(
								found,
								("%s sizes itself on %s to a least %d, and adds its padding of %d outside it"):format(
									object:GetFullName(),
									axis,
									(least.MinSize :: any)[axis],
									pads[axis]
								)
							)
						end
					end
				end
			end
		end
	end
	return found
end

-- Every rule, on `root`.
function Layout.check(root: any, screenHeight: number): { string }
	local found = Layout.automaticSizes(root)
	for _, line in ipairs(Layout.canvases(root)) do
		table.insert(found, line)
	end
	for _, line in ipairs(Layout.leastSizes(root)) do
		table.insert(found, line)
	end
	for _, line in ipairs(Layout.truncation(root, screenHeight)) do
		table.insert(found, line)
	end
	for _, line in ipairs(Layout.sharedRows(root)) do
		table.insert(found, line)
	end
	return found
end

return Layout
