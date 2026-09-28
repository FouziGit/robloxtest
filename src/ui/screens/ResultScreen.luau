--!strict
-- ResultScreen: the end-of-match takeover (D-147), over everything but the toasts (Layers.Result). No title
-- bar: the outcome itself is the title, across the top third of the screen (OutcomeBanner), and the world
-- goes darker than under a menu, washed in the outcome's colour -- gold for a victory, indigo for a defeat,
-- chalk for a draw. Under it, the card (ResultCard) the player screenshots, and at its foot "Play again",
-- where a pad's focus lands, and OK.
--
-- MenuController opens it on MatchEnded; the outcome is read from MatchController, which kept the last
-- payload the server sent. It closes itself after the mode's ResultSeconds, shown as a ring that empties
-- beside OK -- unless the player touches anything first: then the ring goes and the card waits
-- for them (the server's return to the hub still happens on time). "Play again" is the one-click loop: the
-- server keeps the wish while this screen is up and honours it the moment the match lets the player go.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local MatchConfig = require(Shared.Config.MatchConfig)
local Motion = require(script.Parent.Parent.Motion)
local OutcomeBanner = require(script.Parent.Parent.components.OutcomeBanner)
local ResultCard = require(script.Parent.Parent.components.ResultCard)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Sticker = require(script.Parent.Parent.components.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	-- Last MatchEnded payload: the server decided every number rendered here. joinQueue is the one-click
	-- loop (docs/JUICE_PLAN.md phase 8, item 2).
	MatchController: { getLastOutcome: () -> Types.MatchOutcome?, joinQueue: (modeId: string) -> () },
	OnClose: () -> (),
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen, args: any?) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type Destroyable = { Destroy: (self: any) -> () }

local ResultScreen = {}

local FALLBACK_RESULT_SECONDS = MatchConfig.Modes[MatchConfig.ModeOrder[1]].ResultSeconds
-- The world goes darker than under a menu: this ink over the backdrop's own dim (0.35) makes it 0.25.
local DEEPEN_TRANSPARENCY = 0.25 / 0.35
-- The outcome takes the top of the screen; the card the rest, as wide as a readable measure allows.
local BANNER_SHARE = 0.3
local CARD_SHARE = Vector2.new(0.94, 0.68)
local CARD_WIDTH = 760
local CARD_ELEVATION = 8
local ENTER_SCALE = 0.88
local RING_SIZE = 40
local RING_STROKE = 3
-- The counts and the coins wait for the card to land.
local CELEBRATE_DELAY = 0.35
local RING_TICK_SECONDS = 1
local TITLE_KEYS = { Victory = "match.victory", Defeat = "match.defeat", Draw = "match.draw" }
-- What counts as the player touching the card: a click, a tap, a key, a button.
local PRESSES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.Touch] = true,
	[Enum.UserInputType.Keyboard] = true,
}
local GAMEPAD_PREFIX = "Gamepad"

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

local function outcomeOf(outcome: Types.MatchOutcome): OutcomeBanner.Outcome
	if outcome.Draw then
		return "Draw"
	end
	return if outcome.Won then "Victory" else "Defeat"
end

local function resultSeconds(modeId: string): number
	local def = MatchConfig.Modes[modeId]
	if def == nil then
		return FALLBACK_RESULT_SECONDS
	end
	return math.max(1, def.ResultSeconds)
end

local function isPress(input: InputObject): boolean
	local kind = input.UserInputType
	return PRESSES[kind] == true or string.sub(kind.Name, 1, #GAMEPAD_PREFIX) == GAMEPAD_PREFIX
end

function ResultScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local autoClose: thread? = nil
	-- Bumped whenever the screen opens or closes, so a delayed celebration or ring tick never lands on a
	-- card that has moved on.
	local session = 0

	local root = ScreenRoot.new({
		Name = "ResultScreen",
		DisplayOrder = Theme.Layers.Result,
		Chapter = "Draw",
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	-- The extra ink over the whole viewport, the notch included, under the takeover.
	local deepen = Instance.new("Frame")
	deepen.Name = "Deepen"
	deepen.BackgroundColor3 = Theme.Colors.Plate
	deepen.BackgroundTransparency = 1
	deepen.BorderSizePixel = 0
	deepen.Size = UDim2.fromScale(1, 1)
	deepen.ZIndex = 0
	deepen.Parent = root.Instance
	trove:Add(function()
		Motion.cancel(deepen)
	end)

	local takeover = Instance.new("Frame")
	takeover.Name = "Takeover"
	takeover.BackgroundTransparency = 1
	takeover.Size = UDim2.fromScale(1, 1)
	takeover.Parent = root.Content
	local entrance = Instance.new("UIScale")
	entrance.Name = "Entrance"
	entrance.Parent = takeover
	trove:Add(function()
		Motion.cancel(entrance)
	end)

	local bannerArea = Instance.new("Frame")
	bannerArea.Name = "Banner"
	bannerArea.BackgroundTransparency = 1
	bannerArea.Size = UDim2.fromScale(1, BANNER_SHARE)
	bannerArea.Parent = takeover
	local banner = OutcomeBanner.new(bannerArea)
	own(trove, banner)

	local card = Sticker.new({
		Kind = "Card",
		Fill = Theme.Colors.Panel,
		Corner = UDim.new(0, Theme.Sizes.CornerPanel),
		Elevation = CARD_ELEVATION,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, BANNER_SHARE),
		Size = UDim2.fromScale(CARD_SHARE.X, CARD_SHARE.Y),
		Name = "Card",
		Parent = takeover,
	})
	own(trove, card)
	card.Face.ClipsDescendants = true
	-- A readable measure with a pointer; all of the width on a phone, which needs it.
	local measure = Instance.new("UISizeConstraint")
	measure.Parent = card.Instance
	trove:Add(Theme.bindScale(function()
		measure.MaxSize = if Theme.touchOnly()
			then Vector2.new(math.huge, math.huge)
			else Vector2.new(CARD_WIDTH, math.huge)
	end))

	-- The buttons carry the touch minimum, which follows the viewport.
	local function footerHeight(): number
		return Theme.Sizes.PaddingSmall + Theme.Sizes.Padding + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
	end
	local rowsArea = Instance.new("Frame")
	rowsArea.Name = "Body"
	rowsArea.BackgroundTransparency = 1
	rowsArea.Parent = card.Face
	local rows = ResultCard.new(deps.Localize, rowsArea)
	own(trove, rows)
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Parent = card.Face
	local footerPadding = Instance.new("UIPadding")
	footerPadding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	footerPadding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	footerPadding.PaddingBottom = UDim.new(0, Theme.Sizes.Padding)
	footerPadding.Parent = footer
	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	footerLayout.Parent = footer
	trove:Add(Theme.bindScale(function()
		local height = footerHeight()
		footer.Size = UDim2.new(1, 0, 0, height)
		rowsArea.Size = UDim2.new(1, 0, 1, -height)
	end))

	-- The auto-close ring: what is left of the wait, emptying once a second (ThemeConfig ResultRing).
	local ring: GuiObject
	local ringGradient = Theme.gradient("ResultRing")
	local ringId = Theme.texture("SealRing")
	if ringId ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = ringId
		image.ImageColor3 = Theme.Colors.Accent
		image.BackgroundTransparency = 1
		ringGradient.Parent = image
		ring = image
	else
		-- Not uploaded: the ring is a stroke, and the stroke carries the gradient.
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		Theme.corner(frame, Theme.Pill)
		ringGradient.Parent = Theme.stroke(frame, "Accent", RING_STROKE)
		ring = frame
	end
	ring.Name = "AutoClose"
	ring.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
	ring.LayoutOrder = 1
	ring.Parent = footer

	local function leave()
		screen:Close()
		deps.OnClose()
	end

	-- It closes the card; the return to the hub is the server's, on time whatever the player does, so the
	-- button promises no more than it does.
	local okButton = Button.new({
		Name = "Ok",
		Text = t("common.ok"),
		Variant = "Secondary",
		LayoutOrder = 2,
		Parent = footer,
		OnClick = leave,
	})
	own(trove, okButton)

	-- The loop: one click from the result back into the queue, without a hub to cross.
	local againButton = Button.new({
		Name = "Again",
		Text = t("match.again"),
		Variant = "Primary",
		Wide = true,
		LayoutOrder = 3,
		Parent = footer,
		OnClick = function()
			local outcome = deps.MatchController.getLastOutcome()
			if outcome ~= nil then
				deps.MatchController.joinQueue(outcome.ModeId)
			end
			leave()
		end,
	})
	own(trove, againButton)

	local function cancelAutoClose()
		local timer = autoClose
		if timer ~= nil then
			task.cancel(timer)
			autoClose = nil
		end
	end
	trove:Add(cancelAutoClose)

	local function tickRing(mine: number, deadline: number, total: number)
		if session ~= mine or autoClose == nil then
			return
		end
		local left = math.max(0, deadline - os.clock())
		ringGradient.Transparency = Theme.ringTransparency(left / total)
		if left > 0 then
			task.delay(math.min(RING_TICK_SECONDS, left), tickRing, mine, deadline, total)
		end
	end

	-- The player touched something: the card is theirs now, and waits for them.
	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if screen.Visible and autoClose ~= nil and isPress(input) then
			cancelAutoClose()
			ring.Visible = false
		end
	end)

	----------------------------------------------------------------
	-- The takeover's own entrance and exit (ScreenRoot plays them)
	----------------------------------------------------------------

	local exitGroup: CanvasGroup? = nil
	local exitToken = 0
	local function restoreFromExit()
		local group = exitGroup
		exitGroup = nil
		if group ~= nil then
			Motion.cancel(group)
			takeover.Parent = root.Content
			group:Destroy()
		end
	end
	trove:Add(function()
		exitToken += 1
		restoreFromExit()
	end)

	root:SetCard({
		PlayEnter = function()
			exitToken += 1
			restoreFromExit()
			Motion.set(entrance, { Scale = ENTER_SCALE })
			Motion.to(entrance, { Scale = 1 }, "UiPop")
		end,
		-- The takeover fades as one piece in a transient group, then goes back where it was.
		PlayExit = function(_self: any, onDone: () -> ())
			if exitGroup ~= nil or not takeover:IsDescendantOf(game) then
				onDone()
				return
			end
			exitToken += 1
			local token = exitToken
			local group = Instance.new("CanvasGroup")
			group.Name = "Exit"
			group.BackgroundTransparency = 1
			group.Size = UDim2.fromScale(1, 1)
			group.Parent = root.Content
			takeover.Parent = group
			exitGroup = group
			Motion.to(group, { GroupTransparency = 1 }, "UiExit", function()
				if exitToken == token then
					restoreFromExit()
					onDone()
				end
			end)
			if not UiPrefs.reducedMotion() then
				Motion.to(entrance, { Scale = ENTER_SCALE }, "UiExit")
			end
		end,
	})

	-- The XP this match paid can land after MatchEnded -- they are two pushes -- so the card re-reads the
	-- profile while it is open instead of trusting the order the two arrive in.
	trove:Connect(deps.ClientData.Changed, function(section: string)
		local outcome = deps.MatchController.getLastOutcome()
		if screen.Visible and outcome ~= nil and (section == "*" or section == "Progression") then
			rows:ShowProgress(outcome, deps.ClientData.get())
		end
	end)

	local function focus()
		if not UserInputService.GamepadEnabled then
			return
		end
		GuiService.SelectedObject = if againButton:IsDisabled() then okButton.Instance else againButton.Instance
	end

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		local outcome = deps.MatchController.getLastOutcome()
		if outcome == nil then
			-- Nothing to show (no match played yet). Handing control back is deferred so MenuController
			-- finishes its open first and does not leave gameplay input suspended behind a hidden screen.
			task.defer(deps.OnClose)
			return
		end
		self.Visible = true
		session += 1
		local mine = session
		local kind: OutcomeBanner.Outcome = outcomeOf(outcome)
		root:SetChapter(kind)
		banner:Show(kind, t(TITLE_KEYS[kind]))
		rows:Render(outcome)
		rows:ShowProgress(outcome, deps.ClientData.get())
		againButton:SetDisabled(MatchConfig.Modes[outcome.ModeId] == nil)
		root:PlayEnter()
		Motion.set(deepen, { BackgroundTransparency = 1 })
		Motion.to(deepen, { BackgroundTransparency = DEEPEN_TRANSPARENCY }, "Ui")
		focus()
		deps.SoundController.play("UiOpen")
		task.delay(CELEBRATE_DELAY, function()
			if session == mine then
				rows:Celebrate(outcome)
			end
		end)

		cancelAutoClose()
		local total = resultSeconds(outcome.ModeId)
		ring.Visible = true
		autoClose = task.delay(total, function()
			autoClose = nil
			if not screen.Visible then
				return
			end
			leave()
		end)
		tickRing(mine, os.clock() + total, total)
	end

	local function close(self: Screen)
		cancelAutoClose()
		if not self.Visible then
			return
		end
		self.Visible = false
		session += 1
		rows:Stop()
		local selected = GuiService.SelectedObject
		if selected ~= nil and selected:IsDescendantOf(takeover) then
			GuiService.SelectedObject = nil
		end
		Motion.to(deepen, { BackgroundTransparency = 1 }, "Ui")
		root:PlayExit(function()
			banner:Clear()
		end)
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		session += 1
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = close,
		Destroy = destroy,
	}
	return screen
end

return ResultScreen
