--!strict
-- Badge: the count of what is waiting to be claimed, on a tile, a button or a seal (D-147). A blot of the
-- primary yellow -- never red: nothing is wrong, something is owed to you -- with the count, or "!", in
-- the heavy label face, tipped a few degrees. It pops in, and it breathes while it is there.
--
-- Every badge breathes on ONE loop: a single value, sprung back and forth once for the whole client, that
-- each badge reads (ThemeConfig.Budget.MaxIdleLoops). Ten badges on a screen cost one loop, and they
-- breathe together, which is also what makes them read as one system rather than as ten alarms.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Value = number | string

export type Badge = {
	Instance: Frame,
	-- nil or 0 hides the badge.
	Set: (self: Badge, value: Value?) -> (),
	Destroy: (self: Badge) -> (),
}

local Badge = {}

-- How far a breath swells the badge.
local BREATH_SCALE = 1.12
local TILT = 6
-- The blot's ink reaches about two thirds of its plane, so the count sits in the middle two thirds.
local LABEL_SCALE = 0.62

local breath: NumberValue? = nil
local breathers = 0
local stopBreath: (() -> ())? = nil

-- Joins the shared breath and returns the value to read.
local function joinBreath(): NumberValue
	breathers += 1
	local value = breath
	if value ~= nil then
		return value
	end
	local created = Instance.new("NumberValue")
	created.Name = "BadgeBreath"
	created.Value = 1
	-- Motion only springs what is in the DataModel.
	created.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	breath = created
	stopBreath = Motion.loop(created, { Value = 1 }, { Value = BREATH_SCALE }, "Ui", Theme.Timing.IdleBreathSeconds)
	return created
end

local function leaveBreath()
	breathers -= 1
	if breathers > 0 then
		return
	end
	local stop = stopBreath
	local value = breath
	stopBreath = nil
	breath = nil
	if stop ~= nil then
		stop()
	end
	if value ~= nil then
		Motion.cancel(value)
		value:Destroy()
	end
end

local function display(value: Value?): string?
	if value == nil or value == 0 then
		return nil
	end
	return tostring(value)
end

-- A badge on the top-right corner of `parent`, showing `value`. `tint` is the blot's colour: the primary
-- yellow, or the sheet on a surface that is itself the primary yellow.
function Badge.new(value: Value?, parent: Instance, tint: Color3?): Badge
	local trove = Trove.new()
	local size = Theme.Sizes.Badge

	-- The breath scales the holder, the pop scales the blot: two scales on two frames multiply.
	local holder = Instance.new("Frame")
	holder.Name = "Badge"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(1, -size / 4, 0, size / 4)
	holder.Size = UDim2.fromOffset(size, size)
	holder.ZIndex = 10
	holder.Visible = false
	trove:Add(holder)
	local breathScale = Instance.new("UIScale")
	breathScale.Parent = holder

	local id = Theme.texture("InkBlot")
	local blot: GuiObject
	if id ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = id
		image.ImageColor3 = tint or Theme.Colors.Primary
		image.BackgroundTransparency = 1
		blot = image
	else
		local disc = Instance.new("Frame")
		disc.BackgroundColor3 = tint or Theme.Colors.Primary
		Theme.corner(disc, Theme.Pill)
		Theme.stroke(disc, "Accent", Theme.Sizes.StrokeThin)
		blot = disc
	end
	blot.Name = "Blot"
	blot.BorderSizePixel = 0
	blot.Size = UDim2.fromScale(1, 1)
	blot.Rotation = TILT
	blot.ZIndex = 10
	blot.Parent = holder
	local popScale = Instance.new("UIScale")
	popScale.Parent = blot
	trove:Add(function()
		Motion.cancel(popScale)
	end)

	local label = Instance.new("TextLabel")
	label.Name = "Count"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(LABEL_SCALE, LABEL_SCALE)
	label.FontFace = Theme.Fonts.Label
	label.TextScaled = true
	label.TextColor3 = Theme.Colors.Text
	label.ZIndex = 11
	label.Parent = blot
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 14
	cap.Parent = label

	local breathing: RBXScriptConnection? = nil
	local function setBreathing(on: boolean)
		if on == (breathing ~= nil) then
			return
		end
		local connection = breathing
		if connection ~= nil then
			connection:Disconnect()
			breathing = nil
			breathScale.Scale = 1
			leaveBreath()
			return
		end
		local shared = joinBreath()
		breathing = shared.Changed:Connect(function(current: number)
			breathScale.Scale = current
		end)
	end
	trove:Add(function()
		setBreathing(false)
	end)

	local function set(_self: Badge?, next: Value?)
		local text = display(next)
		if text == nil then
			holder.Visible = false
			setBreathing(false)
			return
		end
		local appearing = not holder.Visible
		label.Text = text
		holder.Visible = true
		setBreathing(true)
		if appearing then
			Motion.punch(popScale)
		end
	end

	holder.Parent = parent
	set(nil, value)

	local function destroy(_self: Badge)
		trove:Destroy()
	end

	local object: Badge = {
		Instance = holder,
		Set = set,
		Destroy = destroy,
	}
	return object
end

return Badge
