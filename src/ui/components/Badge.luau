--!strict
-- Badge: the count of what is waiting to be claimed, on a tile, a button or a seal (D-147). A blot of the
-- primary yellow -- never red: nothing is wrong, something is owed to you -- with the count, or "!", in
-- the heavy label face, tipped a few degrees. It pops in, and it breathes while it is there.
--
-- Every badge breathes on ONE loop (Breath): ten badges on a screen cost one loop, and they breathe
-- together, which is also what makes them read as one system rather than as ten alarms.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Breath = require(script.Parent.Parent.Breath)
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

	local reader: Breath.Reader? = nil
	local following: RBXScriptConnection? = nil
	local function setBreathing(on: boolean)
		if on == (reader ~= nil) then
			return
		end
		local current = reader
		if current ~= nil then
			local connection = following
			if connection ~= nil then
				connection:Disconnect()
			end
			following = nil
			reader = nil
			breathScale.Scale = 1
			current.Leave()
			return
		end
		local joined = Breath.join("Badge", 1, BREATH_SCALE, Theme.Timing.IdleBreathSeconds)
		reader = joined
		following = joined.Value.Changed:Connect(function(breath: number)
			breathScale.Scale = breath
		end)
	end
	trove:Add(function()
		setBreathing(false)
	end)
	-- A badge destroyed with whatever it sits on, without its Destroy, still leaves the shared breath: a
	-- breath nobody reads would spring on for the rest of the session.
	holder.Destroying:Once(function()
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
