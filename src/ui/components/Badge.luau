--!strict
-- Badge: the count of what is waiting to be claimed, on a tile, a button or a seal (D-147). An upright disc
-- of the primary yellow in its ink outline, inside its host's top-right corner as the board draws it -- never
-- red: nothing is wrong, something is owed to you -- with the count, or "!", in the number face; a count of
-- two figures stretches it into a pill. A host less than twice the disc tall (a claim seal of the hub, a quick
-- button) wears it astride its corner instead, where inside it hid what the host shows. It pops in, and it
-- breathes while it is there.
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
-- The disc (its height and least width: Theme.Sizes.Badge), how far inside its host's corner it sits, the room
-- either side of the count, and the count's size.
local SIZE = Theme.Sizes.Badge
local INSET = 8
local PAD_X = 8
local TEXT_SIZE = 17
-- A host less than this tall wears the disc astride its corner.
local HOLD = SIZE * 2

-- How far into its host's top-right corner a badge inside it reaches: what a host's own words keep clear of.
function Badge.reach(): number
	return INSET + SIZE
end

local function display(value: Value?): string?
	if value == nil or value == 0 then
		return nil
	end
	return tostring(value)
end

-- A badge in the top-right corner of `parent`, showing `value`. `tint` is the disc's colour: the primary
-- yellow, or the sheet on a surface that is itself the primary yellow.
function Badge.new(value: Value?, parent: Instance, tint: Color3?): Badge
	local trove = Trove.new()

	-- The breath scales the holder, the pop scales the disc: two scales on two frames multiply.
	local holder = Instance.new("Frame")
	holder.Name = "Badge"
	holder.BackgroundTransparency = 1
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Size = UDim2.fromOffset(0, SIZE)
	holder.ZIndex = 10
	holder.Visible = false
	trove:Add(holder)
	local breathScale = Instance.new("UIScale")
	breathScale.Parent = holder

	local disc = Instance.new("Frame")
	disc.Name = "Blot"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = tint or Theme.Colors.Primary
	disc.AutomaticSize = Enum.AutomaticSize.X
	disc.Size = UDim2.fromOffset(0, SIZE)
	disc.ZIndex = 10
	Theme.corner(disc, Theme.Pill)
	Theme.stroke(disc, "Accent", Theme.Sizes.Stroke)
	-- The room either side of the count is the count's own: the engine holds a frame that sizes itself to its
	-- least size before it adds that frame's padding, and a lone figure made a pill of 48 (seen in Studio).
	local least = Instance.new("UISizeConstraint")
	least.MinSize = Vector2.new(SIZE, SIZE)
	least.Parent = disc
	-- The count in the middle of the disc: a lone figure, or "!", is narrower than the disc's least width, and
	-- laid out from the left it sat against the disc's left edge.
	local centre = Instance.new("UIListLayout")
	centre.FillDirection = Enum.FillDirection.Horizontal
	centre.HorizontalAlignment = Enum.HorizontalAlignment.Center
	centre.VerticalAlignment = Enum.VerticalAlignment.Center
	centre.Parent = disc
	disc.Parent = holder
	local popScale = Instance.new("UIScale")
	popScale.Parent = disc
	trove:Add(function()
		Motion.cancel(popScale)
	end)

	local label = Instance.new("TextLabel")
	label.Name = "Count"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = Theme.Fonts.Numeric
	label.TextSize = TEXT_SIZE
	label.TextColor3 = Theme.Colors.Text
	label.ZIndex = 11
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PAD_X)
	padding.PaddingRight = UDim.new(0, PAD_X)
	padding.Parent = label
	label.Parent = disc

	-- Inside the corner, unless the host is too short to hold the disc there (measured once it is laid out).
	local function place()
		local height = 0
		local host = holder.Parent
		if host ~= nil and host:IsA("GuiObject") then
			height = host.AbsoluteSize.Y / Theme.activeScale()
		end
		if height > 0 and height < HOLD then
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Position = UDim2.fromScale(1, 0)
		else
			holder.AnchorPoint = Vector2.new(1, 0)
			holder.Position = UDim2.new(1, -INSET, 0, INSET)
		end
	end
	if parent:IsA("GuiObject") then
		trove:Connect(parent:GetPropertyChangedSignal("AbsoluteSize"), place)
	end

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
	place()
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
