--!strict
-- The interface's palette and typography, as pure data, so that a test can hold them to
-- docs/ART_BIBLE.md and to a contrast ratio without an engine.
--
-- ENCRE VIVE (D-147): the world is still a page, and the vellum is still the paper every screen is drawn on;
-- what changed is what is laid on it. Each menu screen owns one chapter colour, and every button, card,
-- tile and toast is a sticker -- a flat vivid face, a three-unit ink outline, and a hard lip (what you
-- press) or a hard ink shadow (what you read). In a fight the colour keeps its meaning (rule 11): ink
-- plates, cyan for us, red only for what is about to hit you, the school colours for glyphs, and none
-- of the value colours -- the primary yellow, the Tyrian purple, the rarities -- ever enter a fight.
--
-- Colours are {r, g, b} in 0..255. A font is an Enum.Font name, an Enum.FontWeight name and, when it is
-- not upright, an Enum.FontStyle name; src/ui/Theme.luau turns all of them into engine values and is the
-- only place that does.

local ThemeConfig = {}

export type Rgb = { number }
export type FontDef = { Font: string, Weight: string, Style: string? }
-- A colour stop of a gradient: a role of Colors, or "Base", the colour the caller passes in, moved by
-- Shade (Theme.shade) when one is given.
export type ColorStop = { Time: number, Role: string, Shade: number? }
-- {time, transparency}
export type Keypoint = { number }
export type GradientDef = {
	Color: { ColorStop },
	Transparency: { Keypoint }?,
	Rotation: number,
	-- A GradientType name; Linear when absent.
	Kind: string?,
}
export type RarityDef = { Fill: string, Pips: number, Seal: boolean?, Shimmer: boolean? }
export type RankDef = { Fill: string, Rim: string?, Shimmer: boolean? }

-- docs/ART_BIBLE.md: Vélin #E8E0CE, Charbon #17150F. Every hex of the interface is written ONCE, here,
-- and the roles below point at these locals: a role that repeated a literal could drift from the bible
-- (or from the pigment it is the exact copy of) while the test that holds the source still passed.
local VELLUM: Rgb = { 232, 224, 206 }
local CHARCOAL: Rgb = { 23, 21, 15 }
-- The sheet laid on the page: cards, rows, the face of a Secondary button, a toast.
local SHEET: Rgb = { 247, 242, 230 }
local CHALK: Rgb = { 201, 194, 177 }
local BORDER: Rgb = { 168, 156, 132 }
local INK_SOFT: Rgb = { 74, 69, 56 }
-- The bottom of an inkwell: bar tracks, slot wells, sockets.
local WELL: Rgb = { 43, 39, 30 }
-- Poster Orpiment. At least 100 (redmean) away from the default gold the bible bans (108), which the
-- exact Orpiment is not (45): that one is a school, this one is a button.
local PRIMARY: Rgb = { 255, 214, 10 }
local VERDIGRIS_VIF: Rgb = { 55, 184, 141 }
local INDIGO_VIF: Rgb = { 76, 125, 255 }
local CINNABAR_VIF: Rgb = { 242, 74, 43 }
-- Rule 7's cyan: us.
local ALLY: Rgb = { 115, 227, 255 }
-- Pourpre de Tyr, a historical pigment the interface borrows and no glyph ever wears.
local TYRIAN: Rgb = { 126, 58, 200 }
-- Verdigris and Orpiment soaked into the page: dark enough to be read as text on it.
local SUCCESS_INK: Rgb = { 26, 88, 70 }
local PREMIUM_INK: Rgb = { 104, 82, 8 }
-- The exact pigments the interface draws with. ThemeConfig requires nothing (Lune loads it by path), so
-- they are literals here; tests/UiColor.spec.luau ties each one to PigmentConfig.Colors.
local CINNABAR: Rgb = { 217, 58, 34 }
local INDIGO: Rgb = { 46, 74, 140 }
local UMBER: Rgb = { 107, 74, 47 }
local VERDIGRIS: Rgb = { 79, 168, 140 }
local ORPIMENT: Rgb = { 232, 192, 34 }

ThemeConfig.Vellum = VELLUM
ThemeConfig.Charcoal = CHARCOAL

ThemeConfig.Colors = {
	-- The page: the body of every screen card.
	Panel = VELLUM,
	-- The sheet: cards, rows, Secondary faces, toasts, keycaps, knobs, and hero text over any fill.
	PanelRaised = SHEET,
	-- Disabled, Common, the silver medal, the Blank rank. Never alone on the page without its outline.
	Chalk = CHALK,
	-- A decorative hairline, never the only edge of a control.
	Border = BORDER,
	-- Ink: all text on paper and on the light fills.
	Text = CHARCOAL,
	TextMuted = INK_SOFT,
	-- Vellum on ink: text on a plate, on Indigo, Umber and Tyrian.
	TextInverse = VELLUM,
	-- The ink outline every sticker wears, the outer ring of the focus, the scrollbars. Not a fill for a
	-- primary action: that is Primary.
	Accent = CHARCOAL,
	-- The stroke around a floating number, so it reads over any floor.
	Outline = CHARCOAL,
	-- HUD plates, ink chapter bands, ink tiles, hard shadows.
	Plate = CHARCOAL,
	Well = WELL,
	-- The dim behind an open screen.
	Overlay = CHARCOAL,
	-- Go, claim, value: the Primary face, the Play and Daily chapters, the Folio coin, the XP fill,
	-- Legendary, Codex. Never in a fight.
	Primary = PRIMARY,
	-- The Shop chapter, the claimed stamp, a toggle that is on. Never in a fight.
	SuccessFill = VERDIGRIS_VIF,
	-- Success as text on paper.
	Success = SUCCESS_INK,
	-- The Quests chapter, Rare, the Script rank, the info toast.
	InfoFill = INDIGO_VIF,
	-- The inkwell: the ink bar's fill.
	Ink = INDIGO_VIF,
	-- Indigo, exact: information as text on paper, and the Defeat outcome.
	Info = INDIGO,
	-- Imminent danger drawn as a fill: damage taken, low health, the boss. Never a chapter, never the
	-- enemy side.
	DangerFill = CINNABAR_VIF,
	-- Cinnabar, exact: the health ghost, the low-health edge, a large "rating fell".
	Danger = CINNABAR,
	-- Rule 7: cyan is ours -- your own health included.
	Ally = ALLY,
	Health = ALLY,
	-- Tyrian: the Battle Pass chapter, Epic, the Illumination rank. Never in a fight.
	Epic = TYRIAN,
	-- Orpiment as ink: premium and Robux as text on paper.
	Premium = PREMIUM_INK,
	-- Umber, exact: third place, the Sketch rank.
	Bronze = UMBER,
} :: { [string]: Rgb }

-- The colour a pigment takes as text or a number over ink (a plate, an ink stroke). Umber has none: on ink
-- it is 2.30, so it is drawn as sheet text in an Umber stroke (Theme.pigmentOnInk). Exact Indigo is 2.15
-- on ink, so its number is the vivid Indigo. Orpiment is the exact pigment and never Primary, which may
-- not enter a fight.
ThemeConfig.PigmentOnInk = {
	Cinnabar = CINNABAR,
	Indigo = INDIGO_VIF,
	Verdigris = VERDIGRIS,
	Orpiment = ORPIMENT,
} :: { [string]: Rgb }

-- The lip under a pressable face: the face's pigment shaded a quarter toward the ink
-- (PigmentConfig.shade(rgb, -0.25, Charcoal, Vellum)), which tests/UiColor.spec.luau recomputes. Epic is
-- Tyrian under the same formula; Secondary and Plate sit on a paper edge.
ThemeConfig.Lips = {
	Primary = { 180, 149, 29 },
	Success = { 65, 131, 109 },
	Info = { 40, 61, 109 },
	Danger = { 169, 49, 29 },
	Epic = { 100, 49, 154 },
	Secondary = CHALK,
	Plate = CHALK,
} :: { [string]: Rgb }

-- The lip each face role sits on, by Lips key.
ThemeConfig.LipFor = {
	Primary = "Primary",
	SuccessFill = "Success",
	InfoFill = "Info",
	DangerFill = "Danger",
	Epic = "Epic",
	PanelRaised = "Secondary",
	Plate = "Plate",
} :: { [string]: string }

-- Each menu screen owns one chapter colour: its header band, its selected tab, its backdrop wash, its
-- Owner buttons. Red is never a chapter and neither is the ally cyan. The Result screen takes the colour
-- of its outcome.
ThemeConfig.Chapters = {
	Menu = "Plate",
	Play = "Primary",
	Daily = "Primary",
	Shop = "SuccessFill",
	Quests = "InfoFill",
	Battlepass = "Epic",
	Loadout = "Plate",
	Leaderboard = "Plate",
	Settings = "Plate",
	Victory = "Primary",
	Defeat = "Info",
	Draw = "Chalk",
} :: { [string]: string }

-- Chapters whose ink band carries the five-pigment stripe, the brand's palette motif.
ThemeConfig.ChapterStripe = { Menu = true, Loadout = true } :: { [string]: boolean }

-- Colour is never the only cue: every rarity surface also shows its pips and its word.
ThemeConfig.Rarity = {
	Common = { Fill = "Chalk", Pips = 1 },
	Rare = { Fill = "InfoFill", Pips = 2 },
	Epic = { Fill = "Epic", Pips = 3 },
	Legendary = { Fill = "Primary", Pips = 4, Seal = true, Shimmer = true },
} :: { [string]: RarityDef }

-- The rank ladder, illuminated as it climbs: blank, then earth, then ink, then purple with a gold rim,
-- then full gold leaf, rimmed in gold and shimmering. One entry per RankingConfig.Tiers id.
ThemeConfig.Ranks = {
	Blank = { Fill = "Chalk" },
	Sketch = { Fill = "Bronze" },
	Script = { Fill = "InfoFill" },
	Illumination = { Fill = "Epic", Rim = "Primary" },
	Codex = { Fill = "Primary", Rim = "Primary", Shimmer = true },
} :: { [string]: RankDef }

-- The transparency of the part of the Result's auto-close ring already spent.
local RING_SPENT = 0.85
-- Below this fraction of the ring, the edge between what is left and what is spent is one keypoint away
-- from an end of the sequence, and a sequence may not repeat a time.
local RING_EDGE = 0.001

-- The Result's auto-close ring: opaque for the `fraction` of the turn still left, faint for the rest.
function ThemeConfig.ringTransparency(fraction: number): { Keypoint }
	local f = math.clamp(fraction, 0, 1)
	if f >= 1 - RING_EDGE then
		return { { 0, 0 }, { 1, 0 } }
	elseif f <= RING_EDGE then
		return { { 0, RING_SPENT }, { 1, RING_SPENT } }
	end
	return { { 0, 0 }, { f, 0 }, { f + RING_EDGE, RING_SPENT }, { 1, RING_SPENT } }
end

-- Every gradient of the interface (Theme.gradient). Rotation 90 puts keypoint 0 at the top.
ThemeConfig.Gradients = {
	-- The light caught by the top of a vivid face: the sheet at half strength, fading out (the board's
	-- `linear-gradient(sheet, transparent)` at an opacity of .5).
	Gloss = {
		Color = { { Time = 0, Role = "PanelRaised" }, { Time = 1, Role = "PanelRaised" } },
		Transparency = { { 0, 0.5 }, { 1, 1 } },
		Rotation = 90,
	},
	-- The fade at the bottom of a list that says there is more below.
	MoreBelow = {
		Color = { { Time = 0, Role = "Base" }, { Time = 1, Role = "Base" } },
		Transparency = { { 0, 1 }, { 1, 0 } },
		Rotation = 90,
	},
	-- The sweep of light across gold leaf: a Legendary ribbon and card, the Codex seal, the seventh day. The
	-- Shimmer component sweeps it, and holds a screen to Budget.MaxAnimatedGradients of them.
	Shimmer = {
		Color = { { Time = 0, Role = "PanelRaised" }, { Time = 1, Role = "PanelRaised" } },
		Transparency = { { 0, 1 }, { 0.42, 1 }, { 0.5, 0.3 }, { 0.58, 1 }, { 1, 1 } },
		Rotation = 20,
	},
	-- The Result's auto-close ring, drawn full; the screen rewrites its transparency once a second.
	ResultRing = {
		Color = { { Time = 0, Role = "PanelRaised" }, { Time = 1, Role = "PanelRaised" } },
		Transparency = ThemeConfig.ringTransparency(1),
		Rotation = -90,
		Kind = "Conical",
	},
} :: { [string]: GradientDef }

-- Interface timings. Nothing here is a gameplay number: the server decides, the interface follows.
ThemeConfig.Timing = {
	-- A pending button gives up after this and tells the player the server did not answer.
	PendingTimeoutSeconds = 5,
	SuccessFlashSeconds = 0.4,
	-- A toast stays BaseSeconds, plus PerCharSeconds for every character past FreeChars, up to MaxSeconds.
	Toast = {
		BaseSeconds = 2.5,
		PerCharSeconds = 0.06,
		FreeChars = 30,
		MaxSeconds = 5,
		CelebrateSeconds = 3.5,
		MaxVisibleHub = 3,
		MaxVisibleMatch = 2,
	},
	-- List entrances: one child every StaggerSeconds, the first StaggerMax of them, the rest at once.
	StaggerSeconds = 0.035,
	StaggerMax = 8,
	-- A centre banner's whole life: in, hold and out.
	SplashSeconds = 1.2,
	KillPopSeconds = 0.9,
	-- One leg of a badge's breath.
	IdleBreathSeconds = 1.2,
	WiggleEverySeconds = 2.5,
	DailyAutoOpenDelaySeconds = 3,
	UndoSeconds = 3,
	ShimmerPauseSeconds = 3,
}

-- Roblox's own text size setting (GuiService.PreferredTextSize), as a multiplier of the menus and toasts.
-- Never the HUD, whose geometry is measured.
ThemeConfig.TextScale = { Medium = 1, Large = 1.15, Larger = 1.3, Largest = 1.3 } :: { [string]: number }

-- What one open screen may cost: splats (Splat), animated gradients (the Shimmer on gold leaf), idle loops
-- (Motion.loop) and staggered entrances (Motion.stagger), each held where it is spent. And what the HUD
-- draws in a fight, in GuiObjects shown, with every slot a pass opens and a full 3v3 in the band: on a phone
-- with its touch discs, the budget the colour pass set; with a pointer, whose hotbar spells each glyph's
-- keys and whose Menu names its own, the ceiling it is built to (tests/HudBudget.spec.luau, D-168).
ThemeConfig.Budget = {
	MaxSplats = 12,
	MaxAnimatedGradients = 3,
	MaxIdleLoops = 3,
	MaxStaggered = 8,
	MaxHudObjects = 180,
	MaxHudObjectsPointer = 340,
}

-- The HUD's geometry, in design units (D-147): never scaled by the player's text size, and laid out to fit a
-- landscape phone's height at the touch floor.
ThemeConfig.Hud = {
	-- The top-centre column's ceiling (HudController's topStack): what a 375-point phone leaves above the
	-- bottom stack at the touch floor, with a gap to spare.
	TopStackMaxHeight = 240,
	-- And how far under the safe area's top edge the column starts.
	TopPad = 12,
	-- The combat dock: centred at the bottom, off the bottom edge by this much with a pointer and on touch.
	DockBottomPad = 16,
	DockBottomPadTouch = 12,
	DockWidthPointer = 460,
	-- On touch it is also never wider than the gap between the thumbs (InputController.touchRects).
	DockWidthTouchMax = 300,
	-- Nor narrower than this, which holds six pips: where the discs reach the middle of a small phone, the dock
	-- keeps this width and slides left of them instead (TouchCluster.dockSpan).
	DockWidthTouchMin = 200,
	-- Health 26 + ink 14 + padding 10 * 2 + gap 10.
	DockHeight = 70,
	-- The hotbar: with a pointer, a slot per equipped glyph over the key strip that casts it, this far apart;
	-- on touch, a row of pips across the top of the dock, this tall.
	HotbarSlot = 56,
	-- A cap of 19 on its 3-unit lip: its pigment strip leaves the letter 13 (D-172). At 18 a cap of 15 left
	-- it 9, and the letter stood on the strip.
	HotbarKeyStrip = 22,
	HotbarGap = 8,
	HotbarPipsHeight = 26,
	-- The combo row: its chips, the gap between it and what is under it, and the preview pill in it (the board's
	-- pill, about 41 against its chips' 44). With a pointer the row stands this much further off the hotbar, whose
	-- keys it would otherwise crowd.
	ChipSize = 44,
	ChipRowGap = 8,
	PreviewHeight = 40,
	ComboLift = 20,
	-- Health at or under this share of the maximum is danger: red, hatched, pulsing, and the edges burn.
	LowHealthFraction = 0.3,
	-- The lock's mark warns this many studs before the distance a lock breaks at (LockOnConfig.BreakStuds).
	LockWarnStuds = 20,
	-- The hub's meta cluster: level, Folios, claims and the queue, in a column this wide.
	MetaWidth = 300,
}

-- docs/ART_BIBLE.md (D-147): a rounded poster face for titles (Fredoka One), a rounded grotesque for words
-- (Nunito), a condensed grotesque for numbers (Oswald); the roman (Merriweather) keeps the lore, in
-- italic, and the drop caps. Merriweather is also the only one of the four with the arrows.
ThemeConfig.Fonts = {
	Title = { Font = "FredokaOne", Weight = "Regular" },
	Display = { Font = "FredokaOne", Weight = "Regular" },
	Body = { Font = "Nunito", Weight = "SemiBold" },
	Bold = { Font = "Nunito", Weight = "ExtraBold" },
	Label = { Font = "Nunito", Weight = "Heavy" },
	Numeric = { Font = "Oswald", Weight = "Bold" },
	-- A count read at rest beside its bar, lighter than a number that flies past: the Menu's XP.
	NumericMedium = { Font = "Oswald", Weight = "Medium" },
	Lore = { Font = "Merriweather", Weight = "Regular", Style = "Italic" },
	Initial = { Font = "Merriweather", Weight = "Heavy" },
	Symbol = { Font = "Merriweather", Weight = "Bold" },
} :: { [string]: FontDef }

-- WCAG relative luminance of an sRGB colour, the number a contrast ratio is made of.
local function channel(value: number): number
	local c = value / 255
	if c <= 0.03928 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

function ThemeConfig.luminance(rgb: Rgb): number
	return 0.2126 * channel(rgb[1]) + 0.7152 * channel(rgb[2]) + 0.0722 * channel(rgb[3])
end

-- Contrast ratio between two colours, 1 to 21. Body text wants 4.5, large text and accents 3.
function ThemeConfig.contrast(a: Rgb, b: Rgb): number
	local la = ThemeConfig.luminance(a)
	local lb = ThemeConfig.luminance(b)
	local high = math.max(la, lb)
	local low = math.min(la, lb)
	return (high + 0.05) / (low + 0.05)
end

-- The interface's scale (D-128). Every size in src/ui/Theme.luau is designed at ReferenceHeight; a taller
-- viewport grows the whole interface with it, a shorter one never shrinks it under the floor of its
-- input. Found in Studio: a window 700 points tall scaled everything to 0.62, body text to nine points,
-- and the developer could not read a menu or find a screen. Viewport sizes are in points, as the engine
-- reports them.
--   PointerFloor  mouse and gamepad: never smaller than designed
--   TouchFloor    a touch-only device: a phone is small in points but held close, and the HUD and the
--                 panels are laid out to fit a landscape phone at this scale (ThemeConfig.Hud is
--                 measured at it)
--   Max           a 4K monitor's 2160 points doubles the interface; beyond that it stops growing
ThemeConfig.Scale = {
	ReferenceHeight = 1080,
	PointerFloor = 1,
	TouchFloor = 0.68,
	Max = 2,
}

-- The UIScale every ScreenRoot applies, for a viewport `height` points tall. Never shrinks as the
-- viewport grows (tests/Typography.spec.luau).
function ThemeConfig.scaleFor(height: number, touchOnly: boolean): number
	local scale = ThemeConfig.Scale
	local floor = if touchOnly then scale.TouchFloor else scale.PointerFloor
	return math.clamp(height / scale.ReferenceHeight, floor, scale.Max)
end

-- The ink that reads on `background`: charcoal on a light fill (Primary, the cyan, Orpiment, Verdigris,
-- the vivid Indigo), vellum on a dark one (Tyrian, the plate, exact Indigo, Umber). Decided by contrast,
-- not by a luminance threshold someone guessed.
function ThemeConfig.inkOn(background: Rgb): Rgb
	local text = ThemeConfig.Colors.Text
	local inverse = ThemeConfig.Colors.TextInverse
	if ThemeConfig.contrast(background, text) >= ThemeConfig.contrast(background, inverse) then
		return text
	end
	return inverse
end

-- The role a word is set in on the fill role `fill`: charcoal where charcoal reads (inkOn); on the ink
-- plate, the vellum that is the page's own inverse; on any other dark fill, the sheet, which clears 4.5 on
-- Tyrian where vellum only just does (5.65 against 4.81).
function ThemeConfig.labelRole(fill: string): string
	local rgb = ThemeConfig.Colors[fill]
	if rgb == nil then
		error(("no colour role %s to set a word on"):format(fill))
	end
	if ThemeConfig.inkOn(rgb) == ThemeConfig.Colors.Text then
		return "Text"
	elseif fill == "Plate" then
		return "TextInverse"
	end
	return "PanelRaised"
end

-- The letters a drop cap can hold, by code point: ASCII's, and Latin-1's, which carry French's accented
-- capitals (É, À, Ç). Latin-1 files two signs among its letters, and they are not letters.
local LETTER_RANGES = { { 65, 90 }, { 97, 122 }, { 192, 255 } }
local LATIN1_SIGNS = { [215] = true, [247] = true } -- × and ÷

-- A screen title split for its drop cap (D-147): the first character, when it is a letter, and the rest --
-- "Quêtes" is "Q" then "uêtes", as a manuscript opens a chapter. A title that opens on anything else (a
-- digit, a quote, a sign) has no drop cap and stays whole.
function ThemeConfig.dropCap(title: string): (string?, string)
	if title == "" or utf8.len(title) == nil then
		return nil, title
	end
	local second = utf8.offset(title, 2) :: number
	local first = string.sub(title, 1, second - 1)
	local codepoint = utf8.codepoint(first)
	if LATIN1_SIGNS[codepoint] then
		return nil, title
	end
	for _, range in ipairs(LETTER_RANGES) do
		if codepoint >= range[1] and codepoint <= range[2] then
			return first, string.sub(title, second)
		end
	end
	return nil, title
end

return ThemeConfig
