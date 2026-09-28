--!strict
-- The numbers a hit prints over the world (D-147): an amplified hit grows by the config's own scale, and every
-- number wears the Number stroke, the ink that keeps it readable over the brightest impact. Engine code,
-- held by reading it.
local FeelConfig = require("../src/shared/Config/FeelConfig")
local Harness = require("./harness")
local fs = require("@lune/fs")

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

describe("the damage numbers", function()
	it("grow an amplified hit by the config's scale, with no number of their own", function()
		local spawn = body(FEEL, "function Feel.damageNumber(")
		expect(has(spawn, "if critical then sizeScale *= config.AmplifiedScale end")).toBe(true)
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
end)
