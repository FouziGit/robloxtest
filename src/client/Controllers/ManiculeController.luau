--!strict
-- ManiculeController: the Manicule of the Flyleaf (E16-S2) -- the pointing hand of a manuscript's margins, which
-- marks a member who took FlyleafConfig.ManiculeKills lives without losing theirs. It hangs over their head, pointing
-- down at them, for every client that sees them.
--
-- Who wears it is the server's word alone: FlyleafService marks the body with FlyleafConfig.ManiculeAttribute and
-- takes the mark off, and a body that dies takes it with it. An attribute a client sets never leaves that client,
-- so a client that marks itself only fools its own screen. Drawn in the world's two tints, ink on a chalk outline
-- (docs/ART_BIBLE.md rule 1: the world is never saturated), in sight only -- never through a wall -- and it grows
-- into place (rule 3: nothing appears). No loop: each body's attribute says when it changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local FlyleafConfig = require(Shared.Config.FlyleafConfig)
local Log = require(Shared.Util.Log)
local Motion = require(UI.Motion)
local Palette = require(Shared.Util.Palette)
local Trove = require(Packages.Trove)

local log = Log.new("ManiculeController")

type TroveType = typeof(Trove.new())

local ATTRIBUTE = FlyleafConfig.ManiculeAttribute
local HEAD_NAME = "Head"
-- The hand in studs, and how far over the head it hangs; read out to where a rival's name would still be read.
local MARK_STUDS = Vector2.new(2.2, 2.8)
local HEAD_CLEARANCE_STUDS = 2.9
local MAX_DISTANCE_STUDS = 150
-- The hand's pieces, in fractions of the mark: the cuff at the top, the palm, the thumb on its side and the index
-- pointing down. Each is an ink shape with a chalk outline.
local PIECES = {
	{ Name = "Cuff", Position = { 0.5, 0.1 }, Size = { 0.6, 0.16 }, Rotation = 0, Round = 0.2 },
	{ Name = "Palm", Position = { 0.5, 0.36 }, Size = { 0.52, 0.3 }, Rotation = 0, Round = 0.3 },
	{ Name = "Thumb", Position = { 0.2, 0.4 }, Size = { 0.14, 0.24 }, Rotation = -25, Round = 0.5 },
	{ Name = "Index", Position = { 0.56, 0.68 }, Size = { 0.16, 0.44 }, Rotation = 0, Round = 0.5 },
}
local OUTLINE_PIXELS = 2
local ENTER_SCALE = 0

local ManiculeController = {}

-- Where the marks are drawn from, resolved once the client starts.
local playerGui: Instance? = nil
-- Body -> its mark, while it wears one.
local marks: { [Model]: BillboardGui } = {}
-- Each body's connections, and each player's.
local bodyTroves: { [Model]: TroveType } = {}
local playerTroves: { [Player]: TroveType } = {}

local function erase(character: Model)
	local mark: BillboardGui? = marks[character]
	marks[character] = nil
	if mark ~= nil then
		mark:Destroy()
	end
end

-- The hand over `character`'s head, pointing down.
local function draw(character: Model)
	local existing: BillboardGui? = marks[character]
	if existing ~= nil then
		return
	end
	local head = character:FindFirstChild(HEAD_NAME)
	local gui = playerGui
	if head == nil or not head:IsA("BasePart") or gui == nil then
		return
	end
	local ink = Palette.world("Ink")
	local chalk = Palette.world("Chalk")
	local mark = Instance.new("BillboardGui")
	mark.Name = "Manicule"
	mark.Adornee = head
	mark.Size = UDim2.fromScale(MARK_STUDS.X, MARK_STUDS.Y)
	mark.StudsOffsetWorldSpace = Vector3.new(0, HEAD_CLEARANCE_STUDS, 0)
	mark.MaxDistance = MAX_DISTANCE_STUDS
	mark.AlwaysOnTop = false
	mark.LightInfluence = 0
	mark.ResetOnSpawn = false
	local hand = Instance.new("Frame")
	hand.Name = "Hand"
	hand.BackgroundTransparency = 1
	hand.Size = UDim2.fromScale(1, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = hand
	for _, piece in ipairs(PIECES) do
		local shape = Instance.new("Frame")
		shape.Name = piece.Name
		shape.AnchorPoint = Vector2.new(0.5, 0.5)
		shape.Position = UDim2.fromScale(piece.Position[1], piece.Position[2])
		shape.Size = UDim2.fromScale(piece.Size[1], piece.Size[2])
		shape.Rotation = piece.Rotation
		shape.BackgroundColor3 = ink
		shape.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(piece.Round, 0)
		corner.Parent = shape
		local outline = Instance.new("UIStroke")
		outline.Color = chalk
		outline.Thickness = OUTLINE_PIXELS
		outline.LineJoinMode = Enum.LineJoinMode.Round
		outline.Parent = shape
		shape.Parent = hand
	end
	hand.Parent = mark
	mark.Parent = gui
	marks[character] = mark
	Motion.set(scale, { Scale = ENTER_SCALE })
	Motion.to(scale, { Scale = 1 }, "UiPop")
end

local function refresh(character: Model)
	if character:GetAttribute(ATTRIBUTE) == true and character.Parent ~= nil then
		draw(character)
	else
		erase(character)
	end
end

local function unbind(character: Model)
	erase(character)
	local trove = bodyTroves[character]
	bodyTroves[character] = nil
	if trove ~= nil then
		trove:Destroy()
	end
end

local function bind(character: Model)
	if bodyTroves[character] ~= nil then
		return
	end
	local trove = Trove.new()
	bodyTroves[character] = trove
	trove:Connect(character:GetAttributeChangedSignal(ATTRIBUTE), function()
		refresh(character)
	end)
	trove:Connect(character.AncestryChanged, function()
		if character.Parent == nil then
			unbind(character)
		end
	end)
	refresh(character)
end

local function watch(player: Player)
	if playerTroves[player] ~= nil then
		return
	end
	local trove = Trove.new()
	playerTroves[player] = trove
	trove:Connect(player.CharacterAdded, bind)
	trove:Connect(player.CharacterRemoving, unbind)
	local character = player.Character
	if character ~= nil then
		bind(character)
	end
end

local function forget(player: Player)
	local trove = playerTroves[player]
	playerTroves[player] = nil
	if trove ~= nil then
		trove:Destroy()
	end
	local character = player.Character
	if character ~= nil then
		unbind(character)
	end
end

function ManiculeController.Start()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(forget)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	log.info("started")
end

return ManiculeController
