# La Page — le grand Battleground (design)

Date : 2026-10-09. Décision : D-282. Références du développeur : `docs/world/battleground/ref-1.jpg` (vue
aérienne en jeu) et `ref-2.jpg` (plan de niveau), générées avec Gemini.

## Ce que le développeur a demandé

- Une carte « super grande, comme les battlegrounds Roblox actuels », là où tout le monde s'affronte.
- **PvP libre + Forgers** : tous les membres présents peuvent se frapper ; les Forgers restent, en plus.
  La carte remplace le Battleground actuel (page de 170 studs, D-131).
- **Kill joueur récompensé, avec anti-farm** : un peu d'XP et de Folios ; tuer encore la même personne ne
  rapporte plus rien pendant quelques minutes. Les Forgers paient comme aujourd'hui.
- **Bulle de 3 s** à l'arrivée et à la réapparition, qui tombe dès qu'on attaque. Pas de zone sûre fixe.

## Hypothèses (décidées sans le développeur, à corriger s'il le faut)

- 700 × 700 studs, toujours à X = 1500 (de 1150 à 1850 : loin des arènes à x = z = 0 et de la Page de garde
  à x = −1500). Douze membres au plus, comme aujourd'hui.
- Construit en code avec des pièces simples (`Part` blocs, `WedgePart`, cylindres), comme le hub et la page
  actuelle : collisions exactes, rien à uploader, règles testées sans moteur.
- Le rayon de diffusion des effets (250 studs) ne change pas : sur 700 studs, un combat lointain n'est plus
  envoyé à tout le monde, ce qui allège les clients. C'est voulu.

## La carte

Repère local de `BattlegroundLayout` : x vers l'est, z vers le sud, y = 0 au-dessus du sol, centre (0, 0).
Positions et tailles indicatives : le test de disposition tient les règles, pas ces chiffres exacts.

| Lieu | Où | Forme (pièces simples) |
|---|---|---|
| Place centrale | centre | estrade de 200 × 200, haute de 1 stud (une marche, les Forgers y montent), filet d'encre au bord, couverts bas (murets de 4 à 6 studs) en L et en I |
| Livre ouvert | nord-ouest (≈ −200, −230) | deux demi-pages en collines à gradins (jusqu'à 18 studs), vallée de 20 studs le long du dos |
| Plume tombée | nord (≈ 60, −240) | tige couchée en diagonale, 180 de long, 24 de large, montée en rampe du sol jusqu'à 40 studs, pointe biseautée |
| Falaises de folios | nord-est (≈ 230, −220) | livres empilés en paliers de 15, 30, 45 et 60 studs, reliés par des rampes : le point le plus haut |
| Lit réglé | des falaises vers le bord sud, côté est | chenal de 40 de large, creusé de 3 studs, lignes d'encre au fond |
| Pont cousu | est (≈ 240, 30) | tablier de 30 × 60 au-dessus du chenal, points de couture en croix |
| Champ des sceaux | sud (≈ 40, 250) | 8 à 10 disques de cire (cylindres de 2 à 6 studs de haut, 16 à 30 de diamètre) et taches d'encre plates |
| Ruines du scriptorium | sud-ouest (≈ −230, 200) | 3 ou 4 arches (deux piles et un linteau, 24 studs), pupitres brisés (blocs de 6 à 8) |
| Cratère d'encrier | ouest (≈ −250, −20) | rebord en anneau de 6 studs, rayon extérieur 60, quatre brèches |
| Camp | bord ouest | le camp actuel : `Arrival_1..6` et `ReturnPortal`, sans protection propre |

- Sol : vélin réglé avec sa ligne de marge, comme le hub. Couleurs du décor : vélin, craie, os et encre
  uniquement (règle 1 de la bible) ; aucune couleur d'école.
- Bord : la page déchirée ; au-delà, la `KillZone` actuelle (une chute tue).
- Aucun couloir de moins de 16 studs entre deux pièces posées au sol.
- Douze points d'apparition (`Arrival_7..18` en plus du camp) sur le pourtour, à 80 studs au moins les uns des
  autres et à 40 au moins des points d'apparition des Forgers.

## Les règles

- **PvP libre** : dans la zone Battleground, un membre peut blesser tout autre membre (pas d'équipe). Un
  joueur hors de la page ne peut ni blesser un membre ni en être blessé. Passe par `CombatService.claimZone`
  et `DamageZones`, comme les autres zones.
- **Bulle** : à l'arrivée et à chaque réapparition dans la page, `SpawnProtectedUntil` vaut
  `now + BattlegroundConfig.ArrivalProtectionSeconds` (3). Attaquer pendant la bulle la fait tomber
  aussitôt. Ailleurs, la protection de `GameConfig.Spawn` reste telle quelle.
- **Récompense d'un kill joueur** (`Rewards`) : le tueur (dernier coup) gagne `PlayerKill.Xp` et
  `PlayerKill.Folios`. Les Folios passent par le même plafond quotidien que ceux des Forgers
  (`DailyCap`, compté dans le profil). Une paire tueur → victime ne paie qu'une fois toutes les
  `PlayerKill.PairCooldownSeconds` (300). Aucun paiement si la victime était encore sous sa bulle ou si le
  tueur n'est pas membre.
- **Forgers** : inchangés, sauf leur grille de déplacement, qui passe à un nœud tous les 20 studs. Ils
  restent au sol ; ce qui est en hauteur leur échappe.

## Performances

- Budget de pièces de la carte : 1500 au plus, compté par le test de disposition.
- Aucune boucle par joueur : tout passe par le Heartbeat existant du service.
- Le streaming reste coupé ; on ne l'active que si une mesure sur mobile le demande.

## Tests

- `tests/BattlegroundLayout.spec.luau` : la page fait 700 ; chaque pièce est dans la page ; le budget de 1500
  pièces tient ; aucun couloir de moins de 16 studs au sol ; chaque quartier est relié à la place par la
  grille des Forgers ; les points d'apparition respectent leurs distances ; rien de solide sur un point
  d'apparition.
- `tests/Battleground.spec.luau` : deux membres se blessent ; un joueur du hub ne blesse pas un membre ; la
  bulle bloque les coups reçus et tombe quand son porteur attaque ; un kill paie, le même kill répété dans
  les 300 s ne paie plus, les Folios respectent le plafond quotidien.
- Les cinq portes de qualité restent vertes à chaque commit.

## Hors périmètre

- Volumes « encre » modélisés pour les repères (phase 2, si les pièces simples ne suffisent pas à l'œil).
- Streaming, classement propre au Battleground, fil des kills, équipes.
