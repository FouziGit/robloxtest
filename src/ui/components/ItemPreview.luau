--!strict
-- ItemPreview: what a cosmetic looks like, drawn from the catalog with no image to upload (D-147). A title is
-- its own words on a scrap of paper; anything else is a swatch of the colour it is worn in -- a skin in its
-- glyph's pigment moved by its shade, exactly as the world draws it, and an aura, a trail or a finisher in
-- the page's ink it is made of (CosmeticConfig.Tones). The swatch is a blot of that colour in an ink outline
-- (rule 11), a little wider than tall and tipped, as the board draws it: about three fifths of the height it
-- is given, whatever its width.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local Theme = require(script.Parent.Parent.Theme)
local WorldConfig = require(Shared.Config.WorldConfig)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

local ItemPreview = {}

-- The blot's share of the height it is given, its width over its height and its tilt; the scrap's share of
-- its square, and the title's share of the scrap.
local BLOT_HEIGHT = 0.58
local BLOT_ASPECT = 8 / 7
local BLOT_TILT = -6
local SCRAP_SCALE = 0.9
local TITLE_WIDTH = 0.8
local TITLE_HEIGHT = 0.5

-- The colour `item` is worn in.
function ItemPreview.color(item: CosmeticConfig.CosmeticDef): Color3
	if item.Slot == "Skin" then
		local glyph = GlyphConfig.ById[item.Target or ""]
		local base = if glyph ~= nil then PigmentConfig.Colors[glyph.Pigment :: any] else nil
		if base ~= nil then
			return Theme.rgb(
				PigmentConfig.shade(base, item.Look.Shade or 0, WorldConfig.Colors.Ink, WorldConfig.Colors.Page)
			)
		end
	end
	return Theme.rgb(CosmeticConfig.Tones[item.Look.Tone or "Ink"])
end

-- `item` drawn in the middle of `parent`, which it fills as a square; returns what it drew.
function ItemPreview.new(item: CosmeticConfig.CosmeticDef, parent: GuiObject, localize: Localizer): GuiObject
	local textKey = item.Look.TextKey
	if item.Slot == "Title" and textKey ~= nil then
		local id = Theme.texture("PaperScrap")
		local scrap: GuiObject
		if id ~= "" then
			local image = Instance.new("ImageLabel")
			image.Image = id
			image.ImageColor3 = Theme.Colors.PanelRaised
			image.BackgroundTransparency = 1
			image.ScaleType = Enum.ScaleType.Fit
			scrap = image
		else
			-- Not uploaded: a pill of the sheet says the same, less well.
			local pill = Instance.new("Frame")
			pill.BackgroundColor3 = Theme.Colors.PanelRaised
			Theme.corner(pill, Theme.Pill)
			Theme.stroke(pill, "Accent", Theme.Sizes.StrokeThin)
			scrap = pill
		end
		scrap.Name = "Scrap"
		scrap.BorderSizePixel = 0
		scrap.AnchorPoint = Vector2.new(0.5, 0.5)
		scrap.Position = UDim2.fromScale(0.5, 0.5)
		scrap.Size = UDim2.fromScale(SCRAP_SCALE, SCRAP_SCALE)
		local words = Instance.new("TextLabel")
		words.Name = "Title"
		words.BackgroundTransparency = 1
		words.AnchorPoint = Vector2.new(0.5, 0.5)
		words.Position = UDim2.fromScale(0.5, 0.5)
		words.Size = UDim2.fromScale(TITLE_WIDTH, TITLE_HEIGHT)
		words.FontFace = Theme.Fonts.Title
		words.TextScaled = true
		words.TextColor3 = Theme.Colors.Text
		words.Text = localize.t(textKey)
		words.ZIndex = 2
		words.Parent = scrap
		scrap.Parent = parent
		return scrap
	end
	local blot = Instance.new("Frame")
	blot.Name = "Swatch"
	blot.BorderSizePixel = 0
	blot.BackgroundColor3 = ItemPreview.color(item)
	blot.AnchorPoint = Vector2.new(0.5, 0.5)
	blot.Position = UDim2.fromScale(0.5, 0.5)
	-- As wide as the parent allows and BLOT_HEIGHT of its height: the constraint fits the blot's own shape inside.
	blot.Size = UDim2.fromScale(1, BLOT_HEIGHT)
	blot.Rotation = BLOT_TILT
	Theme.corner(blot, Theme.Pill)
	Theme.stroke(blot, "Accent", Theme.Sizes.Stroke)
	local shape = Instance.new("UIAspectRatioConstraint")
	shape.AspectRatio = BLOT_ASPECT
	shape.AspectType = Enum.AspectType.FitWithinMaxSize
	shape.Parent = blot
	blot.Parent = parent
	return blot
end

return ItemPreview
