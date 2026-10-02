--!strict
-- UndoStrip: a card that rises from the foot of a screen's card after a change, says what changed, and
-- offers to undo it for a few seconds (ThemeConfig.Timing.UndoSeconds, D-147). A toast cannot hold a
-- button; this can, and it stays inside the screen it belongs to.
--
-- It fades and slides as one piece in a CanvasGroup of its own -- one group per visible strip, like a
-- toast (ThemeConfig.Budget) -- so its screen puts it away (Hide(false)) before the card's own exit
-- fades the card in a group, and no group is ever drawn inside another.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Button)
local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	-- The word of the way back ("Undo").
	ActionText: string,
	-- The screen's card: the strip rises from its foot.
	Parent: Instance,
}

export type UndoStrip = {
	Instance: CanvasGroup,
	-- Says `message`, and runs `onUndo` if the player asks before the strip goes. A second change replaces
	-- the first: only the last one can be undone.
	Show: (self: UndoStrip, message: string, onUndo: () -> ()) -> (),
	Hide: (self: UndoStrip, animate: boolean) -> (),
	Destroy: (self: UndoStrip) -> (),
}

local UndoStrip = {}

local HEIGHT = 60
local WIDTH = 0.9
local MAX_WIDTH = 560
local ELEVATION = 4
-- It rests this far above the foot of the card, and rises from this far below where it rests.
local REST = -Theme.Sizes.Padding
local RISE = 24

function UndoStrip.new(props: Props): UndoStrip
	local trove = Trove.new()
	local pending: (() -> ())? = nil
	local token = 0

	local group = Instance.new("CanvasGroup")
	group.Name = "Undo"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 1)
	group.Position = UDim2.new(0.5, 0, 1, REST + RISE)
	group.Size = UDim2.new(WIDTH, 0, 0, HEIGHT + ELEVATION)
	group.GroupTransparency = 1
	group.ZIndex = 10
	group.Visible = false
	trove:Add(group)
	trove:Add(function()
		Motion.cancel(group)
	end)
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	cap.Parent = group

	local card = Sticker.new({
		Kind = "Card",
		Fill = Theme.Colors.PanelRaised,
		Corner = UDim.new(0, Theme.Sizes.CornerCard),
		Elevation = ELEVATION,
		Name = "Strip",
		Parent = group,
	})
	trove:Add(function()
		card:Destroy()
	end)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingSmall)
	padding.Parent = card.Face
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = card.Face

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.BackgroundTransparency = 1
	message.Size = UDim2.fromScale(0, 1)
	message.LayoutOrder = 1
	message.FontFace = Theme.Fonts.Bold
	message.TextSize = Theme.Sizes.TextBody
	message.TextColor3 = Theme.Colors.Text
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.TextWrapped = true
	message.Text = ""
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = message
	message.Parent = card.Face

	local function hide(_self: UndoStrip?, animate: boolean)
		token += 1
		pending = nil
		if not animate or not group.Visible then
			Motion.cancel(group)
			group.Visible = false
			group.GroupTransparency = 1
			return
		end
		local mine = token
		Motion.to(group, { Position = UDim2.new(0.5, 0, 1, REST + RISE) }, "UiExit")
		Motion.to(group, { GroupTransparency = 1 }, "UiExit", function()
			if token == mine then
				group.Visible = false
			end
		end)
	end

	local button = Button.new({
		Name = "Undo",
		Text = props.ActionText,
		Variant = "Ghost",
		LayoutOrder = 2,
		Parent = card.Face,
		OnClick = function()
			local onUndo = pending
			hide(nil, true)
			if onUndo ~= nil then
				onUndo()
			end
		end,
	})
	trove:Add(function()
		button:Destroy()
	end)

	local function show(_self: UndoStrip, text: string, onUndo: () -> ())
		pending = onUndo
		message.Text = text
		token += 1
		local mine = token
		if not group.Visible then
			group.Visible = true
			Motion.set(group, { Position = UDim2.new(0.5, 0, 1, REST + RISE) })
		end
		Motion.to(group, { Position = UDim2.new(0.5, 0, 1, REST) }, "UiPop")
		Motion.to(group, { GroupTransparency = 0 }, "Ui")
		task.delay(Theme.Timing.UndoSeconds, function()
			if token == mine then
				hide(nil, true)
			end
		end)
	end

	group.Parent = props.Parent

	local function destroy(_self: UndoStrip)
		trove:Destroy()
	end

	local object: UndoStrip = {
		Instance = group,
		Show = show,
		Hide = hide,
		Destroy = destroy,
	}
	return object
end

return UndoStrip
