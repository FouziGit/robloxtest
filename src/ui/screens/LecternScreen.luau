--!strict
-- LecternScreen: the Lectern of the hub (docs/GAME_DESIGN.md §9 bis), on the ink band of its chapter (D-147),
-- opened at the Lectern's prompt. Its tabs:
--
--   Drills  the kit's drills, then one recipe drill per glyph (DrillCatalog), each with the best grade the server
--           has paid (three ♦, the grade in words) and the way to begin it: Start, Again once graded, Equip for a
--           glyph that is not in the loadout (it opens the Loadout over this screen), and a locked glyph's level.
--           The set the player is doing heads the list, with the way to put it down. Starting a drill closes the
--           screen: the drill is done on the training dummies, and the server counts it and says every step.
--   Road      the level road (LevelRoadWords): every glyph, the pigment and every milestone to the last level,
--             the next one ringed, what the profile already holds marked as its own.
--   ExLibris  the plates of the Ex-libris (ExLibrisConfig): the ones earned sealed, the others with how far the
--             profile's lifetime measures are, and what each pays.
--
-- Nothing here decides anything: the grades, the milestones, the plates and the running set are the server's (the
-- profile's Drills, Milestones, ExLibris, Stats and Unlocks, and DrillChanged). A tab is built when it is shown, and
-- built again when what it shows moves while the screen is up; a change while the screen is away only marks it for
-- the next opening. The drills and the road are built a chunk at a time, as the page scrolls down to them
-- (Progressive, D-234): a drill for every glyph drew 736 objects where a screen is held to 400
-- (tests/ScreenBudget.spec.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local DrillCatalog = require(Shared.DrillCatalog)
local DrillConfig = require(Shared.Config.DrillConfig)
local DrillLogic = require(Shared.Pure.DrillLogic)
local ExLibris = require(Shared.Pure.ExLibris)
local ExLibrisConfig = require(Shared.Config.ExLibrisConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local LevelRoadWords = require(script.Parent.Parent.LevelRoadWords)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local Pips = require(script.Parent.Parent.components.Pips)
local Progressive = require(script.Parent.Parent.Progressive)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Seal = require(script.Parent.Parent.components.Seal)
local Tabs = require(script.Parent.Parent.components.Tabs)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: {
		fire: (name: string, ...any) -> (),
		on: (name: string, handler: (...any) -> ()) -> any,
	},
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	OnClose: () -> (),
	OnNavigate: (id: string, args: any?) -> (),
	OnBack: () -> (),
	CanGoBack: () -> boolean,
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen, args: any?) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

-- The set its player is doing, as the server tells it (DrillService.Snapshot).
type Running = { Drill: string, Reps: number, Target: number, Misses: number }
type Destroyable = { Destroy: (self: any) -> () }

local LecternScreen = {}

local CHAPTER = "Lectern"
local TAB_ORDER: { string } = { "Drills", "Road", "ExLibris" }
local TAB_KEYS: { [string]: string } =
	{ Drills = "lectern.tab.drills", Road = "lectern.tab.road", ExLibris = "lectern.tab.exlibris" }
local TABS_HEIGHT = 48
local PIP_SIZE = 14
local STEP_SEAL = 40
-- A tab's rows are built this many at a time, as the page scrolls down to them (Progressive): more than a phone's
-- window holds, fewer drill rows than the budget has room for.
local ROWS_CHUNK = 8
local GRADES = DrillConfig.Grades
local PIGMENT_NAME_KEYS = (PigmentConfig.NameKeys :: any) :: { [string]: string? }
local KIT_IDS: { string } = {}
for _, kit in ipairs(DrillConfig.Kit) do
	table.insert(KIT_IDS, kit.Id)
end
-- The profile's sections a tab reads: a push of any of them rebuilds the tab shown.
local WATCHED: { [string]: boolean } = {
	["*"] = true,
	Drills = true,
	Milestones = true,
	Unlocks = true,
	Loadout = true,
	Progression = true,
	ExLibris = true,
	Stats = true,
}

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

function LecternScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local pageTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen
	local current = TAB_ORDER[1]
	local running: Running? = nil
	-- A change arrived while the screen was away: the tab is built afresh at the next opening.
	local stale = true
	local firstButton: GuiObject? = nil

	local root = ScreenRoot.new({
		Name = "LecternScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local function close()
		screen:Close()
		deps.OnClose()
	end

	local panel = Panel.new({
		Title = t("lectern.title"),
		Chapter = CHAPTER,
		Closable = true,
		OnClose = close,
		OnBack = deps.OnBack,
		ShowBack = deps.CanGoBack,
		Localize = deps.Localize,
		Parent = root.Content,
	})
	own(trove, panel)
	root:SetCard(panel)
	-- The tabs carry the touch minimum, which follows the viewport.
	panel:SetHeaderHeight(function()
		return Theme.Sizes.PaddingSmall * 2 + Theme.touchTargetHeight(TABS_HEIGHT)
	end)

	----------------------------------------------------------------
	-- Rows
	----------------------------------------------------------------

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- The shown tab's rows, each built when Progressive comes to it: in order, so each takes the next LayoutOrder.
	local rows: { () -> () } = {}
	local function later(build: () -> ())
		table.insert(rows, build)
	end

	local function header(key: string)
		own(
			pageTrove,
			ListRow.new({
				Variant = "Header",
				Chapter = CHAPTER,
				Left = t(key),
				LayoutOrder = nextOrder(),
				Name = "Section",
				Parent = panel.Content,
			})
		)
	end

	local function button(name: string, text: string, variant: Button.Variant, onClick: (() -> ())?): Button.Button
		local created = Button.new({
			Name = name,
			Text = text,
			Variant = variant,
			Compact = true,
			OnClick = onClick,
		})
		own(pageTrove, created)
		if firstButton == nil and onClick ~= nil then
			firstButton = created.Instance
		end
		return created
	end

	local function stopButton(): Button.Button
		return button("Stop", t("lectern.stop"), "Secondary", function()
			deps.RemoteClient.fire("StopDrill")
		end)
	end

	-- The way to begin `drill`, or why it cannot be begun yet.
	local function actionFor(drill: DrillLogic.Drill, data: Types.ProfileData, best: number): Button.Button
		local set = running
		if set ~= nil and set.Drill == drill.Id then
			return stopButton()
		end
		local glyphId = drill.Glyph
		local def = if glyphId ~= nil then GlyphConfig.byId(glyphId) else nil
		if def ~= nil then
			if table.find(data.Unlocks.Glyphs, def.Id) == nil then
				local locked = button("Locked", t("lectern.start"), "Secondary", nil)
				local level = def.Unlock.Value
				local pigment = PIGMENT_NAME_KEYS[def.Pigment]
				local reason = if def.Unlock.Kind == "Level" and level ~= nil
					then t("loadout.locked", { level = level })
					else t(
						"loadout.lockedPigment",
						{ pigment = if pigment ~= nil then t(pigment) else def.Pigment }
					)
				locked:SetDisabled(true, "Locked", reason)
				return locked
			end
			if table.find(data.Loadout.Slots, def.Id) == nil then
				return button("Equip", t("loadout.equip"), "Secondary", function()
					deps.OnNavigate("Loadout")
				end)
			end
		end
		return button("Start", t(if best > 0 then "lectern.again" else "lectern.start"), "Primary", function()
			deps.RemoteClient.fire("StartDrill", drill.Id)
			close()
		end)
	end

	local function drillRow(drill: DrillLogic.Drill, data: Types.ProfileData)
		local best = data.Drills[drill.Id] or 0
		local grade = GRADES[best]
		local pips = Pips.new(best, DrillLogic.MaxGrade, Theme.Colors.Text, PIP_SIZE)
		own(pageTrove, pips)
		local glyphId = drill.Glyph
		local def = if glyphId ~= nil then GlyphConfig.byId(glyphId) else nil
		own(
			pageTrove,
			ListRow.new({
				Left = t(drill.NameKey),
				Subtitle = t("lectern.drillLine", {
					hint = t(drill.HintKey, { reps = drill.Reps }),
					grade = if grade ~= nil then t(grade.NameKey) else t("lectern.blank"),
				}),
				Leading = pips.Instance,
				Right = actionFor(drill, data, best).Instance,
				Tint = if def ~= nil then Theme.pigmentColor(def.Pigment) else nil,
				LayoutOrder = nextOrder(),
				Name = drill.Id,
				Parent = panel.Content,
			})
		)
	end

	local function renderDrills(data: Types.ProfileData)
		local set = running
		local drill = if set ~= nil then DrillCatalog.ById[set.Drill] else nil
		if set ~= nil and drill ~= nil then
			own(
				pageTrove,
				ListRow.new({
					Variant = "Highlight",
					Left = t("lectern.running", {
						name = t(drill.NameKey),
						count = set.Reps,
						reps = set.Target,
						misses = set.Misses,
					}),
					Right = stopButton().Instance,
					LayoutOrder = nextOrder(),
					Name = "Running",
					Parent = panel.Content,
				})
			)
		end
		later(function()
			header("lectern.kit")
		end)
		for _, entry in ipairs(DrillCatalog.List) do
			if entry.Glyph == nil then
				later(function()
					drillRow(entry, data)
				end)
			end
		end
		later(function()
			header("lectern.recipes")
		end)
		for _, entry in ipairs(DrillCatalog.List) do
			if entry.Glyph ~= nil then
				later(function()
					drillRow(entry, data)
				end)
			end
		end
	end

	local function renderRoad(data: Types.ProfileData)
		local level = data.Progression.Level
		local upcoming = LevelRoadWords.next(data, level)
		own(
			pageTrove,
			ListRow.new({
				Variant = "Header",
				Chapter = CHAPTER,
				Left = t("lectern.road.level", { level = level }),
				LayoutOrder = nextOrder(),
				Name = "Level",
				Parent = panel.Content,
			})
		)
		for _, step in ipairs(LevelRoadWords.Road) do
			later(function()
				local held = LevelRoadWords.holds(data, step)
				local seal = Seal.new({
					Text = tostring(step.Level),
					Fill = if held then Theme.Colors.Primary else Theme.Colors.Chalk,
					Size = STEP_SEAL,
					Face = "Numeric",
				})
				own(pageTrove, seal)
				local kind = if step.Kind == "Glyph"
					then "lectern.road.glyph"
					elseif step.Kind == "Pigment" then "lectern.road.pigment"
					elseif step.Title ~= nil then "lectern.road.titled"
					else "lectern.road.milestone"
				own(
					pageTrove,
					ListRow.new({
						Variant = if step == upcoming then "Highlight" else "Item",
						Left = LevelRoadWords.row(step, t),
						Subtitle = t(kind),
						Leading = seal.Instance,
						Right = if held
							then t("lectern.road.held")
							elseif step == upcoming then t("lectern.road.next")
							else nil,
						LayoutOrder = nextOrder(),
						Name = "Step" .. step.Level .. step.Id,
						Parent = panel.Content,
					})
				)
			end)
		end
	end

	local function renderExLibris(data: Types.ProfileData)
		local facts = ExLibris.facts(data.Stats, data.Drills, KIT_IDS)
		local earned = 0
		for _, plate in ipairs(ExLibrisConfig.Plates) do
			if data.ExLibris[plate.Id] ~= nil then
				earned += 1
			end
		end
		own(
			pageTrove,
			ListRow.new({
				Variant = "Header",
				Chapter = CHAPTER,
				Left = t("lectern.exlibris.count", { count = earned, total = #ExLibrisConfig.Plates }),
				LayoutOrder = nextOrder(),
				Name = "Count",
				Parent = panel.Content,
			})
		)
		for _, plate in ipairs(ExLibrisConfig.Plates) do
			local held = data.ExLibris[plate.Id] ~= nil
			local seal = Seal.new({
				Text = if held then Theme.Glyphs.Check else "",
				Fill = if held then Theme.Colors.Primary else Theme.Colors.Chalk,
				Size = STEP_SEAL,
			})
			own(pageTrove, seal)
			local desc = t(plate.DescKey, { amount = plate.Target })
			own(
				pageTrove,
				ListRow.new({
					Left = t(plate.NameKey),
					Subtitle = if held
						then t("lectern.exlibris.earned", { desc = desc })
						else t("lectern.exlibris.progress", {
							desc = desc,
							count = ExLibris.progress(plate, facts),
							target = plate.Target,
						}),
					Leading = seal.Instance,
					Right = t(
						if plate.Title ~= nil then "lectern.exlibris.rewardTitled" else "reward.folios",
						{ amount = plate.Folios }
					),
					LayoutOrder = nextOrder(),
					Name = plate.Id,
					Parent = panel.Content,
				})
			)
		end
	end

	local function render()
		pageTrove:Clean()
		order = 0
		firstButton = nil
		stale = false
		panel.Content.CanvasPosition = Vector2.zero
		local data = deps.ClientData.get()
		if data == nil then
			own(pageTrove, ListRow.new({ Variant = "Skeleton", Left = "", LayoutOrder = 1, Parent = panel.Content }))
			return
		end
		rows = {}
		if current == "Road" then
			renderRoad(data)
		elseif current == "ExLibris" then
			renderExLibris(data)
		else
			renderDrills(data)
		end
		local shown = rows
		own(
			pageTrove,
			Progressive.new({
				Scroller = panel.Content,
				Count = #shown,
				Chunk = ROWS_CHUNK,
				Build = function(index: number)
					shown[index]()
				end,
			})
		)
	end

	-- A tab chosen by an opening, not by the player: no click.
	local switching = false
	local items: { Tabs.Item } = {}
	for _, id in ipairs(TAB_ORDER) do
		table.insert(items, { Id = id, Text = t(TAB_KEYS[id]) })
	end
	local tabs = Tabs.new({
		Items = items,
		Selected = current,
		Chapter = CHAPTER,
		-- Tabs make no sound of their own (a Button does): the click is the screen's.
		OnSelect = function(id: string)
			if not switching then
				deps.SoundController.play("UiClick")
			end
			current = id
			render()
		end,
		LayoutOrder = 1,
		Parent = panel.Header,
	})
	own(trove, tabs)

	local function refresh()
		if screen.Visible then
			-- A push rebuilds the rows under the pad: it goes on to the tab's first button, or the way out, rather
			-- than onto nothing (E12-S4).
			panel:KeepGamepadFocus(render, function(): GuiObject?
				return firstButton
			end)
		else
			stale = true
		end
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if WATCHED[section] then
			refresh()
		end
	end)
	trove:Add(deps.RemoteClient.on("DrillChanged", function(snapshot: Running?)
		running = snapshot
		refresh()
	end))

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen, args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		local tab = if type(args) == "table" then args.Tab else nil
		if type(tab) == "string" and TAB_KEYS[tab] ~= nil and tab ~= current then
			switching = true
			tabs:Select(tab)
			switching = false
		elseif stale then
			render()
		end
		root:PlayEnter()
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
	end

	local function closeScreen(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		panel:ReleaseGamepadFocus()
		root:PlayExit()
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = closeScreen,
		Destroy = destroy,
	}
	return screen
end

return LecternScreen
