--!strict
-- OnboardingController: the first glyph before the fifteenth second, without a word to read.
--
-- docs/JUICE_PLAN.md phase 8, item 6. A player whose profile has never cast a glyph is shown, in the
-- sequence row of the HUD, the recipe of the first glyph everyone starts with -- as ghost chips, the
-- same chips their own presses will draw, so the hint IS the thing to do rather than a description of
-- it. The moment a sequence resolves, the ghosts fold away and never come back: the profile now says
-- one glyph was cast, and the server is the one that says so.
--
-- Nothing here persists anything. The only state is the profile's Stats.GlyphsCast, which the server
-- writes; a hint drawn from a client flag would follow a player who never learned anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)

local log = Log.new("OnboardingController")

type Deps = { ClientData: any, ComboController: any, HudController: any }

local OnboardingController = {}

local clientData: any
local comboController: any
local hudController: any
local showing = false

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

local function onResolved()
	if not showing then
		return
	end
	showing = false
	hudController.showGhostSequence(nil)
end

function OnboardingController.Init(deps: Deps)
	clientData = deps.ClientData
	comboController = deps.ComboController
	hudController = deps.HudController
end

function OnboardingController.Start()
	clientData.Changed:Connect(function(section: string)
		if section == "*" or section == "Stats" then
			refresh()
		end
	end)
	comboController.SequenceResolved:Connect(onResolved)
	refresh()
	log.info("started")
end

return OnboardingController
