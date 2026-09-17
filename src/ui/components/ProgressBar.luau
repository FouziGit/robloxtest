--!strict
-- ProgressBar: rounded track with an animated fill and a centered label.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

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
	local currentTween: Tween? = nil

	local track = Instance.new("Frame")
	track.Name = props.Name or "ProgressBar"
	track.BackgroundColor3 = Theme.Colors.PanelRaised
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Size = props.Size or UDim2.new(1, 0, 0, DEFAULT_HEIGHT)
	track.LayoutOrder = props.LayoutOrder or 0
	trove:Add(track)
	roundCorners(track)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = props.Color or Theme.Colors.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(math.clamp(props.Progress or 0, 0, 1), 1)
	fill.Parent = track
	roundCorners(fill)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Font = Theme.Fonts.Bold
	label.TextSize = Theme.Sizes.TextSmall
	label.TextColor3 = Theme.Colors.Text
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = props.Label or ""
	label.Parent = track

	trove:Add(function()
		if currentTween ~= nil then
			currentTween:Cancel()
			currentTween = nil
		end
	end)

	track.Parent = props.Parent

	local function setProgress(_self: ProgressBar, progress: number)
		local clamped = math.clamp(progress, 0, 1)
		if currentTween ~= nil then
			currentTween:Cancel()
		end
		local tween = TweenService:Create(
			fill,
			TweenInfo.new(Theme.Animation.Normal, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(clamped, 1) }
		)
		currentTween = tween
		tween:Play()
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
