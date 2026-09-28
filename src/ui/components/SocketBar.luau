--!strict
-- SocketBar: the loadout's slots as a row of sockets (D-147). An equipped glyph is a disc of its pigment
-- with its sigil, in the order it was equipped, and a tap on it takes it off (OnSocket); a free slot is an
-- empty disc of the sheet with a "+"; a slot only a pass would open is chalk with a lock. Discs, not
-- splats: ten of them would spend a screen's splat budget on their own.
--
-- A socket clicks like a button when it is tapped. The row scrolls sideways when an account holds more
-- slots than fit, and it shakes when a full loadout refuses a glyph (Shake): the track sits in a holder
-- outside any layout, free to move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local GlyphConfig = require(Config:WaitForChild("GlyphConfig"))
local Icon = require(script.Parent.Icon)
local LoadoutEdit = require(Shared:WaitForChild("Pure"):WaitForChild("LoadoutEdit"))
local Motion = require(script.Parent.Parent.Motion)
local PigmentConfig = require(Config:WaitForChild("PigmentConfig"))
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiSound = require(script.Parent.Parent.UiSound)

export type Props = {
	-- A tap on the socket of the equipped glyph `id`.
	OnSocket: (id: string) -> (),
	LayoutOrder: number?,
	Parent: Instance?,
}

export type SocketBar = {
	-- The holder: the row it sits in sizes it (its height is Height()).
	Instance: Frame,
	Set: (self: SocketBar, sockets: { LoadoutEdit.Socket }) -> (),
	Shake: (self: SocketBar) -> (),
	Destroy: (self: SocketBar) -> (),
}

local SocketBar = {}

local SIZE = 44
local GAP = 8
-- The sockets' outline sits inside them; this margin keeps the focus ring and the shake inside the bar.
local MARGIN = 4
local MARK_SCALE = 0.6
local LOCK_SCALE = 0.45

-- The bar's height, in design units.
function SocketBar.height(): number
	return SIZE + MARGIN * 2
end

local function disc(fill: Color3, thickness: number, order: number): TextButton
	local socket = Instance.new("TextButton")
	socket.Name = "Socket"
	socket.AutoButtonColor = false
	socket.BorderSizePixel = 0
	socket.BackgroundColor3 = fill
	socket.Size = UDim2.fromOffset(SIZE, SIZE)
	socket.LayoutOrder = order
	socket.Text = ""
	socket.Active = false
	socket.Selectable = false
	Theme.corner(socket, Theme.Pill)
	Theme.stroke(socket, "Accent", thickness)
	return socket
end

local function mark(parent: Instance, text: string, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = "Mark"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(MARK_SCALE, MARK_SCALE)
	label.FontFace = Theme.Fonts.Bold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
end

function SocketBar.new(props: Props): SocketBar
	local trove = Trove.new()
	local socketTrove = trove:Extend()

	local holder = Instance.new("Frame")
	holder.Name = "SocketBar"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(0, SocketBar.height())
	holder.LayoutOrder = props.LayoutOrder or 0
	trove:Add(holder)

	local track = Instance.new("ScrollingFrame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Size = UDim2.fromScale(1, 1)
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.ScrollBarThickness = 0
	track.CanvasSize = UDim2.new()
	track.AutomaticCanvasSize = Enum.AutomaticSize.X
	track.Selectable = false
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, MARGIN)
	padding.PaddingRight = UDim.new(0, MARGIN)
	padding.PaddingTop = UDim.new(0, MARGIN)
	padding.Parent = track
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = track
	track.Parent = holder
	trove:Add(function()
		Motion.cancel(track)
	end)

	local function set(_self: SocketBar, sockets: { LoadoutEdit.Socket })
		socketTrove:Clean()
		for index, socket in ipairs(sockets) do
			local id = socket.Id
			local def = if id ~= nil then GlyphConfig.ById[id] else nil
			local circle: TextButton
			if socket.Kind == "Filled" and id ~= nil and def ~= nil then
				local fill = Theme.pigmentColor(def.Pigment)
				circle = disc(fill, Theme.Sizes.Stroke, index)
				mark(circle, (PigmentConfig.Sigils :: any)[def.Pigment] or "", Theme.inkOn(fill))
				circle.Active = true
				circle.Selectable = true
				circle.SelectionImageObject = socketTrove:Add(Theme.focusRing(nil, Theme.Pill))
				socketTrove:Connect(circle.Activated, function()
					UiSound.play("UiClick")
					props.OnSocket(id)
				end)
			elseif socket.Kind == "Locked" then
				circle = disc(Theme.Colors.Chalk, Theme.Sizes.StrokeThin, index)
				local lock = Icon.new("Lock", SIZE * LOCK_SCALE, Theme.Colors.TextMuted)
				lock.AnchorPoint = Vector2.new(0.5, 0.5)
				lock.Position = UDim2.fromScale(0.5, 0.5)
				lock.Parent = circle
			else
				circle = disc(Theme.Colors.PanelRaised, Theme.Sizes.StrokeThin, index)
				mark(circle, Theme.Glyphs.Plus, Theme.Colors.TextMuted)
			end
			circle.Parent = track
			socketTrove:Add(circle)
		end
	end

	local function shake(_self: SocketBar)
		Motion.shake(track)
	end

	holder.Parent = props.Parent

	local function destroy(_self: SocketBar)
		trove:Destroy()
	end

	local object: SocketBar = {
		Instance = holder,
		Set = set,
		Shake = shake,
		Destroy = destroy,
	}
	return object
end

return SocketBar
