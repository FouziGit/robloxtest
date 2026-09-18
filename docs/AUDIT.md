# Audit V1 — Vellum

> Note de relecture : cet audit date de la V1. Les noms de sorts, d'éléments, de modules et de fichiers qu'il cite ont été réécrits par le renommage de lexique (`docs/ART_BIBLE.md`) pour rester cherchables ; les chemins de fichiers V1 (`JutsuEffects.lua`) n'existent plus sous ce nom.

Date : 2026-09-17 · Périmètre : 19 fichiers Luau (≈ 3 500 lignes hors `ProfileService.lua` vendoré, 2 413 lignes), `default.project.json`, `README_INSTALLATION.md`, `StudioTools/`.
Méthode : 4 lecteurs indépendants (bugs, exploits, dette, gameplay/plateforme) ont lu chaque fichier ; tous les constats *haut* ont été contre-vérifiés par un second agent chargé de les réfuter (16/16 confirmés). Les constats *moyen/bas* sont rapportés tels quels.

Bilan : **68 constats** — 16 hauts, 34 moyens, 18 bas — et 7 points forts à préserver. Aucun constat *critique* (pas de perte de données ni de crash serveur reproductible) : la V1 est une base saine mais un prototype solo, pas un battleground.

---

## 1. Ce qui est bien construit (à préserver)

| # | Pigment | Où | Pourquoi le garder |
|---|---|---|---|
| K1 | Pipeline de cast serveur-autoritaire | `GlyphService.lua:82-164` | Validation stricte du payload (type / longueur / whitelist de pigments), anti-spam qui ne consomme pas la fenêtre sur un refus, cooldown armé seulement après succès de l'effet. Référence pour `CombatService`. |
| K2 | Résolveur de combo par préfixe | `GlyphConfig.lua:126-143`, `GlyphController.client.lua:196-225` | `ByCombo` / `PrefixSet` construits à la charge avec détection de doublons ; décision client « combo & non-préfixe → tir immédiat / préfixe → attente / mort → reset », timers protégés par compteur de génération. Devient le module pur `ComboResolver`. |
| K3 | Injection de dépendances, point d'entrée unique | `MainServer.server.lua:60-71` | `Init(deps)` sans `require` circulaire, noms de remotes centralisés dans la config. Modèle du futur `Bootstrap`. |
| K4 | Source unique d'XP et claims validés serveur | `BattlepassService.lua:108-161, 170-230` | `AddXP(player, amount, reason)` est le seul chemin de progression ; `HandleClaimReward` vérifie palier / doublon / type côté serveur. |
| K5 | Chargement de profil robuste | `DataManager.lua:120-159` | Session lock, `AddUserId` (RGPD), `Reconcile`, kick si le verrou est repris ailleurs, snapshots copiés avant envoi. |
| K6 | Config data-driven | `GlyphConfig.lua:5-10`, `GameConfig.lua:93-115` | Ajouter un glyphe = une entrée + une fonction d'effet ; whitelist de touches unique. |
| K7 | UI 100 % générée en code | tous les `*.client.lua` | Rien à reconstruire dans Studio ; base pour une couche composants/thème. |

---

## 2. Bugs (comportement incorrect à l'exécution)

| Sév. | Fichier:ligne | Constat | Conséquence |
|---|---|---|---|
| Haut | `GameConfig.lua:21` | Touche par défaut Cinabre = `A`, qui est le strafe gauche QWERTY ; la whitelist retire W/S/D/Z/Q mais garde A | Sur QWERTY (majorité des joueurs) chaque pas à gauche empile un mantra ; deux pas rapides lancent une Marque ; toast d'erreur 1,5 s plus tard. Le jeu est injouable avant rebind. |
| Moyen | `GlyphEffects.lua:180` | La Marque ignore le Marge (`Touched` retourne sur tout `EFFECT_TAG`, mur `CanQuery=false`) | Aucun glyphe n'est bloqué par le mur ; il ne bloque que la marche. |
| Moyen | `GlyphEffects.lua:319, 506-510` | Knockback écrit `AssemblyLinearVelocity` côté serveur | No-op sur les mannequins (ancrés) ; écrasé en une frame sur les joueurs (network ownership client). Les descriptions « projette / repousse » sont fausses. |
| Moyen | `MovementController.client.lua:179` | `JumpRequest` se répète tant que la touche est tenue ; debounce temporel de 0,18 s | Maintenir Espace consomme automatiquement le double saut ; impossible de le temporiser. |
| Moyen | `OptionsMenu.client.lua:241` | `stopCapture()` efface l'attribut `RebindCapture` de façon synchrone dans le même dispatch `InputBegan` | Ordre des connexions indéfini → la touche capturée peut aussi entrer comme mantra dans `GlyphController`. |
| Moyen | `OptionsMenu.client.lua:274` | Tout `DataChanged` (donc chaque gain d'XP) écrase `pendingKeybinds` | Un tick d'effet ou une mort de mannequin pendant l'édition annule silencieusement les touches en cours de modification. |
| Moyen | `MainServer.server.lua:182` | `DeathHooked` est un attribut, copié par `Clone()` | Tout ennemi respawné par clonage n'est jamais hooké → 0 XP de kill ; `LastAttackerUserId` cloné crédite le mauvais joueur. |
| Bas | `MainServer.server.lua:197` | `LastAttackerUserId` jamais effacé | Une mort ultérieure sans rapport crédite le dernier lanceur. |
| Bas | `MainServer.server.lua:134` | `profileWaiters[player]` recréé après nettoyage si un invoke est en vol | Fuite d'une entrée par joueur parti pendant un chargement. |
| Bas | `GlyphEffects.lua:338` | Bavure : `Ball` de taille non uniforme → rendu 8 studs, rayon de dégâts 9 (18 studs) | Zone de dégâts deux fois plus large que le visuel. |
| Bas | `BattlepassMenu.client.lua:196` | Pas de cas niveau max | Affiche « Niveau 200 — 0 / 7967 XP ». |
| Bas | `OptionsMenu.client.lua:249`, `GameConfig.lua:96-100` | `O` = zoom caméra Roblox, `I` autorisée (zoom in), `One..Four` = raccourcis Backpack | Ouvrir les options dézoome ; un mantra sur 1-4 équipe/déséquipe un outil. |
| Bas | `OptionsMenu.client.lua:210` | Statut « Sauvegarde en cours… » jamais résolu | Le joueur ne sait pas si la sauvegarde a réussi. |
| Bas | `README_INSTALLATION.md:11-23` | Table d'installation manuelle incomplète (6 fichiers manquants dont `ProfileService`, `SoundConfig`) | Installation manuelle → `DataManager` bloque sur `WaitForChild`. |

---

## 3. Exploits et sécurité (client malveillant)

| Sév. | Fichier:ligne | Constat | Impact |
|---|---|---|---|
| Haut | `MovementController.client.lua:109, 185-190, 221-226` | Vitesse, stamina, double saut et position sont 100 % client. Le ralentissement serveur (`BrumeSlow`) n'est respecté que parce que le client accepte de ne pas réécrire `WalkSpeed` | Speed/teleport libre ; immunité à tout debuff en supprimant un `if` ; origines de glyphes (`rootPart.CFrame`) déplaçables n'importe où. |
| Moyen | `GlyphService.lua:161-163` | XP accordée à chaque cast accepté, sans toucher personne ; aucune ressource (encre) | Macro AFK dans le vide : ≈ 22,9 XP/s → 50 paliers (28 420 XP, 14 600 Ryo + 10 cosmétiques) en ≈ 21 min. |
| Moyen | `GlyphEffects.lua:47, 312-321, 362-371, 404` | `PvPEnabled` ne gate que les dégâts : slow, knockback, projection et collision du mur touchent tout le monde ; AoE centrées sur le lanceur au spawn (rayon 18) ; pas de fenêtre d'invulnérabilité au spawn | Spawn-kill (Rupture 35 × 3 casts), murs collidables 80 % du temps à 10 s de cooldown, griefing par ralentissement. |
| Moyen | `GlyphEffects.lua:176-184` | Explosion de la Marque sur `Touched` | Un autre client peut simuler le contact (`firetouchinterest`) et faire exploser tout projectile à sa sortie. |
| Bas | `GlyphService.lua:84-96, 179-205`, `BattlepassService.lua:177-180` | Refus silencieux sans compteur ni kick ; chemins d'échec de `CastGlyph` non throttlés (chaque refus renvoie un `FireClient`) ; `GetProfileData` répond au rythme du client pendant 1 s de cache | Spam gratuit ; pas de détection d'abus. |

---

## 4. Dette technique et architecture (bloquant pour la V2)

| Sév. | Fichier:ligne | Constat | Coût pour la V2 |
|---|---|---|---|
| Haut | `GlyphController.client.lua:230-246` | Entrée clavier uniquement (`UserInputType.Keyboard`), zéro `ContextActionService`, `TouchEnabled`, `Gamepad`, `UIScale`, `UIAspectRatioConstraint` | **0 glyph lançable sur mobile ou manette**, UI fixe en pixels (panneau battlepass 480 px > viewport téléphone). |
| Haut | 12 fichiers, 80 sites (`GlyphConfig` 16, `BattlepassConfig` 14, `OptionsMenu` 13, `GlyphService` 8…) | Toutes les chaînes joueur sont du français en dur ; le serveur envoie de la prose ; `SoundController.client.lua:76` choisit les sons par `string.find` sur ce texte | Localisation impossible sans réécriture ; couplage son ↔ texte. |
| Haut | `GameConfig.lua:16` | `Pigments = {"Cinabre","Indigo","Terre d'Ombre","Vert-de-gris"}` sert de clé DataStore, de clé de combo, de clé son **et** de libellé | Renommer/traduire un pigment corrompt les profils ; ajouter Orpiment touche 6 fichiers. |
| Haut | `GlyphEffects.lua:34-55` | `dealDamage` est `local` au fichier d'effets ; gate PvP = booléen global ; aucun concept d'équipe / arène / statut | Melee, boss, DoT, chute : impossibles sans dupliquer le tunnel de dégâts. → `CombatService.ApplyDamage`. |
| Haut | `MainServer.server.lua:181-223` | `Humanoid.Died` hooké seulement sur les modèles taggés `Enemy` | **Un kill PvP ne donne ni XP, ni Ryo, ni compteur** : la boucle PvP n'existe pas. |
| Haut | `CLAUDE.md`, `docs/DECISIONS.md` | Décrivent la structure cible (`src/`, tests, gates) qui n'existe pas encore | Attendu : ce sont des documents prospectifs de Phase 0 ; la Phase 1 les matérialise. Noté ici pour honnêteté. |
| Moyen | `GlyphEffects.lua:141-510` | Toutes les constantes d'équilibrage sauf `Damage`/`Cooldown` sont des littéraux dans le code (rayons, vitesses, durées, ticks) | Aucun équilibrage sans toucher au code d'effet. |
| Moyen | `GlyphEffects.lua:84-100` | Le serveur crée, tween et simule tous les VFX (`SetNetworkOwner(nil)`, `Touched` serveur) | Coût réseau ∝ joueurs × casts ; pas de particules, pas de hit-stop, pas de qualité adaptative mobile. |
| Moyen | `GameConfig.lua:87` | `GlyphFeedback` = bus de texte libre pour 7 types d'événements | Bloque la localisation et le typage des événements ; le son dépend de la langue. |
| Moyen | `DataManager.lua:51-77` | `DataVersion` sans migration ; battlepass non saisonnier (`ClaimedRewards["5"]`) ; aucun schéma monétisation | Saison 2 → paliers déjà « réclamés » ; achats non idempotents impossibles. |
| Moyen | `ProfileService.lua:1` | 2 413 lignes vendorées sans SHA ni gestionnaire de paquets ; `DataManager.SaveProfile` est une surface morte | Mise à jour et audit impossibles ; remplacé par ProfileStore épinglé (D-4). |
| Moyen | `GlyphService.lua:28-54`, `BattlepassService.lua:26-41` | DI non typée, upvalues `nil`, absence de dépendance détectée au premier usage | Erreurs tardives ; → `Init(deps)` typé + assertions au boot. |
| Moyen | `GlyphService.lua:84`, `BattlepassService.lua:177` | Validation et debounce réimplémentés par handler | → module `Guard` + token bucket partagé. |
| Moyen | `MainServer.server.lua:145-151`, `GlyphEffects.lua:217` | Polling `while … task.wait(0.5)` par invocation ; une coroutine de tick par cast | → signal `ProfileLoaded`, ticks centralisés sur `Heartbeat`. |
| Moyen | `BattlepassService.lua:108-230` | Le service « Battlepass » possède niveau joueur, leaderstats et l'unique écriture de monnaie ; `GlyphService` possède les keybinds ; `MainServer` mixe XP ennemi et cache RPC | Frontières à redessiner : `ProgressionService`, `CurrencyService`, `SettingsService`. |
| Moyen | `MainServer.server.lua:120-127` | Trois LocalScripts invoquent chacun `GetProfileData` et gardent leur copie | → un `ClientData` unique + `DataChanged` diffé. |
| Moyen | `OptionsMenu.client.lua:48-88`, `BattlepassMenu.client.lua:35-75` | Panneaux, barres, boutons dupliqués (~30 lignes identiques ×2), palette en littéraux | → `ui/components` + `Theme`. |
| Moyen | `default.project.json` | Aucun test, lint, format, `--!strict`, CI ; seuls 3 services mappés (map, Lighting, spawn vivent dans le `.rbxl` ignoré) | → Phase 1 toolchain ; hub/arènes générés en code. |
| Moyen | `GlyphEffects.lua:350`, `MovementController.client.lua:40` | Contrats string (`BrumeSlow`, `RebindCapture`, touches `O`/`B`) dupliqués en littéraux dans 2-4 fichiers | Rename = régression silencieuse. |
| Bas | `GlyphConfig.lua:37` | `Description` jamais affichée | Config morte. |
| Bas | `BattlepassConfig.lua:82-91` | Texte UI dans la config ; « Ryo » en dur malgré `CurrencyName` | |
| Bas | `GlyphConfig.lua:30-100`, `BattlepassConfig.lua:33-78` | Identifiants français persistés (`BouleDeCinabre`, `ManteauHokage`) | Migration nécessaire vers des IDs anglais stables. |
| Bas | `StudioTools/organize_map.lua` | Outil non versionné, hors arbre Rojo, agissant sur une map ignorée par git | Déplacé sous `scripts/studio/`. |

---

## 5. Écarts produit et plateforme (vs cible V2)

| Sév. | Domaine | Constat chiffré |
|---|---|---|
| Haut | PvP | Aucun mode, arène, équipe, matchmaking, classement, cycle de match ; `PvPEnabled` global = FFA partout, spawn compris. |
| Haut | Combos | `PrefixSet` = {Cinabre, Indigo, Terre d'Ombre, Vert-de-gris, Cinabre-Cinabre, Indigo-Indigo, Terre d'Ombre-Terre d'Ombre} : 3 des 4 glyphes de base attendent 1,5 s (préfixes de combos à 3 touches) tandis que les combos « avancés » sont instantanés. Spammer une touche ne lance rien. Inversion totale du feeling voulu. |
| Haut | Monétisation | 0 occurrence de `MarketplaceService` ; Ryo n'a aucun puits ; les cosmétiques ne sont jamais rendus. |
| Haut | Mobile / manette | 0 chemin d'entrée tactile ou manette ; `ValidKeybindKeys` refuse tout `ButtonA/DPad*`. |
| Haut | Localisation | 0 `LocalizationService`, 80 chaînes FR en dur, sons choisis par texte. |
| Haut | Ressource | Pas d'encre : plafond théorique 81,5 casts/min limité par les seuls cooldowns. |
| Moyen | Équilibrage | DPS soutenu : Marque 6,25 (portée 270 studs) > Empattement 4,4 > Balayage 4,0 > Lavis 3,6 > Bavure 3,0 > Roussi 2,5 > Rupture 2,3 : les 2 touches dominent les 3 touches. Knockback inopérant sur tout le PvE livré. |
| Moyen | Progression | Battlepass 28 420 XP total, terminable en une session, non saisonnier, sans piste premium. Niveau joueur : 6,78 M XP pour L200 (≈ 82 h au débit max) **sans aucun effet gameplay**. |
| Moyen | PvE | 5 mannequins ancrés à 30 studs d'écart : aucune AoE ne touche deux cibles, aucun knockback visible, pas de boss. |
| Moyen | Rétention | Ni quêtes, ni récompenses journalières, ni streak, ni bonus de première victoire ; `AddXP.reason` ignoré. |
| Moyen | Analytics | 0 appel `AnalyticsService`. |
| Moyen | Kit de combat | Ni melee, ni dash, ni parade : rien à faire entre deux cooldowns. |
| Moyen | UI | Aucune mise à l'échelle ; barre de stamina sous le joystick tactile. |
| Bas | Roster | 4 pigments, 8 glyphes (cible : 5 pigments, ≥ 16 glyphes + Orpiment). |

---

## 6. Conclusion pour le plan

1. **Rien n'est à jeter dans les idées** : cast serveur-autoritaire, résolveur préfixe, DI, config data-driven, session lock → conservés et promus en modules typés.
2. **Tout le code doit être réécrit dans la nouvelle structure** (`src/`, `.luau`, `--!strict`, EN) : la dette de localisation (80 chaînes), le couplage des noms de pigments et l'absence de frontières de services rendent une traduction mécanique plus coûteuse qu'une réécriture guidée par les points forts.
3. **Ordre imposé par les dépendances** : toolchain + données + remotes sûrs (Phase 1) avant le combat (Phase 2), qui précède les modes (Phase 4) et la monétisation (Phase 7). Le mobile (Phase 3) précède les modes pour que chaque mode soit testé mentalement en tactile dès sa création.
4. **Les 4 bugs « haut » et les exploits de mouvement se résolvent par conception** : touches par défaut hors WASD/ZQSD, `CombatService` unique, mouvement décidé côté serveur, XP conditionnée à un hit ou à un résultat de match, encre comme ressource.
