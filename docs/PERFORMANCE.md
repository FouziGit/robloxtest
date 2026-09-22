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
fin. Remonter est **quatre fois plus lent** que descendre, parce que la transition qui traverse le niveau
Performance rallume les cinq effets de post-traitement, ce qui compile des shaders : un niveau qui oscille
là-dessus coûte plus cher que celui qu'il essayait de quitter.

Un échantillon ne compte **au plus que sa propre durée**. Sans ce plafond, un seul gel de trois secondes —
un niveau qui charge, un téléport, un personnage qui apparaît — arrivait comme un échantillon de trois
secondes à un tiers d'image par seconde et satisfaisait « trois secondes sous quarante » à lui tout seul :
un à-coup coûtait un niveau. Il faut maintenant trois **échantillons** mauvais, c'est-à-dire trois secondes
à être vraiment lent.

Trois valeurs, pas deux : le choix du joueur est un **plafond**, ce que les images par seconde ont décidé
est un second niveau tenu à part, et ce qui est dessiné est le **pire des deux**. C'est ce qui fait qu'un
joueur déjà rétrogradé qui choisit un niveau plus bas obtient bien le plus bas — écrire son choix
directement dans le niveau dessiné le faisait **remonter**.

## Ce que coûte chaque effet

Sortie de `lune run scripts/effect-cost -- --table`. « Pic simultané » est le nombre de couches vivantes
en même temps au pire instant de l'effet — c'est ce que le budget ci-dessus dépense. « Instances » est ce
que l'effet emprunte au pool. Les phases à fenêtre sont mesurées à la fenêtre la plus longue que la
configuration autorise (`MaxWindowSeconds`), donc au pire cas.

| Effet | Couches | Dessinées | Pic simultané | Durée (s) | Particules | Instances au pic | Part | Decal | Emitter | Attach | Trail | Beam | Light |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Binding | 13 | 10 | 5 | 2.70 | 53 | 15 | 6 | 4 | 1 | 2 | 0 | 1 | 1 |
| Bleed | 13 | 11 | 4 | 4.60 | 52 | 11 | 5 | 1 | 1 | 2 | 0 | 1 | 1 |
| Blot | 17 | 13 | 7 | 2.70 | 136 | 18 | 8 | 1 | 2 | 4 | 1 | 1 | 1 |
| BossDefeated | 16 | 12 | 5 | 3.30 | 123 | 10 | 5 | 2 | 2 | 0 | 0 | 0 | 1 |
| BossEruption | 20 | 15 | 7 | 4.30 | 156 | 14 | 7 | 3 | 3 | 0 | 0 | 0 | 1 |
| BossEruptionSafe | 4 | 4 | 3 | 3.80 | 22 | 6 | 3 | 2 | 1 | 0 | 0 | 0 | 0 |
| BossFury | 20 | 14 | 6 | 4.50 | 146 | 13 | 6 | 4 | 2 | 0 | 0 | 0 | 1 |
| BossPhase | 8 | 5 | 2 | 3.30 | 52 | 5 | 2 | 1 | 1 | 0 | 0 | 0 | 1 |
| BossScour | 4 | 4 | 4 | 1.60 | 11 | 8 | 4 | 2 | 1 | 0 | 0 | 0 | 1 |
| BossSlam | 17 | 12 | 5 | 4.00 | 103 | 11 | 5 | 3 | 2 | 0 | 0 | 0 | 1 |
| BossSpawn | 17 | 13 | 6 | 3.30 | 130 | 12 | 6 | 2 | 3 | 0 | 0 | 0 | 1 |
| BossSweep | 20 | 15 | 8 | 4.00 | 98 | 17 | 8 | 6 | 2 | 0 | 0 | 0 | 1 |
| Brand | 10 | 8 | 4 | 1.80 | 47 | 9 | 4 | 0 | 1 | 2 | 1 | 0 | 1 |
| Caret | 15 | 12 | 8 | 1.08 | 76 | 19 | 8 | 4 | 3 | 2 | 1 | 0 | 1 |
| Cast | 9 | 7 | 4 | 0.84 | 32 | 15 | 5 | 4 | 2 | 2 | 0 | 1 | 1 |
| Colophon | 16 | 12 | 7 | 2.38 | 64 | 24 | 8 | 6 | 2 | 4 | 0 | 2 | 2 |
| ColophonLink | 11 | 9 | 6 | 1.91 | 48 | 20 | 7 | 4 | 2 | 4 | 0 | 2 | 1 |
| Dash | 5 | 5 | 3 | 0.87 | 12 | 9 | 3 | 1 | 1 | 2 | 1 | 0 | 1 |
| Explosion | 10 | 7 | 5 | 3.22 | 44 | 12 | 5 | 4 | 2 | 0 | 0 | 0 | 1 |
| Gilding | 17 | 14 | 4 | 4.00 | 42 | 16 | 4 | 4 | 1 | 4 | 2 | 0 | 1 |
| Hairline | 12 | 9 | 5 | 1.11 | 27 | 17 | 6 | 0 | 1 | 6 | 2 | 1 | 1 |
| Hit | 6 | 5 | 3 | 2.58 | 20 | 8 | 3 | 3 | 1 | 0 | 0 | 0 | 1 |
| Ligature | 27 | 25 | 10 | 3.06 | 108 | 23 | 10 | 6 | 3 | 2 | 1 | 0 | 1 |
| Margin | 14 | 11 | 5 | 5.46 | 39 | 12 | 5 | 5 | 1 | 0 | 0 | 0 | 1 |
| Melee | 5 | 5 | 3 | 0.46 | 14 | 7 | 3 | 2 | 1 | 0 | 0 | 0 | 1 |
| Pounce | 14 | 13 | 6 | 4.82 | 201 | 12 | 6 | 2 | 3 | 0 | 0 | 0 | 1 |
| Rupture | 13 | 10 | 4 | 3.27 | 112 | 11 | 4 | 3 | 2 | 0 | 0 | 0 | 2 |
| Scorch | 20 | 17 | 8 | 3.36 | 62 | 26 | 8 | 3 | 1 | 8 | 4 | 0 | 2 |
| Serif | 19 | 16 | 10 | 2.30 | 80 | 27 | 12 | 5 | 2 | 4 | 0 | 2 | 2 |
| Spiral | 16 | 11 | 5 | 4.70 | 109 | 10 | 5 | 2 | 2 | 0 | 0 | 0 | 1 |
| Stipple | 12 | 9 | 6 | 2.36 | 53 | 14 | 6 | 2 | 2 | 2 | 1 | 0 | 1 |
| Strike | 12 | 9 | 6 | 0.91 | 56 | 15 | 6 | 1 | 3 | 2 | 1 | 0 | 2 |
| Sweep | 12 | 9 | 5 | 1.24 | 65 | 12 | 5 | 5 | 1 | 0 | 0 | 0 | 1 |
| Wash | 15 | 12 | 8 | 3.00 | 50 | 18 | 8 | 5 | 1 | 2 | 1 | 0 | 1 |
| Watermark | 18 | 13 | 4 | 4.34 | 115 | 9 | 4 | 2 | 2 | 0 | 0 | 0 | 1 |

**Lecture.** 35 timelines et 477 couches, dont 376 qui prennent une place du budget. Pire effet : 10 couches vivantes au même instant, 201 particules, 27 instances empruntées au pic. Le budget du niveau le plus élevé tient donc neuf fois le
pire effet, et celui du niveau **Performance** deux fois — ce que `tests/EffectCost.spec.luau` exige de
chaque effet : un effet qui ne tiendrait pas deux fois dans le plancher rendrait la machine la plus faible
incapable de montrer deux effets à la fois.

Trois colonnes valent une explication. « Couches » compte tout ce que la timeline déclare ; « Dessinées »
n'en garde que ce qui occupe une place du budget — une secousse, un éclair d'écran et un son sont remis à
`Feel`, `WorldLighting` et `SoundController` et n'y reviennent jamais ; « Instances au pic » est ce que
l'effet emprunte **au même instant**, pas sur sa vie entière, parce qu'un plafond de pool est une limite de
simultanéité.

Trois plafonds, dont **deux dérivés** d'un autre nombre du dépôt et un **choisi** :

| Plafond | D'où il vient | Valeur aujourd'hui |
|---|---|---|
| pic de couches d'un effet | moitié du budget du niveau plancher (24) | ≤ 12 (pire : 10, `Serif`) |
| instances d'un effet par classe, au pic | quatre copies doivent tenir sous chaque plafond de `PoolPolicy` | pire : 3 lumières (`Ligature`) contre 24/4 = 6 |
| particules d'un effet | **choisi** : environ deux fois ce que le pire effet demande | ≤ 400 (pire : 201, `Pounce`) |

Le troisième est un cliquet contre la dérive, pas une mesure : **aucun appareil n'a fait tourner ce jeu**,
et c'est le premier nombre à remplacer par une mesure. Une porte tient aussi le modèle de coût au rendu
lui-même : si une couche empruntait une classe que le modèle ne connaît pas, chaque comparaison ci-dessus
serait optimiste, donc le test relit les emprunts dans la source du rendu.

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
| les empreintes ne peuvent évincer un résidu **à aucun niveau** | `tests/WorldConfig.spec.luau` : le seuil de retenue est une **fraction** du budget du niveau dessiné (0,66), et la somme seuil + empreintes tient dans le budget de chacun des quatre |
| le modèle de coût emprunte ce que le rendu emprunte | `tests/EffectCost.spec.luau` relit les emprunts dans la source de `VfxTimeline` |

## Ce qui n'est pas mesuré

**Aucun nombre d'images par seconde de ce document ne vient d'un appareil.** Les coûts sont ce que le
rendu **va** emprunter et demander, ce que le dépôt peut savoir exactement ; ce qu'une image prend ensuite
sur un téléphone donné est l'autre moitié, et elle demande cet appareil. Les seuils de 40 et 55 images/s
sont les valeurs usuelles d'un client Roblox mobile, pas une mesure : ce sont les deux nombres à corriger
en premier avec un appareil en main.

**Comment les mesurer.** Dans Studio : `View → Performance Stats` (ou `Ctrl+Shift+F2`) pour les images par
seconde et la mémoire, et le **MicroProfiler** (`Ctrl+F6`, `Ctrl+P` pour une capture) pour voir où part une
image — chercher `Render/Prepare/Particles`, `Lighting` et le nombre de `RenderJob`. Sur un vrai téléphone :
publier la place, l'ouvrir dans l'application Roblox, et lire le compteur de l'application
(`Roblox menu → Settings → Performance Stats`). Ce qu'il faut regarder, dans cet ordre : les images par
seconde pendant un échange à six joueurs au niveau **Élevé** (si ça tient, rien à faire), puis au niveau
**Performance** (si ça ne tient pas, les seuils 40/55 sont trop hauts pour cet appareil et le plancher doit
descendre), puis la consommation quand `QualityController` change de niveau en plein combat (un à-coup à ce
moment veut dire que la remontée est encore trop rapide). Les nombres à corriger en premier sont
`QualityConfig.Auto.DropBelowFps` et `RaiseAboveFps`, puis `PARTICLE_CEILING` dans
`tests/EffectCost.spec.luau`.

Rien de la passe 9 n'a tourné dans un client. La dégradation n'a donc jamais été **vue** descendre ni
remonter, et les quatre niveaux n'ont pas été comparés à l'œil : ce sont des budgets tenus par des tests,
pas un réglage éprouvé. Le mode Performance en particulier échange le post-traitement contre des images —
c'est la bonne direction, mais le point exact où il devient laid appartient à l'appareil.
