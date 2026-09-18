# Plan d'exécution — passe Identité & Game Feel

Découle de `docs/JUICE_AUDIT.md` (le constat) et de `docs/ART_BIBLE.md` (la direction retenue :
VELLUM). Chaque phase se termine par des portes vertes, un ou plusieurs commits atomiques, et un push.

Principe de séquencement : **ce qui se répète le plus est refait en premier.** Un joueur presse M1 et
l'esquive des centaines de fois par match, et lance Raijin une fois. La sensation se gagne donc sur le
M1 avant de se gagner sur l'ultime.

## Phase 1 — Le lexique et le lore

Renommage complet vers le lexique de l'`ART_BIBLE` : Glyphe, Encre, les cinq pigments, les cinq rangs,
Volume, L'Effacement, Épreuve. Touche les identifiants de configuration, les clés de localisation EN et
FR, les documents, et le nom du projet.

- Les identifiants internes (`Fireball`, `Fire`) deviennent les identifiants de pigment et de glyphe.
- Migration de profil : un profil enregistré avec les anciens identifiants doit continuer à charger. La
  migration mappe l'ancien nom vers le nouveau, et un test le prouve.
- Sortie : plus aucun terme emprunté. Vérifié par un test qui interdit la liste des mots bannis.

## Phase 2 — `Feel` et `FeelConfig`

Un module client unique appelé par tous les systèmes, et un seul fichier de réglages.

| Brique | Ce qu'elle fait |
|---|---|
| Hit-stop | gel réel de 40 à 90 ms, échelonné sur les dégâts, jamais cumulé |
| Camera shake | bruit de Perlin, amplitude / fréquence / décroissance par profil d'impact, atténué par la distance |
| FOV punch | impulsion au cast et à l'esquive, retour en spring |
| Hit flash | `Highlight` bref sur la cible touchée |
| Knockback | courbe, plus linéaire |
| Nombres de dégâts | flottants, typographie de l'`ART_BIBLE`, critique distinct |
| Springs | un ressort réutilisable pour l'UI et la caméra |
| Haptique | impact et cast, mobile et manette |

Appliqué d'abord au M1 et à l'esquive. Tout est chiffré dans `FeelConfig`, rien dans le code.

## Phase 3 — Le pipeline VFX

- `VfxLibrary` passe d'un ensemble de fonctions à un **système de timelines à phases** :
  Anticipation → Cast → Voyage → Impact → Résidu. Chaque phase déclare ses couches.
- **Pooling** : aucune création ou destruction d'instance en boucle. Un pool par type, réinitialisation
  à l'emprunt, retour au `Trove` de l'effet.
- **Textures générées** : scripts Python dans `tools/textures/` produisant fumée, étincelles, fissures,
  ondes de choc, flipbooks d'explosion et dégradés, cohérents avec la palette. PNG et scripts commités.
- `AssetIds` centralisé, avertissement explicite par identifiant manquant, jamais de plantage.
- Configuration de `Lighting` et `Atmosphere` selon l'`ART_BIBLE`, et les cinq effets de
  post-traitement, tous animés et jamais permanents.

## Phase 4 — Refonte sort par sort

Du plus utilisé au plus rare. Un sort refait = un commit + sa fiche dans `docs/VFX_SPECS.md`.
Ordre : Cast et Hit (partagés par tout le monde) → Boule de Feu → mêlée et esquive → les quatre glyphes
de base → les glyphes de niveau → les quatre glyphes d'Orpiment → L'Effacement.

Aucun sort ne sort de cette phase avec moins de 4 couches, une lumière dynamique, une trace au sol et
un son en couches.

## Phase 5 — Audio

Chaque glyphe devient attaque + corps + queue + impact. Variation de hauteur de ±5 %. Ducking de la
musique sur les impacts lourds. **La séquence devient musicale** : une note par pigment, montant avec
la longueur de la séquence, de sorte qu'une séquence réussie sonne comme une phrase résolue et une
séquence ratée comme une dissonance.

Sources libres de droits vérifiables uniquement, ou sons générés par script. Chaque fichier est tracé
dans `docs/ASSETS.md` avec sa source et sa licence.

## Phase 6 — Interface

Application de l'`ART_BIBLE` : palette vélin et charbon, pigments, typographie. Springs partout, barre
de vie avec fantôme qui rattrape, compteur de séquence, écran de résultat composé pour la capture
d'écran.

## Phase 7 — Le monde

`Lighting`, `Atmosphere`, ciel, brume. Hub et arènes retravaillés sous la contrainte « le décor n'est
jamais saturé ». Sol qui réagit. L'Effacement mis en scène : annonce, montée, phases lisibles.

## Phase 8 — La boucle

Dans l'ordre de priorité de la mission :

1. Plafond de skill : annulation de récupération par esquive à coût d'Encre, extension de séquence par
   timing serré, et une **matrice outil → contre** écrite dans `docs/GAME_DESIGN.md`. Chaque glyphe a
   une réponse explicite.
2. Boucle courte : relance en un clic depuis l'écran de résultat, moins de dix secondes entre deux
   duels.
3. Progression lisible juste après le duel, barre animée, prochaine récompense visible.
4. Feedback de maîtrise : compteur de séquence, note d'exécution de fin de duel, meilleure séquence
   personnelle, défis d'exécution.
5. Social : spectateur après élimination, emotes, revanche directe, partage.
6. Onboarding de 90 secondes, premier glyphe lancé avant la quinzième seconde, sans texte à lire.
7. Variable sans être manipulatoire : rotation quotidienne, défis tournants, Effacement annoncé.

## Phase 9 — Performance et finition

`docs/PERFORMANCE.md` : plafond de particules simultanées, coût client estimé par glyphe, stratégie de
pooling, et dégradation automatique si le nombre d'images par seconde chute. Trois réglages graphiques
plus un mode Performance qui coupe le post-traitement. Vérification qu'un duel complet ne laisse aucune
instance ni aucune connexion derrière lui.

## Ce qui est bloquant à chaque commit

Portes de qualité vertes, tests verts, `rojo build` vert, CI verte. Aucun texte joueur en dur. Aucun
TODO, aucun placeholder, aucun effet provisoire : ce qui n'est pas fini est retiré.

## Dépendances externes

Aucune n'est ajoutée sans vérification préalable de son existence, de sa licence et de sa maintenance
sur Wally et GitHub. Le verdict par bibliothèque est consigné dans `docs/DECISIONS.md`. Le principe est
de ne pas réécrire ce qui existe et est maintenu, et de ne pas dépendre de ce qui ne l'est plus.

## Ce que je ne ferai pas

- Pas de changement de framework d'interface pour le plaisir. L'interface actuelle est faite de
  composants maison propres, avec un thème central. Le gain d'un framework réactif ne compense pas la
  réécriture de dix écrans, sauf preuve du contraire consignée dans `DECISIONS`.
- Pas de modèle importé de la boîte à outils. La provenance douteuse est une cause classique de
  suppression de jeu.
- Pas d'effet dont je ne peux pas garantir le coût. Un effet qu'on ne peut pas afficher partout est un
  effet qu'on ne livre pas.
