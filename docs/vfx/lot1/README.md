# Lot 1 — Lavis, Balayage, Empattement

Planche : `avant-apres.jpg` (labo Studio ; en haut avant, en bas après ; mêmes caméras). Ce lot a aussi refait les deux effets que les vingt glyphes partagent : le **lancer** (éclat de pigment à cœur chaud dans la main, sceau qui s'ouvre et se replie en 0,14 s au lieu de 0,34 s — il arrivait après la plupart des sorts) et le **coup reçu** (cœur qui claque, étoile, petit jet d'encre ; un coup de poing reste à l'encre, sans lumière).

| Glyphe | Ce que l'avant montrait | Ce qui a changé | Notes avant → après |
|---|---|---|---|
| Lavis | la vague dessinée au **centre** de la sphère de dégâts : le coup tombe 0,3 s avant que le front arrive ; bouffées grises identiques | front dessiné **au bord** de la sphère (7 studs devant le porteur), tourné vers chaque caméra, lèvre d'encre devant ; perles de pigment qui retombent à la place de la fumée ; crête à cœur chaud et jets d'encre ; ruban nu | 2/2/2/1/1/3 → 3/3/4/3/3/4 |
| Balayage | dessiné **sur le lanceur** (le serveur envoie sa position, les dégâts sont 10 studs devant) et 0,16 s **après** les dégâts ; vert pâle invisible | joué **au centre des dégâts** et **à t = 0** ; croissant d'encre qui balaie le sol jusqu'au bord de la zone, jets d'encre et papier arraché vers le haut, cœur sous le seuil du halo (le vert-de-gris chauffé en halo virait au cyan, couleur d'un allié) | 1/1/2/2/1/4 → 3/3/3/4/4/4 |
| Empattement | cinq petites empreintes brunes et des tirets gris : rien depuis la caméra de jeu | cinq **pointes d'encre** de 8 studs qui jaillissent du sol aux cinq points frappés (nouvelle texture `ink_spike.png`, plans tournés vers la caméra), la dernière avec cœur et jet d'encre | 1/2/2/1/1/4 → 3/3/4/4/3/4 |

Notes : lisibilité, contraste, couleur du pigment, dynamisme, impact, performance (grille du skill `vellum-vfx`).

Ce qui reste à 3 : un sort en ligne droite est, depuis la caméra du lanceur, caché derrière sa propre tête — les pointes et le front dépassent maintenant, mais le cœur de l'effet se lit de profil et chez la cible.
