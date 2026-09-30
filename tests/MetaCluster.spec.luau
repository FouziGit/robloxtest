--!strict
-- The hub's meta cluster (D-147): the level on a seal, the Folios on an ink pill with the way to more, a seal
-- per kind of claim waiting, and the queue while the player waits. It may show value colours, being the hub's
-- alone (tests/UiColor.spec.luau holds that the HUD hides it in a fight). Engine code, held by reading it,
-- with the colours it draws checked against each other.
local Engine = require("./engine")
local Harness = require("./harness")
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local Measure = require("./measure")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

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
		expect(has(currency, "heldFolios = math.floor(currency.Folios) if column.Visible then showFolios() end")).toBe(
			true
		)
		local show = body(source, "showFolios")
		local first = string.find(show, "if from == nil then count.Text = balance(target) return end", 1, true)
		local counted =
			string.find(show, "if target ~= from then Motion.countTo(count, from, target, balance) end", 1, true)
		assert(first ~= nil and counted ~= nil, "the Folios no longer count to what the profile holds")
		expect(first :: number).toBeLessThan(counted :: number)
		-- Hidden in a fight, nothing counts; back in the hub, what was won counts up.
		expect(has(body(source, "setVisible"), "column.Visible = visible if visible then showFolios() end")).toBe(true)
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
				"Badge.new(nil, seal.Instance, if fill == Theme.Colors.Primary then Theme.Colors.PanelRaised else nil)"
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

-- Landscape phones by their height in points, and the top bar over their game in pixels (TouchCluster.spec).
local PHONE_HEIGHTS = { 375, 390, 414 }
local TOP_INSET = 36

-- The real cluster, built in `corner` (tests/engine.luau), with what it opened recorded; on a 667 x 375 phone
-- when `phone`, whose touch floor makes a 44-pixel target larger than the designs it holds.
local function build(corner: string, phone: boolean?): (any, any, { string })
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	if phone then
		Engine.phone(world, 667, 375)
	end
	local MetaCluster = world.require(string.gsub(CLUSTER, "%.luau$", ""))
	local opened: { string } = {}
	local holder = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
	local cluster = MetaCluster.new({
		Parent = holder,
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		Corner = corner,
		OnOpen = function(screen: string)
			table.insert(opened, screen)
		end,
		OnLeaveQueue = function() end,
	})
	cluster:SetChecklist({ Cast = false, Match = false, Daily = false })
	return world, cluster, opened
end

describe("the hub's meta cluster over the thumbstick, run", function()
	it("puts every tap it has on touch in one row under the level", function()
		local _world, cluster = build("Top")
		local column = cluster.Instance
		local tray = column:FindFirstChild("Tray")
		expect(tray).never.toBeNil()
		expect(tray.LayoutOrder).toBeLessThan(column:FindFirstChild("Steps").LayoutOrder)
		for _, name in ipairs({ "Folios", "Claims", "Queue" }) do
			expect(tray:FindFirstChild(name)).never.toBeNil()
		end
		local buttons = 0
		for _, part in ipairs(column:GetDescendants()) do
			if part:IsA("GuiButton") then
				buttons += 1
				if not part:IsDescendantOf(tray) then
					error(("%s takes a tap outside the row under the level"):format(part:GetFullName()))
				end
			end
		end
		expect(buttons).toBeGreaterThan(0)
	end)

	it("ends that row above the thumbstick's frame on every landscape phone", function()
		-- PlayerModule's DynamicThumbstick takes a touch that begins over the left 40 % of its ScreenGui and its
		-- lower two thirds; that ScreenGui sits under the top bar, as the HUD's safe area does.
		local world, cluster = build("Top")
		local Theme = world.require("src/ui/Theme")
		local column = cluster.Instance
		local gap = column:FindFirstChildOfClass("UIListLayout").Padding.Offset
		local level = column:FindFirstChild("Level").Size.Y.Offset
		local row = column:FindFirstChild("Tray")
		-- What the row holds stands under the room it keeps for the claims' badges.
		local padding = row:FindFirstChildOfClass("UIPadding")
		local room = if padding ~= nil then padding.PaddingTop.Offset else 0
		local foot = if padding ~= nil then padding.PaddingBottom.Offset else 0
		local tray = row.Size.Y.Offset - room - foot
		for _, points in ipairs(PHONE_HEIGHTS) do
			local scale = ThemeConfig.scaleFor(points, true)
			local inset = TOP_INSET / scale
			local frameTop = inset + (points / scale - inset) / 3
			-- The row's taps stand centred on what it holds, floored at the touch minimum.
			local tallest = math.max(tray, Theme.MinTouchTarget / scale)
			local bottom = inset + column.Position.Y.Offset + level + gap + room + tray / 2 + tallest / 2
			if bottom > frameTop then
				error(
					("on a %d-point phone the cluster takes taps down to %.1f, the thumbstick from %.1f"):format(
						points,
						bottom,
						frameTop
					)
				)
			end
		end
	end)

	it("groups the Folios by thousands in the player's language, first written and then counted", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local MetaCluster = world.require(string.gsub(CLUSTER, "%.luau$", ""))
		local holder = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
		local cluster = MetaCluster.new({
			Parent = holder,
			Localize = {
				t = function(key: string, params: { [string]: any }?): string
					return Strings.t(key, params, "fr")
				end,
			},
			Corner = "Top",
			OnOpen = function() end,
			OnLeaveQueue = function() end,
		})
		local count = cluster.Instance:FindFirstChild("Tray"):FindFirstChild("Folios"):FindFirstChild("Count", true)
		local thin = "\u{202F}"
		cluster:SetCurrency({ Folios = 2480 })
		expect(count.Text).toBe("2" .. thin .. "480")
		cluster:SetCurrency({ Folios = 12480 })
		world:advance(0.1)
		expect(string.match(count.Text, "^%d+" .. thin .. "%d%d%d$")).never.toBeNil()
		world:advance(3)
		expect(count.Text).toBe("12" .. thin .. "480")
	end)

	it("lets a thumb on the first steps walk, where a pointer still clicks them", function()
		local _touchWorld, touch = build("Top")
		for _, part in ipairs(touch.Instance:FindFirstChild("Steps"):GetDescendants()) do
			if part:IsA("GuiButton") then
				error(("%s takes a tap under the thumbstick's frame"):format(part:GetFullName()))
			end
		end
		local _pointerWorld, pointer, opened = build("Bottom")
		expect(pointer.Instance:FindFirstChild("Tray")).toBeNil()
		local steps = pointer.Instance:FindFirstChild("Steps")
		local match
		for _, part in ipairs(steps:GetDescendants()) do
			if part.Name == "Match" then
				match = part
			end
		end
		expect(match:IsA("GuiButton")).toBe(true)
		match.Activated:Fire()
		expect(opened).toEqual({ "Play" })
	end)
end)

describe("the hub's meta cluster at a phone's touch floor, run", function()
	-- The floor (Theme.minPixelSize) makes a claim's and a circle's hit area larger than what it draws.
	local function floored(button: any): number
		local constraint = button:FindFirstChildOfClass("UISizeConstraint")
		assert(constraint ~= nil, button:GetFullName() .. " has no touch floor: this gate would check nothing")
		return constraint.MinSize.Y
	end

	local function centred(object: any, size: number)
		expect(object.Size.X.Offset).toBe(size)
		expect(object.Size.Y.Offset).toBe(size)
		expect(object.Size.X.Scale).toBe(0)
		expect(object.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
		expect(object.Position).toBe(roblox.UDim2.fromScale(0.5, 0.5))
	end

	it("draws each claim seal at its size in the middle of its hit area, badged on the seal", function()
		local _world, cluster = build("Top", true)
		local claims = cluster.Instance:FindFirstChild("Claims", true)
		local seals = number(code(CLUSTER), "CLAIM_SEAL")
		local checked = 0
		for _, button in ipairs(claims:GetChildren()) do
			if button:IsA("TextButton") then
				checked += 1
				expect(floored(button)).toBeGreaterThan(seals)
				local seal = button:FindFirstChild("Seal")
				centred(seal, seals)
				expect(seal:FindFirstChild("Badge")).never.toBeNil()
				expect(button:FindFirstChild("Badge")).toBeNil()
			end
		end
		expect(checked).toBe(3)
	end)

	it("draws the Folios' + and the queue's cross at their size in the middle of theirs", function()
		local _world, cluster = build("Top", true)
		local circle = number(code(CLUSTER), "CIRCLE")
		for _, name in ipairs({ "More", "Leave" }) do
			local button = cluster.Instance:FindFirstChild(name, true)
			expect(floored(button)).toBeGreaterThan(circle)
			centred(button:FindFirstChild("Face"), circle)
		end
	end)
end)

describe("a claim's badge in the hub, run", function()
	type Rect = { Name: string, Left: number, Top: number, Right: number, Bottom: number }

	local function overlaps(a: Rect, b: Rect): boolean
		return a.Left < b.Right and b.Left < a.Right and a.Top < b.Bottom and b.Top < a.Bottom
	end

	-- How far down `row` its list, centring across, places a child `height` tall: in the middle of what the row
	-- leaves under its padding.
	local function centred(row: any, height: number): number
		local layout = row:FindFirstChildOfClass("UIListLayout")
		assert(
			layout.FillDirection.Name == "Horizontal" and layout.VerticalAlignment.Name == "Center",
			row:GetFullName() .. " no longer centres its row: this gate would measure a layout nobody draws"
		)
		local padding = row:FindFirstChildOfClass("UIPadding")
		local top = if padding ~= nil then padding.PaddingTop.Offset else 0
		local foot = if padding ~= nil then padding.PaddingBottom.Offset else 0
		return top + (row.Size.Y.Offset - top - foot - height) / 2
	end

	-- How large `object` is drawn on `axis`: its size, or its touch floor where that is larger.
	local function drawn(object: any, axis: string): number
		local size = (object.Size :: any)[axis].Offset
		local floor = object:FindFirstChild("TouchFloor")
		return if floor ~= nil then math.max(size, (floor.MinSize :: any)[axis]) else size
	end

	-- The claims' seals, visible, in the order their row lays them out.
	local function shown(claims: any): { any }
		local buttons = {}
		for _, button in ipairs(claims:GetChildren()) do
			if button:IsA("TextButton") and button.Visible then
				table.insert(buttons, button)
			end
		end
		table.sort(buttons, function(a: any, b: any): boolean
			return a.LayoutOrder < b.LayoutOrder
		end)
		return buttons
	end

	-- The cluster in `corner`, on the phone when `phone`, with a claim of each kind waiting (one of two figures);
	-- each seal measured as the engine lays it out, which is what its badge reads to sit astride it; and the
	-- breath's peak, run.
	local function laidOut(corner: string, phone: boolean): (any, number)
		local world, cluster = build(corner, phone)
		local scale = world.require("src/ui/Theme").activeScale()
		cluster:SetClaims({ Daily = 1, Quests = 3, Pass = 12 })
		local breath
		for _, button in ipairs(shown(cluster.Instance:FindFirstChild("Claims", true))) do
			local seal = button:FindFirstChild("Seal")
			seal.AbsoluteSize = roblox.Vector2.new(seal.Size.X.Offset * scale, seal.Size.Y.Offset * scale)
			breath = seal:FindFirstChild("Badge"):FindFirstChildOfClass("UIScale")
		end
		local peak = 1
		for _ = 1, 4 * 60 do
			world:frames(1)
			peak = math.max(peak, breath.Scale)
		end
		return cluster, peak
	end

	it("stands clear of the Folios and of every row over the seals, with a pointer and on a phone", function()
		for _, case in ipairs({ { Corner = "Bottom", Phone = false }, { Corner = "Top", Phone = true } }) do
			local cluster, peak = laidOut(case.Corner, case.Phone)
			local column = cluster.Instance
			local claims = column:FindFirstChild("Claims", true)
			local folios = column:FindFirstChild("Folios", true)
			-- The column's row the seals stand in: their own with a pointer, the tray beside the Folios on touch.
			local row = if claims.Parent == column then claims else claims.Parent
			local rowTop = Measure.listTop(column, row)
			local claimsTop = if row == claims then rowTop else rowTop + centred(row, claims.Size.Y.Offset)
			-- Down from the column's top, across from the claims' left edge. The Folios pill is as wide as its count,
			-- which Lune does not lay out: it is taken to reach as far as it could toward the seals, across the
			-- column over them, and up to the tray's gap beside them.
			local pill: Rect
			if row == claims then
				local top = Measure.listTop(column, folios)
				pill = { Name = "Folios", Left = 0, Top = top, Right = math.huge, Bottom = top + folios.Size.Y.Offset }
			else
				expect(folios.Parent).toBe(row)
				expect(folios.LayoutOrder + 1).toBe(claims.LayoutOrder)
				local top = rowTop + centred(row, folios.Size.Y.Offset)
				local beside = -row:FindFirstChildOfClass("UIListLayout").Padding.Offset
				pill = {
					Name = "Folios",
					Left = -math.huge,
					Top = top,
					Right = beside,
					Bottom = top + folios.Size.Y.Offset,
				}
			end
			-- And every other row of the column over the seals' own, as wide as the column could be.
			local over: { Rect } = { pill }
			for _, other in ipairs(column:GetChildren()) do
				local before = other:IsA("GuiObject") and other.Visible and other.LayoutOrder < row.LayoutOrder
				if before and other ~= folios then
					local top = Measure.listTop(column, other)
					local bottom = top + other.Size.Y.Offset
					table.insert(
						over,
						{ Name = other.Name, Left = -math.huge, Top = top, Right = math.huge, Bottom = bottom }
					)
				end
			end
			expect(#over).toBeGreaterThan(1)
			-- Each seal in the middle of its hit area, the areas left to right; its badge astride its corner, swollen
			-- by its breath about the point it is placed at.
			local gap = claims:FindFirstChildOfClass("UIListLayout").Padding.Offset
			local left, checked = 0, 0
			for _, button in ipairs(shown(claims)) do
				local seal = button:FindFirstChild("Seal")
				local width, height = drawn(button, "X"), drawn(button, "Y")
				local sealLeft = left + (width - seal.Size.X.Offset) / 2
				local sealTop = claimsTop + centred(claims, height) + (height - seal.Size.Y.Offset) / 2
				local holder = seal:FindFirstChild("Badge")
				local disc = holder:FindFirstChild("Blot")
				local count = disc:FindFirstChild("Count")
				local room = count:FindFirstChildOfClass("UIPadding")
				local words = Measure.textWidth(count.Text, count.TextSize) + room.PaddingLeft.Offset * 2
				local tall = disc.Size.Y.Offset * peak
				local wide = math.max(disc.Size.Y.Offset, words) * peak
				local x = sealLeft
					+ holder.Position.X.Scale * seal.Size.X.Offset
					+ holder.Position.X.Offset
					- holder.AnchorPoint.X * wide
				local y = sealTop
					+ holder.Position.Y.Scale * seal.Size.Y.Offset
					+ holder.Position.Y.Offset
					- holder.AnchorPoint.Y * tall
				local badge = { Name = button.Name, Left = x, Top = y, Right = x + wide, Bottom = y + tall }
				expect(holder.Visible).toBe(true)
				for _, rect in ipairs(over) do
					if overlaps(badge, rect) then
						error(
							("%s: %s's badge (%.1f to %.1f down, %.1f to %.1f across) reaches %s (%.1f to %.1f down)"):format(
								case.Corner,
								badge.Name,
								badge.Top,
								badge.Bottom,
								badge.Left,
								badge.Right,
								rect.Name,
								rect.Top,
								rect.Bottom
							)
						)
					end
				end
				left += width + gap
				checked += 1
			end
			expect(checked).toBe(3)
		end
	end)
end)

describe("the hub's claims, run", function()
	it(
		"seals the day's reward once the client hears the servers' clock, which it has not as the profile lands",
		function()
			local today = math.floor(os.time() / 86400)
			local quests = { PeriodKey = "", Claimed = {}, Progress = {} }
			-- Claimed yesterday: today's reward waits.
			local fixture = Hud.build({
				ClockHeardAfter = 0.3,
				Profile = {
					Settings = {
						Keyboard = table.clone(InputConfig.DefaultKeyboard),
						Gamepad = table.clone(InputConfig.DefaultGamepad),
						CameraShake = true,
					},
					Loadout = { Slots = { "Brand" }, SlotLimit = 6 },
					Progression = { Level = 5, XP = 10 },
					Currency = { Folios = 100 },
					Stats = { GlyphsCast = 3, MatchesPlayed = 2 },
					Daily = { LastClaimDay = today - 1, Streak = 1, CalendarDay = 1, Signets = 0 },
					Quests = { Daily = quests, Weekly = table.clone(quests) },
					Battlepass = {},
				},
			})
			local seal = fixture.screen:FindFirstChild("Claims", true):FindFirstChild("Daily")
			assert(seal ~= nil, "the cluster has no daily seal: this gate would check nothing")
			-- Counted on day 0, before the clock was heard: nothing to claim yet.
			expect(seal.Visible).toBe(false)
			-- Not a whole day later: as soon as the clock is heard.
			fixture.world:advance(1)
			expect(seal.Visible).toBe(true)
		end
	)
end)

return nil
