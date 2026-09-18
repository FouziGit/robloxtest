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

-- Whitelist for gamepad rebinding. Every button listed here must stay assignable, so none of them may
-- double as the rebind capture cancel (see InputController): a button that cancels can never be bound.
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

-- Keys that abort a pending rebind capture. They must stay OUT of both whitelists above, or the key a
-- player tries to assign would cancel the capture instead of being recorded, which is exactly what
-- ButtonB used to do. tests/Config.spec.luau enforces the disjunction.
--
-- Escape covers keyboard. ButtonA covers gamepad: it is the button that armed the capture by activating
-- the row, so pressing it again cancelling is the behaviour a pad player expects, and it is excluded
-- from AllowedGamepad because the engine owns it for GUI activation. ButtonStart is not usable, it opens
-- the Roblox menu (which cancels through GuiService.MenuOpened anyway).
InputConfig.CaptureCancelKeys = { "Escape", "ButtonA" } :: { string }

-- Touch layout. Pure data: the InputController resolves it to pixels at bind time by measuring the
-- ContextActionService button frame and the engine jump button, so no value here is a fraction of a
-- frame whose size is unknown. ButtonSize / Gap / Margin are px at UIScale 1 (scaled by
-- Theme.scaleFor); Gap is also the free space enforced between two discs, so two centres are never
-- closer than the disc diameter + Gap. MinButtonSize is a floor in raw screen px applied after the
-- scale: these discs are the primary combat controls and no UIScale corrects them, so on a short
-- viewport (scale 0.68) the scaled size would fall under the smallest reliable touch target.
-- JumpReserve is in raw screen px: the bottom-right area kept free for the engine jump button while
-- TouchGui has not built it yet.
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
	MinButtonSize = 44,
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

-- Short labels for the touch discs only. A disc is Touch.MinButtonSize wide, and the full name does not
-- fit one line at that width in every locale: "Corps à corps" (fr action.melee) clips even scaled down
-- to the label's minimum text size. The Settings rows keep the full names. Elements are not here, they
-- use ElementConfig.Glyphs.
InputConfig.ActionShortKeys = {
	Melee = "action.melee.short",
	Dash = "action.dash.short",
	Block = "action.block.short",
	Menu = "action.menu.short",
} :: { [ActionId]: string }

local actionLookup: { [string]: boolean } = {}
for _, action in ipairs(InputConfig.Actions) do
	actionLookup[action] = true
end

function InputConfig.isAction(value: any): boolean
	return type(value) == "string" and actionLookup[value] == true
end

return InputConfig
