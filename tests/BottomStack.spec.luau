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
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local Layout = require("./layout")
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
	-- The sheet's line inside an edge, the board's inset ring: one stroke, drawn inward.
	local function sheetLine(holder: any, Theme: any)
		local strokes = 0
		for _, part in ipairs(holder:GetChildren()) do
			if part.ClassName == "UIStroke" then
				strokes += 1
				expect(part.Color).toBe(Theme.Colors.PanelRaised)
				expect(part.Thickness).toBeGreaterThanOrEqual(Theme.Sizes.StrokeThin)
				expect(part.BorderStrokePosition).toBe(roblox.Enum.BorderStrokePosition.Inner)
			end
		end
		expect(strokes).toBe(1)
	end

	-- The sheet's ring on a plate: a frame the plate's own size and corner, its line inside the plate's edge.
	local function flush(ring: any, plate: any, Theme: any)
		assert(ring ~= nil and plate ~= nil, "no ring or no plate: this gate would check nothing")
		expect(ring.Size).toBe(roblox.UDim2.fromScale(1, 1))
		expect(ring.Position).toBe(roblox.UDim2.new())
		expect(ring:FindFirstChildOfClass("UICorner").CornerRadius).toBe(
			plate:FindFirstChildOfClass("UICorner").CornerRadius
		)
		sheetLine(ring, Theme)
	end

	it("sit on the plate's own edge, the board's inset line, with the plate's corner, round a heavy sigil", function()
		local _root, _combo, dock, hotbar, Theme = build(false)
		local slots = 0
		for _, slot in ipairs(hotbar.Instance:GetChildren()) do
			if string.sub(slot.Name, 1, 4) == "Slot" then
				slots += 1
				local face = slot:FindFirstChild("Plate", true):FindFirstChild("Face")
				-- A slot's ring is its face's own line, with its corner: no frame drawn for it (the budget).
				assert(face ~= nil, "a slot has no plate face: this gate would check nothing")
				sheetLine(face, Theme)
				for _, part in ipairs(face:GetChildren()) do
					expect(part:IsA("GuiObject")).toBe(false)
				end
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

describe("the hotbar's keys, run", function()
	it("run each key's pigment the width of its cap, on the foot of a cap with no lip", function()
		local _root, _combo, _dock, hotbar, Theme = build(false)
		local caps = 0
		for _, strip in ipairs(hotbar.Instance:GetDescendants()) do
			if strip.Name == "Pigment" then
				caps += 1
				local cap = strip.Parent
				expect(cap.Size.Y.Offset).toBe(ThemeConfig.Hud.HotbarKeyStrip - 3)
				expect(cap:FindFirstChild("Face").Size).toBe(roblox.UDim2.fromScale(1, 1))
				expect(strip.Size).toBe(roblox.UDim2.new(1, -Theme.Sizes.StrokeThin * 2, 0, 4))
				expect(strip.Position).toBe(roblox.UDim2.new(0.5, 0, 1, -Theme.Sizes.StrokeThin))
				expect(strip:FindFirstChildOfClass("UICorner").CornerRadius).toBe(
					roblox.UDim.new(0, Theme.Sizes.CornerKeycap - Theme.Sizes.StrokeThin)
				)
				-- No lip at all: nothing under the face in the lip's chalk, whatever is under it lies exactly under
				-- it, and no outline of the cap is drawn outside it.
				local face = cap:FindFirstChild("Face")
				for _, part in ipairs(cap:GetChildren()) do
					if part.Name == "Base" then
						expect(part.BackgroundColor3 == Theme.lip("Secondary")).toBe(false)
						expect(part.Position).toBe(face.Position)
						expect(part.Size).toBe(face.Size)
					end
				end
				for _, line in ipairs(cap:GetDescendants()) do
					if line.ClassName == "UIStroke" and line.ApplyStrokeMode == roblox.Enum.ApplyStrokeMode.Border then
						expect(line.BorderStrokePosition).toBe(roblox.Enum.BorderStrokePosition.Inner)
					end
				end
			end
		end
		expect(caps).toBeGreaterThanOrEqual(6)
	end)

	it("keep the lip everywhere else, and a pad's round button keeps its strip off the curve", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Keycap = world.require("src/ui/components/Keycap")
		local Theme = world.require("src/ui/Theme")
		local localize = {
			t = function(key: string): string
				return key
			end,
		}
		local cap = Keycap.new({ Key = "J", Device = "Keyboard", Localize = localize, Size = 19, Pigment = "Cinnabar" })
		expect(cap.Instance.Size.Y.Offset).toBe(22)
		-- On its chalk lip, three units under the face.
		local base = cap.Instance:FindFirstChild("Base")
		expect(base.BackgroundColor3).toBe(Theme.lip("Secondary"))
		expect(base.Position).toBe(roblox.UDim2.fromOffset(0, 3))
		local strip = cap.Instance:FindFirstChild("Pigment")
		expect(strip.Position).toBe(roblox.UDim2.new(0.5, 0, 1, -Theme.Sizes.StrokeThin - 3))
		expect(strip.Size).toBe(roblox.UDim2.new(1, -Theme.Sizes.StrokeThin * 2, 0, 4))
		local pad =
			Keycap.new({ Key = "ButtonX", Device = "Gamepad", Localize = localize, Size = 19, Pigment = "Indigo" })
		local padStrip = pad.Instance:FindFirstChild("Pigment")
		expect(padStrip.Size).toBe(roblox.UDim2.new(1, -Theme.Sizes.CornerKeycap * 2, 0, 4))
		expect(padStrip:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
	end)
end)

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
		-- The veil is the slot's, its full width, over the chip and the ring.
		local veil = square:FindFirstChild("Drain")
		assert(veil ~= nil, "the slot has no veil of its own: this gate would check nothing")
		expect(chip:FindFirstChild("Drain")).toBeNil()
		expect(veil.Size.X.Scale).toBe(1)
		expect(veil.Size.X.Offset).toBe(0)
		expect(veil.ZIndex).toBeGreaterThan(chip.ZIndex)
		-- Cut straight where it ends, as the board's face cuts it: a clear window, no corner of its own, clipping
		-- an ink the slot's full height with the slot's corner, so only its top corners are ever rounded.
		expect(veil.BackgroundTransparency).toBe(1)
		expect(veil.ClipsDescendants).toBe(true)
		expect(veil:FindFirstChildOfClass("UICorner")).toBeNil()
		local ink = veil:FindFirstChild("Ink")
		assert(ink ~= nil, "the veil holds no ink: this gate would check nothing")
		expect(#veil:GetChildren()).toBe(1)
		expect(ink.Position).toBe(roblox.UDim2.new())
		expect(ink.Size).toBe(roblox.UDim2.new(1, 0, 0, ThemeConfig.Hud.HotbarSlot))
		expect(square.Size.Y.Offset).toBe(ThemeConfig.Hud.HotbarSlot)
		expect(ink:FindFirstChildOfClass("UICorner").CornerRadius).toBe(roblox.UDim.new(0, Theme.Sizes.CornerChip))
		expect(ink.BackgroundColor3).toBe(Theme.Colors.Plate)
		expect(ink.BackgroundTransparency).toBe(0.31)
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

describe("a slot ready again, run", function()
	it("flashes from the slot's centre, and leaves the bar its widths once the flash has faded", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Hotbar = world.require("src/ui/components/Hotbar")
		local GlyphConfig = world.require("src/shared/Config/GlyphConfig")
		local gui = Engine.instance("ScreenGui", world.playerGui)
		local hotbar = Hotbar.new({
			Parent = gui,
			Mode = "Slots",
			Localize = {
				t = function(key: string, params: { [string]: any }?): string
					return Strings.t(key, params, "en")
				end,
			},
			LayoutOrder = 1,
		})
		hotbar:SetLoadout({ "Brand", "Wash" })
		local def = GlyphConfig.byId("Brand")
		local column = hotbar.Instance:FindFirstChild("Slot1")
		local flash = column:FindFirstChild("Square"):FindFirstChild("Ready")
		assert(flash ~= nil, "the slot has no ready flash: this gate would check nothing")
		-- The slot sizes itself to its keys: whatever it holds grows it, unless it is centred.
		expect(column.AutomaticSize.Name).toBe("X")
		hotbar:SetState({ Ink = 100, Cooldowns = { Brand = def.Cooldown / 2 } })
		world:advance(1)
		hotbar:SetState({ Ink = 100, Cooldowns = {} })
		world:advance(2)
		-- The flash has run: faded, grown past the slot, and grown about the slot's centre.
		expect(flash.ImageTransparency).toBeCloseTo(1, 2)
		expect(flash:FindFirstChildOfClass("UIScale").Scale).toBeGreaterThan(1)
		expect(flash.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
		expect(flash.Position).toBe(roblox.UDim2.fromScale(0.5, 0.5))
		-- Seen in Studio: grown from its corner, it kept the slot 78.4 wide, and the bar's gaps uneven.
		local found = Layout.scaledContents(gui)
		if #found > 0 then
			error(table.concat(found, "\n"))
		end
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

-- The stack the HUD itself builds, by how the player plays (InputMode, D-XXX), run: the real HudController, so the
-- stack a touch laptop gets when it is touched is the one built again, not one this spec assembles. Its refusal
-- still hangs over whatever stands under it.
describe("the HUD's own bottom stack, by how the player plays, run", function()
	local function player(): any
		local quests = { PeriodKey = "", Claimed = {}, Progress = {} }
		return {
			Settings = {
				Keyboard = table.clone(InputConfig.DefaultKeyboard),
				Gamepad = table.clone(InputConfig.DefaultGamepad),
				CameraShake = true,
			},
			Loadout = { Slots = { "Brand", "Wash", "Serif" }, SlotLimit = 6 },
			Progression = { Level = 5, XP = 10 },
			Currency = { Folios = 100 },
			Stats = { GlyphsCast = 3, MatchesPlayed = 2 },
			Daily = { LastClaimDay = 0, Streak = 0 },
			Quests = { Daily = quests, Weekly = table.clone(quests) },
			Battlepass = {},
		}
	end

	-- The stack's refusal pill painted over every part of what stands under it: the dock, and its pips or the
	-- hotbar's slots. Returns which of the two the stack draws.
	local function refusalOnTop(fixture: Hud.Fixture): string
		local stacks = {}
		for _, part in ipairs(fixture.screen:GetDescendants()) do
			if part.Name == "BottomStack" then
				table.insert(stacks, part)
			end
		end
		expect(#stacks).toBe(1)
		local stack = stacks[1]
		local pill = stack:FindFirstChild("Refusal", true):FindFirstChild("Pill")
		local checked = 0
		for _, name in ipairs({ "Dock", "Hotbar" }) do
			local under = stack:FindFirstChild(name, true)
			if under ~= nil then
				for _, part in ipairs(under:GetDescendants()) do
					if part:IsA("GuiObject") then
						checked += 1
						if not paintsOver(pill, part) then
							error(("the refusal is painted under the %s's %s"):format(name, part:GetFullName()))
						end
					end
				end
			end
		end
		expect(checked).toBeGreaterThan(0)
		if stack:FindFirstChild("Pip1", true) ~= nil then
			return "Pips"
		end
		assert(stack:FindFirstChild("Slot1", true) ~= nil, "the stack draws neither pips nor slots")
		return "Slots"
	end

	it("draws a touch laptop typed on the slots, and a phone with a pad the pips, under its refusal", function()
		local typed = Hud.build({ Profile = player(), Plays = "TouchKeyboard" })
		typed.world:advance(1)
		expect(refusalOnTop(typed)).toBe("Slots")
		local padded = Hud.build({ Profile = player(), Phone = { 844, 390 }, Plays = "TouchGamepad" })
		padded.world:advance(1)
		expect(refusalOnTop(padded)).toBe("Pips")
	end)

	it("is built again with the pips when a touch laptop is touched, and with the slots when it is typed on", function()
		local fixture = Hud.build({ Profile = player(), Plays = "TouchKeyboard" })
		fixture.world:advance(1)
		Engine.plays(fixture.world, "TouchLaptop")
		fixture.world:advance(1)
		expect(refusalOnTop(fixture)).toBe("Pips")
		Engine.plays(fixture.world, "TouchKeyboard")
		fixture.world:advance(1)
		expect(refusalOnTop(fixture)).toBe("Slots")
	end)
end)

return nil
