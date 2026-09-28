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
--   Canvases         A ScrollingFrame's CanvasSize scale is of the ScrollingFrame's parent, as a Size is, not of
--                    its window (D-171): a canvas of fromScale(1, 1) in a window its parent's header and footer
--                    shorten is taller than the window, and it scrolls onto nothing.
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

-- Every rule, on `root`.
function Layout.check(root: any, _screenHeight: number): { string }
	local found = Layout.automaticSizes(root)
	for _, line in ipairs(Layout.canvases(root)) do
		table.insert(found, line)
	end
	return found
end

return Layout
