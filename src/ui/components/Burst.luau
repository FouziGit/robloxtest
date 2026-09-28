--!strict
-- Burst: blots of ink that pop out from behind something just acquired and fade (D-147) -- a purchase, a
-- claimed reward. The blots are the screen's own pooled splats (Splat), handed back once they have faded,
-- so a burst costs no budget after it; a screen that has spent its splats simply bursts fewer. Under reduced
-- motion the blots only fade: a burst is decoration, and its size is the part that moves.

local Motion = require(script.Parent.Parent.Motion)
local Splat = require(script.Parent.Splat)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

local Burst = {}

-- Each blot is this share of what it bursts from, pops from FROM to TO times that, and is gone after SECONDS.
local SIZE = 0.9
local FROM = 0.6
local TO = 1.4
local TRANSPARENCY = 0.2
local SECONDS = 0.6
-- Where the blots land around the object, in fractions of it, one after another.
local PLACES = {
	Vector2.new(0.2, 0.3),
	Vector2.new(0.8, 0.25),
	Vector2.new(0.5, 0.8),
	Vector2.new(0.15, 0.75),
	Vector2.new(0.85, 0.7),
}

-- One blot per entry of `tints`, behind `parent`'s other children.
function Burst.play(parent: GuiObject, tints: { Color3 })
	for index, tint in ipairs(tints) do
		local place = PLACES[(index - 1) % #PLACES + 1]
		local splat = Splat.new({
			Size = UDim2.fromScale(SIZE, SIZE),
			Tint = tint,
			Rotation = Splat.rotation(index),
			Transparency = TRANSPARENCY,
			Position = UDim2.fromScale(place.X, place.Y),
			ZIndex = 0,
			Name = "Burst",
			Parent = parent,
		})
		if splat == nil then
			continue
		end
		local scale = Instance.new("UIScale")
		scale.Name = "Burst"
		scale.Parent = splat
		if not UiPrefs.reducedMotion() then
			Motion.set(scale, { Scale = FROM })
			Motion.to(scale, { Scale = TO }, "UiPop")
		end
		Splat.fade(splat, 1, "Ui")
		task.delay(SECONDS, function()
			Motion.cancel(scale)
			scale:Destroy()
			Splat.release(splat)
		end)
	end
end

return Burst
