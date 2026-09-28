--!strict
-- The movement guard's numbers: Pure/MovementGuard judges with them, Security/MovementAudit measures and acts
-- with them. Lives under src/server, which Rojo maps to ServerScriptService, so no client can read it: the
-- algorithm is no secret, but a client that knew every slack and window could fly or blink just inside them.
--
-- Pure on purpose: no Roblox global and no require, so the tests can load it (tests/Config.spec.luau holds how
-- its numbers relate to the rest of the game). Gravity, the jump velocities, the speed ceiling and the tick are
-- not here: MovementAudit takes them from the engine and GameConfig.

local MovementGuardConfig = {}

----------------------------------------------------------------
-- Rollout and response
----------------------------------------------------------------

-- Observe logs verdicts, Correct also pivots the body back, Enforce also strikes. Shipped in Observe until the
-- Studio checks and clean live logs say the rules hold.
MovementGuardConfig.Mode = "Observe" :: "Observe" | "Correct" | "Enforce"
-- Movement strikes within GameConfig.Server.AbuseWindowSeconds before a kick. Each needs a confirmed incident
-- no exemption covered.
MovementGuardConfig.KickThreshold = 8

----------------------------------------------------------------
-- Horizontal: the chased anchor (H1) and the walking average (H2)
----------------------------------------------------------------

-- Unexplained studs the anchor may trail by before a flag. Above small shoves (a Margin wall, the boss's facing
-- snap) and a spawn on the corner of the hub pad; at 25 a body could sit 50 studs from a Caret destination.
MovementGuardConfig.TeleportSlackStuds = 12
-- A stream silent this long whose next sample jumps is a stall catching up, forgiven what walking at 1.25 x 16
-- could have covered through the silence, banked for at most StallCapSeconds (180 studs).
MovementGuardConfig.StallSeconds = 1
MovementGuardConfig.StallSpeedStudsPerSecond = 20
MovementGuardConfig.StallCapSeconds = 10
-- A sample becomes a correction target only once the anchor is this close to having caught up.
MovementGuardConfig.CleanGapStuds = 6
-- The walking ceiling is the server WalkSpeed x 1.25 + 2 (22 at a walk): it catches 23 studs per second, and
-- walking through a match freeze.
MovementGuardConfig.SustainedFactor = 1.25
MovementGuardConfig.SustainedSlackStudsPerSecond = 2
-- Three seconds of ungranted, contact-free travel out of the last four before H2 speaks.
MovementGuardConfig.SustainedWindowSeconds = 4
MovementGuardConfig.SustainedEvidenceSeconds = 3
-- The ceiling is the fastest WalkSpeed of the last round trip plus this: the client learns a slow late.
MovementGuardConfig.WalkCeilingGraceSeconds = 0.5

----------------------------------------------------------------
-- Grants
----------------------------------------------------------------

-- The client mover overshoots a granted distance at a low frame rate: x1.10 at 60 fps, x1.39 at 15.
MovementGuardConfig.HorizontalOvershoot = 1.5
-- 1 + FeelConfig.Impulse.KnockbackExponent, the peak of the impulse curve: an upper bound at any frame rate.
MovementGuardConfig.LiftOvershoot = 2.9
-- An honest juggle peaks at about 73 horizontal and 99 lift studs; the caps stop grants banking without end.
MovementGuardConfig.MaxAllowanceStuds = 100
MovementGuardConfig.MaxLiftStuds = 120
-- A grant lasts its duration plus clamp(round trip + 0.35, 0.5, 1.5): GetNetworkPing leaves out frame and send
-- time.
MovementGuardConfig.GraceOverheadSeconds = 0.35
MovementGuardConfig.GraceMinSeconds = 0.5
MovementGuardConfig.GraceMaxSeconds = 1.5
-- A grant waits at most this long for its displacement to show, then runs its own duration plus this grace.
MovementGuardConfig.AwaitCapSeconds = 2
MovementGuardConfig.ActivationGraceSeconds = 0.5
-- The round trip is read as the highest of the last RttHoldSeconds and capped here. It rises at once and falls
-- late: a filter that rose slowly would under-grant an honest ping spike.
MovementGuardConfig.MaxRttSeconds = 2
MovementGuardConfig.RttHoldSeconds = 5

----------------------------------------------------------------
-- Vertical: altitude (F1), sink, hang (F2), frozen in the air (F3), path scan
----------------------------------------------------------------

-- A jump and a double jump reach 12.74 studs; 2 more, and a pop of 18.5 onto a ledge is caught.
MovementGuardConfig.AltitudeSlackStuds = 2
-- Receive-time jitter in the fall envelope: without it an honest fall from 900 studs reads as a sink.
MovementGuardConfig.JitterSeconds = 0.35
-- How long the single ascent token lasts, and the smallest rise that counts as one.
MovementGuardConfig.AscentSeconds = 0.65
MovementGuardConfig.RiseEpsilonStuds = 0.25
-- F2 and sink tolerances.
MovementGuardConfig.HangGraceSeconds = 0.3
MovementGuardConfig.DropSlackStuds = 4
MovementGuardConfig.SinkSlackStuds = 6
-- F3 flags a body still in the air every 3 s, 3 studs above its ground, and strikes from the second flag
-- within 30 s.
MovementGuardConfig.FrozenAirSeconds = 3
MovementGuardConfig.FrozenMinHeightStuds = 3
MovementGuardConfig.FrozenStrikeRepeat = 2
MovementGuardConfig.FrozenRepeatWindowSeconds = 30
-- A client counts as alive only when a validated remote arrived a round trip and this much after the freeze.
MovementGuardConfig.InboundMarginSeconds = 0.5
-- The path scan: slack on a landing between two samples, how much of the recent path it covers, the box's
-- margins around it, and how many parts it reads.
MovementGuardConfig.LandingSlackStuds = 1.5
MovementGuardConfig.ScanPathSeconds = 1.5
MovementGuardConfig.ScanMarginStuds = 3
MovementGuardConfig.ScanMaxParts = 32
-- Below the lowest feet and above the root, so a surface level with either is still in the box.
MovementGuardConfig.ScanHeightMarginStuds = 1
-- Surfaces chained through in one scan, each a jump above the last: a body lands only a few times within
-- ScanPathSeconds.
MovementGuardConfig.ScanChainSteps = 3

----------------------------------------------------------------
-- Noclip (N1)
----------------------------------------------------------------

-- A wall is crossed honestly only by a root this far above its top, give or take the slack; steps shorter
-- than NoclipMinStepStuds cast no ray.
MovementGuardConfig.StandMinStuds = 2
MovementGuardConfig.NoclipTopSlackStuds = 1
MovementGuardConfig.NoclipMinStepStuds = 0.5
-- A fall from 900 lands at about 594 studs per second and may tunnel through a 4-stud floor between two
-- physics steps; a drop through a floor is excused only that fast and after a real fall.
MovementGuardConfig.FloorSinkStuds = 1
MovementGuardConfig.TunnelSpeedStudsPerSecond = 150
MovementGuardConfig.TunnelMinFallStuds = 60

----------------------------------------------------------------
-- Confirmation and exemptions
----------------------------------------------------------------

-- Two fresh samples within 2 s confirm a flag; a flag without a new sample counts again after 0.35 s.
MovementGuardConfig.ConfirmCount = 2
MovementGuardConfig.ConfirmWindowSeconds = 2
MovementGuardConfig.PersistSeconds = 0.35
-- Contact exempts for max(1, round trip + 0.5) s; two bodies moving together (unit displacements at least this
-- aligned) get no exemption from each other.
MovementGuardConfig.ContactLatchSeconds = 1
MovementGuardConfig.ContactRttMarginSeconds = 0.5
MovementGuardConfig.CoMoveDot = 0.9
-- No strike right after a spawn or a server hitch; a tick slower than HitchSeconds is a hitch.
MovementGuardConfig.SpawnGraceSeconds = 1
MovementGuardConfig.HitchGraceSeconds = 1
MovementGuardConfig.HitchSeconds = 0.25

----------------------------------------------------------------
-- Server teleports
----------------------------------------------------------------

-- Samples this soon after a pivot are stale and ignored: clamp(round trip + 0.1, 0.2, 1.0).
MovementGuardConfig.SettleMinSeconds = 0.2
MovementGuardConfig.SettleMaxSeconds = 1.0
MovementGuardConfig.SettleOverheadSeconds = 0.1
-- Arrival within 8 studs; a pivot not applied after settle + 2 s is sent again, and the third time counts as
-- resisting; refusals older than 30 s are forgotten.
MovementGuardConfig.ArrivalRadiusStuds = 8
MovementGuardConfig.ArrivalTimeoutSeconds = 2
MovementGuardConfig.ResistTimeouts = 3
MovementGuardConfig.RefusalWindowSeconds = 30
-- Packets can arrive out of order after a pivot: a stale sample just after arrival is ignored, and a return
-- toward where the body came from is not struck.
MovementGuardConfig.ReturnWindowSeconds = 1.5
MovementGuardConfig.ReturnExemptSeconds = 5

----------------------------------------------------------------
-- Sanity, targets and memory
----------------------------------------------------------------

-- A coordinate beyond this is broken: the Battleground's origin sits at 1500 studs.
MovementGuardConfig.MaxCoordinateStuds = 1e5
-- A flight correction prefers a ground point no older than this.
MovementGuardConfig.GroundMaxAgeSeconds = 10
-- Ring sizes in entries, each at least its window x 20 Hz x 1.2.
MovementGuardConfig.SegmentRing = 96
MovementGuardConfig.SafeRing = 16
MovementGuardConfig.PathRing = 40
MovementGuardConfig.WalkRing = 8

----------------------------------------------------------------
-- MovementAudit only
----------------------------------------------------------------

-- The support probe: a sphere cast down from the root to a little past the feet.
MovementGuardConfig.GroundProbeRadiusStuds = 1.5
MovementGuardConfig.GroundProbeSlackStuds = 1.5
-- The last check before any flight correction: wider and deeper than the support probe.
MovementGuardConfig.ConfirmProbeRadiusStuds = 2.5
MovementGuardConfig.ConfirmProbeReachStuds = 4
-- Crossing geometry: a normal this upright is a floor, and a chord this close to a wall's edge is a corner cut.
MovementGuardConfig.FloorNormalY = 0.7
MovementGuardConfig.BodyHalfWidthStuds = 1
-- No barrier ray over a longer step: H1 already flags it.
MovementGuardConfig.RaySkipStuds = 200
-- Contact: roots this close, or a root this far inside a shover's grown box.
MovementGuardConfig.ContactRadiusStuds = 6
MovementGuardConfig.ShoveMarginStuds = 3
-- A root with no Humanoid is taken to stand this high.
MovementGuardConfig.DefaultStandHeightStuds = 3
-- Loop breaker: more than 6 corrections in 10 s pause corrections for 5 s.
MovementGuardConfig.CorrectionBurstLimit = 6
MovementGuardConfig.CorrectionBurstSeconds = 10
MovementGuardConfig.LoopPauseSeconds = 5
-- Log and strike rate limits, per kind.
MovementGuardConfig.WatchLogIntervalSeconds = 10
MovementGuardConfig.StrikeSpacingSeconds = 2
-- The CollectionService tag on barrier geometry: arena floors, walls and cover, the hub platform and kerbs.
MovementGuardConfig.BarrierTag = "MovementBarrier"

return MovementGuardConfig
