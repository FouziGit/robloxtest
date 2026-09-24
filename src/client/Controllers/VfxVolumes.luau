--!strict
-- VfxVolumes: the generated volumes of the timelines (D-114) -- how a Mesh layer is built and stepped.
--
-- Not a controller: a sibling of VfxTimeline, which owns the schedule, the pool, the budget and the ground
-- probe and hands them over through `bind`, so a volume is placed, borrowed, dried and faded exactly like
-- every other layer. It lives apart because the runtime is already the largest file in the client.
--
-- A volume is a pooled part carrying a SpecialMesh, the one route a client script can set a mesh id
-- through. What Studio taught before a line of this was written (MeshConfig, the Studio mesh lab):
--   * one unit of a generated mesh is one stud once imported, so a layer's Size -- studs of the mesh's
--     reference extent -- is its Scale, multiplied per axis by Stretch;
--   * the importer recentres a mesh on its bounds, so Offset puts the mesh's own origin, its pivot, back
--     on the part: a crown stands ON the floor instead of half inside it;
--   * every normal of a volume points up its turning axis (the lighting rule), so it only ever turns about
--     that axis and takes one flat tone, like a mark on the floor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Log = require(Shared.Util.Log)
local MeshConfig = require(Shared.Config.MeshConfig)
local Palette = require(Shared.Util.Palette)
local Scatter = require(Shared.Pure.Scatter)
local VfxConfig = require(Shared.Config.VfxConfig)
local VfxTimelineConfig = require(Shared.Config.VfxTimelineConfig)
local VolumeMath = require(Shared.Pure.VolumeMath)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("VfxVolumes")

-- Below this, a transparency is drawn fully opaque: a volume in the transparent pass sorts against the
-- ink under it and flickers, and nobody can see the difference between 0.02 and 0.
local OPAQUE_BELOW = 0.02
-- Studs added around a volume's largest reach for its part's box, which is what the engine culls by.
local ENVELOPE_MARGIN = 0.5

-- A volume's own state: the mesh it draws, the frame it turns in, and its seeded start angle.
export type Volume = { Mesh: MeshConfig.Mesh, Base: CFrame, Jitter: number }

-- One scrap of paper thrown off a blast (a Debris layer): its part and mesh, its flight (Pure/Scatter),
-- its size and proportions, when it lands and how long it lasts, and the axis it tumbles about.
type Scrap = {
	Part: BasePart,
	Mesh: SpecialMesh,
	Shape: MeshConfig.Mesh,
	Piece: Scatter.Piece,
	Size: Vector3,
	Lands: number?,
	Lasts: number,
	Axis: Vector3,
	Yaw: number,
}

-- A Debris layer's scraps, where they were thrown from, and how far below that they land (0 when they
-- have nowhere to land: then no scrap has a Lands).
export type Debris = { Origin: Vector3, Depth: number, Scraps: { Scrap } }

-- One limb of a sketch (an Afterimage layer): its part and mesh, and the scale that fits the mesh to the
-- limb it copies.
type Limb = { Part: BasePart, Mesh: SpecialMesh, Scale: Vector3 }

-- An Afterimage layer's limbs.
export type Afterimage = { Limbs: { Limb } }

-- What the runtime hands over (VfxTimeline.Init): its own helpers, so there is one of each.
export type Kit = {
	borrow: (entry: any, className: string) -> Instance?,
	host: (entry: any, place: CFrame, size: Vector3) -> BasePart?,
	groundAt: (position: Vector3) -> (Vector3, Vector3, boolean),
	-- Whether something lying `reach` studs around a point of the floor would cover a live warning.
	overWarning: (position: Vector3, reach: number) -> boolean,
	wetAndDry: (context: any, color: Color3) -> (Color3, Color3),
	driedBy: (entry: any, now: number) -> number,
	fadeOf: (layer: any, elapsed: number, alpha: number, fallback: number) -> number,
	lerp: (from: number?, to: number?, alpha: number, fallback: number) -> number,
}

-- The part of a live layer this module reads and writes (VfxTimeline's Live).
type Entry = {
	Layer: any,
	Context: any,
	Scales: { Effect: number, Size: number, Span: number, Offset: number },
	PlayStartedAt: number,
	StartedAt: number,
	Primary: Instance?,
	Wet: Color3?,
	Dry: Color3?,
	Volume: Volume?,
	LayerIndex: number,
	-- Set by a landing (VfxTimeline.land): the volume splats flat and dries out from here, its shape held
	-- where the landing found it (Alpha).
	Ending: { At: number, From: number, Alpha: number? }?,
	Debris: Debris?,
	Afterimage: Afterimage?,
}

local VfxVolumes = {}

local kit: Kit
local warned: { [string]: boolean } = {}

local ONE = { 1, 1, 1 }

-- The SpecialMesh.Offset that puts the mesh's pivot back on its part at `scale` (VolumeMath.pivotOffset).
local function pivotOffset(mesh: MeshConfig.Mesh, scale: Vector3): Vector3
	return Vector3.new(VolumeMath.pivotOffset(mesh.Min, mesh.Max, mesh.Pivot, scale.X, scale.Y, scale.Z))
end

local function turn(axis: MeshConfig.Axis, angle: number): CFrame
	return CFrame.Angles(VolumeMath.turn(axis, angle))
end

-- The effect's facing, turned only about the vertical: a volume is lit by its up axis and never tips.
local function yawOf(place: CFrame): CFrame
	local look = place.LookVector
	return CFrame.lookAlong(place.Position, Vector3.new(VolumeMath.flatFacing(look.X, look.Y, look.Z)))
end

-- A seeded draw every client makes the same, from the point its play is drawn at (VolumeMath.seed).
local function randomFor(entry: Entry, salt: number): Random
	local origin: Vector3 = entry.Context.Origin
	return Random.new(VolumeMath.seed(origin.X, origin.Y, origin.Z, salt))
end

-- Flat on the floor under `place`, forward along the effect's facing, lifted `lift` studs: the frame an
-- ensō is drawn in. nil when there is no floor and the layer asked for one (a crown in mid-air is a
-- crown of nothing).
local function groundFrame(place: CFrame, lift: number, needsGround: boolean): CFrame?
	local position, normal, found = kit.groundAt(place.Position)
	if not found and needsGround then
		return nil
	end
	local forward = place.LookVector - normal * place.LookVector:Dot(normal)
	if forward.Magnitude < 1e-3 then
		forward = Vector3.xAxis - normal * normal.X
	end
	local base = position + normal * (0.03 + math.max(lift, 0))
	return CFrame.lookAt(base, base + forward.Unit, normal)
end

local function largest(values: { number }): number
	return math.max(values[1], values[2], values[3])
end

-- Draws nothing, once named in the output, for a mesh that is not in MeshConfig or has no id yet.
local function missing(key: string, why: string): boolean
	if not warned[key] then
		warned[key] = true
		log.warn("mesh %s %s", key, why)
	end
	return true
end

-- Builds a Mesh layer at `place`. Draws nothing when the mesh is unknown or unresolved, when a volume that
-- needs a floor has none, when one laid on the floor would cover a warning (rule 9), or when the pool
-- refuses: like every layer, a volume it cannot draw it skips.
function VfxVolumes.build(entry: Entry, place: CFrame)
	local layer = entry.Layer
	local key: string = layer.Mesh
	local mesh = MeshConfig.get(key)
	if mesh == nil then
		missing(key, "is not in MeshConfig")
		return
	end
	if mesh.Id == "" or mesh.Native == nil then
		missing(key, ("has no id yet: upload and resolve %s (scripts/upload_assets.py)"):format(mesh.Source))
		return
	end
	local reach = largest({ mesh.Max[1] - mesh.Min[1], mesh.Max[2] - mesh.Min[2], mesh.Max[3] - mesh.Min[3] })
	local size = math.max(layer.Size or 1, layer.EndSize or 0) * entry.Scales.Size
	local stretch = math.max(largest(layer.Stretch or ONE), largest(layer.EndStretch or layer.Stretch or ONE))
	local base: CFrame? = yawOf(place)
	if layer.Face == "Ground" then
		local offset: { number }? = layer.Offset
		local lift = if offset ~= nil then offset[2] * entry.Scales.Effect else 0
		base = groundFrame(place, lift, layer.NeedsGround == true)
		-- Another play's warning under it: the warning is read, the volume is weight (rule 9).
		if base ~= nil and kit.overWarning(base.Position, reach * size * stretch / 2) then
			return
		end
	end
	if base == nil then
		return
	end
	local part = kit.host(entry, base, Vector3.one * (reach * size * stretch + ENVELOPE_MARGIN))
	if part == nil then
		return
	end
	local instance = kit.borrow(entry, "SpecialMesh")
	if instance == nil then
		return
	end
	local special = instance :: SpecialMesh
	special.MeshId = mesh.Id
	special.Parent = part
	-- Seeded by where the play is drawn and by the layer, so every client draws the same ring at the same
	-- angle.
	local spread: number = layer.Jitter or 0
	local jitter = if spread > 0 then randomFor(entry, entry.LayerIndex):NextNumber(-spread, spread) else 0
	entry.Volume = { Mesh = mesh, Base = base, Jitter = jitter }
	-- Dried on its play's clock, like the marks (VfxConfig.InkRamp), in its pigment and skin.
	local wet, dry = kit.wetAndDry(entry.Context, entry.Context.Color)
	entry.Wet = wet
	entry.Dry = dry
	entry.Primary = part
	VfxVolumes.step(entry, 0, 0, entry.StartedAt)
end

-- One frame of a volume: its size and stretch on the layer's ease, its fade on the ink's clock, its colour
-- drying on the play's, and its turn about its own axis by an angle -- never an increment -- on the play's
-- clock, so a volume handed from one layer to the next (Chain) keeps turning without a jump.
function VfxVolumes.step(entry: Entry, alpha: number, elapsed: number, now: number)
	local primary = entry.Primary
	local volume = entry.Volume
	if primary == nil or primary.Parent == nil or volume == nil then
		return
	end
	local part = primary :: BasePart
	local special = part:FindFirstChildOfClass("SpecialMesh")
	if special == nil then
		return
	end
	local layer = entry.Layer
	local mesh = volume.Mesh
	local ending = entry.Ending
	-- A landed volume keeps the shape the landing found it in: its shortened life would otherwise re-ease
	-- it to its end shape in one frame.
	local shape = if ending ~= nil and ending.Alpha ~= nil then ending.Alpha else alpha
	local size = kit.lerp(layer.Size, layer.EndSize, shape, 1) * entry.Scales.Size
	local from: { number } = layer.Stretch or ONE
	local to: { number } = layer.EndStretch or from
	local scale = Vector3.new(
		size * (from[1] + (to[1] - from[1]) * shape),
		size * (from[2] + (to[2] - from[2]) * shape),
		size * (from[3] + (to[3] - from[3]) * shape)
	)
	local transparency =
		math.clamp(kit.lerp(layer.Transparency, layer.EndTransparency, kit.fadeOf(layer, elapsed, alpha, 0), 0), 0, 1)
	if ending ~= nil then
		-- Landed: the drop splats into what it hit -- wider, flat along its flight -- and dries out, from
		-- where it was. Never a pop (rule 3), and fast then easing (rule 4).
		local splat = VolumeMath.splat(now - ending.At, VfxTimelineConfig.Land.Fade)
		local wide, long = VolumeMath.splatScale(splat)
		scale = Vector3.new(scale.X * wide, scale.Y * wide, scale.Z * long)
		transparency = ending.From + (1 - ending.From) * splat
	end
	special.Scale = scale
	special.Offset = pivotOffset(mesh, scale)
	-- A volume that rides a carrier was put on it this frame by the runtime (followCarrier), so its frame
	-- is the part's own; any other volume turns in the frame it was built in. Either way the turn is laid
	-- on a frame set this frame, never accumulated.
	local base = if layer.Ride == true then part.CFrame else volume.Base
	local angle = volume.Jitter + (layer.Spin or 0) * (now - entry.PlayStartedAt)
	part.CFrame = base * CFrame.Angles(0, 0, math.rad(layer.Roll or 0)) * turn(mesh.Axis, angle)
	part.Transparency = if transparency < OPAQUE_BELOW then 0 else transparency
	local wet, dry = entry.Wet, entry.Dry
	if wet ~= nil and dry ~= nil then
		part.Color = wet:Lerp(dry, kit.driedBy(entry, now))
	end
end

-- Scraps of the page thrown off a blast (a Debris layer, D-114): `count` of them, each a seeded throw
-- inside Spread degrees of straight up, in the layer's tones -- paper, never a pigment. Client only, no
-- physics: every client computes the same flights from the same seed (Pure/Scatter, VolumeMath.seed).
-- Not thrown over another play's warning (rule 9), and with no floor under the blast they fade in the
-- air instead of lying flat on nothing. A scrap grows in and fades out on VolumeMath's clocks.
function VfxVolumes.buildDebris(entry: Entry, place: CFrame, count: number)
	local layer = entry.Layer
	local shapes: { MeshConfig.Mesh } = {}
	for _, key in ipairs(layer.Meshes or {}) do
		local mesh = MeshConfig.get(key)
		if mesh == nil then
			missing(key, "is not in MeshConfig")
		elseif mesh.Id == "" then
			missing(key, ("has no id yet: upload and resolve %s (scripts/upload_assets.py)"):format(mesh.Source))
		else
			table.insert(shapes, mesh)
		end
	end
	if #shapes == 0 then
		return
	end
	local origin = place.Position
	local tones: { string } = layer.Tones or { "Ink" }
	local speed: { number } = layer.Speed or { 12, 24 }
	local lifetime: { number } = layer.Lifetime or { 1, 1.5 }
	local tumble: { number } = layer.Tumble or { 6, 12 }
	local spread = math.rad(layer.Spread or 45)
	local drag: number = layer.Drag or 3
	local floor, _, found = kit.groundAt(origin)
	local depth = VolumeMath.scrapDepth(origin.Y, floor.Y, found)
	-- The furthest a scrap can come down from the blast: its fastest throw carried to a standstill by the
	-- drag, its widest rock, and its own size.
	local reach = speed[2] * entry.Scales.Effect * math.sin(math.min(spread, math.pi / 2)) / drag
		+ 0.6
		+ (layer.Size or 0.8) * 1.3 * entry.Scales.Size
	if kit.overWarning(if depth ~= nil then Vector3.new(origin.X, origin.Y - depth, origin.Z) else origin, reach) then
		return
	end
	local scraps: { Scrap } = {}
	for index = 1, count do
		local random = randomFor(entry, entry.LayerIndex * 64 + index)
		-- Shape and tone drawn apart: two cycles run in step would pair the same shape with the same tone.
		local shape = shapes[random:NextInteger(1, #shapes)]
		local tone: { number } = WorldConfig.Colors[tones[random:NextInteger(1, #tones)]] or WorldConfig.Colors.Ink
		local around = random:NextNumber(0, 2 * math.pi)
		local up = random:NextNumber(0, spread)
		local throw = random:NextNumber(speed[1], speed[2]) * entry.Scales.Effect
		local piece: Scatter.Piece = {
			VX = math.sin(up) * math.cos(around) * throw,
			VY = math.cos(up) * throw,
			VZ = math.sin(up) * math.sin(around) * throw,
			Drag = drag,
			Fall = layer.Fall or 7,
			Rock = random:NextNumber(0.35, 0.6),
			RockRate = random:NextNumber(7, 10),
			Phase = random:NextNumber(0, 2 * math.pi),
			Tumble = random:NextNumber(tumble[1], tumble[2]),
		}
		local lasts = random:NextNumber(lifetime[1], lifetime[2])
		local size = (layer.Size or 0.8) * random:NextNumber(0.7, 1.3) * entry.Scales.Size
		local aspect = random:NextNumber(0.7, 1.3)
		-- The mesh first: a part hosted and then refused its mesh would stand in the world as a bare block
		-- for the layer's whole life, while a mesh refused its part stays parked and draws nothing.
		local instance = kit.borrow(entry, "SpecialMesh")
		if instance == nil then
			break
		end
		local part = kit.host(entry, CFrame.new(origin), Vector3.one * (size * 1.5 + 0.5))
		if part == nil then
			break
		end
		local special = instance :: SpecialMesh
		special.MeshId = shape.Id
		special.Parent = part
		part.Color = Palette.rgb(tone)
		local axis = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1))
		table.insert(scraps, {
			Part = part,
			Mesh = special,
			Shape = shape,
			Piece = piece,
			Size = Vector3.new(size * aspect, size, size / aspect),
			Lands = if depth ~= nil then Scatter.landing(piece, depth, lasts) else nil,
			Lasts = lasts,
			Axis = if axis.Magnitude > 1e-3 then axis.Unit else Vector3.xAxis,
			Yaw = random:NextNumber(0, 2 * math.pi),
		})
	end
	if #scraps == 0 then
		return
	end
	entry.Debris = { Origin = origin, Depth = depth or 0, Scraps = scraps }
	entry.Primary = scraps[1].Part
	VfxVolumes.stepDebris(entry, entry.StartedAt)
end

-- One frame of every scrap of a Debris layer, moved together (Workspace:BulkMoveTo).
function VfxVolumes.stepDebris(entry: Entry, now: number)
	local debris = entry.Debris
	if debris == nil then
		return
	end
	local t = now - entry.StartedAt
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for _, scrap in ipairs(debris.Scraps) do
		if scrap.Part.Parent ~= nil then
			local piece = scrap.Piece
			local grow = VolumeMath.scrapGrow(t)
			local fade = VolumeMath.scrapFade(t, scrap.Lasts)
			local shrink = 1 - fade * fade
			local lands = scrap.Lands
			local frame: CFrame
			if lands ~= nil and t >= lands then
				-- Down: where it touched the page, turning over SETTLE_SECONDS to lie flat on it.
				local x, _, z = Scatter.offset(piece, lands)
				local position = debris.Origin + Vector3.new(x, -debris.Depth + 0.02, z)
				local tumbling = CFrame.fromAxisAngle(scrap.Axis, Scatter.tumble(piece, lands))
				local flat = CFrame.Angles(0, scrap.Yaw, 0)
				local settle = math.min((t - lands) / VolumeMath.SettleSeconds, 1)
				frame = CFrame.new(position) * tumbling:Lerp(flat, 1 - (1 - settle) * (1 - settle))
			else
				local x, y, z = Scatter.offset(piece, t)
				frame = CFrame.new(debris.Origin + Vector3.new(x, y, z))
					* CFrame.fromAxisAngle(scrap.Axis, Scatter.tumble(piece, t))
			end
			local scale = scrap.Size * (grow * shrink)
			scrap.Mesh.Scale = scale
			scrap.Mesh.Offset = pivotOffset(scrap.Shape, scale)
			scrap.Part.Transparency = fade
			table.insert(parts, scrap.Part)
			table.insert(frames, frame)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Whether the dasher's own sketch would stand in their way: the camera inside the character (first
-- person hides it), or the dash running along the camera's aim, where every limb of it would stand
-- between the player and what they are running at.
local function inOwnWay(body: Instance, direction: Vector3): boolean
	local head = body:FindFirstChild("Head")
	if head ~= nil and head:IsA("BasePart") and head.LocalTransparencyModifier > 0.5 then
		return true
	end
	local camera = Workspace.CurrentCamera
	local dash = direction * Vector3.new(1, 0, 1)
	local look = if camera ~= nil then camera.CFrame.LookVector * Vector3.new(1, 0, 1) else Vector3.zero
	if dash.Magnitude < 1e-3 or look.Magnitude < 1e-3 then
		return false
	end
	return dash.Unit:Dot(look.Unit) >= math.cos(math.rad(VfxConfig.Afterimage.OwnHiddenWithinDegrees))
end

-- The limbs of `body` a sketch copies: every listed one that is a MeshPart with a mesh and shows.
local function limbsOf(body: Instance): { MeshPart }
	local out: { MeshPart } = {}
	for _, name in ipairs(VfxConfig.Afterimage.BodyParts) do
		local limb = body:FindFirstChild(name)
		if limb ~= nil and limb:IsA("MeshPart") and limb.MeshId ~= "" and limb.Transparency < 0.99 then
			local native = limb.MeshSize
			if native.X > 1e-4 and native.Y > 1e-4 and native.Z > 1e-4 then
				table.insert(out, limb)
			end
		end
	end
	return out
end

-- Whether a sketch of the body in `context` would be drawn at all: asked BEFORE the runtime spends a
-- slot of its budget on it, which it otherwise retired a live layer for, for nothing (review).
function VfxVolumes.canSketch(context: any): boolean
	local root: BasePart? = context.Follow
	local body = if root ~= nil then root.Parent else nil
	if body == nil or #limbsOf(body) == 0 then
		return false
	end
	return body ~= Players.LocalPlayer.Character or not inOwnWay(body, context.Direction)
end

-- Whether the body in `context` has covered `layer.Along` of its dash, as this screen sees it move: a
-- print laid by the clock landed on the still body on every other screen, whose copy of the dasher
-- starts moving only after the latency (review).
function VfxVolumes.reached(layer: any, context: any): boolean
	local root: BasePart? = context.Follow
	local reach: number? = context.Reach
	if root == nil or reach == nil then
		return true
	end
	local flat = context.Direction * Vector3.new(1, 0, 1)
	if flat.Magnitude < 1e-3 then
		return true
	end
	return (root.Position - context.Origin):Dot(flat.Unit) >= (layer.Along or 0) * reach
end

-- A print of the body `root` belongs to (an Afterimage layer, D-116): each of its limbs copied once where
-- it stands -- its mesh, its size, its frame -- into one Model, drawn flat by one Highlight: a fill in the
-- layer's Tone and an outline in ink, an ink print rather than a translucent copy, which read as a ghost
-- (review). Never moved again: a print is where the body WAS. The limb's mesh is already loaded by the
-- avatar, so nothing pops in. All or nothing: a print the pool cannot give every limb to is not drawn,
-- never drawn missing its legs.
function VfxVolumes.buildAfterimage(entry: Entry, root: BasePart?)
	local body = if root ~= nil then root.Parent else nil
	if body == nil then
		return
	end
	local config = VfxConfig.Afterimage
	local limbs = limbsOf(body)
	if #limbs == 0 then
		return
	end
	local own = body == Players.LocalPlayer.Character
	local toneName: string = if own then config.OwnTone else entry.Layer.Tone or ""
	local tone = CosmeticConfig.Tones[toneName] or CosmeticConfig.Tones.Graphite
	local outline = CosmeticConfig.Tones[config.Outline] or CosmeticConfig.Tones.Ink
	local modelInstance = kit.borrow(entry, "Model")
	local highlightInstance = kit.borrow(entry, "Highlight")
	if modelInstance == nil or highlightInstance == nil then
		return
	end
	local model = modelInstance :: Model
	local copies: { Limb } = {}
	for _, limb in ipairs(limbs) do
		-- The mesh first, as for the scraps: a part refused its mesh would be a bare block.
		local instance = kit.borrow(entry, "SpecialMesh")
		if instance == nil then
			return
		end
		local part = kit.host(entry, limb.CFrame, limb.Size)
		if part == nil then
			return
		end
		local special = instance :: SpecialMesh
		special.MeshId = limb.MeshId
		special.Parent = part
		part.Color = Palette.rgb(tone)
		part.Parent = model
		table.insert(copies, { Part = part, Mesh = special, Scale = limb.Size / limb.MeshSize })
	end
	local highlight = highlightInstance :: Highlight
	highlight.FillColor = Palette.rgb(tone)
	highlight.FillTransparency = 0
	highlight.OutlineColor = Palette.rgb(outline)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	model.Parent = Workspace
	entry.Afterimage = { Limbs = copies }
	entry.Primary = copies[1].Part
	VfxVolumes.stepAfterimage(entry, 0, 0)
end

-- One frame of a print: its limbs bleed from Size to EndSize, then shrink away (VolumeMath.sketchShrink).
-- Never moved, and never faded: a highlight is not drawn over a part that is at all transparent, so a
-- print goes by its size.
function VfxVolumes.stepAfterimage(entry: Entry, alpha: number, elapsed: number)
	local sketch = entry.Afterimage
	if sketch == nil then
		return
	end
	local layer = entry.Layer
	local size = kit.lerp(layer.Size, layer.EndSize, alpha, 1)
		* VolumeMath.sketchShrink(elapsed, VfxConfig.Afterimage.ShrinkShare)
	for _, limb in ipairs(sketch.Limbs) do
		if limb.Part.Parent ~= nil then
			limb.Mesh.Scale = limb.Scale * size
		end
	end
end

function VfxVolumes.bind(helpers: Kit)
	kit = helpers
end

return VfxVolumes
