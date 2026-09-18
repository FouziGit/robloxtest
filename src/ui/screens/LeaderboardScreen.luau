--!strict
-- LeaderboardScreen: one tab per RankingConfig.Leaderboard board. Rows come from the server through the
-- RequestLeaderboard function: a board is requested when it is opened, at most every REFRESH_MIN_SECONDS,
-- and the answer is cached per board so switching tabs is instant. Under the tabs sits the local player's
-- own standing, taken from the board itself when they are listed and from the profile's ranked record
-- otherwise. A failed or late request leaves the rows on screen untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local RankingConfig = require(Shared.Config.RankingConfig)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Tabs = require(script.Parent.Parent.components.Tabs)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: {
		fire: (name: string, ...any) -> (),
		invoke: (name: string, timeout: number, ...any) -> (boolean, ...any),
	},
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

type Destroyable = { Destroy: (self: any) -> () }
type Entry = Types.LeaderboardEntry

local LeaderboardScreen = {}

local OVERLAY_TRANSPARENCY = 0.45
local INVOKE_TIMEOUT = 10
local REFRESH_MIN_SECONDS = 30
local BOARDS = RankingConfig.Leaderboard.Boards
local TOP_COUNT = RankingConfig.Leaderboard.TopCount
local BOARD_KEY_PREFIX = "leaderboard.board."
local STATUS_HEIGHT = Theme.Sizes.TextBody + Theme.Sizes.PaddingSmall

-- Boards named after a ranked mode read that mode's record in the profile; "Global" spans every mode.
local MODE_BOARDS: { [string]: boolean } = {}
for _, modeId in ipairs(RankingConfig.Modes) do
	MODE_BOARDS[modeId] = true
end

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

local function finite(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.floor(value)
end

-- Rows are server-authored; a truncated entry is dropped rather than rendered half empty.
local function readEntries(payload: any): { Entry }
	local entries: { Entry } = {}
	if type(payload) ~= "table" then
		return entries
	end
	for _, raw in ipairs(payload) do
		if type(raw) == "table" and type(raw.Name) == "string" then
			table.insert(entries, {
				Rank = math.max(1, finite(raw.Rank, #entries + 1)),
				UserId = math.max(0, finite(raw.UserId, 0)),
				Name = raw.Name,
				Rating = math.max(0, finite(raw.Rating, 0)),
				RankKey = if type(raw.RankKey) == "string" then raw.RankKey else "",
			})
		end
	end
	return entries
end

-- Right slot of a row: rank tier (muted) then rating (bold).
local function makeRatingSlot(tierText: string, ratingText: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Rating"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(0, 1)
	frame.AutomaticSize = Enum.AutomaticSize.X

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = frame

	local tier = Instance.new("TextLabel")
	tier.Name = "Tier"
	tier.BackgroundTransparency = 1
	tier.Size = UDim2.fromScale(0, 1)
	tier.AutomaticSize = Enum.AutomaticSize.X
	tier.LayoutOrder = 1
	tier.Font = Theme.Fonts.Body
	tier.TextSize = Theme.Sizes.TextSmall
	tier.TextColor3 = Theme.Colors.TextMuted
	tier.TextXAlignment = Enum.TextXAlignment.Right
	tier.Text = tierText
	tier.Parent = frame

	local rating = Instance.new("TextLabel")
	rating.Name = "Value"
	rating.BackgroundTransparency = 1
	rating.Size = UDim2.fromScale(0, 1)
	rating.AutomaticSize = Enum.AutomaticSize.X
	rating.LayoutOrder = 2
	rating.Font = Theme.Fonts.Bold
	rating.TextSize = Theme.Sizes.TextBody
	rating.TextColor3 = Theme.Colors.Accent
	rating.TextXAlignment = Enum.TextXAlignment.Right
	rating.Text = ratingText
	rating.Parent = frame

	return frame
end

function LeaderboardScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local rowsTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen

	local entriesByBoard: { [string]: { Entry } } = {}
	local fetchedAt: { [string]: number } = {}
	local fetching: { [string]: boolean } = {}
	local currentBoard: string = BOARDS[1]
	local destroyed = false

	local root = ScreenRoot.new({ Name = "LeaderboardScreen", DisplayOrder = Theme.Layers.Screen })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("leaderboard.title"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	-- The tab strip carries the touch minimum, so the header band is measured from the same height.
	panel:SetHeaderHeight(
		Theme.Sizes.PaddingSmall * 2 + Theme.touchTargetHeight(Theme.Sizes.RowHeight) + Theme.Sizes.Gap + STATUS_HEIGHT
	)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Vertical
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	local youLabel = Instance.new("TextLabel")
	youLabel.Name = "You"
	youLabel.BackgroundTransparency = 1
	youLabel.Size = UDim2.new(1, 0, 0, STATUS_HEIGHT)
	youLabel.LayoutOrder = 2
	youLabel.Font = Theme.Fonts.Bold
	youLabel.TextSize = Theme.Sizes.TextBody
	youLabel.TextColor3 = Theme.Colors.Accent
	youLabel.TextXAlignment = Enum.TextXAlignment.Left
	youLabel.TextTruncate = Enum.TextTruncate.AtEnd
	youLabel.Text = ""
	youLabel.Parent = panel.Header

	-- True when the profile shows at least one played ranked match on that board.
	local function hasRating(boardId: string): boolean
		local data = deps.ClientData.get()
		if data == nil then
			return false
		end
		local modes = data.Rank.Modes
		if MODE_BOARDS[boardId] then
			local mode = modes[boardId]
			return mode ~= nil and mode.Matches > 0
		end
		for _, modeId in ipairs(RankingConfig.Modes) do
			local mode = modes[modeId]
			if mode ~= nil and mode.Matches > 0 then
				return true
			end
		end
		return false
	end

	local function refreshYou()
		local entries = entriesByBoard[currentBoard]
		if entries == nil then
			youLabel.Text = "" -- nothing requested yet: no claim about the player's standing
			return
		end
		local userId = Players.LocalPlayer.UserId
		for _, entry in ipairs(entries) do
			if entry.UserId == userId then
				youLabel.Text = t("leaderboard.you", { rank = entry.Rank, rating = entry.Rating })
				return
			end
		end
		if hasRating(currentBoard) then
			youLabel.Text = t("leaderboard.youUnlisted", { count = TOP_COUNT })
			return
		end
		youLabel.Text = t("leaderboard.unranked")
	end

	local function renderBoard()
		rowsTrove:Clean()
		panel.Content.CanvasPosition = Vector2.zero
		refreshYou()
		local entries = entriesByBoard[currentBoard]
		if entries == nil then
			return -- the first answer for this board has not arrived yet
		end
		if #entries == 0 then
			local empty = ListRow.new({ Left = t("leaderboard.empty"), LayoutOrder = 1, Parent = panel.Content })
			own(rowsTrove, empty)
			return
		end
		for index, entry in ipairs(entries) do
			local tierText = if entry.RankKey ~= "" then t(entry.RankKey) else ""
			local row = ListRow.new({
				Left = t("leaderboard.row", { rank = entry.Rank, name = entry.Name }),
				Right = makeRatingSlot(tierText, t("leaderboard.rating", { rating = entry.Rating })),
				LayoutOrder = index,
				Parent = panel.Content,
			})
			own(rowsTrove, row)
		end
	end

	local function fetch(boardId: string)
		if fetching[boardId] then
			return
		end
		local last = fetchedAt[boardId]
		if last ~= nil and os.clock() - last < REFRESH_MIN_SECONDS then
			return
		end
		fetching[boardId] = true
		task.spawn(function()
			local ok, result = deps.RemoteClient.invoke("RequestLeaderboard", INVOKE_TIMEOUT, boardId)
			fetching[boardId] = false
			if destroyed or not ok or type(result) ~= "table" then
				return -- a failed request keeps the cached rows and allows an immediate retry
			end
			fetchedAt[boardId] = os.clock()
			entriesByBoard[boardId] = readEntries(result.Entries)
			if boardId == currentBoard then
				renderBoard()
			end
		end)
	end

	local tabItems: { Tabs.Item } = {}
	for _, boardId in ipairs(BOARDS) do
		table.insert(tabItems, { Id = boardId, Text = t(BOARD_KEY_PREFIX .. boardId) })
	end

	local tabs = Tabs.new({
		Items = tabItems,
		Selected = currentBoard,
		OnSelect = function(id: string)
			deps.SoundController.play("UiClick")
			currentBoard = id
			renderBoard()
			fetch(id)
		end,
		LayoutOrder = 1,
		Parent = panel.Header,
	})
	own(trove, tabs)

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Rank" then
			refreshYou()
		end
	end)

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		renderBoard()
		fetch(currentBoard)
		root.Instance.Enabled = true
		panel:FocusForGamepad()
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
		destroyed = true
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

return LeaderboardScreen
