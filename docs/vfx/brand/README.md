# La Marque (Cinabre + Cinabre)

Planches (labo Studio, temps d'effet depuis le paquet de lancer ; lignes = caméra de jeu, profil, gros plan d'impact) :
- `avant.jpg` — l'effet d'origine ;
- `tour1.jpg` — premier tour du style « encre vive à cœur chauffé » (D-119) ;
- `apres.jpg` — tour 3, l'état livré ;
- `avant-apres.jpg` — les mêmes instants, avant et après.

Les planches « avant » sous-estiment la traînée d'origine : le labo d'alors changeait la durée de vie des traînées en plein vol, ce qui les effaçait. Même corrigé, elle ne rendait presque rien (texture de pinceau étirée sur tout le ruban, voir D-119).

## Avant — diagnostic

| Instant | Ce qu'on voit | Problème |
|---|---|---|
| lancer 0,03 s | de dos : rien ; de profil : une petite goutte devant le ventre | le sort naît caché derrière le corps |
| départ 0,06 s | halo rose au sol, sceau à peine visible autour de la tête | aucun éclat dans la main ; le sceau commun a 0,24 s de retard |
| trajet 0,16 s | de dos : rien (le projectile est derrière la tête) ; de profil : goutte fine, deux fumées pâles, croissant réduit à un trait | traînée invisible (≈30 % d'opacité) et répétée chaque stud ; étincelles vers le haut |
| impact 0,24 s | de dos : image entière blanchie ; gros plan : mannequin brûlé en blanc, anneau pâle au sol | `PageFlash` −55 % de saturation ; formes posées à plat ; l'impact est caché par la tête du lanceur |
| +0,1 s | de près : couronne rouge vive au sol, nuage rouge, papiers noirs | le meilleur instant, mais trop tard et trop bas pour la caméra de jeu |
| +0,3 s | grand nuage rouge flou et uniforme | nuage mou, pas de silhouette nette |
| fin 1,4 s | brume rouge autour du mannequin, petite tache | trace faible |

## Les tours

| Tour | Ce que la planche a montré | Correction |
|---|---|---|
| essais | cœur pâle invisible sur la page ; l'éclat de la main caché par la hanche ; traînée texturée au pinceau réduite à une tache floue | cœur entouré d'une tache de pigment qui claque (`Pop`), déplacé d'un stud hors du corps ; traînées nues effilées (encre + trait chaud) |
| 1 | les trois temps se lisent ; mais depuis la caméra de jeu l'impact est caché derrière la tête du lanceur, les gouttes montent et flottent en nuage, le flash blanchit trop | — |
| 2 | gerbe d'encre verticale, anneau de choc plus grand, gouttes lestées (`Weight`), flash moins fort : l'anneau et la gerbe dépassent la tête du lanceur | — |
| 3 | à +0,3 s il restait des gouttes grises dans le ciel | gouttes plus courtes et plus petites : à +0,3 s il ne reste que les papiers d'encre et la brûlure |

## Notes (sur 5)

| Critère | Avant | Tour 1 | Après (tour 3) |
|---|---|---|---|
| Lisibilité | 1 | 4 | 4 |
| Contraste | 1 | 4 | 4 |
| Couleur du pigment | 2 | 4 | 5 |
| Dynamisme | 2 | 4 | 4 |
| Impact | 1 | 3 | 4 |
| Performance | 4 | 4 | 4 |

Ce qui reste à 4 et pourquoi : depuis la caméra de jeu, une cible droit devant est derrière la tête du lanceur — l'anneau, la gerbe et la lumière au sol la signalent, mais le cœur de l'impact se voit de profil et chez la cible, pas chez le lanceur.

## Performance

`stress` du labo, Studio sur Mac (pas une mesure d'appareil) :

| Charge | Moyenne | 95e centile | Pire image | Couches au pic |
|---|---|---|---|---|
| 1 Marque + son explosion | 16,7 ms | 18,2 ms | 18,7 ms | 18 |
| 6 Marques + 6 explosions, niveau Haut | 16,7 ms | 18,2 ms | 18,8 ms | 90 (plafond atteint, les plus anciennes couches ordinaires partent) |
| idem, niveau Performance | 16,7 ms | 18,3 ms | 18,8 ms | 24 (plafond) |

Coût par effet (`lune run scripts/effect-cost`) : Marque 12 couches au pic, 69 particules ; explosion 11 et 60 ; éclat d'appui 4 et 10.
