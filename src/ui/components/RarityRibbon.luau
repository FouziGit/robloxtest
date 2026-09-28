--!strict
-- RarityRibbon: the pill in the top-left corner of an item card that says how rare it is (D-147) -- in its
-- colour, in its word and in its pips, because colour is never the only cue (Rare and Epic are only 113
-- apart for a deuteranope). A Legendary's ribbon also wears a seal ring and a sweep of light across it,
-- the shimmer: one of the few animated gradients a screen may have, still under reduced motion and on the
-- lowest graphics tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Pips = require(script.Parent.Pips)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type RarityRibbon = {
	Instance: Frame,
	Destroy: (self: RarityRibbon) -> (),
}

local RarityRibbon = {}

local HEIGHT = 24
local WORD_SIZE = 14
local INSET = 8

-- The ribbon of `rarity` (a ThemeConfig.Rarity key), reading `word` -- the player's word for it
-- (`Theme.rarity(rarity).WordKey`, translated by the caller).
function RarityRibbon.new(rarity: string, word: string, parent: Instance?): RarityRibbon
	local trove = Trove.new()
	local look = Theme.rarity(rarity)

	local pill = Instance.new("Frame")
	pill.Name = "Rarity"
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = look.Fill
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, HEIGHT)
	pill.Position = UDim2.fromOffset(INSET, INSET)
	pill.ZIndex = 5
	Theme.corner(pill, Theme.Pill)
	Theme.stroke(pill, "Accent", Theme.Sizes.StrokeThin)
	trove:Add(pill)

	-- The word and its pips, in a row that sizes the pill; the shine lies over the whole pill, outside it.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.X
	content.Size = UDim2.fromScale(0, 1)
	content.ZIndex = 6
	content.Parent = pill

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, INSET)
	padding.PaddingRight = UDim.new(0, INSET)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall / 2)
	layout.Parent = content

	if look.Seal then
		local id = Theme.texture("SealRing")
		if id ~= "" then
			local ring = Instance.new("ImageLabel")
			ring.Name = "Seal"
			ring.BackgroundTransparency = 1
			ring.Image = id
			ring.ImageColor3 = look.Ink
			ring.Size = UDim2.fromOffset(HEIGHT - 6, HEIGHT - 6)
			ring.LayoutOrder = 0
			ring.ZIndex = 6
			ring.Parent = content
		end
	end

	local label = Instance.new("TextLabel")
	label.Name = "Word"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = Theme.Fonts.Label
	label.TextSize = WORD_SIZE
	label.TextColor3 = look.Ink
	label.Text = word
	label.LayoutOrder = 1
	label.ZIndex = 6
	label.Parent = content

	-- Only the pips it has: a Common ribbon shows one, a Legendary four.
	local pips = Pips.new(look.Pips, look.Pips, look.Ink)
	pips.Instance.LayoutOrder = 2
	pips.Instance.ZIndex = 6
	pips.Instance.Parent = content
	trove:Add(function()
		pips:Destroy()
	end)

	if look.Shimmer and not UiPrefs.reducedMotion() and not UiPrefs.lowQuality() then
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.BorderSizePixel = 0
		shine.BackgroundColor3 = Theme.Colors.PanelRaised
		shine.Size = UDim2.fromScale(1, 1)
		shine.ZIndex = 7
		Theme.corner(shine, Theme.Pill)
		local gradient = Theme.gradient("Shimmer")
		gradient.Offset = Vector2.new(-1, 0)
		gradient.Parent = shine
		shine.Parent = pill

		-- One sweep, a pause, the next; only while the ribbon is on a screen, and again when it comes back.
		local running = true
		local sweeping = false
		trove:Add(function()
			running = false
			Motion.cancel(gradient)
		end)
		local function sweep()
			if not running or not gradient:IsDescendantOf(game) then
				sweeping = false
				return
			end
			sweeping = true
			Motion.set(gradient, { Offset = Vector2.new(-1, 0) })
			Motion.to(gradient, { Offset = Vector2.new(1, 0) }, "Ui", function()
				task.delay(Theme.Timing.ShimmerPauseSeconds, sweep)
			end)
		end
		trove:Connect(pill.AncestryChanged, function()
			if not sweeping and pill:IsDescendantOf(game) then
				sweep()
			end
		end)
	end

	pill.Parent = parent

	local function destroy(_self: RarityRibbon)
		trove:Destroy()
	end

	local object: RarityRibbon = {
		Instance = pill,
		Destroy = destroy,
	}
	return object
end

return RarityRibbon
