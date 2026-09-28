--!strict
-- The hub's words and prompts, as the colourful interface draws them (D-147). They stand in the world, so they
-- stay unsaturated (docs/ART_BIBLE.md rule 1): ink plates edged in the sheet, vellum and chalk words, and the
-- prompts drawn as the same ink with the key on a cap. Colour arrives with the screen a prompt opens. The pins of
-- tests/Hub.spec.luau hold what the signs say and when a prompt is live; this holds how they look.
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SIGNS = "src/client/Controllers/HubSignsController.luau"
local COLORS = ThemeConfig.Colors
-- What the world's words may be drawn in: ink, the sheet, chalk, and the vellum and muted inks on them.
local WORLD_ROLES = { Plate = true, PanelRaised = true, Chalk = true, TextInverse = true, TextMuted = true }

local function code(path: string): string
	local withoutBlocks = string.gsub(fs.readFile(path), "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- The body of the local function `name` in `source`, up to its closing `end` at the same indent, folded.
local function body(source: string, name: string): string
	local indent, rest = string.match(source, "\n(\t*)local function " .. name .. "%((.*)")
	assert(indent ~= nil and rest ~= nil, ("no local function %s: this gate would check nothing"):format(name))
	local finish = string.find(rest :: string, "\n" .. (indent :: string) .. "end\n", 1, true)
	assert(finish ~= nil, ("%s has no end"):format(name))
	return (string.gsub(string.sub(rest :: string, 1, finish :: number), "%s+", " "))
end

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
end

local function number(source: string, name: string): number
	local value = tonumber(string.match(source, "local " .. name .. " = ([%d%.]+)\n"))
	assert(value ~= nil, ("no number %s: this gate would check nothing"):format(name))
	return value :: number
end

describe("the hub's words", function()
	it("are ink, the sheet and chalk: nothing saturated stands in the world (rule 1)", function()
		local signs = code(SIGNS)
		local count = 0
		for role in string.gmatch(signs, "Theme%.Colors%.(%w+)") do
			count += 1
			if not WORLD_ROLES[role] then
				error(("HubSignsController paints the world with Theme.Colors.%s"):format(role))
			end
		end
		expect(count).toBeGreaterThan(5)
		for role in string.gmatch(signs, 'Theme%.stroke%([^,]+, "(%w+)"') do
			expect(WORLD_ROLES[role]).toBe(true)
		end
	end)

	it("set a name in the title face on an ink plate edged in the sheet, its hint in chalk", function()
		local signs = code(SIGNS)
		local plate = body(signs, "namePlate")
		expect(
			has(
				plate,
				"plate.BackgroundColor3 = Theme.Colors.Plate plate.BackgroundTransparency = 0 plate.BorderSizePixel = 0"
			)
		).toBe(true)
		expect(has(plate, "Theme.corner(plate, Theme.Sizes.CornerCard)")).toBe(true)
		expect(has(plate, 'Theme.stroke(plate, "PanelRaised", Theme.Sizes.StrokeThin)')).toBe(true)
		expect(has(plate, 'local label = textLabel("Name", name, NAME_MAX_TEXT, Theme.Colors.TextInverse, plate)')).toBe(
			true
		)
		expect(has(plate, "label.TextScaled = true")).toBe(true)
		expect(has(plate, "cap.MaxTextSize = NAME_MAX_TEXT")).toBe(true)
		expect(number(signs, "NAME_MAX_TEXT")).toBe(30)
		expect(has(plate, 'local line = textLabel("Hint", hint, HINT_TEXT, Theme.Colors.Chalk, plate)')).toBe(true)
		expect(has(plate, "line.FontFace = Theme.Fonts.Body")).toBe(true)
		expect(number(signs, "HINT_TEXT")).toBe(18)
		expect(ThemeConfig.contrast(COLORS.TextInverse, COLORS.Plate)).toBeGreaterThanOrEqual(4.5)
		expect(ThemeConfig.contrast(COLORS.Chalk, COLORS.Plate)).toBeGreaterThanOrEqual(4.5)
		-- Against the cream world the plate is the darkest thing there is.
		expect(ThemeConfig.contrast(COLORS.Plate, COLORS.Panel)).toBeGreaterThanOrEqual(4.5)
		-- A board with no row yet says so in the lore's italic.
		expect(has(body(signs, "wordBoard"), "empty.FontFace = Theme.Fonts.Lore")).toBe(true)
	end)

	it("draw their prompts themselves: an ink pill with the key on a cap, pressed by hand on touch", function()
		local signs = code(SIGNS)
		expect(has(body(signs, "wordPedestal"), "prompt.Style = Enum.ProximityPromptStyle.Custom")).toBe(true)
		expect(has(signs, "ProximityPromptService.PromptShown:Connect(onPromptShown)")).toBe(true)
		local shown = body(signs, "onPromptShown")
		-- Only this controller's prompts, once each.
		expect(has(shown, "if table.find(prompts, prompt) == nil or shownPrompts[prompt] then return end")).toBe(true)
		expect(has(shown, "billboard.StudsOffsetWorldSpace = Vector3.new(0, PROMPT_STUDS_ABOVE, 0)")).toBe(true)
		expect(has(shown, "billboard.AlwaysOnTop = true")).toBe(true)
		expect(number(signs, "PROMPT_STUDS_ABOVE")).toBe(3)
		expect(has(signs, "local PROMPT_SIZE = UDim2.fromOffset(220, 48)")).toBe(true)
		expect(has(shown, 'Kind = "Plate", Fill = Theme.Colors.Plate, Corner = Theme.Pill,')).toBe(true)
		-- The key the prompt listens for, on a cap, for the device in use; no cap on touch, where the pill is pressed.
		expect(has(shown, "if inputType ~= Enum.ProximityPromptInputType.Touch then")).toBe(true)
		expect(has(shown, "Key = if gamepad then InputConfig.HubPrompt.Gamepad else InputConfig.HubPrompt.Keyboard,")).toBe(
			true
		)
		expect(Strings.Table["key." .. InputConfig.HubPrompt.Gamepad].en).toBe("RB")
		expect(has(shown, "prompt:InputHoldBegin()")).toBe(true)
		expect(has(shown, "prompt:InputHoldEnd()")).toBe(true)
		expect(has(shown, "prompt.ActionText, PROMPT_ACTION_TEXT, Theme.Colors.TextInverse")).toBe(true)
		expect(has(shown, "prompt.ObjectText, PROMPT_OBJECT_TEXT, Theme.Colors.Chalk")).toBe(true)
		-- In with the pop, out the way it came, and gone with the prompt.
		expect(has(shown, 'Motion.set(scale, { Scale = PROMPT_FROM_SCALE }) Motion.to(scale, { Scale = 1 }, "UiPop")')).toBe(
			true
		)
		expect(has(shown, 'Motion.to(scale, { Scale = 0 }, "UiExit", function() billboard:Destroy() end)')).toBe(true)
		expect(has(shown, "prompt.Destroying:Once(function() shownPrompts[prompt] = nil billboard:Destroy() end)")).toBe(
			true
		)
	end)
end)
