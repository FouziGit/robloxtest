--!strict
-- The HUD's bottom stack, run (tests/engine.luau): the real ScreenRoot, ComboRow, CombatDock and Hotbar, built
-- in the order HudController.buildBottomStack builds them, and asked what the engine paints over what.
--
-- The refusal pill ("Not enough ink", "On cooldown", "No glyph matches" -- no longer toasts) hangs from the
-- bottom of the combo row onto whatever stands under it. The row came first in the stack and the dock and the
-- hotbar after it at the same ZIndex, so under ZIndexBehavior.Sibling they painted over the whole row, pill
-- included: the dock's plate hid its words on a phone, the hotbar's slots with a pointer.
local Engine = require("./engine")
local Harness = require("./harness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- The chain from the root down to `object`.
local function chain(object: any): { any }
	local path = {}
	local current = object
	while current ~= nil do
		table.insert(path, 1, current)
		current = current.Parent
	end
	return path
end

-- Whether the engine paints `a` over `b` in a ScreenGui whose ZIndexBehavior is Sibling: where their chains
-- part, the higher ZIndex wins, and at the same ZIndex the later sibling; a descendant paints over its
-- ancestor.
local function paintsOver(a: any, b: any): boolean
	local pathA, pathB = chain(a), chain(b)
	local depth = 1
	while pathA[depth] ~= nil and pathA[depth] == pathB[depth] do
		depth += 1
	end
	local branchA, branchB = pathA[depth], pathB[depth]
	if branchA == nil then
		return false
	elseif branchB == nil then
		return true
	end
	if branchA.ZIndex ~= branchB.ZIndex then
		return branchA.ZIndex > branchB.ZIndex
	end
	local siblings = branchA.Parent:GetChildren()
	return (table.find(siblings, branchA) :: number) > (table.find(siblings, branchB) :: number)
end

-- The HUD's root and its bottom stack, for a phone (`touch`) or a pointer, as HudController builds them.
local function build(touch: boolean): (any, any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local ScreenRoot = world.require("src/ui/components/ScreenRoot")
	local ComboRow = world.require("src/ui/components/ComboRow")
	local CombatDock = world.require("src/ui/components/CombatDock")
	local Hotbar = world.require("src/ui/components/Hotbar")
	local localize = {
		t = function(key: string): string
			return key
		end,
	}
	local root = ScreenRoot.new({ Name = "Hud", DisplayOrder = 1 })
	root.Instance.Parent = world.playerGui
	local stack = Engine.instance("Frame", root.Content)
	stack.Name = "BottomStack"
	local combo = ComboRow.new({ Parent = stack, Localize = localize, LayoutOrder = 1 })
	local dock = CombatDock.new({ Parent = stack, Screen = root.Instance, LayoutOrder = 2, Width = 460, Pips = touch })
	local hotbar = Hotbar.new({
		Parent = if touch then dock.PipRow or stack else stack,
		Mode = if touch then "Pips" else "Slots",
		Localize = localize,
		LayoutOrder = 3,
	})
	hotbar:SetLoadout({ "Brand", "Wash", "Serif" })
	return root, combo, dock, hotbar
end

local function refusalPill(combo: any): any
	local anchor = combo.Instance:FindFirstChild("Refusal")
	assert(anchor ~= nil, "the combo row has no Refusal anchor: this gate would check nothing")
	return anchor:FindFirstChild("Pill")
end

describe("the HUD's bottom stack, run", function()
	it("is laid out by ZIndexBehavior.Sibling, the rule this spec paints by", function()
		local root = build(false)
		expect(root.Instance.ZIndexBehavior).toBe(roblox.Enum.ZIndexBehavior.Sibling)
	end)

	it("paints a refusal over the dock's plate on a phone", function()
		local _root, combo, dock = build(true)
		local pill = refusalPill(combo)
		for _, part in ipairs(dock.Instance:GetDescendants()) do
			if part:IsA("GuiObject") and not paintsOver(pill, part) then
				error(("the refusal is painted under the dock's %s"):format(part:GetFullName()))
			end
		end
	end)

	it("paints a refusal over the hotbar's slots with a pointer", function()
		local _root, combo, dock, hotbar = build(false)
		local pill = refusalPill(combo)
		local checked = 0
		for _, part in ipairs(hotbar.Instance:GetDescendants()) do
			if part:IsA("GuiObject") then
				checked += 1
				if not paintsOver(pill, part) then
					error(("the refusal is painted under the hotbar's %s"):format(part:GetFullName()))
				end
			end
		end
		expect(checked).toBeGreaterThan(0)
		expect(paintsOver(pill, dock.Instance)).toBe(true)
	end)
end)

return nil
