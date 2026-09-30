--!strict
-- QuestsScreen: the daily and weekly quest boards, in the blue of the Quests chapter (D-147). Each section
-- lists the quests the server selected for the running period (QuestLogic.select on the period key stored
-- in the profile, so the client shows exactly the set the server tracks) under a header that counts down
-- to the next draw, on the server's clock. Each quest is a QuestCard, and the board lists first what can be
-- claimed, then what is being played, then what is done (QuestBoard.order). Every claimable Claim button
-- sways now and then, on the one breath every claim on screen sways on (Sway).
--
-- Claims go through the ClaimQuest remote and wait for the profile push that marks them claimed: then the
-- card stamps its seal and the Folios in the band count up. The server decides whether a reward is
-- granted; nothing here does. Rows are rebuilt only when the selected quests change (period rollover); a
-- progress push just refreshes them. Until the profile has arrived each section holds skeleton rows,
-- never an empty card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local FoliosPill = require(script.Parent.Parent.components.FoliosPill)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local QuestBoard = require(Shared.Pure.QuestBoard)
local QuestCard = require(script.Parent.Parent.components.QuestCard)
local QuestConfig = require(Shared.Config.QuestConfig)
local QuestLogic = require(Shared.Pure.QuestLogic)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Sway = require(script.Parent.Parent.Sway)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	-- A claim the server never answers is said in the HUD's toasts, as the Daily reward and the Shop say it.
	HudController: { showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> () },
	OnClose: () -> (),
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

type Period = QuestLogic.Period
type QuestDef = QuestConfig.QuestDef
type PeriodDef = { Count: number, RewardXp: number, RewardFolios: number }
type Destroyable = { Destroy: (self: any) -> () }
type Section = {
	Signature: string,
	Cards: { QuestCard.QuestCard },
	Header: ListRow.ListRow,
	Trove: any,
	-- True while the section holds skeleton rows, waiting for the profile.
	Waiting: boolean,
}

local QuestsScreen = {}

local CHAPTER = "Quests"
local PERIODS: { string } = { "Daily", "Weekly" }
local TITLE_KEYS: { [string]: string } = { Daily = "quest.daily", Weekly = "quest.weekly" }
-- Layout band per section: the header sits on the base, its quests right after it.
local LAYOUT_BASE: { [string]: number } = { Daily = 1, Weekly = 100 }
-- A section waiting for the profile shows this many skeleton rows.
local SKELETON_ROWS = 3
-- The Folios in the band: the shared pill (FoliosPill), as tall as the Shop's.
local PILL_HEIGHT = 40
local SECONDS_PER_MINUTE = 60

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

-- PERIODS holds the two ids the profile's Quests section and QuestConfig.Periods are keyed by; the
-- cast hands them to the pure module with its literal type (same pattern as MatchController.asModeId).
local function asPeriod(period: string): Period
	return (period :: any) :: Period
end

local function periodDef(period: string): PeriodDef
	if period == "Daily" then
		return QuestConfig.Periods.Daily
	end
	return QuestConfig.Periods.Weekly
end

local function questSet(data: Types.ProfileData, period: string): Types.QuestSetData
	if period == "Daily" then
		return data.Quests.Daily
	end
	return data.Quests.Weekly
end

function QuestsScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local sections: { [string]: Section } = {}
	local firstButton: GuiObject? = nil
	local visible = false
	-- Bumped by every open and close, so a timer set by one opening never runs into the next.
	local session = 0

	local root = ScreenRoot.new({
		Name = "QuestsScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("menu.quests"),
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

	local foliosPill = FoliosPill.new({ Localize = deps.Localize, Height = PILL_HEIGHT, Parent = panel.Right })
	own(trove, foliosPill)

	-- The count follows the profile: it counts while the screen is up (a claim paid out), and is simply
	-- written otherwise.
	local function refreshFolios()
		local data = deps.ClientData.get()
		foliosPill.Instance.Visible = data ~= nil
		if data ~= nil then
			foliosPill:Set(data.Currency.Folios, visible)
		end
	end

	----------------------------------------------------------------
	-- Sections
	----------------------------------------------------------------

	-- Quests selected for the period the profile is on. A profile that has never been through the
	-- server's period check carries no key yet: the current one is derived from the same pure helpers, at the
	-- pool revision the server stores (QuestService), so the draw shown is the draw the server will keep.
	local function activeQuests(period: string, set: Types.QuestSetData): { QuestDef }
		local typed: Period = asPeriod(period)
		local key = if set.PeriodKey ~= ""
			then set.PeriodKey
			else QuestLogic.setKey(QuestLogic.periodKey(typed, os.time()), QuestConfig.PoolRevision)
		return QuestLogic.select(QuestConfig.Pool, typed, periodDef(period).Count, key)
	end

	local function signatureOf(set: Types.QuestSetData, quests: { QuestDef }): string
		local parts = { set.PeriodKey }
		for _, def in ipairs(quests) do
			table.insert(parts, def.Id)
		end
		return table.concat(parts, "|")
	end

	-- "Resets in 4h 12m": the time to the next draw, on the server's clock.
	local function resetsIn(period: string): string
		local now = workspace:GetServerTimeNow()
		local key, params = QuestBoard.countdown(QuestLogic.periodEndsAt(asPeriod(period), now) - now)
		return t("quest.resetsIn", { time = t(key, params) })
	end

	for _, period in ipairs(PERIODS) do
		local header = ListRow.new({
			Variant = "Header",
			Chapter = CHAPTER,
			Left = t(TITLE_KEYS[period]),
			Right = resetsIn(period),
			LayoutOrder = LAYOUT_BASE[period],
			Name = period .. "Header",
			Parent = panel.Content,
		})
		own(trove, header)
		sections[period] = { Signature = "", Cards = {}, Header = header, Trove = trove:Extend(), Waiting = false }
	end

	local function refreshCountdowns()
		for _, period in ipairs(PERIODS) do
			sections[period].Header:SetRight(resetsIn(period))
		end
	end

	-- A section with no profile yet: chalk rows breathing where the quests will be.
	local function buildSkeleton(period: string)
		local section = sections[period]
		section.Trove:Clean()
		section.Cards = {}
		section.Signature = ""
		section.Waiting = true
		for index = 1, SKELETON_ROWS do
			own(
				section.Trove,
				ListRow.new({
					Variant = "Skeleton",
					Left = "",
					LayoutOrder = LAYOUT_BASE[period] + index,
					Name = "Skeleton",
					Parent = panel.Content,
				})
			)
		end
	end

	local function buildCards(period: string, quests: { QuestDef })
		local section = sections[period]
		section.Trove:Clean()
		section.Cards = {}
		section.Waiting = false
		local def = periodDef(period)
		for _, quest in ipairs(quests) do
			local card = QuestCard.new({
				Title = t(quest.NameKey, { target = quest.Target }),
				Reward = t("quest.reward", { xp = def.RewardXp, folios = def.RewardFolios }),
				ClaimText = t("quest.claim"),
				ClaimedText = t("quest.claimed"),
				OnClaim = function()
					deps.RemoteClient.fire("ClaimQuest", period, quest.Id)
				end,
				OnTimeout = function()
					deps.HudController.showLocalToast("common.pendingTimeout", nil, "Error")
				end,
				Name = quest.Id,
				Parent = panel.Content,
			})
			own(section.Trove, card)
			table.insert(section.Cards, card)
		end
	end

	-- The board's Claim buttons, each with whether it sways now: a claim that can be pressed, and not one already
	-- sent. One breath for the whole board, only while it is up and has a claim to find (ThemeConfig.Budget).
	local stopSway: (() -> ())? = nil
	local function claimButtons(): { [GuiObject]: boolean }
		local named: { [GuiObject]: boolean } = {}
		for _, period in ipairs(PERIODS) do
			for _, card in ipairs(sections[period].Cards) do
				named[card.Button.Instance] = card:GetState() == "Claimable" and not card:IsPending()
			end
		end
		return named
	end
	local function setSwaying(on: boolean)
		if on == (stopSway ~= nil) then
			return
		end
		local stop = stopSway
		if stop ~= nil then
			stopSway = nil
			stop()
			return
		end
		stopSway = Sway.start(claimButtons)
	end
	trove:Add(function()
		setSwaying(false)
	end)

	local function refresh()
		local data = deps.ClientData.get()
		firstButton = nil
		for _, period in ipairs(PERIODS) do
			local section = sections[period]
			if data == nil then
				if not section.Waiting then
					buildSkeleton(period)
				end
				continue
			end
			local set = questSet(data, period)
			local quests = activeQuests(period, set)
			local signature = signatureOf(set, quests)
			if signature ~= section.Signature then
				section.Signature = signature
				buildCards(period, quests)
			end
			local statuses = QuestLogic.status(set, quests)
			local states: { QuestBoard.State } = {}
			for _, status in ipairs(statuses) do
				table.insert(states, QuestBoard.state(status))
			end
			for position, index in ipairs(QuestBoard.order(states)) do
				local card = section.Cards[index]
				local status = statuses[index]
				local state: QuestBoard.State = states[index]
				if card ~= nil then
					card.Instance.LayoutOrder = LAYOUT_BASE[period] + position
					card:Set(
						state,
						if status.Target > 0 then status.Progress / status.Target else 1,
						t("quest.progress", { progress = status.Progress, target = status.Target }),
						visible
					)
					-- Gamepad focus goes to the first quest the player can claim.
					if firstButton == nil and state == "Claimable" then
						firstButton = card.Button.Instance
					end
				end
			end
		end
		refreshFolios()
		-- A claim to find sways; a board with none left, or put away, holds no breath.
		setSwaying(visible and firstButton ~= nil)
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Quests" then
			-- A new draw rebuilds the cards under the pad: it goes on to the first claim, or the way out, rather
			-- than onto nothing (E12-S4).
			panel:KeepGamepadFocus(refresh, function(): GuiObject?
				return firstButton
			end)
		elseif section == "Currency" then
			refreshFolios()
		end
	end)

	----------------------------------------------------------------
	-- While the screen is up: the countdown each minute
	----------------------------------------------------------------

	-- The headers are rewritten when the minute turns, never per frame.
	local function tickCountdown(mine: number)
		if session ~= mine then
			return
		end
		refreshCountdowns()
		local now = workspace:GetServerTimeNow()
		task.delay(SECONDS_PER_MINUTE - now % SECONDS_PER_MINUTE, tickCountdown, mine)
	end

	refresh()

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		session += 1
		-- Written as they are, not animated: what changed while the screen was away is not news.
		refresh()
		visible = true
		setSwaying(firstButton ~= nil)
		root:PlayEnter()
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
		local mine = session
		tickCountdown(mine)
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		visible = false
		session += 1
		setSwaying(false)
		panel:ReleaseGamepadFocus()
		root:PlayExit()
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		visible = false
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

return QuestsScreen
