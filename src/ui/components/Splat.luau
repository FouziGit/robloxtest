--!strict
-- Splat: a blot of ink behind what matters -- a reward, a banner, a tile's icon, a burst (D-147). It is the
-- InkBlot texture every impact already leaves on the ground, tinted, so it costs no new asset. Its ink only
-- reaches 0.53 to 0.83 of its half-width (AssetIds), so a splat that backs an object is drawn about 1.6
-- times that object's size.
--
-- Splats are pooled per screen, under ThemeConfig.Budget.MaxSplats: a burst takes what a previous burst
-- released, and a screen that asks for more than its budget gets nil for the extra ones -- a splat is
-- decoration, and the one that is not drawn is the one nobody misses. Rotations come from a fixed list so
-- nothing jitters between two openings of the same screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Log"))
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)

local log = Log.new("Splat")

export type Props = {
	Size: UDim2,
	Tint: Color3,
	Parent: Instance,
	Rotation: number?,
	Transparency: number?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	Name: string?,
}

type Pool = { Live: number, Free: { GuiObject }, Warned: boolean }

local Splat = {}

local ROTATIONS = { -18, 7, 24, -9, 13, -4 }

-- One pool per screen (its ScreenGui), dropped with it.
local pools: { [Instance]: Pool } = setmetatable({}, { __mode = "k" }) :: any
local poolOf: { [GuiObject]: Pool } = setmetatable({}, { __mode = "k" }) :: any

-- The rotation of the `index`-th splat of a composition, from the fixed list.
function Splat.rotation(index: number): number
	return ROTATIONS[(index - 1) % #ROTATIONS + 1]
end

local function screenOf(parent: Instance): Instance
	if parent:IsA("ScreenGui") then
		return parent
	end
	return parent:FindFirstAncestorOfClass("ScreenGui") or parent
end

local function build(pool: Pool): GuiObject
	local id = Theme.texture("InkBlot")
	local splat: GuiObject
	if id ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = id
		image.ScaleType = Enum.ScaleType.Fit
		image.BackgroundTransparency = 1
		splat = image
	else
		-- Not uploaded: a disc says the same thing, less well.
		local disc = Instance.new("Frame")
		Theme.corner(disc, Theme.Pill)
		splat = disc
	end
	splat.BorderSizePixel = 0
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = splat
	pool.Live += 1
	poolOf[splat] = pool
	splat.Destroying:Once(function()
		pool.Live -= 1
		local index = table.find(pool.Free, splat)
		if index ~= nil then
			table.remove(pool.Free, index)
		end
	end)
	return splat
end

-- A splat under `props.Parent`, or nil when that screen has spent its budget.
function Splat.new(props: Props): GuiObject?
	local screen = screenOf(props.Parent)
	local pool = pools[screen]
	if pool == nil then
		pool = { Live = 0, Free = {}, Warned = false }
		pools[screen] = pool
	end
	local splat = table.remove(pool.Free)
	if splat == nil then
		if pool.Live >= Theme.Budget.MaxSplats then
			if not pool.Warned then
				pool.Warned = true
				log.warn(
					"%s asked for more than %d splats: the extra ones are not drawn",
					screen:GetFullName(),
					Theme.Budget.MaxSplats
				)
			end
			return nil
		end
		splat = build(pool)
	end
	local object = splat :: GuiObject
	object.Name = props.Name or "Splat"
	object.Visible = true
	object.Size = props.Size
	object.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	object.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	object.Rotation = props.Rotation or 0
	object.ZIndex = props.ZIndex or 1
	local transparency = props.Transparency or 0
	if object:IsA("ImageLabel") then
		object.ImageColor3 = props.Tint
		object.ImageTransparency = transparency
	else
		object.BackgroundColor3 = props.Tint
		object.BackgroundTransparency = transparency
	end
	object.Parent = props.Parent
	return object
end

-- Hands a splat back to its screen's pool: hidden, still, ready for the next burst.
function Splat.release(splat: GuiObject)
	local pool = poolOf[splat]
	if pool == nil or table.find(pool.Free, splat) ~= nil then
		return
	end
	Motion.cancel(splat)
	splat.Visible = false
	table.insert(pool.Free, splat)
end

return Splat
