# Journal des décisions

Format : **D-n — Titre** · Phase · Décision · Raison (deux lignes).

---

**D-1 — Langue des documents et du code** · Phase 0
Docs (`docs/`, `README.md`, `CLAUDE.md`) en français ; identifiants, commentaires de code et clés de localisation en anglais ; textes joueur EN par défaut + FR via `Strings`.
Raison : le propriétaire lit le français, les conventions Luau/outillage sont anglophones, et Roblox sert un public majoritairement anglophone.

**D-2 — Branche `main`** · Phase 0
Renommage de `master` en `main` (local + GitHub, branche par défaut mise à jour).
Raison : la mission impose `git push origin main` ; un seul commit existait, renommer est sans risque.

**D-3 — Toolchain via rokit, versions épinglées** · Phase 0
`rokit.toml` : rojo 7.7.0, wally 0.3.2, selene 0.31.0, StyLua 2.5.2, luau-lsp 1.69.0, lune 0.10.5. rokit 1.2.0 installé via le script officiel (`~/.rokit/bin`), absent de Homebrew.
Raison : versions résolues et testées localement le 2026-09-16 ; épingler garantit la reproductibilité CI/local.

**D-4 — ProfileStore vendoré depuis la source officielle, pas depuis Wally** · Phase 0
`src/server/Vendor/ProfileStore.luau` = copie exacte de `MadStudioRoblox/ProfileStore@45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31, 2242 lignes), SHA noté en tête de fichier. Aucune modification locale.
Raison : loleris ne publie pas ProfileStore sur Wally ; les seuls paquets (`ddashdev`, `goset33`, `b1ntran`…) sont des forks non audités (le mieux noté diffère de 662 lignes de l'original). Une source officielle épinglée est plus sûre qu'un fork inconnu.

**D-5 — Dépendances Wally** · Phase 0
`evaera/promise@4.0.0`, `sleitnick/signal@2.0.3`, `sleitnick/trove@1.8.0`. Existence vérifiée sur le registre le 2026-09-16.
Raison : bibliothèques standard de l'écosystème, maintenues, typées ; Trove préféré à Janitor pour son API plus petite et sa compatibilité Signal.

**D-6 — Tests : harnais Lune maison, modules purs sans `require`** · Phase 0
Pas de Jest-Lua ni TestEZ. `tests/harness.luau` fournit `describe / it / expect` (toBe, toEqual, toBeCloseTo, toThrow, toBeTruthy…) et `tests/run.luau` découvre `tests/**/*.spec.luau`. Les modules purs (`ComboResolver`, `Elo`, `MatchmakingCore`, `QuestLogic`, `DataMigration`, `ReceiptProcessor`, `Strings`) n'ont aucun `require` ni global Roblox et sont chargés par chemin relatif.
Raison : les paquets Wally (TestEZ, Jest-Lua, Promise…) utilisent `require(script.Parent…)` et ne se chargent pas sous Lune sans darklua ; un harnais de 150 lignes évite une chaîne de build supplémentaire. Vérifié : `lune run` + `require("../src/…")` fonctionne (probe du 2026-09-16).

**D-17 — Les statuts de combat sont des attributs de Humanoid avec leur propre expiration** · Phase 2
`Fanned`, `Conductive` et `StoneSkin` sont écrits par `CombatService` comme attributs portant un horodatage `os.clock` serveur, relus paresseusement dans `ApplyDamage` (aucun ticker, aucune boucle par joueur) et effacés à la réapparition. L'ordre est : marque élémentaire → réduction StoneSkin → garde, avec un seul arrondi final.
Raison : une file de timers par statut et par joueur coûterait plus cher que la lecture ponctuelle, et les attributs sont lisibles par le client pour l'affichage. Attention : la valeur est une horloge serveur, jamais comparable à `os.clock()` côté client.

**D-18 — Prison d'Eau immobilise par un ralentissement à 0, pas par un stun** · Phase 2
`WaterPrison` applique `applySlow(Def.Id, 0, 1.5)` au lieu de `applyStun`.
Raison : la cible reste capable de lancer un jutsu et de se défendre — c'est un contrôle de position, pas un silence ; un stun de 1,5 s serait au-dessus du budget d'étourdissement du genre.

**D-19 — LightningStep téléporte côté serveur après validation par raycast** · Phase 2
Le serveur lance un rayon sur `Def.Range`, recule de `WallBackoffStuds`, vérifie `ClearanceRadius` et raccroche au sol sur `GroundSnapStuds`, puis écrit le pivot du personnage. `MovementCommand` n'a pas de type « Teleport ».
Raison : un déplacement instantané confié au client serait un téléport arbitraire ; la validation serveur garantit qu'on ne traverse ni mur ni vide, et le pivot écrit une seule fois est immédiatement répliqué.

**D-7 — luau-lsp avec définitions Roblox téléchargées** · Phase 0
`scripts/setup.sh` télécharge `globalTypes.d.luau` depuis le dépôt luau-lsp (fichier ignoré par git) ; `.luau-lsp.json` déclare les alias. L'analyse stricte bloquante porte sur `src/shared` (gate), le reste est analysé en mode avertissement.
Raison : sans définitions, `luau-lsp analyze` ne connaît pas `game`, `Instance`, etc. ; limiter le gate strict à `shared` (modules purs + config) garde la CI fiable pendant la migration.

**D-8 — Le sprint V1 est remplacé par le dash** · Phase 1
Plus de sprint/endurance côté client : le kit V2 (M1, dash avec i-frames, garde) le remplace ; la vitesse de marche est fixée par le serveur (`MovementService`).
Raison : le sprint client-autoritaire était l'exploit n°1 de l'audit et n'existe pas dans le genre battlegrounds ; le dash apporte la mobilité attendue sans laisser le client écrire `WalkSpeed`.

**D-9 — Les effets de jutsus sont livrés directement dans l'architecture cible** · Phase 1
Le serveur ne fait que la détection de coups (overlaps / raycasts pas à pas / parts de collision invisibles) et diffuse des paquets `Vfx` ; chaque client rend via `VfxLibrary`. Le chakra (`CombatConfig`) est introduit en même temps.
Raison : réécrire les effets deux fois (Parts serveur en Phase 1 puis client en Phase 2) aurait doublé le travail sans valeur intermédiaire ; le plan Phase 1/2 est fusionné sur ce point.

**D-10 — Dash et knockback appliqués par le client propriétaire de la physique** · Phase 1
Le serveur décide (cooldown, chakra, i-frames, cible) puis envoie `MovementCommand` ; le client applique la vitesse sur son `HumanoidRootPart`.
Raison : sur Roblox, le personnage est simulé par le client propriétaire : une vitesse écrite par le serveur est écrasée en une frame (constat de l'audit). La décision reste serveur ; l'anti-teleport (Phase 8) borne la dérive.

**D-11 — Touches par défaut J / K / L / H / U, menu M, garde F, dash Maj gauche** · Phase 1
`InputConfig.DefaultKeyboard` évite WASD (QWERTY), ZQSD (AZERTY), Espace, Tab, Échap, I/O (zoom) et les chiffres (backpack) ; la liste blanche de rebind exclut ces mêmes touches.
Raison : résout le bug « A = strafe » sans dépendre de la disposition du clavier du joueur.

**D-12 — CI : rokit installé par le script officiel, pas par une action tierce** · Phase 1
`ci.yml` et `publish.yml` installent rokit via `install.sh` puis `rokit install --no-trust-check`.
Raison : aucune action GitHub officielle maintenue par rojo-rbx ; le script est la voie documentée et reste alignée sur `rokit.toml`.

**D-13 — Les i-frames du dash sont accordées sur la seule décision serveur** · Phase 1
Le serveur accorde 0,25 s d'invulnérabilité au moment où il valide le dash, sans observer le déplacement (le personnage est simulé par le client propriétaire, D-10). Un client qui ignore `MovementCommand` garde donc les i-frames sans bouger.
Raison : impossible d'observer le déplacement de façon fiable en Phase 1 ; la Phase 8 enregistre position/direction/durée attendues à l'envoi de la commande et les compare à la position réelle après `Duration + GameConfig.Latency.OriginToleranceStuds`.

**D-14 — Les ralentissements sont indexés par clé** · Phase 1
`MovementService.applySlow(player, key, factor, seconds)` / `clearSlow(player, key?)` : le facteur effectif est le minimum des entrées vivantes. La garde utilise la clé `"Block"`, chaque jutsu utilise son `Id`.
Raison : une seule valeur globale permettait de « nettoyer » le ralentissement d'un jutsu adverse en tapant la garde une fraction de seconde.

**D-15 — La zone sûre du hub est symétrique** · Phase 1
Un joueur à l'intérieur de la zone sûre ne peut ni subir ni infliger de dégâts PvP (avant : il était seulement protégé).
Raison : la protection à sens unique faisait de la zone un poste de tir imprenable. Les PNJ (mannequins, boss) restent frappables depuis la zone.

**D-16 — Les rejets de rate limit ne comptent pas comme triche** · Phase 1
`RemoteRegistry` distingue `"Schema"` (payload malformé → seuil `GameConfig.Server.AbuseKickThreshold`, 25) de `"RateLimit"` (débit trop élevé → seuil `RateLimitKickThreshold`, 600). Le client limite en plus ses propres envois au rythme que le serveur accepte.
Raison : un joueur qui martèle le clic gauche dépassait le budget de jetons et se faisait éjecter pour triche ; les deux compteurs ne s'additionnent jamais.
