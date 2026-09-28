--!strict
-- TouchButton: one disc of the touch cluster, drawn as a sticker you press (D-147). InputController owns the
-- input and tells the disc what state it is in; the disc only draws it:
--
--   Pigment  the exact pigment (rule 2), ink-outlined and ringed with the sheet, on its own lip, its sigil in
--            the ink that reads on it
--   Kit      an ink plate (melee, dash, guard, lock) ringed with the sheet, on a chalk lip, its short word in
--            vellum; no outline, since ink already stands out from the cream world
--   Menu     the sheet, ink-outlined, on a chalk lip
--
-- A press sinks the face onto its lip and bursts a blot of its colour behind it. The dash disc shows its
-- cooldown as an ink veil drained from the top, with the seconds on it. A disc that continues the sequence
-- breathes a thicker ring, and a pigment that leads to no glyph the ink can pay for dims its sigil. It is a
-- fight surface: no value colour (rule 11). The discs sit under no UIScale, so every size below is the
-- design size on the design disc (Theme.Sizes.TouchButton), taken as a share of the real diameter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")

local Breath = require(script.Parent.Parent.Breath)
local Motion = require(script.Parent.Parent.Motion)
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local Splat = require(script.Parent.Splat)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Kind = "Pigment" | "Kit" | "Menu"

export type Props = {
	Label: string,
	Kind: Kind,
	-- Pigment only: its PigmentConfig id.
	Pigment: string?,
	Size: number, -- disc diameter in rendered px (these buttons sit under no UIScale)
	Position: UDim2,
	Parent: Instance?,
	Name: string?,
}

export type TouchButton = {
	Instance: Frame,
	SetPressed: (self: TouchButton, pressed: boolean) -> (),
	-- `remaining` seconds of `total`: the veil and the seconds, gone at 0.
	SetCooldown: (self: TouchButton, remaining: number, total: number) -> (),
	-- This disc continues the sequence being pressed.
	SetHint: (self: TouchButton, hinted: boolean) -> (),
	-- False when the pigment leads to no glyph the ink can pay for right now.
	SetAvailable: (self: TouchButton, available: boolean) -> (),
	Destroy: (self: TouchButton) -> (),
}

local TouchButton = {}

-- The design disc every share below is taken from.
local DESIGN = Theme.Sizes.TouchButton
-- The lip under the face (the redesign's pressable disc: 4).
local LIP = 4
-- The sheet ring, inside the outline.
local RING_INSET = 3
-- How much of the world shows through the face, times the player's own setting (UiPrefs.transparency).
local FACE_TRANSPARENCY: { [Kind]: number } = { Pigment = 0.05, Kit = 0.08, Menu = 0 }
local PRESSED_SCALE = 0.88
-- A sigil fills 60 % of its disc; a word is set at the label size of a 64 disc.
local SIGIL_SHARE = 0.6
local WORD_SIZE = 14
local MIN_TEXT = 10
-- The blot a press throws behind the disc.
local BURST_FROM, BURST_TO = 0.6, 1.4
local BURST_OPACITY = 0.3
-- The cooldown veil: ink, drained from the top, and the seconds left on it.
local VEIL_TRANSPARENCY = 0.4
local SECONDS_SIZE = 16
-- A hinted disc: its sheet ring thickened, breathing between these transparencies.
local HINT_RING = 4
local HINT_FROM, HINT_TO = 0.1, 0.6
local HINT_BREATH = "TouchHint"
local DIMMED = 0.5

-- `design` units of the design disc, on a disc `diameter` px wide.
local function share(design: number, diameter: number): number
	return design * diameter / DESIGN
end

-- The lip of a pigment: its world colour shaded a quarter toward the ink (ThemeConfig.Lips uses the same rule).
local function pigmentLip(pigment: string): Color3
	local rgb = PigmentConfig.Colors[pigment :: any]
	if rgb == nil then
		return Theme.lip("Secondary")
	end
	return Theme.rgb(PigmentConfig.shade(rgb, -0.25, ThemeConfig.Charcoal, ThemeConfig.Vellum))
end

type Look = { Fill: Color3, Lip: Color3, Ink: Color3, Outline: boolean, Ring: boolean, Burst: Color3 }

local function lookFor(kind: Kind, pigment: string?): Look
	if kind == "Pigment" then
		local fill = Theme.pigmentColor(pigment or "")
		return {
			Fill = fill,
			Lip = pigmentLip(pigment or ""),
			Ink = Theme.inkOn(fill),
			Outline = true,
			Ring = true,
			Burst = fill,
		}
	elseif kind == "Kit" then
		return {
			Fill = Theme.Colors.Plate,
			Lip = Theme.Colors.Chalk,
			Ink = Theme.Colors.TextInverse,
			Outline = false,
			Ring = true,
			Burst = Theme.Colors.Chalk,
		}
	end
	return {
		Fill = Theme.Colors.PanelRaised,
		Lip = Theme.lip("Secondary"),
		Ink = Theme.Colors.Text,
		Outline = true,
		Ring = false,
		Burst = Theme.Colors.Chalk,
	}
end

-- A circle inset inside the face, carrying one sheet ring of `thickness`.
local function ringFrame(name: string, face: Frame, inset: number, thickness: number): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromOffset(inset, inset)
	frame.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	frame.ZIndex = 3
	Theme.corner(frame, Theme.Pill)
	local stroke = Theme.stroke(frame, "PanelRaised", thickness)
	frame.Parent = face
	return frame, stroke
end

local function textLabel(name: string, font: Font, color: Color3, maxSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.FontFace = font
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = false -- one line: a wrapped word inside a disc reads worse than a smaller one
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = MIN_TEXT
	cap.MaxTextSize = math.max(MIN_TEXT, math.floor(maxSize))
	cap.Parent = label
	return label
end

function TouchButton.new(props: Props): TouchButton
	local trove = Trove.new()
	local kind: Kind = props.Kind
	local look = lookFor(kind, props.Pigment)
	local diameter = props.Size
	local lip = math.max(2, math.floor(share(LIP, diameter) + 0.5))
	local pressed, hinted, available = false, false, true
	local shownFraction = 0

	local frame = Instance.new("Frame")
	frame.Name = props.Name or "TouchButton"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = props.Position
	frame.Size = UDim2.fromOffset(diameter, diameter)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = true
	trove:Add(frame)

	local scale = Instance.new("UIScale")
	scale.Parent = frame
	trove:Add(function()
		Motion.cancel(scale)
	end)

	-- The face is the disc; its lip hangs below it.
	local sticker = Sticker.new({
		Kind = "Pressable",
		Fill = look.Fill,
		Lip = look.Lip,
		Corner = Theme.Pill,
		Elevation = lip,
		Outline = look.Outline,
		Size = UDim2.new(1, 0, 1, lip),
		Parent = frame,
		Name = "Disc",
	})
	sticker.Instance.ZIndex = 1
	trove:Add(function()
		sticker:Destroy()
	end)
	local face = sticker.Face

	local function applyTransparency()
		face.BackgroundTransparency = FACE_TRANSPARENCY[kind] * UiPrefs.transparency()
	end
	applyTransparency()
	local followingPrefs = UiPrefs.Changed:Connect(applyTransparency)
	trove:Add(function()
		followingPrefs:Disconnect()
	end)

	local ring: Frame? = nil
	if look.Ring then
		ring = ringFrame("Ring", face, RING_INSET, Theme.Sizes.StrokeThin)
	end
	local hint, hintStroke = ringFrame("Hint", face, RING_INSET, HINT_RING)
	hint.Visible = false

	local label = if kind == "Pigment"
		then textLabel("Label", Theme.Fonts.Bold, look.Ink, diameter * SIGIL_SHARE)
		else textLabel("Label", Theme.Fonts.Label, look.Ink, share(WORD_SIZE, diameter))
	label.Text = props.Label
	label.Parent = face
	trove:Add(function()
		Motion.cancel(label)
	end)

	-- The cooldown: a frame cut at the height still to wait, over a veil the size of the whole disc, so what
	-- shows is the top of a circle.
	local cooldown = Instance.new("Frame")
	cooldown.Name = "Cooldown"
	cooldown.BackgroundTransparency = 1
	cooldown.ClipsDescendants = true
	cooldown.Size = UDim2.fromScale(1, 0)
	cooldown.ZIndex = 4
	cooldown.Parent = face
	trove:Add(function()
		Motion.cancel(cooldown)
	end)
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.BorderSizePixel = 0
	veil.BackgroundColor3 = Theme.Colors.Plate
	veil.BackgroundTransparency = VEIL_TRANSPARENCY
	veil.Size = UDim2.fromOffset(diameter, diameter)
	veil.ZIndex = 4
	Theme.corner(veil, Theme.Pill)
	veil.Parent = cooldown
	local seconds = textLabel("Seconds", Theme.Fonts.Numeric, Theme.Colors.TextInverse, share(SECONDS_SIZE, diameter))
	seconds.ZIndex = 6
	seconds.Visible = false
	seconds.Parent = face

	-- The blot of a press, made on the first one and kept: a disc is pressed many times a round.
	local burstBlot: GuiObject? = nil
	local burstScale: UIScale? = nil
	local function burst()
		if UiPrefs.reducedMotion() or UiPrefs.lowQuality() then
			return
		end
		local blot = burstBlot
		if blot == nil then
			blot = Splat.new({
				Size = UDim2.fromOffset(diameter, diameter),
				Tint = look.Burst,
				Transparency = 1,
				ZIndex = 0,
				Parent = frame,
				Name = "Burst",
			})
			if blot == nil then
				return
			end
			burstBlot = blot
			local existing = blot:FindFirstChildOfClass("UIScale")
			local blotScale = existing or Instance.new("UIScale")
			blotScale.Parent = blot
			burstScale = blotScale
		end
		local blotScale = burstScale :: UIScale
		Motion.set(blotScale, { Scale = BURST_FROM })
		Motion.to(blotScale, { Scale = BURST_TO }, "Ui")
		Splat.fade(blot :: GuiObject, BURST_OPACITY)
		Splat.fade(blot :: GuiObject, 1, "Ui")
	end
	-- The blot goes back to its screen's pool, out of the disc, before the disc goes: a rebuilt cluster would
	-- otherwise find the pool spent on blots destroyed with their discs. Before the trove, whose order is not
	-- guaranteed.
	local function releaseBurst()
		local blot = burstBlot
		if blot == nil then
			return
		end
		burstBlot = nil
		local blotScale = burstScale
		if blotScale ~= nil then
			Motion.cancel(blotScale)
		end
		Splat.release(blot)
		blot.Parent = nil
	end

	local breath: Breath.Reader? = nil
	local following: RBXScriptConnection? = nil
	local function stopBreath()
		if following ~= nil then
			following:Disconnect()
			following = nil
		end
		if breath ~= nil then
			breath.Leave()
			breath = nil
		end
	end
	trove:Add(stopBreath)

	frame.Parent = props.Parent

	local function setPressed(_self: TouchButton, value: boolean)
		if value == pressed then
			return
		end
		pressed = value
		sticker:SetState(if value then "Pressed" else "Idle")
		Motion.to(scale, { Scale = if value then PRESSED_SCALE else 1 }, "UiSnappy")
		if value then
			burst()
		end
	end

	local function setCooldown(_self: TouchButton, remaining: number, total: number)
		local fraction = if total > 0 then math.clamp(remaining / total, 0, 1) else 0
		if fraction ~= shownFraction then
			shownFraction = fraction
			Motion.to(cooldown, { Size = UDim2.fromScale(1, fraction) }, "UiSnappy")
		end
		-- The seconds stand where the word was, until the dash is back.
		seconds.Visible = remaining > 0
		seconds.Text = tostring(math.ceil(remaining))
		label.Visible = remaining <= 0
	end

	local function setHint(_self: TouchButton, value: boolean)
		if value == hinted then
			return
		end
		hinted = value
		hint.Visible = value
		if ring ~= nil then
			ring.Visible = not value
		end
		stopBreath()
		if not value then
			return
		end
		if UiPrefs.reducedMotion() then
			hintStroke.Transparency = HINT_FROM
			return
		end
		local reader = Breath.join(HINT_BREATH, HINT_FROM, HINT_TO, Theme.Timing.IdleBreathSeconds, "Ui")
		breath = reader
		hintStroke.Transparency = reader.Value.Value
		following = reader.Value.Changed:Connect(function(next: number)
			hintStroke.Transparency = next
		end)
	end

	local function setAvailable(_self: TouchButton, value: boolean)
		if value == available then
			return
		end
		available = value
		Motion.to(label, { TextTransparency = if value then 0 else DIMMED }, "Ui")
	end

	local function destroy(_self: TouchButton)
		releaseBurst()
		trove:Destroy()
	end

	local object: TouchButton = {
		Instance = frame,
		SetPressed = setPressed,
		SetCooldown = setCooldown,
		SetHint = setHint,
		SetAvailable = setAvailable,
		Destroy = destroy,
	}
	return object
end

return TouchButton
