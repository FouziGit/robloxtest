--!strict
-- Sway: the one way a claim that waits is found (D-XXX). Every Claim button a screen names tilts DEGREES each way
-- on the shared "Wiggle" breath (Breath), once every Theme.Timing.WiggleEverySeconds, all of them together: one
-- idle loop for a whole screen of claims, however many (ThemeConfig.Budget.MaxIdleLoops). Under reduced motion
-- the breath rests at its first value, and every button rests upright with it. The Pass's track and the Quests'
-- board both sway this way; the quest card's own timer, a second way of doing the same thing, is gone.

local Breath = require(script.Parent.Breath)
local Theme = require(script.Parent.Theme)

local Sway = {}

local DEGREES = 2

-- Sways the buttons `buttons()` names, each time the breath moves, each with whether it may sway now: a claim
-- already sent rests upright. Returns the stop, which leaves the breath and sets every button it swayed upright.
function Sway.start(buttons: () -> { [GuiObject]: boolean }): () -> ()
	local reader = Breath.join("Wiggle", 0, 1, Theme.Timing.WiggleEverySeconds)
	-- Weak: a list that rebuilds its rows leaves the old buttons to the collector, not to this table.
	local swayed: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local connection = reader.Value.Changed:Connect(function(value: number)
		local rotation = DEGREES * math.sin(value * 2 * math.pi)
		for button, sways in pairs(buttons()) do
			button.Rotation = if sways then rotation else 0
			swayed[button] = true
		end
	end)
	return function()
		connection:Disconnect()
		reader.Leave()
		for button in pairs(swayed) do
			button.Rotation = 0
		end
	end
end

return Sway
