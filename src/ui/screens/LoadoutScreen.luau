--!strict
-- LoadoutScreen: which glyphs the player takes into a fight, on the ink band of the Loadout chapter with its
-- five-pigment stripe (D-147). Across the top, the socket bar: one socket per slot the player may fill,
-- holding the equipped glyphs in their order (tap one to take it off), the free ones empty, and the ones
-- a pass would open locked; beside it the count, and -- only here, where a full loadout is felt -- the
-- offer of four more slots. Under it, the tabs: what is equipped, then one tab per pigment with its sigil
-- and its colour, so no page is the whole roster. The page is a grid of GlyphCards: each glyph's recipe as
-- the player presses it, its numbers, its lore, and Equip, Unequip, "Slots full" or why it is locked.
--
-- A change toggles the glyph in a local mirror of the list (LoadoutEdit) and sends the complete new list
-- through SetLoadout. The server validates it and pushes the Loadout section back, which re-syncs the
-- mirror: the list shown is always the last one the server accepted. After each change a strip rises from
-- the foot of the card for a few seconds, saying what changed, with the way to undo it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local GlyphCard = require(script.Parent.Parent.components.GlyphCard)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local ListRow = require(script.Parent.Parent.components.ListRow)
local LoadoutEdit = require(Shared.Pure.LoadoutEdit)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Panel = require(script.Parent.Parent.components.Panel)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local SocketBar = require(script.Parent.Parent.components.SocketBar)
local Tabs = require(script.Parent.Parent.components.Tabs)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)
local UndoStrip = require(script.Parent.Parent.components.UndoStrip)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	OnClose: () -> (),
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

type Destroyable = { Destroy: (self: any) -> () }
type GlyphDef = GlyphConfig.GlyphDef

local LoadoutScreen = {}

local CHAPTER = "Loadout"
local EQUIPPED_TAB = "Equipped"
local PASS_KEY = "LoadoutSlots"
local BASE_SLOTS = ProgressionConfig.Loadout.BaseSlots
-- The bar always shows every slot a pass could open, so the locked ones say what there is to get.
local SHOWN_SOCKETS = ProgressionConfig.Loadout.MaxSlots
local TABS_HEIGHT = 48
-- A glyph card: its band, its recipe, its numbers, two lines of lore and the action, on a lip.
local CARD_HEIGHT = 250
local COLUMNS_POINTER = 3
local COLUMNS_TOUCH = 2
local SKELETON_CELLS = 3

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

function LoadoutScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local tabTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen
	local equipped: { string } = {}
	local currentTab = EQUIPPED_TAB
	local cards: { [string]: GlyphCard.GlyphCard } = {}
	-- The equipped list the Equipped tab was built from: that tab is rebuilt when the list changes.
	local builtSignature: string? = nil
	local device: GlyphCard.Device = GlyphCard.device()
	local firstButton: GuiObject? = nil

	local root = ScreenRoot.new({
		Name = "LoadoutScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("loadout.title"),
		Chapter = CHAPTER,
		ContentMode = "Grid",
		GridCell = UDim2.new(
			1 / (if Theme.touchOnly() then COLUMNS_TOUCH else COLUMNS_POINTER),
			-Theme.Sizes.Gap,
			0,
			CARD_HEIGHT
		),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		OnBack = deps.OnBack,
		ShowBack = deps.CanGoBack,
		Localize = deps.Localize,
		Parent = root.Content,
	})
	own(trove, panel)
	root:SetCard(panel)
	-- The sockets row and the tabs both carry the touch minimum, which follows the viewport.
	panel:SetHeaderHeight(function()
		return Theme.Sizes.PaddingSmall * 2
			+ Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
			+ Theme.Sizes.Gap
			+ Theme.touchTargetHeight(TABS_HEIGHT)
	end)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Vertical
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	----------------------------------------------------------------
	-- The socket bar, the count and the offer
	----------------------------------------------------------------

	local socketRow = Instance.new("Frame")
	socketRow.Name = "Sockets"
	socketRow.BackgroundTransparency = 1
	socketRow.Size = UDim2.new(1, 0, 0, Theme.touchTargetHeight(Theme.Sizes.ButtonHeight))
	socketRow.LayoutOrder = 1
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	rowLayout.Parent = socketRow
	socketRow.Parent = panel.Header
	trove:Add(Theme.bindScale(function()
		socketRow.Size = UDim2.new(1, 0, 0, Theme.touchTargetHeight(Theme.Sizes.ButtonHeight))
	end))

	-- The bar takes what the count and the offer leave. A tap on an equipped glyph takes it off: wired below,
	-- once the toggle exists.
	local toggleById: (id: string) -> ()
	local sockets = SocketBar.new({
		OnSocket = function(id: string)
			toggleById(id)
		end,
		LayoutOrder = 1,
		Parent = socketRow,
	})
	own(trove, sockets)
	local socketFill = Instance.new("UIFlexItem")
	socketFill.FlexMode = Enum.UIFlexMode.Fill
	socketFill.Parent = sockets.Instance

	local slotsLabel = Instance.new("TextLabel")
	slotsLabel.Name = "Count"
	slotsLabel.BackgroundTransparency = 1
	slotsLabel.AutomaticSize = Enum.AutomaticSize.X
	slotsLabel.Size = UDim2.fromScale(0, 1)
	slotsLabel.LayoutOrder = 2
	slotsLabel.FontFace = Theme.Fonts.Numeric
	slotsLabel.TextSize = Theme.Sizes.NumSmall
	slotsLabel.TextColor3 = Theme.Colors.Text
	slotsLabel.Text = ""
	slotsLabel.Parent = socketRow

	-- The offer of more slots lives here and nowhere else (docs/ECONOMY.md §5: a full loadout is where it
	-- is wanted). The server prompts; the button only asks.
	local moreSlots = Button.new({
		Name = "MoreSlots",
		Text = t("loadout.moreSlots", { count = ProgressionConfig.Loadout.PassExtraSlots }),
		Variant = "Premium",
		LayoutOrder = 3,
		Parent = socketRow,
		OnClick = function()
			deps.RemoteClient.fire("PromptPurchase", "Pass", PASS_KEY)
		end,
	})
	own(trove, moreSlots)
	-- Greyed while the pass has no id to sell (MonetizationConfig), like every offer in the Shop.
	moreSlots:SetDisabled(MonetizationConfig.Passes[PASS_KEY].Id == 0)

	----------------------------------------------------------------
	-- Profile reads
	----------------------------------------------------------------

	-- The number the server decided, not a second copy of the rule. Recomputing it here could not express
	-- an account that holds the whole roster, and would drift the day the rule changes.
	local function totalSlots(): number
		local data = deps.ClientData.get()
		local limit = if data ~= nil then data.Loadout.SlotLimit else nil
		if type(limit) ~= "number" or limit < 1 then
			return BASE_SLOTS
		end
		return math.floor(limit)
	end

	local function isUnlocked(data: Types.ProfileData?, def: GlyphDef): boolean
		if data == nil then
			return false
		end
		return table.find(data.Unlocks.Glyphs, def.Id) ~= nil
	end

	local function lockReason(def: GlyphDef): string
		if def.Unlock.Kind == "Level" then
			return t("loadout.locked", { level = def.Unlock.Value or 0 })
		elseif def.Unlock.Kind == "Pigment" then
			return t("loadout.lockedPigment", { pigment = t(PigmentConfig.NameKeys[def.Pigment :: any]) })
		end
		return t("common.locked")
	end

	local function syncEquipped()
		local data = deps.ClientData.get()
		equipped = {}
		if data == nil then
			return
		end
		for _, id in ipairs(data.Loadout.Slots) do
			if GlyphConfig.ById[id] ~= nil then
				table.insert(equipped, id)
			end
		end
	end

	-- The keys each pigment is bound to on the device in hand, from the player's own settings.
	local function bindingsFor(kind: GlyphCard.Device): { [string]: string }
		local data = deps.ClientData.get()
		return GlyphCard.bindings(if data ~= nil then data.Settings else nil, kind)
	end

	----------------------------------------------------------------
	-- Intent: a change, and the way to undo it
	----------------------------------------------------------------

	local render: () -> ()

	local undoStrip = UndoStrip.new({ ActionText = t("common.undo"), Parent = panel.Instance })
	own(trove, undoStrip)

	-- What changed, and the way back to the list before it.
	local function showUndo(outcome: LoadoutEdit.Outcome, def: GlyphDef, previous: { string })
		local key = if outcome == "Equipped" then "loadout.equippedToast" else "loadout.unequippedToast"
		undoStrip:Show(t(key, { name = t(def.NameKey) }), function()
			equipped = previous
			render()
			deps.RemoteClient.fire("SetLoadout", previous)
		end)
	end

	-- A full loadout refuses: the socket bar shakes, and nothing is sent.
	local function refuse()
		sockets:Shake()
	end

	-- Toggles the glyph in the local mirror and sends the whole list; the server has the last word.
	local function toggle(def: GlyphDef)
		local previous = table.clone(equipped)
		local updated: { string }, outcome: LoadoutEdit.Outcome = LoadoutEdit.toggle(equipped, def.Id, totalSlots())
		if outcome == "Full" then
			refuse()
			return
		end
		equipped = updated
		render()
		deps.RemoteClient.fire("SetLoadout", updated)
		showUndo(outcome, def, previous)
	end

	toggleById = function(id: string)
		local def = GlyphConfig.ById[id]
		if def ~= nil then
			toggle(def)
		end
	end

	----------------------------------------------------------------
	-- Rendering
	----------------------------------------------------------------

	local function signatureOf(list: { string }): string
		return table.concat(list, "|")
	end

	-- The glyphs of the open tab: the equipped ones in their slots' order, or one pigment's in the roster's.
	local function tabGlyphs(): { GlyphDef }
		local defs: { GlyphDef } = {}
		if currentTab == EQUIPPED_TAB then
			for _, id in ipairs(equipped) do
				table.insert(defs, GlyphConfig.ById[id])
			end
		else
			for _, def in ipairs(GlyphConfig.Glyphs) do
				if def.Pigment == currentTab then
					table.insert(defs, def)
				end
			end
		end
		return defs
	end

	local function buildTab()
		tabTrove:Clean()
		cards = {}
		builtSignature = signatureOf(equipped)
		panel.Content.CanvasPosition = Vector2.zero
		if deps.ClientData.get() == nil then
			-- No profile yet: chalk where the cards will be.
			for index = 1, SKELETON_CELLS do
				own(
					tabTrove,
					ListRow.new({ Variant = "Skeleton", Left = "", LayoutOrder = index, Parent = panel.Content })
				)
			end
			return
		end
		local bindings = bindingsFor(device)
		for index, def in ipairs(tabGlyphs()) do
			local card = GlyphCard.new({
				Def = def,
				Localize = deps.Localize,
				Bindings = bindings,
				Device = device,
				OnAction = function()
					toggle(def)
				end,
				OnRefused = refuse,
				LayoutOrder = index,
				Parent = panel.Content,
			})
			own(tabTrove, card)
			cards[def.Id] = card
		end
	end

	local function renderCards()
		local data = deps.ClientData.get()
		local full = #equipped >= totalSlots()
		firstButton = nil
		for index, def in ipairs(tabGlyphs()) do
			local card = cards[def.Id]
			if card == nil then
				continue
			end
			local state: LoadoutEdit.CardState =
				LoadoutEdit.cardState(isUnlocked(data, def), table.find(equipped, def.Id) ~= nil, full)
			card:SetState(state, if state == "Locked" then lockReason(def) else nil)
			-- Gamepad focus goes to the first card the player can act on.
			if firstButton == nil and (state == "Available" or state == "Equipped") then
				firstButton = card.Button.Instance
			end
			card.Instance.LayoutOrder = index
		end
	end

	-- A change rebuilds the sockets and, on the Equipped tab, the cards: the pad goes on to the first card the
	-- player can act on when what it was on went with them.
	render = function()
		panel:KeepGamepadFocus(function()
			local data = deps.ClientData.get()
			slotsLabel.Text = t("loadout.slots", { used = #equipped, total = totalSlots() })
			-- Offered until the pass is owned.
			moreSlots.Instance.Visible = data ~= nil and data.Passes[PASS_KEY] ~= true
			sockets:Set(LoadoutEdit.sockets(equipped, totalSlots(), SHOWN_SOCKETS))
			local stale = next(cards) == nil and data ~= nil
			if stale or (currentTab == EQUIPPED_TAB and builtSignature ~= signatureOf(equipped)) then
				buildTab()
			end
			renderCards()
		end, function()
			return firstButton
		end)
	end

	----------------------------------------------------------------
	-- Tabs
	----------------------------------------------------------------

	local tabItems: { Tabs.Item } = { { Id = EQUIPPED_TAB, Text = t("loadout.equipped") } }
	for _, pigment in ipairs(PigmentConfig.Order) do
		local id: string = pigment
		local sigil: string = (PigmentConfig.Sigils :: any)[id]
		table.insert(tabItems, {
			Id = id,
			Text = sigil .. " " .. t((PigmentConfig.NameKeys :: any)[id]),
			Tint = Theme.pigmentColor(id),
		})
	end
	local tabs = Tabs.new({
		Items = tabItems,
		Selected = currentTab,
		Chapter = CHAPTER,
		LayoutOrder = 2,
		Parent = panel.Header,
		-- Tabs make no sound of their own (a Button does): the click is the screen's.
		OnSelect = function(id: string)
			deps.SoundController.play("UiClick")
			currentTab = id
			buildTab()
			renderCards()
		end,
	})
	own(trove, tabs)

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Loadout" or section == "Unlocks" or section == "Progression" then
			syncEquipped()
			render()
		elseif section == "Passes" then
			render()
		elseif section == "Settings" then
			local bindings = bindingsFor(device)
			for _, card in pairs(cards) do
				card:SetRecipe(bindings, device)
			end
		end
	end)

	-- The recipes follow the hand: a player who picks up a pad sees its buttons.
	trove:Connect(UserInputService.LastInputTypeChanged, function()
		local latest: GlyphCard.Device = GlyphCard.device()
		if latest == device then
			return
		end
		device = latest
		local bindings = bindingsFor(device)
		for _, card in pairs(cards) do
			card:SetRecipe(bindings, device)
		end
	end)

	syncEquipped()
	buildTab()
	render()

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		syncEquipped()
		render()
		root:PlayEnter()
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		-- Off at once: the card fades as one piece, and a group inside it would be a group in a group.
		undoStrip:Hide(false)
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
		Close = close,
		Destroy = destroy,
	}
	return screen
end

return LoadoutScreen
