--!strict
-- Contextual prompts (docs/ECONOMY.md §5). A prompt is a localized toast offering an item, never an
-- automatic purchase dialog: the player opens the dialog themselves from the offer.
--
-- Guard-rails, all from MonetizationConfig.Prompts: nothing during the first minutes of the very first
-- session, nothing during a match, at most one prompt every MinIntervalSeconds, plus the per-reason
-- cooldown / per-session cap / minimum level of the reason. An offer the player already owns, an entry
-- with no asset id yet and an unknown reason are all silent refusals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Context = require(script.Parent.Context)
local Log = require(Shared.Util.Log)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)

local log = Log.new("MonetizationService")

type Deps = Context.Deps
type ProfileData = Context.ProfileData

-- One contextual offer: the guard-rail numbers come from the config, the mapping from a moment of play
-- to an item is the rule of docs/ECONOMY.md §5.
type Offer = {
	Kind: Context.PurchaseKind,
	Key: string,
	CooldownSeconds: number?, -- per-reason cooldown, on top of the global interval
	PerSession: number?, -- how many times this reason may prompt in one session
	MinLevel: number?,
}
type ReasonState = { At: number, Count: number }
type PromptState = { LastAt: number, Reasons: { [string]: ReasonState } }

local Rules = MonetizationConfig.Prompts

local OFFERS: { [string]: Offer } = {
	-- Narrow loss: an XP boost turns the next run into progress.
	CloseLoss = { Kind = "Product", Key = "XpBoost1h", CooldownSeconds = Rules.CloseLossCooldownSeconds },
	-- Premium reward the player just reached but cannot claim (battle pass screen only).
	PassTierLocked = { Kind = "Product", Key = "PremiumPass" },
	-- Killed by a Orpiment user, once per session and never to a beginner.
	OrpimentDeath = {
		Kind = "Pass",
		Key = "Orpiment",
		MinLevel = Rules.OrpimentDeathMinLevel,
		PerSession = Rules.OrpimentDeathPerSession,
	},
	-- Every loadout slot taken (loadout screen only).
	LoadoutFull = { Kind = "Pass", Key = "LoadoutSlots" },
}

local Prompts = {}

local deps: Deps
local states: { [Player]: PromptState } = {}

local function stateFor(player: Player): PromptState
	local state = states[player]
	if state == nil then
		-- -math.huge, not 0: os.clock() is small on a fresh server and must not block the first prompt.
		state = { LastAt = -math.huge, Reasons = {} }
		states[player] = state
	end
	return state
end

-- No prompt during the first FirstSessionGraceSeconds of a player's very first session. Once the window
-- has elapsed the gate is recorded in the profile, so later sessions skip the check for good.
local function gateOpen(player: Player, data: ProfileData): boolean
	if data.Meta.FirstSessionPromptGate then
		return true
	end
	if data.Meta.SessionCount <= 1 and os.time() - data.Meta.FirstJoin < Rules.FirstSessionGraceSeconds then
		return false
	end
	data.Meta.FirstSessionPromptGate = true
	deps.DataService.push(player, "Meta")
	return true
end

-- Description key of an offer, or nil when the entry is unknown or has no asset id yet.
local function descKeyOf(offer: Offer): string?
	if offer.Kind == "Pass" then
		local pass = MonetizationConfig.Passes[offer.Key]
		if pass == nil or pass.Id == 0 then
			return nil
		end
		return pass.DescKey
	end
	local product = MonetizationConfig.Products[offer.Key]
	if product == nil or product.Id == 0 then
		return nil
	end
	return product.DescKey
end

-- True when the player already has what the offer sells: nothing to prompt.
local function redundant(player: Player, data: ProfileData, offer: Offer): boolean
	if offer.Kind == "Pass" then
		return data.Passes[offer.Key] == true
	end
	local product = MonetizationConfig.Products[offer.Key]
	if product == nil then
		return true
	end
	if product.Kind == "PremiumPass" then
		return deps.Battlepass.isPremium(player)
	end
	if product.Kind == "XpBoost" then
		return data.Boosts.XpUntil > os.time()
	end
	if product.Kind == "TierSkip" then
		return Context.atMaxTier(data)
	end
	return false
end

-- Offers `reason`'s item to `player` if every guard-rail allows it. Returns true when it was shown.
function Prompts.maybePrompt(player: Player, reason: string): boolean
	local offer = OFFERS[reason]
	if offer == nil then
		log.warn("maybePrompt: unknown reason %s", reason)
		return false
	end
	local data = deps.DataService.get(player)
	if data == nil then
		return false
	end
	if deps.Match.isInMatch(player) then
		return false
	end
	if not gateOpen(player, data) then
		return false
	end
	local descKey = descKeyOf(offer)
	if descKey == nil then
		return false
	end
	if offer.MinLevel ~= nil and deps.Progression.getLevel(player) < offer.MinLevel then
		return false
	end
	if redundant(player, data, offer) then
		return false
	end

	local now = os.clock()
	local state = stateFor(player)
	if now - state.LastAt < Rules.MinIntervalSeconds then
		return false
	end
	local reasonState = state.Reasons[reason]
	if reasonState == nil then
		reasonState = { At = -math.huge, Count = 0 }
		state.Reasons[reason] = reasonState
	end
	if offer.PerSession ~= nil and reasonState.Count >= offer.PerSession then
		return false
	end
	if offer.CooldownSeconds ~= nil and now - reasonState.At < offer.CooldownSeconds then
		return false
	end

	state.LastAt = now
	reasonState.At = now
	reasonState.Count += 1
	deps.Notify.send(player, descKey, nil, "Info")
	deps.Analytics.custom(player, Context.EventPromptShown, nil, { reason = reason, offer = offer.Key })
	log.info("prompted %s with %s (%s)", player.Name, offer.Key, reason)
	return true
end

function Prompts.release(player: Player)
	states[player] = nil
end

function Prompts.Init(injected: Deps)
	deps = injected
end

return Prompts
