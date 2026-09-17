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

-- Reference resolution used to compute UIScale. Phones typically land around 0.7-0.85.
Theme.ReferenceHeight = 1080
Theme.MinScale = 0.62
Theme.MaxScale = 1.15

function Theme.scaleFor(viewportSize: Vector2): number
	local scale = viewportSize.Y / Theme.ReferenceHeight
	-- Wide/short viewports (phones in landscape) get a boost so touch targets stay large.
	if viewportSize.Y < 500 then
		scale = math.max(scale, 0.68)
	end
	return math.clamp(scale, Theme.MinScale, Theme.MaxScale)
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
