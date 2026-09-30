# Économie — Vellum V2

Toutes les valeurs sont des points de départ à ajuster avec les données réelles (voir KPIs). Les identifiants Roblox (game passes, developer products) sont à renseigner dans `src/shared/Config/MonetizationConfig.luau` (voir `docs/STUDIO_SETUP.md`).

## 1. Monnaies

| Monnaie | Nature | Obtention | Usage |
|---|---|---|---|
| **Folios** | douce (gagnée) | matchs, kills, quêtes, boss, streak, pass, achat de packs | boutique cosmétique, rotation quotidienne |
| **Robux** | dure | achat réel | game passes, developer products, prompts contextuels |

Aucun pigment de puissance n'est vendu contre Robux : Orpiment est un sidegrade débloquable au niveau 40 (`docs/GAME_DESIGN.md` §5), les slots de loadout apportent de la variété, tout le reste est cosmétique ou du confort (boost d'XP, saut de paliers).

## 2. Sources de Folios (par heure de jeu typique : ~6 matchs, 2 quêtes, 1 boss)

| Source | Folios | Fréquence / h | Total / h |
|---|---|---|---|
| Victoire 1v1 / 3v3 | 60 | ×3 | 180 |
| Défaite | 20 | ×3 | 60 |
| Kill joueur | 15 | ×8 | 120 |
| Épreuve du hub (mannequin, E10-S3) | 2 | ×20, plafond **40 / jour** (profil) | 40 |
| Quête journalière | 50 | ×2 | 100 |
| Quête hebdomadaire (amortie) | 200 | ×0,4 | 80 |
| World Boss (participation + bonus) | 80 + 150 | ×0,8 | 180 |
| Faussaires du champ de bataille (D-131) | 1–4 (Barbouilleur, Plume 1 ; Surchargeur 4) | plafond **150 / jour** (profil) | hors du total ci-dessous |
| Entraînement contre l'Effacement (D-132) | ≤ 58 (×0,25 d'une participation) | 3 / jour (profil), 1 / 20 min ; une paie sous 1 Folio n'en décompte aucun (D-134) | ≤ 174 / jour, hors du total |
| Première victoire du jour | 100 | ×1 | 100 |
| Streak de connexion (J7 moyen) | 120 | ×1 | 120 |
| **Total** | | | **≈ 980 Folios / h** (≈ 700 pour un joueur moyen) |

VIP : Folios ×1,5 (≈ 1 400 / h). Premium (abonnés Roblox Premium) : +150 Folios / jour via le bonus dédié.

Les deux sources ajoutées par les portails sont bornées **par jour, dans le profil** (`DailyCap`, compteurs `Daily.ForgerDay` / `ForgerFolios` et `PracticeDay` / `PracticePaid`) : changer de serveur ne les remet pas à zéro. Le plafond des Faussaires porte sur le montant de base, avant le VIP ; au-delà, un Faussaire ne paie plus que de l'XP, et un toast le dit une fois par jour.

Les Épreuves du hub le sont aussi depuis E10-S3 (`TrialPay`, compteurs `Daily.TrialDay` / `TrialKills` / `TrialFolios`) : 40 Folios par jour au plus, l'XP entière (40) pour les 25 premiers kills du jour puis 5 % (2 XP), rien sans glyphe lancé ni ruée dans la minute, et jamais d'XP de pass ; un glyphe qui touche une Épreuve ne paie pas d'XP (D-XXX). Un toast le dit une fois par jour, au kill qui épuise les Folios.

**XP à l'heure : voir §2 bis**, mesurée par le simulateur sur les vraies configs et non plus estimée à la main. L'XP des Faussaires reste sans plafond : 9 716 XP/h pour un joueur seul, au-dessus d'une heure de duels (8 237). Ce n'est pas l'objet de E10-S3, mais c'est désormais l'activité sûre la mieux payée ; à revoir avec le développeur.

## 2 bis. Le rythme, mesuré par le simulateur

`lune run scripts/pacing -- --table` joue quatre profils pendant 60 jours avec les vraies configs et les règles que le serveur exécute (`TrialPay`, `DailyCap`, `QuestLogic` avec plancher Solo et relance gratuite, rotation réelle de la boutique) ; `tests/Pacing.spec.luau` le lance à chaque porte de qualité. L'export jour par jour est `docs/economy/pacing.csv`, repris en formules dans `docs/economy/Vellum-economie.xlsx` (`python3 tools/economy/workbook.py`). Sortie du 30/09/2026 :

| Profil | Niv. 5 | Niv. 10 | Niv. 20 | Niv. 40 | Pass fini | Folios gagnés J7 | Folios gagnés J30 | Catalogue complet |
|---|---|---|---|---|---|---|---|---|
| 20 min/j seul (5 min d'Épreuves, 15 min de Faussaires) | 1 min | 9 min | 43 min | 253 min | J41 | 4 460 | 21 825 | après J60 |
| 20 min/j en PvP (duels) | 3 min | 11 min | 52 min | 277 min | J34 | 7 170 | 34 825 | J41 |
| 60 min/j en PvP (duels) | 3 min | 11 min | 65 min | 364 min | J15 | 15 205 | 60 375 | J32 |
| Fermier d'Épreuves (60 min/j) | 1 min | 19 min | 237 min | 1 144 min | jamais | 2 830 | 12 875 | après J60 |

XP par heure de chaque activité seule (sans quêtes, série ni première victoire) : duels 8 237, Faussaires 9 716, Épreuves du fermier 1 858 (22,6 % des duels ; le gate exige moins de 30 %). Le pass coûte 152 880 XP (D-XXX) ; 24 objets s'obtiennent sans Robux (les 14 de la boutique et les 10 de la piste gratuite). « Catalogue complet » : le jour où le profil possède ces 24 objets en achetant, chaque jour, le moins cher de la rotation qu'il peut payer.

Ce que les configs ne disent pas est dans `Pacing.Assumptions`, une fois chacun, à remplacer par des mesures (E8) : file de 45 s et 10 s de portail par duel, manche de 50 s, matchs par quatre (deux gagnés, deux perdus, un net et un serré de chaque), un glyphe sur deux qui touche en duel (7 sur 10 sur un Faussaire, tous sur une Épreuve), un tiers du combat au corps à corps en duel, 6 ruées et 1 annulation par minute, un glyphe sur cinq enchaîné, un Faussaire qui encaisse 60 % des dégâts et demande 3 s d'approche. Les lancers de glyphes suivent l'encre en combat (`CombatConfig.Ink.RegenInCombat` sur le coût moyen de l'équipement de départ), les coups de poing la cadence du combo (`CombatConfig.Melee`).

Deux constats pour le développeur, hors de ces stories : le niveau 40 (Orpiment) arrive en 4 à 6 h de jeu et non en 15-20 h, et une heure de Faussaires paie plus d'XP qu'une heure de duels.

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
| Pass premium (saison) | 349 | piste premium de la saison courante | `PremiumPass` |
| +5 paliers de pass | 149 | avance de 5 paliers | `TierSkip5` |
| Boost d'XP 1 h | 79 | XP ×2 pendant 60 min | `XpBoost1h` |

Conversion implicite : 1 R$ ≈ 10-13 Folios. Un légendaire (8 000 Folios) vaut ≈ 600 R$ ou ≈ 11 h de jeu : le joueur gratuit peut tout obtenir, le joueur payant gagne du temps.

## 5. Placement des prompts (non agressif)

| Moment | Prompt | Garde-fou |
|---|---|---|
| Défaite de peu (< 15 % de vie d'écart) | Boost d'XP | max 1 / 30 min |
| Palier de pass bloqué (piste premium) | Pass premium | seulement depuis l'écran du pass |
| Mort face à un joueur Orpiment | Pass Orpiment | max 1 / session, jamais avant le niveau 10 |
| Loadout plein | Slots | seulement depuis l'écran de loadout |
| Boutique | article en Folios insuffisant | la fiche de confirmation le dit (solde après achat en rouge), grise « Acheter » et propose « Obtenir des Folios », qui ouvre l'onglet Folios ; le prix « R$ » de l'article reste sur sa carte |

Règles globales : **aucun prompt dans les 3 premières minutes de la première session** (`Meta.FirstSessionPromptGate`), jamais plus d'un prompt toutes les 5 minutes, jamais pendant un match. Chaque prompt affiché / accepté / refusé est journalisé (`Analytics`).

### Surfaces d'achat à l'initiative du joueur (D-147)

La passe UI couleur ajoute des endroits où le joueur **choisit** d'acheter ; aucun n'ouvre quoi que ce soit de lui-même. Chacun n'ouvre la fenêtre d'achat de Roblox que sur un geste du joueur, et seulement pour une entrée qui a un id sur Roblox (`MonetizationConfig`, id non nul ; sinon le bouton est grisé). Le serveur reste l'autorité : il résout l'id, refuse ce qui est déjà possédé, un saut de paliers au dernier palier, un article sorti de la rotation, et le dit par un toast. Les garde-fous du tableau ci-dessus (première session, 5 minutes, jamais en match) continuent de régir les prompts contextuels, qui restent des toasts ; **aucun prompt automatique n'a été ajouté**.

| Écran | Surface | Ce qu'elle déclenche | Garde-fou côté interface |
|---|---|---|---|
| Boutique, onglet « Du jour » | le prix en Folios de chaque article | la fiche de confirmation (l'article, le solde avant → après), puis `BuyCosmetic` sur « Acheter » ; jamais en un seul geste | « Acheter » grisé si le solde ne suffit pas ; l'achat attend la réponse du serveur (5 s au plus) |
| Boutique, onglet « Du jour » | le prix « R$ » de chaque article | `PromptPurchase("Cosmetic", id)` | le produit de sa rareté doit exister sur Roblox |
| Boutique, onglet « Folios » | les trois packs (1 000, 3 500, 8 000) | `PromptPurchase("Product", FolioSmall / FolioMedium / FolioLarge)` | id non nul |
| Boutique, onglet « Pass et packs » | VIP, Slots d'équipement, Pigment Orpiment, Pack de skins ; Battle Pass Premium, +5 paliers, Boost d'XP | `PromptPurchase("Pass", clé)` ou `PromptPurchase("Product", clé)` | id non nul ; un pass possédé (et le premium de la saison) montre « Possédé » au lieu d'un prix ; +5 paliers grisé au dernier palier |
| Battle Pass | « Obtenir le Premium », « +5 paliers » | `PromptPurchase("Product", PremiumPass / TierSkip5)` | « Obtenir le Premium » caché une fois le premium possédé ; +5 paliers grisé au dernier palier ; une récompense premium verrouillée montre le mot « Premium » et un cadenas, sans phrase de refus |
| Équipement (tranche B) | « +4 emplacements », tant que `LoadoutSlots` n'est pas possédé | `PromptPurchase("Pass", LoadoutSlots)` | id non nul ; pas de prix affiché (l'invite de Roblox le montre) ; l'offre contextuelle reste réservée à l'écran d'équipement (la ligne « Loadout plein » ci-dessus) |
| Menu | le « + » à côté des Folios | ouvre la Boutique sur l'onglet Folios ; n'achète rien | — |

Le Casier (onglet de la Boutique) ne vend rien : il montre ce que le joueur possède, pour l'équiper ou le retirer.

## 6. Premium Payouts

Les abonnés Roblox Premium génèrent des payouts proportionnels au temps passé. Leviers : bonus quotidien Premium (150 Folios + 30 min de boost d'XP), file prioritaire visuelle (badge), quêtes hebdomadaires bonus. Aucune exclusivité de gameplay.

## 7. Idempotence et sécurité des achats

- `ProcessReceipt` : lit le profil (`DataService.waitFor`), vérifie `Purchases.Receipts` (anneau de 100 ids), applique le produit, enregistre `PurchaseId`, force une sauvegarde (`saveNow`) puis renvoie `PurchaseGranted`. Toute erreur ou profil absent → `NotProcessedYet` (Roblox réessaiera). Jamais de yield non protégé.
- Game passes : `UserOwnsGamePassAsync` à la connexion (pcall + retries), cache dans `Passes`, mise à jour sur `PromptGamePassPurchaseFinished`. Achats hors connexion couverts par la vérification à la connexion.
- Aucune valeur de prix n'est lue depuis le client ; les IDs vivent uniquement dans `MonetizationConfig`, validés au démarrage (`warn` explicite par ID manquant).

## 8. KPIs à suivre (Analytics + Creator Dashboard)

| KPI | Cible V2 | Levier |
|---|---|---|
| D1 / D7 rétention | 40 % / 15 % | quêtes, streak, première victoire du jour |
| Durée de session | 18 min | matchs courts, file rapide |
| Matchs par session | 5 | matchmaking intra-serveur |
| Taux de conversion | 2-4 % | prompts contextuels, pass premium |
| ARPDAU | 0,02-0,05 $ | packs de Folios, VIP |
| Funnel onboarding | 90 % première touche → 70 % premier glyphe → 45 % premier match | tutoriel HUD, mannequins |

## 9. Raisonner en dollars (DevEx)

- Roblox retient 30 % sur les game passes / developer products : le développeur reçoit 70 % des Robux.
- DevEx : 0,0038 $ par Robux (taux 2024-2025 ; vérifier sur le portail).
- Exemples : VIP 399 R$ → 279 R$ nets → **1,06 $** ; pass premium 349 R$ → 244 R$ → **0,93 $** ; pack Folios 599 R$ → 419 R$ → **1,59 $**.
- Objectif : 1 000 joueurs actifs / jour × ARPDAU 0,03 $ ≈ **900 $ / mois** ; chaque point de conversion supplémentaire à 2 $ de panier moyen ≈ +600 $ / mois.
