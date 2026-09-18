# Architecture et contrats d'API

Référence des modules et de leurs interfaces. Toute implémentation (humaine ou agent) respecte ces signatures ; une modification de contrat passe par ce fichier d'abord. Conventions générales : `CLAUDE.md`. Plan : `docs/PLAN.md`.

## Arbre Rojo (`default.project.json`)

| Source | Cible Studio |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/ui` | `ReplicatedStorage.UI` |
| `Packages` (wally) | `ReplicatedStorage.Packages` (`Promise`, `Signal`, `Trove`) |
| `src/server` | `ServerScriptService` |
| `src/client` | `StarterPlayer.StarterPlayerScripts` |

Requires : `local Shared = ReplicatedStorage:WaitForChild("Shared")` puis `require(Shared.Config.X)`, `require(Shared.Util.X)`, `require(Shared.Pure.X)`. Côté serveur, modules frères via `require(script.Parent.X)`.

## Modules partagés (`src/shared`)

| Module | Rôle | API |
|---|---|---|
| `Types` | types (`ProfileData`, `JutsuDef`, `HitEvent`, …) | types uniquement |
| `Config/*` | données pures (aucun require, aucun global Roblox) | `ElementConfig`, `InputConfig`, `GameConfig`, `ProgressionConfig`, `JutsuConfig`, `CombatConfig`, `BattlepassConfig`, `SoundConfig` |
| `Strings` | localisation | `Strings.t(key, params?, locale?)`, `Strings.has(key)`, `Strings.localeFromId(localeId)` |
| `Remotes` | registre typé des remotes | `Remotes.Definitions[name] = {Kind, Direction, Args?, Rate?}`, `Remotes.FolderName` |
| `Util/Guard` | validation | `Guard.check(schema, value) -> (ok, reason?)` |
| `Util/TokenBucket` | rate limit | `new(capacity, refill, now)`, `tryTake(bucket, now, cost?)` |
| `Util/Log` | logs préfixés | `Log.new(prefix) -> {info, warn, error, try}` |
| `Pure/ComboResolver` | combos | `new(recipes, maxLength)`, `push(resolver, seq, element) -> (seq, decision)`, `timeout(resolver, seq)`, `resolve(resolver, seq) -> jutsuId?` |
| `Pure/DataMigration` | schéma | `migrate(raw, template, seasonId) -> (data, info)` |

## Remotes (`src/shared/Remotes.luau`)

Client → serveur (Guard + token bucket, abus → `AntiCheatService.strike`) :

| Nom | Args | Handler |
|---|---|---|
| `CastJutsu` | `{ElementId}` (2..4) | `JutsuService` |
| `CombatAction` | `"Melee" \| "Dash" \| "BlockStart" \| "BlockEnd"` | `CombatService` | `setPolicy(fn) -> Policy?` (retourne la policy remplacée, pour qu'un propriétaire temporaire la rende) ; `ApplyDamage(source, targetModel, amount, kind, tags, element?) -> {Applied, Killed, Blocked}` (UNIQUE chemin de dégâts : policy PvP et zone sûre symétrique, protection de spawn, i-frames par tag, marques élémentaires de `CombatConfig.Status` — l'élément pose sa propre marque et lit celle qui l'amplifie —, réduction StoneSkin, garde, stun, arrondi unique à la fin) ; `grantIFrames(player, seconds)`, `applyStoneSkin(player) -> bool`, `knockback(targetModel, velocity, duration)` (sans effet sur une cible StoneSkin), `getState(player)`, `trySpendChakra(player, cost) -> bool`, `isBlocking(player)`, `isStunned(player)`, `setPolicy(fn)` ; handlers `CombatAction` (M1, dash, garde) ; tick `Heartbeat` centralisé ; signal `Killed(sourceUserId, victimModel)` |
| `UpdateKeybinds` | `"Keyboard" \| "Gamepad"`, `{[ActionId]: keyName}` | `SettingsService` |
| `UpdateSettings` | `{MusicVolume, SfxVolume, CameraShake}` | `SettingsService` |
| `ClaimBattlepassReward` | `tier (1..50)`, `"Free" \| "Premium"` | `BattlepassService` |
| `RequestProfile` (fonction) | — | `DataService` (snapshot) |
| `JoinQueue` | `MatchModeId` | `MatchmakingService` |
| `LeaveQueue` | — | `MatchmakingService` |
| `RequestLeaderboard` (fonction) | `boardId` | `LeaderboardService` |
| `ClaimQuest` | `"Daily" \| "Weekly"`, `questId` | `QuestService` |
| `ClaimDaily` | — | `DailyRewardService` |
| `SetLoadout` | `{jutsuId}` (≤ 10) | `LoadoutService` |
| `EquipCosmetic` | `slotKey`, `cosmeticId` (`""` = retirer) | `CosmeticService` |
| `BuyCosmetic` | `cosmeticId` (achat en Ryo) | `ShopService` |
| `PromptPurchase` | `"Pass" \| "Product"`, `clé du catalogue` | `MonetizationService` (le client n'envoie jamais d'ID Roblox) |

Serveur → client :

| Nom | Payload |
|---|---|
| `ProfileChanged` | `(section: string \| "*", value)` — section = clé de premier niveau de `ProfileData` |
| `Notify` | `{Key: string, Params: table?, Kind: "Info" \| "Success" \| "Error", Sfx: string?}` — le client localise |
| `Vfx` (unreliable) / `VfxReliable` | `{Id, Origin: Vector3, Direction: Vector3, Caster: number?, Targets: {Vector3}?, Params: table?}` |
| `CombatState` (unreliable) | `{Chakra, MaxChakra, Health, MaxHealth, InCombat, Blocking, Cooldowns: {[jutsuId]: secondsLeft}}` |
| `MovementCommand` | `{Kind="Dash", Direction, Distance, Duration} \| {Kind="Knockback", Velocity, Duration} \| {Kind="Stun", Seconds}` |
| `QueueChanged` | `Types.QueueSnapshot` — état de file du joueur (`Queued = false` quand il n'est dans aucune) |
| `MatchChanged` | `Types.MatchSnapshot` (ou `nil` à la fin du match) — poussé quelques fois par seconde aux participants |
| `MatchEnded` | `Types.MatchOutcome` — résumé unique avant le retour au hub |
| `BossChanged` | `Types.BossSnapshot` (ou `nil` hors événement) — diffusé à tout le serveur |
| `ShopChanged` | `Types.ShopSnapshot` — rotation du jour avec la possession résolue pour le destinataire |

## Serveur (`src/server`)

`Bootstrap.server.luau` : crée le `RemoteRegistry` (reporter = `AntiCheatService.strike`), `Init(deps)` de chaque service dans l'ordre des dépendances, puis `Start()` de chacun. `deps` est une table nommée : `{Registry, DataService, Notify, AntiCheat, Progression, Currency, Battlepass, Settings, Combat, Jutsu, Effects, Vfx, Movement, Enemy}` (chaque service ne lit que ce qu'il déclare).

| Service | API publique |
|---|---|
| `RemoteRegistry` | `create(reporter) -> {on(name, handler), setCallback(name, fn), fire(name, player, ...), fireAll(name, ...), fireExcept(name, player, ...), get(name), removePlayer(player)}` ; `reporter(player, remoteName, reason, kind)` avec `kind = "Schema"` (direction, arité ou payload refusé par Guard) ou `"RateLimit"` (débordement du token bucket) — les deux ne partagent jamais le même compteur |
| `DataService` | `template()`, `get(player) -> ProfileData?` (table vivante), `waitFor(player, timeout?)`, `snapshot(player)`, `push(player, section \| "*")`, `recordReceipt(player, id) -> bool`, `saveNow(player)`, `isActive(player)`, signaux `ProfileLoaded(player, data)`, `ProfileReleased(player)` |
| `AntiCheatService` | `strike(player, source, reason, kind: "Schema" \| "RateLimit"?)` — un compteur et un seuil par `kind` dans `AbuseWindowSeconds` : `Schema` (défaut) kick à `GameConfig.Server.AbuseKickThreshold`, `RateLimit` à son propre seuil, bien plus haut (une rafale d'input légitime en produit) ; `Init`, `Start` |
| `NotifyService` | `send(player, key, params?, kind?, sfx?)`, `sendAll(key, params?, kind?, sfx?)` |
| `CurrencyService` | `get(player) -> number`, `add(player, amount, reason) -> number` (retourne le Ryo réellement crédité ; multiplicateur VIP), `trySpend(player, amount, reason) -> bool` ; pousse `Currency` |
| `ProgressionService` | `addXp(player, amount, reason) -> number` (retourne l'XP réellement créditée ; multiplicateur VIP × boost temporaire `Boosts.XpUntil`, niveaux en cascade, XP de pass via Battlepass, leaderstats `Level`/`Ryo`), `getLevel(player)`, signal `LevelUp(player, level)` ; pousse `Progression` |
| `BattlepassService` | `addXp(player, amount)`, `addTiers(player, count) -> number`, `grantXpBoost(player, minutes)`, `claim(player, tier, track)`, `isPremium(player)`, `setPremium(player, value)` ; pousse `Battlepass` ; les cosmétiques passent par `CosmeticService.grant` |
| `SettingsService` | handlers `UpdateKeybinds` / `UpdateSettings` (whitelists `InputConfig.Allowed*`, `Rebindable`, sans doublon) ; pousse `Settings` ; `Notify settings.saved` |
| `MovementService` | applique `GameConfig.Movement` au spawn ; `applySlow(player, key, factor, seconds)` (ralentissements indexés par source : facteur effectif = minimum des entrées vivantes), `clearSlow(player, key?)` (une source, ou toutes si `key == nil`), `applyStun(player, seconds)`, `isStunned(player)` (attributs `CombatConfig.Status.*` sur le Humanoid) ; `command(player, payload)` → `MovementCommand` |
| `CombatService` | `ApplyDamage(source: Player?, targetModel: Model, amount, kind: DamageKind, tags: {string}, element: string?) -> {Applied: number, Killed: boolean, Blocked: boolean}` (UNIQUE chemin de dégâts : PvP policy symétrique — la zone sûre protège ET interdit de frapper —, protection de spawn, i-frames par tag, garde, stun ; `element` colore le paquet `Hit`) ; `getState(player) -> {Chakra, MaxChakra, InCombat, Blocking, Stunned}`, `trySpendChakra(player, cost) -> bool`, `setPolicy(fn(source, targetModel) -> bool)` ; handlers `CombatAction` (M1 combo, dash, block) ; tick `Heartbeat` centralisé (régén chakra/vie, timers, `CombatState` à 5 Hz) ; signal `Killed(sourceUserId, victimModel)` |
| `JutsuService` | handler `CastJutsu` : profil chargé → vivant, non stun, non en garde → `ComboResolver.resolve` → débloqué + dans le loadout → cooldown → chakra → origine/direction depuis le `HumanoidRootPart` → `JutsuEffects[def.Effect](ctx)` → XP si ≥ 1 touche → stats → `Notify` ; `getCooldowns(player)` |
| `JutsuEffects` | `[effectId] = function(ctx) -> hitCount` avec `ctx = {Caster, Def, Origin, Direction, Combat, Vfx, Movement}` ; détection serveur uniquement, aucun visuel ; un effet peut demander un déplacement via `Movement.command` (dash d'EmberStep) ou déplacer le lanceur lui-même après validation par raycast (téléport de LightningStep) ; chaque paquet porte `Id = Def.VfxId` et `Params.Element = Def.Element` |
| `VfxBroadcaster` | `emit(packet, reliable?)` (tous les clients à moins de `GameConfig.Vfx.BroadcastRadiusStuds`), `emitTo(player, packet, reliable?)` |
| `HubService` | construit le hub en code sous `workspace.Hub`, idempotent (plateforme, `HubSpawn` unique, zone d'entraînement alignée sur la zone sûre, `QueueTerminal`, `LeaderboardBoard_<board>`, `ShopKiosk`) ; `getSpawn() -> BasePart`, `getLeaderboardEntries(boardId) -> Frame?`, `teleportToHub(player)` (8 emplacements en anneau, vitesse remise à zéro) ; aucun panneau serveur ne porte de texte (non localisable), les libellés sont côté client |
| `ArenaService` | gabarits dans `ServerStorage.ArenaTemplates`, arènes vivantes dans `workspace.Arenas` ; `acquire(arenaId) -> Arena?` (`{Instance, Id, SlotIndex, Spawns: {{BasePart}}, KillZone}`, `nil` journalisé si l'id est inconnu), `release(arena)` idempotent par emplacement ; emplacements verticaux globaux espacés de `MatchConfig.ArenaSpacingStuds` |
| `GameModes/*` | interface `GameMode` : `Id`, `CanStart(userIds) -> bool`, `Start(match)`, `RoundVerdict(match, now) -> Verdict?` (conditions de victoire de la manche), `OnPlayerLeft(match, player)`, `End(match) -> MatchResult` ; `Duel1v1` (best of 3), `Team3v3` (manche unique) |
| `MatchmakingService` | files par mode via `Pure/MatchmakingCore` (fenêtre de rating élargie), handlers `JoinQueue` / `LeaveQueue`, tick `MatchConfig.Matchmaking.TickSeconds`, pousse `QueueChanged`, remet en file les joueurs d'un match avorté |
| `MatchService` | cycle de vie : arène, téléport, compte à rebours, manches, conditions de victoire, abandons, récompenses, retour au hub, cleanup Trove ; `isInMatch(player)`, `getMatch(player)` ; pousse `MatchChanged` / `MatchEnded` ; installe la policy PvP de `CombatService` (seuls les participants se blessent) |
| `RankingService` | `getRating(player, modeId)`, `applyResult(result)` via `Pure/Elo` + `Pure/RankTiers` (K dégressif, bornes, saison) ; pousse `Rank` ; signal `RatingChanged(player, modeId, before, after)` |
| `LeaderboardService` | `OrderedDataStore` par saison et par board, rafraîchi toutes les `RankingConfig.Leaderboard.RefreshSeconds` avec budget d'écriture respecté ; `getBoard(boardId) -> LeaderboardSnapshot`, handler `RequestLeaderboard`, affichage sur les `SurfaceGui` du hub |
| `QuestService` | quêtes journalières/hebdomadaires via `Pure/QuestLogic` (sélection déterministe par période) ; `report(player, event, amount)` (appelé par JutsuService, MatchService, CombatService, EnemyService, WorldBossService), `getActive(player)`, handler `ClaimQuest` ; pousse `Quests` |
| `DailyRewardService` | unique propriétaire de `Daily` : streak de connexion (`Pure/DailyStreak`), `markFirstWin(player)`, `grantPremiumBonus(player)`, handler `ClaimDaily` ; pousse `Daily` |
| `LoadoutService` | unique propriétaire de `Loadout` et `Unlocks` : débloque les jutsus au niveau et par élément, `grantElement(player, elementId)`, handler `SetLoadout` (slots, doublons, déblocages validés) |
| `CosmeticService` | unique **écrivain** de `Cosmetics.Owned` : `grant(player, cosmeticId) -> bool` (idempotent), signal `Granted(player, cosmeticId)`, handler `EquipCosmetic` ; publie l'équipement sur le personnage en attributs `CosmeticAura` / `CosmeticTrail` / `CosmeticKillEffect` / `CosmeticTitle` |
| `ShopService` | rotation quotidienne via `Pure/ShopRotation` ; handler `BuyCosmetic` (Ryo), `setPurchaseIntent(player, cosmeticId) -> (productKey?, reasonKey?)` / `consumePurchaseIntent(player)` pour le chemin Robux, `getSnapshot(player)` ; pousse `ShopChanged` |
| `MonetizationService` | seul module à parler à `MarketplaceService` : validation des IDs au démarrage (un `warn` par ID manquant), ownership des passes en cache, `ProcessReceipt` idempotent via `Pure/ReceiptProcessor`, handler `PromptPurchase` (`"Pass"` / `"Product"` / `"Cosmetic"` — le client nomme toujours une entrée de catalogue), `maybePrompt(player, reason)` pour les prompts contextuels |
| `AnalyticsService` | enveloppe limitée en débit d'`AnalyticsService` Roblox : `economy`, `funnel`, `progression`, `custom` ; silencieuse quand le service est indisponible |
| `WorldBossService` | événement périodique (`WorldBossConfig`) : annonce, arène Boss, PV mis à l'échelle, phases, attaques télégraphiées, récompenses à la contribution ; `isLive()` ; emprunte la policy PvP de `CombatService` et la rend à la fin |
| `EnemyService` | mannequins (`GameConfig.Enemy`), tag `Enemy`, crédit du tueur via l'attribut `LastAttackerUserId` posé par `CombatService`, XP/Ryo `DummyKill`, respawn |

## Client (`src/client`)

`Bootstrap.client.luau` : trois passes distinctes sur l'ordre `ClientData`, `Localize`, `SoundController`, `VfxController`, `HudController`, `MenuController`, `InputController`, `ComboController`, `CombatController`, `MovementController`.

1. `require` de tous les modules : `deps` est complet et l'état construit au chargement (Signals, table d'état par défaut) existe pour tous avant le premier `Init`.
2. `Init(deps)` de chacun : peut référencer n'importe quel contrôleur, quel que soit son rang, et le stocker ; ne dépend d'aucun autre `Init`.
3. `Start()` de chacun : peut se connecter à n'importe quel Signal et appeler tout accesseur qui ne lit que l'état de chargement (garantis par la passe 1, à tout rang) ; ne pilote un comportement installé par un autre `Start` (handlers de remote, bindings d'input, widgets construits) que si ce contrôleur est listé avant.

L'ordre exprime donc la disponibilité du comportement installé par `Start`, pas les dépendances d'`Init` : ajouter une dépendance entre contrôleurs ne demande aucun réordonnancement.

| Contrôleur | API |
|---|---|
| `RemoteClient` | `get(name)`, `fire(name, ...)`, `on(name, handler)`, `invoke(name, timeout, ...) -> (ok, ...)` |
| `Controllers/ClientData` | `get() -> ProfileData?`, `waitForLoad()`, signaux `Loaded`, `Changed(section)` |
| `Controllers/Localize` | `t(key, params?)` (locale via `LocalizationService.RobloxLocaleId`), `locale()` |
| `Controllers/InputController` | `ContextActionService` : clavier (+ souris), manette, tactile (boutons colorés par élément, haptique ; layout résolu en pixels écran à partir de `InputConfig.Touch` — anneau d'éléments au-dessus et à gauche du bouton de saut du moteur, rangée Melee/Block/Dash à sa gauche, Menu en haut à droite, distance minimale entre centres = diamètre + gap, recalculé si le viewport change ou si le bouton de saut apparaît ; diamètre planché à `InputConfig.Touch.MinButtonSize` = 44 px réels, libellés courts `InputConfig.ActionShortKeys` pour tenir dans le disque) ; signal `Action(actionId, began: boolean)` ; `captureNext(kind, callback)` / `cancelCapture()` pour le rebind (suspend les actions ; annulation par `InputConfig.CaptureCancelKeys` (Échap, `ButtonA` en manette — aucune n'est assignable, un test l'exige) ou le menu Roblox → `callback(nil)`) ; `setSuspended(bool)`, `isSuspended()`, signal `SuspendedChanged(bool)` (menus) ; `rebuild()` après changement de `Settings` |
| `Controllers/ComboController` | consomme `Action` des 5 éléments, `ComboResolver`, timeout `GameConfig.Combo.TimeoutSeconds`, `RemoteClient.fire("CastJutsu", seq)` ; signal `SequenceChanged(seq)` pour le HUD |
| `Controllers/CombatController` | `Melee` / `Dash` / `Block` → `CombatAction`, throttlé sur l'intervalle d'acceptation du serveur (`CombatConfig.Melee.HitIntervalSeconds`, `CombatConfig.Dash.CooldownSeconds`, garde coalescée sur les vrais changements d'état) pour qu'un joueur légitime ne déborde jamais le token bucket ; état local depuis `CombatState` ; signal `StateChanged(state)` |
| `Controllers/MovementController` | double saut (front d'appui, `GameConfig.Movement`), applique `MovementCommand` (dash, knockback, stun = verrou d'entrée) |
| `Controllers/HudController` | barres vie/chakra/niveau, pastilles de combo, toasts (`Notify` localisé + `Sfx`), rappel du menu (clé selon `UserInputService:GetLastInputType()` : manette → `Settings.Gamepad`, clavier/souris → `Settings.Keyboard`, tactile → masqué) ; en tactile les barres vie/chakra passent en bas-centre au-dessus de la rangée de combo pour libérer le stick du moteur |
| `Controllers/VfxController` + `VfxLibrary` | rend `Vfx`/`VfxReliable` par `Id` (particules, beams, tweens, camera shake selon `Settings.CameraShake`, hit-stop) ; `VfxLibrary[id] = function(packet, trove, api)` avec `api = {Sound, Shake(intensity), HitStop(seconds), ElementColor(element), LocalCharacter()}` ; durée de vie max `GameConfig.Vfx.LifetimeSeconds`. Un **seul** `Heartbeat` client anime tous les effets vivants (ouvert au premier, fermé au dernier) ; un effet dont le centre dépasse `GameConfig.Vfx.AnimateRadiusStuds` du personnage local n'est pas animé, ce rayon couvrant les deux arènes PvP en entier |
| `Controllers/SoundController` | `play(sfxId, position?)`, musique, volumes depuis `Settings` |
| `Controllers/MatchController` | file (`JoinQueue`/`LeaveQueue`), état depuis `QueueChanged` / `MatchChanged` / `MatchEnded` ; signaux `QueueChanged(snapshot)`, `MatchChanged(snapshot?)`, `MatchEnded(outcome)` ; pilote le HUD de match et l'écran de résultat |
| `Controllers/BossController` | bandeau d'événement World Boss (PV, phase, temps, contribution, alerte de télégraphe) depuis `BossChanged` ; possède son propre `ScreenRoot` |
| `Controllers/MenuController` | ouvre/ferme les écrans (`Menu`, `Settings`, `Battlepass`, `Play`, `Result`, `Leaderboard`, `Quests`, `Daily`, `Loadout`, `Shop`), suspend `InputController`, écrans depuis `UI/screens` |

## UI (`src/ui`)

`Theme` : couleurs, polices, tailles, `elementColor(id)`, `scaleFor(viewport)` et `activeScale()`. Il possède aussi trois choses que les composants ne doivent plus deviner :

- `Theme.Layers` — ordre de dessin des `ScreenGui` (`Hud`, `Screen`, `Result`, espacés de dix). Deux `ScreenGui` de même `DisplayOrder` n'ont pas d'ordre défini sur Roblox, donc chaque calque a sa valeur. Le bandeau du World Boss n'y figure pas : il est enfant de la colonne du HUD (D-35).
- `Theme.MinTouchTarget` (44) et `Theme.minPixelSize(objet, pixels)` — plancher exprimé en pixels **réels**, posé comme `UISizeConstraint` de valeur `pixels / activeScale()` et rafraîchi quand le viewport change. Sans lui, l'`UIScale` du `ScreenRoot` (0,68 sur un téléphone 812x375) réduisait chaque cible sous le minimum tactile.
- `Theme.touchTargetHeight(hauteurDesign)` — la hauteur qu'une cible planchée occupe réellement. Tout bandeau construit autour d'une cible (barre de titre, en-têtes, pieds de panneau, rangées de battle pass) se mesure là-dessus, sinon relever le plancher pousserait un bouton à travers son en-tête.

Composants dans `src/ui/components`, chacun `new(props) -> {Instance, Destroy(), …}` et nettoyé par Trove :

| Composant | Props principales |
|---|---|
| `ScreenRoot` | `Name` → `ScreenGui` (`ResetOnSpawn=false`, `IgnoreGuiInset=true`) + `UIScale` (Theme) + marge safe-area |
| `Panel` | `Title`, `Size`, `Closable` → cadre centré avec `UIAspectRatioConstraint` optionnel ; `CloseButton`, `FocusForGamepad(target?)` / `ReleaseGamepadFocus()` (sélection manette prise à l'Open, rendue au Close) |
| `Button` | `Text`, `Variant ("Primary" \| "Secondary" \| "Danger")`, `OnClick`, `Disabled` |
| `ProgressBar` | `Color`, `SetProgress(0..1)`, `SetLabel(text)` |
| `Tabs` | `Items = {{Id, Text}}`, `OnSelect(id)` |
| `ListRow` | `Left`, `Right` (instances ou textes) |
| `Slider` | `Min`, `Max`, `Value`, `OnChange` |
| `Toggle` | `Value`, `OnChange` |
| `Toast` | file d'attente de messages `Show(text, kind)` |
| `TouchButton` | `Label`, `Color`, `Position` → bouton rond pour `ContextActionService` |

Écrans dans `src/ui/screens` : `MenuScreen`, `SettingsScreen`, `BattlepassScreen` (Phase 1), puis `LoadoutScreen`, `ShopScreen`, `LeaderboardScreen`, `QuestsScreen`, `MatchScreen`.

## Règles transverses

- Chaque changement de profil : muter `DataService.get(player)` puis `DataService.push(player, section)` (y compris après un rejet, pour que le client sorte de son état « en cours »).
- Tags de dégâts des jutsus : `{Def.Id, Def.Archetype}` — `tags[1]` sert de clé d'i-frames, l'archétype permet `CombatConfig.Block.BrokenBy`.
- Aucun texte joueur hors `Strings` ; ajouter une clé = ajouter `en` + `fr` (test `Strings.spec`).
- Aucune boucle par joueur. Chaque service qui a besoin d'un tick ouvre **un seul** `Heartbeat`, jamais un par joueur : `CombatService`, `MovementService`, `MatchService`, `MatchmakingService`, `QuestService`, `ShopService`, `LeaderboardService`, `WorldBossService` (avec accumulateur) et `VfxBroadcaster` (qui s'en sert seulement pour invalider son instantané de destinataires une fois par image), soit neuf au total. Côté client il y en a deux, ouvertes à la demande et refermées ensuite : la secousse d'écran de `VfxController` et le ticker unique de `VfxLibrary`.
- La régénération n'utilise jamais la durée nominale du tick : l'accumulateur ne déclenche qu'une fois par image et jette le reste, donc les taux par seconde s'intègrent sur l'intervalle réellement écoulé (D-36).
- Toute erreur attrapée est journalisée avec contexte (`Log`).

## Budgets mesurés (12 joueurs, le maximum documenté)

Les limites Roblox sont par serveur : `60 + 10 × joueurs` requêtes/minute pour la famille écriture et lecture d'un DataStore, `5 + 2 × joueurs` pour `GetSortedAsync`.

| Opération | Pire cas | Budget | Occupation |
|---|---|---|---|
| Sauvegarde automatique ProfileStore | 2,4 /min | 180 | 1 % |
| Classement `SetAsync` (12 joueurs × 3 tableaux, 1 écriture / 30 s par clé) | 72 /min | 180 | 40 % |
| `GetSortedAsync` (3 tableaux, 1 / 60 s) | 3 /min | 29 | 10 % |
| `GetAsync` récompense de saison + import V1 (à la connexion) | 24 en rafale | 180 | — |

Le pire cas du classement suppose que les douze joueurs changent de score toutes les trente secondes sur les trois tableaux, ce qu'un match de plusieurs minutes ne produit jamais. La pression réelle est très inférieure. `RankingConfig.Leaderboard.MinWriteIntervalSeconds` (30 s) est le paramètre qui borne cette ligne : le diviser par deux doublerait l'occupation.

Le tick serveur le plus chargé est celui de `CombatService` : une requête spatiale par joueur en combat et par tick, pas par frame. `MatchmakingService` scanne ses files toutes les `MatchConfig.Matchmaking.TickSeconds`, et se met en pause pendant un World Boss (D-25).
