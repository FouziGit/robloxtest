# Économie — Vellum V2

Toutes les valeurs sont des points de départ à ajuster avec les données réelles (voir KPIs). Les identifiants Roblox (game passes, developer products) sont à renseigner dans `src/shared/Config/MonetizationConfig.luau` (voir `docs/STUDIO_SETUP.md`).

## 1. Monnaies

| Monnaie | Nature | Obtention | Usage |
|---|---|---|---|
| **Folios** | douce (gagnée) | matchs, kills, quêtes, boss, streak, pass, achat de packs | boutique cosmétique, rotation quotidienne |
| **Robux** | dure | achat réel | game passes, developer products, depuis les surfaces d'achat (§5) |

Aucun pigment de puissance n'est vendu contre Robux : Orpiment est un sidegrade débloquable au niveau 40 (`docs/GAME_DESIGN.md` §5), les slots de loadout apportent de la variété, tout le reste est cosmétique ou du confort (boost d'XP, saut de paliers).

## 2. Sources de Folios (par heure de jeu typique : ~6 matchs, 2 quêtes, 1 boss)

| Source | Folios | Fréquence / h | Total / h |
|---|---|---|---|
| Victoire 1v1 / 3v3 | 60 | ×3 | 180 |
| Défaite | 20 | ×3 | 60 |
| Kill joueur | 15 | ×8 | 120 |
| Mannequin | 2 | ×20 | 40 |
| Quête journalière | 50 | ×2 | 100 |
| Quête hebdomadaire (amortie) | 200 | ×0,4 | 80 |
| World Boss (participation + bonus) | 80 + 150 | ×0,8 | 180 |
| Faussaires du champ de bataille (D-131) | 1–4 (Barbouilleur, Plume 1 ; Surchargeur 4) | plafond **150 / jour** (profil) | hors du total ci-dessous |
| Entraînement contre l'Effacement (D-132) | ≤ 58 (×0,25 d'une participation) | 3 / jour (profil), 1 / 20 min ; une paie sous 1 Folio n'en décompte aucun (D-134) | ≤ 174 / jour, hors du total |
| Première victoire du jour | 100 | ×1 | 100 |
| Streak de connexion (J7 moyen) | 120 | ×1 | 120 |
| **Total** | | | **≈ 980 Folios / h** (≈ 700 pour un joueur moyen) |

VIP : Folios ×1,5 (≈ 1 400 / h). Premium (abonnés Roblox Premium) : +150 Folios et 30 min d'XP doublée par jour, via le bonus dédié (§6).

Les deux sources ajoutées par les portails sont bornées **par jour, dans le profil** (`DailyCap`, compteurs `Daily.ForgerDay` / `ForgerFolios` et `PracticeDay` / `PracticePaid`) : changer de serveur ne les remet pas à zéro. Le plafond des Faussaires porte sur le montant de base, avant le VIP ; au-delà, un Faussaire ne paie plus que de l'XP, et un toast le dit une fois par jour.

**XP à l'heure, estimation de conception (non mesurée).** L'XP des Faussaires n'est pas plafonnée (30 / 35 / 100 par figure). Limitée par l'offre, 300 à 450 Faussaires à l'heure donneraient **10 000 à 15 000 XP/h**, au-dessus des 7 200 à 9 000 XP/h que suppose la courbe de niveaux (`ProgressionConfig` : 2 à 2,5 XP/s en match) ; les mannequins du hub en donnent déjà environ 19 000, écart plus grand encore, qui demande sa propre revue. À mesurer en jeu avant d'ajuster.

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
- Panne de DataStore : tant que ProfileStore est dans son état critique (`DataService.isCritical`), aucune fenêtre d'achat en Robux ne s'ouvre (`purchase.savesDelayed`) et chaque joueur est prévenu une fois, au début puis à la fin (`save.delayed`, `save.restored`) ; l'achat en Folios reste ouvert (D-XXXsave).
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

## 9. Raisonner en dollars (DevEx)

- Roblox retient 30 % sur les game passes / developer products : le développeur reçoit 70 % des Robux.
- DevEx : 0,0038 $ par Robux (taux 2024-2025 ; vérifier sur le portail).
- Exemples : VIP 399 R$ → 279 R$ nets → **1,06 $** ; pass premium 349 R$ → 244 R$ → **0,93 $** ; pack Folios 599 R$ → 419 R$ → **1,59 $**.
- Objectif : 1 000 joueurs actifs / jour × ARPDAU 0,03 $ ≈ **900 $ / mois** ; chaque point de conversion supplémentaire à 2 $ de panier moyen ≈ +600 $ / mois.
