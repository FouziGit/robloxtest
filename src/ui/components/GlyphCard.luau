--!strict
-- GlyphCard: one glyph on the loadout screen (D-147). A sheet on the lip of its own pigment, with a band of
-- that pigment across the top holding its name and its sigil. Under the band, its recipe as the player
-- presses it: the keys they bound (each keycap carries the strip of the pigment it presses), the D-pad
-- arrows on a gamepad, or small pigment discs on a phone. Then what it costs and does, with icons -- a hit
-- mark for its damage, a drop for its ink, a clock for its cooldown -- one line of its lore, and the action.
--
--   Available  the chapter's Equip
--   Equipped   a thicker ink ring, a green check seal on the corner, and Unequip on the sheet (never red:
--              taking a glyph off is not a danger)
--   Full       Equip disabled, saying "Slots full"; a tap on it is still heard (OnRefused)
--   Locked     a chalk veil and a lock over the card, and the reason in the disabled button

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local Button = require(script.Parent.Button)
local GlyphConfig = require(Config:WaitForChild("GlyphConfig"))
local Icon = require(script.Parent.Icon)
local InputConfig = require(Config:WaitForChild("InputConfig"))
local Keycap = require(script.Parent.Keycap)
local LoadoutEdit = require(Shared:WaitForChild("Pure"):WaitForChild("LoadoutEdit"))
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local Seal = require(script.Parent.Seal)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))
local Trove = require(Packages.Trove)
local Types = require(Shared:WaitForChild("Types"))

export type Device = "Keyboard" | "Gamepad" | "Touch"
export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	Def: GlyphConfig.GlyphDef,
	Localize: Localizer,
	-- The key each pigment's action is bound to, for `Device` (ignored on touch).
	Bindings: { [string]: string },
	Device: Device,
	-- Equip or Unequip, as the card's state says.
	OnAction: () -> (),
	-- A tap on Equip while every slot is taken.
	OnRefused: () -> (),
	LayoutOrder: number?,
	Parent: Instance?,
}

export type GlyphCard = {
	Instance: Frame,
	Button: Button.Button,
	-- `lockText` is the reason a locked glyph is locked ("Unlocks at level 12").
	SetState: (self: GlyphCard, state: LoadoutEdit.CardState, lockText: string?) -> (),
	SetRecipe: (self: GlyphCard, bindings: { [string]: string }, device: Device) -> (),
	Destroy: (self: GlyphCard) -> (),
}

local GlyphCard = {}

-- A glyph card is a tile: it stands on its lip like a menu tile does (D-147 §2.4).
local ELEVATION = 6
-- Every lip is its face's pigment shaded this far toward the ink (ThemeConfig.Lips).
local LIP_SHADE = -0.25
local INSET = Theme.Sizes.Padding
local BAND_HEIGHT = 40
local NAME_SIZE = 20
local SIGIL_SIZE = 22
local ROW_GAP = Theme.Sizes.PaddingSmall
local RECIPE_HEIGHT = Theme.Sizes.Keycap + 6
local KEY_GAP = 6
local DISC_SIZE = 20
local STAT_HEIGHT = 24
local STAT_ICON = 18
local STAT_GAP = 4
local LORE_SIZE = 15
local LORE_LINES = 2
-- A line of the lore font, as a multiple of its size.
local LINE_HEIGHT = 1.25
local RING_THICKNESS = 4
local SEAL_SIZE = 24
local VEIL_TRANSPARENCY = 0.4
local LOCK_SIZE = 32

local GAMEPAD_PREFIX = "Gamepad"

-- How the player plays right now, which is how a recipe is drawn: the keys on a keyboard, the buttons on
-- a pad the last input came from, the discs on a phone.
function GlyphCard.device(): Device
	if Theme.touchOnly() then
		return "Touch"
	end
	local inputType = UserInputService:GetLastInputType()
	if string.sub(inputType.Name, 1, #GAMEPAD_PREFIX) == GAMEPAD_PREFIX then
		return "Gamepad"
	end
	return "Keyboard"
end

-- The key each pigment is bound to on `device`, as the player saved it (`settings`, the profile's) or by
-- default: the recipe a card shows is the one the player's hands will press.
function GlyphCard.bindings(settings: Types.SettingsData?, device: Device): { [string]: string }
	local gamepad = device == "Gamepad"
	local saved: Types.KeybindMap? = if settings == nil
		then nil
		elseif gamepad then settings.Gamepad
		else settings.Keyboard
	local defaults = ((if gamepad then InputConfig.DefaultGamepad else InputConfig.DefaultKeyboard) :: any) :: {
		[string]: string,
	}
	local map: { [string]: string } = {}
	for _, pigment in ipairs(PigmentConfig.Order) do
		local key = if saved ~= nil then saved[pigment] else nil
		map[pigment] = key or defaults[pigment]
	end
	return map
end

-- The pigment's own lip: the card of a Cinnabar glyph stands on the Cinnabar shaded toward the ink.
local function pigmentLip(pigment: string): Color3
	local rgb = (PigmentConfig.Colors :: any)[pigment]
	if rgb == nil then
		return Theme.lip("Secondary")
	end
	return Theme.rgb(PigmentConfig.shade(rgb, LIP_SHADE, ThemeConfig.Colors.Text, ThemeConfig.Colors.Panel))
end

local function textLabel(name: string, font: Font, size: number, color: Color3, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.LayoutOrder = order
	return label
end

local function listLayout(parent: Instance, direction: Enum.FillDirection, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
end

-- A row across the body, `height` tall, laid out left to right.
local function bodyRow(name: string, height: number, order: number, gap: number, parent: Instance): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, height)
	row.LayoutOrder = order
	listLayout(row, Enum.FillDirection.Horizontal, gap)
	row.Parent = parent
	return row
end

-- An icon and its number, side by side.
local function stat(parent: Instance, icon: Icon.Name, iconColor: Color3?, text: string, order: number)
	local group = Instance.new("Frame")
	group.Name = icon
	group.BackgroundTransparency = 1
	group.AutomaticSize = Enum.AutomaticSize.X
	group.Size = UDim2.fromScale(0, 1)
	group.LayoutOrder = order
	listLayout(group, Enum.FillDirection.Horizontal, STAT_GAP)
	local mark = Icon.new(icon, STAT_ICON, iconColor)
	mark.LayoutOrder = 1
	mark.Parent = group
	local value = textLabel("Value", Theme.Fonts.Numeric, Theme.Sizes.NumSmall, Theme.Colors.Text, 2)
	value.AutomaticSize = Enum.AutomaticSize.X
	value.Size = UDim2.fromScale(0, 1)
	value.Text = text
	value.Parent = group
	group.Parent = parent
end

function GlyphCard.new(props: Props): GlyphCard
	local trove = Trove.new()
	local def = props.Def
	local t = props.Localize.t
	local pigment = Theme.pigmentColor(def.Pigment)
	local ink = Theme.inkOn(pigment)
	local state: LoadoutEdit.CardState? = nil

	local sticker = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.PanelRaised,
		Lip = pigmentLip(def.Pigment),
		Corner = UDim.new(0, Theme.Sizes.CornerTile),
		Elevation = ELEVATION,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = props.LayoutOrder,
		Name = def.Id,
	})
	trove:Add(function()
		sticker:Destroy()
	end)
	local root = sticker.Instance :: Frame
	local face = sticker.Face

	-- The band, inside the face's ink outline, its bottom corners squared by a filler of its colour.
	local stroke = Theme.Sizes.Stroke
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BorderSizePixel = 0
	band.BackgroundColor3 = pigment
	band.Position = UDim2.fromOffset(stroke, stroke)
	band.Size = UDim2.new(1, -stroke * 2, 0, BAND_HEIGHT)
	band.ZIndex = 2
	Theme.corner(band, Theme.Sizes.CornerTile - stroke)
	local filler = Instance.new("Frame")
	filler.Name = "Square"
	filler.BorderSizePixel = 0
	filler.BackgroundColor3 = pigment
	filler.Position = UDim2.fromScale(0, 0.5)
	filler.Size = UDim2.fromScale(1, 0.5)
	filler.ZIndex = 2
	filler.Parent = band
	local bandRow = Instance.new("Frame")
	bandRow.Name = "Row"
	bandRow.BackgroundTransparency = 1
	bandRow.Size = UDim2.fromScale(1, 1)
	bandRow.ZIndex = 3
	local bandPadding = Instance.new("UIPadding")
	bandPadding.PaddingLeft = UDim.new(0, INSET)
	bandPadding.PaddingRight = UDim.new(0, INSET)
	bandPadding.Parent = bandRow
	listLayout(bandRow, Enum.FillDirection.Horizontal, ROW_GAP)
	local name = textLabel("Name", Theme.Fonts.Title, NAME_SIZE, ink, 1)
	name.Size = UDim2.fromScale(0, 1)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = t(def.NameKey)
	local nameFill = Instance.new("UIFlexItem")
	nameFill.FlexMode = Enum.UIFlexMode.Fill
	nameFill.Parent = name
	name.Parent = bandRow
	local sigil = textLabel("Sigil", Theme.Fonts.Bold, SIGIL_SIZE, ink, 2)
	sigil.AutomaticSize = Enum.AutomaticSize.X
	sigil.Size = UDim2.fromScale(0, 1)
	sigil.Text = (PigmentConfig.Sigils :: any)[def.Pigment] or ""
	sigil.Parent = bandRow
	bandRow.Parent = band
	band.Parent = face

	-- The body: the recipe, the numbers, the lore.
	local top = stroke + BAND_HEIGHT + ROW_GAP
	local bottom = Theme.Sizes.ButtonHeight + INSET + ROW_GAP
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, top)
	body.Size = UDim2.new(1, 0, 1, -(top + bottom))
	body.ZIndex = 2
	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingLeft = UDim.new(0, INSET)
	bodyPadding.PaddingRight = UDim.new(0, INSET)
	bodyPadding.Parent = body
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Vertical
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, ROW_GAP)
	bodyLayout.Parent = body
	body.Parent = face

	local recipe = bodyRow("Recipe", RECIPE_HEIGHT, 1, KEY_GAP, body)
	local stats = bodyRow("Stats", STAT_HEIGHT, 2, INSET, body)
	-- A hit mark, not ✦: that is the Orpiment's sigil.
	stat(stats, "Cross", nil, tostring(def.Damage), 1)
	stat(stats, "Drop", Theme.Colors.Info, tostring(def.Cost), 2)
	stat(stats, "Clock", nil, t("common.seconds", { seconds = def.Cooldown }), 3)
	local lore = textLabel("Lore", Theme.Fonts.Lore, LORE_SIZE, Theme.Colors.TextMuted, 3)
	lore.Size = UDim2.new(1, 0, 0, math.ceil(LORE_SIZE * LINE_HEIGHT) * LORE_LINES)
	lore.TextWrapped = true
	lore.TextXAlignment = Enum.TextXAlignment.Left
	lore.TextYAlignment = Enum.TextYAlignment.Top
	-- The lore is the one text a card may cut: the name and the button never are.
	lore.TextTruncate = Enum.TextTruncate.AtEnd
	lore.Text = t(def.DescriptionKey)
	lore.Parent = body

	-- Locked: a chalk veil and a lock over everything but the button, which says why.
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.BorderSizePixel = 0
	veil.BackgroundColor3 = Theme.Colors.Chalk
	veil.BackgroundTransparency = VEIL_TRANSPARENCY
	veil.Size = UDim2.fromScale(1, 1)
	veil.ZIndex = 5
	veil.Visible = false
	Theme.corner(veil, Theme.Sizes.CornerTile)
	local lock = Icon.new("Lock", LOCK_SIZE, Theme.Colors.Accent)
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Position = UDim2.new(0.5, 0, 0.5, -bottom / 2)
	lock.ZIndex = 5
	lock.Parent = veil
	veil.Parent = face

	-- Equipped: the outline thickens, and the check seal sits on the corner.
	local ring = Instance.new("Frame")
	ring.Name = "Equipped"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	ring.ZIndex = 7
	ring.Visible = false
	Theme.corner(ring, Theme.Sizes.CornerTile)
	Theme.stroke(ring, "Accent", RING_THICKNESS)
	ring.Parent = face
	local seal = Seal.new({
		Text = Theme.Glyphs.Check,
		Fill = Theme.Colors.SuccessFill,
		Size = SEAL_SIZE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -stroke * 2, 0, stroke * 2),
		Name = "Check",
		Parent = root,
	})
	seal.Instance.ZIndex = 4
	seal.Instance.Visible = false
	trove:Add(function()
		seal:Destroy()
	end)

	local button = Button.new({
		Name = "Action",
		Text = t("loadout.equip"),
		Variant = "Owner",
		Chapter = "Loadout",
		Size = UDim2.new(1, -INSET * 2, 0, Theme.Sizes.ButtonHeight),
		OnClick = props.OnAction,
	})
	button.Instance.AnchorPoint = Vector2.new(0.5, 1)
	button.Instance.Position = UDim2.new(0.5, 0, 1, -INSET)
	button.Instance.ZIndex = 6
	button.Instance.Parent = face
	trove:Add(function()
		button:Destroy()
	end)
	-- A disabled button hears nothing itself: a tap on a full loadout's Equip is still an answer to give.
	trove:Connect(button.Instance.Activated, function()
		if state == "Full" then
			props.OnRefused()
		end
	end)

	local recipeTrove = trove:Extend()
	local function setRecipe(_self: GlyphCard?, bindings: { [string]: string }, device: Device)
		recipeTrove:Clean()
		for index, step in ipairs(def.Combo) do
			if device == "Touch" then
				-- A phone presses discs, not keys: a small disc of the pigment with its sigil.
				local disc = Instance.new("Frame")
				disc.Name = step
				disc.BorderSizePixel = 0
				disc.BackgroundColor3 = Theme.pigmentColor(step)
				disc.Size = UDim2.fromOffset(DISC_SIZE, DISC_SIZE)
				disc.LayoutOrder = index
				Theme.corner(disc, Theme.Pill)
				Theme.stroke(disc, "Accent", Theme.Sizes.StrokeThin)
				local mark = textLabel("Sigil", Theme.Fonts.Bold, DISC_SIZE, Theme.inkOn(disc.BackgroundColor3), 1)
				mark.Size = UDim2.fromScale(0.8, 0.8)
				mark.AnchorPoint = Vector2.new(0.5, 0.5)
				mark.Position = UDim2.fromScale(0.5, 0.5)
				mark.TextScaled = true
				mark.Text = (PigmentConfig.Sigils :: any)[step] or ""
				mark.Parent = disc
				disc.Parent = recipe
				recipeTrove:Add(disc)
			else
				local cap = Keycap.new({
					Key = bindings[step] or step,
					Device = device,
					Localize = props.Localize,
					Pigment = step,
					LayoutOrder = index,
					Parent = recipe,
				})
				recipeTrove:Add(function()
					cap:Destroy()
				end)
			end
		end
	end
	setRecipe(nil, props.Bindings, props.Device)

	local function setState(_self: GlyphCard, next: LoadoutEdit.CardState, lockText: string?)
		state = next
		veil.Visible = next == "Locked"
		ring.Visible = next == "Equipped"
		seal.Instance.Visible = next == "Equipped"
		if next == "Equipped" then
			button:SetVariant("Secondary")
			button:SetText(t("loadout.unequip"))
			button:SetDisabled(false)
		elseif next == "Locked" then
			button:SetVariant("Secondary")
			button:SetText(t("loadout.equip"))
			button:SetDisabled(true, "Locked", lockText)
		elseif next == "Full" then
			button:SetVariant("Owner")
			button:SetText(t("loadout.equip"))
			button:SetDisabled(true, "Full", t("loadout.fullShort"))
		else
			button:SetVariant("Owner")
			button:SetText(t("loadout.equip"))
			button:SetDisabled(false)
		end
	end

	root.Parent = props.Parent

	local function destroy(_self: GlyphCard)
		trove:Destroy()
	end

	local object: GlyphCard = {
		Instance = root,
		Button = button,
		SetState = setState,
		SetRecipe = setRecipe,
		Destroy = destroy,
	}
	return object
end

return GlyphCard
