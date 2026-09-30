# Game Design — Vellum V2

## 1. Piliers

1. **Le combo est le skill.** Un glyph = une séquence de touches de pigment. La vitesse d'exécution, la mémorisation et la lecture de l'adversaire (mind games : feinter un début de combo, punir un cast long) font la différence, pas les statistiques.
2. **Serveur autoritaire, client expressif.** Le serveur décide de tout ce qui compte (dégâts, ressources, positions de référence) ; le client rend des effets riches (particules, secousses, hit-stop) sans jamais être cru.
3. **Rejouable.** Modes courts (1v1 en 2-3 min, 3v3 en 4-5 min), classement saisonnier, quêtes, pass, World Boss périodique.
4. **Équitable.** Aucun achat n'ajoute de puissance brute : Orpiment est un *sidegrade* atteignable gratuitement, les cosmétiques sont purement visuels, les slots de loadout supplémentaires offrent de la variété, pas de l'avantage.

## 2. Contrôles

| Action | Clavier (défaut) | Manette | Tactile |
|---|---|---|---|
| Cinabre / Indigo / Terre d'Ombre / Vert-de-gris | `J` / `K` / `L` / `H` | D-pad haut / droite / bas / gauche | boutons colorés, pouce droit |
| Orpiment (débloquée) | `U` | `Y` | disque jaune, absent tant qu'elle n'est pas débloquée |
| Corps à corps (M1) | clic gauche | `X` | disque, le plus grand |
| Dash | Maj gauche | `B` | bouton |
| Garde | `F` | `LT` | bouton (maintenir) |
| Verrouiller un adversaire | clic molette | `R3` | bouton |
| Menu | `M` | `Select` | bouton |
| Saut / double saut | Espace ×2 | `A` ×2 | bouton saut Roblox |

Aucune touche par défaut n'entre en conflit avec WASD (QWERTY), ZQSD (AZERTY), le zoom (I/O), le classement (Tab) ni le sac (1-9). Tout est réassignable (clavier et manette) dans les options.

**Ce que le HUD dit des contrôles (D-147).**
- **La barre de glyphes.** Avec une souris ou une manette, un emplacement par glyphe équipé, et sous lui sa recette en touches liées : chaque touche porte la bande du pigment qu'elle presse (« J » sur Cinabre). C'est la légende du clavier. La recharge s'écoule sur la puce au rythme du serveur ; un glyphe que l'encre ne paie pas passe à la craie avec une goutte. Au toucher, une rangée de pastilles dans le dock.
- **La pilule d'aperçu.** Quand la séquence est déjà un glyphe et que le contrôleur attend de voir si elle s'allonge, « → Brand » s'affiche dans la couleur du glyphe au-dessus des puces, sur un trait qui s'écoule : l'attente de prolongation se lit comme un choix, pas comme un retard. Son coût est marqué sur la barre d'encre, qui clignote avant la dernière pression si l'encre manque.
- **La pilule de refus.** Un lancer refusé (recharge, encre, verrouillé, séquence sans recette) se dit sous les puces, qui tremblent, jamais par un toast en haut de l'écran ; une recharge fait aussi clignoter l'emplacement du glyphe.
- **Les disques tactiles.** Chaque pigment dans sa couleur exacte sur sa lèvre, le kit sur une plaque d'encre ; le corps à corps est le plus grand. Après une ou deux pressions, les disques qui prolongent la séquence respirent ; un pigment qui ne mène à aucun glyphe payable pâlit ; le dash montre sa recharge. Un pigment verrouillé n'a pas de disque.
- **Le verrou.** Le losange d'encre porte une plaque avec le nom et la vie de la cible, pâlit à la craie vingt studs avant la rupture, et un chevron au bord de l'écran montre une cible hors champ. Un verrou qui ne trouve rien dit « Aucune cible ».

## 3. Ressources et kit de base

- **Vie** : 100. Régénération 3/s hors combat après 8 s sans dégât.
- **Ink** : 100. Chaque glyph coûte 15-50. Régénération 12/s hors combat, 4/s en combat (6 s après avoir donné ou reçu un coup). Le encre est la vraie limite au spam ; les cooldowns empêchent la répétition d'un même glyph.
- **M1** : combo de 4 coups (8 / 8 / 8 / 14), fenêtre de chaînage 0,9 s, portée 7 studs. Le 4e coup projette (knockback + léger envol), étourdit 0,5 s, brise la garde, puis impose 1,2 s de recharge. Sur un avatar articulé (AJU), la victime est projetée inerte, tombe, reste à terre un instant et se relève : 1,1 s pendant lesquelles elle ne peut pas agir et **ne peut pas être touchée** (D-113) — un knockdown n'offre jamais de suite garantie.
- **Dash** : 22 studs en 0,22 s, 0,25 s d'invulnérabilité, recharge 2,5 s, coûte 10 encre. Direction = déplacement en cours, sinon regard.
- **Garde** : -70 % de dégâts, marche à 50 %, 4 s max puis 1,5 s de recharge. Brisée (1 s de stun) par les *Ultimes* et par le 4e coup de M1.
- **Stun / ragdoll léger** : sur certains impacts (Empattement, Rupture, finisher M1) — jamais plus de 2 s cumulées. Un étourdissement de glyphe ne prolonge jamais celui qui court et ne tombe pas dans la demi-seconde qui suit sa fin (D-213) : un enchaînement de glyphes ne tient personne plus longtemps que son plus long glyphe (0,8 s, la Rupture).
- **Protection de spawn** : 4 s sans donner ni recevoir de dégâts. Les **zones** disent qui blesse qui (`ZoneConfig`, D-266) : aucun PvP au hub ni au Champ de bataille (les mannequins et les Faussaires restent frappables), les adversaires d'un même match entre eux, les membres de la Page de garde entre eux hors de leur protection, jamais entre joueurs de l'Effacement.

## 4. Combos : règles de résolution

Le résolveur (`ComboResolver`, module pur testé) applique :

1. La séquence tapée **est une recette et n'est le début d'aucune autre** → cast immédiat.
2. La séquence **est le début d'une recette plus longue** → attente de la touche suivante.
3. Sinon → reset (« aucun glyphe ne correspond »).
4. **Fenêtre d'extension** : si la séquence est *déjà* une recette **et** le début d'une plus longue (`Cinabre Cinabre` → `Cinabre Cinabre Terre d'Ombre`), le client n'attend que `ExtendWindowSeconds` (0,35 s) au lieu du timeout complet (1,2 s). Un joueur rapide enchaîne `Cinabre Cinabre Terre d'Ombre` en moins de 350 ms ; un joueur qui voulait `Cinabre Cinabre` ne perd que 350 ms. C'est le cœur du « fun par la vitesse d'exécution ».
5. Timeout complet (1,2 s) uniquement pour les séquences qui ne sont pas encore une recette.

Le serveur re-résout la séquence reçue ; il ne fait jamais confiance au client pour l'identité du glyph.

## 5. Roster (28 glyphes)

Archétypes : **Projectile** (ligne, esquivable), **AoE** (instantané devant soi), **Zone** (persistante, contrôle d'espace), **Mur** (défense), **Mobilité**, **Contre**, **Buff**, **Ultime** (long combo, gros coût, gros impact).

Légende combos : C Cinabre · I Indigo · U Terre d'Ombre · V Vert-de-gris · O Orpiment.

| Pigment | Combo | Glyph | Archétype | Coût | CD | Dégâts | Rôle |
|---|---|---|---|---|---|---|---|
| Cinabre | C C | Marque | Projectile | 20 | 4 | 25 | poke fiable, explose (rayon 7) |
| Cinabre | C V | Ligature | Mobilité | 15 | 6 | 6 | dash court qui laisse une traînée brûlante 2 s |
| Cinabre | C C V | Roussi | Zone | 35 | 12 | 10 ×3 | anneau autour de soi, zone anti-mêlée |
| Cinabre | C C U | Pâté | Ultime | 50 | 20 | 40 | projectile lourd en cloche, AoE 10, brise la garde (40 × 1,25 sur cible *Éventée* = 50, le plafond) |
| Cinabre | C I | Rubrique | Projectile | 24 | 6 | 25 | chargée 0,7 s sans bouger (canalisation), puis une ligne droite qui transperce 3 cibles, portée 85, arrêtée par un mur |
| Cinabre | C U | Hachures | AoE | 25 | 7 | 5 ×5 | rafale canalisée devant soi (1,36 s), chaque trait ralentit, le dernier projette et étourdit 0,4 s |
| Indigo | I I | Lavis | AoE | 22 | 5 | 18 | ligne, knockback |
| Indigo | I C | Bavure | Zone | 28 | 8 | 8 ×3 | ralentit 60 % |
| Indigo | I V | Reliure | Contre | 30 | 12 | 10 | racine la cible devant soi 1,5 s |
| Indigo | I I U | Marge | Mur | 30 | 10 | 0 | bloque projectiles et M1 pendant 6 s ; **pigment Terre d'Ombre** (le mur est la moitié Ombre du §6), combo Indigo |
| Indigo | I U | Volute | AoE | 25 | 6 | 24 | chargée 0,4 s dans la main (canalisation), puis plaquée sur le corps le plus proche devant soi : projeté, étourdi 0,4 s |
| Indigo | I I I I | Cartouche | Ultime | 50 | 20 | 28 + 4 ×5 | cadre de rayon 16 autour de soi : un sceau qui brise la garde et étourdit 0,4 s, puis 5 ticks qui ralentissent 50 % ; tant que le lanceur s'y tient, ses autres glyphes se rechargent deux fois plus vite (4 s gagnées au plus, D-256) |
| Terre d'Ombre | U U | Empattement | AoE | 22 | 5 | 22 | ligne, stun 0,4 s |
| Terre d'Ombre | U I | Pointillé | Projectile | 18 | 4 | 16 | ralentit 40 % 2 s |
| Terre d'Ombre | U V | Dorure | Buff | 25 | 14 | 0 | -40 % dégâts reçus 4 s, immunité au knockback |
| Terre d'Ombre | U U U | Rupture | Ultime | 45 | 15 | 35 | AoE 18, envol, stun 0,8 s |
| Terre d'Ombre | U C | Paraphe | AoE | 25 | 7 | 20 | vague au ras du sol (12 de large, 5 de haut) jusqu'à 45 studs, arrêtée au premier mur |
| Terre d'Ombre | U U V | Gaufrage | AoE | 35 | 12 | 24 | souffle autour de soi (rayon 13) qui repousse de 25 studs, sans stun ni brise-garde |
| Vert-de-gris | V V | Balayage | AoE | 15 | 3 | 12 | cône, gros knockback, applique *Éventé* |
| Vert-de-gris | V C | Délié | Projectile | 15 | 3 | 14 | rapide, portée 60, applique *Éventé* |
| Vert-de-gris | V V I | Spiral | Zone | 35 | 12 | 6 ×4 | attire vers le centre |
| Vert-de-gris | V V U | Poncif | Zone | 30 | 10 | 5 ×3 | ralentit 30 %, brouille la vue (fog local) |
| Vert-de-gris | V U | Obèle | Mobilité | 25 | 10 | 14 | réapparaît dans le dos du corps le plus proche devant soi (25 studs, cône de 35°) et le frappe ; sans cible, rien (l'encre reste dépensée) |
| Vert-de-gris | V I | Chaînette | Contre | 25 | 10 | 10 | projectile qui ramène la première cible à 4 studs du lanceur et l'enracine 0,8 s |
| Orpiment | O O | Rature | Projectile | 20 | 4 | 22 | hitscan instantané, portée 70 |
| Orpiment | O V | Insertion | Mobilité | 20 | 7 | 0 | téléport 18 studs, 0,4 s d'i-frames |
| Orpiment | O O U | Filigrane | Zone | 35 | 12 | 6 ×4 | micro-stun à chaque tick |
| Orpiment | O O O O | Colophon | Ultime | 55 | 25 | 40 | chaîne sur 3 cibles, stun 0,6 s |

Cibles d'équilibrage : temps pour tuer un adversaire qui esquive mal ≈ 12-15 s ; DPS soutenu des 2 touches ≈ 4-6/s ; un Ultime ne dépasse jamais 50 % de la vie, sceau et ticks compris (Cartouche : 28 + 4 × 5 = 48). Les 8 glyphes V1 sont conservés (Marque, Lavis, Empattement, Balayage, Bavure, Marge, Roussi, Rupture) avec les coûts d'encre ci-dessus.

### Déblocages

- Par défaut : les 8 glyphes V1.
- Niveau 5 : Délié, Pointillé · niveau 8 : Volute · niveau 10 : Ligature, Reliure · niveau 12 : Paraphe · niveau 15 : Dorure, Poncif · niveau 18 : Hachures · niveau 20 : Spiral · niveau 22 : Chaînette · niveau 25 : Pâté · niveau 28 : Obèle · niveau 30 : Gaufrage · niveau 33 : Rubrique · niveau 36 : Cartouche.
- **Orpiment** : pigment *sidegrade* — même budget de dégâts que les autres, mais hitscan / mobilité / contrôle au lieu de zones. Débloquée au **niveau 40** **ou** via le game pass Orpiment. Le niveau 40 vient après 4 h 37 de jeu à 20 min/jour de duels (J14), 6 h 04 à une heure par jour (J6), 4 h 13 à 20 min/jour seul (J13) et 19 h pour un fermier d'Épreuves (J20), selon `scripts/pacing.luau` sur les vraies configs (docs/ECONOMY.md §2 bis) : bien moins que les 15-20 h que ce paragraphe estimait à la main. Un joueur sans Orpiment n'est jamais désavantagé statistiquement : Orpiment échange la puissance de zone contre la précision.
- **Loadout** : 6 slots de base (max 10 avec le pass *Slots*). Équiper = choisir sa main ; les glyphes non équipés ne peuvent pas être lancés.

## 5 bis. Plafond de compétence : annulation, enchaînement, matrice des réponses

Trois règles portent le plafond. Elles sont serveur et mesurables, et **une seule coûte de l'encre** : la
seconde en **rend** (moins que le glyphe le moins cher, donc un enchaînement ne se paie jamais lui-même) et
la troisième est un affichage. C'est la première qui porte la décision.

| Règle | Ce que le joueur fait | Prix | Où c'est décidé |
|---|---|---|---|
| **Annulation de récupération** | ruer pendant la récupération du 4ᵉ coup de M1 (1,2 s) : la récupération s'arrête net | coût de la ruée **+ `Dash.CancelCost`** (10 + 15 encre) — et seulement si le joueur peut payer les 25 : en dessous, la ruée part normalement à 10 et la récupération continue, parce qu'une ruée d'esquive ne doit jamais disparaître | `CombatService.onDash` |
| **Enchaînement** | lancer un glyphe dans les `Combo.ChainWindowSeconds` (1,0 s) qui suivent le précédent **accepté** | rend `Combo.ChainInkRefund` (5 encre), donc une séquence serrée se paie presque elle-même sans jamais être bénéficiaire (le glyphe le moins cher coûte 15) | `GlyphService.onCastGlyph` |
| **Compteur d'enchaînement** | le HUD affiche `×N` dès deux glyphes ; le profil garde `Stats.BestChain` | — | compté par le serveur, jamais par le client |

L'annulation ne rend ni l'invulnérabilité ni le cooldown de la ruée : elle échange de l'encre contre du
tempo. Un joueur à court d'encre ne peut pas annuler, ce qui est exactement la décision qu'on veut créer.

**Canalisation** (D-142) : la Volute et la Rubrique pendant leur charge, les Hachures pendant leur rafale,
tiennent leur lanceur — ni M1 ni autre glyphe. Une ruée la rompt et la charge, ou le reste de la rafale, est
perdue, encre et recharge comprises ; lever la garde ou être étourdi aussi. C'est le prix d'un coup qu'on voit
venir.

### Matrice outil → contre

Chaque glyphe a une réponse explicite. « Réponse » = ce qui annule ou punit l'outil ; « fenêtre » = ce qui
rend la réponse possible. Rien ici n'est un contre universel : chaque ligne se paie en encre, en cooldown
ou en position.

| Outil | Réponse principale | Réponse secondaire | Fenêtre |
|---|---|---|---|
| Marque (projectile) | Marge (mur) l'arrête | ruée latérale, Dorure (−40 %) | vol visible, trajectoire droite |
| Ligature (ruée brûlante) | Reliure (racine) la punit à l'arrivée | reculer hors de la traînée | 2 s de traînée fixe au sol |
| Roussi (anneau anti-mêlée) | rester à distance : c'est un outil de zone, pas de portée | Lavis pour pousser le lanceur hors de son anneau | anneau fixe autour du lanceur |
| Pâté (ultime, brise la garde) | Insertion / ruée : la cloche est lente et téléphonée | Marge l'absorbe (projectile) | temps de vol le plus long du roster |
| Lavis (ligne, knockback) | Dorure (immunité au knockback) | ruée perpendiculaire | ligne étroite, instantanée |
| Bavure (zone ralentissante) | Indigo éteint le Cinabre, mais contre Bavure : Insertion (téléport hors zone) | Dorure pour tanker les ticks | zone persistante, sortie possible |
| Reliure (contre, racine) | ne pas venir de face : c'est un cône court devant le lanceur | Insertion pendant la racine | 1,5 s de racine, cooldown 12 s |
| Marge (mur) | Empattement / Rupture : les AoE de contact passent au-dessus du mur | contourner : le mur est un panneau, pas un dôme | 6 s, position fixe |
| Empattement (ligne, stun) | Dorure (dégâts réduits, stun subi mais knockback nul) | garde : c'est un AoE, pas un ultime | portée courte, faut être devant |
| Pointillé (projectile ralentissant) | Marge l'arrête | Dorure annule l'usage qu'on veut en faire | 110 studs/s sur 70 studs : ~0,64 s de vol, donc une Marge **prévue**, pas une réaction |
| Dorure (buff défensif) | attendre : 4 s puis 14 s de cooldown, l'agresseur choisit son moment | pression à l'encre (forcer la dépense) | fenêtre de 10 s sans buff |
| Rupture (ultime, envol) | Dorure (immunité au knockback : l'envol est annulé) ; **préventif**, pas réactif | tenir plus de 18 studs, ou punir les 15 s de recharge | **aucune** : les dégâts tombent sur l'image du lancer (`GlyphEffects.Rupture`), donc rien ne s'esquive après coup |
| Balayage (cône, *Éventé*) | ruée : le cône est large mais court | garde (réduction, pas de brise-garde) | applique *Éventé*, donc annonce un Cinabre derrière |
| Délié (projectile rapide) | Marge l'arrête | Dorure réduit, mais le vrai contre est la position | portée 60, cooldown 3 s : c'est du poke |
| Spiral (attire vers le centre) | Insertion (téléport) ou Dorure (immunité au knockback : l'attraction ne prend pas) | sortir avant le 2ᵉ tick | 4 ticks, zone visible |
| Poncif (brouille la vue) | sortir : la brume est locale, la zone est petite | Rature (hitscan, n'a pas besoin de voir la trajectoire) | 3 ticks, ralentissement 30 % |
| Rature (hitscan) | **rien ne l'esquive** : la réponse est l'encre — 20 par tir, et 70 studs de portée obligent le lanceur à rester exposé | Marge l'arrête (c'est un projectile instantané, pas un rayon ignorant les murs) | cooldown 4 s, coût 20 |
| Insertion (téléport) | Reliure à l'arrivée, Filigrane / Spiral sur la zone d'arrivée probable | poursuivre : 0,4 s d'i-frames seulement | cooldown 7 s |
| Filigrane (micro-stuns) | Dorure, puis sortir : les stuns sont courts mais reviennent à chaque tick (jamais sur un autre étourdissement, D-213) | Insertion | 4 ticks, zone fixe |
| Colophon (ultime, chaîne 3 cibles) | se séparer : la chaîne a besoin de cibles proches | Marge pour le premier maillon | combo à 4 touches, 55 encre, 25 s |
| Volute (chargée, projette) | ruée pendant les 0,4 s de charge | garde (−70 %), Dorure (pas de projection) | la charge se voit dans la main, portée 8 |
| Rubrique (ligne chargée) | quitter la ligne tracée au sol | Marge l'arrête ; étourdir le lanceur rompt la charge, le repousser de plus de 6 studs la lui fait perdre | 0,7 s de charge, lanceur immobile |
| Paraphe (vague au sol) | Marge l'arrête | sauter au bon moment (5 de haut), ruée latérale (12 de large) | environ 0,55 s pour traverser 41 studs |
| Obèle (dans le dos) | ruée : ses i-frames font qu'il ne vous choisit pas | dos au mur (pas de place derrière) ; garde | recharge 10 s, aucun étourdissement |
| Cartouche (ultime, sceau puis ticks) | Dorure préventive | sortir du cadre après le sceau ; étourdir le lanceur arrête les ticks et sa recharge accélérée ; le pousser hors de son cadre lui retire la seconde | combo à 4 touches, 50 encre, 20 s |
| Gaufrage (souffle) | Dorure (immunité au knockback) | rester à plus de 13 studs | instantané, recharge 12 s |
| Chaînette (ramène, enracine) | Marge l'arrête | ruée latérale ; Dorure (pas de traction) | projectile visible sur 32 studs |
| Hachures (rafale canalisée) | ruée hors de la boîte (7 studs devant le lanceur) | garde | 1,36 s de rafale, seul le dernier trait projette |

**Ce que la matrice garantit, et ce qu'elle ne garantit pas.** Aucun glyphe n'a pour seule réponse « avoir
le même glyphe » : les trois réponses structurelles — **Marge** (arrêter ce qui vole), **Dorure** (absorber
ce qui pousse), **Insertion / ruée** (ne plus être là) — couvrent le roster entier, et chacune est une
ressource qu'on dépense (10, 14, 7 s de recharge) et non un état qu'on maintient.

Deux choses qu'elle ne garantit **pas**, et qui sont des dettes d'équilibrage plutôt que des erreurs de
document :

- **Marge et Dorure sont toutes deux de la Terre d'Ombre** (`GlyphConfig.Pigment`), donc deux des trois
  réponses structurelles viennent du même pigment — un joueur sans Terre d'Ombre équipée n'a que
  l'Insertion, et l'Insertion demande l'Orpiment (niveau 40 ou pass). La ruée de base reste la réponse
  universelle gratuite, mais c'est elle qui porte alors tout le poids.
- **Une recharge de réponse n'est pas toujours plus longue que l'outil** : l'Insertion (7 s) répond à la
  Bavure (8), au Spiral (12), au Filigrane (12), à la Rupture (15) et au Pâté (20). C'est la réponse la
  moins chère et la plus disponible du roster, et elle couvre six outils.

Les deux sont à corriger par les données (un second mur ou un second buff dans un autre pigment, une
recharge d'Insertion plus longue), pas par cette page.

## 6. Interactions de pigment (simples, lisibles)

| Interaction | Règle serveur (`CombatService` tags) |
|---|---|
| **Le Vert-de-gris attise le Cinabre** | une cible touchée par un glyphe Vert-de-gris porte *Éventé* 3 s : +25 % de dégâts de Cinabre |
| **L'Indigo éteint le Cinabre** | une AoE/Zone d'Indigo lancée dans une zone de Cinabre active (Roussi, traînée de Ligature) la termine |
| **La Terre d'Ombre bloque** | Marge et Dorure arrêtent projectiles et knockback |
| **L'Orpiment conduit dans l'Indigo** | une cible dans une Bavure ou un Lavis en cours subit +25 % de dégâts d'Orpiment |

Chaque interaction est un bonus plat et visible (VFX + texte flottant), jamais un multiplicateur caché.

## 7. Modes

| Mode | Joueurs | Durée | Victoire | Récompenses |
|---|---|---|---|---|
| Hub | tous | libre | — | Épreuves (mannequins) : 40 Folios/jour au plus, XP entière pour 25 kills puis 5 %, rien sans glyphe ni ruée dans la minute, jamais d'XP de pass (D-245 à D-247) ; quêtes |
| 1v1 classé | 2 | 3 min, best-of-3 optionnel | KO adverse | XP, Folios, Elo, pass ; duel rapide non classé pour les nouveaux venus (E10-S7) |
| 3v3 | 6 | 5 min | équipe adverse éliminée ou plus de KO | XP, Folios, Elo équipe, pass |
| World Boss | serveur entier | événement toutes les 20 min | boss vaincu avant le timer | contribution aux dégâts → XP/Folios/pass |
| Champ de bataille (D-131) | tous (12 max) | libre | — | XP/Folios par Faussaire vaincu (Folios plafonnés à 150/jour), quête `BotKill` |
| Page de garde (E16-S2, D-267) | tous (12 max) | libre | — | 60 XP par victoire, 5 Folios (plafonnés à 100/jour), rien au-delà de 3 morts du même rival en 10 min ; ni rang ni Elo |
| Duel d'épreuve (E10-S6) | 1 contre un Faussaire Duelliste, pendant la file 1v1 | premier à 2 manches, 1 min par manche | KO du Faussaire, ou la plus grande part de vie au chrono | ×0,5 d'un duel classé, 3 fois/jour ; ni Elo, ni rang, ni quête, ni première victoire, ni `MatchesPlayed` |
| Entraînement contre l'Effacement (D-132) | 1+ (rejoindre en cours ; le boss grandit au premier coup du nouveau venu) | 4 min | boss vaincu | ×0,25 d'une participation, 3 fois/jour, 1 fois/20 min, les deux tenus par le profil (une paie sous 1 Folio ne décompte rien), ni quête ni `BossKills` |

Le champ de bataille et l'entraînement s'ouvrent par les **portails** du hub (D-130) : on se tient dans le cercle de craie sous le portique (1,5 s ; 2 s pour revenir), sans touche ni remote, et le serveur déplace. Au champ de bataille, PvE seulement : les Faussaires (Barbouilleur au corps à corps, Plume à distance, Surchargeur lourd — le joueur ne lit que « Faussaires ») annoncent chaque coup à l'encre au sol pendant toute sa préparation (D-133) ; trois pour un joueur, un de plus par joueur actif, dix au plus ; un camp à l'ouest où ils n'entrent pas, où l'on régénère et où l'on réapparaît, et d'où un coup ne compte pour rien (D-134). L'événement de l'Effacement y appelle les joueurs comme ailleurs.

Dans un serveur privé acheté par un joueur (`game.PrivateServerOwnerId ~= 0`), 1v1 et 3v3 se jouent en non classé : ni Elo ni classement, la moitié de l'XP et des Folios d'un match, ni première victoire du jour ni quête de victoire, et la file l'annonce (« Non classé en serveur privé »). Un serveur réservé par le jeu reste classé (D-251).

La **Page de garde** (E16-S2) est la mêlée libre du troisième portail, au centre des trois : chaque membre contre chaque autre, sans file ni rang. On arrive, et l'on revient 3 s après une mort, sur celui des six sceaux le plus loin des autres membres, protégé 4 s (un champ de force le montre ; ni coup reçu ni coup donné). Une victoire paie 60 XP et 5 Folios, plafonnés à 100 Folios par jour dans le profil ; plus rien n'est payé pour un rival qu'on a déjà vaincu trois fois dans les dix dernières minutes. Trois victoires sans mourir posent la **Manicule** au-dessus de la tête : la main qui pointe des marges, que tout le monde voit, jusqu'à la mort de celui qui la porte ; chacun apprend qui la porte et qui la fait tomber.

Le **duel rapide** (E10-S7) : tant qu'un joueur n'a pas atteint le niveau 10 et joué 5 matchs, ses matchs sont non classés. Un match où joue un nouveau venu ne bouge le classement de personne et un abandon n'y coûte rien ; il est joué, compté et payé en entier. En file, un nouveau venu n'est apparié qu'à 300 de classement au plus de lui pendant ses 120 premières secondes d'attente. L'écran Jouer lui dit pourquoi et ce qui lui manque ; l'annonce du match donne le niveau et le rang de chaque adversaire.

Le **duel d'épreuve** s'offre sur la carte 1v1 de l'écran Jouer après 20 s seul dans la file 1v1 : le joueur garde sa place, affronte dans une fosse un Faussaire Duelliste (deux barres verticales sur la poitrine, une chaîne de trois coups qui fait tomber et un trait pour qui ne fait que courir), sur le HUD et la carte de résultat d'un match non classé. Un humain qui arrive dans la file prend la main à la prochaine pause de manche : pendant une manche, le matchmaking ne le prend pas ; à la pause, le duel s'arrête avant que le match commence, sans rien payer. « Quitter l'épreuve » en sort à tout moment, sans rien payer, et la file continue ; tant qu'il se bat, sa place dans la file n'expire pas.

Cycle d'un match : file → arène instanciée → téléport → compte à rebours 5 s → combat (PvP limité aux adversaires — pas de tir ami en 3v3, D-113 —, spawn protection 4 s) → fin (KO, timer : vainqueur = plus de vie restante, égalité possible) → écran de résultat → retour hub → cleanup.

Le classé ne se farme pas à deux comptes (D-255) : un forfait avant 30 s de jeu, ou sans un seul point de dégâts échangé, est **nul** (celui qui part est débité, celui qui reste n'a rien : ni Elo, ni récompense, ni quête) ; au-delà de 6 matchs classés d'une même paire dans la journée UTC (un duel et cinq revanches), l'Elo de la paire ne bouge plus et le match ne rapporte qu'un quart de son XP et de ses Folios ; une journée de matchs rapporte au plus 1 400 Folios (avant le VIP), kills compris. Chiffres : `MatchConfig.MinPlayedSeconds`, `MatchConfig.DailyFolioCap`, `RankingConfig.Opponents`.

## 8. Hub et arènes (générés en code — points d'ancrage)

- **Hub** : plateforme 200×200 en vélin bordée d'encre, spawn au centre (un sceau de craie sur un rebord d'encre), anneau d'épreuves (rayon 22), terminal de file et boutique (un emblème d'encre ; chaque client y écrit le nom dans sa langue et y place une invite qui ouvre l'écran Jouer ou Boutique), tableaux de classement (SurfaceGui : les lignes par le serveur, le titre et l'état vide par chaque client), D-128 ; trois portails au nord, sur un anneau de 68 studs, face au spawn : la Page de garde à −π/2, le champ de bataille et l'Effacement à ±0,45 rad de part et d'autre (D-130, D-267). Couleurs et matériau : `WorldConfig` (D-86). Le **Pupitre** (`DrillLectern`, D-223) est un pédestal comme le terminal et la boutique, sur leur anneau à −π/4, entre le terminal et le portail de l'Effacement : son emblème est un trait de plume penché, chaque client écrit son nom au-dessus et y place l'invite qui ouvre l'écran du Pupitre (§9 bis). Le remplacement par des assets doit conserver les noms de `WorldConfig.HubAnchors` : `HubSpawn`, `QueueTerminal`, `LeaderboardBoard_<mode>` (son `Panel`), `ShopKiosk`, `BattlegroundPortal`, `BossPortal`, `FlyleafPortal`, `DrillLectern`.
- **Portail** (`World/PortalGate`, D-130) : deux poteaux et un linteau d'encre, un `Panel` à emblème (formes seulement, jamais de texte), un sceau de craie de 10 studs sur un rebord d'encre ; la zone est la pièce invisible `Seal` à son pied, étiquetée `PortalConfig.SealTag` et nommant sa destination dans l'attribut `PortalConfig.SealAttribute` (`Battleground`, `WorldBoss`, `Flyleaf`, `Return`). Chaque client écrit au-dessus où il mène et ce qu'il demande.
- **Arène 1v1** : plateforme 80×80 en vélin, murs os à filet d'encre et kill zone sous le sol, `Spawn_Team1` / `Spawn_Team2` à 30 studs l'un de l'autre.
- **Arène 3v3** : 120×120, trois spawns par équipe espacés de 8 studs, deux murs bas centraux pour casser les lignes.
- **Arène Boss** : 160×160, spawns joueurs sur le périmètre, `BossSpawn` au centre. L'Effacement y est une figure blanche à bande d'encre dont la hauteur dit la phase (D-87). Un portail de retour `ReturnPortal` dans un coin, à 12 studs des deux murs, face au centre (dans le gabarit, donc dans chaque copie).
- **Champ de bataille** (`workspace.Battleground`, D-131) : une page de 170×170 à X = 1500, murs os à filet d'encre, huit piliers et une stèle au centre, six couverts de 14 studs (plus haut que le double saut), réglure à l'encre ; le camp à l'ouest (lavis, ligne d'encre à x = −59) avec `Arrival_1..6` et le portail `ReturnPortal` face à l'est ; `BotSpawn_1..8` loin des arrivées ; `KillZone` 40 studs sous le sol ; les Faussaires dans `workspace.Forgers`, étiquetés `Forger`.
- **Page de garde** (`workspace.Flyleaf`, E16-S2) : une page de 120×120 à X = −1500, murs os à filet d'encre, réglure à l'encre, quatre couverts d'encre de 14 studs autour du centre ; six sceaux de craie `Seal_1..6` sur un hexagone de rayon 38 ; le portail `ReturnPortal` contre le mur nord, face au sud ; `KillZone` 40 studs sous le sol. Le corps d'un membre porte l'attribut `FlyleafMember`, celui qui porte la Manicule l'attribut `Manicule`.
- **Fosses du duel d'épreuve** (`workspace.SparPits`, E10-S6) : quatre sols de 60×60 dans le repère de la page, à sa hauteur, en ligne à l'est (x local 420, 750, 1080, 1410), chacun à plus de 250 studs (la portée des paquets) de la page et du suivant ; murs os à filet d'encre de 20 studs, au-dessus du double saut ; le joueur posé à l'est, face au Faussaire à l'ouest, sur l'axe de la page ; une chute de 40 studs sous le sol est une mort.

## 9. Rétention

Quêtes journalières (3) et hebdomadaires (3) data-driven, dont au moins deux qu'un joueur seul peut finir dans chaque tirage, et une relance gratuite par jour d'une quête du jour vers une quête Solo (D-241, D-242), calendrier de connexion de 28 jours (une série de jours réclamés d'affilée, un cosmétique jamais vendu aux jours 7, 14, 21 et 28, et le Signet, un marque-page gagné le 3ᵉ jour de chaque semaine, deux au plus, qui garde la série un jour manqué ; E15-S1), bonus de première victoire du jour, pass saisonnier 50 paliers (gratuit / premium) qui dure un Volume : 152 880 XP, fini à J34 à 20 min/jour de duels, J41 à 20 min/jour seul, J15 à une heure par jour (`scripts/pacing.luau`, D-249), rang saisonnier (Vierge → Esquisse → Écriture → Enluminure → Codex) avec récompense de fin de saison, cosmétiques (skins de glyphes = une nuance du pigment du glyphe, jamais une autre teinte ; auras, traînées, effets de kill et titres dessinés dans les encres de la page — D-109).

**Objectifs longs (E17-S2, D-224, D-225).**
- **Les jalons de 45 à 100.** Passé le dernier glyphe (36) et l'Orpiment (40), un jalon tous les cinq niveaux jusqu'à 100 paie une fois dix Folios par niveau du jalon, et un titre réservé à 50 (Rubricateur), 75 (Maître copiste) et 100 (Cent feuillets). Glyphes, pigment et jalons sont une seule **route des niveaux** (`Pure/LevelRoad`) : la carte Résultat nomme toujours sa prochaine étape (« Prochain : 450 Folios au niveau 45 »), sans promettre ce que le joueur tient déjà, et dit au niveau 100 que la route est parcourue. Un profil qui charge avec des jalons dépassés et jamais payés les reçoit en une ligne.
- **L'Ex-libris.** Treize plaques à vie, chacune accordée une fois par le serveur quand une mesure qu'il compte déjà atteint sa cible : adversaires vaincus (100, 1 000), matchs joués (25, 250), glyphes tracés (1 000, 10 000), la plus longue chaîne (4, 6), l'Effacement vaincu pendant son événement (1, 10), et les grades du Pupitre (le kit en Calligraphie, 10 exercices en Mise au net, 20 en Calligraphie). Des Folios, et quatre titres réservés (Mille ratures, Écorné, D'un seul souffle, Calligraphe). Montants : `docs/ECONOMY.md` §2.

**Ce que l'interface en montre (D-147).**
- **Les badges.** Ce qui attend d'être récupéré (récompense du jour, quêtes terminées, paliers du pass) est compté par `Claimables` et badgé : sur le bouton Menu, et dans l'amas méta du hub, un sceau par sorte, dans la couleur de l'écran qu'il ouvre, visible seulement quand il y a quelque chose. Jamais en combat.
- **La récompense du jour s'ouvre seule**, une fois par session, trois secondes après l'arrivée du profil, si elle attend et que rien d'autre ne retient le joueur (ni combat, ni file, ni écran ouvert).
- **Les premiers pas.** Sous l'amas méta, une carte pour un nouveau joueur : tracer un glyphe, jouer un match, récupérer la récompense du jour, cochées depuis le profil seul (aucun champ nouveau) ; les deux dernières ouvrent leur écran à la souris ; au toucher la carte se lit seulement, parce qu'elle est sous le cadre du joystick du moteur (D-158). Une fois les trois faites, la carte est tamponnée et se replie.
- **Les puces fantômes** de la première recette reviennent après une séquence qui n'a pas abouti, jusqu'au premier glyphe compté par le serveur.

Détails économiques : `docs/ECONOMY.md`.

## 9 bis. Les Exercices au Pupitre (E14-S2, D-223)

Au Pupitre du hub, le joueur choisit un exercice ; l'écran se ferme et l'exercice se fait sur les mannequins de l'anneau d'épreuves. Le serveur le compte, répétition par répétition, à partir de ce qu'il a lui-même accepté, et le dit en toasts (« Marque · 2 / 3 », « raté », le grade).

| Exercice | Une répétition | Un raté | Répétitions | Temps de la Calligraphie |
|---|---|---|---|---|
| **Les quatre traits** (kit) | les quatre coups d'un enchaînement de M1, chacun porté | un coup de M1 qui ne touche rien | 3 | 12 s |
| **L'annulation** (kit) | le dernier coup porté, puis la ruée qui coupe sa récupération (§5 bis) | une ruée qui n'annule rien, ou qui suit un dernier coup dans le vide | 3 | 15 s |
| **La chaîne de trois** (kit) | trois glyphes acceptés, chacun dans la seconde du précédent | une chaîne qui s'arrête avant trois | 2 | 20 s |
| **Une recette** (un par glyphe) | le glyphe posé sur un corps ; un mur, un buff ou un saut dès qu'il est accepté | le glyphe qui ne touche rien, ou un autre glyphe | 3 | la recharge entre chaque lancer, plus 8 s |

Une série finie est notée **Brouillon** (finie), **Mise au net** (au plus un raté) ou **Calligraphie** (aucun raté, et la dernière répétition dans le temps depuis le premier événement compté). Chaque grade de chaque exercice paie une fois (`DrillConfig.Grades`) ; refaire un exercice n'a de prix que pour un meilleur grade. Une recette demande son glyphe débloqué et équipé : l'écran propose sinon d'aller à l'Équipement, ou dit le niveau qui le débloque. Un exercice ne compte qu'au hub : partir en match, au champ de bataille ou devant l'Effacement le pose, une minute sans rien de compté aussi. L'écran du Pupitre a trois onglets : les exercices (la série en cours en tête, avec « Poser »), la route des niveaux, l'Ex-libris.
