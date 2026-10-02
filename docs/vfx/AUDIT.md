# Passe VFX — audit et plan

Mission : donner du punch et du dynamisme aux effets, **en les voyant**. Aucun changement de gameplay ni de timing serveur. Branche `feat/vfx-pass`. Décisions : D-118 et suivantes.

## Phase 0 — audit (lecture seule, 5 lecteurs parallèles + vérifs en direct)

### Outils

| Point | Constat |
|---|---|
| MCP Roblox Studio | branché ; `screen_capture` renvoie l'image à l'agent mais n'écrit rien sur le disque |
| `screencapture` macOS | refusé (« could not create image from display ») : le terminal n'a pas le droit d'enregistrer l'écran |
| Planches d'images | **résolu sans permission** : l'historique de session garde chaque capture ; `tools/vfxlab/captures.py` les en extrait, `planche.py` les monte |
| Rojo | pas reconnecté après la réouverture de Studio ; le code est poussé dans la place ouverte par un petit serveur de fichiers local (127.0.0.1, lecture seule) et `HttpService` activé **dans la copie locale** `build/Vellum.rbxl` uniquement |

### Système d'effets (déjà bon, on l'étend au lieu d'en créer un autre)

- **Répartition vérifiée** : le serveur ne dessine rien (sauf le mur de la Marge). Il diffuse des paquets `{Id, Origin, Direction, Caster, Params}` (`VfxBroadcaster`, 250 studs), fiables ou non. Chaque client dessine.
- **Client** : `VfxController` → `VfxLibrary` (un rendu par Id) → `VfxTimeline`. Ce dernier est une seule boucle Heartbeat pour toutes les couches, avec un pool d'instances, un budget par palier et une sonde de sol.
  - Autres acteurs : `Feel` (caméra, arrêt, flash de silhouette, image d'impact), `WorldLighting` (post-traitement, flashs d'écran) et `SoundController`.
- **Effets en données** : `VfxTimelineConfig.luau` (39 timelines, 502 couches).
  - 5 phases : Anticipation, Cast, Travel, Impact, Residue.
  - 13 sortes de couches : Carrier, Sprite, Emitter, Beam, Trail, Light, Mark, Mesh, Debris, Afterimage, Shake, Flash, Sound.
- **Ressources** : 17 textures générées, blanches et teintées par pigment. 7 maillages générés (goutte, croissant, ensō, anneau fendu, couronne, deux papiers). 4 voix sonores par pigment.

### Sorts et pigments

| Pigment | Couleur | Contraste sur le vélin / le sol d'entraînement | Sorts |
|---|---|---|---|
| Cinabre | #D93A22 | 3,49 / **1,69** | Marque, Roussi, Ligature, Pâté |
| Indigo | #2E4A8C | 6,46 / 3,13 | Lavis, Bavure, Reliure |
| Terre d'Ombre | #6B4A2F | 6,04 / 2,93 | Empattement, Marge, Rupture, Pointillé, Dorure |
| Vert-de-gris | #4FA88C | 2,19 / **1,06** | Balayage, Délié, Spirale, Poncif |
| Orpiment | #E8C022 | **1,33** / 1,55 | Rature, Insertion, Filigrane, Colophon |

Usage : Marque > Lavis > Balayage > Empattement > Bavure > Marge (le deck de départ), puis Délié et Pointillé (niveau 5). Ultimes : Colophon, Pâté, Rupture.

### Pourquoi c'était plat (mesuré dans le code, puis vu dans le labo)

1. **Aucune lueur possible** :
   - `LightEmission = 0` partout, plafonné à 0,1 par un test.
   - La charte interdisait le cœur lumineux, le Neon et l'additif.
   - Sur un vélin clair, un pigment translucide devient rose ou gris.
2. **Traînée de la Marque** :
   - Texture en mode `Static` avec `TextureLength` resté à 1 : le trait de pinceau se répète **à chaque stud** (les « traits parallèles identiques »).
   - Opacité effective d'environ 30 %, contraste de 1,2 à 1,4.
3. **Gerbes qui partent vers le haut** : 40 émetteurs n'ont jamais reçu de `EmissionDirection` ; les étincelles « vers l'avant » partent vers le ciel.
4. **Impact délavé** : le `PageFlash`, déclenché par l'explosion et par chaque coup, retire **55 % de saturation** à l'écran pendant 0,2 s, pile au moment de l'impact.
5. **Impact à plat** :
   - L'ensō et l'anneau sont posés au sol, épais de 0,09 stud ; depuis la caméra de jeu, ce sont des lignes.
   - Le mannequin ne réagit pas.
6. **Rien ne sort de la main** :
   - Le sort naît à 3–4 studs devant la racine, caché par le corps depuis la caméra de jeu.
   - Le sceau commun est en retard de 0,24 s sur le projectile.
   - Aucun ancrage sur la main.
7. **Désynchronisations visibles** :
   - le Lavis frappe le mannequin à 0,12 s, mais sa vague dessinée n'y arrive qu'à 0,5 s ;
   - les dégâts du Balayage tombent à 0 s, son visuel à 0,16 s.
8. **Pas de réglage flashs** : seul « Secousses de caméra » existe (plus le mouvement réduit de la plateforme).

## Plan (mission du développeur, points de validation délégués : « fais le meilleur choix »)

| Phase | Contenu |
|---|---|
| 1 — des yeux | `EffectClock` / `VfxClock` (temps des effets ralenti ou figé, Studio seulement ; micro-arrêt d'impact en jeu) ; labo `tools/vfxlab/` (lance un sort sur un mannequin, fige à un instant exact, 3 caméras) ; planches « avant » de la Marque, du Lavis et du Balayage |
| 2 — style | 3 styles prototypés sur la Marque, palettes par pigment, choix argumenté ; Bloom proposé à part |
| 3 — Marque finale | recette en couches (cœur, pigment, contour d'encre, secondaire, trace au sol, flash, secousse, son) ; rythme en 3 temps ; impact fort ; réglage flashs/secousses ; notes /5 et au moins deux tours |
| 4 — tous les sorts | skill `.claude/skills/vellum-vfx/`, application sort par sort par lots de 3, planches avant/après |
