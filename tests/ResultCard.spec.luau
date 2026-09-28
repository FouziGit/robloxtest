--!strict
-- The Result takeover (D-147, slice B), read from its source since Lune cannot build an interface: the seal
-- of every hand the server can grade, the world darker than under a menu, the outcome in its own colours
-- (a defeat never bounces), the rating's fall in red only at a size red may be read at, the default focus on
-- Play again, and an auto-close that the player's first touch hands back to them -- with the lines the
-- earlier Result pinned still where they were.
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SCREEN = "src/ui/screens/ResultScreen.luau"
local CARD = "src/ui/components/ResultCard.luau"
local BANNER = "src/ui/components/OutcomeBanner.luau"
local ROOT = "src/ui/components/ScreenRoot.luau"
local EXECUTION = "src/shared/Pure/Execution.luau"

local function stripComments(source: string): string
	local lines = {}
	for line in string.gmatch(source .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function body(source: string, name: string, indent: string): string
	local found = string.match(source, "local function " .. name .. "%(.-\n" .. indent .. "end\n")
	if found == nil then
		error(("no local function %s: this gate would check nothing"):format(name))
	end
	return found
end

describe("the result takeover", function()
	local screen = stripComments(fs.readFile(SCREEN))
	local card = stripComments(fs.readFile(CARD))
	local banner = stripComments(fs.readFile(BANNER))

	it("has a seal for every hand the server grades, steadier ones fuller", function()
		local grades = string.match(fs.readFile(EXECUTION), "export type Grade = ([^\n]+)")
		assert(grades ~= nil, "Execution no longer exports its grades")
		local pips: { number } = {}
		local count = 0
		for grade in string.gmatch(grades :: string, '"([%w%.]+)"') do
			count += 1
			local found = string.match(
				card,
				'%["' .. grade:gsub("%.", "%%.") .. '"%] = { Fill = Theme%.Colors%.%w+, Pips = (%d) }'
			)
			if found == nil then
				error(("the Result has no seal for %s"):format(grade))
			end
			table.insert(pips, tonumber(found) :: number)
		end
		expect(count).toBe(4)
		-- Listed from the steadiest: each one fuller than the next, so no two hands look alike.
		for index = 2, #pips do
			expect(pips[index - 1]).toBeGreaterThan(pips[index])
		end
		expect(card).toContain("gradeSeal:SetText(string.rep(Theme.Glyphs.Pip, grade.Pips))")
	end)

	it("darkens the world to 0.25 over the backdrop's own dim", function()
		local dim = tonumber(string.match(stripComments(fs.readFile(ROOT)), "local DIM = ([%d%.]+)"))
		local numerator, denominator = string.match(screen, "local DEEPEN_TRANSPARENCY = ([%d%.]+) / ([%d%.]+)")
		assert(dim ~= nil and numerator ~= nil and denominator ~= nil, "the takeover's dim is no longer readable")
		expect(tonumber(denominator)).toBe(dim)
		-- Two inks over each other let through the product of what each lets through.
		expect((dim :: number) * tonumber(numerator) / tonumber(denominator)).toBeCloseTo(0.25, 6)
		expect(screen).toContain("deepen.Parent = root.Instance")
	end)

	it("takes each outcome's colours, and lets a defeat come down with no bounce", function()
		expect(ThemeConfig.Chapters.Victory).toBe("Primary")
		expect(ThemeConfig.Chapters.Defeat).toBe("Info")
		expect(ThemeConfig.Chapters.Draw).toBe("Chalk")
		expect(screen).toContain("root:SetChapter(kind)")
		expect(banner).toContain('Motion.to(title, { Position = rest }, "UiExit")')
		expect(banner).toContain('Motion.to(titleScale, { Scale = 1 }, "UiPop")')
		-- Our cyan joins a victory, and never a defeat.
		local defeat = string.match(banner, "Defeat = {(.-)\n\t},")
		assert(defeat ~= nil, "OutcomeBanner no longer draws a defeat")
		expect(string.find(defeat :: string, "Ally", 1, true)).toBeNil()
		expect(string.match(banner, "Victory = {(.-)\n\t},")).toContain("Theme.Colors.Ally")
	end)

	it("keeps its bursts inside the screen's splat budget", function()
		local spots = string.match(banner, "local SPOTS: .-= (%b{})")
		assert(spots ~= nil, "OutcomeBanner has no SPOTS")
		local _, count = string.gsub(spots :: string, "{ X = ", "")
		local corners = select(2, string.gsub(stripComments(fs.readFile(ROOT)), "{ Position = UDim2%.fromScale", ""))
		expect(count + corners).toBeLessThanOrEqual(ThemeConfig.Budget.MaxSplats)
	end)

	it("writes a fall of rating in red only at a size red may be read at", function()
		expect(card).toContain(
			"ratingLine.TextColor3 = if delta >= 0 then Theme.Colors.Success else Theme.Colors.Danger"
		)
		local size = tonumber(string.match(card, "local RATING_SIZE = (%d+)"))
		assert(size ~= nil, "ResultCard has no RATING_SIZE")
		expect(size :: number).toBeGreaterThanOrEqual(24)
	end)

	it("counts what the match paid once the card has landed, and stamps a new rank", function()
		expect(screen).toContain(
			"task.delay(CELEBRATE_DELAY, function()\n\t\t\tif session == mine then\n\t\t\t\trows:Celebrate(outcome)"
		)
		local celebrate = body(card, "celebrate", "\t")
		expect(celebrate).toContain("Motion.countTo(xpText, 0, outcome.Xp,")
		expect(celebrate).toContain("Motion.countTo(foliosText, 0, outcome.Folios,")
		expect(celebrate).toContain("if rankRow.Visible then\n\t\t\trankSeal:Stamp()")
		expect(card).toContain("details.Visible = not Theme.touchOnly()")
	end)

	it("puts a pad's focus on Play again", function()
		expect(body(screen, "focus", "\t")).toContain(
			"GuiService.SelectedObject = if againButton:IsDisabled() then okButton.Instance else againButton.Instance"
		)
	end)

	it("hands the card to the player at their first touch, and empties its ring once a second", function()
		local pause = string.match(
			screen,
			"trove:Connect%(UserInputService%.InputBegan, function%(input: InputObject%)(.-)\n\tend%)"
		)
		assert(pause ~= nil, "ResultScreen no longer listens for the player's touch")
		expect(pause).toContain("if screen.Visible and autoClose ~= nil and isPress(input) then")
		expect(pause).toContain("cancelAutoClose()")
		expect(pause).toContain("ring.Visible = false")
		expect(screen).toContain("local RING_TICK_SECONDS = 1")
		expect(body(screen, "tickRing", "\t")).toContain("task.delay(math.min(RING_TICK_SECONDS, left), tickRing,")
		for _, source in ipairs({ screen, card, banner }) do
			expect(string.find(source, "Heartbeat", 1, true)).toBeNil()
			expect(string.find(source, "RenderStepped", 1, true)).toBeNil()
		end
	end)

	it("keeps the lines the earlier Result was held to", function()
		expect(screen).toContain("local function cancelAutoClose()")
		expect(screen).toContain("local total = resultSeconds(outcome.ModeId)")
		expect(screen).toContain("againButton:SetDisabled(MatchConfig.Modes[outcome.ModeId] == nil)")
	end)
end)
