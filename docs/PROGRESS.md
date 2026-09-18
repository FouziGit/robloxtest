# Progression

Reprise : « continue depuis docs/PROGRESS.md ». Lire ensuite `docs/PLAN.md` (phases), `docs/DECISIONS.md` (D-1 à D-27), `docs/ARCHITECTURE.md` (contrats d'API), `CLAUDE.md` (conventions).

## État global

| Phase | Statut | Commit |
|---|---|---|
| 0 — Audit, plan, conventions | ✅ | `4e14c6f` |
| 1 — Fondations (toolchain, `src/`, ProfileStore, remotes sûrs, services, client, UI) | ✅ | `a8f943d`…`130db43`, correctifs `d72a551` |
| 2 — Cœur du combat + roster 20 jutsus + Foudre | ✅ | `ca3883a` |
| 3 — Mobile, manette, UI responsive, localisation EN/FR | ✅ | intégrée aux phases 1-2 + `c022f71` (export CSV, garde anti-chaîne en dur) |
| 4 — Hub, arènes, matchmaking, matchs classés, Elo, leaderboards | ✅ | `84d91c7` |
| 5 — World Boss | ✅ | `831a789` |
| 6 — Quêtes, daily, loadout, cosmétiques | ✅ | `831a789` |
| 7 — Monétisation, boutique, analytics | ✅ | `831a789` |
| 8 — Sécurité, performance, polish, docs finales | ✅ | `8eac72b`…`1b160c2` |

## Chiffres

133 fichiers `.luau` hors bibliothèque vendorée, 30 426 lignes, 8 documents, 306 clés de localisation EN/FR, 126 tests Lune sur 20 fichiers de spécification, 7 portes de qualité en CI.

## Ce qui reste à faire par le propriétaire

1. **Créer les game passes et developer products** dans le Creator Dashboard et coller les IDs dans `src/shared/Config/MonetizationConfig.luau` — noms, prix conseillés et emplacements exacts dans `docs/STUDIO_SETUP.md`. Le serveur affiche un `warn` par ID manquant au démarrage et refuse proprement ces achats en attendant.
2. **Publier la place** et cocher *Game Settings → Security → Enable Studio Access to API Services*, sinon rien n'est sauvegardé (ProfileStore le signale dans l'Output).
3. **Aucune `SpawnLocation` ni baseplate ne doit être créée à la main** : `HubService` construit le hub et `HubSpawn` doit rester le seul point de spawn (le service avertit s'il en trouve un autre).
4. Optionnel : secrets `ROBLOX_API_KEY`, `UNIVERSE_ID`, `PLACE_ID` pour la publication automatisée (`.github/workflows/publish.yml`).

## Reste (suite technique possible)

- File d'attente inter-serveurs via `MemoryStoreService` (l'interface de `MatchmakingService` est prête ; aujourd'hui la file est intra-serveur).
- Anti-téléport / anti-speed par comparaison du déplacement attendu et observé (D-13 : les i-frames du dash sont accordées sur la seule décision serveur).
- Caisses ou aléatoire payant : volontairement absents (boutique directe, voir `docs/ECONOMY.md`) ; nécessiteraient `PolicyService` et l'affichage des probabilités.
- Système de spectateur (D-22 : un joueur éliminé attend au hub).
- Découper les trois gros modules, par maintenabilité seulement : `VfxLibrary` (1 851 lignes, un module par famille d'effets), `CombatService` (1 271, le corps-à-corps et la garde sont séparables du cœur de dégâts) et `Effects/JutsuEffects` (1 183, un module par archétype). Aucun effet sur le jeu, mais à faire avant d'ajouter un sixième élément. `MatchService` (792), `SettingsScreen` (706) et `InputController` (670) sont au-dessus de la limite indicative de 500 lignes sans être problématiques ; `Strings` (554) est une table de données et n'entre pas dans le compte.

## Definition of Done (mission §9)

- [x] Tous les documents de §5 existent et sont à jour ; `CLAUDE.md` à la racine
- [x] `rojo build` OK, format/lint/analyse/tests verts, CI verte sur GitHub
- [x] 1v1 classé et 3v3 jouables de bout en bout (file → match → résultat → Elo → classement → hub)
- [x] World Boss fonctionnel
- [x] 20 jutsus + élément Foudre, chakra, M1/dash/garde, VFX rendus par le client
- [x] Mobile et manette jouables ; touches par défaut sans conflit QWERTY/AZERTY
- [x] EN par défaut + FR, zéro chaîne en dur (vérifié en CI)
- [x] Game passes, developer products, `ProcessReceipt` idempotent, pass premium, boutique, bonus Premium, analytics
- [x] Aucun TODO/placeholder ; seuls les IDs Roblox restent à renseigner, avec avertissements au démarrage
- [x] Historique git propre en Conventional Commits, tout poussé sur `origin main`
- [x] Passe de durcissement : trois revues adversariales enchaînées. La première a rendu 30 constats retenus (3 critiques, 10 élevés) ; la seconde, lancée sur les correctifs eux-mêmes, en a rendu 21 de plus dont 9 confirmés et 1 critique — une régression introduite par le premier correctif anti-triche. Tout est corrigé, et les décisions dont la conception a changé en route (D-32, D-33) ont été réécrites plutôt que contredites.
- [ ] Rapport final dans le chat
