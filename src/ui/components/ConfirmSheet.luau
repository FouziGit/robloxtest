--!strict
-- ConfirmSheet: the question a screen asks before it does something that costs (D-147) -- a purchase, a
-- reset. A sheet slides up from the bottom of the card over an ink scrim: a title, a line, an optional
-- preview, and two buttons, the confirmation on the right. Nothing is bought on one tap anywhere else.
--
-- The safe answer is the default: the gamepad's focus lands on Cancel, and B cancels (bound above the
-- game's own actions and sunk, so it never also closes the screen behind). The sheet does not close
-- itself on an answer: the caller decides, because a purchase waits for the server before it goes.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Button)
local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Answer = { Text: string, Variant: Button.Variant? }

export type Props = {
	Title: string,
	Body: string,
	Preview: GuiObject?,
	Confirm: Answer,
	Cancel: Answer,
	OnConfirm: () -> (),
	OnCancel: () -> (),
	-- The screen's card: the scrim covers it and the sheet rises from its bottom edge.
	Parent: GuiObject,
}

export type ConfirmSheet = {
	Instance: Frame,
	ConfirmButton: Button.Button,
	CancelButton: Button.Button,
	-- Slides the sheet away, then destroys it and calls `onDone`.
	Close: (self: ConfirmSheet, onDone: (() -> ())?) -> (),
	Destroy: (self: ConfirmSheet) -> (),
}

local ConfirmSheet = {}

local WIDTH = 520
local ELEVATION = 5
local SLIDE = 80
local SCRIM_TRANSPARENCY = 0.35
local TITLE_SIZE = 26
local LAYER = 50
-- Above the game's own actions (InputController binds at High), so B answers the sheet and nothing else.
local CANCEL_PRIORITY = Enum.ContextActionPriority.High.Value + 1

local opened = 0

function ConfirmSheet.new(props: Props): ConfirmSheet
	local trove = Trove.new()
	opened += 1
	local cancelAction = "ConfirmSheetCancel" .. opened

	local scrim = Instance.new("Frame")
	scrim.Name = "ConfirmSheet"
	scrim.BorderSizePixel = 0
	scrim.BackgroundColor3 = Theme.Colors.Plate
	scrim.BackgroundTransparency = 1
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.ZIndex = LAYER
	-- Takes the clicks meant for the card behind it.
	scrim.Active = true
	trove:Add(scrim)
	trove:Add(function()
		Motion.cancel(scrim)
	end)

	local sheet = Sticker.new({
		Kind = "Card",
		Fill = Theme.Colors.PanelRaised,
		Elevation = ELEVATION,
		Size = UDim2.new(1, -Theme.Sizes.Padding * 2, 0, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, SLIDE),
		Name = "Sheet",
	})
	trove:Add(function()
		sheet:Destroy()
	end)
	local root = sheet.Instance
	root.ZIndex = LAYER + 1
	root.AutomaticSize = Enum.AutomaticSize.Y
	local widest = Instance.new("UISizeConstraint")
	widest.MaxSize = Vector2.new(WIDTH, math.huge)
	widest.Parent = root
	trove:Add(function()
		Motion.cancel(root)
	end)

	-- The content sizes the sheet: its face and shadow fill whatever height it asks, less the shadow.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.fromScale(1, 0)
	content.ZIndex = LAYER + 2
	content.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingBottom = UDim.new(0, Theme.Sizes.Padding + ELEVATION)
	padding.Parent = content
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Theme.Sizes.Gap)
	list.Parent = content

	local function text(name: string, value: string, font: Font, size: number, order: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.fromScale(1, 0)
		label.FontFace = font
		label.TextSize = size
		label.TextColor3 = Theme.Colors.Text
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = value
		label.LayoutOrder = order
		label.ZIndex = LAYER + 2
		label.Parent = content
		return label
	end
	text("Title", props.Title, Theme.Fonts.Title, TITLE_SIZE, 1)
	text("Body", props.Body, Theme.Fonts.Body, Theme.Sizes.TextBody, 2)

	local preview = props.Preview
	if preview ~= nil then
		preview.LayoutOrder = 3
		preview.Parent = content
	end

	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.AutomaticSize = Enum.AutomaticSize.Y
	footer.Size = UDim2.fromScale(1, 0)
	footer.LayoutOrder = 4
	footer.ZIndex = LAYER + 2
	footer.Parent = content
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Right
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, Theme.Sizes.Gap)
	row.Parent = footer

	local function answer(which: Answer, variant: Button.Variant, order: number, onClick: () -> ()): Button.Button
		local button = Button.new({
			Text = which.Text,
			Variant = which.Variant or variant,
			Size = UDim2.fromOffset(0, Theme.Sizes.ButtonHeight),
			LayoutOrder = order,
			Parent = footer,
			OnClick = onClick,
		})
		button.Instance.AutomaticSize = Enum.AutomaticSize.X
		trove:Add(function()
			button:Destroy()
		end)
		return button
	end
	local cancelButton = answer(props.Cancel, "Secondary", 1, props.OnCancel)
	local confirmButton = answer(props.Confirm, "Primary", 2, props.OnConfirm)

	ContextActionService:BindActionAtPriority(cancelAction, function(_name, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		task.defer(props.OnCancel)
		return Enum.ContextActionResult.Sink
	end, false, CANCEL_PRIORITY, Enum.KeyCode.ButtonB)
	trove:Add(function()
		ContextActionService:UnbindAction(cancelAction)
	end)

	root.Parent = scrim
	scrim.Parent = props.Parent

	-- In: the scrim darkens and the sheet rises from under the card's edge.
	Motion.to(scrim, { BackgroundTransparency = SCRIM_TRANSPARENCY * UiPrefs.transparency() }, "Ui")
	Motion.to(root, { Position = UDim2.new(0.5, 0, 1, -Theme.Sizes.Padding) }, "UiPop")
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = cancelButton.Instance
	end

	local closing = false
	local function close(_self: ConfirmSheet, onDone: (() -> ())?)
		if closing then
			return
		end
		closing = true
		-- The answers are given: neither button is pressed again while the sheet slides away.
		for _, button in ipairs({ cancelButton, confirmButton }) do
			if not button:IsDisabled() then
				button:SetDisabled(true)
			end
		end
		ContextActionService:UnbindAction(cancelAction)
		if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(scrim) then
			GuiService.SelectedObject = nil
		end
		Motion.to(scrim, { BackgroundTransparency = 1 }, "Ui")
		Motion.to(root, { Position = UDim2.new(0.5, 0, 1, SLIDE) }, "UiExit", function()
			trove:Destroy()
			if onDone ~= nil then
				onDone()
			end
		end)
	end

	local function destroy(_self: ConfirmSheet)
		trove:Destroy()
	end

	local object: ConfirmSheet = {
		Instance = scrim,
		ConfirmButton = confirmButton,
		CancelButton = cancelButton,
		Close = close,
		Destroy = destroy,
	}
	return object
end

return ConfirmSheet
