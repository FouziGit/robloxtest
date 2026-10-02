# Économie — Vellum V2

Toutes les valeurs sont des points de départ à ajuster avec les données réelles (voir KPIs). Les identifiants Roblox (game passes, developer products) sont à renseigner dans `src/shared/Config/MonetizationConfig.luau` (voir `docs/STUDIO_SETUP.md`).

## 1. Monnaies

| Monnaie | Nature | Obtention | Usage |
|---|---|---|---|
| **Folios** | douce (gagnée) | matchs, kills, quêtes, boss, calendrier de connexion, pass, achat de packs | boutique cosmétique, rotation quotidienne |
| **Robux** | dure | achat réel | game passes, developer products, depuis les surfaces d'achat (§5) |

Aucun pigment de puissance n'est vendu contre Robux : Orpiment est un sidegrade débloquable au niveau 40 (`docs/GAME_DESIGN.md` §5), les slots de loadout apportent de la variété, tout le reste est cosmétique ou du confort (boost d'XP, saut de paliers).

## 2. Sources de Folios (par heure de jeu typique : ~6 matchs, 2 quêtes, 1 boss)

| Source | Folios | Fréquence / h | Total / h |
|---|---|---|---|
| Victoire 1v1 / 3v3 (plafond de 1 400 / jour avec les défaites et les kills, D-255) | 60 | ×3 | 180 |
| Défaite | 20 | ×3 | 60 |
| Kill joueur (payé avec le résultat du match, sous les mêmes règles) | 15 | ×8 | 120 |
| Épreuve du hub (mannequin, E10-S3) | 2 | ×20, plafond **40 / jour** (profil) | 40 |
| Quête journalière | 50 | ×2 | 100 |
| Quête hebdomadaire (amortie) | 200 | ×0,4 | 80 |
| World Boss (participation + bonus) | 80 + 150 | ×0,8 | 180 |
| Faussaires du champ de bataille (D-131) | 1–4 (Barbouilleur, Plume 1 ; Surchargeur 4) | plafond **150 / jour** (profil) | hors du total ci-dessous |
| Page de garde (E16-S2) | 5 par victoire (60 XP) | plafond **100 / jour** (profil) ; rien au-delà de 3 morts du même rival en 10 min | hors du total ci-dessous |
| Entraînement contre l'Effacement (D-132) | ≤ 58 (×0,25 d'une participation) | 3 / jour, 1 / 20 min (les deux dans le profil, D-222) ; une paie sous 1 Folio n'en décompte aucun (D-134) | ≤ 174 / jour, hors du total |
| Duel d'épreuve contre un Faussaire (E10-S6) | 30 / 18 / 10 (×0,5 d'une victoire, égalité, défaite) | 3 / jour (profil, `Daily.SparDay` / `SparPaid`) | ≤ 90 / jour, hors du total |
| Première victoire du jour | 100 | ×1 | 100 |
| Calendrier de connexion (28 jours, moyenne) | 159 | ×1 | 159 |
| **Total** | | | **≈ 1 020 Folios / h** (≈ 700 pour un joueur moyen) |

VIP : Folios ×1,5 (≈ 1 400 / h). Premium (abonnés Roblox Premium) : +150 Folios et 30 min d'XP doublée par jour, via le bonus dédié (§6).

**Calendrier de connexion (E15-S1).** 28 jours réclamés un par jour (`DailyConfig.Calendar`) : chaque semaine reprend la rangée montante de l'ancienne série de 7 jours, un peu plus haut que la précédente (850, 1 025, 1 200 et 1 375 Folios), soit **4 450 Folios et 8 000 XP par mois**, contre 4 000 Folios pour quatre semaines de l'ancienne série. Les jours 7, 14, 21 et 28 donnent un cosmétique jamais vendu (titre Rare, traînée Rare, titre Épique, aura Épique) ; un cosmétique déjà possédé (le deuxième mois) paie 300 Folios de plus à sa place (`OwnedCosmeticFolios`). Le 3ᵉ jour de chaque semaine glisse un Signet dans le livre, deux au plus : un Signet garde la série un jour manqué. Les Signets ne se vendent pas.

Les matchs classés sont bornés eux aussi (D-255) : **1 400 Folios par jour** au plus, résultats et kills ensemble (`MatchConfig.DailyFolioCap`, montant de base avant le VIP, compté dans le profil : `Daily.MatchDay` / `MatchFolios`), soit environ quatre heures de matchs au rythme du tableau ci-dessus (360 / h) ; au-delà, un match ne paie plus que de l'XP, et un toast le dit. Au-delà de 6 matchs d'une même paire de joueurs dans la journée UTC (un duel et cinq revanches) (`RankingConfig.Opponents`, compté dans les deux profils : `Rank.Opponents`), le match ne rapporte qu'un quart de son XP et de ses Folios, et l'Elo de la paire ne bouge plus ; un match qui ne bouge aucun Elo (le duel rapide d'un nouveau venu, un serveur privé acheté) compte pour la paire et suit la même règle. Un forfait avant 30 s de jeu ou sans dégâts échangés est nul : le survivant ne touche rien. Les kills d'un match (120 XP et 15 Folios chacun) sont payés par `MatchService` avec son résultat et sous ses règles : la moitié en serveur privé, le quart pour une paire répétée, rien pour un match nul ou annulé ni pour celui qui est parti, et leurs Folios sous le même plafond. Ce que rapporte au mieux un farm à deux comptes : six victoires pleines par compte secondaire et par jour, sous le même plafond qu'une journée honnête. Aucun âge de compte minimum n'est exigé.

Serveur privé acheté (D-251) : le classé n'y compte pas. Un match y paie la moitié de son XP et de ses Folios, kills compris (`MatchConfig.PrivateServer.RewardShare`), et le quart de cette moitié au-delà des 6 matchs de la paire dans la journée ; ni la première victoire du jour ni la quête d'une victoire, et aucun Elo ne bouge. Un serveur réservé par le jeu reste classé.

Les trois sources ajoutées par les portails sont bornées **par jour, dans le profil** (`DailyCap`, compteurs `Daily.ForgerDay` / `ForgerFolios`, `PracticeDay` / `PracticePaid` et `FlyleafDay` / `FlyleafFolios`) : changer de serveur ne les remet pas à zéro. À la Page de garde, une victoire ne passe pas par le « Kill joueur » du match (15 Folios, 120 XP) : la page la paie elle-même, 5 Folios et 60 XP, et ne paie plus rien pour un rival qu'on a vaincu trois fois dans les dix dernières minutes (le registre vit dans la mémoire du serveur, et quitter puis revenir ne l'efface pas). Le plafond des Faussaires porte sur le montant de base, avant le VIP ; au-delà, un Faussaire ne paie plus que de l'XP, et un toast le dit une fois par jour.

Les Épreuves du hub le sont aussi depuis E10-S3 (`TrialPay`, compteurs `Daily.TrialDay` / `TrialKills` / `TrialFolios`) : 40 Folios par jour au plus, l'XP entière (40) pour les 25 premiers kills du jour puis 5 % (2 XP), rien sans glyphe lancé ni ruée dans la minute, et jamais d'XP de pass ; un glyphe qui touche une Épreuve ne paie pas d'XP (D-245 à D-247). Un toast le dit une fois par jour, au kill qui épuise les Folios.

**Récompenses uniques (E14-S2, E17-S2 ; D-223 à D-225).** Trois sources ne paient qu'une fois par profil, écrites dans le profil avant d'être payées ; elles sont hors du total à l'heure ci-dessus. Montants de base, avant le VIP (Folios ×1,5, XP ×2) et le boost d'XP.

| Source | Par unité | Plafond par jour | Total à vie | Rythme attendu |
|---|---|---|---|---|
| Exercices du Pupitre (`DrillConfig`) | 15 / 30 / 60 Folios et 50 / 100 / 200 XP par grade (Brouillon, Mise au net, Calligraphie) : **105 Folios et 350 XP** par exercice mené jusqu'à la Calligraphie | ce que le profil a débloqué et pas encore noté : **1 155 Folios et 3 850 XP** le premier jour au plus (les 3 exercices du kit et les 8 glyphes de départ), puis **105 Folios et 350 XP** par glyphe nouvellement débloqué | **3 255 Folios, 10 850 XP** (3 + 28 exercices) | une série dure moins d'une minute ; les 10 850 XP valent 1,2 à 1,5 h de match (7 200 à 9 000 XP/h), et mèneraient un profil neuf qui ferait tout d'un coup du niveau 1 au niveau 19 (les glyphes débloqués en chemin ouvrent leurs exercices) |
| Jalons de niveau 45 → 100 (`ProgressionConfig.Milestones`) | 10 Folios par niveau du jalon (450 à 1 000), et un titre à 50, 75 et 100 | un jalon tous les cinq niveaux : 22 463 XP séparent 45 de 50 (2,5 à 3,1 h), 59 789 séparent 95 de 100 (6,6 à 8,3 h) ; **au plus ≈ 500 Folios par jour** pour 3 h de jeu vers 45-50, moins ensuite | **8 700 Folios**, 0 XP | 444 653 XP de 45 à 100, soit 49 à 62 h : **≈ 140 à 180 Folios/h** en moyenne, +14 à 18 % sur les ≈ 980 Folios/h ci-dessus, pour un vétéran seulement |
| Ex-libris (`ExLibrisConfig`) | 150 à 600 Folios par plaque, un titre pour quatre d'entre elles | borné par les mesures : les plaques faciles (100 adversaires, 25 matchs, 1 000 glyphes, une chaîne de 4, l'Effacement une fois, le kit en Calligraphie) valent **≈ 950 Folios** sur les premières semaines ; aucune ne se répète | **4 200 Folios**, 0 XP | le reste (mille adversaires, 250 matchs, 10 000 glyphes, une chaîne de 6, l'Effacement dix fois, vingt exercices en Calligraphie) sur des dizaines d'heures |

Aucune de ces sources ne se renouvelle : un changement de serveur ou une reconnexion ne rouvre rien (`Drills`, `Milestones`, `ExLibris` dans le profil, D-226). Les titres sont des cosmétiques réservés (`Sellable = false`), jamais en boutique.

**XP à l'heure : voir §2 bis**, mesurée par le simulateur sur les vraies configs et non plus estimée à la main. L'XP des Faussaires reste sans plafond : 9 716 XP/h pour un joueur seul, au-dessus d'une heure de duels (8 237). Ce n'est pas l'objet de E10-S3, mais c'est désormais l'activité sûre la mieux payée ; à revoir avec le développeur.

## 2 bis. Le rythme, mesuré par le simulateur

`lune run scripts/pacing -- --table` joue quatre profils pendant 60 jours avec les vraies configs et les règles que le serveur exécute (`TrialPay`, `DailyCap`, `QuestLogic` avec plancher Solo et relance gratuite, les jalons de niveau et les plaques de l'Ex-libris par `ExLibris` depuis la fusion de la vague 2, rotation réelle de la boutique) ; `tests/Pacing.spec.luau` le lance à chaque porte de qualité. L'export jour par jour est `docs/economy/pacing.csv`, repris en formules dans `docs/economy/Vellum-economie.xlsx` (`python3 tools/economy/workbook.py`). Sortie du 30/09/2026 :

| Profil | Niv. 5 | Niv. 10 | Niv. 20 | Niv. 40 | Pass fini | Folios gagnés J7 | Folios gagnés J30 | Catalogue complet |
|---|---|---|---|---|---|---|---|---|
| 20 min/j seul (5 min d'Épreuves, 15 min de Faussaires) | 1 min | 9 min | 43 min | 253 min | J41 | 4 760 | 25 125 | J55 |
| 20 min/j en PvP (duels) | 3 min | 11 min | 52 min | 277 min | J34 | 7 320 | 37 775 | J35 |
| 60 min/j en PvP (duels) | 3 min | 11 min | 65 min | 364 min | J15 | 15 655 | 67 825 | J18 |
| Fermier d'Épreuves (60 min/j) | 1 min | 19 min | 237 min | 1 144 min | jamais | 4 030 | 15 625 | après J60 |

XP par heure de chaque activité seule (sans quêtes, série ni première victoire) : duels 8 237, Faussaires 9 716, Épreuves du fermier 1 858 (22,6 % des duels ; le gate exige moins de 30 %). Le pass coûte 152 880 XP (D-249) ; 24 objets s'obtiennent sans Robux (les 14 de la boutique et les 10 de la piste gratuite). « Catalogue complet » : le jour où le profil possède ces 24 objets en achetant, chaque jour, le moins cher de la rotation qu'il peut payer ; les titres des jalons et de l'Ex-libris, réservés, n'en sont pas.

Les jalons et l'Ex-libris (D-224, D-225) comptent dans ces Folios : aucun profil ne fait d'exercice ni ne combat l'Effacement, les plaques payées sont celles des adversaires, des matchs, des glyphes et des chaînes (la plus longue chaîne d'un joueur est prise comme la plus longue dont le nombre attendu, sur ses lancers, atteint un). À la fusion de la vague 2, ils ont avancé le catalogue complet de J32 à J18 à une heure de duels par jour, de J41 à J36 à 20 minutes, et l'ont fait tenir dans les 60 jours du joueur seul (J58) ; une heure de duels par jour atteint le niveau 100 avant J60, et le fermier touche les plaques d'adversaires (100 et 1 000) dès J1 et J3, une Épreuve abattue comptant comme un kill qu'elle paie ou non (`EnemyService`). À la fusion de la vague 3, le simulateur réclame le calendrier de 28 jours (D-271) au lieu de l'ancienne série de 7 jours : sa première semaine paie 850 Folios au lieu de 1 000 (J7 un peu plus bas), le mois 4 450 au lieu de 4 000 (J30 plus haut), et le catalogue complet avance d'un à trois jours (J55 pour le joueur seul, J35 à 20 minutes de duels) ; les cosmétiques du calendrier, jamais vendus, n'entrent pas dans ce catalogue.

Ce que les configs ne disent pas est dans `Pacing.Assumptions`, une fois chacun, à remplacer par des mesures (E8) : file de 45 s et 10 s de portail par duel, manche de 50 s, matchs par quatre (deux gagnés, deux perdus, un net et un serré de chaque), un glyphe sur deux qui touche en duel (7 sur 10 sur un Faussaire, tous sur une Épreuve), un tiers du combat au corps à corps en duel, 6 ruées et 1 annulation par minute, un glyphe sur cinq enchaîné, un Faussaire qui encaisse 60 % des dégâts et demande 3 s d'approche. Les lancers de glyphes suivent l'encre en combat (`CombatConfig.Ink.RegenInCombat` sur le coût moyen de l'équipement de départ), les coups de poing la cadence du combo (`CombatConfig.Melee`).

Trois constats pour le développeur, hors de ces stories : le niveau 40 (Orpiment) arrive en 4 à 6 h de jeu et non en 15-20 h ; une heure de Faussaires paie plus d'XP qu'une heure de duels ; et les plaques « adversaires » de l'Ex-libris se gagnent sur les Épreuves du hub (650 Folios au fermier en trois jours), ce que E17-S2 n'avait pas pesé. À la Page de garde, l'XP n'est pas plafonnée non plus (60 par victoire) mais elle suit les victoires sur de vrais joueurs : une victoire toutes les 30 à 60 s donnerait **3 600 à 7 200 XP/h**, sous la courbe d'un match ; deux comptes qui échangent leurs victoires s'arrêtent à trois chacun toutes les dix minutes (≈ 2 200 XP/h pour chacun).

## 3. Puits de Folios (boutique cosmétique)

| Rareté | Prix Folios | Heures de jeu ≈ | Exemples |
|---|---|---|---|
| Commun | 600 | 1 h | traînée simple, titre |
| Rare | 1 800 | 2,5 h | aura ou traînée à l'encre (un style), skin de glyphe (une nuance de son pigment) |
| Épique | 4 000 | 6 h | effet de kill, aura animée |
| Légendaire | 8 000 | 11 h | aura à plusieurs styles superposés (aura du Codex), effet de kill |

Rotation quotidienne : 6 articles (2 communs, 2 rares, 1 épique, 1 légendaire) tirés de façon déterministe par jour (`ShopRotation`, seed = jour UTC). Chaque article peut être acheté en Folios **ou** via un developer product Robux équivalent (jamais de tirage aléatoire payant : boutique directe, conforme aux politiques Roblox sans `PolicyService` d'aléatoire payant).

## 4. Catalogue Robux

### Game passes (permanents)

| Pass | Prix R$ | Contenu | Clé `MonetizationConfig.Passes` |
|---|---|---|---|
| VIP | 399 | XP ×2, Folios ×1,5, tag chat, aura exclusive | `Vip` |
| Slots de loadout | 199 | +4 slots (6 → 10) | `LoadoutSlots` |
| Pigment Orpiment | 299 | déblocage immédiat d'Orpiment (sinon niveau 40) | `Orpiment` |
| Pack de skins | 249 | 4 skins de glyphe (1 par pigment de base) | `SkinPack` |

### Developer products (consommables)

| Produit | Prix R$ | Contenu | Clé `MonetizationConfig.Products` |
|---|---|---|---|
| Folios ×1 000 | 99 | 1 000 Folios | `FolioSmall` |
| Folios ×3 500 | 299 | 3 500 Folios (+17 %) | `FolioMedium` |
| Folios ×8 000 | 599 | 8 000 Folios (+33 %) | `FolioLarge` |
| Pass premium (saison) | 349 | piste premium de la saison courante ; déjà possédée à l'arrivée du reçu, 3 530 Folios (D-202) | `PremiumPass` |
| +5 paliers de pass | 149 | avance de 5 paliers ; chaque palier au-delà du dernier est payé 310 Folios (D-202) | `TierSkip5` |
| Boost d'XP 1 h | 79 | XP ×2 pendant 60 min | `XpBoost1h` |

Conversion implicite : 1 R$ ≈ 10-13 Folios. Un légendaire (8 000 Folios) vaut ≈ 600 R$ ou ≈ 11 h de jeu : le joueur gratuit peut tout obtenir, le joueur payant gagne du temps.

## 5. Placement des offres (non agressif)

**Aucune offre ne s'ouvre d'elle-même** : ni prompt contextuel, ni fenêtre d'achat automatique (D-205). Chaque offre est une surface que le joueur touche, posée là où l'envie naît.

| Moment | Offre | Garde-fou |
|---|---|---|
| Palier de pass bloqué (piste premium) | Pass premium | seulement sur l'écran du Pass, sur le geste du joueur : « Obtenir le Premium », au-dessus des récompenses verrouillées (le mot « Premium » et un cadenas) |
| Loadout plein | Slots | seulement sur l'écran d'équipement, sur le geste du joueur : « +4 emplacements » |
| Boutique | article en Folios insuffisant | la fiche de confirmation le dit (solde après achat en rouge), grise « Acheter » et propose « Obtenir des Folios », qui ouvre l'onglet Folios ; le prix « R$ » de l'article reste sur sa carte |
| Défaite de peu, mort face à un joueur Orpiment | aucune | un toast de vente juste après une défaite est le placement le plus agressif ; il n'existe pas (D-205) |

Chaque fenêtre ouverte est journalisée, acceptée ou refusée (`Analytics`, `PromptAccepted` / `PromptDeclined`). Si une offre contextuelle revient un jour, elle reste un toast et suit ces garde-fous : jamais pendant un combat, rien dans les 3 premières minutes de la première session, au plus une toutes les 5 minutes, et chaque offre affichée journalisée elle aussi.

### Surfaces d'achat à l'initiative du joueur (D-147)

La passe UI couleur ajoute des endroits où le joueur **choisit** d'acheter ; aucun n'ouvre quoi que ce soit de lui-même. Chacun n'ouvre la fenêtre d'achat de Roblox que sur un geste du joueur, et seulement pour une entrée qui a un id sur Roblox (`MonetizationConfig`, id non nul ; sinon le bouton est grisé). Le serveur reste l'autorité : il résout l'id, refuse ce qui est déjà possédé, un saut de paliers au dernier palier, un article sorti de la rotation, et le dit par un toast. **Aucun prompt automatique n'a été ajouté**, et il n'y a pas de prompt contextuel (D-205).

| Écran | Surface | Ce qu'elle déclenche | Garde-fou côté interface |
|---|---|---|---|
| Boutique, onglet « Du jour » | le prix en Folios de chaque article | la fiche de confirmation (l'article, le solde avant → après), puis `BuyCosmetic` sur « Acheter » ; jamais en un seul geste | « Acheter » grisé si le solde ne suffit pas ; l'achat attend la réponse du serveur (5 s au plus) |
| Boutique, onglet « Du jour » | le prix « R$ » de chaque article | `PromptPurchase("Cosmetic", id)` | le produit de sa rareté doit exister sur Roblox |
| Boutique, onglet « Folios » | les trois packs (1 000, 3 500, 8 000) | `PromptPurchase("Product", FolioSmall / FolioMedium / FolioLarge)` | id non nul |
| Boutique, onglet « Pass et packs » | VIP, Slots d'équipement, Pigment Orpiment, Pack de skins ; Battle Pass Premium, +5 paliers, Boost d'XP | `PromptPurchase("Pass", clé)` ou `PromptPurchase("Product", clé)` | id non nul ; un pass possédé (et le premium de la saison) montre « Possédé » au lieu d'un prix ; +5 paliers grisé au dernier palier |
| Battle Pass | « Obtenir le Premium », « +5 paliers » | `PromptPurchase("Product", PremiumPass / TierSkip5)` | « Obtenir le Premium » caché une fois le premium possédé ; +5 paliers grisé au dernier palier ; une récompense premium verrouillée montre le mot « Premium » et un cadenas, sans phrase de refus |
| Équipement (tranche B) | « +4 emplacements », tant que `LoadoutSlots` n'est pas possédé | `PromptPurchase("Pass", LoadoutSlots)` | id non nul ; pas de prix affiché (l'invite de Roblox le montre) ; c'est l'offre de la ligne « Loadout plein » ci-dessus |
| Menu | le « + » à côté des Folios | ouvre la Boutique sur l'onglet Folios ; n'achète rien | — |

Le Casier (onglet de la Boutique) ne vend rien : il montre ce que le joueur possède, pour l'équiper ou le retirer.

## 6. Premium Payouts

Les abonnés Roblox Premium génèrent des payouts proportionnels au temps passé. Levier : le bonus quotidien Premium, 150 Folios et 30 min d'XP doublée (`DailyConfig.PremiumBonus`), une fois par jour UTC, versé au chargement du profil et dès qu'un joueur devient Premium en cours de session (`PlayerMembershipChanged`). Ni badge de file ni quêtes hebdomadaires bonus (D-204). Aucune exclusivité de gameplay.

## 7. Idempotence et sécurité des achats

- `ProcessReceipt` : lit le profil (`DataService.waitFor`), vérifie `Purchases.Receipts` (anneau de 100 ids), applique le produit, enregistre `PurchaseId`, force une sauvegarde (`saveNow`) puis renvoie `PurchaseGranted`. Un reçu déjà enregistré repasse lui aussi par une sauvegarde confirmée avant `PurchaseGranted` : enregistré dans le profil vivant n'est pas écrit, et c'est justement une sauvegarde ratée qui fait redemander Roblox. Toute erreur ou profil absent → `NotProcessedYet` (Roblox réessaiera). Jamais de yield non protégé.
- Un reçu ne se refuse jamais pour de bon : les Robux sont déjà pris, et `NotProcessedYet` ferait relivrer le reçu sans fin. Ce qu'il ne peut plus livrer se paie en Folios (D-202) : un cosmétique d'une rareté entièrement possédée à son prix en Folios, un palier au-delà du dernier et un Pass Premium déjà possédé à leur `CompensationFolios`.
- Game passes : `UserOwnsGamePassAsync` à la connexion (pcall + retries) pour chaque pass qui a un identifiant, cache dans `Passes` qui suit les réponses nettes de Roblox dans les deux sens (un pass remboursé ou retiré de l'inventaire en sort ; une vérification qui échoue ne change rien), mise à jour sur `PromptGamePassPurchaseFinished` (une vente entre dans le cache, une fenêtre fermée sans vente fait redemander le pass). Achats hors connexion couverts par la vérification à la connexion (D-211).
- Un achat en Folios débite puis accorde ; si l'attribution échoue sans que l'article soit écrit, `CurrencyService.refund` rend exactement le débit, sans le ×1,5 du VIP et sans rien écrire pour le compte développeur qui n'a rien payé ; un article écrit est un achat réglé, jamais remboursé (D-203).
- Studio : un achat de test n'accorde rien et ne s'enregistre pas tant que `StudioConfig.PersistTestPurchases` est éteint (D-211).
- Panne de DataStore : tant que ProfileStore est dans son état critique (`DataService.isCritical`), aucune fenêtre d'achat en Robux ne s'ouvre (`purchase.savesDelayed`) et chaque joueur est prévenu une fois, au début puis à la fin (`save.delayed`, `save.restored`) ; l'achat en Folios reste ouvert (D-254).
- Aucune valeur de prix n'est lue depuis le client ; les IDs vivent uniquement dans `MonetizationConfig`, validés au démarrage (`warn` explicite par ID manquant).

## 8. KPIs à suivre (Analytics + Creator Dashboard)

| KPI | Cible V2 | Levier |
|---|---|---|
| D1 / D7 rétention | 40 % / 15 % | quêtes, streak, première victoire du jour |
| Durée de session | 18 min | matchs courts, file rapide |
| Matchs par session | 5 | matchmaking intra-serveur |
| Taux de conversion | 2-4 % | surfaces d'achat placées là où l'envie naît (§5), pass premium |
| ARPDAU | 0,02-0,05 $ | packs de Folios, VIP |
| Funnel onboarding | 90 % première touche → 70 % premier glyphe → 45 % premier match | tutoriel HUD, mannequins |

**Ce que reçoit le tableau Économie.** Chaque Folio gagné ou dépensé part une fois, de `CurrencyService`, avec la raison qu'on lui a donnée : `AnalyticsConfig.economyOf` en tire le type de transaction de Roblox et l'article. Les récompenses de jeu (matchs, KO, épreuves, Faussaires, Effacement, quêtes, pass, saison) sont `Gameplay`, la série quotidienne, la première victoire du jour et le bonus Premium `TimedReward`, les packs de Folios et ce qu'un reçu paie à la place de ce qu'il ne peut plus livrer `IAP` (article : le produit), un achat de la boutique `Shop` (article : l'objet, et le remboursement d'une attribution ratée repart en source sous le même article). Les jalons de niveau et les plaques de l'Ex-libris sont `Gameplay`, les grades des Exercices du Pupitre `Onboarding`, chacun sous sa raison entière comme article (`Milestone45`, `ExLibrisBreath4`, `DrillKitStringDraft` : `AnalyticsConfig.FamilyTransactions`, D-258). Un achat du compte développeur ne déplace aucun Folio et n'envoie rien (D-129). `tests/EconomyEvents.spec.luau` liste chaque appel qui déplace des Folios et refuse celui qui n'y est pas.

**Les événements personnalisés.** Onze noms, tous dans `AnalyticsConfig.Events` (Roblox en garde 100), chacun avec ses champs `CustomField01` à `03` en texte ; `AnalyticsService` refuse tout autre nom ou toute autre clé.

| Événement | Champs (01, 02, 03) | Valeur | Pour lire |
|---|---|---|---|
| `PromptAccepted`, `PromptDeclined` | `Pass` ou `Product`, la clé | 1 | la conversion de chaque fenêtre d'achat |
| `ProductPurchased`, `PassPurchased` | la clé | le prix en Robux | les revenus par offre |
| `MatchFormed` | le mode | les secondes d'attente | l'attente avant un match |
| `QueueTimedOut` | le mode | les secondes d'attente | les attentes abandonnées |
| `MatchEnded` | le mode, `Win` / `Loss` / `Draw` | les secondes du match | les matchs par session, leur durée |
| `MatchVoided` | le mode, `Empty` / `Closing` / `Error` / `Cancelled` / `Unplayed` | les secondes jouées | les matchs perdus pour tout le monde, dont les forfaits d'un match qui n'a pas été joué (D-255) |
| `BossEnded` | `Event` / `Practice`, `Defeated` / `Expired` | les secondes du combat | combien de fois l'Effacement tombe |
| `GlyphPick` | le glyphe, le mode | 1 | le taux de choix |
| `GlyphMatch` | le glyphe, le mode, `Win` / `Loss` (un nul n'est pas une victoire) | les dégâts du glyphe dans le match | le taux de victoire et les dégâts |

**Où lire l'équilibre des 28 glyphes (E8-S7, pour le tableau de bord de E8-S6).** Creator Dashboard, l'expérience, **Analytics → Custom Events**, page **Explore** (le chemin exact des menus est à confirmer à la première capture sur Vellum-Test) :

- **Taux de choix** : événement `GlyphPick`, agrégation *Count*, ventilé par `CustomField01` (le glyphe), filtré sur `CustomField02` (le mode) : la part de chaque glyphe dans les entrées en file du mode, une par attente : quitter et rejoindre la file avec le même équipement ne recompte rien avant un match ou une file expirée (D-264).
- **Taux de victoire** : événement `GlyphMatch`, agrégation *Count*, ventilé par `CustomField01` puis `CustomField03` : `Win` / (`Win` + `Loss`) pour chaque glyphe, filtré sur le mode.
- **Dégâts** : événement `GlyphMatch`, agrégation *Average value*, ventilé par `CustomField01` : les dégâts moyens d'un glyphe dans un match où il a été lancé (*Sum value* pour le total).

Au plus 28 × 2 × 2 = 112 combinaisons de champs pour `GlyphMatch` et 56 pour `GlyphPick`, loin des 8 000 au-delà desquels Roblox regroupe le reste en « Other » (`tests/GlyphTelemetry.spec.luau`). Les événements ne partent que d'un serveur publié et mettent jusqu'à 24 h à paraître.

## 9. Raisonner en dollars (DevEx)

- Roblox retient 30 % sur les game passes / developer products : le développeur reçoit 70 % des Robux.
- DevEx : 0,0038 $ par Robux (taux 2024-2025 ; vérifier sur le portail).
- Exemples : VIP 399 R$ → 279 R$ nets → **1,06 $** ; pass premium 349 R$ → 244 R$ → **0,93 $** ; pack Folios 599 R$ → 419 R$ → **1,59 $**.
- Objectif : 1 000 joueurs actifs / jour × ARPDAU 0,03 $ ≈ **900 $ / mois** ; chaque point de conversion supplémentaire à 2 $ de panier moyen ≈ +600 $ / mois.
