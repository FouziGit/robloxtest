--!strict
-- Watching after being eliminated (D-147): who is watched is said on a plate where the dock was -- not a toast
-- that says it once and leaves -- and its discs step round the living teammates, keeping the one chosen
-- while they live. A fight surface: ink and the sheet, and the fight's focus ring for a gamepad. Engine code,
-- held by reading it.
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SPECTATE = "src/client/Controllers/SpectateController.luau"
local HUD_CONTROLLER = "src/client/Controllers/HudController.luau"
local PLATE = "src/ui/components/SpectatePlate.luau"
local CIRCLE = "src/ui/components/CircleButton.luau"

local function code(path: string): string
	local withoutBlocks = string.gsub(fs.readFile(path), "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function folded(path: string): string
	return (string.gsub(code(path), "%s+", " "))
end

-- The body of the local function `name` in `source`, up to its closing `end` at the same indent, folded.
local function body(source: string, name: string): string
	local indent, rest = string.match(source, "\n(\t*)local function " .. name .. "%((.*)")
	assert(indent ~= nil and rest ~= nil, ("no local function %s: this gate would check nothing"):format(name))
	local finish = string.find(rest :: string, "\n" .. (indent :: string) .. "end\n", 1, true)
	assert(finish ~= nil, ("%s has no end"):format(name))
	return (string.gsub(string.sub(rest :: string, 1, finish :: number), "%s+", " "))
end

-- The folded body of the function whose header is `header`, up to its first top-level `end`.
local function method(path: string, header: string): string
	local source = code(path)
	local start = string.find(source, header, 1, true)
	assert(start ~= nil, ("%s has no %s: this gate would check nothing"):format(path, header))
	local finish = string.find(source, "\nend\n", start :: number, true)
	return (string.gsub(string.sub(source, start :: number, finish or #source), "%s+", " "))
end

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
end

local function number(source: string, name: string): number
	local value = tonumber(string.match(source, "local " .. name .. " = ([%d%.]+)\n"))
	assert(value ~= nil, ("no number %s: this gate would check nothing"):format(name))
	return value :: number
end

describe("watching after being eliminated", function()
	it("says who is watched on a plate where the dock was, and never as a toast", function()
		local spectate = code(SPECTATE)
		expect(has(spectate, "showLocalToast")).toBe(false)
		expect(has(body(spectate, "watch"), "hudController.showSpectating(name, SpectateController.cycle)")).toBe(true)
		expect(has(body(spectate, "stop"), "hudController.showSpectating(nil)")).toBe(true)
		expect(
			has(
				folded(HUD_CONTROLLER),
				"spectatePlate = SpectatePlate.new({ Parent = bottomStack, Localize = localize, LayoutOrder = DOCK_ORDER })"
			)
		).toBe(true)
		local swap = method(HUD_CONTROLLER, "function HudController.showSpectating(")
		-- Out, then in: the dock and the plate never stand in the stack together.
		expect(
			has(
				swap,
				'Motion.to(dockScale, { Scale = 0 }, "UiExit", function() if token == spectateToken then combatDock.Instance.Visible = false spectatePlate:Show(name, onCycle) end end)'
			)
		).toBe(true)
		expect(
			has(
				swap,
				'spectatePlate:Hide(function() if token == spectateToken then combatDock.Instance.Visible = true Motion.to(dockScale, { Scale = 1 }, "UiPop") end end)'
			)
		).toBe(true)
		expect(Strings.has("match.watching")).toBe(true)
	end)

	it("keeps the teammate chosen while they live, and steps round the living ones", function()
		local spectate = code(SPECTATE)
		local pick = body(spectate, "pick")
		local kept = string.find(
			pick,
			"if candidate.UserId == watching then return candidate.UserId, candidate.Name end",
			1,
			true
		)
		local first = string.find(pick, "local first = list[1]", 1, true)
		assert(kept ~= nil and first ~= nil, "the pick no longer keeps who is watched")
		expect(kept :: number).toBeLessThan(first :: number)
		expect(
			has(
				body(spectate, "candidates"),
				"if member.Alive and member.UserId ~= player.UserId and humanoidOf(member.UserId) ~= nil then"
			)
		).toBe(true)
		local cycle = method(SPECTATE, "function SpectateController.cycle(")
		expect(has(cycle, "if index == 0 or #list < 2 then return end")).toBe(true)
		expect(has(cycle, "local next = list[(index - 1 + step) % #list + 1]")).toBe(true)
		expect(has(cycle, "watch(next.UserId, next.Name)")).toBe(true)
	end)

	it("draws the plate in ink and the sheet, its discs a gamepad reaches on the fight's ring", function()
		local plate = code(PLATE)
		expect(number(plate, "WIDTH")).toBe(360)
		expect(number(plate, "HEIGHT")).toBe(56)
		expect(number(plate, "DISC")).toBe(44)
		expect(has(plate, "Fill = Theme.Colors.Plate,")).toBe(true)
		expect(has(plate, "label.TextColor3 = Theme.Colors.TextInverse")).toBe(true)
		expect(has(plate, "label.TextTruncate = Enum.TextTruncate.AtEnd")).toBe(true)
		expect(number(plate, "TEXT")).toBe(18)
		local fold = folded(PLATE)
		expect(select(2, string.gsub(fold, 'Focus = "Fight",', ""))).toBe(2)
		expect(has(fold, "SignRotation = BACK_ROTATION,")).toBe(true)
		expect(number(plate, "BACK_ROTATION")).toBe(180)
		expect(has(body(plate, "show"), 'Motion.to(scale, { Scale = 1 }, "UiPop")')).toBe(true)
		expect(has(body(plate, "hide"), 'Motion.to(scale, { Scale = 0 }, "UiExit", function()')).toBe(true)
		local circle = folded(CIRCLE)
		expect(has(circle, "button.SelectionImageObject = trove:Add(Theme.focusRing(props.Focus, Theme.Pill))")).toBe(
			true
		)
		-- The fight's ring is the sheet inside the ink: no value colour.
		expect(has(folded("src/ui/Theme.luau"), 'if kind == "Fight" then "PanelRaised" else "Primary"')).toBe(true)
	end)
end)
