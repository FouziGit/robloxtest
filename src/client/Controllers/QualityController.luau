--!strict
-- QualityController: the one place that knows what this client is allowed to draw right now.
--
-- Two inputs. The player's setting, which is a CEILING they own (Settings.Quality), and the frame rate,
-- which can push the effective tier below it and give it back later. Nothing else decides: VfxTimeline,
-- WorldLighting and FootprintController all ask here, so a client that is struggling thins every system at
-- once instead of one system noticing and the others carrying on.
--
-- docs/JUICE_PLAN.md phase 9, and art bible rule 8: an effect we cannot afford to draw is an effect we do
-- not draw. The measurement is deliberately dumb -- frames counted over a second, averaged -- because the
-- decision it feeds is coarse: one step down after three bad seconds, one step back after twelve good
-- ones. A cleverer estimator would move the tier on a single hitch, and a tier that oscillates costs more
-- than the tier it was trying to leave (every change re-enables post-processing, which compiles shaders).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local QualityConfig = require(Shared.Config.QualityConfig)
local Signal = require(Packages.Signal)

local log = Log.new("QualityController")

type Deps = { ClientData: any }

local AUTO = QualityConfig.Auto

local QualityController = {}

-- (tier: QualityConfig.Tier) -- the EFFECTIVE tier, after the frame rate has had its say.
QualityController.Changed = Signal.new()

local clientData: any
-- What the player asked for, and what they are getting. Held as plain strings, always a name
-- QualityConfig.isTier accepts: the union lives in the config, and every value here has been through it.
local chosen: string = QualityConfig.Default
local effective: string = QualityConfig.Default
-- Rolling frame counter.
local frames = 0
local elapsed = 0
local belowFor = 0
local aboveFor = 0

local function apply(tier: string, why: string)
	if tier == effective then
		return
	end
	effective = tier
	belowFor = 0
	aboveFor = 0
	log.info("drawing at %s (%s)", tier, why)
	QualityController.Changed:Fire(tier)
end

-- The tier being drawn right now.
function QualityController.get(): string
	return effective
end

-- Its row. Every caller reads this per use rather than caching it, so a change needs no subscription to
-- take effect on the next layer, the next print or the next pulse.
function QualityController.def(): QualityConfig.TierDef
	return QualityConfig.tier(effective)
end

-- What the player chose, which is the ceiling the frame rate may fall below but never rise above.
function QualityController.chosen(): string
	return chosen
end

local function readProfile()
	local data = clientData.get()
	if data == nil then
		return
	end
	local wanted = data.Settings.Quality
	if not QualityConfig.isTier(wanted) then
		wanted = QualityConfig.Default
	end
	if wanted == chosen then
		return
	end
	chosen = wanted
	-- A new ceiling resets the automatic part: the player has just told us what they want, and holding a
	-- drop decided under the old ceiling against them would make the setting look broken.
	apply(chosen, "chosen by the player")
end

local function onHeartbeat(deltaTime: number)
	frames += 1
	elapsed += deltaTime
	if elapsed < AUTO.SampleSeconds then
		return
	end
	local fps = frames / elapsed
	local sample = elapsed
	frames = 0
	elapsed = 0

	if fps < AUTO.DropBelowFps then
		aboveFor = 0
		belowFor += sample
		if belowFor >= AUTO.DropAfterSeconds then
			local lower = QualityConfig.lower(effective)
			if lower ~= nil then
				apply(lower, string.format("%d fps", math.floor(fps)))
			else
				belowFor = 0
			end
		end
	elseif fps > AUTO.RaiseAboveFps then
		belowFor = 0
		aboveFor += sample
		if aboveFor >= AUTO.RaiseAfterSeconds and effective ~= chosen then
			local higher = QualityConfig.higher(effective)
			if higher ~= nil then
				apply(QualityConfig.worse(higher, chosen), string.format("%d fps", math.floor(fps)))
			end
		end
	else
		-- Between the two thresholds nothing is decided, and neither timer runs: the gap is what keeps a
		-- client sitting at fifty frames from stepping down and up forever.
		belowFor = 0
		aboveFor = 0
	end
end

function QualityController.Init(deps: Deps)
	clientData = deps.ClientData
end

function QualityController.Start()
	readProfile()
	clientData.Changed:Connect(function(section: string)
		if section == "*" or section == "Settings" then
			readProfile()
		end
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started at %s (drops under %d fps, recovers over %d)", effective, AUTO.DropBelowFps, AUTO.RaiseAboveFps)
end

return QualityController
