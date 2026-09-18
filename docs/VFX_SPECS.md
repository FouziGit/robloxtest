# Fiches d'effets

Une fiche par effet refait dans la passe 4 de `docs/JUICE_PLAN.md`. Elle dit ce que l'effet **veut faire
sentir**, ce qu'il a remplacé, et ce qui le tient. Les couches elles-mêmes sont dans
`src/shared/Config/VfxTimelineConfig.luau` ; cette page n'est pas leur copie, c'est leur raison.

## La barre

Aucun effet ne sort de cette phase avec moins de quatre couches, sans lumière dynamique, sans laisser de
trace là où il atterrit. `tests/VfxTimeline.spec.luau` refuse le build autrement :

| Règle | Où elle est vérifiée |
|---|---|
| Quatre couches minimum | compte des couches de toutes les phases |
| Une anticipation pour tout ce qu'un joueur exécute | dérivé de la présence d'une phase Lancement ou Voyage |
| Une phase de résidu partout | présence de la phase |
| Une trace au sol partout où quelque chose atterrit | toute timeline à phase Impact porte une couche `Mark` |
| Une lumière dynamique sur chaque glyphe | croisé avec `GlyphConfig.Glyphs` |
| Aucune interpolation linéaire | `Linear` absent de l'union `Ease`, et refusé en données |
| Un projectile ne vole jamais plus loin que sa portée | `Carrier.Travel` croisé avec `GlyphConfig.Range` |
| Un porteur pour chaque passager, un passager pour chaque porteur | `Ride` croisé avec `Carrier` |
| Aucune couleur dans une timeline | tout champ dont le nom contient « color » est refusé |

**Le son en couches n'est pas là.** La barre de la passe 4 le demande ; la passe 5 le construit en entier,
avec l'attaque, le corps, la queue, l'impact et la variation de hauteur. Aujourd'hui chaque effet joue un
son unique depuis son rendu, comme avant. Ce n'est pas fait, et ce n'est pas prétendu fait.

---

## `Melee` — le coup

**Ce qu'il doit faire sentir.** Le poids d'une main. C'est l'action la plus répétée du jeu — un joueur en
lance des centaines par match et un Colophon —, donc c'est elle qui décide si le jeu a du corps.

**Ce qu'il a remplacé.** Un rectangle blanc plat, tourné de septante degrés et interpolé en retour. Aucune
anticipation, aucune trace, et la même forme quelle que soit la main.

**Comment il est construit.** Deux images de rassemblement — assez court pour ne jamais retarder l'entrée,
assez long pour que le coup ait un avant —, puis un trait balayé devant, sur la texture de pinceau plutôt
qu'en arc dur : un balayage qui lit comme une **forme** est une arme, un balayage qui lit comme une
**marque** est une main. Le finisher est le même trait, plus lourd, par l'échelle.

**Il est blanc, pas coloré.** Le corps-à-corps n'appartient à aucune école, et la règle 2 dit qu'une
couleur à l'écran nomme une école. Celle-ci n'en nomme aucune.

---

## `Brand` — la Marque (Cinabre, projectile)

**Ce qu'il doit faire sentir.** Quelque chose de **lancé**. Le premier glyphe que tout joueur apprend et
celui qu'il jette le plus.

**Ce qu'il a remplacé.** Une boule portant la classe `Fire` de Roblox, volant en ligne droite à vitesse
constante pendant une seconde pleine. Trois mots sur quatre sont une règle enfreinte : rien ne se déplace
en linéaire, rien dans ce jeu n'est un effet de moteur d'origine, et une chose lancée par une main décrit
une courbe.

**Comment il est construit.** L'encre est **aspirée** dans la main avant d'être jetée — vitesse négative,
ce qui fait lire l'anticipation comme une charge et non comme une dépense déjà en cours. Puis un porteur
invisible vole quatre-vingt-dix studs en une seconde, avec trois studs de montée et de descente : à peine
visible, et c'est toute la différence entre lancé et tiré. La traînée, la fumée et la lumière **montent
dessus** ; elles ne peuvent donc pas être en désaccord sur l'endroit où se trouve le projectile, parce
qu'il n'y en a qu'un.

**Il n'a pas de phase d'impact.** Sa détonation est un paquet distinct : le serveur le fait exploser et
émet `Explosion`. Cette séparation est juste et non accidentelle — le projectile ne sait pas où il finira,
et l'explosion ne sait pas d'où il venait.

---

## `Explosion` — la détonation partagée

**Ce qu'il doit faire sentir.** Que la page a été transpercée.

**Ce qu'il a remplacé.** Une sphère qui grossit et un jet de braises, avec une secousse de caméra sur
l'ancienne échelle numérique.

**Comment il est construit.** Un anneau qui s'ouvre, la floraison d'encre de 64 images — le seul endroit du
jeu où un flipbook justifie sa taille —, des étincelles directionnelles, une lumière forte et brève, une
secousse lourde et un blanchiment de page. Puis **deux** traces au sol qui se superposent : le réseau de
fissures et la tache d'encre, à durées différentes, parce qu'une seule trace lit comme un décalque et deux
lisent comme un endroit où il s'est passé quelque chose.

**Il est à la taille des dégâts.** Le serveur envoie le rayon qu'il a réellement utilisé et la timeline est
mise à l'échelle par le rapport. Une explosion dessinée plus petite que ce qu'elle blesse est le mensonge
le plus coûteux qu'un jeu de combat puisse faire.
