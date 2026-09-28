--!strict
-- Icon: the interface's small pictures, built from Frames and the symbol blocks the engine's fallback is
-- proven to render, so none of them is an image to upload (D-147). Each is drawn in a square of `size`
-- design units, in fractions of that square, so one drawing serves every size. `color` is the ink of the
-- drawing where it has one; the coin, the deck, the invite and the shield carry their own colours.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared:WaitForChild("Util"):WaitForChild("Log"))
local PigmentConfig = require(Shared:WaitForChild("Config"):WaitForChild("PigmentConfig"))
local Theme = require(script.Parent.Parent.Theme)

local log = Log.new("Icon")

export type Name =
	"Coin"
	| "Drop"
	| "Lock"
	| "Clock"
	| "Check"
	| "Cross"
	| "Play"
	| "Back"
	| "Sliders"
	| "Podium"
	| "Deck"
	| "Pass"
	| "Calendar"
	| "Scroll"
	| "Invite"
	| "Burger"
	| "Shield"

local Icon = {}

-- The five pigments of the deck, in their order, fanned from -12 to +12 degrees.
local DECK_FAN = { -12, -6, 0, 6, 12 }

-- Names already reported as unknown, so a caller's typo warns once.
local warned: { [string]: boolean } = {}

-- A filled rectangle at fractions of the square, centred on (x, y), rounded by `corner` (a pill unless
-- told otherwise).
local function bar(
	parent: Instance,
	width: number,
	height: number,
	x: number,
	y: number,
	color: Color3,
	rotation: number?,
	corner: UDim?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(width, height)
	frame.Rotation = rotation or 0
	Theme.corner(frame, corner or Theme.Pill)
	frame.Parent = parent
	return frame
end

-- An outlined, empty rectangle: the page of a calendar, a quest's box.
local function box(parent: Instance, width: number, height: number, x: number, y: number, color: Color3): Frame
	local frame = bar(parent, width, height, x, y, color, 0, UDim.new(0.2, 0))
	frame.BackgroundTransparency = 1
	Theme.stroke(frame, color, Theme.Sizes.StrokeThin)
	return frame
end

-- A disc at fractions of the square; `ring` draws only its edge.
local function disc(parent: Instance, diameter: number, x: number, y: number, color: Color3, ring: boolean?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Disc"
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(diameter, diameter)
	Theme.corner(frame, Theme.Pill)
	if ring then
		frame.BackgroundTransparency = 1
		Theme.stroke(frame, color, Theme.Sizes.StrokeThin)
	else
		frame.BackgroundColor3 = color
	end
	frame.Parent = parent
	return frame
end

-- A glyph or a letter filling `scale` of the square.
local function glyph(parent: Instance, text: string, font: Font, color: Color3, scale: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Glyph"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(scale, scale)
	label.FontFace = font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	return label
end

local builders: { [string]: (square: Frame, color: Color3) -> () } = {
	-- The Folio: a gold coin struck with an F.
	Coin = function(square)
		local coin = disc(square, 1, 0.5, 0.5, Theme.Colors.Primary)
		Theme.stroke(coin, "Accent", Theme.Sizes.StrokeThin)
		glyph(coin, "F", Theme.Fonts.Initial, Theme.Colors.Text, 0.6)
	end,
	-- A drop of ink: a disc with a square turned onto its point above it.
	Drop = function(square, color)
		disc(square, 0.64, 0.5, 0.62, color)
		bar(square, 0.45, 0.45, 0.5, 0.43, color, 45, UDim.new())
	end,
	Lock = function(square, color)
		disc(square, 0.5, 0.5, 0.34, color, true)
		bar(square, 0.8, 0.6, 0.5, 0.68, color, 0, UDim.new(0.2, 0))
	end,
	Clock = function(square, color)
		disc(square, 0.92, 0.5, 0.5, color, true)
		bar(square, 0.1, 0.34, 0.5, 0.36, color)
		bar(square, 0.28, 0.1, 0.62, 0.5, color)
	end,
	Check = function(square, color)
		glyph(square, Theme.Glyphs.Check, Theme.Fonts.Bold, color, 1)
	end,
	Cross = function(square, color)
		bar(square, 0.16, 0.9, 0.5, 0.5, color, 45)
		bar(square, 0.16, 0.9, 0.5, 0.5, color, -45)
	end,
	Play = function(square, color)
		glyph(square, Theme.Glyphs.Play, Theme.Fonts.Bold, color, 0.9)
	end,
	Back = function(square, color)
		glyph(square, Theme.Glyphs.Back, Theme.Fonts.Bold, color, 1)
	end,
	-- Settings: three rails, each with its knob somewhere else.
	Sliders = function(square, color)
		for index, knob in ipairs({ 0.3, 0.7, 0.45 }) do
			local y = 0.2 + (index - 1) * 0.3
			bar(square, 0.9, 0.1, 0.5, y, color)
			disc(square, 0.26, knob, y, color)
		end
	end,
	-- The leaderboard: second, first, third.
	Podium = function(square, color)
		for index, height in ipairs({ 0.6, 0.9, 0.4 }) do
			bar(square, 0.28, height, 0.18 + (index - 1) * 0.32, 1 - height / 2, color, 0, UDim.new(0.15, 0))
		end
	end,
	-- The loadout: five pigment cards fanned from one hand.
	Deck = function(square)
		for index, rotation in ipairs(DECK_FAN) do
			local card = Instance.new("Frame")
			card.Name = "Card"
			card.BorderSizePixel = 0
			card.BackgroundColor3 = Theme.pigmentColor(PigmentConfig.Order[index])
			card.AnchorPoint = Vector2.new(0.5, 1)
			card.Position = UDim2.fromScale(0.5 + (index - 3) * 0.1, 0.95)
			card.Size = UDim2.fromScale(0.4, 0.56)
			card.Rotation = rotation
			Theme.corner(card, UDim.new(0.15, 0))
			Theme.stroke(card, "Accent", Theme.Sizes.StrokeThin)
			card.Parent = square
		end
	end,
	-- The battle pass: a seal ring around the first volume.
	Pass = function(square, color)
		local id = Theme.texture("SealRing")
		if id ~= "" then
			local ring = Instance.new("ImageLabel")
			ring.Name = "Ring"
			ring.BackgroundTransparency = 1
			ring.Image = id
			ring.ImageColor3 = color
			ring.Size = UDim2.fromScale(1, 1)
			ring.Parent = square
		else
			disc(square, 0.9, 0.5, 0.5, color, true)
		end
		glyph(square, "1", Theme.Fonts.Title, color, 0.6)
	end,
	-- The daily reward: a page of a calendar, the seventh day.
	Calendar = function(square, color)
		box(square, 0.9, 0.84, 0.5, 0.54, color)
		bar(square, 0.9, 0.24, 0.5, 0.24, color, 0, UDim.new(0.15, 0))
		glyph(square, "7", Theme.Fonts.Numeric, color, 0.5).Position = UDim2.fromScale(0.5, 0.64)
	end,
	-- The quests: three lines, each with its box.
	Scroll = function(square, color)
		for index = 1, 3 do
			local y = 0.2 + (index - 1) * 0.3
			box(square, 0.22, 0.22, 0.14, y, color)
			bar(square, 0.6, 0.1, 0.65, y, color)
		end
	end,
	-- Invite: two of us.
	Invite = function(square)
		for _, x in ipairs({ 0.36, 0.64 }) do
			local head = disc(square, 0.56, x, 0.5, Theme.Colors.Ally)
			Theme.stroke(head, "Accent", Theme.Sizes.StrokeThin)
		end
	end,
	Burger = function(square, color)
		for index = 1, 3 do
			bar(square, 0.9, 0.14, 0.5, 0.2 + (index - 1) * 0.3, color)
		end
	end,
	-- The guard: a diamond of the sheet, which a fight may show.
	Shield = function(square)
		local diamond = bar(square, 0.66, 0.66, 0.5, 0.5, Theme.Colors.PanelRaised, 45, UDim.new(0.1, 0))
		Theme.stroke(diamond, "Accent", Theme.Sizes.StrokeThin)
	end,
}

-- A new icon `name`, `size` design units square, in `color` (ink by default). An unknown name is a typo in
-- the caller: it draws an empty square and warns once.
function Icon.new(name: Name, size: number, color: Color3?): Frame
	local square = Instance.new("Frame")
	square.Name = name
	square.BackgroundTransparency = 1
	square.BorderSizePixel = 0
	square.Size = UDim2.fromOffset(size, size)
	local build = builders[name]
	if build ~= nil then
		build(square, color or Theme.Colors.Accent)
	elseif not warned[name] then
		warned[name] = true
		log.warn("no icon %s: drawn empty", name)
	end
	return square
end

return Icon
