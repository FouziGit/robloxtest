# Bible artistique

Ce document décide de l'identité du jeu. Tout le reste en découle : VFX, UI, son, monde, lexique.
Il est écrit après `docs/JUICE_AUDIT.md`, qui explique pourquoi il fallait le faire.

## La contrainte qui décide de tout

Il n'y a pas d'artiste 3D sur ce projet, et il n'y en aura pas. Aucune direction ne peut donc reposer
sur du modèle fait à la main, du sculpt ou de la texture peinte. Ce qui reste est en réalité suffisant :

- géométrie primitive (`Part`, `Beam`, `Trail`) ;
- lumière (`PointLight`, `SpotLight`, `Lighting`, `Atmosphere`) ;
- particules (`ParticleEmitter` avec courbes et flipbooks) ;
- post-traitement (`ColorCorrection`, `Bloom`, `Blur`, `DepthOfField`) ;
- textures générées par script, pas piochées dans la boîte à outils ;
- géométrie générée par script (Blender sans interface, graine fixée, reproductible à l'octet — D-114) ;
- et surtout le **timing**.

Les jeux Roblox les plus reconnaissables ne sont pas les plus détaillés, ce sont les plus cohérents.
La beauté viendra du contraste et de la discipline, pas du nombre de polygones.

---

## Trois directions

### Direction A — VELLUM : le monde est une page, le pouvoir est de l'encre

Le monde est décoloré, presque monochrome : os, craie, charbon. **Rien dans le décor n'est saturé.**
Le seul élément saturé de l'écran est un sort. Un joueur qui voit une couleur voit donc une menace,
toujours, sans exception.

Le pouvoir ne « sort » pas d'un personnage : il **se dessine**. Une incantation trace un sceau lumineux
dans l'air, trait par trait, avant de se replier et de partir. Un impact fait mordre l'encre de toute
l'image un instant — contraste et saturation, le halo débordant de son cœur —, puis laisse une brûlure
d'encre qui s'efface. (Il blanchissait l'écran comme une page surexposée ; vu au labo, ce blanchiment
effaçait l'éclat même qu'il marquait, D-119.)

| | |
|---|---|
| Palette | Vélin `#E8E0CE` · Charbon `#17150F` · Cinabre `#D93A22` · Indigo `#2E4A8C` · Vert-de-gris `#4FA88C` |
| Pigments | les cinq écoles sont cinq pigments historiques : Cinabre, Indigo, Terre d'Ombre `#6B4A2F`, Vert-de-gris, Orpiment `#E8C022` |
| Forme | silhouettes plates, arêtes dures, traits de pinceau. Pas de dégradé dans le décor. |
| Matière | `SmoothPlastic`, réflectance nulle. Aucun métal, aucun verre, aucun néon. |
| Lumière | clé haute : le monde est clair, la magie est sombre ou saturée. L'inverse du genre. |
| Typographie | une ronde d'affiche pour les titres (Fredoka One), une grotesque ronde pour les mots (Nunito), une grotesque condensée pour les chiffres (Oswald) ; la romane (Merriweather) garde le lore, en italique, et les lettrines (D-147) |
| Son | papier, pinceau, bois, percussion sèche. Du **silence** entre les coups, ce qui rend les impacts énormes. |

**Pourquoi c'est lisible :** un seul canal d'information porte le danger, la couleur, et le fond ne
concourt jamais avec lui. C'est le rapport signal sur bruit le plus élevé qu'on puisse construire.

**Pourquoi c'est produisible :** un trait qui se dessine est un `Beam` dont on anime `CurveSize`. Une
page qui surexpose est un `ColorCorrection` dont on pousse `Brightness` et on tombe `Saturation` sur
40 ms. Une brûlure est un `Decal` qui s'efface. Rien de tout cela ne demande un artiste.

**Pourquoi ça tient sur une miniature :** un monde crème traversé d'un unique trait cinabre. Dans une
grille de vignettes YouTube toutes sombres et néon, c'est la seule qui soit claire.

### Direction B — CINDERGLASS : béton, lumière dure, verre qui éclate

Monde de cendre et de béton brut, magie faite de lumière dure et de verre qui se fracture. Bloom
appuyé, monde sombre, magie émissive, arêtes nettes.

| | |
|---|---|
| Palette | Cendre `#2A2A2E` · Béton `#4A4A50` · Cyan dur `#22D3EE` · Magenta `#E11D74` · Blanc brûlé `#F8F8FF` |
| Forme | prismes, éclats, plans qui se brisent |
| Lumière | clé basse, bloom fort, tout ce qui compte est émissif |
| Son | synthèse, sub-basses, verre |

**Rejetée.** C'est exactement le rendu par défaut de Roblox depuis cinq ans : monde sombre, magie
néon, bloom. Un effet pris ici et collé dans n'importe quel autre battleground ne se remarquerait pas,
ce qui est précisément le critère d'échec. Gardée comme piste si un jour l'identité doit virer au
science-fiction.

### Direction C — HOLLOW : les sorts sont vivants

Folklore organique. Un sort n'est pas une énergie, c'est une **colonie** : spores, racines, insectes,
fumée qui se comporte comme un banc de poissons. Rien n'est symétrique, tout respire.

| | |
|---|---|
| Palette | Os `#D9D0BE` · Mousse `#5A6B3F` · Rouille `#8C4A2F` · Ecchymose `#4A3A5C` · Bioluminescence `#7FD4C1` |
| Forme | grappes de petites pièces animées avec cohérence, jamais une forme unique |
| Lumière | contre-jour, brume volumétrique, sources ponctuelles faibles et nombreuses |
| Son | organique, insectes, bois qui craque, souffle |

**Rejetée pour l'instant.** Distinctive, mais elle perd sur les deux autres critères : des formes
organiques se confondent en mêlée à six, et une identité faite de nuées coûte cher en particules, ce
qui est exactement le budget qu'on n'a pas. Gardée comme piste pour un mode PvE ou un boss.

---

## Direction retenue : VELLUM

1. **Lisibilité.** C'est la seule des trois où le décor ne peut pas être confondu avec une menace. En
   3v3, la question « est-ce que ça va me toucher » se répond à la couleur seule.
2. **Production.** Traits, aplats, lumières, post-traitement, décalques — et des volumes générés par
   script (Blender en ligne de commande, semés, quelques centaines de triangles). Zéro modèle *sculpté ou
   fait à la main*, zéro texture peinte à la main : tout ce dont elle a besoin, je peux le générer.
3. **Miniature.** Un jeu clair au milieu de jeux sombres. C'est un avantage d'acquisition gratuit, et
   c'est le seul des trois qui en offre un.
4. **Cohérence du lexique.** Encre, pigments, sceaux, volumes : l'univers, la ressource, les écoles et
   la progression tombent d'un seul bloc, sans rien emprunter à personne.
5. **Extensibilité.** Ajouter une école, c'est ajouter un pigment. La règle tient sans exception.

---

## Univers et lexique

Le vocabulaire actuel est calqué sur une licence existante. C'est un risque de modération et de DMCA,
et surtout un obstacle à toute marque. Voici le remplacement, mécanique identique, mots neufs.

### Le jeu

**VELLUM.** Un mot, prononçable, disponible, et qui dit déjà la direction : le vélin est la peau
préparée sur laquelle on écrit ce qui doit durer.

### Le lore, une page

> Le monde a été écrit. Tout ce qui existe est une marque sur le Vélin, et tout ce qui est marqué peut
> être effacé.
>
> Les Écoles de l'Encre l'ont compris avant les autres. Elles ont appris à tracer, non pas sur la page,
> mais dans l'air : des sceaux qui tiennent le temps d'un souffle et qui, en se refermant, déchirent ce
> qu'on leur désigne. Chaque école garde un pigment, et chaque pigment garde une manière de déchirer.
>
> On ne se bat pas ici pour un territoire. On se bat pour ce qui sera consigné. Le vainqueur écrit la
> page, le perdant est effacé de ce qu'il croyait être le sien. Les archives des Volumes précédents sont
> pleines de noms que plus personne ne sait lire.
>
> Reste à savoir quelle main tiendra la plume à la fin de ce Volume.

### Le lexique

| Avant | Maintenant | Pourquoi |
|---|---|---|
| jutsu | **Glyphe** (Glyph) | ce qu'on trace ; compréhensible sans traduction |
| chakra | **Encre** (Ink) | la ressource se dépense en traçant ; la jauge devient un encrier |
| élément | **Pigment** (Pigment) | une couleur ET une matière, donc une identité visuelle immédiate |
| Feu | **Cinabre** (Cinnabar) | rouge de mercure |
| Eau | **Indigo** (Indigo) | bleu de cuve |
| Terre | **Terre d'Ombre** (Umber) | brun de terre |
| Vent | **Vert-de-gris** (Verdigris) | vert de cuivre oxydé |
| Foudre | **Orpiment** (Orpiment) | jaune d'arsenic |
| combo | **Séquence** (Sequence) | l'ordre des traits |
| rangs Genin → Kage | **Vierge → Esquisse → Copie → Enluminure → Codex** | les états d'un manuscrit |
| saison | **Volume** (Volume) | une saison est un tome |
| match | **Duel / Assaut** | sans emprunt |
| World Boss | **L'Effacement** (The Erasure) | ce qui vient effacer la page |
| mannequin | **Épreuve** (Proof) | une épreuve d'imprimerie, ce sur quoi on essaie |
| ryo (monnaie) | **Folio** (Folio) | un feuillet de manuscrit : dans Vellum, la page est la monnaie |
| ennemi du champ de bataille | **Faussaire** (Forger) | une écriture qui contrefait la page et se retourne contre qui la lit ; figures d'encre marquées de craie, jamais d'une couleur (D-131) |

### Les cinq écoles

| École | Pigment | Couleur | Manière |
|---|---|---|---|
| Maison du Cinabre | Cinabre | `#D93A22` | ce qui consume : projectiles, zones qui brûlent |
| Maison de l'Indigo | Indigo | `#2E4A8C` | ce qui contient : vagues, prisons, contrôle |
| Maison de l'Ombre | Terre d'Ombre | `#6B4A2F` | ce qui résiste : murs, pointes, armure |
| Maison du Vert-de-gris | Vert-de-gris | `#4FA88C` | ce qui déplace : rafales, cyclones, mobilité |
| Maison de l'Orpiment | Orpiment | `#E8C022` | ce qui frappe d'un coup : éclairs, translation |

---

## Les règles non négociables

Elles s'appliquent à chaque ligne de rendu écrite à partir de maintenant.

1. **Le décor n'est jamais saturé.** Toute couleur vive à l'écran appartient à un glyphe. Aucune
   exception dans le monde, pas même pour un élément d'interface diégétique (plaque, panneau, invite,
   marqueur posé dans le décor), sauf ce qu'un corps porte (D-148) : une aura ou une traînée a ses propres
   couleurs, prises aux matières du livre — feuille d'or, lapis, garance, encre ferro-gallique, braise,
   pointe d'argent, vert de vessie, ocre, pourpre de murex —, jamais celle d'une école, ni le blanc, ni le
   cyan allié (`tests/Cosmetics.spec.luau` les en tient loin), et elle se tait en combat : moins dense,
   plus transparente, sans lumière, pour que les glyphes gardent la couleur du combat. Un effet de kill,
   qui tombe dans le combat d'un autre, reste à l'encre de la page. L'interface d'écran — ce qui est
   dessiné sur la vitre et non dans le monde — peut être vive, sous la règle 11 (D-147).
2. **Un glyphe = un pigment = une couleur.** Un sort ne mélange jamais deux pigments. Un joueur doit
   pouvoir nommer l'école d'un sort à la couleur seule, de dos, à trente studs. Ce qui n'est d'aucune
   école — le coup de poing, l'esquive — est à l'encre de la page, le charbon (D-114).
3. **Rien n'apparaît.** Tout se dessine, croît, ou est projeté. Une apparition instantanée est un bug
   de direction artistique.
4. **Rien ne bouge en linéaire.** Toute interpolation a une accélération. Le linéaire est réservé aux
   objets mécaniques, et il n'y en a pas.
5. **Chaque impact laisse une trace** qui s'efface. Le monde se souvient pendant quelques secondes.
6. **Le silence est un matériau.** On coupe pour faire entendre. Un impact lourd baisse la musique.
7. **Le rouge est réservé au danger imminent.** Blanc = invulnérable, cyan = allié — ta propre vie
   comprise. L'adversaire n'est pas rouge : il est à l'encre ; le rouge ne dit que « ça va te toucher ».
   Le Cinabre est rouge, donc les télégraphies de Cinabre sont les seules qui n'ont pas besoin d'un code
   séparé.
8. **La densité de particules est plafonnée** et diminue avec le nombre de joueurs proches et le
   réglage graphique. Un effet qu'on ne peut pas afficher est un effet qu'on ne joue pas.
9. **Un volume est surtout de l'air.** C'est un trait de pinceau qui a pris de l'épaisseur — goutte,
   anneau, couronne d'éclaboussure, balayage, papier arraché —, jamais un objet ni de l'énergie. Il est
   du pigment, pas de la lumière. Il ne couvre jamais un avertissement, ne dépasse jamais le mal qu'il
   dessine, et ne reste pas haut et sombre plus d'un tiers de seconde.
10. **Seul le cœur brûle** (D-119). La page reste de l'encre ; un glyphe est la seule chose qui ait le
   droit de briller, et seulement en son **cœur** : le pigment chauffé vers le blanc — jamais le blanc
   pur (règle 7) —, petit, au centre d'un éclat, et toujours entouré de son pigment ou de l'encre de la
   page (un cœur pâle seul sur le vélin est une tache pâle). Tout le reste est pigment saturé ou encre
   charbon, qui se lisent sur une page claire. Le réglage « Secousses et flashs » éteint ce feu.
11. **Une couleur, un sens, un lieu** (D-147). Dans un menu, une teinte nomme un chapitre ; en combat, elle
   nomme une école, un allié (cyan) ou un danger (rouge). Les couleurs de valeur — le jaune primaire, le
   pourpre, les raretés — n'entrent jamais dans un combat. Toute forme vive posée sur le papier porte un
   contour d'encre : c'est le contour qui la détache, pas sa couleur.

## L'interface : encre vive

L'interface d'écran (D-147) garde la page pour fond et y pose des autocollants : un aplat vif, un contour
d'encre de 3, et une lèvre (ce qui se presse) ou une ombre dure d'encre (ce qui se lit). Les rôles vivent
dans `src/shared/Config/ThemeConfig.luau`, chacun écrit une seule fois.

| Rôle | Hex | Sens |
|---|---|---|
| `Panel` | `#E8E0CE` | la page : le corps de chaque écran, sous le grain du papier ; jamais le HUD |
| `PanelRaised` | `#F7F2E6` | la feuille : cartes, lignes, faces secondaires, toasts, touches, curseurs, texte héros sur un aplat |
| `Chalk` | `#C9C2B1` | craie : désactivé, Commun, argent, rang Vierge, lèvre secondaire, indice sur une plaque |
| `Border` | `#A89C84` | filet décoratif, jamais le seul bord d'un contrôle |
| `Text` | `#17150F` | tout texte sur le papier et sur les aplats clairs |
| `TextMuted` | `#4A4538` | lignes secondaires, onglets non choisis, libellés désactivés ; jamais sur une plaque |
| `TextInverse` | `#E8E0CE` | texte sur une plaque, sur l'Indigo, la Terre d'Ombre et le pourpre |
| `Accent` | `#17150F` | le contour d'encre : autocollants, anneau extérieur du focus, barres de défilement |
| `Outline` | `#17150F` | le trait autour des nombres flottants |
| `Plate` | `#17150F` | plaques du HUD, bandes de chapitre à l'encre, tuiles d'encre, ombres dures |
| `Well` | `#2B271E` | le fond de l'encrier : pistes des barres, emplacements, douilles ; jamais du texte |
| `Overlay` | `#17150F` | le voile derrière un écran ouvert |
| `Primary` | `#FFD60A` | « vas-y, récupère, ça vaut » : bouton primaire, chapitres Jouer et Récompense du jour, Folio, XP, Légendaire, Codex ; jamais en combat |
| `SuccessFill` | `#37B88D` | chapitre Boutique, tampon √, interrupteur allumé, « Acquis ! » ; jamais en combat |
| `Success` | `#1A5846` | le succès en texte sur le papier |
| `InfoFill` | `#4C7DFF` | chapitre Quêtes, Rare, rang Écriture, médaillon d'info, remplissage de la barre d'encre |
| `Ink` | `#4C7DFF` | la barre d'encre |
| `Info` | `#2E4A8C` | l'information en texte sur le papier, la défaite |
| `DangerFill` | `#F24A2B` | danger imminent en aplat : dégâts reçus, vie basse, le boss, confirmation destructive ; jamais un chapitre ni l'adversaire |
| `Danger` | `#D93A22` | Cinabre exact : le fantôme de la vie, le bord de l'écran en vie basse, un grand « classement en baisse » |
| `Ally` | `#73E3FF` | le cyan de la règle 7 : ta propre vie, le score allié, « nous » ; jamais un chapitre |
| `Health` | `#73E3FF` | la barre de vie, alias d'`Ally` |
| `Epic` | `#7E3AC8` | pourpre de Tyr, pigment d'interface que nul glyphe ne porte : chapitre Pass, Épique, rang Enluminure ; jamais en combat |
| `Premium` | `#685208` | premium et Robux en texte sur le papier |
| `Bronze` | `#6B4A2F` | Terre d'Ombre exacte : troisième place, rang Esquisse |

| Écran | Chapitre | Bande | Encre du titre | Lèvre de ce qui se presse |
|---|---|---|---|---|
| Menu | `Plate` et la bande des cinq pigments | `#17150F` | `TextInverse` 13,89 | `Chalk` |
| Jouer | `Primary` | `#FFD60A` | `Text` 12,93 | `#B4951D` |
| Récompense du jour | `Primary` | `#FFD60A` | `Text` 12,93 | `#B4951D` |
| Boutique | `SuccessFill` | `#37B88D` | `Text` 7,30 | `#41836D` |
| Quêtes | `InfoFill` | `#4C7DFF` | `Text` 4,94 | `#283D6D` |
| Battle Pass | `Epic` | `#7E3AC8` | `PanelRaised` 5,65 | `#64319A` |
| Équipement | `Plate` et la bande des cinq pigments | `#17150F` | `TextInverse` 13,89 | `Chalk` |
| Classement | `Plate` | `#17150F` | `TextInverse` 13,89 | `Chalk` |
| Options | `Plate` | `#17150F` | `TextInverse` 13,89 | `Chalk` |
| Résultat | selon l'issue : victoire `Primary`, défaite `Info`, égalité `Chalk` | — | victoire `Text`, défaite `PanelRaised` 7,60, égalité `Text` 10,29 | — |

Le rouge n'est jamais un chapitre, le cyan non plus. Deux tuiles de même couleur ne se touchent jamais sur
la grille du Menu. La bande des cinq pigments fait 6 de haut sous une bande d'encre : cinq segments égaux
aux couleurs exactes des pigments, dans l'ordre de `PigmentConfig.Order`.

## Ce que cela invalide dans l'existant

- La palette d'interface actuelle (gris `24,24,30`, accent or `230,180,60`) est le thème sombre par
  défaut de Roblox. Elle est remplacée intégralement.
- Les polices `Gotham` et `RobotoMono` sont les polices par défaut de Roblox. Remplacées.
- Les couleurs d'élément actuelles sont la roue élémentaire par défaut (orange, bleu, brun, vert pâle,
  jaune). Remplacées par les cinq pigments.
- L'éclairage n'est jamais configuré : le jeu tourne sur le ciel et la lumière par défaut de Roblox.
  C'est la première chose qui rend une capture d'écran interchangeable. À configurer entièrement.
- La page monochrome de D-83 (accent charbon, Merriweather partout, succès et premium seulement « en encre ») : remplacée par l'encre vive (D-147). L'or par défaut `230,180,60` reste banni ; le jaune primaire en est tenu à distance par un test.
