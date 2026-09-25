# Style des effets — trois prototypes, un choix

Planche : `prototypes.jpg`, avec la Marque dans les trois styles, figée au labo au départ, en vol et à l'impact. Ces prototypes ont été montés dans des copies de travail ; seul le style retenu entre dans le code.

| Style | Idée | Ce qu'on a vu |
|---|---|---|
| **A — Encre vive** | trait de pinceau, taches et éclaboussures d'encre, contour charbon | impact net et fort (tache noire, gerbe rouge, traits d'encre, anneau sombre au sol) ; l'éclaboussure monte au-dessus de la cible ; vol encore discret |
| **B — Poudre de pigment** | cœur chauffé qui brille, poudre qui explose et freine, étincelles en étoile, onde de choc | le plus spectaculaire (halo, rayons, grande onde face à la caméra) ; mais le blanc domine sur le vélin, la poudre se perd, et l'effet se lit comme de la « magie » générique plutôt que de l'encre |
| **C — Enluminure** | trait calligraphique avec liseré lumineux, sceau rayonnant | la traînée d'encre sombre à bord brûlant se lit très bien en vol ; le sceau pâle à l'impact manque de contraste (clair sur clair) |

## Notes (sur 5)

| Critère | A | B | C |
|---|---|---|---|
| Lisibilité | 4 | 4 | 3 |
| Contraste sur le vélin | 4 | 3 | 3 |
| Couleur du pigment | 4 | 3 | 3 |
| Dynamisme | 3 | 5 | 2 |
| Impact | 4 | 5 | 3 |
| Identité Vellum | 5 | 2 | 4 |

## Choix : « Encre vive à cœur chauffé » (D-119)

La base est **A**, parce que c'est de l'encre et qu'elle tranche sur le vélin. On y greffe le meilleur des deux autres :
- **de B**, le cœur chauffé qui brille (petit, au centre seulement), les étincelles en étoile et l'onde de choc face à la caméra ;
- **de C**, la traînée d'encre sombre à bord brûlant.

Règle de couleur, par couche (`Role`) :

| Rôle | Rendu | Usage |
|---|---|---|
| Cœur | pigment chauffé à 72 % vers le blanc, lumineux (`Glow`, `Brightness`), qui refroidit dans le pigment | le centre d'un éclat, jamais plus |
| Pigment | le pigment saturé, humide puis sec | le corps de l'effet |
| Encre | le charbon de la page | contour, ombre, taches : ce qui détache l'effet du sol clair |

## Palettes par pigment

| Pigment | Cœur (chauffé) | Pigment | Humide | Sec | Encre |
|---|---|---|---|---|---|
| Cinabre | #F4C8C1 | #D93A22 | #DB4E37 | #B2331E | #17150F |
| Indigo | #C4CCDF | #2E4A8C | #445C94 | #293F73 | #17150F |
| Terre d'Ombre | #D6CCC5 | #6B4A2F | #7A5C42 | #5A3F29 | #17150F |
| Vert-de-gris | #CEE7DF | #4FA88C | #61AF94 | #448B73 | #17150F |
| Orpiment | #F9EDC1 | #E8C022 | #E8C437 | #BE9E1E | #17150F |

Le cœur n'est **jamais du blanc pur** : dans Vellum, le blanc veut dire « invulnérable » (règle 7 de la charte). L'or reste réservé à l'Orpiment : une touche dorée sur un autre pigment se lirait comme un deuxième école.

## Halo global (Bloom) — proposé à part, non appliqué

Le jeu a déjà un Bloom au repos, d'intensité 0,25 et de seuil 1,6. Tant que rien ne dépassait une luminosité de 1, il ne servait à rien. Avec les cœurs à `Brightness` 2 à 4, **seuls les cœurs des sorts franchissent le seuil**. Le halo existe donc désormais là où il faut, sans toucher au rendu du reste du jeu.

Je recommande de **ne pas** monter le Bloom global : cela délaverait le vélin et les interfaces. Le flash d'impact ajoute déjà +0,6 de Bloom pendant 0,2 s.
