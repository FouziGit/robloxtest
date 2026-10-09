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
| Place centrale | centre | estrade de 200 × 200 surélevée de 7 studs, un escalier de 60 de large au milieu de chaque côté (six marches d'un stud, les Forgers y montent ; ailleurs le bord est à pic), filet d'encre au bord, couverts bas (murets de 6 studs) en L et en I, parapet brisé en L à chaque coin |
| Livre ouvert | nord-ouest (≈ −200, −240) | 200 × 140 : deux demi-pages de 90 en collines courbes (cinq pentes chacune, du bord à 4 studs jusqu'à une crête de 18, qui retombe à 8 sur le dos), vallée de 20 studs au sol le long du dos |
| Petit livre ouvert | sud-ouest de la place (≈ −70, 200) | 80 × 56, mêmes collines, jusqu'à 7 studs |
| Plume tombée | nord (pied ≈ 50, −140) | 190 de long, 24 de large, penchée vers le nord-nord-est : un escalier de 30 marches de 2 studs entre deux rampes jusqu'à un palier à 60 studs, pointe biseautée |
| Falaises de folios | nord-est, tout le coin (220 × 220) | socle rocheux de 15 studs, livres fermés empilés en paliers de 30, 45 et 60 studs (le point le plus haut), une rampe par palier, deux depuis le sol (ouest et sud) |
| Lit réglé | des falaises au bord sud, côté est puis vers le sud-ouest | bande de 60 de large en trois tronçons, coudes arrondis, dessinée à plat (D-282 : creusé, un membre au fond passerait sous la profondeur qui tient la page), rives à l'encre et lignes |
| Pont cousu | est (≈ 260, −30) | tablier de 76 × 30 au-dessus du lit, rampes, points de couture en croix |
| Champ des sceaux | sud, de part et d'autre du lit | 11 disques de cire de 20 à 36 de diamètre, trois empilés, et taches d'encre plates |
| Ruines du scriptorium | sud-ouest (≈ −290, 215) | arcade de quatre arches sous une même poutre, haute de 30 studs, 102 de long, corbeaux aux angles ; pupitres brisés (blocs et coins de 14 × 9) et deux souches de 14 et 20 studs |
| Cratère d'encrier | ouest (≈ −215, 0) | rebord en anneau de 7 studs, 140 de diamètre, quatre brèches ; le fond est le sol de la page |
| Camp | bord ouest | le camp actuel : `Arrival_1..6` et `ReturnPortal`, sans protection propre |

- Sol : vélin réglé avec sa ligne de marge, comme le hub. Couleurs du décor : vélin, craie, os et encre
  uniquement (règle 1 de la bible) ; aucune couleur d'école.
- Bord : la page déchirée ; au-delà, la `KillZone` actuelle (une chute tue).
- Aucun couloir de moins de 16 studs entre deux pièces posées au sol.
- Douze points d'apparition (`Arrival_7..18` en plus du camp) sur le pourtour, à 80 studs au moins les uns des
  autres et à 60 au moins des points d'apparition des Forgers. Un joueur atterrit sur l'arrivée la plus éloignée
  des membres déjà présents ; sur une page vide, les arrivées passent à tour de rôle.

## Les règles

- **PvP libre** : dans la zone Battleground, un membre peut blesser tout autre membre (pas d'équipe). Un
  joueur hors de la page ne peut ni blesser un membre ni en être blessé. Passe par `CombatService.claimZone`
  et `DamageZones`, comme les autres zones.
- **Bulle** : à l'arrivée et à chaque réapparition dans la page, `SpawnProtectedUntil` vaut
  `now + BattlegroundConfig.ArrivalProtectionSeconds` (3). Le premier coup de son porteur qui touche la fait tomber
  (un coup refusé ou arrondi à zéro la laisse). Ailleurs, la protection de `GameConfig.Spawn` reste telle quelle.
- **Récompense d'un kill joueur** (`Rewards`) : le tueur (dernier coup) gagne `PlayerKill.Xp` et
  `PlayerKill.Folios`. Les Folios passent par le même plafond quotidien que ceux des Forgers, l'XP par son
  propre plafond (`PlayerKill.DailyXpCap`, 1200), tous deux comptés dans le profil (`DailyCap`). Une paire de
  joueurs, dans un sens comme dans l'autre, ne paie qu'une fois toutes les `PlayerKill.PairCooldownSeconds`
  (300) : deux joueurs qui s'entretuent ne gagnent qu'une fois. Aucun paiement si la victime était encore
  sous sa bulle ou si le tueur n'est pas membre à cet instant (un membre mort qui attend son corps ne gagne
  rien).
- **Forgers** : inchangés, sauf leur grille de déplacement, qui passe à un nœud tous les 20 studs. Ils
  restent au sol et montent sur la place par ses escaliers : la hauteur d'un corps se compte depuis le sol
  sous lui, la place comprise (`BattlegroundLayout.groundAt`). Ce qui est en hauteur ailleurs leur échappe.

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
  bulle bloque les coups reçus et tombe au premier coup de son porteur qui touche ; un kill paie, le même
  kill répété dans les 300 s, dans un sens comme dans l'autre, ne paie plus, les Folios et l'XP respectent
  leur plafond quotidien.
- Les cinq portes de qualité restent vertes à chaque commit.

## Hors périmètre

- Volumes « encre » modélisés pour les repères (phase 2, si les pièces simples ne suffisent pas à l'œil).
- Streaming, classement propre au Battleground, fil des kills, équipes.
