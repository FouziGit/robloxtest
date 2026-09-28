--!strict
-- LeaderboardScreen: the ranked boards, on the ink band of the Leaderboard chapter (D-147). One tab per
-- RankingConfig.Leaderboard board. Rows come from the server through the RequestLeaderboard function: a
-- board is requested when it is opened, at most every REFRESH_MIN_SECONDS, and the answer is cached per
-- board so switching tabs is instant. A request in flight shows skeleton rows; one that fails or does not
-- answer in LOAD_TIMEOUT seconds says so, with a way to try again; a failure never wipes rows already shown.
--
-- Under the tabs, the player's own standing: a seal in the colour of their tier, and where they are -- from
-- the board when they are listed, from the profile's ranked record otherwise -- with a way to find their
-- row. The first three stand on a podium (LeaderboardView), the rest are rows with a seal of their tier:
-- the illuminated rank ladder, read from the rank key the server wrote on each row. The player's own row
-- is ringed, and pinned at the foot of the card while it is scrolled out of sight. Pinned, it says what the
-- standing says, and a tap on it finds the row: the standing then steps aside, which on a phone is the
-- difference between one row of the list in view and more than two (tests/LeaderboardFit.spec.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local LeaderboardView = require(Shared.Pure.LeaderboardView)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local RankTiers = require(Shared.Pure.RankTiers)
local RankingConfig = require(Shared.Config.RankingConfig)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Standings = require(script.Parent.Parent.components.Standings)
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
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
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

type Destroyable = { Destroy: (self: any) -> () }
type Entry = Types.LeaderboardEntry

local LeaderboardScreen = {}

local CHAPTER = "Leaderboard"
-- A request that has not answered in this long is a failure the player is told about.
local LOAD_TIMEOUT = 5
local REFRESH_MIN_SECONDS = 30
local BOARDS = RankingConfig.Leaderboard.Boards
local TOP_COUNT = RankingConfig.Leaderboard.TopCount
local BOARD_KEY_PREFIX = "leaderboard.board."
local TABS_HEIGHT = 48
local SKELETON_ROWS = 5
local STANDING_SEAL = 36
local ROWS_BASE = 10
-- Boards named after a ranked mode read that mode's record in the profile; "Global" spans every mode.
local MODE_BOARDS: { [string]: boolean } = {}
for _, modeId in ipairs(RankingConfig.Modes) do
	MODE_BOARDS[modeId] = true
end

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

function LeaderboardScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local boardTrove = trove:Extend()
	local pinnedTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen

	local entriesByBoard: { [string]: { Entry } } = {}
	local fetchedAt: { [string]: number } = {}
	local fetching: { [string]: boolean } = {}
	local failed: { [string]: boolean } = {}
	local currentBoard: string = BOARDS[1]
	local destroyed = false
	-- The player's own row on the board shown, while they are listed below the podium.
	local ownRow: Frame? = nil
	local ownEntry: Entry? = nil
	local pinned = false

	local root = ScreenRoot.new({
		Name = "LeaderboardScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("leaderboard.title"),
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
	-- The tabs and the standing's button carry the touch minimum, which follows the viewport. The standing is
	-- not there while the player's own row is pinned.
	local function headerHeight(): number
		local tabsHeight = Theme.Sizes.PaddingSmall * 2 + Theme.touchTargetHeight(TABS_HEIGHT)
		if pinned then
			return tabsHeight
		end
		return tabsHeight + Theme.Sizes.Gap + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
	end
	panel:SetHeaderHeight(headerHeight)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Vertical
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	----------------------------------------------------------------
	-- The player's own standing
	----------------------------------------------------------------

	local standing = Instance.new("Frame")
	standing.Name = "Standing"
	standing.BackgroundTransparency = 1
	standing.Size = UDim2.new(1, 0, 0, Theme.touchTargetHeight(Theme.Sizes.ButtonHeight))
	standing.LayoutOrder = 2
	local standingLayout = Instance.new("UIListLayout")
	standingLayout.FillDirection = Enum.FillDirection.Horizontal
	standingLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	standingLayout.SortOrder = Enum.SortOrder.LayoutOrder
	standingLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	standingLayout.Parent = standing
	standing.Parent = panel.Header
	trove:Add(Theme.bindScale(function()
		standing.Size = UDim2.new(1, 0, 0, Theme.touchTargetHeight(Theme.Sizes.ButtonHeight))
	end))

	local youSeal = Standings.seal(RankingConfig.Tiers[1].Id, STANDING_SEAL, standing, 1)
	own(trove, youSeal)
	local youLabel = Instance.new("TextLabel")
	youLabel.Name = "You"
	youLabel.BackgroundTransparency = 1
	youLabel.FontFace = Theme.Fonts.Bold
	youLabel.TextSize = Theme.Sizes.TextBody
	youLabel.TextColor3 = Theme.Colors.Text
	youLabel.Size = UDim2.fromScale(0, 1)
	youLabel.LayoutOrder = 2
	youLabel.TextXAlignment = Enum.TextXAlignment.Left
	youLabel.TextTruncate = Enum.TextTruncate.AtEnd
	youLabel.Text = ""
	local youFill = Instance.new("UIFlexItem")
	youFill.FlexMode = Enum.UIFlexMode.Fill
	youFill.Parent = youLabel
	youLabel.Parent = standing

	-- Scrolls the page to the player's own row: the podium's top when they stand on it.
	local function findMe()
		local content = panel.Content
		local row = ownRow
		if row == nil then
			content.CanvasPosition = Vector2.zero
			return
		end
		local offset = row.AbsolutePosition.Y - content.AbsolutePosition.Y + content.CanvasPosition.Y
		local centred = offset - (content.AbsoluteWindowSize.Y - row.AbsoluteSize.Y) / 2
		local maximum = math.max(0, content.AbsoluteCanvasSize.Y - content.AbsoluteWindowSize.Y)
		content.CanvasPosition = Vector2.new(0, math.clamp(centred, 0, maximum))
	end

	local findButton = Button.new({
		Name = "FindMe",
		Text = t("leaderboard.findMe"),
		Variant = "Ghost",
		LayoutOrder = 3,
		Parent = standing,
		OnClick = findMe,
	})
	own(trove, findButton)

	-- The player's record on a board they are not listed on: whether they have played a ranked match there,
	-- and the tier it holds -- the tier of that mode, or the highest over the modes played for the Global board.
	local function profileStanding(boardId: string): (boolean, string)
		local data = deps.ClientData.get()
		local played = false
		local best = RankingConfig.Tiers[1]
		if data == nil then
			return played, best.Id
		end
		for _, modeId in ipairs(RankingConfig.Modes) do
			local mode = data.Rank.Modes[modeId]
			if mode ~= nil and mode.Matches > 0 and (boardId == modeId or not MODE_BOARDS[boardId]) then
				played = true
				local tier = RankTiers.tierFor(mode.Rating, RankingConfig.Tiers)
				if tier.Min > best.Min then
					best = tier
				end
			end
		end
		return played, best.Id
	end

	local function refreshYou()
		local entries = entriesByBoard[currentBoard]
		findButton.Instance.Visible = false
		if entries == nil then
			youLabel.Text = "" -- nothing requested yet: no claim about the player's standing
			youSeal.Instance.Visible = false
			return
		end
		youSeal.Instance.Visible = true
		local played, tierId = profileStanding(currentBoard)
		local mine = ownEntry
		if mine ~= nil then
			tierId = LeaderboardView.tierId(mine.RankKey, RankingConfig.Tiers) or tierId
			youLabel.Text = t("leaderboard.you", { rank = mine.Rank, rating = mine.Rating })
			findButton.Instance.Visible = true
		elseif played then
			youLabel.Text = t("leaderboard.youUnlisted", { count = TOP_COUNT })
		else
			youLabel.Text = t("leaderboard.unranked")
		end
		local rank = Theme.rank(tierId)
		youSeal:SetFill(rank.Fill, rank.Rim)
	end

	----------------------------------------------------------------
	-- The board
	----------------------------------------------------------------

	local fetch: (boardId: string, force: boolean) -> ()

	local function rating(entry: Entry): string
		return t("leaderboard.rating", { rating = entry.Rating })
	end

	-- The player's own row, pinned at the foot of the card while the list has scrolled it out of sight.
	local function refreshPinned()
		local row = ownRow
		local entry = ownEntry
		local content = panel.Content
		local hidden = false
		if row ~= nil and entry ~= nil then
			local top = content.AbsolutePosition.Y
			local bottom = top + content.AbsoluteWindowSize.Y
			local rowTop = row.AbsolutePosition.Y
			hidden = rowTop + row.AbsoluteSize.Y < top or rowTop > bottom
		end
		if hidden == pinned then
			return
		end
		pinned = hidden
		pinnedTrove:Clean()
		-- The header's height follows: SetFooterHeight below lays the card out again.
		standing.Visible = not hidden
		if hidden and entry ~= nil then
			local pinnedRow = Standings.row({
				Entry = entry,
				Variant = "Highlight",
				Rating = rating(entry),
				LayoutOrder = 1,
				Parent = panel.Footer,
			})
			own(pinnedTrove, pinnedRow)
			-- The standing's "Find me", while the standing steps aside: a tap on the pinned row.
			local find = Instance.new("TextButton")
			find.Name = "FindMe"
			find.AutoButtonColor = false
			find.BackgroundTransparency = 1
			find.Text = ""
			find.Size = UDim2.fromScale(1, 1)
			find.ZIndex = 10
			find.Parent = pinnedRow.Instance
			pinnedTrove:Connect(find.Activated, function()
				deps.SoundController.play("UiClick")
				findMe()
			end)
			panel:SetFooterHeight(function()
				return Theme.Sizes.PaddingSmall + Theme.Sizes.Padding + Theme.touchTargetHeight(Theme.Sizes.RowHeight)
			end)
		else
			panel:SetFooterHeight(0)
		end
	end
	trove:Connect(panel.Content:GetPropertyChangedSignal("CanvasPosition"), refreshPinned)
	trove:Connect(panel.Content:GetPropertyChangedSignal("AbsoluteCanvasSize"), refreshPinned)
	trove:Connect(panel.Content:GetPropertyChangedSignal("AbsoluteWindowSize"), refreshPinned)

	-- Nothing to list: a line of lore under a grey blot, and a button when there is something to try.
	local function emptyState(text: string, retry: boolean)
		local button: Button.Button? = nil
		if retry then
			local created = Button.new({
				Name = "Retry",
				Text = t("common.retry"),
				Variant = "Primary",
				OnClick = function()
					fetch(currentBoard, true)
				end,
			})
			own(boardTrove, created)
			button = created
		end
		own(
			boardTrove,
			ListRow.new({
				Variant = "Empty",
				Left = text,
				Right = if button ~= nil then button.Instance else nil,
				LayoutOrder = 1,
				Parent = panel.Content,
			})
		)
	end

	local function renderBoard()
		boardTrove:Clean()
		ownRow = nil
		ownEntry = nil
		panel.Content.CanvasPosition = Vector2.zero
		local entries = entriesByBoard[currentBoard]
		if entries == nil then
			if failed[currentBoard] then
				emptyState(t("common.loadFailed"), true)
			else
				for index = 1, SKELETON_ROWS do
					own(
						boardTrove,
						ListRow.new({ Variant = "Skeleton", Left = "", LayoutOrder = index, Parent = panel.Content })
					)
				end
			end
		elseif #entries == 0 then
			emptyState(t("leaderboard.empty"), false)
		else
			local podium, rows, ownIndex = LeaderboardView.split(entries, Players.LocalPlayer.UserId)
			ownEntry = if ownIndex ~= nil then entries[ownIndex] else nil
			own(
				boardTrove,
				Standings.podium({ Entries = podium, Rating = rating, LayoutOrder = 1, Parent = panel.Content })
			)
			for index, entry in ipairs(rows) do
				local mine = ownIndex ~= nil and entries[ownIndex] == entry
				local row = Standings.row({
					Entry = entry,
					Variant = if mine then "Highlight" else "Item",
					Rating = rating(entry),
					LayoutOrder = ROWS_BASE + index,
					Parent = panel.Content,
				})
				own(boardTrove, row)
				if mine then
					ownRow = row.Instance
				end
			end
		end
		refreshYou()
		refreshPinned()
	end

	fetch = function(boardId: string, force: boolean)
		if fetching[boardId] then
			return
		end
		local last = fetchedAt[boardId]
		if not force and last ~= nil and os.clock() - last < REFRESH_MIN_SECONDS then
			return
		end
		fetching[boardId] = true
		if force and boardId == currentBoard and entriesByBoard[boardId] == nil then
			failed[boardId] = false
			renderBoard()
		end
		task.spawn(function()
			local ok, result = deps.RemoteClient.invoke("RequestLeaderboard", LOAD_TIMEOUT, boardId)
			fetching[boardId] = false
			if destroyed then
				return
			end
			if not ok or type(result) ~= "table" then
				-- A failed request keeps the cached rows and allows an immediate retry; with no rows to
				-- keep, the board says it could not load.
				failed[boardId] = true
				if boardId == currentBoard and entriesByBoard[boardId] == nil then
					renderBoard()
				end
				return
			end
			failed[boardId] = false
			fetchedAt[boardId] = os.clock()
			entriesByBoard[boardId] = LeaderboardView.read(result.Entries)
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
		Chapter = CHAPTER,
		-- Tabs make no sound of their own (a Button does): the click is the screen's.
		OnSelect = function(id: string)
			deps.SoundController.play("UiClick")
			currentBoard = id
			renderBoard()
			fetch(id, false)
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

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		renderBoard()
		fetch(currentBoard, false)
		root:PlayEnter()
		-- The tabs are where a pad starts: the board to read is chosen first.
		local selectedTab = tabs.Instance:FindFirstChild(currentBoard, true)
		panel:FocusForGamepad(if selectedTab ~= nil and selectedTab:IsA("GuiObject") then selectedTab else nil)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		panel:ReleaseGamepadFocus()
		root:PlayExit()
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
