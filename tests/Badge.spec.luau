--!strict
-- The badge, run (tests/engine.luau): the real Badge, Breath, Motion and Theme.
--
-- The board badges a menu tile with an upright disc inside its top-right corner, in an ink outline, its count
-- in the number face. The game's was an ink blot tipped 6 degrees and straddling the corner, its count scaled
-- into the blot in the label face.
local Engine = require("./engine")
local Harness = require("./harness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function bench(): (any, any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local Badge = world.require("src/ui/components/Badge")
	local Theme = world.require("src/ui/Theme")
	local host = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
	return world, Badge, Theme, host
end

describe("a badge, run", function()
	it("is an upright disc of the primary yellow in its ink outline, inside its host's corner", function()
		local _world, Badge, Theme, host = bench()
		local badge = Badge.new(3, host)
		local holder = badge.Instance
		expect(holder.Name).toBe("Badge")
		expect(holder.Parent).toBe(host)
		expect(holder.Visible).toBe(true)
		expect(holder.AnchorPoint).toBe(roblox.Vector2.new(1, 0))
		expect(holder.Position).toBe(roblox.UDim2.new(1, -8, 0, 8))
		expect(holder.Rotation).toBe(0)
		local disc = holder:FindFirstChild("Blot")
		expect(disc.ClassName).toBe("Frame")
		expect(disc.Rotation).toBe(0)
		expect(disc.BackgroundColor3).toBe(Theme.Colors.Primary)
		expect(disc:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
		local stroke = disc:FindFirstChildOfClass("UIStroke")
		expect(stroke.Color).toBe(Theme.Colors.Accent)
		expect(stroke.Thickness).toBeGreaterThanOrEqual(2)
		expect(stroke.Thickness).toBeLessThanOrEqual(3)
		-- 32 tall, and never narrower: a count of two figures stretches it into a pill.
		expect(disc.Size.Y.Offset).toBe(32)
		expect(disc.AutomaticSize.Name).toBe("X")
		expect(holder.AutomaticSize.Name).toBe("X")
		expect(disc:FindFirstChildOfClass("UISizeConstraint").MinSize).toBe(roblox.Vector2.new(32, 32))
		expect(disc:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset).toBeGreaterThan(0)
		local count = disc:FindFirstChild("Count")
		expect(count.Text).toBe("3")
		expect(count.FontFace).toBe(Theme.Fonts.Numeric)
		expect(count.TextColor3).toBe(Theme.Colors.Text)
		expect(count.TextScaled == true).toBe(false)
		expect(count.TextSize).toBe(17)
		-- Nothing drawn from a texture: no ink blot image.
		for _, part in ipairs(holder:GetDescendants()) do
			expect(part:IsA("ImageLabel")).toBe(false)
		end
	end)

	it("takes the sheet on a host of the primary yellow", function()
		local _world, Badge, Theme, host = bench()
		local badge = Badge.new("!", host, Theme.Colors.PanelRaised)
		expect(badge.Instance:FindFirstChild("Blot").BackgroundColor3).toBe(Theme.Colors.PanelRaised)
		expect(badge.Instance:FindFirstChild("Count", true).Text).toBe("!")
	end)

	it("sits astride the corner of a host too short to hold it, and inside again when the host grows", function()
		local _world, Badge, _Theme, host = bench()
		-- A claim seal of the hub.
		host.AbsoluteSize = roblox.Vector2.new(36, 36)
		local badge = Badge.new(2, host)
		expect(badge.Instance.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
		expect(badge.Instance.Position).toBe(roblox.UDim2.fromScale(1, 0))
		-- A menu tile, once laid out.
		host.AbsoluteSize = roblox.Vector2.new(220, 150)
		expect(badge.Instance.AnchorPoint).toBe(roblox.Vector2.new(1, 0))
		expect(badge.Instance.Position).toBe(roblox.UDim2.new(1, -8, 0, 8))
		-- Twice the disc is tall enough.
		host.AbsoluteSize = roblox.Vector2.new(64, 64)
		expect(badge.Instance.AnchorPoint).toBe(roblox.Vector2.new(1, 0))
		host.AbsoluteSize = roblox.Vector2.new(63, 63)
		expect(badge.Instance.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
	end)

	it("pops in, breathes while it shows, and hides for nothing to claim", function()
		local world, Badge, _Theme, host = bench()
		local badge = Badge.new(1, host)
		local breath = badge.Instance:FindFirstChildOfClass("UIScale")
		local seen: { [number]: boolean } = {}
		for _ = 1, 4 * 60 do
			world:frames(1)
			seen[math.floor(breath.Scale * 100 + 0.5)] = true
		end
		local values = 0
		for _ in pairs(seen) do
			values += 1
		end
		expect(values).toBeGreaterThan(3)
		badge:Set(0)
		expect(badge.Instance.Visible).toBe(false)
		expect(breath.Scale).toBe(1)
		badge:Set(12)
		expect(badge.Instance.Visible).toBe(true)
		expect(badge.Instance:FindFirstChild("Count", true).Text).toBe("12")
		badge:Destroy()
		world:advance(3)
		expect(world.Heartbeat:count()).toBe(0)
	end)
end)

return nil
