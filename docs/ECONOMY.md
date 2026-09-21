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
| Mannequin | 2 | ×20 | 40 |
| Quête journalière | 50 | ×2 | 100 |
| Quête hebdomadaire (amortie) | 200 | ×0,4 | 80 |
| World Boss (participation + bonus) | 80 + 150 | ×0,8 | 180 |
| Première victoire du jour | 100 | ×1 | 100 |
| Streak de connexion (J7 moyen) | 120 | ×1 | 120 |
| **Total** | | | **≈ 980 Folios / h** (≈ 700 pour un joueur moyen) |

VIP : Folios ×1,5 (≈ 1 400 / h). Premium (abonnés Roblox Premium) : +150 Folios / jour via le bonus dédié.

## 3. Puits de Folios (boutique cosmétique)

| Rareté | Prix Folios | Heures de jeu ≈ | Exemples |
|---|---|---|---|
| Commun | 600 | 1 h | traînée simple, titre |
| Rare | 1 800 | 2,5 h | aura colorée, skin de glyphe 1 palette |
| Épique | 4 000 | 6 h | effet de kill, aura animée |
| Légendaire | 8 000 | 11 h | skin de glyphe complet (palette + forme), aura Codex |

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
| Boutique | article en Folios insuffisant | bouton « Acheter avec Robux » explicite |

Règles globales : **aucun prompt dans les 3 premières minutes de la première session** (`Meta.FirstSessionPromptGate`), jamais plus d'un prompt toutes les 5 minutes, jamais pendant un match. Chaque prompt affiché / accepté / refusé est journalisé (`Analytics`).

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
