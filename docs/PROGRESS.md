# Progression

Reprise : « continue depuis docs/PROGRESS.md ». Lire ensuite `docs/PLAN.md` (phases), `docs/DECISIONS.md` (choix actés), `docs/ARCHITECTURE.md` (contrats d'API).

## État global

| Phase | Statut | Commit(s) |
|---|---|---|
| 0 — Audit, plan, conventions | ✅ fait | `4e14c6f` (poussé) |
| 1 — Fondations (toolchain, structure, ProfileStore, remotes sûrs, services, client, UI) | ✅ implémentée, poussée (`130db43`), CI verte ; revue adversariale en cours | `a8f943d`…`130db43` |
| 2 — Cœur du combat | 🔶 fusionnée dans la Phase 1 (D-9) : chakra, M1/dash/garde, effets serveur + VFX client | |
| 3 — Mobile, manette, UI, localisation | ⏳ à faire (InputController tactile/manette déjà prévu en Phase 1) | |
| 4 — Hub, arènes, matchmaking, matchs, classement | 🔶 modules purs faits (`Elo`, `RankTiers`, `MatchmakingCore`, `RankingConfig`, `MatchConfig`) ; services à faire | `411b7f2` |
| 5 — World Boss | ⏳ à faire | |
| 6 — Progression et rétention | 🔶 modules purs faits (`QuestLogic`, `DailyStreak`, `QuestConfig`, `DailyConfig`, `CosmeticConfig`, `ShopRotation`) ; services/écrans à faire | `e78ed2c`, suivant |
| 7 — Monétisation, analytics, économie | 🔶 `MonetizationConfig`, `ReceiptProcessor`, `ShopConfig`, `docs/ECONOMY.md`, `docs/STUDIO_SETUP.md` faits ; services à faire | |
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

- Revue adversariale multi-agents de la Phase 1 (contrats, exploits, runtime, mobile/UI) ; corrections à commiter en `fix(...)`.

## Reste (prochaines actions, dans l'ordre)

1. Appliquer les constats confirmés de la revue → `fix(...)` → push.
2. Phase 2 : roster 20 jutsus + Foudre dans `JutsuConfig` (design `GAME_DESIGN.md` §5) + `JutsuEffects` + `VfxLibrary` + Strings ; interactions élémentaires (`Éventé`, extinction, conduction) dans `CombatService` ; schéma `Boosts.XpUntil` (Types/DataService/DataMigration) pour le boost d'XP.
3. Phase 3 : export CSV des Strings (`scripts/export-strings.luau`), test « zéro chaîne en dur », passe mobile/manette sur les écrans.
4. Phase 4 : `HubService`, `ArenaService`, `GameMode`, `MatchmakingService`, `MatchService`, `RankingService`, `LeaderboardService`, `MatchController`, écrans file/résultat/classement.
5. Phase 5 : `WorldBossService` + `WorldBossMode`.
6. Phase 6 : `QuestService`, `DailyRewardService`, `LoadoutService`, `CosmeticService`, écrans quêtes/loadout/boutique.
7. Phase 7 : `MonetizationService` (passes, produits, `ProcessReceipt`), `ShopService`, `AnalyticsService`, prompts contextuels.
8. Phase 8 : passe sécurité/perf, `README.md`, docs finales, rapport.

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
