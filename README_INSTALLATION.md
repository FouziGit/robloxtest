# Jeu de Jutsus — Guide d'installation Roblox Studio

Architecture complète : Jutsus à combos de Mantras, Options (rebind des touches),
Battlepass 1-50 avec XP, et sauvegarde DataStore unique.

## 1. Guide de placement

Chaque fichier `.lua` de ce dossier se copie-colle dans Roblox Studio à l'emplacement
indiqué. **Respecte le type de script** (Script / LocalScript / ModuleScript) et le nom.

| Fichier | Emplacement dans Studio | Type | Nom de l'objet |
|---|---|---|---|
| `ReplicatedStorage/Modules/GameConfig.lua` | ReplicatedStorage > Modules | **ModuleScript** | `GameConfig` |
| `ReplicatedStorage/Modules/JutsuConfig.lua` | ReplicatedStorage > Modules | **ModuleScript** | `JutsuConfig` |
| `ReplicatedStorage/Modules/BattlepassConfig.lua` | ReplicatedStorage > Modules | **ModuleScript** | `BattlepassConfig` |
| `ServerScriptService/Modules/DataManager.lua` | ServerScriptService > Modules | **ModuleScript** | `DataManager` |
| `ServerScriptService/Modules/BattlepassService.lua` | ServerScriptService > Modules | **ModuleScript** | `BattlepassService` |
| `ServerScriptService/Modules/JutsuService.lua` | ServerScriptService > Modules | **ModuleScript** | `JutsuService` |
| `ServerScriptService/Modules/JutsuEffects.lua` | ServerScriptService > Modules | **ModuleScript** | `JutsuEffects` |
| `ServerScriptService/MainServer.server.lua` | ServerScriptService | **Script** | `MainServer` |
| `StarterPlayer/StarterPlayerScripts/JutsuController.client.lua` | StarterPlayer > StarterPlayerScripts | **LocalScript** | `JutsuController` |
| `StarterPlayer/StarterPlayerScripts/OptionsMenu.client.lua` | StarterPlayer > StarterPlayerScripts | **LocalScript** | `OptionsMenu` |
| `StarterPlayer/StarterPlayerScripts/BattlepassMenu.client.lua` | StarterPlayer > StarterPlayerScripts | **LocalScript** | `BattlepassMenu` |

À créer à la main dans Studio :
- Un **Folder** nommé `Modules` dans **ReplicatedStorage** (contient les 3 configs).
- Un **Folder** nommé `Modules` dans **ServerScriptService** (contient les 4 modules serveur).
- (Optionnel) Un **Folder** nommé `Enemies` dans **Workspace** pour tes PNJ ennemis.

Le dossier `Remotes` dans ReplicatedStorage est créé **automatiquement** par
`MainServer` au démarrage — ne le crée pas toi-même.

## 2. Activer les DataStores

1. **File > Game Settings > Security** → active **Enable Studio Access to API Services**.
2. Le jeu doit être **publié** (File > Publish to Roblox) pour que les DataStores marchent.

Sans ça, le jeu reste jouable en Studio mais rien n'est sauvegardé
(un avertissement s'affiche dans l'Output).

## 3. Ajouter des ennemis

Deux façons (au choix) de faire qu'un PNJ donne de l'XP quand il meurt :
- Pose ton Model dans le dossier `Workspace > Enemies` → il est tagué automatiquement.
- Ou ajoute-lui le tag CollectionService **`Enemy`** (via le Tag Editor de Studio).

Dans les deux cas, le Model doit contenir un **Humanoid** (présent au moment
du dépôt, ou ajouté dans les 10 secondes) pour que le kill soit compté.

Chaque kill rapporte `GameConfig.XP.PerEnemyKill` XP (50 par défaut) au joueur
qui a porté le dernier coup avec un jutsu.

## 4. Contrôles en jeu

| Touche | Action |
|---|---|
| `A` | Mantra **Feu** (réassignable) |
| `E` | Mantra **Eau** (réassignable) |
| `R` | Mantra **Terre** (réassignable) |
| `T` | Mantra **Vent** (réassignable) |
| `O` | Menu Options (rebind des touches) |
| `B` | Menu Battlepass |

> **Clavier QWERTY ?** La touche `A` sert aussi au déplacement latéral sur
> QWERTY. Les défauts A/E/R/T sont pensés pour l'AZERTY ; un joueur QWERTY
> réassigne simplement Feu sur une autre touche dans le menu Options (`O`).
> Les touches de déplacement W/S/D/Z/Q sont exclues de la réassignation.

Combos livrés :

| Combo | Jutsu |
|---|---|
| Feu + Feu | Boule de Feu |
| Eau + Eau | Vague Aquatique |
| Terre + Terre | Piques de Terre |
| Vent + Vent | Rafale Tranchante |
| Eau + Feu | Brume Bouillante |
| Eau + Eau + Terre | **Mur de Boue** |
| Feu + Feu + Vent | Tempête de Braises |
| Terre + Terre + Terre | Séisme |

## 5. Comment étendre

- **Ajouter un jutsu** : une entrée dans `JutsuConfig.Jutsus` + une fonction du même
  nom que son champ `Effect` dans `JutsuEffects`. Le client (détection de combo, HUD)
  et le serveur (validation, cooldown, XP) suivent automatiquement.
- **Modifier une récompense de palier** : édite `BattlepassConfig.Rewards[n]`.
- **Changer les courbes d'XP** : `GameConfig.PlayerXPForLevel` (niveau joueur)
  et `BattlepassConfig.XPForTier` (paliers du pass).
- **Changer les touches par défaut / timings / PvP** : tout est dans `GameConfig`.
- **Ajouter un champ sauvegardé** : ajoute-le au `PROFILE_TEMPLATE` de `DataManager` —
  la reconciliation l'injecte automatiquement dans les profils existants.

## 6. Architecture (qui parle à qui)

```
CLIENT                                   SERVEUR
JutsuController ──CastJutsu──────────▶ JutsuService ──▶ JutsuEffects (dégâts, visuels)
                                            │ XP jutsu
OptionsMenu ──UpdateKeybinds─────────▶ JutsuService ──▶ profil (Keybinds)
                                            ▼
BattlepassMenu ──ClaimBattlepassReward▶ BattlepassService ◀── XP kill (MainServer, ennemis)
                                            │
Tous ◀──────DataChanged / JutsuFeedback─────┘
                                            ▼
                                       DataManager ──▶ DataStore (1 clé/joueur :
                                       touches + XP + niveau + battlepass + monnaie)
```

Sauvegarde : automatique toutes les 2 minutes, à la déconnexion, et à la
fermeture du serveur (BindToClose). Verrou de session anti-doublon inclus.
