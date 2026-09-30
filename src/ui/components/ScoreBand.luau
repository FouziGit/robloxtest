--!strict
-- ScoreBand: the match, on the board's ink pill at the top of the screen while one is held (D-147). One band of
-- HudController's top-centre column, at the LayoutOrder the HUD gives it; it goes as soon as the snapshot is nil.
--
--   our score      in cyan, straight on the ink: cyan is us (docs/ART_BIBLE.md rule 7)
--   the middle     "Round 3 · 1v1" in chalk, and under it the round's clock, which the board leaves out and a
--                  fight still needs; before a round starts, the words only: the count's digits are the
--                  centre's (Banner)
--   their score    in the sheet. Not red: red would sit beside their name for a whole match, and red means only
--                  what is about to hit you (D-89)
--   the rosters    in a team match, a disc per fighter, ours ringed cyan and theirs in the sheet, each ring the
--                  fighter's health going round it; a fallen one turns chalk under a cross. A duel has none: the
--                  two scores already say who is who
--
-- The last ten seconds of a round tick and punch the clock, and it never changes colour: a clock is not a
-- danger. A fight surface: nothing here wears a value colour (rule 11). The pill is as wide as what it says.
-- Everything is pooled, so a snapshot four times a second rebuilds nothing, and a health ring is only
-- rewritten when its health moved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local HudPlate = require(script.Parent.HudPlate)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared:WaitForChild("Types"))
local UiSound = require(script.Parent.Parent.UiSound)

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

type Member = {
	Disc: Frame,
	Edge: UIStroke,
	Arc: UIGradient,
	Initial: TextLabel,
	Fraction: number,
}

local ScoreBand = {}

-- A band that is shown grows into place: rule 3 of docs/ART_BIBLE.md, nothing appears.
local BAND_ENTER_SCALE = 0.9
-- The pill's inset, over and under its line and at its two ends, and the gap between what stands in it.
local PADDING_Y = 6
local PADDING_X = 16
local GAP = 12
local SCORE_TEXT = Theme.Sizes.Num
local ROUND_TEXT = Theme.Sizes.TextSmall
local TIMER_TEXT = Theme.Sizes.NumSmall
local MEMBER = 28
local MEMBER_GAP = 6
local MEMBER_TEXT = 14
local ALLY_RING = 3
local FALLEN = 0.6
-- The mode's word, "1v1" or "3v3": the leaderboard's own name for the board of that mode.
local MODE_KEY = "leaderboard.board."
local COUNTDOWN_PHASE = "Countdown"
local PLAYING_PHASE = "Playing"
-- The last seconds of a round: the clock ticks and punches on each, and never turns red.
local LAST_SECONDS = 10
local LAST_PUNCH = 1.08
local TICK_SOUND = "Countdown"

local function textLabel(name: string, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = ""
	return label
end

-- A line of the pill, as wide as its words: the pill is as wide as what it holds.
local function line(name: string, font: Font, size: number, color: Color3, order: number, parent: Instance): TextLabel
	local label = textLabel(name, font, size, color)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, size)
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

-- A row or a column as big as what it holds, laid out down or across its middle.
local function listFrame(
	name: string,
	order: number,
	direction: Enum.FillDirection,
	gap: number,
	parent: Instance
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new()
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

-- The first character of a name, whatever its script.
local function initialOf(name: string): string
	if name == "" or utf8.len(name) == nil then
		return ""
	end
	local second = utf8.offset(name, 2) or #name + 1
	return string.sub(name, 1, second - 1)
end

function ScoreBand.new(props: Props): ScoreBand
	local trove = Trove.new()
	local localize = props.Localize
	local members: { [string]: { Member } } = { Ours = {}, Theirs = {} }
	local lastSecond = -1

	local plate = HudPlate.new({
		Name = "Match",
		Corner = Theme.Pill,
		Padding = PADDING_Y,
		PaddingX = PADDING_X,
		Gap = MEMBER_GAP,
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	})
	trove:Add(function()
		plate:Destroy()
	end)
	local content = plate.Content

	-- Ours, the middle, theirs: one line across the pill.
	local top = listFrame("Score", 1, Enum.FillDirection.Horizontal, GAP, content)
	local oursScore = line("Ours", Theme.Fonts.Numeric, SCORE_TEXT, Theme.Colors.Ally, 1, top)

	-- The middle: the round and the mode, and under them the clock while a round is played.
	local middle = listFrame("Clock", 2, Enum.FillDirection.Vertical, 0, top)
	local roundLabel = line("Round", Theme.Fonts.Bold, ROUND_TEXT, Theme.Colors.Chalk, 1, middle)
	local timerLabel = line("Timer", Theme.Fonts.Numeric, TIMER_TEXT, Theme.Colors.PanelRaised, 2, middle)
	local timerScale = Instance.new("UIScale")
	timerScale.Parent = timerLabel

	local theirsScore = line("Theirs", Theme.Fonts.Numeric, SCORE_TEXT, Theme.Colors.PanelRaised, 3, top)

	-- The rosters, in a team match: ours, then theirs.
	local rosters = listFrame("Roster", 2, Enum.FillDirection.Horizontal, GAP, content)
	rosters.Visible = false
	local sides: { [string]: Frame } = {}
	for order, side in ipairs({ "Ours", "Theirs" }) do
		sides[side] = listFrame(side, order, Enum.FillDirection.Horizontal, MEMBER_GAP, rosters)
	end

	trove:Add(function()
		Motion.cancel(timerScale)
	end)

	-- A fighter's disc, pooled per side and place.
	local function member(side: string, slot: number): Member
		local list = members[side]
		local existing: Member? = list[slot]
		if existing ~= nil then
			existing.Disc.Visible = true
			return existing
		end
		local disc = Instance.new("Frame")
		disc.Name = side .. slot
		disc.BorderSizePixel = 0
		disc.Size = UDim2.fromOffset(MEMBER, MEMBER)
		disc.LayoutOrder = slot
		Theme.corner(disc, Theme.Pill)
		local ally = side == "Ours"
		local edge = Theme.stroke(
			disc,
			if ally then "Ally" else "PanelRaised",
			if ally then ALLY_RING else Theme.Sizes.StrokeThin
		)
		-- The health going round the ring: whole, the ring is whole; hurt, the part lost is faint.
		local arc = Theme.gradient("ResultRing")
		arc.Parent = edge
		local initial = textLabel("Initial", Theme.Fonts.Label, MEMBER_TEXT, Theme.Colors.PanelRaised)
		initial.Size = UDim2.fromScale(1, 1)
		initial.Parent = disc
		disc.Parent = sides[side]
		local created: Member = { Disc = disc, Edge = edge, Arc = arc, Initial = initial, Fraction = 1 }
		list[slot] = created
		return created
	end

	local function refreshMember(entry: Member, fighter: Types.MatchPlayerSnapshot)
		local fraction = if fighter.MaxHealth > 0 then math.clamp(fighter.Health / fighter.MaxHealth, 0, 1) else 1
		if not fighter.Alive then
			fraction = 0
		end
		if fraction ~= entry.Fraction then
			entry.Fraction = fraction
			entry.Arc.Transparency = Theme.ringTransparency(fraction)
		end
		local fade = if fighter.Alive then 0 else FALLEN
		entry.Disc.BackgroundColor3 = if fighter.Alive then Theme.Colors.Plate else Theme.Colors.Chalk
		entry.Disc.BackgroundTransparency = fade
		entry.Edge.Transparency = fade
		entry.Initial.TextTransparency = fade
		entry.Initial.TextColor3 = if fighter.Alive then Theme.Colors.PanelRaised else Theme.Colors.Text
		entry.Initial.Text = if fighter.Alive then initialOf(fighter.Name) else Theme.Glyphs.Close
	end

	local function refreshRosters(snapshot: Types.MatchSnapshot)
		local counts: { [string]: number } = { Ours = 0, Theirs = 0 }
		for teamIndex, team in ipairs(snapshot.Teams) do
			local side = if teamIndex == snapshot.LocalTeam then "Ours" else "Theirs"
			for _, fighter in ipairs(team) do
				counts[side] += 1
				refreshMember(member(side, counts[side]), fighter)
			end
		end
		for side, list in pairs(members) do
			for slot = counts[side] + 1, #list do
				list[slot].Disc.Visible = false
			end
		end
		-- A duel's two scores already say who is who: the discs are for a team.
		rosters.Visible = math.max(counts.Ours, counts.Theirs) > 1
	end

	local function set(_self: ScoreBand, snapshot: Types.MatchSnapshot?)
		if snapshot == nil then
			plate.Instance.Visible = false
			lastSecond = -1
			return
		end
		local won, lost = 0, 0
		for index, score in ipairs(snapshot.Scores) do
			if index == snapshot.LocalTeam then
				won = score
			else
				lost = math.max(lost, score)
			end
		end
		oursScore.Text = tostring(won)
		theirsScore.Text = tostring(lost)
		roundLabel.Text = localize.t("match.band", {
			round = snapshot.Round,
			mode = localize.t(MODE_KEY .. snapshot.ModeId),
		})

		local seconds = math.max(0, math.ceil(snapshot.SecondsLeft))
		local counting = snapshot.Phase == COUNTDOWN_PHASE
		timerLabel.Visible = not counting
		if not counting then
			timerLabel.Text = localize.t("match.timeLeft", { seconds = seconds })
			if
				snapshot.Phase == PLAYING_PHASE
				and seconds <= LAST_SECONDS
				and seconds > 0
				and seconds ~= lastSecond
			then
				Motion.punch(timerScale, LAST_PUNCH)
				UiSound.play(TICK_SOUND)
			end
		end
		lastSecond = seconds

		refreshRosters(snapshot)
		plate:Grow(BAND_ENTER_SCALE)
	end

	local function destroy(_self: ScoreBand)
		trove:Destroy()
	end

	local object: ScoreBand = {
		Instance = plate.Instance,
		Set = set,
		Destroy = destroy,
	}
	return object
end

return ScoreBand
