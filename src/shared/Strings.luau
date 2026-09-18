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
	["common.save"] = { en = "Save", fr = "Sauvegarder" },
	["common.reset"] = { en = "Reset", fr = "Réinitialiser" },
	["common.locked"] = { en = "Locked", fr = "Verrouillé" },

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
	["hud.hint.gamepad"] = { en = "{menu} = Menu", fr = "{menu} = Menu" },
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
	["jutsu.EmberStep.name"] = { en = "Ember Step", fr = "Pas de Braise" },
	["jutsu.EmberStep.desc"] = {
		en = "A short dash that leaves a burning trail behind you.",
		fr = "Une ruée courte qui laisse une traînée brûlante derrière toi.",
	},
	["jutsu.Meteor.name"] = { en = "Meteor", fr = "Météore" },
	["jutsu.Meteor.desc"] = {
		en = "Calls down a blazing rock that shatters guards where it lands.",
		fr = "Fait tomber un rocher enflammé qui brise les gardes là où il s'écrase.",
	},
	["jutsu.WaterPrison.name"] = { en = "Water Prison", fr = "Prison d'Eau" },
	["jutsu.WaterPrison.desc"] = {
		en = "Traps the closest enemy in a sphere of water and roots them in place.",
		fr = "Emprisonne l'ennemi le plus proche dans une sphère d'eau et le cloue au sol.",
	},
	["jutsu.MudShot.name"] = { en = "Mud Shot", fr = "Tir de Boue" },
	["jutsu.MudShot.desc"] = {
		en = "Spits a fast bullet of mud that slows whoever it hits.",
		fr = "Crache une balle de boue rapide qui ralentit sa cible.",
	},
	["jutsu.StoneSkin.name"] = { en = "Stone Skin", fr = "Peau de Pierre" },
	["jutsu.StoneSkin.desc"] = {
		en = "Hardens your skin: less damage taken and no knockback for a few seconds.",
		fr = "Durcit ta peau : moins de dégâts subis et aucun recul pendant quelques secondes.",
	},
	["jutsu.WindBlade.name"] = { en = "Wind Blade", fr = "Lame de Vent" },
	["jutsu.WindBlade.desc"] = {
		en = "Throws a blade of wind that fans its target for your next fire jutsu.",
		fr = "Lance une lame de vent qui évente sa cible pour ton prochain jutsu de feu.",
	},
	["jutsu.Cyclone.name"] = { en = "Cyclone", fr = "Cyclone" },
	["jutsu.Cyclone.desc"] = {
		en = "A whirlwind that drags everyone caught in it toward its centre.",
		fr = "Une tornade qui attire vers son centre tout ce qu'elle happe.",
	},
	["jutsu.Sandstorm.name"] = { en = "Sandstorm", fr = "Tempête de Sable" },
	["jutsu.Sandstorm.desc"] = {
		en = "A storm of sand that blinds and slows everyone inside it.",
		fr = "Une tempête de sable qui aveugle et ralentit ceux qui s'y trouvent.",
	},
	["jutsu.LightningBolt.name"] = { en = "Lightning Bolt", fr = "Éclair" },
	["jutsu.LightningBolt.desc"] = {
		en = "An instant bolt that strikes the first enemy in your line of sight.",
		fr = "Un éclair instantané qui frappe le premier ennemi dans ta ligne de vue.",
	},
	["jutsu.LightningStep.name"] = { en = "Lightning Step", fr = "Pas de l'Éclair" },
	["jutsu.LightningStep.desc"] = {
		en = "Blink forward in a flash, untouchable for an instant.",
		fr = "Disparais vers l'avant dans un éclair, intouchable un instant.",
	},
	["jutsu.StaticField.name"] = { en = "Static Field", fr = "Champ Statique" },
	["jutsu.StaticField.desc"] = {
		en = "A crackling field that shocks and locks up anyone standing in it.",
		fr = "Un champ crépitant qui électrise et bloque ceux qui s'y attardent.",
	},
	["jutsu.Raijin.name"] = { en = "Raijin", fr = "Raijin" },
	["jutsu.Raijin.desc"] = {
		en = "The thunder god's wrath arcs from enemy to enemy.",
		fr = "La colère du dieu du tonnerre bondit d'ennemi en ennemi.",
	},

	-- Elemental statuses (CombatConfig.Status): shown as floating text on the marked target
	["status.fanned"] = { en = "Fanned", fr = "Éventé" },
	["status.conductive"] = { en = "Conductive", fr = "Conducteur" },
	["status.stoneSkin"] = { en = "Stone Skin", fr = "Peau de Pierre" },
	["hud.status.bonus"] = { en = "{status}: +{percent}% damage", fr = "{status} : +{percent} % de dégâts" },

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

	-- Ranks & modes
	["rank.genin"] = { en = "Genin", fr = "Genin" },
	["rank.chunin"] = { en = "Chunin", fr = "Chunin" },
	["rank.jonin"] = { en = "Jonin", fr = "Jonin" },
	["rank.anbu"] = { en = "Anbu", fr = "Anbu" },
	["rank.kage"] = { en = "Kage", fr = "Kage" },
	["mode.duel1v1"] = { en = "Ranked 1v1", fr = "1v1 classé" },
	["mode.team3v3"] = { en = "Team 3v3", fr = "3v3 en équipe" },
	["cosmetic.TitleJonin"] = { en = "Title: Jonin", fr = "Titre : Jonin" },
	["cosmetic.TitleAnbu"] = { en = "Title: Anbu", fr = "Titre : Anbu" },
	["cosmetic.TitleKageSeason"] = { en = "Title: Season Kage", fr = "Titre : Kage de la saison" },

	-- Quests & daily
	["quest.castJutsus"] = { en = "Cast {target} jutsus", fr = "Lance {target} jutsus" },
	["quest.hitJutsus"] = { en = "Hit enemies with {target} jutsus", fr = "Touche des ennemis avec {target} jutsus" },
	["quest.defeatDummies"] = { en = "Defeat {target} training dummies", fr = "Détruis {target} mannequins" },
	["quest.winMatches"] = { en = "Win {target} matches", fr = "Gagne {target} matchs" },
	["quest.playMatches"] = { en = "Play {target} matches", fr = "Joue {target} matchs" },
	["quest.dealDamage"] = { en = "Deal {target} damage", fr = "Inflige {target} dégâts" },
	["quest.useDash"] = { en = "Dash {target} times", fr = "Utilise le dash {target} fois" },
	["quest.landMelee"] = { en = "Land {target} melee hits", fr = "Place {target} coups au corps à corps" },
	["quest.defeatPlayers"] = { en = "Defeat {target} players", fr = "Vaincs {target} joueurs" },
	["quest.joinBoss"] = {
		en = "Take part in {target} World Boss fights",
		fr = "Participe à {target} combats de World Boss",
	},
	["quest.daily"] = { en = "Daily quests", fr = "Quêtes journalières" },
	["quest.weekly"] = { en = "Weekly quests", fr = "Quêtes hebdomadaires" },
	["quest.progress"] = { en = "{progress} / {target}", fr = "{progress} / {target}" },
	["quest.claim"] = { en = "Claim", fr = "Récupérer" },
	["quest.claimed"] = { en = "Claimed", fr = "Récupérée" },
	["quest.reward"] = { en = "+{xp} XP, +{ryo} Ryo", fr = "+{xp} XP, +{ryo} Ryo" },
	["quest.completed"] = { en = "Quest completed: {name}", fr = "Quête terminée : {name}" },
	["daily.title"] = { en = "Daily reward", fr = "Récompense du jour" },
	["daily.streak"] = { en = "Login streak: day {day}", fr = "Série de connexion : jour {day}" },
	["daily.claimed"] = {
		en = "Day {day} reward: +{xp} XP, +{ryo} Ryo",
		fr = "Récompense du jour {day} : +{xp} XP, +{ryo} Ryo",
	},
	["daily.broken"] = {
		en = "Your streak was reset. Come back tomorrow to keep it going!",
		fr = "Ta série est repartie de zéro. Reviens demain pour la garder !",
	},
	["daily.firstWin"] = {
		en = "First win of the day! +{xp} XP, +{ryo} Ryo",
		fr = "Première victoire du jour ! +{xp} XP, +{ryo} Ryo",
	},
	["daily.premium"] = { en = "Premium bonus: +{xp} XP, +{ryo} Ryo", fr = "Bonus Premium : +{xp} XP, +{ryo} Ryo" },

	["cosmetic.SkinWaterWaveJade"] = { en = "Jade Water Wave Skin", fr = "Skin Vague Aquatique Jade" },
	["cosmetic.SkinEarthSpikesObsidian"] = { en = "Obsidian Earth Spikes Skin", fr = "Skin Piques de Terre Obsidienne" },
	["cosmetic.SkinWindGustSilver"] = { en = "Silver Gust Skin", fr = "Skin Rafale Argent" },
	["cosmetic.TrailLeaf"] = { en = "Leaf Trail", fr = "Traînée de Feuilles" },
	["cosmetic.TrailSand"] = { en = "Sand Trail", fr = "Traînée de Sable" },
	["cosmetic.TitleRookie"] = { en = "Title: Rookie", fr = "Titre : Recrue" },
	["cosmetic.TitleWanderer"] = { en = "Title: Wanderer", fr = "Titre : Vagabond" },
	["cosmetic.AuraFrost"] = { en = "Frost Aura", fr = "Aura de Givre" },
	["cosmetic.AuraEmber"] = { en = "Ember Aura", fr = "Aura de Braise" },
	["cosmetic.TrailViolet"] = { en = "Violet Trail", fr = "Traînée Violette" },
	["cosmetic.SkinFireballEmerald"] = { en = "Emerald Fireball Skin", fr = "Skin Boule de Feu Émeraude" },
	["cosmetic.KillEffectPetals"] = { en = "Petal Finisher", fr = "Finisher Pétales" },
	["cosmetic.AuraStorm"] = { en = "Storm Aura", fr = "Aura de Tempête" },
	["cosmetic.SkinEmberStormAzure"] = { en = "Azure Ember Storm Skin", fr = "Skin Tempête de Braises Azur" },
	["cosmetic.AuraVoid"] = { en = "Void Aura", fr = "Aura du Néant" },
	["cosmetic.KillEffectSupernova"] = { en = "Supernova Finisher", fr = "Finisher Supernova" },
	["cosmetic.SkinEarthquakeCrystal"] = { en = "Crystal Earthquake Skin", fr = "Skin Séisme Cristal" },

	-- Passes, products, shop
	["pass.vip"] = { en = "VIP", fr = "VIP" },
	["pass.vip.desc"] = {
		en = "Double XP, +50% Ryo, chat tag and an exclusive aura.",
		fr = "XP ×2, +50 % de Ryo, tag dans le chat et une aura exclusive.",
	},
	["pass.loadoutSlots"] = { en = "Loadout Slots", fr = "Slots d'équipement" },
	["pass.loadoutSlots.desc"] = {
		en = "+4 loadout slots (10 in total).",
		fr = "+4 slots d'équipement (10 au total).",
	},
	["pass.lightning"] = { en = "Lightning Element", fr = "Élément Foudre" },
	["pass.lightning.desc"] = {
		en = "Unlock Lightning right away (or reach level {level} for free).",
		fr = "Débloque la Foudre tout de suite (ou atteins le niveau {level} gratuitement).",
	},
	["pass.skinPack"] = { en = "Skin Pack", fr = "Pack de skins" },
	["pass.skinPack.desc"] = {
		en = "Four jutsu skins, one per base element.",
		fr = "Quatre skins de jutsu, un par élément de base.",
	},
	["product.ryoSmall"] = { en = "1,000 Ryo", fr = "1 000 Ryo" },
	["product.ryoMedium"] = { en = "3,500 Ryo", fr = "3 500 Ryo" },
	["product.ryoLarge"] = { en = "8,000 Ryo", fr = "8 000 Ryo" },
	["product.ryo.desc"] = {
		en = "Ryo to spend in the cosmetic shop.",
		fr = "Des Ryo à dépenser dans la boutique de cosmétiques.",
	},
	["product.premiumPass"] = { en = "Premium Battle Pass", fr = "Battle Pass Premium" },
	["product.premiumPass.desc"] = {
		en = "Unlock the premium track of the current season.",
		fr = "Débloque la piste premium de la saison en cours.",
	},
	["product.tierSkip5"] = { en = "+5 Tiers", fr = "+5 paliers" },
	["product.tierSkip5.desc"] = {
		en = "Advance five battle pass tiers.",
		fr = "Avance de cinq paliers du battle pass.",
	},
	["product.xpBoost1h"] = { en = "XP Boost (1 h)", fr = "Boost d'XP (1 h)" },
	["product.xpBoost1h.desc"] = { en = "Double XP for one hour.", fr = "XP doublée pendant une heure." },
	["product.cosmetic"] = { en = "Cosmetic", fr = "Cosmétique" },
	["product.cosmetic.desc"] = {
		en = "Buy the selected cosmetic with Robux.",
		fr = "Achète le cosmétique sélectionné avec des Robux.",
	},
	["shop.title"] = { en = "Shop", fr = "Boutique" },
	["shop.rotation"] = { en = "Today's selection", fr = "Sélection du jour" },
	["shop.buyRyo"] = { en = "{price} Ryo", fr = "{price} Ryo" },
	["shop.buyRobux"] = { en = "Buy with Robux", fr = "Acheter en Robux" },
	["shop.owned"] = { en = "Owned", fr = "Possédé" },
	["shop.equip"] = { en = "Equip", fr = "Équiper" },
	["shop.equipped"] = { en = "Equipped", fr = "Équipé" },
	["shop.notEnoughRyo"] = { en = "Not enough Ryo.", fr = "Pas assez de Ryo." },
	["shop.purchased"] = { en = "Purchased: {name}", fr = "Acheté : {name}" },
	["shop.rarity.Common"] = { en = "Common", fr = "Commun" },
	["shop.rarity.Rare"] = { en = "Rare", fr = "Rare" },
	["shop.rarity.Epic"] = { en = "Epic", fr = "Épique" },
	["shop.rarity.Legendary"] = { en = "Legendary", fr = "Légendaire" },

	-- Queue, matches and leaderboard
	["queue.title"] = { en = "Play", fr = "Jouer" },
	["queue.join"] = { en = "Join queue", fr = "Rejoindre la file" },
	["queue.leave"] = { en = "Leave queue", fr = "Quitter la file" },
	["queue.searching"] = { en = "Searching… {waited}s", fr = "Recherche… {waited}s" },
	["queue.teamSize"] = { en = "{size}v{size}", fr = "{size}v{size}" },
	["queue.waiting"] = { en = "{queued} / {needed} players", fr = "{queued} / {needed} joueurs" },
	["queue.joined"] = { en = "Queued for {mode}.", fr = "En file pour {mode}." },
	["queue.left"] = { en = "You left the queue.", fr = "Tu as quitté la file." },
	["queue.timedOut"] = { en = "No opponent found. Try again!", fr = "Aucun adversaire trouvé. Réessaie !" },
	["queue.alreadyQueued"] = { en = "You are already in a queue.", fr = "Tu es déjà dans une file." },
	["queue.inMatch"] = { en = "You are already in a match.", fr = "Tu es déjà en match." },
	["match.countdown"] = { en = "{seconds}", fr = "{seconds}" },
	["match.round"] = { en = "Round {round} / {total}", fr = "Manche {round} / {total}" },
	["match.timeLeft"] = { en = "{seconds}s", fr = "{seconds}s" },
	["match.score"] = { en = "{ours} - {theirs}", fr = "{ours} - {theirs}" },
	["match.roundWon"] = { en = "Round won!", fr = "Manche gagnée !" },
	["match.roundLost"] = { en = "Round lost", fr = "Manche perdue" },
	["match.victory"] = { en = "Victory!", fr = "Victoire !" },
	["match.defeat"] = { en = "Defeat", fr = "Défaite" },
	["match.draw"] = { en = "Draw", fr = "Égalité" },
	["match.rewards"] = { en = "+{xp} XP, +{ryo} Ryo", fr = "+{xp} XP, +{ryo} Ryo" },
	["match.ratingUp"] = { en = "{rank}  {rating} (+{delta})", fr = "{rank}  {rating} (+{delta})" },
	["match.ratingDown"] = { en = "{rank}  {rating} ({delta})", fr = "{rank}  {rating} ({delta})" },
	["match.rankUp"] = { en = "New rank: {rank}!", fr = "Nouveau rang : {rank} !" },
	["season.rewardGranted"] = {
		en = "Season reward ({rank}): +{amount} Ryo",
		fr = "Récompense de saison ({rank}) : +{amount} Ryo",
	},
	["match.firstWin"] = { en = "First win of the day!", fr = "Première victoire du jour !" },
	["match.opponentLeft"] = { en = "Your opponent left.", fr = "Ton adversaire est parti." },
	["match.returning"] = { en = "Returning to the hub…", fr = "Retour au hub…" },
	["leaderboard.title"] = { en = "Leaderboard", fr = "Classement" },
	["leaderboard.board.Global"] = { en = "Global", fr = "Global" },
	["leaderboard.board.Duel1v1"] = { en = "1v1", fr = "1v1" },
	["leaderboard.board.Team3v3"] = { en = "3v3", fr = "3v3" },
	["leaderboard.empty"] = { en = "No ranked player yet.", fr = "Aucun joueur classé pour l'instant." },
	["leaderboard.row"] = { en = "#{rank}  {name}", fr = "#{rank}  {name}" },
	["leaderboard.rating"] = { en = "{rating}", fr = "{rating}" },
	["leaderboard.you"] = { en = "You: #{rank} ({rating})", fr = "Toi : #{rank} ({rating})" },
	["leaderboard.youUnlisted"] = { en = "You: outside the top {count}", fr = "Toi : hors du top {count}" },
	["leaderboard.unranked"] = { en = "Unranked — play a ranked match", fr = "Non classé — joue un match classé" },

	-- World Boss
	["boss.name"] = { en = "World Boss", fr = "Boss du monde" },
	["boss.announced"] = {
		en = "A World Boss appears in {seconds}s!",
		fr = "Un boss du monde apparaît dans {seconds}s !",
	},
	["boss.started"] = { en = "The World Boss is here!", fr = "Le boss du monde est là !" },
	["boss.health"] = { en = "{health} / {max}", fr = "{health} / {max}" },
	["boss.phase"] = { en = "Phase {phase}", fr = "Phase {phase}" },
	["boss.timeLeft"] = { en = "{seconds}s left", fr = "{seconds}s restantes" },
	["boss.share"] = { en = "Your damage: {percent}%", fr = "Tes dégâts : {percent} %" },
	["boss.defeated"] = { en = "World Boss defeated!", fr = "Boss du monde vaincu !" },
	["boss.expired"] = { en = "The World Boss escaped…", fr = "Le boss du monde s'est échappé…" },
	["boss.reward"] = { en = "Boss reward: +{xp} XP, +{ryo} Ryo", fr = "Récompense du boss : +{xp} XP, +{ryo} Ryo" },
	["boss.killBonus"] = { en = "Top damage bonus!", fr = "Bonus de meilleur dégât !" },
	["boss.attack.slam"] = { en = "Slam", fr = "Écrasement" },
	["boss.attack.sweep"] = { en = "Sweep", fr = "Balayage" },
	["boss.attack.eruption"] = { en = "Eruption", fr = "Éruption" },
	["boss.attack.fury"] = { en = "Fury", fr = "Furie" },
	["boss.incoming"] = { en = "{attack} incoming!", fr = "{attack} en approche !" },

	-- Loadout
	["loadout.title"] = { en = "Loadout", fr = "Équipement" },
	["loadout.slots"] = { en = "{used} / {total} slots", fr = "{used} / {total} slots" },
	["loadout.equip"] = { en = "Equip", fr = "Équiper" },
	["loadout.unequip"] = { en = "Unequip", fr = "Retirer" },
	["loadout.equipped"] = { en = "Equipped", fr = "Équipé" },
	["loadout.full"] = { en = "Every slot is taken.", fr = "Tous les slots sont pris." },
	["loadout.locked"] = { en = "Unlocks at level {level}", fr = "Se débloque au niveau {level}" },
	["loadout.lockedElement"] = { en = "Requires the {element} element", fr = "Nécessite l'élément {element}" },
	["loadout.saved"] = { en = "Loadout saved!", fr = "Équipement sauvegardé !" },
	["loadout.invalid"] = { en = "Invalid loadout.", fr = "Équipement invalide." },
	["loadout.combo"] = { en = "Combo: {combo}", fr = "Combo : {combo}" },
	["loadout.stats"] = {
		en = "{damage} damage · {cost} chakra · {cooldown}s",
		fr = "{damage} dégâts · {cost} chakra · {cooldown}s",
	},

	-- Cosmetics
	["cosmetics.none"] = { en = "None", fr = "Aucun" },
	["cosmetics.equipped"] = { en = "Equipped: {name}", fr = "Équipé : {name}" },
	["cosmetics.notOwned"] = { en = "You do not own this cosmetic.", fr = "Tu ne possèdes pas ce cosmétique." },

	-- Purchases
	["purchase.prompt"] = { en = "Opening the Roblox purchase…", fr = "Ouverture de l'achat Roblox…" },
	["purchase.granted"] = { en = "Purchase complete: {name}", fr = "Achat terminé : {name}" },
	["purchase.grantedRyoInstead"] = {
		en = "You own every item of that rarity: +{amount} Ryo instead",
		fr = "Tu possèdes tous les articles de cette rareté : +{amount} Ryo à la place",
	},
	["purchase.failed"] = { en = "The purchase could not be completed.", fr = "L'achat n'a pas pu aboutir." },
	["purchase.unavailable"] = {
		en = "This item is not available yet.",
		fr = "Cet article n'est pas encore disponible.",
	},
	["purchase.alreadyOwned"] = { en = "You already own this.", fr = "Tu possèdes déjà cet article." },
	["purchase.passGranted"] = { en = "{name} unlocked!", fr = "{name} débloqué !" },
	["purchase.boostActive"] = {
		en = "XP boost active for {minutes} min",
		fr = "Boost d'XP actif pendant {minutes} min",
	},
	["purchase.tiersGranted"] = { en = "+{tiers} battle pass tiers", fr = "+{tiers} paliers de battle pass" },

	-- Enemies

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
