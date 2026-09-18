# Game Design — Vellum V2

## 1. Piliers

1. **Le combo est le skill.** Un glyph = une séquence de touches de pigment. La vitesse d'exécution, la mémorisation et la lecture de l'adversaire (mind games : feinter un début de combo, punir un cast long) font la différence, pas les statistiques.
2. **Serveur autoritaire, client expressif.** Le serveur décide de tout ce qui compte (dégâts, ressources, positions de référence) ; le client rend des effets riches (particules, secousses, hit-stop) sans jamais être cru.
3. **Rejouable.** Modes courts (1v1 en 2-3 min, 3v3 en 4-5 min), classement saisonnier, quêtes, pass, World Boss périodique.
4. **Équitable.** Aucun achat n'ajoute de puissance brute : Orpiment est un *sidegrade* atteignable gratuitement, les cosmétiques sont purement visuels, les slots de loadout supplémentaires offrent de la variété, pas de l'avantage.

## 2. Contrôles

| Action | Clavier (défaut) | Manette | Tactile |
|---|---|---|---|
| Cinabre / Indigo / Terre d'Ombre / Vert-de-gris | `J` / `K` / `L` / `H` | D-pad haut / droite / bas / gauche | boutons colorés, pouce droit |
| Orpiment (débloquée) | `U` | `Y` | bouton jaune |
| Corps à corps (M1) | clic gauche | `X` | bouton |
| Dash | Maj gauche | `B` | bouton |
| Garde | `F` | `LT` | bouton (maintenir) |
| Menu | `M` | `Select` | bouton |
| Saut / double saut | Espace ×2 | `A` ×2 | bouton saut Roblox |

Aucune touche par défaut n'entre en conflit avec WASD (QWERTY), ZQSD (AZERTY), le zoom (I/O), le classement (Tab) ni le sac (1-9). Tout est réassignable (clavier et manette) dans les options.

## 3. Ressources et kit de base

- **Vie** : 100. Régénération 3/s hors combat après 8 s sans dégât.
- **Ink** : 100. Chaque glyph coûte 15-50. Régénération 12/s hors combat, 4/s en combat (6 s après avoir donné ou reçu un coup). Le encre est la vraie limite au spam ; les cooldowns empêchent la répétition d'un même glyph.
- **M1** : combo de 4 coups (8 / 8 / 8 / 14), fenêtre de chaînage 0,9 s, portée 7 studs. Le 4e coup projette (knockback + léger envol), étourdit 0,5 s, brise la garde, puis impose 1,2 s de recharge.
- **Dash** : 22 studs en 0,22 s, 0,25 s d'invulnérabilité, recharge 2,5 s, coûte 10 encre. Direction = déplacement en cours, sinon regard.
- **Garde** : -70 % de dégâts, marche à 50 %, 4 s max puis 1,5 s de recharge. Brisée (1 s de stun) par les *Ultimes* et par le 4e coup de M1.
- **Stun / ragdoll léger** : sur certains impacts (Empattement, Rupture, finisher M1) — jamais plus de 2 s cumulées.
- **Protection de spawn** : 4 s sans donner ni recevoir de dégâts. La **zone sûre** autour du spawn du hub est symétrique : un joueur à l'intérieur ne peut ni subir ni infliger de dégâts PvP (les mannequins restent frappables).

## 4. Combos : règles de résolution

Le résolveur (`ComboResolver`, module pur testé) applique :

1. La séquence tapée **est une recette et n'est le début d'aucune autre** → cast immédiat.
2. La séquence **est le début d'une recette plus longue** → attente de la touche suivante.
3. Sinon → reset (« aucun glyphe ne correspond »).
4. **Fenêtre d'extension** : si la séquence est *déjà* une recette **et** le début d'une plus longue (`Cinabre Cinabre` → `Cinabre Cinabre Terre d'Ombre`), le client n'attend que `ExtendWindowSeconds` (0,35 s) au lieu du timeout complet (1,2 s). Un joueur rapide enchaîne `Cinabre Cinabre Terre d'Ombre` en moins de 350 ms ; un joueur qui voulait `Cinabre Cinabre` ne perd que 350 ms. C'est le cœur du « fun par la vitesse d'exécution ».
5. Timeout complet (1,2 s) uniquement pour les séquences qui ne sont pas encore une recette.

Le serveur re-résout la séquence reçue ; il ne fait jamais confiance au client pour l'identité du glyph.

## 5. Roster (20 glyphes, Phase 2)

Archétypes : **Projectile** (ligne, esquivable), **AoE** (instantané devant soi), **Zone** (persistante, contrôle d'espace), **Mur** (défense), **Mobilité**, **Contre**, **Buff**, **Ultime** (long combo, gros coût, gros impact).

Légende combos : C Cinabre · I Indigo · U Terre d'Ombre · V Vert-de-gris · O Orpiment.

| Pigment | Combo | Glyph | Archétype | Coût | CD | Dégâts | Rôle |
|---|---|---|---|---|---|---|---|
| Cinabre | C C | Marque | Projectile | 20 | 4 | 25 | poke fiable, explose (rayon 7) |
| Cinabre | C V | Ligature | Mobilité | 15 | 6 | 6 | dash court qui laisse une traînée brûlante 2 s |
| Cinabre | C C V | Roussi | Zone | 35 | 12 | 10 ×3 | anneau autour de soi, zone anti-mêlée |
| Cinabre | C C U | Pâté | Ultime | 50 | 20 | 45 | projectile lourd en cloche, AoE 10, brise la garde |
| Indigo | I I | Lavis | AoE | 22 | 5 | 18 | ligne, knockback |
| Indigo | I C | Bavure | Zone | 28 | 8 | 8 ×3 | ralentit 60 % |
| Indigo | I V | Reliure | Contre | 30 | 12 | 10 | racine la cible devant soi 1,5 s |
| Indigo | I I U | Marge | Mur | 30 | 10 | 0 | bloque projectiles et M1 pendant 6 s |
| Terre d'Ombre | U U | Empattement | AoE | 22 | 5 | 22 | ligne, stun 0,4 s |
| Terre d'Ombre | U I | Pointillé | Projectile | 18 | 4 | 16 | ralentit 40 % 2 s |
| Terre d'Ombre | U V | Dorure | Buff | 25 | 14 | 0 | -40 % dégâts reçus 4 s, immunité au knockback |
| Terre d'Ombre | U U U | Rupture | Ultime | 45 | 15 | 35 | AoE 18, envol, stun 0,8 s |
| Vert-de-gris | V V | Balayage | AoE | 15 | 3 | 12 | cône, gros knockback, applique *Éventé* |
| Vert-de-gris | V C | Délié | Projectile | 15 | 3 | 14 | rapide, portée 60, applique *Éventé* |
| Vert-de-gris | V V I | Spiral | Zone | 35 | 12 | 6 ×4 | attire vers le centre |
| Vert-de-gris | V V U | Poncif | Zone | 30 | 10 | 5 ×3 | ralentit 30 %, brouille la vue (fog local) |
| Orpiment | O O | Rature | Projectile | 20 | 4 | 22 | hitscan instantané, portée 70 |
| Orpiment | O V | Insertion | Mobilité | 20 | 7 | 0 | téléport 18 studs, 0,4 s d'i-frames |
| Orpiment | O O U | Filigrane | Zone | 35 | 12 | 6 ×4 | micro-stun à chaque tick |
| Orpiment | O O O O | Colophon | Ultime | 55 | 25 | 40 | chaîne sur 3 cibles, stun 0,6 s |

Cibles d'équilibrage : temps pour tuer un adversaire qui esquive mal ≈ 12-15 s ; DPS soutenu des 2 touches ≈ 4-6/s ; un Ultime ne dépasse jamais 50 % de la vie. Les 8 glyphes V1 sont conservés (Marque, Lavis, Empattement, Balayage, Bavure, Marge, Roussi, Rupture) avec les coûts d'encre ci-dessus.

### Déblocages

- Par défaut : les 8 glyphes V1.
- Niveau 5 : Délié, Pointillé · niveau 10 : Ligature, Reliure · niveau 15 : Dorure, Poncif · niveau 20 : Spiral · niveau 25 : Pâté.
- **Orpiment** : pigment *sidegrade* — même budget de dégâts que les autres, mais hitscan / mobilité / contrôle au lieu de zones. Débloquée au **niveau 40** (grind ≈ 15-20 h) **ou** via le game pass Orpiment. Un joueur sans Orpiment n'est jamais désavantagé statistiquement : Orpiment échange la puissance de zone contre la précision.
- **Loadout** : 6 slots de base (max 10 avec le pass *Slots*). Équiper = choisir sa main ; les glyphes non équipés ne peuvent pas être lancés.

## 6. Interactions de pigment (simples, lisibles)

| Interaction | Règle serveur (`CombatService` tags) |
|---|---|
| **Le Vert-de-gris attise le Cinabre** | une cible touchée par un glyphe Vert-de-gris porte *Éventé* 3 s : +25 % de dégâts de Cinabre |
| **L'Indigo éteint le Cinabre** | une AoE/Zone d'Indigo lancée dans une zone de Cinabre active (Roussi, traînée de Ligature) la termine |
| **La Terre d'Ombre bloque** | Marge et Dorure arrêtent projectiles et knockback |
| **L'Orpiment conduit dans l'Indigo** | une cible dans une Bavure ou un Lavis en cours subit +25 % de dégâts d'Orpiment |

Chaque interaction est un bonus plat et visible (VFX + texte flottant), jamais un multiplicateur caché.

## 7. Modes

| Mode | Joueurs | Durée | Victoire | Récompenses |
|---|---|---|---|---|
| Hub | tous | libre | — | XP des mannequins, quêtes |
| 1v1 classé | 2 | 3 min, best-of-3 optionnel | KO adverse | XP, Ryo, Elo, pass |
| 3v3 | 6 | 5 min | équipe adverse éliminée ou plus de KO | XP, Ryo, Elo équipe, pass |
| World Boss | serveur entier | événement toutes les 20 min | boss vaincu avant le timer | contribution aux dégâts → XP/Ryo/pass |

Cycle d'un match : file → arène instanciée → téléport → compte à rebours 5 s → combat (PvP limité aux participants, spawn protection 4 s) → fin (KO, timer : vainqueur = plus de vie restante, égalité possible) → écran de résultat → retour hub → cleanup.

## 8. Hub et arènes (générés en code — points d'ancrage)

- **Hub** : plateforme 200×200, spawn au centre, anneau de mannequins (rayon 22), terminal de file (panneau interactif), tableaux de classement (SurfaceGui), boutique (panneau). Le remplacement par des assets doit conserver les noms `HubSpawn`, `QueueTerminal`, `LeaderboardBoard_<mode>`, `ShopKiosk`.
- **Arène 1v1** : plateforme 80×80 avec murs et kill zone sous le sol, `Spawn_Team1` / `Spawn_Team2` à 30 studs l'un de l'autre.
- **Arène 3v3** : 120×120, trois spawns par équipe espacés de 8 studs, deux murs bas centraux pour casser les lignes.
- **Arène Boss** : 160×160, spawns joueurs sur le périmètre, `BossSpawn` au centre.

## 9. Rétention

Quêtes journalières (3) et hebdomadaires (3) data-driven, streak de connexion (bonus croissant J1→J7), bonus de première victoire du jour, pass saisonnier 50 paliers (gratuit / premium), rang saisonnier (Vierge → Esquisse → Écriture → Enluminure → Codex) avec récompense de fin de saison, cosmétiques (skins de glyphes = palettes VFX, auras, traînées, effets de kill, titres).

Détails économiques : `docs/ECONOMY.md`.
