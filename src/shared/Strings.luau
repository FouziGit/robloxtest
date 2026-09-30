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
	["common.reset"] = { en = "Reset", fr = "Réinitialiser" },
	["common.locked"] = { en = "Locked", fr = "Verrouillé" },

	-- Pigments & actions
	["pigment.cinnabar"] = { en = "Cinnabar", fr = "Cinabre" },
	["pigment.indigo"] = { en = "Indigo", fr = "Indigo" },
	["pigment.umber"] = { en = "Umber", fr = "Terre d'Ombre" },
	["pigment.verdigris"] = { en = "Verdigris", fr = "Vert-de-gris" },
	["pigment.orpiment"] = { en = "Orpiment", fr = "Orpiment" },
	["action.melee"] = { en = "Melee", fr = "Corps à corps" },
	-- Touch disc labels: short enough to fit a 44 px disc in every locale (InputConfig.ActionShortKeys).
	["action.melee.short"] = { en = "Melee", fr = "CAC" },
	["action.dash.short"] = { en = "Dash", fr = "Ruée" },
	["action.block.short"] = { en = "Block", fr = "Garde" },
	["action.lockOn.short"] = { en = "Lock", fr = "Cible" },
	["action.menu.short"] = { en = "Menu", fr = "Menu" },
	["action.dash"] = { en = "Dash", fr = "Ruée" },
	["action.block"] = { en = "Block", fr = "Garde" },
	["action.lockOn"] = { en = "Lock on", fr = "Verrouiller" },
	["action.menu"] = { en = "Menu", fr = "Menu" },
	["currency.folio"] = { en = "Folios", fr = "Folios" },

	-- HUD / casting feedback
	["hud.combo.noMatch"] = { en = "No glyph matches…", fr = "Aucun glyphe ne correspond…" },
	["hud.combo.dissipated"] = { en = "The sequence dissipated…", fr = "La séquence s'est dissipée…" },
	["hud.sequence.streak"] = { en = "×{count}", fr = "×{count}" },
	["hud.cast.cooldown"] = { en = "{name}: {seconds}s left", fr = "{name} : encore {seconds}s" },
	["hud.cast.chain"] = {
		en = "{name}! ×{count} chain, +{ink} ink",
		fr = "{name} ! Enchaînement ×{count}, +{ink} encre",
	},
	["hud.cast.notEnoughInk"] = { en = "Not enough ink", fr = "Plus d'encre" },
	["hud.cast.locked"] = { en = "{name} is locked", fr = "{name} est verrouillé" },
	["hud.cast.notEquipped"] = { en = "{name} is not in your loadout", fr = "{name} n'est pas dans ton équipement" },
	["hud.cast.failed"] = { en = "{name} failed", fr = "{name} a échoué" },
	["hud.levelUp"] = { en = "Level {level} reached!", fr = "Niveau {level} atteint !" },
	["hud.tierUp"] = { en = "Battle pass tier {tier} unlocked!", fr = "Palier {tier} du pass débloqué !" },
	["hud.killReward"] = { en = "Enemy defeated! +{xp} XP", fr = "Ennemi vaincu ! +{xp} XP" },
	["hud.playerKill"] = { en = "You defeated {name}! +{xp} XP", fr = "Tu as vaincu {name} ! +{xp} XP" },

	-- Level bar
	["level.xp"] = { en = "{xp} / {needed} XP", fr = "{xp} / {needed} XP" },
	["level.max"] = { en = "Max level", fr = "Niveau max" },

	-- Menu
	["menu.title"] = { en = "Menu", fr = "Menu" },
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
	["settings.saved"] = { en = "Settings saved!", fr = "Options sauvegardées !" },
	["settings.saveFailed"] = { en = "Could not save settings.", fr = "Impossible de sauvegarder les options." },
	["settings.music"] = { en = "Music volume", fr = "Volume musique" },
	["settings.sfx"] = { en = "Effects volume", fr = "Volume effets" },
	-- What the switch has governed since D-112 and D-119: the camera's shakes, the page's flashes and the
	-- glow of a spell's core.
	["settings.cameraShake"] = { en = "Shakes and flashes", fr = "Secousses et flashs" },
	["settings.tab.graphics"] = { en = "Graphics", fr = "Graphismes" },
	["settings.quality"] = { en = "Quality", fr = "Qualité" },
	["settings.qualityHint"] = {
		en = "Lower it if the game stutters. The game lowers it by itself when your frame rate drops, and gives it back when it recovers.",
		fr = "Baisse-la si le jeu saccade. Le jeu la baisse tout seul quand tes images par seconde tombent, et la rend quand elles remontent.",
	},
	["quality.high"] = { en = "High", fr = "Élevée" },
	["quality.medium"] = { en = "Medium", fr = "Moyenne" },
	["quality.low"] = { en = "Low", fr = "Basse" },
	["quality.performance"] = { en = "Performance", fr = "Performance" },

	-- Battle pass
	["battlepass.title"] = { en = "Battle Pass — Volume {season}", fr = "Battle Pass — Volume {season}" },
	["battlepass.tier"] = { en = "Tier {tier} / {max}", fr = "Palier {tier} / {max}" },
	["battlepass.xp"] = { en = "{xp} / {needed} XP", fr = "{xp} / {needed} XP" },
	["battlepass.completed"] = { en = "Completed!", fr = "Terminé !" },
	["battlepass.premium"] = { en = "Premium", fr = "Premium" },
	["battlepass.claim"] = { en = "Claim", fr = "Réclamer" },
	["battlepass.reward.folio"] = { en = "{amount} Folios", fr = "{amount} Folios" },
	["battlepass.reward.cosmetic"] = { en = "Cosmetic: {name}", fr = "Cosmétique : {name}" },
	["battlepass.reward.xpBoost"] = { en = "XP boost ({minutes} min)", fr = "Boost d'XP ({minutes} min)" },
	["battlepass.notReached"] = { en = "Tier {tier} not reached yet.", fr = "Palier {tier} pas encore atteint." },
	["battlepass.alreadyClaimed"] = { en = "Already claimed.", fr = "Déjà réclamé." },
	["battlepass.premiumRequired"] = { en = "Premium pass required.", fr = "Pass premium requis." },

	-- Glyphs
	["glyph.Brand.name"] = { en = "Brand", fr = "Marque" },
	["glyph.Brand.desc"] = {
		en = "Hurls a sphere of flames that explodes on impact.",
		fr = "Projette une sphère de flammes qui explose à l'impact.",
	},
	["glyph.Wash.name"] = { en = "Wash", fr = "Lavis" },
	["glyph.Wash.desc"] = {
		en = "A wave surges forward and sweeps enemies away.",
		fr = "Une vague déferle et balaie les ennemis.",
	},
	["glyph.Serif.name"] = { en = "Serif", fr = "Empattement" },
	["glyph.Serif.desc"] = {
		en = "Rock spikes burst from the ground in a straight line.",
		fr = "Des piques rocheuses jaillissent du sol en ligne droite.",
	},
	["glyph.Sweep.name"] = { en = "Sweep", fr = "Balayage" },
	["glyph.Sweep.desc"] = {
		en = "A cone of wind violently pushes nearby enemies back.",
		fr = "Un cône de vent repousse violemment les ennemis proches.",
	},
	["glyph.Bleed.name"] = { en = "Bleed", fr = "Bavure" },
	["glyph.Bleed.desc"] = {
		en = "A scalding cloud that burns and slows enemies inside.",
		fr = "Un nuage brûlant qui blesse et ralentit les ennemis à l'intérieur.",
	},
	["glyph.Margin.name"] = { en = "Margin", fr = "Marge" },
	["glyph.Margin.desc"] = {
		en = "Raises a defensive wall of mud in front of you.",
		fr = "Érige un mur de boue défensif devant toi.",
	},
	["glyph.Scorch.name"] = { en = "Scorch", fr = "Roussi" },
	["glyph.Scorch.desc"] = {
		en = "A scorched ring that follows you: everything inside it burns.",
		fr = "Un anneau roussi qui te suit : tout ce qui s'y tient brûle.",
	},
	["glyph.Rupture.name"] = { en = "Rupture", fr = "Rupture" },
	["glyph.Rupture.desc"] = {
		en = "Slam the ground: a massive shockwave launches enemies.",
		fr = "Frappe le sol : une onde de choc massive projette les ennemis.",
	},
	["glyph.Ligature.name"] = { en = "Ligature", fr = "Ligature" },
	["glyph.Ligature.desc"] = {
		en = "A short dash that leaves a burning trail behind you.",
		fr = "Une ruée courte qui laisse une traînée brûlante derrière toi.",
	},
	["glyph.Blot.name"] = { en = "Blot", fr = "Pâté" },
	["glyph.Blot.desc"] = {
		en = "Drops a blot of ink from above that shatters guards where it lands.",
		fr = "Fait tomber un pâté d'encre qui brise les gardes là où il s'écrase.",
	},
	["glyph.Binding.name"] = { en = "Binding", fr = "Reliure" },
	["glyph.Binding.desc"] = {
		en = "Traps the closest enemy in a sphere of water and roots them in place.",
		fr = "Emprisonne l'ennemi le plus proche dans une sphère d'eau et le cloue au sol.",
	},
	["glyph.Stipple.name"] = { en = "Stipple", fr = "Pointillé" },
	["glyph.Stipple.desc"] = {
		en = "Spits a fast bullet of mud that slows whoever it hits.",
		fr = "Crache une balle de boue rapide qui ralentit sa cible.",
	},
	["glyph.Gilding.name"] = { en = "Gilding", fr = "Dorure" },
	["glyph.Gilding.desc"] = {
		en = "Hardens your skin: less damage taken and no knockback for a few seconds.",
		fr = "Durcit ta peau : moins de dégâts subis et aucun recul pendant quelques secondes.",
	},
	["glyph.Hairline.name"] = { en = "Hairline", fr = "Délié" },
	["glyph.Hairline.desc"] = {
		en = "Throws a blade of wind that fans its target for your next fire glyph.",
		fr = "Trace un délié qui évente sa cible pour ton prochain glyphe de Cinabre.",
	},
	["glyph.Spiral.name"] = { en = "Spiral", fr = "Spirale" },
	["glyph.Spiral.desc"] = {
		en = "A whirlwind that drags everyone caught in it toward its centre.",
		fr = "Une tornade qui attire vers son centre tout ce qu'elle happe.",
	},
	["glyph.Pounce.name"] = { en = "Pounce", fr = "Poncif" },
	["glyph.Pounce.desc"] = {
		en = "A storm of sand that blinds and slows everyone inside it.",
		fr = "Une tempête de sable qui aveugle et ralentit ceux qui s'y trouvent.",
	},
	["glyph.Strike.name"] = { en = "Strike", fr = "Rature" },
	["glyph.Strike.desc"] = {
		en = "One stroke crosses out the first enemy in your line of sight.",
		fr = "Un seul trait rature le premier ennemi dans ta ligne de vue.",
	},
	["glyph.Caret.name"] = { en = "Caret", fr = "Insertion" },
	["glyph.Caret.desc"] = {
		en = "Cross yourself out here and write yourself in further on, untouchable between the two.",
		fr = "Rature-toi ici et réécris-toi plus loin, intouchable entre les deux.",
	},
	["glyph.Watermark.name"] = { en = "Watermark", fr = "Filigrane" },
	["glyph.Watermark.desc"] = {
		en = "A mark pressed into the ground: whoever stays in it is held by the page.",
		fr = "Une marque pressée dans le sol : qui s'y attarde est retenu par la page.",
	},
	["glyph.Colophon.name"] = { en = "Colophon", fr = "Colophon" },
	["glyph.Colophon.desc"] = {
		en = "Your signature leaps from body to body, and everyone it touches is signed.",
		fr = "Ta signature bondit d'un corps à l'autre, et chacun qu'elle touche est signé.",
	},
	["glyph.Volute.name"] = { en = "Volute", fr = "Volute" },
	["glyph.Volute.desc"] = {
		en = "Winds a coil of ink in your hand, then presses it into the closest enemy: hurled back and stunned.",
		fr = "Enroule une volute d'encre dans ta main, puis la plaque sur l'ennemi le plus proche : projeté et étourdi.",
	},
	["glyph.Rubric.name"] = { en = "Rubric", fr = "Rubrique" },
	["glyph.Rubric.desc"] = {
		en = "Hold still to charge, then rule a thick red line straight ahead that pierces up to three enemies.",
		fr = "Charge sans bouger, puis trace droit devant une épaisse ligne rouge qui transperce jusqu'à trois ennemis.",
	},
	["glyph.Swash.name"] = { en = "Swash", fr = "Paraphe" },
	["glyph.Swash.desc"] = {
		en = "Sweeps a wide flourish of ink along the ground, cutting through everyone in its path until a wall stops it.",
		fr = "Lance au ras du sol un large paraphe d'encre qui tranche tous ceux qu'il traverse, jusqu'au premier mur.",
	},
	["glyph.Dagger.name"] = { en = "Dagger", fr = "Obèle" },
	["glyph.Dagger.desc"] = {
		en = "Vanish and reappear behind the nearest enemy in front of you, striking their back.",
		fr = "Disparais et réapparais dans le dos de l'ennemi le plus proche devant toi, et frappe-le.",
	},
	["glyph.Cartouche.name"] = { en = "Cartouche", fr = "Cartouche" },
	["glyph.Cartouche.desc"] = {
		en = "Frames the ground around you in ink: enemies inside are stunned through their guard, then slowed and hurt while they stay.",
		fr = "Encadre d'encre le sol autour de toi : les ennemis pris dedans sont étourdis malgré leur garde, puis ralentis et blessés tant qu'ils y restent.",
	},
	["glyph.Emboss.name"] = { en = "Emboss", fr = "Gaufrage" },
	["glyph.Emboss.desc"] = {
		en = "Presses the page outward from you: everyone around you is thrown back.",
		fr = "Repousse la page tout autour de toi : tous ceux qui t'entourent sont projetés.",
	},
	["glyph.Stitch.name"] = { en = "Stitch", fr = "Chaînette" },
	["glyph.Stitch.desc"] = {
		en = "Throws a stitch of ink that catches the first enemy in its path and drags them to you, rooted.",
		fr = "Lance une chaînette d'encre qui saisit le premier ennemi sur sa route et le ramène à toi, cloué au sol.",
	},
	["glyph.Hatching.name"] = { en = "Hatching", fr = "Hachures" },
	["glyph.Hatching.desc"] = {
		en = "A flurry of strokes in front of you, then a last one that launches.",
		fr = "Une rafale de traits devant toi, puis un dernier qui projette.",
	},

	-- Pigment statuses (CombatConfig.Status): shown as floating text on the marked target
	["status.fanned"] = { en = "Fanned", fr = "Éventé" },
	["status.conductive"] = { en = "Conductive", fr = "Conducteur" },
	["status.stoneSkin"] = { en = "Stone Skin", fr = "Peau de Pierre" },
	["hud.status.bonus"] = { en = "{status}: +{percent}% damage", fr = "{status} : +{percent} % de dégâts" },

	-- Cosmetics
	["cosmetic.BlankHeadband"] = { en = "Title: Apprentice", fr = "Titre : Apprenti" },
	["cosmetic.SteelStylus"] = { en = "Stylus Trail", fr = "Traînée de Stylet" },
	["cosmetic.PalimpsestCape"] = { en = "Palimpsest Aura", fr = "Aura de Palimpseste" },
	["cosmetic.FrisketMask"] = { en = "Title: Frisket", fr = "Titre : Frisquette" },
	["cosmetic.BlueInkAura"] = { en = "Wet Ink Aura", fr = "Aura d'Encre Fraîche" },
	["cosmetic.ScriptoriumRobe"] = { en = "Title: Scriptorium Hand", fr = "Titre : Main du Scriptorium" },
	["cosmetic.VioletInkAura"] = { en = "Iron-Gall Aura", fr = "Aura Ferro-Gallique" },
	["cosmetic.ScribeCloak"] = { en = "Scribe's Stroke", fr = "Trait du Scribe" },
	["cosmetic.GoldenInkAura"] = { en = "Illuminated Aura", fr = "Aura Enluminée" },
	["cosmetic.CodexCloak"] = { en = "Title: Keeper of the Codex", fr = "Titre : Gardien du Codex" },
	["cosmetic.TrailEmber"] = { en = "Soot Trail", fr = "Traînée de Suie" },
	["cosmetic.AuraCrimson"] = { en = "Smoke Aura", fr = "Aura de Fumée" },
	["cosmetic.KillEffectShatter"] = { en = "Torn Page Finisher", fr = "Finisher Page Déchirée" },
	["cosmetic.TitleShadow"] = { en = "Title: Silent Hand", fr = "Titre : Main Silencieuse" },
	["cosmetic.SkinBrandAzure"] = { en = "Charred Brand Skin", fr = "Skin Marque Calcinée" },
	["cosmetic.TrailStorm"] = { en = "Scrawl Trail", fr = "Traînée de Griffonnage" },
	["cosmetic.SkinRuptureMagma"] = { en = "Bedrock Rupture Skin", fr = "Skin Rupture du Socle" },
	["cosmetic.KillEffectRedaction"] = { en = "Redaction Finisher", fr = "Finisher Caviardage" },
	["cosmetic.TitleCodex"] = { en = "Title: Bound in Vellum", fr = "Titre : Relié de Vélin" },
	["cosmetic.AuraCodex"] = { en = "Codex Aura", fr = "Aura du Codex" },

	-- Ranks & modes
	["rank.blank"] = { en = "Blank", fr = "Vierge" },
	["rank.sketch"] = { en = "Sketch", fr = "Esquisse" },
	["rank.script"] = { en = "Script", fr = "Écriture" },
	["rank.illumination"] = { en = "Illumination", fr = "Enluminure" },
	["rank.codex"] = { en = "Codex", fr = "Codex" },
	["mode.duel1v1"] = { en = "Ranked 1v1", fr = "1v1 classé" },
	["mode.team3v3"] = { en = "Team 3v3", fr = "3v3 en équipe" },
	["cosmetic.TitleScript"] = { en = "Title: Script", fr = "Titre : Écriture" },
	["cosmetic.TitleIllumination"] = { en = "Title: Illumination", fr = "Titre : Enluminure" },
	["cosmetic.TitleCodexSeason"] = { en = "Title: Codex of the Volume", fr = "Titre : Codex du volume" },

	-- Quests & daily
	["quest.castGlyphs"] = { en = "Cast {target} glyphs", fr = "Trace {target} glyphes" },
	["quest.hitGlyphs"] = { en = "Hit enemies with {target} glyphs", fr = "Touche des ennemis avec {target} glyphes" },
	["quest.defeatDummies"] = { en = "Defeat {target} training dummies", fr = "Détruis {target} mannequins" },
	["quest.defeatForgers"] = { en = "Defeat {target} Forgers", fr = "Vaincs {target} Faussaires" },
	["quest.winMatch"] = { en = "Win a match", fr = "Gagne un match" },
	["quest.winMatches"] = { en = "Win {target} matches", fr = "Gagne {target} matchs" },
	["quest.playMatches"] = { en = "Play {target} matches", fr = "Joue {target} matchs" },
	["quest.dealDamage"] = { en = "Deal {target} damage", fr = "Inflige {target} dégâts" },
	["quest.useDash"] = { en = "Dash {target} times", fr = "Utilise le dash {target} fois" },
	["quest.landMelee"] = { en = "Land {target} melee hits", fr = "Place {target} coups au corps à corps" },
	["quest.defeatPlayers"] = { en = "Defeat {target} players", fr = "Vaincs {target} joueurs" },
	["quest.joinBoss"] = {
		en = "Face the Erasure {target} times",
		fr = "Affronte l'Effacement {target} fois",
	},
	["quest.chainCasts"] = { en = "Chain {target} glyphs", fr = "Enchaîne {target} glyphes" },
	["quest.cancelRecovery"] = {
		en = "Cancel {target} recoveries with a dash",
		fr = "Annule {target} récupérations d'une ruée",
	},
	["quest.daily"] = { en = "Daily quests", fr = "Quêtes journalières" },
	["quest.weekly"] = { en = "Weekly quests", fr = "Quêtes hebdomadaires" },
	["quest.progress"] = { en = "{progress} / {target}", fr = "{progress} / {target}" },
	["quest.claim"] = { en = "Claim", fr = "Réclamer" },
	["quest.claimed"] = { en = "Claimed", fr = "Réclamée" },
	["quest.reward"] = { en = "+{xp} XP, +{folios} Folios", fr = "+{xp} XP, +{folios} Folios" },
	["quest.completed"] = { en = "Quest completed: {name}", fr = "Quête terminée : {name}" },
	["daily.title"] = { en = "Daily reward", fr = "Récompense du jour" },
	["daily.streak"] = { en = "Login streak: day {day}", fr = "Série de connexion : jour {day}" },
	["daily.claimed"] = {
		en = "Day {day} reward: +{xp} XP, +{folios} Folios",
		fr = "Récompense du jour {day} : +{xp} XP, +{folios} Folios",
	},
	["daily.broken"] = {
		en = "Your streak was reset. Come back tomorrow to keep it going!",
		fr = "Ta série est repartie de zéro. Reviens demain pour la garder !",
	},
	["daily.firstWin"] = {
		en = "First win of the day! +{xp} XP, +{folios} Folios",
		fr = "Première victoire du jour ! +{xp} XP, +{folios} Folios",
	},
	["daily.premium"] = {
		en = "Premium bonus: +{folios} Folios and double XP for {minutes} min",
		fr = "Bonus Premium : +{folios} Folios et XP doublée pendant {minutes} min",
	},

	["cosmetic.SkinWashJade"] = { en = "Deep Wash Skin", fr = "Skin Lavis Profond" },
	["cosmetic.SkinSerifObsidian"] = { en = "Obsidian Serif Skin", fr = "Skin Empattement Obsidienne" },
	["cosmetic.SkinSweepSilver"] = { en = "Faded Sweep Skin", fr = "Skin Balayage Passé" },
	["cosmetic.TrailFolio"] = { en = "Folio Trail", fr = "Traînée de Folios" },
	["cosmetic.TrailSand"] = { en = "Pumice Trail", fr = "Traînée de Ponce" },
	["cosmetic.TitleRookie"] = { en = "Title: Rookie", fr = "Titre : Recrue" },
	["cosmetic.TitleWanderer"] = { en = "Title: Wanderer", fr = "Titre : Vagabond" },
	["cosmetic.AuraFrost"] = { en = "Graphite Aura", fr = "Aura de Graphite" },
	["cosmetic.AuraEmber"] = { en = "Soot Aura", fr = "Aura de Suie" },
	["cosmetic.TrailViolet"] = { en = "Iron-Gall Trail", fr = "Traînée Ferro-Gallique" },
	["cosmetic.SkinBrandEmerald"] = { en = "Vermilion Brand Skin", fr = "Skin Marque Vermillon" },
	["cosmetic.KillEffectPetals"] = { en = "Paper Petals Finisher", fr = "Finisher Pétales de Papier" },
	["cosmetic.AuraStorm"] = { en = "Scrawl Aura", fr = "Aura de Griffonnage" },
	["cosmetic.SkinScorchAzure"] = { en = "Smouldering Scorch Skin", fr = "Skin Roussi Couvant" },
	["cosmetic.AuraVoid"] = { en = "Void Aura", fr = "Aura du Néant" },
	["cosmetic.KillEffectSupernova"] = { en = "Seal Finisher", fr = "Finisher Sceau" },
	["cosmetic.VipAura"] = { en = "Patron's Aura", fr = "Aura du Mécène" },
	["cosmetic.SkinRuptureCrystal"] = { en = "Sandstone Rupture Skin", fr = "Skin Rupture de Grès" },
	-- The words a Title cosmetic writes above its wearer (CosmeticController).
	["cosmetic.title.BlankHeadband"] = { en = "Apprentice", fr = "Apprenti" },
	["cosmetic.title.FrisketMask"] = { en = "Frisket", fr = "Frisquette" },
	["cosmetic.title.ScriptoriumRobe"] = { en = "Scriptorium Hand", fr = "Main du Scriptorium" },
	["cosmetic.title.CodexCloak"] = { en = "Keeper of the Codex", fr = "Gardien du Codex" },
	["cosmetic.title.TitleShadow"] = { en = "Silent Hand", fr = "Main Silencieuse" },
	["cosmetic.title.TitleCodex"] = { en = "Bound in Vellum", fr = "Relié de Vélin" },
	["cosmetic.title.TitleScript"] = { en = "Script", fr = "Écriture" },
	["cosmetic.title.TitleIllumination"] = { en = "Illumination", fr = "Enluminure" },
	["cosmetic.title.TitleCodexSeason"] = { en = "Codex of the Volume", fr = "Codex du volume" },
	["cosmetic.title.TitleRookie"] = { en = "Rookie", fr = "Recrue" },
	["cosmetic.title.TitleWanderer"] = { en = "Wanderer", fr = "Vagabond" },

	-- Passes, products, shop
	["pass.vip"] = { en = "VIP", fr = "VIP" },
	["pass.vip.desc"] = {
		en = "Double XP, +50% Folios, chat tag and an exclusive aura.",
		fr = "XP ×2, +50 % de Folios, tag dans le chat et une aura exclusive.",
	},
	-- Drawn before a VIP's name in the chat, in the reader's language (ChatConfig.VipTag).
	["chat.vipTag"] = { en = "[VIP]", fr = "[VIP]" },
	["pass.loadoutSlots"] = { en = "Loadout Slots", fr = "Slots d'équipement" },
	["pass.loadoutSlots.desc"] = {
		en = "+4 loadout slots (10 in total).",
		fr = "+4 slots d'équipement (10 au total).",
	},
	["pass.orpiment"] = { en = "Orpiment Pigment", fr = "Pigment Orpiment" },
	["pass.orpiment.desc"] = {
		en = "Unlock Orpiment right away (or reach level {level} for free).",
		fr = "Débloque l'Orpiment tout de suite (ou atteins le niveau {level} gratuitement).",
	},
	["pass.skinPack"] = { en = "Skin Pack", fr = "Pack de skins" },
	["pass.skinPack.desc"] = {
		en = "Four glyph skins, one per base pigment.",
		fr = "Quatre skins de glyphe, un par pigment de base.",
	},
	["product.folioSmall"] = { en = "1,000 Folios", fr = "1 000 Folios" },
	["product.folioMedium"] = { en = "3,500 Folios", fr = "3 500 Folios" },
	["product.folioLarge"] = { en = "8,000 Folios", fr = "8 000 Folios" },
	["product.folios.desc"] = {
		en = "Folios to spend in the cosmetic shop.",
		fr = "Des Folios à dépenser dans la boutique de cosmétiques.",
	},
	["product.premiumPass"] = { en = "Premium Battle Pass", fr = "Battle Pass Premium" },
	["product.premiumPass.desc"] = {
		en = "Unlock the premium track of the current volume.",
		fr = "Débloque la piste premium du volume en cours.",
	},
	["product.tierSkip5"] = { en = "+5 Tiers", fr = "+5 paliers" },
	["product.tierSkip5.desc"] = {
		en = "Five battle pass tiers; any past the last one are paid in Folios.",
		fr = "Cinq paliers du battle pass ; ceux au-delà du dernier sont payés en Folios.",
	},
	["product.xpBoost1h"] = { en = "XP Boost (1 h)", fr = "Boost d'XP (1 h)" },
	["product.xpBoost1h.desc"] = { en = "Double XP for one hour.", fr = "XP doublée pendant une heure." },
	["product.cosmetic"] = { en = "Cosmetic", fr = "Cosmétique" },
	["product.cosmetic.desc"] = {
		en = "Buy the selected cosmetic with Robux.",
		fr = "Achète le cosmétique sélectionné avec des Robux.",
	},
	["shop.title"] = { en = "Shop", fr = "Boutique" },
	["shop.buyFolios"] = { en = "{price} Folios", fr = "{price} Folios" },
	["shop.owned"] = { en = "Owned", fr = "Possédé" },
	["shop.equip"] = { en = "Equip", fr = "Équiper" },
	["shop.equipped"] = { en = "Equipped", fr = "Équipé" },
	["shop.notEnoughFolios"] = { en = "Not enough Folios.", fr = "Pas assez de Folios." },
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
	["queue.waiting"] = { en = "{queued} / {needed} players", fr = "{queued} / {needed} joueurs" },
	["queue.joined"] = { en = "Queued for {mode}.", fr = "En file pour {mode}." },
	["queue.left"] = { en = "You left the queue.", fr = "Tu as quitté la file." },
	["queue.timedOut"] = { en = "No opponent found. Try again!", fr = "Aucun adversaire trouvé. Réessaie !" },
	["queue.alreadyQueued"] = { en = "You are already in a queue.", fr = "Tu es déjà dans une file." },
	["queue.inMatch"] = { en = "You are already in a match.", fr = "Tu es déjà en match." },
	["match.countdown"] = { en = "{seconds}", fr = "{seconds}" },
	-- The match's band (ScoreBand): the round, and the mode in the leaderboard's word for it ("1v1").
	["match.band"] = { en = "Round {round} · {mode}", fr = "Manche {round} · {mode}" },
	["match.timeLeft"] = { en = "{seconds}s", fr = "{seconds}s" },
	["match.roundWon"] = { en = "Round won!", fr = "Manche gagnée !" },
	["match.roundLost"] = { en = "Round lost", fr = "Manche perdue" },
	["match.victory"] = { en = "Victory!", fr = "Victoire !" },
	["match.defeat"] = { en = "Defeat", fr = "Défaite" },
	["match.draw"] = { en = "Draw", fr = "Égalité" },
	["match.ratingUp"] = { en = "{rank}  {rating} (+{delta})", fr = "{rank}  {rating} (+{delta})" },
	["match.ratingDown"] = { en = "{rank}  {rating} ({delta})", fr = "{rank}  {rating} ({delta})" },
	["match.rankUp"] = { en = "New rank: {rank}!", fr = "Nouveau rang : {rank} !" },
	["season.rewardGranted"] = {
		en = "Volume reward ({rank}): +{amount} Folios",
		fr = "Récompense du volume ({rank}) : +{amount} Folios",
	},
	["match.firstWin"] = { en = "First win of the day!", fr = "Première victoire du jour !" },
	["match.again"] = { en = "Play again", fr = "Rejouer" },
	["match.watching"] = { en = "Watching {name}", fr = "Tu regardes {name}" },
	["menu.inviteUnavailable"] = {
		en = "Invites are not available here.",
		fr = "Les invitations ne sont pas disponibles ici.",
	},
	["match.grade"] = { en = "Execution: {grade}", fr = "Exécution : {grade}" },
	["match.execution"] = {
		en = "{hits} / {casts} glyphs landed · {damage} damage",
		fr = "{hits} / {casts} glyphes placés · {damage} dégâts",
	},
	["match.level"] = { en = "Level {level} · {xp} / {needed} XP", fr = "Niveau {level} · {xp} / {needed} XP" },
	["match.levelMax"] = { en = "Level {level} · max", fr = "Niveau {level} · max" },
	["match.nextUnlock"] = { en = "Next: {name} at level {level}", fr = "Prochain : {name} au niveau {level}" },
	["grade.steady"] = { en = "a steady hand", fr = "une main sûre" },
	["grade.clean"] = { en = "a clean hand", fr = "une main nette" },
	["grade.unsure"] = { en = "an unsure hand", fr = "une main incertaine" },
	["grade.shaky"] = { en = "a shaking hand", fr = "une main tremblante" },
	["match.bestChain"] = { en = "Best chain: ×{count}", fr = "Meilleure chaîne : ×{count}" },
	["match.opponentLeft"] = { en = "Your opponent left.", fr = "Ton adversaire est parti." },
	["match.returning"] = { en = "Returning to the hub…", fr = "Retour au hub…" },
	["leaderboard.title"] = { en = "Leaderboard", fr = "Classement" },
	["leaderboard.board.Global"] = { en = "Global", fr = "Global" },
	["leaderboard.board.Duel1v1"] = { en = "1v1", fr = "1v1" },
	["leaderboard.board.Team3v3"] = { en = "3v3", fr = "3v3" },
	["leaderboard.empty"] = { en = "No ranked player yet.", fr = "Aucun joueur classé pour l'instant." },
	-- The hub, worded by each client (HubSignsController, D-128).
	["hub.board.title"] = { en = "Leaderboard · {board}", fr = "Classement · {board}" },
	["hub.queue.name"] = { en = "Ranked matches", fr = "Matchs classés" },
	["hub.prompt.open"] = { en = "Open", fr = "Ouvrir" },
	["leaderboard.row"] = { en = "#{rank}  {name}", fr = "#{rank}  {name}" },
	["leaderboard.rating"] = { en = "{rating}", fr = "{rating}" },
	["leaderboard.you"] = { en = "You: #{rank} ({rating})", fr = "Toi : #{rank} ({rating})" },
	["leaderboard.youUnlisted"] = { en = "You: outside the top {count}", fr = "Toi : hors du top {count}" },
	["leaderboard.unranked"] = { en = "Unranked — play a ranked match", fr = "Non classé — joue un match classé" },

	-- The portals (D-130): the name of each seal and what it asks of whoever stands in it (PortalConfig.Zones).
	["portal.battleground.name"] = { en = "Battleground", fr = "Champ de bataille" },
	["portal.worldBoss.name"] = { en = "Face the Erasure", fr = "Affronter l'Effacement" },
	["portal.return.name"] = { en = "Back to the hub", fr = "Retour au hub" },
	["portal.hint.enter"] = { en = "Stay in the circle to enter", fr = "Reste dans le cercle pour entrer" },
	["portal.hint.return"] = { en = "Stay in the circle to go back", fr = "Reste dans le cercle pour revenir" },
	["portal.unavailable"] = { en = "This way is closed for now.", fr = "Ce passage est fermé pour l'instant." },
	-- The band that fills while its player stands in a circle (TravelController): {place} is the seal's name.
	["portal.entering"] = { en = "Stay in the circle: {place}", fr = "Reste dans le cercle : {place}" },
	-- A circle stood in just after a trip: step out, then back in, once this has passed (PortalService).
	["portal.cooldown"] = {
		en = "Wait a moment before travelling again.",
		fr = "Attends un instant avant de repartir.",
	},

	-- The Battleground and its Forgers (D-131).
	["battleground.entered"] = { en = "The Forgers have seen you.", fr = "Les Faussaires t'ont vu." },
	-- The member's band (TravelController): Forgers on the page now, and how many they helped defeat.
	["battleground.status"] = {
		en = "{standing} Forgers standing · {defeated} defeated",
		fr = "{standing} Faussaires debout · {defeated} vaincus",
	},
	["battleground.full"] = {
		en = "The battleground is full. Try again in a moment.",
		fr = "Le champ de bataille est plein. Réessaie dans un instant.",
	},
	["battleground.folioCap"] = {
		en = "Forgers pay no more Folios today. XP still counts.",
		fr = "Les Faussaires ne rapportent plus de Folios aujourd'hui. L'XP compte toujours.",
	},
	["battleground.campHit"] = {
		en = "Hits from the camp don't count. Step out to fight.",
		fr = "Les coups portés depuis le camp ne comptent pas. Sors pour te battre.",
	},

	-- L'Effacement (the World Boss, docs/GAME_DESIGN.md §7)
	["boss.name"] = { en = "The Erasure", fr = "L'Effacement" },
	["boss.announced"] = {
		en = "The Erasure comes for the page in {seconds}s!",
		fr = "L'Effacement vient pour la page dans {seconds}s !",
	},
	["boss.started"] = { en = "The Erasure is here.", fr = "L'Effacement est là." },
	["boss.health"] = { en = "{health} / {max}", fr = "{health} / {max}" },
	["boss.phase"] = { en = "Phase {phase}", fr = "Phase {phase}" },
	["boss.timeLeft"] = { en = "{seconds}s left", fr = "{seconds}s restantes" },
	["boss.share"] = { en = "Your damage: {percent}%", fr = "Tes dégâts : {percent} %" },
	["boss.defeated"] = {
		en = "The Erasure is undone. The page keeps.",
		fr = "L'Effacement est défait. La page reste.",
	},
	["boss.expired"] = { en = "The Erasure has left the page…", fr = "L'Effacement a quitté la page…" },
	["boss.reward"] = {
		en = "Erasure reward: +{xp} XP, +{folios} Folios",
		fr = "Récompense de l'Effacement : +{xp} XP, +{folios} Folios",
	},
	["boss.killBonus"] = { en = "Top damage bonus!", fr = "Bonus de meilleur dégât !" },
	["boss.attack.slam"] = { en = "Slam", fr = "Écrasement" },
	["boss.attack.sweep"] = { en = "Sweep", fr = "Balayage" },
	["boss.attack.eruption"] = { en = "Eruption", fr = "Éruption" },
	["boss.attack.fury"] = { en = "Fury", fr = "Furie" },
	-- Practice against the Erasure and joining a fight through the hub's gate (D-132).
	["boss.practice.title"] = { en = "The Erasure · practice", fr = "L'Effacement · entraînement" },
	["boss.portal.announced"] = {
		en = "The Erasure arrives in {seconds}s: you will be drawn in.",
		fr = "L'Effacement arrive dans {seconds} s : tu y seras appelé.",
	},
	["boss.portal.eventSoon"] = {
		en = "The Erasure itself comes in {seconds}s: no practice now.",
		fr = "Le vrai Effacement arrive dans {seconds} s : pas d'entraînement maintenant.",
	},
	["boss.portal.closing"] = {
		en = "This fight is ending. Try again in a moment.",
		fr = "Ce combat se termine. Réessaie dans un instant.",
	},
	["boss.portal.cooldown"] = { en = "Practice again in {seconds}s.", fr = "Nouvel entraînement dans {seconds} s." },
	["boss.portal.busy"] = {
		en = "No arena is free. Try again in a moment.",
		fr = "Aucune arène libre. Réessaie dans un instant.",
	},
	["boss.portal.noReentry"] = {
		en = "You have used your returns for this fight.",
		fr = "Tu as épuisé tes retours pour ce combat.",
	},
	["boss.practice.noReward"] = {
		en = "Practice rewards come back in {minutes} min.",
		fr = "Les récompenses d'entraînement reviennent dans {minutes} min.",
	},
	["boss.practice.dailyDone"] = {
		en = "Practice rewards are done for today.",
		fr = "Les récompenses d'entraînement sont épuisées pour aujourd'hui.",
	},

	-- Loadout
	["loadout.title"] = { en = "Loadout", fr = "Équipement" },
	["loadout.slots"] = { en = "{used} / {total} slots", fr = "{used} / {total} slots" },
	["loadout.equip"] = { en = "Equip", fr = "Équiper" },
	["loadout.unequip"] = { en = "Unequip", fr = "Retirer" },
	["loadout.equipped"] = { en = "Equipped", fr = "Équipé" },
	["loadout.locked"] = { en = "Unlocks at level {level}", fr = "Se débloque au niveau {level}" },
	["loadout.lockedPigment"] = { en = "Requires the {pigment} pigment", fr = "Nécessite le pigment {pigment}" },
	["loadout.saved"] = { en = "Loadout saved!", fr = "Équipement sauvegardé !" },
	["loadout.invalid"] = { en = "Invalid loadout.", fr = "Équipement invalide." },
	["loadout.caughtUp"] = {
		en = "New glyphs unlocked: {count}. Add them to your loadout.",
		fr = "Nouveaux glyphes débloqués : {count}. Ajoute-les à ton équipement.",
	},

	-- Cosmetics
	["cosmetics.none"] = { en = "None", fr = "Aucun" },
	["cosmetics.equipped"] = { en = "Equipped: {name}", fr = "Équipé : {name}" },
	["cosmetics.notOwned"] = { en = "You do not own this cosmetic.", fr = "Tu ne possèdes pas ce cosmétique." },

	-- Purchases
	["purchase.prompt"] = { en = "Opening the Roblox purchase…", fr = "Ouverture de l'achat Roblox…" },
	["purchase.granted"] = { en = "Purchase complete: {name}", fr = "Achat terminé : {name}" },
	["purchase.grantedFoliosInstead"] = {
		en = "You own every item of that rarity: +{amount} Folios instead",
		fr = "Tu possèdes tous les articles de cette rareté : +{amount} Folios à la place",
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
	["purchase.premiumOwnedFolios"] = {
		en = "You already have the Premium Battle Pass: +{amount} Folios instead",
		fr = "Tu as déjà le Battle Pass Premium : +{amount} Folios à la place",
	},
	["purchase.tiersPastLast"] = {
		en = "Past the last tier: +{amount} Folios instead",
		fr = "Au-delà du dernier palier : +{amount} Folios à la place",
	},
	-- Seen only in Studio, where a test purchase grants nothing (StudioConfig.PersistTestPurchases).
	["purchase.sandboxed"] = {
		en = "Studio test purchase of {name}: nothing was granted or saved.",
		fr = "Achat de test dans Studio ({name}) : rien n'a été accordé ni enregistré.",
	},
	-- A DataStore outage (DataService, ProfileStore's critical state): once to each player, and when it ends.
	["purchase.savesDelayed"] = {
		en = "Robux purchases are paused while saving is delayed.",
		fr = "Les achats en Robux sont suspendus tant que la sauvegarde est retardée.",
	},
	["save.delayed"] = {
		en = "Saving is delayed. Your progress is kept here, and Robux purchases are paused until it's back.",
		fr = "La sauvegarde est retardée. Ta progression est gardée ici, et les achats en Robux attendent son retour.",
	},
	["save.restored"] = {
		en = "Saving is back. Robux purchases are open again.",
		fr = "La sauvegarde est revenue. Les achats en Robux sont rouverts.",
	},

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

	-- D-147 · slice F (components and shared)
	-- The words on a keycap (Keycap.label): every rebindable key longer than a letter, in the player's language.
	["key.LeftShift"] = { en = "Shift", fr = "Maj" },
	["key.RightShift"] = { en = "Right Shift", fr = "Maj droite" },
	["key.LeftControl"] = { en = "Ctrl", fr = "Ctrl" },
	["key.RightControl"] = { en = "Right Ctrl", fr = "Ctrl droite" },
	["key.LeftAlt"] = { en = "Alt", fr = "Alt" },
	["key.RightAlt"] = { en = "Alt Gr", fr = "Alt Gr" },
	["key.MouseButton1"] = { en = "Left click", fr = "Clic gauche" },
	["key.MouseButton2"] = { en = "Right click", fr = "Clic droit" },
	["key.MouseButton3"] = { en = "Middle click", fr = "Clic molette" },
	["key.ButtonB"] = { en = "B", fr = "B" },
	["key.ButtonX"] = { en = "X", fr = "X" },
	["key.ButtonY"] = { en = "Y", fr = "Y" },
	["key.ButtonL1"] = { en = "LB", fr = "LB" },
	["key.ButtonR1"] = { en = "RB", fr = "RB" },
	["key.ButtonL2"] = { en = "LT", fr = "LT" },
	["key.ButtonR2"] = { en = "RT", fr = "RT" },
	["key.ButtonL3"] = { en = "L3", fr = "L3" },
	["key.ButtonR3"] = { en = "R3", fr = "R3" },
	["key.ButtonSelect"] = { en = "Select", fr = "Sélection" },
	-- The way back on a screen opened from another one (ChapterBand).
	["nav.back"] = { en = "Back", fr = "Retour" },

	-- D-147 · slice A (menus: menu, play, shop, battle pass, daily)
	-- The play cards (PlayScreen): the tag on a ranked mode, its rule, and what the card says when the server
	-- finds nobody. A mode of one round has its own rule: "first to 1 rounds" reads wrong in both languages.
	["queue.ranked"] = { en = "Ranked", fr = "Classé" },
	["queue.rule"] = { en = "First to {rounds} rounds wins", fr = "Le premier à {rounds} manches gagne" },
	["queue.rule.one"] = { en = "A single round decides", fr = "Une seule manche décide" },
	["queue.timedOut.title"] = { en = "Nobody in the queue right now", fr = "Personne en file pour l'instant" },
	["queue.timedOut.hint"] = {
		en = "Try the Battleground or face the Erasure: their circles are in the hub.",
		fr = "Essaie le Champ de bataille ou affronte l'Effacement : leurs cercles sont dans le hub.",
	},
	-- Slice F's shared words, entered with their first reader (D-150).
	["common.retry"] = { en = "Retry", fr = "Réessayer" },
	["time.minutesSeconds"] = { en = "{minutes}:{seconds}", fr = "{minutes}:{seconds}" },
	["time.hoursMinutes"] = { en = "{hours}h {minutes}m", fr = "{hours} h {minutes}" },
	["common.cancel"] = { en = "Cancel", fr = "Annuler" },
	["common.pendingTimeout"] = {
		en = "No answer from the server. Try again.",
		fr = "Pas de réponse du serveur. Réessaie.",
	},
	-- The shop (ShopScreen): the countdown to the next rotation, the Robux price, and the sheet that asks
	-- before a Folios purchase.
	["shop.nextRotation"] = { en = "New items in {time}", fr = "Nouveautés dans {time}" },
	["shop.robuxPrice"] = { en = "R$ {price}", fr = "R$ {price}" },
	["shop.confirm.title"] = { en = "Buy {name}?", fr = "Acheter {name} ?" },
	["shop.confirm.balance"] = { en = "{before} → {after} Folios", fr = "{before} → {after} Folios" },
	["shop.buy"] = { en = "Buy", fr = "Acheter" },
	["shop.acquired"] = { en = "Acquired!", fr = "Acquis !" },
	["shop.getFolios"] = { en = "Get Folios", fr = "Obtenir des Folios" },
	-- The shop's tabs, and the locker of what the player owns, by slot.
	["shop.tab.today"] = { en = "Today", fr = "Du jour" },
	["shop.tab.folios"] = { en = "Folios", fr = "Folios" },
	["shop.tab.passes"] = { en = "Passes & packs", fr = "Pass et packs" },
	["shop.tab.locker"] = { en = "Locker", fr = "Casier" },
	["shop.unequip"] = { en = "Unequip", fr = "Retirer" },
	["shop.locker.empty"] = {
		en = "Nothing here yet. Earn cosmetics in the Battle Pass or buy them in today's selection.",
		fr = "Rien pour l'instant. Gagne des cosmétiques avec le Battle Pass ou achète-les dans la sélection du jour.",
	},
	["cosmetics.slot.Aura"] = { en = "Auras", fr = "Auras" },
	["cosmetics.slot.Trail"] = { en = "Trails", fr = "Traînées" },
	["cosmetics.slot.KillEffect"] = { en = "Takedown effects", fr = "Effets d'élimination" },
	["cosmetics.slot.Title"] = { en = "Titles", fr = "Titres" },
	["cosmetics.slot.Skin"] = { en = "Glyph skins", fr = "Apparences de glyphe" },
	-- The battle pass (BattlepassScreen): its header's buttons, the showcase of the next reward, and a cell's
	-- amounts. A cell is too narrow for "XP boost (30 min)": it shows the clock and the minutes.
	["battlepass.getPremium"] = { en = "Get Premium", fr = "Obtenir le Premium" },
	["battlepass.claimAll"] = { en = "Claim all ({count})", fr = "Tout réclamer ({count})" },
	["battlepass.nextReward"] = { en = "Next reward", fr = "Prochaine récompense" },
	["battlepass.tierShort"] = { en = "Tier {tier}", fr = "Palier {tier}" },
	["battlepass.reward.minutes"] = { en = "{minutes} min", fr = "{minutes} min" },
	["reward.folios"] = { en = "+{amount}", fr = "+{amount}" },
	["reward.xp"] = { en = "+{xp} XP", fr = "+{xp} XP" },
	-- The player's balance where a screen shows it (FoliosPill, the hub's MetaCluster): the amount alone, grouped
	-- by thousands as every amount of Folios is.
	["folios.balance"] = { en = "{folios}", fr = "{folios}" },
	-- The daily reward (DailyScreen): each day's card, the claim, tomorrow's reward, and the streak worth keeping.
	["daily.day"] = { en = "Day {day}", fr = "Jour {day}" },
	["daily.claim"] = { en = "Claim", fr = "Réclamer" },
	["daily.tomorrow"] = { en = "Tomorrow: {reward}", fr = "Demain : {reward}" },
	["daily.atRisk"] = {
		en = "Claim today to keep your {streak}-day streak!",
		fr = "Réclame aujourd'hui pour garder ta série de {streak} jours !",
	},

	-- D-147 · slice B (menus: loadout, quests, leaderboard, result, settings)
	-- A time left, on a countdown (QuestBoard.countdown): days and hours past a day (under a day it reads
	-- time.hoursMinutes, entered above by slice A).
	["time.daysHours"] = { en = "{days}d {hours}h", fr = "{days} j {hours} h" },
	-- The quests board: when each section is drawn again.
	["quest.resetsIn"] = { en = "Resets in {time}", fr = "Réinitialisation dans {time}" },
	-- A number of seconds, beside a clock (a glyph's cooldown on its card).
	["common.seconds"] = { en = "{seconds}s", fr = "{seconds} s" },
	-- The loadout: a full loadout's Equip, the offer of the pass's slots, and the strip that undoes a change.
	["loadout.fullShort"] = { en = "Slots full", fr = "Emplacements pleins" },
	["loadout.moreSlots"] = { en = "+{count} slots", fr = "+{count} slots" },
	["loadout.equippedToast"] = { en = "{name} equipped", fr = "{name} équipé" },
	["loadout.unequippedToast"] = { en = "{name} removed", fr = "{name} retiré" },
	["common.undo"] = { en = "Undo", fr = "Annuler" },
	-- The leaderboard: the way to the player's own row, and a board that could not be fetched.
	["leaderboard.findMe"] = { en = "My place", fr = "Ma place" },
	["common.loadFailed"] = { en = "Couldn't load.", fr = "Impossible de charger." },
	-- Settings: the accessibility tab, the words of a switch and of a percentage, the way a pad rebinds, and
	-- the question before a reset.
	["settings.tab.accessibility"] = { en = "Accessibility", fr = "Accessibilité" },
	["common.on"] = { en = "On", fr = "Oui" },
	["common.off"] = { en = "Off", fr = "Non" },
	["common.percent"] = { en = "{value}%", fr = "{value} %" },
	["settings.hint.gamepad"] = {
		en = "Select a binding, then press the new button. A cancels.",
		fr = "Sélectionne une touche, puis appuie sur le nouveau bouton. A annule.",
	},
	["settings.pressButton"] = {
		en = "Press a button for {action}… (A to cancel)",
		fr = "Appuie sur un bouton pour {action}… (A pour annuler)",
	},
	-- What a key being rebound shows while it waits for the new one.
	["settings.capturing"] = { en = "…", fr = "…" },
	["settings.resetConfirm"] = {
		en = "Reset every binding to its default?",
		fr = "Remettre toutes les touches par défaut ?",
	},
	-- Roblox's own accessibility settings, shown as they are (UiPrefs) and changed in the Roblox menu.
	["settings.reducedMotion"] = { en = "Reduced motion", fr = "Mouvements réduits" },
	["settings.textSize"] = { en = "Text size", fr = "Taille du texte" },
	["settings.textSize.Medium"] = { en = "Standard", fr = "Standard" },
	["settings.textSize.Large"] = { en = "Large", fr = "Grand" },
	["settings.textSize.Larger"] = { en = "Larger", fr = "Plus grand" },
	["settings.textSize.Largest"] = { en = "Largest", fr = "Très grand" },
	["settings.transparency"] = { en = "Background transparency", fr = "Transparence des fonds" },
	["settings.systemHint"] = {
		en = "Set in the Roblox menu, under Settings.",
		fr = "Se règle dans le menu Roblox, dans Paramètres.",
	},
	-- The Result: the details folded on a phone (its chips count up with reward.xp and reward.folios, above).
	["result.details"] = { en = "Details", fr = "Détails" },

	-- D-147 · slice C (HUD, toasts, world)
	-- The centre splashes of a match (Banner).
	["hud.splash.matchFound"] = { en = "Match found!", fr = "Match trouvé !" },
	["hud.splash.fight"] = { en = "Fight!", fr = "Au combat !" },
	["hud.splash.defeated"] = { en = "Defeated!", fr = "Vaincu !" },
	-- The lock's mark (LockMarker): a press that finds nothing, the pill over the target with its name and the
	-- health it has left, and the pill's name for what is not a player.
	["hud.lock.none"] = { en = "No target", fr = "Aucune cible" },
	["hud.lock.target"] = { en = "{name} · {health}", fr = "{name} · {health}" },
	-- A cooling glyph's seconds on its hotbar slot, in tenths under ten (CooldownText): the language's own mark.
	["hud.hotbar.seconds"] = { en = "{whole}.{tenth}", fr = "{whole},{tenth}" },
	["hud.lock.dummy"] = { en = "Training dummy", fr = "Mannequin" },
	["hud.lock.forger"] = { en = "Forger", fr = "Faussaire" },
	-- A new player's first steps (MetaCluster), until all three are done.
	["hud.checklist.title"] = { en = "First steps", fr = "Premiers pas" },
	["hud.checklist.cast"] = { en = "Cast a glyph", fr = "Trace un glyphe" },
	["hud.checklist.match"] = { en = "Play a match", fr = "Joue un match" },
	["hud.checklist.daily"] = { en = "Claim your daily reward", fr = "Réclame ta récompense du jour" },
} :: { [string]: Entry }

-- The placeholders that carry an amount of Folios or XP: an integer given to one of them is grouped by thousands
-- in the player's language (Strings.number). Ratings, ranks, levels, counts, seconds and health are not amounts
-- and are never grouped. {needed} is also queue.waiting's count of players, which never reaches a thousand. A
-- price ({price}) is not grouped yet: a Today card's row holds its two prices with no room for the separator
-- (tests/ShopEquip.spec.luau measures it).
Strings.Quantities = {
	xp = true,
	needed = true,
	folios = true,
	amount = true,
	before = true,
	after = true,
} :: { [string]: boolean }

-- The mark between two groups of three digits: a narrow no-break space in French, a comma in English.
local GROUP_SEPARATORS: { [string]: string } = { en = ",", fr = "\u{202F}" }
local GROUP = 3

-- `n` with its digits grouped by three for `locale` ("3 120" in French, "3,120" in English), the sign kept. A
-- number under a thousand, or one that is not a whole number, reads exactly as tostring gives it.
function Strings.number(n: number, locale: string?): string
	if math.abs(n) < 1000 or n ~= math.floor(n) or math.abs(n) == math.huge then
		return tostring(n)
	end
	local separator = GROUP_SEPARATORS[locale or Strings.DefaultLocale] or GROUP_SEPARATORS[Strings.DefaultLocale]
	local digits = string.format("%.0f", math.abs(n))
	local head = #digits % GROUP
	local groups: { string } = {}
	if head > 0 then
		table.insert(groups, string.sub(digits, 1, head))
	end
	for start = head + 1, #digits, GROUP do
		table.insert(groups, string.sub(digits, start, start + GROUP - 1))
	end
	local grouped = table.concat(groups, separator)
	return if n < 0 then "-" .. grouped else grouped
end

-- `params` with every number given to a quantity grouped for `locale`; the table itself when it holds none.
local function withAmounts(params: { [string]: any }?, locale: string): { [string]: any }?
	if params == nil then
		return nil
	end
	local amounts: { [string]: any }? = nil
	for name, value in pairs(params) do
		if Strings.Quantities[name] and type(value) == "number" then
			local copy = amounts or table.clone(params)
			copy[name] = Strings.number(value, locale)
			amounts = copy
		end
	end
	return amounts or params
end

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

-- Translates `key` for `locale` (falls back to English, then to "[key]" so missing entries are visible). An
-- amount of Folios or XP is grouped by thousands the way the locale writes it (Strings.Quantities).
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
	return Strings.format(template, withAmounts(params, chosen))
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
