--!strict
-- The ground a portal gate covers (D-130), from WorldConfig.Portal and PortalConfig.ZoneRadiusStuds, for the
-- gates that have to place one: the hub (tests/Hub.spec.luau), the Erasure's arena (tests/Config.spec.luau)
-- and the Battleground (tests/BattlegroundLayout.spec.luau). One reading of the gate's geometry, so the three
-- placements are proved against the same gate.
local PortalConfig = require("../src/shared/Config/PortalConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")

local Gate = {}

-- In the space of the gate's base: x across it, z behind it (away from where players come from). The posts'
-- outer faces -- the lintel spans exactly them -- are HalfWidth either side; the rim's front edge is Front
-- ahead and the posts' back faces Back behind. The rim is a disc of RimRadius around the base.
export type Footprint = { HalfWidth: number, Front: number, Back: number, RimRadius: number }

function Gate.footprint(): Footprint
	local portal = WorldConfig.Portal
	local radius = PortalConfig.ZoneRadiusStuds
	return {
		HalfWidth = portal.OpeningStuds / 2 + portal.PostStuds[1],
		Front = radius + portal.SealRimStuds,
		Back = radius + math.max(portal.PostStuds[3], portal.LintelStuds),
		RimRadius = radius + portal.SealRimStuds,
	}
end

-- The four corners of the rectangle that holds the whole gate -- rim, posts and lintel -- for a base at
-- (x, z) whose LookVector is the unit (lookX, lookZ), as ground points {x, z}. A CFrame's RightVector is
-- (-lookZ, lookX) on the ground and "behind" is -look.
function Gate.corners(x: number, z: number, lookX: number, lookZ: number): { { number } }
	local footprint = Gate.footprint()
	local half = math.max(footprint.HalfWidth, footprint.RimRadius)
	local back = math.max(footprint.Back, footprint.RimRadius)
	local corners = {}
	for _, across in ipairs({ -half, half }) do
		for _, behind in ipairs({ -footprint.Front, back }) do
			table.insert(corners, {
				x - lookZ * across - lookX * behind,
				z + lookX * across - lookZ * behind,
			})
		end
	end
	return corners
end

return Gate
