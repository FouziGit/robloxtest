# Jutsu Battlegrounds

Battleground PvP Roblox où les jutsus se lancent en **tapant des séquences de touches élémentaires**. `J J` = Boule de Feu, `K K L` = Mur de Boue, `L L L` = Séisme. Le fun vient de la vitesse d'exécution, de la mémorisation des combos et des mind games — pas des statistiques.

Modes : hub d'entraînement, **1v1 classé**, **3v3**, **World Boss**. Mobile, manette et clavier. Anglais par défaut, français inclus.

---

## Démarrer en 10 minutes

```bash
# 1. Installer rokit (gestionnaire d'outils)
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash

# 2. Cloner et installer (rojo, wally, selene, stylua, luau-lsp, lune + paquets + types Roblox)
git clone https://github.com/FouziGit/robloxtest.git jutsu-battlegrounds
cd jutsu-battlegrounds
./scripts/setup.sh

# 3. Vérifier que tout est vert
./scripts/check.sh

# 4. Construire la place et l'ouvrir dans Studio
rojo build default.project.json -o build/JutsuBattlegrounds.rbxl
open build/JutsuBattlegrounds.rbxl
```

Puis **Play**. C'est tout. Le fichier construit contient déjà le serveur, le client, l'interface et les paquets : aucun plugin, aucune connexion, rien qui puisse échouer. À reconstruire après chaque modification du code.

Pour développer avec la synchronisation en direct : `rojo serve default.project.json`, plugin Rojo (`rojo plugin install`), onglet **Plugins → Rojo → Connect**. Attention, la synchronisation n'atteint que la place ouverte **et** connectée. Si Play affiche des mannequins sans aucune interface, c'est ça : voir le dépannage dans [docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md#8-dépannage).

Pour que les sauvegardes fonctionnent : publier la place et cocher *Game Settings → Security → Enable Studio Access to API Services*. Détails et checklist complète (game passes, developer products, secrets CI) : **[docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md)**.

---

## Comment jouer

| Action | Clavier | Manette | Tactile |
|---|---|---|---|
| Feu / Eau / Terre / Vent | `J` `K` `L` `H` | D-pad | boutons colorés |
| Foudre (niveau 40 ou pass) | `U` | `Y` | bouton jaune |
| Corps à corps | clic gauche | `X` | bouton |
| Dash (i-frames) | Maj gauche | `B` | bouton |
| Garde | `F` | `LT` | maintenir |
| Menu | `M` | `Select` | bouton |
| Double saut | Espace ×2 | `A` ×2 | bouton saut |

Toutes les touches sont réassignables (clavier **et** manette) dans les Options. Aucune touche par défaut n'entre en conflit avec WASD (QWERTY) ou ZQSD (AZERTY).

Le **chakra** (100, régénération plus lente en combat) est la vraie limite au spam ; les cooldowns empêchent la répétition d'un même jutsu. Design complet : **[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)**.

---

## Architecture

```
                   CLIENT (src/client)                         SERVEUR (src/server)
  ┌──────────────────────────────────────┐        ┌─────────────────────────────────────────┐
  │ InputController  clavier/manette/    │        │ Bootstrap.server.luau                   │
  │                  tactile (CAS)       │        │   crée les remotes, injecte les deps,   │
  │        │ Action(actionId, began)     │        │   Init() puis Start() chaque service    │
  │        ▼                             │        │                                         │
  │ ComboController  ComboResolver       │        │ RemoteRegistry                          │
  │        │                             │        │   Guard (schémas) + token bucket        │
  │        └── CastJutsu ────────────────┼───────▶│   + AntiCheat (strikes → kick)          │
  │ CombatController ── CombatAction ────┼───────▶│        │                                │
  │                                      │        │        ▼                                │
  │ ClientData   ◀── ProfileChanged ─────┼────────│ JutsuService ──▶ JutsuEffects            │
  │   (copie unique du profil)           │        │   (résout, vérifie chakra/cooldown/     │
  │        │                             │        │    unlock/loadout, origine serveur)     │
  │        ▼                             │        │        │                                │
  │ HudController / MenuController       │        │        ▼                                │
  │   src/ui (Theme + composants)        │        │ CombatService.ApplyDamage  ← UNIQUE     │
  │                                      │        │   PvP policy, spawn protection,         │
  │ VfxController ◀── Vfx / VfxReliable ─┼────────│   i-frames, garde, stun, knockback      │
  │   VfxLibrary (particules, shake,     │        │        │                                │
  │   hit-stop) — le serveur n'affiche   │        │        ▼                                │
  │   AUCUN visuel                       │        │ Progression / Currency / Battlepass     │
  │                                      │        │        │                                │
  │ MovementController ◀ MovementCommand─┼────────│ MovementService (WalkSpeed serveur)     │
  └──────────────────────────────────────┘        │        ▼                                │
                                                  │ DataService ──▶ ProfileStore ──▶ DataStore
                                                  │   1 profil / joueur, verrou de session, │
                                                  │   migration V1→V2 versionnée            │
                                                  └─────────────────────────────────────────┘
                  PARTAGÉ (src/shared) : Config/*, Strings (EN/FR), Remotes typés,
                  Util/{Guard,TokenBucket,Log}, Pure/* (modules sans Roblox, testés sous Lune)
```

Principes non négociables (détail : [CLAUDE.md](CLAUDE.md), contrats : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)) :

- **Serveur autoritaire.** Le client n'envoie que des *intentions* (séquence d'éléments, Melee/Dash/Block). Origine, direction, dégâts, ressources, récompenses : serveur.
- **Un seul chemin de dégâts** : `CombatService.ApplyDamage`.
- **Le serveur ne construit aucun VFX** : il diffuse `{Id, Origin, Direction, Params}` et chaque client rend localement.
- **Zéro chaîne joueur en dur** : tout passe par `Strings` (test bloquant en CI).
- **Modules purs testables** : `ComboResolver`, `Elo`, `RankTiers`, `MatchmakingCore`, `SeriesOutcome`, `QuestLogic`, `DailyStreak`, `ReceiptProcessor`, `ReceiptItem`, `ShopRotation`, `DataMigration` — aucun `require`, aucun global Roblox, testés sous Lune. Toute décision qui touche au classement ou à un paiement vit là et a ses tests.

---

## Ajouter du contenu

### Un jutsu

1. Une entrée dans `src/shared/Config/JutsuConfig.luau` (`Id`, `Element`, `Combo`, `Cost`, `Cooldown`, `Damage`, `Range`, `Archetype`, `Effect`, `VfxId`, `SfxId`, `Unlock`, `NameKey`, `DescriptionKey`, `Params`).
2. La fonction d'effet correspondante dans `src/server/Effects/JutsuEffects.luau` : `function(ctx) -> hitCount`, dégâts **uniquement** via `ctx.Combat.ApplyDamage`, aucun visuel.
3. Le rendu dans `src/client/Controllers/VfxLibrary.luau`, indexé par `VfxId`.
4. Les clés `jutsu.<Id>.name` / `.desc` dans `src/shared/Strings.luau` (EN + FR).

Le résolveur de combo, la validation serveur, les cooldowns, l'XP et le HUD suivent automatiquement. `tests/Config.spec.luau` vérifie l'unicité des combos et la présence des clés.

### Un mode de jeu

Une entrée dans `src/shared/Config/MatchConfig.luau` + un module implémentant l'interface `GameMode` (`CanStart`, `Start`, `OnPlayerLeft`, `End`) dans `src/server/GameModes/`. Le matchmaking et le cycle de match sont génériques.

### Un produit monétisé

Une entrée dans `src/shared/Config/MonetizationConfig.luau` (l'ID Roblox est le **seul** endroit où coller un identifiant). Le serveur `warn` au démarrage pour chaque ID resté à `0`. Prix et placement des prompts : **[docs/ECONOMY.md](docs/ECONOMY.md)**.

### Une traduction

Ajouter `en` + `fr` à la clé dans `src/shared/Strings.luau`, puis `lune run scripts/export-strings` pour régénérer `localization.csv` (importable dans le portail de localisation Roblox). La CI échoue si le CSV n'est pas à jour ou si une chaîne joueur est écrite en dur.

---

## Qualité

`./scripts/check.sh` enchaîne les portes bloquantes, identiques à la CI GitHub :

| Porte | Commande |
|---|---|
| Format | `stylua --check src tests` |
| Lint | `selene src tests` |
| Types (strict sur `src/shared`) | `luau-lsp analyze …` |
| Tests | `lune run tests/run` |
| Chaînes en dur | `lune run scripts/check-strings` |
| Localisation à jour | `lune run scripts/export-strings -- --check` |
| Build | `rojo build default.project.json -o build/JutsuBattlegrounds.rbxl` |

105 tests sur 18 fichiers de spécification. Cinq d'entre eux ne testent pas du code mais des invariants que rien d'autre ne peut attraper : aucun global Roblox dans les modules purs, aucune clé de localisation morte ni manquante, un producteur serveur pour chaque événement de quête, aucune touche d'annulation qui soit aussi assignable, et le coût borné d'une charge utile rejetée.

---

## Documentation

| Document | Contenu |
|---|---|
| [CLAUDE.md](CLAUDE.md) | conventions de code, structure, git |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | contrats d'API de chaque module et remote |
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | roster, combos, interactions, modes, arènes |
| [docs/ECONOMY.md](docs/ECONOMY.md) | prix, flux de Ryo, prompts, KPIs, DevEx |
| [docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md) | checklist manuelle Studio / Creator Dashboard |
| [docs/AUDIT.md](docs/AUDIT.md) | audit de la V1 (68 constats) |
| [docs/PLAN.md](docs/PLAN.md) · [docs/PROGRESS.md](docs/PROGRESS.md) · [docs/DECISIONS.md](docs/DECISIONS.md) | feuille de route, état, décisions |
