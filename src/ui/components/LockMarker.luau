--!strict
-- LockMarker: the mark over the opponent a lock is on (LockOnController, D-115, D-147). The board's diamond: the
-- sheet in a thick ink outline, so it reads over the page and over a dark body alike, floating above the
-- target's head and drawn over everything: a lock that cannot be seen behind a wall is a lock nobody trusts.
-- Over it a small ink pill names the target and its health, "Rival_07 · 64". It stays in ink and the sheet
-- (docs/ART_BIBLE.md rule 1: it is drawn in the world): a locked target is not a danger to you, so it is
-- never red.
--
-- It clamps down onto the target when a lock is taken and lifts off when it is let go, on the interface's
-- springs (Motion); it never simply appears or vanishes. Near the distance a lock breaks at, the diamond
-- turns chalk and breathes, in its ink outline. With the target out of view, a chevron at the edge of the
-- screen points to it; a press that finds nothing to lock says so. One for the session: built once by
-- LockOnController and re-aimed at each new target.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Motion = require(script.Parent.Parent.Motion)
local ScreenEdge = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pure"):WaitForChild("ScreenEdge"))
local ScreenRoot = require(script.Parent.ScreenRoot)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type LockMarker = {
	Show: (self: LockMarker, adornee: BasePart, lift: number) -> (),
	-- What the pill over the diamond says: the target's name, and its health, followed while it shows.
	SetTarget: (self: LockMarker, name: string, humanoid: Humanoid) -> (),
	-- Near the distance the lock breaks at: the diamond turns chalk and breathes.
	SetWarning: (self: LockMarker, warning: boolean) -> (),
	-- The target is out of view, toward `direction` from the middle of the screen (screen axes), or in view.
	SetOffscreen: (self: LockMarker, direction: Vector2?) -> (),
	-- A press found nothing to lock.
	ShowMiss: (self: LockMarker) -> (),
	Hide: (self: LockMarker) -> (),
}

local LockMarker = {}

-- How much larger the mark starts when a lock is taken, and ends when it is let go.
local TAKE_FROM_SCALE = 1.8
local LET_GO_SCALE = 0.5
-- The ink outline of the diamond, inside its frame.
local INK_THICKNESS = 4
-- The pill over the diamond, in pixels (a billboard's own): as wide as its words up to the widest, this tall,
-- this far over the diamond, and its inset.
local PLATE_MAX_WIDTH = 180
local PLATE_HEIGHT = 22
local PLATE_GAP = 6
local PLATE_CORNER = 6
local PLATE_PADDING_Y = 2
local PLATE_PADDING_X = 8
local PLATE_TRANSPARENCY = 0.1
local NAME_TEXT = 14
local TARGET_KEY = "hud.lock.target"
-- A lock about to break: the diamond turns chalk and breathes between these transparencies.
local WARN_FROM, WARN_TO = 0, 0.5
-- The chevron: an ink disc with the sheet's arrow, this far inside the safe area.
local CHEVRON = 32
local CHEVRON_INSET = 24
local ARROW_TEXT = 18
-- "No target": a pill a little under the middle of the screen, for this long.
local MISS_HEIGHT = 0.58
local MISS_TEXT = 16
local MISS_PILL = 30
local MISS_SECONDS = 0.8
local MISS_FROM_SCALE = 0.8
local MISS_KEY = "hud.lock.none"

local function blank(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- Builds the mark, hidden, under `parent` (the local PlayerGui), `size` pixels across.
function LockMarker.new(parent: Instance, size: number, localize: Localizer): LockMarker
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LockMarker"
	-- Room for the diamond's corners at its widest, when it clamps down from TAKE_FROM_SCALE.
	billboard.Size = UDim2.fromOffset(size * 3, size * 3)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	billboard.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = 1

	-- Turned a quarter of a right angle: a diamond, the one shape no other mark in the game uses. The sheet,
	-- in the ink's outline; both fade in with the lock.
	local diamond = blank("Diamond", billboard)
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromOffset(size, size)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = Theme.Colors.PanelRaised
	scale.Parent = diamond
	local ink = Theme.stroke(diamond, "Accent", INK_THICKNESS)
	ink.Transparency = 1

	-- The pill, on a billboard of its own centred where the diamond is: the pill stands in its upper half, over
	-- the diamond, as wide as its words.
	local plateBoard = Instance.new("BillboardGui")
	plateBoard.Name = "LockPlate"
	plateBoard.Size = UDim2.fromOffset(PLATE_MAX_WIDTH, (size / 2 + PLATE_GAP + PLATE_HEIGHT) * 2)
	plateBoard.AlwaysOnTop = true
	plateBoard.LightInfluence = 0
	plateBoard.ResetOnSpawn = false
	plateBoard.Enabled = false
	plateBoard.Parent = parent
	local plate = blank("Plate", plateBoard)
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 0.5, -(size / 2 + PLATE_GAP))
	plate.Size = UDim2.fromOffset(0, PLATE_HEIGHT)
	plate.AutomaticSize = Enum.AutomaticSize.X
	plate.BackgroundColor3 = Theme.Colors.Plate
	Theme.corner(plate, PLATE_CORNER)
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0, PLATE_PADDING_Y)
	inset.PaddingBottom = UDim.new(0, PLATE_PADDING_Y)
	inset.PaddingLeft = UDim.new(0, PLATE_PADDING_X)
	inset.PaddingRight = UDim.new(0, PLATE_PADDING_X)
	inset.Parent = plate
	local plateScale = Instance.new("UIScale")
	plateScale.Parent = plate
	local function applyTransparency()
		plate.BackgroundTransparency = PLATE_TRANSPARENCY * UiPrefs.transparency()
	end
	applyTransparency()
	UiPrefs.Changed:Connect(applyTransparency)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.AutomaticSize = Enum.AutomaticSize.X
	nameLabel.Size = UDim2.fromScale(0, 1)
	nameLabel.FontFace = Theme.Fonts.Bold
	nameLabel.TextSize = NAME_TEXT
	nameLabel.TextColor3 = Theme.Colors.PanelRaised
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	-- A long name is cut at the billboard's edge rather than run past it.
	local widest = Instance.new("UISizeConstraint")
	widest.MaxSize = Vector2.new(PLATE_MAX_WIDTH - PLATE_PADDING_X * 2, math.huge)
	widest.Parent = nameLabel
	nameLabel.Parent = plate

	-- The screen-space half: the chevron and the miss, on the HUD's layer, inside the safe area.
	local overlay = ScreenRoot.new({ Name = "LockOverlay", DisplayOrder = Theme.Layers.Hud, Parent = parent })
	local chevron = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Corner = Theme.Pill,
		Size = UDim2.fromOffset(CHEVRON, CHEVRON),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = overlay.Content,
		Name = "Chevron",
	})
	chevron.Instance.Visible = false
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.FontFace = Theme.Fonts.Bold
	arrow.TextSize = ARROW_TEXT
	arrow.TextColor3 = Theme.Colors.PanelRaised
	arrow.Text = Theme.Glyphs.Play
	arrow.ZIndex = 3
	arrow.Parent = chevron.Face

	local miss = blank("NoTarget", overlay.Content)
	miss.AnchorPoint = Vector2.new(0.5, 0.5)
	miss.Position = UDim2.fromScale(0.5, MISS_HEIGHT)
	miss.Size = UDim2.fromOffset(0, MISS_PILL)
	miss.AutomaticSize = Enum.AutomaticSize.X
	miss.Visible = false
	local missScale = Instance.new("UIScale")
	missScale.Parent = miss
	-- The pill hosts its plate: it is as wide as its word (Sticker's Host, D-170).
	Sticker.new({ Kind = "Plate", Fill = Theme.Colors.Plate, Corner = Theme.Pill, Host = miss })
	local missLabel = Instance.new("TextLabel")
	missLabel.Name = "Text"
	missLabel.BackgroundTransparency = 1
	missLabel.AutomaticSize = Enum.AutomaticSize.X
	missLabel.Size = UDim2.fromScale(0, 1)
	missLabel.ZIndex = 3
	missLabel.FontFace = Theme.Fonts.Bold
	missLabel.TextSize = MISS_TEXT
	missLabel.TextColor3 = Theme.Colors.TextInverse
	missLabel.Text = localize.t(MISS_KEY)
	local missPadding = Instance.new("UIPadding")
	missPadding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	missPadding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	missPadding.Parent = missLabel
	missLabel.Parent = miss

	-- Which Show a Hide's settling belongs to: a lock let go and retaken at once must not be hidden by
	-- the first one's fade finishing.
	local generation = 0
	local missToken = 0
	local following: { RBXScriptConnection } = {}
	local stopWarning: (() -> ())? = nil
	local offscreen = false

	local function unfollow()
		for _, connection in ipairs(following) do
			connection:Disconnect()
		end
		table.clear(following)
	end

	local function endWarning()
		local stop = stopWarning
		stopWarning = nil
		if stop ~= nil then
			stop()
		end
		Motion.cancel(diamond)
		diamond.BackgroundColor3 = Theme.Colors.PanelRaised
	end

	local function setOffscreen(_self: LockMarker?, direction: Vector2?)
		if direction == nil then
			if offscreen then
				offscreen = false
				chevron.Instance.Visible = false
			end
			return
		end
		local area = overlay.Content.AbsoluteSize / overlay:GetScale()
		local reach = CHEVRON_INSET + CHEVRON / 2
		local x, y, angle = ScreenEdge.toward(direction.X, direction.Y, area.X / 2 - reach, area.Y / 2 - reach)
		if x == nil or y == nil or angle == nil then
			return
		end
		offscreen = true
		chevron.Instance.Position = UDim2.fromOffset(area.X / 2 + x, area.Y / 2 + y)
		chevron.Instance.Rotation = angle
		chevron.Instance.Visible = true
	end

	local function show(_self: LockMarker, adornee: BasePart, lift: number)
		generation += 1
		for _, board in ipairs({ billboard, plateBoard }) do
			board.Adornee = adornee
			board.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
			board.Enabled = true
		end
		Motion.set(scale, { Scale = TAKE_FROM_SCALE })
		Motion.to(scale, { Scale = 1 }, "UiSnappy")
		Motion.to(ink, { Transparency = 0 }, "UiSnappy")
		Motion.to(diamond, { BackgroundTransparency = 0 }, "UiSnappy")
		Motion.set(plateScale, { Scale = 0 })
		Motion.to(plateScale, { Scale = 1 }, "UiPop")
	end

	-- The name and the health left, rewritten as the target's health moves; a target is never below nothing.
	local function setTarget(_self: LockMarker, name: string, humanoid: Humanoid)
		unfollow()
		local function refresh()
			local health = math.max(0, math.ceil(humanoid.Health))
			nameLabel.Text = localize.t(TARGET_KEY, { name = name, health = health })
		end
		refresh()
		table.insert(following, humanoid:GetPropertyChangedSignal("Health"):Connect(refresh))
	end

	local function setWarning(_self: LockMarker, warning: boolean)
		if warning == (stopWarning ~= nil) then
			return
		end
		if not warning then
			endWarning()
			Motion.to(diamond, { BackgroundTransparency = 0 }, "UiSnappy")
			return
		end
		diamond.BackgroundColor3 = Theme.Colors.Chalk
		stopWarning = Motion.loop(
			diamond,
			{ BackgroundTransparency = WARN_FROM },
			{ BackgroundTransparency = WARN_TO },
			"Ui"
		)
	end

	local function showMiss(_self: LockMarker)
		missToken += 1
		local token = missToken
		miss.Visible = true
		Motion.set(missScale, { Scale = MISS_FROM_SCALE })
		Motion.to(missScale, { Scale = 1 }, "UiPop")
		task.delay(MISS_SECONDS, function()
			if token ~= missToken then
				return
			end
			Motion.to(missScale, { Scale = 0 }, "UiExit", function()
				if token == missToken then
					miss.Visible = false
				end
			end)
		end)
	end

	local function hide(_self: LockMarker)
		unfollow()
		setOffscreen(nil, nil)
		if not billboard.Enabled then
			return
		end
		endWarning()
		generation += 1
		local mine = generation
		Motion.to(scale, { Scale = LET_GO_SCALE }, "UiSnappy")
		Motion.to(diamond, { BackgroundTransparency = 1 }, "UiSnappy")
		Motion.to(plateScale, { Scale = 0 }, "UiSnappy")
		Motion.to(ink, { Transparency = 1 }, "UiSnappy", function()
			if generation == mine then
				billboard.Enabled = false
				plateBoard.Enabled = false
			end
		end)
	end

	return {
		Show = show,
		SetTarget = setTarget,
		SetWarning = setWarning,
		SetOffscreen = setOffscreen,
		ShowMiss = showMiss,
		Hide = hide,
	}
end

return LockMarker
