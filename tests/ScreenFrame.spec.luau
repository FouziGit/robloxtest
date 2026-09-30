--!strict
-- The frame every screen shares (D-147): the root's backdrop, its entrance and exit, the card and its band.
-- Most of it is engine code that Lune cannot run, so what can regress silently is held by reading it: a
-- screen that vanishes instead of leaving, a dim that ignores the player's own setting, a HUD that grows
-- with the menus' text size, a cross that turns red. The drop cap's split is pure and runs here.
local Engine = require("./engine")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOT = "src/ui/components/ScreenRoot.luau"
local PANEL = "src/ui/components/Panel.luau"
local BAND = "src/ui/components/ChapterBand.luau"
local CONTENT = "src/ui/components/CardContent.luau"
local HUD = "src/client/Controllers/HudController.luau"

-- The title of every screen that has one, as the player reads it.
local TITLE_KEYS = {
	"menu.title",
	"queue.title",
	"shop.title",
	"battlepass.title",
	"daily.title",
	"menu.quests",
	"loadout.title",
	"leaderboard.title",
	"settings.title",
}

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function code(path: string): string
	return stripComments(fs.readFile(path))
end

-- The body of the local function `name` in `source`, up to its closing `end` at the same indent.
local function body(source: string, name: string): string
	local indent, rest = string.match(source, "\n(\t*)local function " .. name .. "%((.*)")
	assert(indent ~= nil and rest ~= nil, ("no local function %s: this gate would check nothing"):format(name))
	local finish = string.find(rest :: string, "\n" .. (indent :: string) .. "end\n", 1, true)
	assert(finish ~= nil, ("%s has no end"):format(name))
	return string.sub(rest :: string, 1, finish :: number)
end

local function count(source: string, plain: string): number
	local found, from = 0, 1
	while true do
		local at = string.find(source, plain, from, true)
		if at == nil then
			return found
		end
		found += 1
		from = at + 1
	end
end

describe("the drop cap", function()
	it("takes a title's first letter, accented or not, and leaves the rest", function()
		local letter, rest = ThemeConfig.dropCap("Quêtes")
		expect(letter).toBe("Q")
		expect(rest).toBe("uêtes")
		letter, rest = ThemeConfig.dropCap("Équipement")
		expect(letter).toBe("É")
		expect(rest).toBe("quipement")
		letter, rest = ThemeConfig.dropCap("M")
		expect(letter).toBe("M")
		expect(rest).toBe("")
	end)

	it("is never a digit, a quote or a sign: that title stays whole", function()
		for _, title in ipairs({ "3v3", "« Menu »", "×2", "", "—" }) do
			local letter, rest = ThemeConfig.dropCap(title)
			if letter ~= nil then
				error(("%q opens on %q, which is no letter"):format(title, letter))
			end
			expect(rest).toBe(title)
		end
	end)

	it("opens every screen's title in both languages, as one character", function()
		for _, key in ipairs(TITLE_KEYS) do
			local entry = Strings.Table[key]
			assert(entry ~= nil, ("no title %s"):format(key))
			for _, title in ipairs({ entry.en, entry.fr }) do
				local letter, rest = ThemeConfig.dropCap(title)
				if letter == nil then
					error(("%s (%q) has no drop cap"):format(key, title))
				end
				expect(utf8.len(letter :: string)).toBe(1)
				expect((letter :: string) .. rest).toBe(title)
			end
		end
	end)
end)

describe("the drop cap, drawn", function()
	it("is the title's own first letter: the roman at its heaviest, a fifth larger, in the band's title ink", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local DropCap = world.require("src/ui/components/DropCap")
		local Theme = world.require("src/ui/Theme")
		for screen in pairs(ThemeConfig.Chapters) do
			local cap = DropCap.new("Q", screen, world.playerGui)
			local label = cap.Instance
			-- A bare letter, as the board's `.cap`: no square of sheet under it, no ring or outline around it.
			expect(label.ClassName).toBe("TextLabel")
			expect(label.Text).toBe("Q")
			expect(label.BackgroundTransparency).toBe(1)
			for _, part in ipairs(label:GetDescendants()) do
				if part:IsA("GuiObject") or part:IsA("UIStroke") then
					error(("%s's drop cap draws %s"):format(screen, part.Name))
				end
			end
			expect(label.FontFace.Family).toBe(Theme.Fonts.Initial.Family)
			expect(label.FontFace.Weight).toBe(Theme.Fonts.Initial.Weight)
			expect(label.TextSize / Theme.Sizes.TextTitle).toBeCloseTo(1.2, 1)
			expect(label.TextSize).toBe(36)
			expect(label.TextColor3).toBe(Theme.chapter(screen).Title)
			expect(label.AutomaticSize.Name).toBe("X")
			cap:Destroy()
		end
		-- The Menu's is the vellum of its ink band's title, the pass's the sheet of its purple one.
		expect(DropCap.new("M", "Menu").Instance.TextColor3).toBe(Theme.Colors.TextInverse)
		expect(DropCap.new("B", "Battlepass").Instance.TextColor3).toBe(Theme.Colors.PanelRaised)
		expect(DropCap.new("Q", "Quests").Instance.TextColor3).toBe(Theme.Colors.Text)
	end)

	it("still lands after its band at an entrance", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local DropCap = world.require("src/ui/components/DropCap")
		local cap = DropCap.new("Q", "Quests", world.playerGui)
		cap:Stamp()
		expect(cap.Instance.Visible).toBe(false)
		world:advance(1)
		expect(cap.Instance.Visible).toBe(true)
		expect(cap.Instance:FindFirstChildOfClass("UIScale").Scale).toBeCloseTo(1, 2)
	end)
end)

describe("the backdrop", function()
	it("dims by the player's own background-transparency setting, and takes the clicks", function()
		local root = code(ROOT)
		expect(string.find(root, "local DIM = 0.35\n", 1, true)).never.toBeNil()
		expect(string.find(body(root, "dimTarget"), "return DIM * UiPrefs.transparency()", 1, true)).never.toBeNil()
		expect(string.find(root, "overlay.Active = true", 1, true)).never.toBeNil()
	end)

	it("draws no corner blots on the lowest graphics tier", function()
		expect(string.find(body(code(ROOT), "showCorners"), "local shown = not UiPrefs.lowQuality()", 1, true)).never.toBeNil()
	end)

	it("leaves the screen at least half of its splats", function()
		local blots = count(string.match(code(ROOT), "local CORNERS[^=]*= (%b{})") or "", "Position =")
		expect(blots).toBe(3)
		-- The band is flat (D-178): it hangs no drips and spends no splat of its screen's.
		local band = code(BAND)
		expect(string.find(band, "Splat", 1, true)).toBeNil()
		expect(string.find(band, "DRIPS", 1, true)).toBeNil()
		expect(blots).toBeLessThanOrEqual(ThemeConfig.Budget.MaxSplats / 2)
	end)
end)

describe("the player's text size", function()
	it("grows a menu that asks for it, and never the HUD", function()
		expect(
			string.find(
				code(ROOT),
				"currentScale = Theme.activeScale() * (if textScalable then UiPrefs.textScale() else 1)",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(code(ROOT), "local textScalable = props.TextScalable == true", 1, true)).never.toBeNil()
		-- The HUD's geometry is measured at the designed sizes (D-147 §2.9).
		local hud: string? = nil
		for call in string.gmatch(code(HUD), "ScreenRoot%.new(%b())") do
			if string.find(call, 'Name = "Hud"', 1, true) ~= nil then
				hud = call
			end
		end
		assert(hud ~= nil, "the HUD builds no root: this gate would check nothing")
		expect(string.find(hud :: string, "TextScalable", 1, true)).toBeNil()
	end)
end)

describe("a screen that leaves", function()
	it("is disabled only once its card has faded out (rule 3: nothing vanishes)", function()
		local root = code(ROOT)
		-- One place turns a screen off: the end of its exit.
		expect(count(root, "gui.Enabled = false")).toBe(1)
		expect(string.find(body(root, "finish"), "gui.Enabled = false", 1, true)).never.toBeNil()
		expect(string.find(body(root, "playExit"), "current:PlayExit(finish)", 1, true)).never.toBeNil()
	end)

	it("fades once when asked to leave twice, and the second caller waits for the same end", function()
		local exit = body(code(ROOT), "playExit")
		local guard = string.find(exit, "if exiting then\n\t\t\treturn\n\t\tend", 1, true)
		local start = string.find(exit, "exitToken += 1", 1, true)
		assert(guard ~= nil and start ~= nil, "the exit has no guard: a second call would cut the first short")
		expect(guard :: number).toBeLessThan(start :: number)
		expect(string.find(exit, "table.insert(exitCallbacks, onDone)", 1, true)).never.toBeNil()
	end)

	it("fades its card as one piece, through a group that does not outlive the exit", function()
		local panel = code(PANEL)
		local exit = body(panel, "playExit")
		expect(string.find(exit, 'Instance.new("CanvasGroup")', 1, true)).never.toBeNil()
		expect(string.find(exit, 'Motion.to(group, { GroupTransparency = 1 }, "UiExit", function()', 1, true)).never.toBeNil()
		expect(string.find(body(panel, "restoreFromExit"), "group:Destroy()", 1, true)).never.toBeNil()
		-- Under reduced motion only the fade runs.
		expect(string.find(exit, "if not UiPrefs.reducedMotion() then", 1, true)).never.toBeNil()
		-- An entrance catches an exit in flight: the card comes back, and that exit never calls its end.
		expect(string.find(body(panel, "playEnter"), "exitToken += 1\n\t\trestoreFromExit()", 1, true)).never.toBeNil()
	end)
end)

describe("the card", function()
	it("is a vellum sticker, its band flat and flush inside its ink (rule 11)", function()
		local panel = code(PANEL)
		expect(string.find(panel, 'Kind = "Card",\n\t\tFill = Theme.Colors.Panel,', 1, true)).never.toBeNil()
		-- Run: the card's ink outline is the band's, and the band runs from one side of it to the other.
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Panel = world.require("src/ui/components/Panel")
		local ChapterBand = world.require("src/ui/components/ChapterBand")
		local Theme = world.require("src/ui/Theme")
		local stroke = Theme.Sizes.Stroke
		for _, case in ipairs({ { Chapter = "Menu", Stripe = 8 }, { Chapter = "Quests", Stripe = 0 } }) do
			local card =
				Panel.new({ Title = "Quêtes", Chapter = case.Chapter, Closable = true, Parent = world.playerGui })
			local face = card.Instance:FindFirstChild("Face")
			local outline = face:FindFirstChildOfClass("UIStroke")
			expect(outline.Color).toBe(Theme.Colors.Accent)
			expect(outline.Thickness).toBe(stroke)
			local top = face:FindFirstChild("Top")
			local band = top:FindFirstChild("Band")
			assert(band ~= nil, "the card has no band: this gate would check nothing")
			local height = ChapterBand.height()
			expect(top.Position).toBe(roblox.UDim2.fromOffset(stroke, stroke))
			expect(top.Size).toBe(roblox.UDim2.new(1, -2 * stroke, 0, height + case.Stripe))
			-- Flat: no outline, no light across it; its top corners the card's inner ones, its foot square.
			expect(band:FindFirstChildOfClass("UIStroke")).toBeNil()
			expect(band:FindFirstChildOfClass("UIGradient")).toBeNil()
			expect(band:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(Theme.Sizes.CornerPanel - stroke)
			expect(band.Size).toBe(roblox.UDim2.new(1, 0, 1, -case.Stripe))
			local square = band:FindFirstChild("Square")
			expect(square.BackgroundColor3).toBe(band.BackgroundColor3)
			expect(square.Position).toBe(roblox.UDim2.fromScale(0, 0.5))
			expect(square.Size).toBe(roblox.UDim2.fromScale(1, 0.5))
			expect(square:FindFirstChildOfClass("UICorner")).toBeNil()
			expect(band.BackgroundColor3).toBe(Theme.chapter(case.Chapter).Band)
			-- An ink band's stripe right under it, edge to edge, 8 tall, the pigments in their order.
			local stripe = top:FindFirstChild("Stripe")
			if case.Stripe > 0 then
				assert(stripe ~= nil, "the Menu's band has no stripe")
				expect(stripe.Parent).toBe(top)
				expect(stripe.AnchorPoint).toBe(roblox.Vector2.new(0, 1))
				expect(stripe.Position).toBe(roblox.UDim2.fromScale(0, 1))
				expect(stripe.Size).toBe(roblox.UDim2.new(1, 0, 0, 8))
			else
				expect(stripe).toBeNil()
			end
			-- The content never starts lower than it did under a band inset 8 from the card's edge.
			local header = face:FindFirstChild("Header")
			local before = Theme.Sizes.PaddingSmall + height + Theme.Sizes.PaddingSmall
			expect(header.Position.Y.Offset).toBe(
				math.min(stroke + height + case.Stripe + Theme.Sizes.PaddingSmall, before)
			)
			expect(header.Position.Y.Offset).toBeLessThanOrEqual(before)
			expect(#top:GetChildren()).toBe(if case.Stripe > 0 then 2 else 1)
		end
		-- A chapter that gains or loses the stripe moves the content's top with it.
		local card = Panel.new({ Title = "Menu", Chapter = "Quests", Parent = world.playerGui })
		local header = card.Instance:FindFirstChild("Face"):FindFirstChild("Header")
		local plain = header.Position.Y.Offset
		card:SetChapter("Menu")
		expect(header.Position.Y.Offset).toBeGreaterThan(plain)
	end)

	it("closes on a flat disc of the sheet that darkens as it is reached and pressed", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local ChapterBand = world.require("src/ui/components/ChapterBand")
		local Theme = world.require("src/ui/Theme")
		local closed = 0
		local band = ChapterBand.new({
			Title = "Menu",
			Chapter = "Menu",
			Position = roblox.UDim2.new(),
			Closable = true,
			OnClose = function()
				closed += 1
			end,
			Parent = world.playerGui,
		})
		local close = band.CloseButton
		local disc = close:FindFirstChild("Disc")
		assert(disc ~= nil, "the cross has no disc: this gate would check nothing")
		-- The board's `.m-close`: no lip, no shadow, the sheet in its ink.
		expect(close:FindFirstChild("Base", true)).toBeNil()
		expect(disc.Size).toBe(roblox.UDim2.fromScale(1, 1))
		expect(disc:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.Accent)
		expect(disc:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
		local sheet = Theme.Colors.PanelRaised
		expect(disc.BackgroundColor3).toBe(sheet)
		close.MouseEnter:Fire()
		local hovered = disc.BackgroundColor3
		expect(hovered).toBe(Theme.shade(sheet, -0.06))
		close.MouseButton1Down:Fire()
		expect(disc.BackgroundColor3).toBe(Theme.shade(sheet, -0.12))
		close.MouseButton1Up:Fire()
		expect(disc.BackgroundColor3).toBe(hovered)
		close.MouseLeave:Fire()
		expect(disc.BackgroundColor3).toBe(sheet)
		close.SelectionGained:Fire()
		expect(disc.BackgroundColor3).toBe(hovered)
		close.SelectionLost:Fire()
		expect(disc.BackgroundColor3).toBe(sheet)
		close.Activated:Fire()
		expect(closed).toBe(1)
	end)

	it("closes without red: leaving a screen is no danger", function()
		for _, path in ipairs({ ROOT, PANEL, BAND, CONTENT }) do
			if string.find(code(path), "Danger", 1, true) ~= nil then
				error(path .. " draws in red")
			end
		end
	end)

	it("springs up the first rows in view at an entrance, and never one scrolled past", function()
		local content = code(CONTENT)
		local enter = body(content, "playEnter")
		expect(string.find(enter, "child.Visible and not scrolledPast(child)", 1, true)).never.toBeNil()
		expect(string.find(enter, 'Motion.stagger(scales, { Scale = 1 }, "UiPop")', 1, true)).never.toBeNil()
		local past = body(content, "scrolledPast")
		expect(
			string.find(past, "child.AbsolutePosition.Y + child.AbsoluteSize.Y <= content.AbsolutePosition.Y", 1, true)
		).never.toBeNil()
		expect(
			string.find(past, "child.AbsolutePosition.X + child.AbsoluteSize.X <= content.AbsolutePosition.X", 1, true)
		).never.toBeNil()
	end)

	it("bobs its more-below arrow only while there is more and the screen is up", function()
		expect(string.find(body(code(CONTENT), "update"), "setBobbing(more and shown)", 1, true)).never.toBeNil()
	end)
end)

describe("the safe area, run", function()
	local INSET = Engine.TOP_INSET

	local function phoneRoot(): (any, any)
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		Engine.phone(world, 667, 375)
		local ScreenRoot = world.require("src/ui/components/ScreenRoot")
		local root = ScreenRoot.new({ Name = "Hud" })
		root.Instance.Parent = world.playerGui
		return world, root
	end

	it("stands a child of its content on the pixel asked, from inside the top bar's padding", function()
		local _world, root = phoneRoot()
		local scale = root:GetScale()
		expect(scale).toBeCloseTo(ThemeConfig.Scale.TouchFloor, 5)
		local padding = root.Content:FindFirstChildOfClass("UIPadding")
		local top = padding.PaddingTop.Offset
		expect(top).toBeGreaterThan(0)
		-- A disc's height under the top bar, placed there, lands back on that pixel: the padding plus the
		-- offset, times the scale. (A UDim's offset is whole, and a Vector2 single precision.)
		local pixel = roblox.Vector2.new(600, INSET + 68)
		local at = root:ToContent(pixel)
		expect((top + at.Y) * scale).toBeCloseTo(pixel.Y, 2)
		expect(at.X * scale).toBeCloseTo(pixel.X, 2)
		-- Measured from the content's corner instead, it lands a whole padding lower.
		expect(pixel.Y / scale - at.Y).toBeCloseTo(top, 2)
	end)
end)

return nil
