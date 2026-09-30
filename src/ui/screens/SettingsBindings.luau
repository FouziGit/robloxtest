--!strict
-- SettingsBindings: the Keyboard and Gamepad pages of the Settings screen (D-147). A row per action the
-- player may rebind: its name, and its key as a keycap on a pressable sheet. Pressing it asks for the new
-- key (InputController.captureNext): the keycap gives way to a breathing ellipsis, the row is ringed, and
-- the line under the tabs says how to answer -- a key, or Escape to cancel on a keyboard; a button, or A
-- on a pad. "Click" and "Escape" are never said to a pad.
--
-- Every change is saved as it is made: there is no Save button, so nothing is lost by closing. The whole
-- map goes through UpdateKeybinds as soon as the remote's budget allows, one send in flight at a time. The
-- push that holds exactly what was sent confirms it, and the rows that changed flash green; a refusal
-- (SettingsService says settings.saveFailed) puts the rows back to what the server holds. Reset asks first,
-- with the only red confirm of the menus (ConfirmSheet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local ConfirmSheet = require(script.Parent.Parent.components.ConfirmSheet)
local InputConfig = require(Shared.Config.InputConfig)
local KeyButton = require(script.Parent.Parent.components.KeyButton)
local Keycap = require(script.Parent.Parent.components.Keycap)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Rebind = require(Shared.Pure.Rebind)
local Remotes = require(Shared.Remotes)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type BindKind = "Keyboard" | "Gamepad"

export type Props = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: {
		captureNext: (kind: string, callback: (keyName: string?) -> ()) -> (),
		cancelCapture: () -> (),
	},
	-- Every message of the server (HudController.Notified): how a refused save is heard.
	Notified: any?,
	-- Where the rows go, and the card the reset question rises over.
	Content: ScrollingFrame,
	Card: GuiObject,
	SetStatus: (text: string) -> (),
}

export type Bindings = {
	-- Draws the rows of `kind`; they belong to `trove`, the screen's page.
	Build: (self: Bindings, kind: BindKind, trove: any) -> (),
	-- The page is going: a capture in progress and an open question are dropped.
	Leave: (self: Bindings) -> (),
	-- The screen opens: the maps follow the profile again.
	Open: (self: Bindings) -> (),
	-- The footer's Reset: asks, then puts every rebindable key of the page back to its default.
	AskReset: (self: Bindings) -> (),
	Destroy: (self: Bindings) -> (),
}

type Map = Rebind.Map
type Row = { Key: KeyButton.KeyButton, Ring: Frame }

local SettingsBindings = {}

local RING_THICKNESS = 4
-- A row holds its key's lip and the ink around it inside its own outline, as the values' rows do: at the list's
-- 56 the key's rim crossed the row's foot (seen in Studio).
local ROW_HEIGHT = Theme.Sizes.RowHeight + Theme.Sizes.PaddingSmall
local UPDATE_KEYBINDS_RATE = Remotes.Definitions.UpdateKeybinds.Rate
-- Two sends stay one refilled token apart, so rebinding key after key never outruns the remote's bucket
-- (a rate-limited call is dropped, and with it the change).
local MIN_INTERVAL_SECONDS = if UPDATE_KEYBINDS_RATE ~= nil and UPDATE_KEYBINDS_RATE.Refill > 0
	then 1 / UPDATE_KEYBINDS_RATE.Refill
	else Theme.Timing.PendingTimeoutSeconds
local KINDS: { string } = { "Keyboard", "Gamepad" }

-- KINDS holds the two literals the remote and the profile are keyed by; the cast hands them on with their
-- literal type (the pattern of QuestsScreen.asPeriod).
local function asKind(name: string): BindKind
	return (name :: any) :: BindKind
end

-- Config maps are keyed by the ActionId literal union; the screen works with plain string keys.
local function stringMap(map: { [InputConfig.ActionId]: string }): Map
	return (map :: any) :: Map
end

local DEFAULTS: { [string]: Map } = {
	Keyboard = stringMap(InputConfig.DefaultKeyboard),
	Gamepad = stringMap(InputConfig.DefaultGamepad),
}
local ALLOWED: { [string]: { [string]: boolean } } = {
	Keyboard = InputConfig.AllowedKeyboard,
	Gamepad = InputConfig.AllowedGamepad,
}
local ACTION_NAME_KEYS = stringMap(InputConfig.ActionNameKeys)
local ACTIONS = (InputConfig.Actions :: any) :: { string }
local REBINDABLE_LIST = (InputConfig.Rebindable :: any) :: { string }
local REBINDABLE: { [string]: boolean } = {}
for _, action in ipairs(REBINDABLE_LIST) do
	REBINDABLE[action] = true
end

function SettingsBindings.new(props: Props): Bindings
	local trove = Trove.new()
	local t = props.Localize.t
	local pending: { [string]: Map } = { Keyboard = {}, Gamepad = {} }
	-- A kind whose edits the server has not confirmed yet: a push does not overwrite it.
	local dirty: { [string]: boolean } = { Keyboard = false, Gamepad = false }
	-- Kinds with an edit still to send, the one in flight and what it carried, and the actions whose
	-- rows flash when it is confirmed.
	local waiting: { [string]: boolean } = { Keyboard = false, Gamepad = false }
	local inFlight: BindKind? = nil
	local sent: Map? = nil
	local sentToken = 0
	local lastSentAt = -math.huge
	local sendTimer: thread? = nil
	local changed: { [string]: { [string]: boolean } } = { Keyboard = {}, Gamepad = {} }
	local shownKind: BindKind? = nil
	local rows: { [string]: Row } = {}
	local capturing: string? = nil
	local sheet: ConfirmSheet.ConfirmSheet? = nil

	local function actionName(action: string): string
		local key: string? = ACTION_NAME_KEYS[action]
		return if key ~= nil then t(key) else action
	end

	-- What the profile holds for `kind`, every action filled (by default where the profile has none).
	local function stored(kind: BindKind): Map
		local data = props.ClientData.get()
		local saved: Types.KeybindMap? = if data == nil
			then nil
			elseif kind == "Keyboard" then data.Settings.Keyboard
			else data.Settings.Gamepad
		local map: Map = {}
		for _, action in ipairs(ACTIONS) do
			local key: string? = if saved ~= nil then saved[action] else nil
			map[action] = key or DEFAULTS[kind][action]
		end
		return map
	end

	local function refreshKeys()
		local kind: BindKind? = shownKind
		if kind == nil then
			return
		end
		for action, row in pairs(rows) do
			row.Key:SetKey(pending[kind][action])
		end
	end

	local function sync(kind: BindKind)
		pending[kind] = stored(kind)
		dirty[kind] = false
		changed[kind] = {}
		if shownKind == kind then
			refreshKeys()
		end
	end

	----------------------------------------------------------------
	-- Saving as the player goes
	----------------------------------------------------------------

	local trySend: () -> ()

	-- The server did not take the map, or never answered: the rows go back to what it holds.
	local function refused(kind: BindKind)
		inFlight = nil
		sent = nil
		waiting[kind] = false
		sync(kind)
		props.SetStatus(t("settings.saveFailed"))
		trySend()
	end

	trySend = function()
		if inFlight ~= nil or sendTimer ~= nil then
			return
		end
		local kind: BindKind? = nil
		for _, name in ipairs(KINDS) do
			local candidate: BindKind = asKind(name)
			if waiting[candidate] then
				kind = candidate
				break
			end
		end
		if kind == nil then
			return
		end
		-- Without a loaded profile the server refuses the save and pushes nothing back.
		if props.ClientData.get() == nil then
			waiting[kind] = false
			props.SetStatus(t("settings.saveFailed"))
			return
		end
		local wait = MIN_INTERVAL_SECONDS - (os.clock() - lastSentAt)
		if wait > 0 then
			sendTimer = task.delay(wait, function()
				sendTimer = nil
				trySend()
			end)
			return
		end
		local map = table.clone(pending[kind])
		waiting[kind] = false
		inFlight = kind
		sent = map
		lastSentAt = os.clock()
		sentToken += 1
		local token = sentToken
		props.RemoteClient.fire("UpdateKeybinds", kind, table.clone(map))
		-- A send that is neither confirmed nor refused in time is not waited on forever.
		task.delay(Theme.Timing.PendingTimeoutSeconds, function()
			if inFlight == kind and sentToken == token then
				refused(kind)
			end
		end)
	end
	trove:Add(function()
		local timer = sendTimer
		if timer ~= nil then
			task.cancel(timer)
		end
		sentToken += 1
	end)

	-- Keeps `updated` as the map of `kind` and sends it; `actions` flash once the server holds it.
	local function commit(kind: BindKind, updated: Map, actions: { string })
		pending[kind] = updated
		dirty[kind] = true
		for _, action in ipairs(actions) do
			changed[kind][action] = true
		end
		refreshKeys()
		waiting[kind] = true
		trySend()
	end

	-- A push: the one that holds what was sent confirms it; any other leaves the send waiting (an audio
	-- change pushes the same section). Kinds with nothing unconfirmed follow the profile.
	trove:Connect(props.ClientData.Changed, function(section: string)
		if section ~= "*" and section ~= "Settings" then
			return
		end
		local kind: BindKind? = inFlight
		local map = sent
		if kind ~= nil and map ~= nil and Rebind.same(stored(kind), map, ACTIONS) then
			inFlight = nil
			sent = nil
			if not waiting[kind] then
				dirty[kind] = false
			end
			if shownKind == kind then
				for action in pairs(changed[kind]) do
					local row = rows[action]
					if row ~= nil then
						row.Key:Flash()
					end
				end
			end
			changed[kind] = {}
			props.SetStatus(t("settings.saved"))
		end
		for _, name in ipairs(KINDS) do
			local other: BindKind = asKind(name)
			if not dirty[other] and inFlight ~= other then
				sync(other)
			end
		end
		trySend()
	end)

	if props.Notified ~= nil then
		trove:Connect(props.Notified, function(key: string)
			local kind: BindKind? = inFlight
			if key == "settings.saveFailed" and kind ~= nil then
				refused(kind)
			end
		end)
	end

	----------------------------------------------------------------
	-- Capturing a key
	----------------------------------------------------------------

	local function setCapturing(action: string?, on: boolean)
		if action == nil then
			return
		end
		local row = rows[action]
		if row ~= nil then
			row.Key:SetCapturing(on)
			row.Ring.Visible = on
		end
	end

	local function hint(kind: BindKind): string
		return t(if kind == "Gamepad" then "settings.hint.gamepad" else "settings.hint")
	end

	local function finishCapture(kind: BindKind, action: string, key: string?)
		capturing = nil
		setCapturing(action, false)
		local result: Rebind.Result, updated: Map, holder: string? =
			Rebind.apply(pending[kind], action, key, ALLOWED[kind], REBINDABLE)
		local shown = if key ~= nil then Keycap.label(key, props.Localize) else ""
		if result == "Cancelled" then
			props.SetStatus(t("settings.captureCancelled"))
		elseif result == "NotAllowed" then
			props.SetStatus(t("settings.keyNotAllowed", { key = shown }))
		elseif result == "Duplicate" then
			props.SetStatus(t("settings.duplicate", { key = shown }))
		elseif result == "Swapped" and holder ~= nil then
			commit(kind, updated, { action, holder })
			props.SetStatus(t("settings.swapped", { a = actionName(action), b = actionName(holder) }))
		elseif result == "Bound" then
			commit(kind, updated, { action })
			props.SetStatus(t("settings.bound", { action = actionName(action), key = shown }))
		else
			props.SetStatus(t("settings.bound", { action = actionName(action), key = shown }))
		end
	end

	-- Drops a capture in progress. InputController.cancelCapture does not fire the pending callback, so the
	-- row is restored here and rebinding stays usable.
	local function abortCapture()
		local action = capturing
		if action == nil then
			return
		end
		capturing = nil
		setCapturing(action, false)
		props.InputController.cancelCapture()
	end

	local function beginCapture(kind: BindKind, action: string)
		if capturing ~= nil then
			-- Tapping the ringed key again cancels: a touch screen has no Escape, and the Roblox menu button
			-- closes the whole screen.
			if capturing == action then
				abortCapture()
				props.SetStatus(t("settings.captureCancelled"))
			end
			return
		end
		capturing = action
		setCapturing(action, true)
		local prompt = if kind == "Gamepad" then "settings.pressButton" else "settings.pressKey"
		props.SetStatus(t(prompt, { action = actionName(action) }))
		props.InputController.captureNext(kind, function(keyName: string?)
			if capturing ~= action then
				return -- the page was left or the screen closed meanwhile
			end
			finishCapture(kind, action, keyName)
		end)
	end

	----------------------------------------------------------------
	-- Reset
	----------------------------------------------------------------

	local function closeSheet()
		local open = sheet
		sheet = nil
		if open ~= nil then
			open:Close()
		end
	end
	trove:Add(function()
		local open = sheet
		sheet = nil
		if open ~= nil then
			open:Destroy()
		end
	end)

	local function reset()
		local kind: BindKind? = shownKind
		if kind == nil then
			return
		end
		local defaults = Rebind.reset(pending[kind], DEFAULTS[kind], REBINDABLE_LIST)
		local moved: { string } = {}
		for _, action in ipairs(REBINDABLE_LIST) do
			if defaults[action] ~= pending[kind][action] then
				table.insert(moved, action)
			end
		end
		if #moved > 0 then
			commit(kind, defaults, moved)
		end
	end

	local function askReset(_self: Bindings)
		if sheet ~= nil or shownKind == nil then
			return
		end
		abortCapture()
		sheet = ConfirmSheet.new({
			Title = t("common.reset"),
			Body = t("settings.resetConfirm"),
			-- The one red confirm of the menus: it wipes what the player chose.
			Confirm = { Text = t("common.reset"), Variant = "Danger" },
			Cancel = { Text = t("common.cancel") },
			OnConfirm = function()
				closeSheet()
				reset()
			end,
			OnCancel = closeSheet,
			Parent = props.Card,
		})
	end

	----------------------------------------------------------------
	-- The page
	----------------------------------------------------------------

	local function build(_self: Bindings, kind: BindKind, page: any)
		shownKind = kind
		rows = {}
		page:Add(function()
			if shownKind == kind then
				shownKind = nil
				rows = {}
			end
		end)
		for index, action in ipairs(REBINDABLE_LIST) do
			local key = KeyButton.new({
				Key = pending[kind][action],
				Device = kind,
				Localize = props.Localize,
				WaitingText = t("settings.capturing"),
				OnClick = function()
					beginCapture(kind, action)
				end,
			})
			page:Add(function()
				key:Destroy()
			end)
			local row = ListRow.new({
				Left = actionName(action),
				Right = key.Instance,
				Height = ROW_HEIGHT,
				LayoutOrder = index,
				Name = action,
				Parent = props.Content,
			})
			page:Add(function()
				row:Destroy()
			end)
			-- Ringed in the primary yellow while it waits for its key.
			local ring = Instance.new("Frame")
			ring.Name = "Capturing"
			ring.BackgroundTransparency = 1
			ring.Size = UDim2.fromScale(1, 1)
			ring.ZIndex = 4
			ring.Visible = false
			Theme.corner(ring, Theme.Sizes.CornerCard)
			Theme.stroke(ring, "Primary", RING_THICKNESS)
			ring.Parent = row.Instance
			rows[action] = { Key = key, Ring = ring }
		end
		props.SetStatus(hint(kind))
	end

	local function leave(_self: Bindings)
		abortCapture()
		closeSheet()
	end

	local function open(_self: Bindings)
		abortCapture()
		for _, name in ipairs(KINDS) do
			local kind: BindKind = asKind(name)
			if not dirty[kind] then
				sync(kind)
			end
		end
	end

	for _, name in ipairs(KINDS) do
		local kind: BindKind = asKind(name)
		sync(kind)
	end

	local function destroy(_self: Bindings)
		capturing = nil
		trove:Destroy()
	end

	return {
		Build = build,
		Leave = leave,
		Open = open,
		AskReset = askReset,
		Destroy = destroy,
	}
end

return SettingsBindings
