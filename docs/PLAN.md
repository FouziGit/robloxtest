# Plan V2 — Vellum

Adapté aux constats de `docs/AUDIT.md`. Chaque phase se termine par : quality gates verts → commits Conventional Commits → `git push origin main` → `docs/PROGRESS.md` à jour. Le jeu reste `rojo build`-able et les tests verts à chaque commit.

Quality gates (`scripts/check.sh`) : `stylua --check src tests` · `selene src tests` · `luau-lsp analyze` strict sur tout `src` · `lune run tests/run` · `rojo build default.project.json -o build/Vellum.rbxl`.

---

## Architecture cible

```
src/
  shared/                       → ReplicatedStorage/Shared
    Config/                     GameConfig, PigmentConfig, GlyphConfig, CombatConfig, ProgressionConfig,
                                BattlepassConfig, QuestConfig, CosmeticConfig, ShopConfig, MonetizationConfig,
                                MatchConfig, RankingConfig, WorldBossConfig, InputConfig, VfxConfig, SoundConfig
    Types.luau                  types partagés (Profile, GlyphDef, MatchState, …)
    Remotes.luau                définition typée de chaque remote (nom, direction, fiabilité, schéma Guard)
    Strings.luau                {[key] = {en, fr}} + Strings.t(key, params) (module pur)
    Pure/                       modules purs sans require : ComboResolver, Elo, MatchmakingCore, QuestLogic,
                                DataMigration, ReceiptProcessor, RankTiers, ShopRotation, DailyStreak
    Util/                       Guard, TokenBucket, Signal (wally), Trove (wally), Promise (wally), Log
  server/                       → ServerScriptService
    Bootstrap.server.luau       crée les remotes, instancie et démarre les services dans l'ordre
    Vendor/ProfileStore.luau    copie épinglée (D-4)
    Services/                   DataService, SettingsService, ProgressionService, CurrencyService,
                                CombatService, GlyphService, MovementService, VfxBroadcaster,
                                HubService, ArenaService, MatchmakingService, MatchService, RankingService,
                                LeaderboardService, WorldBossService, QuestService, DailyRewardService,
                                BattlepassService, CosmeticService, ShopService, MonetizationService,
                                AnalyticsService, AntiCheatService, EnemyService
    GameModes/                  GameMode interface + Duel1v1, Team3v3, WorldBossMode
  client/                       → StarterPlayerScripts
    Bootstrap.client.luau
    Controllers/                ClientData, InputController (clavier/tactile/manette), ComboController,
                                CombatController (M1/dash/block), VfxController (VfxLibrary), SoundController,
                                HudController, MenuController, MatchController, ShopController, …
  ui/                           → ReplicatedStorage/UI
    Theme.luau, components/ (Button, Panel, ProgressBar, List, Toast, Modal, TouchButton, …), screens/
tests/                          harness.luau, run.luau, *.spec.luau
scripts/                        check.sh, setup.sh, studio/ (outils barre de commande)
docs/                           AUDIT, PLAN, DECISIONS, PROGRESS, GAME_DESIGN, ECONOMY, STUDIO_SETUP
.github/workflows/              ci.yml, publish.yml (workflow_dispatch)
```

Principes non négociables (voir `CLAUDE.md`) : serveur autoritaire, dégâts via `CombatService.ApplyDamage` uniquement, VFX rendus par le client, config dans `shared/Config`, zéro chaîne joueur en dur, `Guard` + token bucket sur chaque remote.

---

## Phase 0 — Audit, plan, conventions ✅

Livrables : `docs/AUDIT.md`, `docs/PLAN.md`, `docs/DECISIONS.md` (D-1…D-7), `docs/PROGRESS.md`, `CLAUDE.md`. Branche `main`. Toolchain vérifiée localement (rokit 1.2.0 ; rojo 7.7.0, wally 0.3.2, selene 0.31.0, StyLua 2.5.2, luau-lsp 1.69.0, lune 0.10.5) ; ProfileStore épinglé `45c9847` ; harnais Lune validé.

## Phase 1 — Fondations : toolchain, structure, données, remotes sûrs

Objectif : tout ce que la V1 fait fonctionne à nouveau dans la nouvelle structure, en `.luau` strict, anglais, avec ProfileStore et des remotes protégés.

1. Fichiers de toolchain : `rokit.toml`, `wally.toml`, `.luaurc` (strict), `selene.toml` (std roblox), `stylua.toml`, `.luau-lsp.json`, `scripts/setup.sh` (globalTypes), `scripts/check.sh`, `.gitignore` (Packages/, build/, globalTypes.d.luau), `default.project.json` réécrit (`src/*`, `Packages` → `ReplicatedStorage/Packages`, Lighting/Workspace hub générés par code donc non mappés).
2. Harnais de test `tests/harness.luau` + `tests/run.luau` ; premier test : `DataMigration`.
3. `shared/Config/*` : pigments ré-identifiés en anglais (`Cinnabar, Indigo, Umber, Verdigris`, `Orpiment` réservé), touches par défaut hors déplacement QWERTY/AZERTY (`J K L ;`→ décision : `J, K, L, H` clavier ; voir InputConfig), constantes d'effets sorties de `GlyphEffects` vers `GlyphConfig`.
4. `shared/Strings.luau` : toutes les chaînes de la V1 réécrites en clés EN/FR ; test « chaque clé a `en` et `fr` ».
5. `shared/Util/Guard.luau` (schémas : string, number bornés, enum, array typé, table stricte) + `TokenBucket.luau` ; `shared/Remotes.luau` typé.
6. `server/Vendor/ProfileStore.luau` (copie officielle épinglée) ; `DataService` avec schéma `DataVersion = 2`, `Pure/DataMigration.luau` (v1 → v2 : `Cinabre/Indigo/Terre d'Ombre/Vert-de-gris` → `Cinnabar/Indigo/Umber/Verdigris` dans Keybinds, IDs de glyphes/cosmétiques FR → EN, `ClaimedRewards` → `Battlepass[SeasonId].Claimed`, conserve XP/niveaux/monnaie ; nouveaux champs : `Purchases`, `Passes`, `Quests`, `Daily`, `Loadouts`, `Cosmetics{Owned, Equipped}`, `Rank`, `Stats`), signal `ProfileLoaded`.
7. `Bootstrap.server.luau` / `Bootstrap.client.luau` ; services `SettingsService` (keybinds), `ProgressionService` (niveau joueur), `CurrencyService`, `GlyphService` (pipeline K1 réécrit, effets encore serveur dans cette phase), `EnemyService` (mannequins, hook par table et non par attribut, effacement de `LastAttackerUserId`), `AntiCheatService` (compteur d'abus + kick), `Log`.
8. Client : `ClientData` (une seule source, diff `DataChanged`), `ComboController` (utilise `ComboResolver` pur), `HudController`, `SettingsScreen`, `BattlepassScreen` sur `ui/components` + `Theme` ; `MovementController` avec décision de sprint serveur (`MovementService` fixe `WalkSpeed`, valide stamina) et double saut par front d'appui.
9. Suppression de l'arbre V1 (`ReplicatedStorage/`, `ServerScriptService/`, `StarterPlayer/`, `README_INSTALLATION.md`), déplacement de `StudioTools/` vers `scripts/studio/`.
10. `.github/workflows/ci.yml` (rokit action, wally install, gates, artefact `.rbxl`).

Tests Phase 1 : `DataMigration`, `Strings`, `Guard`, `TokenBucket`.

## Phase 2 — Cœur du combat

1. `Pure/ComboResolver.luau` : `new(recipes, maxLength)`, `push(state, pigment) → {action = "cast"|"wait"|"reset", glyphId?}`, `timeout(state)`, index préfixe ; tests (préfixes, timeouts, longueur max, ambiguïtés, spam d'une touche).
2. `CombatConfig` : encre (max, coût par glyph, régénération hors/en combat, délai « en combat »), M1 (3 coups + finisher knockback, fenêtres), dash (distance, i-frames, cooldown), block (réduction, glyphes qui cassent la garde), stun/ragdoll léger, i-frames par cible par glyph, tolérance de latence.
3. `CombatService` : `ApplyDamage(source, target, amount, kind, tags)` unique (gate PvP par mode/équipe/spawn-protection/ForceField, i-frames, block, stun, knockback serveur via `LinearVelocity` éphémère), `CombatState` par joueur (encre, inCombat, blocking, stunned, iFrames), tick centralisé `Heartbeat`.
4. `GlyphService` réécrit : coût encre, cooldowns, origine/direction serveur avec tolérance bornée, exécution via `GlyphEffects` serveur **sans visuel** (hit detection `GetPartBoundsInRadius/Box`, raycasts, Parts de collision invisibles, plus de `Touched`), XP conditionnée à ≥ 1 hit ou à un résultat de match.
5. Roster `GlyphConfig` ≥ 16 glyphes (8 conservés rééquilibrés + 8 nouveaux) sur 4 pigments + Orpiment (4 combos), combos 2-4 touches, archétypes variés, arbre de combos sans préfixe bloquant pour les 2 touches de base (voir `GAME_DESIGN.md`), interactions de pigment simples.
6. `VfxBroadcaster` (serveur) → `UnreliableRemoteEvent` `{vfxId, origin, direction, targets}` ; client `VfxController` + `VfxLibrary` data-driven (ParticleEmitters, Beams, Trails, Tweens, camera shake, hit-stop, hit flash) ; sons via `SoundConfig` par `sfxId`.
7. `CombatController` client : intentions `Melee`, `Dash`, `Block` ; HUD encre.

Tests Phase 2 : `ComboResolver`, `GlyphConfig` (unicité, longueurs, coûts > 0, `Unlock` valide, tous les `vfxId` existent dans `VfxConfig`).

## Phase 3 — Mobile, manette, UI responsive, localisation complète

1. `InputController` : `ContextActionService` pour pigments / Dash / Melee / Block / Menu, boutons tactiles pouce droit (icônes + couleurs par pigment), haptique si dispo, manette (D-pad = pigments, boutons = actions), clavier QWERTY/AZERTY sans conflit, rebind clavier **et** manette dans les options.
2. `Theme` + composants responsives (`UIScale` par résolution, `UIAspectRatioConstraint`, safe area, `IgnoreGuiInset` cohérent), `ScreenOrientation = LandscapeSensor`, test mental 16:9 / 4:3.
3. `Strings` finalisé + `scripts/export-strings.luau` → `localization.csv` importable ; test « zéro chaîne en dur » (grep CI sur `src/` : aucune string littérale de plus de 2 mots hors `Strings.luau` et commentaires).

## Phase 4 — Hub, arènes, matchmaking, matchs, classement

1. `HubService` : hub géométrique (spawn, zone d'entraînement avec mannequins, terminal de queue, panneaux leaderboard `SurfaceGui`, boutique) ; `ArenaService` : arènes générées en code dans `ServerStorage` (murs, spawns par équipe, kill zone, éclairage), instanciées par match ; ancrages documentés (`docs/GAME_DESIGN.md`).
2. `Pure/MatchmakingCore.luau` (file par mode, fenêtre de rating élargie dans le temps, retrait, tests) ; `MatchmakingService` intra-serveur 1v1 / 3v3 ; interface réservée pour `MemoryStoreService`.
3. `GameMode` (`CanStart, Start, OnPlayerLeft, End`) ; `MatchService` (instanciation d'arène, téléport, compte à rebours, timer, conditions de victoire, best-of-3 optionnel, déconnexions/abandons, retour hub, cleanup Trove, PvP restreint aux participants, spawn protection).
4. `Pure/Elo.luau` (K dégressif, symétrie, bornes, tests) ; `Pure/RankTiers.luau` (Vierge → Esquisse → Écriture → Enluminure → Codex) ; `RankingService` + `LeaderboardService` (`OrderedDataStore` par saison : global, 1v1, 3v3 ; refresh 60 s sous budget) ; `MatchController` + `LeaderboardScreen`.
5. Récompenses de fin de match (XP, Ryo, XP de pass, quêtes) ; bonus première victoire du jour.

Tests Phase 4 : `MatchmakingCore`, `Elo`, `RankTiers`.

## Phase 5 — World Boss

`WorldBossService` + `WorldBossMode` : annonce + compte à rebours périodiques, boss avec HP scalé sur les joueurs, 3-4 attaques télégraphiées (VFX client), phases, contribution aux dégâts → récompenses, pas de PvP pendant l'événement.

## Phase 6 — Progression et rétention

Déblocage de glyphes par niveau, loadouts (slots limités), `Pure/QuestLogic.luau` + `QuestService` (journalières / hebdomadaires data-driven), `Pure/DailyStreak.luau` + `DailyRewardService`, battle pass saisonnier gratuit/premium, `CosmeticService` (skins de glyphes = palettes VFX, auras, traînées, effets de kill, titres ; rendu par `VfxController`), récompenses de fin de saison.

Tests Phase 6 : `QuestLogic`, `DailyStreak`, `BattlepassConfig` (50 paliers, deux pistes).

## Phase 7 — Monétisation, analytics, économie

`MonetizationConfig` (IDs + validation au boot avec `warn` par ID manquant), `MonetizationService` (game passes : VIP, slots de loadout, Orpiment, pack de skins ; dev products : 3 packs de Ryo, pass premium, saut de paliers, boost XP ; ownership vérifiée à la connexion / cachée / mise à jour sur `PromptGamePassPurchaseFinished` ; `Pure/ReceiptProcessor.luau` idempotent testé avec mocks ; achats hors connexion), `ShopService` + `Pure/ShopRotation.luau` (rotation quotidienne seedée), bonus Premium, `PolicyService` avant tout aléatoire payant (boutique directe, pas de caisses), prompts contextuels non agressifs (jamais dans les 3 premières minutes de la première session), `AnalyticsService` (économie, funnel, custom, rate-limité), `docs/ECONOMY.md`.

Tests Phase 7 : `ReceiptProcessor`, `ShopRotation`, `MonetizationConfig` (validation).

## Phase 8 — Sécurité, performance, polish, docs, CI finale

Passe §4 complète (Guard/rate limit/kick sur chaque remote, anti-teleport/speed en match, aucun `RemoteFunction` yield sans timeout), budgets (aucune boucle par joueur, DataStore/MemoryStore avec retries + backoff), polish VFX/UI, `README.md`, `docs/STUDIO_SETUP.md`, `docs/GAME_DESIGN.md` et `docs/ECONOMY.md` finalisés, `publish.yml` (Open Cloud, `workflow_dispatch`), dernier push, rapport final.

---

## Définition de fini (rappel)

Voir la mission §9 ; suivi ligne par ligne dans `docs/PROGRESS.md`.
