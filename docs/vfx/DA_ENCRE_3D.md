# DA « Encre en volume » — la bible des corps de glyphes

> La direction artistique choisie par le développeur (D-273), étendue aux **26 glyphes** encore dessinés à
> l'ancienne. La Marque et le Lavis l'ont déjà : ce sont les deux corps de référence.
> Document de travail, 1er octobre 2026. Rien ici n'est téléversé et aucun chiffre de gameplay ne bouge.
> Chaque modèle passe d'abord par `tools/meshes/preview.py`. Le téléversement attend l'accord explicite du
> développeur, et le corps est ensuite jugé au labo Studio (skill `vellum-vfx`).

## Sommaire

0. Mode d'emploi
1. Le look en une page
2. Trois tons et un contour
3. Une famille, cinq écoles : le vocabulaire des formes
4. L'échelle : la vérité du serveur
5. Le mouvement, temps par temps
6. Ce qui reste en particules
7. Les budgets
8. Le kit de volumes partagé (K0 à K11)
9. Les corps sur mesure
10. Ce que le rendu doit apprendre (R1 à R8, outils, tests)
11. Les 28 glyphes
12. Les lots de construction
13. Fiches de modélisation : lot 1
14. Validation et questions ouvertes

---

## 0. Mode d'emploi

| Qui | Lit d'abord | Pour |
|---|---|---|
| Le développeur | §1, §3, §11, §12, §14 | valider le look, l'ordre des lots et les questions ouvertes |
| La session qui modélise | §2, §4, §8, la fiche du glyphe (§11), sa fiche de modélisation (§13) | écrire la recette Python et la planche |
| La session qui intègre | §5, §6, §7, §10 | écrire la timeline et les changements du rendu |
| Le juge | §1, §4.3, la grille du skill | noter au labo |

Ce qui fait foi : le **serveur** (`src/server/Effects/GlyphEffects.luau`, `src/shared/Config/GlyphConfig.luau`)
décide de la taille, de la place et de la durée. Le **skill** `.claude/skills/vellum-vfx/` fixe la méthode
et le labo. **Ce document** fixe la forme. En cas de désaccord, le serveur a raison et le corps se corrige.

Le contrat ne se négocie pas. Aucun chiffre de gameplay ni aucun temps du serveur ne bouge. On dessine la
vérité : un corps est exactement là où est le mal, aussi grand que lui, jamais au-delà, et une zone dure
exactement le temps où le serveur la fait tiquer. Le corps se lit depuis la caméra du lanceur, par-dessus son
épaule. Il tient dans les budgets (≤ 12 couches, plafonds de triangles) au niveau Performance.

---

## 1. Le look en une page

**Un glyphe est un trait de plume qui a pris de l'épaisseur.** Ce n'est ni une énergie, ni un objet, ni une
roche : c'est de l'encre et du pigment, dessinés en cel-shading. Il a trois aplats et un contour d'encre épais,
et il est surtout fait d'air. Il a la forme et la taille exactes du mal qu'il fait, et il ne vit que le temps
où il fait mal.

**Les références du développeur.** Pour l'eau, `docs/vfx/wash/ref-1.jpg` (la vague en jeu), `ref-2.jpg` (la
planche annotée) et `ref-3.jpg` (quatre vues). On y voit une vague d'encre indigo à la géométrie calligraphique
fluide, aux plans durs et aux contours épais. Ses lobes de crête sont pâles, des lignes de flux à l'encre
courent sur ses nappes et des fouets la suivent, partiellement attachés. Son intérieur est fait de vrilles
creuses (« pas de noyau de roche »). Au sol, elle laisse des éclaboussures, et vue de dessus elle dessine une
spirale. Pour le feu (images non conservées sur le disque), il y a deux références. La première est une boule
vue de face, tourbillon de 6 à 9 langues crochues qui gonflent, cernées d'encre et striées de pâle, autour d'un
centre sombre, avec de fins rubans qui s'échappent en spirale. La seconde est la planche 3D d'une sphère
low-poly enveloppée de rubans plats qui se détachent en pointes recourbées.

**Les deux corps de référence (livrés, D-273).**

| | La vague du Lavis (Wash) | La boule de la Marque (Brand) |
|---|---|---|
| Ce que c'est | trois nappes d'encre drapées l'une sur l'autre, qui montent en crête et retombent en crochet sur un creux d'encre ; cinq lobes d'écume pâle ; des fouets qui traînent | treize rubans : sept bras en spirale d'un œil sombre à l'autre, six langues en virgule qui se détachent, longues et courtes alternées ; un trait chaud sur chaque langue |
| Recette | `tools/meshes/wave.py` → `WaveBody` / `WaveCrest` / `WaveInk` | `tools/meshes/fireball.py` → `FireBody` / `FireCore` / `FireInk` |
| Référence, axe | `Width` = 16 studs (le diamètre exact de la sphère), axe Y, pivot au sol sous le centre de la sphère | `Diameter` = 3,6 au lâcher, 3,4 en vol, axe Z (le vol) |
| Planches | `docs/vfx/wash/modele.png`, `corps.jpg` | `docs/vfx/brand/modele.png`, `corps.jpg` |
| Ce qu'elle apprend | pas de noyau plein : des nappes et de l'air. Le pâle seulement sur les lobes. Un creux d'encre donne la profondeur. Écrasée à 45 %, l'encre faisait une dalle noire : on s'écrase à 60 % et l'encre s'efface d'abord | des rubans sur une sphère. Chaque langue tourne sa face vers le lanceur, donc de dos on voit une lame, pas une aiguille. Un seul sens de crochet fait un tourbillon. À 2,4 studs, la boule n'était qu'un point à 20 studs de la caméra de jeu |
| Notes au labo | 5 / 5 / 4 / 4 / 4 / 5 | 4 / 5 / 5 / 4 / 4 / 5 |

**Cinq mots.**
- **Aplat** : un ton par volume, éclairé à plat (normales « up », D-114).
- **Contour** : la coque inversée d'encre.
- **Crochet** : toute pointe finit en crochet, ou en perle ronde quand c'est de l'encre qui coule.
- **Plein-délié** : le trait est chargé où la plume appuie et sec où elle se lève.
- **Air** : on voit à travers le corps, par ses jours, ses creux et ses vrilles.

**Interdits.** Le dégradé, la texture peinte, la lumière ailleurs qu'au cœur, toute matière (pierre, métal,
verre, néon), le nuage ou la fumée qui couvre une cible, la symétrie parfaite, les traits parallèles
identiques, l'aplat d'encre en dalle, le blanc pur (il veut dire invulnérable), l'or hors de l'Orpiment et le
cyan (il veut dire allié).

---

## 2. Trois tons et un contour

Chaque corps est fait de **trois maillages tirés d'une seule construction**, avec une échelle et un pivot
communs, d'une teinte chacun.

| Rôle | Couleur | Ce qu'il porte | Règles |
|---|---|---|---|
| `Pigment` | le pigment, humide puis sec | le corps : nappes, lames, rubans, vrilles | au moins 60 % de la surface vue ; il sèche de l'humide au sec pendant sa vie |
| `Core` | le pigment chauffé vers le blanc | lobes d'écume, stries chaudes, biseaux pâles, fil d'un tranchant | seul le cœur brille (règle 10). Petit, coupé dans les triangles du pigment et soulevé de 0,03 à 0,08 stud, **toujours entouré de pigment**, jamais au bord extérieur, jamais blanc pur |
| `Ink` | charbon `#17150F` | la coque inversée, les lignes de flux, un creux sombre | c'est l'encre qui détache le corps de la page |

**Les palettes** (cœur / pigment / humide / sec ; l'encre est toujours `#17150F`) et leur contraste mesuré
(`docs/vfx/AUDIT.md`) :

| Pigment | Cœur | Pigment | Humide | Sec | Contraste vélin / sol d'entraînement | Coque à la taille finale | Pâle visible |
|---|---|---|---|---|---|---|---|
| Cinabre | `#F4C8C1` | `#D93A22` | `#DB4E37` | `#B2331E` | 3,49 / **1,69** | 0,15 – 0,20 stud | ≤ 12 % (stries des langues) |
| Indigo | `#C4CCDF` | `#2E4A8C` | `#445C94` | `#293F73` | 6,46 / 3,13 | 0,10 – 0,15 stud | ≤ 10 % (écume, lèvres) |
| Terre d'Ombre | `#D6CCC5` | `#6B4A2F` | `#7A5C42` | `#5A3F29` | 6,04 / 2,93 | 0,10 – 0,14 stud | ≤ 6 % (un biseau, un liseré) |
| Vert-de-gris | `#CEE7DF` | `#4FA88C` | `#61AF94` | `#448B73` | 2,19 / **1,06** | 0,20 – 0,28 stud + lignes de flux | ≤ 6 %, `Brightness` < 1,6 |
| Orpiment | `#F9EDC1` | `#E8C022` | `#E8C437` | `#BE9E1E` | **1,33** / 1,55 | 0,15 – 0,25 stud + double filet | ≤ 8 %, ne jamais compter sur lui |

L'or appartient à l'Orpiment seul. Le Vert-de-gris chauffé tire vers le cyan, la couleur d'un allié : son
cœur reste petit et sous le seuil du halo. Le cœur de l'Orpiment (`#F9EDC1`) est presque le vélin, donc chez
lui c'est l'encre qui dessine, et l'or n'est que la couleur à l'intérieur.

**L'encre, quatre usages et pas un de plus.**
1. **La coque inversée.** Chaque sommet est poussé le long de sa normale selon un poids (`strokes.Volume`),
   puis la coque est retournée : on n'en voit que le bord qui dépasse de la silhouette, comme un contour.
   Le poids est plus lourd là où la plume appuie (pied, racine, plein) et plus léger aux pointes. Il ne
   descend jamais sous **0,1 stud** à la taille finale, le minimum lisible à 30 studs. Au sol, le pied de la
   coque dessine le contour sur la page.
2. **Les lignes de flux.** De 2 à 7 par corps (`strokes.surface_ribbon`), effilées comme un coup de pinceau.
   Elles suivent le mouvement, sont de longueurs inégales et jamais parallèles.
3. **Un creux sombre au plus** : l'œil de la Marque, la barrique de la vague, le chas d'une maille, la bouche
   d'une fissure. C'est la profondeur, jamais une dalle.
4. **Le contour au sol** d'un corps posé sur la page, qui est le bas de sa coque.

Quand un corps s'affaisse, **son encre s'efface la première** : un contour écrasé fait une dalle noire (leçon
du Lavis).

---

## 3. Une famille, cinq écoles : le vocabulaire des formes

**Ce que les 28 corps partagent** : les trois aplats et la coque, le profil de pression (tête chargée, queue
sèche qui se fend en brins), au moins un crochet, plus d'air que de matière, le cœur seulement dedans, et
l'affaissement dans la page, encre d'abord.

**Ce qui distingue les écoles** (la manière de la bible, en formes) :

| École | Manière | Formes | Crochet | Mouvement | Corps |
|---|---|---|---|---|---|
| Cinabre | ce qui consume | langues en virgule, tourbillon vers l'extérieur, œil ou centre sombre ; perles rondes quand c'est de l'encre qui brûle | traîne contre la rotation | Spin négatif, qui traîne (−1 à −6) ; une charge s'enroule en positif | Marque, Roussi, Ligature, Hachures, Rubrique, Pâté |
| Indigo | ce qui contient | nappes qui roulent vers l'intérieur, écume sur les lèvres, vrilles creuses, cages, creux d'encre | se referme vers le centre | lent, respire, serre | Lavis, Bavure, Volute, Reliure, Cartouche |
| Terre d'Ombre | ce qui résiste | facettes dures, biseaux, pointes, empattements, plaques, reliefs ; mat, le pâle seulement sur un biseau | un ciseau, un empattement | jaillit, tient, s'affaisse en empreinte ; ne tourne presque pas | Empattement, Marge, Rupture, Pointillé, Paraphe, Dorure, Gaufrage |
| Vert-de-gris | ce qui déplace | faucilles, volutes de vent, fouets, spirales, dunes ; le plus ouvert de tous | roule dans le sens de la poussée ou de la traction | balaie, tourne, vrille | Balayage, Délié, Poncif, Spirale, Chaînette, Obèle |
| Orpiment | ce qui frappe d'un coup | signes typographiques : filets réglés, ^, fil d'or, nœud de signature, double filet | un délié qui se lève (le coup de fouet de la plume) | réglé en un souffle, il tient, puis il est pressé à plat ; ne roule jamais | Rature, Insertion, Filigrane, Colophon |

**Deux exceptions voulues.** Le Pointillé est lisse : c'est de la boue, et une boule à facettes mate serait un
boulet (cette école n'a pas de roche). Le Pâté finit ses fouets en perles rondes, jamais en pointes : c'est
de l'encre qui brûle, pas une flamme, et il doit se distinguer de la Marque d'un coup d'œil.

**Les paires qu'on ne doit pas confondre.**

| Paire | Ce qui les sépare |
|---|---|
| Marque / Pâté / bouton de la Rubrique | Marque : langues pointues, œil sombre, Spin −6. Pâté : tête ronde, fouets à perles, Spin −2,5, deux fois plus gros. Bouton : pétales repliés vers l'intérieur sur un cœur pâle, Spin +4, seulement dans les mains |
| Bavure / Spirale / Poncif / Filigrane (zones au sol) | Bavure : mare basse et vrilles debout, presque immobile. Spirale : bol entier qui tourne trois fois plus vite. Poncif : arcs brisés mats, immobiles. Filigrane : fil d'or en relief, emblème |
| Empattement / Rupture / Gaufrage | même langue Terre d'Ombre, rangée de puissance : 5 pointes en ligne, puis couronne de 36 studs, puis anneau bas. La Rupture reste la plus haute et la plus longue |
| Rature / Rubrique | Rature : lame d'or mince (2,2 × 0,4) à double filet. Rubrique : barre rouge lourde (5,6 × 1,7) à trois lobes |
| Obèle / Insertion | † vert planté sur un trait droit, contre ^ d'or ouvert autour du lanceur au bout d'un arc |
| Balayage / Délié / croissant du coup reçu | Balayage : bande couchée au sol. Délié : faucille penchée en l'air, avec des fouets. Coup reçu : petit croissant plat sur le corps touché |

---

## 4. L'échelle : la vérité du serveur

### 4.1 La référence d'un corps est un chiffre du serveur

Chaque maillage est normalisé : son étendue de référence (`Reference` dans le manifeste) vaut exactement 1, et
la timeline le pose à la taille que le serveur a frappée.

| Archétype | Étendue de référence | Taille posée | Exemple |
|---|---|---|---|
| Projectile | `Diameter`, `Length` ou `Span` de la tête | dans la sphère `HitRadius` du serveur, moins ce que le porteur dessiné peut traîner ; jamais sous 2,6 studs | Délié 5,6 dans 7 ; Pointillé 2,6 dans 8 |
| Coup ou zone au sol | `OuterDiameter` (l'encre extérieure, coque comprise) | `Face = "Ground"`, `SizeFrom = "Radius"`, `Size = 2` : le contour tombe au rayon. `Volumes.spec` le tient entre 0,95 et 1,0 R | Bavure 18, Roussi 26, Rupture 36 |
| Rayon (hitscan) | `Length` = 1 le long de −Z | longueur = `Reach` (la portée réelle du serveur, R1), largeur ≤ 2 × `HitRadius` | Rature 2,2 de large sur ≤ 70 |
| Front qui roule | `Width` | exactement la `Width` du serveur, sans jamais d'ease au-delà | Paraphe 12 |
| Mur | la Part du serveur | une gaine collée à 0,05 stud près | Marge 14 × 9 × 2,5 |
| Statut porté | `Height` ou `Diameter` autour de l'avatar R15 | la hanche est à 3,2 studs, le sommet de la tête à 6,2 | Dorure, nœud du Colophon |

### 4.2 Jamais au-delà du mal

- **XZ ne dépasse jamais.** Pas de `Back` sur la largeur : le bord est l'information d'esquive. Seul Y peut
  dépasser, et sous le dôme de la sphère, qui est centrée à hauteur de racine (3 studs au-dessus du sol) :
  **h ≤ √(R² − r²) + 3**.
- **Au sol, la sphère touche la page à √(R² − 9).** Quand ce disque est plus petit que R, le corps vise ce
  disque tout en restant dans la tolérance de `Volumes.spec` (0,95 R au moins). Exemples : Balayage `Size`
  1,93 (11,58 studs pour un disque de 11,62) ; Gaufrage `Size` 1,97 (lèvre à 12,8 à 1,65 de haut).
- **Ce qui tourne reste dans le rayon 0,5 du pivot.** Un Spin, un Jitter ou un Roll ne peut pas pousser un
  sommet hors de la sphère.
- **La durée est celle du mal.** Un corps qui blesse vit jusqu'au dernier tick, à la fin de l'étourdissement,
  des i-frames ou du statut, et pas une image de plus. Pour un coup instantané, il reste « haut et sombre »
  au plus ⅓ s (règle 9).
- **On ne dessine que ce qui blesse.** Pas de forme au sol sous un éclat aérien que la sphère ne touche pas
  (question ouverte du Pâté, §14).

### 4.3 Lisible depuis le lanceur

- La caméra de jeu est à 11-12 studs derrière la racine et 5-6 au-dessus ; l'œil est à environ 8-9 studs du
  sol.
- **Ce qui est droit devant passe derrière la tête du lanceur** (règle connue du labo). Un corps se lit donc
  par ses bords, avec des pointes, des cornes ou des fouets qui dépassent de chaque côté, ou en montant
  au-dessus de la tête.
- **Une zone devant** a sa bande centrale cachée par le corps du lanceur sous 1,6 à 2,1 studs de haut. Elle se
  lit par son bord : anneau, crochets, crête, arcs.
- **Des fouets pointés vers la caméra** se lisent comme « ça s'éloigne ».
- **Un projectile fait au moins 2,6 studs.**
- **Un corps au sol reste sous la taille** (≤ 3 studs), sauf ses pointes. Il ne couvre jamais un torse plus
  de ⅓ s, et une cible doit rester visible au-dessus du genou.
- `preview.py` rend six vues, dont les deux du lanceur. L'outil T2 (§10) ajoute la vue « caméra de jeu de
  zone ».

---

## 5. Le mouvement, temps par temps

### 5.1 Règles communes (tenues par `tests/Volumes.spec.luau`)

- **Trois volumes, un seul corps.** Ils ont la même fenêtre, la même place, la même taille, le même
  étirement, le même ease et le même Spin. Seule l'encre peut finir plus tôt, par un fondu dans sa propre
  chaîne.
- **Un volume ne tourne que sur son axe** : Y pour ce qui est posé au sol, Z pour ce qui vole. `Roll` fixe
  une inclinaison.
- **Le premier maillon ne surgit pas.** Il naît petit (`Size` ≤ 35 % de sa taille d'arrivée), à plat (un
  étirement ≤ 0,1) ou transparent (≥ 0,6), et il ne fait jamais plus de 60 % de son chemin en une image.
  Durées minimales mesurées :

  | Ease (Out) | Durée minimale du premier maillon | Part du chemin dans la 1ʳᵉ image |
  |---|---|---|
  | Quad | 0,06 s | 48 % |
  | Cubic | 0,08 s | 50 % |
  | Quart | 0,10 s | 52 % (à 0,08 s : 61 %, refusé) |
  | Quint | 0,12 s | 53 % |
  | Back | 0,12 s | 54 % (à 0,10 s : 62 %, refusé) |

- **Le dernier maillon** d'un corps non porté finit aplati (≤ 0,1), réduit (≤ 10 %) ou effacé (≥ 0,95).
- **Une chaîne** (`Chain`) reprend exactement là où le maillon précédent s'est arrêté : même maillage, même
  `Face`, même taille, même transparence, même étirement, même Spin, même `SizeFrom`.
- **Rien de linéaire.**

### 5.2 Par temps

| Temps | Ce que fait le corps | Chiffres qui marchent |
|---|---|---|
| Naît dans la main | seulement si la fenêtre dure ≥ 0,06 s (la Marque) ou si c'est une charge tenue (Rubrique, Volute : `Follow`, R2). Sinon le Cast commun suffit : un volume ne peut pas pousser en 0,03 s | Quad Out 0,06 s, de 0,3 à la taille de vol |
| Vol | porté par le porteur du serveur (`Ride`). Étiré le long du vol au lâcher, il s'arrondit ensuite comme le ferait la traînée de l'air. Il tourne sur Z | Exponential Out ; Stretch Z 1,25 → 1,05 |
| Coup ou zone, première image | XZ au rayon dès la première image : né à plat (Y de 0,04 à 0,08) ou à au moins 72 % du rayon ; il jaillit en Y | Back Out ≥ 0,12 s ou Quart Out ≥ 0,1 s |
| Ticks | un maillon « bond » par tick, qui **atterrit sur le tick** (timeline `Steady`), puis un maillon « repos ». Des ticks identiques donnent des bonds identiques : un corps ne promet pas des dégâts que le serveur ne fait pas | bond Back Out 0,08-0,12 s, Y × 1,35-1,45 ; repos Sine |
| Fin | il s'affaisse dans la page à la fin exacte du mal : Y → 0,02-0,06, encre d'abord | Quad In 0,14-0,35 s |
| Atterrissage | un projectile prend la forme d'atterrissage de son corps (R4) : éclaboussure, cisaille ou affaissement | `Land.Fade` 0,1 s |
| Retrait | quand le serveur reprend la zone (D-141), le corps s'affaisse au lieu de disparaître (R5) | 0,12-0,15 s, Quad In |
| Trace | le corps peut devenir sa propre trace : une empreinte aplatie qui sèche remplace une `Mark` et libère une couche | l'empreinte de l'Empattement |

### 5.3 Sens de rotation

- **Les crochets traînent contre la rotation** : c'est ce qui fait lire une flamme qui file.
- **Une spirale coule vers l'intérieur quand son rayon croît dans le sens de la rotation.** On compte θ de +X
  vers −Z ; un Spin positif tourne dans le sens antihoraire vu de dessus. Un bras r = r₀·e^(bθ) avec b > 0
  coule donc vers le centre quand Spin > 0. C'est vital pour la Spirale, qui tire : une traction lue comme
  une poussée envoie le joueur du mauvais côté. À prouver au labo, une fois en miroir.
- **Par école** : Cinabre négatif (Marque −6, Roussi −1,2, Pâté −2,5), sauf une charge qui s'enroule (bouton
  de la Rubrique +4). Indigo lent (Bavure +0,3), et la Volute vrille en charge (−10). Terre d'Ombre presque
  immobile (Rupture +0,5, Dorure +0,5). Vert-de-gris : il balaie (Balayage +1,5), il aspire (Spirale +2,6),
  il vrille (Chaînette −12), mais le Délié ne roule pas (0). Orpiment ne roule jamais, sauf le nœud du
  Colophon (+1,5).

---

## 6. Ce qui reste en particules

**Le corps remplace ce qui dessinait la même chose** : sprites `InkSpike`, `BrushStroke` en sprite, le
`GradientRadial` qui gonfle, le croissant plat, l'`Enso` quand la coque est déjà le bord. Il faut alors garder
une `Mark` de repli, car un volume au sol est sauté au-dessus de l'avertissement d'un autre jeu
(`overWarning`).

**Ce qui reste**, parce qu'un volume ne sait pas le faire :
- le Cast commun dans la main (tache, cœur, sceau) ;
- les étincelles le long de la visée (`Emit = "Aim"`) ;
- le geyser d'encre vertical, qui monte au-dessus de la tête du lanceur ;
- les perles lestées (`Weight`), la poussière, les papiers arrachés (`Debris`) ;
- le scintillement d'une flamme : un seul anneau `InkFlame` piloté par le rendu (`Driven`) ;
- l'anneau de choc tourné vers la caméra ;
- les marques et les traces au sol : taches, fissures, brûlures ;
- les traînées, pour une longueur variable (le trait du Colophon) et pour le sillage d'un projectile (ruban
  nu, effilé, sans texture) ;
- la lumière, l'`Outline` d'un statut porté (la Dorure le garde), les secousses, le flash de page et les sons.

---

## 7. Les budgets

| Quoi | Plafond | Tenu par |
|---|---|---|
| Couches vivantes par timeline | 12 (un volume = une couche ; un maillon chaîné ne compte qu'une fois) | `scripts/effect-cost`, `tests/EffectCost.spec.luau` |
| Particules par timeline | 400 | idem |
| Triangles d'un volume porté (projectile, charge, nœud) | 1 000 | `tests/MeshConfig.spec.luau` `BODY_CAPS` |
| Triangles d'un grand corps (zone, ultime, mur, front) | 1 800 | idem |
| Triangles d'une petite pièce répétée (une pointe, une rature) | 450 (le plafond par défaut) | idem |
| Triangles dessinés par lancer (cible) | ≤ 3 500 | revue de la planche |
| Taille d'un fichier | 200 000 octets, reproductible à l'octet | `tools/meshes/generate_all.py` |
| Six lancers à la fois | 60 i/s en Élevé et en Performance | `stress` au labo |

Viser sous le plafond pour les sorts qu'on spamme : le Balayage (recharge 3 s) reste près de 1 000 triangles
par volume, même s'il aurait droit à 1 800.

**Éviction.** Au plafond de couches, le rendu retire la plus ancienne couche « ordinaire ». Il ne retire
jamais un porteur, un avertissement ou un volume porté (`Ride`), mais un corps posé au sol n'est pas protégé :
il peut perdre son encre avant son pigment. C'est R6.

---

## 8. Le kit de volumes partagé

Onze pièces de volume et un outil. Chaque pièce sert au moins deux glyphes, et chacune est une fonction Python
dans l'espace Roblox (X droite, Y haut, avant −Z) qui rend des `strokes.Volume` fermés. L'outil K0 en tire les
trois maillages. Emplacement proposé : `tools/meshes/kit.py` pour les pièces et `tools/meshes/roles.py` pour
K0. Les corps vivent dans `tools/meshes/<glyphe>.py` et s'inscrivent dans `recipes.RECIPES` avec leur
plafond.

### K0 — Les trois rôles (outil)
- **Ce que c'est.** Une construction entre et trois maillages sortent. `Pigment` : les volumes fusionnés.
  `Core` : les lobes, stries et biseaux coupés dans les triangles du pigment et soulevés. Le coupeur promeut
  `fireball.streak` et les coiffes d'écume de `wave.py` (`_FOAM_CAPS`). `Ink` : `inverted_hull` de chaque
  volume, plus les lignes de flux (`surface_ribbon`) et les creux. L'outil applique **une seule** échelle et
  **un seul** pivot aux trois, normalise l'étendue de référence à 1, compte les triangles par rôle et refuse
  un dépassement. Il promeut aussi `blade`, `blade_hull` et `skin` de `fireball.py` dans `strokes.py`.
- **Glyphes.** Les 26.
- **Axe, référence.** Ceux du corps.

### K1 — La lame de plume (le « plein »)
- **Ce que c'est.** Une lame facettée qui sort de la page, à plans durs, avec une lèvre de racine biseautée
  (la trace d'un bec carré). Elle s'effile selon le profil de pression et finit en biseau de plume ou en
  pointe. Paramètres : section (hexagone, losange, lentille à 4 pans), inclinaison, torsion (jusqu'à un quart
  de tour), crochet tangentiel au sommet, et des pieds au choix : empattement à congés en travers du trait
  (Empattement), garde à bouts empattés avec pommeau en goutte (Obèle), ou lèvre de page déchirée (Rupture).
- **Glyphes.** Empattement, Rupture, Obèle.
- **Axe.** Y.
- **Référence.** `Height` (une lame) ; `OuterDiameter` quand K7 la pose en couronne.
- **Budget.** 60 à 300 triangles par lame.

### K2 — Le croissant plein-délié
- **Ce que c'est.** Une lame en lentille, renflée au milieu (le plein) et effilée jusqu'au cheveu à ses deux
  bouts (les déliés). Le paramètre de cambrure va de 0 (lentille droite, une taille de burin) à 0,35 (une
  faucille). Options : pointes recourbées, fil pâle sur le bord d'attaque (`Core`), brins secs à la sortie.
- **Glyphes.** Délié (faucille en l'air), Hachures (lentilles droites). Plus tard, il remplacera le croissant
  plat du coup reçu et du corps-à-corps.
- **Axe.** Z en vol ; `Roll` fixe l'angle du coup.
- **Référence.** `Span` (de pointe à pointe) ou `Length`.
- **Budget.** 200 à 520.

### K3 — Le trait réglé
- **Ce que c'est.** Un trait droit modelé à la longueur 1 le long de −Z. Sa tête est pressée sur les premiers
  3 %, son corps a une section constante, et sa fin (les derniers 4-5 %) est un coup de fouet qui se lève ou
  une queue sèche en 2-3 brins. Comme sa section est constante, on peut l'étirer à n'importe quelle portée
  sans le déformer (R1). Sections : lentille à arête (Rature), ventre rond à tête en biseau et cornes
  (Rubrique), triangle (la rature de départ de l'Obèle et de l'Insertion), dalle haute à bourrelet roulé
  (Marge). Deux traits joints font un chevron ^ (Insertion). Option : double filet d'encre de part et d'autre
  de l'arête.
- **Glyphes.** Rature, Rubrique, Insertion, Obèle, Marge.
- **Axe.** Z quand il est couché (Y pour la Marge, debout).
- **Référence.** `Length`, étirée à `Reach` ; `Width` pour la Marge.
- **Budget.** 40 à 480, et 1 100 pour la Marge.

### K4 — La langue crochue
- **Ce que c'est.** La bande pelée de `fireball.py` rendue générique. C'est un ruban en virgule : étroit à la
  racine, plus large passé le milieu, pointe vive avec un dernier crochet. Sa section s'ouvre en dalle plate
  (dont le contour se tient égal pendant qu'elle se tord), sa face tourne vers le regard, et elle porte une
  strie chaude sur ses deux faces. Le signe du crochet est un paramètre : vers l'extérieur c'est une flamme,
  vers l'intérieur c'est un bouton. On la pose en boule (la Marque, existante), debout en couronne sur un
  anneau (Roussi, par K7), en nœuds de 3-4 sur une ligne (Ligature) ou en bouton de 6 pétales repliés (charge
  de la Rubrique).
- **Glyphes.** Roussi, Ligature, Rubrique (et la Marque, à refaire avec sans changer son rendu).
- **Axe.** Y debout ; Z en bouton.
- **Référence.** `Height` (une langue) ; `OuterDiameter`, `Length` ou `Diameter` (l'ensemble).
- **Budget.** 60 à 100 par langue.

### K5 — Le fouet
- **Ce que c'est.** Une vrille le long d'un chemin Catmull-Rom. Sa section est un tube à trois pans
  (`strokes.tube`) ou une lentille plate (le « nerf »). Sa racine est enfouie dans ce qui la porte, elle
  s'effile, finit en crochet, et peut porter une perle ronde au bout. On la fabrique en jeux de N le long d'un
  arc ou d'une ligne : courbure vers l'intérieur ou l'extérieur, longueurs inégales, partiellement attachée.
  Variante cage : N cordes en loxodromie sur une sphère étirée, nouées au sommet (Reliure).
- **Glyphes.** Balayage, Bavure, Délié, Pointillé, Reliure, Paraphe, Spirale, Pâté (et les fouets du Lavis,
  encore trop droits).
- **Axe, référence.** Ceux du corps qui le porte.
- **Budget.** 30 à 80 par fouet.

### K6 — La goutte et l'éclaboussure
- **Ce que c'est.** Cinq formes de l'encre qui coule :
  - (a) une tête de goutte tournée, lisse (Pointillé) ou taillée en plans (Pâté), à ventre sombre ;
  - (b) une perle ronde avec sa propre coque et une coiffe pâle ;
  - (c) un chapelet de perles détachées qui rapetissent le long d'un chemin ;
  - (d) une éclaboussure en relief : une mare basse (hauteur ≤ 0,04 du diamètre), des doigts capillaires
    finis en crochet exactement au bord, le centre ouvert ou non, des perles satellites ;
  - (e) une étoile 3D : des bras radiaux finis en perles rondes posées sur la sphère du mal.
- **Glyphes.** Bavure (d), Pointillé (a, c), Pâté (a, e), Reliure et Obèle (d en petite rosette).
- **Axe.** Y pour l'éclaboussure et l'étoile ; Z pour la goutte.
- **Référence.** `OuterDiameter` ou `Diameter` ; `Length` pour la goutte.
- **Budget.** 8 triangles par perle ; 400 à 1 050 pour une mare.

### K7 — L'anneau-mur
- **Ce que c'est.** Un anneau de base fermé, dont l'encre extérieure tombe exactement au rayon 0,5, qui porte
  N pièces. Le profil des pièces est un paramètre : langue K4 (Roussi), cran biseauté (Gaufrage), plaque de
  cuir (Dorure), feuille roulée K10 (Cartouche), lame K1 (Rupture). Options : une encoche ouverte (le fer à
  cheval de la Rupture), l'inclinaison et la variance pièce par pièce. Les pièces sont enracinées assez à
  l'intérieur pour que leurs pointes et leur coque restent dans 0,5.
- **Glyphes.** Roussi, Gaufrage, Dorure, Cartouche, Rupture (placement).
- **Axe.** Y, `Face = "Ground"` ou porté sur le corps.
- **Référence.** `OuterDiameter`.

### K8 — La spirale
- **Ce que c'est.** Un générateur de spirales logarithmiques. Soit K bras du bord vers un œil (nombre de
  tours, profondeur du bol, bout chargé, brins secs, rayon de l'œil en part du rayon, crochets de bord), soit
  un seul ruban plat de 2,5 tours, à œil pâle bombé et terminaison crochue. Il porte la règle de sens du §5.3.
- **Glyphes.** Spirale (bol à plat), Volute (ruban face au regard), Bavure (le chemin de ses lignes de flux).
- **Axe.** Y à plat ; Z face au regard.
- **Référence.** `OuterDiameter` ou `Diameter`.

### K9 — Le relief tracé
- **Ce que c'est.** Des lignes en bas-relief couchées sur la page le long de chemins : arcs concentriques
  brisés, C-volutes, rosettes. Le profil est un paramètre : la dune (asymétrique, pente douce au vent, raide
  sous le vent, bout sec crocheté) ou le fil (rond à trois pans, avec l'option torsadée à deux brins). Des tas
  ou des perles se posent le long des courbes, et une ligne pâle court sur la crête. Hauteur ≤ 0,04 du
  diamètre.
- **Glyphes.** Poncif (dune), Filigrane (fil).
- **Axe.** Y, `Face = "Ground"`.
- **Référence.** `OuterDiameter`.

### K10 — La nappe roulée
- **Ce que c'est.** La nappe de `wave.py` rendue générique : une nappe debout, épaisse au pied et en délié à
  la lèvre, balayée le long d'un chemin (ligne cambrée, arc au sol, segments de cercle). Sa lèvre roule en
  volutes (vers l'intérieur, l'extérieur ou l'avant) ou se ferme en boucles de paraphe. L'écume pâle coiffe
  le rouleau (`Core`) et le creux de la volute est à l'encre. Elle donne aussi la couronne d'écume d'une crête
  (le bourrelet de la Marge).
- **Glyphes.** Balayage (arc au sol), Paraphe (ligne cambrée), Cartouche (douze segments de cercle), Marge
  (lobes de crête). Le Lavis en est la source.
- **Axe.** Y.
- **Référence.** `Width` (Paraphe) ; `OuterDiameter` (Balayage, Cartouche).

### K11 — La maille
- **Ce que c'est.** Un ruban au bec large balayé le long d'une courbe 3D fermée : épais sur les pleins
  (descendants), fin aux croisements (l'angle du bec), avec un chas sombre en option. Il donne une boucle en
  goutte (tête de la Chaînette), trois anneaux entrelacés (manille de la Chaînette) et le nœud de cadelure
  (Colophon).
- **Glyphes.** Chaînette, Colophon.
- **Axe.** Z quand il vole ; Y quand il est porté.
- **Référence.** `Length` (maille), `Diameter` (manille), `Height` (nœud).

---

## 9. Les corps sur mesure

Ces corps tirent du kit, mais leur **composition est le dessin** : chacun a son propre module, comme la vague
et la boule, et un juge choisit entre deux constructions concurrentes, comme pour D-273.

| Corps | Module | Pourquoi sur mesure |
|---|---|---|
| La Couronne de pleins (Rupture) | `rupture.py` | ultime du deck de départ : fer à cheval ouvert vers le lanceur, trois rayons de lames, l'écart du tir dégagé |
| Le filet gras (Marge) | `margin.py` | une gaine qui habille une Part du serveur à 0,05 stud près, recto et verso |
| La Larme et le Pâté (Blot) | `blot.py` | deux corps, l'un après l'autre : une tête à fouets en vol, une étoile au point d'éclatement |
| Le signe d'insertion (Insertion) | `caret.py` | un signe exact (^), dont l'ouverture est la vue du lanceur |
| La Forme (Filigrane) | `watermark.py` | un emblème : rim torsadé, quatre C-volutes, rosette |
| La Cadelure (Colophon) | `colophon.py` | un chemin de nœud précis autour d'un avatar ; c'est la vitrine du game pass |

`wave.py` et `fireball.py` restent sur mesure ; ce sont les sources de K10 et de K4.

---

## 10. Ce que le rendu doit apprendre

Tous ces changements sont **visuels**. Chacun demande une entrée dans `docs/DECISIONS.md` et un test prouvé
par mutation. Ceux qui touchent un paquet du serveur (R3, R8 serveur) demandent en plus l'accord du
développeur.

| Id | Changement | Glyphes | Lot |
|---|---|---|---|
| R1 | **Span sur un volume.** Un `Mesh` honore `Span` / `SpanFrom = "Reach"` sur son axe avant seulement. Cela touche `scale.Z` dans `VfxVolumes.step`, l'enveloppe de `build` (`overWarning`) et `pivotOffset` | Rature, Rubrique | 4, 5 |
| R2 | **Un volume qui suit.** Il est bâti au repère du corps suivi (comme une `Mark` qui suit), puis recalé à chaque image sur sa position, et sur son lacet si on le demande, sans jamais pencher. Le corps suivi est la racine du lanceur, une victime nommée ou une Part du serveur. `Face = "Ground"` avec `Follow` devient permis, le sol étant sondé sous le corps. `Volumes.spec` l'interdit aujourd'hui ; il faut l'amender et étendre sa règle de portée aux volumes qui suivent. Aujourd'hui `VfxVolumes.step` replace tout volume non porté sur `volume.Base` | Roussi ; Volute, Rubrique (charges) ; Hachures ; Dorure ; Chaînette, Reliure, Colophon (victime) ; Marge (dalle) | 1 à 5 |
| R3 | **L'atterrissage des projectiles à coup direct.** `nextShot()` dans `Params`, un paquet fiable, et un `Fizzle {Shot}` à l'arrêt, touché ou raté, comme la Marque, le Pâté, le Paraphe et la Chaînette. Aucun chiffre et aucun temps ne bougent | Délié, Pointillé | 2 |
| R4 | **Une forme d'atterrissage par corps** : `Land = "Splat"` (aujourd'hui : X et Y × 1,6, Z × 0,1), `"Shear"` (la largeur tenue, Z → 0,1 : une lame cisaille sans grandir) ou `"Slump"` (Y → 0,05, X × 1, Z × 1,25, encre d'abord). Sans cela, le Paraphe serait dessiné sur 19 studs de large au mur et le Délié sur 9 dans une sphère de 7 | Délié, Paraphe | 2, 3 |
| R5 | **Le retrait en douceur.** `VfxTimeline.cancel` met `EndsAt = now` ; un volume reçoit à la place un affaissement de 0,12-0,15 s (Y → 0,02, Quad In, encre d'abord) | Bavure, Roussi, Spirale, Poncif, Filigrane, Cartouche, Hachures, les charges | 1 à 5 |
| R6 | **L'éviction d'un corps entier.** Les volumes d'un corps au sol ou porté sur un avatar sont protégés comme un corps porté, ou partent ensemble ; les particules et les flourishes partent d'abord | toutes les zones et tous les ultimes | 1 |
| R7 | **La chaîne de ticks.** Une fonction de `VfxTimelineConfig` écrit les maillons bond / repos des trois volumes à partir de `Ticks`, `TickInterval` et de l'avance de phase. Chaque bond tombe sur son tick par construction, et les trois volumes ne peuvent pas se décaler | Bavure, Roussi, Empattement, Ligature, Poncif, Spirale, Filigrane, Cartouche | 1 |
| R8 | **Des mesures en plus.** L'Empattement reçoit `Radius = HitRadius` (passé par `VfxLibrary.Serif` depuis `GlyphConfig`, côté client). L'Obèle reçoit la distance du corps (`Targets[2]`, client) et l'Insertion son arrivée sur `Targets[1]` (client). Pour le Pâté, `Params.Glyph = "Blot"` dans le paquet `Explosion` (serveur, champ visuel). Pour le Colophon et la Reliure, les modèles touchés dans le paquet (serveur, champ visuel, comme `StitchCatch.Victim`) | Empattement ; Obèle, Insertion ; Pâté ; Colophon, Reliure | 1, 2, 4, 5 |

**Outils.**
- **T1** : K0 (`roles.py`).
- **T2** : une vue « caméra de jeu de zone » dans `preview.py`. La caméra est à 11 studs derrière la racine
  et 5 au-dessus, le centre de la zone est à `Params.Offset`, et une silhouette de 5 studs fait écran. Un fil
  dessine la sphère du serveur, pour voir « jamais au-delà ».
- **T3** : une entrée `BODY_CAPS` dans `tests/MeshConfig.spec.luau` pour chaque volume de plus de 450
  triangles.

**Tests à amender.** On va toujours vers une vérité plus précise, prouvée par mutation, et jamais vers un test
plus faible.
- `VfxStyle` « stands a spike up out of the page » : l'Empattement passe à cinq volumes aux cinq points du
  serveur, au pas de `StepDelay`.
- `VfxStyle` « rings the Scorch's fire » : un bond de couronne par tick (± 0,035 s), couronne qui suit au
  `Radius`. L'anneau `InkFlame` piloté reste, pour « a fire ».
- `Volumes.spec` : `Ground` + `Follow` (R2), une règle de portée pour les corps `Face = "Aim"` (l'étoile du
  Pâté contre `BlastRadius`), et une charge tenue en main pendant une phase à fenêtre (Rubrique).

---

## 11. Les 28 glyphes

Format : le corps en deux ou trois phrases, puis les volumes (`Pigment` / `Core` / `Ink`), la référence,
l'axe, les pièces du kit, le lot, les prérequis et le pic de couches (avant → après).

### Cinabre — ce qui consume

**La Marque (Brand) — livrée, référence.** Une boule de 13 rubans : sept bras en spirale et six langues
crochues, longues et courtes alternées, un œil sombre, un trait chaud sur chaque langue, une coque d'encre.
Elle naît dans la main (Quad Out 0,06 s jusqu'à 3,6) et vole à 3,4 en tournant à −6 rad/s sur Z.
`FireBody` / `FireCore` / `FireInk` · `Diameter` · Z. Reste à faire : la reconstruire avec K4 une fois le kit
écrit, sans changer son rendu.

**Le Roussi (Scorch) — « le Fleuron », lot 1.** Une couronne de 12 langues crochues debout sur un anneau mince
exactement au rayon 13 autour du lanceur. Les longues font 3,2 studs, les courtes 2,2, et toutes crochent dans
le même sens : c'est le tourbillon de la Marque vu de dessus. Elle suit le lanceur (position seule), bondit
sur chaque tick (0 / 0,8 / 1,6 s) et s'affaisse 0,3 s après le dernier. Elle remplace les rafales de flamme
par tick et deux des trois anneaux de flamme (358 → environ 150 particules). `ScorchCrown` / `ScorchCore` /
`ScorchInk` · `OuterDiameter` (26) · Y · K4 + K7 · R2, R5, R6, R7 · pic 10 → 9.

**La Ligature — « la liaison ardente », lot 2.** Un ruban de cinabre couché le long de la course (de −5 à +21
studs, 9 de large au plus), tête chargée au départ, queue sèche en brins à l'arrivée. Il porte cinq nœuds de 3
ou 4 langues (K4), un sur chaque flaque du serveur ; leur hauteur baisse de 4,5 à 2 studs, si bien que la
caméra du lanceur passe au-dessus des derniers. Il se déroule en 0,1 s, bondit à chaque tick (toutes les
0,4 s) et retombe au dernier, à 1,6 s et non à 2,0. `TieBody` / `TieCore` / `TieInk` · `Length` (26) · Y ·
`Face = "Aim"` avec `Offset` −3 : un corps qui blesse ne doit pas être sauté au-dessus d'un avertissement ·
K4 + K3 · R7 · pic 12 → environ 10.

**Les Hachures (Hatching) — lot 3.** Cinq tailles de burin (K2 droit) : des lentilles vermillon de 7 à 7,6
studs, fines comme une aiguille aux deux bouts, avec un filet chaud sur l'arête. Elles se croisent à ±41° devant
le lanceur, une par temps (toutes les 0,34 s), et chacune vit 0,16 s. La cinquième fait 8,2 studs, en pleine
diagonale de la boîte de 6 × 6, plus épaisse, et part avec le geyser. Aucune langue : c'est un trait gravé, pas
une flamme. `HatchBody` / `HatchCore` / `HatchInk` · `Length` · Z + `Roll` · R2 (chaque taille au repère du
lanceur à son temps), R5 · pic 7 → 10.

**La Rubrique (Rubric) — lot 4.** Deux corps pour un seul geste. La charge est un bouton de 6 pétales crochus
repliés vers l'intérieur sur un cœur pâle (K4, crochet inversé), 2,6 studs dans les mains. Il se resserre en
trois pulsations, sur celles du serveur, en tournant à +4 (il s'enroule), puis éclate à plat au lâcher. Le
trait est la règle rouge du rubricateur (K3, ventre rond) : 5,6 studs de large (≤ 8), réglé de la main au mur
en 0,08 s, avec trois lobes pâles (les trois corps qu'il traverse), puis pressé à plat en 0,33 s.
`RubricBud` / `RubricHeart` / `RubricBudInk` et `RubricBar` / `RubricLobes` / `RubricBarInk` · R1, R2, test
de phase à fenêtre · pics 6 → 8 et 8 → 9.

**Le Pâté (Blot) — lot 4, corps sur mesure.** En vol, c'est la Larme : une tête d'encre cinabre de 4,2 studs
taillée en plans (K6), un lobe pâle mouillé dessus, un ventre sombre. Cinq fouets (K5) la suivent en spirale
et finissent en **perles rondes, jamais en pointes**. Elle tourne à −2,5 et pique tête la première dans la
descente. À l'éclat, le Pâté est une étoile d'encre en volume (K6) : 9 bras, dont 3 qui montent, et des perles
posées exactement sur la sphère de 10 studs. Il est dessiné là où le serveur éclate, en l'air s'il éclate en
l'air ; il tient, ploie et goutte en 0,36 s. `TeardropBody` / `Core` / `Ink` et `BlotBody` / `BlotCore` /
`BlotInk` · R8 (`Params.Glyph`), règle de portée `Face = "Aim"` · pic 12 → 12 (deux couches retirées pour
trois volumes).

### Indigo — ce qui contient

**Le Lavis (Wash) — livré, référence.** Une vague de 16 studs, le diamètre exact de la sphère. Son pied est
sous son centre et sa lèvre au bord avant ; elle a cinq lobes d'écume, un creux d'encre, deux nappes drapées
et des fouets. Elle sort à plat (Back), roule, s'écrase à 60 %, et la page la boit, encre d'abord.
`WaveBody` / `WaveCrest` / `WaveInk` · `Width` · Y. Reste à faire : onduler les fouets (K5).

**La Bavure (Bleed) — « la Bavochure », lot 1.** Un anneau de mare indigo de 18 studs posé à 12 studs devant.
Il est gonflé en ménisque à facettes dures, avec un centre ouvert, neuf doigts capillaires finis en crochet
exactement au rayon 9 et quatre perles détachées (K6). Sur l'arc lointain, sept vrilles creuses (K5) se
dressent et se recourbent vers le centre comme des doigts qui se ferment : c'est le ralentissement. Ses
lignes de flux s'enroulent vers l'intérieur. Elle respire à chaque gorgée (0 / 1 / 2 s, vrilles levées à 3,5
studs) et s'enfonce à 2,5 s. `BleedPool` / `BleedSheen` / `BleedInk` · `OuterDiameter` (18) · Y · K6 + K5
(chemin K8) · R5, R6, R7 · pic 7 → 9.

**La Volute — lot 2.** Une spirale logarithmique de 2,5 tours (K8) : un ruban plat indigo à facettes dures,
plus d'air que d'encre, un œil pâle au centre, un tour extérieur fini en crochet. Pendant la charge de 0,4 s,
sur l'épaule droite et face au lanceur, elle s'enroule de 0,5 à 2,4 studs à −10 rad/s. Au coup, elle est
plaquée sur 6 studs (≤ 8) au centre frappé, puis se referme dans son œil en 0,18 s ; on voit la cible partir à
travers elle. `VoluteBody` / `VoluteEye` / `VoluteInk` · `Diameter` · Z · R2 · pics 5 → 6 et 8 → 9.

**La Reliure (Binding) — « les nerfs », lot 2.** Six nerfs d'encre (K5, section en lentille) jaillissent d'une
rosette au sol (K6) et s'enroulent d'un demi-tour autour du corps pris, jusqu'à se nouer au-dessus de sa tête
(une cage de 5,2 × 6,2 studs), avec une couronne d'écume pâle au nœud. Elle serre pendant exactement 1,5 s
(XZ 1 → 0,94), puis retombe et éclabousse. Les jours entre les nerfs font au moins 1,5 stud : on vise encore
le prisonnier. `CordsBody` / `CordsFoam` / `CordsInk` · `Height` · Y · une variante « personne de pris » (les
nerfs fouettent et retombent aussitôt), R2 et R8 si la victime est poussée · pic 10 → 9.

**Le Cartouche — lot 4.** Le cadre à enroulements des pages de titre : douze feuilles d'encre indigo (K10)
debout exactement au rayon 16, hautes de 2,6 studs, chacune roulant sa lèvre vers l'intérieur. Il y a de
l'écume pâle sur chaque rouleau, un creux d'encre dedans, et une encoche entre deux feuilles : c'est un cadre
de pièces, pas un mur plein. Il naît du sol au sceau, sur le bord et pas au centre. À chacun des 5 ticks,
toutes les volutes se resserrent d'un coup puis se relâchent ; au dernier, elles se déroulent dans la page.
`ScrollworkBody` / `ScrollworkCore` / `ScrollworkInk` · `OuterDiameter` (32) · Y · K10 + K7 · R5, R6, R7 ·
pic 10 → 10.

### Terre d'Ombre — ce qui résiste

**L'Empattement (Serif) — lot 1.** Cinq pieds de lettre (K1) frappés hors de la page aux cinq points du serveur
(6, 11, 16, 21 et 26 studs), un toutes les 0,08 s. Chacun est une tige facettée qui s'effile vers un biseau,
penchée de 6° vers la cible, sur un pied à deux congés couché en travers du trait, comme l'empattement d'une
capitale romaine. Les hauteurs montent de 5,2 à 7,2 studs pour que les dernières pointes dépassent la tête du
lanceur, et seule la cinquième porte un biseau pâle. Chaque pointe frappe puis s'affaisse dans son pied, et
l'empreinte en ⊥ qui sèche est la trace. `SerifBody` / `SerifCore` / `SerifInk` · `Height` · Y · R7, R8,
`Steady` · pic 12 → 11.

**La Rupture — « la Couronne de pleins », lot 1, corps sur mesure.** La page cède sous le lanceur et se
hérisse : 4 grandes lames de 8 à 9,5 studs qui encadrent la visée, 6 moyennes et 6 dents sur le bord au rayon
18 (K1). Chaque lame est biseautée à la racine, tourne d'un quart de tour en montant, finit en crochet couché
dans le sens du tourbillon, et porte un lobe pâle sous son crochet. La couronne est en fer à cheval, ouverte
vers le lanceur : aucune lame à ±40° derrière lui. Elle jaillit en 0,12 s, tient pendant que les corps
montent, et s'enfonce à 0,34 s. `DownstrokeBody` / `DownstrokeCore` / `DownstrokeInk` · `OuterDiameter` (36)
· Y · K1 + K7 · R6 · pic 12 → 10.

**La Marge (Margin) — « le filet gras », lot 2, corps sur mesure.** Un seul trait de plume large dressé de
champ, qui habille la dalle du serveur (14 × 9 × 2,5) à 0,05 stud près. Il a une tête ronde à gauche, un plein
qui gonfle, une queue sèche fendue en trois brins à droite, un bourrelet roulé coiffé de cinq lobes pâles
(K10), et des lignes de flux qui descendent comme des strates de boue (K3 dalle). Il monte avec la dalle
(0,22 s), ne bouge plus, puis redescend avec elle (0,45 s), encre d'abord. `RuleBody` / `RuleLip` / `RuleInk`
· `Width` · Y · R2 (suivre la dalle, et la reprendre quand `retireOldestWall` la retire), décision « règle 9
pour un mur » · pic 12 → environ 9.

**Le Pointillé (Stipple) — lot 2.** Une limace de boue d'ombre crachée (K6, goutte lisse de 2,6 studs) avec
deux lobes pâles mouillés, un chapelet de trois perles détachées qui rapetissent (la ligne pointillée en
volume) et deux giclures courtes (K5). Crachée longue, elle s'arrondit (Exponential Out). À l'arrêt du
serveur, elle s'écrase en éclaboussure sur sa cible. `MudBody` / `MudGloss` / `MudInk` · `Length` · Z · R3 ·
pic 9 → environ 11.

**Le Paraphe (Swash) — lot 3.** Le trait qui souligne une signature, dressé au ras du sol. C'est une lame
d'encre terre d'ombre de 12 studs de large exactement (la largeur du serveur), cambrée (le milieu devant, les
cornes en arrière), épaisse au pied, en délié au sommet (4,6 studs). Ses cornes se ferment en boucles de
paraphe (K10), un patin gratte la page et trois fouets traînent. Elle file sur le porteur à la vitesse du
serveur et se couche au mur. `SwashBody` / `SwashEdge` / `SwashInk` · `Width` · Y, `Face = "Aim"`, portée ·
R4 (Slump) · pic 10 → 11.

**La Dorure (Gilding) — « les fers », lot 3.** Une collerette de six plaques de cuir terre d'ombre (K7)
plantées autour des jambes (4,8 de diamètre, 3,2 de haut, sous la hanche), à facettes nettes, avec un liseré
bruni pâle, un fleuron estampé en losange et deux filets d'encre. Elle se ferme sur le lanceur en 0,16 s,
tourne lentement en le suivant pendant 4 s, puis ses plaques tombent vers l'extérieur à la fin exacte du
statut. **Pas d'or** : l'or est à l'Orpiment. L'`Outline` reste. `IronsBody` / `IronsCore` / `IronsInk` ·
`Diameter` · Y · R2 · pic 11 → 9.

**Le Gaufrage (Emboss) — lot 4.** La page repoussée par-derrière : un bourrelet en anneau (K7) à deux gradins
biseautés et seize crans penchés vers l'extérieur. Il jaillit autour des tibias (3,3 studs de haut pour 3 de
diamètre), file jusqu'à 12,8 studs en s'abaissant à 1,65, puis se couche, avec seize biseaux pâles. Il est
plus bas et plus court que la Rupture : c'est la rangée de puissance. `EmbossBody` / `EmbossBevel` /
`EmbossInk` · `OuterDiameter` (`Size` 1,97 R) · Y · pic 9 → 11.

### Vert-de-gris — ce qui déplace

**Le Balayage (Sweep) — lot 1.** Un coup de brosse large donné à plat : une bande de vent couchée au sol en arc
devant le lanceur, ouverte vers lui. Sa tête est chargée à gauche et sa queue sèche à droite, en trois fouets.
Sa lèvre extérieure se brise en quatre volutes qui roulent dans le sens où le serveur pousse, le long de la
visée. Elle se déploie d'un coup à 72 % puis au bord exact du disque (11,6 studs), ses volutes giclent à
120 % (la portance), elle balaie 35° et se couche à 0,42 s. C'est la cousine plate et circulaire de la vague,
sans crête ni écume. `GustBody` / `GustCrest` / `GustInk` · `OuterDiameter` (`Size` 1,93 R) · Y · K10 + K5 ·
pic 9 → 11.

**Le Délié (Hairline) — lot 2.** Une faucille de vent écrite d'un seul plein-délié (K2) : un croissant de 5,6
studs penché à −35°, renflé au milieu, effilé jusqu'au cheveu, aux pointes recourbées vers le lanceur. Un fil
pâle court sur son bord d'attaque et trois fouets courts (≤ 2 studs) filent derrière elle. Elle naît aiguille
et s'ouvre en faucille dans les 13 premiers studs ; de profil, elle reste le glyphe le plus fin du jeu.
`WindBlade` / `WindEdge` / `WindInk` · `Span` · Z, `Roll` −35 · R3, R4 (Shear) · pic 8 → 11.

**Le Poncif (Pounce) — « la Poncée », lot 3.** La page saupoudrée en dunes ratissées sur 26 studs : trois
anneaux d'arcs brisés (K9, profil dune) et deux courbes pointillées de petits tas ronds (le patron piqué),
jamais plus d'un stud de haut, avec des crêtes pâles et un contour lourd. Elle ne tourne pas : elle se tasse
d'un cran à chaque versement, ou fait un bond identique si le labo lit le tassement comme une escalade. Elle
n'aveugle jamais personne. `PounceDunes` / `PounceCrest` / `PounceInk` · `OuterDiameter` · Y · R5, R7 ·
pic 6 → 8.

**La Spirale — « le Cul-de-lampe », lot 3.** Un bol-tourbillon de 22 studs. Ses sept bras (K8) sont chargés et
hauts au bord (1,6 studs), puis s'amincissent et se fendent en brins secs à l'œil, au rayon 3 (=
`PullMinDistance`). Cinq crochets se recourbent vers l'intérieur sur le bord, et l'œil est un disque plat
d'encre. Elle tourne à +2,6 dans le sens où les bras se versent dans l'œil (§5.3), et plonge, comme une
gorgée, à chaque traction. Jamais une tornade. `SpiralBowl` / `SpiralCore` / `SpiralInk` · `OuterDiameter` ·
Y · R5, R7 · pic 7 → 10.

**La Chaînette (Stitch) — lot 3.** En vol, c'est une maille en goutte (K11) de ruban plat, pleine d'un côté et
déliée de l'autre, refermée sur un chas sombre, avec une aiguille devant ; elle vrille à −12. À la prise, la
boucle s'ouvre en manille : trois mailles entrelacées se ferment à la taille du corps pris (de 3,6 à 3,2 de
diamètre) et le suivent pendant la traction et l'immobilisation (0,8 s). `LoopBody` / `LoopCore` / `LoopInk`
et `ShackleBody` / `ShackleCore` / `ShackleInk` · R2 (la victime est déjà dans `Params.Victim`) · pics 7 → 9
et 7 → 9.

**L'Obèle (Dagger) — lot 4.** La croix d'obèle † : une lame de plume à section en losange (K1, avec garde), de
6 studs, plantée entre le lanceur et le dos de la cible le temps des i-frames (0,2 s). La garde est à hauteur
d'épaule, et une rosette d'encre (K6) gicle là où la pointe entre. Au départ, une rature verticale (K3) barre
la place quittée. `ObelusBody` / `ObelusCore` / `ObelusInk` + `StrikeOut` · `Height` · Y · R8 · pic 9 → 11.

### Orpiment — ce qui frappe d'un coup

**La Rature (Strike) — lot 5.** Une rature d'or réglée d'un souffle (K3, lentille) : une lame plate de 2,2
studs à hauteur de hanche, de la bouche jusqu'au mur. Sa tête est pressée et sa fin se relève d'un coup de
fouet ; un double filet d'encre court de part et d'autre de l'arête, et un fil chaud sur les premiers 60 %.
Réglée en 0,06 s, elle claque, puis est pressée à plat à 0,32 s ; la ligne brûlée reste. `RatureBand` /
`RatureSpine` / `RatureInk` · `Length` × `Reach` · Z · R1 · pic 8 → 10.

**L'Insertion (Caret) — lot 5, corps sur mesure.** Le geste du correcteur. Au départ, une rature horizontale
(K3) barre la place quittée et se referme. À l'arrivée, un grand ^ d'or (deux traits K3 : un délié montant
fin et un plein descendant à empattement) encadre le lanceur, les pieds de part et d'autre (±2,5 =
`ClearanceRadius`), la pointe au-dessus de sa tête, sans aucun Spin. Il tient exactement les i-frames (0,4 s),
puis se replie dans la page. `CaretBody` / `CaretCore` / `CaretInk` + `Rature` · `Width` · Y · R8 · pic 9 →
11.

**Le Filigrane (Watermark) — « la Forme », lot 5, corps sur mesure.** Le moule du papetier en fil d'or (K9,
profil fil) : un rim torsadé à deux brins exactement au rayon 12, quatre C-volutes, une rosette de cinq
boucles et des perles de granulation, avec le vélin partout entre les fils, une ligne pâle sur chaque fil et
une coque lourde. Il se lève, puis se presse à plat sur chacun des quatre ticks, tous identiques.
`WatermarkWire` / `WatermarkGleam` / `WatermarkInk` · `OuterDiameter` · Y · R5, R6, R7 · pic 6 → 9.

**Le Colophon — « la Cadelure », lot 5, corps sur mesure.** Le trait de signature reste un ruban de traînées
(sa longueur varie). Le volume est le nœud (K11) qui se ferme autour de chaque corps signé : une ellipse à la
taille, deux boucles croisées à ±35° (la croix connue, en volume), une queue de paraphe au-dessus de la tête,
un plein épais et un délié fin, un point d'encre à chaque levée. Il tient exactement l'étourdissement (0,6 s)
en serrant, puis se dénoue et s'envole. `CadelBody` / `CadelCore` / `CadelInk` · `Height` (8,5) · Y,
`Face = "Aim"` · R2 + R8 (victimes), nouvelle timeline `ColophonKnot` · pics 12 → 10 et 9 → 7.

---

## 12. Les lots de construction

L'ordre suit ce qu'un joueur voit le plus. Le deck de départ passe en premier, puis les déblocages par niveau
(un déblocage tôt veut dire plus de joueurs ; une recharge courte veut dire plus de lancers), puis l'Orpiment.
Chaque lot construit les pièces du kit dont le suivant aura besoin.

| Lot | Glyphes | Pourquoi ce lot | Kit construit | Rendu et outils |
|---|---|---|---|---|
| 1 | Empattement, Balayage, Bavure, Roussi, Rupture | les cinq débloqués par défaut ; le Balayage, l'Empattement et la Bavure sont dans le deck de départ et suivent la Marque et le Lavis en usage. Ce lot écrit le gros du kit | K0, K1, K4, K5, K6, K7, K10 (+ le chemin de K8) | R2 (sol + suivi, Roussi), R5, R6, R7, R8 (Empattement), `Steady` sur l'Empattement, T1, T2 |
| 2 | Délié, Pointillé, Marge, Ligature, Volute, Reliure | tout ce qu'un joueur possède au niveau 10. Délié (recharge 3 s) et Pointillé (4 s), au niveau 5, sont les plus lancés après le deck de départ ; la Marge **est** dans le deck de départ | K2, K3, K8, K5 cage, K6 goutte et chapelet | R3, R4 (Shear), R2 (charge, dalle, victime) |
| 3 | Paraphe, Poncif, Dorure, Hachures, Spirale, Chaînette | niveaux 12 à 22 | K9 dune, K11, K10 boucles | R4 (Slump), R2 (corps, victime) |
| 4 | Pâté, Obèle, Gaufrage, Rubrique, Cartouche | niveaux 25 à 36, dont deux ultimes | K3 ventre rond, K6 étoile, K7 crans | R1, R8 (Pâté, Obèle), test de phase à fenêtre |
| 5 | Rature, Insertion, Filigrane, Colophon | l'Orpiment (niveau 40 ou game pass) | K9 fil, K11 nœud, K3 lentille et chevron | R1, R8 (Insertion, Colophon) |

**La Marge** est elle aussi débloquée par défaut et dans le deck de départ. Elle ouvre le lot 2 et non le lot
1 parce que son corps habille une Part du serveur et attend deux changements du rendu : suivre la dalle, et la
reprendre quand elle est retirée. Le développeur peut l'avancer (question 1, §14).

---

## 13. Fiches de modélisation — lot 1

Ce qui vaut pour les cinq :
- **Repère Roblox** : X à droite, Y en haut, avant = −Z = la visée.
- **Normalisation.** Trois maillages par corps (`Pigment`, `Core`, `Ink`), tirés d'une construction, avec une
  seule mise à l'échelle et un seul pivot. L'étendue de référence nommée vaut exactement 1 ; les tailles
  ci-dessous sont données en unités de référence, puis en studs à la taille posée.
- **Rendu.** Normales « up » ; un ton par maillage ; contour en coque inversée, faces arrière éliminées comme
  le fait un `SpecialMesh`. Rien sous le sol (`FLOOR_CLEARANCE`).
- **Planche.** `python3 tools/meshes/preview.py <planche.json> <sortie.png>`, avec
  `{"pigment": "...", "layers": [{"recipe": "...", "module": "...", "role": "Pigment"}, …]}`, six vues plus la
  vue de zone (T2), **avant tout téléversement**.
- **Fichiers.** Les recettes s'inscrivent dans `recipes.RECIPES` avec leur plafond. `generate_all.py` doit
  rester reproductible à l'octet.

### 13.1 L'Empattement (Serif) — « cinq pieds de lettre »

- **Vérité du serveur.** Cinq sphères de rayon 5 (`HitRadius`), centrées à hauteur de racine (3 studs
  au-dessus du sol), à 6, 11, 16, 21 et 26 studs le long de la visée, à t = 0 ; 0,08 ; 0,16 ; 0,24 ; 0,32 s.
  Au sol, chaque sphère a un rayon de 4 ; elle monte jusqu'à 8 studs.
- **Maillages.** `SerifBody` (Pigment), `SerifCore` (Core), `SerifInk` (Ink). Un seul modèle de pointe, que la
  timeline pose cinq fois.
- **Référence, axe, pivot.** `Height` = 1, du sol au sommet du biseau. Axe Y. Pivot (0, 0, 0) au sol, sous
  l'axe de la tige, à sa racine. `Face = "Ground"`.
- **Tige.** Section hexagonale à facettes dures, 0,30 de large (X) sur 0,22 de profondeur (Z) à la racine.
  Elle s'effile selon le profil de pression (appui rapide, puis relâche) jusqu'à 0,07 × 0,05 à 0,9 de hauteur.
  Elle penche de 6° vers −Z (sommet à z ≈ −0,1) et se tord de 8° au plus, pour que deux facettes voisines
  n'aient jamais la même largeur vue de dos.
- **Sommet.** Un biseau de plume coupé net à 35° entre 0,9 et 1,0 : un plan incliné dont l'arête est
  transversale (le long de X).
- **Pied, l'empattement.** Deux congés concaves partent de la racine et se couchent **en travers du trait** :
  0,44 vers −X et 0,40 vers +X (la main n'est pas symétrique), mais seulement ±0,15 le long de Z. Ils font
  0,18 de haut contre la tige et descendent en courbe concave jusqu'à 0,02 au bout. Les bouts sont coupés
  carré, avec un petit relevé crocheté de 0,03. Vu de dessus, cela fait un ⊥, le pied d'une capitale romaine.
- **Enveloppe.** Rien au-delà de 0,46 du pivot dans le plan XZ. À la taille posée (1,44 R), cela fait 0,63 R ;
  écrasé à × 1,2, 0,76 R. La règle de portée au sol de `Volumes.spec` tient.
- **Cœur** (`SerifCore`, posé seulement sur la cinquième pointe). Le plan du biseau, recoupé dans les
  triangles du sommet et soulevé de 0,005 ; plus une strie de 0,02 de large sur l'arête avant (−Z), de 0,4 à
  0,85 de hauteur. Environ 6 % de la surface vue. Rien de pâle sur le pied.
- **Encre** (`SerifInk`). Une coque inversée de poids 0,035 à la racine et au pied, et 0,02 au sommet (soit
  0,25 → 0,14 stud à 7,2 studs de haut). Une rainure calligraphique (`surface_ribbon` de 0,035 de large) court
  sur la facette tournée vers le lanceur (+Z, côté +X), de 0,15 à 0,8. Le bord de la coque au sol dessine le ⊥
  sur la page.
- **Plafonds.** Pigment ≤ 300, Core ≤ 60, Ink ≤ 350 triangles. C'est sous le plafond par défaut de 450 : pas
  d'entrée `BODY_CAPS`.
- **Silhouette.** De dos (le lanceur), une tige brun foncé qui s'effile vers un biseau, sur un ⊥ ; de profil,
  une lame qui penche vers la cible ; de dessus, la barre d'empattement. Ce qui fait l'Empattement, ce sont le
  pied en travers, le biseau et la rampe de hauteurs. Ce n'est jamais un cône de roche.
- **Kit.** K1 lame de plume (`section="hex"`, `lean=6°`, `twist=8°`, `tip="chisel"`, `feet="serif"`) et K0
  trois rôles. La tige servira aux pleins de la Rupture, et le pied à la garde de l'Obèle.
- **Pose dans la timeline.**
  - Cinq couches par volume, `Face = "Ground"`, `SizeFrom = "Radius"` (`Radius` = `HitRadius` 5, passé par
    `VfxLibrary.Serif` : R8).
  - `Offset` avant 6 / 11 / 16 / 21 / 26 ; `Size` 1,04 / 1,14 / 1,24 / 1,34 / 1,44 (de 5,2 à 7,2 studs) ;
    `Jitter` ±0,15 rad.
  - Maillons de chaque pointe, chaque premier à son tick :
    - « frappe » : Quad Out 0,06 s, `Stretch` {0.7, 0.05, 0.7} → {1, 1.1, 1} (7,9 studs, sous le sommet de
      8) ;
    - « pose » : Sine Out 0,04 s → {1, 1, 1} ;
    - « affaissement » : Quad In 0,10 s → {1.2, 0.06, 1.2} ;
    - « empreinte » : Sine In 1,35 s (1,75 pour la cinquième) → {1.25, 0.02, 1.25}, transparence 0,1 → 1.
  - L'encre fait la frappe, puis la pose et un fondu en 0,07 s : 0,13 s en tout, deux encres vivantes au pic.
  - `Steady = true`. Retirés : 5 sprites `InkSpike`, 5 marques `InkBlot`, le `DustMote` du cœur. Pic 12 → 11.

### 13.2 Le Balayage (Sweep) — « le coup de brosse à plat »

- **Vérité du serveur.** Une seule passe à t = 0. Une sphère de `Radius` 12 est centrée à 10 studs devant la
  racine, à hauteur de racine ; au sol, elle fait un disque de rayon 11,62. Le lanceur est dans ce disque, à 10
  studs du centre. La poussée suit la visée (`Push` 70, `Lift` 30) : elle n'est pas radiale.
- **Maillages.** `GustBody` (Pigment), `GustCrest` (Core), `GustInk` (Ink).
- **Référence, axe, pivot.** `OuterDiameter` = 1 : l'encre extérieure, coque comprise, dans le plan. Axe Y.
  Pivot (0, 0, 0) au sol au centre du disque. L'ouverture est tournée vers +Z (le lanceur), et l'ensemble est
  **pré-tourné de −0,3 rad** autour de Y, pour que les volutes pointent le long de la visée à 0,2 s.
- **Bande.** Un secteur d'anneau de r 0,21 à 0,47 (la coque le porte à 0,50), sur un arc de 220° centré sur
  −Z (de −110° à +110° de la visée). La section monte du bord intérieur, posé à plat (0,005), vers une lèvre
  extérieure de 0,10 de haut côté tête et 0,06 côté queue.
- **Tête et queue.** La tête est chargée et arrondie, pressée, du côté −X : c'est là que va le balayage. La
  queue, côté +X, s'amincit à 0,12 de large radial et se fend en trois fouets (K5) de 0,06 / 0,09 / 0,13. Ils
  se détachent vers l'extérieur et se recourbent vers l'arc : **jamais dans l'ouverture**, et jamais au-delà
  de 120° de la visée. Le secteur de 120° côté lanceur reste vide à tout instant.
- **Volutes.** Quatre volutes de lèvre (K10) à environ −75°, −25°, +25° et +75° de la visée (variées à la main
  de ±5°). Chacune est un crochet roulé qui monte à 0,13 au plus (3 studs à la taille finale) et roule **vers
  −Z**, le sens de la poussée, et non vers l'extérieur. Leurs pointes, coque comprise, restent dans r ≤ 0,5.
- **Cœur.** Une petite coiffe sur le dessus de chaque volute (≤ 0,04 × 0,06) et deux stries de 0,02 × 0,12
  sur le dessus de la tête. Moins de 8 % de la surface vue. `Brightness` reste < 1,6, sans `Glow` : le vert
  chauffé vire au cyan.
- **Encre.** Une coque de poids 0,012 sur la bande (0,28 stud), 0,008 au bout des volutes et 0,006 sur les
  fouets. Cinq lignes de flux (`surface_ribbon` de 0,008 à 0,012 de large) couvrent de 0,3 à 0,7 de l'arc :
  longueurs inégales, elles suivent l'arc et se perdent dans les volutes. Le bord de la coque au sol dessine
  le contour.
- **Plafonds.** Pigment ≤ 1 000, Core ≤ 250, Ink ≤ 1 200 (à inscrire dans `BODY_CAPS`). C'est le sort le plus
  lancé : rester près de ces chiffres.
- **Silhouette.** De dos, le lanceur ne cache qu'une bande de ±1 stud droit devant ; les flancs, sur ±11
  studs, et les volutes sortent nettement de chaque côté de son corps. De dessus, c'est un C de vent ouvert
  vers le lanceur, chargé d'un bout et fendu de l'autre. Ce qui fait le Balayage, ce sont les volutes qui
  roulent toutes du même côté (la poussée lue en une image) et le fait qu'il reste bas.
- **Kit.** K10 nappe roulée (chemin : un arc au sol ; lèvre : des volutes vers l'avant), K5 fouets, K0.
  Servira à la Spirale, au Poncif et au bord du cône de `BossSweep`.
- **Pose dans la timeline.**
  - `Face = "Ground"`, `SizeFrom = "Radius"`, `Size` 1,93 : l'encre extérieure tombe à 11,58 studs, pour un
    disque de 11,62 au sol, et `Volumes.spec` exige ≥ 0,95.
  - `Spin` +1,5 rad/s ; `Jitter` 0 (la poussée a un sens).
  - « souffle » : Quart Out **0,10 s**, `Stretch` {0.72, 0.08, 0.72} → {1, 1.2, 1}. La carte proposait
    {0.72, 0.15, 0.72} en 0,08 s, ce que le test refuse.
  - « retombée » : Sine InOut 0,12 s → {1, 1, 1} ; l'encre y finit à transparence 1.
  - « couché » : Quad In 0,22 s → {1.03, 0.02, 1.03}, transparence 0 → 1.
  - Retiré : le croissant au sol. Gardés : la tache repoussée au bord, le cœur, les jets, la poussière, les
    papiers, la lumière, la trace `BrushStroke`. Pic 9 → 11.

### 13.3 La Bavure (Bleed) — « la Bavochure »

- **Vérité du serveur.** Le centre est fixe, à la racine plus 12 studs le long de la visée. La sphère a un
  `Radius` de 9 et est centrée à hauteur de racine. Elle boit à t = 0, 1 et 2 s (8 de dégâts et un
  ralentissement de 0,4 pendant 2,5 s), et elle est retirée si le lanceur s'arrête (D-141).
- **Maillages.** `BleedPool` (Pigment), `BleedSheen` (Core), `BleedInk` (Ink).
- **Référence, axe, pivot.** `OuterDiameter` = 1 (18 studs). Axe Y. Pivot au sol au centre. −Z est l'arc
  lointain. `Face = "Ground"`.
- **Mare.** Un anneau continu de r 0,25 à 0,40, au bord intérieur irrégulier. Il est gonflé en ménisque de
  0,02 à 0,033 de haut (0,35 à 0,6 stud), taillé en 8 à 10 plans durs. Le centre (r < 0,25) est vide : la
  tache du vélin se voit à travers.
- **Doigts.** Neuf doigts capillaires partent du bord à 0,40. Ils font de 0,03 à 0,06 de large à la racine,
  s'effilent sur des longueurs inégales, et finissent chacun par un crochet tourné dans le sens du flux. Leur
  pointe, coque comprise, touche **exactement** r = 0,5.
- **Perles.** Quatre perles détachées (K6) de 0,028 de diamètre, entre les doigts, à r 0,44-0,48.
- **Vrilles.** Sept vrilles creuses (K5, tube à trois pans, racine enfouie dans l'anneau), seulement sur l'arc
  lointain de 160° centré sur −Z. Racines à r 0,30-0,38, hauteur 0,09-0,13 (1,6 à 2,4 studs), épaisseur de
  0,03-0,04 à la racine. Elles montent puis se recourbent **vers le centre**, la pointe restant à r ≥ 0,15.
  Aucune à moins de 100° de +Z : elles ne doivent jamais se dresser au bas de l'écran du lanceur.
- **Cœur.** Un lobe sur la crête de chaque doigt (0,055 à 0,09 × 0,015) et une lèche sur l'extérieur de la
  courbe de chaque vrille (0,045 à 0,065), soulevés de 0,002.
- **Encre.** Une coque de poids 0,007 à 0,01 (0,12 à 0,18 stud), réduite à 0,004 au bout des vrilles. Sept
  lignes de flux sur le dessus de l'anneau, de 0,014 à 0,02 de large, de longueurs inégales : ce sont des
  spirales r = r₀·e^(bθ) avec b > 0 (θ de +X vers −Z), qui coulent vers l'intérieur avec un `Spin` de +0,3
  (§5.3). Le bord de la coque au sol fait le contour de la mare.
- **Plafonds.** Pigment ≤ 1 100, Core ≤ 280, Ink ≤ 1 400 (`BODY_CAPS`).
- **Silhouette.** Depuis le lanceur, la mare va de 14 à 32 studs de l'objectif. On lit son **bord** : une
  ellipse indigo épaisse cernée d'encre, avec neuf doigts crochus qui encadrent le lanceur de chaque côté. Les
  vrilles se tiennent comme des crochets autour des tibias des cibles, sous la taille. Ce qui fait la
  Bavure : de l'encre mouillée qui saisit, et plus d'air que de mare (au moins la moitié du disque est vide).
  Jamais un nuage.
- **Kit.** K6 éclaboussure en relief (centre ouvert, doigts, perles), K5 vrilles, chemin de spirale de K8 pour
  les lignes de flux, K0. Servira à la rosette de la Reliure, à la tache du Pâté et aux marques du Lavis.
- **Pose dans la timeline.**
  - `Face = "Ground"`, `SizeFrom = "Radius"`, `Size` 2, `Spin` +0,3, `Jitter` 0.
  - « éclaboussure » : Quart Out 0,14 s, {0.85, 0.05, 0.85} → {0.96, 1.45, 0.96}.
  - « repos » : Sine Out jusqu'à 1,0 s → {1, 1, 1}.
  - « gorgée » : Back Out 0,12 s → {0.96, 1.45, 0.96}, puis repos, puis une troisième gorgée à 2,0 s.
  - « enfoncement » : Quad In de 2,12 à 2,5 s → {1, 0.02, 1}, l'encre d'abord.
  - Les gorgées sont écrites par R7. Le retrait passe par R5.
  - XZ ne passe jamais 1, et ne finit jamais un maillon sous 0,96.
  - Retiré : l'`Enso`, puisque la coque est le bord. Une `Mark` de repli reste pour `overWarning`. Gardés :
    l'anneau de choc qui se referme, la pointe de chaque gorgée (test), le cœur, la lumière, les perles
    aspirées, les taches. Pic 7 → 9.

### 13.4 Le Roussi (Scorch) — « le Fleuron »

- **Vérité du serveur.** Une sphère de `Radius` 13, re-centrée sur la racine validée du lanceur **à chaque
  tick** (t = 0 ; 0,8 ; 1,6 s), 10 de dégâts par tick. Rien ne brûle après 1,6 s. Elle est retirée si le
  lanceur s'arrête.
- **Maillages.** `ScorchCrown` (Pigment), `ScorchCore` (Core), `ScorchInk` (Ink).
- **Référence, axe, pivot.** `OuterDiameter` = 1 (26 studs). Axe Y. Pivot au sol, sous la racine du lanceur.
- **Anneau de base.** Fermé, de r 0,466 à 0,494, 0,0096 de haut (0,25 stud) ; la coque le porte à 0,5.
- **Langues.** Douze langues (K4, debout), longues et courtes alternées. Les longues font 0,123 de haut (3,2
  studs), les courtes 0,085 (2,2), et elles font de 0,062 à 0,085 à leur plus large. Chacune est une virgule :
  racine étroite (0,03) sur la moitié intérieure de l'anneau, plus large à 0,6 de sa hauteur, puis une pointe
  vive avec un dernier crochet **tangentiel**. Tous les crochets tournent dans le même sens : ils traînent
  contre `Spin` −1,2, donc vers +θ.
- **Inclinaison et sections.** Les langues penchent vers l'extérieur de 8° au plus, avec pointe et coque à
  r ≤ 0,5. Elles ont une section en dalle plate (`blade()`), et leur face tourne d'environ 30° vers la
  tangente : on voit des lames sous tous les angles, jamais des tranches.
- **Cœur.** Une strie de 0,012 à 0,019 de large sur les deux faces de chaque langue, de 0,15 à 0,8 de sa
  hauteur (`fireball.streak`), et un fil chaud de 0,006 sur le dessus de l'anneau.
- **Encre.** Une coque de poids 0,006 à 0,008 aux racines (0,15 à 0,2 stud) et 0,004 aux pointes, autour de
  chaque langue et de l'anneau. Le contour extérieur de l'anneau est posé au sol à r = 0,5.
- **Plafonds.** Pigment ≤ 1 200, Core ≤ 320, Ink ≤ 1 300 (`BODY_CAPS`).
- **Silhouette.** La caméra du lanceur est **dans** l'anneau (11 studs < 13). La couronne encadre tout
  l'écran : l'arc lointain est à 24 studs, et les arcs latéraux passent dans les coins bas. Les langues, de
  2,2 à 4,5 studs, restent sous la ligne de l'œil à 8 studs. Vu par un attaquant au corps-à-corps, c'est un
  anneau crochu au rayon exact, avec le lanceur dans l'œil. Ce qui fait le Roussi : le tourbillon de la
  Marque, déroulé en couronne de fleuron, qui bondit d'un bloc.
- **Kit.** K4 langue crochue, posée par K7 anneau-mur ; K0. Servira à la Ligature et au bouton de la
  Rubrique, et K7 au Gaufrage, à la Dorure et au Cartouche.
- **Pose dans la timeline.**
  - `Face = "Ground"` + `Follow` (R2 : position seule, sol sondé sous le corps), `SizeFrom = "Radius"`,
    `Size` 2, `Spin` −1,2, `Jitter` π.
  - « éruption » : Back Out 0,12 s au premier tick, {1, 0.05, 1} → {1, 1.35, 1}.
  - « repos » : Sine Out jusqu'à 0,77 → {1, 0.85, 1}.
  - « bond » : Back Out 0,10 s, qui démarre sur le tick 0,8 → {1, 1.4, 1} (4,5 studs, sous le dôme de 6,2 à
    r 12,6) ; puis repos, puis un bond sur le tick 1,6.
  - « effondrement » : Quad In de 1,67 à 1,95 → {1, 0.02, 1}, l'encre d'abord.
  - Les bonds sont écrits par R7 ; le retrait passe par R5.
  - Retirés : les trois rafales `InkFlame` par tick et les anneaux de flamme `Core` et `Ink`. Gardés : **un**
    anneau `InkFlame` de pigment piloté (environ 60/s, pour le scintillement et le test « a fire »), le cœur
    aux pieds, la lumière qui suit, le sceau au bord, la brûlure posée là où se tenait le lanceur au dernier
    tick. Particules 358 → environ 150 ; pic 10 → 9.

### 13.5 La Rupture — « la Couronne de pleins »

- **Vérité du serveur.** Une seule passe à la racine du lanceur, fixe. La sphère a un `Radius` de 18 (36 de
  diamètre) ; 35 de dégâts (`Ultimate`), une projection **verticale** (`Launch` 60) pendant 0,25 s et un
  étourdissement de 0,8 s.
- **Maillages.** `DownstrokeBody` (Pigment), `DownstrokeCore` (Core), `DownstrokeInk` (Ink). Corps sur
  mesure : `tools/meshes/rupture.py`.
- **Référence, axe, pivot.** `OuterDiameter` = 1 (36 studs). Axe Y. Pivot au sol sous la racine. Avant = −Z
  (la visée). **Encoche : aucune pièce à moins de 40° de +Z.**
- **Pleins.** Trois rangs de lames K1 à section en lentille à 4 pans. Chacune a une lèvre de racine biseautée
  au carré (la trace du bec), tourne d'un quart de tour en montant, s'effile, et finit en crochet couché
  tangentiellement, dans le sens du tourbillon.
  - **4 grands pleins** à r 0,17-0,22 et à ±50° et ±110° de −Z : hauteurs 0,264 (−50°), 0,25 (+50°), 0,236
    (+110°) et 0,222 (−110°), soit de 8 à 9,5 studs. Racine 0,05 × 0,014 (1,8 × 0,5 studs), 0,012 près du
    sommet. Aucun grand plein dans l'axe : une cible droit devant, entre 8 et 15 studs, apparaît entre eux.
  - **6 pleins moyens** à r 0,31-0,39, à ±25°, ±75° et ±130°, de 0,111 à 0,167 de haut (4 à 6 studs). Le
    couloir de ±15° autour de la visée reste libre.
  - **6 dents de bord** à r 0,43-0,486, à ±20°, ±70° et ±125°, de 0,042 à 0,069 de haut. Leurs lèvres de
    racine, coque comprise, tombent à r = 0,5.
- **Lèvres et col.** Au pied de chaque grand plein et de chaque plein moyen, une lèvre de page déchirée : 3 à
  4 rabats dentelés de 0,012, cernés d'encre. Au centre, un col bas de page soulevée, à r 0,069-0,097, haut de
  0,033 au plus, en 5 rabats, ouvert lui aussi vers +Z. Aucune lame à r < 0,11 : le lanceur est là, et la
  caméra regarde au travers.
- **Dôme.** Tout tient sous h ≤ √(18² − r²) + 3 (en studs).
- **Cœur.** Un lobe pâle sur la face extérieure de chaque plein, sous son crochet, sur 25 à 35 % de la
  hauteur de la lame, coupé dans ses triangles et soulevé de 0,002 (0,07 stud). Les lobes doivent être assez
  grands pour se lire à 20 studs : la Terre d'Ombre n'a que 2,93 de contraste sur le sol d'entraînement.
- **Encre.** Une coque par lame et par rabat, de poids 0,003 à 0,004 (0,11 à 0,14 stud), plus lourde aux
  racines. Deux lignes de flux par grand plein, qui suivent la torsion, et une bouche de fissure sombre posée
  au sol à chaque racine (soulevée de 0,004). S'il faut gagner des triangles, on retire d'abord les lignes des
  dents.
- **Plafonds.** Pigment ≤ 1 500, Core ≤ 280, Ink ≤ 1 750 (`BODY_CAPS`, grand corps).
- **Silhouette.** La caméra est à l'intérieur (10-12 studs < 18), du côté ouvert : rien ne monte entre
  l'objectif et le lanceur. Devant et sur les côtés, un anneau de lames brunes à crochets pâles jaillit de la
  page ; les cibles montent au-dessus des lames, projetées. Un adversaire voit une couronne pleine, ouverte
  seulement côté lanceur. De dessus, les crochets dessinent la spirale de la planche du Lavis. Ce qui fait la
  Rupture : des pleins de plume plantés à l'envers, presque verticaux, parce que le serveur projette tout
  droit vers le haut.
- **Kit.** K1 (pleins, rabats de lèvre), placés par K7 en fer à cheval sur trois rayons ; K0. Les pleins
  serviront à l'Obèle, et le fer à cheval aux ultimes suivants.
- **Pose dans la timeline.**
  - `Face = "Ground"`, `SizeFrom = "Radius"`, `Size` 2 (XZ tenu à 1 sur tous les maillons), `Spin` +0,5,
    `Jitter` 0 : l'encoche fait toujours face au lanceur.
  - « éruption » : Back Out **0,12 s** (0,10 s refusé par le test : 62 % dans la première image),
    {1, 0.04, 1} → {1, 1, 1}. Seul Y dépasse, jusqu'à environ 1,1.
  - « tenue » : Sine InOut de 0,12 à 0,20 → {1, 0.9, 1}.
  - « enfoncement » : Quad In de 0,20 à 0,34 → {1, 0.03, 1}. L'encre devient transparente pendant
    l'enfoncement, puis le cœur, et le pigment part déjà à plat. Le corps est haut pendant environ 0,32 s.
  - Retirés : les cinq sprites `InkSpike`, dont celui du cœur posé sur le lanceur. Gardés : les fissures en
    deux temps, l'`Enso` au rayon, le flash, le geyser de grains, la lumière, la secousse `Heavy`, le
    `PageFlash`, la trace. Pic 12 → 10.

---

## 14. Validation et questions ouvertes

**La méthode, pour chaque corps.**
1. La recette Python et la planche `preview.py` (six vues et la vue de zone), corrigées jusqu'à ce qu'elles
   tiennent. Pour un corps sur mesure, un juge choisit entre deux constructions, puis un relecteur
   indépendant vérifie.
2. **L'accord du développeur**, puis le téléversement (`scripts/upload_assets.py`) et les identifiants lus dans
   Studio.
3. Le labo Studio : planches avant / après, au moins deux tours, la grille des six critères, et `stress` à 6×
   en Élevé et en Performance.
4. Les tests (le style, les volumes, les plafonds), chacun prouvé par mutation ; `docs/DECISIONS.md`,
   `docs/PROGRESS.md` et `docs/vfx/<glyphe>/README.md`.

**Les questions pour le développeur.**
1. **La Marge dans le lot 1 ?** Elle est débloquée par défaut et dans le deck de départ ; elle attend R2
   (suivre la dalle) et la reprise quand la dalle est retirée.
2. **Des textes à reformuler (EN et FR, sans toucher au gameplay).** Le Balayage dit « cône de vent » mais le
   serveur frappe un disque. La Bavure dit « nuage brûlant » : c'est une mare qui saisit. Le Poncif dit
   « aveugle », et rien n'aveugle dans le code. L'Empattement dit « pointes de roche » : elles restent
   d'encre.
3. **Le Pâté qui éclate en l'air.** Le plus souvent, il éclate à environ 9,5 studs de haut et à 66 studs de
   distance, et sa sphère ne touche le sol que sur un rayon de 3. L'`Enso` et la couronne d'`Explosion` sont
   pourtant dessinés en grand au sol, au-delà du mal. Faut-il que l'arc touche le sol ? C'est une décision de
   gameplay, hors de cette passe. L'étoile, elle, sera dessinée en l'air.
4. **R3** : le Délié et le Pointillé passent sur un paquet fiable avec `Fizzle`. C'est un changement de paquet
   côté serveur, sans chiffre ni temps qui bouge. Accord ?
5. **Le Colophon** mérite-t-il d'avancer, comme vitrine du game pass Orpiment ?
6. **R6** : l'ordre d'éviction au plafond de couches. Faut-il protéger le corps entier, ou au moins son
   encre ?
