# Progression

Reprise : « continue depuis docs/PROGRESS.md ». Lire ensuite `docs/PLAN.md` (phases), `docs/DECISIONS.md` (D-1 à D-27), `docs/ARCHITECTURE.md` (contrats d'API), `CLAUDE.md` (conventions).

## État global

| Phase | Statut | Commit |
|---|---|---|
| 0 — Audit, plan, conventions | ✅ | `4e14c6f` |
| 1 — Fondations (toolchain, `src/`, ProfileStore, remotes sûrs, services, client, UI) | ✅ | `a8f943d`…`130db43`, correctifs `d72a551` |
| 2 — Cœur du combat + roster 20 glyphes + Orpiment | ✅ | `ca3883a` |
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
- Découper les trois gros modules, par maintenabilité seulement : `VfxLibrary` (1 851 lignes, un module par famille d'effets), `CombatService` (1 271, le corps-à-corps et la garde sont séparables du cœur de dégâts) et `Effects/GlyphEffects` (1 183, un module par archétype). Aucun effet sur le jeu, mais à faire avant d'ajouter un sixième pigment. `MatchService` (792), `SettingsScreen` (706) et `InputController` (670) sont au-dessus de la limite indicative de 500 lignes sans être problématiques ; `Strings` (554) est une table de données et n'entre pas dans le compte.

## Definition of Done (mission §9)

- [x] Tous les documents de §5 existent et sont à jour ; `CLAUDE.md` à la racine
- [x] `rojo build` OK, format/lint/analyse/tests verts, CI verte sur GitHub
- [x] 1v1 classé et 3v3 jouables de bout en bout (file → match → résultat → Elo → classement → hub)
- [x] World Boss fonctionnel
- [x] 20 glyphes + pigment Orpiment, encre, M1/dash/garde, VFX rendus par le client
- [x] Mobile et manette jouables ; touches par défaut sans conflit QWERTY/AZERTY
- [x] EN par défaut + FR, zéro chaîne en dur (vérifié en CI)
- [x] Game passes, developer products, `ProcessReceipt` idempotent, pass premium, boutique, bonus Premium, analytics
- [x] Aucun TODO/placeholder ; seuls les IDs Roblox restent à renseigner, avec avertissements au démarrage
- [x] Historique git propre en Conventional Commits, tout poussé sur `origin main`
- [x] Passe de durcissement : trois revues adversariales enchaînées. La première a rendu 30 constats retenus (3 critiques, 10 élevés) ; la seconde, lancée sur les correctifs eux-mêmes, en a rendu 21 de plus dont 9 confirmés et 1 critique — une régression introduite par le premier correctif anti-triche. Tout est corrigé, et les décisions dont la conception a changé en route (D-32, D-33) ont été réécrites plutôt que contredites.
- [x] Rapport final dans le chat

## Passe « Identité & Game Feel »

| Phase | Statut | Commit |
|---|---|---|
| 0 — Audit du game feel, bible d'art, plan | ✅ | `266bbf3`, `573a3d7` |
| 1 — Le lexique et le lore | ✅ | `4fc31f6`…`fddeb8b` |
| 2 — `Feel` et `FeelConfig` | ✅ | `14ef09b`, `be45b2f` |
| 3 — Le pipeline VFX | ✅ | `3a7f5ec`…`b8820f7` |
| 4 à 9 — sorts, audio, UI, monde, boucle d'accroche, performance | ⬜ | — |

### Phase 1 — fait

- Cinq pigments, vingt glyphes, cinq rangs, « encre », vingt-trois cosmétiques, les noms de modules et de fichiers, les clés EN et FR, les documents, et le nom du projet (**Vellum**).
- `DataMigration` version 3 déplace quatre clés de profil et traduit leurs valeurs ; `Pure/LegacyNames.luau` porte les quatre tables de correspondance. `DataService` passe ces tables à la migration — sans ce paramètre un profil V2 se rechargeait vide.
- Trois portes nouvelles : `tests/Lexicon.spec.luau` (quatorze mots interdits dans `src`, `tests` et `docs`, camelCase inclus, plus la vérification des exemptions), `tests/EffectCoverage.spec.luau` (chaque sort atteint son effet serveur et son rendu client), et la preuve de migration étendue aux cosmétiques et aux compteurs.
- Deux noms de DataStore restent volontairement inchangés (D-44).

### Phase 1 — ce que les portes ont attrapé

- `GlyphConfig` réclamait `Effect = "Brand"` quand `GlyphEffects` déclarait encore `Fireball` : **aucun des vingt sorts n'était lançable**, et les sept portes étaient vertes. D'où `tests/EffectCoverage.spec.luau`.
- `Instance.new("Fire")` réécrit en `Instance.new("Cinnabar")` : `Fire` est une classe Roblox, pas un pigment. Selene l'a refusé, pour la deuxième fois.
- Le document de design listait toujours les cinq rangs empruntés et l'économie vendait encore une aura nommée d'après un personnage de la licence, longtemps après que le code fût propre. D'où l'extension du test aux documents. (Ce journal est scanné comme le reste : il décrit les mots refusés sans les écrire, ce qui est la bonne discipline de toute façon.)
- Deux balayages ont réécrit des fichiers qui doivent garder les anciens noms : la colonne « Avant » de l'`ART_BIBLE` et les fixtures de migration. D'où les assertions qui vérifient que les fichiers exemptés contiennent encore ce pour quoi ils sont exemptés.

### Phase 2 — fait

- `Pure/Spring.luau` (Euler semi-implicite à pas fixe, sous-échantillonné pour survivre à une image longue), `Pure/FeelMath.luau` (hit-stop selon les dégâts, atténuation par la distance, courbe d'impulsion normalisée, maintien puis fondu), `Config/FeelConfig.luau` : tous les chiffres, aucun ne touche à l'équilibrage.
- `Controllers/Feel.luau` : hit-stop, secousse par bruit de Perlin, impulsions de champ de vision, contour d'impact, nombres de dégâts, haptique manette, ressorts partagés. Une seule liaison de rendu pour tout.
- Câblé d'abord sur le M1 et l'esquive, puis sur l'impact. Le paquet `Hit` porte maintenant l'attaquant, la victime et la direction du coup.
- Recul et esquive suivent une courbe décroissante à distance totale inchangée.
- `Pure/Spring.luau` remplace `littensy/ripple` (D-47).

### Phase 2 — ce que les portes ont attrapé

- La porte d'analyse ne couvrait que `src/shared`, soit un quart du code et aucun fichier touchant le moteur. Élargie (D-51), elle a immédiatement révélé deux erreurs de type réelles.
- Selene a refusé un helper devenu mort après le passage de la secousse dans `Feel`.

### Phase 3 — fait

- **Textures générées.** `tools/textures/` : générateurs en Python pur (bibliothèque standard seule, y compris l'écriture PNG), douze textures dans `assets/textures/`, toutes blanches à canal alpha pour être teintées par pigment. Déterministes, vérifié en régénérant deux fois et en comparant les octets. Aucune ne vient de la boîte à outils.
- **Palette.** Les cinq pigments prennent les valeurs exactes de l'`ART_BIBLE`, et un test tient chaque paire à distance perceptuelle (D-52).
- **Éclairage.** `LightingConfig` + `WorldLighting` : le monde était sur le ciel et la lumière par défaut de Roblox. Les cinq effets de post-traitement sont déclarés en **décalages depuis le repos**, jamais en valeurs cibles, ce qui rend « jamais permanent » structurel.
- **Pooling.** `Pure/PoolPolicy` (comptabilité testable sans moteur) + `VfxPool` (les instances). Réinitialisation à l'emprunt, jamais au retour.
- **Timelines.** `VfxTimelineConfig` décrit un effet en cinq phases ; `VfxTimeline` les joue sur une seule connexion `Heartbeat`. Trois effets convertis en preuve : le lancement, l'impact et l'esquive.
- **`AssetIds`** centralisé, identifiant vide = pas encore téléversé, avertissement nommant le fichier, jamais de plantage.

### Phase 3 — ce que les portes et la relecture ont attrapé

- Le générateur de trait de pinceau produisait un losange chromé lisible dans n'importe quel autre jeu Roblox. Réécrit : directionnel, quinze pour un, poils discrets, queue qui se casse par seuil et non par fondu. C'est la règle de jugement de la mission appliquée à sa propre sortie.
- Le pool ne connaissait ni `Decal` ni `Beam`, que la timeline emprunte : chaque sceau et chaque brûlure au sol serait sorti sans texture, et aucun trait n'aurait été tracé.
- `VfxPool.acquire` peut refuser au plafond et renvoyer `nil` ; le runtime l'assumait non-nul. Une couche qui n'obtient pas ses instances n'est simplement pas dessinée, ce qui est la dégradation que demande la règle 8.
- `WorldLighting.pulse` ne renvoie rien ; mon runtime testait sa valeur de retour et aurait averti à chaque impact.
- `Trail` et `Light` ne s'unifient pas en Luau : `Trail | Light` n'a aucun membre, donc la branche combinée est une erreur de type et non un raccourci.
