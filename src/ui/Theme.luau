--!strict
-- Central UI theme: colors, fonts, sizes, spacing. Every component reads from here.

local ElementConfig = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ElementConfig")
)

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(24, 24, 30),
	Panel = Color3.fromRGB(32, 32, 40),
	PanelRaised = Color3.fromRGB(42, 42, 52),
	Border = Color3.fromRGB(60, 60, 74),
	Text = Color3.fromRGB(240, 240, 245),
	TextMuted = Color3.fromRGB(170, 170, 185),
	TextInverse = Color3.fromRGB(20, 20, 24),
	Accent = Color3.fromRGB(230, 180, 60),
	AccentSoft = Color3.fromRGB(120, 90, 40),
	Success = Color3.fromRGB(90, 190, 110),
	Danger = Color3.fromRGB(225, 90, 80),
	Info = Color3.fromRGB(90, 160, 240),
	Chakra = Color3.fromRGB(80, 170, 255),
	Health = Color3.fromRGB(90, 200, 110),
	Overlay = Color3.fromRGB(0, 0, 0),
	Premium = Color3.fromRGB(200, 140, 255),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBold,
	Body = Enum.Font.Gotham,
	Bold = Enum.Font.GothamBold,
	Mono = Enum.Font.RobotoMono,
}

-- Base sizes at UIScale 1 (1080p). Screens apply Theme.scaleFor(viewport).
Theme.Sizes = {
	TextSmall = 13,
	TextBody = 15,
	TextLarge = 18,
	TextTitle = 22,
	TextHero = 30,
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

Theme.Animation = {
	Fast = 0.12,
	Normal = 0.2,
	Slow = 0.35,
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

function Theme.elementColor(elementId: string): Color3
	local rgb = ElementConfig.Colors[elementId :: any]
	if rgb == nil then
		return Theme.Colors.Accent
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Slightly darker/lighter variants for hover/pressed states.
function Theme.shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

return Theme
