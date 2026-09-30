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
local Strings = require("../src/shared/Strings")
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
local function build(touch: boolean): (any, any, any, any, any)
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
	return root, combo, dock, hotbar, world.require("src/ui/Theme")
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

describe("the slots' and the dock's rings, run", function()
	-- The sheet's ring on a plate: a frame the plate's own size and corner, its line inside the plate's edge.
	local function flush(ring: any, plate: any, Theme: any)
		assert(ring ~= nil and plate ~= nil, "no ring or no plate: this gate would check nothing")
		expect(ring.Size).toBe(roblox.UDim2.fromScale(1, 1))
		expect(ring.Position).toBe(roblox.UDim2.new())
		expect(ring:FindFirstChildOfClass("UICorner").CornerRadius).toBe(
			plate:FindFirstChildOfClass("UICorner").CornerRadius
		)
		local line = ring:FindFirstChildOfClass("UIStroke")
		expect(line.Color).toBe(Theme.Colors.PanelRaised)
		expect(line.BorderStrokePosition).toBe(roblox.Enum.BorderStrokePosition.Inner)
	end

	it("sit on the plate's own edge, the board's inset line, with the plate's corner, round a heavy sigil", function()
		local _root, _combo, dock, hotbar, Theme = build(false)
		local slots = 0
		for _, slot in ipairs(hotbar.Instance:GetChildren()) do
			if string.sub(slot.Name, 1, 4) == "Slot" then
				slots += 1
				local face = slot:FindFirstChild("Plate", true):FindFirstChild("Face")
				flush(face:FindFirstChild("Ring"), face, Theme)
				expect(face:FindFirstChildOfClass("UICorner").CornerRadius).toBe(
					roblox.UDim.new(0, Theme.Sizes.CornerChip)
				)
				-- The chip's sigil in the heavy face, the board's 21.
				local sigil = slot:FindFirstChild("Sigil", true)
				expect(sigil.FontFace.Family).toBe(Theme.Fonts.Label.Family)
				expect(sigil.FontFace.Weight).toBe(Theme.Fonts.Label.Weight)
				expect(sigil.TextSize).toBe(21)
			end
		end
		expect(slots).toBe(3)
		local face = dock.Instance:FindFirstChild("Plate"):FindFirstChild("Face")
		flush(face:FindFirstChild("Ring"), face, Theme)
		expect(face:FindFirstChildOfClass("UICorner").CornerRadius).toBe(roblox.UDim.new(0, Theme.Sizes.CornerTile))
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

describe("a cooling slot, run", function()
	it("veils the whole slot and counts down in tenths on the veil's edge, in the language's mark", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Hotbar = world.require("src/ui/components/Hotbar")
		local GlyphConfig = world.require("src/shared/Config/GlyphConfig")
		local Theme = world.require("src/ui/Theme")
		local gui = Engine.instance("ScreenGui", world.playerGui)
		local hotbar = Hotbar.new({
			Parent = gui,
			Mode = "Slots",
			Localize = {
				t = function(key: string, params: { [string]: any }?): string
					return Strings.t(key, params, "fr")
				end,
			},
			LayoutOrder = 1,
		})
		hotbar:SetLoadout({ "Brand" })
		local def = GlyphConfig.byId("Brand")
		local square = hotbar.Instance:FindFirstChild("Slot1"):FindFirstChild("Square")
		local chip = square:FindFirstChild("Chip")
		-- The veil is the slot's, its full width and its corner, over the chip and the ring.
		local veil = square:FindFirstChild("Drain")
		assert(veil ~= nil, "the slot has no veil of its own: this gate would check nothing")
		expect(chip:FindFirstChild("Drain")).toBeNil()
		expect(veil.Size.X.Scale).toBe(1)
		expect(veil.Size.X.Offset).toBe(0)
		expect(veil:FindFirstChildOfClass("UICorner").CornerRadius).toBe(roblox.UDim.new(0, Theme.Sizes.CornerChip))
		expect(veil.BackgroundColor3).toBe(Theme.Colors.Plate)
		expect(veil.BackgroundTransparency).toBe(0.31)
		expect(veil.ZIndex).toBeGreaterThan(chip.ZIndex)
		-- Half cooled: the seconds stand on the veil's edge, four over it.
		hotbar:SetState({ Ink = 100, Cooldowns = { Brand = def.Cooldown / 2 } })
		world:advance(1)
		local seconds = square:FindFirstChild("Seconds")
		expect(seconds.Visible).toBe(true)
		expect(seconds.Text).toBe(Strings.t("hud.hotbar.seconds", { whole = def.Cooldown // 2, tenth = 0 }, "fr"))
		expect(seconds.TextColor3).toBe(Theme.Colors.PanelRaised)
		expect(seconds.AnchorPoint).toBe(roblox.Vector2.new(0.5, 1))
		expect(veil.Size.Y.Scale).toBeCloseTo(0.5, 2)
		expect(seconds.Position.Y.Offset).toBeCloseTo(0.5 * ThemeConfig.Hud.HotbarSlot - 4, 1)
		-- Nearly ready: the veil is thin, and the seconds stay whole at the top, on their ink stroke.
		hotbar:SetState({ Ink = 100, Cooldowns = { Brand = 0.2 } })
		world:advance(1)
		expect(seconds.Text).toBe("0,2")
		expect(seconds.Position.Y.Offset).toBeCloseTo(16, 1)
		expect(seconds:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.Outline)
		-- Ten and more: whole seconds.
		hotbar:SetState({ Ink = 100, Cooldowns = { Brand = 12 } })
		expect(seconds.Text).toBe("12")
		-- Ready: gone.
		hotbar:SetState({ Ink = 100, Cooldowns = {} })
		expect(seconds.Visible).toBe(false)
	end)
end)

describe("a slot short of ink, run", function()
	it("marks it with the blue drop on a rim of the sheet, built the first time it shows", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Hotbar = world.require("src/ui/components/Hotbar")
		local GlyphConfig = world.require("src/shared/Config/GlyphConfig")
		local Theme = world.require("src/ui/Theme")
		local gui = Engine.instance("ScreenGui", world.playerGui)
		local hotbar = Hotbar.new({
			Parent = gui,
			Mode = "Slots",
			Localize = {
				t = function(key: string): string
					return key
				end,
			},
			LayoutOrder = 1,
		})
		hotbar:SetLoadout({ "Brand" })
		local square = hotbar.Instance:FindFirstChild("Slot1"):FindFirstChild("Square")
		hotbar:SetState({ Ink = 100, Cooldowns = {} })
		expect(square:FindFirstChild("Drop")).toBeNil()
		hotbar:SetState({ Ink = GlyphConfig.byId("Brand").Cost - 1, Cooldowns = {} })
		local holder = square:FindFirstChild("Drop")
		assert(holder ~= nil, "a slot short of ink shows no drop: this gate would check nothing")
		expect(holder.Visible).toBe(true)
		local rim = holder:FindFirstChild("Rim")
		local drop = holder:FindFirstChild("Drop")
		expect(rim.Size).toBe(roblox.UDim2.fromOffset(18, 18))
		expect(drop.Size).toBe(roblox.UDim2.fromOffset(14, 14))
		expect(holder.Size).toBe(rim.Size)
		expect(drop.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
		expect(drop.Position).toBe(roblox.UDim2.fromScale(0.5, 0.5))
		-- The rim behind, the blue over it: each drawn in its own colour.
		local order = holder:GetChildren()
		expect(table.find(order, rim) :: number).toBeLessThan(table.find(order, drop) :: number)
		for _, part in ipairs(rim:GetChildren()) do
			if part:IsA("GuiObject") then
				expect(part.BackgroundColor3).toBe(Theme.Colors.PanelRaised)
			end
		end
		for _, part in ipairs(drop:GetChildren()) do
			if part:IsA("GuiObject") then
				expect(part.BackgroundColor3).toBe(Theme.Colors.InfoFill)
			end
		end
		expect(holder.ZIndex).toBeGreaterThan(square:FindFirstChild("Drain").ZIndex)
		-- The sheet stands out from the ink of the slot, where the blue barely does.
		expect(ThemeConfig.contrast(ThemeConfig.Colors.PanelRaised, ThemeConfig.Colors.Plate)).toBeGreaterThanOrEqual(3)
		hotbar:SetState({ Ink = 100, Cooldowns = {} })
		expect(holder.Visible).toBe(false)
	end)
end)

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

	it("drains its window from the right end, its left end held where the words begin", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local ComboRow = world.require("src/ui/components/ComboRow")
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
		local window = row.Instance:FindFirstChild("Window", true)
		row:SetPreview("Brand", 0.35)
		expect(window.AnchorPoint).toBe(roblox.Vector2.new(0, 1))
		local left = window.Position
		expect(left.X.Scale).toBe(0)
		expect(left.X.Offset).toBe(14)
		expect(window.Size.X.Scale).toBe(1)
		expect(window.Size.X.Offset).toBe(-28)
		world:advance(0.1)
		-- Shorter, from the right: the left end has not moved.
		expect(window.Size.X.Scale).toBeLessThan(1)
		expect(window.Position).toBe(left)
		world:advance(2)
		expect(window.Size.X.Scale).toBeCloseTo(0, 2)
		expect(window.Position).toBe(left)
	end)
end)

return nil
