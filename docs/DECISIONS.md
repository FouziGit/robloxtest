# Journal des décisions

Format : **D-n — Titre** · Phase · Décision · Raison (deux lignes).

---

**D-1 — Langue des documents et du code** · Phase 0
Docs (`docs/`, `README.md`, `CLAUDE.md`) en français ; identifiants, commentaires de code et clés de localisation en anglais ; textes joueur EN par défaut + FR via `Strings`.
Raison : le propriétaire lit le français, les conventions Luau/outillage sont anglophones, et Roblox sert un public majoritairement anglophone.

**D-2 — Branche `main`** · Phase 0
Renommage de `master` en `main` (local + GitHub, branche par défaut mise à jour).
Raison : la mission impose `git push origin main` ; un seul commit existait, renommer est sans risque.

**D-3 — Toolchain via rokit, versions épinglées** · Phase 0
`rokit.toml` : rojo 7.7.0, wally 0.3.2, selene 0.31.0, StyLua 2.5.2, luau-lsp 1.69.0, lune 0.10.5. rokit 1.2.0 installé via le script officiel (`~/.rokit/bin`), absent de Homebrew.
Raison : versions résolues et testées localement le 2026-09-16 ; épingler garantit la reproductibilité CI/local.

**D-4 — ProfileStore vendoré depuis la source officielle, pas depuis Wally** · Phase 0
`src/server/Vendor/ProfileStore.luau` = copie exacte de `MadStudioRoblox/ProfileStore@45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31, 2242 lignes), SHA noté en tête de fichier. Aucune modification locale.
Raison : loleris ne publie pas ProfileStore sur Wally ; les seuls paquets (`ddashdev`, `goset33`, `b1ntran`…) sont des forks non audités (le mieux noté diffère de 662 lignes de l'original). Une source officielle épinglée est plus sûre qu'un fork inconnu.

**D-5 — Dépendances Wally** · Phase 0
`evaera/promise@4.0.0`, `sleitnick/signal@2.0.3`, `sleitnick/trove@1.8.0`. Existence vérifiée sur le registre le 2026-09-16.
Raison : bibliothèques standard de l'écosystème, maintenues, typées ; Trove préféré à Janitor pour son API plus petite et sa compatibilité Signal.

**D-6 — Tests : harnais Lune maison, modules purs sans `require`** · Phase 0
Pas de Jest-Lua ni TestEZ. `tests/harness.luau` fournit `describe / it / expect` (toBe, toEqual, toBeCloseTo, toThrow, toBeTruthy…) et `tests/run.luau` découvre `tests/**/*.spec.luau`. Les modules purs (`ComboResolver`, `Elo`, `MatchmakingCore`, `QuestLogic`, `DataMigration`, `ReceiptProcessor`, `Strings`) n'ont aucun `require` ni global Roblox et sont chargés par chemin relatif.
Raison : les paquets Wally (TestEZ, Jest-Lua, Promise…) utilisent `require(script.Parent…)` et ne se chargent pas sous Lune sans darklua ; un harnais de 150 lignes évite une chaîne de build supplémentaire. Vérifié : `lune run` + `require("../src/…")` fonctionne (probe du 2026-09-16).

**D-17 — Les statuts de combat sont des attributs de Humanoid avec leur propre expiration** · Phase 2
`Fanned`, `Conductive` et `StoneSkin` sont écrits par `CombatService` comme attributs portant un horodatage `os.clock` serveur, relus paresseusement dans `ApplyDamage` (aucun ticker, aucune boucle par joueur) et effacés à la réapparition. L'ordre est : marque élémentaire → réduction StoneSkin → garde, avec un seul arrondi final.
Raison : une file de timers par statut et par joueur coûterait plus cher que la lecture ponctuelle, et les attributs sont lisibles par le client pour l'affichage. Attention : la valeur est une horloge serveur, jamais comparable à `os.clock()` côté client.

**D-18 — Prison d'Eau immobilise par un ralentissement à 0, pas par un stun** · Phase 2
`WaterPrison` applique `applySlow(Def.Id, 0, 1.5)` au lieu de `applyStun`.
Raison : la cible reste capable de lancer un jutsu et de se défendre — c'est un contrôle de position, pas un silence ; un stun de 1,5 s serait au-dessus du budget d'étourdissement du genre.

**D-19 — LightningStep téléporte côté serveur après validation par raycast** · Phase 2
Le serveur lance un rayon sur `Def.Range`, recule de `WallBackoffStuds`, vérifie `ClearanceRadius` et raccroche au sol sur `GroundSnapStuds`, puis écrit le pivot du personnage. `MovementCommand` n'a pas de type « Teleport ».
Raison : un déplacement instantané confié au client serait un téléport arbitraire ; la validation serveur garantit qu'on ne traverse ni mur ni vide, et le pivot écrit une seule fois est immédiatement répliqué.

**D-20 — Une manche redémarre sur un personnage neuf** · Phase 4
`MatchService` fait `LoadCharacterAsync` entre les manches plutôt que de réinitialiser l'état de combat en place.
Raison : `CombatService` n'expose pas de remise à zéro complète (chakra, statuts, mémoire d'i-frames, protection de spawn) ; recharger le personnage réutilise le chemin `CharacterAdded` déjà testé et garantit qu'aucun statut ne fuit d'une manche à l'autre.

**D-21 — Le PvP du hub est désactivé dès qu'un match existe** · Phase 4
`MatchService.setPolicy` remplace la policy par défaut : seuls les participants d'un même match se blessent. Les joueurs du hub ne peuvent donc plus se frapper entre eux (les mannequins restent frappables).
Raison : le hub est une zone sociale et d'entraînement ; le PvP libre y ouvrait le harcèlement au spawn, et le combat classé se joue en arène.

**D-22 — Pas de spectateur : un joueur éliminé attend au hub** · Phase 4
Un participant éliminé en cours de manche est renvoyé au hub et re-téléporté à la manche suivante ; il n'y a ni caméra spectateur ni fantôme.
Raison : un système de spectateur demande sa propre caméra, sa propre UI et ses propres règles anti-triche ; hors périmètre de la V2, et les manches durent moins d'une minute.

**D-23 — `applyFreeze` est distinct de `applyStun`** · Phase 4
`applyStun` reste plafonné par `CombatConfig.Hit.StunMaxSeconds` (2 s) pour le combat ; `applyFreeze` n'est pas plafonné et sert aux pauses scriptées décidées par le serveur (compte à rebours, fin de match).
Raison : avec le seul `applyStun`, un compte à rebours de 5 s devait être ré-appliqué à chaque tick, ce qui envoyait un `MovementCommand` par tick et par joueur.

**D-24 — Un achat Robux de cosmétique nomme l'article, pas le produit** · Phase 7
Les developer products cosmétiques sont génériques par rareté ; le client envoie donc `PromptPurchase("Cosmetic", cosmeticId)` et le serveur enregistre l'intention (`ShopService.setPurchaseIntent`) avant d'ouvrir le prompt du produit correspondant.
Raison : sans cette intention, un produit « cosmétique épique » ne dit pas *lequel* accorder ; et faire envoyer un ID de produit par le client rouvrirait la porte à l'achat d'un article non sélectionné.

**D-25 — Le matchmaking se met en pause pendant un World Boss** · Phase 7
`CombatService` n'a qu'un seul emplacement de policy PvP. `WorldBossService` l'emprunte pour la durée de l'événement et la rend ensuite ; `MatchmakingService` refuse donc de former un match tant que `WorldBoss.isLive()` (les joueurs restent en file, leur minuteur continue).
Raison : c'est le plus petit changement qui supprime le conflit, et un match formé pendant l'événement perdrait le PvP entre participants. Une pile de policies serait plus générale mais plus risquée pour un gain nul en V2.

**D-26 — Un seul écrivain par section de profil** · Phase 7
`Cosmetics.Owned` n'est écrit que par `CosmeticService`, `Daily` que par `DailyRewardService`, `Loadout`/`Unlocks` que par `LoadoutService`. Le battle pass et les matchs appellent ces services au lieu d'écrire la table.
Raison : le battle pass insérait directement dans `Cosmetics.Owned`, ce qui contournait le signal que la boutique écoute pour rafraîchir la possession ; et le bonus de première victoire était dupliqué entre `MatchService` et le service qui possède la série quotidienne.

**D-27 — Le boost d'XP est un vrai champ de profil** · Phase 7
La récompense « boost » du battle pass et le produit Robux écrivent `Boosts.XpUntil` / `XpMultiplier` ; `ProgressionService` applique le multiplicateur à chaque gain.
Raison : la V1 du battle pass payait un montant d'XP équivalent faute de champ — un contournement visible pour le joueur (pas de boost, juste de l'XP) et impossible à cumuler avec le VIP.

**D-7 — luau-lsp avec définitions Roblox téléchargées** · Phase 0
`scripts/setup.sh` télécharge `globalTypes.d.luau` depuis le dépôt luau-lsp (fichier ignoré par git) ; `.luau-lsp.json` déclare les alias. L'analyse stricte bloquante porte sur `src/shared` (gate), le reste est analysé en mode avertissement.
Raison : sans définitions, `luau-lsp analyze` ne connaît pas `game`, `Instance`, etc. ; limiter le gate strict à `shared` (modules purs + config) garde la CI fiable pendant la migration.

**D-8 — Le sprint V1 est remplacé par le dash** · Phase 1
Plus de sprint/endurance côté client : le kit V2 (M1, dash avec i-frames, garde) le remplace ; la vitesse de marche est fixée par le serveur (`MovementService`).
Raison : le sprint client-autoritaire était l'exploit n°1 de l'audit et n'existe pas dans le genre battlegrounds ; le dash apporte la mobilité attendue sans laisser le client écrire `WalkSpeed`.

**D-9 — Les effets de jutsus sont livrés directement dans l'architecture cible** · Phase 1
Le serveur ne fait que la détection de coups (overlaps / raycasts pas à pas / parts de collision invisibles) et diffuse des paquets `Vfx` ; chaque client rend via `VfxLibrary`. Le chakra (`CombatConfig`) est introduit en même temps.
Raison : réécrire les effets deux fois (Parts serveur en Phase 1 puis client en Phase 2) aurait doublé le travail sans valeur intermédiaire ; le plan Phase 1/2 est fusionné sur ce point.

**D-10 — Dash et knockback appliqués par le client propriétaire de la physique** · Phase 1
Le serveur décide (cooldown, chakra, i-frames, cible) puis envoie `MovementCommand` ; le client applique la vitesse sur son `HumanoidRootPart`.
Raison : sur Roblox, le personnage est simulé par le client propriétaire : une vitesse écrite par le serveur est écrasée en une frame (constat de l'audit). La décision reste serveur : il valide, débite le chakra, arme la recharge et envoie l'ordre. Le déplacement qu'il demande est ajouté à la provision de trajet du joueur (D-32), donc un dash légitime ne ressemble jamais à une téléportation.

**D-11 — Touches par défaut J / K / L / H / U, menu M, garde F, dash Maj gauche** · Phase 1
`InputConfig.DefaultKeyboard` évite WASD (QWERTY), ZQSD (AZERTY), Espace, Tab, Échap, I/O (zoom) et les chiffres (backpack) ; la liste blanche de rebind exclut ces mêmes touches.
Raison : résout le bug « A = strafe » sans dépendre de la disposition du clavier du joueur.

**D-12 — CI : rokit installé par le script officiel, pas par une action tierce** · Phase 1
`ci.yml` et `publish.yml` installent rokit via `install.sh` puis `rokit install --no-trust-check`.
Raison : aucune action GitHub officielle maintenue par rojo-rbx ; le script est la voie documentée et reste alignée sur `rokit.toml`.

**D-13 — Les i-frames du dash sont accordées sur la seule décision serveur** · Phase 1
Le serveur accorde 0,25 s d'invulnérabilité au moment où il valide le dash, sans observer le déplacement (le personnage est simulé par le client propriétaire, D-10). Un client qui ignore `MovementCommand` garde donc les i-frames sans bouger.
Raison : le déplacement du dash lui-même n'est pas observable (D-10), donc ce qui borne l'esquive est son coût en chakra et sa recharge. En revanche l'**origine** de chaque attaque est désormais validée (D-32) : un client qui ignore `MovementCommand` garde ses i-frames sans bouger, mais il ne peut plus frapper depuis une position que le serveur n'a pas crue.

**D-14 — Les ralentissements sont indexés par clé** · Phase 1
`MovementService.applySlow(player, key, factor, seconds)` / `clearSlow(player, key?)` : le facteur effectif est le minimum des entrées vivantes. La garde utilise la clé `"Block"`, chaque jutsu utilise son `Id`.
Raison : une seule valeur globale permettait de « nettoyer » le ralentissement d'un jutsu adverse en tapant la garde une fraction de seconde.

**D-15 — La zone sûre du hub est symétrique** · Phase 1
Un joueur à l'intérieur de la zone sûre ne peut ni subir ni infliger de dégâts PvP (avant : il était seulement protégé).
Raison : la protection à sens unique faisait de la zone un poste de tir imprenable. Les PNJ (mannequins, boss) restent frappables depuis la zone.

**D-16 — Les rejets de rate limit ne comptent pas comme triche** · Phase 1
`RemoteRegistry` distingue `"Schema"` (payload malformé → seuil `GameConfig.Server.AbuseKickThreshold`, 25) de `"RateLimit"` (débit trop élevé → seuil `RateLimitKickThreshold`, 600). Le client limite en plus ses propres envois au rythme que le serveur accepte.
Raison : un joueur qui martèle le clic gauche dépassait le budget de jetons et se faisait éjecter pour triche ; les deux compteurs ne s'additionnent jamais.

**D-28 — Chaque événement de quête a exactement un producteur, vérifié par un test** · Phase 8
`QuestConfig.Pool` nommait onze événements ; trois n'étaient émis par personne (`DamageDealt`, `MeleeHit`, `Dash`). `CombatService` expose désormais `Damaged` et `Dashed` à côté de `Killed`, et `QuestService` s'y abonne. `tests/QuestEvents.spec.luau` exige un appel `report…("Event")` dans `src/server` pour chaque événement du pool.
Raison : quatre quêtes sur treize restaient bloquées à zéro pour toujours. `QuestLogic.select` tire trois quêtes quotidiennes parmi huit, donc la plupart des journées contenaient une quête impossible et le joueur perdait la récompense sans explication. Le test empêche qu'une quête ajoutée plus tard reparte avec le même défaut.

**D-29 — `RankingService` accorde le cosmétique de fin de saison via `CosmeticService`** · Phase 8
La récompense de saison faisait un `table.insert` direct dans `Cosmetics.Owned`. Elle passe maintenant par `CosmeticService.grant`, comme le battle pass et le pack de skins.
Raison : c'était le dernier contournement de D-26. Il sautait la validation de l'identifiant contre `CosmeticConfig` (un identifiant erroné dans `RankingConfig` était écrit dans le profil pour toujours) et le signal `Granted` que la boutique écoute, donc l'article restait affiché comme achetable jusqu'au prochain rafraîchissement.

**D-30 — Le multiplicateur de boost d'XP est dans la config, et `Boosts` n'a qu'un écrivain** · Phase 8
`ProgressionConfig.XpBoostMultiplier` remplace les deux constantes `2` qui vivaient dans `BattlepassService` et dans `Receipts`. Le produit Robux « XpBoost » appelle `BattlepassService.grantXpBoost` au lieu de réécrire la section lui-même.
Raison : deux sources de vérité pour le même chiffre. Changer l'une faisait silencieusement diverger le boost payé du boost offert par le pass, et la logique « prolonger sans raccourcir » était dupliquée à l'identique aux deux endroits.

**D-31 — Les sections `Rank`, `Stats`, `Loadout` et `Meta` gardent deux écrivains, sur des champs disjoints** · Phase 8
`DataService` écrit la remise à zéro de saison (`Rank.SeasonId`, `Rank.Modes`) et les champs de session de `Meta` ; `RankingService` écrit les classements, `MonetizationService` écrit `Loadout.ExtraSlots` (droit lié au pass) et `Meta.FirstSessionPromptGate`, et chaque service de jeu incrémente son propre compteur dans `Stats`.
Raison : D-26 existe pour les sections qui portent un effet de bord (un signal, une validation, une règle métier). Ces quatre-là sont des sacs de champs indépendants, sans signal ni invariant croisé : un accesseur par champ ajouterait de l'indirection sans supprimer un seul risque. `Stats` n'est lu par aucun système de récompense, donc frapper un mannequin et tuer un joueur peuvent partager le compteur `Kills` sans ouvrir d'exploit.

**D-32 — L'origine d'une attaque est mesurée, jamais crue ; on la recale au lieu d'éjecter** · Phase 8
`CombatService.trustedCFrame` compare la position répliquée par le client à la dernière que le serveur a acceptée. Si l'écart dépasse `GameConfig.Latency.MaxSpeedStudsPerSecond × temps écoulé + OriginToleranceStuds`, l'action a lieu quand même mais ancrée sur la dernière position crue : l'attaquant frappe dans le vide. Les déplacements décidés par le serveur (dash, knockback) ajoutent leur distance à la provision pendant leur durée plus `AllowanceGraceSeconds` ; les téléportations serveur (spawn de match, retour au hub, placement boss, LightningStep) appellent `resyncPosition`. L'échantillonnage par tick ne frappe jamais l'anti-triche ; seule une action choisie le fait, après `ViolationsBeforeStrike` origines invraisemblables d'affilée.
Raison : le personnage est simulé par le client propriétaire, donc `root.CFrame` valait ce que le client voulait : il suffisait de se placer sur l'adversaire, d'envoyer `CombatAction("Melee")` et de revenir pour poser tout le combo depuis n'importe où dans l'arène. La config qui devait borner cela existait depuis la Phase 1 et n'était lue par personne. Le recalage plutôt que le rejet est délibéré : il annule entièrement le gain de la triche sans punir une mauvaise connexion. Et l'éjection est réservée aux actions, parce qu'une longue chute dépasse le plafond de vitesse et aurait éjecté des joueurs honnêtes.

**D-33 — Un abandon en classé est débité à la sortie, via `DataService.BeforeRelease`** · Phase 8
`DataService` émet `BeforeRelease` pendant que le profil du partant est encore chargé ; `MatchService` y débite le forfait avec le même calcul Elo qu'une défaite réelle, et `applyResult` saute ensuite ce joueur. `RankingService` mémorise par session la dernière note vue pour chaque identifiant, donc l'équipe adverse est notée contre l'adversaire réel et non contre un débutant.
Raison : `applyResult` sautait tout participant sans `Player` vivant, et un partant est exactement ce cas. Quitter ne coûtait donc rien : pas de note perdue, pas de défaite comptée. Quitter était strictement meilleur que perdre, une note ne pouvait que monter, et deux comptes qui se relayaient pour partir se hissaient mutuellement dans le classement.

**D-34 — Un forfait ne renverse pas une série déjà gagnée** · Phase 8
`Pure/SeriesOutcome` décide : une équipe qui a déjà atteint `RoundsToWin` garde sa victoire quoi qu'il arrive ensuite, sinon le forfait donne la série à l'équipe encore debout, et le score de celle-ci est relevé juste au-dessus du meilleur autre score.
Raison : le code relevait le survivant à `RoundsToWin` sans condition, ce qui transformait un 2-0 abandonné entre deux manches en 2-2 : `scoreWinner` y voyait une égalité et payait un match nul aux deux camps, y compris à celui qui avait gagné toutes les manches. Le relèvement conditionnel garde l'écran de résultat cohérent, car il suppose que le vainqueur détient le score le plus élevé.

**D-35 — Les trois bandeaux du haut de l'écran sont une seule colonne** · Phase 8
`HudController` possède une colonne centrée en haut avec un `UIListLayout` ; le bandeau de match, celui du World Boss et la file de toasts en sont les enfants, ordonnés état persistant d'abord, messages éphémères ensuite. Le bandeau du boss abandonne son propre `ScreenGui`.
Raison : les trois déclaraient le même ancrage et la même position. Le toast de manche gagnée masquait la manche, le score et le compte à rebours dans chaque match classé, et pendant un événement le bandeau du boss (420 px) recouvrait celui du match (360 px). Deux `ScreenGui` de même `DisplayOrder` n'ont pas d'ordre de dessin défini.

**D-36 — La régénération intègre le temps réel écoulé** · Phase 8
Chakra et vie multipliaient leur taux par la durée nominale du tick. Elles multiplient maintenant par l'intervalle réellement écoulé depuis le tick précédent.
Raison : l'accumulateur ne déclenche qu'un tick par image et jette le reste, donc sous la fréquence configurée le jeu versait silencieusement moins que ce que la config promet. Les taux sont par seconde : intégrer sur l'intervalle réel les rend indépendants du nombre d'images par seconde.
