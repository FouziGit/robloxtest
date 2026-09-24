# Pipeline d'animation — suivi

Mission : améliorer la qualité des animations de Vellum sans toucher au gameplay. Branche `feat/anim-pipeline`. Décision : D-117.
Reprise après un redémarrage de Claude : relancer avec `claude -c`, puis lire ce fichier.

## Phase 0 — audit

| Point | Constat |
|---|---|
| Blender | 5.2.2 LTS, `/Applications/Blender.app` (utilisé sans interface, `-b`) |
| uv | `/Users/fouzi/.local/bin/uv` (pas nécessaire : les outils sont en Python standard) |
| MCP | Roblox Studio connecté ; aucun MCP Blender (et aucun installé, voir phase 1) |
| Production des `.rbxmx` | `tools/animations/retarget.py` dans Blender : clips CC0 Quaternius reciblés sur R15, chaque image cuite, easing linéaire entre les images ; `generate_all.py` + `clips.json` |
| Publication | `scripts/upload_assets.py` (Open Cloud) → verrou `assets/roblox-assets.lock.json` → bloc `UPLOADED` de `AnimationConfig.luau` |
| Timing serveur de la Marque | paquet `Cast` à l'acceptation, puis `task.wait(Windup)` = **0,06 s** avant le vol (`GlyphEffects.Brand`) |
| Affichage client du projectile | timeline `BRAND` : Anticipation 0,04 + Cast 0,02 → le vol dessiné part à **0,06 s**, avec le vrai (`tests/Flight.spec.luau`) |
| Lecture du clip | `Moves` joue l'action `Cast` sur le paquet `Cast`, priorité Action, fondu 0,06 s, vitesse 1,2, sans marqueur |
| Pourquoi c'était médiocre | un seul clip générique pour les vingt glyphes ; mesuré en jeu, **main 2,2 studs derrière le corps** quand la Marque part ; pose presque immobile de tout le lancer ; toutes les articulations posées, jambes comprises (pieds qui glissent en course) ; un coup et un lancer à la même priorité se mélangeaient |

## Phase 1 — outils (décidé)

- Pas de MCP Blender : rendus Blender sans interface, pilotés par script. Aucun code tiers installé ni exécuté, rien à ouvrir à la main.
- Le skill tiers (dillydog580) n'a pas été installé ; aucun plugin ajouté.
- `.blend` d'origine : aucun n'est ouvert ni modifié (l'outil n'en utilise pas).

## Phase 2 — la Marque (fait)

| Étape | Résultat |
|---|---|
| Poses clés | repos → **lâcher 0,06 s** (paume dans le sceau, buste tourné 26°, penché) → main gauche à la hanche 0,10 s → **dépassement 0,12 s** → tenue jusqu'à 0,24 s → retour 0,40 s → repos 0,58 s |
| Courbes | courbe douce par angle (monotone, sans rebond parasite) ; `QuadIn` jusqu'au contact, `QuadOut` dans le dépassement, `SineInOut` pour la tenue ; aucun linéaire (refusé par l'outil) |
| Secondaire | dépassement bras 98° → 88°, buste 38° → 29° ; main gauche en retard ; poignet qui fouette (15° → 45° → 28°) ; tête qui garde la cible |
| Chiffres | pire rotation 34,7°/image à 60 i/s ; début et fin au repos ; main devant le corps au lâcher sur les deux rigs ; aucune articulation sous la taille |
| Studio (vrai lancer J+J, clip enregistré localement, pas publié) | **avant** : main à z +2,18 (derrière) au départ de la Marque ; **après** : z −2,48, y +0,30, dans le sceau ; marche intacte ; console sans erreur du jeu |
| Code | `CastByGlyph` + `castClip` ; `Moves` joue le lancer du glyphe ; `Posture` s'écarte pour la même question ; un coup ou un lancer arrête le précédent |
| Portes | `tests/AnimationConfig.spec.luau` (11 mutations, 11 échecs) ; `check.sh` et la CI reconstruisent le clip depuis ses poses |

Fichiers : `tools/animations/keyed.py`, `tools/animations/preview_blender.py`, `tools/animations/keyed/brand_throw.json`, `tools/animations/rigs/*.json` (mesurés dans Studio : R15 standard et l'avatar du développeur), `assets/animations/brand_throw.rbxmx`.

## Idées d'anticipation — proposées, non appliquées

Le lâcher tombe à 0,06 s : trop tôt pour une vraie anticipation. Pistes, à décider par le développeur :

1. **Pose de « charge » sur la première touche de pigment** (client seulement) : dès la première touche d'une recette, la main droite se ramène à la hanche ; le paquet `Cast` part alors d'une pose armée. Aucun changement serveur. Limite : une première touche commence plusieurs recettes, la charge doit donc être par pigment, et relâchée si la recette est abandonnée.
2. **Allonger le Windup de la Marque** (0,06 → 0,10–0,12 s) pour 3 à 4 images d'armé visible. **Change le gameplay** (la Marque part plus tard, à toutes les portées) : à ne faire que sur décision explicite.
3. **Une traînée d'encre au lâcher** qui suit la main (le balayage de pinceau existe déjà côté VFX) : renforce le contact sans rien changer au timing.

## Phase 3 — skill (en cours)

`.claude/skills/vellum-animation/` + lignes dans `CLAUDE.md` ; test sur un second glyphe (le Lavis, Indigo + Indigo).

## Ce que le développeur doit faire

1. Regarder l'avant/après et les GIF (envoyés dans la conversation).
2. S'il valide : autoriser l'envoi du clip sur Roblox. La commande, déjà vérifiée à blanc (`plan` : un seul fichier) : `python3 scripts/upload_assets.py upload`. Elle écrit l'id dans `AnimationConfig.luau` ; la Marque joue alors son propre lancer, sans autre changement.
3. Relire et fusionner la branche `feat/anim-pipeline`.
