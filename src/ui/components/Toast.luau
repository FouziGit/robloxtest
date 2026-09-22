--!strict
-- Toast: stacked notification messages at the top-center of a parent GuiObject. `Show` queues a
-- message; at most MAX_VISIBLE are on screen at once and the rest wait their turn. Each message fades
-- in, stays DURATION_SECONDS, fades out and frees its slot. The caller localizes the text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Kind = "Info" | "Success" | "Error"

export type Props = {
	Parent: GuiObject,
	Name: string?,
	-- Set when the parent lays its children out. The container then takes its place in that layout
	-- instead of pinning itself to the top centre, which is what used to make it draw over the match
	-- band and the World Boss band.
	LayoutOrder: number?,
}

export type Toast = {
	Instance: Frame,
	Show: (self: Toast, text: string, kind: Kind) -> (),
	Destroy: (self: Toast) -> (),
}

type Entry = { Text: string, Kind: Kind }

local Toast = {}

local MAX_VISIBLE = 3
local MAX_PENDING = 8 -- older waiting messages are dropped beyond this
local DURATION_SECONDS = 2.5
local WIDTH = 360
local STROKE_THICKNESS = 2
-- A message lands from just under its size: rule 3 of docs/ART_BIBLE.md, nothing appears.
local ENTER_SCALE = 0.92

local function colorFor(kind: Kind): Color3
	if kind == "Success" then
		return Theme.Colors.Success
	elseif kind == "Error" then
		return Theme.Colors.Danger
	end
	return Theme.Colors.Info
end

local function buildItem(entry: Entry): CanvasGroup
	local group = Instance.new("CanvasGroup")
	group.Name = entry.Kind
	group.AutomaticSize = Enum.AutomaticSize.Y
	group.Size = UDim2.fromScale(1, 0)
	group.BackgroundColor3 = Theme.Colors.Panel
	group.BorderSizePixel = 0
	group.GroupTransparency = 1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = group

	local stroke = Instance.new("UIStroke")
	stroke.Color = colorFor(entry.Kind)
	stroke.Thickness = STROKE_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = group

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.Sizes.PaddingSmall)
	padding.PaddingBottom = UDim.new(0, Theme.Sizes.PaddingSmall)
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.Parent = group

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.fromScale(1, 0)
	label.FontFace = Theme.Fonts.Bold
	label.TextSize = Theme.Sizes.TextBody
	label.TextColor3 = Theme.Colors.Text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = entry.Text
	label.Parent = group

	return group
end

function Toast.new(props: Props): Toast
	local trove = Trove.new()
	local pending: { Entry } = {}
	local activeCount = 0
	local sequence = 0
	local destroyed = false

	local container = Instance.new("Frame")
	container.Name = props.Name or "Toasts"
	if props.LayoutOrder ~= nil then
		container.LayoutOrder = props.LayoutOrder
	else
		container.AnchorPoint = Vector2.new(0.5, 0)
		container.Position = UDim2.new(0.5, 0, 0, Theme.Sizes.Padding)
	end
	container.Size = UDim2.fromOffset(WIDTH, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	trove:Add(container)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(WIDTH, math.huge)
	sizeConstraint.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = container

	local pump: () -> ()

	local function present(entry: Entry)
		activeCount += 1
		sequence += 1

		local itemTrove = trove:Extend()
		local item = itemTrove:Add(buildItem(entry))
		item.LayoutOrder = sequence
		item.Parent = container

		local function release()
			if destroyed then
				return
			end
			trove:Remove(itemTrove)
			activeCount -= 1
			pump()
		end

		local scale = Instance.new("UIScale")
		scale.Name = "Scale"
		scale.Scale = ENTER_SCALE
		scale.Parent = item
		itemTrove:Add(function()
			Motion.cancel(item)
			Motion.cancel(scale)
		end)
		Motion.to(scale, { Scale = 1 }, "UiSnappy")
		Motion.to(item, { GroupTransparency = 0 }, "Ui")

		itemTrove:Add(task.delay(DURATION_SECONDS, function()
			-- The slot is released once the fade has settled, not on a timer guessed to match it.
			Motion.to(item, { GroupTransparency = 1 }, "Ui", release)
		end))
	end

	pump = function()
		while activeCount < MAX_VISIBLE and #pending > 0 do
			local entry = table.remove(pending, 1) :: Entry
			present(entry)
		end
	end

	container.Parent = props.Parent

	-- Which message goes when the queue is full. A fight can post a line a second, and a refused purchase
	-- or a claimed quest must not be the thing that falls off the end behind them: the oldest INFO goes
	-- first, and only when there is none does the oldest of anything. A new Info arriving into a queue of
	-- nothing but Success and Error is simply not queued.
	local function dropOne(incoming: Kind): boolean
		for index, entry in ipairs(pending) do
			if entry.Kind == "Info" then
				table.remove(pending, index)
				return true
			end
		end
		if incoming == "Info" then
			return false
		end
		table.remove(pending, 1)
		return true
	end

	local function show(_self: Toast, text: string, kind: Kind)
		if destroyed then
			return
		end
		if #pending >= MAX_PENDING and not dropOne(kind) then
			return
		end
		table.insert(pending, { Text = text, Kind = kind })
		while #pending > MAX_PENDING do
			table.remove(pending, 1)
		end
		pump()
	end

	local function destroy(_self: Toast)
		destroyed = true
		table.clear(pending)
		trove:Destroy()
	end

	local object: Toast = {
		Instance = container,
		Show = show,
		Destroy = destroy,
	}
	return object
end

return Toast
