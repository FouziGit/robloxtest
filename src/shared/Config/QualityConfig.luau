--!strict
-- What the client is allowed to draw, in four tiers, and when it drops one on its own.
--
-- docs/JUICE_PLAN.md phase 9: three graphics settings plus a Performance mode that cuts post-processing,
-- and automatic degradation if the frame rate falls. Art bible rule 8, in full: "La densité de particules
-- est plafonnée et diminue avec le nombre de joueurs proches et le réglage graphique. Un effet qu'on ne
-- peut pas afficher est un effet qu'on ne joue pas." The graphics setting is here; the number of nearby
-- players is NOT counted anywhere, and the frame rate stands in for it on purpose (D-93) -- six players
-- casting at once is what the counter would have measured, and the frame rate is its consequence.
--
-- One tier is one row, and every field of that row has exactly one reader:
--   Layers          -- src/client/Controllers/VfxTimeline (the live-layer ceiling, oldest retired first)
--   ParticleScale   -- src/client/Controllers/VfxTimeline (Rate and Burst of every emitter)
--   Lights          -- src/client/Controllers/VfxTimeline (a Light layer is not drawn at all when false)
--   PostProcessing  -- src/client/Controllers/WorldLighting (the five effects, and every pulse)
--   Footprints      -- src/client/Controllers/FootprintController (a share of its own budget, 0 = none)
--   Flourishes      -- src/client/Controllers/VfxTimeline (a volume marked Flourish is not drawn when false)
--   Afterimages     -- src/client/Controllers/VfxTimeline (how many of a dash's prints are drawn, 0 = none)
--   EngineShare     -- QualityConfig.drivenShare, for VfxTimeline's Driven flows (the engine's thinning, modelled)
--   NameKey         -- src/ui/screens/SettingsScreen
-- tests/EffectCost.spec.luau reads that list back out of the sources: a field nothing reads is a promise
-- to the player that nothing keeps.
--
-- Pure data: no require and no Roblox global (tests/Purity.spec.luau). The High tier repeats
-- VfxTimelineConfig.MaxLiveLayers because a config module may not require another one; the test holds the
-- two equal, so the ceiling of the game and the ceiling of its best tier cannot drift apart.

local QualityConfig = {}

export type Tier = "High" | "Medium" | "Low" | "Performance"

export type TierDef = {
	NameKey: string,
	Layers: number,
	ParticleScale: number,
	Lights: boolean,
	PostProcessing: boolean,
	Footprints: number,
	-- The volumes that add weight rather than meaning (a blast's second ring, its paper scraps, D-114).
	Flourishes: boolean,
	-- How many sketches of a dashing body are left behind (D-116). Each is a limb-for-limb copy of the
	-- avatar, a thousand triangles for a blocky body and ten for a detailed one, so the lower tiers draw
	-- none.
	Afterimages: number,
	-- The share of an emitter's Rate the engine is taken to draw on a device held at this tier: its automatic
	-- graphics quality thins a Rate and never an Emit (D-124). A model until phones are measured (E6-S5): a
	-- device that holds High is not thinned, the floor is the one measurement there is -- the lab's eighty
	-- flames a second drawn as five at the engine's lowest automatic quality -- and each step between halves.
	EngineShare: number,
}

-- Best first. Every step down is a step the client can take by itself, and the last one is the floor.
QualityConfig.Order = { "High", "Medium", "Low", "Performance" } :: { Tier }
QualityConfig.Default = "High" :: Tier

local tiers: { [string]: TierDef } = {
	-- What the effects were authored against (docs/VFX_SPECS.md), on a machine that can hold them.
	High = {
		NameKey = "quality.high",
		Layers = 90,
		ParticleScale = 1,
		Lights = true,
		PostProcessing = true,
		Footprints = 1,
		Flourishes = true,
		Afterimages = 2,
		EngineShare = 1,
	},
	-- Two thirds of the layers and a little over half the particles: the same effects, thinner. Nothing
	-- structural goes -- every telegraph, every mark, every light is still there -- so the game still
	-- reads exactly the same way, which is the only thing a tier may not trade away.
	Medium = {
		NameKey = "quality.medium",
		Layers = 60,
		ParticleScale = 0.6,
		Lights = true,
		PostProcessing = true,
		Footprints = 0.5,
		Flourishes = true,
		Afterimages = 1,
		EngineShare = 0.5,
	},
	-- Dynamic lights go. Roblox pays for a local light whether or not the surface ends up lit, and on a
	-- phone they are the most expensive thing in the frame after the post-processing; the effects keep
	-- their shapes, their marks and their colours, which is what carries the reading.
	Low = {
		NameKey = "quality.low",
		Layers = 36,
		ParticleScale = 0.35,
		Lights = false,
		PostProcessing = true,
		Footprints = 0,
		Flourishes = false,
		Afterimages = 0,
		EngineShare = 0.25,
	},
	-- The post-processing goes too: no bloom, no grade, no depth of field, and no page flash. This is the
	-- floor, and it is still Vellum -- the world is lit high and pale by Lighting itself, not by the
	-- five effects on top of it.
	Performance = {
		NameKey = "quality.performance",
		Layers = 24,
		ParticleScale = 0.2,
		Lights = false,
		PostProcessing = false,
		Footprints = 0,
		Flourishes = false,
		Afterimages = 0,
		EngineShare = 5 / 80,
	},
}

QualityConfig.Tiers = tiers

-- When the client lowers a tier by itself, and when it gives it back.
--
-- It only ever drops BELOW what the player chose, never above: the setting is a ceiling the player owns.
-- Dropping is quick because a player at twenty frames is already having a bad time; giving it back is
-- slow, because a tier that oscillates on every cast is worse than either tier.
QualityConfig.Auto = {
	SampleSeconds = 1,
	DropBelowFps = 40,
	DropAfterSeconds = 3,
	RaiseAboveFps = 55,
	RaiseAfterSeconds = 12,
}

-- A Driven flow (VfxTimelineConfig's Layer.Driven) emits its own particles, which the engine does not thin: a
-- fire's density is its meaning (D-124). It may beat the engine's thinning by this much and no more, so a weak
-- device keeps most of what the engine's thinning saved it (D-229).
QualityConfig.DrivenOverEngine = 2

-- Where a client starts, before its frame rate has said anything (D-229). A new player's first seconds decide
-- whether they stay, and a modest phone that started at High spent them at twenty frames until three bad
-- seconds brought it down. Two things the client knows before its first frame:
--   a screen held in the hand (InputMode.handheld) this many points tall or less is a phone: it starts at Phone;
--   a Roblox graphics level the player set by hand (UserGameSettings.SavedQualityLevel, 1 to 10) at or under
--   LowLevelAtOrUnder starts at LowLevel -- they already told Roblox their device is weak.
-- Either is only a start, never above what the player chose, which stays the ceiling; the frame rate moves it
-- from there (Auto), and a choice made later in the Options is followed as it is.
QualityConfig.Start = {
	PhoneMaxHeight = 430,
	Phone = "Medium" :: Tier,
	LowLevelAtOrUnder = 3,
	LowLevel = "Low" :: Tier,
}

function QualityConfig.isTier(value: any): boolean
	return type(value) == "string" and tiers[value] ~= nil
end

-- The row of `name`, or the default's row for anything else: a profile written by an older build, or a
-- payload from a client that made a name up, must not leave the renderer without a budget.
function QualityConfig.tier(name: any): TierDef
	if QualityConfig.isTier(name) then
		return tiers[name :: string]
	end
	return tiers[QualityConfig.Default]
end

function QualityConfig.indexOf(name: any): number
	for index, tier in ipairs(QualityConfig.Order) do
		if tier == name then
			return index
		end
	end
	return 1
end

-- One step down, or nil at the floor.
function QualityConfig.lower(name: any): Tier?
	return QualityConfig.Order[QualityConfig.indexOf(name) + 1]
end

-- One step up, or nil at the top.
function QualityConfig.higher(name: any): Tier?
	local index = QualityConfig.indexOf(name) - 1
	if index < 1 then
		return nil
	end
	return QualityConfig.Order[index]
end

-- The lower of two tiers: what the client actually draws, given the player's ceiling and what the frame
-- rate has forced.
function QualityConfig.worse(a: any, b: any): Tier
	local index = math.max(QualityConfig.indexOf(a), QualityConfig.indexOf(b))
	return QualityConfig.Order[index]
end

-- The tier a client starts at (Start): what the player chose, lowered on a phone or under a low Roblox graphics
-- level. `level` is the level the player set by hand, or nil when Roblox chooses it (automatic).
function QualityConfig.startTier(chosen: any, phone: boolean, level: number?): Tier
	local start: Tier = if QualityConfig.isTier(chosen) then chosen else QualityConfig.Default
	if phone then
		start = QualityConfig.worse(start, QualityConfig.Start.Phone)
	end
	if level ~= nil and level <= QualityConfig.Start.LowLevelAtOrUnder then
		start = QualityConfig.worse(start, QualityConfig.Start.LowLevel)
	end
	return start
end

-- The share of a Driven flow's rate `tier` draws: all of it where the engine would draw at least
-- 1 / DrivenOverEngine of a Rate, and otherwise DrivenOverEngine times what the engine would.
function QualityConfig.drivenShare(tier: TierDef): number
	return math.min(1, QualityConfig.DrivenOverEngine * tier.EngineShare)
end

return QualityConfig
