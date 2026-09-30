--!strict
-- The login calendar on screen, run (tests/engine.luau): the real DailyScreen and the hub's MetaCluster, in the
-- player's words (the real Strings, in English). The screen shows the week today falls in, its seventh card the
-- week's cosmetic, a bookmark on the day that gives a Signet, and the Signets held; the hub's HUD counts the
-- streak (E15-S1).
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DailyConfig = require("../src/shared/Config/DailyConfig")
local Engine = require("./engine")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SECONDS_PER_DAY = 86400

local function english(key: string, params: { [string]: any }?): string
	local resolved: { [string]: any } = {}
	for name, value in pairs(params or {}) do
		resolved[name] = if type(value) == "string" and Strings.has(value)
			then Strings.t(value, params, "en")
			else value
	end
	return Strings.t(key, resolved, "en")
end

-- The screen over a profile that claimed calendar day `day` (streak `streak`) `ago` days ago, holding `signets`.
local function build(day: number, streak: number, ago: number, signets: number): (any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local Screen = world.require("src/ui/screens/DailyScreen")
	local today = math.floor(world.workspace:GetServerTimeNow() / SECONDS_PER_DAY)
	local data = {
		Currency = { Folios = 0 },
		Daily = {
			LastClaimDay = today - ago,
			Streak = streak,
			CalendarDay = day,
			Signets = signets,
			FirstWinDay = 0,
			PremiumBonusDay = 0,
		},
	}
	local changed = Engine.signal()
	local screen = Screen.new({
		Localize = { t = english },
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = changed,
		},
		RemoteClient = { fire = function() end },
		InputController = { captureNext = function() end },
		SoundController = { play = function() end },
		HudController = { showLocalToast = function() end },
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	screen:Open()
	world:advance(0.5)
	return screen, data, changed
end

local function card(screen: any, slot: number): any
	local found = screen.Instance:FindFirstChild("Calendar", true):FindFirstChild("Day" .. slot)
	assert(found ~= nil, "no card in slot " .. slot .. ": this gate would check nothing")
	return found
end

local function word(screen: any, slot: number): string
	return card(screen, slot)
		:FindFirstChild("Face")
		:FindFirstChild("Body")
		:FindFirstChild("DayRow")
		:FindFirstChild("Day").Text
end

describe("the login calendar on screen, run", function()
	it("shows the week today falls in, today's card waiting, and says where the 28 days stand", function()
		-- Day 9 claimed yesterday: today is day 10, the third of the second week.
		local screen = build(9, 9, 1, 0)
		for slot = 1, 7 do
			expect(word(screen, slot)).toBe(("Day %d"):format(7 + slot))
		end
		expect(card(screen, 3):FindFirstChild("Badge").Visible).toBe(true)
		expect(card(screen, 2):FindFirstChild("Badge").Visible).toBe(false)
		local line = screen.Instance:FindFirstChild("Standing", true):FindFirstChild("Streak").Text
		expect(line).toBe("Day 10 of 28 · Streak 9")
	end)

	it("dresses the seventh card as the week's cosmetic: its name, and its rarity's rim and ribbon", function()
		for _, case in ipairs({ { Day = 3, Prize = 7 }, { Day = 16, Prize = 21 }, { Day = 27, Prize = 28 } }) do
			local screen = build(case.Day, case.Day, 1, 0)
			local item = CosmeticConfig.ById[DailyConfig.Calendar[case.Prize].Cosmetic :: string]
			local face = card(screen, 7):FindFirstChild("Face")
			expect(face:FindFirstChild("Body"):FindFirstChild("Prize").Text).toBe(Strings.t(item.NameKey, nil, "en"))
			local ribbon = face:FindFirstChild("Rarity")
			assert(ribbon ~= nil, "the prize card has no ribbon")
			expect(ribbon.BackgroundColor3).toBe(face:FindFirstChild("Rim"):FindFirstChildOfClass("UIStroke").Color)
			local ribbons = 0
			for _, child in ipairs(face:GetChildren()) do
				if child.Name == "Rarity" then
					ribbons += 1
				end
			end
			expect(ribbons).toBe(1)
		end
	end)

	it("wears one ribbon, of the week's rarity, as the weeks go by on the same screen", function()
		local screen, data, changed = build(6, 6, 1, 0)
		local face = card(screen, 7):FindFirstChild("Face")
		-- Three weeks on: the profile says so, the screen still up.
		data.Daily.CalendarDay = 20
		data.Daily.Streak = 20
		changed:Fire("Daily")
		local ribbons = {}
		for _, child in ipairs(face:GetChildren()) do
			if child.Name == "Rarity" then
				table.insert(ribbons, child)
			end
		end
		expect(#ribbons).toBe(1)
		expect(ribbons[1].BackgroundColor3).toBe(face:FindFirstChild("Rim"):FindFirstChildOfClass("UIStroke").Color)
		local item = CosmeticConfig.ById[DailyConfig.Calendar[21].Cosmetic :: string]
		expect(face:FindFirstChild("Body"):FindFirstChild("Prize").Text).toBe(Strings.t(item.NameKey, nil, "en"))
		expect(word(screen, 1)).toBe("Day 15")
	end)

	it("marks the day that slips a Signet in with a bookmark, and no other", function()
		local screen = build(9, 9, 1, 0)
		for slot = 1, 6 do
			local mark = card(screen, slot):FindFirstChild("Face"):FindFirstChild("SignetMark")
			expect(mark.Visible).toBe(DailyConfig.Calendar[7 + slot].Signet == true)
		end
		expect(card(screen, 3):FindFirstChild("Face"):FindFirstChild("SignetMark").Visible).toBe(true)
	end)

	it("shows the Signets held in ink, the others faded", function()
		local screen = build(4, 4, 1, 1)
		local signets = screen.Instance:FindFirstChild("Standing", true):FindFirstChild("Signets")
		local function inked(name: string): boolean
			local parts = 0
			for _, part in ipairs(signets:FindFirstChild(name):GetDescendants()) do
				if part:IsA("GuiObject") then
					parts += 1
					if part.BackgroundTransparency ~= 0 then
						return false
					end
				end
			end
			assert(parts > 0, "a bookmark with nothing drawn: this gate would check nothing")
			return true
		end
		expect(inked("Signet1")).toBe(true)
		expect(inked("Signet2")).toBe(false)
	end)

	it("says a Signet keeps the streak after a missed day, and what one is for otherwise", function()
		local saved = build(5, 5, 2, 1)
		local line = saved.Instance:FindFirstChild("AtRisk", true).Text
		expect(line).toBe(Strings.t("daily.signetSaves", nil, "en"))
		local claimed = build(5, 5, 0, 1)
		expect(claimed.Instance:FindFirstChild("AtRisk", true).Text).toBe(Strings.t("daily.signetHint", nil, "en"))
		local broken = build(5, 5, 3, 1)
		expect(word(broken, 1)).toBe("Day 1")
		expect(broken.Instance:FindFirstChild("AtRisk", true).Text).toBe(Strings.t("daily.signetHint", nil, "en"))
	end)

	it("names tomorrow's cosmetic, or its Signet, in the line under the row", function()
		local screen = build(5, 5, 1, 0)
		local item = CosmeticConfig.ById[DailyConfig.Calendar[7].Cosmetic :: string]
		expect(screen.Instance:FindFirstChild("Tomorrow", true).Text).toBe(
			Strings.t("daily.tomorrow", { reward = Strings.t(item.NameKey, nil, "en") }, "en")
		)
		local signet = build(1, 1, 1, 0)
		expect(string.find(signet.Instance:FindFirstChild("Tomorrow", true).Text, "Signet", 1, true)).never.toBeNil()
	end)
end)

describe("the streak on the hub's HUD, run", function()
	local function cluster(): any
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local MetaCluster = world.require("src/ui/components/MetaCluster")
		local holder = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
		return MetaCluster.new({
			Parent = holder,
			Localize = { t = english },
			Corner = "Bottom",
			OnOpen = function() end,
			OnLeaveQueue = function() end,
		})
	end

	it("counts the streak at the XP strip's other end, from its first day, never pressed", function()
		local meta = cluster()
		local streak = meta.Instance:FindFirstChild("Level"):FindFirstChild("Streak", true)
		assert(streak ~= nil, "the cluster has no streak: this gate would check nothing")
		meta:SetStreak(0)
		expect(streak.Visible).toBe(false)
		meta:SetStreak(12)
		expect(streak.Visible).toBe(true)
		expect(streak.Text).toBe("Streak 12")
		expect(streak.ClassName).toBe("TextLabel")
	end)

	it("is fed the streak as it stands on the server's day", function()
		local hud = (fs.readFile("src/client/Controllers/HudController.luau"):gsub("%s+", " "))
		expect(
			string.find(
				hud,
				"metaCluster:SetStreak(DailyStreak.standing(data.Daily, DailyStreak.dayIndex(Workspace:GetServerTimeNow())))",
				1,
				true
			)
		).never.toBeNil()
	end)
end)

return nil
