--!strict
-- Standings: what the leaderboard draws of its players (D-147). The first three on a podium -- second on
-- the left, first in the centre on the tallest plinth, third on the right; the primary yellow, chalk and
-- bronze -- each with the player's headshot, their name, their place and their rating, stamped in one after
-- the other. Every other player is a row: their place, the seal of their tier on the illuminated rank
-- ladder, their name and their rating. The tier is the one the server wrote on the entry (LeaderboardView).
--
-- A headshot is fetched off the thread and may never come: until it does, and for good if it fails, the
-- player is an initial on a chalk disc.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LeaderboardView = require(Shared:WaitForChild("Pure"):WaitForChild("LeaderboardView"))
local ListRow = require(script.Parent.ListRow)
local Log = require(Shared:WaitForChild("Util"):WaitForChild("Log"))
local Motion = require(script.Parent.Parent.Motion)
local RankingConfig = require(Shared:WaitForChild("Config"):WaitForChild("RankingConfig"))
local Seal = require(script.Parent.Seal)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

local log = Log.new("Standings")

export type Entry = LeaderboardView.Entry

export type PodiumProps = {
	-- The first places of the board, in place order.
	Entries: { Entry },
	-- An entry's rating, worded.
	Rating: (entry: Entry) -> string,
	LayoutOrder: number?,
	Parent: Instance,
}

export type Podium = { Instance: Frame, Destroy: (self: Podium) -> () }

export type RowProps = {
	Entry: Entry,
	Variant: ListRow.Variant,
	Rating: string,
	LayoutOrder: number?,
	Parent: Instance,
}

local Standings = {}

-- A plinth per place: its colour and its height.
local PLINTHS: { { Fill: Color3, Height: number } } = {
	{ Fill = Theme.Colors.Primary, Height = 120 },
	{ Fill = Theme.Colors.Chalk, Height = 96 },
	{ Fill = Theme.Colors.Bronze, Height = 80 },
}
local PLINTH_WIDTH = 160
local HEADSHOT = 64
local GAP = 12
local NAME_SIZE = 18
local RANK_SIZE = 40
-- The plinths arrive this small and stamp up to their size.
local STAMP_FROM = 0.6
-- A row: the place, the tier's seal, the name, the rating.
local ROW_RANK_WIDTH = 48
local ROW_RANK_SIZE = 22
local ROW_SEAL = 24

-- The podium's height, in design units: the tallest plinth, the headshot and the name over it.
function Standings.podiumHeight(): number
	return PLINTHS[1].Height + HEADSHOT + NAME_SIZE + GAP * 3
end

local function textLabel(name: string, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	return label
end

-- The seal of a tier (Theme.rank): its fill, and the rim the higher ones wear.
function Standings.seal(tierId: string, size: number, parent: Instance, order: number): Seal.Seal
	local rank = Theme.rank(tierId)
	return Seal.new({ Text = "", Fill = rank.Fill, Rim = rank.Rim, Size = size, LayoutOrder = order, Parent = parent })
end

-- The tier an entry's seal wears: the server's, or the first when its key names none.
local function tierOf(entry: Entry): string
	return LeaderboardView.tierId(entry.RankKey, RankingConfig.Tiers) or RankingConfig.Tiers[1].Id
end

-- The first character of a name, for a headshot that could not be fetched.
local function initial(name: string): string
	local finish = utf8.offset(name, 2)
	return if finish ~= nil then string.sub(name, 1, finish - 1) else name
end

-- The headshot: chalk and an initial until the picture arrives, and for good if it never does.
local function headshot(entry: Entry, parent: Instance, alive: () -> boolean)
	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BorderSizePixel = 0
	head.BackgroundColor3 = Theme.Colors.Chalk
	head.Size = UDim2.fromOffset(HEADSHOT, HEADSHOT)
	head.LayoutOrder = 1
	Theme.corner(head, Theme.Pill)
	Theme.stroke(head, "Accent", Theme.Sizes.StrokeThin)
	local letter = textLabel("Initial", Theme.Fonts.Title, Theme.Sizes.TextTitle, Theme.Colors.Text)
	letter.Size = UDim2.fromScale(1, 1)
	letter.Text = initial(entry.Name)
	letter.Parent = head
	head.Parent = parent
	task.spawn(function()
		local ok, image = pcall(function(): string
			return (
				Players:GetUserThumbnailAsync(entry.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			)
		end)
		if not ok then
			log.warn("no headshot for %s (%d) on the podium: %s", entry.Name, entry.UserId, tostring(image))
			return
		end
		if alive() then
			head.Image = image
			letter.Visible = false
		end
	end)
end

function Standings.podium(props: PodiumProps): Podium
	local trove = Trove.new()
	local alive = true
	trove:Add(function()
		alive = false
	end)

	local stand = Instance.new("Frame")
	stand.Name = "Podium"
	stand.BackgroundTransparency = 1
	stand.Size = UDim2.new(1, 0, 0, Standings.podiumHeight())
	stand.LayoutOrder = props.LayoutOrder or 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = stand
	trove:Add(stand)

	local scales: { Instance } = {}
	for place, entry in ipairs(props.Entries) do
		local look = PLINTHS[place]
		if look == nil then
			break
		end
		local column = Instance.new("Frame")
		column.Name = "Place" .. tostring(place)
		column.BackgroundTransparency = 1
		column.Size = UDim2.new(0, PLINTH_WIDTH, 1, 0)
		column.LayoutOrder = table.find(LeaderboardView.PodiumOrder, place) or place
		local stack = Instance.new("UIListLayout")
		stack.FillDirection = Enum.FillDirection.Vertical
		stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
		stack.VerticalAlignment = Enum.VerticalAlignment.Bottom
		stack.SortOrder = Enum.SortOrder.LayoutOrder
		stack.Padding = UDim.new(0, GAP / 2)
		stack.Parent = column
		local scale = Instance.new("UIScale")
		scale.Scale = STAMP_FROM
		scale.Parent = column
		trove:Add(function()
			Motion.cancel(scale)
		end)
		table.insert(scales, scale)

		headshot(entry, column, function()
			return alive
		end)
		local name = textLabel("Name", Theme.Fonts.Bold, NAME_SIZE, Theme.Colors.Text)
		name.Size = UDim2.new(1, 0, 0, NAME_SIZE + 4)
		name.LayoutOrder = 2
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = entry.Name
		name.Parent = column

		-- A vivid block on the page: a sticker, in its ink outline (docs/ART_BIBLE.md rule 11).
		local block = Sticker.new({
			Kind = "Card",
			Fill = look.Fill,
			Corner = UDim.new(0, Theme.Sizes.CornerCard),
			Size = UDim2.new(1, 0, 0, look.Height),
			LayoutOrder = 3,
			Name = "Plinth",
			Parent = column,
		})
		trove:Add(function()
			block:Destroy()
		end)
		local ink = Theme.inkOn(look.Fill)
		local rank = textLabel("Rank", Theme.Fonts.Title, RANK_SIZE, ink)
		rank.Size = UDim2.new(1, 0, 0, RANK_SIZE)
		rank.Position = UDim2.fromOffset(0, Theme.Sizes.PaddingSmall)
		rank.Text = tostring(entry.Rank)
		rank.Parent = block.Face
		local rating = textLabel("Rating", Theme.Fonts.Numeric, Theme.Sizes.NumSmall, ink)
		rating.Size = UDim2.new(1, 0, 0, Theme.Sizes.NumSmall)
		rating.Position = UDim2.fromOffset(0, Theme.Sizes.PaddingSmall * 2 + RANK_SIZE)
		rating.Text = props.Rating(entry)
		rating.Parent = block.Face
		column.Parent = stand
	end
	stand.Parent = props.Parent
	-- They stamp in one after the other: first place, then second, then third.
	Motion.stagger(scales, { Scale = 1 }, "UiPop")

	local function destroy(_self: Podium)
		trove:Destroy()
	end

	return { Instance = stand, Destroy = destroy }
end

function Standings.row(props: RowProps): ListRow.ListRow
	local entry = props.Entry
	local left = Instance.new("Frame")
	left.Name = "Player"
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(1, 1)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = left
	local place = textLabel("Rank", Theme.Fonts.Numeric, ROW_RANK_SIZE, Theme.Colors.Text)
	place.Size = UDim2.new(0, ROW_RANK_WIDTH, 1, 0)
	place.LayoutOrder = 1
	place.Text = tostring(entry.Rank)
	place.Parent = left
	Standings.seal(tierOf(entry), ROW_SEAL, left, 2)
	local name = textLabel("Name", Theme.Fonts.Bold, NAME_SIZE, Theme.Colors.Text)
	name.Size = UDim2.fromScale(0, 1)
	name.LayoutOrder = 3
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = entry.Name
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = name
	name.Parent = left
	local rating = textLabel("Rating", Theme.Fonts.Numeric, Theme.Sizes.NumSmall, Theme.Colors.Text)
	rating.AutomaticSize = Enum.AutomaticSize.X
	rating.Size = UDim2.fromScale(0, 1)
	rating.Text = props.Rating
	return ListRow.new({
		Variant = props.Variant,
		Left = left,
		Right = rating,
		LayoutOrder = props.LayoutOrder,
		Name = "Row" .. tostring(entry.Rank),
		Parent = props.Parent,
	})
end

return Standings
