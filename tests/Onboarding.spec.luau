--!strict
-- A new player's first minutes (D-147): the ghost chips of the first recipe, under the keys that press them or
-- over the discs that breathe, coming back until the server has counted one cast; the three first steps, ticked
-- as they happen and folded away once done; and the daily reward, which opens by itself once a session when
-- nothing else has the player. Engine code, held by reading it.
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ONBOARDING = "src/client/Controllers/OnboardingController.luau"
local HUD_CONTROLLER = "src/client/Controllers/HudController.luau"
local COMBO_ROW = "src/ui/components/ComboRow.luau"
local CLUSTER = "src/ui/components/MetaCluster.luau"
local COLORS = ThemeConfig.Colors

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

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
end

local function number(source: string, name: string): number
	local value = tonumber(string.match(source, "local " .. name .. " = ([%d%.]+)\n"))
	assert(value ~= nil, ("no number %s: this gate would check nothing"):format(name))
	return value :: number
end

describe("the first recipe's ghosts", function()
	it("come back once the sequence is empty without a cast the server confirmed, until one is counted", function()
		local onboarding = code(ONBOARDING)
		expect(number(onboarding, "RETURN_SECONDS")).toBe(1.5)
		local changed = body(onboarding, "onSequenceChanged")
		expect(has(changed, "returnToken += 1 if #sequence > 0 then dismiss() return end")).toBe(true)
		expect(has(changed, "task.delay(RETURN_SECONDS, function() if token == returnToken then refresh() end end)")).toBe(
			true
		)
		expect(has(body(onboarding, "onCast"), "returnToken += 1 dismiss()")).toBe(true)
		expect(has(onboarding, "vfxController.LocalCast:Connect(onCast)")).toBe(true)
		-- The profile's count, the server's own, is what ends them.
		expect(has(body(onboarding, "refresh"), "if data.Stats.GlyphsCast > 0 then return end")).toBe(true)
	end)

	it("stand under the player's own keys with a pointer, and make the discs breathe on touch", function()
		local hud = code(HUD_CONTROLLER)
		local show = folded(HUD_CONTROLLER)
		expect(has(show, 'comboRow:ShowGhosts(pigments, if hintSource == "Touch" then nil else hotbarKeys)')).toBe(true)
		expect(has(show, "inputController.setHints(ONBOARDING_HINTS, pigments or {})")).toBe(true)
		expect(
			has(
				body(hud, "refreshHotbarKeys"),
				'hotbarKeys = { Device = if gamepad then "Gamepad" else "Keyboard", Keys = keys }'
			)
		).toBe(true)
		-- Over the ghosts, since the hotbar stands under the row; each cap in a slot as wide as a chip, spaced like
		-- the chips, from the right where the ghosts are.
		local row = folded(COMBO_ROW)
		expect(has(row, "keyStrip.AnchorPoint = Vector2.new(1, 1)")).toBe(true)
		expect(has(row, "keyStrip.Position = UDim2.new(1, 0, 0, -GHOST_KEY_GAP)")).toBe(true)
		expect(has(row, "keyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right")).toBe(true)
		expect(has(row, "keyLayout.Padding = UDim.new(0, Theme.Sizes.Gap)")).toBe(true)
		expect(has(row, "layout.Padding = UDim.new(0, Theme.Sizes.Gap)")).toBe(true)
		local ghosts = body(code(COMBO_ROW), "showGhosts")
		expect(has(ghosts, 'Motion.to(slot, { Size = CHIP_OPEN }, "UiPop")')).toBe(true)
		expect(has(ghosts, "Pigment = pigment,")).toBe(true)
		expect(has(ghosts, "for _, slot in ipairs(ghostKeys) do fold(slot) end")).toBe(true)
	end)
end)

describe("the first steps", function()
	it("are the three a new player takes, each leading where it is done", function()
		local cluster = folded(CLUSTER)
		for _, line in ipairs({
			'{ Kind = "Cast", Key = "hud.checklist.cast" },',
			'{ Kind = "Match", Key = "hud.checklist.match", Screen = "Play" },',
			'{ Kind = "Daily", Key = "hud.checklist.daily", Screen = "Daily" },',
		}) do
			if not has(cluster, line) then
				error("the first steps no longer list " .. line)
			end
		end
		for _, key in ipairs({
			"hud.checklist.title",
			"hud.checklist.cast",
			"hud.checklist.match",
			"hud.checklist.daily",
		}) do
			expect(Strings.has(key)).toBe(true)
		end
		expect(number(code(CLUSTER), "STEPS_WIDTH")).toBe(280)
		-- Ticked from the profile alone: nothing new is saved for them.
		local profile = folded(HUD_CONTROLLER)
		expect(
			has(
				profile,
				"metaCluster:SetChecklist({ Cast = data.Stats.GlyphsCast > 0, Match = data.Stats.MatchesPlayed > 0, Daily = data.Daily.LastClaimDay > 0, })"
			)
		).toBe(true)
		expect(
			has(profile, 'if section == "*" or section == "Stats" or section == "Daily" then metaCluster:SetChecklist(')
		).toBe(true)
	end)

	it(
		"tick in the claimed green, and fold away stamped once all three are done, or never show for a veteran",
		function()
			local steps = body(code(CLUSTER), "setChecklist")
			expect(
				has(steps, "row.Box.BackgroundColor3 = if ticked then Theme.Colors.SuccessFill else Theme.Colors.Chalk")
			).toBe(true)
			expect(ThemeConfig.contrast(COLORS.Text, COLORS.SuccessFill)).toBeGreaterThanOrEqual(4.5)
			expect(has(steps, "if before == nil then steps.Visible = not all return end")).toBe(true)
			expect(has(steps, "if all and not before then")).toBe(true)
			expect(has(steps, "Fill = Theme.Colors.SuccessFill, Size = STEPS_SEAL, Stamp = true,")).toBe(true)
			expect(has(steps, 'Motion.to(stepsScale, { Scale = 0 }, "UiExit", function()')).toBe(true)
			expect(has(steps, "task.delay(STAMP_SECONDS, function()")).toBe(true)
		end
	)
end)

describe("the daily reward", function()
	it("opens by itself once a session, when it waits and nothing else has the player", function()
		local hud = code(HUD_CONTROLLER)
		local offer = body(hud, "offerDaily")
		local once = string.find(offer, "if dailyOffered then return end dailyOffered = true", 1, true)
		local later = string.find(offer, "task.delay(Theme.Timing.DailyAutoOpenDelaySeconds, function()", 1, true)
		assert(once ~= nil and later ~= nil, "the daily reward no longer offers itself once, a moment later")
		expect(once :: number).toBeLessThan(later :: number)
		expect(has(offer, "local waiting = Claims.count(clientData.get(), Workspace:GetServerTimeNow()).Daily > 0")).toBe(
			true
		)
		expect(
			has(
				offer,
				"if waiting and not (inMatch or inArena or queued) and not menuController.isOpen() then menuController.open(DAILY_SCREEN) end"
			)
		).toBe(true)
		expect(has(hud, 'local DAILY_SCREEN = "Daily"\n')).toBe(true)
		expect(ThemeConfig.Timing.DailyAutoOpenDelaySeconds).toBe(3)
		expect(has(body(hud, "refreshProfile"), "offerDaily()")).toBe(true)
	end)
end)
