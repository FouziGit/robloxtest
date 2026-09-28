--!strict
-- Cell: one reward of the battle pass on its track (D-147) -- a free one above the line, a premium one below,
-- which wears the primary yellow inside its ink and a seal ring in its corner. It shows its reward (the coin
-- and the amount, the clock and the minutes, or the item's swatch) and what can be done with it now:
--
--   Claimable  a Claim button, which the track wiggles on the pass's one shared breath
--   Claimed    a check seal
--   Locked     veiled in chalk, with a lock: the tier is not reached
--   Premium    the lock and the word "Premium": no sentence of refusal
--
-- The claim itself is the screen's (OnClaim), which paces it under the remote's rate. A cell builds its
-- button only while its reward waits, so a fifty-tier pass holds buttons only where they can be pressed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local Button = require(script.Parent.Parent.Parent.components.Button)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Icon = require(script.Parent.Parent.Parent.components.Icon)
local ItemPreview = require(script.Parent.Parent.Parent.components.ItemPreview)
local Seal = require(script.Parent.Parent.Parent.components.Seal)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Types = require(Shared.Types)

export type Track = "Free" | "Premium"
export type State = "Claimable" | "Claimed" | "Locked" | "Premium"
export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Cell = {
	Tier: number,
	Track: Track,
	Frame: Frame,
	-- The Claim button while the reward waits, nil otherwise.
	Claim: Button.Button?,
	-- Shows what `state` allows; a state already shown changes nothing.
	Paint: (self: Cell, state: State) -> (),
	Destroy: (self: Cell) -> (),
}

local Cell = {}

local PADDING = 4
local ICON = 32
local AMOUNT_SIZE = 18
local CLAIM_HEIGHT = 40
local PREMIUM_RIM = 3
local CORNER_RING = 24
local VEIL_TRANSPARENCY = 0.4

-- The height a cell needs: its reward row and its Claim button, which carries the touch minimum on a phone.
function Cell.height(designed: number): number
	return math.max(designed, PADDING * 4 + ICON + Theme.Sizes.PaddingSmall + Theme.touchTargetHeight(CLAIM_HEIGHT))
end

-- What claiming a reward would do now, by the server's own order of refusals (BattlepassService): already
-- claimed, premium without the pass, tier not reached.
function Cell.state(tier: number, track: Track, season: Types.BattlepassSeasonData?): State
	local claimed = if season == nil
		then nil
		elseif track == "Premium" then season.ClaimedPremium
		else season.ClaimedFree
	if claimed ~= nil and claimed[tostring(tier)] == true then
		return "Claimed"
	elseif track == "Premium" and (season == nil or not season.Premium) then
		return "Premium"
	elseif season == nil or tier > season.Tier then
		return "Locked"
	end
	return "Claimable"
end

local function blank(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function row(name: string, parent: Instance, height: number, order: number): Frame
	local frame = blank(name, parent)
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, PADDING)
	layout.Parent = frame
	return frame
end

local function word(name: string, text: string, font: Font, size: number, color: Color3, parent: Instance)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.LayoutOrder = 2
	label.ZIndex = 4
	label.Parent = parent
end

-- The reward's picture: the coin and the amount, the clock and the minutes, or the item's swatch.
local function drawReward(parent: Frame, reward: BattlepassConfig.Reward, localize: Localizer)
	local line = row("Reward", parent, ICON, 1)
	local icon = blank("Icon", line)
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.LayoutOrder = 1
	if reward.Kind == "Folios" then
		Icon.new("Coin", ICON).Parent = icon
		word(
			"Amount",
			localize.t("reward.folios", { amount = reward.Amount }),
			Theme.Fonts.Numeric,
			AMOUNT_SIZE,
			Theme.Colors.Text,
			line
		)
	elseif reward.Kind == "XpBoost" then
		Icon.new("Clock", ICON, Theme.Colors.Text).Parent = icon
		word(
			"Amount",
			localize.t("battlepass.reward.minutes", { minutes = reward.Minutes }),
			Theme.Fonts.Numeric,
			AMOUNT_SIZE,
			Theme.Colors.Text,
			line
		)
	else
		local item = CosmeticConfig.ById[reward.Id]
		if item ~= nil then
			ItemPreview.new(item, icon, localize)
		end
	end
end

-- The cell of `tier`'s `track` reward, under `parent`; `onClaim` is what its Claim button does.
function Cell.new(
	tier: number,
	track: Track,
	reward: BattlepassConfig.Reward,
	localize: Localizer,
	parent: Instance,
	onClaim: () -> ()
): Cell
	local t = localize.t
	local shown: State? = nil
	local claim: Button.Button? = nil
	local mark: Seal.Seal? = nil

	local frame = Instance.new("Frame")
	frame.Name = track .. tostring(tier)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Theme.Colors.PanelRaised
	frame.ZIndex = 2
	Theme.corner(frame, UDim.new(0, Theme.Sizes.CornerCard))
	if track == "Premium" then
		Theme.stroke(frame, "Primary", PREMIUM_RIM)
		local ringId = Theme.texture("SealRing")
		if ringId ~= "" then
			local ring = Instance.new("ImageLabel")
			ring.Name = "Ring"
			ring.BackgroundTransparency = 1
			ring.Image = ringId
			ring.ImageColor3 = Theme.Colors.Primary
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(1, 0)
			ring.Size = UDim2.fromOffset(CORNER_RING, CORNER_RING)
			ring.ZIndex = 5
			ring.Parent = frame
		end
	else
		Theme.stroke(frame, "Accent", Theme.Sizes.StrokeThin)
	end

	local body = blank("Body", frame)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 2
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING * 2)
	padding.PaddingBottom = UDim.new(0, PADDING * 2)
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = body
	drawReward(body, reward, localize)

	local veil = blank("Veil", frame)
	veil.BackgroundTransparency = VEIL_TRANSPARENCY
	veil.BackgroundColor3 = Theme.Colors.Chalk
	veil.Size = UDim2.fromScale(1, 1)
	veil.ZIndex = 3
	veil.Visible = false
	Theme.corner(veil, UDim.new(0, Theme.Sizes.CornerCard))
	local lock = row("Lock", body, CLAIM_HEIGHT, 2)
	lock.ZIndex = 4
	lock.Visible = false
	local lockIcon = Icon.new("Lock", AMOUNT_SIZE, Theme.Colors.Text)
	lockIcon.LayoutOrder = 1
	lockIcon.ZIndex = 4
	lockIcon.Parent = lock
	if track == "Premium" then
		word("Premium", t("battlepass.premium"), Theme.Fonts.Label, Theme.Sizes.TextLabel, Theme.Colors.Premium, lock)
	end
	frame.Parent = parent

	local object: Cell

	local function paint(_self: Cell, state: State)
		if state == shown then
			return
		end
		shown = state
		veil.Visible = state == "Locked"
		lock.Visible = state == "Locked" or state == "Premium"
		local button = claim
		if state ~= "Claimable" and button ~= nil then
			claim = nil
			object.Claim = nil
			button:Destroy()
		elseif state == "Claimable" and button == nil then
			local created = Button.new({
				Text = t("battlepass.claim"),
				Variant = "Primary",
				Size = UDim2.new(1, 0, 0, CLAIM_HEIGHT),
				LayoutOrder = 3,
				Parent = body,
				OnClick = onClaim,
			})
			-- As wide as the cell, not the minimum width of a free-standing button.
			created.Instance.AutomaticSize = Enum.AutomaticSize.None
			claim = created
			object.Claim = created
		end
		local seal = mark
		if state ~= "Claimed" and seal ~= nil then
			mark = nil
			seal:Destroy()
		elseif state == "Claimed" and seal == nil then
			mark = Seal.new({
				Text = Theme.Glyphs.Check,
				Fill = Theme.Colors.SuccessFill,
				Size = CLAIM_HEIGHT - Theme.Sizes.PaddingSmall,
				LayoutOrder = 3,
				Parent = body,
			})
		end
	end

	local function destroy(_self: Cell)
		local button = claim
		claim = nil
		if button ~= nil then
			button:Destroy()
		end
		frame:Destroy()
	end

	object = {
		Tier = tier,
		Track = track,
		Frame = frame,
		Claim = nil,
		Paint = paint,
		Destroy = destroy,
	}
	return object
end

return Cell
