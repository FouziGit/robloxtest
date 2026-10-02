# Le Lavis (Indigo + Indigo)

## Avant — diagnostic

| Instant | Ce qu'on voit | Problème |
|---|---|---|
| départ 0,10 s | une bouffée de fumée bleue et une tache au sol devant le personnage, anneau fin | aucun geste lisible ; la « vague » n'est qu'une fumée |
| 1er coup 0,12–0,14 s | le mannequin est déjà touché ; seul un fin croissant bleu sur son flanc | **les dégâts précèdent le dessin** : le front dessiné est encore au lanceur |
| +0,3 s | file de bouffées gris-bleu toutes identiques, taches bleues, brume au loin | rythme mécanique, gris, sans front net |
| +0,6 s (de dos) | presque rien | contraste faible sur le vélin |

## Notes (sur 5)

| Critère | Avant |
|---|---|
| Lisibilité | 2 |
| Contraste | 2 |
| Couleur du pigment | 2 |
| Dynamisme | 1 |
| Impact | 1 |
| Performance | 3 |

## La vague d'encre (D-273)

À la demande du développeur, d'après ses références (`ref-1.jpg` en jeu, `ref-2.jpg` planche annotée, `ref-3.jpg` quatre vues) : le front de pinceau devient une vague d'encre indigo en volume — corps (pigment), écume de la crête (cœur), encre (contour en coque inversée, lignes de flux, fouets). `modele.png` : la planche du modèle livré, rendue comme le jeu la dessine (`tools/meshes/preview.py`), six vues dont les deux du lanceur. Choisie entre trois constructions (profil balayé, brins, feuilles superposées) par un juge, deux tours de retouche, vérifiée par un relecteur indépendant. Les planches au labo Studio (avant/après, deux tours, notes) restent à faire.

### Au labo Studio (1er octobre 2026) — `corps.jpg`

Vue dans le vrai moteur : une vraie vague de profil (volute indigo sur un creux sombre, contour d'encre, fouets vers le lanceur), lisible de dos depuis la caméra du lanceur, posée au sol (pied 0,3 stud sous la page). Tour 1 : écrasée à 45 % de sa hauteur, le contour et le noir du creux s'étalaient en une dalle noire. Tour 2 : elle s'écrase à 60 % puis s'enfonce dans la page en 0,3 s, et son encre s'efface pendant qu'elle retombe — il reste une vague indigo qui retombe. Charge : 6 Lavis à la fois, 16,7 ms en moyenne, 18,8 ms au pire, en Élevé comme en Performance.

| Critère | Corps (D-273) |
|---|---|
| Lisibilité | 5 |
| Contraste | 5 |
| Couleur du pigment | 4 |
| Dynamisme | 4 |
| Impact | 4 |
| Performance | 5 |

Reste : les fouets sont encore presque droits (des rubans animés comme le prototype de la boule de feu les feraient onduler).
