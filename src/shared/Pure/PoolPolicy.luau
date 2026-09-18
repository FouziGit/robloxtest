--!strict
-- PoolPolicy: the accounting half of the VFX instance pool, and the half that can be reasoned about
-- without an engine. It answers two questions -- what should this borrow do, what should this release do
-- -- and keeps the counts that say whether the pool is healthy. It never touches an instance.
--
-- The split exists because the part of pooling that breaks is never the Instance.new call. It is the
-- bookkeeping: a count that drifts until the pool creates on every borrow and the pooling buys nothing, a
-- double release that parks one part twice so two effects end up drawing with the same instance, a pool
-- that grows every fight because nothing ever decides to discard. None of that needs a Part to reproduce,
-- so none of it should need Studio to catch. Pure, so tests/PoolPolicy.spec.luau drives a whole fight's
-- worth of borrows in a millisecond.
--
-- Two ceilings per class, because they answer different questions. `Live` is how many of a class may be
-- out at once: a rendering budget, and the one place docs/ART_BIBLE.md rule 8 is enforced as a number --
-- an effect we cannot afford to draw is an effect we do not draw, so a borrow past the ceiling is refused
-- and the renderer drops a layer rather than the frame rate dropping for everyone. `Parked` is how many
-- we keep warm between effects: a memory budget. Live may exceed Parked during a burst; the excess is
-- discarded on the way back instead of being retained for a peak that happened once.

local PoolPolicy = {}
PoolPolicy.__index = PoolPolicy

export type Limits = {
	Live: number, -- how many of this class may be borrowed at once
	Parked: number, -- how many the pool keeps between borrows
}

export type ClassState = {
	Live: number,
	Parked: number,
	Created: number,
	Discarded: number,
	Refused: number, -- borrows denied at the live ceiling
	Unowned: number, -- releases refused because nothing of the class was out
	PeakLive: number,
	PeakParked: number,
}

-- What the caller should do with a borrow. "Reuse" comes with the index of the parked entry to take.
export type Borrow = "Reuse" | "Create" | "Refuse"
-- What the caller should do with the instance coming back.
export type Release = "Park" | "Discard" | "Refuse"

export type Policy = {
	Limits: { [string]: Limits },
	States: { [string]: ClassState },
}

type PolicyImpl = typeof(setmetatable({} :: Policy, PoolPolicy))

-- Shipped ceilings, one row per class the VFX layer builds.
--
-- These are NOT what enforces art bible rule 8. VfxTimelineConfig.MaxLiveLayers is: ninety layers alive
-- at once across every effect on screen, past which the runtime retires the oldest early. A layer borrows
-- between one and five instances, so the timeline runs out of layer budget long before it runs out of any
-- row below, and most of these ceilings are deliberately out of reach of it.
--
-- What they are is the backstop, and it has two jobs a layer budget cannot do. The thirty renderers phase
-- 4 has not converted yet still call Instance.new directly and will come through here one at a time as
-- they are rewritten, each arriving without a budget of its own. And a leak -- a release that never
-- happens because an effect threw halfway through -- shows up here as a live count that climbs and never
-- falls, which is what PeakLive exists to make visible.
--
-- The scene they are sized for is about two dozen effects alive at once on a full server, the heaviest of
-- them ten parts (a spiral is four rings plus six wisps, a stone shell six plates, a boss eruption eight
-- pillars).
PoolPolicy.Limits = {
	-- 24 effects times the heaviest effect's ten parts. Parked at 64 covers the working set of a duel --
	-- casts, hits, melee arcs and dashes overlapping -- without holding a 3v3's peak for the rest of the
	-- session.
	Part = { Live = 240, Parked = 64 },
	-- Emitters ride a minority of those parts: the heavy effects attach smoke or grit to a few anchors,
	-- not to every plate.
	ParticleEmitter = { Live = 120, Parked = 32 },
	-- Trails belong to the things that travel -- embers, blades, dashes -- and there are far fewer of
	-- those on screen than there are parts.
	Trail = { Live = 48, Parked = 16 },
	-- Deliberately the tightest row. Roblox renders only a handful of local lights per surface and drops
	-- the rest, so a higher ceiling would buy nothing but cost: past a couple of dozen the extra lights
	-- are paid for and not seen.
	PointLight = { Live = 24, Parked = 8 },
	-- Two per trail (a trail needs a top and a bottom), two per beam, plus the ones effects use as
	-- emitter anchors.
	Attachment = { Live = 160, Parked = 48 },
	-- Textures on flat surfaces: a sprite carries two (front and back, so it reads from either side) and
	-- a ground mark carries one. Close to Part rather than far below it, because the timelines that use
	-- them are the frequent ones -- every cast draws a seal, every hit leaves a burn -- and most parts a
	-- timeline borrows exist only to host one of these.
	Decal = { Live = 200, Parked = 48 },
	-- The drawn stroke. Rarer than a trail: a beam is a deliberate line between two points, not something
	-- a moving body leaves behind on its own.
	Beam = { Live = 40, Parked = 12 },
} :: { [string]: Limits }

-- No ceiling may exceed this. A row of math.huge is not a generous ceiling, it is the absence of one, and
-- the whole reason this module exists is that the VFX layer must not be able to grow without bound.
local MAX_CEILING = 4096

local function count(value: number): number
	-- A malformed row must not become a negative ceiling, which would read as "refuse everything" in one
	-- place and "park forever" in another, nor an infinite one, which reads as no ceiling at all while
	-- looking like a number.
	if value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, MAX_CEILING)
end

local function newState(): ClassState
	return {
		Live = 0,
		Parked = 0,
		Created = 0,
		Discarded = 0,
		Refused = 0,
		Unowned = 0,
		PeakLive = 0,
		PeakParked = 0,
	}
end

-- `limits` is copied, not held: a caller that mutates its own table later cannot move a ceiling under a
-- pool that has already handed instances out against it.
function PoolPolicy.new(limits: { [string]: Limits }): PolicyImpl
	local copied: { [string]: Limits } = {}
	local states: { [string]: ClassState } = {}
	for className, limit in pairs(limits) do
		copied[className] = { Live = count(limit.Live), Parked = count(limit.Parked) }
		states[className] = newState()
	end
	return setmetatable({ Limits = copied, States = states }, PoolPolicy)
end

-- Decides a borrow, and counts it. Returns the action plus, for "Reuse", the index of the parked entry
-- the caller must take.
--
-- The ceiling is tested before the parked set, and that ordering is what bounds the pool: a class only
-- ever creates while nothing of it is parked, so everything ever built for a class is either out or parked
-- and the two together stay under the live ceiling. Without it, the ceiling would bound what is on screen
-- while the parked set grew behind it.
function PoolPolicy.borrow(self: PolicyImpl, className: string): (Borrow, number)
	local state = self.States[className]
	local limit = self.Limits[className]
	if state == nil or limit == nil then
		return "Refuse", 0
	end
	if state.Live >= limit.Live then
		state.Refused += 1
		return "Refuse", 0
	end

	state.Live += 1
	if state.Live > state.PeakLive then
		state.PeakLive = state.Live
	end
	if state.Parked > 0 then
		-- The most recently parked entry, which is the top of the caller's stack. Last in, first out
		-- keeps the working set small and hot: taking from the bottom would rotate every parked instance
		-- through every effect for no gain, since one blank Part is worth exactly as much as another.
		local index = state.Parked
		state.Parked -= 1
		return "Reuse", index
	end
	state.Created += 1
	return "Create", 0
end

-- Decides what happens to an instance coming back, and counts it.
--
-- Over capacity the arriving instance is the one discarded, never an older parked one: swapping them
-- would cost a destroy and a create to end up with the same number of identical blanks.
function PoolPolicy.release(self: PolicyImpl, className: string): Release
	local state = self.States[className]
	local limit = self.Limits[className]
	if state == nil or limit == nil then
		return "Refuse"
	end
	if state.Live <= 0 then
		-- Nothing of this class is out, so this is a double release or an instance the pool never handed
		-- out. Accepting it is the bug that puts one instance in the parked set twice and then hands it
		-- to two effects at once, which is unwatchable and almost impossible to read back from the
		-- symptom. It is also how a live count goes negative and the ceiling stops holding.
		state.Unowned += 1
		return "Refuse"
	end

	state.Live -= 1
	if state.Parked >= limit.Parked then
		state.Discarded += 1
		return "Discard"
	end
	state.Parked += 1
	if state.Parked > state.PeakParked then
		state.PeakParked = state.Parked
	end
	return "Park"
end

-- A parked instance is gone: something outside the pool destroyed it, or the folder holding it was
-- rebuilt. Keeps the parked count equal to what the caller actually holds, which is the invariant the
-- borrow index depends on. False when the class has nothing parked to drop.
function PoolPolicy.drop(self: PolicyImpl, className: string): boolean
	local state = self.States[className]
	if state == nil or state.Parked <= 0 then
		return false
	end
	state.Parked -= 1
	state.Discarded += 1
	return true
end

-- How many instances are out across every class. Zero is the only right answer once an effect's trove has
-- been cleaned, so this is the leak check: a duel that ends above zero is holding instances somewhere.
function PoolPolicy.outstanding(self: PolicyImpl): number
	local total = 0
	for _, state in pairs(self.States) do
		total += state.Live
	end
	return total
end

-- A copy of the accounting, for a log line or a performance report. Copied so a reader cannot edit the
-- counts by accident, and called rarely enough that the garbage does not matter.
function PoolPolicy.report(self: PolicyImpl): { [string]: ClassState }
	local out: { [string]: ClassState } = {}
	for className, state in pairs(self.States) do
		out[className] = {
			Live = state.Live,
			Parked = state.Parked,
			Created = state.Created,
			Discarded = state.Discarded,
			Refused = state.Refused,
			Unowned = state.Unowned,
			PeakLive = state.PeakLive,
			PeakParked = state.PeakParked,
		}
	end
	return out
end

return PoolPolicy
