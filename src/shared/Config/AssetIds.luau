--!strict
-- Every Roblox content id the game renders with, in one place.
--
-- CLAUDE.md puts game passes, products and the place id in MonetizationConfig. These are the other kind:
-- textures, decals and flipbooks. They are separated because they fail differently. A missing product id
-- costs money and has to stop a purchase; a missing texture costs a little beauty and must never stop
-- anything, because the assets are uploaded by a human to a Roblox account and there is always a window
-- where the code exists and the upload does not.
--
-- So an id here is allowed to be empty, and empty means "not uploaded yet". The renderer asks for the id,
-- gets "", warns once naming the file that needs uploading, and draws the effect without the texture.
-- Nothing crashes and nothing is silently invisible (docs/JUICE_PLAN.md phase 3).
--
-- Every texture is GENERATED, by the scripts in tools/textures/, and committed as a PNG in
-- assets/textures/. None of it comes from the toolbox: dubious provenance is a classic reason a Roblox
-- experience is taken down, and a borrowed texture would make the art direction somebody else's.
--
-- Each one is white with an alpha channel so the renderer tints it per pigment. That is what keeps art
-- bible rule 2 -- one glyph, one pigment, one colour -- true without shipping five copies of every asset.
--
-- Pure data: no require, no Roblox global, so tests/AssetIds.spec.luau can hold the table to its own rules.

export type Asset = {
	-- "rbxassetid://123", or "" while the PNG has not been uploaded yet.
	Id: string,
	-- The file in assets/textures/ this id must be the upload of. Named in the warning, so whoever sees
	-- it in the output knows exactly which file to upload and where to paste the id back.
	Source: string,
	-- Pixel size of the source, which the renderer needs for flipbooks and for aspect-correct sprites.
	Width: number,
	Height: number,
	-- Frames per row and per column, for a flipbook. 1 and 1 for a still image.
	Columns: number,
	Rows: number,
	-- How far the ink reaches from the centre, in half-widths of the plane it is drawn on: Least is the
	-- direction it reaches least, Most the direction it reaches most. A plane is sized to its edge and
	-- a player reads the alpha, so this is the number a decal is REALLY drawn at -- the blot's ink stops
	-- at half its plane, a full-bleed square runs to 1.41 on its diagonals. Measured off the PNG by
	-- tools/textures/check_ink.py, which fails the build when a value here stops matching the file, and
	-- read by tests/BossTelegraph.spec.luau so that a warning is held to its ink rather than to its
	-- rectangle. Absent for a texture that is not square, which no warning may use.
	Ink: { Least: number, Most: number }?,
}

local AssetIds = {}

-- Written by scripts/upload_assets.py from assets/roblox-assets.lock.json: the source file of every
-- uploaded asset, and its id. Never edited by hand -- tests/UploadedAssets.spec.luau holds this block to
-- the lock file, and the lock file to the bytes of each file, so a regenerated asset whose id went stale
-- fails the build instead of rendering the old upload.
-- BEGIN UPLOADED
local UPLOADED: { [string]: string } = {
	["assets/textures/brush_stroke.png"] = "rbxassetid://86444840583183",
	["assets/textures/crack_web.png"] = "rbxassetid://109963232583770",
	["assets/textures/dust_mote.png"] = "rbxassetid://135616436571861",
	["assets/textures/explosion_flipbook.png"] = "rbxassetid://112524424027614",
	["assets/textures/gradient_linear.png"] = "rbxassetid://111708517818955",
	["assets/textures/gradient_radial.png"] = "rbxassetid://107271909193136",
	["assets/textures/ink_blot.png"] = "rbxassetid://73894677941580",
	["assets/textures/paper_grain.png"] = "rbxassetid://127023824364504",
	["assets/textures/paper_scrap.png"] = "rbxassetid://82591519572234",
	["assets/textures/seal_ring.png"] = "rbxassetid://101561475000641",
	["assets/textures/shockwave_ring.png"] = "rbxassetid://80296968876762",
	["assets/textures/smoke_soft.png"] = "rbxassetid://108342464159696",
	["assets/textures/spark_streak.png"] = "rbxassetid://84878236280705",
	["assets/textures/telegraph_bar.png"] = "rbxassetid://93590001410469",
	["assets/textures/telegraph_disc.png"] = "rbxassetid://130043464666920",
	["assets/textures/telegraph_page.png"] = "rbxassetid://88424550504238",
	["assets/textures/telegraph_ring.png"] = "rbxassetid://78927750663153",
}
-- END UPLOADED

local function texture(source: string, width: number, height: number, least: number?, most: number?): Asset
	local ink = if least ~= nil and most ~= nil then { Least = least, Most = most } else nil
	return {
		Id = UPLOADED[source] or "",
		Source = source,
		Width = width,
		Height = height,
		Columns = 1,
		Rows = 1,
		Ink = ink,
	}
end

local function flipbook(source: string, size: number, columns: number, rows: number): Asset
	return {
		Id = UPLOADED[source] or "",
		Source = source,
		Width = size,
		Height = size,
		Columns = columns,
		Rows = rows,
	}
end

AssetIds.Textures = {
	-- Volumetric-looking smoke and dust. The noisy edge is the point: a clean circle reads as a gradient,
	-- a ragged one reads as matter.
	SmokeSoft = texture("assets/textures/smoke_soft.png", 256, 256, 0.535, 0.875),
	-- Sparks. Tapers along +X so the emitter's own velocity orients it and a spark reads as travelling.
	SparkStreak = texture("assets/textures/spark_streak.png", 128, 128, 0.039, 0.812),
	-- The residue every impact leaves on the ground (art bible rule 5: the world remembers for a few
	-- seconds). An irregular blot, because a circle is a decal and a blot is ink.
	InkBlot = texture("assets/textures/ink_blot.png", 256, 256, 0.531, 0.828),
	-- Cracks radiating from a heavy impact.
	CrackWeb = texture("assets/textures/crack_web.png", 512, 512, 0.043, 0.895),
	-- One thin ring, for an expanding wave. Scaled rather than redrawn.
	ShockwaveRing = texture("assets/textures/shockwave_ring.png", 512, 512, 0.814, 0.828),
	-- Tileable grain for world surfaces. Low contrast on purpose: it is the paper the world is written
	-- on, and paper you notice is a texture, not a surface.
	PaperGrain = texture("assets/textures/paper_grain.png", 512, 512, 0.998, 1.414),
	-- The seal a cast draws in the air before it fires. This is the art direction's signature image and
	-- the reason a cast has an anticipation phase at all.
	SealRing = texture("assets/textures/seal_ring.png", 512, 512, 0.902, 0.918),
	-- A tapered brush stroke, dry at both ends, for beams and trails. A beam with a hard edge is a laser
	-- and belongs to a different game.
	BrushStroke = texture("assets/textures/brush_stroke.png", 512, 128),
	-- Ambient motes, for the residue that hangs after a zone ends.
	DustMote = texture("assets/textures/dust_mote.png", 64, 64, 0.688, 0.719),
	-- A scrap of torn paper: straight cut sides and one torn edge, so it reads as paper and not as a
	-- petal. What a page sheds when it is struck or erased -- the kill effects and the paper cosmetics.
	PaperScrap = texture("assets/textures/paper_scrap.png", 128, 128, 0.344, 0.930),
	GradientRadial = texture("assets/textures/gradient_radial.png", 256, 256, 0.836, 0.848),
	GradientLinear = texture("assets/textures/gradient_linear.png", 256, 256, 0.688, 1.414),
	-- L'Effacement's warnings, and the only textures whose edge is a rule: the plane is sized to the
	-- damage and the ink reaches the plane (tools/textures/telegraph.py). A disc of flooding ink, one
	-- stroke on its rim, a full-bleed bar for the wedge the Sweep opens, and a disc of bare page for the
	-- one place an Eruption does not touch.
	TelegraphDisc = texture("assets/textures/telegraph_disc.png", 512, 512, 0.998, 1.004),
	TelegraphRing = texture("assets/textures/telegraph_ring.png", 512, 512, 0.998, 1.004),
	TelegraphBar = texture("assets/textures/telegraph_bar.png", 256, 256, 0.996, 1.414),
	TelegraphPage = texture("assets/textures/telegraph_page.png", 512, 512, 0.998, 1.004),
	-- An ink bloom opening and dispersing, as an 8x8 grid read left to right, top to bottom, which is
	-- what Enum.ParticleFlipbookLayout.Grid8x8 expects.
	ExplosionBloom = flipbook("assets/textures/explosion_flipbook.png", 1024, 8, 8),
} :: { [string]: Asset }

-- Returns the content id for `key`, or "" when it has not been uploaded. `known` is false for a key that
-- does not exist at all, which is a typo in the caller rather than a missing upload and deserves a
-- different warning.
function AssetIds.get(key: string): (string, boolean)
	local asset = AssetIds.Textures[key]
	if asset == nil then
		return "", false
	end
	return asset.Id, true
end

-- Every key whose PNG still has to be uploaded. The client logs this once at startup so the gap is
-- visible in the output rather than discovered as an effect that looks wrong.
function AssetIds.missing(): { string }
	local keys: { string } = {}
	for key, asset in pairs(AssetIds.Textures) do
		if asset.Id == "" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

-- Frame count of a flipbook, for a renderer that has to pick a rate from it.
function AssetIds.frameCount(key: string): number
	local asset = AssetIds.Textures[key]
	if asset == nil then
		return 0
	end
	return asset.Columns * asset.Rows
end

return AssetIds
