--!strict
-- Tabs: a pill of sheet holding its tabs, and ONE thumb that slides to the selected one (D-147). The thumb
-- wears the screen's chapter colour -- or the tab's own tint, the pigment of a Loadout tab -- and the
-- selected word turns to the ink that reads on it; the others stay muted. A strip too long for its width
-- scrolls sideways rather than cutting a French word. `Select` switches tabs programmatically and fires
-- OnSelect exactly like a click would (nothing happens when the tab is already selected). The `Selected`
-- prop only sets the initial visual state, so screens build their first page explicitly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Badge = require(script.Parent.Badge)
local Icon = require(script.Parent.Icon)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Item = { Id: string, Text: string, Icon: Icon.Name?, Badge: Badge.Value?, Tint: Color3? }

export type Props = {
	Items: { Item },
	Selected: string?,
	OnSelect: (id: string) -> (),
	-- The screen whose chapter colours the thumb (a ThemeConfig.Chapters key). An ink chapter's thumb is
	-- the primary yellow: an ink thumb on an ink band would be nothing.
	Chapter: string?,
	Size: UDim2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Tabs = {
	Instance: ScrollingFrame,
	Select: (self: Tabs, id: string) -> (),
	GetSelected: (self: Tabs) -> string?,
	Destroy: (self: Tabs) -> (),
}

local Tabs = {}

local HEIGHT = 48
local INSET = 4
local MIN_TAB_WIDTH = 96
local TAB_PADDING = 14
local ICON_SIZE = 20
local HOVER_TRANSPARENCY = 0.5

local function thumbFill(chapter: string?): Color3
	if chapter == nil then
		return Theme.Colors.Primary
	end
	local band = Theme.chapter(chapter).Band
	return if band == Theme.Colors.Plate then Theme.Colors.Primary else band
end

-- A pill that sits behind a tab: the selection, or the hover.
local function makeThumb(name: string, color: Color3, zIndex: number): Frame
	local thumb = Instance.new("Frame")
	thumb.Name = name
	thumb.BorderSizePixel = 0
	thumb.BackgroundColor3 = color
	thumb.Size = UDim2.fromScale(0, 1)
	thumb.ZIndex = zIndex
	thumb.Visible = false
	Theme.corner(thumb, Theme.Pill)
	return thumb
end

function Tabs.new(props: Props): Tabs
	local trove = Trove.new()
	local selected: string? = props.Selected
	local hovered: string? = nil
	local defaultFill = thumbFill(props.Chapter)
	local buttons: { [string]: TextButton } = {}
	local labels: { [string]: TextLabel } = {}
	local fills: { [string]: Color3 } = {}

	local track = Instance.new("ScrollingFrame")
	track.Name = props.Name or "Tabs"
	track.BackgroundColor3 = Theme.Colors.PanelRaised
	track.BorderSizePixel = 0
	track.Size = props.Size or UDim2.new(1, 0, 0, HEIGHT)
	track.LayoutOrder = props.LayoutOrder or 0
	-- Sideways only, and without a bar: a strip that fits never scrolls, one that does not slides.
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.ScrollBarThickness = 0
	track.CanvasSize = UDim2.new()
	track.AutomaticCanvasSize = Enum.AutomaticSize.X
	track.ElasticBehavior = Enum.ElasticBehavior.Never
	track.Selectable = false
	Theme.corner(track, Theme.Pill)
	Theme.stroke(track, "Accent", Theme.Sizes.StrokeThin)
	trove:Add(track)

	-- The tabs fill the strip, so flooring the strip is enough to keep every tab tappable.
	Theme.minPixelSize(track, Theme.MinTouchTarget)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, INSET)
	padding.PaddingBottom = UDim.new(0, INSET)
	padding.PaddingLeft = UDim.new(0, INSET)
	padding.PaddingRight = UDim.new(0, INSET)
	padding.Parent = track

	-- The thumbs lie in the strip, under the row of tabs, and are placed in fractions of it: fractions
	-- need no knowledge of the UIScale above, which offsets would.
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AutomaticSize = Enum.AutomaticSize.X
	strip.Size = UDim2.fromScale(0, 1)
	strip.Parent = track

	local hoverThumb = makeThumb("Hover", Theme.Colors.Chalk, 1)
	hoverThumb.BackgroundTransparency = HOVER_TRANSPARENCY
	hoverThumb.Parent = strip
	local thumb = makeThumb("Thumb", defaultFill, 2)
	Theme.stroke(thumb, "Accent", Theme.Sizes.StrokeThin)
	thumb.Parent = strip
	trove:Add(function()
		Motion.cancel(thumb)
	end)

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromScale(0, 1)
	row.ZIndex = 3
	row.Parent = strip
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, INSET)
	layout.Parent = row

	-- Where the tab `id` sits in the strip, in fractions of it; nil before the engine has laid it out.
	local function spanOf(id: string?): (UDim2?, UDim2?)
		local button = if id ~= nil then buttons[id] else nil
		local width = strip.AbsoluteSize.X
		if button == nil or width <= 0 then
			return nil, nil
		end
		local x = (button.AbsolutePosition.X - strip.AbsolutePosition.X) / width
		return UDim2.fromScale(x, 0), UDim2.fromScale(button.AbsoluteSize.X / width, 1)
	end

	local function place(animate: boolean)
		local position, size = spanOf(selected)
		if position ~= nil and size ~= nil then
			thumb.Visible = true
			if animate then
				Motion.to(thumb, { Position = position, Size = size }, "UiSnappy")
			else
				Motion.set(thumb, { Position = position, Size = size })
			end
		else
			thumb.Visible = false
		end
		local hoverPosition, hoverSize = spanOf(if hovered ~= selected then hovered else nil)
		hoverThumb.Visible = hoverPosition ~= nil
		if hoverPosition ~= nil and hoverSize ~= nil then
			hoverThumb.Position = hoverPosition
			hoverThumb.Size = hoverSize
		end
	end

	local function refresh(animate: boolean)
		local fill = if selected ~= nil then fills[selected] or defaultFill else defaultFill
		thumb.BackgroundColor3 = fill
		for id, label in pairs(labels) do
			if id == selected then
				label.TextColor3 = Theme.inkOn(fill)
			elseif id == hovered then
				label.TextColor3 = Theme.Colors.Text
			else
				label.TextColor3 = Theme.Colors.TextMuted
			end
		end
		place(animate)
	end

	local function selectTab(id: string)
		local button: TextButton? = buttons[id]
		if button == nil or selected == id then
			return
		end
		selected = id
		refresh(true)
		props.OnSelect(id)
	end

	for index, item in ipairs(props.Items) do
		local button = Instance.new("TextButton")
		button.Name = item.Id
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Text = ""
		button.LayoutOrder = index
		-- As wide as its word, never narrower than a thumb.
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.new(0, MIN_TAB_WIDTH, 1, 0)
		button.SelectionImageObject = trove:Add(Theme.focusRing())
		local content = Instance.new("UIListLayout")
		content.FillDirection = Enum.FillDirection.Horizontal
		content.HorizontalAlignment = Enum.HorizontalAlignment.Center
		content.VerticalAlignment = Enum.VerticalAlignment.Center
		content.SortOrder = Enum.SortOrder.LayoutOrder
		content.Padding = UDim.new(0, INSET)
		content.Parent = button
		local tabPadding = Instance.new("UIPadding")
		tabPadding.PaddingLeft = UDim.new(0, TAB_PADDING)
		tabPadding.PaddingRight = UDim.new(0, TAB_PADDING)
		tabPadding.Parent = button

		if item.Icon ~= nil then
			local icon = Icon.new(item.Icon, ICON_SIZE)
			icon.LayoutOrder = 1
			icon.Parent = button
		end
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.LayoutOrder = 2
		-- Bold and at 20: large text, so a word on a tint only has to clear 3.
		label.FontFace = Theme.Fonts.Bold
		label.TextSize = Theme.Sizes.TextButton
		label.TextColor3 = Theme.Colors.TextMuted
		label.Text = item.Text
		label.Parent = button
		if item.Badge ~= nil then
			Badge.new(item.Badge, button)
		end

		trove:Connect(button.MouseEnter, function()
			hovered = item.Id
			refresh(false)
		end)
		trove:Connect(button.MouseLeave, function()
			if hovered == item.Id then
				hovered = nil
			end
			refresh(false)
		end)
		trove:Connect(button.SelectionGained, function()
			hovered = item.Id
			refresh(false)
		end)
		trove:Connect(button.SelectionLost, function()
			if hovered == item.Id then
				hovered = nil
			end
			refresh(false)
		end)
		trove:Connect(button.Activated, function()
			selectTab(item.Id)
		end)
		-- A word that lands late (a font still loading) or a new scale moves the tabs: the thumb follows.
		trove:Connect(button:GetPropertyChangedSignal("AbsoluteSize"), function()
			place(false)
		end)

		button.Parent = row
		buttons[item.Id] = button
		labels[item.Id] = label
		local tint = item.Tint
		if tint ~= nil then
			fills[item.Id] = tint
		end
	end
	trove:Connect(strip:GetPropertyChangedSignal("AbsoluteSize"), function()
		place(false)
	end)

	refresh(false)
	track.Parent = props.Parent

	local function selectMethod(_self: Tabs, id: string)
		selectTab(id)
	end

	local function getSelected(_self: Tabs): string?
		return selected
	end

	local function destroy(_self: Tabs)
		trove:Destroy()
	end

	local object: Tabs = {
		Instance = track,
		Select = selectMethod,
		GetSelected = getSelected,
		Destroy = destroy,
	}
	return object
end

return Tabs
