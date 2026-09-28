--!strict
-- SpectatePlate: who an eliminated player is watching, where their dock was (D-147). An ink plate saying
-- "Watching {name}" in vellum, between a disc back and a disc on, which step through the living teammates
-- (SpectateController.cycle). It replaces the toast that used to say it once and leave: the player watching
-- is the one with nothing else to read. A fight surface: ink and the sheet only (docs/ART_BIBLE.md rule 11);
-- a gamepad may select its discs while it shows, on the fight's focus ring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local CircleButton = require(script.Parent.CircleButton)
local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	Parent: Instance,
	Localize: Localizer,
	LayoutOrder: number?,
}

export type SpectatePlate = {
	Instance: Frame,
	-- Watching `name`; the discs call `onCycle` with -1 or 1.
	Show: (self: SpectatePlate, name: string, onCycle: (step: number) -> ()) -> (),
	-- Gone, then `onDone`.
	Hide: (self: SpectatePlate, onDone: (() -> ())?) -> (),
	Destroy: (self: SpectatePlate) -> (),
}

local SpectatePlate = {}

local WIDTH = 360
local HEIGHT = 56
local DISC = 44
local GAP = 6
local TEXT = 18
-- The play sign turned half a turn points back.
local BACK_ROTATION = 180
local WATCHING_KEY = "match.watching"

function SpectatePlate.new(props: Props): SpectatePlate
	local trove = Trove.new()
	local cycle: ((step: number) -> ())? = nil
	local shown = false
	local token = 0

	local root = Instance.new("Frame")
	root.Name = "Spectate"
	root.BackgroundTransparency = 1
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	root.Visible = false
	trove:Add(root)
	local scale = Instance.new("UIScale")
	scale.Parent = root
	trove:Add(function()
		Motion.cancel(scale)
	end)
	local plate = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Corner = UDim.new(0, Theme.Sizes.CornerCard),
		Parent = root,
		Name = "Plate",
	})
	trove:Add(function()
		plate:Destroy()
	end)

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = 3
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = row
	row.Parent = root

	local function step(by: number)
		local onCycle = cycle
		if onCycle ~= nil then
			onCycle(by)
		end
	end
	trove:Add(CircleButton.new({
		Sign = Theme.Glyphs.Play,
		SignRotation = BACK_ROTATION,
		Size = DISC,
		Focus = "Fight",
		LayoutOrder = 1,
		Parent = row,
		Name = "Previous",
		OnClick = function()
			step(-1)
		end,
	}))
	local label = Instance.new("TextLabel")
	label.Name = "Watching"
	label.BackgroundTransparency = 1
	label.LayoutOrder = 2
	label.Size = UDim2.new(0, WIDTH - (DISC + GAP) * 2 - GAP * 2, 1, 0)
	label.FontFace = Theme.Fonts.Bold
	label.TextSize = TEXT
	label.TextColor3 = Theme.Colors.TextInverse
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = row
	trove:Add(CircleButton.new({
		Sign = Theme.Glyphs.Play,
		Size = DISC,
		Focus = "Fight",
		LayoutOrder = 3,
		Parent = row,
		Name = "Next",
		OnClick = function()
			step(1)
		end,
	}))

	root.Parent = props.Parent

	local function show(_self: SpectatePlate, name: string, onCycle: (step: number) -> ())
		cycle = onCycle
		label.Text = props.Localize.t(WATCHING_KEY, { name = name })
		token += 1
		if shown then
			return
		end
		shown = true
		root.Visible = true
		Motion.set(scale, { Scale = 0 })
		Motion.to(scale, { Scale = 1 }, "UiPop")
	end

	local function hide(_self: SpectatePlate, onDone: (() -> ())?)
		cycle = nil
		token += 1
		local mine = token
		if not shown then
			if onDone ~= nil then
				onDone()
			end
			return
		end
		shown = false
		Motion.to(scale, { Scale = 0 }, "UiExit", function()
			if mine ~= token then
				return
			end
			root.Visible = false
			if onDone ~= nil then
				onDone()
			end
		end)
	end

	local function destroy(_self: SpectatePlate)
		trove:Destroy()
	end

	return { Instance = root, Show = show, Hide = hide, Destroy = destroy }
end

return SpectatePlate
