--!strict
-- SpectatePlate: who an eliminated player is watching, where their dock was (D-147). An ink plate saying
-- "Watching {name}" in vellum, between a disc back and a disc on, which step through the living teammates
-- (SpectateController.cycle). It replaces the toast that used to say it once and leave: the player watching
-- is the one with nothing else to read. A fight surface: ink and the sheet only (docs/ART_BIBLE.md rule 11);
-- a gamepad may select its discs while it shows, on the fight's focus ring.
--
-- A pad reaches them by its shoulders: nothing gives a pad a selection when the plate shows, the D-pad casts
-- the pigments and Select opens the menu, so while the plate is up the shoulder buttons step back and on,
-- named on caps beside the discs.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local CircleButton = require(script.Parent.CircleButton)
local Keycap = require(script.Parent.Keycap)
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
-- The shoulders, and the step each one takes, bound above the game's own actions (InputController binds at
-- High) and sunk while the plate shows.
local STEP_ACTION = "SpectateStep"
local STEP_PRIORITY = Enum.ContextActionPriority.High.Value + 1
local SHOULDERS: { { Key: string, Step: number, Order: number } } = {
	{ Key = "ButtonL1", Step = -1, Order = 0 },
	{ Key = "ButtonR1", Step = 1, Order = 4 },
}

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
	-- What the discs and the caps leave.
	label.Size = UDim2.fromScale(0, 1)
	local labelFill = Instance.new("UIFlexItem")
	labelFill.FlexMode = Enum.UIFlexMode.Fill
	labelFill.Parent = label
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
	local caps: { Frame } = {}
	local byKey: { [string]: number } = {}
	local shoulders: { Enum.KeyCode } = {}
	for _, shoulder in ipairs(SHOULDERS) do
		local cap = Keycap.new({
			Key = shoulder.Key,
			Device = "Gamepad",
			Localize = props.Localize,
			LayoutOrder = shoulder.Order,
			Parent = row,
			Name = shoulder.Key,
		})
		trove:Add(cap)
		cap.Instance.Visible = false
		table.insert(caps, cap.Instance)
		byKey[shoulder.Key] = shoulder.Step
		table.insert(shoulders, (Enum.KeyCode :: any)[shoulder.Key])
	end

	local function unbind()
		ContextActionService:UnbindAction(STEP_ACTION)
	end
	trove:Add(unbind)

	root.Parent = props.Parent

	local function show(_self: SpectatePlate, name: string, onCycle: (step: number) -> ())
		cycle = onCycle
		label.Text = props.Localize.t(WATCHING_KEY, { name = name })
		token += 1
		if shown then
			return
		end
		shown = true
		for _, cap in ipairs(caps) do
			cap.Visible = UserInputService.GamepadEnabled
		end
		ContextActionService:BindActionAtPriority(
			STEP_ACTION,
			function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
				local by = byKey[input.KeyCode.Name]
				if state ~= Enum.UserInputState.Begin or by == nil then
					return Enum.ContextActionResult.Pass
				end
				step(by)
				return Enum.ContextActionResult.Sink
			end,
			false,
			STEP_PRIORITY,
			table.unpack(shoulders)
		)
		root.Visible = true
		Motion.set(scale, { Scale = 0 })
		Motion.to(scale, { Scale = 1 }, "UiPop")
	end

	local function hide(_self: SpectatePlate, onDone: (() -> ())?)
		cycle = nil
		unbind()
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
