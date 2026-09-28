--!strict
-- OutcomeBanner: the top of the Result takeover (D-147) -- the outcome, set large in the poster face, in the
-- sheet on an ink stroke, turned a little, over a swash of the outcome's colour, with six blots of ink
-- bursting behind it one after the other. A victory is gold, green and our cyan, and lands with a bounce; a
-- defeat is indigo and ink, and comes down heavily, with no bounce: sad things are heavy; a draw is chalk,
-- and simply appears.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Splat = require(script.Parent.Splat)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Outcome = "Victory" | "Defeat" | "Draw"

export type OutcomeBanner = {
	Instance: Frame,
	Show: (self: OutcomeBanner, outcome: Outcome, title: string) -> (),
	-- Gives the blots back to the screen's pool.
	Clear: (self: OutcomeBanner) -> (),
	Destroy: (self: OutcomeBanner) -> (),
}

type Look = { Splats: { Color3 }, Swash: Color3 }

local OutcomeBanner = {}

local LOOKS: { [Outcome]: Look } = {
	Victory = {
		Splats = {
			Theme.Colors.Primary,
			Theme.Colors.SuccessFill,
			Theme.Colors.Primary,
			Theme.Colors.Ally,
			Theme.Colors.SuccessFill,
			Theme.Colors.Primary,
		},
		Swash = Theme.Colors.Primary,
	},
	Defeat = {
		Splats = { Theme.Colors.Info, Theme.Colors.Plate, Theme.Colors.Info, Theme.Colors.Plate, Theme.Colors.Info },
		Swash = Theme.Colors.Info,
	},
	Draw = {
		Splats = { Theme.Colors.Chalk, Theme.Colors.Chalk, Theme.Colors.Chalk, Theme.Colors.Chalk },
		Swash = Theme.Colors.Chalk,
	},
}
-- Where the blots land around the title (fractions of the banner, from its centre) and how wide each is.
local SPOTS: { { X: number, Y: number, Size: number } } = {
	{ X = -0.2, Y = -0.05, Size = 220 },
	{ X = 0.18, Y = -0.12, Size = 180 },
	{ X = 0.02, Y = 0.2, Size = 150 },
	{ X = 0.3, Y = 0.18, Size = 130 },
	{ X = -0.32, Y = 0.2, Size = 110 },
	{ X = 0.06, Y = -0.28, Size = 160 },
}
local SPLAT_FROM = 0.4
local SPLAT_STEP_SECONDS = 0.04
local TITLE_TILT = -4
local TITLE_STROKE = 6
local SWASH_WIDTH = 520
local SWASH_HEIGHT = 84
local SWASH_DROP = 22
-- A victory lands from larger than itself; a defeat drops from above.
local VICTORY_FROM = 1.6
local DEFEAT_DROP = 40

function OutcomeBanner.new(parent: Instance): OutcomeBanner
	local trove = Trove.new()
	local splats: { GuiObject } = {}
	local token = 0

	local banner = Instance.new("Frame")
	banner.Name = "Outcome"
	banner.BackgroundTransparency = 1
	banner.Size = UDim2.fromScale(1, 1)
	trove:Add(banner)

	local swash: GuiObject
	local id = Theme.texture("BrushStroke")
	if id ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = id
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Stretch
		swash = image
	else
		local bar = Instance.new("Frame")
		Theme.corner(bar, Theme.Pill)
		swash = bar
	end
	swash.Name = "Swash"
	swash.BorderSizePixel = 0
	swash.AnchorPoint = Vector2.new(0.5, 0.5)
	swash.Position = UDim2.new(0.5, 0, 0.5, SWASH_DROP)
	swash.Size = UDim2.fromOffset(SWASH_WIDTH, SWASH_HEIGHT)
	swash.Rotation = TITLE_TILT
	swash.ZIndex = 2
	swash.Parent = banner

	local rest = UDim2.fromScale(0.5, 0.5)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = rest
	title.AutomaticSize = Enum.AutomaticSize.XY
	title.Size = UDim2.new()
	title.Rotation = TITLE_TILT
	title.FontFace = Theme.Fonts.Title
	title.TextSize = Theme.Sizes.TextDisplay
	title.TextColor3 = Theme.Colors.PanelRaised
	title.ZIndex = 3
	title.Text = ""
	local titleStroke = Theme.stroke(title, "Outline", TITLE_STROKE, "Contextual")
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title
	title.Parent = banner
	trove:Add(function()
		Motion.cancel(title)
		Motion.cancel(titleScale)
		Motion.cancel(titleStroke)
	end)

	local function clear(_self: OutcomeBanner?)
		token += 1
		for _, splat in ipairs(splats) do
			Splat.release(splat)
		end
		table.clear(splats)
	end
	trove:Add(function()
		clear(nil)
	end)

	local function show(_self: OutcomeBanner, outcome: Outcome, text: string)
		clear(nil)
		local mine = token
		local look = LOOKS[outcome]
		title.Text = text
		if swash:IsA("ImageLabel") then
			swash.ImageColor3 = look.Swash
		else
			swash.BackgroundColor3 = look.Swash
		end

		-- The blots burst one after the other; under reduced motion they are simply there.
		local reduced = UiPrefs.reducedMotion()
		for index, tint in ipairs(look.Splats) do
			local spot = SPOTS[index]
			local full = UDim2.fromOffset(spot.Size, spot.Size)
			local splat = Splat.new({
				Size = if reduced then full else UDim2.fromOffset(spot.Size * SPLAT_FROM, spot.Size * SPLAT_FROM),
				Tint = tint,
				Rotation = Splat.rotation(index),
				Position = UDim2.fromScale(0.5 + spot.X, 0.5 + spot.Y),
				ZIndex = 1,
				Name = "Burst",
				Parent = banner,
			})
			if splat ~= nil then
				table.insert(splats, splat)
				if not reduced then
					task.delay((index - 1) * SPLAT_STEP_SECONDS, function()
						if token == mine then
							Motion.to(splat, { Size = full }, "UiPop")
						end
					end)
				end
			end
		end

		-- The title: in the sheet on its ink, appearing as the outcome says.
		Motion.set(title, { TextTransparency = 1, Position = rest })
		Motion.set(titleStroke, { Transparency = 1 })
		Motion.set(titleScale, { Scale = 1 })
		Motion.to(title, { TextTransparency = 0 }, "Ui")
		Motion.to(titleStroke, { Transparency = 0 }, "Ui")
		if outcome == "Victory" then
			Motion.set(titleScale, { Scale = VICTORY_FROM })
			Motion.to(titleScale, { Scale = 1 }, "UiPop")
		elseif outcome == "Defeat" then
			Motion.set(title, { Position = rest - UDim2.fromOffset(0, DEFEAT_DROP) })
			Motion.to(title, { Position = rest }, "UiExit")
		end
	end

	banner.Parent = parent

	local function destroy(_self: OutcomeBanner)
		trove:Destroy()
	end

	return {
		Instance = banner,
		Show = show,
		Clear = clear,
		Destroy = destroy,
	}
end

return OutcomeBanner
