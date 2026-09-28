--!strict
-- Hotbar: the glyphs the player has equipped, and when each of them can be cast again (D-147). The server
-- pushes every glyph's remaining cooldown five times a second (CombatController.State.Cooldowns), and until
-- now nothing drew it: a player learned a glyph was cooling down by pressing its recipe and being refused.
--
-- With a pointer, a row of slots over the dock: each an ink plate ringed with the sheet, holding a chip of
-- the glyph's own pigment with its sigil (rule 2: the glyph's colour is its school's), and under it the
-- recipe as the keys the player has bound, each key carrying a strip of the pigment it presses -- "J" on
-- Cinnabar, "K" on Indigo. That strip is what teaches the keyboard. On touch, where the discs already say it,
-- a row of pips across the top of the dock.
--
-- Cooling down, an ink veil drains off the chip, with the seconds left on it; ready again, the slot pops and
-- a seal flashes behind it. A glyph the ink cannot pay for turns chalk and shows a drop. It is a fight
-- surface: no value colour (rule 11). Slots are pooled by index, so a push at 5 Hz rebuilds nothing, and a
-- drain only springs when its value changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local GlyphConfig = require(Config:WaitForChild("GlyphConfig"))
local Icon = require(script.Parent.Icon)
local Keycap = require(script.Parent.Keycap)
local Motion = require(script.Parent.Parent.Motion)
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))
local Trove = require(Packages.Trove)

export type Mode = "Slots" | "Pips"

export type Props = {
	Parent: Instance,
	-- Slots with their keys (a mouse or a gamepad), or pips (touch).
	Mode: Mode,
	Localize: Keycap.Localizer,
	LayoutOrder: number?,
}

-- The part of CombatController.State the hotbar draws.
export type State = { Ink: number, Cooldowns: { [string]: number } }

export type Hotbar = {
	Instance: Frame,
	-- The equipped glyph ids, in slot order (ProfileData.Loadout.Slots).
	SetLoadout: (self: Hotbar, slots: { string }) -> (),
	-- The device the keys are drawn for, and the key bound to each pigment.
	SetKeys: (self: Hotbar, device: Keycap.Device, keys: { [string]: string }) -> (),
	SetState: (self: Hotbar, state: State) -> (),
	-- A cast of the glyph named `nameKey` refused for its cooldown: its slot flashes chalk twice.
	Refuse: (self: Hotbar, nameKey: string) -> (),
	Destroy: (self: Hotbar) -> (),
}

type Slot = {
	Root: Frame,
	Scale: UIScale,
	Chip: Frame,
	Sigil: TextLabel?,
	Drain: Frame,
	Seconds: TextLabel?,
	Drop: Frame?,
	Flash: ImageLabel?,
	FlashScale: UIScale?,
	Keys: Frame?,
	Caps: { Keycap.Keycap },
	GlyphId: string?,
	Fraction: number,
	Remaining: number,
	Unaffordable: boolean,
}

local Hotbar = {}

local HUD = ThemeConfig.Hud
local CHIP = 40
local SIGIL_SCALE = 0.6
local RING_INSET = 3
-- The veil a cooling glyph wears, drained from the top as the cooldown runs out.
local DRAIN_TRANSPARENCY = 0.35
local SECONDS_TEXT = 16
local SECONDS_STROKE = 2
local DROP = 14
-- A key cap stands on a 3-unit lip: a cap of 15 fills the key strip exactly.
local CAP = HUD.HotbarKeyStrip - 3
local CAP_GAP = 2
local PIP_GAP = 3
local READY_PUNCH = 1.12
local FLASH_FROM = 0.2
local FLASH_SCALE_FROM = 0.8
local FLASH_SCALE_TO = 1.4

local function fill(slot: Slot, color: Color3, animate: boolean)
	if animate then
		Motion.to(slot.Chip, { BackgroundColor3 = color }, "Ui")
	else
		Motion.set(slot.Chip, { BackgroundColor3 = color })
	end
	local sigil = slot.Sigil
	if sigil ~= nil then
		sigil.TextColor3 = Theme.inkOn(color)
	end
end

-- The veil over a chip: ink, draining off from the top.
local function drain(chip: Frame): Frame
	local veil = Instance.new("Frame")
	veil.Name = "Drain"
	veil.BorderSizePixel = 0
	veil.BackgroundColor3 = Theme.Colors.Plate
	veil.BackgroundTransparency = DRAIN_TRANSPARENCY
	veil.Size = UDim2.fromScale(1, 0)
	veil.ZIndex = 4
	veil.Parent = chip
	return veil
end

local function buildSlot(index: number, parent: Instance, trove: typeof(Trove.new())): Slot
	local column = Instance.new("Frame")
	column.Name = "Slot" .. index
	column.BackgroundTransparency = 1
	column.LayoutOrder = index
	column.Size = UDim2.fromOffset(HUD.HotbarSlot, HUD.HotbarSlot + HUD.HotbarKeyStrip)
	column.AutomaticSize = Enum.AutomaticSize.X
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column

	local square = Instance.new("Frame")
	square.Name = "Square"
	square.BackgroundTransparency = 1
	square.Size = UDim2.fromOffset(HUD.HotbarSlot, HUD.HotbarSlot)
	square.LayoutOrder = 1
	square.Parent = column
	local scale = Instance.new("UIScale")
	scale.Parent = square

	-- The seal that flashes behind a glyph that is ready again.
	local flash: ImageLabel? = nil
	local flashScale: UIScale? = nil
	local id = Theme.texture("SealRing")
	if id ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "Ready"
		image.BackgroundTransparency = 1
		image.Image = id
		image.ImageColor3 = Theme.Colors.PanelRaised
		image.ImageTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ZIndex = 0
		local imageScale = Instance.new("UIScale")
		imageScale.Parent = image
		image.Parent = square
		flash, flashScale = image, imageScale
	end

	local plate = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Corner = UDim.new(0, Theme.Sizes.CornerChip),
		Size = UDim2.fromScale(1, 1),
		Parent = square,
		Name = "Plate",
	})
	trove:Add(function()
		plate:Destroy()
	end)
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(RING_INSET, RING_INSET)
	ring.Size = UDim2.new(1, -RING_INSET * 2, 1, -RING_INSET * 2)
	Theme.corner(ring, Theme.Sizes.CornerChip - RING_INSET)
	Theme.stroke(ring, "PanelRaised", Theme.Sizes.StrokeThin)
	ring.Parent = plate.Face

	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.BorderSizePixel = 0
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Position = UDim2.fromScale(0.5, 0.5)
	chip.Size = UDim2.fromOffset(CHIP, CHIP)
	chip.ClipsDescendants = true
	chip.ZIndex = 3
	Theme.corner(chip, Theme.Sizes.CornerChip)
	chip.Parent = square

	local sigil = Instance.new("TextLabel")
	sigil.Name = "Sigil"
	sigil.BackgroundTransparency = 1
	sigil.Size = UDim2.fromScale(1, 1)
	sigil.FontFace = Theme.Fonts.Bold
	sigil.TextSize = CHIP * SIGIL_SCALE
	sigil.ZIndex = 3
	sigil.Parent = chip

	local seconds = Instance.new("TextLabel")
	seconds.Name = "Seconds"
	seconds.BackgroundTransparency = 1
	seconds.Size = UDim2.fromScale(1, 1)
	seconds.FontFace = Theme.Fonts.Numeric
	seconds.TextSize = SECONDS_TEXT
	seconds.TextColor3 = Theme.Colors.PanelRaised
	seconds.ZIndex = 5
	seconds.Visible = false
	Theme.stroke(seconds, "Outline", SECONDS_STROKE, "Contextual")
	seconds.Parent = square

	local drop = Icon.new("Drop", DROP, Theme.Colors.InfoFill)
	drop.AnchorPoint = Vector2.new(1, 1)
	drop.Position = UDim2.new(1, -RING_INSET, 1, -RING_INSET)
	drop.ZIndex = 5
	drop.Visible = false
	drop.Parent = square

	local keys = Instance.new("Frame")
	keys.Name = "Keys"
	keys.BackgroundTransparency = 1
	keys.Size = UDim2.fromOffset(0, HUD.HotbarKeyStrip)
	keys.AutomaticSize = Enum.AutomaticSize.X
	keys.LayoutOrder = 2
	local keysLayout = Instance.new("UIListLayout")
	keysLayout.FillDirection = Enum.FillDirection.Horizontal
	keysLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	keysLayout.SortOrder = Enum.SortOrder.LayoutOrder
	keysLayout.Padding = UDim.new(0, CAP_GAP)
	keysLayout.Parent = keys
	keys.Parent = column

	column.Parent = parent
	return {
		Root = column,
		Scale = scale,
		Chip = chip,
		Sigil = sigil,
		Drain = drain(chip),
		Seconds = seconds,
		Drop = drop,
		Flash = flash,
		FlashScale = flashScale,
		Keys = keys,
		Caps = {},
		GlyphId = nil,
		Fraction = 0,
		Remaining = 0,
		Unaffordable = false,
	}
end

local function buildPip(index: number, parent: Instance): Slot
	local pip = Instance.new("Frame")
	pip.Name = "Pip" .. index
	pip.BorderSizePixel = 0
	pip.LayoutOrder = index
	pip.ClipsDescendants = true
	Theme.corner(pip, Theme.Pill)
	Theme.stroke(pip, "Accent", Theme.Sizes.StrokeThin)
	-- Round in whatever share of the row setLoadout gives it, and never taller than the row.
	local round = Instance.new("UIAspectRatioConstraint")
	round.AspectRatio = 1
	round.AspectType = Enum.AspectType.FitWithinMaxSize
	round.Parent = pip
	local scale = Instance.new("UIScale")
	scale.Parent = pip
	pip.Parent = parent
	return {
		Root = pip,
		Scale = scale,
		Chip = pip,
		Sigil = nil,
		Drain = drain(pip),
		Seconds = nil,
		Drop = nil,
		Flash = nil,
		FlashScale = nil,
		Keys = nil,
		Caps = {},
		GlyphId = nil,
		Fraction = 0,
		Remaining = 0,
		Unaffordable = false,
	}
end

function Hotbar.new(props: Props): Hotbar
	local trove = Trove.new()
	local pips = props.Mode == "Pips"
	local slots: { Slot } = {}
	local device: Keycap.Device = "Keyboard"
	local keys: { [string]: string } = {}

	local row = Instance.new("Frame")
	row.Name = "Hotbar"
	row.BackgroundTransparency = 1
	row.LayoutOrder = props.LayoutOrder or 0
	row.Size = if pips then UDim2.new(1, 0, 0, HUD.HotbarPipsHeight) else UDim2.new()
	row.AutomaticSize = if pips then Enum.AutomaticSize.None else Enum.AutomaticSize.XY
	trove:Add(row)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, if pips then PIP_GAP else HUD.HotbarGap)
	layout.Parent = row
	trove:Add(function()
		for _, slot in ipairs(slots) do
			Motion.cancel(slot.Scale)
			Motion.cancel(slot.Chip)
			Motion.cancel(slot.Drain)
			local image, imageScale = slot.Flash, slot.FlashScale
			if image ~= nil and imageScale ~= nil then
				Motion.cancel(image)
				Motion.cancel(imageScale)
			end
			for _, cap in ipairs(slot.Caps) do
				cap:Destroy()
			end
		end
	end)

	row.Parent = props.Parent

	local function drawKeys(slot: Slot, def: GlyphConfig.GlyphDef)
		local strip = slot.Keys
		if strip == nil then
			return
		end
		for _, cap in ipairs(slot.Caps) do
			cap:Destroy()
		end
		table.clear(slot.Caps)
		for step, pigment in ipairs(def.Combo) do
			table.insert(
				slot.Caps,
				Keycap.new({
					Key = keys[pigment] or "",
					Device = device,
					Localize = props.Localize,
					Size = CAP,
					Pigment = pigment,
					LayoutOrder = step,
					Parent = strip,
				})
			)
		end
	end

	local function draw(slot: Slot, def: GlyphConfig.GlyphDef)
		slot.GlyphId = def.Id
		slot.Fraction = 0
		slot.Remaining = 0
		slot.Unaffordable = false
		Motion.set(slot.Drain, { Size = UDim2.fromScale(1, 0) })
		fill(slot, Theme.pigmentColor(def.Pigment), false)
		local sigil = slot.Sigil
		if sigil ~= nil then
			sigil.Text = PigmentConfig.Sigils[def.Pigment :: any] or ""
		end
		local drop, seconds = slot.Drop, slot.Seconds
		if drop ~= nil then
			drop.Visible = false
		end
		if seconds ~= nil then
			seconds.Visible = false
		end
		drawKeys(slot, def)
	end

	local function setLoadout(_self: Hotbar, next: { string })
		local count = 0
		for _, glyphId in ipairs(next) do
			if GlyphConfig.byId(glyphId) ~= nil then
				count += 1
			end
		end
		-- A pip's share of the dock's row, less its share of the gaps (rounded up, a UDim's offset being whole):
		-- as many as a pass allows fit the narrowest dock, and a few stay the row's height.
		local pipShare = UDim2.new(1 / math.max(count, 1), -math.ceil(PIP_GAP * (count - 1) / math.max(count, 1)), 1, 0)
		local shown = 0
		for _, glyphId in ipairs(next) do
			local def = GlyphConfig.byId(glyphId)
			if def ~= nil then
				shown += 1
				local slot = slots[shown]
				if slot == nil then
					slot = if pips then buildPip(shown, row) else buildSlot(shown, row, trove)
					slots[shown] = slot
				end
				local current = slot :: Slot
				current.Root.Visible = true
				if pips then
					current.Root.Size = pipShare
				end
				if current.GlyphId ~= def.Id then
					draw(current, def)
				end
			end
		end
		for index = shown + 1, #slots do
			slots[index].Root.Visible = false
			slots[index].GlyphId = nil
		end
	end

	local function setKeys(_self: Hotbar, nextDevice: Keycap.Device, nextKeys: { [string]: string })
		device = nextDevice
		keys = table.clone(nextKeys)
		for _, slot in ipairs(slots) do
			local def = if slot.GlyphId ~= nil then GlyphConfig.byId(slot.GlyphId) else nil
			if def ~= nil then
				drawKeys(slot, def)
			end
		end
	end

	-- A glyph ready again: the slot pops, and the seal behind it flashes out.
	local function ready(slot: Slot)
		Motion.punch(slot.Scale, READY_PUNCH)
		local image, imageScale = slot.Flash, slot.FlashScale
		if image ~= nil and imageScale ~= nil then
			Motion.set(image, { ImageTransparency = FLASH_FROM })
			Motion.set(imageScale, { Scale = FLASH_SCALE_FROM })
			Motion.to(image, { ImageTransparency = 1 }, "Ui")
			Motion.to(imageScale, { Scale = FLASH_SCALE_TO }, "Ui")
		end
	end

	local function setState(_self: Hotbar, state: State)
		for _, slot in ipairs(slots) do
			local glyphId = slot.GlyphId
			local def = if glyphId ~= nil then GlyphConfig.byId(glyphId) else nil
			if def ~= nil then
				local left = state.Cooldowns[def.Id]
				local remaining = if type(left) == "number" and left > 0 then left else 0
				local fraction = if def.Cooldown > 0 then math.clamp(remaining / def.Cooldown, 0, 1) else 0
				if fraction ~= slot.Fraction then
					-- Retargeted at the server's pace: the spring keeps its speed, so the drain reads as one
					-- movement rather than five steps a second.
					slot.Fraction = fraction
					Motion.to(slot.Drain, { Size = UDim2.fromScale(1, fraction) }, "UiSnappy")
				end
				if slot.Remaining > 0 and remaining <= 0 then
					ready(slot)
				end
				slot.Remaining = remaining
				local seconds = slot.Seconds
				if seconds ~= nil then
					seconds.Visible = remaining > 0
					seconds.Text = tostring(math.ceil(remaining))
				end
				local unaffordable = state.Ink < def.Cost
				if unaffordable ~= slot.Unaffordable then
					slot.Unaffordable = unaffordable
					fill(slot, if unaffordable then Theme.Colors.Chalk else Theme.pigmentColor(def.Pigment), true)
					local drop = slot.Drop
					if drop ~= nil then
						drop.Visible = unaffordable
					end
				end
			end
		end
	end

	local function refuse(_self: Hotbar, nameKey: string)
		for _, slot in ipairs(slots) do
			local def = if slot.GlyphId ~= nil then GlyphConfig.byId(slot.GlyphId) else nil
			if def ~= nil and def.NameKey == nameKey and slot.Root.Visible then
				local color = if slot.Unaffordable then Theme.Colors.Chalk else Theme.pigmentColor(def.Pigment)
				Motion.set(slot.Chip, { BackgroundColor3 = Theme.Colors.Chalk })
				Motion.to(slot.Chip, { BackgroundColor3 = color }, "UiPop", function()
					Motion.set(slot.Chip, { BackgroundColor3 = Theme.Colors.Chalk })
					Motion.to(slot.Chip, { BackgroundColor3 = color }, "UiPop")
				end)
			end
		end
	end

	local function destroy(_self: Hotbar)
		trove:Destroy()
	end

	local object: Hotbar = {
		Instance = row,
		SetLoadout = setLoadout,
		SetKeys = setKeys,
		SetState = setState,
		Refuse = refuse,
		Destroy = destroy,
	}
	return object
end

return Hotbar
