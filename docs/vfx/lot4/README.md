# Lot 4 — Ligature, Pâte, Entrave

Planche : `avant-apres.jpg` (labo Studio ; en haut avant, en bas après). Le feu a sa propre planche :
`../feu/avant-apres.jpg` (D-123, D-124).

| Glyphe | Ce que l'avant montrait | Ce qui a changé | Notes avant → après |
|---|---|---|---|
| Ligature | des **flaques** plates étalées au passage de la course, alors que le serveur les pose toutes au paquet et les brûle dès son premier tick ; « les flammes c'est des flaques » | les cinq flaques s'étalent en un dixième de seconde là où le serveur les a posées (c'est le sol qui blesse) ; dessus, **un feu** : lit de langues de pigment debout sur toute la course, cœur chaud en bas, suie d'encre au-dessus, qui **bondit** à chaque tick du serveur ; émis par le rendu, pour que le moteur ne l'éclaircisse pas | 2/2/2/1/1/4 → 4/4/4/4/3/4 |
| Pâte (ultime) | partie 0,28 s après le météore qui blesse, plus vite et plus bas que lui ; en vol, un nuage flou | part en 0,03 s sur l'**arc du serveur** ; une **comète de feu** (goutte, ruban d'encre, flammes qui restent le long de l'arc, perles qui retombent) ; l'éclat pose la goutte là où le météore du serveur a éclaté, et elle sèche où il s'est arrêté s'il n'éclate pas | 1/1/2/2/2/4 → 3/3/4/4/4/4 |
| Entrave | des anneaux fins au point de lancer | jouée **sur la cible prise** (la première du paquet) : sceau au sol, flaque d'indigo, quatre barreaux d'encre debout jusqu'à la fin de l'immobilisation, un cœur | 2/2/2/2/2/4 → 3/3/3/3/3/4 |
| Brûlis (repris du lot 3) | une couronne de pointes rigides sur une grande tache : des flaques, pas du feu | un **anneau de feu au rayon du serveur** qui suit le lanceur, bondit à chaque tick (une gerbe par tick au lieu de cinq plans : le budget tient) | 3/3/4/4/4/4 → 4/4/4/4/4/4 |

Ce que le labo a appris :

- **Le temps réel ment autrement que le ralenti.** Un émetteur à 80 flammes/s n'en montre que cinq en
  temps réel (qualité graphique automatique du moteur) ; le même débit émis par le rendu (`Driven`) est un
  mur de feu. Tout ce qui doit être dense se juge aussi à `slow = 1`.
- **Un sort qui ne touche personne s'éclate ailleurs.** La Pâte vole soixante-dix studs, par-dessus un
  mannequin à vingt : la caméra « impact » cadre maintenant l'éclat là où il a eu lieu.
- La caméra de profil monte d'un tiers de l'écart pour passer au-dessus des mannequins.
