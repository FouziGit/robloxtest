--!strict
-- KeyButton: a key the player may rebind (D-147). The keycap as their hand knows it (Keycap: the letter,
-- the word, the pad's arrow) on a sheet that presses like a Secondary button and clicks like one. While a
-- new key is awaited the keycap gives way to a breathing ellipsis (SetCapturing); once the server holds a
-- new key the sheet turns green for a moment (Flash).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Keycap = require(script.Parent.Keycap)
local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiSound = require(script.Parent.Parent.UiSound)

export type Props = {
	Key: string,
	Device: Keycap.Device,
	Localize: Keycap.Localizer,
	-- What the button shows while it waits for a key, worded by the caller.
	WaitingText: string,
	OnClick: () -> (),
}

export type KeyButton = {
	Instance: TextButton,
	SetKey: (self: KeyButton, key: string) -> (),
	SetCapturing: (self: KeyButton, capturing: boolean) -> (),
	Flash: (self: KeyButton) -> (),
	Destroy: (self: KeyButton) -> (),
}

local KeyButton = {}

local WIDTH = 150
local ELEVATION = 5
-- The ellipsis waiting for a key breathes between these.
local WAIT_FROM = 0
local WAIT_TO = 0.6
local WAIT_HOLD = 0.2

function KeyButton.new(props: Props): KeyButton
	local trove = Trove.new()

	local button = Instance.new("TextButton")
	button.Name = "Key"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = UDim2.fromOffset(WIDTH, Theme.Sizes.ButtonHeight)
	button.SelectionImageObject = trove:Add(Theme.focusRing(nil, Theme.Pill))
	Theme.minPixelSize(button, Theme.MinTouchTarget)
	trove:Add(button)

	local sticker = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.PanelRaised,
		Lip = Theme.lip("Secondary"),
		Corner = Theme.Pill,
		Elevation = ELEVATION,
		Parent = button,
	})
	trove:Add(function()
		sticker:Destroy()
	end)
	local cap = Keycap.new({ Key = props.Key, Device = props.Device, Localize = props.Localize, Parent = sticker.Face })
	cap.Instance.AnchorPoint = Vector2.new(0.5, 0.5)
	cap.Instance.Position = UDim2.fromScale(0.5, 0.5)
	trove:Add(function()
		cap:Destroy()
	end)
	local waiting = Instance.new("TextLabel")
	waiting.Name = "Waiting"
	waiting.BackgroundTransparency = 1
	waiting.Size = UDim2.fromScale(1, 1)
	waiting.FontFace = Theme.Fonts.Numeric
	waiting.TextSize = Theme.Sizes.NumSmall
	waiting.TextColor3 = Theme.Colors.Text
	waiting.Text = props.WaitingText
	waiting.Visible = false
	waiting.Parent = sticker.Face

	local hovered, pressed = false, false
	local function render()
		sticker:SetState(if pressed then "Pressed" elseif hovered then "Hover" else "Idle")
	end
	trove:Connect(button.MouseEnter, function()
		hovered = true
		render()
	end)
	trove:Connect(button.MouseLeave, function()
		hovered, pressed = false, false
		render()
	end)
	trove:Connect(button.MouseButton1Down, function()
		pressed = true
		render()
	end)
	trove:Connect(button.MouseButton1Up, function()
		pressed = false
		render()
	end)
	trove:Connect(button.Activated, function()
		UiSound.play("UiClick")
		props.OnClick()
	end)

	local stopBreath: (() -> ())? = nil
	local flashToken = 0
	trove:Add(function()
		local stop = stopBreath
		stopBreath = nil
		if stop ~= nil then
			stop()
		end
		Motion.cancel(waiting)
		flashToken += 1
	end)

	local function setKey(_self: KeyButton, key: string)
		cap:SetKey(key)
	end

	local function setCapturing(_self: KeyButton, capturing: boolean)
		cap.Instance.Visible = not capturing
		waiting.Visible = capturing
		local stop = stopBreath
		stopBreath = nil
		if stop ~= nil then
			stop()
		end
		if capturing then
			stopBreath = Motion.loop(
				waiting,
				{ TextTransparency = WAIT_FROM },
				{ TextTransparency = WAIT_TO },
				"Ui",
				WAIT_HOLD
			)
		else
			Motion.set(waiting, { TextTransparency = WAIT_FROM })
		end
	end

	local function flash(_self: KeyButton)
		flashToken += 1
		local mine = flashToken
		sticker:SetFill(Theme.Colors.SuccessFill)
		task.delay(Theme.Timing.SuccessFlashSeconds, function()
			if flashToken == mine and button:IsDescendantOf(game) then
				sticker:SetFill(Theme.Colors.PanelRaised)
			end
		end)
	end

	local function destroy(_self: KeyButton)
		trove:Destroy()
	end

	local object: KeyButton = {
		Instance = button,
		SetKey = setKey,
		SetCapturing = setCapturing,
		Flash = flash,
		Destroy = destroy,
	}
	return object
end

return KeyButton
