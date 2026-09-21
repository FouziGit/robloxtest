--!strict
-- Central UI theme: colors, fonts, sizes, spacing. Every component reads from here, and this reads the
-- palette and the typography from ThemeConfig, which is pure data a test holds to docs/ART_BIBLE.md and
-- to a contrast ratio. Nothing in src/ui names a colour or a font that is not here.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))

local Theme = {}

local function fromRgb(rgb: ThemeConfig.Rgb): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

Theme.Colors = {
	Background = fromRgb(ThemeConfig.Colors.Background),
	Panel = fromRgb(ThemeConfig.Colors.Panel),
	PanelRaised = fromRgb(ThemeConfig.Colors.PanelRaised),
	Border = fromRgb(ThemeConfig.Colors.Border),
	Text = fromRgb(ThemeConfig.Colors.Text),
	TextMuted = fromRgb(ThemeConfig.Colors.TextMuted),
	TextInverse = fromRgb(ThemeConfig.Colors.TextInverse),
	Accent = fromRgb(ThemeConfig.Colors.Accent),
	AccentSoft = fromRgb(ThemeConfig.Colors.AccentSoft),
	Success = fromRgb(ThemeConfig.Colors.Success),
	Danger = fromRgb(ThemeConfig.Colors.Danger),
	Info = fromRgb(ThemeConfig.Colors.Info),
	Ink = fromRgb(ThemeConfig.Colors.Ink),
	Health = fromRgb(ThemeConfig.Colors.Health),
	Overlay = fromRgb(ThemeConfig.Colors.Overlay),
	Premium = fromRgb(ThemeConfig.Colors.Premium),
	Outline = fromRgb(ThemeConfig.Colors.Outline),
}

-- A Font (FontFace) rather than an Enum.Font: the enum has one weight per family, and the page is set
-- in one face at two weights. Components write `label.FontFace = Theme.Fonts.X`.
local function font(def: ThemeConfig.FontDef): Font
	local family = Font.fromEnum((Enum.Font :: any)[def.Font] :: Enum.Font).Family
	return Font.new(family, (Enum.FontWeight :: any)[def.Weight] :: Enum.FontWeight)
end

Theme.Fonts = {
	Title = font(ThemeConfig.Fonts.Title),
	Body = font(ThemeConfig.Fonts.Body),
	Bold = font(ThemeConfig.Fonts.Bold),
	-- Numbers that fly past the eye: a condensed grotesque, per docs/ART_BIBLE.md. Condensed because a
	-- four-digit hit has to stay one readable block at arm's length on a phone, and because it has to
	-- not be the same face as the prose, which is what makes a number read as a number.
	Numeric = font(ThemeConfig.Fonts.Numeric),
}

-- Base sizes at UIScale 1 (1080p). Screens apply Theme.scaleFor(viewport).
Theme.Sizes = {
	TextSmall = 13,
	TextBody = 15,
	TextLarge = 18,
	TextTitle = 22,
	TextHero = 30,
	-- The one number a screenshot is taken for: the score of the result card.
	TextDisplay = 48,
	ButtonHeight = 40,
	RowHeight = 44,
	CornerRadius = 10,
	CornerRadiusSmall = 6,
	Padding = 12,
	PaddingSmall = 6,
	Gap = 8,
	PanelWidth = 560,
	PanelHeight = 460,
	TouchButton = 64,
}

-- ScreenGui draw order. Roblox leaves the relative order of two ScreenGuis with the same DisplayOrder
-- undefined, and a screen's dim overlay only covers what sits below its own ScreenGui, so every layer
-- owns a distinct value. Spaced by ten so a new layer slots in without renumbering the others.
-- The World Boss band has no entry: it is a child of the HUD's own top-centre column, not a ScreenGui,
-- precisely so it cannot race the HUD for draw order.
Theme.Layers = {
	Hud = 10,
	Screen = 30,
	Result = 40, -- above the menus: the match is over, the result is the only thing left to read
	-- Notification layer. A server message explains what just happened (a refused purchase, a failed
	-- claim) and is worthless once something covers it, so nothing may be layered above this.
	Toast = 50,
}

-- Reference resolution used to compute UIScale. Phones typically land around 0.7-0.85.
Theme.ReferenceHeight = 1080
Theme.MinScale = 0.62
Theme.MaxScale = 1.15
-- Shortest side a touch target may render at, in real screen pixels (Roblox, iOS and Android all ask
-- for 44). The UIScale below 1 on a phone must never eat into it.
Theme.MinTouchTarget = 44

-- Viewport assumed before a camera exists: 16:9 at the reference height, which scales by exactly 1.
local FALLBACK_VIEWPORT = Vector2.new(Theme.ReferenceHeight * 16 / 9, Theme.ReferenceHeight)

function Theme.scaleFor(viewportSize: Vector2): number
	local scale = viewportSize.Y / Theme.ReferenceHeight
	-- Wide/short viewports (phones in landscape) get a boost so text stays legible.
	if viewportSize.Y < 500 then
		scale = math.max(scale, 0.68)
	end
	return math.clamp(scale, Theme.MinScale, Theme.MaxScale)
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

function Theme.pigmentColor(pigmentId: string): Color3
	local rgb = PigmentConfig.Colors[pigmentId :: any]
	if rgb == nil then
		return Theme.Colors.Accent
	end
	return fromRgb(rgb)
end

-- The ink that reads on `background` (see ThemeConfig.inkOn): a sigil on an Orpiment chip is charcoal,
-- on an Indigo chip vellum.
function Theme.inkOn(background: Color3): Color3
	local rgb = { background.R * 255, background.G * 255, background.B * 255 }
	return fromRgb(ThemeConfig.inkOn(rgb))
end

-- Slightly darker/lighter variants for hover/pressed states.
function Theme.shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

return Theme
