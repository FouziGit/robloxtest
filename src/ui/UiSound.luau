--!strict
-- UiSound: how a component plays the sound of the interface without requiring a client controller (src/ui
-- never does). The client bootstrap hands it SoundController.play once; until then a play is silent, which
-- only matters for a click nobody can have made yet.

local UiSound = {}

local player: ((id: string) -> ())? = nil

function UiSound.setPlayer(play: (id: string) -> ())
	player = play
end

-- Plays the SoundConfig cue `id` (a click, a claim).
function UiSound.play(id: string)
	local play = player
	if play ~= nil then
		play(id)
	end
end

return UiSound
