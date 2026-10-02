--!strict
-- The numbers a hit prints over the world (D-147): an amplified hit grows by the config's own scale, every
-- number dealt wears the Number stroke, the ink that keeps it readable over the brightest impact, and damage the
-- player took is a red minus in the sheet's stroke, drifting down. Engine code, held by reading it and by running
-- the pooled marker on tests/engine.luau.
local Engine = require("./engine")
local FeelConfig = require("../src/shared/Config/FeelConfig")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local FEEL = "src/client/Controllers/Feel.luau"
local NUMBER = "src/ui/components/DamageNumber.luau"

local function code(path: string): string
	local withoutBlocks = string.gsub(fs.readFile(path), "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- The folded body of the function whose header is `header`, up to its first top-level `end`.
local function body(path: string, header: string): string
	local source = code(path)
	local start = string.find(source, header, 1, true)
	assert(start ~= nil, ("%s has no %s: this gate would check nothing"):format(path, header))
	local finish = string.find(source, "\nend\n", start :: number, true)
	return (string.gsub(string.sub(source, start :: number, finish or #source), "%s+", " "))
end

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
end

-- Every Luau file under `directory`, but the configs, whose tokens are what is looked for.
local function readers(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Config" then
				readers(path, out)
			end
		elseif string.match(entry, "%.luau$") then
			table.insert(out, code(path))
		end
	end
end

describe("the damage numbers", function()
	it("have no token nothing reads", function()
		-- A token with no reader is a promise the game does not keep, and a test pinning its value passes
		-- whatever the numbers do (TakenRiseStuds said damage taken drifted down; nothing drew it so).
		local sources = {}
		readers("src", sources)
		local all = table.concat(sources, "\n")
		local count = 0
		for name in pairs(FeelConfig.DamageNumbers) do
			count += 1
			if string.find(all, "%." .. name .. "%f[^%w_]") == nil then
				error(("FeelConfig.DamageNumbers.%s is read by nothing"):format(name))
			end
		end
		expect(count).toBeGreaterThan(5)
	end)

	it("grow an amplified hit by the config's scale, with no number of their own", function()
		local spawn = body(FEEL, "function Feel.damageNumber(")
		expect(has(spawn, "if style.Amplified then sizeScale *= config.AmplifiedScale end")).toBe(true)
		expect(string.find(spawn, "sizeScale %*= %d")).toBeNil()
		expect(FeelConfig.DamageNumbers.AmplifiedScale).toBe(1.35)
	end)

	it("wear the Number stroke: ink, three units, on the glyphs, faded with the number", function()
		local number = code(NUMBER)
		expect(has(number, 'local stroke = Theme.stroke(label, "Outline", NUMBER_STROKE, "Contextual")')).toBe(true)
		expect(has(number, "local NUMBER_STROKE = 3\n")).toBe(true)
		-- A stroke on text fades by its transparency, never by its thickness (docs/ART_BIBLE.md, D-147).
		local place = body(NUMBER, "function DamageNumber.place(")
		expect(has(place, "marker.Stroke.Transparency = math.clamp(transparency + STROKE_TRANSPARENCY, 0, 1)")).toBe(
			true
		)
		expect(has(number, "Thickness")).toBe(false)
	end)

	it("write damage taken as a red minus in the sheet's stroke, at the base size, drifting down", function()
		local spawn = body(FEEL, "function Feel.damageNumber(")
		expect(has(spawn, 'local taken = style.Kind == "Taken"')).toBe(true)
		-- Read, not weighed: no severity growth, whatever the hit.
		expect(has(spawn, "local sizeScale = if taken then 1 else FeelMath.lerp(1, config.MaxSizeScale, severity)")).toBe(
			true
		)
		expect(
			has(
				spawn,
				"DamageNumber.dress( marker, Theme.Glyphs.Minus .. value, Theme.Colors.DangerFill, Theme.Colors.PanelRaised, sizeScale, tag )"
			)
		).toBe(true)
		expect(has(spawn, "DamageNumber.dress(marker, value, color, Theme.Colors.Outline, sizeScale, tag)")).toBe(true)
		-- Its fall is its own, kept with it, and the one loop moves every number by what it keeps.
		expect(has(spawn, "Rise = if taken then config.TakenRiseStuds else config.RiseStuds,")).toBe(true)
		local step = body(FEEL, "local function stepNumbers(")
		expect(has(step, "local rise = entry.Rise * (1 - (1 - alpha) * (1 - alpha))")).toBe(true)
		expect(has(step, "config.RiseStuds")).toBe(false)
		expect(FeelConfig.DamageNumbers.TakenRiseStuds).toBe(-1.6)
		expect(FeelConfig.DamageNumbers.TakenRiseStuds).toBeLessThan(0)
		expect(-FeelConfig.DamageNumbers.TakenRiseStuds).toBeLessThan(FeelConfig.DamageNumbers.RiseStuds)
		-- Red on the sheet at thirty units and up is large text: 3.25.
		local colors = ThemeConfig.Colors
		expect(ThemeConfig.contrast(colors.DangerFill, colors.PanelRaised)).toBeGreaterThanOrEqual(3)
		expect(FeelConfig.DamageNumbers.BaseTextSize).toBeGreaterThanOrEqual(24)
	end)

	it("recolour a pooled marker's stroke on every dress, never its thickness", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local DamageNumber = world.require("src/ui/components/DamageNumber")
		local Theme = world.require("src/ui/Theme")
		local marker = DamageNumber.acquire()
		local thickness = marker.Stroke.Thickness
		DamageNumber.dress(marker, Theme.Glyphs.Minus .. "12", Theme.Colors.DangerFill, Theme.Colors.PanelRaised, 1)
		expect(marker.Label.Text).toBe("\u{2212}12")
		expect(marker.Label.TextColor3).toBe(Theme.Colors.DangerFill)
		expect(marker.Stroke.Color).toBe(Theme.Colors.PanelRaised)
		expect(marker.Label.TextSize).toBe(FeelConfig.DamageNumbers.BaseTextSize)
		DamageNumber.release(marker)
		local again = DamageNumber.acquire()
		expect(again).toBe(marker)
		DamageNumber.dress(again, "25", Theme.Colors.Danger, Theme.Colors.Outline, 1.5)
		expect(again.Stroke.Color).toBe(Theme.Colors.Outline)
		expect(again.Label.TextColor3).toBe(Theme.Colors.Danger)
		expect(again.Stroke.Thickness).toBe(thickness)
	end)
end)

-- The rest of §4.12 (D-156, D-230), run: the real Feel spawns each number on tests/engine.luau. A glyph's number
-- was its exact pigment on the ink's stroke, and the exact Indigo (2.15) and Umber (2.30) do not read there; an
-- amplified hit grew and said nothing of what had paid off, though the server names the status and its bonus.
describe("a glyph's number and an amplified hit's status, run", function()
	local function spawn(style: any): (any, any)
		-- The camera's shake is not what is looked at here, and its package builds on the engine's Random.
		local stubs = Engine.interfaceStubs()
		stubs["Packages/Shake"] = {}
		local world = Engine.world({ Stubs = stubs, Services = { HapticService = {} } })
		local Feel = world.require("src/client/Controllers/Feel")
		local Strings = require("../src/shared/Strings")
		Feel.Init({
			ClientData = {
				get = function(): any
					return nil
				end,
			},
			MovementController = {},
			Localize = {
				t = function(key: string, params: any?): string
					return Strings.t(key, params, "en")
				end,
				resolveParams = function(params: any?): any
					local resolved = {}
					for name, value in pairs(params or {}) do
						resolved[name] = if type(value) == "string" and Strings.has(value)
							then Strings.t(value, nil, "en")
							else value
					end
					return resolved
				end,
			},
		})
		local Theme = world.require("src/ui/Theme")
		Feel.damageNumber(roblox.Vector3.zero, 40, Theme.Colors.Accent, style)
		local folder = world.workspace:FindFirstChild("VellumDamageNumbers")
		assert(folder ~= nil, "Feel drew no number: this gate would check nothing")
		local billboard = folder:FindFirstChild("DamageNumber"):FindFirstChild("Number")
		return billboard, Theme
	end

	it("draws a glyph's number in its pigment's form on ink, each of them readable there", function()
		for _, pigment in ipairs({ "Cinnabar", "Indigo", "Umber", "Verdigris", "Orpiment" }) do
			local billboard, Theme = spawn({ Kind = "Glyph", Pigment = pigment })
			local value = billboard:FindFirstChild("Value")
			local fill, edge = Theme.pigmentOnInk(pigment)
			expect(value.TextColor3).toBe(fill)
			expect(value:FindFirstChildOfClass("UIStroke").Color).toBe(edge)
			local function rgb(color: any): { number }
				return { color.R * 255, color.G * 255, color.B * 255 }
			end
			if ThemeConfig.contrast(rgb(fill), rgb(edge)) < 3 then
				error(
					("a %s number is %.2f against its stroke"):format(
						pigment,
						ThemeConfig.contrast(rgb(fill), rgb(edge))
					)
				)
			end
		end
		-- A fist's, or a hit with no pigment, keeps the colour it is given.
		local billboard, Theme = spawn({ Kind = "Fist" })
		expect(billboard:FindFirstChild("Value").TextColor3).toBe(Theme.Colors.Accent)
	end)

	it("says under an amplified hit which status paid off and by how much, in the player's language", function()
		local billboard = spawn({
			Kind = "Glyph",
			Pigment = "Cinnabar",
			Amplified = true,
			Status = { Key = "status.fanned", Percent = 25 },
		})
		local status = billboard:FindFirstChild("Status")
		expect(status.Visible).toBe(true)
		expect(status.Text).toBe("Fanned: +25% damage")
		-- Under the number, inside the billboard, never over it.
		local value = billboard:FindFirstChild("Value")
		expect(status.Position.Y.Scale).toBe(value.Size.Y.Scale)
		expect(math.abs(value.Size.Y.Scale + status.Size.Y.Scale - 1)).toBeLessThan(1e-6)
		-- No status: no line.
		local plain = spawn({ Kind = "Glyph", Pigment = "Cinnabar", Amplified = false })
		expect(plain:FindFirstChild("Status").Visible).toBe(false)
	end)
end)
