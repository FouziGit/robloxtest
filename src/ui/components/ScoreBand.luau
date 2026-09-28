--!strict
-- ScoreBand: the match, at the top of the screen while one is held (D-147). The round, the phase timer (the
-- countdown number while the round has not started), the score and both team rosters with a dead / alive
-- marker. It is one band of HudController's top-centre column, at the LayoutOrder the HUD gives it, and it
-- disappears as soon as the snapshot is nil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared:WaitForChild("Types"))

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	Parent: Instance,
	Localize: Localizer,
	LayoutOrder: number,
}

export type ScoreBand = {
	Instance: Frame,
	-- The match as the server last described it, or nil once it is over.
	Set: (self: ScoreBand, snapshot: Types.MatchSnapshot?) -> (),
	Destroy: (self: ScoreBand) -> (),
}

local ScoreBand = {}

local BAND_WIDTH = 360
-- A band that is shown grows into place: rule 3 of docs/ART_BIBLE.md, nothing appears.
local BAND_ENTER_SCALE = 0.9
local BAND_ROW_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local BAND_HERO_HEIGHT = Theme.Sizes.TextHero + Theme.Sizes.PaddingSmall
local ROSTER_COLUMN_WIDTH = (BAND_WIDTH - Theme.Sizes.Gap) / 2
local ROSTER_ROW_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local COUNTDOWN_PHASE = "Countdown"
-- Icon glyphs, locale independent (same convention as the panel close button).
local ALIVE_GLYPH = "●"
local DEAD_GLYPH = "✕"

-- Centered line of the band.
local function makeBandLabel(name: string, order: number, height: number, textSize: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.LayoutOrder = order
	label.FontFace = Theme.Fonts.Bold
	label.TextSize = textSize
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeColor3 = Theme.Colors.TextInverse
	label.TextStrokeTransparency = 0.6
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

function ScoreBand.new(props: Props): ScoreBand
	local trove = Trove.new()
	local localize = props.Localize
	local rosterColumns: { Frame } = {}
	local rosterLabels: { { TextLabel } } = {}

	local band = Instance.new("Frame")
	band.Name = "Match"
	band.BackgroundTransparency = 1
	band.LayoutOrder = props.LayoutOrder
	band.Size = UDim2.fromOffset(BAND_WIDTH, 0)
	band.AutomaticSize = Enum.AutomaticSize.Y
	band.Visible = false -- Set shows it while a snapshot is held
	trove:Add(band)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = band

	local roundLabel = makeBandLabel("Round", 1, ROSTER_ROW_HEIGHT, Theme.Sizes.TextSmall, band)
	roundLabel.TextColor3 = Theme.Colors.TextMuted
	local scoreLabel = makeBandLabel("Score", 2, BAND_ROW_HEIGHT, Theme.Sizes.TextTitle, band)
	scoreLabel.TextColor3 = Theme.Colors.Accent
	scoreLabel.FontFace = Theme.Fonts.Numeric
	local timerLabel = makeBandLabel("Timer", 3, BAND_ROW_HEIGHT, Theme.Sizes.TextLarge, band)
	timerLabel.FontFace = Theme.Fonts.Numeric

	local roster = Instance.new("Frame")
	roster.Name = "Roster"
	roster.BackgroundTransparency = 1
	roster.Size = UDim2.fromScale(1, 0)
	roster.AutomaticSize = Enum.AutomaticSize.Y
	roster.LayoutOrder = 4
	local rosterLayout = Instance.new("UIListLayout")
	rosterLayout.FillDirection = Enum.FillDirection.Horizontal
	rosterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rosterLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rosterLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	rosterLayout.Parent = roster
	roster.Parent = band

	local scale = Instance.new("UIScale")
	scale.Name = "Entrance"
	scale.Parent = band
	trove:Add(function()
		Motion.cancel(scale)
	end)

	band.Parent = props.Parent

	-- Roster instances are pooled: a match snapshot lands a few times per second, so nothing is rebuilt.
	-- Visibility is the caller's business (an empty team hides its whole column).
	local function rosterColumn(index: number): Frame
		local existing: Frame? = rosterColumns[index]
		if existing ~= nil then
			return existing
		end
		local column = Instance.new("Frame")
		column.Name = "Team" .. index
		column.BackgroundTransparency = 1
		column.Size = UDim2.fromOffset(ROSTER_COLUMN_WIDTH, 0)
		column.AutomaticSize = Enum.AutomaticSize.Y
		column.LayoutOrder = index
		local columnLayout = Instance.new("UIListLayout")
		columnLayout.FillDirection = Enum.FillDirection.Vertical
		columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		columnLayout.Parent = column
		column.Parent = roster
		rosterColumns[index] = column
		rosterLabels[index] = {}
		return column
	end

	local function rosterLabel(teamIndex: number, slot: number): TextLabel
		local column = rosterColumn(teamIndex)
		local labels = rosterLabels[teamIndex]
		local existing: TextLabel? = labels[slot]
		if existing ~= nil then
			existing.Visible = true
			return existing
		end
		local label = Instance.new("TextLabel")
		label.Name = "Member" .. slot
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, ROSTER_ROW_HEIGHT)
		label.LayoutOrder = slot
		label.FontFace = Theme.Fonts.Body
		label.TextSize = Theme.Sizes.TextSmall
		label.TextStrokeColor3 = Theme.Colors.TextInverse
		label.TextStrokeTransparency = 0.6
		-- Teams read outwards from the middle of the band: odd teams on the left, even teams on the right.
		label.TextXAlignment = if teamIndex % 2 == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = ""
		label.Parent = column
		labels[slot] = label
		return label
	end

	local function refreshRoster(snapshot: Types.MatchSnapshot)
		for teamIndex, members in ipairs(snapshot.Teams) do
			local column = rosterColumn(teamIndex)
			column.Visible = #members > 0
			for slot, member in ipairs(members) do
				local label = rosterLabel(teamIndex, slot)
				label.Text = (if member.Alive then ALIVE_GLYPH else DEAD_GLYPH) .. " " .. member.Name
				if not member.Alive then
					label.TextColor3 = Theme.Colors.TextMuted
				elseif teamIndex == snapshot.LocalTeam then
					label.TextColor3 = Theme.Colors.Success
				else
					-- Ink, not Cinnabar. Rule 7 of docs/ART_BIBLE.md reserves red for danger that is about to
					-- land on you, and the roster carried it for the whole match beside a name: six things on
					-- this HUD were red at once, so none of them meant anything.
					label.TextColor3 = Theme.Colors.Text
				end
			end
			local labels = rosterLabels[teamIndex]
			for slot = #members + 1, #labels do
				labels[slot].Visible = false
			end
		end
		for index = #snapshot.Teams + 1, #rosterColumns do
			rosterColumns[index].Visible = false
		end
	end

	local function set(_self: ScoreBand, snapshot: Types.MatchSnapshot?)
		if snapshot == nil then
			band.Visible = false
			return
		end
		-- Best-of series: winning RoundsToWin rounds takes at most 2 * RoundsToWin - 1 rounds.
		local total = math.max(snapshot.Round, snapshot.RoundsToWin * 2 - 1)
		roundLabel.Text = localize.t("match.round", { round = snapshot.Round, total = total })

		local ours = 0
		local theirs = 0
		for index, score in ipairs(snapshot.Scores) do
			if index == snapshot.LocalTeam then
				ours = score
			else
				theirs = math.max(theirs, score)
			end
		end
		scoreLabel.Text = localize.t("match.score", { ours = ours, theirs = theirs })

		local seconds = math.max(0, math.ceil(snapshot.SecondsLeft))
		if snapshot.Phase == COUNTDOWN_PHASE then
			timerLabel.Size = UDim2.new(1, 0, 0, BAND_HERO_HEIGHT)
			timerLabel.TextSize = Theme.Sizes.TextHero
			timerLabel.Text = localize.t("match.countdown", { seconds = seconds })
		else
			timerLabel.Size = UDim2.new(1, 0, 0, BAND_ROW_HEIGHT)
			timerLabel.TextSize = Theme.Sizes.TextLarge
			timerLabel.Text = localize.t("match.timeLeft", { seconds = seconds })
		end

		refreshRoster(snapshot)
		if not band.Visible then
			band.Visible = true
			Motion.set(scale, { Scale = BAND_ENTER_SCALE })
			Motion.to(scale, { Scale = 1 }, "UiSnappy")
		end
	end

	local function destroy(_self: ScoreBand)
		trove:Destroy()
	end

	local object: ScoreBand = {
		Instance = band,
		Set = set,
		Destroy = destroy,
	}
	return object
end

return ScoreBand
