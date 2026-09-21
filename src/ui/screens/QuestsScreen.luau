--!strict
-- QuestsScreen: the daily and weekly quest boards. Each section lists the quests the server selected
-- for the running period (QuestLogic.select on the period key stored in the profile, so the client
-- shows exactly the set the server tracks) with its progress and a Claim button. Claims go through the
-- ClaimQuest remote; the server answers with a profile push and a Notify toast, so nothing here decides
-- whether a reward is granted.
--
-- Rows are rebuilt only when the selected quests change (period rollover); a progress push just
-- refreshes the labels and the button states.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local QuestConfig = require(Shared.Config.QuestConfig)
local QuestLogic = require(Shared.Pure.QuestLogic)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	OnClose: () -> (),
	OnNavigate: (id: string) -> (),
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type Period = QuestLogic.Period
type QuestDef = QuestConfig.QuestDef
type PeriodDef = { Count: number, RewardXp: number, RewardRyo: number }
type Destroyable = { Destroy: (self: any) -> () }
type QuestRow = { Name: TextLabel, Progress: TextLabel, Button: Button.Button }
type Section = { Signature: string, Rows: { QuestRow }, Trove: any }

local QuestsScreen = {}

local OVERLAY_TRANSPARENCY = 0.45
local BUTTON_WIDTH = 130
local NAME_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local PROGRESS_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local QUEST_ROW_HEIGHT = NAME_HEIGHT + PROGRESS_HEIGHT + Theme.Sizes.Padding
local PERIODS: { string } = { "Daily", "Weekly" }
local TITLE_KEYS: { [string]: string } = { Daily = "quest.daily", Weekly = "quest.weekly" }
-- Layout band per section: the header sits on the base, its quests right after it.
local LAYOUT_BASE: { [string]: number } = { Daily = 1, Weekly = 100 }

-- Dimmed backdrop that also swallows clicks so the world under the menu is not interacted with.
local function makeOverlay(parent: Instance): Frame
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = Theme.Colors.Overlay
	overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Active = true
	overlay.Parent = parent
	return overlay
end

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

-- Two stacked lines for a quest row: its name (target substituted) and its progress.
local function makeQuestLabel(): (Frame, TextLabel, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = "Quest"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, NAME_HEIGHT)
	name.LayoutOrder = 1
	name.FontFace = Theme.Fonts.Bold
	name.TextSize = Theme.Sizes.TextLarge
	name.TextColor3 = Theme.Colors.Text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = ""
	name.Parent = frame

	local progress = Instance.new("TextLabel")
	progress.Name = "Progress"
	progress.BackgroundTransparency = 1
	progress.Size = UDim2.new(1, 0, 0, PROGRESS_HEIGHT)
	progress.LayoutOrder = 2
	progress.FontFace = Theme.Fonts.Body
	progress.TextSize = Theme.Sizes.TextSmall
	progress.TextColor3 = Theme.Colors.TextMuted
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.TextTruncate = Enum.TextTruncate.AtEnd
	progress.Text = ""
	progress.Parent = frame

	return frame, name, progress
end

function QuestsScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local sections: { [string]: Section } = {}
	local firstButton: GuiObject? = nil

	local root = ScreenRoot.new({ Name = "QuestsScreen", DisplayOrder = Theme.Layers.Screen })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("menu.quests"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)

	----------------------------------------------------------------
	-- Sections
	----------------------------------------------------------------

	-- Quests selected for the period the profile is on. A profile that has never been through the
	-- server's period check carries no key yet: the current one is derived from the same pure helper.
	local function activeQuests(period: string, set: Types.QuestSetData): { QuestDef }
		local typed: Period = asPeriod(period)
		local key = if set.PeriodKey ~= "" then set.PeriodKey else QuestLogic.periodKey(typed, os.time())
		return QuestLogic.select(QuestConfig.Pool, typed, periodDef(period).Count, key)
	end

	local function signatureOf(set: Types.QuestSetData, quests: { QuestDef }): string
		local parts = { set.PeriodKey }
		for _, def in ipairs(quests) do
			table.insert(parts, def.Id)
		end
		return table.concat(parts, "|")
	end

	for _, period in ipairs(PERIODS) do
		local def = periodDef(period)
		local header = ListRow.new({
			Left = t(TITLE_KEYS[period]),
			Right = t("quest.reward", { xp = def.RewardXp, ryo = def.RewardRyo }),
			LayoutOrder = LAYOUT_BASE[period],
			Name = period .. "Header",
			Parent = panel.Content,
		})
		own(trove, header)
		sections[period] = { Signature = "", Rows = {}, Trove = trove:Extend() }
	end

	local function claim(period: string, questId: string)
		deps.SoundController.play("UiClick")
		deps.RemoteClient.fire("ClaimQuest", period, questId)
	end

	local function buildRows(period: string, quests: { QuestDef })
		local section = sections[period]
		section.Trove:Clean()
		section.Rows = {}
		for index, def in ipairs(quests) do
			local frame, name, progress = makeQuestLabel()
			local button = Button.new({
				Text = t("quest.claim"),
				Variant = "Secondary",
				Disabled = true,
				Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
				OnClick = function()
					claim(period, def.Id)
				end,
			})
			own(section.Trove, button)
			local row = ListRow.new({
				Left = frame,
				Right = button.Instance,
				Height = QUEST_ROW_HEIGHT,
				LayoutOrder = LAYOUT_BASE[period] + index,
				Name = def.Id,
				Parent = panel.Content,
			})
			own(section.Trove, row)
			name.Text = t(def.NameKey, { target = def.Target })
			table.insert(section.Rows, { Name = name, Progress = progress, Button = button })
		end
	end

	local function updateRow(row: QuestRow, status: QuestLogic.Status)
		row.Progress.Text = t("quest.progress", { progress = status.Progress, target = status.Target })
		if status.Claimed then
			row.Button:SetText(t("quest.claimed"))
			row.Button:SetVariant("Secondary")
			row.Button:SetDisabled(true)
		elseif status.Completed then
			row.Button:SetText(t("quest.claim"))
			row.Button:SetVariant("Primary")
			row.Button:SetDisabled(false)
		else
			row.Button:SetText(t("quest.claim"))
			row.Button:SetVariant("Secondary")
			row.Button:SetDisabled(true)
		end
	end

	local function refresh()
		local data = deps.ClientData.get()
		firstButton = nil
		for _, period in ipairs(PERIODS) do
			local section = sections[period]
			if data == nil then
				section.Signature = ""
				section.Trove:Clean()
				section.Rows = {}
				continue
			end
			local set = questSet(data, period)
			local quests = activeQuests(period, set)
			local signature = signatureOf(set, quests)
			if signature ~= section.Signature then
				section.Signature = signature
				buildRows(period, quests)
			end
			for index, status in ipairs(QuestLogic.status(set, quests)) do
				local row = section.Rows[index]
				if row ~= nil then
					updateRow(row, status)
					-- Gamepad focus goes to the first button the player can actually press.
					if firstButton == nil and not row.Button:IsDisabled() then
						firstButton = row.Button.Instance
					end
				end
			end
		end
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Quests" then
			refresh()
		end
	end)

	refresh()

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		refresh()
		root.Instance.Enabled = true
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		panel:ReleaseGamepadFocus()
		root.Instance.Enabled = false
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
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
