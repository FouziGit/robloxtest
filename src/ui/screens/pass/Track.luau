--!strict
-- Track: the battle pass's tiers as a road that scrolls sideways (D-147). A column per tier: its free reward
-- above the line, its premium one below (pass/Cell), and its seal on the line -- chalk ahead, the chapter's
-- purple behind, and the current tier in the primary yellow on a brush stroke. The line itself is the inkwell,
-- filled in yellow up to the tier reached. The view comes to rest on the current tier on a spring.
--
-- A fifty-tier pass is never built at once: the columns around the current tier are built when the screen
-- opens, and the rest ten at a time as the view nears them. Every reward waiting to be claimed wiggles on ONE
-- shared breath (Breath), however many there are, and only while the screen asks for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local Breath = require(script.Parent.Parent.Parent.Breath)
local Cell = require(script.Parent.Cell)
local Motion = require(script.Parent.Parent.Parent.Motion)
local ProgressBar = require(script.Parent.Parent.Parent.components.ProgressBar)
local Seal = require(script.Parent.Parent.Parent.components.Seal)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Props = {
	Tiers: { BattlepassConfig.Tier },
	Localize: Cell.Localizer,
	-- What a cell's Claim button asks for.
	OnClaim: (tier: number, track: Cell.Track) -> (),
	LayoutOrder: number?,
	Parent: Instance,
}

export type Track = {
	Instance: ScrollingFrame,
	-- Builds the columns of [from, to] not built yet.
	Ensure: (self: Track, from: number, to: number) -> (),
	-- Paints every built column for `season`: seals, the line, and what each reward allows.
	Paint: (self: Track, season: Types.BattlepassSeasonData?) -> (),
	-- Springs the view to `tier`, from wherever it is.
	CentreOn: (self: Track, tier: number) -> (),
	SetWiggling: (self: Track, on: boolean) -> (),
	-- The Claim button of `tier`, when one of its rewards waits.
	ClaimOf: (self: Track, tier: number) -> GuiObject?,
	Destroy: (self: Track) -> (),
}

type Column = { Tier: number, Seal: Seal.Seal, Swash: GuiObject, Cells: { Cell.Cell } }

local Track = {}

local PITCH = 132
local CELL_WIDTH = 112
local CELL_HEIGHT = 112
local LINE_ZONE = 48
local LINE_HEIGHT = 8
local TIER_SEAL = 36
local SWASH_WIDTH = 60
local SWASH_HEIGHT = 12
local PADDING = 16
local CHUNK = 10
-- A waiting reward's wiggle: this many degrees each way, once every WiggleEverySeconds.
local WIGGLE_DEGREES = 2

-- A column's two rewards, above the line and below it.
local TRACKS: { Cell.Track } = { "Free", "Premium" }

function Track.new(props: Props): Track
	local trove = Trove.new()
	local tiers = props.Tiers
	local count = #tiers
	local columns: { [number]: Column } = {}
	local season: Types.BattlepassSeasonData? = nil
	local wiggle: Breath.Reader? = nil
	local wiggleConnection: RBXScriptConnection? = nil

	local frame = Instance.new("ScrollingFrame")
	frame.Name = "Track"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(0, 1)
	frame.LayoutOrder = props.LayoutOrder or 0
	-- Sideways along the tiers, and down on a phone too short for both cells.
	frame.ScrollingDirection = Enum.ScrollingDirection.XY
	frame.ScrollBarThickness = Theme.Sizes.PaddingSmall
	frame.ScrollBarImageColor3 = Theme.Colors.Accent
	frame.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	frame.Selectable = false
	trove:Add(frame)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = frame

	-- Where the view is springing to: its centre, in design units along the road.
	local scroll = Instance.new("NumberValue")
	scroll.Name = "Scroll"
	scroll.Parent = frame
	trove:Add(function()
		Motion.cancel(scroll)
	end)

	local line = ProgressBar.new({
		Color = Theme.Colors.Primary,
		Size = UDim2.fromOffset(count * PITCH - (PITCH - CELL_WIDTH), LINE_HEIGHT),
		Name = "Line",
		Parent = frame,
	})
	trove:Add(function()
		line:Destroy()
	end)

	local function columnX(tier: number): number
		return PADDING + (tier - 1) * PITCH
	end

	-- Sizes the road and places everything built on it, for the cell height the current scale needs.
	local function layout()
		local cell = Cell.height(CELL_HEIGHT)
		local lineY = PADDING + cell + LINE_ZONE / 2
		frame.CanvasSize = UDim2.fromOffset(PADDING * 2 + count * PITCH, PADDING * 2 + cell * 2 + LINE_ZONE)
		line.Instance.Position = UDim2.fromOffset(PADDING + (PITCH - CELL_WIDTH) / 2, lineY - LINE_HEIGHT / 2)
		for tier, column in pairs(columns) do
			local centre = columnX(tier) + PITCH / 2
			column.Seal.Instance.Position = UDim2.fromOffset(centre, lineY)
			column.Swash.Position = UDim2.fromOffset(centre, lineY + TIER_SEAL / 2)
			for _, slot in ipairs(column.Cells) do
				slot.Frame.Size = UDim2.fromOffset(CELL_WIDTH, cell)
				slot.Frame.Position = UDim2.fromOffset(
					columnX(tier) + (PITCH - CELL_WIDTH) / 2,
					if slot.Track == "Free" then PADDING else PADDING + cell + LINE_ZONE
				)
			end
		end
	end
	trove:Add(Theme.bindScale(layout))

	local function paintColumn(column: Column)
		local reached = if season ~= nil then season.Tier else 1
		local tier = column.Tier
		column.Seal:SetFill(
			if tier == reached
				then Theme.Colors.Primary
				elseif tier < reached then Theme.Colors.Epic
				else Theme.Colors.Chalk
		)
		column.Swash.Visible = tier == reached
		for _, slot in ipairs(column.Cells) do
			slot:Paint(Cell.state(tier, slot.Track, season))
		end
	end

	local function buildColumn(tier: number)
		local seal = Seal.new({
			Text = tostring(tier),
			Fill = Theme.Colors.Chalk,
			Size = TIER_SEAL,
			Face = "Numeric",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = frame,
		})
		seal.Instance.ZIndex = 3
		-- The current tier stands on a brush stroke of the primary yellow.
		local swash: GuiObject
		local swashId = Theme.texture("BrushStroke")
		if swashId ~= "" then
			local image = Instance.new("ImageLabel")
			image.Image = swashId
			image.ImageColor3 = Theme.Colors.Primary
			image.BackgroundTransparency = 1
			image.ScaleType = Enum.ScaleType.Stretch
			swash = image
		else
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = Theme.Colors.Primary
			Theme.corner(bar, Theme.Pill)
			swash = bar
		end
		swash.Name = "Swash"
		swash.BorderSizePixel = 0
		swash.AnchorPoint = Vector2.new(0.5, 0.5)
		swash.Size = UDim2.fromOffset(SWASH_WIDTH, SWASH_HEIGHT)
		swash.ZIndex = 2
		swash.Visible = false
		swash.Parent = frame
		local cells: { Cell.Cell } = {}
		local def = tiers[tier]
		for index = 1, #TRACKS do
			local which: Cell.Track = TRACKS[index]
			local reward = if def == nil then nil elseif which == "Free" then def.Free else def.Premium
			if reward ~= nil then
				table.insert(
					cells,
					Cell.new(tier, which, reward, props.Localize, frame, function()
						props.OnClaim(tier, which)
					end)
				)
			end
		end
		local column: Column = { Tier = tier, Seal = seal, Swash = swash, Cells = cells }
		columns[tier] = column
		trove:Add(function()
			seal:Destroy()
			for _, slot in ipairs(cells) do
				slot:Destroy()
			end
		end)
	end

	local function ensure(_self: Track?, from: number, to: number)
		local built: { Column } = {}
		for tier = math.max(1, from), math.min(count, to) do
			if columns[tier] == nil then
				buildColumn(tier)
				table.insert(built, columns[tier])
			end
		end
		if #built > 0 then
			layout()
			for _, column in ipairs(built) do
				paintColumn(column)
			end
		end
	end

	-- Design units of the road per pixel of its canvas, whatever scales sit above it.
	local function unitsPerPixel(): number?
		local width = frame.AbsoluteCanvasSize.X
		if width <= 0 then
			return nil
		end
		return (PADDING * 2 + count * PITCH) / width
	end

	-- The tiers in view, and a chunk past each end, are built as the view nears them.
	trove:Connect(frame:GetPropertyChangedSignal("CanvasPosition"), function()
		local ratio = unitsPerPixel()
		if ratio == nil then
			return
		end
		local left = frame.CanvasPosition.X * ratio - PADDING
		local right = left + frame.AbsoluteWindowSize.X * ratio
		local first = math.floor(left / PITCH) + 1
		local last = math.ceil(right / PITCH)
		ensure(nil, math.floor((first - 1) / CHUNK) * CHUNK - CHUNK + 1, math.ceil(last / CHUNK) * CHUNK + CHUNK)
	end)

	-- The view follows the spring.
	trove:Connect(scroll.Changed, function(centre: number)
		local ratio = unitsPerPixel()
		if ratio == nil then
			return
		end
		local maximum = math.max(0, frame.AbsoluteCanvasSize.X - frame.AbsoluteWindowSize.X)
		local x = math.clamp(centre / ratio - frame.AbsoluteWindowSize.X / 2, 0, maximum)
		frame.CanvasPosition = Vector2.new(x, frame.CanvasPosition.Y)
	end)

	local function claimButtons(): { Instance }
		local buttons: { Instance } = {}
		for _, column in pairs(columns) do
			for _, slot in ipairs(column.Cells) do
				local claim = slot.Claim
				if claim ~= nil then
					table.insert(buttons, claim.Instance)
				end
			end
		end
		return buttons
	end

	local function setWiggling(_self: Track?, on: boolean)
		if on == (wiggle ~= nil) then
			return
		end
		local reader = wiggle
		if reader ~= nil then
			local connection = wiggleConnection
			if connection ~= nil then
				connection:Disconnect()
			end
			wiggleConnection = nil
			wiggle = nil
			reader.Leave()
			for _, button in ipairs(claimButtons()) do
				(button :: TextButton).Rotation = 0
			end
			return
		end
		-- Still between wiggles, and still under reduced motion (the breath rests at its first value).
		local joined = Breath.join("Wiggle", 0, 1, Theme.Timing.WiggleEverySeconds)
		wiggle = joined
		wiggleConnection = joined.Value.Changed:Connect(function(value: number)
			local rotation = WIGGLE_DEGREES * math.sin(value * 2 * math.pi)
			for _, button in ipairs(claimButtons()) do
				(button :: TextButton).Rotation = rotation
			end
		end)
	end
	trove:Add(function()
		setWiggling(nil, false)
	end)

	local function paint(_self: Track, next: Types.BattlepassSeasonData?)
		season = next
		local reached = if next ~= nil then next.Tier else 1
		line:SetProgress((reached - 0.5) / count)
		for _, column in pairs(columns) do
			paintColumn(column)
		end
	end

	local function centreOn(_self: Track, tier: number)
		local ratio = unitsPerPixel()
		local from = if ratio ~= nil
			then (frame.CanvasPosition.X + frame.AbsoluteWindowSize.X / 2) * ratio
			else columnX(1)
		Motion.set(scroll, { Value = from })
		Motion.to(scroll, { Value = columnX(tier) + PITCH / 2 }, "UiSnappy")
	end

	local function claimOf(_self: Track, tier: number): GuiObject?
		local column = columns[tier]
		if column == nil then
			return nil
		end
		for _, slot in ipairs(column.Cells) do
			local claim = slot.Claim
			if claim ~= nil then
				return claim.Instance
			end
		end
		return nil
	end

	local function destroy(_self: Track)
		trove:Destroy()
	end

	frame.Parent = props.Parent
	layout()

	local object: Track = {
		Instance = frame,
		Ensure = ensure,
		Paint = paint,
		CentreOn = centreOn,
		SetWiggling = setWiggling,
		ClaimOf = claimOf,
		Destroy = destroy,
	}
	return object
end

return Track
