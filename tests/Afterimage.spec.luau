--!strict
-- The kit in charcoal and the dodge's sketch (D-114, D-116): the punch, its hit and the dash drawn in the
-- page's ink rather than a pigment or white, its hit told to the two people in it in vellum; the dash
-- leaving flat ink prints of the body -- every limb, one highlight, never moved, laid where the body
-- really passed, shrinking away -- fewer on the lower tiers and none on the lowest, the dasher's own
-- paler and kept out of their way. The engine draws a print, so the runtime is held by its lines.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local EffectCost = require("../scripts/effect-cost")
local FeelConfig = require("../src/shared/Config/FeelConfig")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local PoolPolicy = require("../src/shared/Pure/PoolPolicy")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local VolumeMath = require("../src/shared/Pure/VolumeMath")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local VOLUMES = "src/client/Controllers/VfxVolumes.luau"
local TIMELINE = "src/client/Controllers/VfxTimeline.luau"
local LIBRARY = "src/client/Controllers/VfxLibrary.luau"

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

type Placed = { Id: string, Phase: any, Layer: any }

local function layersOf(kind: string): { Placed }
	local out: { Placed } = {}
	for id, timeline in pairs(VfxTimelineConfig.Timelines) do
		for _, phase in ipairs(timeline.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Kind == kind then
					table.insert(out, { Id = id, Phase = phase, Layer = layer })
				end
			end
		end
	end
	return out
end

local function luminance(rgb: { number }): number
	return 0.2126 * rgb[1] + 0.7152 * rgb[2] + 0.0722 * rgb[3]
end

describe("a dash's sketch", function()
	it("is an ink print laid along the path, bleeding a little, never transparent, never following", function()
		local sketches = layersOf("Afterimage")
		expect(#sketches).toBeGreaterThanOrEqual(2)
		local along: { [number]: number } = {}
		for _, placed in ipairs(sketches) do
			local layer = placed.Layer
			-- A dodge names no school: ink, never a pigment.
			expect((CosmeticConfig.Tones :: any)[layer.Tone]).never.toBe(nil)
			expect((PigmentConfig.Colors :: any)[layer.Tone]).toBe(nil)
			-- A highlight is not drawn over a part that is at all transparent: a print goes by its size.
			expect(layer.Transparency).toBe(nil)
			expect(layer.EndTransparency).toBe(nil)
			-- The bleed of ink, not a growing body, and brief: a print is a moment, not a decoy.
			expect(type(layer.Ease)).toBe("string")
			expect(layer.Size).toBe(1)
			expect(layer.EndSize > 1 and layer.EndSize <= 1.1).toBe(true)
			expect(layer.For).toBeLessThanOrEqual(1 / 3)
			expect(layer.Along > 0 and layer.Along < 1).toBe(true)
			along[layer.Print] = layer.Along
			-- Follow would drag the print along with the body: a print is where the body WAS.
			expect(layer.Follow).never.toBe(true)
			expect(placed.Phase.Window).never.toBe(true)
			expect(placed.Id).toBe("Dash")
		end
		-- Each further along the path than the one before.
		for rank = 2, #sketches do
			expect(along[rank] > along[rank - 1]).toBe(true)
		end
	end)

	it("is numbered, and each tier draws at most as many as it says -- the lowest two none", function()
		local prints: { [number]: boolean } = {}
		local highest = 0
		for _, placed in ipairs(layersOf("Afterimage")) do
			local rank = placed.Layer.Print
			expect(type(rank)).toBe("number")
			expect(rank).toBe(math.floor(rank))
			expect(prints[rank]).toBe(nil)
			prints[rank] = true
			highest = math.max(highest, rank)
		end
		for rank = 1, highest do
			expect(prints[rank]).toBe(true)
		end
		local previous = math.huge
		for _, tierName in ipairs(QualityConfig.Order) do
			local count = QualityConfig.Tiers[tierName].Afterimages
			expect(count <= previous).toBe(true)
			previous = count
		end
		expect(QualityConfig.Tiers.High.Afterimages).toBe(highest)
		expect(QualityConfig.Tiers.Low.Afterimages).toBe(0)
		expect(QualityConfig.Tiers.Performance.Afterimages).toBe(0)
	end)

	it("copies every limb the cost model pays for and nothing worn, within ceilings of its own", function()
		local config = VfxConfig.Afterimage
		local parts = config.BodyParts
		local borrows = EffectCost.Borrows.Afterimage
		expect(#parts).toBe(borrows.Part)
		expect(#parts).toBe(borrows.SpecialMesh)
		expect(borrows.Model).toBe(1)
		expect(borrows.Highlight).toBe(1)
		local r15: { [string]: boolean } = {}
		for _, name in ipairs({
			"Head",
			"UpperTorso",
			"LowerTorso",
			"LeftUpperArm",
			"LeftLowerArm",
			"LeftHand",
			"RightUpperArm",
			"RightLowerArm",
			"RightHand",
			"LeftUpperLeg",
			"LeftLowerLeg",
			"LeftFoot",
			"RightUpperLeg",
			"RightLowerLeg",
			"RightFoot",
		}) do
			r15[name] = true
		end
		local seen: { [string]: boolean } = {}
		for _, name in ipairs(parts) do
			if not r15[name] then
				error(name .. " is not a limb of an R15 body")
			end
			seen[name] = true
		end
		-- Every limb: a print without its hands and feet was a ghost floating on stumps (review).
		for name in pairs(r15) do
			if not seen[name] then
				error("a print leaves out " .. name)
			end
		end
		-- Its own ceilings: a highlight each within the engine's 31 beside Feel's outlines and impact
		-- frames, and its meshes within half the pool, the rest being the volumes'.
		expect(config.MaxAlive).toBeGreaterThanOrEqual(QualityConfig.Tiers.High.Afterimages)
		expect(config.MaxAlive + FeelConfig.Flash.MaxConcurrent + 2).toBeLessThanOrEqual(31)
		expect(config.MaxAlive).toBeLessThanOrEqual(PoolPolicy.Limits.Highlight.Live)
		expect(config.MaxAlive).toBeLessThanOrEqual(PoolPolicy.Limits.Model.Live)
		expect(config.MaxAlive * #parts).toBeLessThanOrEqual(PoolPolicy.Limits.SpecialMesh.Live / 2)
		expect(config.WaitSeconds > 0 and config.WaitSeconds <= 1).toBe(true)
		expect(config.ShrinkShare > 0 and config.ShrinkShare <= 1).toBe(true)
		-- Ink outlined in ink; the dasher's own paler than anyone else's.
		expect((CosmeticConfig.Tones :: any)[config.Outline]).never.toBe(nil)
		local own = (CosmeticConfig.Tones :: any)[config.OwnTone]
		expect(own).never.toBe(nil)
		for _, placed in ipairs(layersOf("Afterimage")) do
			expect(luminance(own) > luminance((CosmeticConfig.Tones :: any)[placed.Layer.Tone])).toBe(true)
		end
		expect(config.OwnHiddenWithinDegrees > 0 and config.OwnHiddenWithinDegrees < 90).toBe(true)
	end)

	it("shrinks away at the end of its life, slow then fast, and never before", function()
		local share = VfxConfig.Afterimage.ShrinkShare
		expect(VolumeMath.sketchShrink(0, share)).toBe(1)
		expect(VolumeMath.sketchShrink(1 - share, share)).toBe(1)
		expect(VolumeMath.sketchShrink(1, share)).toBe(0)
		expect(VolumeMath.sketchShrink(1 - share / 2, share)).toBeGreaterThan(0.5)
		local previous = 1
		for step = 0, 40 do
			local value = VolumeMath.sketchShrink(step / 40, share)
			expect(value <= previous).toBe(true)
			previous = value
		end
	end)

	it("waits for the body, is decided before the budget, and is drawn whole or not at all", function()
		local build = functionIn(VOLUMES, "function VfxVolumes.buildAfterimage(")
		for _, line in ipairs({
			"local limbs = limbsOf(body) if #limbs == 0 then return end",
			"local own = body == Players.LocalPlayer.Character",
			'local toneName: string = if own then config.OwnTone else entry.Layer.Tone or ""',
			'local modelInstance = kit.borrow(entry, "Model") local highlightInstance = kit.borrow(entry, "Highlight") if modelInstance == nil or highlightInstance == nil then return end',
			'local instance = kit.borrow(entry, "SpecialMesh") if instance == nil then return end local part = kit.host(entry, limb.CFrame, limb.Size) if part == nil then return end',
			"special.MeshId = limb.MeshId special.Parent = part part.Color = Palette.rgb(tone) part.Parent = model",
			"table.insert(copies, { Part = part, Mesh = special, Scale = limb.Size / limb.MeshSize })",
			"highlight.FillColor = Palette.rgb(tone) highlight.FillTransparency = 0 highlight.OutlineColor = Palette.rgb(outline) highlight.OutlineTransparency = 0 highlight.DepthMode = Enum.HighlightDepthMode.Occluded highlight.Adornee = model highlight.Parent = model model.Parent = Workspace",
			"entry.Afterimage = { Limbs = copies } entry.Primary = copies[1].Part",
		}) do
			if not has(build, line) then
				error("buildAfterimage no longer does: " .. line)
			end
		end
		local limbs = functionIn(VOLUMES, "local function limbsOf(")
		expect(
			has(
				limbs,
				'for _, name in ipairs(VfxConfig.Afterimage.BodyParts) do local limb = body:FindFirstChild(name) if limb ~= nil and limb:IsA("MeshPart") and limb.MeshId ~= "" and limb.Transparency < 0.99 then local native = limb.MeshSize if native.X > 1e-4 and native.Y > 1e-4 and native.Z > 1e-4 then table.insert(out, limb)'
			)
		).toBe(true)
		local way = functionIn(VOLUMES, "local function inOwnWay(")
		for _, line in ipairs({
			'if head ~= nil and head:IsA("BasePart") and head.LocalTransparencyModifier > 0.5 then return true end',
			"local dash = direction * Vector3.new(1, 0, 1)",
			"local look = if camera ~= nil then camera.CFrame.LookVector * Vector3.new(1, 0, 1) else Vector3.zero",
			"return dash.Unit:Dot(look.Unit) >= math.cos(math.rad(VfxConfig.Afterimage.OwnHiddenWithinDegrees))",
		}) do
			if not has(way, line) then
				error("inOwnWay no longer does: " .. line)
			end
		end
		expect(
			has(
				functionIn(VOLUMES, "function VfxVolumes.canSketch("),
				"if body == nil or #limbsOf(body) == 0 then return false end return body ~= Players.LocalPlayer.Character or not inOwnWay(body, context.Direction)"
			)
		).toBe(true)
		expect(
			has(
				functionIn(VOLUMES, "function VfxVolumes.reached("),
				"return (root.Position - context.Origin):Dot(flat.Unit) >= (layer.Along or 0) * reach"
			)
		).toBe(true)
		local step = functionIn(VOLUMES, "function VfxVolumes.stepAfterimage(")
		expect(
			has(
				step,
				"local size = kit.lerp(layer.Size, layer.EndSize, alpha, 1) * VolumeMath.sketchShrink(elapsed, VfxConfig.Afterimage.ShrinkShare)"
			)
		).toBe(true)
		expect(
			has(
				step,
				"for _, limb in ipairs(sketch.Limbs) do if limb.Part.Parent ~= nil then limb.Mesh.Scale = limb.Scale * size"
			)
		).toBe(true)
		-- Where the body was: nothing moves or fades a print after it is laid.
		expect(has(step, "CFrame")).toBe(false)
		expect(has(step, "Transparency")).toBe(false)
		local activate = functionIn(TIMELINE, "local function activate(")
		local gate = activate:find(
			'if layer.Kind == "Afterimage" then if (layer.Print or 1) > tier.Afterimages then return end local standing = 0 for _, entry in ipairs(live) do if entry.Layer.Kind == "Afterimage" then standing += 1 end end if standing >= VfxConfig.Afterimage.MaxAlive or not VfxVolumes.canSketch(context) then return end end',
			1,
			true
		)
		local budget = activate:find("if predecessor == nil and #live >= tier.Layers then", 1, true)
		expect(gate).never.toBe(nil)
		expect(budget).never.toBe(nil)
		expect((gate :: number) < (budget :: number)).toBe(true)
		expect(
			has(activate, 'elseif layer.Kind == "Afterimage" then VfxVolumes.buildAfterimage(entry, context.Follow)')
		).toBe(true)
		expect(
			has(
				functionIn(TIMELINE, "local function onHeartbeat("),
				'if now >= item.At and item.Layer.Kind == "Afterimage" and not VfxVolumes.reached(item.Layer, item.Context) then if now >= item.At + VfxConfig.Afterimage.WaitSeconds then table.remove(pending, index) else index += 1 end'
			)
		).toBe(true)
		expect(
			has(
				functionIn(TIMELINE, "local function stepLive("),
				'elseif kind == "Afterimage" then VfxVolumes.stepAfterimage(entry, alpha, elapsed)'
			)
		).toBe(true)
		local dash = functionIn(LIBRARY, "VfxLibrary.Dash = function(")
		expect(has(dash, "Follow = root,")).toBe(true)
		expect(has(dash, "Reach = CombatConfig.Dash.Distance,")).toBe(true)
	end)
end)

describe("the kit", function()
	it("is drawn in the page's charcoal, and its hit told to the two people in it in vellum", function()
		local library = strip(fs.readFile(LIBRARY)):gsub("%s+", " ")
		expect(has(library, "local KIT_INK = Palette.rgb(WorldConfig.Colors.Ink)")).toBe(true)
		expect(has(library, "local KIT_FEEDBACK = Palette.rgb(WorldConfig.Colors.Page)")).toBe(true)
		expect(has(functionIn(LIBRARY, "VfxLibrary.Melee = function("), "Color = KIT_INK,")).toBe(true)
		expect(has(functionIn(LIBRARY, "VfxLibrary.Dash = function("), "Color = KIT_INK,")).toBe(true)
		local hit = functionIn(LIBRARY, "VfxLibrary.Hit = function(")
		for _, line in ipairs({
			'local color = if pigment ~= "" then glyphColor(pigment, packet, api) else KIT_INK',
			'local feedback = if pigment ~= "" then color else KIT_FEEDBACK',
			'Unlit = pigment == "",',
			"feel.flash(targetModel, if takenByMe then HIT_TAKEN_COLOR else feedback)",
			"feel.damageNumber(packet.Origin, amount, if takenByMe then HIT_TAKEN_COLOR else feedback, amplified)",
		}) do
			if not has(hit, line) then
				error("the Hit renderer no longer does: " .. line)
			end
		end
		-- A number in the stroke's own colour is no number: the feedback is never the outline's ink.
		local page = WorldConfig.Colors.Page
		local outline = ThemeConfig.Colors.Outline
		expect(page[1] ~= outline[1] or page[2] ~= outline[2] or page[3] ~= outline[3]).toBe(true)
		expect(luminance(page) - luminance(outline)).toBeGreaterThan(120)
	end)

	it("lays ink rather than shining, and strokes each swing with a volume inside its reach", function()
		for _, id in ipairs({ "Melee", "Dash" }) do
			for _, phase in ipairs(VfxTimelineConfig.Timelines[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Light" then
						error(id .. " lights the page: charcoal ink does not shine")
					end
				end
			end
		end
		-- The Hit timeline is shared with glyphs: a fist's play is Unlit and its lights are skipped.
		expect(
			has(
				functionIn(TIMELINE, "local function activate("),
				'if layer.Kind == "Light" and (not tier.Lights or context.Unlit == true) then'
			)
		).toBe(true)
		local strokes = 0
		for _, id in ipairs({ "Melee", "Hit" }) do
			for _, phase in ipairs(VfxTimelineConfig.Timelines[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Mesh" and layer.Mesh == "Crescent" then
						strokes += 1
						expect(layer.Transparency or 0).toBeGreaterThanOrEqual(0.05)
						if id == "Melee" then
							-- At the finisher's weight (VfxLibrary.Melee scales it by 1.4), still inside the
							-- fist's box: a stroke past it lies about the reach.
							local offset = layer.Offset or { 0, 0, 0 }
							local reach = (offset[3] + (layer.EndSize or layer.Size) / 2) * 1.4
							expect(reach).toBeLessThanOrEqual(CombatConfig.Melee.Range)
						end
					end
				end
			end
		end
		expect(strokes).toBe(2)
		expect(has(functionIn(LIBRARY, "VfxLibrary.Melee = function("), "Scale = if finisher then 1.4 else 1,")).toBe(
			true
		)
	end)
end)
