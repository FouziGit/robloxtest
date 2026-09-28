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
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
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

-- The touch dock with its pips, `glyphs` of them, at `width` (CombatDock.SetWidth, as HudController.fitDock
-- sets it): how wide each pip is drawn, and the room the row has.
local function pipsAt(width: number, glyphs: number): (number, number, number)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local CombatDock = world.require("src/ui/components/CombatDock")
	local Hotbar = world.require("src/ui/components/Hotbar")
	local GlyphConfig = world.require("src/shared/Config/GlyphConfig")
	local gui = Engine.instance("ScreenGui", world.playerGui)
	local dock = CombatDock.new({ Parent = gui, Screen = gui, LayoutOrder = 1, Width = width, Pips = true })
	dock:SetWidth(width)
	local hotbar = Hotbar.new({
		Parent = dock.PipRow,
		Mode = "Pips",
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		LayoutOrder = 1,
	})
	local ids = {}
	for index = 1, glyphs do
		table.insert(ids, GlyphConfig.Glyphs[index].Id)
	end
	hotbar:SetLoadout(ids)
	local padding = dock.PipRow.Parent:FindFirstChildOfClass("UIPadding")
	local inner = width - padding.PaddingLeft.Offset - padding.PaddingRight.Offset
	local gap = hotbar.Instance:FindFirstChildOfClass("UIListLayout").Padding.Offset
	local pip = hotbar.Instance:FindFirstChild("Pip1")
	local round = pip:FindFirstChildOfClass("UIAspectRatioConstraint")
	assert(round ~= nil and round.AspectRatio == 1, "a pip is no longer kept round: this gate would check nothing")
	-- Round within its share of the row and the row's height.
	local share = inner * pip.Size.X.Scale + pip.Size.X.Offset
	local side = math.min(share, dock.PipRow.Size.Y.Offset)
	return side, gap, inner
end

describe("the touch dock's pips, run", function()
	it("fit every slot a pass opens in the narrowest dock", function()
		local most = ProgressionConfig.Loadout.MaxSlots
		for count = ProgressionConfig.Loadout.BaseSlots, most do
			local side, gap, inner = pipsAt(ThemeConfig.Hud.DockWidthTouchMin, count)
			local row = count * side + (count - 1) * gap
			if row > inner then
				error(("%d pips need %.1f units and the narrowest dock has %.1f"):format(count, row, inner))
			end
			expect(side).toBeGreaterThan(0)
		end
	end)

	it("keeps a few pips at the row's height", function()
		local side = pipsAt(ThemeConfig.Hud.DockWidthTouchMax, 6)
		expect(side).toBe(ThemeConfig.Hud.HotbarPipsHeight)
	end)
end)

describe("the touch dock's pips on its ink, run", function()
	it("ring every pip in the sheet, outside its cooling veil, so a dark pigment keeps its shape", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local CombatDock = world.require("src/ui/components/CombatDock")
		local Hotbar = world.require("src/ui/components/Hotbar")
		local GlyphConfig = world.require("src/shared/Config/GlyphConfig")
		local Theme = world.require("src/ui/Theme")
		local gui = Engine.instance("ScreenGui", world.playerGui)
		local dock = CombatDock.new({ Parent = gui, Screen = gui, LayoutOrder = 1, Width = 300, Pips = true })
		local hotbar = Hotbar.new({
			Parent = dock.PipRow,
			Mode = "Pips",
			Localize = {
				t = function(key: string): string
					return key
				end,
			},
			LayoutOrder = 1,
		})
		-- One glyph of each pigment, the two dark ones included.
		local ids, seen = {}, {}
		for _, def in ipairs(GlyphConfig.Glyphs) do
			if not seen[def.Pigment] then
				seen[def.Pigment] = true
				table.insert(ids, def.Id)
			end
		end
		expect(seen.Indigo and seen.Umber).toBe(true)
		hotbar:SetLoadout(ids)
		-- The sheet stands clear of the ink the pips sit on, where the pigment alone does not.
		expect(ThemeConfig.contrast(ThemeConfig.Colors.PanelRaised, ThemeConfig.Colors.Plate)).toBeGreaterThanOrEqual(3)
		for index = 1, #ids do
			local pip = hotbar.Instance:FindFirstChild("Pip" .. index)
			local ring = pip:FindFirstChildOfClass("UIStroke")
			expect(ring).never.toBeNil()
			expect(ring.Color).toBe(Theme.Colors.PanelRaised)
			-- Outside the pip, where the veil it clips never reaches.
			expect(pip.ClipsDescendants).toBe(true)
			expect(ring.BorderStrokePosition).toBe(roblox.Enum.BorderStrokePosition.Outer)
		end
	end)
end)

describe("the preview pill, run", function()
	-- Words, on the ink pill, at the preview's size (WCAG body text).
	local BODY_CONTRAST = 4.5

	it("names each pigment's glyph in words that read on ink, after an arrow in the roman", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local ComboRow = world.require("src/ui/components/ComboRow")
		local GlyphConfig = world.require("src/shared/Config/GlyphConfig")
		local Theme = world.require("src/ui/Theme")
		local gui = Engine.instance("ScreenGui", world.playerGui)
		local row = ComboRow.new({
			Parent = gui,
			Localize = {
				t = function(key: string): string
					return key
				end,
			},
			LayoutOrder = 1,
		})
		local preview = row.Instance:FindFirstChild("Preview", true)
		local name = preview:FindFirstChild("Text", true)
		local arrow = preview:FindFirstChild("Arrow", true)
		expect(arrow).never.toBeNil()
		local seen: { [string]: boolean } = {}
		for _, def in ipairs(GlyphConfig.Glyphs) do
			if seen[def.Pigment] then
				continue
			end
			seen[def.Pigment] = true
			row:SetPreview(def.Id, 1)
			expect(name.Text).toBe(def.NameKey)
			local contrast = Theme.contrast(name.TextColor3, Theme.Colors.Plate)
			if contrast < BODY_CONTRAST then
				error(("%s's name is %.2f on the ink pill"):format(def.Pigment, contrast))
			end
			-- A name drawn in the sheet still says its pigment, in its stroke.
			local stroke = name:FindFirstChildOfClass("UIStroke")
			if name.TextColor3 == Theme.Colors.PanelRaised then
				expect(stroke.Enabled).toBe(true)
				local own = if def.Pigment == "Umber" then Theme.Colors.Bronze else Theme.pigmentColor(def.Pigment)
				expect(stroke.Color).toBe(own)
			else
				expect(stroke.Enabled).toBe(false)
			end
			expect(arrow.Text).toBe(Theme.Glyphs.Arrow)
			expect(arrow.FontFace.Family).toBe(Theme.Fonts.Symbol.Family)
			expect(arrow.TextColor3).toBe(name.TextColor3)
		end
		expect(seen.Cinnabar and seen.Umber).toBe(true)
	end)
end)

return nil
