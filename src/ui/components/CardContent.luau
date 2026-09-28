--!strict
-- CardContent: the scrolling part of a screen's card (D-147). What a screen puts in it is laid out as a list,
-- a grid of tiles, or a track that scrolls sideways. While a list runs on past the card's foot, a fade in the
-- card's own colour says so, with an arrow that bobs as long as its screen is up. And at an entrance the
-- first children in view spring up one after another (ThemeConfig.Timing's stagger), the rest simply there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Mode = "List" | "Grid" | "Track"

export type Props = {
	Mode: Mode?,
	-- The size of a cell in Grid mode (three to a row, TileHeight tall, by default).
	GridCell: UDim2?,
	Parent: Instance?,
}

export type CardContent = {
	Instance: ScrollingFrame,
	-- The fade at the foot: a sibling the card lays over the bottom edge of the content, so it never scrolls.
	MoreBelow: Frame,
	SetMode: (self: CardContent, mode: Mode) -> (),
	-- Whether the screen is up. The arrow only bobs while it is: a closed screen keeps no idle loop.
	SetShown: (self: CardContent, shown: boolean) -> (),
	PlayEnter: (self: CardContent) -> (),
	Destroy: (self: CardContent) -> (),
}

local CardContent = {}

local SCROLLBAR_TRANSPARENCY = 0.4
local DEFAULT_GRID_CELL = UDim2.new(1 / 3, -Theme.Sizes.Gap, 0, Theme.Sizes.TileHeight)
-- Children that spring up at an entrance start this small.
local STAGGER_FROM = 0.9
-- The fade, how close to the end of the list it goes, and its arrow's bob.
local MORE_BELOW_HEIGHT = 28
local MORE_BELOW_SLACK = 4
local ARROW_SIZE = 18
local ARROW_BOB = 4
local ARROW_HOLD = 0.3

-- The layout for `mode`, which also decides which way the canvas grows and scrolls.
local function makeLayout(content: ScrollingFrame, mode: Mode, gridCell: UDim2?): UIGridStyleLayout
	local layout: UIGridStyleLayout
	if mode == "Grid" then
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = gridCell or DEFAULT_GRID_CELL
		grid.CellPadding = UDim2.fromOffset(Theme.Sizes.Gap, Theme.Sizes.Gap)
		layout = grid
	else
		local list = Instance.new("UIListLayout")
		list.FillDirection = if mode == "Track" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		list.Padding = UDim.new(0, Theme.Sizes.Gap)
		layout = list
	end
	layout.Name = "Layout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local sideways = mode == "Track"
	content.ScrollingDirection = if sideways then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
	content.AutomaticCanvasSize = if sideways then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.CanvasPosition = Vector2.zero
	layout.Parent = content
	return layout
end

function CardContent.new(props: Props): CardContent
	local trove = Trove.new()
	local mode: Mode = props.Mode or "List"
	local shown = false

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Selectable = false
	content.ScrollBarThickness = Theme.Sizes.PaddingSmall
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.ScrollBarImageTransparency = SCROLLBAR_TRANSPARENCY
	content.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	content.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	content.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	trove:Add(content)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingTop = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingBottom = UDim.new(0, Theme.Sizes.Padding)
	padding.Parent = content
	local layout = makeLayout(content, mode, props.GridCell)

	local moreBelow = Instance.new("Frame")
	moreBelow.Name = "MoreBelow"
	moreBelow.BackgroundColor3 = Theme.Colors.Panel
	moreBelow.BorderSizePixel = 0
	moreBelow.AnchorPoint = Vector2.new(0, 1)
	moreBelow.Size = UDim2.new(1, 0, 0, MORE_BELOW_HEIGHT)
	moreBelow.Visible = false
	Theme.gradient("MoreBelow", Theme.Colors.Panel).Parent = moreBelow
	trove:Add(moreBelow)
	local arrowRest = UDim2.new(0.5, 0, 1, -ARROW_BOB)
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 1)
	arrow.Position = arrowRest
	arrow.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
	arrow.FontFace = Theme.Fonts.Bold
	arrow.TextSize = ARROW_SIZE
	-- Ink, never the chapter: a yellow arrow on the page would stand at 1.07 against it.
	arrow.TextColor3 = Theme.Colors.Accent
	arrow.Text = Theme.Glyphs.Down
	arrow.Parent = moreBelow

	local stopBob: (() -> ())? = nil
	local function setBobbing(active: boolean)
		local stop = stopBob
		if active and stop == nil then
			stopBob = Motion.loop(
				arrow,
				{ Position = arrowRest },
				{ Position = UDim2.fromScale(0.5, 1) },
				"UiSnappy",
				ARROW_HOLD
			)
		elseif not active and stop ~= nil then
			stopBob = nil
			stop()
		end
	end
	trove:Add(function()
		setBobbing(false)
		Motion.cancel(arrow)
	end)

	local function update()
		local hidden = content.AbsoluteCanvasSize.Y - content.AbsoluteWindowSize.Y - MORE_BELOW_SLACK
		local more = mode ~= "Track" and content.CanvasPosition.Y < hidden
		moreBelow.Visible = more
		setBobbing(more and shown)
	end
	for _, property in ipairs({ "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" }) do
		trove:Connect(content:GetPropertyChangedSignal(property), update)
	end

	content.Parent = props.Parent
	moreBelow.Parent = props.Parent

	local function setMode(_self: CardContent, next: Mode)
		if next == mode then
			return
		end
		mode = next
		layout:Destroy()
		layout = makeLayout(content, next, props.GridCell)
		update()
	end

	local function setShown(_self: CardContent, next: boolean)
		shown = next
		update()
	end

	-- A child scrolled past, wholly before the window: a list opened on its current row (the pass's tier).
	local function scrolledPast(child: GuiObject): boolean
		if mode == "Track" then
			return child.AbsolutePosition.X + child.AbsoluteSize.X <= content.AbsolutePosition.X
		end
		return child.AbsolutePosition.Y + child.AbsoluteSize.Y <= content.AbsolutePosition.Y
	end

	-- The first children in view spring up one after another, the rest are simply there. Those scrolled
	-- past are left alone: growing one would shift every row in view.
	local function playEnter(_self: CardContent)
		local children: { GuiObject } = {}
		for _, child in ipairs(content:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible and not scrolledPast(child) then
				table.insert(children, child)
			end
		end
		table.sort(children, function(a: GuiObject, b: GuiObject): boolean
			return a.LayoutOrder < b.LayoutOrder
		end)
		local scales: { Instance } = {}
		for index, child in ipairs(children) do
			-- A child that scales itself (a button) enters on its own UIScale: only one per object applies.
			local scale = child:FindFirstChildOfClass("UIScale")
			if scale == nil then
				local created = Instance.new("UIScale")
				created.Name = "Enter"
				created.Parent = child
				scale = created
			end
			local found = scale :: UIScale
			if index <= Theme.Timing.StaggerMax then
				Motion.set(found, { Scale = STAGGER_FROM })
			end
			table.insert(scales, found)
		end
		Motion.stagger(scales, { Scale = 1 }, "UiPop")
		update()
	end

	local function destroy(_self: CardContent)
		trove:Destroy()
	end

	local object: CardContent = {
		Instance = content,
		MoreBelow = moreBelow,
		SetMode = setMode,
		SetShown = setShown,
		PlayEnter = playEnter,
		Destroy = destroy,
	}
	return object
end

return CardContent
