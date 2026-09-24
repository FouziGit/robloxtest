--!strict
-- LockMarker: the mark over the opponent a lock is on (LockOnController, D-115). A small diamond of
-- charcoal ink edged in vellum, so it reads over the page and over a dark body alike, floating above the
-- target's head and drawn over everything: a lock that cannot be seen behind a wall is a lock nobody
-- trusts. It clamps down onto the target when a lock is taken and lifts off when it is let go, on the
-- interface's springs (Motion); it never simply appears or vanishes. One for the session: built once by
-- LockOnController and re-aimed at each new target, so it has nothing to destroy.

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)

export type LockMarker = {
	Show: (self: LockMarker, adornee: BasePart, lift: number) -> (),
	Hide: (self: LockMarker) -> (),
}

local LockMarker = {}

-- How much larger the mark starts when a lock is taken, and ends when it is let go.
local TAKE_FROM_SCALE = 1.8
local LET_GO_SCALE = 0.5
local INK_THICKNESS = 3
local EDGE_THICKNESS = 5
-- The dot at its centre, as a share of the mark.
local DOT_SHARE = 0.22

-- Builds the mark, hidden, under `parent` (the local PlayerGui), `size` pixels across.
function LockMarker.new(parent: Instance, size: number): LockMarker
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LockMarker"
	-- Room for the diamond's corners at its widest, when it clamps down from TAKE_FROM_SCALE.
	billboard.Size = UDim2.fromOffset(size * 3, size * 3)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	billboard.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = 1

	-- Turned a quarter of a right angle: a diamond, the one shape no other mark in the game uses.
	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromOffset(size, size)
	diamond.Rotation = 45
	diamond.BackgroundTransparency = 1
	diamond.BorderSizePixel = 0
	diamond.Parent = billboard
	scale.Parent = diamond

	-- The vellum edge sits under the ink: a wider stroke on a frame of the same size behind it.
	local edgeFrame = Instance.new("Frame")
	edgeFrame.Name = "Edge"
	edgeFrame.Size = UDim2.fromScale(1, 1)
	edgeFrame.BackgroundTransparency = 1
	edgeFrame.BorderSizePixel = 0
	edgeFrame.ZIndex = 1
	edgeFrame.Parent = diamond
	local edge = Instance.new("UIStroke")
	edge.Color = Theme.Colors.Panel
	edge.Thickness = EDGE_THICKNESS
	edge.Transparency = 1
	edge.Parent = edgeFrame

	local inkFrame = Instance.new("Frame")
	inkFrame.Name = "Ink"
	inkFrame.Size = UDim2.fromScale(1, 1)
	inkFrame.BackgroundTransparency = 1
	inkFrame.BorderSizePixel = 0
	inkFrame.ZIndex = 2
	inkFrame.Parent = diamond
	local ink = Instance.new("UIStroke")
	ink.Color = Theme.Colors.Text
	ink.Thickness = INK_THICKNESS
	ink.Transparency = 1
	ink.Parent = inkFrame

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(DOT_SHARE, DOT_SHARE)
	dot.BackgroundColor3 = Theme.Colors.Text
	dot.BackgroundTransparency = 1
	dot.BorderSizePixel = 0
	dot.ZIndex = 3
	dot.Parent = diamond

	-- Which Show a Hide's settling belongs to: a lock let go and retaken at once must not be hidden by
	-- the first one's fade finishing.
	local generation = 0

	local function show(_self: LockMarker, adornee: BasePart, lift: number)
		generation += 1
		billboard.Adornee = adornee
		billboard.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
		billboard.Enabled = true
		Motion.set(scale, { Scale = TAKE_FROM_SCALE })
		Motion.to(scale, { Scale = 1 }, "UiSnappy")
		Motion.to(ink, { Transparency = 0 }, "UiSnappy")
		Motion.to(edge, { Transparency = 0.2 }, "UiSnappy")
		Motion.to(dot, { BackgroundTransparency = 0 }, "UiSnappy")
	end

	local function hide(_self: LockMarker)
		if not billboard.Enabled then
			return
		end
		generation += 1
		local mine = generation
		Motion.to(scale, { Scale = LET_GO_SCALE }, "UiSnappy")
		Motion.to(edge, { Transparency = 1 }, "UiSnappy")
		Motion.to(dot, { BackgroundTransparency = 1 }, "UiSnappy")
		Motion.to(ink, { Transparency = 1 }, "UiSnappy", function()
			if generation == mine then
				billboard.Enabled = false
			end
		end)
	end

	return { Show = show, Hide = hide }
end

return LockMarker
