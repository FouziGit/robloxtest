--!strict
-- The portals (D-130): a chalk seal on an ink rim, under an ink gateway, that moves whoever STANDS in it.
-- Pure data.
--
-- A portal is a zone, not a button. The server watches every player's trusted position against every seal
-- in the Workspace (PortalService) and moves whoever has stayed inside one for its DwellSeconds. No
-- client-to-server remote exists for travelling: what the client cannot ask for, it cannot forge, and a
-- circle works the same on a keyboard, a gamepad and a touch screen, whatever key the player rebound.
--
-- The gateway's own geometry -- posts, lintel, panel, rim -- is WorldConfig.Portal, and PortalGate builds it.
-- The zone is measured from the Seal part at the gate's foot, which carries SealTag and names its destination
-- in SealAttribute.

export type PortalId = "Battleground" | "WorldBoss" | "Return"
export type ZoneDef = { NameKey: string, HintKey: string, DwellSeconds: number }

local PortalConfig = {}

PortalConfig.Ids = { "Battleground", "WorldBoss", "Return" } :: { PortalId }

-- The CollectionService tag on every gate's Seal part. A tag survives Clone(), so a gate built into an arena
-- template arrives with every copy of it.
PortalConfig.SealTag = "PortalSeal"
-- The attribute on that same part naming where its circle leads: one of Ids. A seal that names anything else
-- opens nothing (PortalService). The gate's board carries it too, for its words.
PortalConfig.SealAttribute = "PortalId"
-- The tag on every gate's board (D-174), which each client writes where the gate leads on: the board is found as
-- the seal is, so a copied or streamed gate is worded without a list of places, and without its seal.
PortalConfig.SignTag = "PortalSign"

-- What a gate's parts are called: the invisible Seal every reader measures from, the Sign its words are written
-- on, and the Model name of the gate that leads back to the hub from the Battleground and from the Erasure's
-- arena (docs/GAME_DESIGN.md §8).
PortalConfig.Anchors = { Seal = "Seal", Sign = "Sign", ReturnGate = "ReturnPortal" }

-- What each seal is called and says on the plate above it, in each player's language, and how long a player
-- has to stand in it before it moves them.
PortalConfig.Zones = {
	Battleground = { NameKey = "portal.battleground.name", HintKey = "portal.hint.enter", DwellSeconds = 1.5 },
	WorldBoss = { NameKey = "portal.worldBoss.name", HintKey = "portal.hint.enter", DwellSeconds = 1.5 },
	-- Longer: a return gate stands where fights happen, so an accidental pass-through must take effort.
	Return = { NameKey = "portal.return.name", HintKey = "portal.hint.return", DwellSeconds = 2 },
} :: { [string]: ZoneDef }

-- The zone: a horizontal disc of this radius around the Seal's position -- the chalk disc a player sees is
-- exactly this wide -- and this far above or below it. A standing root is about 3.5 studs above the seal.
PortalConfig.ZoneRadiusStuds = 5
PortalConfig.ZoneHeightStuds = 8
-- How often the server looks: the resolution of a dwell. Never more often than the gameplay tick.
PortalConfig.CheckHz = 10
-- After a trip, before the next one: no ping-pong between two gates, and no chaining the entry's
-- invulnerability into a player who can never be hit.
PortalConfig.CooldownSeconds = 3
PortalConfig.EntryIFrameSeconds = 1.5
-- The longest a trip waits for the world around its landing to stream in, when the place streams at all
-- (Workspace.StreamingEnabled, pinned in default.project.json): every server teleport that can wait goes through
-- World/Teleport with it -- the Battleground lies past the streaming radius, the arenas 900 studs up.
PortalConfig.StreamTimeoutSeconds = 2

-- The two hub gates: on a ring around the spawn, either side of the platform's empty north (-pi/2), facing
-- the centre. tests/Hub.spec.luau recomputes their clearance from the hub's own numbers.
PortalConfig.Hub = { RingRadiusStuds = 68, AngleOffsetRadians = 0.25 }

-- The Return gate of the Erasure's arena: this far in from both walls of one corner, facing the centre, so
-- its posts stand inside the walls.
PortalConfig.BossArenaGateInsetStuds = 12

return PortalConfig
