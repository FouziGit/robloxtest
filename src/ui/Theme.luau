--!strict
-- Central UI theme: colors, fonts, sizes, spacing, strokes, gradients. Every component reads from here,
-- and this reads the palette and the typography from ThemeConfig, which is pure data a test holds to
-- docs/ART_BIBLE.md and to a contrast ratio. Nothing in src/ui names a colour or a font that is not here.

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local AssetIds = require(Config:WaitForChild("AssetIds"))
local Log = require(Shared:WaitForChild("Util"):WaitForChild("Log"))
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local RankingConfig = require(Config:WaitForChild("RankingConfig"))
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))

local log = Log.new("Theme")

local Theme = {}

export type StrokeMode = "Border" | "Contextual"
export type StrokePosition = "Inner" | "Outer" | "Center"
-- A menu's focus ring shows the primary yellow; a fight's may not (rule 11), so its inner ring is sheet.
export type FocusKind = "Menu" | "Fight"
export type Chapter = { Band: Color3, Title: Color3, Lip: Color3, Stripe: boolean }
export type Rarity = { Fill: Color3, Ink: Color3, Pips: number, WordKey: string, Seal: boolean, Shimmer: boolean }
export type Rank = { Fill: Color3, Ink: Color3, Rim: Color3?, Seal: boolean, Shimmer: boolean, NameKey: string }

-- Each unknown name is reported once, with what asked for it: a typo in a caller is a bug to find, and a
-- warning repeated every frame hides every other line of the output.
local warned: { [string]: boolean } = {}
local function warnOnce(key: string, message: string, ...: any)
	if warned[key] then
		return
	end
	warned[key] = true
	log.warn(message, ...)
end

local function fromRgb(rgb: ThemeConfig.Rgb): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- The only public converter: a cosmetic's tone swatch or a skin shade is a triple from a config, and it
-- is turned into a colour here like every role is.
function Theme.rgb(tuple: { number }): Color3
	return fromRgb(tuple)
end

Theme.Colors = {
	Panel = fromRgb(ThemeConfig.Colors.Panel),
	PanelRaised = fromRgb(ThemeConfig.Colors.PanelRaised),
	Chalk = fromRgb(ThemeConfig.Colors.Chalk),
	Border = fromRgb(ThemeConfig.Colors.Border),
	Text = fromRgb(ThemeConfig.Colors.Text),
	TextMuted = fromRgb(ThemeConfig.Colors.TextMuted),
	TextInverse = fromRgb(ThemeConfig.Colors.TextInverse),
	Accent = fromRgb(ThemeConfig.Colors.Accent),
	Outline = fromRgb(ThemeConfig.Colors.Outline),
	Plate = fromRgb(ThemeConfig.Colors.Plate),
	Well = fromRgb(ThemeConfig.Colors.Well),
	Overlay = fromRgb(ThemeConfig.Colors.Overlay),
	Primary = fromRgb(ThemeConfig.Colors.Primary),
	SuccessFill = fromRgb(ThemeConfig.Colors.SuccessFill),
	Success = fromRgb(ThemeConfig.Colors.Success),
	InfoFill = fromRgb(ThemeConfig.Colors.InfoFill),
	Ink = fromRgb(ThemeConfig.Colors.Ink),
	Info = fromRgb(ThemeConfig.Colors.Info),
	DangerFill = fromRgb(ThemeConfig.Colors.DangerFill),
	Danger = fromRgb(ThemeConfig.Colors.Danger),
	Ally = fromRgb(ThemeConfig.Colors.Ally),
	Health = fromRgb(ThemeConfig.Colors.Health),
	Epic = fromRgb(ThemeConfig.Colors.Epic),
	Premium = fromRgb(ThemeConfig.Colors.Premium),
	Bronze = fromRgb(ThemeConfig.Colors.Bronze),
}

-- The same colours by role name, for the tables that name a role (chapters, rarities, ranks, gradients).
local byRole: { [string]: Color3 } = {}
for role, rgb in pairs(ThemeConfig.Colors) do
	byRole[role] = fromRgb(rgb)
end

-- The colour of `role`. An unknown role is a typo in a config and warns once; the ink is what it draws.
function Theme.color(role: string): Color3
	local color: Color3? = byRole[role]
	if color == nil then
		warnOnce("role:" .. role, "no colour role %s: drawn in ink", role)
		return Theme.Colors.Accent
	end
	return color
end

-- A Font (FontFace) rather than an Enum.Font: the enum has one weight per family, and the interface is set
-- in four families at several weights, one of them italic. Components write `label.FontFace = Theme.Fonts.X`.
local function font(def: ThemeConfig.FontDef): Font
	local family = Font.fromEnum((Enum.Font :: any)[def.Font] :: Enum.Font).Family
	local weight = (Enum.FontWeight :: any)[def.Weight] :: Enum.FontWeight
	local style = (Enum.FontStyle :: any)[def.Style or "Normal"] :: Enum.FontStyle
	return Font.new(family, weight, style)
end

Theme.Fonts = {
	-- Screen titles, tile labels, splashes, the chain counter, the countdown.
	Title = font(ThemeConfig.Fonts.Title),
	-- Hero numbers inside a splash.
	Display = font(ThemeConfig.Fonts.Display),
	Body = font(ThemeConfig.Fonts.Body),
	-- Buttons, row titles, labels.
	Bold = font(ThemeConfig.Fonts.Bold),
	-- Ribbons, badges, tags, the words on a keycap.
	Label = font(ThemeConfig.Fonts.Label),
	-- Numbers that fly past the eye: a condensed grotesque, per docs/ART_BIBLE.md. Condensed because a
	-- four-digit hit has to stay one readable block at arm's length on a phone, and because it has to
	-- not be the same face as the prose, which is what makes a number read as a number.
	Numeric = font(ThemeConfig.Fonts.Numeric),
	-- Glyph flavour lines, empty states, the pass subtitle: the page keeps its voice.
	Lore = font(ThemeConfig.Fonts.Lore),
	-- DropCap only: one illuminated character, never a word.
	Initial = font(ThemeConfig.Fonts.Initial),
	-- The D-pad arrows, which only the roman has.
	Symbol = font(ThemeConfig.Fonts.Symbol),
}

-- Base sizes at UIScale 1 (1080p). Screens apply Theme.scaleFor(viewport). The comments give the size a
-- landscape phone draws at the touch floor of 0.68.
Theme.Sizes = {
	TextSmall = 16, -- 10.9 on a phone: the floor
	TextBody = 18,
	TextButton = 20,
	TextLarge = 22,
	TextTitle = 30, -- 20.4 on a phone
	TextHero = 44,
	-- The Result's outcome and the round banners.
	TextDisplay = 72,
	-- The countdown's 3-2-1.
	TextMega = 120,
	-- Ribbons and tags, in the heavy weight.
	TextLabel = 15,
	NumSmall = 20,
	Num = 26,
	NumLarge = 36,
	NumScore = 48,
	ButtonHeight = 52,
	RowHeight = 56,
	TileHeight = 150,
	-- The HUD's chips, hotbar slots and pips are ThemeConfig.Hud's, one home for the numbers HudFit adds up.
	Keycap = 28,
	Badge = 32,
	Medallion = 48,
	-- The ink outline of a sticker, and the thin one of a row, a chip or a keycap.
	Stroke = 3,
	StrokeThin = 2,
	CornerPanel = 20,
	CornerTile = 18,
	CornerCard = 14,
	CornerChip = 12,
	CornerKeycap = 6,
	CornerRadius = 20,
	CornerRadiusSmall = 12,
	Padding = 16,
	PaddingSmall = 8,
	Gap = 10,
	-- The largest a screen card grows to with a pointer; on a touch-only device it fills 94 % by 90 %.
	PanelWidth = 960,
	PanelHeight = 600,
	TouchButton = 64,
}

-- The corner of a pill: buttons, badges, bars, toggles, discs, seals.
Theme.Pill = UDim.new(0.5, 0)

-- ScreenGui draw order. Roblox leaves the relative order of two ScreenGuis with the same DisplayOrder
-- undefined, and a screen's dim overlay only covers what sits below its own ScreenGui, so every layer
-- owns a distinct value. Spaced by ten so a new layer slots in without renumbering the others.
-- The World Boss band has no entry: it is a child of the HUD's own top-centre column, not a ScreenGui,
-- precisely so it cannot race the HUD for draw order.
Theme.Layers = {
	Hud = 10,
	-- Centre splashes: match found, the countdown, a round won or lost. Under any menu.
	Banner = 20,
	Screen = 30,
	Result = 40, -- above the menus: the match is over, the result is the only thing left to read
	-- Notification layer. A server message explains what just happened (a refused purchase, a failed
	-- claim) and is worthless once something covers it, so nothing may be layered above this.
	Toast = 50,
}

-- Symbols the interface draws as text. Every one is in both bundled faces of Arimo, the engine's first fallback,
-- so it is drawn whatever face its label is set in (tests/Sigils.spec.luau, D-149); the arrows are set in
-- Fonts.Symbol, the only face of the interface that has them. The cross, the tick, the play and the pip are the
-- nearest shapes that are: the fallback has no ✕, ✓, ▶ or ◆ and would draw each as an empty box.
Theme.Glyphs = {
	Close = "×",
	Check = "√",
	Play = "►",
	Down = "▼",
	Pip = "♦",
	Dot = "●",
	Back = "‹",
	Next = "›",
	Arrow = "→",
	Plus = "+",
	Minus = "−",
}

Theme.Timing = ThemeConfig.Timing
Theme.Budget = ThemeConfig.Budget

-- Reference resolution the sizes above are designed at (ThemeConfig.Scale, D-128).
Theme.ReferenceHeight = ThemeConfig.Scale.ReferenceHeight
-- Shortest side a touch target may render at, in real screen pixels (Roblox, iOS and Android all ask
-- for 44). The UIScale below 1 on a phone must never eat into it.
Theme.MinTouchTarget = 44
-- The thinnest a line of the interface may render, in real pixels: a three-unit outline at the touch
-- floor would otherwise fall to two, and a two-unit one to one, if the engine scales strokes with UIScale.
local MIN_STROKE_PIXELS = 2

-- Viewport assumed before a camera exists: 16:9 at the reference height, which scales by exactly 1.
local FALLBACK_VIEWPORT = Vector2.new(Theme.ReferenceHeight * 16 / 9, Theme.ReferenceHeight)

-- A device with a touch screen and no keyboard: a phone or a tablet held in the hand. A touch laptop or a
-- tablet with a keyboard is used like a desktop and gets the pointer floor.
local function touchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end
-- The same test, for a component laid out per device: a screen card has no size cap on a phone.
Theme.touchOnly = touchOnly

function Theme.scaleFor(viewportSize: Vector2): number
	return ThemeConfig.scaleFor(viewportSize.Y, touchOnly())
end

-- The scale every ScreenRoot is currently applying. Components read it from here so the sizing rules
-- below live in one place instead of being re-derived per component.
function Theme.activeScale(): number
	local camera: Camera? = workspace.CurrentCamera
	if camera == nil then
		return Theme.scaleFor(FALLBACK_VIEWPORT)
	end
	return Theme.scaleFor(camera.ViewportSize)
end

-- `pixels` real screen pixels expressed as an unscaled offset: every offset under a ScreenRoot is
-- multiplied by its UIScale, so a size that must render at a fixed pixel count is divided by it first.
local function unscaled(pixels: number): number
	return pixels / Theme.activeScale()
end

-- Height a touch target of `designHeight` really occupies: minPixelSize below floors it at
-- MinTouchTarget real pixels, so a band built around it (a header, a footer, a card row) has to reserve
-- the same height or the target overflows it on a phone.
function Theme.touchTargetHeight(designHeight: number): number
	return math.max(designHeight, unscaled(Theme.MinTouchTarget))
end

-- Calls `callback` now and again whenever the active scale can have changed. Returns the disconnect
-- function, which a Trove holds directly.
function Theme.bindScale(callback: () -> ()): () -> ()
	local viewportConnection: RBXScriptConnection? = nil

	local function bindCamera()
		local previous = viewportConnection
		if previous ~= nil then
			previous:Disconnect()
			viewportConnection = nil
		end
		local camera: Camera? = workspace.CurrentCamera
		if camera ~= nil then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(callback)
		end
		callback()
	end

	local cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()

	return function()
		cameraConnection:Disconnect()
		local connection = viewportConnection
		if connection ~= nil then
			connection:Disconnect()
			viewportConnection = nil
		end
	end
end

-- Floors `object` at `pixels` real pixels on both axes whatever the UIScale above it: the scale tunes
-- type for the viewport and must not shrink what a finger has to hit (touch targets pass
-- Theme.MinTouchTarget). The constraint follows the viewport and releases itself with the object, so
-- callers only destroy the object.
function Theme.minPixelSize(object: GuiObject, pixels: number)
	local constraint = Instance.new("UISizeConstraint")
	local unbind = Theme.bindScale(function()
		local minimum = unscaled(pixels)
		constraint.MinSize = Vector2.new(minimum, minimum)
	end)
	constraint.Destroying:Once(unbind)
	constraint.Parent = object
end

-- Rounds `parent`'s corners by `radius` (a design offset, or Theme.Pill).
function Theme.corner(parent: Instance, radius: number | UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius :: number)
	corner.Parent = parent
	return corner
end

-- Every stroke of the interface (docs/ART_BIBLE.md rule 11: the outline is what detaches a vivid shape
-- from the page). Fixed-size and round-jointed; a Border stroke sits Inner unless told otherwise, so an
-- outline never grows a shape past its layout. The thickness is floored at MIN_STROKE_PIXELS real pixels
-- whether or not the engine applies the UIScale to it, and is read once, when the stroke is made: a scale
-- only changes with the viewport, and a screen is rebuilt long before that matters. Never tween the
-- Thickness of a stroke on text: animate its Transparency.
function Theme.stroke(
	parent: Instance,
	color: string | Color3,
	thickness: number,
	mode: StrokeMode?,
	position: StrokePosition?
): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = if typeof(color) == "Color3" then color else Theme.color(color :: string)
	stroke.Thickness = math.max(thickness, MIN_STROKE_PIXELS / Theme.activeScale())
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	if mode == "Contextual" then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	else
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		if position == "Outer" then
			stroke.BorderStrokePosition = Enum.BorderStrokePosition.Outer
		elseif position == "Center" then
			stroke.BorderStrokePosition = Enum.BorderStrokePosition.Center
		else
			stroke.BorderStrokePosition = Enum.BorderStrokePosition.Inner
		end
	end
	stroke.Parent = parent
	return stroke
end

local function numberSequence(keypoints: { ThemeConfig.Keypoint }): NumberSequence
	local sequence: { NumberSequenceKeypoint } = {}
	for _, keypoint in ipairs(keypoints) do
		table.insert(sequence, NumberSequenceKeypoint.new(keypoint[1], keypoint[2]))
	end
	return NumberSequence.new(sequence)
end

-- A new UIGradient (not parented) built from ThemeConfig.Gradients[name]. `base` is the colour a
-- gradient made of "Base" stops is drawn from: a header band's chapter, a list's card fill.
function Theme.gradient(name: string, base: Color3?): UIGradient
	local gradient = Instance.new("UIGradient")
	local def = ThemeConfig.Gradients[name]
	if def == nil then
		warnOnce("gradient:" .. name, "no gradient %s: drawn without one", name)
		gradient.Enabled = false
		return gradient
	end
	local keypoints: { ColorSequenceKeypoint } = {}
	for _, stop in ipairs(def.Color) do
		local color: Color3
		if stop.Role == "Base" then
			if base == nil then
				warnOnce("gradient base:" .. name, "gradient %s needs a base colour: drawn on the page", name)
			end
			color = base or Theme.Colors.Panel
		else
			color = Theme.color(stop.Role)
		end
		local shade = stop.Shade
		if shade ~= nil then
			color = Theme.shade(color, shade)
		end
		table.insert(keypoints, ColorSequenceKeypoint.new(stop.Time, color))
	end
	gradient.Color = ColorSequence.new(keypoints)
	local transparency = def.Transparency
	if transparency ~= nil then
		gradient.Transparency = numberSequence(transparency)
	end
	gradient.Rotation = def.Rotation
	if def.Kind == "Conical" then
		gradient.Type = Enum.GradientType.Conical
	elseif def.Kind == "Radial" then
		gradient.Type = Enum.GradientType.Radial
	end
	return gradient
end

-- The transparency of the Result's auto-close ring with `fraction` of it left (ThemeConfig.ringTransparency).
function Theme.ringTransparency(fraction: number): NumberSequence
	return numberSequence(ThemeConfig.ringTransparency(fraction))
end

-- The content id of an AssetIds texture, or "" when it has not been uploaded: the caller draws its
-- fallback. Warns once per key, naming what is missing.
function Theme.texture(key: string): string
	local id, known = AssetIds.get(key)
	if not known then
		warnOnce("texture:" .. key, "no texture %s in AssetIds: drawing its fallback", key)
	elseif id == "" then
		warnOnce("texture:" .. key, "texture %s is not uploaded yet: drawing its fallback", key)
	end
	return id
end

-- The exact pigment. An unknown id warns once and is drawn in ink.
function Theme.pigmentColor(pigmentId: string): Color3
	local rgb = PigmentConfig.Colors[pigmentId :: any]
	if rgb == nil then
		warnOnce("pigment:" .. pigmentId, "no pigment %s: drawn in ink", pigmentId)
		return Theme.Colors.Accent
	end
	return fromRgb(rgb)
end

-- The colour a pigment takes as text or a number over ink, and the stroke around it. Umber has no colour
-- that reads on ink: it is the sheet, in an Umber stroke.
function Theme.pigmentOnInk(pigmentId: string): (Color3, Color3)
	if pigmentId == "Umber" then
		return Theme.Colors.PanelRaised, Theme.Colors.Bronze
	end
	local rgb = ThemeConfig.PigmentOnInk[pigmentId]
	if rgb == nil then
		warnOnce("pigment on ink:" .. pigmentId, "no pigment %s to draw on ink: drawn as the sheet", pigmentId)
		return Theme.Colors.PanelRaised, Theme.Colors.Outline
	end
	return fromRgb(rgb), Theme.Colors.Outline
end

-- The lip under a pressable face (ThemeConfig.Lips). An unknown key warns once and sits on chalk.
function Theme.lip(key: string): Color3
	local rgb = ThemeConfig.Lips[key]
	if rgb == nil then
		warnOnce("lip:" .. key, "no lip %s: drawn in chalk", key)
		return fromRgb(ThemeConfig.Lips.Secondary)
	end
	return fromRgb(rgb)
end

-- A screen's chapter: its band, the ink of its title, the lip of its Owner buttons, and whether its ink
-- band carries the five-pigment stripe.
function Theme.chapter(screenId: string): Chapter
	local role = ThemeConfig.Chapters[screenId]
	if role == nil then
		warnOnce("chapter:" .. screenId, "no chapter for %s: drawn in ink", screenId)
		role = "Plate"
	end
	return {
		Band = Theme.color(role),
		Title = Theme.color(ThemeConfig.labelRole(role)),
		Lip = Theme.lip(ThemeConfig.LipFor[role] or "Secondary"),
		Stripe = ThemeConfig.ChapterStripe[screenId] == true,
	}
end

-- A rarity's fill, the ink on it, its pips and its word: colour is never the only cue.
function Theme.rarity(rarity: string): Rarity
	local def = ThemeConfig.Rarity[rarity]
	if def == nil then
		warnOnce("rarity:" .. rarity, "no rarity %s: drawn as Common", rarity)
		rarity = "Common"
		def = ThemeConfig.Rarity.Common
	end
	return {
		Fill = Theme.color(def.Fill),
		Ink = Theme.color(ThemeConfig.labelRole(def.Fill)),
		Pips = def.Pips,
		WordKey = "shop.rarity." .. rarity,
		Seal = def.Seal == true,
		Shimmer = def.Shimmer == true,
	}
end

local rankNames: { [string]: string } = {}
for _, tier in ipairs(RankingConfig.Tiers) do
	rankNames[tier.Id] = tier.NameKey
end

-- A rank's seal: the ladder illuminates as it climbs (ThemeConfig.Ranks).
function Theme.rank(tierId: string): Rank
	local def = ThemeConfig.Ranks[tierId]
	local nameKey = rankNames[tierId]
	if def == nil or nameKey == nil then
		warnOnce("rank:" .. tierId, "no rank %s: drawn as the first", tierId)
		local first = RankingConfig.Tiers[1]
		tierId = first.Id
		def = ThemeConfig.Ranks[first.Id]
		nameKey = first.NameKey
	end
	local rim = def.Rim
	return {
		Fill = Theme.color(def.Fill),
		Ink = Theme.color(ThemeConfig.labelRole(def.Fill)),
		Rim = if rim ~= nil then Theme.color(rim) else nil,
		Seal = def.Seal == true,
		Shimmer = def.Shimmer == true,
		NameKey = nameKey,
	}
end

-- The gamepad's focus: a double ring, ink outside and yellow inside, so it reads on every fill -- the ink
-- ring on the yellow face, the yellow ring on an ink tile -- where a single charcoal ring vanished on every
-- charcoal thing it framed. Used as a SelectionImageObject; `corner` follows the target (a pill by default).
function Theme.focusRing(kind: FocusKind?, corner: UDim?): Frame
	local root = Instance.new("Frame")
	root.Name = "Selection"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)

	local function ring(name: string, grow: number, color: string, position: StrokePosition)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.new(1, grow, 1, grow)
		Theme.corner(frame, corner or Theme.Pill)
		Theme.stroke(frame, color, Theme.Sizes.Stroke, "Border", position)
		frame.Parent = root
	end

	ring("Outer", 12, "Accent", "Outer")
	ring("Inner", 4, if kind == "Fight" then "PanelRaised" else "Primary", "Center")
	return root
end

local function toRgb(color: Color3): { number }
	return { color.R * 255, color.G * 255, color.B * 255 }
end

-- The WCAG contrast between two colours (ThemeConfig.contrast), for a component that picks what to draw on.
function Theme.contrast(a: Color3, b: Color3): number
	return ThemeConfig.contrast(toRgb(a), toRgb(b))
end

-- The ink that reads on `background` (see ThemeConfig.inkOn): a sigil on an Orpiment chip is charcoal,
-- on an Indigo chip vellum.
function Theme.inkOn(background: Color3): Color3
	return fromRgb(ThemeConfig.inkOn(toRgb(background)))
end

-- Slightly darker/lighter variants for hover/pressed states.
function Theme.shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

return Theme
