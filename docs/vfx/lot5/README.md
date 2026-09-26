# Lot 5 — Dorure, Spirale, Poncif

Planche : `avant-apres.jpg` (labo Studio, temps réel ; en haut avant, en bas après).

| Glyphe | Ce que l'avant montrait | Ce qui a changé | Notes avant → après |
|---|---|---|---|
| Dorure | l'armure (40 % de dégâts en moins, insensible aux projections, 4 s) donnée au paquet, dessinée 0,38 s plus tard par un grand sceau debout à côté du corps ; pendant les quatre secondes, des traînées au pinceau : **rien** sur le lanceur | au paquet : la feuille de pigment frappée sur le corps de tous côtés, des plaques qui jaillissent autour, un cœur à la poitrine ; puis **le lanceur devient une figure** (couche `Outline` : un contour d'encre et un lavis du pigment sur le corps, jamais à travers un mur) pendant toute la durée du serveur, qui perd des paillettes et des éclats en bougeant, et se défait en une dernière chute de feuille | 1/1/1/1/1/4 → 4/4/3/3/3/4 |
| Spirale | dessinée 0,10 s après son premier tirage ; un halo vert-de-gris qui teintait la page en cyan (la couleur d'un allié), un nuage gris en l'air | au paquet ; **un tourbillon** : deux sceaux qui tournent sur la page (l'intérieur plus vite), l'anneau qui se referme à chaque tirage du serveur, des traits d'encre aspirés vers l'œil depuis une coupole autour de la zone, un cœur qui s'allume au centre | 1/1/2/1/1/4 → 3/4/3/4/3/4 |
| Poncif | dessiné 0,12 s après un ralentissement que le serveur pose au paquet ; les versées portées par des nuages gris qui se lisaient comme de la saleté | au paquet ; chaque versée est une **pluie de grain** sur toute la zone (des rafales, que le moteur n'éclaircit jamais), le bord de la zone tenu au pigment, la tache qui s'élargit d'un cran à chaque tick | 2/1/2/1/1/4 → 3/3/3/3/3/4 |

Ce que le labo a appris :

- **Un corps se dessine par son contour.** Des particules sur un corps disparaissent dans le corps ; un
  `Highlight` (contour d'encre, lavis du pigment, occulté par les murs) dit « ce joueur est protégé » de
  n'importe quelle caméra, pour une instance.
- Une marque au sol peut **tourner** (`Spin` sur une `Mark`) : un sceau qui tourne est un tourbillon.
