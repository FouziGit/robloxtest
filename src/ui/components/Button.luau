--!strict
-- Button: a sticker you press (D-147). A flat face on a coloured lip: hover lifts it, a press sinks it onto
-- the lip, and letting go springs it back with the overshoot of a real key -- the overshoot is the click.
-- The face says what the button is before its word does:
--
--   Primary    the primary yellow: go, claim, buy          Secondary  the sheet: everything else
--   Owner      the colour of the screen's chapter          Danger     red: only a destructive confirm
--   Premium    the yellow, a second line for the price     Tile       a menu tile, sized by its grid
--   Ghost      no face: an underlined word
--
-- A button is as wide as its word, never less than a thumb's worth, and never truncates it. A disabled
-- button says why (a lock and a level, a claimed seal, "slots full"), a pending one bounces three dots
-- until the server answers or gives up, and the button plays its own click (UiSound). Theme.minPixelSize
-- keeps it at Theme.MinTouchTarget real pixels whatever the UIScale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Badge = require(script.Parent.Badge)
local Icon = require(script.Parent.Icon)
local Motion = require(script.Parent.Parent.Motion)
local Seal = require(script.Parent.Seal)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiSound = require(script.Parent.Parent.UiSound)

export type Variant = "Primary" | "Secondary" | "Danger" | "Owner" | "Premium" | "Tile" | "Ghost"
export type DisabledReason = "Locked" | "Claimed" | "Owned" | "Premium" | "Full" | "Pending"
export type FlashKind = "Success" | "Error"

export type Props = {
	Text: string,
	Variant: Variant?,
	OnClick: (() -> ())?,
	Disabled: boolean?,
	Size: UDim2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
	-- An Icon name, drawn before the word.
	Icon: Icon.Name?,
	Badge: Badge.Value?,
	-- A second line: the price of a Premium button, the subtitle of a tile.
	Sublabel: string?,
	-- The screen whose chapter colours an Owner button or a tile (a ThemeConfig.Chapters key).
	Chapter: string?,
	Wide: boolean?,
	DisabledReason: DisabledReason?,
	-- Called when a pending button gives up waiting (ThemeConfig.Timing.PendingTimeoutSeconds).
	OnTimeout: (() -> ())?,
}

export type Button = {
	Instance: TextButton,
	SetText: (self: Button, text: string) -> (),
	-- `reason` says why, and `reasonText` replaces the word while it is disabled ("Level 12").
	SetDisabled: (self: Button, disabled: boolean, reason: DisabledReason?, reasonText: string?) -> (),
	SetVariant: (self: Button, variant: Variant) -> (),
	IsDisabled: (self: Button) -> boolean,
	SetPending: (self: Button, pending: boolean) -> (),
	Flash: (self: Button, kind: FlashKind) -> (),
	SetBadge: (self: Button, value: Badge.Value?) -> (),
	-- The face the button draws its content on, which rides a press; nil for a Ghost, which has none.
	Face: (self: Button) -> Frame?,
	Destroy: (self: Button) -> (),
}

type Look = { Face: Color3, Ink: Color3, Lip: Color3, Gloss: boolean, Elevation: number, Corner: UDim }

local Button = {}

local MIN_WIDTH = 140
local WIDE_WIDTH = 220
local PADDING_X = 18
local ICON_SIZE = 28
local REASON_ICON_SIZE = 20
local GAP = 8
local ELEVATION = 5
local TILE_ELEVATION = 6
local TILE_ICON_SIZE = 48
local TILE_TEXT_SIZE = 24
local GHOST_TEXT_SIZE = 18
local SUBLABEL_SIZE = 18
local MIN_SCALED_TEXT = 14
local HOVER_SCALE = 1.03
local PRESSED_SCALE = 0.97
local FOCUS_SCALE = 1.06
local DOT_SIZE = 8
local DOT_BOUNCE = 4
local RIM_SCALE = 1.2
local RIM_TRANSPARENCY = 0.2

local function lookFor(variant: Variant, chapter: string?): Look
	local look: Look = {
		Face = Theme.Colors.PanelRaised,
		Ink = Theme.Colors.Text,
		Lip = Theme.lip("Secondary"),
		Gloss = false,
		Elevation = ELEVATION,
		Corner = Theme.Pill,
	}
	if variant == "Primary" or variant == "Premium" then
		look.Face = Theme.Colors.Primary
		look.Lip = Theme.lip("Primary")
		look.Gloss = variant == "Primary"
	elseif variant == "Danger" then
		look.Face = Theme.Colors.DangerFill
		look.Lip = Theme.lip("Danger")
	elseif variant == "Owner" or variant == "Tile" then
		local owner = Theme.chapter(chapter or "Menu")
		look.Face = owner.Band
		look.Ink = Theme.inkOn(owner.Band)
		look.Lip = owner.Lip
		look.Gloss = owner.Band ~= Theme.Colors.Plate
		if variant == "Tile" then
			look.Elevation = TILE_ELEVATION
			look.Corner = UDim.new(0, Theme.Sizes.CornerTile)
		end
	elseif variant == "Ghost" then
		look.Elevation = 0
	end
	return look
end

local function textLabel(name: string, font: Font, size: number, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.new()
	label.FontFace = font
	label.TextSize = size
	label.TextTruncate = Enum.TextTruncate.None
	label.LayoutOrder = order
	return label
end

function Button.new(props: Props): Button
	local trove = Trove.new()
	local variant: Variant = props.Variant or "Secondary"
	local look = lookFor(variant, props.Chapter)
	local text = props.Text
	local disabled = props.Disabled == true
	local reason: DisabledReason? = props.DisabledReason
	local reasonText: string? = nil
	local pending = false
	local pendingToken = 0
	local hovered, pressed, focused = false, false, false
	local isTile = variant == "Tile"

	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.Size = props.Size or UDim2.fromOffset(0, Theme.Sizes.ButtonHeight)
	button.LayoutOrder = props.LayoutOrder or 0
	button.Selectable = not disabled
	local stretched = props.Size ~= nil and props.Size.X.Scale ~= 0
	if not isTile and not stretched then
		-- As wide as its word: a French label is never cut. A button its caller stretches by scale keeps that
		-- width: sizing it automatically too, the engine dropped the width's offset (a card's Equip ran over
		-- the card's own outline).
		button.AutomaticSize = Enum.AutomaticSize.X
	end
	button.SelectionImageObject = trove:Add(Theme.focusRing(nil, look.Corner))
	trove:Add(button)

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = button
	trove:Add(function()
		Motion.cancel(scale)
	end)
	Theme.minPixelSize(button, Theme.MinTouchTarget)

	-- Invisible, and what the automatic width is measured on: its padding holds the icon and the margins, its
	-- own size the minimum width. The face and its lip are the button's own children, sized by scale to
	-- whatever it asks for (Sticker's Host), and the word is centred on the face at its own size: nothing
	-- under the face takes its width from it, or the engine would measure it against the screen (D-170).
	local measure = Instance.new("TextLabel")
	measure.Name = "Measure"
	measure.BackgroundTransparency = 1
	measure.TextTransparency = 1
	measure.AutomaticSize = Enum.AutomaticSize.X
	measure.FontFace = Theme.Fonts.Bold
	measure.TextSize = Theme.Sizes.TextButton
	local measurePadding = Instance.new("UIPadding")
	measurePadding.PaddingRight = UDim.new(0, PADDING_X)
	measurePadding.Parent = measure
	measure.Visible = not isTile
	measure.Parent = button

	-- The face's content: the icon slot, then the word and its second line.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	content.Size = UDim2.new()
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.ZIndex = 3
	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Horizontal
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, GAP)
	contentLayout.Parent = content

	local iconSlot = Instance.new("Frame")
	iconSlot.Name = "Icon"
	iconSlot.BackgroundTransparency = 1
	iconSlot.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	iconSlot.LayoutOrder = 1
	iconSlot.Parent = content

	local words = Instance.new("Frame")
	words.Name = "Words"
	words.BackgroundTransparency = 1
	words.AutomaticSize = Enum.AutomaticSize.XY
	words.Size = UDim2.new()
	words.LayoutOrder = 2
	words.Parent = content
	local wordsLayout = Instance.new("UIListLayout")
	wordsLayout.FillDirection = Enum.FillDirection.Vertical
	wordsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	wordsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	wordsLayout.Parent = words

	local label = textLabel("Label", Theme.Fonts.Bold, Theme.Sizes.TextButton, 1)
	label.Parent = words
	local sublabel = textLabel("Sublabel", Theme.Fonts.Numeric, SUBLABEL_SIZE, 2)
	sublabel.Text = props.Sublabel or ""
	sublabel.Visible = props.Sublabel ~= nil
	sublabel.Parent = words

	if isTile then
		-- A tile is sized by its grid: its icon sits top-left and its word fills the bottom, scaled.
		content.AutomaticSize = Enum.AutomaticSize.None
		content.AnchorPoint = Vector2.zero
		content.Size = UDim2.new(1, -Theme.Sizes.Padding * 2, 1, -Theme.Sizes.Padding * 2)
		content.Position = UDim2.fromOffset(Theme.Sizes.Padding, Theme.Sizes.Padding)
		contentLayout.FillDirection = Enum.FillDirection.Vertical
		contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		contentLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		iconSlot.Size = UDim2.fromOffset(TILE_ICON_SIZE, TILE_ICON_SIZE)
		words.AutomaticSize = Enum.AutomaticSize.Y
		words.Size = UDim2.fromScale(1, 0)
		wordsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		label.FontFace = Theme.Fonts.Title
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(1, 0, 0, TILE_TEXT_SIZE + 6)
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		local cap = Instance.new("UITextSizeConstraint")
		cap.MinTextSize = MIN_SCALED_TEXT
		cap.MaxTextSize = TILE_TEXT_SIZE
		cap.Parent = label
		sublabel.FontFace = Theme.Fonts.Body
		sublabel.TextSize = Theme.Sizes.TextBody - 2
	elseif variant == "Ghost" then
		label.TextSize = GHOST_TEXT_SIZE
	end

	-- Three dots that bounce while the server has not answered: a wave on ONE loop goes back and forth across
	-- them, each dot up as it passes, so a pending button spends one of its screen's Budget.MaxIdleLoops, not
	-- three.
	local dots = Instance.new("Frame")
	dots.Name = "Pending"
	dots.BackgroundTransparency = 1
	dots.AnchorPoint = Vector2.new(0.5, 0.5)
	dots.Position = UDim2.fromScale(0.5, 0.5)
	dots.Size = UDim2.fromOffset(DOT_SIZE * 5, DOT_SIZE + DOT_BOUNCE)
	dots.ZIndex = 4
	dots.Visible = false
	local dotList: { Frame } = {}
	for index = 1, 3 do
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.BorderSizePixel = 0
		dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
		dot.Position = UDim2.fromOffset((index - 1) * DOT_SIZE * 2, DOT_BOUNCE)
		Theme.corner(dot, Theme.Pill)
		dot.Parent = dots
		dotList[index] = dot
	end
	local wave = Instance.new("NumberValue")
	wave.Name = "Wave"
	wave.Parent = dots
	trove:Connect(wave.Changed, function(value: number)
		for index, dot in ipairs(dotList) do
			local place = (index - 1) / (#dotList - 1)
			local lift = math.clamp(1 - math.abs(value - place) * #dotList, 0, 1)
			dot.Position = UDim2.fromOffset((index - 1) * DOT_SIZE * 2, DOT_BOUNCE * (1 - lift))
		end
	end)
	local stopDots: (() -> ())? = nil

	local sticker: Sticker.Sticker? = nil
	local ghostRule: Frame? = nil
	local rim: ImageLabel? = nil
	local badge: Badge.Badge? = nil

	-- The face of the current variant, rebuilt when the variant changes; the content moves with it.
	local function buildFace()
		local old = sticker
		sticker = nil
		local oldRule, oldRim = ghostRule, rim
		ghostRule, rim = nil, nil
		if variant == "Ghost" then
			content.Parent = button
			dots.Parent = button
			local rule = Instance.new("Frame")
			rule.Name = "Rule"
			rule.BorderSizePixel = 0
			rule.BackgroundColor3 = Theme.Colors.Accent
			rule.AnchorPoint = Vector2.new(0.5, 1)
			rule.Position = UDim2.new(0.5, 0, 1, -GAP)
			rule.Size = UDim2.new(1, -PADDING_X * 2, 0, Theme.Sizes.StrokeThin)
			rule.Parent = button
			ghostRule = rule
		else
			local face = Sticker.new({
				Kind = "Pressable",
				Fill = look.Face,
				Lip = look.Lip,
				Corner = look.Corner,
				Elevation = look.Elevation,
				Gloss = look.Gloss,
				Host = button,
			})
			content.Parent = face.Face
			dots.Parent = face.Face
			sticker = face
			if variant == "Premium" then
				local id = Theme.texture("SealRing")
				if id ~= "" then
					local ring = Instance.new("ImageLabel")
					ring.Name = "Rim"
					ring.BackgroundTransparency = 1
					ring.Image = id
					ring.ImageColor3 = Theme.Colors.Primary
					ring.ImageTransparency = RIM_TRANSPARENCY
					ring.AnchorPoint = Vector2.new(0.5, 0.5)
					ring.Position = UDim2.fromScale(0.5, 0.5)
					ring.Size = UDim2.fromScale(RIM_SCALE, RIM_SCALE)
					ring.ZIndex = 0
					ring.Parent = button
					rim = ring
				end
			end
		end
		if old ~= nil then
			old:Destroy()
		end
		if oldRule ~= nil then
			oldRule:Destroy()
		end
		if oldRim ~= nil then
			oldRim:Destroy()
		end
		local currentBadge = badge
		if currentBadge ~= nil then
			currentBadge.Instance.Parent = button
		end
	end

	local function clearIcon()
		for _, child in ipairs(iconSlot:GetChildren()) do
			child:Destroy()
		end
	end

	-- The icon slot: the reason a disabled button is disabled, or the button's own icon.
	local function drawIcon()
		clearIcon()
		local ink = if disabled then Theme.Colors.TextMuted else look.Ink
		local size = if isTile then TILE_ICON_SIZE else ICON_SIZE
		local shown = true
		if disabled and (reason == "Claimed" or reason == "Owned") then
			-- Destroyed with the slot's other children on the next redraw, or with the button.
			Seal.new({
				Text = Theme.Glyphs.Check,
				Fill = Theme.Colors.SuccessFill,
				Size = REASON_ICON_SIZE,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Parent = iconSlot,
			})
		elseif disabled and reason == "Locked" then
			Icon.new("Lock", REASON_ICON_SIZE, ink).Parent = iconSlot
		elseif disabled and reason == "Premium" then
			Icon.new("Coin", REASON_ICON_SIZE).Parent = iconSlot
			local lock = Icon.new("Lock", REASON_ICON_SIZE / 2, ink)
			lock.AnchorPoint = Vector2.new(1, 1)
			lock.Position = UDim2.fromScale(1, 1)
			lock.Parent = iconSlot
		elseif props.Icon ~= nil then
			Icon.new(props.Icon, size, ink).Parent = iconSlot
		else
			shown = false
		end
		iconSlot.Visible = shown
		iconSlot.Size = UDim2.fromOffset(size, size)
		local lead = if shown and not isTile then size + GAP else 0
		measurePadding.PaddingLeft = UDim.new(0, PADDING_X + lead)
	end

	local function render(animate: boolean)
		local shown = if disabled and reasonText ~= nil then reasonText :: string else text
		label.Text = shown
		measure.Text = shown
		local minWidth = if props.Wide then WIDE_WIDTH else MIN_WIDTH
		measure.Size = UDim2.new(0, minWidth, 1, 0)
		label.TextColor3 = if disabled then Theme.Colors.TextMuted else look.Ink
		sublabel.TextColor3 = label.TextColor3
		label.Visible = not pending
		sublabel.Visible = props.Sublabel ~= nil and not pending
		iconSlot.Visible = iconSlot.Visible and not pending
		for _, dot in ipairs(dotList) do
			dot.BackgroundColor3 = look.Ink
		end
		local face = sticker
		if face ~= nil then
			local state: Sticker.State = "Idle"
			if disabled then
				state = "Disabled"
			elseif pressed then
				state = "Pressed"
			elseif hovered then
				state = "Hover"
			end
			face:SetState(state)
		end
		local target = 1
		if not disabled then
			if pressed then
				target = PRESSED_SCALE
			elseif focused then
				target = FOCUS_SCALE
			elseif hovered then
				target = HOVER_SCALE
			end
		end
		if animate then
			Motion.to(scale, { Scale = target }, if target == 1 then "UiPop" else "UiSnappy")
		else
			Motion.set(scale, { Scale = target })
		end
	end

	local function setPending(_self: Button?, next: boolean)
		if pending == next then
			return
		end
		pending = next
		pendingToken += 1
		local stop = stopDots
		stopDots = nil
		if stop ~= nil then
			stop()
		end
		dots.Visible = next
		if next then
			stopDots = Motion.loop(wave, { Value = 0 }, { Value = 1 }, "Ui")
			local token = pendingToken
			task.delay(Theme.Timing.PendingTimeoutSeconds, function()
				if pending and pendingToken == token and button:IsDescendantOf(game) then
					setPending(nil, false)
					local onTimeout = props.OnTimeout
					if onTimeout ~= nil then
						onTimeout()
					end
				end
			end)
		end
		drawIcon()
		render(true)
	end
	trove:Add(function()
		pending = false
		local stop = stopDots
		stopDots = nil
		if stop ~= nil then
			stop()
		end
		Motion.cancel(wave)
	end)

	trove:Connect(button.MouseEnter, function()
		hovered = true
		render(true)
	end)
	trove:Connect(button.MouseLeave, function()
		hovered = false
		pressed = false
		render(true)
	end)
	trove:Connect(button.MouseButton1Down, function()
		pressed = true
		render(true)
	end)
	trove:Connect(button.MouseButton1Up, function()
		pressed = false
		render(true)
	end)
	trove:Connect(button.SelectionGained, function()
		focused = true
		render(true)
	end)
	trove:Connect(button.SelectionLost, function()
		focused = false
		pressed = false
		render(true)
	end)
	trove:Connect(button.Activated, function()
		if disabled or pending then
			return
		end
		UiSound.play("UiClick")
		local onClick = props.OnClick
		if onClick ~= nil then
			onClick()
		end
	end)

	buildFace()
	drawIcon()
	render(false)
	if props.Badge ~= nil then
		badge =
			Badge.new(props.Badge, button, if look.Face == Theme.Colors.Primary then Theme.Colors.PanelRaised else nil)
	end
	button.Parent = props.Parent

	local function setText(_self: Button, next: string)
		text = next
		render(false)
	end

	local function setDisabled(_self: Button, value: boolean, why: DisabledReason?, whyText: string?)
		disabled = value
		reason = if value then why else nil
		reasonText = if value then whyText else nil
		button.Selectable = not value
		drawIcon()
		render(true)
	end

	local function setVariant(_self: Button, next: Variant)
		if next == variant then
			return
		end
		variant = next
		look = lookFor(next, props.Chapter)
		buildFace()
		drawIcon()
		render(false)
	end

	local function isDisabled(_self: Button): boolean
		return disabled
	end

	local function flash(_self: Button, kind: FlashKind)
		local face = sticker
		if face == nil then
			return
		end
		local success = kind == "Success"
		face:SetFill(if success then Theme.Colors.SuccessFill else Theme.Colors.DangerFill)
		label.Text = if success then Theme.Glyphs.Check else text
		label.TextColor3 = Theme.Colors.Text
		if success then
			Motion.punch(scale, FOCUS_SCALE)
		else
			-- The word shakes on the face: the button itself is placed by its row's layout.
			Motion.shake(content)
		end
		local shownFace = face
		task.delay(Theme.Timing.SuccessFlashSeconds, function()
			if sticker == shownFace and button:IsDescendantOf(game) then
				shownFace:SetFill(look.Face)
				render(true)
			end
		end)
	end

	local function setBadge(_self: Button, value: Badge.Value?)
		local current = badge
		if current ~= nil then
			current:Set(value)
		elseif value ~= nil then
			badge =
				Badge.new(value, button, if look.Face == Theme.Colors.Primary then Theme.Colors.PanelRaised else nil)
		end
	end

	local function faceOfButton(_self: Button): Frame?
		local current = sticker
		return if current ~= nil then current.Face else nil
	end

	local function destroy(_self: Button)
		local current = badge
		if current ~= nil then
			current:Destroy()
		end
		local face = sticker
		if face ~= nil then
			face:Destroy()
		end
		trove:Destroy()
	end

	local object: Button = {
		Instance = button,
		SetText = setText,
		SetDisabled = setDisabled,
		SetVariant = setVariant,
		IsDisabled = isDisabled,
		SetPending = setPending,
		Flash = flash,
		SetBadge = setBadge,
		Face = faceOfButton,
		Destroy = destroy,
	}
	return object
end

return Button
