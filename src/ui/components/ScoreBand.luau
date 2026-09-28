--!strict
-- ScoreBand: the match, on an ink plate at the top of the screen while one is held (D-147). One band of
-- HudController's top-centre column, at the LayoutOrder the HUD gives it; it goes as soon as the snapshot is nil.
--
--   our score      a cyan pill: cyan is us (docs/ART_BIBLE.md rule 7)
--   the middle     the round's clock, with a pip per round of the series under it (the sheet for a round we
--                  took, chalk for one we lost, an empty ring for one still to play); before a round starts,
--                  the round line and the count
--   their score    an ink pill ringed with the sheet. Not red: red would sit beside their name for a whole
--                  match, and red means only what is about to hit you (D-89)
--   the rosters    a disc per fighter, ours ringed cyan and theirs in the sheet, each ring the fighter's health
--                  going round it; a fallen one turns chalk under a cross
--
-- The last ten seconds of a round tick and punch the clock, and it never changes colour: a clock is not a
-- danger. A fight surface: nothing here wears a value colour (rule 11). Everything is pooled, so a snapshot
-- four times a second rebuilds nothing, and a health ring is only rewritten when its health moved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local HudPlate = require(script.Parent.HudPlate)
local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
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

local BAND_WIDTH = 440
-- A band that is shown grows into place: rule 3 of docs/ART_BIBLE.md, nothing appears.
local BAND_ENTER_SCALE = 0.9
local GAP = 8
local PILL_WIDTH = 96
local PILL_HEIGHT = 52
local PILL_ELEVATION = 5
local RING_INSET = 3
local ROUND_TEXT = 16
local TIMER_TEXT = 32
local PIP = 10
local PIP_GAP = 6
local MEMBER = 28
local MEMBER_TEXT = 14
local ALLY_RING = 3
local FALLEN = 0.6
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

local function listFrame(
	name: string,
	size: UDim2,
	order: number,
	direction: Enum.FillDirection,
	gap: number,
	parent: Instance
): (Frame, UIListLayout)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = size
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
	frame.Parent = parent
	return frame, layout
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
	local pips: { Frame } = {}
	local members: { [string]: { Member } } = { Ours = {}, Theirs = {} }
	local lastSecond = -1

	local plate = HudPlate.new({
		Name = "Match",
		Width = BAND_WIDTH,
		Gap = GAP,
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	})
	trove:Add(function()
		plate:Destroy()
	end)
	local content = plate.Content

	local top = listFrame("Score", UDim2.new(1, 0, 0, PILL_HEIGHT), 1, Enum.FillDirection.Horizontal, GAP, content)

	-- Ours: the cyan pill, pressable-looking but pressed by nothing.
	local ours = Instance.new("Frame")
	ours.Name = "Ours"
	ours.BackgroundTransparency = 1
	ours.Size = UDim2.fromOffset(PILL_WIDTH, PILL_HEIGHT)
	ours.LayoutOrder = 1
	local oursPill = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.Ally,
		Elevation = PILL_ELEVATION,
		Size = UDim2.fromScale(1, 1),
		Parent = ours,
		Name = "Pill",
	})
	trove:Add(function()
		oursPill:Destroy()
	end)
	local oursScore = textLabel("Value", Theme.Fonts.Numeric, Theme.Sizes.NumLarge, Theme.Colors.Text)
	oursScore.Size = UDim2.fromScale(1, 1)
	oursScore.Parent = oursPill.Face
	ours.Parent = top

	-- The middle: the round and the count before a round, the clock and the series' pips during one.
	local middle = listFrame("Clock", UDim2.fromScale(0, 1), 2, Enum.FillDirection.Vertical, 0, top)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = middle
	local roundLabel = textLabel("Round", Theme.Fonts.Bold, ROUND_TEXT, Theme.Colors.TextInverse)
	roundLabel.Size = UDim2.new(1, 0, 0, ROUND_TEXT + 4)
	roundLabel.LayoutOrder = 1
	roundLabel.TextTruncate = Enum.TextTruncate.AtEnd
	roundLabel.Parent = middle
	local timerLabel = textLabel("Timer", Theme.Fonts.Numeric, TIMER_TEXT, Theme.Colors.TextInverse)
	timerLabel.Size = UDim2.new(1, 0, 0, TIMER_TEXT)
	timerLabel.LayoutOrder = 2
	timerLabel.Parent = middle
	local timerScale = Instance.new("UIScale")
	timerScale.Parent = timerLabel
	local pipRow = listFrame("Rounds", UDim2.new(1, 0, 0, PIP), 3, Enum.FillDirection.Horizontal, PIP_GAP, middle)

	-- Theirs: ink ringed with the sheet, never red.
	local theirs = Instance.new("Frame")
	theirs.Name = "Theirs"
	theirs.BorderSizePixel = 0
	theirs.BackgroundColor3 = Theme.Colors.Plate
	theirs.Size = UDim2.fromOffset(PILL_WIDTH, PILL_HEIGHT - PILL_ELEVATION)
	theirs.LayoutOrder = 3
	Theme.corner(theirs, Theme.Pill)
	local theirsRing = Instance.new("Frame")
	theirsRing.Name = "Ring"
	theirsRing.BackgroundTransparency = 1
	theirsRing.Position = UDim2.fromOffset(RING_INSET, RING_INSET)
	theirsRing.Size = UDim2.new(1, -RING_INSET * 2, 1, -RING_INSET * 2)
	Theme.corner(theirsRing, Theme.Pill)
	Theme.stroke(theirsRing, "PanelRaised", Theme.Sizes.StrokeThin)
	theirsRing.Parent = theirs
	local theirsScore = textLabel("Value", Theme.Fonts.Numeric, Theme.Sizes.NumLarge, Theme.Colors.TextInverse)
	theirsScore.Size = UDim2.fromScale(1, 1)
	theirsScore.Parent = theirs
	theirs.Parent = top

	-- The rosters: ours under our pill, theirs under theirs.
	local rosters = listFrame("Roster", UDim2.new(1, 0, 0, MEMBER), 2, Enum.FillDirection.Horizontal, GAP, content)
	local sides: { [string]: Frame } = {}
	for order, side in ipairs({ "Ours", "Theirs" }) do
		local half, halfLayout =
			listFrame(side, UDim2.new(0.5, -GAP / 2, 1, 0), order, Enum.FillDirection.Horizontal, PIP_GAP, rosters)
		-- Each side reads outward from the middle: ours from the left edge, theirs from the right.
		halfLayout.HorizontalAlignment = if side == "Ours"
			then Enum.HorizontalAlignment.Left
			else Enum.HorizontalAlignment.Right
		sides[side] = half
	end

	trove:Add(function()
		Motion.cancel(timerScale)
	end)

	-- A round of the series: the sheet for ours, chalk for theirs, an empty ring for one still to play.
	local function pip(index: number): Frame
		local existing: Frame? = pips[index]
		if existing ~= nil then
			existing.Visible = true
			return existing
		end
		local frame = Instance.new("Frame")
		frame.Name = "Round" .. index
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromOffset(PIP, PIP)
		frame.LayoutOrder = index
		Theme.corner(frame, Theme.Pill)
		Theme.stroke(frame, "Chalk", Theme.Sizes.StrokeThin)
		frame.Parent = pipRow
		pips[index] = frame
		return frame
	end

	local function refreshPips(total: number, won: number, lost: number)
		for index = 1, total do
			local frame = pip(index)
			local played = index <= won + lost
			frame.BackgroundTransparency = if played then 0 else 1
			frame.BackgroundColor3 = if index <= won then Theme.Colors.PanelRaised else Theme.Colors.Chalk
		end
		for index = total + 1, #pips do
			pips[index].Visible = false
		end
	end

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
		local initial = textLabel("Initial", Theme.Fonts.Label, MEMBER_TEXT, Theme.Colors.TextInverse)
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
		entry.Initial.TextColor3 = if fighter.Alive then Theme.Colors.TextInverse else Theme.Colors.Text
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
	end

	local function set(_self: ScoreBand, snapshot: Types.MatchSnapshot?)
		if snapshot == nil then
			plate.Instance.Visible = false
			lastSecond = -1
			return
		end
		-- Best-of series: winning RoundsToWin rounds takes at most 2 * RoundsToWin - 1 rounds.
		local total = math.max(snapshot.Round, snapshot.RoundsToWin * 2 - 1)
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
		refreshPips(total, won, lost)

		local seconds = math.max(0, math.ceil(snapshot.SecondsLeft))
		local counting = snapshot.Phase == COUNTDOWN_PHASE
		roundLabel.Visible = counting
		roundLabel.Text = localize.t("match.round", { round = snapshot.Round, total = total })
		pipRow.Visible = not counting
		if counting then
			timerLabel.Text = localize.t("match.countdown", { seconds = seconds })
		else
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
