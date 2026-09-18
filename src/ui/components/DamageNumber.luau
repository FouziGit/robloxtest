--!strict
-- DamageNumber: one floating number over the world, pooled.
--
-- Pooled rather than created per hit, because this is the single most frequent visual in the game. A
-- six-player arena lands several hits a second, each one is a Part plus a BillboardGui plus a TextLabel
-- plus a UIStroke, and creating and destroying four instances several times a second is how a Roblox
-- client starts hitching after ninety seconds of play. The pool is capped: past the cap the oldest
-- number is taken back and reused, so this can never grow without bound whatever the fight does.
--
-- The component owns the instances and their look. It does not animate: Feel drives the motion from the
-- one render loop, so twenty numbers cost one connection rather than twenty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FeelConfig = require(Shared.Config.FeelConfig)
local Theme = require(script.Parent.Parent.Theme)

export type Marker = {
	Anchor: Part,
	Billboard: BillboardGui,
	Label: TextLabel,
	Stroke: UIStroke,
}

local DamageNumber = {}

local CONTAINER_NAME = "VellumDamageNumbers"
-- Wide enough that a five-digit number never wraps, tall enough for the stroke not to clip.
local BILLBOARD_SIZE = UDim2.fromOffset(220, 60)
-- Past this the number is somebody else's fight and is not drawn at all.
local MAX_DISTANCE_STUDS = 160
local STROKE_THICKNESS = 2.5

local container: Folder? = nil
local pool: { Marker } = {}

local function ensureContainer(): Folder
	local existing = container
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = Workspace
	container = folder
	return folder
end

local function build(): Marker
	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumber"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.05
	anchor.Parent = ensureContainer()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Number"
	billboard.Size = BILLBOARD_SIZE
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE_STUDS
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Fonts.Numeric
	label.TextScaled = false
	label.TextSize = FeelConfig.DamageNumbers.BaseTextSize
	label.Text = ""
	label.Parent = billboard

	-- The stroke is what keeps a number readable over a bright explosion, which is exactly when it is
	-- most needed and least visible.
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = STROKE_THICKNESS
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.15
	stroke.Parent = label

	return { Anchor = anchor, Billboard = billboard, Label = label, Stroke = stroke }
end

-- Takes a marker from the pool, or builds one. The caller always returns it through release.
function DamageNumber.acquire(): Marker
	local marker = table.remove(pool)
	if marker ~= nil and marker.Anchor.Parent ~= nil then
		marker.Billboard.Enabled = true
		return marker
	end
	return build()
end

-- Hides a marker and puts it back. Never destroys: the whole point is that the next hit costs nothing.
function DamageNumber.release(marker: Marker)
	if marker.Anchor.Parent == nil then
		return
	end
	marker.Billboard.Enabled = false
	marker.Label.Text = ""
	-- Out of the way, so a disabled billboard cannot flicker into view for one frame when the pool
	-- hands it back before the next position is written.
	marker.Anchor.CFrame = CFrame.new(0, -500, 0)
	if #pool >= FeelConfig.DamageNumbers.MaxConcurrent then
		marker.Anchor:Destroy()
		return
	end
	table.insert(pool, marker)
end

-- Sets what a marker says and how it looks, once, at the moment it is spawned.
function DamageNumber.dress(marker: Marker, text: string, color: Color3, sizeScale: number)
	marker.Label.Text = text
	marker.Label.TextColor3 = color
	marker.Label.TextSize = math.floor(FeelConfig.DamageNumbers.BaseTextSize * sizeScale + 0.5)
end

-- Places a marker and sets how far through its life it is. Called every frame by Feel.
function DamageNumber.place(marker: Marker, position: Vector3, transparency: number, scale: number)
	marker.Anchor.CFrame = CFrame.new(position)
	marker.Label.TextTransparency = transparency
	marker.Stroke.Transparency = math.clamp(transparency + 0.15, 0, 1)
	marker.Billboard.Size = UDim2.fromOffset(BILLBOARD_SIZE.X.Offset * scale, BILLBOARD_SIZE.Y.Offset * scale)
end

-- Destroys the pool and its container. Called when the local character goes away for good, so a rejoin
-- does not inherit markers adorned to parts from the previous life.
function DamageNumber.clear()
	for _, marker in ipairs(pool) do
		marker.Anchor:Destroy()
	end
	table.clear(pool)
	local folder = container
	container = nil
	if folder ~= nil then
		folder:Destroy()
	end
end

return DamageNumber
