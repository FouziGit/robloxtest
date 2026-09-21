# Configuration manuelle dans Roblox Studio

Tout ce que le code ne peut pas faire à ta place. À faire une fois, dans l'ordre. Les identifiants obtenus se collent **uniquement** dans `src/shared/Config/MonetizationConfig.luau` ; au démarrage, le serveur affiche un `warn` par identifiant encore à `0`.

## Le plus rapide : ouvrir le fichier construit

Deux façons d'avoir le jeu dans Studio. La première ne peut pas échouer et ne demande aucun plugin.

**A. Fichier construit (recommandé pour juste jouer).**

```bash
./scripts/check.sh && open build/Vellum.rbxl
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

## 7. Téléverser les seize textures (15 minutes, une seule fois)

C'est la seule étape manuelle que le code ne peut pas faire à ta place, et tant qu'elle n'est pas faite
les effets se dessinent **sans texture** : ils fonctionnent, mais ils sont plats.

Les PNG sont dans `assets/textures/`. Ils sont générés par les scripts de `tools/textures/` — aucun ne
vient de la boîte à outils, et ils se régénèrent à l'identique avec `python3 tools/textures/generate_all.py`.

1. Creator Dashboard → **Creations** → **Development Items** → **Images** → **Add Image**.
2. Téléverse les seize fichiers de `assets/textures/`. Roblox les passe en modération ; compte quelques
   minutes par image. Les quatre `telegraph_*.png` sont les avertissements de L'Effacement : ce sont les
   seules textures dont le bord est une règle (leur encre atteint le bord du plan, `AssetIds.Ink`), et
   tant qu'elles ne sont pas en ligne le boss prévient avec des **plaques teintées sans texture** — un
   carré rouge au sol dit encore où ne pas se tenir, mais un carré déborde d'un disque dans les coins.
3. Pour chacune, copie l'identifiant (`rbxassetid://…`) et colle-le dans l'entrée correspondante de
   `src/shared/Config/AssetIds.luau`. Chaque entrée nomme déjà son fichier source dans son champ
   `Source`, donc l'appariement est mécanique.
4. Relance `./scripts/check.sh` : `tests/AssetIds.spec.luau` refuse un identifiant qui n'est pas de la
   forme `rbxassetid://<nombre>`, et refuse une entrée dont le PNG n'existe pas ou n'a pas les
   dimensions déclarées.

Tant qu'un identifiant est vide, le client l'annonce **une fois** au démarrage en nommant le fichier à
téléverser, puis l'effet se joue quand même. Une couche qui ne sert qu'à porter une texture — un sceau,
une brûlure au sol — n'est simplement pas dessinée plutôt que de laisser un rectangle de couleur en l'air.
La seule exception est un avertissement du boss, qui se dessine nu : une règle ne disparaît pas parce que
l'art est en retard.

## 8. Téléverser les cinquante-cinq sons (20 minutes, une seule fois)

Même principe que les textures : les WAV sont dans `assets/audio/`, générés par les scripts de
`tools/audio/` (`python3 tools/audio/generate_all.py` les réécrit à l'identique), et **tant qu'ils ne sont
pas en ligne le jeu est silencieux** — pas de son de repli, parce que le seul repli disponible est le
ping du moteur, et un ping du moteur est le son de tous les autres jeux.

1. Creator Dashboard → **Creations** → **Development Items** → **Audio** → **Upload**.
2. Téléverse les cinquante-cinq fichiers de `assets/audio/`. Ce sont des WAV 16 bits mono, 22 050 Hz
   pour les effets et 16 000 Hz pour les trois boucles ; aucun ne dépasse 900 Ko. Roblox les passe en
   modération. Les limites documentées au moment d'écrire : 20 Mo et 7 minutes par fichier, et un
   quota de 100 téléversements audio par 30 jours pour un compte non vérifié (2 000 avec une pièce
   d'identité) — les cinquante-cinq tiennent dans le premier. Un son est privé à l'expérience de celui
   qui l'a téléversé : le compte doit être celui de l'expérience.
3. Pour chacun, copie l'identifiant (`rbxassetid://…`) et colle-le dans l'entrée correspondante de
   `src/shared/Config/SoundConfig.luau`. Chaque entrée nomme déjà son fichier source dans `Source`.
   Les vingt voix des pigments s'appellent `<Pigment><Voix>` (`CinnabarImpact`), les boucles sont
   dans `SoundConfig.Music`.
4. Relance `./scripts/check.sh` : `tests/SoundConfig.spec.luau` refuse un identifiant qui n'est pas de
   la forme `rbxassetid://<nombre>`, et refuse une entrée dont le WAV n'existe pas ou n'a pas la durée,
   le débit ou le format déclarés.

Tant qu'un identifiant est vide, le client l'annonce **une fois** au démarrage en nommant l'entrée,
puis se tait pour elle.

## 9. Assets à remplacer plus tard

Le hub et les arènes sont générés en code (`HubService`, `ArenaService`). Pour les remplacer par des assets, conserver les noms d'ancrage listés dans `docs/GAME_DESIGN.md` §8 (`HubSpawn`, `QueueTerminal`, `LeaderboardBoard_<mode>`, `ShopKiosk`, `Spawn_Team1/2`, `BossSpawn`). Les sons se remplacent dans `src/shared/Config/SoundConfig.luau` (IDs `rbxassetid://`).

## 10. Dépannage

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
