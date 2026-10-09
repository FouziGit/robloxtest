--!strict
-- The landmarks' skins (D-283), held to the boxes they cover. BattlegroundLayout.skins places every mesh
-- tools/meshes/page/ draws; each placed skin must cover boxes the layout has, each at most once, and wrap them -- its
-- bounds hold every box it hides, its walkable top stands just over the box's -- or a player walks on air, or into a
-- wall drawn somewhere else. A cheap check on the meshes' bounds (MeshConfig), not the ray fit the drafts passed: it
-- catches a skin placed, turned or scaled wrong once the layout moves.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BattlegroundLayout = require("../src/server/Pure/BattlegroundLayout")
local BotConfig = require("../src/shared/Config/BotConfig")
local Harness = require("./harness")
local MeshConfig = require("../src/shared/Config/MeshConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MAP = BattlegroundConfig.Map
local LAYOUT = BattlegroundLayout.build(MAP, {
	FloorName = BattlegroundConfig.Anchors.Floor,
	KillZoneName = BattlegroundConfig.Anchors.KillZone,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
	CampTop = WorldConfig.Ladder.Training,
	CampTransparency = WorldConfig.Battleground.CampTransparency,
}, BotConfig.Path.RadiusStuds)
local SKINS = BattlegroundLayout.skins(LAYOUT, MAP)
-- A walkable top stands this far over the top it covers (the wrap contract, tools/meshes/page/kit.py).
local TOP_MIN, TOP_MAX = 0.05, 0.15
local TOLERANCE = 1e-3
-- The quill's barrel shoulders over its rails are drawn, not walked: its top tone stands well over its landing.
local DRAWN_OVER: { [string]: boolean } = { FallenQuill = true }

type Bounds = { Min: { number }, Max: { number } }

local BOXES: { [string]: BattlegroundLayout.Box } = {}
for _, box in ipairs(LAYOUT.Boxes) do
	BOXES[box.Name] = box
end

local function empty(): Bounds
	return { Min = { math.huge, math.huge, math.huge }, Max = { -math.huge, -math.huge, -math.huge } }
end

local function grow(bounds: Bounds, x: number, y: number, z: number)
	for axis, value in ipairs({ x, y, z }) do
		bounds.Min[axis] = math.min(bounds.Min[axis], value)
		bounds.Max[axis] = math.max(bounds.Max[axis], value)
	end
end

-- The eight corners of a box (cx, cy, cz, half extents) turned by `yaw` about the vertical, as the engine turns a
-- part: its own +x along (cos, -sin), its own +z along (sin, cos).
local function turned(bounds: Bounds, yaw: number, x: number, y: number, z: number, hx: number, hy: number, hz: number)
	local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local lx, lz = sx * hx, sz * hz
				grow(bounds, x + c * lx + s * lz, y + sy * hy, z - s * lx + c * lz)
			end
		end
	end
end

-- A mesh as the skin places it: its own bounds scaled, turned by Yaw and moved to the pivot.
local function placed(bounds: Bounds, skin: BattlegroundLayout.Skin, mesh: MeshConfig.Mesh)
	local c, s = math.cos(math.rad(skin.Yaw)), math.sin(math.rad(skin.Yaw))
	local centre, half = {}, {}
	for axis = 1, 3 do
		centre[axis] = (mesh.Min[axis] + mesh.Max[axis]) / 2 * skin.Scale[axis]
		half[axis] = (mesh.Max[axis] - mesh.Min[axis]) / 2 * skin.Scale[axis]
	end
	local x = skin.X + c * centre[1] + s * centre[3]
	local z = skin.Z - s * centre[1] + c * centre[3]
	turned(bounds, skin.Yaw, x, skin.Y + centre[2], z, half[1], half[2], half[3])
end

describe("the landmarks' skins", function()
	it("cover boxes the layout has, each at most once, with meshes MeshConfig draws as scenery", function()
		local covered: { [string]: string } = {}
		for _, skin in ipairs(SKINS) do
			for _, name in ipairs(skin.Boxes) do
				local box = BOXES[name]
				if box == nil or not box.Solid then
					error(("%s skins %s, which is no solid box of the layout"):format(skin.Name, name))
				end
				if covered[name] ~= nil then
					error(("%s skins %s, which %s already skins"):format(skin.Name, name, covered[name]))
				end
				covered[name] = skin.Name
			end
			for _, name in ipairs(skin.Marks) do
				local mark = BOXES[name]
				if mark == nil or mark.Solid then
					error(("%s replaces %s, which is no mark drawn on the page"):format(skin.Name, name))
				end
			end
			expect(#skin.Meshes).toBeGreaterThan(0)
			for _, piece in ipairs(skin.Meshes) do
				local mesh = MeshConfig.get(piece.Mesh)
				if mesh == nil or mesh.Reference ~= "Layout" then
					error(("%s draws %s, which is no landmark mesh of MeshConfig"):format(skin.Name, piece.Mesh))
				end
				expect((WorldConfig.Battleground :: any)["Skin" .. piece.Tone]).never.toBeNil()
			end
		end
		expect(#SKINS).toBeGreaterThanOrEqual(8)
	end)

	it("wrap every box they hide, and stand their walkable top just over it", function()
		for _, skin in ipairs(SKINS) do
			if #skin.Boxes > 0 then
				local body, top = empty(), empty()
				for _, piece in ipairs(skin.Meshes) do
					local mesh = MeshConfig.get(piece.Mesh) :: MeshConfig.Mesh
					-- The ink's hull stands proud of everything, so only the tones hold the boxes.
					if piece.Tone ~= "Ink" then
						placed(body, skin, mesh)
					end
					if piece.Tone == "Top" then
						placed(top, skin, mesh)
					end
				end
				local highest: BattlegroundLayout.Box? = nil
				for _, name in ipairs(skin.Boxes) do
					local box = BOXES[name]
					local hidden = empty()
					turned(hidden, box.Yaw, box.X, box.Y, box.Z, box.SizeX / 2, box.SizeY / 2, box.SizeZ / 2)
					for axis = 1, 3 do
						if
							body.Min[axis] > hidden.Min[axis] + TOLERANCE
							or body.Max[axis] < hidden.Max[axis] - TOLERANCE
						then
							error(("%s does not wrap %s on axis %d"):format(skin.Name, name, axis))
						end
					end
					if highest == nil or box.Y + box.SizeY / 2 > highest.Y + highest.SizeY / 2 then
						highest = box
					end
				end
				local box = highest :: BattlegroundLayout.Box
				local over = top.Max[2] - (box.Y + box.SizeY / 2)
				if over < TOP_MIN then
					error(("%s's top stands %.3f over %s, under it"):format(skin.Name, over, box.Name))
				end
				-- A slope's skin rises past its ridge; only a flat top is held from above.
				if box.Shape == "Block" and not DRAWN_OVER[skin.Name] and over > TOP_MAX then
					error(("%s's top stands %.3f over %s: a player walks on air"):format(skin.Name, over, box.Name))
				end
			end
		end
	end)
end)
