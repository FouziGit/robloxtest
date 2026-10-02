--!strict
-- ChapterBand: the band across the top of a screen's card (D-147), in the colour of the screen's chapter.
-- Flat and flush, from one side of the card's ink to the other (D-178: the card's outline is its outline),
-- it holds, left to right: the way back to the screen this one was opened from, the illuminated drop cap and
-- the rest of the title, a slot for the screen (a Folios pill, a tier seal) and the cross. An ink band has the
-- five-pigment stripe right under it, edge to edge.
--
-- The drop cap and the rest of its word share a row of their own, the cap flush with the word as an
-- illuminated initial sits in a manuscript: at the band's gap between its parts, "Menu" read "M enu". They
-- stand on one baseline, and the row tilts as one, so the cap leans with its word (D-177).
--
-- At an entrance it drops into place just after the card starts to arrive, and its drop cap stamps in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")

local Button = require(script.Parent.Button)
local DropCap = require(script.Parent.DropCap)
local Motion = require(script.Parent.Parent.Motion)
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local Theme = require(script.Parent.Parent.Theme)
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))
local Trove = require(Packages.Trove)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	Title: string,
	-- A ThemeConfig.Chapters key.
	Chapter: string,
	-- Where the band rests; it drops into this place at an entrance.
	Position: UDim2,
	Closable: boolean?,
	OnClose: (() -> ())?,
	-- The way back, worded `nav.back` through `Localize`; both are needed for it to be drawn.
	OnBack: (() -> ())?,
	Localize: Localizer?,
	Parent: Instance?,
}

export type ChapterBand = {
	-- What drops in: the band and the stripe under it. The card sizes it, the band ChapterBand.height() tall
	-- and the stripe StripeHeight() under it.
	Instance: Frame,
	Right: Frame,
	CloseButton: TextButton?,
	-- How tall the stripe under the band is: 0 on a band that carries none.
	StripeHeight: (self: ChapterBand) -> number,
	SetTitle: (self: ChapterBand, title: string) -> (),
	SetChapter: (self: ChapterBand, chapter: string) -> (),
	-- The band's part of an entrance; the way back shows only when `showBack`.
	PlayEnter: (self: ChapterBand, showBack: boolean) -> (),
	Destroy: (self: ChapterBand) -> (),
}

local ChapterBand = {}

-- Never shorter than this, and a touch row plus a margin on a phone, since it holds the cross.
local HEIGHT = 72
local TOUCH_MARGIN = 16
-- It drops into place from this far up, just after the card has started to arrive.
local DROP = 24
local DROP_DELAY = 0.06
local TITLE_TILT = -2
-- Between the drop cap and the rest of its word: next to nothing, set by eye in Studio so that "Menu" reads
-- as one word.
local CAP_GAP = 2
-- The title's line, as tall as the drop cap's, both set to its foot. The roman descends 0.273 of its size and
-- the poster face 0.236 (their fonts' own metrics): on one foot the cap's baseline would stand higher than the
-- title's, so the cap's box reaches lower by the difference.
local ROMAN_LINE = 1.257
local ROMAN_DESCENT = 0.273
local POSTER_DESCENT = 0.236
local HEADING_HEIGHT = math.ceil(DropCap.Size * ROMAN_LINE)
local CAP_DROP = math.round(DropCap.Size * ROMAN_DESCENT - Theme.Sizes.TextTitle * POSTER_DESCENT)
-- Its top corners follow the card's own, inside its ink.
local CORNER = Theme.Sizes.CornerPanel - Theme.Sizes.Stroke
-- The cross: a flat disc of the sheet (the board's `.m-close`), a shade darker when it is hovered or selected
-- and another when it is pressed.
local CLOSE_SIZE = 44
local CLOSE_HOVER_SHADE = -0.06
local CLOSE_PRESSED_SHADE = -0.12
local CROSS_LENGTH = 20
local CROSS_WIDTH = 3
-- The five pigments in a row under an ink band: the brand's palette motif (the board's `.m-stripe`).
local STRIPE_HEIGHT = 8

-- The band's height, in design units, for the current scale.
function ChapterBand.height(): number
	return math.max(HEIGHT, Theme.touchTargetHeight(Theme.Sizes.RowHeight) + TOUCH_MARGIN)
end

-- The cross: a flat sheet disc in its ink, two ink bars. Hovered or selected it darkens a shade, pressed two --
-- never red: closing a screen is not a danger.
local function makeCloseButton(trove: typeof(Trove.new()), onClose: (() -> ())?): TextButton
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE)
	close.BackgroundTransparency = 1
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.Text = ""
	close.Selectable = true
	close.LayoutOrder = 5
	close.SelectionImageObject = trove:Add(Theme.focusRing(nil, Theme.Pill))
	-- On touch this cross is the only way out of an open screen, so it never renders below the minimum.
	Theme.minPixelSize(close, Theme.MinTouchTarget)

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = Theme.Colors.PanelRaised
	disc.Size = UDim2.fromScale(1, 1)
	Theme.corner(disc, Theme.Pill)
	Theme.stroke(disc, "Accent", Theme.Sizes.Stroke)
	disc.Parent = close
	for _, rotation in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Theme.Colors.Accent
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(CROSS_WIDTH, CROSS_LENGTH)
		bar.Rotation = rotation
		Theme.corner(bar, Theme.Pill)
		bar.Parent = disc
	end

	local hovered, selected, pressed = false, false, false
	local function render()
		local shade = if pressed then CLOSE_PRESSED_SHADE elseif hovered or selected then CLOSE_HOVER_SHADE else 0
		disc.BackgroundColor3 = Theme.shade(Theme.Colors.PanelRaised, shade)
	end

	trove:Connect(close.MouseEnter, function()
		hovered = true
		render()
	end)
	trove:Connect(close.MouseLeave, function()
		hovered, pressed = false, false
		render()
	end)
	trove:Connect(close.MouseButton1Down, function()
		pressed = true
		render()
	end)
	trove:Connect(close.MouseButton1Up, function()
		pressed = false
		render()
	end)
	trove:Connect(close.SelectionGained, function()
		selected = true
		render()
	end)
	trove:Connect(close.SelectionLost, function()
		selected, pressed = false, false
		render()
	end)
	trove:Connect(close.Activated, function()
		if onClose ~= nil then
			onClose()
		end
	end)

	return close
end

-- The five-pigment stripe right under an ink band, from one side of the card's ink to the other.
local function makeStripe(parent: Instance): Frame
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.BackgroundTransparency = 1
	stripe.BorderSizePixel = 0
	stripe.AnchorPoint = Vector2.new(0, 1)
	stripe.Position = UDim2.fromScale(0, 1)
	stripe.Size = UDim2.new(1, 0, 0, STRIPE_HEIGHT)
	stripe.ZIndex = 2
	local count = #PigmentConfig.Order
	for index, pigment in ipairs(PigmentConfig.Order) do
		local segment = Instance.new("Frame")
		segment.Name = pigment
		segment.BorderSizePixel = 0
		segment.BackgroundColor3 = Theme.pigmentColor(pigment)
		segment.Position = UDim2.fromScale((index - 1) / count, 0)
		segment.Size = UDim2.fromScale(1 / count, 1)
		segment.ZIndex = 2
		segment.Parent = stripe
	end
	stripe.Parent = parent
	return stripe
end

local function rowLayout(parent: Instance, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
	return layout
end

-- What fills whatever of its row the other parts leave.
local function fill(object: GuiObject)
	local item = Instance.new("UIFlexItem")
	item.FlexMode = Enum.UIFlexMode.Fill
	item.Parent = object
end

function ChapterBand.new(props: Props): ChapterBand
	local trove = Trove.new()
	local chapter = props.Chapter
	local look = Theme.chapter(chapter)
	local rest = props.Position

	-- The band, and the stripe under it: they drop in together.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.BorderSizePixel = 0
	top.Position = rest
	trove:Add(top)
	trove:Add(function()
		Motion.cancel(top)
	end)

	-- Flat, its top corners the card's inner ones; a frame clips to its rectangle and not to its corner, so a
	-- square of its colour over its lower half keeps its foot straight along the card's content.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BorderSizePixel = 0
	band.Size = UDim2.fromScale(1, 1)
	band.ZIndex = 2
	Theme.corner(band, CORNER)
	band.Parent = top
	local square = Instance.new("Frame")
	square.Name = "Square"
	square.BorderSizePixel = 0
	square.Position = UDim2.fromScale(0, 0.5)
	square.Size = UDim2.fromScale(1, 0.5)
	square.ZIndex = 2
	square.Parent = band

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = 3
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingSmall)
	padding.Parent = row
	rowLayout(row, Theme.Sizes.Gap)
	row.Parent = band

	local backButton: Button.Button? = nil
	local onBack = props.OnBack
	local localize = props.Localize
	if onBack ~= nil and localize ~= nil then
		local back = Button.new({
			Text = localize.t("nav.back"),
			Variant = "Secondary",
			Icon = "Back",
			OnClick = onBack,
			LayoutOrder = 1,
			Name = "Back",
			Parent = row,
		})
		-- Hidden until an entrance says whether there is somewhere to go back to.
		back.Instance.Visible = false
		trove:Add(function()
			back:Destroy()
		end)
		backButton = back
	end

	-- The drop cap and the rest of the title, in a row of their own that takes what the band's other parts
	-- leave; the rest of the title takes what the cap leaves, and truncates there.
	local heading = Instance.new("Frame")
	heading.Name = "Heading"
	heading.BackgroundTransparency = 1
	heading.Size = UDim2.fromOffset(0, HEADING_HEIGHT)
	heading.LayoutOrder = 2
	heading.Rotation = TITLE_TILT
	fill(heading)
	-- Both hang from the row's top: the title's box is the row, the cap's reaches CAP_DROP below it.
	rowLayout(heading, CAP_GAP).VerticalAlignment = Enum.VerticalAlignment.Top
	heading.Parent = row

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0, 1)
	title.LayoutOrder = 2
	title.FontFace = Theme.Fonts.Title
	title.TextSize = Theme.Sizes.TextTitle
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.TextTruncate = Enum.TextTruncate.AtEnd
	fill(title)
	title.Parent = heading

	-- The screen's own slot, before the cross.
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.AutomaticSize = Enum.AutomaticSize.X
	right.Size = UDim2.fromScale(0, 1)
	right.LayoutOrder = 4
	rowLayout(right, Theme.Sizes.Gap)
	right.Parent = row

	local closeButton: TextButton? = nil
	if props.Closable == true then
		local close = makeCloseButton(trove, props.OnClose)
		close.Parent = row
		closeButton = close
	end

	local titleText = props.Title
	local cap: DropCap.DropCap? = nil
	local stripe: Frame? = nil

	-- The drop cap takes the title's first letter (ThemeConfig.dropCap); a title that opens on anything
	-- else stays whole.
	local function drawTitle()
		local old = cap
		cap = nil
		if old ~= nil then
			old:Destroy()
		end
		local letter, remainder = ThemeConfig.dropCap(titleText)
		if letter ~= nil then
			local created = DropCap.new(letter, chapter)
			created.Instance.LayoutOrder = 1
			created.Instance.Size = UDim2.new(0, 0, 1, CAP_DROP)
			created.Instance.Parent = heading
			cap = created
		end
		title.Text = remainder
	end
	trove:Add(function()
		local current = cap
		if current ~= nil then
			current:Destroy()
		end
	end)

	local function stripeHeight(): number
		return if look.Stripe then STRIPE_HEIGHT else 0
	end

	local function paint()
		band.BackgroundColor3 = look.Band
		square.BackgroundColor3 = look.Band
		title.TextColor3 = look.Title
		local current = stripe
		if look.Stripe then
			if current == nil then
				stripe = makeStripe(top)
			end
		elseif current ~= nil then
			stripe = nil
			current:Destroy()
		end
		band.Size = UDim2.new(1, 0, 1, -stripeHeight())
		drawTitle()
	end
	paint()

	local alive = true
	-- Bumped by every entrance, so a delayed drop never lands on a band that has entered again since.
	local enterToken = 0
	trove:Add(function()
		alive = false
	end)

	top.Parent = props.Parent

	local function setTitle(_self: ChapterBand, text: string)
		titleText = text
		drawTitle()
	end

	local function setChapter(_self: ChapterBand, next: string)
		chapter = next
		look = Theme.chapter(next)
		paint()
	end

	local function playEnter(_self: ChapterBand, showBack: boolean)
		local back = backButton
		if back ~= nil then
			back.Instance.Visible = showBack
		end
		enterToken += 1
		local token = enterToken
		Motion.set(top, { Position = rest - UDim2.fromOffset(0, DROP) })
		task.delay(DROP_DELAY, function()
			if alive and enterToken == token then
				Motion.to(top, { Position = rest }, "UiSnappy")
			end
		end)
		local current = cap
		if current ~= nil then
			current:Stamp()
		end
	end

	local function getStripeHeight(_self: ChapterBand): number
		return stripeHeight()
	end

	local function destroy(_self: ChapterBand)
		trove:Destroy()
	end

	local object: ChapterBand = {
		Instance = top,
		Right = right,
		CloseButton = closeButton,
		StripeHeight = getStripeHeight,
		SetTitle = setTitle,
		SetChapter = setChapter,
		PlayEnter = playEnter,
		Destroy = destroy,
	}
	return object
end

return ChapterBand
