--!strict
-- Panel: centered card with a title bar, optional close button, fixed Header / Footer slots and a
-- scrolling Content area. The frame fills its parent minus a margin and is capped at `Size`
-- (Theme panel size by default), so it fits 16:9 phones without any per-device code. When a D-pad press
-- leaves the gamepad selection where it was, the panel scrolls the content itself (see scrollRows).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

-- Height of a fixed band. A band whose controls carry the touch minimum passes a callback instead of a
-- number: the minimum follows the viewport, and only the callback is re-read by the relayout below, which
-- already runs on every scale change. A plain number stays as given (0 hides the band).
export type Height = number | (() -> number)

export type Props = {
	Title: string,
	Size: Vector2?, -- max size in px at UIScale 1
	Closable: boolean?,
	OnClose: (() -> ())?,
	AspectRatio: number?, -- optional UIAspectRatioConstraint
	Parent: Instance?,
	Name: string?,
}

export type Panel = {
	Instance: Frame,
	Header: Frame,
	Content: ScrollingFrame,
	Footer: Frame,
	CloseButton: TextButton?,
	SetTitle: (self: Panel, title: string) -> (),
	SetHeaderHeight: (self: Panel, height: Height) -> (),
	SetFooterHeight: (self: Panel, height: Height) -> (),
	-- Gamepad focus. A screen that never sets GuiService.SelectedObject leaves the D-pad dead until the
	-- player presses the navigation button a second time, so screens take the selection on Open
	-- (`target` defaults to the close button) and hand it back on Close.
	FocusForGamepad: (self: Panel, target: GuiObject?) -> (),
	ReleaseGamepadFocus: (self: Panel) -> (),
	Destroy: (self: Panel) -> (),
}

local Panel = {}

-- Rule 3 of docs/ART_BIBLE.md, "rien n'apparaît": the card grows into place from just under its size,
-- about its own centre, whenever the screen it belongs to is enabled.
local ENTER_SCALE = 0.94

local CLOSE_GLYPH = "✕" -- icon glyph, locale independent
local DPAD_SCROLL_ROWS = 1 -- canvas step per D-pad press, in list rows
-- Absorbs the rounding between a band height computed here and the UISizeConstraint the engine applies to
-- the control inside it, so one pixel of disagreement cannot push that control out of its band.
local BAND_SLACK = 1

local function horizontalPadding(parent: Instance, top: number, bottom: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.Parent = parent
	return padding
end

local function makeCloseButton(trove: typeof(Trove.new()), onClose: (() -> ())?): TextButton
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -Theme.Sizes.PaddingSmall, 0.5, 0)
	close.Size = UDim2.fromOffset(Theme.Sizes.RowHeight, Theme.Sizes.RowHeight)
	close.BackgroundColor3 = Theme.Colors.PanelRaised
	close.BackgroundTransparency = 1
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.FontFace = Theme.Fonts.Bold
	close.TextSize = Theme.Sizes.TextLarge
	close.TextColor3 = Theme.Colors.TextMuted
	close.Text = CLOSE_GLYPH
	close.Selectable = true
	-- On touch this cross is the only way out of an open screen, so it never renders below the minimum.
	Theme.minPixelSize(close, Theme.MinTouchTarget)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = close

	local function setHighlighted(highlighted: boolean)
		close.BackgroundTransparency = if highlighted then 0 else 1
		close.TextColor3 = if highlighted then Theme.Colors.Danger else Theme.Colors.TextMuted
	end

	trove:Connect(close.MouseEnter, function()
		setHighlighted(true)
	end)
	trove:Connect(close.MouseLeave, function()
		setHighlighted(false)
	end)
	trove:Connect(close.SelectionGained, function()
		setHighlighted(true)
	end)
	trove:Connect(close.SelectionLost, function()
		setHighlighted(false)
	end)
	trove:Connect(close.Activated, function()
		if onClose ~= nil then
			onClose()
		end
	end)

	return close
end

function Panel.new(props: Props): Panel
	local trove = Trove.new()
	local maxSize = props.Size or Vector2.new(Theme.Sizes.PanelWidth, Theme.Sizes.PanelHeight)

	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, -Theme.Sizes.Padding * 2, 1, -Theme.Sizes.Padding * 2)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	trove:Add(frame)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = maxSize
	sizeConstraint.Parent = frame

	local entrance = Instance.new("UIScale")
	entrance.Name = "Entrance"
	entrance.Parent = frame
	trove:Add(function()
		Motion.cancel(entrance)
	end)

	if props.AspectRatio ~= nil then
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = props.AspectRatio
		aspect.AspectType = Enum.AspectType.FitWithinMaxSize
		aspect.Parent = frame
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundTransparency = 1
	titleBar.Parent = frame

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0, 1)
	divider.Position = UDim2.fromScale(0, 1)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = Theme.Colors.Border
	divider.BorderSizePixel = 0
	divider.Parent = titleBar

	local closeButton: TextButton? = nil
	if props.Closable == true then
		local close = makeCloseButton(trove, props.OnClose)
		close.Parent = titleBar
		closeButton = close
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(Theme.Sizes.Padding, 0)
	title.FontFace = Theme.Fonts.Title
	title.TextSize = Theme.Sizes.TextTitle
	title.TextColor3 = Theme.Colors.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = props.Title
	title.Parent = titleBar

	-- Fixed header slot (tabs, summaries)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromScale(1, 0)
	header.Parent = frame
	horizontalPadding(header, Theme.Sizes.PaddingSmall, Theme.Sizes.PaddingSmall)

	-- Fixed footer slot (action buttons)
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.fromScale(1, 0)
	footer.Parent = frame
	horizontalPadding(footer, Theme.Sizes.PaddingSmall, Theme.Sizes.Padding)

	-- Scrolling content
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Selectable = false
	content.ScrollBarThickness = Theme.Sizes.PaddingSmall
	content.ScrollBarImageColor3 = Theme.Colors.Border
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	content.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	content.Parent = frame
	horizontalPadding(content, Theme.Sizes.Padding, Theme.Sizes.Padding)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = content

	local headerHeight: Height = 0
	local footerHeight: Height = 0

	local function bandHeight(height: Height): number
		local value: number
		if type(height) == "function" then
			value = height()
		else
			value = height
		end
		if value <= 0 then
			return 0
		end
		return value + BAND_SLACK
	end

	-- The title bar holds the close button, so it follows the same minimum: on a phone the unscaled
	-- touch row is taller than Theme.Sizes.RowHeight and the cross would otherwise overflow the bar.
	local function relayout()
		local titleHeight = Theme.touchTargetHeight(Theme.Sizes.RowHeight) + Theme.Sizes.PaddingSmall * 2
		local headerSize = bandHeight(headerHeight)
		local footerSize = bandHeight(footerHeight)
		-- The cross is square, so the width it needs is the height of the bar around it.
		local titleRightMargin = if closeButton ~= nil then titleHeight else Theme.Sizes.Padding
		titleBar.Size = UDim2.new(1, 0, 0, titleHeight)
		title.Size = UDim2.new(1, -(Theme.Sizes.Padding + titleRightMargin), 1, 0)
		header.Position = UDim2.fromOffset(0, titleHeight)
		header.Size = UDim2.new(1, 0, 0, headerSize)
		footer.Size = UDim2.new(1, 0, 0, footerSize)
		content.Position = UDim2.fromOffset(0, titleHeight + headerSize)
		content.Size = UDim2.new(1, 0, 1, -(titleHeight + headerSize + footerSize))
	end
	trove:Add(Theme.bindScale(relayout))

	local function scrollRows(rows: number)
		local maximum = math.max(0, content.AbsoluteCanvasSize.Y - content.AbsoluteWindowSize.Y)
		-- CanvasPosition is in rendered pixels, the row pitch in unscaled offsets.
		local step = (Theme.touchTargetHeight(Theme.Sizes.RowHeight) + Theme.Sizes.Gap) * Theme.activeScale()
		local position = content.CanvasPosition
		content.CanvasPosition = Vector2.new(position.X, math.clamp(position.Y + rows * step, 0, maximum))
	end

	-- Roblox only scrolls a ScrollingFrame when GuiService.SelectedObject travels inside it, so a canvas the
	-- engine has nowhere left to walk to is frozen for a gamepad player: a read-only list has nothing to
	-- select, and a long list whose few selectable cells all sit behind the selection is just as stuck. The
	-- panel then steps the canvas itself, but only once it has seen the press move the selection nowhere --
	-- stepping while the engine is auto-scrolling towards a new selection would fight it.
	-- The step is decided a frame after the press, by which time the panel may already be destroyed.
	local alive = true
	trove:Add(function()
		alive = false
	end)
	local stepPending = false

	local function stepUnlessSelectionMoves(rows: number, before: GuiObject)
		if stepPending then
			return
		end
		stepPending = true
		RunService.Heartbeat:Once(function()
			stepPending = false
			if not alive or GuiService.SelectedObject ~= before then
				return
			end
			scrollRows(rows)
		end)
	end

	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		local rows = if input.KeyCode == Enum.KeyCode.DPadDown
			then DPAD_SCROLL_ROWS
			elseif input.KeyCode == Enum.KeyCode.DPadUp then -DPAD_SCROLL_ROWS
			else 0
		if rows == 0 then
			return
		end
		-- Scoped to the panel holding the selection: another open panel must not scroll with it.
		local selected = GuiService.SelectedObject
		if selected == nil or not selected:IsDescendantOf(frame) then
			return
		end
		stepUnlessSelectionMoves(rows, selected)
	end)

	frame.Parent = props.Parent

	-- The screen this card belongs to. Screens show themselves by enabling their ScreenGui, so that is
	-- where the card learns it is being opened; it is resolved after parenting, when the ancestor exists.
	local screen = frame:FindFirstAncestorWhichIsA("ScreenGui")
	if screen ~= nil then
		trove:Connect(screen:GetPropertyChangedSignal("Enabled"), function()
			if screen.Enabled then
				Motion.set(entrance, { Scale = ENTER_SCALE })
				Motion.to(entrance, { Scale = 1 }, "UiSnappy")
			end
		end)
	end

	local function setTitle(_self: Panel, text: string)
		title.Text = text
	end

	local function setHeaderHeight(_self: Panel, height: Height)
		headerHeight = height
		relayout()
	end

	local function setFooterHeight(_self: Panel, height: Height)
		footerHeight = height
		relayout()
	end

	-- No-op without a gamepad, so screens can call it unconditionally. The ScreenGui must already be
	-- enabled: the engine drops a selection pointing inside a disabled ScreenGui.
	local function focusForGamepad(_self: Panel, target: GuiObject?)
		if not UserInputService.GamepadEnabled then
			return
		end
		local focus: GuiObject? = target or closeButton
		if focus == nil then
			return
		end
		GuiService.SelectedObject = focus
	end

	-- Only releases a selection that belongs to this panel, so a screen closing behind another one
	-- (menu navigation) never steals the focus the new screen just took.
	local function releaseFocus()
		local selected = GuiService.SelectedObject
		if selected ~= nil and selected:IsDescendantOf(frame) then
			GuiService.SelectedObject = nil
		end
	end

	local function releaseGamepadFocus(_self: Panel)
		releaseFocus()
	end

	local function destroy(_self: Panel)
		releaseFocus()
		trove:Destroy()
	end

	local object: Panel = {
		Instance = frame,
		Header = header,
		Content = content,
		Footer = footer,
		CloseButton = closeButton,
		SetTitle = setTitle,
		SetHeaderHeight = setHeaderHeight,
		SetFooterHeight = setFooterHeight,
		FocusForGamepad = focusForGamepad,
		ReleaseGamepadFocus = releaseGamepadFocus,
		Destroy = destroy,
	}
	return object
end

return Panel
