# Progression

Reprise : « continue depuis docs/PROGRESS.md ». Lire ensuite `docs/PLAN.md` (phases), `docs/DECISIONS.md` (choix actés), `docs/ARCHITECTURE.md` (contrats d'API).

## État global

| Phase | Statut | Commit(s) |
|---|---|---|
| 0 — Audit, plan, conventions | ✅ fait | `4e14c6f` (poussé) |
| 1 — Fondations (toolchain, structure, ProfileStore, remotes sûrs, services, client, UI) | 🔶 en cours | 10 commits locaux `a8f943d`…`dff2391` (non poussés) |
| 2 — Cœur du combat | 🔶 fusionnée dans la Phase 1 (D-9) : chakra, M1/dash/garde, effets serveur + VFX client | |
| 3 — Mobile, manette, UI, localisation | ⏳ à faire (InputController tactile/manette déjà prévu en Phase 1) | |
| 4 — Hub, arènes, matchmaking, matchs, classement | ⏳ à faire | |
| 5 — World Boss | ⏳ à faire | |
| 6 — Progression et rétention | ⏳ à faire | |
| 7 — Monétisation, analytics, économie | ⏳ à faire (`docs/ECONOMY.md` déjà rédigé) | |
| 8 — Sécurité, performance, polish, docs, CI finale | ⏳ à faire (`ci.yml` / `publish.yml` déjà écrits) | |

## Fait (Phase 1)

- Toolchain : `rokit.toml`, `wally.toml` (+ `wally.lock`), `.luaurc` strict, `selene.toml`, `stylua.toml`, `.luau-lsp.json`, `scripts/setup.sh`, `scripts/check.sh`, `.github/workflows/{ci,publish}.yml`. Tout est installé localement (`~/.rokit/bin`, exporter le PATH).
- Structure `src/{shared,server,client,ui}` + `default.project.json` ; arbre V1 supprimé ; outil Studio dans `scripts/studio/`.
- Harnais Lune (`tests/harness.luau`, `tests/run.luau`) et 6 specs (32 tests verts) : Guard, TokenBucket, ComboResolver, DataMigration, Strings, Config.
- Contrats partagés : `Types`, `Remotes` (Guard + rate), `Strings` (EN/FR, ~120 clés), `Config/*` (Element, Input, Game, Progression, Jutsu 8 entrées, Combat, Battlepass 50×2 pistes, Sound), `Util/{Guard,TokenBucket,Log}`, `Pure/{ComboResolver (fenêtre d'extension), DataMigration}`.
- Serveur : `Vendor/ProfileStore.luau` (épinglé), `RemoteRegistry`, `Services/DataService` (migration V1→V2 + import legacy), `Bootstrap.server.luau`, `Services/{AntiCheat,Notify,Currency,Progression,Battlepass,Settings,Movement,Enemy}Service` (écrits, conformes aux contrats, **non commités**).
- Client : `RemoteClient`, `Controllers/ClientData`, `Bootstrap.client.luau`, `Controllers/{Localize,SoundController}` (**non commités**).
- UI : `Theme`, `components/{ScreenRoot,Panel,Button,ProgressBar}` (**non commités**).
- Docs : `ARCHITECTURE.md`, `GAME_DESIGN.md`, `ECONOMY.md`, `DECISIONS.md` D-1…D-12.

## En cours

- Workflow d'implémentation des fichiers restants (3 agents) : `Services/{VfxBroadcaster,CombatService,JutsuService}`, `Effects/JutsuEffects` ; contrôleurs client `{VfxLibrary,VfxController,HudController,InputController,ComboController,CombatController,MovementController,MenuController}` ; composants `{Tabs,ListRow,Slider,Toggle,Toast,TouchButton}` et écrans `{MenuScreen,SettingsScreen,BattlepassScreen}`.

## Reste (prochaines actions, dans l'ordre)

1. Vérifier que les fichiers ci-dessus existent (`find src -type f`) ; relancer le workflow ciblé sur les manquants si besoin.
2. Fusionner les `newStringKeys` demandés par les agents dans `src/shared/Strings.luau` (en + fr), puis `scripts/check.sh` (stylua, selene, luau-lsp strict sur `src/shared`, tests, build) et corriger.
3. Revue adversariale multi-agents (contrats, exploits, bugs) → corrections.
4. Commits Conventional (`feat(server): …`, `feat(client): …`, `feat(ui): …`) → `git push origin main` → mettre à jour ce fichier.
5. Phase 2 restante : roster 16+ jutsus + Foudre dans `JutsuConfig` (design dans `GAME_DESIGN.md` §5), effets + VFX correspondants, interactions élémentaires, tests de config.

## Definition of Done (mission §9)

- [ ] Tous les fichiers de §5 existent et sont à jour ; `CLAUDE.md` à la racine
- [ ] `rojo build` OK, lint/format/analyze/tests verts, CI verte sur GitHub
- [ ] 1v1 classé et 3v3 jouables de bout en bout
- [ ] World Boss fonctionnel
- [ ] ≥ 16 jutsus + Foudre, chakra, M1/dash/block, VFX client
- [ ] Mobile et manette jouables ; QWERTY/AZERTY sans conflit
- [ ] EN par défaut + FR, zéro chaîne en dur
- [ ] Game passes, developer products, `ProcessReceipt` idempotent, battle pass premium, boutique, bonus Premium, analytics
- [ ] Aucun TODO/placeholder ; seuls les IDs Roblox restent à renseigner, avec warnings au démarrage
- [ ] Historique git propre en Conventional Commits, tout poussé sur `origin main`
- [ ] Rapport final dans le chat
