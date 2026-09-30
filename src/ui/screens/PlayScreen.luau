--!strict
-- PlayScreen: the queue screen (D-147), in the yellow Play chapter. One mode card per MatchConfig.ModeOrder
-- entry, side by side: a picture of the fight (the number of fighters on each side IS the picture), the mode's
-- name and its "Ranked" tag, its rule, and one button. On a private server a player bought, where no match is
-- ranked (E4-S4), a ranked mode's card says so under its name instead of wearing the tag. A newcomer's ranked card
-- also says that their matches are the quick duel for now, why, and how far off ranked is (E10-S7, Pure/RankedGate),
-- from their own profile. While the player waits, their card breathes a yellow ring and counts the wait in big
-- numbers, the other card is veiled, and the way out is a plain Leave -- leaving a queue is no danger. When the
-- server gives up finding a match, the card says so and offers a retry or the way back to the hub, instead of a lone
-- error line.
--
-- The screen never touches the queue remotes itself: MatchController owns them, so a single JoinQueue /
-- LeaveQueue is sent per press and every number shown here is server-authored. The waited seconds are
-- advanced locally once a second from the last server value, on task.delay, only while the screen is up.
--
-- The 1v1 card also carries the practice duel against a Forger (E10-S6, MatchConfig.Spar): once the server
-- offers it -- after a wait alone in the queue -- the card's rule becomes its pitch, the players line the paid
-- spars left today, and a Spar button stands before the way out of the queue; while one is fought, the rule says
-- a real opponent takes over at the next break, and Leave practice walks out of it. The screen only shows what
-- SparChanged says and asks MatchController; the server decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local MatchConfig = require(Shared.Config.MatchConfig)
local Motion = require(script.Parent.Parent.Motion)
local Panel = require(script.Parent.Parent.components.Panel)
local RankedGate = require(Shared.Pure.RankedGate)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Splat = require(script.Parent.Parent.components.Splat)
local Sticker = require(script.Parent.Parent.components.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	-- Queue state and intents. The screen reads the snapshot and asks for a join / leave; the server decides.
	MatchController: {
		getQueue: () -> Types.QueueSnapshot,
		rankedHere: () -> boolean,
		joinQueue: (modeId: string) -> (),
		leaveQueue: () -> (),
		QueueChanged: any,
		getSpar: () -> Types.SparSnapshot,
		startSpar: () -> (),
		leaveSpar: () -> (),
		SparChanged: any,
	},
	-- Every server message, as it arrives: the one this screen waits for is the queue giving up.
	HudController: { Notified: any },
	OnClose: () -> (),
	OnNavigate: (id: string, args: any?) -> (),
	OnBack: () -> (),
	CanGoBack: () -> boolean,
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen, args: any?) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type State = "Idle" | "Queued" | "Veiled" | "TimedOut"
type Card = {
	ModeId: string,
	Join: Button.Button,
	Leave: Button.Button,
	Retry: Button.Button,
	Fighters: Frame,
	Clock: Frame,
	Timer: TextLabel,
	Waiting: TextLabel,
	-- A ranked mode's word to a newcomer: the quick duel, and what ranked still asks of them.
	Gate: TextLabel?,
	Normal: Frame,
	TimedOut: Frame,
	Veil: Frame,
	Ring: UIStroke,
	StopBreath: (() -> ())?,
	Rule: TextLabel,
	RuleText: string,
	-- The practice duel's two buttons, on the card of the queue it is offered in.
	Spar: Button.Button?,
	LeaveSpar: Button.Button?,
}
type Destroyable = { Destroy: (self: any) -> () }

local PlayScreen = {}

local CHAPTER = "Play"
local TIMED_OUT_KEY = "queue.timedOut"
local CARD_ELEVATION = 6
local CARD_PADDING = 16
local NAME_SIZE = 30
local TAG_SIZE = 14
local TAG_HEIGHT = 24
-- The "Ranked" tag is the Menu's ribbon lying flat: ink, the sheet's word, corners of 8.
local TAG_CORNER = 8
-- Above and below the private server's notice, whose words may take two lines.
local NOTICE_PADDING_Y = 4
local RULE_SIZE = 16
local STATE_TITLE_SIZE = 26
local CROSS_SIZE = 40
-- A fighter on the picture, and the blot of their side behind them (the blot's ink reaches about two thirds
-- of its plane, so it is drawn larger than the fighters it backs).
local FIGHTER_SIZE = 28
local FIGHTER_GAP = 4
local SIDE_SPLAT_SCALE = 1.6
local SIDE_SHARE = 0.4
-- The ring of the card being waited on: the primary yellow, breathing.
local RING_THICKNESS = 4
local RING_BREATH = 0.5
local RING_HOLD = 0.2
local VEIL_TRANSPARENCY = 0.5
local TICK_SECONDS = 1
local SPAR = MatchConfig.Spar

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

local function label(name: string, font: Font, size: number, color: Color3, order: number, parent: Instance): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 0, size + 6)
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.LayoutOrder = order
	text.Text = ""
	text.Parent = parent
	return text
end

local function list(frame: Frame, direction: Enum.FillDirection, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
	return layout
end

local function blank(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- The width of `count` fighters side by side.
local function fightersWidth(count: number): number
	return count * FIGHTER_SIZE + (count - 1) * FIGHTER_GAP
end

-- Every side's blot is the size of the largest team's, so the cards differ by their fighters alone: a lone
-- duellist's blot, sized to them, was hardly larger than their disc and the 1v1 card read as empty.
local function blotSize(): number
	local largest = 1
	for _, mode in ipairs(MatchConfig.ModeOrder) do
		largest = math.max(largest, MatchConfig.Modes[mode].TeamSize)
	end
	return fightersWidth(largest) * SIDE_SPLAT_SCALE
end

-- One side of the fight: a blot of its colour, and one disc per fighter on it. Ours are cyan and outlined in
-- ink; theirs are ink, ringed in the sheet (ink on ink is nothing).
local function side(parent: Instance, order: number, count: number, ours: boolean): Frame
	local frame = blank(if ours then "Allies" else "Opponents", parent)
	frame.Size = UDim2.fromScale(SIDE_SHARE, 1)
	frame.LayoutOrder = order
	local fill = if ours then Theme.Colors.Ally else Theme.Colors.Plate
	local width = fightersWidth(count)
	local blot = blotSize()
	Splat.new({
		Size = UDim2.fromOffset(blot, blot),
		Tint = fill,
		Rotation = Splat.rotation(if ours then 2 else 5),
		Parent = frame,
	})
	local group = blank("Fighters", frame)
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromOffset(width, FIGHTER_SIZE)
	group.ZIndex = 2
	local layout = list(group, Enum.FillDirection.Horizontal, FIGHTER_GAP)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	for index = 1, count do
		local disc = Instance.new("Frame")
		disc.Name = "Fighter"
		disc.BorderSizePixel = 0
		disc.BackgroundColor3 = fill
		disc.Size = UDim2.fromOffset(FIGHTER_SIZE, FIGHTER_SIZE)
		disc.LayoutOrder = index
		disc.ZIndex = 2
		Theme.corner(disc, Theme.Pill)
		Theme.stroke(disc, if ours then "Accent" else "PanelRaised", Theme.Sizes.StrokeThin)
		disc.Parent = group
	end
	return frame
end

function PlayScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local rankedHere = deps.MatchController.rankedHere()
	local screen: Screen
	local cards: { Card } = {}
	-- The mode the player last waited in, and the one the server gave up on.
	local lastMode: string? = nil
	local timedOut: string? = nil
	local ticking = false
	-- Local clock for the waited seconds: base value from the server plus the time since it arrived.
	local waitedBase = 0
	local waitedAt = os.clock()

	local root = ScreenRoot.new({
		Name = "PlayScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("queue.title"),
		Chapter = CHAPTER,
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		OnBack = deps.OnBack,
		ShowBack = deps.CanGoBack,
		Localize = deps.Localize,
		Parent = root.Content,
	})
	own(trove, panel)
	root:SetCard(panel)

	-- The cards fill the card's content, side by side; nothing scrolls.
	panel:SetContentMode("Fill")
	local content = panel.Content
	local deck = blank("Modes", content)
	deck.Size = UDim2.fromScale(1, 1)
	list(deck, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)

	local function waitedSeconds(): number
		return math.max(0, math.floor(waitedBase + (os.clock() - waitedAt)))
	end

	local function clockText(seconds: number): string
		return t("time.minutesSeconds", {
			minutes = math.floor(seconds / 60),
			seconds = string.format("%02d", seconds % 60),
		})
	end

	local function join(modeId: string)
		timedOut = nil
		deps.MatchController.joinQueue(modeId)
	end

	local function buildCard(modeId: string, def: MatchConfig.ModeDef, order: number): Card
		local holder = blank(modeId, deck)
		holder.Size = UDim2.new(1 / #MatchConfig.ModeOrder, -Theme.Sizes.Gap / 2, 1, 0)
		holder.LayoutOrder = order
		local sticker = Sticker.new({
			Kind = "Pressable",
			Fill = Theme.Colors.PanelRaised,
			Lip = Theme.lip("Secondary"),
			Corner = UDim.new(0, Theme.Sizes.CornerTile),
			Elevation = CARD_ELEVATION,
			Parent = holder,
		})
		own(trove, sticker)
		local face = sticker.Face

		local ringFrame = blank("Waiting", face)
		ringFrame.Size = UDim2.fromScale(1, 1)
		ringFrame.ZIndex = 5
		Theme.corner(ringFrame, UDim.new(0, Theme.Sizes.CornerTile))
		local ring = Theme.stroke(ringFrame, "Primary", RING_THICKNESS)
		ring.Enabled = false

		local function padded(name: string): Frame
			local frame = blank(name, face)
			frame.Size = UDim2.fromScale(1, 1)
			frame.ZIndex = 2
			local padding = Instance.new("UIPadding")
			padding.PaddingTop = UDim.new(0, CARD_PADDING)
			padding.PaddingBottom = UDim.new(0, CARD_PADDING)
			padding.PaddingLeft = UDim.new(0, CARD_PADDING)
			padding.PaddingRight = UDim.new(0, CARD_PADDING)
			padding.Parent = frame
			return frame
		end

		-- What the card shows: the picture (or the clock), the name and its tag, the rule, the button.
		local normal = padded("Normal")
		list(normal, Enum.FillDirection.Vertical, Theme.Sizes.PaddingSmall)

		local stage = blank("Stage", normal)
		stage.Size = UDim2.fromScale(1, 0)
		stage.LayoutOrder = 1
		local stageFlex = Instance.new("UIFlexItem")
		stageFlex.FlexMode = Enum.UIFlexMode.Fill
		stageFlex.Parent = stage

		local fighters = blank("Fight", stage)
		fighters.Size = UDim2.fromScale(1, 1)
		local fightLayout = list(fighters, Enum.FillDirection.Horizontal, 0)
		fightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		fightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		side(fighters, 1, def.TeamSize, true)
		local cross = Instance.new("TextLabel")
		cross.Name = "Versus"
		cross.BackgroundTransparency = 1
		cross.Size = UDim2.fromScale(1 - SIDE_SHARE * 2, 1)
		cross.LayoutOrder = 2
		cross.FontFace = Theme.Fonts.Title
		cross.TextSize = CROSS_SIZE
		cross.TextColor3 = Theme.Colors.Text
		cross.Text = Theme.Glyphs.Close
		cross.ZIndex = 3
		cross.Parent = fighters
		side(fighters, 3, def.TeamSize, false)

		-- While waiting: the wait in big numbers, and how many are in the queue.
		local clock = blank("Clock", stage)
		clock.Size = UDim2.fromScale(1, 1)
		clock.Visible = false
		local clockLayout = list(clock, Enum.FillDirection.Vertical, 0)
		clockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		clockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		local timer = label("Timer", Theme.Fonts.Numeric, Theme.Sizes.NumScore, Theme.Colors.Text, 1, clock)
		timer.TextXAlignment = Enum.TextXAlignment.Center
		local waiting = label("Players", Theme.Fonts.Body, RULE_SIZE, Theme.Colors.TextMuted, 2, clock)
		waiting.TextXAlignment = Enum.TextXAlignment.Center

		local heading = blank("Heading", normal)
		heading.Size = UDim2.new(1, 0, 0, NAME_SIZE + 6)
		heading.LayoutOrder = 2
		local headingLayout = list(heading, Enum.FillDirection.Horizontal, Theme.Sizes.PaddingSmall)
		headingLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		local name = label("Name", Theme.Fonts.Title, NAME_SIZE, Theme.Colors.Text, 1, heading)
		name.AutomaticSize = Enum.AutomaticSize.X
		name.Size = UDim2.fromScale(0, 1)
		name.Text = t(def.NameKey)
		if def.Ranked and rankedHere then
			local tag = Instance.new("TextLabel")
			tag.Name = "Ranked"
			tag.BorderSizePixel = 0
			tag.BackgroundColor3 = Theme.Colors.Plate
			tag.AutomaticSize = Enum.AutomaticSize.X
			tag.Size = UDim2.fromOffset(0, TAG_HEIGHT)
			tag.LayoutOrder = 2
			tag.FontFace = Theme.Fonts.Label
			tag.TextSize = TAG_SIZE
			tag.TextColor3 = Theme.Colors.PanelRaised
			tag.Text = t("queue.ranked")
			Theme.corner(tag, TAG_CORNER)
			local tagPadding = Instance.new("UIPadding")
			tagPadding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingSmall)
			tagPadding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingSmall)
			tagPadding.Parent = tag
			tag.Parent = heading
		end
		if def.Ranked and not rankedHere then
			-- The tag's own ink and word, as wide as the card and wrapped: the sentence is longer than a tag.
			local notice = Instance.new("TextLabel")
			notice.Name = "Unranked"
			notice.BorderSizePixel = 0
			notice.BackgroundColor3 = Theme.Colors.Plate
			notice.AutomaticSize = Enum.AutomaticSize.Y
			notice.Size = UDim2.new(1, 0, 0, TAG_HEIGHT)
			notice.LayoutOrder = 3
			notice.FontFace = Theme.Fonts.Label
			notice.TextSize = TAG_SIZE
			notice.TextColor3 = Theme.Colors.PanelRaised
			notice.TextWrapped = true
			notice.TextXAlignment = Enum.TextXAlignment.Left
			notice.Text = t("queue.unranked")
			Theme.corner(notice, TAG_CORNER)
			local noticePadding = Instance.new("UIPadding")
			noticePadding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingSmall)
			noticePadding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingSmall)
			noticePadding.PaddingTop = UDim.new(0, NOTICE_PADDING_Y)
			noticePadding.PaddingBottom = UDim.new(0, NOTICE_PADDING_Y)
			noticePadding.Parent = notice
			notice.Parent = normal
		end

		local rule = label("Rule", Theme.Fonts.Body, RULE_SIZE, Theme.Colors.TextMuted, 4, normal)
		-- One round decides, or the first to so many wins: never "first to 1 rounds" (the rule's two forms).
		-- Kept: the practice duel's pitch takes the line while it is offered (E10-S6), and gives it back.
		local ruleText = t("queue.rule", { rounds = def.RoundsToWin })
		rule.Text = ruleText

		-- Wrapped under the rule, as tall as its words: written by render, from the profile. Only where the card is
		-- ranked: on a server that is not, the notice above already says no match is.
		local gate: TextLabel? = nil
		if def.Ranked and rankedHere then
			local line = label("Gate", Theme.Fonts.Body, RULE_SIZE, Theme.Colors.TextMuted, 5, normal)
			line.TextWrapped = true
			line.TextTruncate = Enum.TextTruncate.None
			line.AutomaticSize = Enum.AutomaticSize.Y
			line.Visible = false
			gate = line
		end

		local actions = blank("Actions", normal)
		actions.AutomaticSize = Enum.AutomaticSize.Y
		actions.Size = UDim2.fromScale(1, 0)
		actions.LayoutOrder = 6
		-- Two buttons side by side do not fit a phone's card: the second goes under the first.
		list(actions, Enum.FillDirection.Horizontal, Theme.Sizes.Gap).Wraps = true

		-- The practice duel, first in the row on the card of the queue it is offered in.
		local sparButton: Button.Button? = nil
		local leaveSparButton: Button.Button? = nil
		if modeId == SPAR.QueueModeId then
			local offer = Button.new({
				Text = t("spar.start"),
				Variant = "Primary",
				Icon = "Play",
				Wide = true,
				LayoutOrder = 0,
				Parent = actions,
				Name = "Spar",
				OnClick = function()
					deps.MatchController.startSpar()
				end,
			})
			own(trove, offer)
			offer.Instance.Visible = false
			local out = Button.new({
				Text = t("spar.leave"),
				Variant = "Secondary",
				Icon = "Cross",
				LayoutOrder = 0,
				Parent = actions,
				Name = "LeaveSpar",
				OnClick = function()
					deps.MatchController.leaveSpar()
				end,
			})
			own(trove, out)
			out.Instance.Visible = false
			sparButton, leaveSparButton = offer, out
		end

		local joinButton = Button.new({
			Text = t("queue.join"),
			Variant = "Primary",
			Wide = true,
			LayoutOrder = 1,
			Parent = actions,
			OnClick = function()
				join(modeId)
			end,
		})
		own(trove, joinButton)
		local leaveButton = Button.new({
			Text = t("queue.leave"),
			Variant = "Secondary",
			Icon = "Cross",
			Wide = true,
			LayoutOrder = 2,
			Parent = actions,
			OnClick = function()
				deps.MatchController.leaveQueue()
			end,
		})
		own(trove, leaveButton)
		leaveButton.Instance.Visible = false

		-- The server found nobody: say so, and offer another try or the way back to the hub.
		local stateCard = padded("TimedOut")
		stateCard.Visible = false
		local stateLayout = list(stateCard, Enum.FillDirection.Vertical, Theme.Sizes.Gap)
		stateLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		local stateTitle = label("Title", Theme.Fonts.Title, STATE_TITLE_SIZE, Theme.Colors.Text, 1, stateCard)
		stateTitle.TextWrapped = true
		stateTitle.AutomaticSize = Enum.AutomaticSize.Y
		stateTitle.TextTruncate = Enum.TextTruncate.None
		stateTitle.Text = t("queue.timedOut.title")
		local hint = label("Hint", Theme.Fonts.Body, Theme.Sizes.TextBody, Theme.Colors.TextMuted, 2, stateCard)
		hint.TextWrapped = true
		hint.AutomaticSize = Enum.AutomaticSize.Y
		hint.TextTruncate = Enum.TextTruncate.None
		hint.Text = t("queue.timedOut.hint")
		local stateActions = blank("Actions", stateCard)
		stateActions.AutomaticSize = Enum.AutomaticSize.Y
		stateActions.Size = UDim2.fromScale(1, 0)
		stateActions.LayoutOrder = 3
		local stateRow = list(stateActions, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)
		stateRow.Wraps = true
		local retryButton = Button.new({
			Text = t("common.retry"),
			Variant = "Primary",
			LayoutOrder = 1,
			Parent = stateActions,
			OnClick = function()
				join(modeId)
			end,
		})
		own(trove, retryButton)
		local hubButton = Button.new({
			Text = t("portal.return.name"),
			Variant = "Secondary",
			LayoutOrder = 2,
			Parent = stateActions,
			OnClick = function()
				screen:Close()
				deps.OnClose()
			end,
		})
		own(trove, hubButton)

		-- Over a card that is not the one waited on: the chalk veil, which lets nothing through.
		local veil = blank("Veil", face)
		veil.BackgroundColor3 = Theme.Colors.Chalk
		veil.BackgroundTransparency = VEIL_TRANSPARENCY
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = 4
		veil.Visible = false
		Theme.corner(veil, UDim.new(0, Theme.Sizes.CornerTile))

		return {
			ModeId = modeId,
			Join = joinButton,
			Leave = leaveButton,
			Retry = retryButton,
			Fighters = fighters,
			Clock = clock,
			Timer = timer,
			Waiting = waiting,
			Gate = gate,
			Normal = normal,
			TimedOut = stateCard,
			Veil = veil,
			Ring = ring,
			StopBreath = nil,
			Rule = rule,
			RuleText = ruleText,
			Spar = sparButton,
			LeaveSpar = leaveSparButton,
		}
	end

	for index, modeId in ipairs(MatchConfig.ModeOrder) do
		local def = MatchConfig.Modes[modeId]
		if def ~= nil then
			table.insert(cards, buildCard(modeId, def, index))
		end
	end

	local function stateOf(card: Card, queue: Types.QueueSnapshot): State
		if timedOut == card.ModeId and not queue.Queued then
			return "TimedOut"
		elseif queue.Queued and queue.ModeId == card.ModeId then
			return "Queued"
		elseif queue.Queued then
			return "Veiled"
		end
		return "Idle"
	end

	local function setBreathing(card: Card, on: boolean)
		local stop = card.StopBreath
		if on and stop == nil and screen.Visible then
			card.Ring.Enabled = true
			card.StopBreath = Motion.loop(
				card.Ring,
				{ Transparency = 0 },
				{ Transparency = RING_BREATH },
				"Ui",
				RING_HOLD
			)
		elseif not on then
			if stop ~= nil then
				card.StopBreath = nil
				stop()
			end
			card.Ring.Enabled = false
		end
	end

	-- Whether `card` shows the practice duel's offer: its queue waited in, and the server offering it.
	local function offering(card: Card, queue: Types.QueueSnapshot): boolean
		return card.Spar ~= nil
			and queue.Queued
			and queue.ModeId == card.ModeId
			and deps.MatchController.getSpar().Offered
	end

	-- What the paid spars left today come to, under the offer.
	local function paidText(): string
		local spar = deps.MatchController.getSpar()
		if spar.PaidLeft > 0 then
			return t("spar.paidLeft", { left = spar.PaidLeft, total = spar.PaidPerDay })
		end
		return t("spar.noneLeft")
	end

	local function refreshClock()
		local queue = deps.MatchController.getQueue()
		for _, card in ipairs(cards) do
			if queue.Queued and queue.ModeId == card.ModeId then
				card.Timer.Text = clockText(waitedSeconds())
				card.Waiting.Text = if offering(card, queue)
					then paidText()
					else t("queue.waiting", { queued = queue.QueuedCount, needed = queue.NeededCount })
			end
		end
	end

	-- Why a newcomer's matches are the quick duel and how far ranked is, or nothing once they are ranked.
	local function gateText(): string?
		local data = deps.ClientData.get()
		if data == nil then
			return nil
		end
		local rules = MatchConfig.Newcomer
		local status = RankedGate.status(data.Stats.MatchesPlayed, data.Progression.Level, rules)
		local params = {
			level = rules.MinLevel,
			current = data.Progression.Level,
			count = rules.MinMatches,
			played = data.Stats.MatchesPlayed,
		}
		if status.Ranked then
			return nil
		elseif status.LevelsLeft > 0 and status.MatchesLeft > 0 then
			return t("queue.gate.both", params)
		elseif status.LevelsLeft > 0 then
			return t("queue.gate.level", params)
		end
		return t("queue.gate.matches", params)
	end

	local function render()
		local text = gateText()
		for _, card in ipairs(cards) do
			local gate = card.Gate
			if gate ~= nil then
				gate.Text = text or ""
				gate.Visible = text ~= nil
			end
		end
		local queue = deps.MatchController.getQueue()
		for _, card in ipairs(cards) do
			local state = stateOf(card, queue)
			card.Normal.Visible = state ~= "TimedOut"
			card.TimedOut.Visible = state == "TimedOut"
			card.Fighters.Visible = state ~= "Queued"
			card.Clock.Visible = state == "Queued"
			card.Veil.Visible = state == "Veiled"
			card.Join.Instance.Visible = state ~= "Queued"
			card.Leave.Instance.Visible = state == "Queued"
			card.Join:SetDisabled(state == "Veiled", "Full")
			setBreathing(card, state == "Queued")
			local offer = offering(card, queue)
			local sparring = card.LeaveSpar ~= nil and deps.MatchController.getSpar().Sparring
			local sparButton, leaveSparButton = card.Spar, card.LeaveSpar
			if sparButton ~= nil and leaveSparButton ~= nil then
				sparButton.Instance.Visible = offer
				leaveSparButton.Instance.Visible = sparring
			end
			card.Rule.Text = if sparring then t("spar.sparring") elseif offer then t("spar.pitch") else card.RuleText
		end
		refreshClock()
	end

	-- The first thing a gamepad can press: the retry, the practice duel offered or fought, the way out of the
	-- queue, or the first join.
	local function focusTarget(): GuiObject?
		local queue = deps.MatchController.getQueue()
		for _, card in ipairs(cards) do
			local state = stateOf(card, queue)
			local sparButton, leaveSparButton = card.Spar, card.LeaveSpar
			if state == "TimedOut" then
				return card.Retry.Instance
			elseif leaveSparButton ~= nil and deps.MatchController.getSpar().Sparring then
				return leaveSparButton.Instance
			elseif sparButton ~= nil and offering(card, queue) then
				return sparButton.Instance
			elseif state == "Queued" then
				return card.Leave.Instance
			end
		end
		local first = cards[1]
		return if first ~= nil then first.Join.Instance else nil
	end

	local function tick()
		if not screen.Visible or not deps.MatchController.getQueue().Queued then
			ticking = false
			return
		end
		refreshClock()
		task.delay(TICK_SECONDS, tick)
	end

	-- The tick only runs while the screen is up and the player is actually waiting in a queue.
	local function syncTick()
		if ticking or not screen.Visible or not deps.MatchController.getQueue().Queued then
			return
		end
		ticking = true
		task.delay(TICK_SECONDS, tick)
	end

	local function adopt(queue: Types.QueueSnapshot)
		waitedBase = queue.WaitedSeconds
		waitedAt = os.clock()
		if queue.Queued then
			lastMode = queue.ModeId
			timedOut = nil
		end
		render()
		syncTick()
	end

	trove:Connect(deps.MatchController.QueueChanged, adopt)
	-- A level or a match gained moves the newcomer's line, and the last one takes it away.
	trove:Connect(deps.ClientData.Changed, function()
		if screen.Visible then
			render()
		end
	end)
	trove:Connect(deps.MatchController.SparChanged, function()
		render()
	end)
	trove:Connect(deps.HudController.Notified, function(key: string)
		if key == TIMED_OUT_KEY and lastMode ~= nil then
			timedOut = lastMode
			render()
		end
	end)

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		adopt(deps.MatchController.getQueue())
		root:PlayEnter()
		panel:FocusForGamepad(focusTarget())
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		-- The next visit starts from the queue as it stands, not from an old refusal.
		timedOut = nil
		for _, card in ipairs(cards) do
			setBreathing(card, false)
		end
		panel:ReleaseGamepadFocus()
		root:PlayExit()
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		for _, card in ipairs(cards) do
			setBreathing(card, false)
		end
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = close,
		Destroy = destroy,
	}
	render()
	return screen
end

return PlayScreen
