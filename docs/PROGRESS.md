# Progression

Reprise : « continue depuis docs/PROGRESS.md ». Lire ensuite `docs/PLAN.md` (phases) et `docs/DECISIONS.md` (choix actés).

## État global

| Phase | Statut | Commit(s) |
|---|---|---|
| 0 — Audit, plan, conventions | ✅ fait | `docs: phase 0 audit, plan, conventions` |
| 1 — Fondations (toolchain, structure, ProfileStore, remotes sûrs) | ⏳ à faire | |
| 2 — Cœur du combat | ⏳ à faire | |
| 3 — Mobile, manette, UI, localisation | ⏳ à faire | |
| 4 — Hub, arènes, matchmaking, matchs, classement | ⏳ à faire | |
| 5 — World Boss | ⏳ à faire | |
| 6 — Progression et rétention | ⏳ à faire | |
| 7 — Monétisation, analytics, économie | ⏳ à faire | |
| 8 — Sécurité, performance, polish, docs, CI finale | ⏳ à faire | |

## Fait

- Audit multi-agents de la V1 (68 constats, 16 hauts confirmés) → `docs/AUDIT.md`.
- Plan en 8 phases adapté à l'audit → `docs/PLAN.md`.
- Conventions → `CLAUDE.md`. Décisions D-1 à D-7 → `docs/DECISIONS.md`.
- Toolchain vérifiée localement (versions dans D-3), ProfileStore officiel épinglé (D-4), harnais Lune validé (D-6).
- Branche `main` créée et poussée.

## En cours

- Rien.

## Reste (prochaine action)

- Phase 1, étape 1 : écrire les fichiers de toolchain (`rokit.toml`, `wally.toml`, `.luaurc`, `selene.toml`, `stylua.toml`, `.luau-lsp.json`, `scripts/setup.sh`, `scripts/check.sh`, `.gitignore`, `default.project.json`).

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
