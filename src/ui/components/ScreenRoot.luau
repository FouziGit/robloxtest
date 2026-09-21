--!strict
-- ScreenRoot: a ScreenGui with a Theme-driven UIScale and a safe-area content frame. Screens parent
-- their overlays to `Content` so they never sit under the Roblox top bar or device notches.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Name: string,
	DisplayOrder: number?,
	Parent: Instance?,
}

export type ScreenRoot = {
	Instance: ScreenGui,
	Content: Frame,
	Scale: UIScale,
	GetScale: (self: ScreenRoot) -> number,
	Destroy: (self: ScreenRoot) -> (),
}

local ScreenRoot = {}

-- Rule 3 of docs/ART_BIBLE.md, "rien n'apparaît": a screen that is enabled grows into place from just
-- under its size, about its centre, on the snappy spring. Every screen gets it here rather than ten
-- screens each remembering to.
local ENTER_SCALE = 0.94

function ScreenRoot.new(props: Props): ScreenRoot
	local trove = Trove.new()

	local gui = Instance.new("ScreenGui")
	gui.Name = props.Name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = props.DisplayOrder or 0
	trove:Add(gui)

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = gui

	local content = Instance.new("Frame")
	content.Name = "SafeArea"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromScale(1, 1)
	-- Centred, so the entrance scales about the middle of the screen and not its top-left corner.
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Parent = gui

	local entrance = Instance.new("UIScale")
	entrance.Name = "Entrance"
	entrance.Parent = content
	trove:Add(function()
		Motion.cancel(entrance)
	end)
	trove:Connect(gui:GetPropertyChangedSignal("Enabled"), function()
		if gui.Enabled then
			Motion.set(entrance, { Scale = ENTER_SCALE })
			Motion.to(entrance, { Scale = 1 }, "UiSnappy")
		end
	end)

	local padding = Instance.new("UIPadding")
	padding.Name = "SafeAreaPadding"
	padding.Parent = content

	local currentScale = 1

	-- Offsets are multiplied by the UIScale, so pixel insets are divided by it to stay exact.
	local function apply()
		currentScale = Theme.activeScale()
		scale.Scale = currentScale
		local topLeft, bottomRight = GuiService:GetGuiInset()
		padding.PaddingTop = UDim.new(0, topLeft.Y / currentScale)
		padding.PaddingLeft = UDim.new(0, topLeft.X / currentScale)
		padding.PaddingBottom = UDim.new(0, bottomRight.Y / currentScale)
		padding.PaddingRight = UDim.new(0, bottomRight.X / currentScale)
	end

	-- Theme.bindScale is the only trigger, on purpose. GuiService.SafeZoneOffsetsChanged is reserved for
	-- engine scripts: connecting to it from a LocalScript raises "lacking capability RobloxScript", which
	-- killed ScreenRoot.new and with it the HUD and every screen. The offsets change when the device
	-- rotates or the topbar resizes, and both of those change the viewport, so bindScale already covers
	-- them. GuiService:GetGuiInset() below is a plain method and stays.
	trove:Add(Theme.bindScale(apply))

	gui.Parent = props.Parent or Players.LocalPlayer:WaitForChild("PlayerGui")

	local function getScale(_self: ScreenRoot): number
		return currentScale
	end

	local function destroy(_self: ScreenRoot)
		trove:Destroy()
	end

	local object: ScreenRoot = {
		Instance = gui,
		Content = content,
		Scale = scale,
		GetScale = getScale,
		Destroy = destroy,
	}
	return object
end

return ScreenRoot
