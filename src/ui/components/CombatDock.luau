--!strict
-- CombatDock: the player's own health and ink, where the thumbs are not (D-147). HudController places it and
-- feeds it the combat state the server pushes; every number on it is the server's.
--
-- What was just lost stays on the health bar in Cinnabar and catches up (the ghost, D-85): a hit reads as a
-- chunk taken out of the bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local ProgressBar = require(script.Parent.ProgressBar)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

-- The part of CombatController.State the dock draws.
export type State = { Health: number, MaxHealth: number, Ink: number, MaxInk: number }

export type Props = {
	Parent: Instance,
	Localize: Localizer,
	AnchorPoint: Vector2,
	Position: UDim2,
}

export type CombatDock = {
	Instance: Frame,
	SetState: (self: CombatDock, state: State) -> (),
	Destroy: (self: CombatDock) -> (),
}

local CombatDock = {}

local WIDTH = 300

function CombatDock.new(props: Props): CombatDock
	local trove = Trove.new()
	local localize = props.Localize

	local column = Instance.new("Frame")
	column.Name = "Bars"
	column.BackgroundTransparency = 1
	column.AnchorPoint = props.AnchorPoint
	column.Position = props.Position
	column.Size = UDim2.fromOffset(WIDTH, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	trove:Add(column)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = column

	local healthBar = ProgressBar.new({
		Name = "HealthBar",
		Color = Theme.Colors.Health,
		Ghost = Theme.Colors.Danger,
		LayoutOrder = 1,
		Parent = column,
	})
	local inkBar = ProgressBar.new({ Name = "InkBar", Color = Theme.Colors.Ink, LayoutOrder = 2, Parent = column })
	trove:Add(function()
		healthBar:Destroy()
		inkBar:Destroy()
	end)

	column.Parent = props.Parent

	local function refreshBar(bar: ProgressBar.ProgressBar, nameKey: string, current: number, max: number)
		bar:SetProgress(if max > 0 then current / max else 0)
		bar:SetLabel(localize.t("hud.bar", {
			name = localize.t(nameKey),
			current = math.floor(current + 0.5),
			max = math.floor(max + 0.5),
		}))
	end

	local function setState(_self: CombatDock, state: State)
		refreshBar(healthBar, "hud.health", state.Health, state.MaxHealth)
		refreshBar(inkBar, "hud.ink", state.Ink, state.MaxInk)
	end

	local function destroy(_self: CombatDock)
		trove:Destroy()
	end

	local object: CombatDock = {
		Instance = column,
		SetState = setState,
		Destroy = destroy,
	}
	return object
end

return CombatDock
