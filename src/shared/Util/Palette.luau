--!strict
-- The world's colours and its material as engine values, converted once from Config/WorldConfig. The
-- only module of src/server that turns a triple into a Color3 or a name into an Enum.Material: a builder
-- that wants a colour names a ROLE ("Page", "Ink") and cannot invent one.

local WorldConfig = require(script.Parent.Parent.Config.WorldConfig)

local Palette = {}

local cache: { [string]: Color3 } = {}

function Palette.rgb(rgb: WorldConfig.Rgb): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- The colour of a role. An unknown name is a build error, not a grey fallback: a wrong role in the
-- world is a colour nobody chose, and this runs at server start where it is caught at once.
function Palette.world(name: string): Color3
	local cached: Color3? = cache[name]
	if cached then
		return cached
	end
	local rgb = WorldConfig.Colors[name]
	if rgb == nil then
		error(("WorldConfig has no colour named %s"):format(tostring(name)))
	end
	local color = Palette.rgb(rgb)
	cache[name] = color
	return color
end

function Palette.material(): Enum.Material
	return (Enum.Material :: any)[WorldConfig.Material] :: Enum.Material
end

function Palette.vector(triple: WorldConfig.Triple): Vector3
	return Vector3.new(triple[1], triple[2], triple[3])
end

return Palette
