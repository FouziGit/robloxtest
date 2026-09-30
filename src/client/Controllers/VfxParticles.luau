--!strict
-- VfxParticles: every particle this screen draws, counted against its tier's budget (QualityConfig Particles,
-- Pure/ParticleBudget). The timeline runtime, what bodies wear and the guard break ask here before they emit,
-- and emit what they are granted: a burst is thinned, a flow the renderer emits itself skips what does not fit,
-- an emitter the engine runs is slowed to what fits (art bible rule 8).
--
-- Counted on the clock its particles age on, or a hold would let them outlive their count: what VfxTimeline
-- draws on the effect clock (an impact holds it, and its particles with it through TimeScale), what it draws on
-- the steady one, and the guard break's shards on the steady clock too -- real time in a published game, and in
-- the Studio lab slower than their particles, so counted longer, never shorter. What bodies wear ages in real
-- time whatever the lab does, and has its own count, for its share (QualityConfig.ParticleLedger.WornShare):
-- counted on the lab's slowed clock, an aura looked at in the lab would fill its share and thin itself.
--
-- A sibling module, not a controller, like VfxClock: it has no loop of its own. Each ledger is swept when it is
-- asked, at most once a step, so a frame of fifty flows asking costs fifty lookups, not fifty sweeps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ParticleBudget = require(Shared.Pure.ParticleBudget)
local QualityConfig = require(Shared.Config.QualityConfig)
local VfxClock = require(script.Parent:WaitForChild("VfxClock"))

export type Clock = "Held" | "Steady"

local SETTINGS = QualityConfig.ParticleLedger

local VfxParticles = {}

local held = ParticleBudget.ledger(SETTINGS.Step)
local steady = ParticleBudget.ledger(SETTINGS.Step)
local worn = ParticleBudget.ledger(SETTINGS.Step)
local heldSwept = -math.huge
local steadySwept = -math.huge
local wornSwept = -math.huge

-- Every ledger swept up to its clock's now (at most once a step), and the particles alive on this screen.
local function alive(): number
	local heldNow = VfxClock.now()
	if heldNow - heldSwept >= SETTINGS.Step then
		ParticleBudget.sweep(held, heldNow)
		heldSwept = heldNow
	end
	local steadyNow = VfxClock.steady()
	if steadyNow - steadySwept >= SETTINGS.Step then
		ParticleBudget.sweep(steady, steadyNow)
		steadySwept = steadyNow
	end
	local realNow = os.clock()
	if realNow - wornSwept >= SETTINGS.Step then
		ParticleBudget.sweep(worn, realNow)
		wornSwept = realNow
	end
	return held.Live + steady.Live + worn.Live
end

local function ledgerOf(clock: Clock): (ParticleBudget.Ledger, number)
	if clock == "Held" then
		return held, VfxClock.now()
	end
	return steady, VfxClock.steady()
end

-- Particles alive on this screen now, every effect and every worn look together.
function VfxParticles.live(): number
	return alive()
end

-- Of `wanted` particles living up to `lifetime` seconds of `clock`, how many an effect may emit now under
-- `budget` (its tier's Particles): those are counted, and the caller emits exactly that many.
function VfxParticles.grant(clock: Clock, wanted: number, lifetime: number, budget: number): number
	local granted = ParticleBudget.grant(wanted, ParticleBudget.room(budget, alive()))
	local ledger, now = ledgerOf(clock)
	ParticleBudget.count(ledger, now, granted, lifetime)
	return granted
end

-- The rate, at most `rate`, an emitter the engine runs for `seconds` may have: what it keeps alive at once is
-- reserved until its last particle can have died. The caller sets the emitter's Rate to exactly that.
function VfxParticles.reserve(clock: Clock, rate: number, lifetime: number, seconds: number, budget: number): number
	local allowed = ParticleBudget.rate(rate, lifetime, ParticleBudget.room(budget, alive()))
	local ledger, now = ledgerOf(clock)
	ParticleBudget.count(ledger, now, ParticleBudget.held(allowed, lifetime), seconds + lifetime)
	return allowed
end

-- The same as grant, for what a body wears: within the worn share of `budget` as well as what is left of it. The
-- local player's own look (`own`) asks only what is left: counted in the share, it leaves the crowd less of it, but
-- a crowd never thins the look a player put on, on his own screen. Held to the share like the crowd's, it was
-- drawn at about half of itself in a hub of twenty-four bodies at High, Medium and Low (found by review).
function VfxParticles.grantWorn(wanted: number, lifetime: number, budget: number, own: boolean): number
	local live = alive()
	local room = if own
		then ParticleBudget.room(budget, live)
		else ParticleBudget.wornRoom(budget, SETTINGS.WornShare, live, worn.Live)
	local granted = ParticleBudget.grant(wanted, room)
	ParticleBudget.count(worn, os.clock(), granted, lifetime)
	return granted
end

return VfxParticles
