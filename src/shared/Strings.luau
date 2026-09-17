--!strict
-- Localization table. Pure module: no requires, no Roblox globals.
-- Every player-visible string lives here as {en = …, fr = …}. English is the default locale.
-- Placeholders use {name} and are substituted by Strings.t(key, params, locale).

export type Entry = { en: string, fr: string }

local Strings = {}

Strings.DefaultLocale = "en"
Strings.Locales = { "en", "fr" }

Strings.Table = {
	-- Common
	["common.ok"] = { en = "OK", fr = "OK" },
	["common.cancel"] = { en = "Cancel", fr = "Annuler" },
	["common.back"] = { en = "Back", fr = "Retour" },
	["common.close"] = { en = "Close", fr = "Fermer" },
	["common.yes"] = { en = "Yes", fr = "Oui" },
	["common.no"] = { en = "No", fr = "Non" },
	["common.save"] = { en = "Save", fr = "Sauvegarder" },
	["common.reset"] = { en = "Reset", fr = "Réinitialiser" },
	["common.locked"] = { en = "Locked", fr = "Verrouillé" },
	["common.level"] = { en = "Level {level}", fr = "Niveau {level}" },

	-- Elements & actions
	["element.fire"] = { en = "Fire", fr = "Feu" },
	["element.water"] = { en = "Water", fr = "Eau" },
	["element.earth"] = { en = "Earth", fr = "Terre" },
	["element.wind"] = { en = "Wind", fr = "Vent" },
	["element.lightning"] = { en = "Lightning", fr = "Foudre" },
	["action.melee"] = { en = "Melee", fr = "Corps à corps" },
	["action.dash"] = { en = "Dash", fr = "Ruée" },
	["action.block"] = { en = "Block", fr = "Garde" },
	["action.menu"] = { en = "Menu", fr = "Menu" },
	["currency.ryo"] = { en = "Ryo", fr = "Ryo" },

	-- HUD / casting feedback
	["hud.combo.noMatch"] = { en = "No jutsu matches…", fr = "Aucun jutsu ne correspond…" },
	["hud.combo.dissipated"] = { en = "The sequence dissipated…", fr = "La séquence s'est dissipée…" },
	["hud.cast.tooFast"] = { en = "Too fast! Catch your breath…", fr = "Trop rapide ! Reprends ton souffle…" },
	["hud.cast.cooldown"] = { en = "{name}: {seconds}s left", fr = "{name} : encore {seconds}s" },
	["hud.cast.success"] = { en = "{name}!", fr = "{name} !" },
	["hud.cast.notEnoughChakra"] = { en = "Not enough chakra", fr = "Pas assez de chakra" },
	["hud.cast.locked"] = { en = "{name} is locked", fr = "{name} est verrouillé" },
	["hud.cast.notEquipped"] = { en = "{name} is not in your loadout", fr = "{name} n'est pas dans ton équipement" },
	["hud.cast.failed"] = { en = "{name} failed", fr = "{name} a échoué" },
	["hud.levelUp"] = { en = "Level {level} reached!", fr = "Niveau {level} atteint !" },
	["hud.tierUp"] = { en = "Battle pass tier {tier} unlocked!", fr = "Palier {tier} du pass débloqué !" },
	["hud.killReward"] = { en = "Enemy defeated! +{xp} XP", fr = "Ennemi vaincu ! +{xp} XP" },
	["hud.playerKill"] = { en = "You defeated {name}! +{xp} XP", fr = "Tu as vaincu {name} ! +{xp} XP" },
	["hud.hint.keyboard"] = { en = "{menu} = Menu", fr = "{menu} = Menu" },
	["hud.chakra"] = { en = "Chakra", fr = "Chakra" },
	["hud.health"] = { en = "Health", fr = "Vie" },
	["hud.bar"] = { en = "{name}  {current} / {max}", fr = "{name}  {current} / {max}" },
	["hud.currency"] = { en = "{amount} {currency}", fr = "{amount} {currency}" },

	-- Level bar
	["level.title"] = { en = "Level {level}", fr = "Niveau {level}" },
	["level.xp"] = { en = "{xp} / {needed} XP", fr = "{xp} / {needed} XP" },
	["level.max"] = { en = "Max level", fr = "Niveau max" },

	-- Menu
	["menu.title"] = { en = "Menu", fr = "Menu" },
	["menu.settings"] = { en = "Settings", fr = "Options" },
	["menu.battlepass"] = { en = "Battle Pass", fr = "Battle Pass" },
	["menu.shop"] = { en = "Shop", fr = "Boutique" },
	["menu.leaderboard"] = { en = "Leaderboard", fr = "Classement" },
	["menu.quests"] = { en = "Quests", fr = "Quêtes" },
	["menu.loadout"] = { en = "Loadout", fr = "Équipement" },

	-- Settings
	["settings.title"] = { en = "Settings", fr = "Options" },
	["settings.tab.keyboard"] = { en = "Keyboard", fr = "Clavier" },
	["settings.tab.gamepad"] = { en = "Gamepad", fr = "Manette" },
	["settings.tab.audio"] = { en = "Audio", fr = "Audio" },
	["settings.hint"] = { en = "Click a binding to change it.", fr = "Clique sur une touche pour la changer." },
	["settings.pressKey"] = {
		en = "Press a key for {action}… (Esc to cancel)",
		fr = "Appuie sur une touche pour {action}… (Échap pour annuler)",
	},
	["settings.captureCancelled"] = { en = "Cancelled.", fr = "Capture annulée." },
	["settings.keyNotAllowed"] = { en = "{key} is not allowed.", fr = "{key} n'est pas autorisée." },
	["settings.swapped"] = {
		en = "Swapped {a} and {b}. Don't forget to save!",
		fr = "{a} et {b} échangés. N'oublie pas de sauvegarder !",
	},
	["settings.bound"] = {
		en = "{action} is now {key}. Don't forget to save!",
		fr = "{action} est maintenant sur {key}. N'oublie pas de sauvegarder !",
	},
	["settings.duplicate"] = { en = "{key} is used twice.", fr = "La touche {key} est utilisée deux fois." },
	["settings.saving"] = { en = "Saving…", fr = "Sauvegarde…" },
	["settings.saved"] = { en = "Settings saved!", fr = "Options sauvegardées !" },
	["settings.saveFailed"] = { en = "Could not save settings.", fr = "Impossible de sauvegarder les options." },
	["settings.music"] = { en = "Music volume", fr = "Volume musique" },
	["settings.sfx"] = { en = "Effects volume", fr = "Volume effets" },
	["settings.cameraShake"] = { en = "Camera shake", fr = "Secousses de caméra" },
	["settings.resetPending"] = {
		en = "Defaults restored. Don't forget to save!",
		fr = "Touches par défaut restaurées. N'oublie pas de sauvegarder !",
	},

	-- Battle pass
	["battlepass.title"] = { en = "Battle Pass — Season {season}", fr = "Battle Pass — Saison {season}" },
	["battlepass.tier"] = { en = "Tier {tier} / {max}", fr = "Palier {tier} / {max}" },
	["battlepass.xp"] = { en = "{xp} / {needed} XP", fr = "{xp} / {needed} XP" },
	["battlepass.completed"] = { en = "Completed!", fr = "Terminé !" },
	["battlepass.free"] = { en = "Free", fr = "Gratuit" },
	["battlepass.premium"] = { en = "Premium", fr = "Premium" },
	["battlepass.claim"] = { en = "Claim", fr = "Récupérer" },
	["battlepass.claimed"] = { en = "Claimed", fr = "Récupéré" },
	["battlepass.reward.ryo"] = { en = "{amount} Ryo", fr = "{amount} Ryo" },
	["battlepass.reward.cosmetic"] = { en = "Cosmetic: {name}", fr = "Cosmétique : {name}" },
	["battlepass.reward.xpBoost"] = { en = "XP boost ({minutes} min)", fr = "Boost d'XP ({minutes} min)" },
	["battlepass.reward.none"] = { en = "No reward", fr = "Aucune récompense" },
	["battlepass.notReached"] = { en = "Tier {tier} not reached yet.", fr = "Palier {tier} pas encore atteint." },
	["battlepass.alreadyClaimed"] = { en = "Already claimed.", fr = "Déjà récupéré." },
	["battlepass.premiumRequired"] = { en = "Premium pass required.", fr = "Pass premium requis." },
	["battlepass.claimedToast"] = { en = "Claimed: {reward}", fr = "Récupéré : {reward}" },
	["battlepass.unlockPremium"] = { en = "Unlock Premium", fr = "Débloquer Premium" },

	-- Jutsus
	["jutsu.Fireball.name"] = { en = "Fireball", fr = "Boule de Feu" },
	["jutsu.Fireball.desc"] = {
		en = "Hurls a sphere of flames that explodes on impact.",
		fr = "Projette une sphère de flammes qui explose à l'impact.",
	},
	["jutsu.WaterWave.name"] = { en = "Water Wave", fr = "Vague Aquatique" },
	["jutsu.WaterWave.desc"] = {
		en = "A wave surges forward and sweeps enemies away.",
		fr = "Une vague déferle et balaie les ennemis.",
	},
	["jutsu.EarthSpikes.name"] = { en = "Earth Spikes", fr = "Piques de Terre" },
	["jutsu.EarthSpikes.desc"] = {
		en = "Rock spikes burst from the ground in a straight line.",
		fr = "Des piques rocheuses jaillissent du sol en ligne droite.",
	},
	["jutsu.WindGust.name"] = { en = "Slicing Gust", fr = "Rafale Tranchante" },
	["jutsu.WindGust.desc"] = {
		en = "A cone of wind violently pushes nearby enemies back.",
		fr = "Un cône de vent repousse violemment les ennemis proches.",
	},
	["jutsu.BoilingMist.name"] = { en = "Boiling Mist", fr = "Brume Bouillante" },
	["jutsu.BoilingMist.desc"] = {
		en = "A scalding cloud that burns and slows enemies inside.",
		fr = "Un nuage brûlant qui blesse et ralentit les ennemis à l'intérieur.",
	},
	["jutsu.MudWall.name"] = { en = "Mud Wall", fr = "Mur de Boue" },
	["jutsu.MudWall.desc"] = {
		en = "Raises a defensive wall of mud in front of you.",
		fr = "Érige un mur de boue défensif devant toi.",
	},
	["jutsu.EmberStorm.name"] = { en = "Ember Storm", fr = "Tempête de Braises" },
	["jutsu.EmberStorm.desc"] = {
		en = "A ring of embers whirls around you and burns everything.",
		fr = "Un anneau de braises tourbillonne autour de toi et brûle tout.",
	},
	["jutsu.Earthquake.name"] = { en = "Earthquake", fr = "Séisme" },
	["jutsu.Earthquake.desc"] = {
		en = "Slam the ground: a massive shockwave launches enemies.",
		fr = "Frappe le sol : une onde de choc massive projette les ennemis.",
	},

	-- Cosmetics
	["cosmetic.GeninHeadband"] = { en = "Genin Headband", fr = "Bandeau du Genin" },
	["cosmetic.SteelKatana"] = { en = "Steel Katana", fr = "Katana d'Acier" },
	["cosmetic.MistCape"] = { en = "Mist Cape", fr = "Cape de Brume" },
	["cosmetic.AnbuMask"] = { en = "Anbu Mask", fr = "Masque Anbu" },
	["cosmetic.BlueChakraAura"] = { en = "Blue Chakra Aura", fr = "Aura de Chakra Bleu" },
	["cosmetic.ClanKimono"] = { en = "Clan Kimono", fr = "Kimono du Clan" },
	["cosmetic.VioletChakraAura"] = { en = "Violet Chakra Aura", fr = "Aura de Chakra Violet" },
	["cosmetic.SageCloak"] = { en = "Sage Cloak", fr = "Manteau de Sage" },
	["cosmetic.GoldenChakraAura"] = { en = "Golden Chakra Aura", fr = "Aura de Chakra Doré" },
	["cosmetic.HokageCloak"] = { en = "Hokage Cloak", fr = "Manteau du Hokage" },
	["cosmetic.TrailEmber"] = { en = "Ember Trail", fr = "Traînée de Braises" },
	["cosmetic.AuraCrimson"] = { en = "Crimson Aura", fr = "Aura Pourpre" },
	["cosmetic.KillEffectShatter"] = { en = "Shatter Finisher", fr = "Finisher Éclat" },
	["cosmetic.TitleShadow"] = { en = "Title: Shadow", fr = "Titre : Ombre" },
	["cosmetic.SkinFireballAzure"] = { en = "Azure Fireball Skin", fr = "Skin Boule de Feu Azur" },
	["cosmetic.TrailStorm"] = { en = "Storm Trail", fr = "Traînée de Tempête" },
	["cosmetic.SkinEarthquakeMagma"] = { en = "Magma Earthquake Skin", fr = "Skin Séisme Magma" },
	["cosmetic.KillEffectLightning"] = { en = "Lightning Finisher", fr = "Finisher Foudre" },
	["cosmetic.TitleKage"] = { en = "Title: Kage", fr = "Titre : Kage" },
	["cosmetic.AuraHokage"] = { en = "Hokage Aura", fr = "Aura du Hokage" },

	-- Enemies
	["enemy.dummy"] = { en = "Training Dummy", fr = "Mannequin d'entraînement" },

	-- Kick / errors
	["kick.sessionElsewhere"] = {
		en = "Your session was opened on another server. Please rejoin.",
		fr = "Ta session a été ouverte sur un autre serveur. Rejoins à nouveau.",
	},
	["kick.loadFailed"] = {
		en = "Could not load your data. Please try again in a minute.",
		fr = "Impossible de charger tes données. Réessaie dans une minute.",
	},
	["kick.abuse"] = {
		en = "Disconnected: too many invalid requests.",
		fr = "Déconnecté : trop de requêtes invalides.",
	},
} :: { [string]: Entry }

-- Substitutes {name} placeholders. Missing params are left as-is.
function Strings.format(template: string, params: { [string]: any }?): string
	if params == nil then
		return template
	end
	local result = string.gsub(template, "{(%w+)}", function(name: string): string
		local value = params[name]
		if value == nil then
			return "{" .. name .. "}"
		end
		return tostring(value)
	end)
	return result
end

-- Translates `key` for `locale` (falls back to English, then to "[key]" so missing entries are visible).
function Strings.t(key: string, params: { [string]: any }?, locale: string?): string
	local entry = Strings.Table[key]
	if entry == nil then
		return "[" .. key .. "]"
	end
	local chosen = locale or Strings.DefaultLocale
	local template = (entry :: any)[chosen]
	if type(template) ~= "string" then
		template = entry.en
	end
	return Strings.format(template, params)
end

function Strings.has(key: string): boolean
	return Strings.Table[key] ~= nil
end

-- Maps a Roblox LocaleId ("fr-fr", "en-us", "de-de") to a supported locale, defaulting to English.
function Strings.localeFromId(localeId: string?): string
	if type(localeId) ~= "string" then
		return Strings.DefaultLocale
	end
	local language = string.lower(string.sub(localeId, 1, 2))
	for _, supported in ipairs(Strings.Locales) do
		if supported == language then
			return supported
		end
	end
	return Strings.DefaultLocale
end

function Strings.keys(): { string }
	local keys = {}
	for key in pairs(Strings.Table) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

return Strings
