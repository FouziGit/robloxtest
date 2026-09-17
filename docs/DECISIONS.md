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

**D-7 — luau-lsp avec définitions Roblox téléchargées** · Phase 0
`scripts/setup.sh` télécharge `globalTypes.d.luau` depuis le dépôt luau-lsp (fichier ignoré par git) ; `.luau-lsp.json` déclare les alias. L'analyse stricte bloquante porte sur `src/shared` (gate), le reste est analysé en mode avertissement.
Raison : sans définitions, `luau-lsp analyze` ne connaît pas `game`, `Instance`, etc. ; limiter le gate strict à `shared` (modules purs + config) garde la CI fiable pendant la migration.
