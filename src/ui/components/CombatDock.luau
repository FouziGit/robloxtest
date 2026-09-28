--!strict
-- CombatDock: the player's own health and ink, on an ink plate between the thumbs (D-147). HudController
-- places it and feeds it the combat state the server pushes; every number on it is the server's.
--
-- It is a fight surface, so its colours keep their meaning (docs/ART_BIBLE.md rules 7 and 11): the plate is
-- ink, the health is cyan -- us, the player's own included -- the ink is the vivid Indigo, and red appears
-- only when the health is low enough to be imminent danger. Then it says so four ways at once, so colour is
-- never the only cue: the bar turns red, hatches and pulses, the edges of the screen burn Cinnabar, and the
-- error sound plays once as the health crosses the line. The edges stand still for a player who turned off
-- "shakes and flashes" or asked Roblox for less motion.
--
-- What was just lost stays on the health bar in Cinnabar and catches up (the ghost, D-85): a hit reads as a
-- chunk taken out of the bar. Beside the health, a diamond lights while the player guards; beside the ink, a
-- dot says the ink is not coming back yet (in combat, regeneration waits).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Breath = require(script.Parent.Parent.Breath)
local Icon = require(script.Parent.Icon)
local ProgressBar = require(script.Parent.ProgressBar)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local ThemeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ThemeConfig"))
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)
local UiSound = require(script.Parent.Parent.UiSound)

-- The part of CombatController.State the dock draws.
export type State = {
	Health: number,
	MaxHealth: number,
	Ink: number,
	MaxInk: number,
	InCombat: boolean,
	Blocking: boolean,
}

export type Props = {
	-- Where the dock sits (the HUD's bottom stack), and the ScreenGui whose edges burn at low health.
	Parent: Instance,
	Screen: ScreenGui,
	LayoutOrder: number?,
	Width: number,
	-- On touch the hotbar's pips ride across the top of the dock (PipRow).
	Pips: boolean?,
}

export type CombatDock = {
	Instance: Frame,
	-- The row the hotbar's pips go in, when the dock was built with Pips.
	PipRow: Frame?,
	SetState: (self: CombatDock, state: State) -> (),
	-- On touch the dock is never wider than the gap between the thumbs.
	SetWidth: (self: CombatDock, width: number) -> (),
	Destroy: (self: CombatDock) -> (),
}

type TroveObject = typeof(Trove.new())

local CombatDock = {}

local HUD = ThemeConfig.Hud
local CORNER = Theme.Sizes.CornerTile
local PADDING = 10
local GAP = 10
local HEALTH_HEIGHT = 26
local INK_HEIGHT = 14
-- The column the numbers stand in, right of their bars, and the gap before it.
local NUMBER_WIDTH = 48
local NUMBER_GAP = 8
local HEALTH_TEXT = 20
local INK_TEXT = 16
local GUARD_SIZE = 16
local GUARD_IDLE = 0.6
local COMBAT_DOT = 8
-- The ring of the sheet inside the plate, and how far in from its edge.
local RING_INSET = 3
-- The low-health edges: four strips of the linear gradient, their dense side against the screen's edge, as
-- deep as this share of its short side, breathing between the two transparencies, or still at the third.
local VIGNETTE_DEPTH = 0.18
local VIGNETTE_FROM = 0.55
local VIGNETTE_TO = 0.75
local VIGNETTE_STILL = 0.7
local VIGNETTE_HOLD = 0.25
local LOW_SOUND = "Error"

local function numberLabel(name: string, size: number, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Numeric
	label.TextSize = size
	label.TextColor3 = Theme.Colors.TextInverse
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromScale(1, 1)
	label.LayoutOrder = order
	label.Text = ""
	return label
end

-- One line of the dock: [lead] [bar, filling what is left] [the number's column].
local function row(name: string, height: number, order: number, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, NUMBER_GAP)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

local function slot(name: string, width: number, order: number, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0, width, 1, 0)
	frame.LayoutOrder = order
	frame.Parent = parent
	return frame
end

local function fill(object: GuiObject)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = object
end

-- The four burning edges, laid out over the whole screen. The gradient runs along the texture's X, dense on
-- its right; the side strips turn it round, the top and bottom ones stand it up.
local function buildVignette(screen: ScreenGui, trove: TroveObject): (Frame, { ImageLabel })
	local frame = Instance.new("Frame")
	frame.Name = "LowHealth"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 0
	frame.Visible = false
	trove:Add(frame)
	local strips: { ImageLabel } = {}
	local id = Theme.texture("GradientLinear")
	if id ~= "" then
		for _, name in ipairs({ "Right", "Left", "Top", "Bottom" }) do
			local strip = Instance.new("ImageLabel")
			strip.Name = name
			strip.BackgroundTransparency = 1
			strip.Image = id
			strip.ImageColor3 = Theme.Colors.Danger
			strip.ImageTransparency = VIGNETTE_STILL
			strip.Parent = frame
			table.insert(strips, strip)
		end
		trove:Add(Theme.bindScale(function()
			local camera: Camera? = workspace.CurrentCamera
			if camera == nil then
				return
			end
			local size = camera.ViewportSize / Theme.activeScale()
			local depth = math.min(size.X, size.Y) * VIGNETTE_DEPTH
			local right, left, top, bottom = strips[1], strips[2], strips[3], strips[4]
			right.AnchorPoint = Vector2.new(1, 0)
			right.Position = UDim2.fromScale(1, 0)
			right.Size = UDim2.new(0, depth, 1, 0)
			left.Position = UDim2.new()
			left.Size = UDim2.new(0, depth, 1, 0)
			left.Rotation = 180
			-- Stood up: a strip `depth` wide and as tall as the screen is wide, turned a quarter.
			for _, strip in ipairs({ top, bottom }) do
				strip.AnchorPoint = Vector2.new(0.5, 0.5)
				strip.Size = UDim2.fromOffset(depth, size.X)
			end
			top.Position = UDim2.new(0.5, 0, 0, depth / 2)
			top.Rotation = -90
			bottom.Position = UDim2.new(0.5, 0, 1, -depth / 2)
			bottom.Rotation = 90
		end))
	end
	frame.Parent = screen
	return frame, strips
end

function CombatDock.new(props: Props): CombatDock
	local trove = Trove.new()
	local low = false
	local breath: Breath.Reader? = nil
	local breathing: RBXScriptConnection? = nil
	local height = HUD.DockHeight + (if props.Pips then HUD.HotbarPipsHeight + GAP else 0)

	local dock = Instance.new("Frame")
	dock.Name = "Dock"
	dock.BackgroundTransparency = 1
	dock.Size = UDim2.fromOffset(props.Width, height)
	dock.LayoutOrder = props.LayoutOrder or 0
	trove:Add(dock)

	local plate = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Corner = UDim.new(0, CORNER),
		Size = UDim2.fromScale(1, 1),
		Parent = dock,
		Name = "Plate",
	})
	trove:Add(function()
		plate:Destroy()
	end)
	-- The leaf's ring inside the ink: what shapes a plate against a dark floor.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(RING_INSET, RING_INSET)
	ring.Size = UDim2.new(1, -RING_INSET * 2, 1, -RING_INSET * 2)
	Theme.corner(ring, CORNER - RING_INSET)
	Theme.stroke(ring, "PanelRaised", Theme.Sizes.StrokeThin)
	ring.Parent = plate.Face

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 3
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING)
	padding.PaddingBottom = UDim.new(0, PADDING)
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = content
	content.Parent = dock

	local pipRow: Frame? = nil
	if props.Pips then
		local frame = Instance.new("Frame")
		frame.Name = "Pips"
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, 0, 0, HUD.HotbarPipsHeight)
		frame.LayoutOrder = 0
		frame.Parent = content
		pipRow = frame
	end

	-- Health: the guard's diamond, the cyan bar with its Cinnabar ghost, the number.
	local healthRow = row("Health", HEALTH_HEIGHT, 1, content)
	local guardSlot = slot("Guard", GUARD_SIZE, 1, healthRow)
	local guard = Icon.new("Shield", GUARD_SIZE)
	guard.AnchorPoint = Vector2.new(0.5, 0.5)
	guard.Position = UDim2.fromScale(0.5, 0.5)
	guard.Parent = guardSlot
	-- The Shield icon draws one diamond: lit in the sheet while guarding, faint chalk otherwise.
	local diamond = guard:FindFirstChildWhichIsA("Frame")
	local diamondEdge = if diamond ~= nil then diamond:FindFirstChildWhichIsA("UIStroke") else nil
	local healthBar = ProgressBar.new({
		Name = "HealthBar",
		Color = Theme.Colors.Health,
		Ghost = Theme.Colors.Danger,
		OnPlate = true,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = healthRow,
	})
	fill(healthBar.Instance)
	local healthNumber = numberLabel("Value", HEALTH_TEXT, 1)
	healthNumber.Parent = slot("Number", NUMBER_WIDTH, 3, healthRow)

	-- Ink: the vivid Indigo bar under the health, its number, and the in-combat dot beside it.
	local inkRow = row("Ink", INK_HEIGHT, 2, content)
	slot("Lead", GUARD_SIZE, 1, inkRow)
	local inkBar = ProgressBar.new({
		Name = "InkBar",
		Color = Theme.Colors.Ink,
		OnPlate = true,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = inkRow,
	})
	fill(inkBar.Instance)
	local inkSlot = slot("Number", NUMBER_WIDTH, 3, inkRow)
	local inkLayout = Instance.new("UIListLayout")
	inkLayout.FillDirection = Enum.FillDirection.Horizontal
	inkLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	inkLayout.SortOrder = Enum.SortOrder.LayoutOrder
	inkLayout.Padding = UDim.new(0, COMBAT_DOT / 2)
	inkLayout.Parent = inkSlot
	local inkNumber = numberLabel("Value", INK_TEXT, 1)
	inkNumber.AutomaticSize = Enum.AutomaticSize.X
	inkNumber.Size = UDim2.fromScale(0, 1)
	inkNumber.Parent = inkSlot
	local combatDot = Instance.new("Frame")
	combatDot.Name = "InCombat"
	combatDot.BorderSizePixel = 0
	combatDot.BackgroundColor3 = Theme.Colors.Chalk
	combatDot.Size = UDim2.fromOffset(COMBAT_DOT, COMBAT_DOT)
	combatDot.LayoutOrder = 2
	combatDot.Visible = false
	Theme.corner(combatDot, Theme.Pill)
	combatDot.Parent = inkSlot

	trove:Add(function()
		healthBar:Destroy()
		inkBar:Destroy()
	end)

	local vignette, strips = buildVignette(props.Screen, trove)

	local function setEdges(transparency: number)
		for _, strip in ipairs(strips) do
			strip.ImageTransparency = transparency
		end
	end

	local function stopBreath()
		local connection = breathing
		breathing = nil
		if connection ~= nil then
			connection:Disconnect()
		end
		local reader = breath
		breath = nil
		if reader ~= nil then
			reader.Leave()
		end
	end

	-- The edges breathe while low, or stand still for a player who asked for no shakes or less motion.
	local function refreshEdges()
		vignette.Visible = low
		local breathes = low and UiPrefs.shakes() and not UiPrefs.reducedMotion()
		if not breathes then
			stopBreath()
			setEdges(VIGNETTE_STILL)
			return
		end
		if breath ~= nil then
			return
		end
		local reader = Breath.join("LowHealth", VIGNETTE_FROM, VIGNETTE_TO, VIGNETTE_HOLD, "Ui")
		breath = reader
		setEdges(reader.Value.Value)
		breathing = reader.Value.Changed:Connect(setEdges)
	end
	local following = UiPrefs.Changed:Connect(refreshEdges)
	trove:Add(function()
		following:Disconnect()
		stopBreath()
	end)

	dock.Parent = props.Parent

	local function setLow(next: boolean)
		if next == low then
			return
		end
		low = next
		healthBar:SetLow(next)
		if next then
			-- The one sound of it, as the line is crossed; the pulse and the edges carry on silently.
			UiSound.play(LOW_SOUND)
		end
		refreshEdges()
	end

	local function setState(_self: CombatDock, state: State)
		healthBar:SetProgress(if state.MaxHealth > 0 then state.Health / state.MaxHealth else 0)
		inkBar:SetProgress(if state.MaxInk > 0 then state.Ink / state.MaxInk else 0)
		healthNumber.Text = tostring(math.floor(state.Health + 0.5))
		inkNumber.Text = tostring(math.floor(state.Ink + 0.5))
		setLow(state.MaxHealth > 0 and state.Health <= state.MaxHealth * HUD.LowHealthFraction)
		if diamond ~= nil then
			diamond.BackgroundColor3 = if state.Blocking then Theme.Colors.PanelRaised else Theme.Colors.Chalk
			diamond.BackgroundTransparency = if state.Blocking then 0 else GUARD_IDLE
		end
		if diamondEdge ~= nil then
			diamondEdge.Transparency = if state.Blocking then 0 else GUARD_IDLE
		end
		combatDot.Visible = state.InCombat
	end

	local function setWidth(_self: CombatDock, width: number)
		dock.Size = UDim2.fromOffset(width, height)
	end

	local function destroy(_self: CombatDock)
		trove:Destroy()
	end

	local object: CombatDock = {
		Instance = dock,
		PipRow = pipRow,
		SetState = setState,
		SetWidth = setWidth,
		Destroy = destroy,
	}
	return object
end

return CombatDock
