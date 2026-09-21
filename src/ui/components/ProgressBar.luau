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
	-- `immediate` writes the value now, with no motion: where an animated bar starts from.
	SetProgress: (self: ProgressBar, progress: number, immediate: boolean?) -> (),
	SetLabel: (self: ProgressBar, text: string) -> (),
	SetColor: (self: ProgressBar, color: Color3) -> (),
	Destroy: (self: ProgressBar) -> (),
}

local ProgressBar = {}

local DEFAULT_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local TRACK_EDGE_TRANSPARENCY = 0.55
local LABEL_HALO_TRANSPARENCY = 0.15

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

	-- An edge of ink. The HUD's bars float over a world that is itself the colour of paper, so a pale
	-- track with no edge has no shape at all out there.
	local edge = Instance.new("UIStroke")
	edge.Color = Theme.Colors.Outline
	edge.Thickness = 1
	edge.Transparency = TRACK_EDGE_TRANSPARENCY
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = track

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
	-- The label crosses the boundary between the ink that is left and the paper that is empty, so neither
	-- colour alone can carry it: it is ink with a halo of page. Over the paper it is charcoal on vellum;
	-- over the fill the halo is what draws the digits. Vellum text with an ink stroke, which is what this
	-- was, measured 1.19 against the track -- an outline with nothing inside it, exactly when a bar is
	-- nearly empty and its number matters most.
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeColor3 = Theme.Colors.TextInverse
	label.TextStrokeTransparency = LABEL_HALO_TRANSPARENCY
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

	local function setProgress(_self: ProgressBar, progress: number, immediate: boolean?)
		local clamped = math.clamp(progress, 0, 1)
		local goal = UDim2.fromScale(clamped, 1)
		local shadow = ghost
		if immediate then
			Motion.set(fill, { Size = goal })
			if shadow ~= nil then
				Motion.set(shadow, { Size = goal })
			end
		elseif shadow ~= nil then
			if clamped < current then
				-- Lost: the fill drops now, the ghost stays and catches up.
				Motion.to(fill, { Size = goal }, "UiSnappy")
				Motion.to(shadow, { Size = goal }, "UiGhost")
			else
				-- Gained: there is no ghost to a gain, so it rides WITH the fill, from where the fill is
				-- now. Writing the goal straight onto it -- which is what this did -- put the ghost ahead
				-- of the fill for the whole rise, so every heal, every out-of-combat tick and the first
				-- frame of the HUD drew a band of Cinnabar where health had just been gained.
				Motion.set(shadow, { Size = fill.Size })
				Motion.to(shadow, { Size = goal }, "Ui")
				Motion.to(fill, { Size = goal }, "Ui")
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
