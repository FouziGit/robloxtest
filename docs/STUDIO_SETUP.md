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

Les écrans s'ouvrent par la barre en bas à droite (**Jouer**, **Boutique**, **Classement**, **Menu (M)**), par la touche `M`, ou en s'approchant du terminal de file et de la boutique du hub (touche `E`). `M` referme l'écran ouvert.

6. `M` → **Quêtes** : trois quêtes du jour. Frapper des mannequins et lancer des glyphes fait avancer celles qui comptent des dégâts, des coups au corps-à-corps, des ruées ou des mannequins. Réclamer une quête terminée crédite XP et Folios.
7. `M` → **Récompense quotidienne** : réclamer aujourd'hui. Le lendemain (ou en avançant l'horloge de la machine) la série passe à 2.
8. `M` → **Équipement** : retirer un glyphe, en mettre un autre, sauvegarder, relancer Play : la sélection est conservée.
9. **Boutique** : six articles du jour. Acheter en Folios si le solde suffit, équiper, vérifier que l'article passe en « possédé ». Le bouton Robux reste grisé tant que l'ID du produit (§4) vaut 0, et l'achat ne fonctionne qu'une fois la place publiée.
10. `M` → **Battle pass** : la barre avance avec l'XP ; réclamer un palier gratuit.

### Le classé, à deux joueurs (Studio le fait tout seul)

11. **Test → Clients and Servers → 2 players → Start**. Deux fenêtres client s'ouvrent.
12. Dans les deux : `M` → **Jouer** → **1v1 classé**. La file les apparie en quelques secondes, l'arène se construit, compte à rebours de 5 s.
13. Se battre. Le premier à deux manches gagne. L'écran de résultat montre le score, l'XP, le Folios et le mouvement de classement ; le rang apparaît sur les tableaux du hub au prochain rafraîchissement (60 s), **si l'accès aux API est activé** (Game Settings → Security → *Enable Studio Access to API Services*, place publiée) : sans lui, les tableaux affichent « Aucun joueur classé pour l'instant ». Seul, un 1v1 ne démarre jamais : il faut deux clients (six pour le 3v3).
14. **Tester l'abandon** : pendant un match, fermer une fenêtre client. Le survivant remporte la série, et le partant est débité comme s'il avait perdu (visible dans l'Output : `[RankingService] … abandoned …`).

### Le World Boss, sans attendre vingt minutes

15. L'événement se déclenche toutes les `WorldBossConfig.Schedule.IntervalSeconds` (1200 s) et demande deux joueurs. Pour le voir tout de suite : ramener `IntervalSeconds` à `30` et `AnnounceSeconds` à `5` dans `src/shared/Config/WorldBossConfig.luau`, relancer le test à 2 joueurs, attendre l'annonce, frapper le boss. **Remettre les valeurs d'origine après.**
16. Pendant l'événement, la file de match est en pause et le compteur d'attente ne tourne pas : c'est voulu (D-25 et le correctif de file).

### Les portails, le champ de bataille et l'Effacement en entraînement, à un seul joueur (5 minutes)

Aucune valeur à changer : un **Play** en solo suffit (D-130 à D-133).

17. **Les portails.** Au nord du hub, deux portiques d'encre au-dessus d'un cercle de craie ; au-dessus de chacun, dans ta langue, « Champ de bataille » ou « Affronter l'Effacement » et « Reste dans le cercle pour entrer ». Il n'y a rien à presser : entre dans le cercle de gauche et restes-y. Une bande en haut de l'écran dit « Reste dans le cercle : Champ de bataille » et se remplit ; au bout d'une seconde et demie tu es dans le camp du champ de bataille. Ressortir du cercle avant la fin : la bande disparaît et rien ne se passe. Un écran ouvert (`M`) se referme à l'arrivée.
18. **Les Faussaires.** À l'arrivée : « Les Faussaires t'ont vu. », une bande qui compte les Faussaires debout (trois pour un joueur seul, « 3 Faussaires debout · 0 vaincus ») et la musique de combat. Trois figures d'encre marquées de barres de craie viennent. Avant chaque coup, un rectangle d'encre au sol va du Faussaire jusqu'au bord de ce qu'il touchera et se remplit ; un éclat de craie à sa main dit « maintenant ». Sortir du rectangle esquive le coup ; le verrou (clic molette) prend un Faussaire. Le camp (à l'ouest de la ligne d'encre) est sûr : aucun Faussaire n'y entre, la vie y remonte après une seconde et demie sans coup, et un Faussaire tué depuis le camp ne paie rien.
19. **Les récompenses.** Un Faussaire vaincu donne de l'XP et des Folios (1, ou 4 pour le lourd) jusqu'à 150 par jour, et fait avancer « Vaincs 15 Faussaires » si la quête est tirée aujourd'hui (`M` → Quêtes). Mourir : on réapparaît dans le camp, la bande reste.
20. **Le retour.** Le portail du camp (« Retour au hub », deux secondes dans le cercle) ramène au hub. Pendant trois secondes après un voyage, un cercle n'emmène personne et ne montre pas de bande.
21. **L'entraînement.** Le portail de droite ouvre, même seul, un combat contre l'Effacement : 2 500 PV pour quatre minutes, bande titrée « L'Effacement · entraînement » ; le classé n'est pas mis en pause. Le portail de retour, dans un coin de l'arène, ramène au hub. Mort pendant le combat : reprendre le portail du hub ramène dans le même combat (deux fois au plus). Le vaincre paie un quart d'une participation, trois fois par jour.
22. **Avant de publier, à regarder dans Studio** (ce que les tests ne peuvent pas voir, D-131 et D-133) : les Faussaires marchent et restent immobiles avec les animations du moteur, s'arrêtent net avant de frapper, sont poussés par une projection, et leur corps s'effondre à la mort ; le signal de coup doit passer au labo `tools/vfxlab/` (planches avant/après et notes de la recette `vellum-vfx`), ce qui n'a pas encore été fait. Si la place publiée active `Workspace.StreamingEnabled`, vérifier aussi que le champ de bataille (X = 1500, au-delà du rayon de streaming par défaut) est chargé à l'arrivée.

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

## 10. Le garde de mouvement : ce que seul Studio peut vérifier (avant de quitter l'observation)

Le garde de mouvement (D-135 à D-139) est livré en **Observe** : il juge chaque corps et journalise ce qu'il aurait fait, mais ne déplace ni ne frappe personne. Ses règles sont prouvées sous Lune sur un client et un réseau **simulés** ; ce qui suit ne se voit que dans le moteur. Chaque point dit comment le voir et ce qu'il décide. Les lignes du garde commencent par `[Combat.MovementAudit]` ; `docs/QA.md` §11 explique comment les lire.

1. **La sonde d'appui.** Se tenir, puis sauter et retomber, sur : le sol plat, le bord d'une plateforme, la tête d'un autre joueur (deux clients), une dalle de la Marge, la coque de l'Effacement (entraînement), une épreuve du hub, la bordure du hub. Attendu : aucune ligne `observe correct (Flight/…)`. Une ligne `a flight flag found ground` dit que la sonde d'appui a raté un sol que la sonde de confirmation a trouvé : noter où.
2. **La durée des échantillons périmés après un téléport.** *File → Studio Settings → Network → Incoming Replication Lag* à 0,2 puis 0,5 s, puis prendre un portail aller-retour. Attendu : aucune ligne `observe repivot` ni `observe correct (Teleport/…)` à l'arrivée. Une telle ligne veut dire que les échantillons d'avant le téléport durent plus que `SettleMaxSeconds` (1 s) : c'est ce chiffre qu'il faudrait revoir.
3. **L'ordre de `CharacterAdded` et du retour de `LoadCharacterAsync`**, et où est la racine dans `CharacterAdded` : lancer un duel à deux clients et regarder le début de chaque manche. Attendu : aucune ligne du garde pendant le compte à rebours. Une ligne `had no spawn point` ou un `observe correct` au placement sur le pad veut dire que le nouveau corps n'était pas où le garde l'attendait.
4. **La hauteur d'éjection d'une dalle de la Marge et la poussée de l'Effacement.** Lever une Marge sous ses propres pieds, puis se tenir au contact de l'Effacement pendant qu'il avance. Attendu : aucune ligne `would strike` (le contact excuse) ; une ligne `observe correct … exempt` reste acceptable.
5. **Une projection contre un mur de 2 studs** (le pic d'une projection est d'environ 232 studs/s) : se faire projeter contre un mur d'arène. Attendu : le corps ne traverse pas. S'il traverse, la ligne `observe correct (Noclip/wall)` dit par où.
6. **La gravité, le streaming et le comportement des signaux**, écrits au démarrage : `[Combat.MovementAudit] mode Observe: gravity 196.2 (judged at 196.2), streaming …, signals …, N barrier parts`. Attendu : les deux gravités égales et `N` à 5, la plateforme du hub et ses quatre bordures (les arènes et le champ de bataille, construits ensuite, s'ajoutent sans ligne) ; 0 veut dire que le hub n'était pas construit avant `CombatService`. Noter `streaming` et `signals` pour la place publiée, qui peut différer de Studio (`docs/QA.md` §13).
7. **Les remotes continuent-elles d'arriver quand le moteur ralentit la physique d'un client ?** Avec l'émulation d'un appareil lent ou une forte latence, sauter et rester en l'air le plus longtemps possible. Une ligne `watch (Flight/frozen) … would strike` sur un client honnête décide que le corps figé en l'air ne pourra jamais être corrigé, et peut-être plus jamais frappé.
8. **L'écriture de la vitesse par le serveur atteint-elle le client ?** Une correction remet la vitesse du corps à zéro. Ne se vérifie qu'en mode **Correct**, sur une copie de test : se téléporter depuis la barre de commande du client (`docs/QA.md` §11) et regarder si le corps ramené repart avec son élan.
9. **Des paquets de physique peuvent-ils arriver dans le désordre après un téléport ?** Même montage qu'au point 2, avec *Incoming Replication Lag* variable. Une ligne `observe correct (Teleport/gap)` qui ramène vers le point de départ du téléport, juste après l'arrivée, dirait que la fenêtre de retour (`ReturnWindowSeconds`, 1,5 s) est trop courte.
10. **Le coût.** MicroProfiler (`Ctrl+F6`, `Ctrl+P` pour une capture, `docs/PERFORMANCE.md`), étiquette `MovementAudit` dans le tick du serveur. Objectif : moins d'une demi-milliseconde par tick à douze joueurs. Aucun chiffre du dépôt ne vient d'une mesure.
11. **Un Humanoid supprimé par le client est-il répliqué ?** Dans la barre de commande du client, `game.Players.LocalPlayer.Character.Humanoid:Destroy()`. Côté serveur, `[CombatService] Humanoid left the character of …` dit que oui ; le garde continue alors de juger la racine.
12. **`GetNetworkPing` contre l'affichage de `Shift+F3`.** Le garde lit l'aller-retour comme deux fois `GetNetworkPing` ; si l'affichage montre la même valeur que `GetNetworkPing` et non le double, le garde surestime l'aller-retour (sans danger pour un joueur honnête, mais ses fenêtres sont plus larges que nécessaire).

**Passer en Correct.** Quand ces douze points sont vus et que les journaux d'une vraie session sont propres (`docs/QA.md` §11), passer `MovementGuardConfig.Mode` à `"Correct"` dans `src/server/Config/MovementGuardConfig.luau`, et changer avec lui le test qui tient `"Observe"` (`tests/Config.spec.luau`) : c'est une décision, à écrire dans `docs/DECISIONS.md`. `"Enforce"` (les frappes) vient ensuite, de la même façon, après des journaux propres en Correct.

## 11. Vérifier l'interface (appareils)

La passe couleur (D-147) est tenue sous Lune par des tests de source et d'arithmétique ; ce qui suit ne se voit qu'à l'écran. Dans Studio, *Test → Device* pour l'émulateur, et *Test → Locale* pour le français.

**Les appareils.** Téléphone 844 × 390 (iPhone 12 à 14) et téléphone 667 × 375, tous deux à l'échelle 0,68 ; iPad paysage 1180 × 820 ; 1920 × 1080 à la souris, puis à la manette (profil Xbox) ; 2560 × 1440 ; chacun en `fr-fr` au moins une fois.

**Avant tout le reste.** Le test de fumée de dix minutes, jamais fait depuis la fondation : ouvrir chaque écran, jouer un match, visiter le Champ de bataille et l'arène de l'Effacement, et relever dans la sortie chaque avertissement ou erreur d'un contrôleur ou d'un écran.

**Les hypothèses de la fiche (§12.1), à vérifier d'abord** — le reste s'appuie dessus :
- A. L'épaisseur d'un `UIStroke` sous `UIScale` : un contour de 3 à l'échelle 0,68, mesuré sur une capture. `Theme.stroke` garde 2 pixels au moins dans les deux cas ; noter ce qu'on voit dans une décision.
- B. `GuiService.ReducedMotionEnabled`, `PreferredTextSize` et `PreferredTransparency` lus et suivis depuis un LocalScript : les afficher, puis les changer dans le menu Roblox. S'ils ne se lisent pas, `UiPrefs` garde ses valeurs neutres avec un avertissement, et la propriété entre dans `RESERVED` de `tests/EngineOnlyApi.spec.luau`.
- C. Les polices (Fredoka One, Nunito, Oswald, Merriweather italique) et le repli des symboles (▲ ■ ● ◆ ▶ ▼ ✦ ✕ ✓ ≈ » ‹ ›, les flèches en Merriweather) sur PC, iOS et Android : une planche de glyphes. Un symbole manquant est redessiné en cadres (`Icon`).
- D. La sortie d'un écran dans son `CanvasGroup` passager, sur l'émulateur puis sur un vrai téléphone modeste ; sinon, échelle et glissé seulement.
- E. Les invites personnalisées et `InputHoldBegin` au toucher (point 12 ci-dessous).
- F. Le dock entre les disques des deux mains (point 4).
- G. La file des toasts au PC sous la liste des joueurs à huit (*Test → Players : 8*) ; sinon la faire partir de 0,40 de la hauteur.
- H. Les comptes à rebours (rotation de la Boutique, quêtes, récompense du jour) contre la bascule du serveur à minuit UTC, horloge décalée dans une place de test.

**À regarder, captures à l'appui (planches avant/après) :**
1. Chaque écran entre et sort par son animation, rien n'apparaît ni ne disparaît d'un coup, et Retour et ✕ font ce que dit la fiche.
2. Aucun texte de bouton tronqué en français (« Rejoindre la file », « Tout récupérer (12) », « Obtenir le Premium »).
3. L'anneau de sélection de la manette se voit sur un bouton jaune, un bouton feuille, une tuile d'encre, l'onglet choisi et les disques du spectateur (anneau « combat » : la feuille, jamais le jaune).
4. Le HUD à 0,68 : le dock, la barre de glyphes, les puces et l'aperçu ne touchent ni les disques ni la zone du stick ; sur le 667 × 375, le dock glisse à gauche des disques à 200 unités ; la colonne du haut reste sous 240.
5. Vie basse : barre rouge hachurée qui bat, bords qui brûlent ; immobiles avec « secousses et éclairs » coupé et avec le mouvement réduit.
6. La grappe tactile : le corps à corps à 55 points, les autres à 44, aucun disque ne se touche ; les lèvres et les anneaux ; l'éclat d'encre à la pression ; le voile du dash coupé en haut du disque ; la respiration des disques suggérés ; les sigles pâlis quand l'encre manque ; pas de disque Orpiment avant le déblocage, puis le disque arrive.
7. La barre rapide : une colonne dans le coin en bas à droite, le Menu au pied, qui ne touche ni le dock ni la barre de glyphes sur un écran de 1280 à 1600 de large (D-157) ; icônes, la touche du Menu sur son capuchon à gauche du bouton, le badge des récompenses ; l'autocollant Jouer à gauche du disque Menu sur téléphone, caché en file et en combat.
8. Le verrou : losange d'encre bordé de feuille, plaque du nom et de la vie sous lui, passage à la craie à 120 studs, chevron au bord de l'écran tourné vers une cible hors champ (surtout derrière la caméra), « Aucune cible » avec un clic plus grave.
9. L'amas méta : en bas à gauche à la souris, en haut à gauche au toucher, où Folios, sceaux et file forment une rangée sous le niveau qui finit au-dessus du joystick (un pouce posé sur la carte des premiers pas marche) ; sceau de niveau, Folios qui comptent en montant, « + » vers l'onglet Folios, sceaux des récompenses, pilule de file (vague, secondes, croix qui quitte) ; la carte des premiers pas, cochée puis tamponnée et repliée ; la récompense du jour qui s'ouvre seule trois secondes après l'arrivée.
10. Les puces fantômes : leurs touches au-dessus d'elles, alignées ; elles reviennent 1,5 s après une séquence ratée.
11. Le spectateur : le dock sort, la plaque « Tu regardes {name} » entre à sa place, les deux disques changent de coéquipier, et le dock revient à la vie suivante ; à la manette, LB et RB font de même, nommés sur leurs capuchons à côté des disques, sans lancer une action du jeu.
12. Le hub : plaques d'encre lisibles de loin ; les invites du terminal et du kiosque en pilule d'encre (touche « E », « RB » à la manette, rien au toucher) ; un appui sur la pilule au toucher ouvre l'écran (`InputHoldBegin`). Si l'invite personnalisée ne répond pas au toucher, garder le style par défaut pour le toucher seulement et le noter.
13. Règle 11 : en match et dans les deux arènes, aucune couleur de valeur (jaune primaire, pourpre, raretés) nulle part à l'écran.
14. Le coût : compteurs d'objets GUI et MicroProfiler sur le téléphone émulé (`docs/PERFORMANCE.md`), et une simulation de daltonisme sur les captures (vie contre encre, Rare contre Épique, chapitres, sigles).

**Les écrans de menu (tranches A et B) :**
15. Le Menu : les tuiles tiennent sans défilement sur téléphone, à l'échelle de texte 1,3 aussi ; leurs badges disent la même chose que le bouton Menu et les sceaux du HUD, avant et après une récupération ; « + » ouvre la Boutique sur l'onglet Folios et Retour revient au Menu ; à la manette, le focus arrive sur Jouer, Droite mène à la Boutique, Gauche depuis la Boutique ou les Quêtes revient à Jouer ; Options et Inviter en icônes de 44.
16. Jouer : les disques des combattants sur leurs taches, l'anneau jaune qui respire autour de la carte en file, le voile de craie sur l'autre, le chronomètre qui avance chaque seconde ; après 240 s seul en file, la carte « Personne en file pour l'instant » avec Réessayer et Retour au hub, et un toast d'information (médaillon « i », jamais le « ! » rouge).
17. La Boutique : cartes de 260 × 330 à la souris, de 400 de large et de la hauteur de la fenêtre au toucher (D-158) ; ombres non rognées par la barre de défilement ; prix qui passent à la ligne sur une carte de 260 à la souris et côte à côte sur la légendaire et sur toute carte au toucher, l'aperçu de l'article visible au-dessus sur un 667 × 375 ; la fiche d'achat au-dessus de la carte, B qui ne ferme qu'elle, les trois points d'attente, le tampon « Acquis ! » et l'éclat quand l'article arrive, la secousse sur `shop.notEnoughFolios`, le toast après 5 s de silence, « Obtenir des Folios » qui change d'onglet ; un clic quand le joueur choisit un onglet, aucun quand l'écran s'ouvre sur l'onglet Folios ; les boutons Robux grisés tant que les identifiants de `MonetizationConfig` sont à 0.
18. Le Battle Pass : la route centrée sur le palier courant pendant l'entrée, les colonnes chargées par dix en glissant, le défilement dans les deux sens sur un petit téléphone, 700 objets GUI au plus à l'ouverture, le balancement des boutons Récupérer ; « Tout récupérer » qui décompte, sans frappe de limite de `ClaimBattlepassReward` dans le journal du serveur sur vingt récupérations.
19. La récompense du jour : sept cartes, la septième deux fois plus large avec son ruban au-dessus du bord, la carte du jour qui respire avec son badge, le tampon et l'éclat de cinq taches à la récupération, les Folios qui comptent, la ligne en squelette avant le profil ; ouverte seule, elle dit bien ce que le serveur accorde (pas « déjà récupérée » quand le badge disait « ! »).
20. Les quêtes : le balancement de ±2° d'un bouton dans une liste, les taches derrière le sceau, le décompte sous chaque en-tête, les squelettes, la pilule de Folios qui compte après une récupération, le toast `common.pendingTimeout` quand le serveur ne répond pas.
21. L'équipement : la grille à 0,68 et à l'échelle de texte 1,3, le nombre d'objets par onglet (environ 65 par carte), la barre de 28 logements d'un compte développeur, la bande « Annuler » qui monte dans la carte et part avant elle, les capuchons à mot (« Maj droite », « Clic molette »), « +4 emplacements » grisé tant que le pass n'a pas d'identifiant.
22. Le classement : les portraits du podium (et l'initiale quand ils manquent), la ligne du joueur épinglée au pied sans osciller, « Me trouver » qui la centre, l'état d'échec quand le service ne répond pas.
23. Les options : le capuchon centré dans sa touche, la capture qui respire, une sauvegarde toutes les 2 s au plus, un refus qui remet la ligne, la feuille « Réinitialiser » (le seul bouton rouge des menus) et B qui ne ferme qu'elle, les lignes d'accessibilité qui suivent le menu Roblox, l'aperçu des effets au nouveau volume.
24. Le résultat : le monde assombri à 0,25, les taches et le trait de l'issue, la défaite qui ne rebondit pas, les pièces qui volent vers les Folios, l'anneau conique qui se vide et s'arrête à la première touche du joueur, la carte qui défile sur le 667 × 375, les détails repliés au toucher.
25. Le verrou à 34 pixels : le losange plus grand, sa plaque dessous, sans chevauchement.
