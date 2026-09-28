--!strict
-- BattlepassScreen: the season's pass (D-147), in the Tyrian purple of its chapter. The header holds the
-- tier seal and the XP to the next tier, and the three things to do with the pass: get its premium track,
-- skip five tiers, and claim everything waiting at once. Under it, the next reward waits in a showcase on the
-- left, and the tiers run to the right as a road that scrolls sideways (pass/Track, pass/Cell) and comes to
-- rest on the current tier when the screen opens.
--
-- Claims go through ClaimBattlepassReward, never faster than the remote's own token bucket allows: a mirror
-- of it, built from Remotes, paces every claim this screen sends -- "Claim all" and a single Claim alike share
-- one queue -- so a burst of claims is never refused as abuse. The server answers each with a profile push
-- and a toast. There is no season timer: BattlepassConfig has no end date (D-147).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local Button = require(script.Parent.Parent.components.Button)
local Cell = require(script.Parent.pass.Cell)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Icon = require(script.Parent.Parent.components.Icon)
local ItemPreview = require(script.Parent.Parent.components.ItemPreview)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Panel = require(script.Parent.Parent.components.Panel)
local ProgressBar = require(script.Parent.Parent.components.ProgressBar)
local Remotes = require(Shared.Remotes)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Seal = require(script.Parent.Parent.components.Seal)
local Splat = require(script.Parent.Parent.components.Splat)
local Sticker = require(script.Parent.Parent.components.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local TokenBucket = require(Shared.Util.TokenBucket)
local Track = require(script.Parent.pass.Track)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	OnClose: () -> (),
	OnNavigate: (id: string, args: any?) -> (),
	OnBack: () -> (),
	CanGoBack: () -> boolean,
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen, args: any?) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type SeasonData = Types.BattlepassSeasonData
type Claim = { Tier: number, Track: Cell.Track }
type Destroyable = { Destroy: (self: any) -> () }

local BattlepassScreen = {}

local CHAPTER = "Battlepass"
local SEASON = GameConfig.SeasonId
local MAX_TIER = BattlepassConfig.MaxTier
local TIERS = BattlepassConfig.Seasons[SEASON].Tiers
-- The remote every claim goes through, and its own rate, which this screen stays under.
local CLAIM_REMOTE = "ClaimBattlepassReward"
local CLAIM_RATE = Remotes.Definitions[CLAIM_REMOTE].Rate :: Remotes.Rate
-- Claims leave at least this far apart, and never before the mirror holds a token and this margin of one: a
-- claim that crosses the network a little faster than the one before must still find its token.
local CLAIM_SPACING = 0.3
local CLAIM_MARGIN = 0.1
-- The header: the tier seal, the XP bar and its line.
local HEADER_SEAL = 48
local XP_BAR_HEIGHT = 16
local XP_BAR_MAX = 360
local XP_TEXT_SIZE = 16
-- The showcase of the next reward.
local SHOWCASE_WIDTH = 240
local SHOWCASE_ICON = 64
local SHOWCASE_NAME_SIZE = 20
local SHOWCASE_TIER_SIZE = 18
local SHOWCASE_SPLAT = 1.6
local SHOWCASE_SPLAT_TRANSPARENCY = 0.2
local MIN_SCALED_TEXT = 14
-- Columns built around the current tier on opening; the track builds the rest as its view nears them.
local BUILD_BEHIND = 10
local BUILD_AHEAD = 15
-- A tier's two rewards.
local TRACKS: { Cell.Track } = { "Free", "Premium" }

-- Whether a Robux product can be bought: it is configured, and it exists on Roblox (a non-zero id).
local function productOffered(productKey: string): boolean
	local product = MonetizationConfig.Products[productKey]
	return product ~= nil and product.Id ~= 0
end

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

local function blank(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function list(frame: Frame, direction: Enum.FillDirection, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
end

local function textLabel(name: string, font: Font, size: number, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.FontFace = font
	label.TextScaled = true
	label.TextColor3 = Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Text = ""
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = MIN_SCALED_TEXT
	cap.MaxTextSize = size
	cap.Parent = label
	label.Parent = parent
	return label
end

local function rewardOf(tier: number, track: Cell.Track): BattlepassConfig.Reward?
	local def = TIERS[tier]
	if def == nil then
		return nil
	end
	return if track == "Premium" then def.Premium else def.Free
end

function BattlepassScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	-- Every reward waiting on the pass, and the claims on their way out.
	local claimable: { Claim } = {}
	local queue: { Claim } = {}
	-- The mirror of the remote's bucket, and when the last claim left.
	local bucket = TokenBucket.new(CLAIM_RATE.Capacity, CLAIM_RATE.Refill, os.clock())
	local lastSent = -math.huge
	local pumping = false
	local alive = true
	local refresh: () -> ()

	local root = ScreenRoot.new({
		Name = "BattlepassScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("battlepass.title", { season = string.match(SEASON, "%d+") or SEASON }),
		Chapter = CHAPTER,
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		OnBack = deps.OnBack,
		ShowBack = deps.CanGoBack,
		Localize = deps.Localize,
		Parent = root.Content,
	})
	own(trove, panel)
	root:SetCard(panel)

	----------------------------------------------------------------
	-- Claims, paced under the remote's bucket
	----------------------------------------------------------------

	-- Sends the queued claims one at a time: never closer than CLAIM_SPACING, and never before the mirror of
	-- the server's bucket holds a token and its margin. With a full bucket the first few leave a spacing
	-- apart, then one a refill.
	local function pump()
		if pumping or not alive then
			return
		end
		local nextClaim = queue[1]
		if nextClaim == nil then
			refresh()
			return
		end
		local now = os.clock()
		local wait = math.max(0, CLAIM_SPACING - (now - lastSent))
		local shortfall = 1 + CLAIM_MARGIN - TokenBucket.available(bucket, now)
		if shortfall > 0 then
			wait = math.max(wait, shortfall / CLAIM_RATE.Refill)
		end
		if wait > 0 then
			pumping = true
			task.delay(wait, function()
				pumping = false
				pump()
			end)
			return
		end
		table.remove(queue, 1)
		if TokenBucket.tryTake(bucket, now) then
			lastSent = now
			deps.RemoteClient.fire(CLAIM_REMOTE, nextClaim.Tier, nextClaim.Track)
		end
		refresh()
		pump()
	end
	trove:Add(function()
		alive = false
		table.clear(queue)
	end)

	local function enqueue(tier: number, track: Cell.Track)
		for _, queued in ipairs(queue) do
			if queued.Tier == tier and queued.Track == track then
				return
			end
		end
		table.insert(queue, { Tier = tier, Track = track })
		pump()
	end

	----------------------------------------------------------------
	-- Header: tier, XP, premium, tier skip, claim all
	----------------------------------------------------------------

	panel:SetHeaderHeight(function()
		return Theme.Sizes.PaddingSmall * 2 + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
	end)
	local header = blank("Season", panel.Header)
	header.Size = UDim2.fromScale(1, 1)
	list(header, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)

	local tierSeal = Seal.new({
		Text = "",
		Fill = Theme.Colors.Epic,
		Size = HEADER_SEAL,
		Face = "Numeric",
		LayoutOrder = 1,
		Parent = header,
	})
	own(trove, tierSeal)

	local xpColumn = blank("Xp", header)
	xpColumn.Size = UDim2.fromScale(0, 1)
	xpColumn.LayoutOrder = 2
	local xpFlex = Instance.new("UIFlexItem")
	xpFlex.FlexMode = Enum.UIFlexMode.Fill
	xpFlex.Parent = xpColumn
	local xpCap = Instance.new("UISizeConstraint")
	xpCap.MaxSize = Vector2.new(XP_BAR_MAX, math.huge)
	xpCap.Parent = xpColumn
	list(xpColumn, Enum.FillDirection.Vertical, 4)
	local tierText = textLabel("Tier", Theme.Fonts.Bold, Theme.Sizes.TextBody, 1, xpColumn)
	local xpBar = ProgressBar.new({
		Color = Theme.Colors.Primary,
		Size = UDim2.new(1, 0, 0, XP_BAR_HEIGHT),
		LayoutOrder = 2,
		Parent = xpColumn,
	})
	own(trove, xpBar)
	local xpText = textLabel("Progress", Theme.Fonts.Numeric, XP_TEXT_SIZE, 3, xpColumn)

	local premiumButton = Button.new({
		Text = t("battlepass.getPremium"),
		Sublabel = t("shop.robuxPrice", { price = MonetizationConfig.Products.PremiumPass.PriceRobux }),
		Variant = "Premium",
		LayoutOrder = 3,
		Parent = header,
		OnClick = function()
			deps.RemoteClient.fire("PromptPurchase", "Product", "PremiumPass")
		end,
	})
	own(trove, premiumButton)

	local skipButton = Button.new({
		Text = t("product.tierSkip5"),
		Variant = "Secondary",
		LayoutOrder = 4,
		Parent = header,
		OnClick = function()
			deps.RemoteClient.fire("PromptPurchase", "Product", "TierSkip5")
		end,
	})
	own(trove, skipButton)

	local claimAllButton = Button.new({
		Text = "",
		Variant = "Owner",
		Chapter = CHAPTER,
		LayoutOrder = 5,
		Parent = header,
		OnClick = function()
			for _, claim in ipairs(claimable) do
				enqueue(claim.Tier, claim.Track)
			end
		end,
	})
	own(trove, claimAllButton)

	----------------------------------------------------------------
	-- The stage: the showcase on the left, the road on the right
	----------------------------------------------------------------

	-- The content never scrolls: its canvas is its window, which the stage fills. The road scrolls itself.
	local content = panel.Content
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	content.CanvasSize = UDim2.fromScale(1, 1)
	local stage = blank("Stage", content)
	stage.Size = UDim2.fromScale(1, 1)
	list(stage, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)

	local showcase = Sticker.new({
		Kind = "Card",
		Fill = Theme.Colors.PanelRaised,
		Size = UDim2.new(0, SHOWCASE_WIDTH, 1, 0),
		LayoutOrder = 1,
		Parent = stage,
		Name = "NextReward",
	})
	own(trove, showcase)
	local showBody = blank("Body", showcase.Face)
	showBody.Size = UDim2.fromScale(1, 1)
	local showPadding = Instance.new("UIPadding")
	showPadding.PaddingTop = UDim.new(0, Theme.Sizes.Padding)
	showPadding.PaddingBottom = UDim.new(0, Theme.Sizes.Padding)
	showPadding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	showPadding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	showPadding.Parent = showBody
	list(showBody, Enum.FillDirection.Vertical, Theme.Sizes.PaddingSmall)
	textLabel("Label", Theme.Fonts.Label, Theme.Sizes.TextLabel, 1, showBody).Text = t("battlepass.nextReward")
	local showArt = blank("Art", showBody)
	showArt.Size = UDim2.fromScale(1, 0)
	showArt.LayoutOrder = 2
	local artFlex = Instance.new("UIFlexItem")
	artFlex.FlexMode = Enum.UIFlexMode.Fill
	artFlex.Parent = showArt
	Splat.new({
		Size = UDim2.fromOffset(SHOWCASE_ICON * SHOWCASE_SPLAT, SHOWCASE_ICON * SHOWCASE_SPLAT),
		Tint = Theme.Colors.Epic,
		Rotation = Splat.rotation(3),
		Transparency = SHOWCASE_SPLAT_TRANSPARENCY,
		Parent = showArt,
	})
	local showIcon = blank("Icon", showArt)
	showIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	showIcon.Position = UDim2.fromScale(0.5, 0.5)
	showIcon.Size = UDim2.fromOffset(SHOWCASE_ICON, SHOWCASE_ICON)
	showIcon.ZIndex = 2
	local showName = textLabel("Name", Theme.Fonts.Title, SHOWCASE_NAME_SIZE, 3, showBody)
	local showTier = textLabel("Tier", Theme.Fonts.Numeric, SHOWCASE_TIER_SIZE, 4, showBody)

	local road = Track.new({
		Tiers = TIERS,
		Localize = deps.Localize,
		OnClaim = enqueue,
		LayoutOrder = 2,
		Parent = stage,
	})
	own(trove, road)

	----------------------------------------------------------------
	-- Refresh
	----------------------------------------------------------------

	local function currentSeason(): SeasonData?
		local data = deps.ClientData.get()
		if data == nil then
			return nil
		end
		return data.Battlepass[SEASON]
	end

	-- The reward of the next tier, on the track the player can have: premium when they own it.
	local function showNext(season: SeasonData?)
		for _, child in ipairs(showIcon:GetChildren()) do
			child:Destroy()
		end
		local reached = if season ~= nil then season.Tier else 1
		if reached >= MAX_TIER then
			showName.Text = t("battlepass.completed")
			showTier.Text = ""
			Seal.new({
				Text = Theme.Glyphs.Check,
				Fill = Theme.Colors.SuccessFill,
				Size = SHOWCASE_ICON,
				Parent = showIcon,
			})
			return
		end
		local tier = reached + 1
		local reward = if season ~= nil and season.Premium
			then rewardOf(tier, "Premium") or rewardOf(tier, "Free")
			else rewardOf(tier, "Free")
		showTier.Text = t("battlepass.tierShort", { tier = tier })
		showName.Text = ""
		if reward == nil then
			return
		end
		if reward.Kind == "Folios" then
			Icon.new("Coin", SHOWCASE_ICON).Parent = showIcon
			showName.Text = t("battlepass.reward.folio", { amount = reward.Amount })
		elseif reward.Kind == "XpBoost" then
			Icon.new("Clock", SHOWCASE_ICON, Theme.Colors.Text).Parent = showIcon
			showName.Text = t("battlepass.reward.xpBoost", { minutes = reward.Minutes })
		else
			local item = CosmeticConfig.ById[reward.Id]
			if item ~= nil then
				ItemPreview.new(item, showIcon, deps.Localize)
				showName.Text = t(item.NameKey)
			end
		end
	end

	-- Every reward of the pass waiting to be claimed, built on the road or not: Claim all counts them all.
	local function countClaimable(season: SeasonData?)
		table.clear(claimable)
		for tier = 1, MAX_TIER do
			for index = 1, #TRACKS do
				local which: Cell.Track = TRACKS[index]
				if rewardOf(tier, which) ~= nil and Cell.state(tier, which, season) == "Claimable" then
					table.insert(claimable, { Tier = tier, Track = which })
				end
			end
		end
	end

	refresh = function()
		local season = currentSeason()
		local tier = if season ~= nil then season.Tier else 1
		local xp = if season ~= nil then season.XP else 0
		tierSeal:SetText(tostring(tier))
		tierText.Text = t("battlepass.tier", { tier = tier, max = MAX_TIER })
		if tier >= MAX_TIER then
			xpBar:SetProgress(1)
			xpText.Text = t("battlepass.completed")
		else
			local needed = BattlepassConfig.xpForTier(tier)
			xpBar:SetProgress(if needed > 0 then xp / needed else 0)
			xpText.Text = t("battlepass.xp", { xp = xp, needed = needed })
		end

		premiumButton.Instance.Visible = season == nil or not season.Premium
		premiumButton:SetDisabled(not productOffered("PremiumPass"))
		if tier >= MAX_TIER then
			skipButton:SetDisabled(true, "Full", t("battlepass.completed"))
		else
			skipButton:SetDisabled(not productOffered("TierSkip5"))
		end

		road:Paint(season)
		countClaimable(season)
		-- Claims queued but not sent yet still wait: the button counts down what is left of them.
		local waiting = #queue > 0
		claimAllButton.Instance.Visible = waiting or #claimable >= 2
		if waiting then
			claimAllButton:SetDisabled(true, "Pending", t("battlepass.claimAll", { count = #queue }))
		else
			claimAllButton:SetDisabled(false)
			claimAllButton:SetText(t("battlepass.claimAll", { count = #claimable }))
		end
		road:SetWiggling(screen.Visible and #claimable > 0)
		showNext(season)
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Battlepass" then
			refresh()
		end
	end)

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	-- Claim all, else the current tier's own claim, else the premium track, else the cross.
	local function focusTarget(): GuiObject?
		if claimAllButton.Instance.Visible and not claimAllButton:IsDisabled() then
			return claimAllButton.Instance
		end
		local season = currentSeason()
		local claim = road:ClaimOf(if season ~= nil then season.Tier else 1)
		if claim ~= nil then
			return claim
		end
		if premiumButton.Instance.Visible and not premiumButton:IsDisabled() then
			return premiumButton.Instance
		end
		return nil
	end

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		local season = currentSeason()
		local tier = if season ~= nil then season.Tier else 1
		road:Ensure(tier - BUILD_BEHIND, tier + BUILD_AHEAD)
		refresh()
		root:PlayEnter()
		road:CentreOn(tier)
		panel:FocusForGamepad(focusTarget())
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		road:SetWiggling(false)
		panel:ReleaseGamepadFocus()
		root:PlayExit()
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = close,
		Destroy = destroy,
	}
	refresh()
	return screen
end

return BattlepassScreen
