# Configuration manuelle dans Roblox Studio

Tout ce que le code ne peut pas faire à ta place. À faire une fois, dans l'ordre. Les identifiants obtenus se collent **uniquement** dans `src/shared/Config/MonetizationConfig.luau` ; au démarrage, le serveur affiche un `warn` par identifiant encore à `0`.

## Le plus rapide : ouvrir le fichier construit

Deux façons d'avoir le jeu dans Studio. La première ne peut pas échouer et ne demande aucun plugin.

**A. Fichier construit (recommandé pour juste jouer).**

```bash
./scripts/check.sh && open build/JutsuBattlegrounds.rbxl
```

`rojo build` écrit un fichier de place complet : serveur, client, interface et paquets sont déjà dedans. Studio l'ouvre comme n'importe quelle place, et **Play** fonctionne immédiatement. Rien à connecter. À refaire après chaque modification du code, car ce fichier est une copie figée.

**B. Synchronisation vive (pour développer).** `rojo serve` plus **Connect** dans le plugin Rojo. Le code suit les fichiers en direct, mais la synchronisation n'atteint que la place ouverte **et connectée** : c'est la source d'erreur numéro un, voir §8.

La place d'origine de la V1 n'est plus utilisée. Ne pas l'ouvrir en croyant y trouver la V2 : les deux n'ont aucun script en commun.

## 1. Outillage local (10 minutes)

1. Installer rokit : `curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash` puis rouvrir le terminal.
2. Dans le dépôt : `./scripts/setup.sh` (installe rojo, wally, selene, stylua, luau-lsp, lune ; télécharge les paquets et les définitions de types).
3. `./scripts/check.sh` doit afficher `✔ all quality gates green`.
4. Dans Studio : installer le plugin Rojo (`rojo plugin install` ou Creator Store), puis `rojo serve default.project.json` et **Connect** dans le plugin. Accepter la synchronisation initiale.

## 2. Paramètres de l'expérience (Creator Dashboard → ton expérience)

| Réglage | Valeur | Où |
|---|---|---|
| Accès API depuis Studio | activé | Game Settings → Security → *Enable Studio Access to API Services* |
| Publication | publiée (au moins en privé) | File → Publish to Roblox |
| Joueurs max par serveur | 12 (assez pour 2 matchs 3v3 + hub) | Game Settings → Places → Max players |
| Orientation | Paysage (`LandscapeSensor`, déjà fixé par `default.project.json`) | — |
| Appareils | ordinateur, téléphone, tablette, console | Game Settings → Basic Info → Devices |
| Chat | texte activé (le VIP a un tag) | Game Settings → Communication |
| Genre / âge | Combat (fantasy), tous publics, violence légère | Game Settings → Basic Info |

## 3. Game passes (Creator Dashboard → Monetization → Passes)

Créer chaque pass avec ce nom et ce prix, puis coller l'ID dans `MonetizationConfig.Passes.<Clé>.Id`.

| Clé | Nom affiché | Prix conseillé | Description à saisir |
|---|---|---|---|
| `Vip` | VIP | 399 R$ | XP ×2, Ryo ×1,5, tag dans le chat, aura exclusive |
| `LoadoutSlots` | Loadout Slots | 199 R$ | +4 slots d'équipement (10 au total) |
| `Lightning` | Lightning Element | 299 R$ | Débloque l'élément Foudre immédiatement (sinon niveau 40) |
| `SkinPack` | Skin Pack | 249 R$ | 4 skins de jutsu (Boule de Feu, Vague, Piques, Rafale) |

## 4. Developer products (Creator Dashboard → Monetization → Developer Products)

| Clé | Nom affiché | Prix conseillé |
|---|---|---|
| `RyoSmall` | 1,000 Ryo | 99 R$ |
| `RyoMedium` | 3,500 Ryo | 299 R$ |
| `RyoLarge` | 8,000 Ryo | 599 R$ |
| `PremiumPass` | Premium Battle Pass (Season) | 349 R$ |
| `TierSkip5` | +5 Battle Pass Tiers | 149 R$ |
| `XpBoost1h` | XP Boost (1 hour) | 79 R$ |
| `CosmeticCommon` | Cosmetic (Common) | 49 R$ |
| `CosmeticRare` | Cosmetic (Rare) | 149 R$ |
| `CosmeticEpic` | Cosmetic (Epic) | 349 R$ |
| `CosmeticLegendary` | Cosmetic (Legendary) | 699 R$ |

Coller chaque ID dans `MonetizationConfig.Products.<Clé>.Id`. Les produits « Cosmetic » sont génériques par rareté : le serveur mémorise l'article choisi avant d'ouvrir le prompt (`ShopService`).

## 5. Vérification en jeu (5 minutes)

1. `rojo serve`, Play dans Studio : l'Output doit montrer `[Bootstrap] Jutsu Battlegrounds v2.0.0 ready` et **aucun** `[MonetizationService] missing id` une fois les IDs saisis.
2. Frapper un mannequin (`J J` = Boule de Feu) → XP, Ryo, barre de niveau.
3. `M` → Options : réassigner une touche, sauvegarder, relancer Play : la touche est conservée (DataStore actif).
4. Test tactile : Test → Device → téléphone : les boutons d'action apparaissent à droite.
5. Test manette : brancher une manette, D-pad = éléments.

## 6. Publication automatisée (optionnel)

`.github/workflows/publish.yml` publie le `.rbxl` construit par la CI via l'API Open Cloud. Secrets à créer dans GitHub → Settings → Secrets and variables → Actions :

| Secret | Valeur |
|---|---|
| `ROBLOX_API_KEY` | clé Open Cloud (Creator Dashboard → Open Cloud → API Keys) avec la permission **universe-places:write** sur l'expérience et l'IP `0.0.0.0/0` (ou celles des runners) |
| `UNIVERSE_ID` | Creator Dashboard → expérience → *Universe ID* |
| `PLACE_ID` | ID de la place de départ |

Lancer ensuite le workflow « Publish to Roblox » depuis l'onglet Actions (`Saved` pour un brouillon, `Published` pour mettre en ligne).

## 7. Assets à remplacer plus tard

Le hub et les arènes sont générés en code (`HubService`, `ArenaService`). Pour les remplacer par des assets, conserver les noms d'ancrage listés dans `docs/GAME_DESIGN.md` §8 (`HubSpawn`, `QueueTerminal`, `LeaderboardBoard_<mode>`, `ShopKiosk`, `Spawn_Team1/2`, `BossSpawn`). Les sons se remplacent dans `src/shared/Config/SoundConfig.luau` (IDs `rbxassetid://`).

## 8. Dépannage

### Je lance Play, les mannequins apparaissent mais il n'y a aucune interface

Le serveur tourne (les mannequins sont construits par `HubService`) et le client n'existe pas dans cette place. Autrement dit la place ouverte n'a pas reçu la synchronisation. Coller ceci dans la **Command Bar** de Studio (View → Command Bar) :

```lua
local SPS = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local RS = game:GetService("ReplicatedStorage")
print("StarterPlayerScripts:", SPS and #SPS:GetChildren() or "ABSENT")
if SPS then for _, c in ipairs(SPS:GetChildren()) do print("   ", c.ClassName, c.Name) end end
for _, n in ipairs({ "Shared", "UI", "Packages" }) do
	print("ReplicatedStorage." .. n .. ":", RS:FindFirstChild(n) and "OK" or "ABSENT")
end
```

Attendu, exactement :

```
StarterPlayerScripts: 3
    LocalScript Bootstrap
    Folder Controllers
    ModuleScript RemoteClient
ReplicatedStorage.Shared: OK
ReplicatedStorage.UI: OK
ReplicatedStorage.Packages: OK
```

| Sortie obtenue | Cause | Correction |
|---|---|---|
| `StarterPlayerScripts: 0` ou `ABSENT` | la place n'est pas synchronisée | ouvrir `build/JutsuBattlegrounds.rbxl` (méthode A ci-dessus) |
| `Shared`, `UI` ou `Packages` `ABSENT` | synchronisation partielle, ou `wally install` jamais lancé | `./scripts/setup.sh` puis reconstruire |
| des scripts aux noms inconnus (`ServerCore`, `DataManager`, `Client`…) | c'est une autre place, d'un autre projet | fermer sans enregistrer, ouvrir `build/JutsuBattlegrounds.rbxl` |
| l'attendu s'affiche mais toujours aucune interface | erreur client à l'exécution | Output, onglet **Client** : la première ligne rouge nomme le contrôleur fautif |

Un détail qui trompe : l'Output de Studio mélange serveur et client. Le HUD est construit par `HudController`, donc une erreur client passe inaperçue si le filtre est resté sur *Server*.

### `ProfileStore` se plaint de l'accès aux données

Game Settings → Security → *Enable Studio Access to API Services*, et la place doit être publiée au moins une fois. Sans cela rien n'est sauvegardé et l'avertissement est normal.

### Deux points d'apparition

`HubService` avertit s'il trouve une `SpawnLocation` autre que `HubSpawn`. Supprimer celle ajoutée à la main : le hub est entièrement construit par le code.
