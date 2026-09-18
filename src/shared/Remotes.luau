--!strict
-- Typed remote registry. The server creates instances from `Definitions`; both sides look them up by
-- name. Every client→server definition carries a Guard schema per argument and a token-bucket rate.

local ElementConfig = require(script.Parent.Config.ElementConfig)
local GameConfig = require(script.Parent.Config.GameConfig)
local Guard = require(script.Parent.Util.Guard)
local InputConfig = require(script.Parent.Config.InputConfig)
local MatchConfig = require(script.Parent.Config.MatchConfig)
local RankingConfig = require(script.Parent.Config.RankingConfig)

export type Kind = "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent"
export type Direction = "ClientToServer" | "ServerToClient"
export type Rate = { Capacity: number, Refill: number }

export type Definition = {
	Kind: Kind,
	Direction: Direction,
	Args: { Guard.Schema }?, -- client→server only
	Rate: Rate?, -- client→server only
}

local Remotes = {}

Remotes.FolderName = "Remotes"

local elementSchema = Guard.oneOf((ElementConfig.Order :: any) :: { any })
local keybindMapSchema = Guard.map(Guard.string({ min = 1, max = 24 }), { maxLength = #InputConfig.Actions })

Remotes.Definitions = {
	-- Client → Server
	CastJutsu = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = {
			Guard.array(
				elementSchema,
				{ minLength = GameConfig.Combo.MinLength, maxLength = GameConfig.Combo.MaxLength }
			),
		},
		Rate = { Capacity = 8, Refill = 3 },
	},
	UpdateKeybinds = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.oneOf({ "Keyboard", "Gamepad" }), keybindMapSchema },
		Rate = { Capacity = 3, Refill = 0.5 },
	},
	UpdateSettings = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = {
			Guard.strict({
				MusicVolume = Guard.number({ min = 0, max = 1 }),
				SfxVolume = Guard.number({ min = 0, max = 1 }),
				CameraShake = Guard.boolean(),
			}),
		},
		Rate = { Capacity = 3, Refill = 0.5 },
	},
	ClaimBattlepassReward = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.number({ min = 1, max = 50, integer = true }), Guard.oneOf({ "Free", "Premium" }) },
		Rate = { Capacity = 4, Refill = 1 },
	},
	RequestProfile = {
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		Args = {},
		Rate = { Capacity = 4, Refill = 0.5 },
	},
	JoinQueue = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.oneOf((MatchConfig.ModeOrder :: any) :: { any }) },
		Rate = { Capacity = 4, Refill = 0.5 },
	},
	LeaveQueue = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = {},
		Rate = { Capacity = 4, Refill = 0.5 },
	},
	RequestLeaderboard = {
		Kind = "RemoteFunction",
		Direction = "ClientToServer",
		Args = { Guard.oneOf((RankingConfig.Leaderboard.Boards :: any) :: { any }) },
		Rate = { Capacity = 3, Refill = 0.5 },
	},
	ClaimQuest = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.oneOf({ "Daily", "Weekly" }), Guard.string({ min = 1, max = 64 }) },
		Rate = { Capacity = 6, Refill = 1 },
	},
	ClaimDaily = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = {},
		Rate = { Capacity = 3, Refill = 0.5 },
	},
	SetLoadout = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.array(Guard.string({ min = 1, max = 64 }), { maxLength = 10 }) },
		Rate = { Capacity = 4, Refill = 0.5 },
	},
	EquipCosmetic = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.string({ min = 1, max = 64 }), Guard.string({ max = 64 }) },
		Rate = { Capacity = 6, Refill = 1 },
	},
	BuyCosmetic = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.string({ min = 1, max = 64 }) },
		Rate = { Capacity = 4, Refill = 0.5 },
	},
	-- The client never sends a Roblox asset id: it names the catalog entry and the server prompts.
	PromptPurchase = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		-- "Cosmetic" names a shop item: the server records the intent and resolves the per-rarity product,
		-- so a generic product can never grant the wrong cosmetic.
		Args = { Guard.oneOf({ "Pass", "Product", "Cosmetic" }), Guard.string({ min = 1, max = 64 }) },
		Rate = { Capacity = 4, Refill = 0.5 },
	},
	CombatAction = {
		Kind = "RemoteEvent",
		Direction = "ClientToServer",
		Args = { Guard.oneOf({ "Melee", "Dash", "BlockStart", "BlockEnd" }) },
		Rate = { Capacity = 12, Refill = 6 },
	},

	-- Server → Client
	ProfileChanged = { Kind = "RemoteEvent", Direction = "ServerToClient" }, -- (section: string | "*", value)
	Notify = { Kind = "RemoteEvent", Direction = "ServerToClient" }, -- ({Key, Params?, Kind, Sfx?})
	-- Disposable visuals: ({Id, Origin: Vector3, Direction: Vector3, Caster: number?, Targets: {Vector3}?, Params: {[string]: any}?})
	Vfx = { Kind = "UnreliableRemoteEvent", Direction = "ServerToClient" },
	-- Important visuals (walls, zones, kill effects): same payload as Vfx.
	VfxReliable = { Kind = "RemoteEvent", Direction = "ServerToClient" },
	-- Per-player combat snapshot: ({Chakra, MaxChakra, Health, MaxHealth, InCombat, Blocking, Cooldowns: {[jutsuId]: secondsLeft}})
	CombatState = { Kind = "UnreliableRemoteEvent", Direction = "ServerToClient" },
	-- Server-approved movement applied by the owning client (characters are client-simulated on Roblox):
	-- ({Kind = "Dash", Direction: Vector3, Distance: number, Duration: number}
	--  | {Kind = "Knockback", Velocity: Vector3, Duration: number}
	--  | {Kind = "Stun", Seconds: number})
	MovementCommand = { Kind = "RemoteEvent", Direction = "ServerToClient" },
	-- Queue state of the receiving player (Types.QueueSnapshot), pushed on every change.
	QueueChanged = { Kind = "RemoteEvent", Direction = "ServerToClient" },
	-- Match snapshot for a participant (Types.MatchSnapshot), or nil when the match is over.
	MatchChanged = { Kind = "RemoteEvent", Direction = "ServerToClient" },
	-- End-of-match summary (Types.MatchOutcome), sent once before the return to the hub.
	MatchEnded = { Kind = "RemoteEvent", Direction = "ServerToClient" },
	-- World Boss state for everyone on the server (Types.BossSnapshot), or nil when no event runs.
	BossChanged = { Kind = "RemoteEvent", Direction = "ServerToClient" },
	-- Today's shop rotation with ownership resolved for the receiver (Types.ShopSnapshot).
	ShopChanged = { Kind = "RemoteEvent", Direction = "ServerToClient" },
} :: { [string]: Definition }

function Remotes.names(): { string }
	local names = {}
	for name in pairs(Remotes.Definitions) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return Remotes
