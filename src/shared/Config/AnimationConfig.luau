--!strict
-- Every animation clip the game plays, and what each one is for.
--
-- The clips are CC0 motion from Quaternius's Universal Animation Library (docs/ASSETS.md), retargeted
-- onto Roblox's R15 skeleton by tools/animations/retarget.py and committed as KeyframeSequences in
-- assets/animations/. scripts/upload_assets.py uploads them and writes their ids into the block below,
-- exactly as it does for the textures and the sounds.
--
-- An id is "" until its clip is uploaded, and an empty id is not an error: the game falls back to the
-- procedural pose for that action (Config/PostureConfig), the same way a texture without an id draws
-- its effect bare.
--
-- Pure data: no require and no Roblox global. Priorities are Enum.AnimationPriority NAMES, converted by
-- the client.

export type Clip = {
	-- "rbxassetid://123", or "" while the clip is not uploaded yet.
	Id: string,
	-- The KeyframeSequence in assets/animations/ this id must be the upload of.
	Source: string,
	-- Length at speed 1, measured from the source clip.
	Seconds: number,
	Looped: boolean,
	Priority: string,
	-- Playback speed. The library clips are paced for a general-purpose game; a battleground hit lands
	-- faster than that, and speeding a clip up is cheaper than re-keying it.
	Speed: number,
	-- Seconds into the clip where the blow lands (the hand at its furthest from the chest, measured by
	-- tools/animations/). The server applies melee damage the moment the hit is requested, so a clip
	-- played from its start would put the spark and the damage number a quarter of a second BEFORE the
	-- fist arrives. Moves starts a strike just before this point instead; 0 for a clip with no blow.
	Impact: number,
}

local AnimationConfig = {}

-- Written by scripts/upload_assets.py from assets/roblox-assets.lock.json: the source file of every
-- uploaded asset, and its id. Never edited by hand -- tests/UploadedAssets.spec.luau holds this block to
-- the lock file, and the lock file to the bytes of each file, so a regenerated asset whose id went stale
-- fails the build instead of rendering the old upload.
-- BEGIN UPLOADED
local UPLOADED: { [string]: string } = {
	["assets/animations/guard_break.rbxmx"] = "rbxassetid://79441446612897",
	["assets/animations/guard_loop.rbxmx"] = "rbxassetid://124143306345974",
	["assets/animations/hit_chest.rbxmx"] = "rbxassetid://91485351933599",
	["assets/animations/melee_hook.rbxmx"] = "rbxassetid://100104040643654",
	["assets/animations/overhand_throw.rbxmx"] = "rbxassetid://89530976835853",
	["assets/animations/punch_cross.rbxmx"] = "rbxassetid://94991981929453",
	["assets/animations/punch_jab.rbxmx"] = "rbxassetid://136529039918121",
	["assets/animations/spell_shoot.rbxmx"] = "rbxassetid://73297736196794",
}
-- END UPLOADED

local function clip(
	source: string,
	seconds: number,
	looped: boolean,
	priority: string,
	speed: number,
	impact: number
): Clip
	local path = "assets/animations/" .. source
	return {
		Id = UPLOADED[path] or "",
		Source = path,
		Seconds = seconds,
		Looped = looped,
		Priority = priority,
		Speed = speed,
		Impact = impact,
	}
end

-- Chosen on screen, from a contact sheet of every candidate frozen at its moment in a live client (a
-- two-handed shove was converted and rejected for the finisher: upright, it read weaker than the
-- overhead smash). Sources and frames: tools/animations/clips.json.
AnimationConfig.Clips = {
	-- The chain escalates: a lead-hand jab, a rear cross, a hook thrown across the body, and an overhead
	-- smash that commits the whole torso -- the hit that launches.
	Jab = clip("punch_jab.rbxmx", 0.88, false, "Action", 1.3, 0.208),
	Cross = clip("punch_cross.rbxmx", 1.0, false, "Action", 1.3, 0.292),
	Hook = clip("melee_hook.rbxmx", 0.46, false, "Action", 1.2, 0.25),
	Smash = clip("overhand_throw.rbxmx", 1.33, false, "Action", 1.25, 0.375),
	-- A glyph leaving the hand: one arm raised high, which no strike does.
	Spell = clip("spell_shoot.rbxmx", 0.5, false, "Action", 1.2, 0),
	-- Held for exactly as long as the guard attribute is on.
	Guard = clip("guard_loop.rbxmx", 2.5, true, "Action", 1, 0),
	-- The guard thrown open: arms flung wide, head back.
	GuardBreak = clip("guard_break.rbxmx", 1.08, false, "Action2", 1, 0),
	-- Taking a blow.
	Flinch = clip("hit_chest.rbxmx", 0.33, false, "Action2", 1, 0),
} :: { [string]: Clip }

-- Which clip plays for which action. The melee chain is indexed like CombatConfig.Melee.Damage; an
-- index with no entry, or an entry whose clip is not uploaded, falls back to the procedural pose.
AnimationConfig.Actions = {
	Melee = { "Jab", "Cross", "Hook", "Smash" },
	Cast = { "Spell" },
	Guard = { "Guard" },
	GuardBreak = { "GuardBreak" },
	Flinch = { "Flinch" },
} :: { [string]: { string } }

-- How long before the blow a strike starts: short enough that the fist lands with the damage number,
-- long enough that the arm is seen travelling rather than appearing.
AnimationConfig.ImpactLeadSeconds = 0.05

-- The clip for an action (and a melee index), or nil when there is none or it is not uploaded yet. The
-- one question both animation systems ask: Moves plays a clip when this returns one, and Posture stands
-- aside for exactly the same actions, so a body is never moved by both.
function AnimationConfig.clipFor(action: string, index: number?): Clip?
	local names = AnimationConfig.Actions[action]
	if names == nil then
		return nil
	end
	local name = names[index or 1]
	local found = if name ~= nil then AnimationConfig.Clips[name] else nil
	if found == nil or found.Id == "" then
		return nil
	end
	return found
end

return AnimationConfig
