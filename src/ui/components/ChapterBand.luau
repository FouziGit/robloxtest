--!strict
-- ChapterBand: the band across the top of a screen's card (D-147), in the colour of the screen's chapter.
-- A sticker on the page, inset from the card's edge and outlined in ink (docs/ART_BIBLE.md rule 11), that
-- holds, left to right: the way back to the screen this one was opened from, the illuminated drop cap and
-- the rest of the title, a slot for the screen (a Folios pill, a tier seal) and the cross. An ink band
-- carries the five-pigment stripe along its foot, and three drips of its colour hang under it.
--
-- The drop cap and the rest of its word share a row of their own, the cap flush with the word as an
-- illuminated initial sits in a manuscript: at the band's gap between its parts, "Menu" read "M enu".
--
-- At an entrance it drops into place just after the card starts to arrive, and its drop cap stamps in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")

local Button = require(script.Parent.Button)
local DropCap = require(script.Parent.DropCap)
local Motion = require(script.Parent.Parent.Motion)
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local Splat = require(script.Parent.Splat)
local Sticker = require(script.Parent.Sticker)
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
	-- What drops in: the band and the drips behind it. The card sizes it.
	Instance: Frame,
	Right: Frame,
	CloseButton: TextButton?,
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
local CLOSE_SIZE = 44
local CLOSE_ELEVATION = 4
local CLOSE_HOVER_SHADE = -0.06
local CROSS_LENGTH = 20
local CROSS_WIDTH = 3
-- The five pigments in a row along the foot of an ink band: the brand's palette motif.
local STRIPE_HEIGHT = 6
-- Three drips of the band's colour: where along it, and how wide.
local DRIPS: { { X: number, Size: number } } = {
	{ X = 0.18, Size = 26 },
	{ X = 0.52, Size = 40 },
	{ X = 0.81, Size = 30 },
}
-- A drip is centred this far under the band's edge, so its ink hangs 10 to 18 below it.
local DRIP_DROP = 4

-- The band's height, in design units, for the current scale.
function ChapterBand.height(): number
	return math.max(HEIGHT, Theme.touchTargetHeight(Theme.Sizes.RowHeight) + TOUCH_MARGIN)
end

-- The cross: a sheet disc on its lip, two ink bars. Hovered or selected it darkens a shade -- never red:
-- closing a screen is not a danger.
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

	local sticker = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.PanelRaised,
		Lip = Theme.lip("Secondary"),
		Corner = Theme.Pill,
		Elevation = CLOSE_ELEVATION,
		Name = "Sticker",
		Parent = close,
	})
	trove:Add(function()
		sticker:Destroy()
	end)
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
		bar.Parent = sticker.Face
	end

	local hovered, selected, pressed = false, false, false
	local fill = Theme.Colors.PanelRaised
	local function render()
		-- A new fill is written at once and would cut the face's spring short: only when it changes.
		local next = if hovered or selected
			then Theme.shade(Theme.Colors.PanelRaised, CLOSE_HOVER_SHADE)
			else Theme.Colors.PanelRaised
		if next ~= fill then
			fill = next
			sticker:SetFill(next)
		end
		sticker:SetState(if pressed then "Pressed" else "Idle")
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

-- The five-pigment stripe along the foot of an ink band, inside its rounded corners and its outline.
local function makeStripe(parent: Instance): Frame
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.BackgroundTransparency = 1
	stripe.BorderSizePixel = 0
	stripe.AnchorPoint = Vector2.new(0.5, 1)
	stripe.Position = UDim2.new(0.5, 0, 1, -Theme.Sizes.Stroke)
	stripe.Size = UDim2.new(1, -Theme.Sizes.CornerCard * 2, 0, STRIPE_HEIGHT)
	stripe.ZIndex = 2
	local count = #PigmentConfig.Order
	for index, pigment in ipairs(PigmentConfig.Order) do
		local segment = Instance.new("Frame")
		segment.Name = pigment
		segment.BorderSizePixel = 0
		segment.BackgroundColor3 = Theme.pigmentColor(pigment)
		segment.Position = UDim2.fromScale((index - 1) / count, 0)
		segment.Size = UDim2.fromScale(1 / count, 1)
		segment.Parent = stripe
	end
	stripe.Parent = parent
	return stripe
end

local function rowLayout(parent: Instance, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
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

	-- The band, and the drips that hang behind it: they drop in together.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.BorderSizePixel = 0
	top.Position = rest
	trove:Add(top)
	trove:Add(function()
		Motion.cancel(top)
	end)

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BorderSizePixel = 0
	band.Size = UDim2.fromScale(1, 1)
	band.ZIndex = 2
	Theme.corner(band, Theme.Sizes.CornerCard)
	Theme.stroke(band, "Accent", Theme.Sizes.Stroke)
	band.Parent = top
	local light: UIGradient? = nil

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
	heading.Size = UDim2.fromScale(0, 1)
	heading.LayoutOrder = 2
	fill(heading)
	rowLayout(heading, CAP_GAP)
	heading.Parent = row

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0, 1)
	title.LayoutOrder = 2
	title.Rotation = TITLE_TILT
	title.FontFace = Theme.Fonts.Title
	title.TextSize = Theme.Sizes.TextTitle
	title.TextXAlignment = Enum.TextXAlignment.Left
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
	local drips: { GuiObject } = {}

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

	local function paint()
		band.BackgroundColor3 = look.Band
		local old = light
		if old ~= nil then
			old:Destroy()
		end
		local gradient = Theme.gradient("BandLight", look.Band)
		gradient.Parent = band
		light = gradient
		title.TextColor3 = look.Title
		local current = stripe
		if look.Stripe then
			if current == nil then
				stripe = makeStripe(band)
			end
		elseif current ~= nil then
			stripe = nil
			current:Destroy()
		end
		for _, drip in ipairs(drips) do
			Splat.tint(drip, look.Band)
		end
		drawTitle()
	end
	paint()

	-- Made at the first entrance, when the band is in its screen: a splat counts against that screen's
	-- budget, and one made anywhere else would be counted against nothing.
	local function hangDrips()
		if #drips > 0 or not top:IsDescendantOf(game) then
			return
		end
		for index, drip in ipairs(DRIPS) do
			local splat = Splat.new({
				Size = UDim2.fromOffset(drip.Size, drip.Size),
				Tint = look.Band,
				Rotation = Splat.rotation(index),
				Position = UDim2.new(drip.X, 0, 1, DRIP_DROP),
				ZIndex = 1,
				Name = "Drip",
				Parent = top,
			})
			if splat ~= nil then
				table.insert(drips, splat)
			end
		end
	end

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
		hangDrips()
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

	local function destroy(_self: ChapterBand)
		trove:Destroy()
	end

	local object: ChapterBand = {
		Instance = top,
		Right = right,
		CloseButton = closeButton,
		SetTitle = setTitle,
		SetChapter = setChapter,
		PlayEnter = playEnter,
		Destroy = destroy,
	}
	return object
end

return ChapterBand
