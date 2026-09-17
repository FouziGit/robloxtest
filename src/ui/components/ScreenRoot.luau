--!strict
-- ScreenRoot: a ScreenGui with a Theme-driven UIScale and a safe-area content frame. Screens parent
-- their overlays to `Content` so they never sit under the Roblox top bar or device notches.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

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

-- Fallback viewport used before a camera exists (16:9 at the reference height).
local FALLBACK_VIEWPORT = Vector2.new(Theme.ReferenceHeight * 16 / 9, Theme.ReferenceHeight)

local function viewportSize(): Vector2
	local camera: Camera? = workspace.CurrentCamera
	if camera == nil then
		return FALLBACK_VIEWPORT
	end
	return camera.ViewportSize
end

function ScreenRoot.new(props: Props): ScreenRoot
	local trove = Trove.new()
	local cameraTrove = trove:Extend()

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
	content.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.Name = "SafeAreaPadding"
	padding.Parent = content

	local currentScale = 1

	-- Offsets are multiplied by the UIScale, so pixel insets are divided by it to stay exact.
	local function apply()
		currentScale = Theme.scaleFor(viewportSize())
		scale.Scale = currentScale
		local topLeft, bottomRight = GuiService:GetGuiInset()
		padding.PaddingTop = UDim.new(0, topLeft.Y / currentScale)
		padding.PaddingLeft = UDim.new(0, topLeft.X / currentScale)
		padding.PaddingBottom = UDim.new(0, bottomRight.Y / currentScale)
		padding.PaddingRight = UDim.new(0, bottomRight.X / currentScale)
	end

	local function bindCamera()
		cameraTrove:Clean()
		local camera: Camera? = workspace.CurrentCamera
		if camera ~= nil then
			cameraTrove:Connect(camera:GetPropertyChangedSignal("ViewportSize"), apply)
		end
		apply()
	end

	trove:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
	trove:Connect(GuiService.SafeZoneOffsetsChanged, apply)
	bindCamera()

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
