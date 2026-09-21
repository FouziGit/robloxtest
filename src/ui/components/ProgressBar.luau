--!strict
-- ProgressBar: a track, a fill that springs to its value, a centered label, and -- when asked -- a ghost.
--
-- The ghost is the bar the plan calls "barre de vie avec fantôme qui rattrape". When the value drops, the
-- fill snaps down and a second fill in the colour of what was lost stays where the value WAS and catches
-- up slowly, so a hit reads as a chunk taken out of the bar rather than as a bar that is now shorter.
-- When the value rises the ghost is simply there already: nothing was lost. Both movements are springs
-- (src/ui/Motion.luau); the ghost's is the one spring in the interface that may never overshoot, because
-- an overshoot on a health bar is health coming back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Color: Color3?,
	Progress: number?, -- 0..1
	Label: string?,
	Size: UDim2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
	-- Draw the ghost of what was lost, in this colour. Absent means no ghost: a level bar only rises.
	Ghost: Color3?,
}

export type ProgressBar = {
	Instance: Frame,
	SetProgress: (self: ProgressBar, progress: number) -> (),
	SetLabel: (self: ProgressBar, text: string) -> (),
	SetColor: (self: ProgressBar, color: Color3) -> (),
	Destroy: (self: ProgressBar) -> (),
}

local ProgressBar = {}

local DEFAULT_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall

local function roundCorners(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = parent
end

function ProgressBar.new(props: Props): ProgressBar
	local trove = Trove.new()
	local current = math.clamp(props.Progress or 0, 0, 1)

	local track = Instance.new("Frame")
	track.Name = props.Name or "ProgressBar"
	track.BackgroundColor3 = Theme.Colors.PanelRaised
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Size = props.Size or UDim2.new(1, 0, 0, DEFAULT_HEIGHT)
	track.LayoutOrder = props.LayoutOrder or 0
	trove:Add(track)
	roundCorners(track)

	local ghost: Frame? = nil
	if props.Ghost ~= nil then
		local frame = Instance.new("Frame")
		frame.Name = "Ghost"
		frame.BackgroundColor3 = props.Ghost
		frame.BorderSizePixel = 0
		frame.ZIndex = 1
		frame.Size = UDim2.fromScale(current, 1)
		frame.Parent = track
		roundCorners(frame)
		ghost = frame
	end

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = props.Color or Theme.Colors.Accent
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Size = UDim2.fromScale(current, 1)
	fill.Parent = track
	roundCorners(fill)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.FontFace = Theme.Fonts.Numeric
	label.TextSize = Theme.Sizes.TextBody
	-- Ink on the page, and the page on ink: the label sits over both halves of the bar, so it is stroked
	-- in the opposite colour to stay legible on either.
	label.TextColor3 = Theme.Colors.TextInverse
	label.TextStrokeColor3 = Theme.Colors.Text
	label.TextStrokeTransparency = 0.35
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = props.Label or ""
	label.Parent = track

	trove:Add(function()
		Motion.cancel(fill)
		if ghost ~= nil then
			Motion.cancel(ghost)
		end
	end)

	track.Parent = props.Parent

	local function setProgress(_self: ProgressBar, progress: number)
		local clamped = math.clamp(progress, 0, 1)
		local goal = UDim2.fromScale(clamped, 1)
		local shadow = ghost
		if shadow ~= nil then
			if clamped < current then
				-- Lost: the fill drops now, the ghost stays and catches up.
				Motion.to(fill, { Size = goal }, "UiSnappy")
				Motion.to(shadow, { Size = goal }, "UiGhost")
			else
				-- Gained: there is no ghost to a gain, so it rides with the fill.
				Motion.to(fill, { Size = goal }, "Ui")
				Motion.set(shadow, { Size = goal })
			end
		else
			Motion.to(fill, { Size = goal }, "Ui")
		end
		current = clamped
	end

	local function setLabel(_self: ProgressBar, text: string)
		label.Text = text
	end

	local function setColor(_self: ProgressBar, color: Color3)
		fill.BackgroundColor3 = color
	end

	local function destroy(_self: ProgressBar)
		trove:Destroy()
	end

	local object: ProgressBar = {
		Instance = track,
		SetProgress = setProgress,
		SetLabel = setLabel,
		SetColor = setColor,
		Destroy = destroy,
	}
	return object
end

return ProgressBar
