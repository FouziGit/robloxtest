--!strict
-- ComboRow: the sequence the player is pressing, as chips in the pigments they pressed (D-147). HudController
-- places it and feeds it the sequence, the casts the server accepted and the sequences that broke.
--
-- Chips grow into the row and collapse out of it (docs/ART_BIBLE.md rule 3: nothing appears): a fourth press
-- adds one chip, and a cast folds the row shut. Beside them, the chain counter -- glyphs the SERVER accepted
-- in a row inside its chain window, shown from the second one -- and, for a new player, ghost chips: the
-- recipe to press, drawn after the live chips, faint, never counted as a sequence (OnboardingController).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Motion = require(script.Parent.Parent.Motion)
local PigmentConfig = require(Shared:WaitForChild("Config"):WaitForChild("PigmentConfig"))
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	Parent: Instance,
	Localize: Localizer,
	AnchorPoint: Vector2,
	Position: UDim2,
}

export type ComboRow = {
	Instance: Frame,
	SetSequence: (self: ComboRow, sequence: { string }) -> (),
	-- `pigments` as ghost chips, or none with nil.
	ShowGhosts: (self: ComboRow, pigments: { string }?) -> (),
	-- One accepted cast, with the chain length the server counted for it.
	Cast: (self: ComboRow, chain: number) -> (),
	-- The chain is over: the counter fades, and the next cast starts again at one.
	FadeStreak: (self: ComboRow) -> (),
	Destroy: (self: ComboRow) -> (),
}

local ComboRow = {}

local CHIP_SIZE = 36
local CHIP_COLLAPSED = UDim2.fromOffset(0, CHIP_SIZE)
local CHIP_OPEN = UDim2.fromOffset(CHIP_SIZE, CHIP_SIZE)
-- Two slots per press: the live chip and, just to its right, the chip that is folding away because the
-- sequence changed under it. Sharing one LayoutOrder left the two in an order Roblox does not define, so
-- a replacement could render to the LEFT of what it replaced.
local CHIP_ORDER_STRIDE = 2
local STREAK_ORDER = 100
local STREAK_MIN_SHOWN = 2
local STREAK_POP_SCALE = 1.4
local GHOST_ORDER = 200
local GHOST_TRANSPARENCY = 0.6

local function makeChip(index: number, pigment: string): Frame
	local chip = Instance.new("Frame")
	chip.Name = "Chip" .. index
	chip.LayoutOrder = index * CHIP_ORDER_STRIDE
	chip.Size = CHIP_COLLAPSED
	chip.ClipsDescendants = true
	chip.BackgroundColor3 = Theme.pigmentColor(pigment)
	chip.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = chip
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.FontFace = Theme.Fonts.Bold
	glyph.TextSize = Theme.Sizes.TextLarge
	-- Charcoal on Orpiment, vellum on Indigo: the ink that reads on this pigment.
	glyph.TextColor3 = Theme.inkOn(chip.BackgroundColor3)
	glyph.Text = PigmentConfig.Sigils[pigment :: any] or ""
	glyph.Parent = chip
	return chip
end

function ComboRow.new(props: Props): ComboRow
	local trove = Trove.new()
	local localize = props.Localize
	local chips: { Frame } = {}
	local chipPigments: { string } = {}
	local ghosts: { Frame } = {}
	local streak = 0
	-- Bumped by every change, so the timer that ends a chain cannot end the one that replaced it.
	local streakGeneration = 0

	local row = Instance.new("Frame")
	row.Name = "Combo"
	row.BackgroundTransparency = 1
	row.AnchorPoint = props.AnchorPoint
	row.Position = props.Position
	row.Size = UDim2.fromOffset(0, CHIP_SIZE)
	row.AutomaticSize = Enum.AutomaticSize.X
	trove:Add(row)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = row

	local streakLabel = Instance.new("TextLabel")
	streakLabel.Name = "Streak"
	streakLabel.BackgroundTransparency = 1
	streakLabel.LayoutOrder = STREAK_ORDER
	streakLabel.Size = UDim2.fromOffset(0, CHIP_SIZE)
	streakLabel.AutomaticSize = Enum.AutomaticSize.X
	streakLabel.FontFace = Theme.Fonts.Numeric
	streakLabel.TextSize = Theme.Sizes.TextHero
	streakLabel.TextColor3 = Theme.Colors.Text
	streakLabel.TextStrokeColor3 = Theme.Colors.TextInverse
	streakLabel.TextStrokeTransparency = 0.4
	streakLabel.Text = ""
	streakLabel.Visible = false
	local streakScale = Instance.new("UIScale")
	streakScale.Name = "Scale"
	streakScale.Parent = streakLabel
	streakLabel.Parent = row
	trove:Add(function()
		Motion.cancel(streakScale)
	end)

	row.Parent = props.Parent

	-- The chips that still match the new sequence stay; the rest collapse out of the row and the new ones
	-- grow into it.
	local function setSequence(_self: ComboRow, sequence: { string })
		local keep = 0
		while keep < #chipPigments and keep < #sequence and chipPigments[keep + 1] == sequence[keep + 1] do
			keep += 1
		end
		for index = #chipPigments, keep + 1, -1 do
			local chip = chips[index]
			chips[index] = nil
			chipPigments[index] = nil
			chip.Name = chip.Name .. "Out"
			chip.LayoutOrder += 1
			Motion.to(chip, { Size = CHIP_COLLAPSED }, "UiSnappy", function()
				chip:Destroy()
			end)
		end
		for index = keep + 1, #sequence do
			local chip = makeChip(index, sequence[index])
			chip.Parent = row
			chips[index] = chip
			chipPigments[index] = sequence[index]
			Motion.to(chip, { Size = CHIP_OPEN }, "UiSnappy")
		end
	end

	-- The ghosts grow in and fold out like the live chips, so the hint obeys the same rule as everything
	-- else: nothing appears.
	local function showGhosts(_self: ComboRow, pigments: { string }?)
		for _, ghost in ipairs(ghosts) do
			Motion.to(ghost, { Size = CHIP_COLLAPSED }, "UiSnappy", function()
				ghost:Destroy()
			end)
		end
		table.clear(ghosts)
		if pigments == nil then
			return
		end
		for index, pigment in ipairs(pigments) do
			local chip = makeChip(index, pigment)
			chip.Name = "Ghost" .. index
			chip.LayoutOrder = GHOST_ORDER + index
			chip.BackgroundTransparency = GHOST_TRANSPARENCY
			local glyph = chip:FindFirstChild("Glyph")
			if glyph ~= nil and glyph:IsA("TextLabel") then
				glyph.TextTransparency = GHOST_TRANSPARENCY
			end
			chip.Parent = row
			table.insert(ghosts, chip)
			Motion.to(chip, { Size = CHIP_OPEN }, "UiSnappy")
		end
	end

	local function refreshStreak()
		streakLabel.Text = localize.t("hud.sequence.streak", { count = streak })
		streakLabel.Visible = streak >= STREAK_MIN_SHOWN
	end

	-- The chain is over: it fades rather than vanishing, and the next cast starts again at one.
	local function fadeStreak(_self: ComboRow?)
		if streak == 0 then
			return
		end
		streak = 0
		streakGeneration += 1
		if not streakLabel.Visible then
			return
		end
		-- What is lost fades out. Not Cinnabar: nothing is about to hit the player (rule 7).
		streakLabel.TextColor3 = Theme.Colors.TextMuted
		Motion.to(streakScale, { Scale = 0 }, "Ui", function()
			refreshStreak()
			Motion.set(streakScale, { Scale = 1 })
		end)
	end

	-- The counter lands on every cast of a chain and ends itself when the window passes without another one.
	local function cast(_self: ComboRow, chain: number)
		streak = math.max(1, chain)
		streakGeneration += 1
		local generation = streakGeneration
		refreshStreak()
		if streakLabel.Visible then
			-- The count lands: it drops onto the row from larger than itself and the spring settles it.
			streakLabel.TextColor3 = Theme.Colors.Text
			Motion.set(streakScale, { Scale = STREAK_POP_SCALE })
			Motion.to(streakScale, { Scale = 1 }, "UiSnappy")
		end
		task.delay(GameConfig.Combo.ChainWindowSeconds, function()
			if streakGeneration == generation then
				fadeStreak(nil)
			end
		end)
	end

	local function destroy(_self: ComboRow)
		trove:Destroy()
	end

	local object: ComboRow = {
		Instance = row,
		SetSequence = setSequence,
		ShowGhosts = showGhosts,
		Cast = cast,
		FadeStreak = fadeStreak,
		Destroy = destroy,
	}
	return object
end

return ComboRow
