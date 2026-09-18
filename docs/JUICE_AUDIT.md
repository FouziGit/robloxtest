# Audit de sensation

Ce que le joueur voit, entend et ressent aujourd'hui, mesuré dans le code et non estimé. Écrit avant
toute ligne de code de la passe « Identité & Game Feel ».

Critère de jugement retenu pour tout le document : **un effet qui pourrait être collé dans n'importe
quel autre jeu Roblox sans qu'on le remarque est un effet raté.**

## Le verdict en un chiffre

Le client compte **34 rendus d'effet** pour 20 glyphes, la mêlée, l'esquive, la garde et le boss.
Toutes catégories confondues, ils totalisent **72 couches visuelles**, soit **2,1 couches par effet**.
La cible de cette passe est de 4 minimum. **Dix effets sur trente-quatre en ont zéro ou une.**

## Inventaire mesuré

Compté automatiquement sur `src/client/Controllers/VfxLibrary.luau`. « Couches » additionne les pièces,
les émetteurs, les lumières, les traînées et les instances `Cinnabar`.

| Effet | Part | Émetteur | Lumière | Trail | Cinnabar | Son | Shake | Linéaire | **Couches** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `Blot` | 1 | 2 | 1 | 1 | 1 | 0 | 1 | 0 | **6** |
| `Ligature` | 2 | 2 | 0 | 1 | 0 | 0 | 0 | 1 | **5** |
| `Stipple` | 2 | 2 | 0 | 1 | 0 | 0 | 0 | 1 | **5** |
| `Brand` | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 1 | **4** |
| `Pounce` | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | **4** |
| `Scorch` | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **3** |
| `Rupture` | 2 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | **3** |
| `Hairline` | 1 | 1 | 0 | 1 | 0 | 0 | 0 | 1 | **3** |
| `Spiral` | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **3** |
| `Dash` | 1 | 1 | 0 | 1 | 0 | 1 | 0 | 1 | **3** |
| `Cast` | 1 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | **2** |
| `Explosion` | 1 | 1 | 0 | 0 | 0 | 1 | 1 | 0 | **2** |
| `Wash` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Serif` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Sweep` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Bleed` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Margin` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Binding` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Gilding` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Watermark` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Hit` | 1 | 1 | 0 | 0 | 0 | 1 | 1 | 0 | **2** |
| `GuardBreak` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `BossSpawn` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `BossDefeated` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **2** |
| `Caret` | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **1** |
| `Colophon` | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | **1** |
| `Melee` | 1 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | **1** |
| `BossSweep` | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **1** |
| `BossEruption` | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **1** |
| `Strike` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `BlockStart` | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | **0** |
| `BlockHit` | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | **0** |
| `BossSlam` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `BossFury` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| **Total (34)** | **34** | **27** | **3** | **6** | **2** | **8** | **5** | **5** | **72** |
### Ce que cette table dit

- **Zéro `Beam` dans tout le jeu.** Aucun lien, aucun arc électrique, aucune traînée d'énergie courbe.
  C'est l'outil le plus expressif de Roblox et il n'est pas utilisé une seule fois.
- **Trois lumières dynamiques au total**, sur trente-quatre effets. Une boule de feu éclaire la scène,
  un météore aussi, Colophon aussi. Les dix-sept autres glyphes traversent le monde sans l'éclairer. C'est
  la moitié de la sensation de puissance, et elle est absente.
- **Aucune trace au sol.** `Decal` et `Texture` n'apparaissent nulle part dans `src`. Un séisme, un
  météore et une tempête de braises ne laissent rien. Le monde n'a aucune mémoire.
- **Aucun post-traitement.** `ColorCorrectionEffect`, `BloomEffect`, `BlurEffect`,
  `DepthOfFieldEffect`, `SunRaysEffect` : zéro occurrence dans tout le dépôt. Aucun flash, aucune
  saturation à l'impact, aucune mise au point.
- **L'éclairage n'est jamais configuré.** Aucun script ne touche `Lighting`, et `default.project.json`
  ne définit ni `Atmosphere`, ni `Sky`, ni `ClockTime`, ni `Technology`. Le jeu tourne sur le ciel et
  la lumière par défaut de Roblox. C'est la raison première pour laquelle une capture d'écran est
  interchangeable avec celle de n'importe quel autre projet.
- **Six effets sur trente-quatre jouent un son.** Vingt-huit sont muets.
- **Cinq interpolations linéaires**, dont le vol de la boule de feu. Un projectile à vitesse constante
  n'a pas de poids.
- Les émetteurs utilisent 38 `NumberSequence` mais seulement **2 `ColorSequence`** : la couleur ne
  varie presque jamais au cours d'une particule. Aucun `FlipbookLayout`, aucun `Squash`, aucun
  `WindAffectsDrag`, aucun `ShapeInOut` : aucune des techniques de particules modernes de Roblox.

## Le cas qui résume tout : la boule de feu

Le sort le plus lancé du jeu, celui qu'un joueur voit dans ses quinze premières secondes.

```
une Part sphérique orange de 3 studs
+ une instance Cinnabar (l'effet hérité de 2008)
+ une PointLight
+ une Trail
déplacée en interpolation LINÉAIRE jusqu'à la fin de sa portée
```

Aucune anticipation : le sort part à l'image même où la séquence est résolue. Aucune mise en scène du
départ, aucun recul du lanceur, aucune déformation de la trajectoire, aucune conséquence au sol. C'est
littéralement la sphère orange générique, et elle est envoyée en ligne droite à vitesse constante.

## Le manque que le comptage ne pouvait pas voir : le personnage ne bouge jamais

`LoadAnimation`, `Animator`, `AnimationId` et `AnimationTrack` n'apparaissent **nulle part** dans
`src`. Les seules occurrences du mot « Animation » sont des durées d'interpolation d'interface et un
type interne à `VfxLibrary`.

Autrement dit : les vingt glyphes sont lancés par un personnage debout dans la pose d'attente par
défaut de Roblox. Aucun sceau de la main, aucune garde, aucun accompagnement. Pour un jeu dont la
mécanique signature est une séquence de sceaux élémentaires, c'est le manque d'identité le plus
coûteux du projet, et aucun compteur de particules ne l'aurait révélé.

## Les vingt sorts partagent une seule mise en scène

Chaque glyphe commence par le **même** paquet `Cast` : une bille de 1,5 stud qui grandit à 6 sur
350 ms, plus une salve de 16 particules, recolorée selon le pigment. Vingt sorts, un visuel de
lancement, cinq couleurs possibles.

Chaque dégât du jeu émet ensuite le **même** paquet `Hit`, qui ne transporte **ni direction, ni
normale, ni gravité** : un tic de brume à 8 dégâts et la détonation d'un météore à 45 produisent
exactement le même éclat et la même constante de secousse. Le client ne peut pas distinguer une
égratignure d'une exécution, parce que le serveur ne le lui dit pas.

## Ce que les particules n'utilisent pas

- **Toutes les particules du jeu sont le sprite par défaut de Roblox.** Aucune texture, aucun
  `ImageLabel`, aucun `rbxassetid` de sprite dans tout `src`.
- **Aucune courbe.** Ni dans les particules, ni dans les traînées. Les valeurs sont plates.
- `FlipbookLayout`, `Squash`, `WindAffectsDrag`, `ShapeInOut` : **zéro occurrence chacun**, alors que
  la vérification d'API confirme que les quatre sont disponibles et non dépréciés aujourd'hui.
- L'interface n'a **aucune couche raster** : 0 `ImageLabel`, 0 `UIGradient`, 0 `ViewportFrame`.
- Le monde n'a **aucun asset** : 0 `MeshPart`, 0 `SpecialMesh`, 0 `Decal`, 0 `Texture`, 0
  `SurfaceAppearance`. Il est entièrement fait de primitives d'une seule palette.

## Un défaut visible, pas seulement une absence

La boule de feu cliente est interpolée en linéaire jusqu'au **bout de sa portée**, 90 studs, et rien
n'annule cette interpolation. Quand le serveur arrête le projectile sur un corps à 20 studs, la bille
continue donc sa route **à travers la cible** pendant que l'explosion s'épanouit derrière elle. Le
serveur n'envoie aucun paquet disant où le projectile est réellement mort.

## Le manque structurel : il n'y a pas d'anticipation

`grep` sur `Windup`, `Anticipation`, `ChargeSeconds`, `CastTime` dans toute la configuration et tout le
serveur : **aucune occurrence**. Aucun glyphe n'a de temps de préparation, aucun n'a de récupération
punitive. Tout part instantanément et tout se termine instantanément.

Ce n'est pas seulement un problème de ressenti, c'est un problème de design : sans fenêtre
d'anticipation, il n'y a rien à lire chez l'adversaire, donc rien à anticiper, donc aucun mind game.
C'est la raison mécanique pour laquelle le combat paraît plat, avant même de parler de particules.

## Ce que la sensation a déjà

Il faut être juste : les fondations existent, elles sont juste minces et mal nommées.

| Élément | État |
|---|---|
| « Hit-stop » | **N'existe pas.** La fonction `hitStop` de `VfxController` ne gèle rien : c'est une impulsion de champ de vision de 60 ms. Le nom ment. |
| Camera shake | Existe, mais c'est **un seul shake** : bruit blanc `math.random`, durée fixe, deux intensités (0,35 et 0,9), décroissance linéaire. Pas de bruit de Perlin, pas de fréquence, pas de profil par type d'impact. |
| Champ de vision | Uniquement dans l'impulsion ci-dessus. Aucun punch au cast, aucun au dash. |
| Haptique | Cinq appels. Présente. |
| Knockback | Existe, appliqué par le client propriétaire sur une durée fixe de 0,25 s. |
| Ragdoll | Une seule occurrence, configurée à 0,6 s. |
| Nombres de dégâts flottants | **Absents.** Aucun. |
| Springs dans l'UI | **Zéro occurrence.** Les interpolations utilisées sont 7 Quad, 6 Linear, 4 Back, 1 Sine. Six mouvements linéaires dans une interface. |
| Barre de vie fantôme | Absente. |
| Compteur de séquence à l'écran | Absent du HUD (seules les pastilles d'éléments pressés existent). |

## Notation par action

Lisibilité = « je comprends ce qui m'arrive ». Punch = « je sens le poids ».

| Action | Lisibilité | Punch | Ce qui manque en premier |
|---|---:|---:|---|
| M1 mêlée | 5/10 | 2/10 | aucun hit-stop réel, aucun flash sur la cible, aucun nombre de dégâts, son unique |
| Dash | 6/10 | 3/10 | pas de punch de champ de vision, traînée discrète, aucune déformation d'image |
| Garde | 4/10 | 2/10 | `BlockStart` et `BlockHit` n'ont **aucun** visuel, seulement un son |
| Prendre un coup | 3/10 | 2/10 | pas de flash, pas de gel, knockback linéaire, aucune direction lisible |
| Tuer | 3/10 | 2/10 | rien de spécifique : pas de ralenti, pas de silhouette, pas de son de finish |
| Mourir | 2/10 | 1/10 | aucune mise en scène, aucun post-traitement, aucun ralenti |
| Gagner un duel | 3/10 | 2/10 | écran de résultat fonctionnel mais sans aucune montée, sans animation de barre |
| Marque | 5/10 | 3/10 | vol linéaire, aucune anticipation, aucune trace |
| Lavis / Empattement / Balayage | 5/10 | 2/10 | une pièce et un émetteur chacun, aucune lumière, aucun son |
| Rupture | 6/10 | 4/10 | le shake porte tout le poids ; aucune fissure, aucun débris, aucune trace |
| Météore | 6/10 | 5/10 | le mieux doté du jeu, et il reste sans trace au sol ni post-traitement |
| Éclair | 1/10 | 1/10 | **zéro instance visuelle.** Le sort le plus rapide du jeu est invisible. |
| Colophon (ultime) | 2/10 | 3/10 | une `PointLight` et un shake. Le sort le plus cher du jeu est un flash. |
| Reliure | 4/10 | 2/10 | une pièce, un émetteur ; l'immobilisation n'est pas lisible sur la cible |
| Peau de Pierre | 3/10 | 2/10 | aucune silhouette `Highlight`, on ne voit pas qu'un joueur est protégé |
| L'Effacement (boss) | 4/10 | 4/10 | quatre de ses six attaques n'ont qu'un shake, le corps est une boîte |

Moyenne pondérée : **lisibilité 4/10, punch 2,5/10.**

## Lisibilité en 3v3 : le test qui échoue

En mêlée à six, la question « qu'est-ce qui va me toucher » se répond aujourd'hui presque uniquement à
la couleur de la particule, et les couleurs actuelles sont la roue élémentaire par défaut : orange,
bleu, brun, vert pâle, jaune. Le vert pâle du Vent (`170, 220, 190`) est à peine distinguable du gris
du décor, et aucun code couleur ne distingue le danger imminent d'un effet décoratif. Il n'existe
aucune télégraphie au sol, aucune montée lumineuse, aucun son qui monte avant un gros sort.

## Les dix gains les plus rentables, par ordre de rapport qualité-prix

0. Donner une animation au lanceur. Le personnage ne bouge pas quand il lance un sort : c'est le
   premier écart d'identité, avant même les particules.
1. Configurer `Lighting` et `Atmosphere`. Une heure de travail, change chaque capture d'écran.
2. Un vrai hit-stop, 40 à 90 ms selon les dégâts. L'effet le plus rentable qui existe en game feel.
3. Post-traitement à l'impact : saturation qui monte et retombe sur 80 ms.
4. Une `PointLight` sur chaque projectile. Dix-sept sorts à éclairer.
5. Camera shake à bruit de Perlin, avec un profil par type d'impact.
6. Nombres de dégâts flottants stylés, avec un critique distinct.
7. Une anticipation lisible sur chaque glyphe lourd, et une récupération punitive.
8. Des traces au sol qui s'effacent.
9. Des springs dans l'interface, et une barre de vie fantôme.
10. Donner un visuel à `Strike`, `Colophon`, `BlockStart` et `BlockHit`, qui n'en ont aucun.

## Ce que la vérification d'API autorise

Vérifié contre l'API live et la documentation, pas de mémoire :

- `FlipbookLayout`, `Squash`, `WindAffectsDrag`, `ShapeInOut` sont **tous disponibles**, non
  dépréciés, non restreints. Aucun n'est utilisé ici.
- `EditableImage` et `EditableMesh` sont vivants et une expérience qui les utilise **peut** être
  publiée, mais derrière une vérification d'âge et d'identité du créateur. C'est une porte que je ne
  peux pas franchir à la place du propriétaire : ces deux API sont donc écartées et notées dans
  `docs/DECISIONS.md`.

## Méthode

Les comptes de cette page sont produits par lecture automatique des sources, pas à l'œil. Les scores
sont mon jugement, appuyé sur ces comptes. Les détails par sort et par surface sont dans
`docs/VFX_SPECS.md` au fur et à mesure de la refonte.
