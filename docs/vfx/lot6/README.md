# Lot 6 — Frappe, Caret, Filigrane

Planche : `avant-apres.jpg` (labo Studio ; en haut avant, en bas après).

| Glyphe | Ce que l'avant montrait | Ce qui a changé | Notes avant → après |
|---|---|---|---|
| Frappe | un tir instantané (le serveur touche au paquet) dessiné 0,21 s plus tard, **depuis le lanceur et sur 70 studs quoi qu'il arrive** : la cible était déjà touchée quand le trait partait, et le trait continuait au-delà du mur | au paquet ; **réglée depuis la bouche jusqu'où le rayon du serveur s'est arrêté** (`TravelFrom = "Reach"`, longueur envoyée par le serveur) : un trait d'encre fin dans une bande d'or, un fil chaud dedans, la plume qui rebondit au bout, et la ligne qui sèche au sol sur exactement cette longueur | 1/1/2/1/1/4 → 4/4/4/3/3/4 |
| Caret | le corps déjà arrivé (le serveur le déplace au paquet) pendant qu'un trait partait 0,18 s plus tard pour **18 studs fixes**, même quand un mur avait raccourci le pas | au paquet ; le caret (^) dessiné en l'air **jusqu'où le serveur a posé le corps**, en bande d'or et fil d'encre ; le départ barré d'un trait d'encre, l'arrivée ouverte par un anneau | 2/1/2/1/1/4 → 3/3/4/4/3/4 |
| Filigrane | un voile jaune qui blanchissait toute l'image, aucune forme de zone | le **bord à l'encre** au rayon du serveur tenu pendant les quatre pressions, le **moule d'or** pressé sur ce bord à chaque tick, un cœur, des paillettes qui sautent et retombent | 1/1/2/1/1/4 → 3/4/3/3/3/4 |

Ce que le labo a appris :

- **Un « contrat de rendu » écrit en commentaire n'est pas un contrat.** La Frappe et le Caret décrivaient
  une origine et une échelle que `playGlyph` n'a jamais appliquées. Le contrat est maintenant dans le code
  (`VfxLibrary.Strike`, `VfxLibrary.Caret`) et un test le tient.
- **Un ruban d'encre seul est une planche grise** vu de profil, dès qu'il pâlit : un trait se dessine en
  bande de pigment, un fil d'encre net dedans, un fil chaud au cœur.
