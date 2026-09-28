--!strict
-- Panel: a screen's card (D-147). A sheet of vellum on a hard ink shadow, its chapter's band across the top
-- (ChapterBand: the colour, the drop cap and the title, the way back and the way out), then the fixed
-- Header and Footer slots around a scrolling Content (CardContent: a list, a grid of tiles or a track that
-- scrolls sideways). The card fills 94 % by 90 % of what holds it, capped on a pointer device (at `Size`,
-- the Theme panel size by default) so a wide monitor keeps a readable measure, and uncapped on a phone,
-- which needs all of it. When a D-pad press leaves the gamepad selection where it was, the panel scrolls
-- the content itself (see scrollRows).
--
-- A chapter screen's entrance and exit are its ScreenRoot's, which plays the card's half of them through
-- PlayEnter and PlayExit here. A Panel given no Chapter wears the Menu's ink band and enters by itself
-- whenever its screen is enabled, as every card did before D-147; that path goes with the last screen to
-- take a chapter (slices A and B of the colour pass).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local CardContent = require(script.Parent.CardContent)
local ChapterBand = require(script.Parent.ChapterBand)
local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

-- Height of a fixed band. A band whose controls carry the touch minimum passes a callback instead of a
-- number: the minimum follows the viewport, and only the callback is re-read by the relayout below, which
-- already runs on every scale change. A plain number stays as given (0 hides the band).
export type Height = number | (() -> number)
export type ContentMode = CardContent.Mode

export type Props = {
	Title: string,
	Size: Vector2?, -- the card's largest size on a pointer device, in px at UIScale 1
	Closable: boolean?,
	OnClose: (() -> ())?,
	AspectRatio: number?, -- optional UIAspectRatioConstraint
	Parent: Instance?,
	Name: string?,
	-- A ThemeConfig.Chapters key: the band's colour, the drop cap's ring, the drips. The Menu's without one.
	Chapter: string?,
	ContentMode: ContentMode?,
	-- The size of a cell in Grid mode (three to a row, TileHeight tall, by default).
	GridCell: UDim2?,
	-- The way back to the screen this one was opened from (MenuController.back), worded `nav.back` through
	-- `Localize`. Shown while `ShowBack` says so, read again at every entrance: the same screen opens from
	-- the menu, where there is a way back, and from the HUD, where there is none.
	OnBack: (() -> ())?,
	ShowBack: (boolean | () -> boolean)?,
	Localize: ChapterBand.Localizer?,
}

export type Panel = {
	Instance: Frame,
	Header: Frame,
	Content: ScrollingFrame,
	Footer: Frame,
	-- The band's own slot, before the cross: a Folios pill, a tier seal.
	Right: Frame,
	CloseButton: TextButton?,
	SetTitle: (self: Panel, title: string) -> (),
	SetChapter: (self: Panel, chapter: string) -> (),
	SetContentMode: (self: Panel, mode: ContentMode) -> (),
	SetHeaderHeight: (self: Panel, height: Height) -> (),
	SetFooterHeight: (self: Panel, height: Height) -> (),
	-- The card's half of a chapter screen's entrance and exit (ScreenRoot). The exit fades the card as one
	-- piece, puts it back where it was, then calls `onDone`.
	PlayEnter: (self: Panel) -> (),
	PlayExit: (self: Panel, onDone: () -> ()) -> (),
	-- Gamepad focus. A screen that never sets GuiService.SelectedObject leaves the D-pad dead until the
	-- player presses the navigation button a second time, so screens take the selection on Open
	-- (`target` defaults to the close button) and hand it back on Close.
	FocusForGamepad: (self: Panel, target: GuiObject?) -> (),
	ReleaseGamepadFocus: (self: Panel) -> (),
	-- Runs `rebuild`, which may destroy the control the pad is on (a socket taken off, a card leaving its tab,
	-- a claim that landed). When the selection was in this panel before and is gone after, it goes to what
	-- `fallback` names (FocusForGamepad's target), instead of leaving the D-pad dead.
	KeepGamepadFocus: (self: Panel, rebuild: () -> (), fallback: () -> GuiObject?) -> (),
	Destroy: (self: Panel) -> (),
}

local Panel = {}

-- The card's share of what holds it, and how far it stands off its ink shadow.
local CARD_SCALE = Vector2.new(0.94, 0.9)
local CARD_ELEVATION = 8
-- It arrives a little small and turned, and leaves a little small and turned the other way.
local ENTER_SCALE = 0.88
local ENTER_TILT = -3
local EXIT_SCALE = 0.92
local EXIT_TILT = 2
-- The band is a sticker on the page, inset from the card's edge.
local BAND_INSET = Theme.Sizes.PaddingSmall
local GRAIN_TILE = 256
local GRAIN_TRANSPARENCY = 0.9
local DPAD_SCROLL_ROWS = 1 -- canvas step per D-pad press, in list rows
-- Absorbs the rounding between a band height computed here and the UISizeConstraint the engine applies to
-- the control inside it, so one pixel of disagreement cannot push that control out of its band.
local BAND_SLACK = 1
-- What a card with no chapter wears: the ink band and the five-pigment stripe.
local DEFAULT_CHAPTER = "Menu"
-- No cap: a phone's card takes all of its share of the screen.
local UNCAPPED = Vector2.new(math.huge, math.huge)

local function horizontalPadding(parent: Instance, top: number, bottom: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.Parent = parent
	return padding
end

-- A fixed slot across the card, over everything but the more-below fade.
local function slot(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 0)
	frame.ZIndex = 3
	frame.Parent = parent
	return frame
end

function Panel.new(props: Props): Panel
	local trove = Trove.new()

	-- The card: a vellum sheet in an ink outline, on a hard ink shadow (a Card sticker, rule 11).
	local card = Sticker.new({
		Kind = "Card",
		Fill = Theme.Colors.Panel,
		Corner = UDim.new(0, Theme.Sizes.CornerPanel),
		Elevation = CARD_ELEVATION,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(CARD_SCALE.X, CARD_SCALE.Y),
		Name = props.Name or "Panel",
	})
	trove:Add(function()
		card:Destroy()
	end)
	local frame = card.Instance :: Frame
	local face = card.Face
	face.ClipsDescendants = true

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.Parent = frame

	local entrance = Instance.new("UIScale")
	entrance.Name = "Entrance"
	entrance.Parent = frame
	trove:Add(function()
		Motion.cancel(entrance)
		Motion.cancel(frame)
	end)

	if props.AspectRatio ~= nil then
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = props.AspectRatio
		aspect.AspectType = Enum.AspectType.FitWithinMaxSize
		aspect.Parent = frame
	end

	local grainId = Theme.texture("PaperGrain")
	if grainId ~= "" then
		local grain = Instance.new("ImageLabel")
		grain.Name = "Grain"
		grain.BackgroundTransparency = 1
		grain.Image = grainId
		grain.ScaleType = Enum.ScaleType.Tile
		grain.TileSize = UDim2.fromOffset(GRAIN_TILE, GRAIN_TILE)
		grain.ImageColor3 = Theme.Colors.TextMuted
		grain.ImageTransparency = GRAIN_TRANSPARENCY
		grain.Size = UDim2.fromScale(1, 1)
		grain.ZIndex = 1
		grain.Parent = face
	end

	local band = ChapterBand.new({
		Title = props.Title,
		Chapter = props.Chapter or DEFAULT_CHAPTER,
		Position = UDim2.fromOffset(BAND_INSET, BAND_INSET),
		Closable = props.Closable,
		OnClose = props.OnClose,
		OnBack = props.OnBack,
		Localize = props.Localize,
	})
	trove:Add(function()
		band:Destroy()
	end)
	-- Over the grain, under the slots: its drips hang behind whatever the header holds.
	band.Instance.ZIndex = 2
	band.Instance.Parent = face

	-- Fixed header slot (tabs, summaries)
	local header = slot("Header", face)
	horizontalPadding(header, Theme.Sizes.PaddingSmall, Theme.Sizes.PaddingSmall)

	-- Fixed footer slot (action buttons)
	local footer = slot("Footer", face)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	horizontalPadding(footer, Theme.Sizes.PaddingSmall, Theme.Sizes.Padding)

	local body = CardContent.new({ Mode = props.ContentMode, GridCell = props.GridCell, Parent = face })
	trove:Add(function()
		body:Destroy()
	end)
	local content = body.Instance
	content.ZIndex = 3
	body.MoreBelow.ZIndex = 4

	local headerHeight: Height = 0
	local footerHeight: Height = 0

	local function bandHeight(height: Height): number
		local value: number
		if type(height) == "function" then
			value = height()
		else
			value = height
		end
		if value <= 0 then
			return 0
		end
		return value + BAND_SLACK
	end

	-- The chapter band holds the cross and the way back, so it follows their touch minimum
	-- (ChapterBand.height): on a phone the unscaled touch row is taller than Theme.Sizes.RowHeight.
	local function relayout()
		sizeConstraint.MaxSize = if Theme.touchOnly()
			then UNCAPPED
			else props.Size or Vector2.new(Theme.Sizes.PanelWidth, Theme.Sizes.PanelHeight)
		local chapterHeight = ChapterBand.height()
		local topHeight = BAND_INSET + chapterHeight + Theme.Sizes.PaddingSmall
		local headerSize = bandHeight(headerHeight)
		local footerSize = bandHeight(footerHeight)
		band.Instance.Size = UDim2.new(1, -BAND_INSET * 2, 0, chapterHeight)
		header.Position = UDim2.fromOffset(0, topHeight)
		header.Size = UDim2.new(1, 0, 0, headerSize)
		footer.Size = UDim2.new(1, 0, 0, footerSize)
		content.Position = UDim2.fromOffset(0, topHeight + headerSize)
		content.Size = UDim2.new(1, 0, 1, -(topHeight + headerSize + footerSize))
		body.MoreBelow.Position = UDim2.new(0, 0, 1, -footerSize)
	end
	trove:Add(Theme.bindScale(relayout))

	local function scrollRows(rows: number)
		local maximum = math.max(0, content.AbsoluteCanvasSize.Y - content.AbsoluteWindowSize.Y)
		-- CanvasPosition is in rendered pixels, the row pitch in unscaled offsets.
		local step = (Theme.touchTargetHeight(Theme.Sizes.RowHeight) + Theme.Sizes.Gap) * Theme.activeScale()
		local position = content.CanvasPosition
		content.CanvasPosition = Vector2.new(position.X, math.clamp(position.Y + rows * step, 0, maximum))
	end

	-- Roblox only scrolls a ScrollingFrame when GuiService.SelectedObject travels inside it, so a canvas the
	-- engine has nowhere left to walk to is frozen for a gamepad player: a read-only list has nothing to
	-- select, and a long list whose few selectable cells all sit behind the selection is just as stuck. The
	-- panel then steps the canvas itself, but only once it has seen the press move the selection nowhere --
	-- stepping while the engine is auto-scrolling towards a new selection would fight it.
	-- The step is decided a frame after the press, by which time the panel may already be destroyed.
	local alive = true
	trove:Add(function()
		alive = false
	end)
	local stepPending = false

	local function stepUnlessSelectionMoves(rows: number, before: GuiObject)
		if stepPending then
			return
		end
		stepPending = true
		RunService.Heartbeat:Once(function()
			stepPending = false
			if not alive or GuiService.SelectedObject ~= before then
				return
			end
			scrollRows(rows)
		end)
	end

	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		local rows = if input.KeyCode == Enum.KeyCode.DPadDown
			then DPAD_SCROLL_ROWS
			elseif input.KeyCode == Enum.KeyCode.DPadUp then -DPAD_SCROLL_ROWS
			else 0
		if rows == 0 then
			return
		end
		-- Scoped to the panel holding the selection: another open panel must not scroll with it.
		local selected = GuiService.SelectedObject
		if selected == nil or not selected:IsDescendantOf(frame) then
			return
		end
		stepUnlessSelectionMoves(rows, selected)
	end)

	----------------------------------------------------------------
	-- Entrance and exit
	----------------------------------------------------------------

	-- The transient group a leaving card fades in, and where the card goes back to after.
	local exitGroup: CanvasGroup? = nil
	local exitHome: Instance? = nil
	-- Bumped by every entrance and exit, so an exit caught by an entrance never calls its `onDone`.
	local exitToken = 0

	local function restoreFromExit()
		local group = exitGroup
		exitGroup = nil
		if group == nil then
			return
		end
		Motion.cancel(group)
		frame.Parent = exitHome
		exitHome = nil
		group:Destroy()
	end
	trove:Add(function()
		exitToken += 1
		restoreFromExit()
	end)

	local function showBack(): boolean
		local shown = props.ShowBack
		if type(shown) == "function" then
			return shown()
		end
		return shown == true
	end

	local function playEnter(_self: Panel?)
		exitToken += 1
		restoreFromExit()
		Motion.set(entrance, { Scale = ENTER_SCALE })
		Motion.to(entrance, { Scale = 1 }, "UiPop")
		Motion.set(frame, { Rotation = ENTER_TILT })
		Motion.to(frame, { Rotation = 0 }, "UiPop")
		band:PlayEnter(showBack())
		body:PlayEnter()
	end

	local function playExit(_self: Panel, onDone: () -> ())
		local home = frame.Parent
		-- Nothing on screen to fade: a spring on an instance outside the DataModel never settles.
		if home == nil or exitGroup ~= nil or not frame:IsDescendantOf(game) then
			onDone()
			return
		end
		exitToken += 1
		local token = exitToken
		-- A transient group, so the card and everything on it fade as one piece. It covers what holds the
		-- card, so the card keeps its own size and place in it, and it lasts as long as the exit.
		local group = Instance.new("CanvasGroup")
		group.Name = "Exit"
		group.BackgroundTransparency = 1
		group.BorderSizePixel = 0
		group.Size = UDim2.fromScale(1, 1)
		group.ZIndex = frame.ZIndex
		group.Parent = home
		frame.Parent = group
		exitGroup = group
		exitHome = home
		Motion.to(group, { GroupTransparency = 1 }, "UiExit", function()
			if exitToken ~= token then
				return
			end
			restoreFromExit()
			Motion.set(entrance, { Scale = 1 })
			Motion.set(frame, { Rotation = 0 })
			onDone()
		end)
		-- Under reduced motion only the fade runs.
		if not UiPrefs.reducedMotion() then
			Motion.to(entrance, { Scale = EXIT_SCALE }, "UiExit")
			Motion.to(frame, { Rotation = EXIT_TILT }, "UiExit")
		end
	end

	frame.Parent = props.Parent

	-- The screen this card belongs to, resolved after parenting, when the ancestor exists. The content's
	-- arrow bobs only while it is up, and a chapterless card enters whenever it is enabled.
	local screen = frame:FindFirstAncestorWhichIsA("ScreenGui")
	if screen ~= nil then
		body:SetShown(screen.Enabled)
		trove:Connect(screen:GetPropertyChangedSignal("Enabled"), function()
			if screen.Enabled and props.Chapter == nil then
				playEnter(nil)
			end
			body:SetShown(screen.Enabled)
		end)
	else
		body:SetShown(true)
	end

	local function setTitle(_self: Panel, text: string)
		band:SetTitle(text)
	end

	local function setChapter(_self: Panel, chapter: string)
		band:SetChapter(chapter)
	end

	local function setContentMode(_self: Panel, mode: ContentMode)
		body:SetMode(mode)
	end

	local function setHeaderHeight(_self: Panel, height: Height)
		headerHeight = height
		relayout()
	end

	local function setFooterHeight(_self: Panel, height: Height)
		footerHeight = height
		relayout()
	end

	-- No-op without a gamepad, so screens can call it unconditionally. The ScreenGui must already be
	-- enabled: the engine drops a selection pointing inside a disabled ScreenGui.
	local function focusForGamepad(_self: Panel, target: GuiObject?)
		if not UserInputService.GamepadEnabled then
			return
		end
		local focus: GuiObject? = target or band.CloseButton
		if focus == nil then
			return
		end
		GuiService.SelectedObject = focus
	end

	-- Only releases a selection that belongs to this panel, so a screen closing behind another one
	-- (menu navigation) never steals the focus the new screen just took.
	local function releaseFocus()
		local selected = GuiService.SelectedObject
		if selected ~= nil and selected:IsDescendantOf(frame) then
			GuiService.SelectedObject = nil
		end
	end

	local function releaseGamepadFocus(_self: Panel)
		releaseFocus()
	end

	local function keepGamepadFocus(self: Panel, rebuild: () -> (), fallback: () -> GuiObject?)
		local before = GuiService.SelectedObject
		local inside = before ~= nil and before:IsDescendantOf(frame)
		rebuild()
		if not inside then
			return
		end
		local after = GuiService.SelectedObject
		if after ~= nil and after:IsDescendantOf(game) then
			return
		end
		focusForGamepad(self, fallback())
	end

	local function destroy(_self: Panel)
		releaseFocus()
		trove:Destroy()
	end

	local object: Panel = {
		Instance = frame,
		Header = header,
		Content = content,
		Footer = footer,
		Right = band.Right,
		CloseButton = band.CloseButton,
		SetTitle = setTitle,
		SetChapter = setChapter,
		SetContentMode = setContentMode,
		SetHeaderHeight = setHeaderHeight,
		SetFooterHeight = setFooterHeight,
		PlayEnter = playEnter,
		PlayExit = playExit,
		FocusForGamepad = focusForGamepad,
		ReleaseGamepadFocus = releaseGamepadFocus,
		KeepGamepadFocus = keepGamepadFocus,
		Destroy = destroy,
	}
	return object
end

return Panel
