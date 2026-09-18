--!strict
-- Sound library. Pure data keyed by SfxId. Ids are Roblox asset ids ("rbxassetid://…") or the
-- engine-built-in fallback, which always exists. Replace ids here; nothing else references them.

export type SoundEntry = { Id: string, Volume: number, Speed: number }

local BUILTIN = "rbxasset://sounds/electronicpingshort.wav"

local SoundConfig = {}

SoundConfig.Sfx = {
	-- Casting (3D, at the caster)
	CastCinnabar = { Id = "rbxassetid://9114428742", Volume = 0.6, Speed = 1.0 },
	CastIndigo = { Id = "rbxassetid://9125703162", Volume = 0.6, Speed = 1.0 },
	CastUmber = { Id = BUILTIN, Volume = 0.7, Speed = 0.55 },
	CastVerdigris = { Id = BUILTIN, Volume = 0.45, Speed = 1.55 },
	CastOrpiment = { Id = BUILTIN, Volume = 0.6, Speed = 1.9 },

	-- Impacts (3D, at the hit point)
	ImpactExplosion = { Id = "rbxassetid://138533090376585", Volume = 0.6, Speed = 1.0 },
	ImpactHit = { Id = BUILTIN, Volume = 0.5, Speed = 1.2 },
	ImpactBlock = { Id = BUILTIN, Volume = 0.5, Speed = 0.8 },

	-- Combat kit
	Melee1 = { Id = BUILTIN, Volume = 0.4, Speed = 1.1 },
	Melee2 = { Id = BUILTIN, Volume = 0.4, Speed = 1.2 },
	Melee3 = { Id = BUILTIN, Volume = 0.45, Speed = 1.3 },
	MeleeFinisher = { Id = BUILTIN, Volume = 0.55, Speed = 0.9 },
	Dash = { Id = BUILTIN, Volume = 0.4, Speed = 1.6 },
	BlockStart = { Id = BUILTIN, Volume = 0.35, Speed = 0.7 },

	-- Personal feedback (2D)
	LevelUp = { Id = BUILTIN, Volume = 0.8, Speed = 1.7 },
	TierUp = { Id = BUILTIN, Volume = 0.8, Speed = 1.35 },
	Kill = { Id = BUILTIN, Volume = 0.6, Speed = 0.9 },
	Claim = { Id = BUILTIN, Volume = 0.7, Speed = 1.5 },
	UiClick = { Id = BUILTIN, Volume = 0.3, Speed = 1.4 },
	UiOpen = { Id = BUILTIN, Volume = 0.3, Speed = 1.2 },
	UiClose = { Id = BUILTIN, Volume = 0.3, Speed = 0.9 },
	Error = { Id = BUILTIN, Volume = 0.35, Speed = 0.5 },
	MatchStart = { Id = BUILTIN, Volume = 0.8, Speed = 1.0 },
	MatchWin = { Id = BUILTIN, Volume = 0.8, Speed = 1.6 },
	MatchLose = { Id = BUILTIN, Volume = 0.7, Speed = 0.6 },
	Countdown = { Id = BUILTIN, Volume = 0.6, Speed = 1.0 },
} :: { [string]: SoundEntry }

-- Looping music. Empty Id = silent.
SoundConfig.Music = {
	Hub = { Id = "rbxassetid://137172521077350", Volume = 0.2, Speed = 1.0 },
	Match = { Id = "", Volume = 0.25, Speed = 1.0 },
	Boss = { Id = "", Volume = 0.3, Speed = 1.0 },
} :: { [string]: SoundEntry }

return SoundConfig
