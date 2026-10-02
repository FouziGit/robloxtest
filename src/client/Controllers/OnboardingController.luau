--!strict
-- OnboardingController: the first glyph before the fifteenth second, without a word to read.
--
-- docs/JUICE_PLAN.md phase 8, item 6. A player whose profile has never cast a glyph is shown, in the
-- sequence row of the HUD, the recipe of the first glyph everyone starts with -- as ghost chips, the
-- same chips their own presses will draw, so the hint IS the thing to do rather than a description of
-- it; with a pointer each stands under the key that presses it, and on touch the discs breathe (D-147).
-- The ghosts fold on the first press. They come back once the sequence is empty again without a cast the
-- server confirmed -- it broke, it dissipated, it was refused -- until the profile says one glyph was
-- cast, and the server is the one that says so.
--
-- Nothing here persists anything. The only state is the profile's Stats.GlyphsCast, which the server
-- writes; a hint drawn from a client flag would follow a player who never learned anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)

local log = Log.new("OnboardingController")

type Deps = { ClientData: any, ComboController: any, HudController: any, VfxController: any }

local OnboardingController = {}

local clientData: any
local comboController: any
local hudController: any
local vfxController: any
local showing = false
-- The ghosts come back this long after the sequence empties: long enough for the server's word on a cast, and
-- for a refusal said under the chips to go first. A press or a confirmed cast in the meantime cancels it.
local RETURN_SECONDS = 1.5
local returnToken = 0

-- The recipe of the first glyph unlocked by default: what a new player can cast at once.
local function firstRecipe(): { string }?
	local defaults = GlyphConfig.defaultUnlocks()
	local firstId = defaults[1]
	if firstId == nil then
		return nil
	end
	for _, def in ipairs(GlyphConfig.Glyphs) do
		if def.Id == firstId then
			return table.clone(def.Combo)
		end
	end
	return nil
end

local function refresh()
	local data = clientData.get()
	if data == nil or showing then
		return
	end
	if data.Stats.GlyphsCast > 0 then
		return
	end
	local recipe = firstRecipe()
	if recipe == nil then
		log.warn("no default glyph to show a new player")
		return
	end
	showing = true
	hudController.showGhostSequence(recipe)
end

-- The hint has done its job the moment the player presses a pigment: the chips they drew are on the row,
-- and two ghost squares parked beside them for the rest of the session are two saturated things in the
-- scenery (rule 1). The profile is what decides whether it comes back next session.
local function dismiss()
	if not showing then
		return
	end
	showing = false
	hudController.showGhostSequence(nil)
end

local function onSequenceChanged(sequence: { string })
	returnToken += 1
	if #sequence > 0 then
		dismiss()
		return
	end
	local token = returnToken
	task.delay(RETURN_SECONDS, function()
		if token == returnToken then
			refresh()
		end
	end)
end

-- The server confirmed a cast: nothing comes back, and the profile's count follows.
local function onCast()
	returnToken += 1
	dismiss()
end

function OnboardingController.Init(deps: Deps)
	clientData = deps.ClientData
	comboController = deps.ComboController
	hudController = deps.HudController
	vfxController = deps.VfxController
end

function OnboardingController.Start()
	clientData.Changed:Connect(function(section: string)
		if section == "*" or section == "Stats" then
			refresh()
		end
	end)
	-- The server's own confirmation of an accepted cast, not the client's resolution of a sequence: a cast
	-- the server refuses for a cooldown or for ink has taught the player nothing.
	vfxController.LocalCast:Connect(onCast)
	comboController.SequenceChanged:Connect(onSequenceChanged)
	refresh()
	log.info("started")
end

return OnboardingController
