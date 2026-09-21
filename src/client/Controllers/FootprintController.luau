--!strict
-- FootprintController: the page remembers where you walked.
--
-- Under every step of every character this client can see, an ink print (WorldConfig.Footprints.Layer)
-- is stamped on the floor and fades in a few seconds. It is the world reacting to the one thing that
-- happens on it all the time, and it is unmistakably this game: a floor that takes ink from feet is a
-- page. Drawn through VfxTimeline.stamp, so a print is a mark like any other -- same pool, same ground
-- probe, same eviction -- and this file owns only WHEN to stamp.
--
-- One Heartbeat for every character; no connection per character. Characters are read from Players each
-- frame, which is what makes a respawn or a leave cost nothing to track.
--
-- Three budgets, because a print is cheap and a crowd is not:
--   * MaxPerCharacter -- one player at a run lays a print every 0.15 s, so without a per-character share
--     the first walker in the list would hold every slot and nobody else would leave a mark at all;
--   * MaxLive -- prints alive at once on this client, all characters together, spent on the characters
--     NEAREST the camera first, which is almost always the local player;
--   * YieldAboveLayers -- no print is stamped while the timeline is already carrying that many layers.
--     Eviction inside the timeline is oldest-first across every effect, so this is the budget that keeps
--     a crowd walking past a duel from pushing the duel's own residue off the screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local Palette = require(Shared.Util.Palette)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("FootprintController")

type Deps = { VfxTimeline: any }

-- Where a character last left a print, which foot is next, and when each of its own prints expires.
type Track = { Last: Vector3, Side: number, Expiries: { number } }
-- One character worth stamping this frame, with its distance to the camera.
type Candidate = { Character: Model, Root: BasePart, Distance: number }

local STAMP_ID = "Footprint"
local FOOTPRINTS = WorldConfig.Footprints
local PRINT_SECONDS = FOOTPRINTS.Layer.At + FOOTPRINTS.Layer.For
-- Below this horizontal speed a character is standing, whatever its root's drift.
local MOVING_STUDS_PER_SECOND = 1

local FootprintController = {}

local timeline: any
local tracks: { [Model]: Track } = {}
-- The ink is the world's, not the interface's: one source for one colour (WorldConfig.Colors.Ink).
local inkColor = Palette.world(FOOTPRINTS.Color)

local function prune(track: Track, now: number)
	local expiries = track.Expiries
	while #expiries > 0 and expiries[1] <= now do
		table.remove(expiries, 1)
	end
end

local function liveCount(): number
	local total = 0
	for _, track in pairs(tracks) do
		total += #track.Expiries
	end
	return total
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
		table.insert(track.Expiries, now + PRINT_SECONDS)
	end
	track.Last = cframe.Position
	track.Side = -track.Side
end

local function onHeartbeat()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	-- A fight owns the layer budget: while the timeline is busy, the floor stops taking prints rather
	-- than pushing an effect's residue out of the pool.
	local stats = timeline.stats()
	local busy = type(stats) == "table" and (stats.Live or 0) >= FOOTPRINTS.YieldAboveLayers

	local now = os.clock()
	local eye = camera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	local candidates: { Candidate } = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character ~= nil and character.Parent ~= nil then
			seen[character] = true
			local track = tracks[character]
			local root, moving = walking(character)
			if root == nil then
				continue
			end
			if track == nil then
				-- A character just found starts its trail under its next stride, not under wherever it
				-- happened to be when this client noticed it.
				tracks[character] = { Last = root.Position, Side = 1, Expiries = {} }
				continue
			end
			prune(track, now)
			local distance = (root.Position - eye).Magnitude
			if
				moving
				and not busy
				and distance <= FOOTPRINTS.RangeStuds
				and #track.Expiries < FOOTPRINTS.MaxPerCharacter
				and (root.Position - track.Last).Magnitude >= FOOTPRINTS.StrideStuds
			then
				table.insert(candidates, { Character = character, Root = root, Distance = distance })
			end
		end
	end

	-- Nearest first: the slots left go to the characters the player is actually looking at.
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.Distance < b.Distance
	end)
	local remaining = FOOTPRINTS.MaxLive - liveCount()
	for _, candidate in ipairs(candidates) do
		if remaining <= 0 then
			break
		end
		local track = tracks[candidate.Character]
		if track ~= nil then
			stamp(candidate.Root, track, now)
			remaining -= 1
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
	log.info(
		"started: a print every %.1f studs, %d alive at most (%d each)",
		FOOTPRINTS.StrideStuds,
		FOOTPRINTS.MaxLive,
		FOOTPRINTS.MaxPerCharacter
	)
end

return FootprintController
