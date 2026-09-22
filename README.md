# Vellum

Battleground PvP Roblox où les glyphes se lancent en **tapant des séquences de touches de pigment**. `J J` = Marque, `K K L` = Marge, `L L L` = Rupture. Le fun vient de la vitesse d'exécution, de la mémorisation des combos et des mind games — pas des statistiques.

Modes : hub d'entraînement, **1v1 classé**, **3v3**, **World Boss**. Mobile, manette et clavier. Anglais par défaut, français inclus.

**À quoi ça ressemble.** Le monde est une page : vélin, charbon, rien de saturé dans le décor. La seule
couleur vive à l'écran est un glyphe, et sa couleur est son école — Cinabre, Indigo, Terre d'Ombre,
Vert-de-gris, Orpiment. Un pouvoir ne sort pas d'un personnage, il **se dessine** ; un impact blanchit
l'écran comme une page surexposée et laisse une brûlure d'encre qui s'efface. Le sol garde vos pas.
Direction complète : **[docs/ART_BIBLE.md](docs/ART_BIBLE.md)**.

---

## Démarrer en 10 minutes

```bash
# 1. Installer rokit (gestionnaire d'outils)
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash

# 2. Cloner et installer (rojo, wally, selene, stylua, luau-lsp, lune + paquets + types Roblox)
git clone https://github.com/FouziGit/robloxtest.git glyph-battlegrounds
cd glyph-battlegrounds
./scripts/setup.sh

# 3. Vérifier que tout est vert
./scripts/check.sh

# 4. Construire la place et l'ouvrir dans Studio
rojo build default.project.json -o build/Vellum.rbxl
open build/Vellum.rbxl
```

Puis **Play**. C'est tout. Le fichier construit contient déjà le serveur, le client, l'interface et les paquets : aucun plugin, aucune connexion, rien qui puisse échouer. À reconstruire après chaque modification du code.

Pour développer avec la synchronisation en direct : `rojo serve default.project.json`, plugin Rojo (`rojo plugin install`), onglet **Plugins → Rojo → Connect**. Attention, la synchronisation n'atteint que la place ouverte **et** connectée. Si Play affiche des mannequins sans aucune interface, c'est ça : voir le dépannage dans [docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md#8-dépannage).

Pour que les sauvegardes fonctionnent : publier la place et cocher *Game Settings → Security → Enable Studio Access to API Services*. Détails et checklist complète (game passes, developer products, secrets CI) : **[docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md)**.

---

## Comment jouer

| Action | Clavier | Manette | Tactile |
|---|---|---|---|
| Cinabre / Indigo / Terre d'Ombre / Vert-de-gris | `J` `K` `L` `H` | D-pad | boutons colorés |
| Orpiment (niveau 40 ou pass) | `U` | `Y` | bouton jaune |
| Corps à corps | clic gauche | `X` | bouton |
| Dash (i-frames) | Maj gauche | `B` | bouton |
| Garde | `F` | `LT` | maintenir |
| Menu | `M` | `Select` | bouton |
| Double saut | Espace ×2 | `A` ×2 | bouton saut |

Toutes les touches sont réassignables (clavier **et** manette) dans les Options. Aucune touche par défaut n'entre en conflit avec WASD (QWERTY) ou ZQSD (AZERTY).

L'**encre** (100, régénération plus lente en combat) est la vraie limite au spam ; les cooldowns empêchent la répétition d'un même glyph.

Deux règles portent le plafond de compétence, et les deux se paient en encre : une **ruée pendant la
récupération** du 4ᵉ coup de mêlée la coupe net (15 encre en plus), et deux glyphes lancés en moins d'une
seconde sont un **enchaînement** qui rend 5 encre — le HUD compte la chaîne (`×N`) et le profil garde la
plus longue. Chaque glyphe a une réponse explicite : la matrice outil → contre est dans le design.

Les options ont un onglet **Graphismes** à quatre niveaux ; le client descend d'un niveau tout seul quand
les images par seconde tombent, et le rend quand elles remontent (**[docs/PERFORMANCE.md](docs/PERFORMANCE.md)**).

Design complet : **[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)**.

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
  │        └── CastGlyph ────────────────┼───────▶│   + AntiCheat (strikes → kick)          │
  │ CombatController ── CombatAction ────┼───────▶│        │                                │
  │                                      │        │        ▼                                │
  │ ClientData   ◀── ProfileChanged ─────┼────────│ GlyphService ──▶ GlyphEffects            │
  │   (copie unique du profil)           │        │   (résout, vérifie encre/cooldown/     │
  │        │                             │        │    unlock/loadout, origine serveur)     │
  │        ▼                             │        │        │                                │
  │ HudController / MenuController       │        │        ▼                                │
  │   src/ui (Theme + composants)        │        │ CombatService.ApplyDamage  ← UNIQUE     │
  │                                      │        │   PvP policy, spawn protection,         │
  │ VfxController ◀── Vfx / VfxReliable ─┼────────│   i-frames, garde, stun, knockback      │
  │   VfxLibrary → VfxTimeline (une      │        │        │                                │
  │   boucle pour toutes les couches de  │        │        ▼                                │
  │   tous les effets) + VfxPool         │        │ Progression / Currency / Battlepass     │
  │   Feel (caméra, hit-stop, secousses) │        │        │                                │
  │   WorldLighting (post-traitement)    │        │        │                                │
  │   QualityController (ce que ce       │        │        │                                │
  │   client a le droit de dessiner)     │        │        │                                │
  │   — le serveur n'affiche AUCUN visuel│        │        │                                │
  │                                      │        │        │                                │
  │ MovementController ◀ MovementCommand─┼────────│ MovementService (WalkSpeed serveur)     │
  └──────────────────────────────────────┘        │        ▼                                │
                                                  │ DataService ──▶ ProfileStore ──▶ DataStore
                                                  │   1 profil / joueur, verrou de session, │
                                                  │   migration V1→V3 versionnée            │
                                                  └─────────────────────────────────────────┘
                  PARTAGÉ (src/shared) : Config/*, Strings (EN/FR), Remotes typés,
                  Util/{Guard,TokenBucket,Log}, Pure/* (modules sans Roblox, testés sous Lune)
```

Principes non négociables (détail : [CLAUDE.md](CLAUDE.md), contrats : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)) :

- **Serveur autoritaire.** Le client n'envoie que des *intentions* (séquence de pigments, Melee/Dash/Block). Origine, direction, dégâts, ressources, récompenses : serveur.
- **Un seul chemin de dégâts** : `CombatService.ApplyDamage`.
- **Le serveur ne construit aucun VFX** : il diffuse `{Id, Origin, Direction, Params}` et chaque client rend localement.
- **Zéro chaîne joueur en dur** : tout passe par `Strings` (test bloquant en CI).
- **Modules purs testables** : `ComboResolver`, `Elo`, `RankTiers`, `MatchmakingCore`, `SeriesOutcome`, `OriginGuard`, `QuestLogic`, `DailyStreak`, `ReceiptProcessor`, `ReceiptItem`, `ShopRotation`, `DataMigration` — aucun `require`, aucun global Roblox, testés sous Lune. Toute décision qui touche au classement, à un paiement ou à la validation d'une position vit là et a ses tests.

---

## Ajouter du contenu

### Un glyph

1. Une entrée dans `src/shared/Config/GlyphConfig.luau` (`Id`, `Pigment`, `Combo`, `Cost`, `Cooldown`, `Damage`, `Range`, `Archetype`, `Effect`, `VfxId`, `Unlock`, `NameKey`, `DescriptionKey`, `Params`). Le son du glyphe est celui de son pigment, par les couches `Sound` de sa timeline (`docs/VFX_SPECS.md`).
2. La fonction d'effet correspondante dans `src/server/Effects/GlyphEffects.luau` : `function(ctx) -> hitCount`, dégâts **uniquement** via `ctx.Combat.ApplyDamage`, aucun visuel.
3. Le rendu dans `src/client/Controllers/VfxLibrary.luau`, indexé par `VfxId`.
4. Les clés `glyph.<Id>.name` / `.desc` dans `src/shared/Strings.luau` (EN + FR).

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
| Types (strict sur tout `src`) | `luau-lsp analyze …` |
| Tests | `lune run tests/run` |
| Chaînes en dur | `lune run scripts/check-strings` |
| Localisation à jour | `lune run scripts/export-strings -- --check` |
| Textures reproductibles | `python3 tools/textures/generate_all.py` + `git diff --quiet` |
| Portée d'encre des textures | `python3 tools/textures/check_ink.py` |
| Audio reproductible | `python3 tools/audio/generate_all.py` + `git diff --quiet` |
| Build | `rojo build default.project.json -o build/Vellum.rbxl` |

338 tests sur 38 fichiers de spécification. Une bonne part d'entre eux ne testent pas du code mais des
invariants que rien d'autre ne peut attraper : aucun global Roblox dans les modules purs, aucune clé de
localisation morte ni manquante, un producteur serveur pour chaque événement de quête, la caméra écrite par
un seul module, aucune couleur ni police hors du thème, le décor jamais saturé, la figure du boss qui
remplit la coque où elle prend les coups, le coût de chaque effet sous des plafonds **dérivés** d'autres
nombres du dépôt, et une seule boucle par image et par système. Chaque porte ajoutée a été vue échouer sur
le défaut qu'elle garde, réintroduit exprès.

---

## Documentation

| Document | Contenu |
|---|---|
| [CLAUDE.md](CLAUDE.md) | conventions de code, structure, git |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | contrats d'API de chaque module et remote |
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | roster, combos, interactions, modes, arènes |
| [docs/ECONOMY.md](docs/ECONOMY.md) | prix, flux de Folios, prompts, KPIs, DevEx |
| [docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md) | checklist manuelle Studio / Creator Dashboard |
| [docs/ART_BIBLE.md](docs/ART_BIBLE.md) | l'identité : palette, formes, lumière, son, lexique, les huit règles non négociables |
| [docs/VFX_SPECS.md](docs/VFX_SPECS.md) | une fiche par effet : ce qu'il doit faire sentir, ce qu'il a remplacé, comment il est construit |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | niveaux graphiques, dégradation automatique, coût calculé de chaque effet, pooling |
| [docs/ASSETS.md](docs/ASSETS.md) | chaque texture et chaque son, son générateur et sa licence |
| [docs/AUDIT.md](docs/AUDIT.md) · [docs/JUICE_AUDIT.md](docs/JUICE_AUDIT.md) | audit de la V1 (68 constats) et audit du game feel qui a lancé la passe d'identité |
| [docs/JUICE_PLAN.md](docs/JUICE_PLAN.md) | le plan en neuf passes de cette identité |
| [docs/PLAN.md](docs/PLAN.md) · [docs/PROGRESS.md](docs/PROGRESS.md) · [docs/DECISIONS.md](docs/DECISIONS.md) | feuille de route, état, décisions |
