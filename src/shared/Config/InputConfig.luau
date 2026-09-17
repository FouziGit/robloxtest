--!strict
-- Input bindings. Pure data (Enum names as strings) so it loads under Lune and can be validated.
-- Keyboard defaults avoid movement keys on QWERTY (W A S D) and AZERTY (Z Q S D), Space (jump),
-- and Roblox-reserved keys (I/O zoom, Tab leaderboard, Esc menu, digits = backpack).

export type ActionId = "Fire" | "Water" | "Earth" | "Wind" | "Lightning" | "Melee" | "Dash" | "Block" | "Menu"

local InputConfig = {}

InputConfig.Actions =
	{ "Fire", "Water", "Earth", "Wind", "Lightning", "Melee", "Dash", "Block", "Menu" } :: { ActionId }

-- Actions the player may rebind (Menu stays fixed so the settings screen is always reachable).
InputConfig.Rebindable = { "Fire", "Water", "Earth", "Wind", "Lightning", "Melee", "Dash", "Block" } :: { ActionId }

-- Enum.KeyCode names, or "MouseButton1" / "MouseButton2" (Enum.UserInputType) for mouse.
InputConfig.DefaultKeyboard = {
	Fire = "J",
	Water = "K",
	Earth = "L",
	Wind = "H",
	Lightning = "U",
	Melee = "MouseButton1",
	Dash = "LeftShift",
	Block = "F",
	Menu = "M",
} :: { [ActionId]: string }

-- Enum.KeyCode names for gamepad buttons. ButtonA (jump) and ButtonStart (Roblox menu) are reserved.
InputConfig.DefaultGamepad = {
	Fire = "DPadUp",
	Water = "DPadRight",
	Earth = "DPadDown",
	Wind = "DPadLeft",
	Lightning = "ButtonY",
	Melee = "ButtonX",
	Dash = "ButtonB",
	Block = "ButtonL2",
	Menu = "ButtonSelect",
} :: { [ActionId]: string }

-- Whitelist for keyboard rebinding (validated on the server).
InputConfig.AllowedKeyboard = {} :: { [string]: boolean }
do
	local excluded: { [string]: boolean } =
		{ A = true, D = true, S = true, W = true, Z = true, Q = true, I = true, O = true }
	for byte = 65, 90 do
		local letter = string.char(byte)
		if not excluded[letter] then
			InputConfig.AllowedKeyboard[letter] = true
		end
	end
	for _, name in ipairs({
		"F1",
		"F2",
		"F3",
		"F4",
		"F5",
		"F6",
		"F7",
		"F8",
		"LeftShift",
		"RightShift",
		"LeftControl",
		"RightControl",
		"LeftAlt",
		"RightAlt",
		"MouseButton1",
		"MouseButton2",
		"MouseButton3",
	}) do
		InputConfig.AllowedKeyboard[name] = true
	end
end

-- Whitelist for gamepad rebinding.
InputConfig.AllowedGamepad = {
	DPadUp = true,
	DPadDown = true,
	DPadLeft = true,
	DPadRight = true,
	ButtonB = true,
	ButtonX = true,
	ButtonY = true,
	ButtonL1 = true,
	ButtonR1 = true,
	ButtonL2 = true,
	ButtonR2 = true,
	ButtonL3 = true,
	ButtonR3 = true,
	ButtonSelect = true,
} :: { [string]: boolean }

-- Touch layout: ContextActionService button positions (fractions of the touch area, right thumb cluster).
InputConfig.Touch = {
	ButtonSize = 64, -- px at UIScale 1
	Positions = {
		Fire = { X = 0.62, Y = 0.30 },
		Water = { X = 0.80, Y = 0.22 },
		Earth = { X = 0.80, Y = 0.52 },
		Wind = { X = 0.62, Y = 0.60 },
		Lightning = { X = 0.71, Y = 0.41 },
		Melee = { X = 0.90, Y = 0.72 },
		Dash = { X = 0.50, Y = 0.78 },
		Block = { X = 0.72, Y = 0.82 },
		Menu = { X = 0.96, Y = 0.05 },
	},
}

-- Names of Strings keys for action labels.
InputConfig.ActionNameKeys = {
	Fire = "element.fire",
	Water = "element.water",
	Earth = "element.earth",
	Wind = "element.wind",
	Lightning = "element.lightning",
	Melee = "action.melee",
	Dash = "action.dash",
	Block = "action.block",
	Menu = "action.menu",
} :: { [ActionId]: string }

local actionLookup: { [string]: boolean } = {}
for _, action in ipairs(InputConfig.Actions) do
	actionLookup[action] = true
end

function InputConfig.isAction(value: any): boolean
	return type(value) == "string" and actionLookup[value] == true
end

return InputConfig
