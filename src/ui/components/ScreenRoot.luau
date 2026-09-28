--!strict
-- ScreenRoot: a ScreenGui with a Theme-driven UIScale and a safe-area content frame. Screens parent their
-- card to `Content` so it never sits under the Roblox top bar or device notches.
--
-- A chapter screen (D-147) also gets its backdrop here, the same one for every screen: the ink dim over the
-- whole viewport, swallowing the clicks meant for the world, the chapter's colour washing out from the
-- centre, and three blots of it in the corners. And its entrance and its exit, which are the backdrop's and
-- the card's (SetCard): in, the dim and the colour come up as the card springs into place; out, the card
-- fades as one piece while the dim lifts, and only then is the screen disabled. Nothing appears and nothing
-- vanishes (docs/ART_BIBLE.md rule 3).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Splat = require(script.Parent.Splat)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

-- What a screen's card lends its root: the card's half of the entrance and of the exit (a Panel).
export type Card = {
	PlayEnter: (self: any) -> (),
	PlayExit: (self: any, onDone: () -> ()) -> (),
}

export type Props = {
	Name: string,
	DisplayOrder: number?,
	Parent: Instance?,
	-- A ThemeConfig.Chapters key: the screen gets the shared backdrop, in that chapter's colour.
	Chapter: string?,
	-- A menu follows the player's own text size (UiPrefs.textScale). The HUD never does: its geometry is
	-- measured at the designed sizes.
	TextScalable: boolean?,
}

export type ScreenRoot = {
	Instance: ScreenGui,
	Content: Frame,
	Scale: UIScale,
	GetScale: (self: ScreenRoot) -> number,
	-- The card whose half of the entrance and exit PlayEnter and PlayExit play.
	SetCard: (self: ScreenRoot, card: Card?) -> (),
	-- Recolours the backdrop: the Result takes its outcome's colour.
	SetChapter: (self: ScreenRoot, chapter: string) -> (),
	-- Enables the screen and brings it in: what a screen's Open calls.
	PlayEnter: (self: ScreenRoot) -> (),
	-- Takes the screen out, disables it, then calls `onDone`: what a screen's Close calls.
	PlayExit: (self: ScreenRoot, onDone: (() -> ())?) -> (),
	Destroy: (self: ScreenRoot) -> (),
}

local ScreenRoot = {}

-- The dim over the world, before the player's own background-transparency setting multiplies it.
local DIM = 0.35
-- The chapter's colour, washed out from the centre over a texture a little larger than the screen.
local WASH_SCALE = 1.4
local WASH_TRANSPARENCY = 0.72
-- Three blots of it in the corners: where each is centred, how wide, how turned.
local CORNER_TRANSPARENCY = 0.85
local CORNERS: { { Position: UDim2, Size: number, Rotation: number } } = {
	{ Position = UDim2.fromScale(0, 0), Size = 360, Rotation = -18 },
	{ Position = UDim2.fromScale(1, 1), Size = 420, Rotation = 24 },
	{ Position = UDim2.fromScale(1, 0), Size = 220, Rotation = 7 },
}

function ScreenRoot.new(props: Props): ScreenRoot
	local trove = Trove.new()
	local textScalable = props.TextScalable == true

	local gui = Instance.new("ScreenGui")
	gui.Name = props.Name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = props.DisplayOrder or 0
	trove:Add(gui)

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = gui

	local content = Instance.new("Frame")
	content.Name = "SafeArea"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 1
	content.Parent = gui

	-- The entrance is the backdrop's and the card's, never this frame's. Scaling it scales the SAFE AREA:
	-- whatever a screen parents to it would leave an undimmed border all around the screen for as long as
	-- the spring ran.

	local padding = Instance.new("UIPadding")
	padding.Name = "SafeAreaPadding"
	padding.Parent = content

	local currentScale = 1

	-- Offsets are multiplied by the UIScale, so pixel insets are divided by it to stay exact.
	local function apply()
		currentScale = Theme.activeScale() * (if textScalable then UiPrefs.textScale() else 1)
		scale.Scale = currentScale
		local topLeft, bottomRight = GuiService:GetGuiInset()
		padding.PaddingTop = UDim.new(0, topLeft.Y / currentScale)
		padding.PaddingLeft = UDim.new(0, topLeft.X / currentScale)
		padding.PaddingBottom = UDim.new(0, bottomRight.Y / currentScale)
		padding.PaddingRight = UDim.new(0, bottomRight.X / currentScale)
	end

	-- Theme.bindScale is the only viewport trigger, on purpose. GuiService.SafeZoneOffsetsChanged is
	-- reserved for engine scripts: connecting to it from a LocalScript raises "lacking capability
	-- RobloxScript", which killed ScreenRoot.new and with it the HUD and every screen. The offsets change
	-- when the device rotates or the topbar resizes, and both of those change the viewport, so bindScale
	-- already covers them. GuiService:GetGuiInset() above is a plain method and stays.
	trove:Add(Theme.bindScale(apply))

	----------------------------------------------------------------
	-- Backdrop
	----------------------------------------------------------------

	-- Under the safe area and over the whole viewport, the notch and the top bar included.
	local backdrop: Frame? = nil
	local dim: Frame? = nil
	local wash: ImageLabel? = nil
	local corners: { GuiObject } = {}

	local function dimTarget(): number
		return DIM * UiPrefs.transparency()
	end

	-- The lowest graphics tier draws no corner blots (ThemeConfig.Budget, D-147 §9).
	local function showCorners()
		local shown = not UiPrefs.lowQuality()
		for _, splat in ipairs(corners) do
			splat.Visible = shown
		end
	end

	local function paint(chapter: string)
		local color = Theme.chapter(chapter).Band
		local image = wash
		if image ~= nil then
			image.ImageColor3 = color
		end
		for _, splat in ipairs(corners) do
			Splat.tint(splat, color)
		end
	end

	local function buildBackdrop(chapter: string)
		local frame = Instance.new("Frame")
		frame.Name = "Backdrop"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(1, 1)
		frame.ZIndex = 0
		frame.Parent = gui
		backdrop = frame

		local overlay = Instance.new("Frame")
		overlay.Name = "Overlay"
		overlay.BackgroundColor3 = Theme.Colors.Overlay
		overlay.BackgroundTransparency = dimTarget()
		overlay.BorderSizePixel = 0
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.ZIndex = 1
		-- Swallows the clicks, so the world under an open screen is never touched through it.
		overlay.Active = true
		overlay.Parent = frame
		dim = overlay

		local id = Theme.texture("GradientRadial")
		if id ~= "" then
			local image = Instance.new("ImageLabel")
			image.Name = "Wash"
			image.BackgroundTransparency = 1
			image.Image = id
			image.ImageTransparency = WASH_TRANSPARENCY
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Position = UDim2.fromScale(0.5, 0.5)
			image.Size = UDim2.fromScale(WASH_SCALE, WASH_SCALE)
			image.ZIndex = 2
			image.Parent = frame
			wash = image
		end

		for _, corner in ipairs(CORNERS) do
			local splat = Splat.new({
				Size = UDim2.fromOffset(corner.Size, corner.Size),
				Tint = Theme.Colors.Plate,
				Rotation = corner.Rotation,
				Transparency = CORNER_TRANSPARENCY,
				Position = corner.Position,
				ZIndex = 3,
				Name = "Corner",
				Parent = frame,
			})
			if splat ~= nil then
				table.insert(corners, splat)
			end
		end
		paint(chapter)
		showCorners()
	end

	if props.Chapter ~= nil then
		buildBackdrop(props.Chapter)
	end

	----------------------------------------------------------------
	-- Entrance and exit
	----------------------------------------------------------------

	local card: Card? = nil
	-- Bumped by every entrance and exit, so an exit caught by a new entrance never disables the screen.
	local exitToken = 0
	local exiting = false
	-- What runs once the screen is off: every caller of the exit in flight.
	local exitCallbacks: { () -> () } = {}

	-- Brings the backdrop's layers up from nothing on the way in, and takes them down to nothing on the way
	-- out; `onSettled` runs when the dim has arrived.
	local function fadeBackdrop(entering: boolean, onSettled: (() -> ())?)
		local overlay = dim
		if overlay ~= nil then
			if entering then
				Motion.set(overlay, { BackgroundTransparency = 1 })
			end
			Motion.to(overlay, { BackgroundTransparency = if entering then dimTarget() else 1 }, "Ui", onSettled)
		end
		local image = wash
		if image ~= nil then
			if entering then
				Motion.set(image, { ImageTransparency = 1 })
			end
			Motion.to(image, { ImageTransparency = if entering then WASH_TRANSPARENCY else 1 }, "Ui")
		end
		for _, splat in ipairs(corners) do
			if entering then
				Splat.fade(splat, 1)
			end
			Splat.fade(splat, if entering then CORNER_TRANSPARENCY else 1, "Ui")
		end
	end

	-- The player changed a setting while the screen is up: the dim, the blots and the text size follow.
	local following = UiPrefs.Changed:Connect(function()
		apply()
		showCorners()
		local overlay = dim
		if overlay ~= nil and gui.Enabled and not exiting then
			Motion.to(overlay, { BackgroundTransparency = dimTarget() }, "Ui")
		end
	end)
	trove:Add(function()
		following:Disconnect()
	end)

	trove:Add(function()
		exitToken += 1
		local overlay = dim
		if overlay ~= nil then
			Motion.cancel(overlay)
		end
		local image = wash
		if image ~= nil then
			Motion.cancel(image)
		end
		for _, splat in ipairs(corners) do
			Motion.cancel(splat)
		end
	end)

	gui.Parent = props.Parent or Players.LocalPlayer:WaitForChild("PlayerGui")

	local function getScale(_self: ScreenRoot): number
		return currentScale
	end

	local function setCard(_self: ScreenRoot, next: Card?)
		card = next
	end

	local function setChapter(_self: ScreenRoot, chapter: string)
		if backdrop == nil then
			buildBackdrop(chapter)
		else
			paint(chapter)
		end
	end

	local function playEnter(_self: ScreenRoot)
		exitToken += 1
		exiting = false
		-- The screen stays on: nothing waiting for it to go off is owed anything.
		table.clear(exitCallbacks)
		gui.Enabled = true
		showCorners()
		fadeBackdrop(true)
		local current = card
		if current ~= nil then
			current:PlayEnter()
		end
	end

	local function playExit(_self: ScreenRoot, onDone: (() -> ())?)
		if onDone ~= nil then
			table.insert(exitCallbacks, onDone)
		end
		-- Already on its way out: this caller waits for the same end, and the fade runs once.
		if exiting then
			return
		end
		exitToken += 1
		local token = exitToken
		local function finish()
			if token ~= exitToken then
				return
			end
			exiting = false
			gui.Enabled = false
			local callbacks = table.clone(exitCallbacks)
			table.clear(exitCallbacks)
			for _, callback in ipairs(callbacks) do
				callback()
			end
		end
		-- Nothing on screen to take away: a spring on an instance outside the DataModel never settles.
		if not gui.Enabled or not gui:IsDescendantOf(game) then
			finish()
			return
		end
		exiting = true
		local current = card
		if current ~= nil then
			fadeBackdrop(false)
			current:PlayExit(finish)
		elseif dim ~= nil then
			fadeBackdrop(false, finish)
		else
			finish()
		end
	end

	local function destroy(_self: ScreenRoot)
		trove:Destroy()
	end

	local object: ScreenRoot = {
		Instance = gui,
		Content = content,
		Scale = scale,
		GetScale = getScale,
		SetCard = setCard,
		SetChapter = setChapter,
		PlayEnter = playEnter,
		PlayExit = playExit,
		Destroy = destroy,
	}
	return object
end

return ScreenRoot
