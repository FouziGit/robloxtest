--!strict
-- FootprintController: the page remembers where you walked.
--
-- Under every step of every character this client can see, an ink print (WorldConfig.Footprints.Layer)
-- is stamped on the floor and fades in a few seconds. It is the world reacting to the one thing that
-- happens on it all the time, and it is unmistakably this game: a floor that takes ink from feet is a
-- page. Drawn through VfxTimeline.stamp, so a print is a mark like any other -- same pool, same ground
-- probe, same eviction -- and this file owns only WHEN to stamp.
--
-- One Heartbeat for every character; no connection per character. A character is found through
-- Players each frame, which is what makes a respawn or a leave cost nothing to track. The budget is
-- MaxLive prints alive at once on this client, counted by their own lifetime, so a crowd in the hub
-- can never evict a fight's own marks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local Log = require(Shared.Util.Log)
local Theme = require(UI.Theme)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("FootprintController")

type Deps = { VfxTimeline: any }

-- Where a character last left a print, and which foot is next.
type Track = { Last: Vector3, Side: number }

local STAMP_ID = "Footprint"
local FOOTPRINTS = WorldConfig.Footprints
-- Below this horizontal speed a character is standing, whatever its root's drift.
local MOVING_STUDS_PER_SECOND = 1

local FootprintController = {}

local timeline: any
local tracks: { [Model]: Track } = {}
-- os.clock at which each live print expires, oldest first.
local expiries: { number } = {}
-- The ink. A print is charcoal on the page; it is the interface's own ink, from the one theme.
local inkColor = Theme.Colors.Text

local function pruneExpired(now: number)
	while #expiries > 0 and expiries[1] <= now do
		table.remove(expiries, 1)
	end
end

-- Whether `character` is on the floor and walking: a foot in the air leaves nothing.
local function walking(character: Model): (BasePart?, boolean)
	local root = character.PrimaryPart
	if root == nil then
		return nil, false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return root, false
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector2.new(velocity.X, velocity.Z).Magnitude
	return root, speed >= MOVING_STUDS_PER_SECOND
end

local function stamp(root: BasePart, track: Track, now: number)
	local cframe = root.CFrame
	local forward = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if forward.Magnitude < 1e-3 then
		forward = Vector3.zAxis
	end
	local origin = cframe.Position + cframe.RightVector * (FOOTPRINTS.FootOffsetStuds * track.Side)
	if timeline.stamp(STAMP_ID, FOOTPRINTS.Layer, { Origin = origin, Direction = forward.Unit, Color = inkColor }) then
		table.insert(expiries, now + FOOTPRINTS.Layer.At + FOOTPRINTS.Layer.For)
	end
	track.Last = cframe.Position
	track.Side = -track.Side
end

local function onHeartbeat()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local now = os.clock()
	pruneExpired(now)
	local eye = camera.CFrame.Position
	local seen: { [Model]: boolean } = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character ~= nil and character.Parent ~= nil then
			seen[character] = true
			local root, moving = walking(character)
			if root ~= nil and moving and (root.Position - eye).Magnitude <= FOOTPRINTS.RangeStuds then
				local track = tracks[character]
				if track == nil then
					-- A character just found starts its trail under its next stride, not under where it
					-- happened to be when this client noticed it.
					tracks[character] = { Last = root.Position, Side = 1 }
				elseif
					(root.Position - track.Last).Magnitude >= FOOTPRINTS.StrideStuds
					and #expiries < FOOTPRINTS.MaxLive
				then
					stamp(root, track, now)
				end
			end
		end
	end

	for character in pairs(tracks) do
		if not seen[character] then
			tracks[character] = nil
		end
	end
end

function FootprintController.Init(deps: Deps)
	timeline = deps.VfxTimeline
end

function FootprintController.Start()
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started: a print every %.1f studs, %d alive at most", FOOTPRINTS.StrideStuds, FOOTPRINTS.MaxLive)
end

return FootprintController
