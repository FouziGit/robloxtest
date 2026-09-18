--!strict
-- LoadoutScreen: which jutsus the player takes into a fight. The header counts the used slots against
-- the ones the profile owns (ProgressionConfig base + purchased extras) and warns when every slot is
-- taken; the content lists the equipped jutsus, then the whole JutsuConfig roster grouped by element
-- with each entry's combo, stats and state (equipped, equippable or locked by level / by element).
--
-- A click toggles the entry in a local mirror of the list and sends the complete new list through
-- SetLoadout. The server validates it (unlocks, slot count) and pushes the Loadout section back, which
-- re-syncs the mirror: the list shown is always the last one the server accepted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local ElementConfig = require(Shared.Config.ElementConfig)
local JutsuConfig = require(Shared.Config.JutsuConfig)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	OnClose: () -> (),
	OnNavigate: (id: string) -> (),
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type Destroyable = { Destroy: (self: any) -> () }
type JutsuDef = JutsuConfig.JutsuDef
type Entry = { Def: JutsuDef, Lock: TextLabel, Button: Button.Button }

local LoadoutScreen = {}

local OVERLAY_TRANSPARENCY = 0.45
local BUTTON_WIDTH = 150
local NAME_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local LINE_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local ENTRY_ROW_HEIGHT = NAME_HEIGHT + LINE_HEIGHT * 3 + Theme.Sizes.Padding
local STATUS_HEIGHT = Theme.Sizes.TextBody + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2 + STATUS_HEIGHT * 2
local BASE_SLOTS = ProgressionConfig.Loadout.BaseSlots
local MAX_SLOTS = ProgressionConfig.Loadout.MaxSlots
-- Layout bands: the equipped section first, then one band per element.
local EQUIPPED_BASE = 1
local ELEMENT_BASE = 100
local ELEMENT_STRIDE = 100
-- Locale independent separator between combo glyphs (same convention as the HUD combo chips).
local GLYPH_SEPARATOR = " "

-- Dimmed backdrop that also swallows clicks so the world under the menu is not interacted with.
local function makeOverlay(parent: Instance): Frame
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = Theme.Colors.Overlay
	overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Active = true
	overlay.Parent = parent
	return overlay
end

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

local function comboGlyphs(def: JutsuDef): string
	local parts: { string } = {}
	for _, element in ipairs(def.Combo) do
		table.insert(parts, ElementConfig.Glyphs[element :: any] or element)
	end
	return table.concat(parts, GLYPH_SEPARATOR)
end

local function makeStatusLabel(name: string, color: Color3, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, STATUS_HEIGHT)
	label.LayoutOrder = order
	label.Font = Theme.Fonts.Bold
	label.TextSize = Theme.Sizes.TextBody
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

local function makeLine(
	name: string,
	height: number,
	size: number,
	color: Color3,
	bold: boolean,
	order: number,
	parent: Instance
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.LayoutOrder = order
	label.Font = if bold then Theme.Fonts.Bold else Theme.Fonts.Body
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- Left slot of a roster row: name, combo, stats and the lock reason (empty while unlocked).
local function makeEntryLabel(): (Frame, TextLabel, TextLabel, TextLabel, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = "Jutsu"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local name = makeLine("Name", NAME_HEIGHT, Theme.Sizes.TextLarge, Theme.Colors.Text, true, 1, frame)
	local combo = makeLine("Combo", LINE_HEIGHT, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, false, 2, frame)
	local stats = makeLine("Stats", LINE_HEIGHT, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, false, 3, frame)
	local lock = makeLine("Lock", LINE_HEIGHT, Theme.Sizes.TextSmall, Theme.Colors.Danger, false, 4, frame)
	return frame, name, combo, stats, lock
end

function LoadoutScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local equippedTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen
	local entries: { Entry } = {}
	local equipped: { string } = {}
	local firstButton: GuiObject? = nil

	local root = ScreenRoot.new({ Name = "LoadoutScreen", DisplayOrder = Theme.Layers.Screen })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("loadout.title"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	panel:SetHeaderHeight(HEADER_HEIGHT)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Vertical
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = panel.Header

	local slotsLabel = makeStatusLabel("Slots", Theme.Colors.Accent, 1, panel.Header)
	local fullLabel = makeStatusLabel("Full", Theme.Colors.Danger, 2, panel.Header)

	local equippedHeader = ListRow.new({
		Left = t("loadout.equipped"),
		LayoutOrder = EQUIPPED_BASE,
		Name = "EquippedHeader",
		Parent = panel.Content,
	})
	own(trove, equippedHeader)

	----------------------------------------------------------------
	-- Profile reads
	----------------------------------------------------------------

	local function totalSlots(): number
		local data = deps.ClientData.get()
		local extra = if data ~= nil then data.Loadout.ExtraSlots else 0
		return math.clamp(BASE_SLOTS + math.max(0, extra), BASE_SLOTS, MAX_SLOTS)
	end

	local function isUnlocked(data: Types.ProfileData?, def: JutsuDef): boolean
		if data == nil then
			return false
		end
		return table.find(data.Unlocks.Jutsus, def.Id) ~= nil
	end

	local function lockReason(def: JutsuDef): string
		if def.Unlock.Kind == "Level" then
			return t("loadout.locked", { level = def.Unlock.Value or 0 })
		elseif def.Unlock.Kind == "Element" then
			return t("loadout.lockedElement", { element = t(ElementConfig.NameKeys[def.Element :: any]) })
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
			if JutsuConfig.ById[id] ~= nil then
				table.insert(equipped, id)
			end
		end
	end

	----------------------------------------------------------------
	-- Rendering
	----------------------------------------------------------------

	local function renderEquipped()
		equippedTrove:Clean()
		for index, id in ipairs(equipped) do
			local def = JutsuConfig.ById[id]
			if def == nil then
				continue
			end
			local row = ListRow.new({
				Left = t(def.NameKey),
				Right = t("loadout.combo", { combo = comboGlyphs(def) }),
				LayoutOrder = EQUIPPED_BASE + index,
				Name = "Equipped" .. tostring(index),
				Parent = panel.Content,
			})
			own(equippedTrove, row)
		end
	end

	local function renderEntries(data: Types.ProfileData?, full: boolean)
		firstButton = nil
		for _, entry in ipairs(entries) do
			local def = entry.Def
			local isEquipped = table.find(equipped, def.Id) ~= nil
			if not isUnlocked(data, def) then
				entry.Lock.Text = lockReason(def)
				entry.Button:SetText(t("common.locked"))
				entry.Button:SetVariant("Secondary")
				entry.Button:SetDisabled(true)
				continue
			end
			entry.Lock.Text = ""
			if isEquipped then
				entry.Button:SetText(t("loadout.unequip"))
				entry.Button:SetVariant("Danger")
				entry.Button:SetDisabled(false)
			else
				entry.Button:SetText(t("loadout.equip"))
				entry.Button:SetVariant(if full then "Secondary" else "Primary")
				entry.Button:SetDisabled(full)
			end
			-- Gamepad focus goes to the first button the player can actually press.
			if firstButton == nil and not entry.Button:IsDisabled() then
				firstButton = entry.Button.Instance
			end
		end
	end

	local function render()
		local total = totalSlots()
		local full = #equipped >= total
		slotsLabel.Text = t("loadout.slots", { used = #equipped, total = total })
		fullLabel.Text = if full then t("loadout.full") else ""
		renderEquipped()
		renderEntries(deps.ClientData.get(), full)
	end

	----------------------------------------------------------------
	-- Intent
	----------------------------------------------------------------

	-- Toggles the entry in the local mirror and sends the whole list; the server has the last word.
	local function toggle(def: JutsuDef)
		deps.SoundController.play("UiClick")
		local updated: { string } = {}
		local removed = false
		for _, id in ipairs(equipped) do
			if id == def.Id then
				removed = true
			else
				table.insert(updated, id)
			end
		end
		if not removed then
			if #updated >= totalSlots() then
				render() -- every slot is taken: the header says so and nothing is sent
				return
			end
			table.insert(updated, def.Id)
		end
		equipped = updated
		render()
		deps.RemoteClient.fire("SetLoadout", updated)
	end

	----------------------------------------------------------------
	-- Roster
	----------------------------------------------------------------

	for elementIndex, elementId in ipairs(ElementConfig.Order) do
		local base = ELEMENT_BASE + (elementIndex - 1) * ELEMENT_STRIDE
		local header = ListRow.new({
			Left = t(ElementConfig.NameKeys[elementId :: any]),
			LayoutOrder = base,
			Name = elementId .. "Header",
			Parent = panel.Content,
		})
		own(trove, header)

		local offset = 0
		for _, def in ipairs(JutsuConfig.Jutsus) do
			if def.Element ~= elementId then
				continue
			end
			offset += 1
			local frame, name, combo, stats, lock = makeEntryLabel()
			name.Text = t(def.NameKey)
			combo.Text = t("loadout.combo", { combo = comboGlyphs(def) })
			stats.Text = t("loadout.stats", { damage = def.Damage, cost = def.Cost, cooldown = def.Cooldown })
			local button = Button.new({
				Text = t("loadout.equip"),
				Variant = "Secondary",
				Disabled = true,
				Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
				OnClick = function()
					toggle(def)
				end,
			})
			own(trove, button)
			local row = ListRow.new({
				Left = frame,
				Right = button.Instance,
				Height = ENTRY_ROW_HEIGHT,
				LayoutOrder = base + offset,
				Name = def.Id,
				Parent = panel.Content,
			})
			own(trove, row)
			table.insert(entries, { Def = def, Lock = lock, Button = button })
		end
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Loadout" or section == "Unlocks" or section == "Progression" then
			syncEquipped()
			render()
		end
	end)

	syncEquipped()
	render()

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		syncEquipped()
		render()
		root.Instance.Enabled = true
		panel:FocusForGamepad(firstButton)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		panel:ReleaseGamepadFocus()
		root.Instance.Enabled = false
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
