--!strict
-- What the HUD draws in a fight, counted (tests/engine.luau, tests/hud.luau): the real HUD built in a 3v3 with
-- every slot a pass opens, on a phone with its touch discs and with a pointer, against ThemeConfig.Budget.
--
-- The colour pass set the fight's HUD at 180 GuiObjects and nothing counted them: a pointer's hotbar alone
-- drew some 28 per glyph, its keys each a pressable cap. A GuiObject shown is one the engine lays out and
-- draws; the hidden ones (the hub's cluster, the spectate plate, a slot's cooldown seconds until a cooldown)
-- wait off screen.
local Engine = require("./engine")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- A player with every slot a pass opens filled.
local function profile(): any
	local slots = {}
	for index = 1, ProgressionConfig.Loadout.MaxSlots do
		table.insert(slots, GlyphConfig.Glyphs[index].Id)
	end
	local quests = { PeriodKey = "", Claimed = {}, Progress = {} }
	return {
		Settings = {
			Keyboard = table.clone(InputConfig.DefaultKeyboard),
			Gamepad = table.clone(InputConfig.DefaultGamepad),
			CameraShake = true,
		},
		Loadout = { Slots = slots, SlotLimit = ProgressionConfig.Loadout.MaxSlots },
		Progression = { Level = 5, XP = 10 },
		Currency = { Folios = 100 },
		Stats = { GlyphsCast = 3, MatchesPlayed = 2 },
		Daily = { LastClaimDay = 0, Streak = 0 },
		Quests = { Daily = quests, Weekly = table.clone(quests) },
		Battlepass = {},
	}
end

-- The GuiObjects under `root` the engine draws: each one shown, with every ancestor up to `root`.
local function shownUnder(root: any): number
	local count = 0
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("GuiObject") then
			local shown = true
			local current = part
			while current ~= nil and current ~= root do
				if current:IsA("GuiObject") and not current.Visible then
					shown = false
					break
				end
				current = current.Parent
			end
			if shown then
				count += 1
			end
		end
	end
	return count
end

-- The HUD of a 3v3 fight, on `phone` or with a pointer.
local function fight(phone: { number }?): any
	local fixture = Hud.build({ Profile = profile(), Phone = phone })
	fixture.match(Hud.match("Team3v3", 3))
	fixture.world:advance(1)
	return fixture
end

-- The touch discs as InputController draws them over the engine's buttons: one per action with a place.
local function discs(fixture: any): number
	local TouchButton = fixture.world.require("src/ui/components/TouchButton")
	local layer = Engine.instance("ScreenGui", fixture.world.playerGui)
	local count = 0
	for action in pairs(InputConfig.Touch.Positions) do
		local holder = Engine.instance("ImageButton", layer)
		local pigment = PigmentConfig.Colors[action] ~= nil
		TouchButton.new({
			Label = action,
			Kind = if pigment then "Pigment" elseif action == "Menu" then "Menu" else "Kit",
			Pigment = if pigment then action else nil,
			Size = InputConfig.Touch.ButtonSize,
			Position = roblox.UDim2.fromScale(0.5, 0.5),
			Parent = holder,
			Name = action,
		})
		count += shownUnder(holder)
	end
	return count
end

describe("the HUD in a fight, counted", function()
	it("stays inside a phone's budget, its touch discs included", function()
		local fixture = fight({ 844, 390 })
		local hud = shownUnder(fixture.screen)
		local total = hud + discs(fixture)
		if total > ThemeConfig.Budget.MaxHudObjects then
			error(("a phone's HUD draws %d GuiObjects in a fight (%d of them the HUD's)"):format(total, hud))
		end
		expect(hud).toBeGreaterThan(40)
	end)

	it("stays inside a pointer's", function()
		local fixture = fight(nil)
		local drawn = shownUnder(fixture.screen)
		if drawn > ThemeConfig.Budget.MaxHudObjectsPointer then
			error(("a pointer's HUD draws %d GuiObjects in a fight"):format(drawn))
		end
		expect(drawn).toBeGreaterThan(ThemeConfig.Budget.MaxHudObjects)
	end)

	it("builds a slot's cooldown seconds and short-ink drop only when it shows them", function()
		local fixture = fight(nil)
		local hotbar = fixture.screen:FindFirstChild("Hotbar", true)
		expect(hotbar).never.toBeNil()
		expect(hotbar:FindFirstChild("Seconds", true)).toBeNil()
		expect(hotbar:FindFirstChild("Drop", true)).toBeNil()
	end)
end)

return nil
