--!strict
-- The kit in charcoal and the dodge's sketch (D-114, D-116): the punch, its hit and the dash drawn in the
-- page's ink rather than a pigment or white; the dash leaving copies of the body's limbs, faint, never
-- moved, fewer on the lower tiers and none on the lowest; the dasher's own fainter and kept out of their
-- way. The arithmetic of a sketch is the engine's (a SpecialMesh on a pooled part), so the runtime is
-- held by its lines.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local EffectCost = require("../scripts/effect-cost")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
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

describe("a dash's sketch", function()
	it("is ink, faint from the start and gone at the end, and never follows the body it copies", function()
		local sketches = layersOf("Afterimage")
		expect(#sketches).toBeGreaterThanOrEqual(2)
		for _, placed in ipairs(sketches) do
			local layer = placed.Layer
			local name = placed.Id .. " print " .. tostring(layer.Print)
			-- A dodge names no school: ink, never a pigment.
			expect((CosmeticConfig.Tones :: any)[layer.Tone]).never.toBe(nil)
			expect((PigmentConfig.Colors :: any)[layer.Tone]).toBe(nil)
			-- Rule 3: it appears faint and goes out entirely.
			if (layer.Transparency or 0) < 0.45 then
				error(name .. " appears as a solid body")
			end
			expect(layer.EndTransparency).toBe(1)
			-- Rule 4, and the bleed of ink rather than a growing body.
			expect(type(layer.Ease)).toBe("string")
			expect(layer.Size).toBe(1)
			expect(layer.EndSize > 1 and layer.EndSize <= 1.1).toBe(true)
			-- Follow would drag the sketch along with the body: a sketch is where the body WAS.
			expect(layer.Follow).never.toBe(true)
			expect(placed.Phase.Window).never.toBe(true)
			expect(placed.Id).toBe("Dash")
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

	it("copies the limbs the cost model pays for, and nothing a player wears", function()
		local parts = VfxConfig.Afterimage.BodyParts
		expect(#parts).toBe(EffectCost.Borrows.Afterimage.Part)
		expect(#parts).toBe(EffectCost.Borrows.Afterimage.SpecialMesh)
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
		for _, name in ipairs(parts) do
			if not r15[name] then
				error(name .. " is not a limb of an R15 body")
			end
		end
		expect(VfxConfig.Afterimage.OwnExtraTransparency).toBeGreaterThan(0)
		expect(VfxConfig.Afterimage.OwnHiddenWithinDegrees).toBeGreaterThan(0)
		expect(VfxConfig.Afterimage.OwnHiddenWithinDegrees).toBeLessThan(90)
	end)

	it("is drawn once from the limbs, the mesh borrowed before its part, and only faded after", function()
		local build = functionIn(VOLUMES, "function VfxVolumes.buildAfterimage(")
		for _, line in ipairs({
			"local body = if root ~= nil then root.Parent else nil",
			"for _, name in ipairs(config.BodyParts) do local limb = body:FindFirstChild(name)",
			'if limb ~= nil and limb:IsA("MeshPart") and limb.MeshId ~= "" and limb.Transparency < 0.99 then',
			"if native.X > 1e-4 and native.Y > 1e-4 and native.Z > 1e-4 then",
			"special.MeshId = limb.MeshId",
			"part.Color = Palette.rgb(tone)",
			"table.insert(limbs, { Part = part, Mesh = special, Scale = limb.Size / native })",
			'local tone = CosmeticConfig.Tones[entry.Layer.Tone or ""] or CosmeticConfig.Tones.Graphite',
			-- The dasher's own: fainter, and not at all along the camera's aim.
			"if body == Players.LocalPlayer.Character then",
			"if dash.Unit:Dot(look.Unit) >= math.cos(math.rad(config.OwnHiddenWithinDegrees)) then return end",
			"extra = config.OwnExtraTransparency",
		}) do
			if not has(build, line) then
				error("buildAfterimage no longer does: " .. line)
			end
		end
		local mesh =
			build:find('local instance = kit.borrow(entry, "SpecialMesh") if instance == nil then break end', 1, true)
		local part = build:find("local part = kit.host(entry, limb.CFrame, limb.Size)", 1, true)
		expect(mesh).never.toBe(nil)
		expect(part).never.toBe(nil)
		expect((mesh :: number) < (part :: number)).toBe(true)
		local step = functionIn(VOLUMES, "function VfxVolumes.stepAfterimage(")
		expect(has(step, "local bleed = kit.lerp(layer.Size, layer.EndSize, alpha, 1)")).toBe(true)
		expect(has(step, "kit.fadeOf(layer, elapsed, alpha, 0), 0) + sketch.Extra")).toBe(true)
		expect(has(step, "limb.Mesh.Scale = limb.Scale * bleed")).toBe(true)
		expect(has(step, "limb.Part.Transparency = transparency")).toBe(true)
		-- Where the body was: nothing moves a sketch after it is drawn.
		expect(has(step, "CFrame")).toBe(false)
		local activate = functionIn(TIMELINE, "local function activate(")
		expect(has(activate, 'if layer.Kind == "Afterimage" and (layer.Print or 1) > tier.Afterimages then return end')).toBe(
			true
		)
		expect(
			has(activate, 'elseif layer.Kind == "Afterimage" then VfxVolumes.buildAfterimage(entry, context.Follow)')
		).toBe(true)
		expect(
			has(
				functionIn(TIMELINE, "local function stepLive("),
				'elseif kind == "Afterimage" then VfxVolumes.stepAfterimage(entry, alpha, elapsed)'
			)
		).toBe(true)
	end)
end)

describe("the kit", function()
	it("is drawn in the page's charcoal: the punch, its hit and the dodge", function()
		local library = strip(fs.readFile(LIBRARY)):gsub("%s+", " ")
		expect(has(library, "local KIT_INK = Palette.rgb(WorldConfig.Colors.Ink)")).toBe(true)
		expect(has(functionIn(LIBRARY, "VfxLibrary.Melee = function("), "Color = KIT_INK,")).toBe(true)
		expect(has(functionIn(LIBRARY, "VfxLibrary.Dash = function("), "Color = KIT_INK,")).toBe(true)
		expect(
			has(
				functionIn(LIBRARY, "VfxLibrary.Hit = function("),
				'local color = if pigment ~= "" then glyphColor(pigment, packet, api) else KIT_INK'
			)
		).toBe(true)
	end)

	it("lays ink rather than shining, and strokes each swing with a volume", function()
		for _, id in ipairs({ "Melee", "Dash" }) do
			for _, phase in ipairs(VfxTimelineConfig.Timelines[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Light" then
						error(id .. " lights the page: charcoal ink does not shine")
					end
				end
			end
		end
		local strokes = 0
		for _, id in ipairs({ "Melee", "Hit" }) do
			for _, phase in ipairs(VfxTimelineConfig.Timelines[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Mesh" and layer.Mesh == "Crescent" then
						strokes += 1
					end
				end
			end
		end
		expect(strokes).toBe(2)
	end)
end)
