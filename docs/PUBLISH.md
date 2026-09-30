# Avant de publier

Ce document liste ce qui doit être vrai avant qu'une version passe en `Published`. Le suivre dans l'ordre : une case non cochée arrête la publication. La passe de jeu se trouve dans `docs/QA.md`, et la configuration faite une seule fois (passes, produits, secrets) dans `docs/STUDIO_SETUP.md`.

Les numéros de ligne renvoient au commit `c0b6687`. `R1` à `R15` renvoient au §12 de `docs/QA.md`.

## 1. Le commit publié

1. **Jamais une branche non relue.** On publie `main`, et rien d'autre. Une branche de travail passe par une PR relue, puis fusionnée. Au commit `c0b6687`, `feat/vfx-pass` a 12 commits d'avance sur `main` : la fusionner d'abord.
2. **CI verte sur ce commit.** Sur `main`, `.github/workflows/ci.yml` passe toutes les portes : format, lint, analyse, tests, chaînes, `localization.csv`, textures, sons, animations et build.
3. **Les portes en local, sur le même commit.** Vérifier que `git status` est propre, puis lancer `./scripts/check.sh`. Attendu : `✔ all quality gates green`. Noter le hash du commit : c'est lui qui sera publié et étiqueté (§2.4).
4. **Ce que la publication ne vérifie pas.** `publish.yml` ne lance que `lune run tests/run` et `rojo build` (`publish.yml:37-43`) : ni stylua, ni selene, ni luau-lsp, ni le contrôle des chaînes, ni celui des assets. **File → Publish to Roblox** dans Studio n'en lance aucune. En pratique :
   - avec `publish.yml`, choisir dans **Run workflow** `main` ou l'étiquette du commit dont la CI est verte ;
   - à la main, ne publier que le `build/Vellum.rbxl` construit depuis ce commit, jamais une place retouchée à la main ni une session `rojo serve`.
5. **Passe QA faite.** Les §1 à §11 de `docs/QA.md` ont été déroulés sur la copie de test, et le rapport est gardé. Chaque KO est soit corrigé, soit rattaché à un écart `R` dont la décision est prise dans ce document.

## 2. Version et journal

1. **Numéro de version.** Monter `GameConfig.Version` (`GameConfig.luau:6`). Il apparaît dans `[Bootstrap] Vellum v<version> ready: 29 services started` et permet de savoir quelle version tourne sur un serveur en ligne.
2. **Journal interne.** Ajouter une entrée dans `docs/PROGRESS.md` (fait / en cours / reste), et les nouvelles décisions dans `docs/DECISIONS.md`.
3. **Notes pour les joueurs.** Écrire quelques lignes en anglais et en français sur ce qui change, pour la description ou l'annonce de mise à jour. Ne rien promettre que le code ne livre pas (§3.4).
4. **Étiquette.** `git tag v<version> <hash>` puis `git push origin v<version>`. Le dépôt n'a encore aucune étiquette ; c'est pourtant elle qui rend le retour arrière immédiat (§9).
5. **Saison.** Ne toucher à `GameConfig.SeasonId` et `PreviousSeasonId` (`GameConfig.luau:9-13`) que pour ouvrir une nouvelle saison. Au chargement de chaque profil, le changement ouvre un battle pass neuf et vide le classement du joueur (`ensureSeason`, `DataService.luau:195-203`). Le jeu passe aussi sur de nouveaux classements nommés `<SeasonId>_<Board>` (`LeaderboardService.luau:2-4`). Pour un profil déjà chargé, c'est irréversible.
6. **Schéma du profil.** Toute version qui ajoute, renomme ou retire un champ du profil monte `DataMigration.CurrentVersion` (`DataMigration.luau:25`), même sans étape de migration. Ce numéro est le seul moyen, pour un serveur resté sur la version précédente, de reconnaître un profil écrit par une version plus récente : il en garde alors les champs qu'il ne connaît pas, et le numéro (`newer`, dans `DataMigration.migrate`). Sans ce numéro, il efface ces champs. L'écrire dans les notes et relire le §9.3 : cette version ne pourra pas être retirée proprement. La version des portails ajoute quatre champs sans monter ce numéro, parce que la version d'avant ne saurait de toute façon pas les garder : c'est pourquoi elle se publie comme le dit le §8.5.
7. **Quêtes.** Une quête ajoutée à `QuestConfig.Pool` porte `Since`, la révision suivante, et `QuestConfig.PoolRevision` passe à cette valeur dans le même commit. Elle n'entre dans le tirage qu'au jour ou à la semaine qui suit la mise en ligne : les quêtes en cours ne changent jamais sous un joueur qui les a déjà réclamées (`QuestLogic.setKey`, `QuestLogic.select`). Ne jamais retirer ni déplacer une entrée : cela changerait le tirage de toutes les révisions, et `tests/QuestLogic.spec.luau` le refuse. Une telle version se publie elle aussi en migrant tous les serveurs aussitôt (§8.5) : un serveur resté sur l'ancienne version ne connaît pas la nouvelle quête et tirerait d'autres quêtes le même jour.
8. **Nom du magasin de données.** Ne jamais renommer `STORE_NAME = "JutsuBattlegrounds_v2"` (`DataService.luau:49`). Un autre nom donnerait un profil vide à tout le monde.

## 3. Identifiants et prix (`MonetizationConfig`)

1. **Les 14 identifiants.** Dans `src/shared/Config/MonetizationConfig.luau:21-121`, chaque `Id` doit être différent de zéro. Attendu au démarrage : `[MonetizationService] started (4 passes, 10 products, 0 missing ids)` (`docs/QA.md` §1.3). Au commit `c0b6687`, les 14 valent `0`.
2. **Chaque identifiant à sa place.** Aucun test ne vérifie qu'un identifiant est unique, ni qu'un identifiant de pass n'a pas été collé dans un produit : `tests/Config.spec.luau:555-588` ne contrôle que les identifiants manquants et les textes. En cas de doublon, `productByAssetId` (`MonetizationConfig.luau:150-160`) rend le premier trouvé, dans un ordre non garanti. Comparer chaque ligne au Creator Dashboard :

| Clé | Type | Prix dans le code (R$) | Ce que le code livre |
|---|---|---|---|
| `Vip` | pass | 399 | aura VIP, XP ×2, Folios ×1,5 |
| `LoadoutSlots` | pass | 199 | 10 emplacements au lieu de 6 |
| `Orpiment` | pass | 299 | le pigment Orpiment sans attendre le niveau 40 |
| `SkinPack` | pass | 249 | 4 skins de glyphe |
| `FolioSmall` / `FolioMedium` / `FolioLarge` | produit | 99 / 299 / 599 | 1000 / 3500 / 8000 Folios |
| `PremiumPass` | produit | 349 | la piste premium de la saison |
| `TierSkip5` | produit | 149 | 5 paliers, moins à partir du palier 46 (R14) |
| `XpBoost1h` | produit | 79 | 60 min de boost d'XP |
| `CosmeticCommon` / `Rare` / `Epic` / `Legendary` | produit | 49 / 149 / 349 / 699 | un cosmétique de la rareté |

3. **Les mêmes prix que le tableau de bord.** Le joueur paie le prix réglé dans le Creator Dashboard. `PriceRobux` ne sert qu'à l'analytique (`Receipts.luau:181`, `Passes.luau:157`) : un écart ne coûte rien au joueur, mais fausse les revenus suivis par `docs/ECONOMY.md` §8.
4. **Des descriptions honnêtes.** Chaque description saisie sur le tableau de bord (`docs/STUDIO_SETUP.md` §3 et §4) doit dire exactement ce que le code livre :
   - **VIP** : soit construire le tag dans le chat, soit retirer « tag dans le chat » aux quatre endroits où il apparaît : le tableau de bord, `Strings.luau:359-362`, `docs/STUDIO_SETUP.md:54` et `docs/ECONOMY.md:48` (R1). À régler avant la mise en vente.
   - **TierSkip5** : soit écrire « jusqu'à cinq paliers », soit refuser l'achat à partir du palier 46 (R14).
   - **Premium** : aligner `docs/ECONOMY.md` §6 sur ce que le code donne (R10).
5. **Acheter une fois chaque article.** Sur la copie de test, avec un compte secondaire, dérouler tout le §3 de `docs/QA.md`. Tant que R2 n'est pas corrigé, retirer `TierSkip5` de la vente : un reçu payé qui boucle, c'est un joueur débité sans rien recevoir.
6. **Prompts contextuels.** `docs/ECONOMY.md` §5 décrit des prompts qui ne s'affichent jamais (R8). Soit les brancher, soit écrire dans le document qu'ils n'existent pas encore.

## 4. Données, accès API, comptes

1. **Accès API.** *Enable Studio Access to API Services* (`docs/STUDIO_SETUP.md` §2) branche Studio sur les **vraies** données : chaque test multi-clients inscrit des identifiants négatifs dans les classements (R5), et chaque achat de test écrit dans le vrai profil (R9). Décision : faire la QA sur une copie de test et, sur l'expérience publique, n'activer l'accès que le temps d'un test précis.
2. **Classements propres.** Avant l'ouverture au public, choisir une option :
   - purger les entrées de test (toute clé négative) des stores `S1_Global`, `S1_Duel1v1` et `S1_Team3v3` ;
   - ouvrir la saison publique sous un autre `SeasonId` (§2.5) ;
   - n'écrire que les `UserId > 0` dans `writeDue` (`LeaderboardService.luau:240-244`).
3. **Profil du développeur.** Les passes obtenus par des achats de test restent en cache (`Passes.luau:2-4`), et les cosmétiques achetés avec les Folios illimités restent possédés (R6). Décider si ce profil part tel quel.
4. **Réglages développeur.** Dans `src/server/Config/DeveloperConfig.luau`, trancher `UnlimitedSlots` (`:17`), `UnlimitedFolios` (`:22`) et `FreeCasting` (`:26`) avant l'ouverture au public. Aujourd'hui, le compte développeur joue le classé avec 20 emplacements et tout le roster contre des joueurs qui en ont 6 (R6). Noter la décision dans `docs/DECISIONS.md`.
5. **World Boss.** `WorldBossConfig.Schedule` doit être à 1200 / 60 / 300 / 15 / 2 (`WorldBossConfig.luau:23-29`). Le raccourci de test fait échouer `tests/Config.spec.luau:615-617`.
6. **Seuils de qualité.** Les seuils de 40 et 55 images/s de `QualityConfig.Auto` (`QualityConfig.luau:110-116`) n'ont été mesurés sur aucun appareil (`docs/PERFORMANCE.md:183-187`). Soit publier en le sachant, soit faire d'abord le §9.5 de `docs/QA.md`.
7. **Arrêts et migrations de serveurs.** Tant que R3 n'est pas corrigé, un arrêt en plein classé peut débiter les deux joueurs. Décider si l'on corrige avant la publication ou si l'on migre les serveurs aux heures creuses (§8.4).

## 5. Assets et modération

1. **Tout approuvé.** Lancer `python3 scripts/upload_assets.py status` (`scripts/upload_assets.py:365-379`). La commande relit la modération de chaque asset, n'affiche que ceux qui ne sont pas `Approved` et termine par un décompte. Attendu : une seule catégorie, `Approved`. La commande réécrit l'état dans `assets/roblox-assets.lock.json` : commiter ce changement. Au commit `c0b6687`, `ink_flame.png` et `ink_spike.png` étaient encore `Reviewing` à l'envoi (R7). Cette commande n'est pas encore décrite au §7 de `docs/STUDIO_SETUP.md`.
2. **Même propriétaire.** Les assets appartiennent au compte `3721321390` (`assets/roblox-assets.lock.json:2-3`). L'expérience publiée doit appartenir au même compte, sinon les animations et les sons ne se jouent pas. Si l'expérience passe à un groupe, il faut renvoyer les assets au nom du groupe.
3. **Identifiants cohérents.** Vérifier que `tests/UploadedAssets.spec.luau` et `tests/MeshConfig.spec.luau` sont verts (ils font partie de `check.sh`) et que les volumes sont résolus (`docs/STUDIO_SETUP.md` §7 bis).
4. **Rien ne manque côté client.** Voir `docs/QA.md` §1.4 : aucune liste de sons manquants.

## 6. Fiche de l'expérience (Creator Dashboard)

Une partie a déjà été faite une fois (`docs/STUDIO_SETUP.md` §2) : accès API, 12 joueurs, appareils, chat, genre. La relire à chaque version et la compléter :

1. **Questionnaire de maturité.** Le remplir d'après ce que le jeu montre : combat fantastique, violence légère, aucun texte saisi par les joueurs en dehors du chat Roblox. Roblox s'en sert pour l'étiquette de maturité et pour l'audience de l'expérience.
2. **Appareils autorisés.** Ordinateur, téléphone, tablette et console. Chaque case cochée doit avoir passé `docs/QA.md` §8 ; sur console, on ne joue qu'à la manette.
3. **Icône et miniatures.** Icône de 512 × 512. Miniatures au format 16:9, qui montrent un glyphe, un duel et le World Boss, sans texte qui promette ce que le jeu ne fait pas.
4. **Nom et description, en anglais et en français.** L'anglais est la langue source. La traduction française du nom et de la description se saisit dans l'onglet Localization de l'expérience.
5. **Serveurs privés.** Décider s'ils sont gratuits, payants ou fermés. Quel que soit ce choix, un serveur privé acheté joue en non classé : ni Elo ni classement, la moitié des récompenses d'un match (D-XXX, serveur privé). L'appariement ne se fait qu'entre joueurs d'un même serveur, et le World Boss demande deux joueurs (`WorldBossConfig.luau:28`) : dans un serveur privé à un seul joueur, il n'y a ni match ni boss.
6. **Joueurs par serveur.** 12 (`docs/STUDIO_SETUP.md` §2) : de quoi tenir deux 3v3 et le hub.
7. **Chat.** Chat texte activé. Les seuls textes venant des joueurs sont le chat Roblox et leurs noms : aucun filtrage à ajouter.
8. **Streaming.** `default.project.json` ne règle aucune propriété de `Workspace`. Ouvrir la place construite et vérifier que `StreamingEnabled` a bien la valeur voulue. Les arènes sont empilées à partir de 900 studs de haut, avec 400 studs de plus par emplacement, sans limite (`altitudeFor`, `ArenaService.luau:299-301,333-338` ; `MatchConfig.luau:71,75`). Le champ de bataille est bâti à X = 1500 (`BattlegroundConfig.Map.Origin`), au-delà du rayon de streaming par défaut : si `StreamingEnabled` est actif, faire le §6 bis.26 de `docs/QA.md`.

## 7. Textes et localisation

1. **Portes.** `lune run scripts/check-strings` (aucun texte joueur écrit en dur) et `lune run scripts/export-strings -- --check` (`localization.csv` à jour) doivent passer. Les deux font partie de `check.sh`.
2. **Table de localisation.** Dans le tableau de bord → Localization : langue source anglais, et ajouter le français. Téléverser `localization.csv` (colonnes `Key, Source, Context, Example, en, fr`, `scripts/export-strings.luau:2-3`).
3. **Traduction automatique de Roblox : coupée (D-XXX, traduction automatique).** Le jeu se traduit lui-même : `Strings.t` écrit l'anglais ou le français selon la langue du joueur (`Localize`, `LocaleService`), et toute autre langue lit l'anglais. Chaque `ScreenGui`, `BillboardGui` et `SurfaceGui` que le code crée, et chaque invite des piédestaux, porte `AutoLocalize = false` : la traduction automatique ne s'applique pas à ce qu'ils portent. La documentation ne dit pas si la capture automatique de texte, qui ne prend que les objets où cette propriété est vraie, s'arrête aussi aux descendants : c'est l'interrupteur du tableau de bord qui la coupe à coup sûr. Dans le tableau de bord → Localization, couper donc **Automatic Text Capture** et **Automatic Translation** pour toutes les langues, puis vérifier sur la place publiée (`docs/QA.md` §10.6). L'espagnol et le portugais du Brésil viendront d'une traduction relue, en P2.

## 8. Mise en ligne

1. **Un brouillon d'abord.** Avec `publish.yml` (secrets : `docs/STUDIO_SETUP.md` §6), cliquer **Run workflow** sur l'étiquette avec `Saved`. À la main : ouvrir le `build/Vellum.rbxl` construit depuis le commit étiqueté, puis **File → Publish to Roblox**.
2. **Vérifier le brouillon.** Ouvrir la place depuis Studio. Attendu : `[Bootstrap] Vellum v<nouvelle version> ready: 29 services started` et `0 missing ids`.
3. **Publier.** Relancer `publish.yml` sur le même commit, cette fois avec `Published`.
4. **Les serveurs déjà ouverts.** Ils gardent l'ancienne version. Les faire passer à la nouvelle depuis le menu de la place (*Restart servers for updates*). Une migration arrête les anciens serveurs : tant que R3 et R15 ne sont pas corrigés, la faire aux heures creuses.
5. **La version des portails : migrer tous les serveurs tout de suite.** Juste après le §8.3, lancer *Restart servers for updates* (anciennement *Migrate To Latest Update*) ou, à défaut, *Shut down all servers*. Aucun serveur de l'ancienne version ne doit rester ouvert, même une heure. La raison : cette version garde dans le profil les plafonds du jour, c'est-à-dire les 150 Folios des Faussaires et les 3 entraînements payés contre l'Effacement (`Daily.ForgerDay`, `ForgerFolios`, `PracticeDay`, `PracticePaid`), pour qu'un changement de serveur ne les remette pas à zéro. Mais l'ancienne version ne connaît pas ces quatre champs : quand elle charge un profil, elle les efface, puis enregistre le profil sans eux (`overlay`, `DataMigration.luau:153-170`). Un joueur qui a atteint son plafond sur un nouveau serveur, puis qui rejoint un ami sur un ancien serveur, revient donc avec des compteurs à zéro : 150 Folios et 3 entraînements payés de plus, et ainsi de suite tant qu'il reste un ancien serveur. De même pour les quêtes : un nouveau serveur range les quêtes qu'il ouvre pour un joueur sous la clé `D<jour>@2` (ou `W<semaine>@2`), dès le jour de la mise en ligne pour qui n'avait pas encore joué ce jour-là. Un ancien serveur prendrait ces quêtes pour celles d'un autre jour : il les remettrait à zéro, et les rendrait réclamables une seconde fois. L'ancienne version ne peut plus être corrigée : seule la fermeture de ses serveurs arrête le problème. Publier donc aux heures creuses, à cause de R3 et R15 (§8.4), puis migrer aussitôt.
6. **Passe courte en ligne.** Dérouler `docs/QA.md` §13, avec `F9` ouvert côté serveur et côté client.

## 9. Plan de retour arrière

À lire **avant** de publier.

1. **Quand revenir en arrière.** En cas de :
   - KO pendant la passe courte ;
   - erreur rouge qui se répète dans la console serveur ;
   - reçus qui bouclent (`[MonetizationService] receipt: …` en série, `Receipts.luau:219`) ;
   - expulsions en masse (`[AntiCheatService] <nom> kicked: …`, `AntiCheatService.luau:85`) ;
   - profils qui ne se chargent pas (`[DataService] load failed for …`).
2. **Comment.** Le plus rapide : tableau de bord → la place → **Version History** → restaurer la version précédente, puis faire passer les serveurs sur cette version (§8.4). Autre possibilité : republier l'étiquette précédente (`publish.yml` → **Run workflow** sur `v<version précédente>`, avec `Published`). Ensuite, corriger `main` avec un `git revert` du commit fautif, jamais en réécrivant l'historique.
3. **Ce qui ne revient pas.** Le code revient en arrière, pas les données :
   - Un profil ouvert par une version plus ancienne perd les champs qu'elle ne sait pas garder. La version du commit `c0b6687` n'en garde aucun : `overlay` ne garde que les clés du modèle (`DataMigration.luau:153-170`), et le numéro de version du profil est réécrit à l'ancienne valeur de `CurrentVersion` (`:376`). Revenir à elle efface les plafonds du jour, donc le champ de bataille et l'entraînement repaient une journée pleine, et rend les quêtes du jour réclamables une seconde fois (clé `D<jour>@2`, §8.5). Depuis la version des portails, un profil écrit par une version plus récente garde ses champs inconnus et son numéro (`newer`, dans `DataMigration.migrate`), à condition que cette version plus récente ait monté `CurrentVersion` (§2.6). Une version qui ajoute un champ ou migre le schéma ne se retire donc proprement que vers une version qui sait garder ses champs ; sinon, on la corrige avec une nouvelle version.
   - Un changement de saison a déjà vidé le classement de chaque profil chargé (`DataService.luau:199-202`).
   - Les achats livrés restent livrés et ne sont pas relivrés, car les reçus traités sont gardés dans le profil (`Purchases.Receipts`).
4. **Après.** Ajouter une entrée dans `docs/DECISIONS.md` : ce qui a cassé, ce qui a été restauré, ce qui manque encore.

## 10. Après la mise en ligne

1. **Première heure.** Surveiller la console serveur (`F9`) d'un serveur en ligne. Attendu : aucune erreur rouge qui se répète, aucune série de `receipt:`, et une ligne `profile ready` pour chaque joueur qui arrive.
2. **Premier jour.** Suivre les entonnoirs et l'économie dans l'analytique du tableau de bord (`AnalyticsService` ; indicateurs du §8 de `docs/ECONOMY.md`).
3. **Première semaine.** Faire l'essai sur téléphone s'il n'a pas eu lieu (`docs/PERFORMANCE.md`, « Ce qui n'est pas mesuré » ; D-124), puis corriger `QualityConfig.Auto` d'après les mesures.

## 11. Documents à aligner avant la mise en vente

Un joueur ou un développeur lit ces documents comme des promesses : les corriger en même temps que la publication.

| Document | Ce qu'il dit | Ce qui est vrai |
|---|---|---|
| `docs/STUDIO_SETUP.md:37,54`, `docs/ECONOMY.md:48` | le VIP a un tag dans le chat | aucun tag (R1) |
| `docs/ECONOMY.md:80` | Premium : 150 Folios + 30 min de boost, badge, quêtes bonus | 150 Folios + 300 XP (R10) |
| `docs/ECONOMY.md` §5 | prompts d'achat contextuels | jamais affichés (R8) |
| `docs/PERFORMANCE.md:137-139` | pire cas : « 201, `Pounce` », « 30 maillages (`Dash`) » | `Scorch` 358 particules, `Dash` 34 `Part` au pic (`docs/PERFORMANCE.md:98,112`, sortie de `lune run scripts/effect-cost -- --table`). Revérifier la ligne des plafonds de `PoolPolicy`. |
| `docs/PROGRESS.md:35` | système de spectateur à faire | `SpectateController.luau` existe |
| `docs/GAME_DESIGN.md:33` | pas de PvP dans la zone sûre du hub (donc PvP ailleurs au hub) | aucun PvP nulle part au hub (`MatchService.luau:616-636`) |
| `docs/GAME_DESIGN.md:164` | 1v1 : « 3 min, best-of-3 optionnel » | toujours en deux manches gagnantes sur trois, 60 s par manche |
| `docs/STUDIO_SETUP.md:80` | `[Bootstrap] Vellum v2.0.0 ready` | `… ready: 29 services started` |
| `docs/STUDIO_SETUP.md:86` | quatre boutons Melee / Dash / Block / Menu | cinq, avec `Cible` / `Lock` (`InputConfig.luau:161`) |
| `docs/STUDIO_SETUP.md` §7 | pas de relecture de la modération | `python3 scripts/upload_assets.py status` |
| `src/server/Config/DeveloperConfig.luau:24-25` (commentaire) | LoadoutService ne s'applique qu'au hub | seul `GlyphService` limite au hub (R6) |
