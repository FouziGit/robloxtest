--!strict
-- ItemPreview: what a cosmetic looks like, drawn from the catalog with no image to upload (D-147). A title is
-- its own words on a scrap of paper; anything else is a swatch of the colour it is worn in -- a skin in its
-- glyph's pigment moved by its shade, exactly as the world draws it, and an aura, a trail or a finisher in
-- the page's ink it is made of (CosmeticConfig.Tones). The swatch is a disc in an ink outline (rule 11), as
-- large as the square it is given allows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local Theme = require(script.Parent.Parent.Theme)
local WorldConfig = require(Shared.Config.WorldConfig)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

local ItemPreview = {}

-- The swatch's share of its square, the scrap's, and the title's share of the scrap.
local SWATCH_SCALE = 0.62
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
	local disc = Instance.new("Frame")
	disc.Name = "Swatch"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = ItemPreview.color(item)
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(SWATCH_SCALE, SWATCH_SCALE)
	Theme.corner(disc, Theme.Pill)
	Theme.stroke(disc, "Accent", Theme.Sizes.Stroke)
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = disc
	disc.Parent = parent
	return disc
end

return ItemPreview
