# CLAUDE.md — Vellum

Conventions du projet. Toute session (humaine ou agent) les respecte. Reprise de travail : lire `docs/PROGRESS.md` puis `docs/PLAN.md`.

## Produit

Battleground PvP Roblox (Luau, Rojo). Mécanique signature : glyphes lancés par séquences de touches de pigment (Cinabre / Indigo / Terre d'Ombre / Vert-de-gris / Orpiment). Modes : hub d'entraînement, 1v1 classé, 3v3, World Boss. Objectif : jeu rejouable et rentable (mobile, EN/FR, rétention, monétisation propre).

## Structure

```
src/shared/   → ReplicatedStorage/Shared   (config, modules purs, types, Strings, VfxLibrary data)
src/server/   → ServerScriptService        (services + Bootstrap.server.luau)
src/client/   → StarterPlayerScripts       (controllers + Bootstrap.client.luau)
src/ui/       → ReplicatedStorage/UI       (composants UI générés en code, thème)
tests/        → tests Lune (*.spec.luau) + tests/run.luau
docs/         → AUDIT, PLAN, DECISIONS, PROGRESS, GAME_DESIGN, ECONOMY, STUDIO_SETUP
Packages/     → généré par `wally install` (ignoré par git)
build/        → sortie `rojo build` (ignoré par git)
```

## Toolchain

`rokit install` (rojo, wally, selene, stylua, luau-lsp, lune) puis `wally install`. Commandes canoniques :

```bash
stylua --check src tests
selene src tests
luau-lsp analyze --definitions=globalTypes.d.luau --settings=.luau-lsp.json --ignore="**/Vendor/**" src
lune run tests/run
rojo build default.project.json -o build/Vellum.rbxl
```

Ces cinq commandes sont les quality gates : toutes vertes avant chaque commit. `scripts/check.sh` les enchaîne.

## Conventions de code

- Extension `.luau`. Identifiants et commentaires en **anglais**. Tout texte visible par le joueur passe par `Strings.t(key, params)` (EN par défaut, FR). Zéro chaîne joueur en dur.
- `--!strict` sur tout `src/shared` et tous les modules purs. `--!nonstrict` ailleurs uniquement si justifié dans un commentaire d'en-tête.
- Un service = un ModuleScript `{ Init(deps), Start() }`. Dépendances injectées par le Bootstrap ; aucun `require` circulaire ; un seul point d'entrée serveur (`Bootstrap.server.luau`) et client (`Bootstrap.client.luau`).
- Modules purs (`ComboResolver`, `Elo`, `MatchmakingCore`, `QuestLogic`, `DataMigration`, `ReceiptProcessor`, `Strings`) : **aucun** `require`, aucun global Roblox. Ils sont testés sous Lune et requis par chemin relatif dans `tests/`.
- `task.*` uniquement (jamais `wait`, `spawn`, `delay`). Cleanup via Trove ; connexions déconnectées à la mort / au départ. Aucune boucle `while true do task.wait() end` par joueur : les tick serveur passent par un `Heartbeat` centralisé avec accumulateurs.
- Config uniquement dans `src/shared/Config/*`. Aucune constante magique dans les services. Les IDs Roblox (game passes, products, place) uniquement dans `MonetizationConfig`, validés au démarrage avec un `warn` explicite par ID manquant.
- UI 100 % générée en code via `src/ui/components` + thème centralisé. Aucune UI construite dans Studio.
- Dégâts uniquement via `CombatService.ApplyDamage(source, target, amount, kind, tags)`. Le serveur ne construit aucun VFX : il diffuse `{vfxId, origin, direction, targets}` et chaque client rend via `VfxLibrary`.
- Chaque remote : `Guard` (type-check strict) + rate limit token-bucket + rejet silencieux journalisé + kick après N abus. Jamais de confiance client pour positions, cibles, dégâts, résultats, monnaie, récompenses, ownership.
- Logs serveur préfixés `[ServiceName]`. `pcall` → toujours `warn` avec contexte ; jamais d'erreur avalée.
- Interdits : `TODO`, `FIXME`, placeholders, fonctions vides, code mort, features à moitié. Impossible à finir → retirer proprement + noter dans `docs/DECISIONS.md`.

## Git

Branche `main`. Conventional Commits (`feat(matchmaking): …`, `fix(combat): …`, `docs: …`, `chore(toolchain): …`). Commits atomiques ; le jeu reste `rojo build`-able et les tests verts à chaque commit. Push après chaque phase. Ne jamais prétendre avoir poussé si le push a échoué.

## Documentation

Toute décision non triviale → `docs/DECISIONS.md` (raison en deux lignes). Fin de phase → `docs/PROGRESS.md` (fait / en cours / reste). Design → `docs/GAME_DESIGN.md`, économie → `docs/ECONOMY.md`, setup manuel Studio → `docs/STUDIO_SETUP.md`.
