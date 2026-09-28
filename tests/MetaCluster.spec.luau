--!strict
-- The hub's meta cluster (D-147): the level on a seal, the Folios on an ink pill with the way to more, a seal
-- per kind of claim waiting, and the queue while the player waits. It may show value colours, being the hub's
-- alone (tests/UiColor.spec.luau holds that the HUD hides it in a fight). Engine code, held by reading it,
-- with the colours it draws checked against each other.
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CLUSTER = "src/ui/components/MetaCluster.luau"
local HUD_CONTROLLER = "src/client/Controllers/HudController.luau"
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

describe("the hub's meta cluster", function()
	it("stands in the corner the engine leaves free: bottom-left with a pointer, top-left on touch", function()
		expect(has(folded(HUD_CONTROLLER), 'Corner = if Theme.touchOnly() then "Top" else "Bottom",')).toBe(true)
		local cluster = folded(CLUSTER)
		expect(has(cluster, "column.AnchorPoint = Vector2.new(0, if bottom then 1 else 0)")).toBe(true)
		expect(
			has(cluster, "column.Position = if bottom then UDim2.new(0, pad, 1, -pad) else UDim2.fromOffset(pad, pad)")
		).toBe(true)
		expect(has(cluster, "column.Size = UDim2.fromOffset(HUD.MetaWidth, 0)")).toBe(true)
		expect(ThemeConfig.Hud.MetaWidth).toBe(300)
	end)

	it("puts the level on a seal of the primary yellow, punched when a level is gained, over its XP", function()
		local source = code(CLUSTER)
		local cluster = folded(CLUSTER)
		expect(
			has(
				cluster,
				'Seal.new({ Text = "", Fill = Theme.Colors.Primary, Size = LEVEL_SEAL, Face = "Numeric", Parent = sealHolder })'
			)
		).toBe(true)
		expect(number(source, "LEVEL_SEAL")).toBe(56)
		local progression = body(source, "setProgression")
		expect(
			has(
				progression,
				"if shownLevel ~= nil and level > shownLevel then Motion.punch(sealScale, LEVEL_PUNCH) end"
			)
		).toBe(true)
		expect(number(source, "LEVEL_PUNCH")).toBe(1.25)
		expect(has(progression, 'localize.t("level.xp", { xp = xp, needed = needed })')).toBe(true)
		expect(has(cluster, "Color = Theme.Colors.Primary, OnPlate = true,")).toBe(true)
		expect(number(source, "XP_BAR_WIDTH")).toBe(200)
		expect(number(source, "XP_BAR_HEIGHT")).toBe(12)
		expect(has(cluster, 'textLabel("Value", Theme.Fonts.Numeric, XP_TEXT, Theme.Colors.TextInverse)')).toBe(true)
		expect(ThemeConfig.contrast(COLORS.Text, COLORS.Primary)).toBeGreaterThanOrEqual(4.5)
		expect(ThemeConfig.contrast(COLORS.Primary, COLORS.Well)).toBeGreaterThanOrEqual(3)
	end)

	it("counts the Folios up as they grow, in the yellow on ink, with a way to the shop's Folios", function()
		local source = code(CLUSTER)
		local currency = body(source, "setCurrency")
		local plain = string.find(
			currency,
			"if from == nil or amount <= from then count.Text = tostring(amount) return end",
			1,
			true
		)
		local counted = string.find(currency, "Motion.countTo(count, from, amount, tostring)", 1, true)
		assert(plain ~= nil and counted ~= nil, "the Folios no longer count up")
		expect(plain :: number).toBeLessThan(counted :: number)
		expect(has(source, 'textLabel("Count", Theme.Fonts.Numeric, Theme.Sizes.Num, Theme.Colors.Primary)')).toBe(true)
		expect(ThemeConfig.contrast(COLORS.Primary, COLORS.Plate)).toBeGreaterThanOrEqual(4.5)
		local cluster = folded(CLUSTER)
		expect(has(cluster, 'props.OnOpen("Shop", { Tab = FOLIOS_TAB })')).toBe(true)
		expect(has(source, 'local FOLIOS_TAB = "Folios"\n')).toBe(true)
		expect(
			has(
				folded(HUD_CONTROLLER),
				"OnOpen = function(screen: string, args: any?) menuController.open(screen, args) end,"
			)
		).toBe(true)
		-- A disc too small for a word, still a thumb's worth to hit, and out of a gamepad's way: no focus is given.
		expect(
			has(
				cluster,
				'CircleButton.new({ Sign = Theme.Glyphs.Plus, Size = CIRCLE, LayoutOrder = 3, Parent = foliosRow, Name = "More", OnClick = function() props.OnOpen("Shop", { Tab = FOLIOS_TAB }) end, })'
			)
		).toBe(true)
		local circle = folded("src/ui/components/CircleButton.luau")
		expect(has(circle, "button.Selectable = props.Focus ~= nil")).toBe(true)
		expect(has(circle, "Theme.minPixelSize(button, Theme.MinTouchTarget)")).toBe(true)
		expect(has(circle, 'UiSound.play("UiClick")')).toBe(true)
	end)

	it("seals each claim waiting in its screen's own colour, badged with how many, and only while it waits", function()
		local source = code(CLUSTER)
		local cluster = folded(CLUSTER)
		local rows = {
			{ Kind = "Daily", Screen = "Daily", Fill = "Primary", Icon = "Calendar" },
			{ Kind = "Quests", Screen = "Quests", Fill = "InfoFill", Icon = "Scroll" },
			{ Kind = "Pass", Screen = "Battlepass", Fill = "Epic", Icon = "Pass" },
		}
		for _, row in ipairs(rows) do
			local line = ('{ Kind = "%s", Screen = "%s", Fill = "%s", Icon = "%s" },'):format(
				row.Kind,
				row.Screen,
				row.Fill,
				row.Icon
			)
			if not has(cluster, line) then
				error("the claims no longer seal " .. line)
			end
			-- The seal is the colour of the chapter it opens.
			expect(ThemeConfig.Chapters[row.Screen]).toBe(row.Fill)
			-- Its icon in the ink that reads on it.
			local fill = COLORS[row.Fill]
			expect(ThemeConfig.contrast(ThemeConfig.inkOn(fill), fill)).toBeGreaterThanOrEqual(3)
		end
		expect(has(cluster, "local icon = Icon.new(claim.Icon, CLAIM_ICON, Theme.inkOn(fill))")).toBe(true)
		local claims = body(source, "setClaims")
		expect(has(claims, "seal.Button.Visible = waiting > 0")).toBe(true)
		expect(has(claims, "seal.Badge:Set(if waiting > 0 then waiting else nil)")).toBe(true)
		expect(has(claims, "claimsRow.Visible = any")).toBe(true)
		expect(has(cluster, "props.OnOpen(claim.Screen)")).toBe(true)
		expect(
			has(
				cluster,
				"Badge.new(nil, button, if fill == Theme.Colors.Primary then Theme.Colors.PanelRaised else nil)"
			)
		).toBe(true)
		expect(has(body(code(HUD_CONTROLLER), "refreshClaims"), "metaCluster:SetClaims(counts)")).toBe(true)
	end)

	it(
		"shows the queue while the player waits: the wait each second, one loop for its dots, a cross to leave",
		function()
			local source = code(CLUSTER)
			local queue = body(source, "setQueue")
			expect(has(queue, "waitedBase, waitedAt = snapshot.WaitedSeconds, os.clock()")).toBe(true)
			expect(has(queue, 'stopWave = Motion.loop(wave, { Value = 0 }, { Value = 1 }, "Ui")')).toBe(true)
			expect(has(queue, 'Motion.to(queueScale, { Scale = 1 }, "UiPop")')).toBe(true)
			expect(has(queue, 'Motion.to(queueScale, { Scale = 0 }, "UiExit", function()')).toBe(true)
			-- The three dots breathe on the one loop: the cluster opens no other.
			expect(select(2, string.gsub(source, "Motion%.loop%(", ""))).toBe(1)
			local tick = body(source, "tick")
			expect(has(tick, "if token ~= queueToken or not queued then return end")).toBe(true)
			expect(has(tick, "local waited = waitedBase + math.floor(os.clock() - waitedAt)")).toBe(true)
			expect(has(tick, 'searching.Text = localize.t("queue.searching", { waited = waited })')).toBe(true)
			expect(has(tick, "task.delay(SECOND, tick, token)")).toBe(true)
			expect(number(source, "SECOND")).toBe(1)
			expect(Strings.has("queue.searching")).toBe(true)
			-- Cyan and the sheet: the queue is ours, not a value.
			expect(has(source, 'local DOT_FILLS: { string } = { "Ally", "PanelRaised", "Ally" }')).toBe(true)
			local cluster = folded(CLUSTER)
			expect(
				has(
					cluster,
					'CircleButton.new({ Sign = Theme.Glyphs.Close, Size = CIRCLE, LayoutOrder = 3, Parent = queueRow, Name = "Leave", OnClick = props.OnLeaveQueue, })'
				)
			).toBe(true)
			expect(has(cluster, "props.OnOpen(PLAY_SCREEN)")).toBe(true)
			expect(has(folded(HUD_CONTROLLER), "OnLeaveQueue = function() matchController.leaveQueue() end,")).toBe(
				true
			)
		end
	)
end)
