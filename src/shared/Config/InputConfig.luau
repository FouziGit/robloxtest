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

-- Touch layout. Pure data: the InputController resolves it to pixels at bind time by measuring the
-- ContextActionService button frame and the engine jump button, so no value here is a fraction of a
-- frame whose size is unknown. ButtonSize / Gap / Margin are px at UIScale 1 (scaled by
-- Theme.scaleFor); Gap is also the free space enforced between two discs, so two centres are never
-- closer than ButtonSize + Gap. JumpReserve is in raw screen px: the bottom-right area kept free for
-- the engine jump button while TouchGui has not built it yet.
-- Anchors, resolved in this order so the first placed keeps its spot:
--   "TopRight" — safe-area top-right corner, away from both thumbs (menu, never a mis-tap in a fight).
--   "JumpRow"  — bottom row left of the jump button; Step 1 is the nearest disc, one step per unit.
--   "Cluster"  — element ring above and left of the jump button; Angle is in degrees counter-clockwise
--                from the +X axis, nil places the disc at the ring centre.
export type TouchAnchor = "TopRight" | "JumpRow" | "Cluster"
export type TouchPlacement = { Anchor: TouchAnchor, Angle: number?, Step: number? }

local touchPositions: { [ActionId]: TouchPlacement } = {
	Fire = { Anchor = "Cluster", Angle = 135 },
	Water = { Anchor = "Cluster", Angle = 45 },
	Earth = { Anchor = "Cluster", Angle = -45 },
	Wind = { Anchor = "Cluster", Angle = -135 },
	Lightning = { Anchor = "Cluster" },
	Melee = { Anchor = "JumpRow", Step = 1 },
	Block = { Anchor = "JumpRow", Step = 2 },
	Dash = { Anchor = "JumpRow", Step = 3 },
	Menu = { Anchor = "TopRight" },
}

InputConfig.Touch = {
	ButtonSize = 64,
	Gap = 14,
	Margin = 16,
	JumpReserve = { Width = 150, Height = 150 },
	Positions = touchPositions,
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
