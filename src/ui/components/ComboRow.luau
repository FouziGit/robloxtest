--!strict
-- ComboRow: the sequence the player is pressing, and everything the HUD says about it (D-147). HudController
-- places it over the hotbar and the dock and feeds it what ComboController and the server say.
--
--   chips          one sticker per press, in the exact pigment pressed, growing in with a pop and folding out
--                  (docs/ART_BIBLE.md rule 3: nothing appears); a cast folds the row shut
--   next pigments  after the first press or two, faint chips of the pigments that go on toward a recipe: one
--                  step ahead, never the whole tree
--   preview        while the sequence already is a glyph and the controller waits to see whether it grows,
--                  "→ Brand" in the glyph's own colour over a line that drains for the time left, so the
--                  short wait reads as a choice and not as input lag
--   chain          glyphs the SERVER accepted in a row, from the second: it grows with the chain, lands on a
--                  splat of the last pigment from four, and sends a ring out on every cast from six
--   refusal        a cast refused (a cooldown, the ink, a sequence that matches nothing) is said under the
--                  chips, which shake: never a toast at the top of the screen in the middle of a fight
--   ghosts         for a new player, the recipe to press, drawn after everything, faint (OnboardingController),
--                  with a pointer each over the key the player has bound to it
--
-- A fight surface: the pigments are the schools' own and nothing wears a value colour (rule 11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local GlyphConfig = require(Config:WaitForChild("GlyphConfig"))
local Keycap = require(script.Parent.Keycap)
local Motion = require(script.Parent.Parent.Motion)
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local Splat = require(script.Parent.Splat)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))
local Trove = require(Packages.Trove)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }
-- The keys a player presses for each pigment, on the device they use (the hotbar's).
export type Keys = { Device: Keycap.Device, Keys: { [string]: string } }

export type Props = {
	-- The HUD's bottom stack, which places the row over the hotbar and the dock.
	Parent: Instance,
	Localize: Localizer,
	LayoutOrder: number?,
}

export type ComboRow = {
	Instance: Frame,
	SetSequence: (self: ComboRow, sequence: { string }) -> (),
	-- The pigments that go on from the sequence, drawn after it; an empty list clears them.
	SetContinuations: (self: ComboRow, pigments: { string }) -> (),
	-- The glyph the sequence already is and the seconds the controller waits for more, or nil.
	SetPreview: (self: ComboRow, glyphId: string?, windowSeconds: number?) -> (),
	-- `pigments` as ghost chips, or none with nil; with `keys`, each stands under the key that presses it.
	ShowGhosts: (self: ComboRow, pigments: { string }?, keys: Keys?) -> (),
	-- One accepted cast, with the chain length the server counted for it and the glyph's pigment.
	Cast: (self: ComboRow, chain: number, pigment: string?) -> (),
	-- The chain is over: the counter fades, and the next cast starts again at one.
	FadeStreak: (self: ComboRow) -> (),
	-- A cast refused, in words, under the chips.
	Refuse: (self: ComboRow, text: string) -> (),
	Destroy: (self: ComboRow) -> (),
}

local ComboRow = {}

local HUD = ThemeConfig.Hud
local CHIP_SIZE = HUD.ChipSize
local CHIP_COLLAPSED = UDim2.fromOffset(0, CHIP_SIZE)
local CHIP_OPEN = UDim2.fromOffset(CHIP_SIZE, CHIP_SIZE)
local CHIP_ELEVATION = 3
local SIGIL_SCALE = 0.6
local RING_INSET = 3
-- Pigments too dark for the ink outline alone: the sheet's ring shapes them.
local RINGED: { [string]: boolean } = { Indigo = true, Umber = true }
-- Two slots per press: the live chip and, just to its right, the chip that is folding away because the
-- sequence changed under it. Sharing one LayoutOrder left the two in an order Roblox does not define, so
-- a replacement could render to the LEFT of what it replaced.
local CHIP_ORDER_STRIDE = 2
local NEXT_ORDER = 100
local PREVIEW_ORDER = 150
local STREAK_ORDER = 160
local GHOST_ORDER = 200
local GHOST_TRANSPARENCY = 0.6
-- The ghosts' keys: caps this tall over the ghost chips, this far above them. Over, not under: under the row
-- stands the hotbar, which a cap there would cover.
local GHOST_KEY = 20
local GHOST_KEY_GAP = 4
-- The row's place among its siblings: above the dock and the hotbar (ZIndexBehavior.Sibling).
local ROW_Z = 2
-- The preview pill.
local PREVIEW_PADDING = 10
local PREVIEW_TEXT = 20
local PREVIEW_LINE = 3
local PREVIEW_ENTER = 0.6
local UMBER_STROKE = 3
-- Between a pill's lead and its words.
local PILL_LEAD_GAP = 6
-- The contrast words need (WCAG body text): a pigment's colour that falls short of it on ink writes its name in
-- the sheet, stroked in the pigment.
local BODY_CONTRAST = 4.5
-- The chain counter: shown from the second cast, growing by this much per cast past it up to a ceiling,
-- on a splat from STREAK_SPLAT casts, sending a ring from STREAK_RING.
local STREAK_MIN_SHOWN = 2
local STREAK_TEXT = 34
local STREAK_STROKE = 4
local STREAK_GROWTH = 0.08
local STREAK_MAX_SCALE = 1.4
local STREAK_POP_SCALE = 1.4
local STREAK_SPLAT = 4
local STREAK_RING = 6
local STREAK_SPLAT_SIZE = CHIP_SIZE * 1.6
local STREAK_SPLAT_TRANSPARENCY = 0.2
local RING_FROM = 0.6
local RING_TO = 1.6
local RING_TRANSPARENCY = 0.2
-- The refusal pill, under the chips.
local REFUSAL_HEIGHT = 30
local REFUSAL_TEXT = 16
local REFUSAL_GAP = 4
local REFUSAL_SECONDS = 1.4
local REFUSAL_ENTER = 0.8
local SHAKE = 8

type TroveObject = typeof(Trove.new())

local function label(name: string, font: Font, size: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	return text
end

-- An ink pill: the preview and the refusal.
local function pill(name: string, height: number, order: number, trove: TroveObject): (Frame, TextLabel, UIScale)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Size = UDim2.fromOffset(0, height)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Visible = false
	-- The pill hosts its plate: it is as wide as its row (Sticker's Host, D-170).
	local plate = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Corner = Theme.Pill,
		Host = frame,
	})
	trove:Add(function()
		plate:Destroy()
	end)
	-- What the pill says, in a row a lead can join (the preview's arrow).
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromScale(0, 1)
	row.ZIndex = 3
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PREVIEW_PADDING)
	padding.PaddingRight = UDim.new(0, PREVIEW_PADDING)
	padding.Parent = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, PILL_LEAD_GAP)
	layout.Parent = row
	row.Parent = frame
	local text = label("Text", Theme.Fonts.Bold, REFUSAL_TEXT, Theme.Colors.TextInverse)
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.fromScale(0, 1)
	text.ZIndex = 3
	text.LayoutOrder = 2
	text.Parent = row
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	trove:Add(function()
		Motion.cancel(scale)
	end)
	return frame, text, scale
end

-- A chip: a sticker in the exact pigment, its sigil in the ink that reads on it.
local function makeChip(name: string, order: number, pigment: string, trove: TroveObject): Frame
	local chip = Instance.new("Frame")
	chip.Name = name
	chip.BackgroundTransparency = 1
	chip.LayoutOrder = order
	chip.Size = CHIP_COLLAPSED
	chip.ClipsDescendants = true
	local color = Theme.pigmentColor(pigment)
	local sticker = Sticker.new({
		Kind = "Card",
		Fill = color,
		Corner = UDim.new(0, Theme.Sizes.CornerChip),
		Elevation = CHIP_ELEVATION,
		Size = UDim2.fromOffset(CHIP_SIZE, CHIP_SIZE),
		Parent = chip,
		Name = "Sticker",
	})
	trove:Add(function()
		sticker:Destroy()
	end)
	if RINGED[pigment] then
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.BackgroundTransparency = 1
		ring.Position = UDim2.fromOffset(RING_INSET, RING_INSET)
		ring.Size = UDim2.new(1, -RING_INSET * 2, 1, -RING_INSET * 2)
		Theme.corner(ring, Theme.Sizes.CornerChip - RING_INSET)
		Theme.stroke(ring, "PanelRaised", Theme.Sizes.StrokeThin)
		ring.Parent = sticker.Face
	end
	local sigil = label("Glyph", Theme.Fonts.Bold, math.floor(CHIP_SIZE * SIGIL_SCALE), Theme.inkOn(color))
	sigil.Size = UDim2.fromScale(1, 1)
	sigil.Text = PigmentConfig.Sigils[pigment :: any] or ""
	sigil.Parent = sticker.Face
	return chip
end

-- A hint rather than a press: everything the chip draws, faint.
local function veil(chip: Frame)
	for _, descendant in ipairs(chip:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.TextTransparency = GHOST_TRANSPARENCY
		elseif descendant:IsA("UIStroke") then
			descendant.Transparency = GHOST_TRANSPARENCY
		elseif descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
			descendant.BackgroundTransparency = GHOST_TRANSPARENCY
		end
	end
end

function ComboRow.new(props: Props): ComboRow
	local trove = Trove.new()
	local localize = props.Localize
	local chips: { Frame } = {}
	local chipPigments: { string } = {}
	local nexts: { Frame } = {}
	local ghosts: { Frame } = {}
	local ghostKeys: { Frame } = {}
	local streak = 0
	-- Bumped by every change, so the timer that ends a chain cannot end the one that replaced it.
	local streakGeneration = 0
	local refusalGeneration = 0

	local row = Instance.new("Frame")
	row.Name = "Combo"
	row.BackgroundTransparency = 1
	row.LayoutOrder = props.LayoutOrder or 0
	-- Over what stands under it in the HUD's stack: its refusal hangs onto the hotbar's slots (pointer) or the
	-- dock's plate (touch), which come after it and would paint over the whole row at the same ZIndex.
	row.ZIndex = ROW_Z
	row.Size = UDim2.fromOffset(0, CHIP_SIZE)
	row.AutomaticSize = Enum.AutomaticSize.X
	trove:Add(row)

	-- The chips and what reads beside them; the row shakes this when a cast is refused.
	local line = Instance.new("Frame")
	line.Name = "Chips"
	line.BackgroundTransparency = 1
	line.Size = UDim2.fromOffset(0, CHIP_SIZE)
	line.AutomaticSize = Enum.AutomaticSize.X
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = line
	line.Parent = row
	trove:Add(function()
		Motion.cancel(line)
	end)

	-- The preview: "→ name" on an ink pill, over a line that drains for the time the controller waits. The arrow
	-- is its own label, in the only face that has it (Theme.Glyphs); the name is in the title face.
	local preview, previewText, previewScale = pill("Preview", HUD.PreviewHeight, PREVIEW_ORDER, trove)
	previewText.FontFace = Theme.Fonts.Title
	previewText.TextSize = PREVIEW_TEXT
	local previewArrow = label("Arrow", Theme.Fonts.Symbol, PREVIEW_TEXT, Theme.Colors.TextInverse)
	previewArrow.AutomaticSize = Enum.AutomaticSize.X
	previewArrow.Size = UDim2.fromScale(0, 1)
	previewArrow.ZIndex = 3
	previewArrow.LayoutOrder = 1
	previewArrow.Text = Theme.Glyphs.Arrow
	previewArrow.Parent = previewText.Parent
	-- Umber has no colour that reads on ink, and Cinnabar's is too dark for words this size: their names are
	-- the sheet, stroked in the pigment.
	local previewStroke = Theme.stroke(previewText, "Bronze", UMBER_STROKE, "Contextual")
	local previewLine = Instance.new("Frame")
	previewLine.Name = "Window"
	previewLine.BorderSizePixel = 0
	previewLine.BackgroundColor3 = Theme.Colors.PanelRaised
	previewLine.AnchorPoint = Vector2.new(0.5, 1)
	previewLine.Position = UDim2.new(0.5, 0, 1, -PREVIEW_LINE)
	previewLine.ZIndex = 3
	Theme.corner(previewLine, Theme.Pill)
	previewLine.Parent = preview
	trove:Add(function()
		Motion.cancel(previewLine)
	end)
	preview.Parent = line

	-- The chain counter, on its splat and its ring, which the counter's scale carries with it.
	local streakHolder = Instance.new("Frame")
	streakHolder.Name = "Streak"
	streakHolder.BackgroundTransparency = 1
	streakHolder.LayoutOrder = STREAK_ORDER
	streakHolder.Size = UDim2.fromOffset(0, CHIP_SIZE)
	streakHolder.AutomaticSize = Enum.AutomaticSize.X
	streakHolder.Visible = false
	local streakLabel = label("Count", Theme.Fonts.Title, STREAK_TEXT, Theme.Colors.PanelRaised)
	streakLabel.AutomaticSize = Enum.AutomaticSize.X
	streakLabel.Size = UDim2.fromScale(0, 1)
	streakLabel.ZIndex = 3
	streakLabel.Text = ""
	streakLabel.Parent = streakHolder
	local streakStroke = Theme.stroke(streakLabel, "Outline", STREAK_STROKE, "Contextual")
	local streakScale = Instance.new("UIScale")
	streakScale.Name = "Scale"
	streakScale.Parent = streakHolder
	local streakSplat: GuiObject? = nil
	local streakRing: ImageLabel? = nil
	local streakRingScale: UIScale? = nil
	streakHolder.Parent = line
	trove:Add(function()
		Motion.cancel(streakScale)
	end)

	-- The refusal hangs under the row from a point, so it never takes room from the stack under it.
	local refusalAnchor = Instance.new("Frame")
	refusalAnchor.Name = "Refusal"
	refusalAnchor.BackgroundTransparency = 1
	refusalAnchor.Position = UDim2.fromScale(0.5, 1)
	refusalAnchor.Size = UDim2.new()
	refusalAnchor.ZIndex = 10
	local refusal, refusalText, refusalScale = pill("Pill", REFUSAL_HEIGHT, 0, trove)
	refusal.AnchorPoint = Vector2.new(0.5, 0)
	refusal.Position = UDim2.fromOffset(0, REFUSAL_GAP)
	refusal.Parent = refusalAnchor
	refusalAnchor.Parent = row

	-- The ghosts' keys, over the right end of the row: the ghosts come after everything, so a slot as wide as a
	-- chip per ghost, from the right, stands each cap over its chip.
	local keyStrip = Instance.new("Frame")
	keyStrip.Name = "GhostKeys"
	keyStrip.BackgroundTransparency = 1
	keyStrip.AnchorPoint = Vector2.new(1, 1)
	keyStrip.Position = UDim2.new(1, 0, 0, -GHOST_KEY_GAP)
	keyStrip.Size = UDim2.fromOffset(0, CHIP_SIZE)
	keyStrip.AutomaticSize = Enum.AutomaticSize.X
	keyStrip.ZIndex = 10
	local keyLayout = Instance.new("UIListLayout")
	keyLayout.FillDirection = Enum.FillDirection.Horizontal
	keyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	keyLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	keyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	keyLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	keyLayout.Parent = keyStrip
	keyStrip.Parent = row

	row.Parent = props.Parent

	-- Folds a chip out of the row and destroys it once it is gone.
	local function fold(chip: Frame)
		Motion.to(chip, { Size = CHIP_COLLAPSED }, "UiSnappy", function()
			chip:Destroy()
		end)
	end

	local function grow(chip: Frame)
		chip.Parent = line
		Motion.to(chip, { Size = CHIP_OPEN }, "UiPop")
	end

	-- The chips that still match the new sequence stay; the rest collapse out of the row and the new ones
	-- grow into it.
	local function setSequence(_self: ComboRow, sequence: { string })
		local keep = 0
		while keep < #chipPigments and keep < #sequence and chipPigments[keep + 1] == sequence[keep + 1] do
			keep += 1
		end
		for index = #chipPigments, keep + 1, -1 do
			local chip = chips[index]
			chips[index] = nil
			chipPigments[index] = nil
			chip.Name = chip.Name .. "Out"
			chip.LayoutOrder += 1
			fold(chip)
		end
		for index = keep + 1, #sequence do
			local chip = makeChip("Chip" .. index, index * CHIP_ORDER_STRIDE, sequence[index], trove)
			grow(chip)
			chips[index] = chip
			chipPigments[index] = sequence[index]
		end
	end

	-- Faint chips (the next pigments, the ghosts): the old ones fold out and the new ones grow in.
	local function replaceFaint(list: { Frame }, prefix: string, order: number, pigments: { string }?)
		for _, chip in ipairs(list) do
			fold(chip)
		end
		table.clear(list)
		if pigments == nil then
			return
		end
		for index, pigment in ipairs(pigments) do
			local chip = makeChip(prefix .. index, order + index, pigment, trove)
			veil(chip)
			grow(chip)
			table.insert(list, chip)
		end
	end

	local function setContinuations(_self: ComboRow, pigments: { string })
		replaceFaint(nexts, "Next", NEXT_ORDER, pigments)
	end

	local function showGhosts(_self: ComboRow, pigments: { string }?, keys: Keys?)
		replaceFaint(ghosts, "Ghost", GHOST_ORDER, pigments)
		for _, slot in ipairs(ghostKeys) do
			fold(slot)
		end
		table.clear(ghostKeys)
		if pigments == nil or keys == nil then
			return
		end
		for index, pigment in ipairs(pigments) do
			local key = keys.Keys[pigment]
			if key == nil then
				continue
			end
			local slot = Instance.new("Frame")
			slot.Name = "Key" .. index
			slot.BackgroundTransparency = 1
			slot.LayoutOrder = index
			slot.Size = CHIP_COLLAPSED
			slot.ClipsDescendants = true
			local cap = Keycap.new({
				Key = key,
				Device = keys.Device,
				Localize = localize,
				Size = GHOST_KEY,
				Pigment = pigment,
				Parent = slot,
			})
			-- A cap's lip is rimmed in ink from outside it (Sticker), and the slot clips as it opens: the cap stands
			-- its outline's reach above the slot's foot, in whole units, so the rim is drawn whole.
			cap.Instance.AnchorPoint = Vector2.new(0.5, 1)
			cap.Instance.Position = UDim2.new(0.5, 0, 1, -math.ceil(Theme.strokeThickness(Theme.Sizes.StrokeThin)))
			slot.Parent = keyStrip
			Motion.to(slot, { Size = CHIP_OPEN }, "UiPop")
			table.insert(ghostKeys, slot)
		end
	end

	local function setPreview(_self: ComboRow, glyphId: string?, windowSeconds: number?)
		local def = if glyphId ~= nil then GlyphConfig.byId(glyphId) else nil
		if def == nil then
			if preview.Visible then
				Motion.to(previewScale, { Scale = 0 }, "UiExit", function()
					preview.Visible = false
				end)
			end
			return
		end
		-- The glyph's own colour over ink (rule 2), where it reads as words; the sheet in its stroke where not.
		local fill, edge = Theme.pigmentOnInk(def.Pigment)
		local short = Theme.contrast(fill, Theme.Colors.Plate) < BODY_CONTRAST
		previewText.TextColor3 = if short then Theme.Colors.PanelRaised else fill
		previewArrow.TextColor3 = previewText.TextColor3
		previewStroke.Color = if short then Theme.pigmentColor(def.Pigment) else edge
		previewStroke.Enabled = short or def.Pigment == "Umber"
		previewText.Text = localize.t(def.NameKey)
		preview.Visible = true
		Motion.set(previewScale, { Scale = PREVIEW_ENTER })
		Motion.to(previewScale, { Scale = 1 }, "UiPop")
		-- The window, draining: the time left to grow the sequence into a longer glyph.
		Motion.set(previewLine, { Size = UDim2.new(1, -PREVIEW_PADDING * 2, 0, PREVIEW_LINE) })
		if windowSeconds ~= nil and windowSeconds > 0 then
			Motion.to(previewLine, { Size = UDim2.fromOffset(0, PREVIEW_LINE) }, "Ui")
		end
	end

	local function refreshStreak()
		streakLabel.Text = localize.t("hud.sequence.streak", { count = streak })
		streakHolder.Visible = streak >= STREAK_MIN_SHOWN
	end

	-- The chain is over: it fades rather than vanishing, and the next cast starts again at one.
	local function fadeStreak(_self: ComboRow?)
		if streak == 0 then
			return
		end
		streak = 0
		streakGeneration += 1
		if not streakHolder.Visible then
			return
		end
		-- What is lost fades out. Not Cinnabar: nothing is about to hit the player (rule 7).
		streakLabel.TextColor3 = Theme.Colors.TextMuted
		Motion.to(streakScale, { Scale = 0 }, "Ui", function()
			refreshStreak()
			Motion.set(streakScale, { Scale = 1 })
		end)
	end

	-- A chain of four and more lands on a splat of its last pigment.
	local function streakBacking(color: Color3)
		local splat = streakSplat
		if streak < STREAK_SPLAT then
			if splat ~= nil then
				splat.Visible = false
			end
			return
		end
		if splat == nil then
			splat = Splat.new({
				Size = UDim2.fromOffset(STREAK_SPLAT_SIZE, STREAK_SPLAT_SIZE),
				Tint = color,
				Rotation = Splat.rotation(STREAK_SPLAT),
				Transparency = STREAK_SPLAT_TRANSPARENCY,
				ZIndex = 1,
				Name = "Splat",
				Parent = streakHolder,
			})
			streakSplat = splat
		end
		if splat ~= nil then
			splat.Visible = true
			Splat.tint(splat, color)
		end
	end

	-- From six, every cast sends a ring out of the counter.
	local function streakPulse(color: Color3)
		if streak < STREAK_RING then
			return
		end
		local ring, ringScale = streakRing, streakRingScale
		if ring == nil or ringScale == nil then
			local id = Theme.texture("ShockwaveRing")
			if id == "" then
				return
			end
			local image = Instance.new("ImageLabel")
			image.Name = "Ring"
			image.BackgroundTransparency = 1
			image.Image = id
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Position = UDim2.fromScale(0.5, 0.5)
			image.Size = UDim2.fromOffset(CHIP_SIZE, CHIP_SIZE)
			image.ZIndex = 2
			local imageScale = Instance.new("UIScale")
			imageScale.Parent = image
			image.Parent = streakHolder
			trove:Add(function()
				Motion.cancel(image)
				Motion.cancel(imageScale)
			end)
			ring, ringScale = image, imageScale
			streakRing, streakRingScale = image, imageScale
		end
		local image, imageScale = ring :: ImageLabel, ringScale :: UIScale
		image.ImageColor3 = color
		Motion.set(image, { ImageTransparency = RING_TRANSPARENCY })
		Motion.set(imageScale, { Scale = RING_FROM })
		Motion.to(image, { ImageTransparency = 1 }, "Ui")
		Motion.to(imageScale, { Scale = RING_TO }, "Ui")
	end

	-- The counter lands on every cast of a chain and ends itself when the window passes without another one.
	local function cast(_self: ComboRow, chain: number, pigment: string?)
		streak = math.max(1, chain)
		streakGeneration += 1
		local generation = streakGeneration
		refreshStreak()
		if streakHolder.Visible then
			local color, edge = Theme.Colors.PanelRaised, Theme.Colors.Outline
			if pigment ~= nil then
				color, edge = Theme.pigmentOnInk(pigment)
			end
			streakLabel.TextColor3 = color
			streakStroke.Color = edge
			streakBacking(color)
			streakPulse(color)
			-- The count lands: it drops onto the row from larger than itself, and the spring settles it at a
			-- size that grows with the chain.
			local rest = math.min(STREAK_MAX_SCALE, 1 + STREAK_GROWTH * (streak - STREAK_MIN_SHOWN))
			Motion.set(streakScale, { Scale = math.max(STREAK_POP_SCALE, rest) })
			Motion.to(streakScale, { Scale = rest }, "UiPop")
		end
		task.delay(GameConfig.Combo.ChainWindowSeconds, function()
			if streakGeneration == generation then
				fadeStreak(nil)
			end
		end)
	end

	local function refuse(_self: ComboRow, text: string)
		refusalGeneration += 1
		local generation = refusalGeneration
		refusalText.Text = text
		refusal.Visible = true
		Motion.set(refusalScale, { Scale = REFUSAL_ENTER })
		Motion.to(refusalScale, { Scale = 1 }, "UiPop")
		Motion.shake(line, SHAKE)
		task.delay(REFUSAL_SECONDS, function()
			if refusalGeneration ~= generation then
				return
			end
			Motion.to(refusalScale, { Scale = 0 }, "UiExit", function()
				if refusalGeneration == generation then
					refusal.Visible = false
				end
			end)
		end)
	end

	local function destroy(_self: ComboRow)
		trove:Destroy()
	end

	local object: ComboRow = {
		Instance = row,
		SetSequence = setSequence,
		SetContinuations = setContinuations,
		SetPreview = setPreview,
		ShowGhosts = showGhosts,
		Cast = cast,
		FadeStreak = fadeStreak,
		Refuse = refuse,
		Destroy = destroy,
	}
	return object
end

return ComboRow
