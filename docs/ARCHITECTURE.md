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
| `CombatAction` | `"Melee" \| "Dash" \| "BlockStart" \| "BlockEnd"` | `CombatService` |
| `UpdateKeybinds` | `"Keyboard" \| "Gamepad"`, `{[ActionId]: keyName}` | `SettingsService` |
| `UpdateSettings` | `{MusicVolume, SfxVolume, CameraShake}` | `SettingsService` |
| `ClaimBattlepassReward` | `tier (1..50)`, `"Free" \| "Premium"` | `BattlepassService` |
| `RequestProfile` (fonction) | — | `DataService` (snapshot) |

Serveur → client :

| Nom | Payload |
|---|---|
| `ProfileChanged` | `(section: string \| "*", value)` — section = clé de premier niveau de `ProfileData` |
| `Notify` | `{Key: string, Params: table?, Kind: "Info" \| "Success" \| "Error", Sfx: string?}` — le client localise |
| `Vfx` (unreliable) / `VfxReliable` | `{Id, Origin: Vector3, Direction: Vector3, Caster: number?, Targets: {Vector3}?, Params: table?}` |
| `CombatState` (unreliable) | `{Chakra, MaxChakra, Health, MaxHealth, InCombat, Blocking, Cooldowns: {[jutsuId]: secondsLeft}}` |
| `MovementCommand` | `{Kind="Dash", Direction, Distance, Duration} \| {Kind="Knockback", Velocity, Duration} \| {Kind="Stun", Seconds}` |

## Serveur (`src/server`)

`Bootstrap.server.luau` : crée le `RemoteRegistry` (reporter = `AntiCheatService.strike`), `Init(deps)` de chaque service dans l'ordre des dépendances, puis `Start()` de chacun. `deps` est une table nommée : `{Registry, DataService, Notify, AntiCheat, Progression, Currency, Battlepass, Settings, Combat, Jutsu, Effects, Vfx, Movement, Enemy}` (chaque service ne lit que ce qu'il déclare).

| Service | API publique |
|---|---|
| `RemoteRegistry` | `create(reporter) -> {on(name, handler), setCallback(name, fn), fire(name, player, ...), fireAll(name, ...), fireExcept(name, player, ...), get(name), removePlayer(player)}` ; `reporter(player, remoteName, reason, kind)` avec `kind = "Schema"` (direction, arité ou payload refusé par Guard) ou `"RateLimit"` (débordement du token bucket) — les deux ne partagent jamais le même compteur |
| `DataService` | `template()`, `get(player) -> ProfileData?` (table vivante), `waitFor(player, timeout?)`, `snapshot(player)`, `push(player, section \| "*")`, `recordReceipt(player, id) -> bool`, `saveNow(player)`, `isActive(player)`, signaux `ProfileLoaded(player, data)`, `ProfileReleased(player)` |
| `AntiCheatService` | `strike(player, source, reason, kind: "Schema" \| "RateLimit"?)` — un compteur et un seuil par `kind` dans `AbuseWindowSeconds` : `Schema` (défaut) kick à `GameConfig.Server.AbuseKickThreshold`, `RateLimit` à son propre seuil, bien plus haut (une rafale d'input légitime en produit) ; `Init`, `Start` |
| `NotifyService` | `send(player, key, params?, kind?, sfx?)`, `sendAll(key, params?, kind?, sfx?)` |
| `CurrencyService` | `get(player) -> number`, `add(player, amount, reason)`, `trySpend(player, amount, reason) -> bool` ; pousse `Currency` |
| `ProgressionService` | `addXp(player, amount, reason)` (niveaux en cascade, XP de pass via Battlepass, leaderstats `Level`/`Ryo`), `getLevel(player)`, signal `LevelUp(player, level)` ; pousse `Progression` |
| `BattlepassService` | `addXp(player, amount)`, `claim(player, tier, track)`, `isPremium(player)`, `setPremium(player, value)` ; pousse `Battlepass` |
| `SettingsService` | handlers `UpdateKeybinds` / `UpdateSettings` (whitelists `InputConfig.Allowed*`, `Rebindable`, sans doublon) ; pousse `Settings` ; `Notify settings.saved` |
| `MovementService` | applique `GameConfig.Movement` au spawn ; `applySlow(player, key, factor, seconds)` (ralentissements indexés par source : facteur effectif = minimum des entrées vivantes), `clearSlow(player, key?)` (une source, ou toutes si `key == nil`), `applyStun(player, seconds)`, `isStunned(player)` (attributs `CombatConfig.Status.*` sur le Humanoid) ; `command(player, payload)` → `MovementCommand` |
| `CombatService` | `ApplyDamage(source: Player?, targetModel: Model, amount, kind: DamageKind, tags: {string}, element: string?) -> {Applied: number, Killed: boolean, Blocked: boolean}` (UNIQUE chemin de dégâts : PvP policy symétrique — la zone sûre protège ET interdit de frapper —, protection de spawn, i-frames par tag, garde, stun ; `element` colore le paquet `Hit`) ; `getState(player) -> {Chakra, MaxChakra, InCombat, Blocking, Stunned}`, `trySpendChakra(player, cost) -> bool`, `setPolicy(fn(source, targetModel) -> bool)` ; handlers `CombatAction` (M1 combo, dash, block) ; tick `Heartbeat` centralisé (régén chakra/vie, timers, `CombatState` à 5 Hz) ; signal `Killed(sourceUserId, victimModel)` |
| `JutsuService` | handler `CastJutsu` : profil chargé → vivant, non stun, non en garde → `ComboResolver.resolve` → débloqué + dans le loadout → cooldown → chakra → origine/direction depuis le `HumanoidRootPart` → `JutsuEffects[def.Effect](ctx)` → XP si ≥ 1 touche → stats → `Notify` ; `getCooldowns(player)` |
| `JutsuEffects` | `[effectId] = function(ctx) -> hitCount` avec `ctx = {Caster: Player, Def: JutsuDef, Origin: CFrame, Direction: Vector3, Combat: CombatService, Vfx: VfxBroadcaster, Movement: MovementService}` ; détection serveur uniquement (`GetPartBoundsInRadius/Box`, raycasts pas à pas pour les projectiles, parts de collision invisibles pour les murs) ; aucun visuel ; paquets Vfx émis sous `def.VfxId` avec `Params.Element = def.Element` ; les effets minutés s'arrêtent dès que le lanceur meurt, quitte, passe en garde ou est stun |
| `VfxBroadcaster` | `emit(packet, reliable?)` (tous les clients à moins de `GameConfig.Vfx.BroadcastRadiusStuds`), `emitTo(player, packet, reliable?)` |
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
| `Controllers/InputController` | `ContextActionService` : clavier (+ souris), manette, tactile (boutons colorés par élément, haptique ; layout résolu en pixels écran à partir de `InputConfig.Touch` — anneau d'éléments au-dessus et à gauche du bouton de saut du moteur, rangée Melee/Block/Dash à sa gauche, Menu en haut à droite, distance minimale entre centres = diamètre + gap, recalculé si le viewport change ou si le bouton de saut apparaît) ; signal `Action(actionId, began: boolean)` ; `captureNext(kind, callback)` / `cancelCapture()` pour le rebind (suspend les actions ; annulation par Échap, `ButtonB` en manette ou le menu Roblox → `callback(nil)`) ; `setSuspended(bool)`, `isSuspended()`, signal `SuspendedChanged(bool)` (menus) ; `rebuild()` après changement de `Settings` |
| `Controllers/ComboController` | consomme `Action` des 5 éléments, `ComboResolver`, timeout `GameConfig.Combo.TimeoutSeconds`, `RemoteClient.fire("CastJutsu", seq)` ; signal `SequenceChanged(seq)` pour le HUD |
| `Controllers/CombatController` | `Melee` / `Dash` / `Block` → `CombatAction`, throttlé sur l'intervalle d'acceptation du serveur (`CombatConfig.Melee.HitIntervalSeconds`, `CombatConfig.Dash.CooldownSeconds`, garde coalescée sur les vrais changements d'état) pour qu'un joueur légitime ne déborde jamais le token bucket ; état local depuis `CombatState` ; signal `StateChanged(state)` |
| `Controllers/MovementController` | double saut (front d'appui, `GameConfig.Movement`), applique `MovementCommand` (dash, knockback, stun = verrou d'entrée) |
| `Controllers/HudController` | barres vie/chakra/niveau, pastilles de combo, toasts (`Notify` localisé + `Sfx`), rappel du menu (clé selon `UserInputService:GetLastInputType()` : manette → `Settings.Gamepad`, clavier/souris → `Settings.Keyboard`, tactile → masqué) ; en tactile les barres vie/chakra passent en bas-centre au-dessus de la rangée de combo pour libérer le stick du moteur |
| `Controllers/VfxController` + `VfxLibrary` | rend `Vfx`/`VfxReliable` par `Id` (particules, beams, tweens, camera shake selon `Settings.CameraShake`, hit-stop) ; `VfxLibrary[id] = function(packet, trove, api)` avec `api = {Sound, Shake(intensity), HitStop(seconds), ElementColor(element), LocalCharacter()}` ; durée de vie max `GameConfig.Vfx.LifetimeSeconds` |
| `Controllers/SoundController` | `play(sfxId, position?)`, musique, volumes depuis `Settings` |
| `Controllers/MenuController` | ouvre/ferme les écrans (`Menu`, `Settings`, `Battlepass`), suspend `InputController`, écrans depuis `UI/screens` |

## UI (`src/ui`)

`Theme` (couleurs, polices, tailles, `scaleFor(viewport)`, `elementColor(id)`). Composants dans `src/ui/components`, chacun `new(props) -> {Instance, Destroy(), …}` et nettoyé par Trove :

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
- Aucune boucle par joueur ; `CombatService` possède l'unique `Heartbeat` de gameplay.
- Toute erreur attrapée est journalisée avec contexte (`Log`).
