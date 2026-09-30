# Passe QA avant une version

Cette passe couvre ce que les tests Lune ne peuvent pas prouver : tout ce qui demande un moteur, un réseau, un vrai achat ou un vrai téléphone. Elle se déroule avant chaque publication en `Published` (voir `docs/PUBLISH.md`), dans l'ordre. Compter environ deux heures pour la passe complète et vingt minutes pour la passe courte (§13).

Les numéros de ligne renvoient au commit `c0b6687`. Si un numéro ne tombe plus juste, le nom de fonction cité à côté permet de retrouver l'endroit. Les écarts `R1` à `R15` sont décrits au §12.

## 0. Avant de commencer

**Les comptes.**

| Compte | Sert à | Ne sert pas à |
|---|---|---|
| Le compte développeur (`src/server/Config/DeveloperConfig.luau:13`) | la boutique et le roster complet au hub | ce qui touche au classé, aux Folios ou aux achats. Il a 20 emplacements (`LoadoutService.luau:107-108`). Il n'est jamais débité en Folios (`CurrencyService.luau:92-95`, D-129). Il lance sans coût au hub (`GlyphService.luau:156-164`). |
| Un compte secondaire, jamais inscrit dans `DeveloperConfig` | achats, Folios, classé, sauvegarde | — |
| Un compte Roblox Premium, si possible | le bonus Premium (§3.18) | — |
| Une deuxième personne | les tests à deux sur de vrais serveurs (§2.4, §5) | — |

**Les lieux.**

| Lieu | Pour | Attention |
|---|---|---|
| Studio, fichier construit (`./scripts/check.sh && open build/Vellum.rbxl`, méthode A de `docs/STUDIO_SETUP.md`) | §1, §6 à §11 | Ce fichier est une copie figée : le reconstruire après chaque modification. |
| Studio, **Test → Clients and Servers** (2 ou 6 joueurs) | §5, §6, §6 bis, §7 | Les joueurs de test ont des identifiants **négatifs**. Avec l'accès API, ils s'inscrivent dans les vrais classements (R5). |
| Une **copie de test** : la même place publiée en privé dans un autre univers | §2, §3, §4, et tout ce qui écrit dans un DataStore ou achète | C'est le seul endroit où un achat de test ou une ligne de classement ne salit pas les données publiques (R5, R9). |
| Un serveur de l'expérience publique | la passe courte après publication (§13) | Les achats y sont réels. |

**Lire les journaux.** Dans Studio, l'Output mélange serveur et client : garder les deux filtres ouverts (`docs/STUDIO_SETUP.md` §9). Sur un serveur en ligne, ouvrir la console développeur (`F9`), onglets **Server** et **Client**. Chaque ligne commence par le nom de son service, par exemple `[DataService] …`.

**Le rapport.** Noter une ligne par étape : numéro (`§3.4`), OK ou KO, ce qui a été vu, le compte et le lieu. Un KO qui correspond à un écart connu (§12) se note avec son numéro `R`, sans ouvrir de nouveau ticket.

## 1. Démarrage et build

1. **Les portes qualité.** Lancer `./scripts/check.sh`. Attendu : la dernière ligne est `✔ all quality gates green` (`scripts/check.sh:92`). Un échec ici arrête la passe.
2. **Le serveur démarre.** `open build/Vellum.rbxl`, puis **Play**. Attendu : `[Bootstrap] Vellum v2.0.0 ready: 28 services started` (28 entrées dans la table `ordered` de `Bootstrap.server.luau` : les 26 du commit `c0b6687`, plus `BattlegroundService` et `PortalService` ; la version vient de `GameConfig.luau:6`). Si le nombre est plus bas, la ligne rouge juste au-dessus nomme le service fautif.
3. **Les identifiants d'achat.** Attendu : `[MonetizationService] started (4 passes, 10 products, 0 missing ids)` et aucune ligne `missing id` (`MonetizationService/init.luau:71-77,96`). Au commit `c0b6687`, les 14 identifiants valent encore `0` et la ligne dit `14 missing ids`. C'est normal tant que le §3 de `docs/PUBLISH.md` n'est pas fait.
4. **Le client est complet.** Dans l'Output, filtre Client. Attendu : aucune ligne `[VfxController] no renderer for …` (`VfxController.luau:231`) et aucune liste de sons manquants de `SoundController` (`SoundController.luau:301-303`).
5. **Un seul point d'apparition.** Attendu : aucune ligne `[HubService] foreign SpawnLocation` (`HubService.luau:422-429`).
6. **La bonne place.** Coller la sonde du §9 de `docs/STUDIO_SETUP.md` dans la barre de commande. Attendu : `StarterPlayerScripts: 3`, et `Shared`, `UI`, `Packages` à `OK`.

## 2. Données et sauvegarde

À faire sur la copie de test, ou dans Studio avec l'accès API. Sans accès API, rien n'est enregistré et le serveur l'annonce : `[DataService] DataStore state: NoAccess (Studio without API access saves nothing)` (`DataService.luau:338-340`). Le jeu reste jouable, mais cette section ne prouve alors rien.

1. **Premier profil.** Faire rejoindre un compte qui n'a jamais joué. Attendu : niveau 1, 0 Folios, 8 glyphes de base, 6 emplacements. Côté serveur : `[DataService] profile ready for <nom> (v4, session #1)` (`DataService.luau:281-286` ; `DataMigration.CurrentVersion = 4`, `DataMigration.luau:25` ; `ProgressionConfig.luau:83`).
2. **Un réglage conservé.** `M` → Options, réassigner une touche, arrêter, relancer. Attendu : la touche est conservée (`docs/STUDIO_SETUP.md` §5.3).
3. **Revenir vite.** En ligne : gagner des Folios, quitter, rejoindre dans les 5 s. Attendu : le profil se charge, parfois avec quelques secondes de retard, le temps que l'ancien serveur relâche la session. Les Folios et l'XP de la session précédente sont là, **comptés une seule fois** (`onPlayerRemoving` → `profile:EndSession()`, `DataService.luau:308-329`).
4. **Un compte sur deux serveurs.** Le même compte rejoint un second serveur alors qu'il est encore sur le premier. Attendu : le premier serveur l'expulse avec le message traduit `kick.sessionElsewhere` (`Strings.luau:556-559`, `onSessionEnd`, `DataService.luau:205-210`). Si cela arrive pendant un duel classé, voir R4.
5. **Arrêt du serveur.** Gagner des Folios, puis Creator Dashboard → **Shut down servers** (ou **Stop** dans Studio avec l'accès API). Attendu : au retour, les Folios sont là (le `BindToClose` de ProfileStore, `ProfileStore.luau:2208`) et la valeur de classement a été écrite (`LeaderboardService.luau:535`, attente bornée par `CLOSE_WAIT_SECONDS = 15`, `:73`). Noter le message d'expulsion affiché : voir R15.
6. **Pour mémoire (pas un test).** Seuls les achats forcent une écriture immédiate (`DataService.saveNow`, `DataService.luau:452`). Le reste attend la sauvegarde automatique toutes les 300 s (`ProfileStore.luau:170`) ou la fin de session. Un crash de serveur fait donc perdre jusqu'à cinq minutes de progression.

## 3. Achats et reçus (Robux)

À faire sur la copie de test, avec les vrais identifiants et **un compte secondaire** : dans Studio avec l'accès API, un achat de test écrit dans le vrai profil (R9). Pour chaque produit, noter le toast, la ligne serveur `[MonetizationService] <nom> received <Clé>` (`Receipts.luau:182`) et le solde après être revenu dans le jeu.

1. **Entrée sans identifiant.** Tant qu'une clé vaut `0`, le bouton Robux est grisé (`docs/STUDIO_SETUP.md` §5.9). Si un écran ouvre quand même l'achat, attendu : toast `purchase.unavailable` et `[MonetizationService] purchase refused for <nom>: product <Clé> has no id yet` (`Purchases.luau:27-30,84-87` ; pour un pass, `:38-41`).
2. **VIP.** Attendu : aura `VipAura` possédée, XP ×2, Folios ×1,5 (`Passes.luau:77-88`, `ProgressionConfig.luau:71-72`, `CurrencyService.luau:70-72`). Il n'y a **pas** de tag dans le chat : voir R1.
3. **LoadoutSlots.** Attendu : 10 emplacements dans l'écran d'équipement (`LoadoutService.setExtraSlots`, `LoadoutService.luau:188` ; plafond en `ProgressionConfig.luau:84`).
4. **Orpiment.** Attendu : le pigment et ses glyphes sont débloqués sans attendre le niveau 40 (`Passes.luau:73-74`, `ProgressionConfig.luau:79`).
5. **SkinPack.** Attendu : les 4 skins sont possédés (`MonetizationConfig.luau:34-39`).
6. **Pass puis retour.** Après chacun des quatre passes : quitter, rejoindre. Attendu : l'effet est toujours appliqué (`Passes.sync`, `Passes.luau:108`).
7. **Pass acheté hors du jeu.** Acheter un pass sur la page web de l'expérience, puis rejoindre. Attendu : il est appliqué à l'arrivée, après au plus trois essais espacés de 2 s (`Passes.luau:32-33,47-64`).
8. **Pass déjà possédé.** Relancer l'achat d'un pass possédé. Attendu : toast `purchase.alreadyOwned` et aucune fenêtre Roblox (`Purchases.luau:42-46`).
9. **Folios.** Acheter `FolioSmall`, `FolioMedium` et `FolioLarge`. Attendu : +1000, +3500 et +8000 Folios (×1,5 avec le VIP) (`MonetizationConfig.luau:42-65`, `grantFolios`, `Receipts.luau:57-73`). Ensuite, confirmer un achat et quitter le jeu aussitôt, puis rejoindre. Attendu : l'achat est crédité **une seule fois** (reçus gardés dans `Purchases.Receipts`, `ReceiptProcessor`).
10. **PremiumPass.** Attendu : la piste premium devient réclamable (`BattlepassService.claim`, contrôle en `BattlepassService.luau:197`). Un second achat affiche `purchase.alreadyOwned` avant toute fenêtre (`Purchases.luau:98-101`).
11. **TierSkip5 sous le palier 46.** Attendu : +5 paliers, et l'XP déjà accumulée vers le palier suivant est conservée (`tierSkipXp`, `Receipts.luau:41-55`).
12. **TierSkip5 entre les paliers 46 et 49.** Attendu : seuls les paliers restants jusqu'à 50 sont accordés (`Receipts.luau:46`), et le toast `purchase.tiersGranted` donne le vrai nombre. La description promet cinq paliers : voir R14. Au palier 50, attendu : l'achat est refusé avant la fenêtre (`Purchases.luau:102-105`).
13. **TierSkip5 deux fois de suite au palier 46.** Confirmer deux achats sans attendre. Attendu : **aucun reçu ne boucle**, c'est-à-dire que le second achat ne reste pas en attente et n'est pas relivré au retour. Aujourd'hui il boucle : voir R2. Même risque si le joueur passe le palier 50 grâce à l'XP d'un match pendant que la fenêtre est ouverte.
14. **XpBoost1h acheté deux fois.** Attendu : la durée du boost s'allonge et ne raccourcit jamais (`BattlepassService.grantXpBoost`, `BattlepassService.luau:135`).
15. **Cosmétique payé en Robux.** Choisir un article de la rotation, puis **Acheter en Robux**. Attendu : exactement cet article est accordé. Le choix est mémorisé 600 s (`ShopService.setPurchaseIntent`, `ShopService.luau:204-223` ; `ShopConfig.luau:21`).
16. **Fenêtre laissée ouverte plus de 10 min.** Attendu : un article de cette rareté est quand même accordé (`ShopService.resolveReceiptItem`, `ShopService.luau:256`).
17. **Rareté entièrement possédée.** Attendu : le joueur reçoit des Folios au prix de la boutique, avec le toast `purchase.grantedFoliosInstead` (`Receipts.luau:89-96`, prix en `ShopConfig.luau:6`).
18. **Bonus Premium.** Faire rejoindre un compte Premium. Attendu : toast `daily.premium`, +150 Folios, +300 XP, une fois par jour UTC, et la ligne `[DailyRewardService] <nom> took the Premium bonus …` (`DailyConfig.luau:20`, `DailyRewardService.luau:102-117,126-128`). Les Premium n'ont aucun autre avantage : voir R10.

L'idempotence des reçus et le cas du profil non chargé sont déjà prouvés par `tests/ReceiptProcessor.spec.luau` et `tests/ReceiptItem.spec.luau`. Ici, on ne vérifie que le trajet réel, de bout en bout.

## 4. Boutique et Folios

À faire avec le compte secondaire. Le compte développeur n'est jamais débité (D-129) : ses achats en Folios ne prouvent aucun débit.

1. **Achat simple.** La boutique montre six articles du jour. En acheter un avec des Folios et l'équiper. Attendu : l'article passe en « possédé » et le solde baisse du prix de sa rareté (`onBuyCosmetic`, `ShopService.luau:274-320`). Côté serveur : `[ShopService] <nom> bought <id> for <n> Folios`.
2. **Solde insuffisant.** Attendu : toast `shop.notEnoughFolios` et solde inchangé. Le bouton Robux permet ensuite d'acheter **cet** article (`ShopService.luau:300-305`).
3. **Dix appuis rapides.** Appuyer dix fois très vite sur Acheter. Attendu : un seul débit et un seul article. Un article déjà possédé est refusé (`ShopService.luau:288-292`), et `BuyCosmetic` est limité à `{ Capacity = 4, Refill = 0.5 }` (`Remotes.luau:122-127`).
4. **Changement de jour.** Attendre 00:00 UTC, ou avancer l'horloge de la machine dans Studio. Attendu : la rotation change en 5 s environ, sans rejoindre, avec la ligne `[ShopService] rotation <jour>: …` (`ShopService.luau:85,120-129,326-335`).
5. **La boucle de jeu.** Quêtes, récompense quotidienne, équipement conservé, palier gratuit : suivre `docs/STUDIO_SETUP.md` §5.6 à §5.10. En plus : sauter un jour, attendu le toast `daily.broken` (`DailyRewardService.luau:122-125`) ; réclamer un palier premium sans Premium, attendu un refus (`BattlepassService.luau:197`).

## 5. Matchs 1v1 / 3v3 et abandons

Dans Studio, **Test → Clients and Servers**, avec 2 joueurs (6 pour le 3v3). Pour tout ce qui touche au classement, lire l'Output serveur.

1. **Appariement.** Sur les deux clients : **Jouer** → **1v1 classé**. Attendu : appariement en quelques secondes, puis un compte à rebours de 5 s (`MatchConfig.luau:19-31`).
2. **Durée des manches.** Attendu : trois manches au plus, de 60 s chacune (180 s / 3, `Duel1v1.Start`, `Duel1v1.luau:23-26` ; `GameModes.maxRounds`, `GameModes/init.luau:107-109`). Le premier à deux manches gagne. Il y a 3 s de pause entre deux manches (`MatchConfig.luau:49`) et 8 s d'écran de résultat.
3. **Temps écoulé.** Laisser le chrono finir sans KO. Attendu : la manche va au joueur qui a le plus de santé ; à santé exactement égale, la manche est nulle (`GameModes.timeoutVerdict`, `GameModes/init.luau:181-198`).
4. **Chute hors de l'arène.** Pousser l'adversaire dans le vide. Attendu : il meurt et l'attaquant est crédité du KO (`onKillZoneTouched`, `MatchService.luau:580-600`).
5. **Abandon.** Fermer un client en plein match. Attendu : le survivant gagne avec le toast `match.opponentLeft`, et le serveur écrit `[RankingService] <nom> abandoned Duel1v1: <avant> -> <après> …` (`MatchService.luau:459-489,688-714` ; `RankingService.applyAbandon`, `RankingService.luau:273-318`). C'est le test du §5.14 de `docs/STUDIO_SETUP.md`.
6. **Abandon après avoir gagné.** Mener 2-0, puis fermer son client pendant la pause de fin de manche. Attendu : aucun débit, la victoire est maintenue (`MatchService.luau:697-705`, D-34).
7. **Départ pendant l'attente.** Quitter le jeu pendant qu'on est en file. Attendu : le joueur est retiré de la file et aucun match fantôme ne se crée (`MatchmakingService.luau:311-319`).
8. **Attente trop longue.** Rester seul en file pendant 240 s. Attendu : toast `queue.timedOut` en information (médaillon « i », pas le « ! » rouge d'un échec, D-147) ; écran Jouer ouvert, la carte du mode devient « Personne en file pour l'instant » avec Réessayer et Retour au hub (`MatchConfig.luau:58`, `MatchmakingService.luau:285-293`, `PlayScreen.luau`).
9. **Rejouer.** Cliquer **Rejouer** sur l'écran de résultat. Attendu : retour immédiat en file, pendant que l'autre joueur voit toujours son écran de résultat (`MatchService.releaseFromResult`, `MatchService.luau:896`).
10. **Pas de PvP au hub.** Deux joueurs au hub se frappent. Attendu : aucun dégât, nulle part dans le hub. Les mannequins, eux, prennent des dégâts (`allowDamage`, `MatchService.luau:616-636`).
11. **3v3 sans tir allié.** Avec six clients, frapper un coéquipier. Attendu : aucun dégât (`MatchService.luau:628-632`, D-113).
12. **3v3 avec un joueur qui part.** Fermer un client. Attendu : son équipe continue à deux et le joueur parti est débité. Si toute une équipe part, le match se termine par forfait (`GameModes.forfeitVerdict`, `GameModes/init.luau:146-160`).
13. **3v3, joueur éliminé.** Attendu : la caméra suit un coéquipier, avec le bandeau `match.watching` (`SpectateController.luau`).
14. **Récompenses.** Avec le compte secondaire, sans VIP ni boost. Attendu : 350 XP et 60 Folios pour une victoire, 120 XP et 20 Folios pour une défaite, ×1,2 en 3v3. La première victoire du jour ajoute +500 XP et +100 Folios, une seule fois (`ProgressionConfig.luau:43-64`, `MatchConfig.luau:61-65`, `DailyRewardService.markFirstWin`, `:84`).
15. **Arrêt du serveur pendant un classé.** Arrêter le serveur pendant un duel. Attendu : aucune ligne `abandoned` et des classements inchangés. Voir R3.
16. **Changement de serveur pendant un classé.** Voir §2.4 et R4.

## 6. World Boss

L'événement revient toutes les 1200 s. Pour le déclencher tout de suite, suivre `docs/STUDIO_SETUP.md` §5.15 (`IntervalSeconds = 30`, `AnnounceSeconds = 5`). Tant que ces valeurs ne sont pas remises, `tests/Config.spec.luau:615-617` échoue. C'est voulu : cela empêche de publier le raccourci.

1. **Déroulé.** Avec 2 clients. Attendu : annonce, apparition du boss, et le boss prend des coups (`WorldBossService/init.luau:247-328`).
2. **Un seul joueur.** Avec 1 client. Attendu : `[WorldBossService] event skipped: 1 player(s) available, 2 needed` (`init.luau:247-253`).
3. **File gelée.** Attendu : pendant l'événement, la file est en pause et le temps d'attente n'est pas compté (`MatchmakingService.luau:248-300`, `docs/STUDIO_SETUP.md` §5.16).
4. **Duel en cours.** Avec 4 clients, dont deux en duel au moment de l'annonce. Attendu : les duellistes ne sont pas emmenés à l'événement, et leurs dégâts entre eux fonctionnent toujours (`bossPolicy`, `init.luau:80-93` ; `Context.eligiblePlayers`).
5. **Pas de PvP pendant l'événement.** Deux joueurs de l'événement se frappent. Attendu : aucun dégât entre eux, mais le boss en prend (`init.luau:92`).
6. **Seuils de récompense.** Attendu : à partir de 1 % des dégâts, toast `boss.reward` ; à partir de 15 %, `boss.killBonus` en plus ; sous 1 %, aucun des deux (`WorldBossConfig.luau:104-107`, `rewardParticipants`, `init.luau:190-210`).
7. **Chrono écoulé.** Ne pas tuer le boss en 300 s. Attendu : `boss.expired`, retour au hub après 15 s, puis l'événement suivant est planifié (`WorldBossConfig.luau:23-29`, `init.luau:238`).
8. **Tout le monde mort ou parti.** Attendu : l'événement se termine comme expiré (issue `Empty`, `init.luau:362`).
9. **Départ en plein combat.** Attendu : le joueur parti ne reçoit rien et l'événement continue pour les autres (`Context.livePlayers`).
10. **Remettre les valeurs.** Remettre `WorldBossConfig.Schedule` à 1200 / 60 / 300 / 15 / 2 (`WorldBossConfig.luau:23-29`), puis vérifier que `./scripts/check.sh` est vert.

## 6 bis. Portails, Champ de bataille et entraînement contre l'Effacement

Ce code n'existe pas au commit `c0b6687` : les renvois donnent le fichier et la fonction, sans numéro de ligne. Le tour rapide à un joueur est au §5 de `docs/STUDIO_SETUP.md` (étapes 17 à 22) ; ici, on vérifie chaque règle. Dans Studio, **Test → Clients and Servers**, avec 1 joueur, ou 2 quand l'étape le demande. Les joueurs de test ne sont pas dans `DeveloperConfig` : ils gagnent et paient comme le compte secondaire.

**Les portails du hub**

1. **Au démarrage.** Attendu côté serveur : `[PortalService] watching 3 portal circles at 10 Hz`, soit les deux portails du hub et le retour du champ de bataille. Le gabarit de l'arène de l'Effacement, rangé dans ServerStorage, n'ouvre aucun cercle (`addSeal`, `PortalService.luau` ; `PortalConfig.CheckHz`). Et aussi : `[BattlegroundService] page built at x 1500: 170 studs, <n> waypoints, up to 12 members and 10 Forgers` (`BattlegroundService.Start`).
2. **Entrer en restant dans le cercle.** Au nord du hub, entrer dans le cercle du portail « Champ de bataille » et ne plus bouger. Attendu : la bande « Reste dans le cercle : Champ de bataille » se remplit en 1,5 s, puis le joueur arrive dans le camp. Aucune touche n'est à presser : aucun remote client→serveur ne fait voyager (`step`, `PortalService.luau` ; `PortalConfig.Zones`, `DwellSeconds = 1.5` ; la bande : `onPortalChanged`, `TravelController.luau` ; `tests/Portal.spec.luau`). Un joueur mort, en match ou à terre n'est emporté par aucun cercle (`standing` et `step`, `PortalService.luau`).
3. **Sortir avant la fin.** Ressortir du cercle avant 1,5 s. Attendu : la bande disparaît et rien ne se passe. Revenir dans le cercle relance l'attente à zéro (`moveTo`, `PortalService.luau`).
4. **Un écran ouvert.** Ouvrir un écran (`M`), puis se tenir dans un cercle. Attendu : l'écran se ferme à l'arrivée, et les commandes ne restent pas suspendues (`MenuController.close` branché sur `TravelController.Travelled`).
5. **Trois secondes entre deux voyages.** Arriver dans le camp, puis entrer tout de suite, en moins d'une seconde, dans le cercle du portail de retour, à quelques pas. Attendu : aucune bande, puis, au bout de 2 s, le toast `portal.cooldown`, et plus rien tant qu'on ne ressort pas du cercle. Recommencer en entrant dans le cercle une à deux secondes après l'arrivée. Attendu : la bande n'apparaît qu'à la fin des 3 s, puis se remplit en 2 s entières à partir de là (`step`, `PortalService.luau` ; `PortalConfig.CooldownSeconds = 3`).
6. **Protégé à l'arrivée.** Attendu : après chaque voyage, 1,5 s pendant laquelle aucun coup ne retire de vie (`journey`, `PortalService.luau` → `CombatService.grantIFrames` ; `PortalConfig.EntryIFrameSeconds = 1.5`). Au champ de bataille, en plus, aucun Faussaire ne vise un arrivant pendant 4 s (`eligible`, `BotBrain.luau` ; `BotConfig.ArrivalGraceSeconds`).

**Le champ de bataille**

7. **L'arrivée.** Attendu : le joueur est dans le camp, à l'ouest, derrière une ligne d'encre, tourné vers le centre. Il reçoit le toast `battleground.entered` (« Les Faussaires t'ont vu. »), une bande « 3 Faussaires debout · 0 vaincus » (`battleground.status`, `onBattlegroundChanged`, `TravelController.luau`) et la musique de combat. Aucun point d'arrivée n'est dans le cercle du retour (`Roster.nextLanding` ; `BattlegroundConfig.Map.Arrivals`). Le compte développeur n'y lance pas ses glyphes sans coût (`BattlegroundService.isInside`, lu par `GlyphService`).
8. **Les Faussaires attaquent.** Sortir du camp. Attendu : trois Faussaires pour un joueur actif (deux Barbouilleurs au corps à corps et une Plume qui tire de loin), un de plus par joueur actif supplémentaire, dix au plus (`populate`, `BattlegroundService/init.luau` ; `BotConfig.BaseCount`, `PerExtraMember`, `MaxBots`, `Roster`). Un seul enchaînement à la fois vise un même joueur, suivi de 0,8 s de répit (`BotBrain.tokenFree` ; `BotConfig.Targeting.TargetRestSeconds`). Un Faussaire vaincu est remplacé au bout de 8 s pour un joueur seul, plus vite à plusieurs, jamais en moins de 4 s (`BotConfig.Respawn`). Le verrou (clic molette) prend un Faussaire (`LockOnController`).
9. **Le signal avant chaque coup.** Attendu : chaque coup est annoncé pendant toute sa préparation. Un rectangle d'encre au sol part du Faussaire, va jusqu'au bord de ce que le coup touchera et se remplit ; un éclat de craie à la main dit « maintenant » (`ForgerTell` : `Attacks.windup`, `BattlegroundService/Attacks.luau` ; le dessin : `VfxLibrary.ForgerTell`). La préparation dure au moins 0,5 s pour le premier coup, et 0,4 s pour chaque coup suivant d'un enchaînement (`BotConfig.MinWindupSeconds`, `MinChainGapSeconds`). Sortir du rectangle à temps esquive le coup. Un Faussaire interrompu pendant sa préparation, ou tué, efface son signal tout de suite (`Attacks.retract`). Aucun coup ne tombe sans signal. Ce signal n'est pas encore passé au labo (D-133) : noter ce qui est vu.
10. **Mourir au champ de bataille.** Se laisser tuer hors du camp. Attendu : le joueur réapparaît dans le camp, pas au hub. La bande reste et garde le compte des vaincus (`onDied` puis `redirect`, `BattlegroundService/Roster.luau` ; `BattlegroundConfig.RespawnInside`, `RespawnRedirectGraceSeconds = 5`).
11. **Le camp.** Revenir blessé dans le camp. Attendu : aucun Faussaire n'y entre, et aucun ne vise quelqu'un qui s'y tient, même celui qui vient de le frapper depuis le camp (`eligible`, `BotBrain.luau` ; le camp est exclu des chemins des Faussaires, `BattlegroundLayout.luau`). La vie remonte de 25 PV/s après 1,5 s sans coup reçu (`observe`, `BattlegroundService/Roster.luau` ; `BotConfig.Camp`).
12. **Rien ne se gagne depuis le camp.** Depuis le camp, frapper au corps à corps ou toucher d'un glyphe un Faussaire resté dehors. Attendu : chaque coup est rendu au Faussaire, dont la barre remonte (`onDamaged` → `BotBrain.creditHit`, `BattlegroundService/init.luau`). Un coup qui le tue depuis le camp ne paie ni XP ni Folios (`BotBrain.creditable`, `Rewards.pay`).
13. **Les récompenses.** Hors du camp, vaincre un Faussaire. Attendu : le toast `hud.killReward`, et par Faussaire 30 XP et 1 Folio (Barbouilleur), 35 XP et 1 Folio (Plume), 100 XP et 4 Folios (Surchargeur), avant VIP et boost (`payOne`, `BattlegroundService/Rewards.luau` ; `ProgressionConfig.luau`, clés `BotSmudger`, `BotQuill`, `BotOverwriter`). Celui qui a retiré au moins un quart de la vie d'un Faussaire est payé lui aussi (`BotConfig.Credit.AssistShare`). La quête « Vaincs 15 Faussaires » avance si elle fait partie des quêtes du jour (`DailyForgers`). Pour un joueur dont l'ancienne version avait déjà ouvert les quêtes du jour, elle n'entre dans le tirage que le lendemain de la mise en ligne ; pour les autres, dès le premier jour (`QuestConfig.PoolRevision`, `QuestLogic.setKey`).
14. **150 Folios par jour, pas plus.** Pour aller vite, dans le fichier construit ouvert dans Studio (jamais dans `src`), passer `DailyFolioCap` à 2 dans `ReplicatedStorage.Shared.Config.BotConfig`, puis vaincre des Barbouilleurs. Attendu : une fois 2 Folios gagnés sur les Faussaires dans la journée, les suivants ne paient que l'XP, avec le toast `battleground.folioCap` (« Les Faussaires ne rapportent plus de Folios aujourd'hui. L'XP compte toujours. »). Ce toast ne s'affiche qu'une fois par jour et par session (`payOne` et `takeFolios`, `BattlegroundService/Rewards.luau` ; `BotConfig.Credit.DailyFolioCap = 150`, compté avant le VIP). Avec l'accès API, arrêter puis relancer **Play** : le plafond est toujours atteint, car il est compté dans le profil (`Daily.ForgerDay`, `Daily.ForgerFolios`) et non dans la mémoire du serveur. Reconstruire le fichier ensuite (`./scripts/check.sh`).
15. **L'Effacement passe aussi par là.** Avec 2 joueurs au champ de bataille et le raccourci du §6 (`IntervalSeconds = 30`). Attendu : l'événement les emmène comme ailleurs, et la bande du champ de bataille disparaît (`stays`, `BattlegroundService/Roster.luau`, qui lit `WorldBoss.isEngaged`). À la fin de l'événement, ils reviennent au hub.
16. **Le retour.** Rester dans le cercle du portail du camp (« Retour au hub »). Attendu : la bande « Reste dans le cercle : Retour au hub » se remplit en 2 s, puis le joueur revient au hub, sans la bande du champ de bataille ni sa musique (`dispatch`, `PortalService.luau` → `BattlegroundService.leave` ; `PortalConfig.Zones`, `Return.DwellSeconds = 2`). Une minute plus tard, si personne n'y est actif, `Workspace.Forgers` est vide (`BotConfig.IdleDespawnSeconds = 60`).

**L'entraînement contre l'Effacement**

17. **Ouvrir un entraînement, seul.** Avec 1 joueur, rester 1,5 s dans le cercle « Affronter l'Effacement ». Attendu : le joueur arrive dans l'arène de l'Effacement. La bande est titrée « L'Effacement · entraînement » (`boss.practice.title`, `BossController.luau`). Le boss a 2 500 PV et le chrono démarre à 240 s (`WorldBossService.enterFromPortal` ; `WorldBossConfig.Practice`, `Health`, `FightSeconds`). La file du classé n'est pas mise en pause, et la règle PvP du hub ne change pas : `WorldBossService.isLive` reste réservé à l'événement.
18. **Rejoindre un entraînement en cours.** Avec 2 joueurs : A ouvre un entraînement, puis B prend le même portail. Attendu : B entre dans le même combat, et le serveur écrit `[WorldBoss.Admission] Practice: <B> Join (2 participant(s))` (`admit`, `WorldBossService/Admission.luau`). Le boss gagne 1 200 PV au premier coup de B, pas avant, et jamais au-delà de 8 000 PV (`Admission.struck`, `BossPractice.growthOnHit` ; `HealthPerJoiner`, `HealthCap`).
19. **Chrono écoulé.** Ne pas vaincre le boss en 240 s. Attendu : le toast `boss.expired`. Après 5 s, ceux qui sont encore dans l'arène reviennent au hub (`finish`, `WorldBossService/init.luau` ; `Practice.CleanupSeconds = 5`). Le serveur écrit `[WorldBossService] practice closed, next event in <n>s` : l'horaire de l'événement n'a pas bougé.
20. **Revenir après une mort, deux fois au plus.** Mourir pendant l'entraînement, puis reprendre le portail du hub. Attendu : le joueur revient dans le même combat, deux fois au plus. La troisième fois, le portail répond `boss.portal.noReentry` (`BossPractice.entryVerdict`, `Admission.join` ; `Practice.MaxReentries = 2`). Seul, il faut revenir dans les 15 s : l'arène vide attend ce temps-là, et le coup que le boss préparait est abandonné, pour qu'on ne revienne jamais sous un coup non annoncé (`closeEmpty`, `WorldBossService/init.luau` ; `EmptyGraceSeconds = 15`).
21. **La récompense.** Vaincre le boss seul. Attendu : les toasts `boss.killBonus` et `boss.reward`, avec +250 XP et +58 Folios, avant VIP et boost. C'est un quart d'une participation, bonus du meilleur dégât compris : 100 + 150 XP et 20 + 38 Folios (`payPractice`, `WorldBossService/Rewards.luau` ; `Practice.RewardFactor = 0.25`). Aucune quête `BossKill` n'avance, et `BossKills` ne bouge pas.
22. **Trois entraînements payés par jour, un toutes les 20 minutes.** Vaincre un deuxième entraînement sur le même serveur moins de 20 min après le premier payé. Attendu : rien n'est payé, avec le toast `boss.practice.noReward` et les minutes restantes (`practiceAllowed`, `WorldBossService/Rewards.luau` ; `RewardGapSeconds = 1200`, gardé par le serveur). Un refus pour ce délai ne consomme pas d'entraînement payé. Ensuite, avec l'accès API, arrêter et relancer **Play** entre deux victoires (le délai repart à zéro avec le serveur, pas le compte du jour). Attendu : le quatrième entraînement payé du jour affiche `boss.practice.dailyDone` (`RewardsPerDay = 3`, compté dans le profil : `Daily.PracticeDay`, `Daily.PracticePaid`).
23. **Ouvrir un entraînement puis sortir aussitôt.** Seul : ouvrir un entraînement, puis ressortir par le portail de retour de l'arène dans les 30 s. Attendu : le serveur écrit `[WorldBossService] practice left empty`, puis le combat se ferme. En reprenant le portail du hub, toast `boss.portal.cooldown`, avec environ 300 s (`Admission.closedEmpty`, `BossPractice.startPenalty` ; `EarlyEmptySeconds = 30`, `EarlyEmptyCooldownSeconds = 300`). Sorti après 30 s, l'attente n'est que de 30 s à compter de la fermeture (`StartCooldownSeconds`).
24. **L'événement est proche.** Avec 2 joueurs et le raccourci du §6 (`IntervalSeconds = 30`), prendre le portail « Affronter l'Effacement » hors événement. Attendu : refus `boss.portal.eventSoon`, avec les secondes restantes avant l'événement. L'événement tomberait avant la fin de l'entraînement (240 + 5 s), et deux joueurs suffisent pour qu'il ait lieu (`BossPractice.startVerdict`, `Admission.startRefusal`). Avec un seul joueur, l'événement ne peut pas avoir lieu : l'entraînement s'ouvre. Pendant l'annonce de l'événement, le portail répond `boss.portal.announced` ; pendant la fin d'un combat, `boss.portal.closing` (`Admission.join`). Remettre ensuite les valeurs du §6.10.
25. **Le portail de retour de l'arène.** Attendu : dans un coin de l'arène, à 12 studs des deux murs, un portail « Retour au hub ». Rester 2 s dans son cercle ramène au hub, et le joueur ne compte plus dans le combat (`WorldBossService.leave` → `Audience.release`, `WorldBossService/Audience.luau` ; `PortalConfig.BossArenaGateInsetStuds = 12`). Chaque copie de l'arène a son portail, pendant l'entraînement comme pendant l'événement (construit dans le gabarit, `ArenaService.luau`).

**Le streaming**

26. **Le champ de bataille chargé à l'arrivée.** Si `Workspace.StreamingEnabled` est actif dans la place (`docs/PUBLISH.md` §6.8), entrer au champ de bataille. Attendu : le sol, le camp et le portail de retour sont là dès l'arrivée, et le joueur ne tombe pas. La page est à X = 1500 (`BattlegroundConfig.Map.Origin`), au-delà du rayon de streaming par défaut. L'entrée attend au plus 2 s que le client charge les alentours du point d'arrivée (`RequestStreamAroundAsync` dans `BattlegroundService.enter` ; `PortalConfig.StreamTimeoutSeconds = 2`). Revenir ensuite au hub : ce retour n'attend aucun chargement (`HubService.teleportToHub`). Noter si le hub apparaît en retard ou si le joueur tombe. Si `StreamingEnabled` est inactif, noter « sans objet ».

## 6 ter. Épreuves plafonnées, quêtes Solo et relance

Ce code n'existe pas au commit `c0b6687` (vague 2, E10-S3, E10-S10). Les règles sont tenues sous Lune (`tests/TrialPay.spec.luau`, `tests/QuestLogic.spec.luau`, `tests/QuestReroll.spec.luau`) ; ce qui suit est ce que Lune ne peut pas voir.

**Les Épreuves du hub**

1. **Rien sans glyphe ni ruée.** Arriver au hub et abattre une Épreuve au seul corps à corps, sans lancer de glyphe ni ruer. Attendu : aucun toast `hud.killReward`, une seule fois dans la session le toast `trials.idle` (« Trace un glyphe ou fais une ruée pour gagner avec les mannequins. »), et `Stats.Kills` monte quand même (`creditKiller`, `EnemyService.luau`).
2. **Payé après un glyphe.** Lancer un glyphe, puis abattre une Épreuve dans la minute. Attendu : `hud.killReward` avec +40 XP (avant VIP et boost) et +2 Folios ; la barre du pass ne bouge pas (`ProgressionConfig.PassExcluded`).
3. **Le toast du plafond, une fois par jour.** Continuer : au 20ᵉ kill payé du jour, le toast `trials.capped` (« Les mannequins rapportent moins jusqu'à demain. Les portails rapportent plus ! »), et plus aucun Folio ensuite ; à partir du 26ᵉ, +10 XP par kill. Arrêter puis relancer **Play** avec l'accès API : pas de nouveau toast, les compteurs sont dans le profil (`Daily.TrialDay`, `TrialKills`, `TrialFolios`).
4. **Un glyphe sur une Épreuve.** Toucher une Épreuve d'un glyphe. Attendu : pas d'XP `GlyphHit` (aucune montée de la barre d'XP au coup), mais la quête « Touche des ennemis avec N glyphes » avance.

**Les quêtes**

5. **Le bouton Changer.** Ouvrir les Quêtes. Attendu : chaque quête du jour en cours porte une pastille « Changer » à droite de ce qu'elle rapporte ; aucune sur une quête hebdomadaire, terminée ou réclamée. Vérifier sur 844 × 390 et 667 × 375 que le nom et la barre de la quête ne sont pas écrasés.
6. **Changer une quête.** Presser « Changer » sur une quête que l'on ne peut pas finir seul (« Gagne un match »). Attendu : le bouton attend (trois points), puis la carte est remplacée par une quête Solo du jour, le toast `quest.rerolled` la nomme, et plus aucune carte ne propose « Changer » avant le lendemain (`QuestService.reroll`).
7. **Le badge suit.** Terminer la quête reçue. Attendu : le sceau des quêtes de l'amas méta et la tuile du Menu comptent la quête reçue, pas celle renvoyée (`Claims.luau`).

## 7. États qui ne doivent pas déborder d'un match à l'autre

Ce qu'un match laisse derrière lui se voit surtout au match suivant. Enchaîner ces étapes sans relancer Play.

1. **Personnage neuf à chaque manche.** Finir une manche marqué d'un pigment, sous la Dorure ou sans encre. Attendu : la manche suivante commence avec toute la santé, toute l'encre et aucun statut. Le personnage est rechargé (`prepareRound`, `MatchService.luau:409-441` ; `CombatService.luau:652-677` ; D-20).
2. **Temps de recharge des glyphes.** Lancer le glyphe au temps de recharge le plus long (25 s) dans les dernières secondes d'une manche. Aujourd'hui, il est encore en recharge au début de la manche suivante : les temps de recharge sont rattachés au joueur, pas au personnage (`GlyphService.luau:166-173,331`), et ne sont effacés qu'au départ du joueur (`:416-418`). Même chose en passant du hub à un match. Noter ce qui est vu (R13).
3. **Retour au hub.** Attendu en fin de match : toast `match.returning`, le joueur est au `HubSpawn` et le HUD de match a disparu (`MatchChanged` passe à `nil`, `MatchService.luau:371-374`).
4. **Personnage débloqué.** Attendu : après l'écran de résultat, ou après **Rejouer**, le personnage peut bouger (`enterResult` le fige pendant `ResultSeconds`, `MatchService.luau:385-395`).
5. **Verrou relâché.** Verrouiller l'adversaire, puis finir le match. Attendu : le losange a disparu au hub, et le clic molette verrouille normalement un mannequin (`LockOnController`, D-115).
6. **Caméra rendue.** Se faire éliminer en 3v3, puis attendre la fin du match. Attendu : la caméra revient sur son propre personnage.
7. **Arène détruite.** Attendu après chaque match : `Workspace.Arenas` ne contient plus l'arène de ce match (`ArenaService.release`, `ArenaService.luau:396-403`), et le serveur écrit `[MatchService] match <id> ended (arena <id> slot <n>)`.
8. **Dix duels d'affilée.** Attendu : l'emplacement 1 est réutilisé à chaque fois, sans pile d'arènes, et la mémoire serveur (`F9` → Memory) reste stable (`finish`, `MatchService.luau:357-383`).
9. **Pas de match fantôme.** Un joueur qui a abandonné revient. Attendu : il peut refaire la file et ne compte plus dans l'ancien match (`MatchService.luau:363-370`).
10. **Règle de dégâts restaurée.** Après un World Boss, faire un duel. Attendu : les coups portent en duel, et le hub reste sans PvP (`WorldBossService/init.luau:102,110`).
11. **Avantages développeur en match.** En match, le compte développeur a des temps de recharge normaux et dépense son encre (`GlyphService.luau:163`). Ses 20 emplacements, eux, le suivent en match : voir R6.

## 8. Mobile, tactile, manette

Commencer dans Studio avec **Test → Device** (l'émulateur), puis sur un vrai téléphone avec la copie de test.

1. **Téléphone 812×375.** Attendu : les pictogrammes `▲ ≈ ■ » ϟ` sont visibles et les libellés courts sont complets (`CAC`, `Ruée`, `Garde`, `Cible`, `Menu`). Aucun bouton ne fait moins de 44 px et rien ne recouvre le bouton de saut (`InputConfig.luau:161,165-172` ; `docs/STUDIO_SETUP.md` §5.4).
2. **Bouton de verrou.** Attendu : le bouton est présent, libellé `Cible` en français et `Lock` en anglais (`Strings.luau:31`), et il verrouille puis relâche. `docs/STUDIO_SETUP.md` §5.4 ne le mentionne pas.
3. **Menu ouvert.** Ouvrir n'importe quel écran. Attendu : les boutons de combat disparaissent et reviennent à la fermeture (`setSuspended`, `InputController.luau:5-7`).
4. **Garde.** Maintenir le bouton Garde. Attendu : le personnage garde tant que le doigt reste appuyé (`docs/GAME_DESIGN.md:18`).
5. **Orpiment non débloqué.** Avec un compte qui n'a pas le pigment, noter ce qu'affiche le bouton Orpiment. `InputController` ne vérifie aucun déblocage. Un bouton affiché qui ne fait rien compte comme un KO d'ergonomie.
6. **Autres écrans.** Sur tablette 1024×768 et petit téléphone 667×375. Attendu : la mise en page tient, toujours en paysage (`default.project.json:45`, `LandscapeSensor`).
7. **Manette.** Attendu : le D-pad sélectionne les pigments et fait défiler le classement (`docs/STUDIO_SETUP.md` §5.5), et R3 verrouille.

## 9. Performances

1. **Niveau choisi par le joueur.** Options → Graphismes, essayer chaque niveau. Attendu côté client : `[QualityController] drawing at <niveau> (chosen by the player)` (`QualityController.luau:54-61,99`). En `Low`, aucune lumière d'effet ; en `Performance`, en plus, aucun post-traitement (`QualityConfig.luau:50-100`).
2. **Baisse automatique.** Rester sous 40 images/s pendant 3 s (combat à six, compteur `Performance Stats`). Attendu : le jeu descend d'un niveau, et la ligne se termine par `(NN fps)` (`QualityConfig.luau:110-116`, `QualityController.luau:122`).
3. **Remontée.** Rester au-dessus de 55 images/s pendant 12 s. Attendu : le jeu remonte d'un niveau, jamais au-dessus du choix du joueur (`QualityController.luau:133`).
4. **Choix plus bas pendant une baisse.** Attendu : c'est le plus bas des deux niveaux qui s'applique (`docs/PERFORMANCE.md:67-70`).
5. **Vrai téléphone.** Sur la copie de test publiée, dans l'application Roblox : mesurer les images/s à six joueurs en `High`, puis en `Performance`, puis pendant un changement de niveau en plein combat (`docs/PERFORMANCE.md:189-199`). Aucun chiffre du dépôt ne vient d'un vrai appareil (`docs/PERFORMANCE.md:183-187`), et l'essai D-124 reste à faire.
6. **Mémoire après une session.** Après le §7.8, ouvrir `F9` → Memory côté serveur et côté client. Attendu : pas de croissance continue.

## 10. Localisation EN/FR

1. **Français.** Dans Studio, **Test → Player Emulator**, langue `fr-fr`. Attendu : chaque écran, chaque toast et chaque panneau du hub est en français, et le client écrit `[Localize] locale fr` (`Localize.luau:48-53` ; `Strings.localeFromId`, `Strings.luau:604-615`).
2. **Autre langue.** Avec `es-es`. Attendu : tout est en anglais (`Strings.luau:10-11`).
3. **Textes longs.** En français, parcourir la boutique, les quêtes, l'écran de résultat et les options. Attendu : aucun texte coupé ni débordant. Le §5.4 de `docs/STUDIO_SETUP.md` ne vérifie que les boutons tactiles.
4. **Message d'expulsion.** Refaire le §2.4 avec un compte réglé en français. Attendu : le message est en français (`DataService.luau:171`).
5. **Portes.** Attendu : `check-strings` et `export-strings --check` passent (tous deux dans `scripts/check.sh`).
6. **Après publication.** Refaire le §10.1 sur la place publiée. Si la traduction automatique de Roblox est active, vérifier qu'elle ne réécrit pas un texte déjà traduit (`docs/PUBLISH.md` §7.3).

## 11. Anti-triche et remotes

1. **Appuis en continu.** Appuyer sur toutes les touches pendant 60 s d'affilée. Attendu : aucune expulsion ; tout au plus des lignes `[AntiCheatService] <nom> RateLimit strike n/600 …` (`AntiCheatService.luau:81`, seuil en `GameConfig.luau:35`).
2. **Couverture des remotes.** Les 15 remotes client→serveur ont chacun un schéma `Guard` et une limite de débit (`Remotes.luau:36-141`). C'est prouvé par `Guard.spec` et `TokenBucket.spec` : rien à faire à la main.

Les étapes 3 à 8 concernent le garde de mouvement (D-135 à D-139). Il est livré en **Observe** : il juge chaque corps et écrit ce qu'il aurait fait, mais ne déplace ni ne frappe personne. Ses lignes commencent par `[Combat.MovementAudit]`, côté serveur. Les vérifications du moteur qu'il attend avant de passer en Correct sont au §10 de `docs/STUDIO_SETUP.md`.

3. **Le garde démarre en observation.** Au **Play**, côté serveur : `[Combat.MovementAudit] mode Observe: gravity 196.2 (judged at 196.2), streaming …, signals …, 5 barrier parts` (`MovementAudit.start`). Attendu : `mode Observe`, le seul mode livré (D-137, tenu par `tests/Config.spec.luau`) ; les deux gravités égales ; 5 barrières, la plateforme du hub et ses quatre bordures. Un autre mode est un KO bloquant tant que le §10 de `docs/STUDIO_SETUP.md` n'est pas fait.
4. **Lire une ligne du garde.** Pour chaque joueur, au plus une ligne par titre et par genre toutes les 10 s. Format : `<joueur> <titre> (<genre>/<règle>): <mesure> against <budget>, back <n> studs; <issue>`.

   | Titre | Niveau | Ce que ça veut dire |
   |---|---|---|
   | `watch` | info | un signal pas encore confirmé, ou un corps immobile en l'air depuis 3 s (`Flight/frozen`) ; `back` vaut 0 |
   | `observe correct` | avertissement | deux signaux frais en 2 s : en Correct, le corps aurait été ramené de `back` studs |
   | `observe repivot` | avertissement | un téléport du serveur que le client n'a toujours pas appliqué : en Correct, le corps aurait été reposé sur la destination (`timeout/timeout`, puis `Resist/resist` au troisième refus en 30 s) |

   | Genre/règle | Le corps… |
   |---|---|
   | `Teleport/gap` | est plus loin, à plat, de là où le serveur le croyait que le plafond de vitesse (40 studs/s) et les mouvements accordés ne l'expliquent, de plus de 12 studs |
   | `Teleport/sink` | est descendu plus vite que la gravité |
   | `Flight/altitude` | est monté plus haut qu'un saut et un double saut (12,7 studs), plus les élévations des projections reçues, plus 2 studs |
   | `Flight/hang` | est resté en l'air plus longtemps qu'une chute ne le permet |
   | `Flight/frozen` | est immobile en l'air depuis 3 s |
   | `Speed/sustained` | a tenu pendant 3 s, sans contact ni mouvement accordé, plus que sa vitesse de marche × 1,25 + 2 studs/s |
   | `Noclip/wall`, `Noclip/floor` | est passé à travers un mur ou un sol étiqueté `MovementBarrier` |
   | `Invalid/invalid` | a une position qui n'est pas un nombre ou qui dépasse 100 000 studs |

   L'issue dit ce que le mode Enforce aurait fait : `exempt` (rien : un contact, une projection ou un dash en cours, une réapparition de moins d'1 s, un tick serveur en retard, le rattrapage d'un silence du réseau, un échantillon d'avant un téléport ou un corps à terre explique le mouvement), `would strike` (une frappe `Movement`). Une ligne `watch` finit par `exempt` : un signal seul ne frappe jamais, sauf `Flight/frozen` répété. Deux autres lignes : `a flight flag found ground N studs under the root, nothing done` (info : la sonde de confirmation a trouvé un sol que la sonde d'appui avait raté, noter l'endroit) ; `had no spawn point` ou `no SpawnLocation to rebase` (pas de `HubSpawn`, voir le §1.5).
5. **Une session honnête.** À deux clients (**Test → Clients and Servers**), jouer dix minutes sans retenir ses coups : marcher, sauter et double-sauter sur les bords, les bordures du hub, une dalle de la Marge et les épreuves ; dasher ; recevoir les projections des glyphes et la finale du combo ; lancer Caret et Ligature ; prendre les deux portails dans les deux sens ; mourir et réapparaître, au hub et au champ de bataille ; tomber d'une arène ; jouer un duel complet. Attendu : aucune ligne `would strike`. Une ligne `exempt` pendant un contact, une projection ou juste après une réapparition est acceptable ; la noter quand même, elle dit ce que Correct aurait fait.
6. **Reconnaître un faux positif.** C'est une ligne `would strike` sur un joueur qui n'a rien fait d'anormal. Noter la ligne entière, ce que le joueur faisait dans la seconde d'avant (sur quoi il a sauté, quelle projection, quel portail, quelle réapparition), son ping (`Shift+F3`) et l'endroit. Où chercher, selon la ligne : `Flight/hang` ou `Flight/altitude` au bord d'une surface, la sonde d'appui (`docs/STUDIO_SETUP.md` §10.1) ; `Teleport/gap` juste après un gel du réseau, qui devrait être `exempt` ; `observe repivot` ou `Teleport/gap` juste après un portail ou un pad, les échantillons périmés (§10.2 et §10.9) ; `Noclip/wall` après une projection contre un mur (§10.5) ; `Flight/frozen` sur un appareil lent (§10.7). En Observe, un faux positif ne touche aucun joueur : ce n'est pas un KO de la version, mais il bloque le passage en Correct (D-137).
7. **Une vraie triche est vue.** Dans Studio seulement, jamais sur la place publique. Vue **Client** (onglet Test, *Current: Client*), loin des épreuves et des autres joueurs, au moins une seconde après être apparu, dans la barre de commande : `local r = game.Players.LocalPlayer.Character.HumanoidRootPart r.CFrame += Vector3.new(0, 60, 0)`. Attendu côté serveur, dans la seconde : une ligne `<joueur> watch (Flight/altitude): …`, puis `<joueur> observe correct (Flight/altitude): … would strike`, et le corps n'est pas ramené (Observe). S'il n'y a aucune ligne, le garde ne voit pas les corps : KO bloquant. Un saut horizontal fait de l'arrêt peut, lui, passer pour le rattrapage d'un silence du réseau et n'être que poursuivi (D-139) : ce n'est pas un KO.
8. **Aucune frappe en Observe.** Sur toute la passe, attendu : aucune ligne `[AntiCheatService] <joueur> Movement strike …` (`AntiCheatService.strike`). Une seule suffit pour un KO bloquant : le garde frapperait en production.

## 12. Écarts connus au commit `c0b6687`

Voici ce que le code fait aujourd'hui et que la passe va rencontrer. Un KO qui correspond à une ligne de ce tableau se note par son numéro. Chaque ligne appelle une décision dans `docs/PUBLISH.md`.

| # | Gravité | Ce qui se passe | Où | Étape |
|---|---|---|---|---|
| R1 | haute (vente) | Le VIP promet un « tag dans le chat » qu'aucun code ne pose : il n'y a ni `TextChatService`, ni `OnIncomingMessage`, ni `PrefixText` dans `src`. | `Strings.luau:359-362`, `docs/STUDIO_SETUP.md:54`, `docs/ECONOMY.md:48` | §3.2 |
| R2 | moyenne | Un TierSkip qui ne peut plus rien donner renvoie `false`, donc `NotProcessedYet` : Roblox relivre sans fin un reçu déjà payé. Cela contredit la règle posée en tête du module. Le contrôle du palier 50 ne se fait qu'à l'ouverture de la fenêtre. | `Receipts.luau:146-150` contre `:6-12` ; `Purchases.luau:102-105` | §3.13 |
| R3 | moyenne, plausible | Un arrêt de serveur en plein classé peut débiter les deux joueurs : `onBeforeRelease` appelle `applyAbandon` pour tout match classé en cours, sans regarder `ProfileStore.IsClosing`. Cela dépend de l'ordre entre `PlayerRemoving` et le `BindToClose` de ProfileStore. | `MatchService.luau:688-714`, `DataService.luau:308-316`, `ProfileStore.luau:2208` | §5.15 |
| R4 | moyenne | Rejoindre un second serveur en plein duel évite le débit. `onSessionEnd` vide le profil avant l'expulsion ; `onPlayerRemoving` ne trouve alors plus rien et `BeforeRelease` n'est jamais émis. | `DataService.luau:205-210,308-316`, `RankingService.luau:287-291` | §2.4, §5.16 : aujourd'hui, ni débit ni ligne `abandoned` |
| R5 | moyenne | Les tests multi-clients de Studio avec l'accès API écrivent des identifiants négatifs dans les classements de la saison (`S1_Global`, `S1_Duel1v1`, `S1_Team3v3`). Faute de nom, ces lignes affichent l'identifiant brut. | `LeaderboardService.luau:240-244`, `nameFor` `:305-324` | §0 |
| R6 | moyenne | En classé, le compte développeur garde 20 emplacements et tout le roster ; seul le lancer gratuit est limité au hub. Le commentaire `DeveloperConfig.luau:24-25` dit le contraire. Les cosmétiques obtenus avec les Folios gratuits restent possédés, et `revokeDeveloperGrants` ne les retire pas. | `src/server/Config/DeveloperConfig.luau:13-26`, `LoadoutService.luau:104-109,281-292`, `GlyphService.luau:156-164`, `ShopService.luau:300-315` | §7.11 |
| R7 | moyenne | Deux textures étaient encore en modération au moment de l'envoi, et tous les assets appartiennent à un compte personnel. | `assets/roblox-assets.lock.json:2-3,601-613` | `docs/PUBLISH.md` §5 |
| R8 | basse | Les prompts d'achat contextuels de `docs/ECONOMY.md` §5 ne s'affichent jamais : `MonetizationService.maybePrompt(player: Player, reason: string): boolean` n'est appelé nulle part, et `CloseLossHealthFraction` n'est lu nulle part. | `MonetizationService/init.luau:46`, `MonetizationConfig.luau:127` | à ne pas attendre |
| R9 | basse | Dans Studio avec l'accès API, un achat de test écrit dans le vrai profil ; les passes mis en cache n'en sortent jamais. | `Passes.luau:2-4,145-162` | §0 |
| R10 | basse | `docs/ECONOMY.md:80` promet aux Premium 150 Folios + 30 min de boost, un badge et des quêtes bonus. Le code donne 150 Folios + 300 XP, et seulement au chargement du profil (aucun `PlayerMembershipChanged`). | `DailyConfig.luau:20`, `DailyRewardService.luau:126-128` | §3.18 |
| R11 | basse | Un PremiumPass reçu par un joueur déjà Premium renvoie `PurchaseGranted` sans rien livrer. Cela n'arrive qu'en cas de course ou de reçu tardif. | `Receipts.luau:132-139` | — |
| R12 | basse | Si l'attribution d'un cosmétique échoue après le débit, les Folios sont perdus. | `ShopService.luau:308-313` | — |
| R13 | basse, **nouveau** | Les temps de recharge des glyphes survivent aux manches, aux matchs et au passage du hub à un match, alors que D-20 promet qu'« aucun statut ne fuit d'une manche à l'autre ». | `GlyphService.luau:166-173,212,331,416-418` | §7.2 |
| R14 | basse, **nouveau** | Entre les paliers 46 et 49, TierSkip5 donne moins de cinq paliers pour le prix de cinq, alors que sa description dit « cinq ». | `Receipts.luau:46`, `Strings.luau:391-394` | §3.12 |
| R15 | basse, **nouveau**, plausible | À l'arrêt du serveur, si le `BindToClose` de ProfileStore relâche un profil avant le départ du joueur, `OnSessionEnd` se déclenche et `DataService` expulse avec `kick.sessionElsewhere`. Le joueur lit alors « Ta session a été ouverte sur un autre serveur ». | `ProfileStore.luau:2224-2230` → `SaveProfileAsync` `:716-725` ; `DataService.luau:205-210,277-279` | §2.5 |

## 13. Passe courte, après chaque publication

Sur un serveur en ligne de l'expérience publique, avec `F9` ouvert côté serveur et côté client, refaire : §1.2 à §1.5, §2.1, §2.3, un seul achat du §3 (`FolioSmall`, avec le compte secondaire), §5.1 à §5.5, puis §6 bis.2, §6 bis.16 et §6 bis.26 (réglage de streaming de la place publiée), et §11.3 (le mode du garde de mouvement, et le streaming et les signaux qu'il lit sur la place publiée). Tout KO ici déclenche le §9 de `docs/PUBLISH.md`.
