--!strict
-- The generated volumes as the timelines draw them (D-114): held to the art bible -- nothing appears or
-- vanishes (rule 3), nothing linear (rule 4), a volume is mostly air, never over a warning, never bigger
-- than the harm it draws, never high and dark for long (rule 9) -- and the runtime held to what Studio
-- measured: pivot put back, one flat tone turned only about its own axis, frames rebuilt and never
-- accumulated, one volume handed from link to link without a second borrow. The arithmetic is held by
-- its outputs (Pure/VolumeMath); the wiring that calls it, by its lines.
local Easing = require("./easing")
local FeelMath = require("../src/shared/Pure/FeelMath")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local MeshConfig = require("../src/shared/Config/MeshConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local VolumeMath = require("../src/shared/Pure/VolumeMath")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function functionIn(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(header .. " is not in " .. path .. ": this gate would check nothing")
	end
	local finish = source:find("\nend\n", start, true)
	if finish == nil then
		error(header .. " has no end in " .. path)
	end
	return (source:sub(start, finish + 4):gsub("%s+", " "))
end

local function has(code: string, fragment: string): boolean
	return code:find(fragment, 1, true) ~= nil
end

local VOLUMES = "src/client/Controllers/VfxVolumes.luau"
local TIMELINE = "src/client/Controllers/VfxTimeline.luau"

type Placed = { Id: string, Phase: any, Layer: any, Start: number }

-- Every Mesh and Debris layer of every timeline, with its absolute start in its timeline's own clock.
local function volumes(): { Placed }
	local out: { Placed } = {}
	for id, timeline in pairs(VfxTimelineConfig.Timelines) do
		for _, phase in ipairs(timeline.Phases) do
			local start = VfxTimelineConfig.phaseAt(id, phase.Name, nil) or 0
			for _, layer in ipairs(phase.Layers) do
				if layer.Kind == "Mesh" or layer.Kind == "Debris" then
					table.insert(out, { Id = id, Phase = phase, Layer = layer, Start = start + layer.At })
				end
			end
		end
	end
	return out
end

-- The links of each chain, in order.
local function chains(): { [string]: { Placed } }
	local out: { [string]: { Placed } } = {}
	for _, placed in ipairs(volumes()) do
		local chain = placed.Layer.Chain
		if chain ~= nil then
			local key = placed.Id .. "/" .. chain
			out[key] = out[key] or {}
			table.insert(out[key], placed)
		end
	end
	for _, links in pairs(out) do
		table.sort(links, function(a, b)
			return a.Start < b.Start
		end)
	end
	return out
end

-- Compared by the config's own layer table: every call to volumes() builds new Placed records, so a
-- record never equals one from another call (which once made every chain link neither first nor last,
-- and let both rule-3 checks below skip every chained volume).
local function isFirstLink(placed: Placed): boolean
	local chain = placed.Layer.Chain
	if chain == nil then
		return true
	end
	return chains()[placed.Id .. "/" .. chain][1].Layer == placed.Layer
end

local function isLastLink(placed: Placed): boolean
	local chain = placed.Layer.Chain
	if chain == nil then
		return true
	end
	local links = chains()[placed.Id .. "/" .. chain]
	return links[#links].Layer == placed.Layer
end

local function smallest(values: { number }?): number
	if values == nil then
		return 1
	end
	return math.min(values[1], values[2], values[3])
end

-- The largest blast radius any glyph has: the size every radius-measured volume is checked at.
local function largestRadius(): number
	local radius = 0
	for _, def in ipairs(GlyphConfig.Glyphs) do
		local params = def.Params :: any
		if type(params) == "table" and type(params.BlastRadius) == "number" then
			radius = math.max(radius, params.BlastRadius)
		end
	end
	return radius
end

-- A layer's eased progress at `t` (0 to 1), on the curve it declares, as the runtime reads it.
local function eased(layer: any, t: number): number
	return Easing.value(layer.Ease, layer.EaseDirection, t)
end

-- WCAG's contrast ratio between two sRGB colours (0-255): what "visible on the page" is measured by.
local function contrast(a: { number }, b: { number }): number
	local function luminance(rgb: { number }): number
		local total = 0
		for index, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
			local c = rgb[index] / 255
			local linear = if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
			total += weight * linear
		end
		return total
	end
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

describe("a Mesh layer", function()
	it("names a mesh MeshConfig has, carries no texture, and declares its size and its ease", function()
		local meshes = 0
		for _, placed in ipairs(volumes()) do
			local layer = placed.Layer
			if layer.Kind == "Mesh" then
				meshes += 1
				expect(MeshConfig.get(layer.Mesh)).never.toBe(nil)
				expect(layer.Texture).toBe(nil)
				expect(type(layer.Size)).toBe("number")
				-- Rule 4: a volume with no declared ease would grow linearly.
				expect(type(layer.Ease)).toBe("string")
				for _, stretch in ipairs({ layer.Stretch or { 1, 1, 1 }, layer.EndStretch or { 1, 1, 1 } }) do
					expect(#stretch).toBe(3)
					for axis = 1, 3 do
						expect(stretch[axis]).toBeGreaterThanOrEqual(0)
					end
				end
				-- Tilted more than this, its up-pointing normals would light it a different tone.
				expect(math.abs(layer.Roll or 0)).toBeLessThanOrEqual(30)
				expect(layer.Face == nil or layer.Face == "Aim" or layer.Face == "Ground").toBe(true)
			end
		end
		expect(meshes).toBeGreaterThanOrEqual(7)
	end)

	it("grows in and goes out: never appears, never vanishes (rule 3)", function()
		for _, placed in ipairs(volumes()) do
			local layer = placed.Layer
			if layer.Kind == "Mesh" then
				local name = placed.Id .. " / " .. layer.Mesh
				if isFirstLink(placed) then
					local small = layer.Size <= 0.35 * (layer.EndSize or layer.Size)
					local flat = smallest(layer.Stretch) <= 0.1
					local faint = (layer.Transparency or 0) >= 0.6
					if not (small or flat or faint) then
						error(name .. " appears at full size")
					end
					-- And over several frames: a drop grown on Back Out in 0.06 s did 87 % of its growth in
					-- one frame at 60 fps, then overshot -- an appearance, however small it started.
					local frame = (1 / 60) / layer.For
					for step = 0, 99 do
						local t = step / 100
						local grown = eased(layer, math.min(t + frame, 1)) - eased(layer, t)
						if grown > 0.6 then
							error(("%s grows %.0f %% of the way in one frame"):format(name, grown * 100))
						end
					end
				end
				-- The last link of a riding volume ends through its landing (VfxTimeline.land), which
				-- splats it and dries it out.
				if isLastLink(placed) and layer.Ride ~= true then
					local faded = (layer.EndTransparency or layer.Transparency or 0) >= 0.95
					local gone = (layer.EndSize or layer.Size) <= 0.1 * layer.Size
					local flattened = smallest(layer.EndStretch or layer.Stretch) <= 0.1
					if not (faded or gone or flattened) then
						error(name .. " vanishes at the end of its life")
					end
				end
			end
		end
	end)

	it("hands a volume from link to link exactly where the last one left it", function()
		-- The runtime takes the first link of a chain a play queues as its head (VfxTimeline.play): that is
		-- the declared order, which must be the order the links start in.
		for id, timeline in pairs(VfxTimelineConfig.Timelines) do
			local last: { [string]: number } = {}
			for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
				for _, phase in ipairs(timeline.Phases) do
					if phase.Name == name then
						local start = VfxTimelineConfig.phaseAt(id, phase.Name, nil) or 0
						for _, layer in ipairs(phase.Layers) do
							local chain = layer.Chain
							if chain ~= nil then
								if last[chain] ~= nil and start + layer.At < last[chain] then
									error(("%s declares a link of %s before the link it follows"):format(id, chain))
								end
								last[chain] = start + layer.At
							end
						end
					end
				end
			end
		end
		local handed = 0
		for key, links in pairs(chains()) do
			expect(#links).toBeGreaterThanOrEqual(2)
			for index = 2, #links do
				local previous, next = links[index - 1].Layer, links[index].Layer
				handed += 1
				local where = key .. " link " .. index
				if math.abs(links[index].Start - (links[index - 1].Start + previous.For)) > 1e-6 then
					error(where .. " does not start where the link before it ends")
				end
				expect(next.Mesh).toBe(previous.Mesh)
				expect(next.Face).toBe(previous.Face)
				expect(next.Size).toBe(previous.EndSize or previous.Size)
				expect(next.Transparency or 0).toBe(previous.EndTransparency or previous.Transparency or 0)
				local ended = previous.EndStretch or previous.Stretch or { 1, 1, 1 }
				local starts = next.Stretch or { 1, 1, 1 }
				for axis = 1, 3 do
					expect(starts[axis]).toBe(ended[axis])
				end
				expect(next.Spin or 0).toBe(previous.Spin or 0)
				expect(next.SizeFrom).toBe(previous.SizeFrom)
			end
		end
		expect(handed).toBeGreaterThanOrEqual(2)
	end)

	it("lies on the ground or rides a carrier, never both, and a timeline has one riding body at most", function()
		local riders: { [string]: number } = {}
		for _, placed in ipairs(volumes()) do
			local layer = placed.Layer
			if layer.Face == "Ground" then
				expect(layer.Ride).never.toBe(true)
				expect(layer.Follow).never.toBe(true)
			end
			if layer.Kind == "Mesh" and layer.Ride == true then
				riders[placed.Id .. "/" .. placed.Phase.Name] = (riders[placed.Id .. "/" .. placed.Phase.Name] or 0) + 1
			end
		end
		for key, count in pairs(riders) do
			if count > 1 then
				error(key .. " rides " .. count .. " volumes: the body of a projectile is one thing")
			end
		end
	end)
end)

describe("the volumes on screen", function()
	it("never sit over a warning: none in a windowed phase, a boss's timeline or a kill effect", function()
		for _, placed in ipairs(volumes()) do
			if placed.Phase.Window == true then
				error(placed.Id .. " draws a volume over its own warning")
			end
			if placed.Id:sub(1, 4) == "Boss" or placed.Id:sub(1, 4) == "Kill" then
				error(placed.Id .. " draws a volume, and a boss's or a kill's page is read, not decorated")
			end
		end
	end)

	it("never reach past the harm they draw, and the blast's circle reaches exactly to it", function()
		-- Every volume laid on the floor measures itself against the blast, so this covers all of them.
		local circles = 0
		for _, placed in ipairs(volumes()) do
			local layer = placed.Layer
			if layer.Kind == "Mesh" and layer.Face == "Ground" then
				local name = placed.Id .. " / " .. layer.Mesh
				if layer.SizeFrom ~= "Radius" then
					error(name .. " lies on the floor without measuring itself against the blast")
				end
				local mesh = MeshConfig.get(layer.Mesh) :: MeshConfig.Mesh
				-- Its real reach from where it is placed: the furthest ink across the floor, at its size and
				-- stretch at every point of its declared ease (a Back overshoots).
				local function reachAt(a: number): number
					local size = layer.Size + ((layer.EndSize or layer.Size) - layer.Size) * a
					local from = layer.Stretch or { 1, 1, 1 }
					local to = layer.EndStretch or from
					local furthest = 0
					for _, axis in ipairs({ 1, 3 }) do
						local stretch = from[axis] + (to[axis] - from[axis]) * a
						local extent = math.max(
							math.abs(mesh.Min[axis] - mesh.Pivot[axis]),
							math.abs(mesh.Max[axis] - mesh.Pivot[axis])
						)
						furthest = math.max(furthest, extent * size * stretch)
					end
					return furthest
				end
				for step = 0, 100 do
					local reach = reachAt(eased(layer, step / 100))
					if reach > 1 + 1e-6 then
						error(("%s reaches %.2f of the blast's radius"):format(name, reach))
					end
				end
				if mesh.Reference == "OuterDiameter" and not layer.Flourish then
					circles += 1
					if math.abs(reachAt(1) - 1) > 0.05 then
						error(("%s ends at %.2f of the blast's radius, not at its edge"):format(name, reachAt(1)))
					end
				end
			end
		end
		expect(circles).toBeGreaterThanOrEqual(1)
	end)

	it("keep a splash crown below the waist, and high and dark for under a third of a second", function()
		-- Measured on each link's own declared curve (tests/easing.luau), at the largest blast radius any
		-- glyph has.
		local radius = largestRadius()
		expect(radius).toBeGreaterThan(0)
		local crowns = 0
		for key, links in pairs(chains()) do
			if links[1].Layer.Mesh == "Crown" then
				crowns += 1
				local mesh = MeshConfig.get("Crown") :: MeshConfig.Mesh
				local tall = mesh.Max[2] - mesh.Min[2]
				local highest, high = 0, 0
				for _, placed in ipairs(links) do
					local layer = placed.Layer
					for step = 0, 100 do
						local t = step / 100
						local a = eased(layer, t)
						local size = (layer.Size + ((layer.EndSize or layer.Size) - layer.Size) * a) * radius
						local from = (layer.Stretch or { 1, 1, 1 })[2]
						local to = (layer.EndStretch or layer.Stretch or { 1, 1, 1 })[2]
						local h = tall * size * (from + (to - from) * a)
						highest = math.max(highest, h)
						if h > 1.5 then
							high += layer.For / 100
						end
					end
				end
				if highest > 3 then
					error(("%s stands %.2f studs tall at a %d-stud blast: over the waist"):format(key, highest, radius))
				end
				if high > 1 / 3 then
					error(("%s stands high for %.2f s at a %d-stud blast"):format(key, high, radius))
				end
			end
		end
		expect(crowns).toBeGreaterThanOrEqual(1)
	end)

	it("throws scraps of paper in the page's inks, never a pigment, and only as a flourish", function()
		local debris = 0
		for _, placed in ipairs(volumes()) do
			local layer = placed.Layer
			if layer.Kind == "Debris" then
				debris += 1
				expect(layer.Flourish).toBe(true)
				expect(layer.Count).toBeGreaterThanOrEqual(1)
				for _, key in ipairs(layer.Meshes) do
					expect(MeshConfig.get(key)).never.toBe(nil)
				end
				-- Every tone, seen against every floor it can fall on: in the page's pale tones -- and in the
				-- training ring's wash, where the proofs stand -- scraps were measured invisible. One by one,
				-- because an average let two invisible tones hide behind two dark ones.
				for _, tone in ipairs(layer.Tones) do
					local rgb = WorldConfig.Colors[tone]
					expect(rgb).never.toBe(nil)
					expect((PigmentConfig.Colors :: any)[tone]).toBe(nil)
					for _, floor in ipairs({ "Page", "Bone", "Wash" }) do
						if contrast(rgb, WorldConfig.Colors[floor]) < 3 then
							error(("%s scraps in %s vanish on %s"):format(placed.Id, tone, floor))
						end
					end
				end
			end
		end
		expect(debris).toBeGreaterThanOrEqual(1)
	end)

	it("carry their meaning on every tier: only named flourishes are left out, and a crown needs a floor", function()
		-- Which volumes are weight and not meaning is a design decision, so it is written down here:
		-- a new volume is drawn on every tier until someone decides otherwise, on purpose.
		local FLOURISHES = { ["Explosion/SplitRing"] = true, ["Explosion/Debris"] = true, ["Hit/Crescent"] = true }
		local found: { [string]: boolean } = {}
		for _, placed in ipairs(volumes()) do
			local layer = placed.Layer
			local key = placed.Id .. "/" .. (layer.Mesh or layer.Kind)
			if layer.Flourish == true then
				found[key] = true
				if not FLOURISHES[key] then
					error(key .. " is left out of the lower tiers and is not a named flourish")
				end
			end
			if layer.Mesh == "Crown" and layer.NeedsGround ~= true then
				error(placed.Id .. " draws a crown that would stand in mid-air")
			end
		end
		for key in pairs(FLOURISHES) do
			if not found[key] then
				error(key .. " is named a flourish and is drawn on every tier")
			end
		end
	end)
end)

describe("the arithmetic of a volume (VolumeMath)", function()
	it("puts every mesh's pivot on its part: a crown stands on the floor, a drop's head leads its flight", function()
		-- Every shipped mesh is pivoted at its origin, so one that is not keeps the pivot honest.
		local shapes: { [string]: any } =
			{ Offcentre = { Min = { -1, 0, -2 }, Max = { 3, 1, 2 }, Pivot = { 1, 0.5, -1 } } }
		for key, mesh in pairs(MeshConfig.Meshes) do
			shapes[key] = mesh
		end
		for key, mesh in pairs(shapes) do
			for _, scale in ipairs({ { 1, 1, 1 }, { 2.5, 0.4, 1.7 } }) do
				local x, y, z = VolumeMath.pivotOffset(mesh.Min, mesh.Max, mesh.Pivot, scale[1], scale[2], scale[3])
				local offset = { x, y, z }
				-- The importer draws the mesh centred on offset; its bounds must land where the generator put
				-- them around its pivot.
				for axis = 1, 3 do
					local half = (mesh.Max[axis] - mesh.Min[axis]) / 2 * scale[axis]
					local low = (mesh.Min[axis] - mesh.Pivot[axis]) * scale[axis]
					local high = (mesh.Max[axis] - mesh.Pivot[axis]) * scale[axis]
					if math.abs(offset[axis] - half - low) > 1e-9 or math.abs(offset[axis] + half - high) > 1e-9 then
						error(("%s is drawn off its pivot on axis %d"):format(key, axis))
					end
				end
			end
		end
		local crown = MeshConfig.get("Crown") :: MeshConfig.Mesh
		local _, up = VolumeMath.pivotOffset(crown.Min, crown.Max, crown.Pivot, 3, 2, 3)
		expect(up - (crown.Max[2] - crown.Min[2])).toBeCloseTo(0, 9)
		-- The drop's round head is on its pivot and its tail trails behind it (+Z: a flight looks down -Z).
		local drop = MeshConfig.get("Drop") :: MeshConfig.Mesh
		local _, _, along = VolumeMath.pivotOffset(drop.Min, drop.Max, drop.Pivot, 1, 1, 1)
		expect(along).toBeGreaterThan(0)
	end)

	it("turns a volume only about its own axis, and faces it along the floor", function()
		for _, case in ipairs({ { "X", 1 }, { "Y", 2 }, { "Z", 3 } }) do
			local angles = { VolumeMath.turn(case[1], 0.7) }
			for axis = 1, 3 do
				expect(angles[axis]).toBe(if axis == case[2] then 0.7 else 0)
			end
		end
		local x, y, z = VolumeMath.flatFacing(3, -4, 4)
		expect(y).toBe(0)
		expect(math.sqrt(x * x + z * z)).toBeCloseTo(1, 9)
		expect(x).toBeCloseTo(0.6, 9)
		expect(z).toBeCloseTo(0.8, 9)
		local fx, fy, fz = VolumeMath.flatFacing(0, 1, 0)
		expect(fx).toBe(0)
		expect(fy).toBe(0)
		expect(fz).toBe(-1)
	end)

	it("splats a landed drop wider and flatter, fast then easing, and done with its fade", function()
		expect(VolumeMath.splat(0, 0.1)).toBe(0)
		expect(VolumeMath.splat(0.1, 0.1)).toBe(1)
		expect(VolumeMath.splat(5, 0.1)).toBe(1)
		expect(VolumeMath.splat(0.05, 0.1)).toBeGreaterThan(0.5)
		local last = 0
		for step = 1, 20 do
			local splat = VolumeMath.splat(step * 0.005, 0.1)
			expect(splat >= last).toBe(true)
			last = splat
		end
		local wide, long = VolumeMath.splatScale(0)
		expect(wide).toBe(1)
		expect(long).toBe(1)
		wide, long = VolumeMath.splatScale(1)
		expect(wide).toBeGreaterThan(1.3)
		expect(long).toBeLessThan(0.3)
	end)

	it("grows a scrap in, fast then easing, and fades it on the ink's clock at the end of its life", function()
		expect(VolumeMath.scrapGrow(0)).toBe(VolumeMath.GrowFrom)
		expect(VolumeMath.scrapGrow(VolumeMath.GrowSeconds)).toBe(1)
		expect(VolumeMath.scrapGrow(10)).toBe(1)
		-- Eased, not linear (rule 4): past halfway at half its time.
		local half = VolumeMath.scrapGrow(VolumeMath.GrowSeconds / 2)
		expect(half).toBeGreaterThan(VolumeMath.GrowFrom + (1 - VolumeMath.GrowFrom) / 2)
		local lasts = 1.3
		expect(VolumeMath.scrapFade(0, lasts)).toBe(0)
		expect(VolumeMath.scrapFade(lasts - VolumeMath.FadeSeconds, lasts)).toBe(0)
		expect(VolumeMath.scrapFade(lasts, lasts)).toBeCloseTo(1, 9)
		local previous = 0
		for step = 0, 60 do
			local t = lasts - VolumeMath.FadeSeconds + step * VolumeMath.FadeSeconds / 60
			local fade = VolumeMath.scrapFade(t, lasts)
			local into = (t - (lasts - VolumeMath.FadeSeconds)) / VolumeMath.FadeSeconds
			expect(fade).toBeCloseTo(FeelMath.inkFade(into, 1), 9)
			-- Never a step a frame could see as a pop.
			expect(fade - previous).toBeLessThan(0.15)
			previous = fade
		end
	end)

	it("lands a scrap only on a floor under the blast", function()
		expect(VolumeMath.scrapDepth(10, 7.5, true)).toBe(2.5)
		expect(VolumeMath.scrapDepth(10, 10, true)).toBe(0)
		expect(VolumeMath.scrapDepth(10, 7.5, false)).toBe(nil)
		-- The probe starts a stud up: a "floor" above the blast is its ceiling, not its floor.
		expect(VolumeMath.scrapDepth(10, 10.6, true)).toBe(nil)
	end)

	it("seeds a blast from what every client received, not from a count of its own", function()
		local a = VolumeMath.seed(12.25, 3, -40.5, 7)
		expect(VolumeMath.seed(12.25, 3, -40.5, 7)).toBe(a)
		expect(VolumeMath.seed(12.25, 3, -40.5, 8)).never.toBe(a)
		expect(VolumeMath.seed(13.25, 3, -40.5, 7)).never.toBe(a)
		expect(VolumeMath.seed(12.25, 3, -39.5, 7)).never.toBe(a)
		for _, seed in ipairs({ a, VolumeMath.seed(-5000, -20, 5000, 999) }) do
			expect(seed).toBe(math.floor(seed))
			expect(seed).toBeGreaterThanOrEqual(0)
			expect(seed).toBeLessThan(2147483647)
		end
	end)
end)

describe("the runtime of a volume", function()
	it("draws with VolumeMath's numbers: pivot, turn, facing, splat, all rebuilt every frame", function()
		local source = strip(fs.readFile(VOLUMES)):gsub("%s+", " ")
		expect(
			has(
				source,
				"return Vector3.new(VolumeMath.pivotOffset(mesh.Min, mesh.Max, mesh.Pivot, scale.X, scale.Y, scale.Z))"
			)
		).toBe(true)
		expect(has(source, "return CFrame.Angles(VolumeMath.turn(axis, angle))")).toBe(true)
		expect(
			has(source, "CFrame.lookAlong(place.Position, Vector3.new(VolumeMath.flatFacing(look.X, look.Y, look.Z)))")
		).toBe(true)
		local step = functionIn(VOLUMES, "function VfxVolumes.step(")
		expect(has(step, "special.Scale = scale special.Offset = pivotOffset(mesh, scale)")).toBe(true)
		expect(
			has(step, "part.CFrame = base * CFrame.Angles(0, 0, math.rad(layer.Roll or 0)) * turn(mesh.Axis, angle)")
		).toBe(true)
		expect(has(step, "local base = if layer.Ride == true then part.CFrame else volume.Base")).toBe(true)
		expect(has(step, "local angle = volume.Jitter + (layer.Spin or 0) * (now - entry.PlayStartedAt)")).toBe(true)
		-- Never a frame compounded onto itself.
		expect(has(source, "part.CFrame = part.CFrame *")).toBe(false)
		-- Faded on the ink's clock, dried like every mark, drawn opaque below a hair of transparency.
		expect(has(step, "kit.fadeOf(layer, elapsed, alpha, 0)")).toBe(true)
		expect(has(step, "part.Color = wet:Lerp(dry, kit.driedBy(entry, now))")).toBe(true)
		expect(has(step, "part.Transparency = if transparency < OPAQUE_BELOW then 0 else transparency")).toBe(true)
		-- Landed: the shape the landing found, splatted by VolumeMath.
		expect(has(step, "local shape = if ending ~= nil and ending.Alpha ~= nil then ending.Alpha else alpha")).toBe(
			true
		)
		expect(has(step, "local size = kit.lerp(layer.Size, layer.EndSize, shape, 1) * entry.Scales.Size")).toBe(true)
		expect(has(step, "size * (from[3] + (to[3] - from[3]) * shape)")).toBe(true)
		expect(has(step, "local splat = VolumeMath.splat(now - ending.At, VfxTimelineConfig.Land.Fade)")).toBe(true)
		expect(has(step, "scale = Vector3.new(scale.X * wide, scale.Y * wide, scale.Z * long)")).toBe(true)
		expect(has(step, "transparency = ending.From + (1 - ending.From) * splat")).toBe(true)
	end)

	it("is seeded from what every client received, and needs a floor where it says so", function()
		local source = strip(fs.readFile(VOLUMES))
		expect(has(source, "PlayId")).toBe(false)
		local seeded = functionIn(VOLUMES, "local function randomFor(")
		expect(has(seeded, "local origin: Vector3 = entry.Context.Origin")).toBe(true)
		expect(has(seeded, "return Random.new(VolumeMath.seed(origin.X, origin.Y, origin.Z, salt))")).toBe(true)
		local build = functionIn(VOLUMES, "function VfxVolumes.build(")
		expect(has(build, "randomFor(entry, entry.LayerIndex):NextNumber(-spread, spread)")).toBe(true)
		expect(has(build, 'if layer.Face == "Ground" then')).toBe(true)
		expect(
			has(build, "if base ~= nil and kit.overWarning(base.Position, reach * size * stretch / 2) then return end")
		).toBe(true)
		local ground = functionIn(VOLUMES, "local function groundFrame(")
		expect(has(ground, "if not found and needsGround then return nil end")).toBe(true)
	end)

	it("finds the floor under a body, never on it", function()
		local ground = functionIn(TIMELINE, "local function groundAt(")
		expect(has(ground, "if result == nil then return position, Vector3.yAxis, false end")).toBe(true)
		expect(
			has(
				ground,
				"local body = bodyOf(result.Instance) if body == nil then return result.Position, result.Normal, true end"
			)
		).toBe(true)
		expect(has(ground, "table.insert(exclude, body)")).toBe(true)
		expect(has(ground, "params.FilterDescendantsInstances = exclude")).toBe(true)
		local body = functionIn(TIMELINE, "local function bodyOf(")
		expect(
			has(
				body,
				'local model = instance:FindFirstAncestorOfClass("Model") if model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil then return model end'
			)
		).toBe(true)
	end)

	it("never lays a volume over another play's warning", function()
		local over = functionIn(TIMELINE, "local function overWarning(")
		expect(has(over, 'if entry.Warning and primary ~= nil and primary:IsA("BasePart") then')).toBe(true)
		expect(has(over, "local point = primary.CFrame:PointToObjectSpace(position)")).toBe(true)
		expect(
			has(
				over,
				"if math.abs(point.Z) <= WARNING_DEPTH_STUDS and across * across + along * along < reach * reach then return true end"
			)
		).toBe(true)
		expect(has(functionIn(TIMELINE, "function VfxTimeline.Init("), "overWarning = overWarning,")).toBe(true)
		local debris = functionIn(VOLUMES, "function VfxVolumes.buildDebris(")
		expect(has(debris, "if kit.overWarning(")).toBe(true)
	end)

	it("splats a riding body, or a link whose flight was dropped, into its landing, in the shape it had", function()
		local land = functionIn(TIMELINE, "function VfxTimeline.land(")
		expect(
			has(land, 'if item.PlayId == playId and item.Phase == "Travel" and chain ~= nil then cut[chain] = true end')
		).toBe(true)
		expect(
			has(
				land,
				'if item.PlayId == playId and (item.Phase == "Travel" or (chain ~= nil and cut[chain])) then table.remove(pending, index)'
			)
		).toBe(true)
		expect(
			has(
				land,
				'elseif entry.Layer.Kind == "Mesh" and primary:IsA("BasePart") and (entry.Layer.Ride == true or (chain ~= nil and cut[chain])) then entry.Ending = { At = now, From = primary.Transparency, Alpha = eased(entry.Layer, progressOf(entry, now)) } entry.EndsAt = now + settings.Fade'
			)
		).toBe(true)
		local activate = functionIn(TIMELINE, "local function activate(")
		expect(has(activate, 'local body = entry.Layer.Kind == "Mesh" and entry.Layer.Ride == true')).toBe(true)
		expect(has(activate, 'if not entry.Warning and entry.Layer.Kind ~= "Carrier" and not body then')).toBe(true)
	end)

	it(
		"hands a volume on without a second borrow or a slot of the budget, and draws a later link only from its head",
		function()
			local activate = functionIn(TIMELINE, "local function activate(")
			expect(
				has(
					activate,
					'local predecessor: number? = nil local chain = layer.Chain if layer.Kind == "Mesh" and chain ~= nil then for index, previous in ipairs(live) do if previous.PlayId == item.PlayId and previous.Layer.Chain == chain and previous.Volume ~= nil then predecessor = index break end end if predecessor == nil and not item.ChainHead then return end end if predecessor == nil and #live >= tier.Layers then'
				)
			).toBe(true)
			expect(
				has(
					activate,
					"if predecessor ~= nil then local previous = table.remove(live, predecessor) :: Live entry.Instances = previous.Instances entry.Primary = previous.Primary entry.Volume = previous.Volume entry.Wet = previous.Wet entry.Dry = previous.Dry end"
				)
			).toBe(true)
			expect(
				has(activate, 'elseif layer.Kind == "Mesh" and entry.Volume == nil then VfxVolumes.build(entry, place)')
			).toBe(true)
			expect(has(activate, "if layer.Flourish == true and not tier.Flourishes then return end")).toBe(true)
			expect(has(activate, "local count = math.floor((layer.Count or 0) * tier.ParticleScale)")).toBe(true)
			local play = functionIn(TIMELINE, "function VfxTimeline.play(")
			expect(
				has(
					play,
					"local chain = layer.Chain local head = chain ~= nil and not begun[chain] if chain ~= nil then begun[chain] = true end"
				)
			).toBe(true)
			expect(has(play, "ChainHead = head,")).toBe(true)
		end
	)

	it("throws every scrap from a seed, lands it only on a floor, and moves them all in one call", function()
		local build = functionIn(VOLUMES, "function VfxVolumes.buildDebris(")
		expect(has(build, "local floor, _, found = kit.groundAt(origin)")).toBe(true)
		expect(has(build, "local depth = VolumeMath.scrapDepth(origin.Y, floor.Y, found)")).toBe(true)
		expect(has(build, "Lands = if depth ~= nil then Scatter.landing(piece, depth, lasts) else nil,")).toBe(true)
		expect(has(build, "local random = randomFor(entry, entry.LayerIndex * 64 + index)")).toBe(true)
		expect(has(build, "local shape = shapes[random:NextInteger(1, #shapes)]")).toBe(true)
		-- The mesh before the part: a part refused its mesh would stand in the world as a bare block.
		local mesh =
			build:find('local instance = kit.borrow(entry, "SpecialMesh") if instance == nil then break end', 1, true)
		local part = build:find("local part = kit.host(entry, CFrame.new(origin)", 1, true)
		expect(mesh).never.toBe(nil)
		expect(part).never.toBe(nil)
		expect((mesh :: number) < (part :: number)).toBe(true)
		local debris = functionIn(VOLUMES, "function VfxVolumes.stepDebris(")
		expect(has(debris, "Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)")).toBe(true)
		expect(has(debris, "local grow = VolumeMath.scrapGrow(t)")).toBe(true)
		expect(has(debris, "local fade = VolumeMath.scrapFade(t, scrap.Lasts)")).toBe(true)
		expect(has(debris, "scrap.Part.Transparency = fade")).toBe(true)
		expect(has(debris, "scrap.Mesh.Offset = pivotOffset(scrap.Shape, scale)")).toBe(true)
	end)
end)
