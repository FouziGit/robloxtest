# Configuration manuelle dans Roblox Studio

Tout ce que le code ne peut pas faire à ta place. À faire une fois, dans l'ordre. Les identifiants obtenus se collent **uniquement** dans `src/shared/Config/MonetizationConfig.luau` ; au démarrage, le serveur affiche un `warn` par identifiant encore à `0`.

## Le plus rapide : ouvrir le fichier construit

Deux façons d'avoir le jeu dans Studio. La première ne peut pas échouer et ne demande aucun plugin.

**A. Fichier construit (recommandé pour juste jouer).**

```bash
./scripts/check.sh && open build/Vellum.rbxl
```

`rojo build` écrit un fichier de place complet : serveur, client, interface et paquets sont déjà dedans. Studio l'ouvre comme n'importe quelle place, et **Play** fonctionne immédiatement. Rien à connecter. À refaire après chaque modification du code, car ce fichier est une copie figée.

**B. Synchronisation vive (pour développer).** `rojo serve` plus **Connect** dans le plugin Rojo. Le code suit les fichiers en direct, mais la synchronisation n'atteint que la place ouverte **et connectée** : c'est la source d'erreur numéro un, voir §9.

La place d'origine de la V1 n'est plus utilisée. Ne pas l'ouvrir en croyant y trouver la V2 : les deux n'ont aucun script en commun.

## 1. Outillage local (10 minutes)

1. Installer rokit : `curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash` puis rouvrir le terminal.
2. Dans le dépôt : `./scripts/setup.sh` (installe rojo, wally, selene, stylua, luau-lsp, lune ; télécharge les paquets et les définitions de types).
3. `./scripts/check.sh` doit afficher `✔ all quality gates green`.
4. Dans Studio : installer le plugin Rojo (`rojo plugin install` ou Creator Store), puis `rojo serve default.project.json` et **Connect** dans le plugin. Accepter la synchronisation initiale.

**Sous Windows**, les étapes 1, 2 et 4 tiennent en une commande PowerShell, depuis la racine du dépôt : `powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1`. Le script installe rokit et les outils, télécharge les paquets et les types, enregistre le chemin de Blender dans la variable `BLENDER` (les outils d'animation et de maillage prennent sinon le chemin macOS), installe le plugin Rojo et construit `build\Vellum.rbxl`. `scripts/check.sh` demande bash (Git Bash convient).

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

## 2 bis. Type d'avatar : laisse R15 — **ne passe pas en R6**

Une version précédente de ce document disait l'inverse. Elle avait tort (`docs/DECISIONS.md` D-103).

Un avatar Roblox moderne n'a plus d'articulations `Motor6D` : c'est l'**Avatar Joint Upgrade**, un rig de contraintes (`AnimationConstraint` + `BallSocketConstraint`), activé par défaut depuis mai 2026 ; Roblox a annoncé la fin de la possibilité de s'en retirer. `Posture` le pose de la manière que Roblox documente — en multipliant `Transform` dans `RunService.PreSimulation`, juste après l'`Animator` — et fonctionne aussi bien sur ce rig que sur un `Motor6D`. Vérifié dans un client en marche : garde levée, les mains avancent et montent d'environ un stud et demi.

Le R6 serait un piège : toutes les bibliothèques d'animation de combat utilisables sont des squelettes R15, le R6 n'a ni coudes ni genoux, et la capture d'animation de Roblox ne produit que du R15. Une garde R6 ne peut pas plier le coude, et c'est le coude qui la rend lisible.

## 3. Game passes (Creator Dashboard → Monetization → Passes)

Créer chaque pass avec ce nom et ce prix, puis coller l'ID dans `MonetizationConfig.Passes.<Clé>.Id`.

| Clé | Nom affiché | Prix conseillé | Description à saisir |
|---|---|---|---|
| `Vip` | VIP | 399 R$ | XP ×2, Folios ×1,5, tag dans le chat, aura exclusive |
| `LoadoutSlots` | Loadout Slots | 199 R$ | +4 slots d'équipement (10 au total) |
| `Orpiment` | Orpiment Pigment | 299 R$ | Débloque le pigment Orpiment immédiatement (sinon niveau 40) |
| `SkinPack` | Skin Pack | 249 R$ | 4 skins de glyphe (Marque, Lavis, Empattement, Balayage) |

## 4. Developer products (Creator Dashboard → Monetization → Developer Products)

| Clé | Nom affiché | Prix conseillé |
|---|---|---|
| `FolioSmall` | 1,000 Folios | 99 R$ |
| `FolioMedium` | 3,500 Folios | 299 R$ |
| `FolioLarge` | 8,000 Folios | 599 R$ |
| `PremiumPass` | Premium Battle Pass (Season) | 349 R$ |
| `TierSkip5` | +5 Battle Pass Tiers | 149 R$ |
| `XpBoost1h` | XP Boost (1 hour) | 79 R$ |
| `CosmeticCommon` | Cosmetic (Common) | 49 R$ |
| `CosmeticRare` | Cosmetic (Rare) | 149 R$ |
| `CosmeticEpic` | Cosmetic (Epic) | 349 R$ |
| `CosmeticLegendary` | Cosmetic (Legendary) | 699 R$ |

Coller chaque ID dans `MonetizationConfig.Products.<Clé>.Id`. Les produits « Cosmetic » sont génériques par rareté : le serveur mémorise l'article choisi avant d'ouvrir le prompt (`ShopService`).

## 5. Vérification en jeu (10 minutes)

La méthode A de l'introduction suffit : `open build/Vellum.rbxl`, puis **Play**.

1. Play dans Studio : l'Output doit montrer `[Bootstrap] Vellum v2.0.0 ready` et **aucun** `[MonetizationService] missing id` une fois les IDs saisis.
2. Frapper un mannequin (`J J` = Marque) → XP, Folios, barre de niveau.
   - Verrou : face à un mannequin, **clic molette** (ou R3) → un losange d'encre au-dessus de lui, la caméra le suit et le personnage lui fait face même en marchant de côté ; clic molette à nouveau → relâché. Il lâche seul si le mannequin tombe à zéro ou si tu t'éloignes de plus de 140 studs. Sur un trackpad sans bouton du milieu, réassigne `Verrouiller` dans les options.
3. `M` → Options : réassigner une touche, sauvegarder, relancer Play : la touche est conservée (DataStore actif).
4. Test tactile : Test → Device → téléphone (812x375, paysage). Vérifier trois choses :
   - les cinq disques de pigments affichent bien un pictogramme (`▲ ≈ ■ » ✦`) et non un carré vide. Ce sont des caractères Unicode ; si l'un d'eux ne s'affiche pas sur ton appareil, le remplacer dans `src/shared/Config/PigmentConfig.luau` (champ `Sigils`) — le HUD et l'écran d'équipement suivent automatiquement ;
   - les disques Melee / Dash / Block / Menu affichent leur libellé court en entier (`CAC`, `Ruée`, `Garde`, `Menu` en français) ;
   - aucun bouton ne mesure moins de 44 px à l'écran, et rien ne chevauche le bouton de saut du moteur.
5. Test manette : brancher une manette, D-pad = pigments. Dans le classement, le D-pad fait défiler la liste (les lignes ne sont pas sélectionnables, le panneau déplace le canevas lui-même).

### La boucle complète, à un seul joueur (5 minutes de plus)

6. `M` → **Quêtes** : trois quêtes du jour. Frapper des mannequins et lancer des glyphes fait avancer celles qui comptent des dégâts, des coups au corps-à-corps, des ruées ou des mannequins. Réclamer une quête terminée crédite XP et Folios.
7. `M` → **Récompense quotidienne** : réclamer aujourd'hui. Le lendemain (ou en avançant l'horloge de la machine) la série passe à 2.
8. `M` → **Équipement** : retirer un glyphe, en mettre un autre, sauvegarder, relancer Play : la sélection est conservée.
9. `M` → **Boutique** : quatre articles du jour. Acheter en Folios si le solde suffit, équiper, vérifier que l'article passe en « possédé ». L'achat en Robux ne fonctionne qu'une fois les IDs de §4 saisis et la place publiée.
10. `M` → **Battle pass** : la barre avance avec l'XP ; réclamer un palier gratuit.

### Le classé, à deux joueurs (Studio le fait tout seul)

11. **Test → Clients and Servers → 2 players → Start**. Deux fenêtres client s'ouvrent.
12. Dans les deux : `M` → **Jouer** → **1v1 classé**. La file les apparie en quelques secondes, l'arène se construit, compte à rebours de 5 s.
13. Se battre. Le premier à deux manches gagne. L'écran de résultat montre le score, l'XP, le Folios et le mouvement de classement ; le rang apparaît sur les tableaux du hub au prochain rafraîchissement (60 s).
14. **Tester l'abandon** : pendant un match, fermer une fenêtre client. Le survivant remporte la série, et le partant est débité comme s'il avait perdu (visible dans l'Output : `[RankingService] … abandoned …`).

### Le World Boss, sans attendre vingt minutes

15. L'événement se déclenche toutes les `WorldBossConfig.Schedule.IntervalSeconds` (1200 s) et demande deux joueurs. Pour le voir tout de suite : ramener `IntervalSeconds` à `30` et `AnnounceSeconds` à `5` dans `src/shared/Config/WorldBossConfig.luau`, relancer le test à 2 joueurs, attendre l'annonce, frapper le boss. **Remettre les valeurs d'origine après.**
16. Pendant l'événement, la file de match est en pause et le compteur d'attente ne tourne pas : c'est voulu (D-25 et le correctif de file).

## 6. Publication automatisée (optionnel)

`.github/workflows/publish.yml` publie le `.rbxl` construit par la CI via l'API Open Cloud. Secrets à créer dans GitHub → Settings → Secrets and variables → Actions :

| Secret | Valeur |
|---|---|
| `ROBLOX_API_KEY` | clé Open Cloud (Creator Dashboard → Open Cloud → API Keys) avec la permission **universe-places:write** sur l'expérience et l'IP `0.0.0.0/0` (ou celles des runners) |
| `UNIVERSE_ID` | Creator Dashboard → expérience → *Universe ID* |
| `PLACE_ID` | ID de la place de départ |

Lancer ensuite le workflow « Publish to Roblox » depuis l'onglet Actions (`Saved` pour un brouillon, `Published` pour mettre en ligne).

## 7. Téléverser les textures et les sons (une commande, une seule fois)

Les 16 PNG de `assets/textures/` et les 55 WAV de `assets/audio/` sont générés par les scripts de `tools/` ; Roblox ne les affiche et ne les joue qu'une fois téléversés sur un compte. `scripts/upload_assets.py` le fait par l'API Open Cloud et **écrit lui-même les identifiants** dans `AssetIds.luau` et `SoundConfig.luau` — plus aucun copier-coller.

**La clé, une fois.** [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials) → **Create API Key** → *Access Permissions* : `assets`, **Read** et **Write**, *Restrict by Experience* désactivé → **Save**. Roblox n'affiche la clé complète qu'à ce moment-là (sinon : **Edit** → **Regenerate Key**). Puis, dans le terminal :

```bash
read -rs "k?Clé Open Cloud : " && echo "ASPHALT_API_KEY=$k" > ~/Desktop/robloxtest/.env.local && unset k
```

Au message `Clé Open Cloud :`, colle **la clé** — rien ne s'affiche, c'est voulu — puis Entrée. `.env.local` est ignoré par git ; la clé n'est jamais affichée par le script.

**L'envoi.**

```bash
python3 scripts/upload_assets.py quota
```

```bash
python3 scripts/upload_assets.py upload
```

`quota` lit le nombre d'envois audio restants ce mois-ci (2 000 avec vérification d'identité, 100 ou 10 sans, selon la page officielle qu'on lit). `upload` n'envoie que ce qui ne l'a jamais été : chaque envoi est consigné avec l'empreinte SHA-256 du fichier dans `assets/roblox-assets.lock.json`, commité avec le reste. Les images partent comme **Image** (l'identifiant que `ParticleEmitter.Texture` attend, pas celui d'un décalque) et l'envoi refuse toute somme en Robux.

**Si un générateur change un fichier**, son identifiant pointe encore sur l'ancien envoi et `tests/UploadedAssets.spec.luau` fait échouer le build. Un fichier audio ou image ne se met pas à jour sur Roblox : il faut le renvoyer, ce qui crée un nouvel identifiant et consomme un envoi.

```bash
python3 scripts/upload_assets.py upload --reupload
```

**La modération.** Chaque envoi passe une modération Roblox, de quelques minutes à quelques heures ; tant qu'il est en revue, il reste invisible ou muet en jeu. Le fichier de verrou note l'état au moment de l'envoi.

**Sans le script** (dernier recours) : Creator Dashboard → *Creations* → *Development Items* → *Images* ou *Audio* → upload, puis ajouter à la main dans le bloc `-- BEGIN UPLOADED` du module concerné une ligne `["<chemin du fichier>"] = "rbxassetid://<id>",` — et la même entrée dans le fichier de verrou, faute de quoi la porte refuse le bloc.

### 7 bis. Les volumes (meshes générés, D-114)

Les volumes de `assets/meshes/` (l'ensō, la couronne, la goutte de la Marque, les bouts de papier…) sont générés par `tools/meshes/` dans Blender sans interface, puis envoyés par le même script, **comme modèles** : Open Cloud ne prend un maillage que dans un modèle. Le jeu, lui, a besoin de l'identifiant du *maillage* qu'il contient, que la clé n'a pas le droit de lire — c'est Studio qui le lit, en une commande.

```bash
python3 tools/meshes/generate_all.py
```

```bash
python3 scripts/upload_assets.py upload
```

```bash
python3 scripts/upload_assets.py resolve-snippet
```

Colle ce qu'imprime la dernière commande dans la barre de commande de Studio (place ouverte, pas besoin de lancer le jeu) ; elle imprime une ligne JSON. Enregistre-la dans un fichier, puis :

```bash
python3 scripts/upload_assets.py record-meshes resolved.json
```

`MeshConfig.luau` reçoit les identifiants et la taille importée de chaque maillage ; `tests/MeshConfig.spec.luau` vérifie qu'un stud du fichier vaut un stud en jeu, et que chaque fichier porte bien le demi-tour que l'importeur annule. Chaque ligne du JSON nomme le modèle d'où elle a été lue : un vieux `resolved.json`, d'avant un nouveau téléversement, est refusé — refais alors le `resolve-snippet`. Tant qu'un volume n'est pas résolu, le jeu ne le dessine pas et l'indique une fois dans la sortie.

## 8. Assets à remplacer plus tard

Le hub et les arènes sont générés en code (`HubService`, `ArenaService`). Pour les remplacer par des assets, conserver les noms d'ancrage listés dans `docs/GAME_DESIGN.md` §8 (`HubSpawn`, `QueueTerminal`, `LeaderboardBoard_<mode>`, `ShopKiosk`, `Spawn_Team1/2`, `BossSpawn`). Les sons se remplacent dans `src/shared/Config/SoundConfig.luau` (IDs `rbxassetid://`).

## 9. Dépannage

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
| `StarterPlayerScripts: 0` ou `ABSENT` | la place n'est pas synchronisée | ouvrir `build/Vellum.rbxl` (méthode A ci-dessus) |
| `Shared`, `UI` ou `Packages` `ABSENT` | synchronisation partielle, ou `wally install` jamais lancé | `./scripts/setup.sh` puis reconstruire |
| des scripts aux noms inconnus (`ServerCore`, `DataManager`, `Client`…) | c'est une autre place, d'un autre projet | fermer sans enregistrer, ouvrir `build/Vellum.rbxl` |
| l'attendu s'affiche mais toujours aucune interface | erreur client à l'exécution | Output, onglet **Client** : la première ligne rouge nomme le contrôleur fautif |

Un détail qui trompe : l'Output de Studio mélange serveur et client. Le HUD est construit par `HudController`, donc une erreur client passe inaperçue si le filtre est resté sur *Server*.

### `ProfileStore` se plaint de l'accès aux données

Game Settings → Security → *Enable Studio Access to API Services*, et la place doit être publiée au moins une fois. Sans cela rien n'est sauvegardé et l'avertissement est normal.

### Deux points d'apparition

`HubService` avertit s'il trouve une `SpawnLocation` autre que `HubSpawn`. Supprimer celle ajoutée à la main : le hub est entièrement construit par le code.
