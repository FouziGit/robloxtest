--!strict
-- The gamepad's way through the ten screens (E12-S4, D-236), run (tests/engine.luau, tests/screens.luau). A pad
-- moves GuiService.SelectedObject among the objects the engine lets it select, and presses what it lands on; a
-- screen that opens with nothing selected leaves the D-pad dead, and a button the pad may not select is an action
-- a console player cannot take. The engine's own defaults decide what is selectable unless a module says otherwise
-- (tests/engine.luau reads them from its reflection database: a button yes, a frame no).
--
-- The audit, per screen: something of the screen is selected as it opens; every action shown -- a button something
-- listens to -- is selectable, or is a disabled Button, whose reason is written on it; every explicit edge
-- (NextSelection*) leads to something selectable and shown. And a list rebuilt under the pad never leaves it on
-- nothing.
local Engine = require("./engine")
local Harness = require("./harness")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local Screens = require("./screens")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local EDGES = { "NextSelectionUp", "NextSelectionDown", "NextSelectionLeft", "NextSelectionRight" }
local PRESSES = { "Activated", "MouseButton1Click" }

-- Whether `object` is drawn: it and every ancestor up to `root` visible.
local function shown(object: any, root: any): boolean
	local current = object
	while current ~= nil and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current == root
end

-- Whether something listens to a press of `button`.
local function listened(button: any): boolean
	for _, press in ipairs(PRESSES) do
		if button[press]:count() > 0 then
			return true
		end
	end
	return false
end

-- A Button (src/ui/components/Button) the screen disabled: it keeps its words and its reason, and is taken out of
-- the pad's way on purpose.
local function disabledButton(button: any): boolean
	return button:GetAttribute("Disabled") == true
end

-- What keeps the pad from an action on `root`, one line each, and how many actions were looked at.
local function audit(root: any, world: any): ({ string }, number)
	local found: { string } = {}
	local actions = 0
	local selected = world.guiService.SelectedObject
	if selected == nil then
		table.insert(found, "nothing is selected as it opens")
	elseif not selected:IsDescendantOf(root) or not shown(selected, root) or not selected.Selectable then
		table.insert(found, ("it opens on %s, which the pad cannot be on"):format(selected:GetFullName()))
	end
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("GuiObject") and shown(object, root) then
			if object:IsA("GuiButton") and object.Interactable ~= false and listened(object) then
				actions += 1
				if not object.Selectable and not disabledButton(object) then
					table.insert(found, ("%s is an action the pad cannot select"):format(object:GetFullName()))
				end
			end
			for _, edge in ipairs(EDGES) do
				local target = object[edge]
				if target ~= nil and (not target.Selectable or not shown(target, root)) then
					table.insert(
						found,
						("%s leads %s to %s, which the pad cannot be on"):format(
							object:GetFullName(),
							edge,
							target:GetFullName()
						)
					)
				end
			end
		end
	end
	return found, actions
end

-- The screens and tabs as a pad opens them on a desktop, for a player part-way into everything.
local function each(fn: (label: string, root: any, world: any, changed: any) -> ())
	for _, entry in ipairs(Screens.LIST) do
		for _, tab in ipairs(entry.Tabs or { "" }) do
			local built, _height, world, changed =
				Screens.open(entry.Name, { Plays = "Gamepad", Args = if tab ~= "" then { Tab = tab } else nil })
			fn(entry.Name .. (if tab ~= "" then " (" .. tab .. ")" else ""), built.Instance, world, changed)
		end
	end
	local result, _height, world = Screens.result({ Plays = "Gamepad" })
	fn("ResultScreen", result.Instance, world, nil)
end

describe("the gamepad's way through the screens, run", function()
	it("opens every screen with the pad on it, and leaves no action out of its reach", function()
		local screens = 0
		local lines: { string } = {}
		each(function(label: string, root: any, world: any)
			screens += 1
			local found, actions = audit(root, world)
			for _, line in ipairs(found) do
				table.insert(lines, label .. ": " .. line)
			end
			-- Every screen has its way out at least: an audit of nothing would pass.
			if actions == 0 then
				table.insert(lines, label .. ": no action was looked at")
			end
		end)
		expect(screens).toBe(13)
		if #lines > 0 then
			error(table.concat(lines, "\n"))
		end
	end)

	-- A push that rebuilds each screen's list: what the player owns, the pass's claims, the day's reward, the
	-- quests' draw, the loadout, the keys, the balance.
	local PUSHES: { [string]: (data: any, today: number) -> () } = {
		MenuScreen = function(data: any)
			data.Progression.Level += 1
		end,
		PlayScreen = function(data: any)
			data.Stats.MatchesPlayed += 1
		end,
		ShopScreen = function(data: any)
			table.insert(data.Cosmetics.Owned, "TrailViolet")
			data.Currency.Folios += 500
		end,
		BattlepassScreen = function(data: any)
			for _, season in pairs(data.Battlepass) do
				season.ClaimedFree["1"] = true
				season.ClaimedFree["2"] = true
			end
		end,
		DailyScreen = function(data: any, today: number)
			data.Daily.LastClaimDay = today
			data.Daily.Streak += 1
		end,
		LoadoutScreen = function(data: any)
			table.remove(data.Loadout.Slots, 1)
		end,
		QuestsScreen = function(data: any)
			data.Quests.Daily.PeriodKey = "rolled"
			data.Quests.Weekly.PeriodKey = "rolled"
		end,
		LeaderboardScreen = function(data: any)
			data.Rank.Modes = {}
		end,
		SettingsScreen = function(data: any)
			data.Settings.Keyboard.Menu = "N"
		end,
	}

	it("never leaves the pad on nothing when a push rebuilds the list under it", function()
		local lines: { string } = {}
		local rebuilt = 0
		for _, entry in ipairs(Screens.LIST) do
			for _, tab in ipairs(entry.Tabs or { "" }) do
				local label = entry.Name .. (if tab ~= "" then " (" .. tab .. ")" else "")
				-- A few cosmetics owned, and every quest done and waiting to be claimed.
				local owning = function(today: number): any
					local data = Screens.profile(today)
					data.Cosmetics.Owned = { "BlankHeadband", "TitleRookie" }
					for _, def in ipairs(QuestConfig.Pool) do
						data.Quests.Daily.Progress[def.Id] = def.Target
						data.Quests.Weekly.Progress[def.Id] = def.Target
					end
					return data
				end
				local built, _height, world, changed, data = Screens.open(
					entry.Name,
					{ Plays = "Gamepad", Args = if tab ~= "" then { Tab = tab } else nil, Profile = owning }
				)
				-- The pad on the last thing it can be on in the list: what a rebuild takes away first.
				local last: any = nil
				local content: any = nil
				for _, object in ipairs(built.Instance:GetDescendants()) do
					if content == nil and object.Name == "Content" and object:IsA("ScrollingFrame") then
						content = object
					end
				end
				assert(content ~= nil, label .. " has no list: this gate would check nothing")
				for _, object in ipairs(content:GetDescendants()) do
					if object:IsA("GuiObject") and object.Selectable and shown(object, built.Instance) then
						last = object
					end
				end
				if last == nil then
					continue
				end
				world.guiService.SelectedObject = last
				local today = math.floor(world.workspace:GetServerTimeNow() / 86400)
				PUSHES[entry.Name](data, today)
				changed:Fire("*")
				world:advance(0.5)
				if Engine.destroyed(last) then
					rebuilt += 1
				end
				local after = world.guiService.SelectedObject
				if after == nil or not after:IsDescendantOf(world.game) then
					table.insert(lines, ("%s: a push rebuilt the list and left the pad on nothing"):format(label))
				end
			end
		end
		if #lines > 0 then
			error(table.concat(lines, "\n"))
		end
		-- Lists were rebuilt under the pad -- the Locker's, the Loadout's, the Quests' -- : this gate checked something.
		expect(rebuilt).toBeGreaterThanOrEqual(3)
	end)
end)

return nil
