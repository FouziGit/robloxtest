# Performance

Ce que le client paie, ce qu'il est autorisé à payer, et ce qu'il coupe tout seul quand il n'y arrive
plus. Les trois questions de la passe 9 du plan (`docs/JUICE_PLAN.md`), plus la règle 8 de
`docs/ART_BIBLE.md` : « la densité de particules est plafonnée et diminue avec le nombre de joueurs
proches et le réglage graphique. Un effet qu'on ne peut pas afficher est un effet qu'on ne joue pas. »

La règle parle aussi du **nombre de joueurs proches**. Il n'y a pas de compteur de voisins : la
dégradation automatique le remplace par sa conséquence — six joueurs qui lancent tout en même temps font
tomber les images par seconde, et c'est ce que le client mesure. C'est un choix (D-93), pas un oubli : un
compteur de voisins amincirait l'image d'un joueur dont la machine n'a aucun problème, et raterait le
joueur seul sur un téléphone de 2018.

**Ce document ne contient aucun nombre inventé.** Le tableau des coûts est la sortie de
`lune run scripts/effect-cost -- --table`, calculée depuis les données qui dessinent les effets ;
`tests/EffectCost.spec.luau` tient chaque plafond à chaque passage des portes. Ce qui n'a **pas** été
mesuré est dit tel quel à la fin.

## Les quatre niveaux

`src/shared/Config/QualityConfig.luau`. Le joueur choisit le sien dans l'onglet **Graphismes** des
options ; son choix est un **plafond** que le client peut descendre, jamais dépasser.

| Niveau | Couches vivantes | Particules | Lumières | Post-traitement | Empreintes |
|---|---|---|---|---|---|
| Élevée | 90 | ×1 | oui | oui | ×1 |
| Moyenne | 60 | ×0,6 | oui | oui | ×0,5 |
| Basse | 36 | ×0,35 | **non** | oui | aucune |
| Performance | 24 | ×0,2 | non | **non** | aucune |

Chaque champ a exactement un lecteur, et un test le vérifie dans la source du lecteur : un champ que
personne ne lit est une promesse faite au joueur que rien ne tient.

- **Couches vivantes** — `VfxTimeline` : au-delà, la couche ordinaire la plus vieille est retirée tôt.
  **Jamais un avertissement** : une télégraphie est une règle que six joueurs lisent, et c'est la couche
  la plus vieille de l'écran au moment où le budget est plein.
- **Particules** — `VfxTimeline` multiplie `Rate` et `Burst` de chaque émetteur. Plancher à une particule :
  un impact sans aucun grain se lit comme un effet manquant, pas comme un effet allégé.
- **Lumières** — `VfxTimeline` ne dessine pas du tout une couche `Light`. Roblox paie une lumière locale
  qu'elle éclaire une surface ou non ; rien que le joueur doive **lire** n'est une lumière (chaque
  télégraphie est une marque), donc les couper amincit l'image sans toucher à une règle.
- **Post-traitement** — `WorldLighting` désactive les cinq effets. Le monde reste clair et pâle : c'est
  `Lighting` lui-même, pas eux.
- **Empreintes** — `FootprintController` prend cette part de son propre budget (0 = aucune).

## La dégradation automatique

`src/client/Controllers/QualityController.luau` compte les images sur une seconde et compare :

| | |
|---|---|
| descend d'un niveau | sous **40 images/s** pendant **3 s** |
| remonte d'un niveau | au-dessus de **55 images/s** pendant **12 s**, jamais au-dessus du choix du joueur |
| entre les deux | rien ne bouge |

L'écart entre 40 et 55 est ce qui empêche un client posé à cinquante images de descendre et remonter sans
fin. Remonter est **quatre fois plus lent** que descendre, parce que chaque changement rallume le
post-traitement, ce qui compile des shaders : un niveau qui oscille coûte plus cher que le niveau qu'il
essayait de quitter. La mesure est volontairement bête — des images comptées sur une seconde — parce que
la décision qu'elle nourrit est grossière ; un estimateur plus fin bougerait le niveau sur un seul
à-coup.

## Ce que coûte chaque effet

Sortie de `lune run scripts/effect-cost -- --table`. « Pic simultané » est le nombre de couches vivantes
en même temps au pire instant de l'effet — c'est ce que le budget ci-dessus dépense. « Instances » est ce
que l'effet emprunte au pool. Les phases à fenêtre sont mesurées à la fenêtre la plus longue que la
configuration autorise (`MaxWindowSeconds`), donc au pire cas.

| Effet | Couches | Pic simultané | Durée (s) | Particules | Instances | Part | Decal | Emitter | Attach | Trail | Beam | Light |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Binding | 13 | 6 | 2.70 | 53 | 25 | 10 | 8 | 3 | 2 | 0 | 1 | 1 |
| Bleed | 13 | 6 | 4.60 | 52 | 28 | 11 | 3 | 2 | 6 | 0 | 3 | 3 |
| Blot | 17 | 8 | 2.70 | 136 | 29 | 13 | 1 | 7 | 4 | 1 | 1 | 2 |
| BossDefeated | 16 | 7 | 3.30 | 123 | 24 | 12 | 6 | 4 | 0 | 0 | 0 | 2 |
| BossEruption | 20 | 10 | 4.30 | 156 | 30 | 15 | 6 | 7 | 0 | 0 | 0 | 2 |
| BossEruptionSafe | 4 | 3 | 3.80 | 22 | 8 | 4 | 3 | 1 | 0 | 0 | 0 | 0 |
| BossFury | 20 | 8 | 4.50 | 146 | 28 | 14 | 8 | 4 | 0 | 0 | 0 | 2 |
| BossPhase | 8 | 5 | 3.30 | 52 | 10 | 5 | 2 | 2 | 0 | 0 | 0 | 1 |
| BossScour | 4 | 4 | 1.60 | 11 | 8 | 4 | 2 | 1 | 0 | 0 | 0 | 1 |
| BossSlam | 17 | 8 | 4.00 | 103 | 24 | 12 | 6 | 4 | 0 | 0 | 0 | 2 |
| BossSpawn | 17 | 8 | 3.30 | 130 | 26 | 13 | 6 | 5 | 0 | 0 | 0 | 2 |
| BossSweep | 20 | 10 | 4.00 | 98 | 30 | 15 | 9 | 4 | 0 | 0 | 0 | 2 |
| Brand | 10 | 5 | 1.80 | 47 | 17 | 8 | 0 | 4 | 2 | 1 | 0 | 2 |
| Caret | 15 | 9 | 1.08 | 76 | 27 | 12 | 6 | 4 | 2 | 1 | 0 | 2 |
| Cast | 9 | 4 | 0.84 | 32 | 18 | 7 | 4 | 3 | 2 | 0 | 1 | 1 |
| Colophon | 16 | 7 | 2.38 | 64 | 31 | 12 | 8 | 3 | 4 | 0 | 2 | 2 |
| ColophonLink | 11 | 7 | 1.91 | 48 | 23 | 9 | 4 | 3 | 4 | 0 | 2 | 1 |
| Dash | 5 | 3 | 0.87 | 12 | 12 | 5 | 1 | 2 | 2 | 1 | 0 | 1 |
| Explosion | 10 | 7 | 3.22 | 44 | 15 | 7 | 4 | 3 | 0 | 0 | 0 | 1 |
| Gilding | 17 | 4 | 4.00 | 42 | 44 | 14 | 5 | 3 | 14 | 7 | 0 | 1 |
| Hairline | 12 | 6 | 1.11 | 27 | 23 | 9 | 0 | 3 | 6 | 2 | 1 | 2 |
| Hit | 6 | 4 | 2.58 | 20 | 11 | 5 | 3 | 2 | 0 | 0 | 0 | 1 |
| Ligature | 27 | 10 | 3.06 | 108 | 51 | 25 | 11 | 7 | 2 | 1 | 0 | 5 |
| Margin | 14 | 6 | 5.46 | 39 | 28 | 11 | 14 | 2 | 0 | 0 | 0 | 1 |
| Melee | 5 | 3 | 0.46 | 14 | 11 | 5 | 2 | 3 | 0 | 0 | 0 | 1 |
| Pounce | 14 | 6 | 4.82 | 201 | 26 | 13 | 5 | 7 | 0 | 0 | 0 | 1 |
| Rupture | 13 | 7 | 3.27 | 112 | 20 | 10 | 4 | 4 | 0 | 0 | 0 | 2 |
| Scorch | 20 | 9 | 3.36 | 62 | 44 | 17 | 5 | 4 | 10 | 5 | 0 | 3 |
| Serif | 19 | 11 | 2.30 | 80 | 36 | 16 | 5 | 7 | 4 | 0 | 2 | 2 |
| Spiral | 16 | 7 | 4.70 | 109 | 22 | 11 | 6 | 4 | 0 | 0 | 0 | 1 |
| Stipple | 12 | 8 | 2.36 | 53 | 20 | 9 | 2 | 4 | 2 | 1 | 0 | 2 |
| Strike | 12 | 8 | 0.91 | 56 | 19 | 9 | 1 | 4 | 2 | 1 | 0 | 2 |
| Sweep | 12 | 7 | 1.24 | 65 | 20 | 9 | 6 | 4 | 0 | 0 | 0 | 1 |
| Wash | 15 | 9 | 3.00 | 50 | 26 | 12 | 6 | 4 | 2 | 1 | 0 | 1 |
| Watermark | 18 | 5 | 4.34 | 115 | 26 | 13 | 3 | 5 | 0 | 0 | 0 | 5 |

**Lecture.** 35 timelines, 477 layers in total. Worst effect: 11 layers alive at once, 201 particles, 51 instances borrowed. Le budget du niveau le plus élevé tient donc huit fois le
pire effet, et celui du niveau **Performance** deux fois — ce que `tests/EffectCost.spec.luau` exige de
chaque effet : un effet qui ne tiendrait pas deux fois dans le plancher rendrait la machine la plus faible
incapable de montrer deux effets à la fois.

Les trois plafonds que la porte dérive au lieu de les choisir :

| Plafond | Dérivé de | Valeur aujourd'hui |
|---|---|---|
| pic de couches d'un effet | moitié du budget du niveau plancher | ≤ 12 (pire : 11, `Serif`) |
| instances d'un effet par classe | quatre copies doivent tenir sous chaque plafond de `PoolPolicy` | pire : 5 lumières (`Ligature`, `Watermark`) contre 24/4 = 6 |
| particules d'un effet | deux fois le pire effet au niveau le plus élevé | ≤ 400 (pire : 201, `Poncif`) |

## Le pooling

`src/client/Controllers/VfxPool` (le moteur) et `src/shared/Pure/PoolPolicy` (la comptabilité, testée sans
moteur). Deux plafonds par classe, parce qu'ils répondent à deux questions : `Live` est un budget de
rendu — une demande au-delà est **refusée** et le rendu perd une couche, pas le jeu ses images —, `Parked`
est un budget de mémoire, ce qu'on garde chaud entre deux effets.

| Classe | Live | Parked |
|---|---|---|
| Part | 240 | 64 |
| Decal | 200 | 48 |
| ParticleEmitter | 120 | 32 |
| Attachment | 160 | 48 |
| Trail | 48 | 16 |
| Beam | 40 | 12 |
| PointLight | 24 | 8 |

Remise à blanc **à l'emprunt**, jamais au retour : une instance rendue avec une couleur oubliée est le bug
de pooling que tout le monde écrit une fois, et il sort à l'écran comme un effet portant la couleur de
l'école précédente — ce que la règle 2 de la bible ne survit pas.

## Ce qui est vérifié, et comment

| Promesse | Porte |
|---|---|
| chaque effet sous ses trois plafonds | `tests/EffectCost.spec.luau` (depuis `scripts/effect-cost.luau`) |
| les niveaux ordonnés, chaque descente moins chère, le plancher seul sans post-traitement | `tests/EffectCost.spec.luau` |
| chaque champ de niveau lu par quelqu'un | `tests/EffectCost.spec.luau` (lit la source du lecteur) |
| **un duel ne laisse aucune instance derrière lui** | `tests/PoolPolicy.spec.luau` : 180 effets, quatre superposés au pic, retour à zéro vivant, zéro retour refusé, rien de garé au-dessus du plafond |
| le pool crée bien moins qu'il ne prête | idem : plus de 5 000 prêts pour moins de 2 % de créations |
| **un duel ne laisse aucune connexion derrière lui** | `tests/Loops.spec.luau` : une boucle par système, quinze en tout, chacune déclarée avec sa raison ; une seconde boucle dans un système qui en a déjà une échoue |
| la densité plafonnée (règle 8) | `VfxTimelineConfig.MaxLiveLayers` = niveau Élevé, et la porte ci-dessus |

## Ce qui n'est pas mesuré

**Aucun nombre d'images par seconde de ce document ne vient d'un appareil.** Les coûts sont ce que le
rendu **va** emprunter et demander, ce que le dépôt peut savoir exactement ; ce qu'une image prend ensuite
sur un téléphone donné est l'autre moitié, et elle demande cet appareil. Les seuils de 40 et 55 images/s
sont les valeurs usuelles d'un client Roblox mobile, pas une mesure : ce sont les deux nombres à corriger
en premier avec un appareil en main.

Rien de la passe 9 n'a tourné dans un client. La dégradation n'a donc jamais été **vue** descendre ni
remonter, et les quatre niveaux n'ont pas été comparés à l'œil : ce sont des budgets tenus par des tests,
pas un réglage éprouvé. Le mode Performance en particulier échange le post-traitement contre des images —
c'est la bonne direction, mais le point exact où il devient laid appartient à l'appareil.
