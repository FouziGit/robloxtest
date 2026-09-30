--!strict
-- DropCap: the illuminated initial that opens every screen's title, as a manuscript opens a chapter (D-147,
-- D-177): "Q", then "uêtes". One character in the roman at its heaviest, a fifth larger than the title and in
-- the title's own colour, set on the title's line -- the board's `.cap`, with no square under it and no ring
-- around it. It is what keeps the page's voice under the poster type, and it is never more than one character.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type DropCap = {
	Instance: TextLabel,
	-- Presses it in, just after the band it sits on: what a screen's entrance plays.
	Stamp: (self: DropCap) -> (),
	Destroy: (self: DropCap) -> (),
}

local DropCap = {}

-- A fifth larger than the title it opens (the board's cap: 30 on a title of 24, 3.8 on 3.2).
local CAP_SCALE = 1.2
local STAMP_FROM = 1.5
-- It lands just after the band it sits on.
local STAMP_DELAY = 0.08

-- The size a cap is set at, in design units.
DropCap.Size = math.round(Theme.Sizes.TextTitle * CAP_SCALE)

-- The drop cap of `letter`, for the title of the screen `chapter` (a ThemeConfig.Chapters key), whose ink it
-- takes. It stands on the foot of its box: its caller gives it the title's line.
function DropCap.new(letter: string, chapter: string, parent: Instance?): DropCap
	assert(utf8.len(letter) == 1, "a drop cap is one character")
	local trove = Trove.new()

	local label = Instance.new("TextLabel")
	label.Name = "DropCap"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = Theme.Fonts.Initial
	label.TextSize = DropCap.Size
	label.TextColor3 = Theme.chapter(chapter).Title
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.TextTruncate = Enum.TextTruncate.None
	label.Text = letter
	trove:Add(label)

	local scale = Instance.new("UIScale")
	scale.Parent = label
	trove:Add(function()
		Motion.cancel(scale)
	end)
	label.Parent = parent

	-- Hidden until it lands, so it never sits there at its stamping size; and shown whatever happens, so a
	-- screen closed in the meantime never reopens without its initial.
	local function stamp(_self: DropCap)
		label.Visible = false
		task.delay(STAMP_DELAY, function()
			label.Visible = true
			if label:IsDescendantOf(game) then
				Motion.set(scale, { Scale = STAMP_FROM })
				Motion.to(scale, { Scale = 1 }, "UiPop")
			end
		end)
	end

	local function destroy(_self: DropCap)
		trove:Destroy()
	end

	local object: DropCap = {
		Instance = label,
		Stamp = stamp,
		Destroy = destroy,
	}
	return object
end

return DropCap
