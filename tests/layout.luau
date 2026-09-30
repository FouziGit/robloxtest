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
--   Scaled contents  A frame that sizes itself on an axis grows to hold a descendant a UIScale draws larger from
--                    its top-left corner (AnchorPoint 0, 0): a hotbar slot 56 wide stayed 78.4 wide after
--                    its ready flash, scaled to 1.4 from its corner, had faded (seen in Studio). Measured there too:
--                    the same flash anchored at its centre, or a badge anchored at its host's right edge or astride
--                    its corner, leaves the frame its size. Checked on the scales at rest.
--   Billboard words  In a BillboardGui, a label that sizes itself and may truncate measures its words against the
--                    room right of where the outermost frame sizing itself around it is placed, not the room its
--                    AnchorPoint centres it in: the lock's pill, placed at the middle of its 180-wide billboard, cut
--                    "Training dummy · 150" to "Training…" in 50 (seen in Studio). Laid out by a list, it has the
--                    list's room.
--   Rows' pressables A row drawn with its own outline (ListRow's Edge) holds a pressable, centred in it, with the
--                    lip's ink rim, drawn outside the pressable's box: a key button of 52 in a row of 56 crossed the
--                    row's foot with its rim (seen in Studio, the Settings' keys).
--   Rows of words    A list laid across that does not wrap draws its buttons at their words' width however little
--                    room its frame has, and the last ones run out of it: a Today card's two prices on a phone
--                    needed 388 and had 374 once "8,000 Folios" was grouped (D-XXX). Each button is measured by
--                    its own hidden Measure label -- its words, its padding, its least width -- at Measure's upper
--                    bound; a row whose frame sizes itself across is left alone, it has no room to run out of.
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

-- A scale resting above 1 under a frame that sizes itself, on something drawn from its top-left corner.
function Layout.scaledContents(root: any): { string }
	local found: { string } = {}
	for _, scale in ipairs(root:GetDescendants()) do
		local object = scale.Parent
		if scale.ClassName == "UIScale" and scale.Scale > 1.001 and object ~= nil and object:IsA("GuiObject") then
			for _, axis in ipairs(AXES) do
				local ancestor = object.Parent
				local sizing = nil
				while ancestor ~= nil and ancestor:IsA("GuiObject") do
					if autoOn(ancestor, axis) then
						sizing = ancestor
						break
					end
					ancestor = ancestor.Parent
				end
				if sizing ~= nil and object.AnchorPoint.X == 0 and object.AnchorPoint.Y == 0 then
					table.insert(
						found,
						("%s rests at a scale of %.2f from its corner, and %s grows on %s to hold it"):format(
							object:GetFullName(),
							scale.Scale,
							sizing:GetFullName(),
							axis
						)
					)
				end
			end
		end
	end
	return found
end

local function laidOut(parent: any): boolean
	return parent ~= nil
		and (parent:FindFirstChildOfClass("UIListLayout") ~= nil or parent:FindFirstChildOfClass("UIGridLayout") ~= nil)
end

function Layout.billboardWords(root: any): { string }
	local found: { string } = {}
	for _, label in ipairs(root:GetDescendants()) do
		local truncate = label.TextTruncate
		if
			(label:IsA("TextLabel") or label:IsA("TextButton"))
			and truncate ~= nil
			and truncate.Name ~= "None"
			and autoOn(label, "X")
			and label:FindFirstAncestorWhichIsA("BillboardGui") ~= nil
		then
			local top = label
			while top.Parent ~= nil and top.Parent:IsA("GuiObject") and autoOn(top.Parent, "X") do
				top = top.Parent
			end
			local positioned = top.AnchorPoint.X ~= 0 or top.Position.X.Scale ~= 0 or top.Position.X.Offset ~= 0
			if not laidOut(top.Parent) and positioned then
				table.insert(
					found,
					("%s may cut its words against the room right of where %s is placed in its billboard"):format(
						label:GetFullName(),
						top:GetFullName()
					)
				)
			end
		end
	end
	return found
end

function Layout.rowPressables(root: any): { string }
	local found: { string } = {}
	for _, edge in ipairs(root:GetDescendants()) do
		local row = edge.Parent
		local line = edge:FindFirstChildOfClass("UIStroke")
		if edge.Name == "Edge" and line ~= nil and row ~= nil and row:IsA("GuiObject") and row.Size.Y.Scale == 0 then
			for _, base in ipairs(row:GetDescendants()) do
				local rim = base:FindFirstChildOfClass("UIStroke")
				if base.Name == "Base" and rim ~= nil and rim.BorderStrokePosition.Name == "Outer" then
					local host = base.Parent
					while host ~= nil and host ~= row and host.Size.Y.Scale ~= 0 do
						host = host.Parent
					end
					if host ~= nil and host ~= row then
						local needed = host.Size.Y.Offset + 2 * rim.Thickness + 2 * line.Thickness
						if needed > row.Size.Y.Offset then
							table.insert(
								found,
								("%s is %d tall with its rim, in %s of %d inside its outline"):format(
									host:GetFullName(),
									host.Size.Y.Offset + 2 * rim.Thickness,
									row:GetFullName(),
									row.Size.Y.Offset - 2 * line.Thickness
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

-- The widest a Button is drawn: its hidden Measure label's words and padding, and never under its least width.
local function buttonWidth(button: any): number?
	local measure = button:FindFirstChild("Measure")
	if measure == nil or not measure:IsA("TextLabel") then
		return nil
	end
	local padding = measure:FindFirstChildOfClass("UIPadding")
	local pads = if padding ~= nil then padding.PaddingLeft.Offset + padding.PaddingRight.Offset else 0
	return math.max(measure.Size.X.Offset, pads + Measure.textWidth(measure.Text, measure.TextSize))
end

-- Whether `frame` or a frame it takes its width from sizes itself across.
local function sizedByContent(frame: any): boolean
	local current = frame
	while current ~= nil and current:IsA("GuiObject") do
		if autoOn(current, "X") then
			return true
		end
		if current.Size.X.Scale == 0 then
			return false
		end
		current = current.Parent
	end
	return false
end

function Layout.rowWords(root: any, screenWidth: number): { string }
	local found: { string } = {}
	for _, layout in ipairs(root:GetDescendants()) do
		local row = layout.Parent
		if
			layout.ClassName == "UIListLayout"
			and layout.FillDirection ~= nil
			and layout.FillDirection.Name == "Horizontal"
			and layout.Wraps ~= true
			and row ~= nil
			and row:IsA("GuiObject")
			and row.Visible ~= false
			and not sizedByContent(row)
		then
			local need, buttons = 0, 0
			local objects = placed(row)
			for _, object in ipairs(objects) do
				local width = if object:IsA("TextButton") then buttonWidth(object) else nil
				if width ~= nil then
					buttons += 1
					need += width
				else
					need += object.Size.X.Offset
				end
			end
			need += math.max(0, #objects - 1) * layout.Padding.Offset
			if buttons >= 2 then
				local padding = row:FindFirstChildOfClass("UIPadding")
				local room = Measure.widthOf(row, screenWidth)
				if padding ~= nil then
					room -= padding.PaddingLeft.Offset + padding.PaddingRight.Offset
				end
				if need > room + 0.5 then
					table.insert(
						found,
						("%s lays %d buttons across in %.1f that need %.1f"):format(
							row:GetFullName(),
							buttons,
							room,
							need
						)
					)
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
	for _, line in ipairs(Layout.scaledContents(root)) do
		table.insert(found, line)
	end
	for _, line in ipairs(Layout.billboardWords(root)) do
		table.insert(found, line)
	end
	for _, line in ipairs(Layout.rowPressables(root)) do
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
