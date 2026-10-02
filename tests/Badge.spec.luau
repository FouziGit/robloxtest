--!strict
-- The badge, run (tests/engine.luau): the real Badge, Breath, Motion and Theme.
--
-- The board badges a menu tile with an upright disc inside its top-right corner, in an ink outline, its count
-- in the number face. The game's was an ink blot tipped 6 degrees and straddling the corner, its count scaled
-- into the blot in the label face.
local Engine = require("./engine")
local Harness = require("./harness")
local Measure = require("./measure")
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
		-- The theme's own badge size, which nothing else reads.
		expect(Theme.Sizes.Badge).toBe(disc.Size.Y.Offset)
		expect(disc.AutomaticSize.Name).toBe("X")
		expect(holder.AutomaticSize.Name).toBe("X")
		expect(disc:FindFirstChildOfClass("UISizeConstraint").MinSize).toBe(roblox.Vector2.new(32, 32))
		-- The room either side of the count is the count's: padded, the disc was held to 32 before its padding
		-- was added, and a lone figure made a pill of 48 (seen in Studio). tests/layout.luau holds the rule.
		expect(disc:FindFirstChildOfClass("UIPadding")).toBeNil()
		local count = disc:FindFirstChild("Count")
		local room = count:FindFirstChildOfClass("UIPadding")
		assert(room ~= nil, "the count has no room either side: a two-figure count would touch the ink")
		expect(room.PaddingLeft.Offset).toBeGreaterThan(0)
		expect(room.PaddingRight.Offset).toBe(room.PaddingLeft.Offset)
		expect(count.Text).toBe("3")
		expect(count.FontFace).toBe(Theme.Fonts.Numeric)
		expect(count.TextColor3).toBe(Theme.Colors.Text)
		expect(count.TextScaled == true).toBe(false)
		expect(count.TextSize).toBe(17)
		-- In the middle of the disc: a lone figure is narrower than the disc's least width, and laid out from the
		-- left it sat against the disc's left edge.
		local centre = disc:FindFirstChildOfClass("UIListLayout")
		assert(centre ~= nil, "the disc lays its count out from the left")
		expect(centre.FillDirection.Name).toBe("Horizontal")
		expect(centre.HorizontalAlignment.Name).toBe("Center")
		expect(centre.VerticalAlignment.Name).toBe("Center")
		expect(count.Parent).toBe(disc)
		-- Nothing drawn from a texture: no ink blot image.
		for _, part in ipairs(holder:GetDescendants()) do
			expect(part:IsA("ImageLabel")).toBe(false)
		end
	end)

	it("is as large as the theme's badge size", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Theme = world.require("src/ui/Theme")
		Theme.Sizes.Badge = 40
		local Badge = world.require("src/ui/components/Badge")
		local host = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
		local disc = Badge.new(3, host).Instance:FindFirstChild("Blot")
		expect(disc.Size.Y.Offset).toBe(40)
		expect(disc:FindFirstChildOfClass("UISizeConstraint").MinSize).toBe(roblox.Vector2.new(40, 40))
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

	it("is half as tall as a host it sits astride, its count and outline with it, and whole again inside", function()
		local _world, Badge, Theme, host = bench()
		-- A claim seal of the hub, which the whole disc covered almost entirely (seen in play).
		host.AbsoluteSize = roblox.Vector2.new(36, 36)
		local holder = Badge.new(1, host).Instance
		local disc = holder:FindFirstChild("Blot")
		local count = disc:FindFirstChild("Count")
		local room = count:FindFirstChildOfClass("UIPadding")
		local function outline(): any
			local found = {}
			for _, child in ipairs(disc:GetChildren()) do
				if child.ClassName == "UIStroke" then
					table.insert(found, child)
				end
			end
			expect(#found).toBe(1)
			return found[1]
		end
		-- Centred on the corner and half the seal tall: a quarter of the seal each way from it.
		expect(holder.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
		expect(holder.Position).toBe(roblox.UDim2.fromScale(1, 0))
		expect(disc.Size.Y.Offset).toBe(18)
		expect(holder.Size.Y.Offset).toBe(18)
		expect(disc:FindFirstChildOfClass("UISizeConstraint").MinSize).toBe(roblox.Vector2.new(18, 18))
		expect(disc.Size.Y.Offset / 2).toBeLessThanOrEqual(36 / 4)
		-- Its count scaled to match in the number face, and a lone figure still the disc, with room either side.
		expect(count.TextSize).toBe(12)
		expect(count.FontFace).toBe(Theme.Fonts.Numeric)
		expect(room.PaddingLeft.Offset).toBeGreaterThan(0)
		expect(room.PaddingRight.Offset).toBe(room.PaddingLeft.Offset)
		expect(Measure.textWidth(count.Text, count.TextSize) + room.PaddingLeft.Offset * 2).toBeLessThanOrEqual(18)
		-- Still the primary yellow in its ink, in the thin outline.
		expect(disc.BackgroundColor3).toBe(Theme.Colors.Primary)
		expect(outline().Color).toBe(Theme.Colors.Accent)
		expect(outline().Thickness).toBe(Theme.Sizes.StrokeThin)
		-- The Menu quick button: half of it too.
		host.AbsoluteSize = roblox.Vector2.new(120, 52)
		expect(disc.Size.Y.Offset).toBe(26)
		expect(count.TextSize).toBe(17)
		expect(Measure.textWidth(count.Text, count.TextSize) + room.PaddingLeft.Offset * 2).toBeLessThanOrEqual(26)
		-- A menu tile: the whole disc inside its corner again, as it was.
		host.AbsoluteSize = roblox.Vector2.new(220, 150)
		expect(disc.Size.Y.Offset).toBe(32)
		expect(holder.Size.Y.Offset).toBe(32)
		expect(disc:FindFirstChildOfClass("UISizeConstraint").MinSize).toBe(roblox.Vector2.new(32, 32))
		expect(count.TextSize).toBe(17)
		expect(room.PaddingLeft.Offset).toBe(8)
		expect(outline().Thickness).toBe(Theme.Sizes.Stroke)
	end)

	it("reaches above a small host no further than its overhang, at the top of its breath", function()
		local world, Badge, _Theme, host = bench()
		host.AbsoluteSize = roblox.Vector2.new(36, 36)
		local badge = Badge.new(1, host)
		local breath = badge.Instance:FindFirstChildOfClass("UIScale")
		local peak = 1
		for _ = 1, 4 * 60 do
			world:frames(1)
			peak = math.max(peak, breath.Scale)
		end
		expect(peak).toBeGreaterThan(1)
		-- Centred on the host's top edge, it swells about its middle: half of it above the edge.
		expect(badge.Instance.AnchorPoint.Y).toBe(0.5)
		local disc = badge.Instance:FindFirstChild("Blot").Size.Y.Offset
		local reach = disc * peak / 2
		expect(Badge.overhang(36)).toBeGreaterThanOrEqual(reach)
		expect(Badge.overhang(36)).toBeLessThan(reach + 1)
		-- Inside its host, it reaches nothing above it.
		expect(Badge.overhang(64)).toBe(0)
	end)

	it("keeps its thin outline 2 pixels thick on a phone", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		Engine.phone(world, 667, 375)
		local Badge = world.require("src/ui/components/Badge")
		local Theme = world.require("src/ui/Theme")
		local host = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
		local scale = Theme.activeScale()
		expect(scale).toBeLessThan(1)
		-- A claim seal of the hub, as the engine measures it on the phone.
		host.AbsoluteSize = roblox.Vector2.new(36 * scale, 36 * scale)
		local disc = Badge.new(1, host).Instance:FindFirstChild("Blot")
		expect(disc.Size.Y.Offset).toBe(18)
		expect(disc:FindFirstChildOfClass("UIStroke").Thickness).toBeGreaterThanOrEqual(2 / scale)
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
