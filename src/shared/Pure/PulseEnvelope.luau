--!strict
-- The life of one post-processing pulse: attack, hold, release. Pure (no require, no Roblox global),
-- so its phases are unit-tested under Lune (tests/PulseEnvelope.spec.luau) instead of trusted.
--
-- It exists as a module because it was wrong, silently, in a way no one could see from the code. A
-- pulse can be asked for at less than full strength -- an impact a few studs away bleaches the page less
-- than one in the player's face -- and the attack used to end only once the weight reached ONE. A
-- pulse asked for at 0.9 converged on 0.9, never reached 0.98, never held, never released: the page
-- stayed bleached for good, and every later hit could only raise it. Measured in a live client after a
-- few punches on a training dummy: brightness +0.200, saturation -0.579, bloom 0.703, forever. Every
-- phase now ends relative to the strength that was asked for.
--
-- The spring is passed in rather than required, because a pure module may require nothing (the same
-- way DataMigration takes its helpers); `shape` sets a spring's tension and friction for a duration.

export type SpringLike = {
	Position: number,
	Goal: number,
	Velocity: number,
	step: (self: any, deltaTime: number) -> number,
	setGoal: (self: any, goal: number) -> (),
	snap: (self: any, value: number) -> (),
}

export type Profile = {
	AttackSeconds: number,
	HoldSeconds: number,
	ReleaseSeconds: number,
}

export type Envelope = {
	Weight: SpringLike,
	Profile: Profile,
	Phase: "Attack" | "Hold" | "Release",
	HoldRemaining: number,
	-- How close to its goal the weight must come for a phase to be over, and how close to zero for the
	-- pulse to be gone.
	Epsilon: number,
	Shape: (spring: SpringLike, seconds: number) -> (),
}

local PulseEnvelope = {}

-- A new pulse, attacking toward `strength` (0 to 1).
function PulseEnvelope.new(
	spring: SpringLike,
	shape: (spring: SpringLike, seconds: number) -> (),
	profile: Profile,
	strength: number,
	epsilon: number
): Envelope
	shape(spring, profile.AttackSeconds)
	spring:setGoal(strength)
	return {
		Weight = spring,
		Profile = profile,
		Phase = "Attack",
		HoldRemaining = profile.HoldSeconds,
		Epsilon = epsilon,
		Shape = shape,
	}
end

-- The same pulse asked for again while it plays. It climbs back from wherever it is, keeping its
-- velocity, and a weaker request never pulls a stronger pulse down: a far impact must not soften the
-- near one already on screen.
--
-- That held for attack and hold from the start, and NOT for the release, which is where a review of the
-- first version of this module caught it: re-armed while fading, a weaker request became the new goal,
-- the attack found the weight already above it and snapped DOWN to it -- a near flash fading from 0.83
-- dropped to 0.10 in one frame when a far hit landed, and a fight with hits at every distance flickered.
-- A fading pulse that is already brighter than what is asked simply keeps fading.
function PulseEnvelope.rearm(envelope: Envelope, strength: number)
	local weight = envelope.Weight
	if envelope.Phase == "Release" and strength <= weight.Position then
		return
	end
	local target = if envelope.Phase == "Release" then strength else math.max(strength, weight.Goal)
	envelope.Shape(weight, envelope.Profile.AttackSeconds)
	weight:setGoal(target)
	envelope.Phase = "Attack"
	envelope.HoldRemaining = envelope.Profile.HoldSeconds
end

-- Advances one frame. Returns true once the pulse has released back to nothing and can be dropped.
function PulseEnvelope.step(envelope: Envelope, deltaTime: number): boolean
	-- A frame that does not advance, or a NaN, is held rather than integrated -- the spring already
	-- refuses one, and the hold's countdown must too: HoldRemaining minus NaN is NaN, which is never
	-- "<= 0", which is a pulse held at full strength for good.
	if deltaTime ~= deltaTime or deltaTime <= 0 then
		return false
	end
	local weight = envelope.Weight
	local epsilon = envelope.Epsilon
	if envelope.Phase == "Attack" then
		weight:step(deltaTime)
		-- Relative to the strength asked for, never to one: this is the line that was wrong.
		if weight.Position >= weight.Goal - epsilon then
			weight:snap(weight.Goal)
			envelope.Phase = "Hold"
		end
		return false
	elseif envelope.Phase == "Hold" then
		envelope.HoldRemaining -= deltaTime
		if envelope.HoldRemaining <= 0 then
			envelope.Shape(weight, envelope.Profile.ReleaseSeconds)
			weight:setGoal(0)
			envelope.Phase = "Release"
		end
		return false
	end
	weight:step(deltaTime)
	return weight.Position <= epsilon
end

return PulseEnvelope
