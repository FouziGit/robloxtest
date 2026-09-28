--!strict
-- ProgressBar: an inkwell track, a vivid fill that springs to its value, a number, and -- when asked -- a
-- ghost (D-147). On the page the track wears the ink outline every sticker wears; on an HUD plate, a ring of
-- the sheet, since ink on ink is nothing. The number is the sheet in an ink stroke, which reads over the
-- fill and over the empty track alike (16.34 against its stroke).
--
-- The ghost is the bar the plan calls "barre de vie avec fantôme qui rattrape". When the value drops, the
-- fill snaps down and a second fill in the colour of what was lost stays where the value WAS and catches
-- up slowly, so a hit reads as a chunk taken out of the bar rather than as a bar that is now shorter.
-- When the value rises the ghost is simply there already: nothing was lost. Both movements are springs
-- (src/ui/Motion.luau); the ghost's is the one spring in the interface that may never overshoot, because
-- an overshoot on a health bar is health coming back.
--
-- Low (SetLow) is imminent danger, the one place red enters the bar: the fill turns red, ink hatching
-- runs through it and it pulses -- three cues, so colour is never the only one.

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
	-- On an HUD plate: a ring of the sheet instead of the ink outline, and a vellum number.
	OnPlate: boolean?,
	-- Fractions to mark on the track: a glyph's cost, quarters, a boss's phases.
	Ticks: { number }?,
	-- The number beside the bar, to its right, rather than on it.
	LabelOutside: boolean?,
	-- Height of the track in design units, when no Size is given.
	Height: number?,
}

export type ProgressBar = {
	Instance: Frame,
	-- `immediate` writes the value now, with no motion: where an animated bar starts from.
	SetProgress: (self: ProgressBar, progress: number, immediate: boolean?) -> (),
	SetLabel: (self: ProgressBar, text: string) -> (),
	SetColor: (self: ProgressBar, color: Color3) -> (),
	SetLow: (self: ProgressBar, low: boolean) -> (),
	-- A flash of the fill and a "+N" that rises off it: ink gained, a reward.
	Gain: (self: ProgressBar, amount: number, label: string?) -> (),
	SetTicks: (self: ProgressBar, ticks: { number }) -> (),
	Destroy: (self: ProgressBar) -> (),
}

local ProgressBar = {}

local DEFAULT_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local LABEL_STROKE = 2
local LABEL_GAP = 8
local TICK_WIDTH = 2
local TICK_TRANSPARENCY = 0.3
local HATCH_BARS = 6
local HATCH_WIDTH = 3
local HATCH_TRANSPARENCY = 0.6
local LOW_PULSE = 0.2
local LOW_HOLD = 0.25
local GAIN_SHADE = 0.15
local GAIN_RISE = 24
local GAIN_TEXT_SIZE = 18
-- WCAG 1.4.11: a fill has to stand 3 apart from the track it runs in.
local GRAPHIC_CONTRAST = 3

-- The track a fill runs in: the inkwell, unless the fill would vanish into it -- an ink fill, which a
-- screen still draws its level with -- and then the sheet, where ink reads.
local function trackFor(fill: Color3): Color3
	if Theme.contrast(fill, Theme.Colors.Well) >= GRAPHIC_CONTRAST then
		return Theme.Colors.Well
	end
	return Theme.Colors.PanelRaised
end

function ProgressBar.new(props: Props): ProgressBar
	local trove = Trove.new()
	local current = math.clamp(props.Progress or 0, 0, 1)
	local color = props.Color or Theme.Colors.Accent
	local low = false
	local stopPulse: (() -> ())? = nil

	-- The bar and its number: the number may hang outside the track, which clips what is inside it.
	local root = Instance.new("Frame")
	root.Name = props.Name or "ProgressBar"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = props.Size or UDim2.new(1, 0, 0, props.Height or DEFAULT_HEIGHT)
	root.LayoutOrder = props.LayoutOrder or 0
	trove:Add(root)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = trackFor(color)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Size = UDim2.fromScale(1, 1)
	Theme.corner(track, Theme.Pill)
	if props.OnPlate then
		-- A well on a plate is 1.23 against it: the ring of the sheet is what shapes it.
		Theme.stroke(track, "PanelRaised", Theme.Sizes.StrokeThin)
	else
		Theme.stroke(track, "Accent", Theme.Sizes.Stroke)
	end
	track.Parent = root

	local ghost: Frame? = nil
	if props.Ghost ~= nil then
		local frame = Instance.new("Frame")
		frame.Name = "Ghost"
		frame.BackgroundColor3 = props.Ghost
		frame.BorderSizePixel = 0
		frame.ZIndex = 1
		frame.Size = UDim2.fromScale(current, 1)
		Theme.corner(frame, Theme.Pill)
		frame.Parent = track
		ghost = frame
	end

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.ClipsDescendants = true
	fill.Size = UDim2.fromScale(current, 1)
	Theme.corner(fill, Theme.Pill)
	fill.Parent = track

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BorderSizePixel = 0
	gloss.BackgroundColor3 = Theme.Colors.PanelRaised
	gloss.Size = UDim2.fromScale(1, 0.45)
	gloss.ZIndex = 3
	Theme.corner(gloss, Theme.Pill)
	Theme.gradient("Gloss").Parent = gloss
	gloss.Parent = fill

	-- Ink hatching through the fill, shown only when low; the fill clips it.
	local hatch = Instance.new("Frame")
	hatch.Name = "Hatch"
	hatch.BackgroundTransparency = 1
	hatch.Size = UDim2.fromScale(1, 1)
	hatch.ZIndex = 3
	hatch.Visible = false
	for index = 1, HATCH_BARS do
		local bar = Instance.new("Frame")
		bar.Name = "Stripe"
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Theme.Colors.Accent
		bar.BackgroundTransparency = HATCH_TRANSPARENCY
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale((index - 0.5) / HATCH_BARS, 0.5)
		bar.Size = UDim2.new(0, HATCH_WIDTH, 2, 0)
		bar.Rotation = 45
		bar.ZIndex = 3
		bar.Parent = hatch
	end
	hatch.Parent = fill

	local ticks = Instance.new("Frame")
	ticks.Name = "Ticks"
	ticks.BackgroundTransparency = 1
	ticks.Size = UDim2.fromScale(1, 1)
	ticks.ZIndex = 4
	ticks.Parent = track

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Numeric
	label.TextSize = Theme.Sizes.NumSmall
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = props.Label or ""
	label.ZIndex = 5
	if props.LabelOutside then
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(1, LABEL_GAP, 0.5, 0)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = if props.OnPlate then Theme.Colors.TextInverse else Theme.Colors.Text
		label.Parent = root
	else
		-- It crosses the boundary between the fill and the empty track, so neither colour can carry it
		-- alone: the sheet, drawn by its ink stroke over any fill.
		label.Size = UDim2.fromScale(1, 1)
		label.TextColor3 = Theme.Colors.PanelRaised
		Theme.stroke(label, "Outline", LABEL_STROKE, "Contextual")
		label.Parent = track
	end

	trove:Add(function()
		Motion.cancel(fill)
		local shadow = ghost
		if shadow ~= nil then
			Motion.cancel(shadow)
		end
		local stop = stopPulse
		if stop ~= nil then
			stop()
		end
	end)

	local function setTicks(_self: ProgressBar?, marks: { number })
		for _, child in ipairs(ticks:GetChildren()) do
			child:Destroy()
		end
		for _, mark in ipairs(marks) do
			local tick = Instance.new("Frame")
			tick.Name = "Tick"
			tick.BorderSizePixel = 0
			tick.BackgroundColor3 = Theme.Colors.Accent
			tick.BackgroundTransparency = TICK_TRANSPARENCY
			tick.AnchorPoint = Vector2.new(0.5, 0)
			tick.Position = UDim2.fromScale(math.clamp(mark, 0, 1), 0)
			tick.Size = UDim2.new(0, TICK_WIDTH, 1, 0)
			tick.ZIndex = 4
			tick.Parent = ticks
		end
	end
	setTicks(nil, props.Ticks or {})

	root.Parent = props.Parent

	local function setProgress(_self: ProgressBar, progress: number, immediate: boolean?)
		local clamped = math.clamp(progress, 0, 1)
		local goal = UDim2.fromScale(clamped, 1)
		local shadow = ghost
		if immediate then
			Motion.set(fill, { Size = goal })
			if shadow ~= nil then
				Motion.set(shadow, { Size = goal })
			end
		elseif clamped == current then
			-- Nothing moved. The combat state is pushed five times a second whether or not it changed, so
			-- treating "the same" as a gain is what wiped the ghost 200 ms after every hit: the damage band
			-- the whole feature exists for lasted one push out of a spring of a second and a half. The fill
			-- is already where it belongs; the ghost, if it is still catching up, is left alone.
			return
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

	local function setColor(_self: ProgressBar, next: Color3)
		color = next
		track.BackgroundColor3 = trackFor(next)
		if not low then
			fill.BackgroundColor3 = next
		end
	end

	local function setLow(_self: ProgressBar, next: boolean)
		if low == next then
			return
		end
		low = next
		hatch.Visible = next
		local stop = stopPulse
		stopPulse = nil
		if stop ~= nil then
			stop()
		end
		Motion.set(fill, { BackgroundTransparency = 0 })
		if next then
			fill.BackgroundColor3 = Theme.Colors.DangerFill
			stopPulse = Motion.loop(
				fill,
				{ BackgroundTransparency = 0 },
				{ BackgroundTransparency = LOW_PULSE },
				"Ui",
				LOW_HOLD
			)
		else
			fill.BackgroundColor3 = color
		end
	end

	local function gain(_self: ProgressBar, amount: number, text: string?)
		local base = fill.BackgroundColor3
		Motion.set(fill, { BackgroundColor3 = Theme.shade(base, GAIN_SHADE) })
		Motion.to(fill, { BackgroundColor3 = base }, "UiPop")
		local rise = Instance.new("TextLabel")
		rise.Name = "Gain"
		rise.BackgroundTransparency = 1
		rise.AnchorPoint = Vector2.new(0.5, 1)
		rise.Position = UDim2.fromScale(current, 0)
		rise.AutomaticSize = Enum.AutomaticSize.XY
		rise.Size = UDim2.new()
		rise.FontFace = Theme.Fonts.Numeric
		rise.TextSize = GAIN_TEXT_SIZE
		rise.TextColor3 = base
		rise.Text = text or (Theme.Glyphs.Plus .. tostring(amount))
		rise.ZIndex = 6
		local edge = Theme.stroke(rise, "Outline", LABEL_STROKE, "Contextual")
		rise.Parent = root
		Motion.to(edge, { Transparency = 1 }, "Ui")
		Motion.to(rise, { Position = UDim2.new(current, 0, 0, -GAIN_RISE), TextTransparency = 1 }, "Ui", function()
			rise:Destroy()
		end)
	end

	local function destroy(_self: ProgressBar)
		trove:Destroy()
	end

	local object: ProgressBar = {
		Instance = root,
		SetProgress = setProgress,
		SetLabel = setLabel,
		SetColor = setColor,
		SetLow = setLow,
		Gain = gain,
		SetTicks = setTicks,
		Destroy = destroy,
	}
	return object
end

return ProgressBar
