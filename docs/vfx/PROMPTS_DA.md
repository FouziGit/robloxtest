# Prompts DA — les 26 corps de glyphes

Ces prompts fabriquent, pour chaque glyphe, les deux images de référence qui ont donné la vague du Lavis et la
boule de la Marque (D-273). Ils traduisent la bible « Encre en volume » : la forme, les couleurs et la taille
de chaque corps viennent d'elle et de la vérité du serveur (`GlyphConfig`, `GlyphEffects`).

**Mode d'emploi.**

1. **Deux images par glyphe.** Le **prompt A** donne une capture en jeu, comme `docs/vfx/wash/ref-1.jpg` : il
   fixe le style et la taille du corps à côté du personnage. Le **prompt B** donne la planche de modélisation
   sur parchemin, comme `docs/vfx/wash/ref-2.jpg` : les vues, les couleurs et les notes pour Blender.
2. **Copier le bloc tel quel** dans le générateur d'images. S'il accepte une image de style, joindre
   `ref-1.jpg` au prompt A et `ref-2.jpg` au prompt B.
3. **Régénérer** si l'image sort de la DA : feu, eau ou fumée réalistes, lueur ailleurs qu'au cœur pâle,
   dégradé, blanc pur, roche, métal, or hors de l'Orpiment, cyan.
4. **Les chiffres font foi, pas l'image.** Un générateur dessine les tailles à peu près : le modèle suit la
   fiche du glyphe dans la bible (§11, et §13 pour le lot 1) et le serveur.
5. **Renvoyer les deux images**, rangées comme celles du Lavis : `docs/vfx/<glyphe>/ref-1.jpg` (A) et
   `ref-2.jpg` (B), où `<glyphe>` est l'identifiant anglais en minuscules (`serif`, `sweep`, `bleed`…).

Pour un glyphe à deux corps (Volute, Chaînette, Pâté, Rubrique, Obèle, Insertion), le prompt A montre le moment
indiqué sous le titre, et la planche B dessine les deux corps.

**Échelle.** Un joueur mesure 6,2 studs (sommet de la tête, bible §4.1) ; les prompts A parlent en « fois sa
taille », les prompts B en studs.

**Palettes** (bible §2) : un aplat par rôle, l'encre est toujours `#17150F`.

| École | Pigment | Cœur pâle | Contour (coque) | Pâle visible |
|---|---|---|---|---|
| Cinabre (Cinnabar) | `#D93A22` | `#F4C8C1` | 0,15 – 0,20 stud | ≤ 12 % |
| Indigo | `#2E4A8C` | `#C4CCDF` | 0,10 – 0,15 stud | ≤ 10 % |
| Terre d'Ombre (Umber) | `#6B4A2F` | `#D6CCC5` | 0,10 – 0,14 stud | ≤ 6 % |
| Vert-de-gris (Verdigris) | `#4FA88C` | `#CEE7DF` | 0,20 – 0,28 stud | ≤ 6 % |
| Orpiment | `#E8C022` | `#F9EDC1` | 0,15 – 0,25 stud + double filet | ≤ 8 % |

---

## Lot 1

### 1. Serif · Empattement

**Terre d'Ombre (Umber)** · Cinq pointes d'encre sortent de la page en ligne droite le long de la visée (à 6,
11, 16, 21 et 26 studs, une toutes les 0,08 s) : 22 dégâts et 0,4 s d'étourdissement.

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar lunges forward, one fist driven down at the flagstones. Five umber ink spikes punch out of the ground in a straight line ahead of him, 0.8 body-heights apart, growing from 0.85 to 1.15 times his height. Each is a letter serif: a faceted hexagonal shaft tapering to a slanted chisel tip, leaning slightly toward the target, on a flat foot of two concave flares lying across the line, like the foot of a Roman capital. Only the farthest has a pale bevel. Ink, never rock. Colours: umber #6B4A2F, pale bevel #D6CCC5, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: UMBER INK SERIF SPIKE. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: SIDE, FRONT, TOP-DOWN, PERSPECTIVE, FOOT DETAIL. One spike: hexagonal faceted shaft, root 0.30 × 0.22 of its height, tapering to 0.07 at 90%, chisel tip cut at 35°, leaning 6° forward, twisted 8°; foot of two concave fillets lying across the stroke (0.44 left, 0.40 right, only ±0.15 deep), squared ends with a tiny hook; top view reads ⊥. Callouts: Umber Base (#6B4A2F), Pale Bevel (#D6CCC5, chisel plane only), Ink Contour (#17150F). Notes for Blender: calligraphic ink geometry, hard edges, inverted-hull contour 0.14–0.25 stud, heavier at the foot, ink groove on the caster-facing facet, never a rock cone; from behind: tapering shaft on its ⊥ foot. Scale: 5.2 to 7.2 studs tall (0.85–1.15 player heights).
```

### 2. Sweep · Balayage

**Vert-de-gris (Verdigris)** · Un seul coup de brosse à plat sur une sphère de 12 studs de rayon centrée 10
studs devant, lanceur compris : 12 dégâts, et chacun est poussé le long de la visée et soulevé.

**A — en jeu**

```text
Roblox game screenshot, three-quarter view from behind and above, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar swings both arms in a wide flat sweep. On the ground in front of him, a verdigris ink wind band curves in a C open toward him, 3.7 times his height across: a flat brush stroke, loaded and rounded at its left end, thinning at its right end into three whips that curl back along the arc. Its outer lip breaks into four rolled hooks that all curl forward, away from him, reaching his waist. The band stays low; no crest, no foam. Colours: verdigris #4FA88C, small pale caps #CEE7DF, ink outline #17150F, no cyan. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: VERDIGRIS INK GUST BAND. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, FRONT, SIDE, PERSPECTIVE, VOLUTE DETAIL. A flat ground band: a 220° ring sector, radius 0.21 to 0.47 of the diameter, open toward the caster; inner edge flush, outer lip 0.10 high at the loaded left head, 0.06 at the right tail, split into three whips curling back along the arc. Four rolled volutes on the outer lip at −75°, −25°, +25°, +75°, all rolling forward, 0.13 high. Callouts: Verdigris Base (#4FA88C), Pale Caps (#CEE7DF, volute tops), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.14–0.28 stud, five uneven flow lines; from behind: flanks and volutes stick out beside the caster. Scale: 23.2 studs across, volutes 3 studs high.
```

### 3. Bleed · Bavure

**Indigo** · Une mare d'encre de 18 studs posée 12 studs devant boit trois fois (à 0, 1 et 2 s, 8 dégâts
chacune) et ralentit à 40 % pendant 2,5 s ; elle est reprise si le lanceur meurt, part, garde ou est étourdi.

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar pushes one open palm down toward the ground. Two body-heights ahead lies a ring-shaped puddle of wet indigo ink, almost three times his height across, ankle-high, cut into hard flat facets, its centre empty so the flagstones show through. Nine hooked fingers run out to an exact round rim, four loose beads between them. On the far side only, seven hollow ink tendrils rise to knee height and curl back toward the centre like closing fingers. Flow lines spiral inward. Not a cloud. Colours: indigo #2E4A8C, pale #C4CCDF on finger crests and tendril curves, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: INDIGO INK BLEED POOL. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, SIDE, FRONT, PERSPECTIVE, TENDRIL SECTION. A ring of ink from radius 0.25 to 0.40 of the diameter, centre empty; a meniscus 0.02–0.033 high cut into 8–10 hard planes; nine tapering capillary fingers of unequal lengths hooked exactly at the rim; four detached beads. Seven hollow three-sided tendrils on the far 160° arc only, 0.09–0.13 high, curling toward the centre. Callouts: Indigo Base (#2E4A8C), Pale Sheen (#C4CCDF, finger crests, tendril curves), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.12–0.18 stud, seven inward-spiralling flow lines, no tendril on the caster's side; from behind: thick rim and hooked fingers framing both sides. Scale: 18 studs across (2.9 player heights), tendrils 1.6–2.4 studs.
```

### 4. Scorch · Roussi

**Cinabre (Cinnabar)** · Un anneau de feu de 26 studs suit le lanceur et brûle tout ce qui est dedans à 0, 0,8
et 1,6 s (10 dégâts chaque fois).

**A — en jeu**

```text
Roblox game screenshot, high three-quarter view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar stands in the centre, arms spread low, palms down. Around him, a crown of twelve cinnabar ink flame tongues stands on a thin ink ring on the ground, the ring four times his height across. Tongues alternate long (half his height) and short (a third), each a comma: narrow root, wider above the middle, sharp tip with a final hook; every hook curls the same way, like a pinwheel seen from above. The tongues are flat blades leaning slightly outward, each with a pale streak inside it. Colours: cinnabar #D93A22, pale streak #F4C8C1, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: CINNABAR INK FLAME CROWN. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, SIDE, FRONT, PERSPECTIVE, TONGUE DETAIL. A closed thin base ring (radius 0.466–0.494 of the diameter) carrying twelve hooked tongues, alternating 0.123 and 0.085 high. Each tongue: flat slab section, narrow root on the ring's inner half, widest at 60% height, sharp tip with a tangential hook; all hooks curl the same way; leaning out ≤8°, face turned 30° toward the tangent. Callouts: Cinnabar Base (#D93A22), Pale Streak (#F4C8C1, both faces of each tongue, thin line on the ring), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.1–0.2 stud; nothing beyond radius 0.5; from behind: blades at every angle, never slivers. Scale: 26 studs across, tongues 2.2 and 3.2 studs.
```

### 5. Rupture

**Terre d'Ombre (Umber)** · Ultime : la page cède autour du lanceur ; 35 dégâts à tout ce qui est à moins de
18 studs, projeté droit vers le haut et étourdi 0,8 s.

**A — en jeu**

```text
Roblox game screenshot, high three-quarter view from behind, sunny stone castle courtyard with flagstones. A blocky Roblox avatar crouches, fists slammed into the ground. Around him the page breaks into a horseshoe crown of umber ink blades almost six times his height across, open behind him: four tall blades (1.3 to 1.5 times his height) near him at the diagonals and sides, six medium blades further out, six teeth on the rim, none straight ahead. Each blade, a bevelled pen stroke, twists a quarter turn rising and ends in a sideways hook, a pale lobe under it; torn paper flaps at the roots. Dummies fly straight up. Colours: umber #6B4A2F, pale #D6CCC5, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: UMBER INK DOWNSTROKE CROWN. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, FRONT, SIDE, PERSPECTIVE, BLADE DETAIL. Horseshoe of 16 blades, nothing within 40° of the rear: 4 tall (0.22–0.26 of the diameter) at ±50° and ±110°, radius 0.17–0.22; 6 medium (0.11–0.17) at ±25°, ±75°, ±130°, radius 0.31–0.39; 6 rim teeth (0.04–0.07) at radius 0.43–0.49. Each blade: four-sided lens section, square bevelled root lip, quarter-turn twist, tangential hooks all turning one way. Torn page flaps at roots, low collar around the caster. Callouts: Umber Base (#6B4A2F), Pale Lobe (#D6CCC5, under each hook), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.11–0.14 stud, dark crack mouths at roots; from behind: nothing between camera and caster. Scale: 36 studs across, tall blades 8–9.5 studs.
```

---

## Lot 2

### 6. Hairline · Délié

**Vert-de-gris (Verdigris)** · Une lame de vent rapide (130 studs/s, 0,6 s au plus) : le premier touché prend
14, est repoussé et marqué Éventé (le prochain coup de Cinabre lui fait × 1,25).

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar follows through a backhand slash, arm whipped across his body. A few steps ahead, a verdigris ink wind sickle flies away from him, tilted 35°: a single thick-thin pen stroke almost as wide as he is tall, swollen in the middle, tapering to hair-thin points that curl back toward him, a thin pale thread just inside its leading edge, three short whips trailing behind. Seen edge-on it is razor thin. Colours: verdigris #4FA88C, pale thread #CEE7DF, ink outline #17150F, no cyan. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: VERDIGRIS INK WIND SICKLE. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT (along the flight), SIDE (edge-on), TOP-DOWN, PERSPECTIVE, CROSS-SECTION. A lens-shaped crescent, camber 0.35: swollen in the middle, tapering to a hair at both tips, tips curled back toward the caster; rolled −35° about the flight axis. A pale thread along the leading edge; three short whips, at most 2 studs, trailing from the back edge. Callouts: Verdigris Base (#4FA88C), Pale Edge (#CEE7DF), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.2–0.28 stud, never under 0.1 at the tips; from behind the caster: a tilted sickle with tips curling back, the thinnest glyph in profile. Scale: 5.6 studs tip to tip (0.9 player height), inside a 7-stud hit sphere.
```

### 7. Stipple · Pointillé

**Terre d'Ombre (Umber)** · Crache une balle de boue rapide (110 studs/s) : le premier touché prend 16 et est
ralenti à 60 % pendant 2 s.

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar flicks one hand forward from the hip, like skipping a stone. In the air ahead of him flies a slug of umber mud ink, about 0.4 times his height long: a smooth stretched teardrop, round head forward, dark belly, two wet pale gloss spots on top, followed by a dotted line of three detached round beads shrinking behind it and two short squirts. Smooth, not faceted, not a rock. Colours: umber #6B4A2F, pale gloss #D6CCC5, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: UMBER INK MUD SLUG. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: SIDE, FRONT (along the flight), TOP-DOWN, PERSPECTIVE, BEAD CHAIN DETAIL, plus a SPLAT inset for the impact. A smooth turned teardrop, round head forward, dark belly underneath, two wet pale gloss lobes on top; behind it a chain of three detached round beads shrinking with distance, and two short squirts curling off the tail. Callouts: Umber Base (#6B4A2F), Pale Gloss (#D6CCC5), Ink Contour (#17150F). Notes for Blender: calligraphic ink geometry, smooth (the one Umber body without facets: mud, not a boulder), inverted-hull contour 0.1–0.14 stud, each bead with its own hull; from behind: round head, gloss lobes and the bead chain trailing toward the camera. Scale: 2.6 studs long (0.4 player height).
```

### 8. Margin · Marge

**Terre d'Ombre (Umber)** · Dresse un mur de boue de 14 × 9 × 2,5 studs, 8 studs devant, pendant 6 s : il
barre le passage et arrête les projectiles.

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar heaves both palms upward and forward. Just ahead of him stands a wall drawn as a single broad umber ink pen stroke set on edge, more than twice his height wide, one and a half times his height tall, 0.4 times his height thick: a round blunt head on the left, a swelling full stroke, a dry tail splitting into three strands on the right, a rolled lip along the top capped with five pale lobes, ink flow lines running down its faces like mud strata. Not bricks. Colours: umber #6B4A2F, pale lobes #D6CCC5, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: UMBER INK RULE WALL. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT, BACK, TOP-DOWN, SIDE, PERSPECTIVE, LIP SECTION. A sleeve wrapping a 14 × 9 × 2.5 stud slab within 0.05 stud, both faces finished: round head on the left, a swelling full stroke, a dry tail split into three strands on the right; a rolled bead along the top capped with five pale lobes; flow lines running down like mud strata. Callouts: Umber Base (#6B4A2F), Pale Lobes (#D6CCC5), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.1–0.14 stud, no brick or stone; from behind, the caster sees the back face: head, tail and lobed bead. Scale: 14 studs wide, 9 tall (1.45 player heights), 2.5 thick.
```

### 9. Ligature

**Cinabre (Cinnabar)** · Un court élan (20 studs en 0,25 s) qui laisse cinq flaques brûlantes ; chacune brûle
toutes les 0,4 s, au plus deux fois par ennemi (6 dégâts).

**A — en jeu**

```text
Roblox game screenshot, side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar finishes a forward dash, leaning low, one arm trailing. Behind him, along his path, lies a cinnabar ink ribbon on the ground, four times his height long and up to one and a half wide: loaded and blunt where the dash began, drying into split strands under his feet. On it sit five evenly spaced knots of three or four hooked flame tongues, tallest at the start (three quarters of his height), shortest near him (a third). Each tongue is a flat comma with a pale streak inside. Colours: cinnabar #D93A22, pale streak #F4C8C1, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: CINNABAR INK BURNING TIE. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, SIDE, FRONT, PERSPECTIVE, KNOT DETAIL. A ribbon along the dash path, 26 studs long, up to 9 wide: loaded head at the start, dry tail splitting into strands at the end. Five knots of 3–4 hooked flame tongues, one on each burning pool, 4 studs apart, heights dropping 4.5 to 2 studs. Tongues: flat commas, narrow root, widest at 60%, hooked sharp tip. Callouts: Cinnabar Base (#D93A22), Pale Streak (#F4C8C1, both tongue faces), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.2 stud; from behind: the camera looks over the low last knots; the tall first ones frame the path. Scale: tallest knot 0.7 player height.
```

### 10. Volute

**Indigo** · Charge 0,4 s une spirale d'encre dans la main, puis la plaque sur l'ennemi le plus proche, 4 studs
devant : 24 dégâts, projeté loin et étourdi 0,4 s.
*Deux états du même corps : A montre le coup, B la charge et le coup.*

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar drives his right palm forward at chest height into a blocky training dummy. Pressed flat against the impact point is a flat indigo ink spiral as wide as he is tall: a logarithmic ribbon of two and a half turns with hard facets, more air than ink, a pale round eye at its centre, its outer turn ending in a hook. The dummy is hurled backward, seen through the gaps of the spiral. Colours: indigo #2E4A8C, pale eye #C4CCDF, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: INDIGO INK VOLUTE COIL. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT (facing the caster), SIDE, TOP-DOWN, PERSPECTIVE, plus a CHARGE-ON-SHOULDER inset. A flat logarithmic spiral ribbon of 2.5 turns, hard facets, wide gaps between turns, a domed pale eye at the centre, the outer turn ending in a hook. Charge: on the right shoulder, facing the caster, winding from 0.5 to 2.4 studs. Strike: pressed flat 6 studs across on the target, then closing into its eye. Callouts: Indigo Base (#2E4A8C), Pale Eye (#C4CCDF), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.1–0.15 stud, air between turns so the target shows through; from behind: the coil faces the caster's camera. Scale: 2.4 studs in hand, 6 studs on impact (one player height).
```

### 11. Binding · Reliure

**Indigo** · Saisit l'ennemi le plus proche dans un rayon de 7 studs autour d'un point 8 studs devant : 10
dégâts, et il est enraciné 1,5 s (il peut encore se battre).

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar pulls one clenched fist back toward his chest, as if tightening a rope. Ahead, another blocky avatar is caught: six indigo ink cords burst from a splash rosette on the ground around its feet and wind half a turn around its body, knotting just above its head into a cage as tall as the avatar, with a pale foam crown on the knot. The cords are flat lens-section ribbons with wide gaps, so the prisoner stays clearly visible. Colours: indigo #2E4A8C, pale foam #C4CCDF, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: INDIGO INK BINDING CORDS. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT, SIDE, TOP-DOWN, PERSPECTIVE, KNOT DETAIL. Six nerve cords with flat lens sections rise from a small splash rosette on the ground, each winding half a turn around a stretched sphere and tying together above the head; a crown of pale foam lobes on the knot. Gaps between cords at least 1.5 studs. Callouts: Indigo Base (#2E4A8C), Pale Foam (#C4CCDF, knot crown), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.1–0.15 stud, tapering cords with buried roots; add a no-catch variant where the cords lash and drop; from behind: the cage and knot read around a visible prisoner. Scale: cage 5.2 studs wide, 6.2 tall (one player height).
```

---

## Lot 3

### 12. Swash · Paraphe

**Terre d'Ombre (Umber)** · Un paraphe d'encre file au ras du sol à 75 studs/s, jusqu'à 45 studs : 20 dégâts
à tout ce que sa boîte de 12 × 5 traverse, poussé le long de la visée, jusqu'au premier mur.

**A — en jeu**

```text
Roblox game screenshot, three-quarter view from behind and to the side, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar finishes a low two-handed underhand sweep. Racing away from him along the ground runs a standing blade of umber ink, twice his height wide and three quarters of his height tall: arched, middle forward and both horns swept back, thick at the foot, thin at the top, each horn closing into a looped signature flourish, a skid scraping the flagstones, three whips trailing behind. A pale thread runs just below its top edge. Colours: umber #6B4A2F, pale thread #D6CCC5, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: UMBER INK SWASH BLADE. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT, TOP-DOWN, SIDE, PERSPECTIVE, HORN LOOP DETAIL, plus a SLUMPED inset for the wall hit. A standing sheet swept along an arched line, middle forward, horns back; thick at the foot, thin at the top; each horn rolls into a closed paraph loop; a low skid along the base; three whips trailing. Callouts: Umber Base (#6B4A2F), Pale Thread (#D6CCC5, just inside the top edge), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.1–0.14 stud, heavier at the foot; width exactly 12 studs, never more; from behind: both looped horns stick out beside the caster. Scale: 12 studs wide (two player heights), 4.6 tall.
```

### 13. Pounce · Poncif

**Vert-de-gris (Verdigris)** · Une zone de 26 studs posée 14 studs devant : 3 ticks de 5 dégâts toutes les
0,9 s, chacun ralentit à 70 % pendant 1,5 s. Rien n'aveugle.

**A — en jeu**

```text
Roblox game screenshot, high three-quarter view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar flings an open hand forward, fingers spread, as if scattering powder. Two body-heights ahead, a circle of ground four times his height across is dusted into raked verdigris dunes: three rings of broken arcs, each with a gentle slope on one side, a steep drop on the other and a dry hooked end, plus two dotted curves of small round heaps like a pricked stencil pattern. Nothing rises above his ankle. Pale crests, heavy outlines. No cloud, no sandstorm. Colours: verdigris #4FA88C, pale crests #CEE7DF, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: VERDIGRIS INK POUNCE DUNES. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, SIDE, FRONT, PERSPECTIVE, DUNE PROFILE SECTION. Bas-relief lines lying on the ground: three concentric rings of broken arcs with a dune profile (gentle windward slope, steep lee side, dry hooked tip) and two dotted curves of small round heaps, a pricked pattern. Height at most 0.04 of the diameter. Callouts: Verdigris Base (#4FA88C), Pale Crest (#CEE7DF, a line along each crest), Ink Contour (#17150F, heavy). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.2–0.28 stud, no rotation, never a cloud; from behind: the broken ring edges read across the ground. Scale: 26 studs across, at most 1 stud high (ankle height).
```

### 14. Gilding · Dorure

**Terre d'Ombre (Umber)** · Durcit le lanceur pendant 4 s : 40 % de dégâts en moins et aucun recul.

**A — en jeu**

```text
Roblox game screenshot, three-quarter front view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar stands braced, fists clenched at his sides, chin up. Around his legs, below the hip, closes a collar of six upright umber plates like tooled leather, about half his height tall, with crisp facets, a pale burnished edging set just inside each rim, a stamped diamond fleuron and two ink fillet lines on each plate, small gaps between plates. No gold, no metal: flat brown ink. Colours: umber #6B4A2F, pale edging #D6CCC5, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: UMBER INK LEATHER IRONS. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT, TOP-DOWN, SIDE, PERSPECTIVE, SINGLE PLATE DETAIL. A ring of six upright leather-like plates around an avatar's legs, crisp facets, each with a pale burnished edging inset from its rim, a stamped diamond fleuron and two ink fillets; narrow gaps between plates. Callouts: Umber Base (#6B4A2F), Pale Burnish (#D6CCC5), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.1–0.14 stud, NO gold and no metal (gold belongs to Orpiment); plates hinge outward to fall at the end; from behind: the plates read as a collar under the caster's hip. Scale: 4.8 studs across, 3.2 tall (half a player height), top under the hip.
```

### 15. Hatching · Hachures

**Cinabre (Cinnabar)** · Une rafale canalisée : 5 traits toutes les 0,34 s dans une boîte de 6 × 6 sur 7 studs
devant (5 dégâts et un ralentissement chacun) ; le dernier projette et étourdit 0,4 s.

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar slashes diagonally with one arm, mid-flurry, a blocky training dummy just in front of him. Across the space in front of him cuts one engraved cinnabar stroke: a long straight lens, longer than he is tall, swollen in the middle and needle-thin at both ends, a pale thread along its ridge, slanted 41° across the target. It is a burin cut, not a flame: no tongues, no flicker. Colours: cinnabar #D93A22, pale thread #F4C8C1, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: CINNABAR INK HATCH CUT. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: SIDE, FRONT, TOP-DOWN, PERSPECTIVE, CROSS-SECTION, plus a diagram of the five cuts crossing at ±41°. One straight lens, no camber: swollen in the middle, needle-thin at both ends, a sharp ridge carrying a pale thread. Four cuts 7–7.6 studs long; the fifth 8.2 studs and thicker, along the full diagonal of a 6 × 6 stud box in front of the caster. Callouts: Cinnabar Base (#D93A22), Pale Thread (#F4C8C1, on the ridge), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.2 stud, never under 0.1 at the tips, no flame tongues; from behind: the ends pass beyond the caster's silhouette on both sides. Scale: 7–8.2 studs long (1.1–1.3 player heights).
```

### 16. Spiral · Spirale

**Vert-de-gris (Verdigris)** · Un tourbillon de 22 studs posé 14 studs devant : 4 ticks de 6 dégâts toutes les
0,6 s, qui tirent tout le monde vers son centre.

**A — en jeu**

```text
Roblox game screenshot, high three-quarter view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar hauls both hands back toward his chest, as if pulling a rope. Two body-heights ahead, a shallow verdigris ink whirlpool bowl three and a half times his height across lies on the ground: seven spiral arms, thick and shin-high at the rim, thinning and splitting into dry strands as they pour into a flat ink eye one body-height across, five hooks curling inward on the rim. The arms clearly flow inward, like water down a drain. Two dummies slide toward the eye. Never a tornado. Colours: verdigris #4FA88C, pale #CEE7DF, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: VERDIGRIS INK SPIRAL BOWL. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN with spin arrow, SIDE, FRONT, PERSPECTIVE, ARM SECTION. A shallow bowl of seven logarithmic spiral arms: loaded and 1.6 studs high at the rim, thinning and splitting into dry strands at the eye (radius 3 studs); five hooks curling inward on the rim; the eye a flat ink disc. Arms curve so that, spinning counter-clockwise seen from above, they pour into the eye. Callouts: Verdigris Base (#4FA88C), Pale Crest (#CEE7DF), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.2–0.28 stud, arms r = r0·e^(bθ) with b > 0; from behind: rim hooks and inward flow read at a glance; never a tornado. Scale: 22 studs across (3.5 player heights).
```

### 17. Stitch · Chaînette

**Vert-de-gris (Verdigris)** · Lance un point de couture (100 studs/s, 32 studs) : le premier touché prend 10,
est tiré à 4 studs du lanceur en 0,35 s et enraciné 0,8 s.
*Deux corps : A montre la manille à la prise, B la maille en vol et la manille.*

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar yanks one arm back over his shoulder, like reeling in a line. A few steps ahead, another blocky avatar is caught at the waist by a verdigris ink shackle: three interlocking flat ribbon loops, each thick on one side and thin on the other, closed tight around its waist, about half its height across, dragging it toward him. Colours: verdigris #4FA88C, pale #CEE7DF, ink outline #17150F, no cyan. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: VERDIGRIS INK STITCH LOOP & SHACKLE. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Two bodies, each in SIDE, FRONT, TOP-DOWN and PERSPECTIVE views. Loop (flight): a teardrop loop of flat broad-nib ribbon, thick on the downstroke, thin at the crossing, closed around a dark eye, a needle point leading; it twists fast about the flight axis. Shackle (catch): three interlocking loops closing around a waist from 3.6 to 3.2 studs across. Callouts: Verdigris Base (#4FA88C), Pale Core (#CEE7DF), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.2–0.28 stud; from behind: the loop's dark eye and needle, then the shackle around the victim. Scale: loop at least 2.6 studs long, inside a 6-stud hit sphere.
```

---

## Lot 4

### 18. Blot · Pâté

**Cinabre (Cinnabar)** · Ultime : une lourde bombe d'encre lobée (55 studs/s, cloche de 20 studs) qui éclate au
premier contact ou au bout de 1,4 s : 40 dégâts sur 10 studs de rayon, repoussés, gardes brisées.
*Deux corps : A montre la Larme en vol, B la Larme et l'étoile de l'éclat.*

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar follows through an overhand lob, arm high. Above the courtyard, diving head first along a high arc toward a group of dummies, flies a heavy cinnabar ink teardrop about two thirds of his height long: a head cut into flat planes, a wet pale lobe on top, a dark belly, and five whips spiralling behind it, each ending in a round bead, never a point. It turns slowly. Colours: cinnabar #D93A22, pale lobe #F4C8C1, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: CINNABAR INK TEARDROP & BLOT STAR. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Two bodies, each in SIDE, FRONT, TOP-DOWN and PERSPECTIVE views. Teardrop (flight): head cut into flat planes, wet pale lobe on top, dark belly, five whips spiralling behind, each ending in a round bead, never a point. Blot (burst): a 3D ink star of nine arms, three rising, round beads exactly on a 10-stud-radius sphere. Callouts: Cinnabar Base (#D93A22), Pale Lobe (#F4C8C1), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.2 stud, each bead with its own hull; must not read as the Brand fireball (round head, beads, no hooked tongues); from behind: beaded whips trailing toward the camera. Scale: teardrop 4.2 studs long, star 20 studs across.
```

### 19. Dagger · Obèle

**Vert-de-gris (Verdigris)** · Disparaît et réapparaît 3 studs derrière l'ennemi le plus proche devant soi
(25 studs, cône de 35°) et frappe son dos : 14 dégâts, avec 0,2 s d'invulnérabilité.
*Deux corps : A montre l'obèle planté, avec la rature de départ au fond ; B les deux.*

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar has just reappeared behind another blocky avatar and strikes its back with an open palm. Between them, planted point-down in the flagstones, stands a verdigris ink obelus dagger † as tall as he is: a diamond-section pen blade, a crossguard with serifed ends at shoulder height, a teardrop pommel on top, a small ink splash rosette where the point enters the ground. Far behind, a vertical ink stroke crosses out the spot he left. Colours: verdigris #4FA88C, pale #CEE7DF, ink outline #17150F, no cyan. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: VERDIGRIS INK OBELUS DAGGER. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT, SIDE, TOP-DOWN, PERSPECTIVE, GUARD DETAIL, plus a STRIKE-OUT inset. A dagger cross † planted point-down: diamond-section pen blade tapering to the point, crossguard with serifed ends at shoulder height, teardrop pommel; a small splash rosette at the point. Inset: a vertical triangular-section pen stroke that crosses out the spot the caster left. Callouts: Verdigris Base (#4FA88C), Pale Thread (#CEE7DF, inside the blade's ridge), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.2–0.28 stud; from behind: the † silhouette between caster and target, guard ends sticking out. Scale: 6 studs tall (one player height), guard at shoulder height.
```

### 20. Emboss · Gaufrage

**Terre d'Ombre (Umber)** · La page se repousse depuis le lanceur : 24 dégâts à tous ceux qui sont à moins de
13 studs, projetés à l'horizontale, sans étourdissement.

**A — en jeu**

```text
Roblox game screenshot, high three-quarter view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar flings both arms outward from a crouch. Around him the ground is pushed up from below into an expanding umber ink ring, about four times his height across and only shin-high: a raised bulge with two bevelled steps and sixteen notches leaning outward, each with a pale bevel. Dummies are thrown outward horizontally. Low and flat, not a crown of blades. Colours: umber #6B4A2F, pale bevels #D6CCC5, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: UMBER INK EMBOSSED RING. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, SIDE, FRONT, PERSPECTIVE, RING SECTION. A closed ring bulge with two bevelled steps and sixteen notches leaning outward, each with a pale bevel. Two states: born around the caster's shins (3 studs across, 3.3 tall), then racing out to 12.8 studs radius while lowering to 1.65 studs. Callouts: Umber Base (#6B4A2F), Pale Bevel (#D6CCC5, sixteen bevels), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, flat facets, inverted-hull contour 0.1–0.14 stud, no stone; must stay lower and shorter than the Rupture crown; from behind: the notched lip reads all around. Scale: 25.6 studs across at full size, 1.65 tall (a quarter player height).
```

### 21. Rubric · Rubrique

**Cinabre (Cinnabar)** · Immobile 0,7 s pour charger, puis règle un trait rouge épais droit devant, jusqu'à 85
studs : 25 dégâts à trois ennemis au plus, poussés le long de la visée.
*Deux corps : A montre la barre, B le bouton de la charge et la barre.*

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar stands planted, both hands thrust forward together at chest height. From his hands to the far wall runs a heavy cinnabar ink rule: a straight bar almost as wide as he is tall and a quarter of his height thick, with a round belly, a bevelled head with small horns at his hands, and three pale lobes where it pierces three dummies in a row. Colours: cinnabar #D93A22, pale lobes #F4C8C1, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: CINNABAR INK RUBRIC BUD & BAR. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Two bodies, each in SIDE, FRONT, TOP-DOWN and PERSPECTIVE views. Bud (charge): six hooked petals folded inward over a pale heart, 2.6 studs, held in both hands. Bar (release): a straight rule modelled at length 1 along the aim, a constant round-belly section 5.6 studs wide and 1.7 tall, a pressed bevelled head with horns, three pale lobes along it. Callouts: Cinnabar Base (#D93A22), Pale Heart and Lobes (#F4C8C1), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.2 stud; the constant section lets the bar stretch to any reach, up to 85 studs; from behind: the bar's round belly end-on, the bud facing the camera. Scale: bar 0.9 player height wide.
```

### 22. Cartouche

**Indigo** · Ultime : un cadre d'encre de 32 studs autour du point de lancer ; un sceau de 28 dégâts qui étourdit
0,4 s, puis 5 ticks de 4 toutes les 0,8 s qui ralentissent ; dedans, les autres glyphes du lanceur rechargent
deux fois plus vite.

**A — en jeu**

```text
Roblox game screenshot, high three-quarter view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar presses one open palm flat onto the flagstones, like stamping a seal. Around him, five times his height across, rises an ornamental title-page frame of twelve standing indigo ink leaves on an exact circle, each less than half his height, each rolling its top lip inward into a scroll with pale foam on the roll and a dark ink hollow inside it, small notches between the leaves: a frame of pieces, not a solid wall. Colours: indigo #2E4A8C, pale foam #C4CCDF, ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: INDIGO INK SCROLLWORK FRAME. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN, SIDE, FRONT, PERSPECTIVE, LEAF SECTION. Twelve standing ink leaves on circle segments, outer ink exactly at radius 16 studs, each thick at the foot and thin at the lip, the lip rolling inward into a volute; pale foam capping each roll, an ink hollow inside it, a notch between neighbouring leaves. Callouts: Indigo Base (#2E4A8C), Pale Foam (#C4CCDF, on the rolls), Ink Contour (#17150F). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.1–0.15 stud, nothing beyond radius 16; the volutes tighten then relax on each tick; from behind (the camera stands inside the ring): the inward rolls show foam and hollow. Scale: 32 studs across (5.2 player heights), leaves 2.6 studs tall.
```

---

## Lot 5

### 23. Strike · Rature

**Orpiment** · Un tir instantané jusqu'à 70 studs : le premier ennemi sur la ligne prend 22 et est repoussé.

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar whips his right arm straight forward, two fingers pointed like a pen. From his hand to the far wall, at hip height, runs a gold ink strike-through: a flat straight blade a third of his height wide, pressed at the head, its far end flicking upward like a lifting pen, a double black ink line along each side of its ridge, a pale warm thread on its first half. A dummy is knocked back. Colours: orpiment gold #E8C022, flat, not metallic; pale thread #F9EDC1; ink outline #17150F, which does the drawing. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: ORPIMENT INK STRIKE-THROUGH. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: SIDE, TOP-DOWN, FRONT (end-on), PERSPECTIVE, HEAD AND TAIL DETAIL. A straight ruled stroke modelled at length 1 along the aim: lens section with a ridge, constant along its body; head pressed over the first 3%; the last 5% a whip-flick that lifts. A double ink fillet on each side of the ridge, a pale thread over the first 60%. Callouts: Orpiment Gold (#E8C022, flat, not metallic), Pale Thread (#F9EDC1), Ink Contour (#17150F, heavy). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.25 stud; the constant section stretches to any reach; from behind: a long gold line receding, double fillet visible. Scale: 2.2 studs wide, at hip height, up to 70 studs long.
```

### 24. Caret · Insertion

**Orpiment** · Se téléporte jusqu'à 18 studs devant ; intouchable 0,4 s à l'arrivée.
*Deux corps : A montre le ^ à l'arrivée, avec la rature de départ au fond ; B les deux.*

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar lands in a crouch after a teleport. A tall gold ink caret ^ frames him: two pen strokes meeting just above his head, their feet planted on either side of him, a little less than his height apart, the rising stroke thin, the falling stroke thick with a serif foot. Far behind, on the spot he left, a horizontal gold ink bar crosses out the ground. Colours: orpiment gold #E8C022, flat, not metallic; pale thread #F9EDC1; ink outline #17150F, which does the drawing. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: ORPIMENT INK CARET. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT (from the caster's camera), SIDE, TOP-DOWN, PERSPECTIVE, plus a STRIKE-OUT inset. A caret ^ of two straight pen strokes: a thin rising hairline and a thick falling full stroke with a serif foot; feet 5 studs apart, 2.5 on each side of the caster; apex just above his head; no spin. Inset: a short horizontal triangular-section stroke crossing out the departure spot. Callouts: Orpiment Gold (#E8C022, flat), Pale Thread (#F9EDC1, inside the thick stroke), Ink Contour (#17150F, double fillet). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.25 stud; from behind: the caster's camera looks through the caret's opening, both strokes framing him. Scale: player 6.2 studs tall, standing between the feet.
```

### 25. Watermark · Filigrane

**Orpiment** · Une forme de papetier pressée au sol, 24 studs de large, 13 studs devant : 4 ticks de 6 dégâts
toutes les 0,7 s, chacun étourdit 0,18 s.

**A — en jeu**

```text
Roblox game screenshot, high three-quarter view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar presses both palms down and forward, as if stamping. Two body-heights ahead, a papermaker's mould of gold ink wire lies in low relief on the ground, almost four times his height across: a twisted two-strand rim on an exact circle, four C-scrolls, a central rosette of five loops and small granulation beads, bare ground everywhere between the wires. Each wire has a pale line and a heavy black outline. Ankle-high at most. Colours: orpiment gold #E8C022, flat, not metallic; pale line #F9EDC1; ink outline #17150F. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: ORPIMENT INK WATERMARK MOULD. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: TOP-DOWN (the emblem), SIDE, FRONT, PERSPECTIVE, WIRE SECTION. Round three-sided wire in bas-relief: a two-strand twisted rim exactly at radius 12 studs, four C-scrolls, a five-loop rosette, granulation beads along the curves; open ground between all wires. Height at most 0.04 of the diameter. Callouts: Orpiment Gold (#E8C022, flat), Pale Line (#F9EDC1, on each wire), Ink Contour (#17150F, heavy). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.25 stud, no spin; it rises, then presses flat on each of four identical ticks; from behind: the twisted rim and scrolls read across the ground. Scale: 24 studs across (3.9 player heights), under 1 stud high.
```

### 26. Colophon

**Orpiment** · Ultime : une signature frappe le premier ennemi en ligne (jusqu'à 60 studs), puis saute à deux
autres, chacun à moins de 26 studs du précédent : 40 dégâts chacun, repoussés et étourdis 0,6 s.

**A — en jeu**

```text
Roblox game screenshot, three-quarter side view, sunny stone castle courtyard with flagstones and archery targets. A blocky Roblox avatar flourishes one arm in a wide signing gesture, two fingers extended. A thin gold signature trail leaps from his hand to three blocky avatars in turn. Around each of them a gold ink knot is tied, taller than they are: an ellipse at the waist, two loops crossing at ±35° over the body, a flourish tail rising above the head, thick full strokes and thin hairlines, a round ink dot at each pen lift. Colours: orpiment gold #E8C022, flat, not metallic; pale thread #F9EDC1; ink outline #17150F, which does the drawing. Cel-shaded, thick black ink outlines, flat colours, calligraphic ink shapes, no glow except the pale core, no realistic fire/water/smoke.
```

**B — planche**

```text
3D MODEL SHEET: ORPIMENT INK CADEL KNOT. STYLE: CEL-SHADED WITH THICK OUTLINES. Annotated concept sheet on aged parchment, hand-lettered labels with arrows. Views: FRONT, SIDE, TOP-DOWN, PERSPECTIVE, CROSSING DETAIL. A closed 3D knot path of broad-nib ribbon around a standing avatar: an ellipse at the waist, two loops crossing at ±35°, a paraph tail above the head; thick on the downstrokes, thin at the crossings; an ink dot at each pen lift. Callouts: Orpiment Gold (#E8C022, flat), Pale Thread (#F9EDC1), Ink Contour (#17150F, heavy). Notes for Blender: calligraphic ink, hard edges, inverted-hull contour 0.15–0.25 stud; the showcase piece of the Orpiment pass; it tightens during the stun, then unties and flies off; from behind: the crossed loops and the tail read around the victim. Scale: 8.5 studs tall (1.4 player heights).
```
