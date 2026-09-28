--!strict
-- DropCap: the illuminated initial that opens every screen's title, as a manuscript opens a chapter
-- (D-147): "Q" on its own square of sheet, then "uêtes". One character in the roman at its heaviest, inside
-- an ink outline and a ring of the chapter's colour. It is what keeps the page's voice under the poster
-- type, and it is never more than one character.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type DropCap = {
	Instance: Frame,
	-- Presses it in, just after the band it sits on: what a screen's entrance plays.
	Stamp: (self: DropCap) -> (),
	Destroy: (self: DropCap) -> (),
}

local DropCap = {}

local LETTER_SIZE = 34
local ELEVATION = 4
local TILT = -2
local STAMP_FROM = 1.5
-- It lands just after the band it sits on.
local STAMP_DELAY = 0.08

-- The drop cap of `letter`, ringed in the colour of the screen `chapter` (a ThemeConfig.Chapters key).
function DropCap.new(letter: string, chapter: string, parent: Instance?): DropCap
	assert(utf8.len(letter) == 1, "a drop cap is one character")
	local trove = Trove.new()
	local size = Theme.Sizes.Medallion

	local sticker = Sticker.new({
		Kind = "Card",
		Fill = Theme.Colors.PanelRaised,
		Elevation = ELEVATION,
		Size = UDim2.fromOffset(size, size + ELEVATION),
		Name = "DropCap",
	})
	trove:Add(function()
		sticker:Destroy()
	end)
	local root = sticker.Instance
	root.Rotation = TILT

	-- The chapter's ring, inside the ink outline.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, -Theme.Sizes.Stroke * 2, 1, -Theme.Sizes.Stroke * 2)
	Theme.corner(ring, UDim.new(0, Theme.Sizes.CornerCard - Theme.Sizes.Stroke))
	Theme.stroke(ring, Theme.chapter(chapter).Band, Theme.Sizes.StrokeThin)
	ring.Parent = sticker.Face

	local label = Instance.new("TextLabel")
	label.Name = "Letter"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Initial
	label.TextSize = LETTER_SIZE
	label.TextColor3 = Theme.Colors.Text
	label.Text = letter
	label.Parent = sticker.Face

	local scale = Instance.new("UIScale")
	scale.Parent = root
	trove:Add(function()
		Motion.cancel(scale)
	end)
	root.Parent = parent

	-- Hidden until it lands, so it never sits there at its stamping size; and shown whatever happens, so a
	-- screen closed in the meantime never reopens without its initial.
	local function stamp(_self: DropCap)
		root.Visible = false
		task.delay(STAMP_DELAY, function()
			root.Visible = true
			if root:IsDescendantOf(game) then
				Motion.set(scale, { Scale = STAMP_FROM })
				Motion.to(scale, { Scale = 1 }, "UiPop")
			end
		end)
	end

	local function destroy(_self: DropCap)
		trove:Destroy()
	end

	local object: DropCap = {
		Instance = root,
		Stamp = stamp,
		Destroy = destroy,
	}
	return object
end

return DropCap
