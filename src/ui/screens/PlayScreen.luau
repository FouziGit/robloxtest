--!strict
-- PlayScreen: the queue screen. One row per MatchConfig.ModeOrder entry (mode name, team size) with a
-- Join / Leave button driven by the queue snapshot, and the live search state in the header: waited
-- seconds (ticked locally from the last server value) and queued / needed players. The screen never
-- touches the queue remotes itself: MatchController owns them, so a single JoinQueue / LeaveQueue is sent
-- per press and every number shown here is server-authored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local ListRow = require(script.Parent.Parent.components.ListRow)
local MatchConfig = require(Shared.Config.MatchConfig)
local Panel = require(script.Parent.Parent.components.Panel)
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
	-- Queue state and intents. The screen reads the snapshot and asks for a join / leave; the server decides.
	MatchController: {
		getQueue: () -> Types.QueueSnapshot,
		joinQueue: (modeId: string) -> (),
		leaveQueue: () -> (),
		QueueChanged: any,
	},
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

type Destroyable = { Destroy: (self: any) -> () }

local PlayScreen = {}

local OVERLAY_TRANSPARENCY = 0.45
local BUTTON_WIDTH = 150
local MODE_ROW_HEIGHT = Theme.Sizes.RowHeight + Theme.Sizes.Padding
local STATUS_HEIGHT = Theme.Sizes.TextBody + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2 + STATUS_HEIGHT
-- The queue snapshot only arrives on a change, so the waited seconds are advanced locally at 1 Hz from
-- the last server value (one Heartbeat accumulator, alive only while the screen is open and queued).
local TICK_SECONDS = 1

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

local function makeStatusLabel(name: string, alignment: Enum.TextXAlignment, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(0, STATUS_HEIGHT)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.LayoutOrder = order
	label.FontFace = Theme.Fonts.Body
	label.TextSize = Theme.Sizes.TextBody
	label.TextColor3 = Theme.Colors.TextMuted
	label.TextXAlignment = alignment
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- Two stacked lines for the row's left slot: the mode name and its team size.
local function makeModeLabel(nameText: string, sizeText: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Mode"
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
	name.Size = UDim2.new(1, 0, 0, Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall)
	name.LayoutOrder = 1
	name.FontFace = Theme.Fonts.Bold
	name.TextSize = Theme.Sizes.TextLarge
	name.TextColor3 = Theme.Colors.Text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = nameText
	name.Parent = frame

	local size = Instance.new("TextLabel")
	size.Name = "TeamSize"
	size.BackgroundTransparency = 1
	size.Size = UDim2.new(1, 0, 0, Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall)
	size.LayoutOrder = 2
	size.FontFace = Theme.Fonts.Body
	size.TextSize = Theme.Sizes.TextSmall
	size.TextColor3 = Theme.Colors.TextMuted
	size.TextXAlignment = Enum.TextXAlignment.Left
	size.TextTruncate = Enum.TextTruncate.AtEnd
	size.Text = sizeText
	size.Parent = frame

	return frame
end

function PlayScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local tickTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen

	local buttons: { [string]: Button.Button } = {}
	local firstButton: GuiObject? = nil
	local ticking = false
	local accumulator = 0
	-- Local clock for the waited seconds: base value from the server plus the time since it arrived.
	local waitedBase = 0
	local waitedAt = os.clock()

	local root = ScreenRoot.new({ Name = "PlayScreen", DisplayOrder = Theme.Layers.Screen })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("queue.title"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	panel:SetHeaderHeight(HEADER_HEIGHT)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	local searchLabel = makeStatusLabel("Search", Enum.TextXAlignment.Left, 1, panel.Header)
	local searchFlex = Instance.new("UIFlexItem")
	searchFlex.FlexMode = Enum.UIFlexMode.Fill
	searchFlex.Parent = searchLabel
	local waitLabel = makeStatusLabel("Waiting", Enum.TextXAlignment.Right, 2, panel.Header)

	local function waitedSeconds(): number
		return math.max(0, math.floor(waitedBase + (os.clock() - waitedAt)))
	end

	local function refreshStatus()
		local queue = deps.MatchController.getQueue()
		if not queue.Queued then
			searchLabel.Text = ""
			waitLabel.Text = ""
			return
		end
		searchLabel.Text = t("queue.searching", { waited = waitedSeconds() })
		waitLabel.Text = t("queue.waiting", { queued = queue.QueuedCount, needed = queue.NeededCount })
	end

	local function refreshRows()
		local queue = deps.MatchController.getQueue()
		for modeId, button in pairs(buttons) do
			local thisMode = queue.Queued and queue.ModeId == modeId
			button:SetText(if thisMode then t("queue.leave") else t("queue.join"))
			button:SetVariant(if thisMode then "Danger" else "Primary")
			button:SetDisabled(queue.Queued and not thisMode)
		end
	end

	-- The tick only runs while the screen is visible and the player is actually waiting in a queue.
	local function syncTick()
		local wanted = screen.Visible and deps.MatchController.getQueue().Queued
		if wanted == ticking then
			return
		end
		ticking = wanted
		if not wanted then
			tickTrove:Clean()
			return
		end
		accumulator = 0
		tickTrove:Connect(RunService.Heartbeat, function(delta: number)
			accumulator += delta
			if accumulator < TICK_SECONDS then
				return
			end
			accumulator = 0
			refreshStatus()
		end)
	end

	local function adopt(queue: Types.QueueSnapshot)
		waitedBase = queue.WaitedSeconds
		waitedAt = os.clock()
		refreshRows()
		refreshStatus()
		syncTick()
	end

	for index, modeId in ipairs(MatchConfig.ModeOrder) do
		local def = MatchConfig.Modes[modeId]
		if def == nil then
			continue
		end
		local button = Button.new({
			Text = t("queue.join"),
			Variant = "Primary",
			Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
			OnClick = function()
				deps.SoundController.play("UiClick")
				local queue = deps.MatchController.getQueue()
				if queue.Queued and queue.ModeId == modeId then
					deps.MatchController.leaveQueue()
				else
					deps.MatchController.joinQueue(modeId)
				end
			end,
		})
		own(trove, button)
		buttons[modeId] = button
		if firstButton == nil then
			firstButton = button.Instance
		end

		local row = ListRow.new({
			Left = makeModeLabel(t(def.NameKey), t("queue.teamSize", { size = def.TeamSize })),
			Right = button.Instance,
			Height = MODE_ROW_HEIGHT,
			LayoutOrder = index,
			Parent = panel.Content,
		})
		own(trove, row)
	end

	trove:Connect(deps.MatchController.QueueChanged, adopt)

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		adopt(deps.MatchController.getQueue())
		root.Instance.Enabled = true
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		syncTick()
		panel:ReleaseGamepadFocus()
		root.Instance.Enabled = false
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		ticking = false
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = close,
		Destroy = destroy,
	}
	refreshRows()
	return screen
end

return PlayScreen
