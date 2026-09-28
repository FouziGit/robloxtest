--!strict
-- Draw: the stateless drawing helpers the world's builders share -- a part in the one material, a disc drawn
-- flat on a floor, a neutral emblem on a panel. Moved out of HubService when the portal gates (PortalGate)
-- needed the same three things in the hub, in the Erasure's arena and in the Battleground: one way to draw a
-- seal, wherever it lies.
--
-- Nothing here keeps state or reads a service. Each call builds what it is asked for and hands it back
-- unparented (the emblem goes onto the panel it is given). Every colour comes in as a Color3 the caller took
-- from Palette.world(role): a builder names roles, never a colour of its own (tests/WorldConfig.spec.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = ReplicatedStorage:WaitForChild("UI")

local Palette = require(Shared.Util.Palette)
local Theme = require(Ui.Theme)
local WorldConfig = require(Shared.Config.WorldConfig)

-- Everything drawn flat on a floor is a slab this thick, sunk into the floor so only its top sliver shows.
local FLAT_THICKNESS_STUDS = WorldConfig.FlatThicknessStuds
local EMBLEM_PIXELS_PER_STUD = 64
local EMBLEM_STROKE_PIXELS = 6

local Draw = {}

-- An anchored part in the world's one material, smooth on top and underneath.
function Draw.part(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = Palette.material()
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- A cylinder's flat faces are on its X axis, so a disc is rolled a quarter turn to lie flat. `center` is a
-- point on the floor's top face, and `top` is where the disc's upper face lands, in studs above it: a rung of
-- WorldConfig.Ladder. Decoration only: nothing collides with a disc, queries it or touches it.
function Draw.flatDisc(name: string, diameter: number, center: Vector3, top: number, color: Color3): Part
	local part = Draw.part(
		name,
		Vector3.new(FLAT_THICKNESS_STUDS, diameter, diameter),
		CFrame.new(center.X, center.Y + top - FLAT_THICKNESS_STUDS / 2, center.Z) * CFrame.Angles(0, 0, math.pi / 2),
		color
	)
	part.Shape = Enum.PartType.Cylinder
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- Neutral emblem on the panel's front face: a ring plus straight bars at the given rotations (degrees), no
-- text, identical for every viewer -- a server-built SurfaceGui reads the same to everyone, so the words that
-- go with it are each client's (HubSignsController, D-128).
function Draw.emblem(panel: BasePart, accent: Color3, bars: { number })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Emblem"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = EMBLEM_PIXELS_PER_STUD
	gui.LightInfluence = 0

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.Colors.Panel
	background.BorderSizePixel = 0
	background.Parent = gui

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.8, 0.8)
	ring.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ring.BackgroundTransparency = 1
	ring.Parent = background

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = EMBLEM_STROKE_PIXELS
	stroke.Parent = ring

	for index, rotation in ipairs(bars) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. index
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(0.12, 0.6)
		bar.SizeConstraint = Enum.SizeConstraint.RelativeYY
		bar.Rotation = rotation
		bar.BackgroundColor3 = accent
		bar.BorderSizePixel = 0
		bar.Parent = ring
	end

	gui.Parent = panel
end

return Draw
