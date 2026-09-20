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

---

# Maison du Cinabre

## `Scorch` — le Roussi (Cinabre, zone)

**Ce qu'il doit faire sentir.** Que la menace est un joueur, pas un endroit. C'est la seule zone du jeu qui
suit son lanceur — le serveur recalcule son centre sur l'origine validée du lanceur à **chaque** tic —,
donc elle ne dit pas « ne va pas là », elle dit « ne va pas près de lui », et elle doit le dire trois fois,
parce que le serveur brûle trois fois à 0,8 seconde d'intervalle et non une fois pendant 2,4.

**Ce qu'il a remplacé.** Huit sphères de braises en orbite autour du lanceur, oscillation sinusoïdale et un
émetteur d'étincelles. Aucune lumière, aucune trace sur la page, aucun bord lisible à trente studs, et
surtout aucun tic : trois paquets de dégâts distincts avaient l'air d'une décoration continue, donc la
seule façon d'apprendre le rythme était d'y laisser des points de vie. La seule chose que cet effet faisait
juste, c'est qu'il **suivait** — et c'est précisément ce qu'une timeline ne doit pas perdre.

**Comment il est construit.** Le format ne peut accrocher qu'un seul genre de couche à un corps qu'il ne
possède pas : une traînée, par `Context.Follow`. Le danger vivant est donc porté par des traînées — un
rideau d'encre brûlante tiré par celui qui porte le feu, **renaissant à chaque tic du serveur**, ce qui
place l'éclat là où sont les dégâts au lieu de le placer à côté. La page ne garde que ce qui est vrai
d'elle : un sceau brûlé au rayon exact (26 studs de diamètre, soit deux fois les 13 studs blessés), tracé
une fois avec le dépassement de la plume vers l'extérieur, **puis consumé** — un anneau laissé au sol
devient un mensonge dès que le lanceur bouge —, la tache d'allumage qui court jusqu'à la ligne tracée, et
le charbon qui s'efface ensuite.

**Deux compromis assumés, écrits pour qu'ils ne passent pas pour des erreurs.** Les tics sont posés sur
l'horloge du serveur et non à 0,8 d'un départ que le serveur ne partage pas : la timeline passe 0,32 s à
dessiner (règle 3, rien n'apparaît), donc les rideaux deux et trois tombent à 0,80 et 1,60 exactement et le
premier tic est couvert par l'allumage. Et il n'y a **aucune lumière sur le centre mobile**, parce qu'une
lumière ne peut pas monter sur `Follow` : les lumières sont sur le charbon, le seul endroit où le feu est
certainement passé. Le brûlage s'arrête à 1,76 s et non à 2,4 : `Ticks * TickInterval` compte un intervalle
qui ne s'écoule jamais, et 0,8 s de sol dessiné en feu alors qu'il ne blesse plus enseigne un rythme que le
serveur n'a pas.

## `Ligature` — la Ligature (Cinabre, mobilité)

**Ce qu'il doit faire sentir.** Un seul geste. Une ligature est le trait qui joint deux lettres sans lever
la plume, et c'est ce que fait le serveur : une ruée de 20 studs en 0,25 s qui dépose cinq foyers à 0, 4,
8, 12 et 16 studs, cinq de rayon chacun, brûlant cinq fois à 0,4 d'intervalle. Un trait, écrit d'un coup,
encore humide, et qui brûle.

**Ce qu'il a remplacé.** Une boule interpolée avec `Enum.EasingStyle.Linear` écrit dans l'appel — la règle 4
enfreinte dans la source, pas par accident — suivie de cinq cylindres Roblox sortis du sol, chacun en 0,2 s
au déclenchement de son propre `task.delay`, donc sans aucun rapport avec le trait censé les avoir posés.
Aucune lumière, rien que le monde garde.

**Comment il est construit.** Il y a **un seul corps** : un porteur invisible qui parcourt les 16 studs de
la ligne d'encre, avec la traînée, les braises et la lumière **montées dessus** — aucune des trois ne peut
donc être en désaccord sur l'endroit où se trouve la plume. Les cinq foyers sont décalés vers l'avant de
l'espacement exact du serveur, et leurs départs sont les instants où la courbe du porteur place la plume
au-dessus de chacun : l'encre tombe **sous** la plume, pas à côté. Chaque foyer est **deux** couches, et ce
n'est pas de l'ornement : le rendu interpole la taille et la transparence sur la même courbe, donc une
tache unique en circulaire-sortant était aux trois quarts transparente au bout de 0,6 s alors que le
serveur blessait encore ces points à 0,8, 1,2 et 1,6. La mèche s'étale vite jusqu'aux dix studs de la
boîte de collision, puis passe la main, à sa propre transparence, à une brûlure qui tient jusqu'au dernier
tic en quintique-entrant et ne se charbonne qu'ensuite.

**Il n'a pas de couche de secousse, et les cinq décalages sont une dette.** La ruée passe par
`grantMovement`, donc `MovementController` secoue déjà la caméra de celui qui l'exécute ; une secousse de
plus la doublerait pour lui seul. En revanche les décalages 0/4/8/12/16 sont `TrailSegments` et
`TrailSpacing` recopiés à la main, parce que des données ne peuvent pas lire `Params` : changer l'un des
deux, ou passer une échelle différente de 1, désaligne chaque tache de la boîte qu'elle dessine. Le résidu
ne porte pas de trace propre : les cinq brûlures **sont** la trace, et une sixième peinte par-dessus
lirait comme un décalque.

## `Blot` — le Pâté (Cinabre, ultime)

**Ce qu'il doit faire sentir.** Le poids. Cinquante d'encre, vingt secondes, quarante-cinq de dégâts, et il
brise les gardes : la chose la plus lourde qu'un joueur du Cinabre possède. Son nom est déjà l'image — un
pâté est ce qu'une plume trop chargée laisse tomber sur une page, et ce qu'il touche n'est plus lisible.

**Ce qu'il a remplacé.** Une boule en `CrackedLava` portant la classe `Fire` de Roblox : le même défaut que
la Marque, dans la même école, sur le sort le plus cher du jeu. Elle volait faux aux deux bouts. Le rendu
prenait `min(Fuse, Range / Speed)` = 1,364 s, alors que le serveur mesure la portée **le long de l'arc** :
`stepProjectile` s'arrête à 1,208 s, à 66,4 studs et 9,5 studs de haut. Le rocher continuait donc 8,6 studs
après une détonation déjà diffusée, et finissait 7,6 studs en dessous d'elle.

**Comment il est construit.** Soixante-six studs, pas soixante-quinze, et vingt studs d'arc, qui sont
l'`ArcHeight` du serveur et culminent où culmine sa parabole. Le corps n'est **pas une sphère** — une sphère
qui grossit et s'efface est exactement l'échec que la mission nomme : c'est un caillot de particules
d'encre, déchiqueté, qui tourne avec le porteur, perd de la fumée et tire un large trait humide en travers
du ciel. L'anticipation est la plume qui se surcharge : l'encre est aspirée dans la main par paquets, et le
sol rend ses écailles, parce qu'aucun autre glyphe ne prend quelque chose au monde pour être lancé. Le
lâcher est de l'encre projetée, pas des étincelles — c'est la matière même du caillot deux images plus
tard, et c'est ce qui distingue le lâcher le plus cher de l'école du moins cher.

**Il n'a pas de phase d'impact, son vol est plus court que son fusible, et son arc a une couture.** La
détonation est un paquet distinct, `Explosion`, mis à l'échelle par le rayon réel — même séparation que la
Marque, pour la même raison. Le vol dure 0,92 s au lieu de 1,208 parce qu'une anticipation ne se paie pas
ailleurs : l'erreur est versée au milieu de l'arc, jamais aux extrémités, et la fin du vol tombe à 1,20 s,
soit huit millisecondes de la détonation du serveur. Reste la verticale : la montée du porteur est
`Arc * sin(alpha * pi)`, nulle aux deux bouts, alors que celle du serveur finit **9,5 studs en haut** ;
le porteur est donc décalé de quatre studs vers le haut, ce qui coupe l'écart en deux à l'arrivée et
rapproche aussi le milieu, puisque le vrai projectile est déjà à treize studs quand ce visuel décolle. Le
vrai télégraphe d'un ultime serait un temps d'incantation côté serveur : il n'existe pas, et aucune
timeline ne peut l'inventer sans mentir sur l'instant du tir. Noté, pas corrigé.

---

# Maison du Indigo

## `Wash` — le Lavis (Indigo, aire)

**Ce qu'il doit faire sentir.** Un pinceau large, chargé, tiré d'un seul geste sur le sol. Pas de l'eau :
un lavis. Le bord qui avance est plus sombre que ce qu'il laisse derrière, parce que le pigment s'entasse
contre le papier sec — c'est cette ligne-là que le joueur lit, et aucun autre battleground ne l'a.

**Ce qu'il a remplacé.** Une dalle en matériau `Glass` tweenée jusqu'au bout de sa portée puis aplatie.
`Glass` est un matériau d'origine, la dalle était un rectangle et non une marque, rien ne la précédait, et
les trente-quatre studs qu'elle traversait l'oubliaient à l'instant.

**Comment il est construit.** La ligne de départ est mouillée **au sol** — pas en l'air : la timeline
`Cast` trace son sceau devant le lanceur pendant exactement ces images, et cet espace est le sien. Puis le
pigment est jeté bas, et **un seul** porteur invisible emmène le front. Le bord d'attaque, le rideau
mouillé, le pigment qui se dépose et la lumière **montent dessus** : aucun d'eux ne peut être en désaccord
sur l'endroit du danger. Trois marques sont posées au sol au moment où le front les traverse, dans cet
ordre — c'est le trait lui-même, et c'est ce que le monde garde.

**Le chronomètre est le sort.** `GlyphEffects.Wash` émet le paquet puis avance son front
**immédiatement**, à vitesse constante, de 6 à 40 studs en 0,8 s, avec un rayon de frappe de 8. Chaque
image passée en anticipation est une image où les dégâts sont devant l'encre : l'anticipation tombe donc à
0,06 et le lancement à 0,04, et le porteur prend les 0,7 qui restent et finit à 0,80 avec le serveur. En
`Sine` sortie sur cette durée, l'encre reste entre 4,2 studs de retard et 5,4 d'avance — toujours **à
l'intérieur** de la sphère qui blesse. Ce chiffre est tout l'enjeu : un front dessiné hors de sa propre
zone de dégâts est un coup venu de rien dans un sens et une esquive gratuite dans l'autre. Une anticipation
plus longue sur ce glyphe n'est pas un choix de style, c'est un mensonge dont on peut donner la taille en
studs.

## `Bleed` — la Bavure (Indigo, zone)

**Ce qu'il doit faire sentir.** De l'encre qui passe le bord qu'on lui a donné et gagne la fibre d'un
papier déjà mouillé. Une page fichue, qui boit ce qui se tient dedans — c'est ça, le ralentissement.

**Ce qu'il a remplacé.** Une `Ball` grossie jusqu'au rayon de la zone, avec un émetteur de vapeur coupé à
la fin. Une sphère qui grossit et s'efface : exactement la forme que cette direction existe pour refuser.
Elle ne disait rien des ticks, rien du ralentissement, et ne laissait aucune trace sur un sol qu'elle
occupait trois secondes.

**Comment il est construit.** La mouillure d'abord, posée à son rayon plein en un dixième de seconde, parce
que la zone blesse dès la première image et qu'une flaque dessinée plus petite que les dégâts est le
mensonge qui coûte une manche. Puis **une seule** marque au sol pour la flaque, qui s'assombrit au lieu de
s'effacer : la page prend de l'encre tout le temps qu'elle fait mal. Par-dessus, chaque tick envoie un
**trait d'encre** filer à ras du papier — un anneau de vapeur jeté vers l'extérieur est la pulsation
standard de tous les autres jeux ; une bavure se définit par ce qui gagne la fibre, et les traits sont
parallèles parce que le papier a un grain. Une couche va à contresens de toutes les autres : celle qui est
tirée vers l'intérieur en continu, parce que la page boit. C'est la seule qui dise pourquoi rester ici
coûte sa vitesse.

**Il n'a pas d'anticipation, et il bat trois fois exactement.** `tickZone` fait mal à t = 0, 1 et 2 sans le
moindre temps de préparation : le serveur émet le paquet et frappe dans la même image. `Bleed` ne déclare
ni lancement ni voyage, donc la barre n'exige aucune anticipation — `Hit` et `Explosion` ouvrent sur
l'impact pour la même raison, et le temps de préparation est la timeline `Cast` qui joue en parallèle.
Toute phase placée devant l'impact décalerait les trois gorgées derrière des dégâts déjà tombés ; sans
elle, elles tombent sur 0, 1 et 2 à l'image près. Et la timeline entière dure 4,6 s, qui n'est pas un
chiffre rond choisi pour la queue : `SlowDuration` vaut 2,5 et le dernier tick l'applique à t = 2, donc la
page finit de sécher quand le sort finit d'agir.

## `Binding` — la Reliure (Indigo, contre)

**Ce qu'il doit faire sentir.** Le nom décide de tout : une reliure est la couture qui tient un cahier dans
son dos. Le glyphe n'enferme personne, il **coud** sa cible dans la page — un cadre réglé autour d'elle, un
point tiré d'un coup, un fil qui traverse le corps, et ça tient jusqu'à ce que l'encre soit finie.

**Ce qu'il a remplacé.** Une bille de `Glass` grossie autour de chaque cible avec un émetteur de tourbillon
dedans : matériau d'origine, sphère qui grossit et s'efface, et aucun rapport avec le seul chiffre qui
compte ici.

**Comment il est construit.** Le cadre est réglé à la taille d'un **corps**, pas à celle de la prise : le
rendu joue cette timeline une fois par cible, donc un anneau au diamètre des quatorze studs de la prise
serait centré sur une victime et non sur le centre de la prise, huit studs devant le lanceur — il ne
montrerait la portée de personne et enterrerait celui qu'il tient. Puis le point se serre : `Quint` en
entrée ne bouge presque pas, puis part d'un seul coup, et la rotation **s'inverse**. Tout s'ouvre vers
l'extérieur dans ce jeu ; un nœud est la seule chose qui doive se fermer. Le fil est posé deux studs et
demi derrière le corps, si bien que sa propre longueur le fait ressortir de l'autre côté.

**L'encre s'épuise exactement quand la racine tombe.** `RootDuration` vaut une seconde et demie, et le
serveur applique la racine **avant** d'émettre le paquet : le compteur tourne déjà quand la première couche
se dessine. Les phases sont donc taillées pour que anticipation plus lancement plus impact fasse 1,50
pile — 0,10 + 0,12 + 1,28. La reliure qui se vide **est** le compteur, lisible par celui qui est tenu comme
par celui qui tient, sans icône ni barre ni chiffre, et ça ne marche que si elle se vide sur la bonne
image. Elle finit en **cassant** : une rafale vers l'extérieur à 1,50 et pas à 1,72, pour que la libération
soit un évènement qu'on peut jouer et non une absence qu'il faut remarquer.

## `Margin` — la Marge (Terre d'Ombre, mur)

**Ce qu'il doit faire sentir.** Une marge est une ligne réglée sur une page. Ce glyphe met cette ligne
debout : quatorze studs de large, neuf de haut, solide, six secondes, et il arrête les projectiles — le
rayon de `stepProjectile` est ce qui rend vrai « l'Ombre bloque ».

**Ce qu'il a remplacé.** Une dalle en matériau `Mud` tweenée hors du sol puis rentrée dedans. Le mouvement
était juste, et c'est pour ça qu'il survit ici ; tout le reste, non. `Mud` est un matériau d'origine, la
dalle arrivait sans avertissement, et le sol qu'elle occupait six secondes n'en gardait rien.

**Comment il est construit.** La marge est **réglée d'abord** : un trait au sol avant que quoi que ce soit
ne monte, ce qui laisse un quart de seconde à l'adversaire pour lire un mur qui vient et autant à l'allié
pour cesser de courir dessus. Puis deux passes d'encre sortent de ce trait, et elles ne sont **pas
coplanaires** : l'origine du paquet est le centre de la dalle, donc les deux couches se posent sur ses deux
faces, à 0,9 stud de part et d'autre dans ses 2,5 d'épaisseur. Deux plans texturés confondus se disputent
le même pixel tant qu'ils vivent, et un mur qui scintille cinq secondes est pire que pas de mur. Sur les
deux faces du feuillet, ils se lisent recto et verso — réglés en deux passes par une main au lieu d'être
extrudés par une machine. Les deux sont centrées **sur** la ligne du sol, ce qui est contraint et juste :
un sprite ne grandit qu'autour de son propre centre, donc une couche centrée plus haut devrait
**apparaître** en l'air (règle 3) au lieu de pousser hors de la page.

**Il ne dessine jamais plus large que ce qui bloque, et jamais plus court trop tôt.** Quatorze studs, pas un
de plus ; sept des neuf studs de hauteur sont tracés, et les deux qui manquent sont le bon côté de
l'erreur. La descente est **séparée** de la tenue, et c'est la correction qui compte le plus : un seul
`Quint` en entrée sur toute la vie du mur laisse l'encre à 84 % de sa hauteur au bout de quatre secondes,
38 % à cinq, et 6 % avec encore une seconde pleine de collision — un joueur entre dans une trace à hauteur
de genou et rebondit sur neuf studs de dalle. Chaque couche tient donc sa hauteur jusqu'à 5,36 puis tombe
en une demie seconde, pour finir à 5,88 et 5,94, un dixième avant que `Debris` prenne la vraie dalle à 6,0.
Ce qui reste comme mensonge est un mur invisible qui bloque encore, jamais de l'encre visible qui ne bloque
plus.

---

# Maison du Terre d'Ombre

## `Serif` — l'Empattement (Terre d'Ombre, zone)

**Ce qu'il doit faire sentir.** Une ligne qui vient vers vous et qui ne s'arrête pas. Ce n'est pas une
explosion : c'est cinq coups, dans l'ordre, sur trente et un studs, et le joueur visé doit sentir lequel va
le prendre avant qu'il le prenne.

**Ce qu'il a remplacé.** Cinq boîtes sur le matériau Slate de Roblox, sorties du sol par une interpolation
Back, tenues une seconde et demie, puis rentrées. Deux couches chacune, aucune lumière, aucune trace, aucun
retour caméra — et un matériau de la boîte à outils portant toute l'identité, ce qui est exactement ce que
la règle interdit : une pointe de pierre teintée existe dans tous les battlegrounds de la plateforme et
n'appartient à aucun.

**Comment il est construit.** La lecture est le nom : un empattement est le trait au pied d'une lettre.
Donc la plume pose d'abord le trait, puis les cinq pieds sont frappés à travers. Le trait est un `Beam` et
non une marque au sol : `buildMark` fabrique un carré dont le lacet vient de la normale du terrain et non
de la visée, il ne peut donc pas dessiner un trait orienté ; un `Beam` court le long de la visée, fait face
à la caméra depuis n'importe quelle place de l'arène et porte la texture de pinceau à peu près à son propre
rapport. Le bible artistique le dit mot pour mot : « un trait qui se dessine est un `Beam` ». Les cinq
pieds sont des `Mark` à plat, aux cinq points que le serveur blesse — 0,08 seconde d'écart, cinq studs
d'écart, de six à vingt-six — chacun encré d'un coup en Quart-Out et pâlissant à mesure qu'il s'étale,
parce que c'est ce que fait l'encre sur le papier. Sept studs de côté font une demi-diagonale de 4,95
contre un `HitRadius` de cinq : l'empreinte ne réclame jamais un coin de terrain que la sphère n'a pas pris.

**Il frappe cinq fois, et on le voit cinq fois.** Cinq empreintes et cinq éclats de gravier, sur l'horaire
du serveur recopié : le compte est l'information. Deux lumières seulement (`PoolPolicy` plafonne
`PointLight` à vingt-quatre, la ligne la plus serrée du fichier) et deux tapes caméra (`MaxConcurrent`
vaut quatre), placées au début et à la fin pour que la ligne se lise comme allant quelque part. Un
`Spacing` changé dans `GlyphConfig` et pas ici se voit immédiatement : les marques ne sont plus là où les
dégâts tombent. Et l'anticipation ne dure que deux images, parce que le serveur blesse son premier point
dans l'image où il émet le paquet : ces deux images sont toute la désaccord, et elles achètent seulement
que la page soit marquée avant de se fendre.

---

## `Stipple` — le Pointillé (Terre d'Ombre, projectile)

**Ce qu'il doit faire sentir.** Du poids lancé à plat. C'est le coup droit de la Terre d'Ombre — dix-huit
d'encre, quatre secondes de recharge — et il ralentit ce qu'il touche, donc la cible doit voir arriver le
ralentissement avant de le subir.

**Ce qu'il a remplacé.** Une boule sur le matériau Mud de Roblox derrière une traînée, déplacée par une
interpolation dont le style d'accélération était écrit `Enum.EasingStyle.Linear` — la règle 4 enfreinte
dans le code source et non par accident —, puis un cylindre qui grossit et s'efface à l'arrivée. Un
matériau d'origine, un disque d'origine, et le seul mot que la direction interdit.

**Comment il est construit.** Le nom, encore : un pointillé est une marque faite de points. Le
rassemblement est donc fait de points là où celui de la Marque est fait de stries — même grammaire, autre
main. En vol, l'émetteur lâche des points denses à vitesse presque nulle, longue durée de vie, traînée
faible : ils restent où ils ont été lâchés, et le vol écrit une ligne pointillée en travers de l'arène. La
tête est une tache d'encre irrégulière, pas un dégradé radial — un halo rond et doux est l'image la plus
empruntée du genre. Elle ne tourne pas : le plan d'un `Sprite` est perpendiculaire à la visée, donc la
tache est de face pour celui qu'elle vise, qui est le seul joueur obligé de la lire, et de profil pour un
spectateur, qui lit la traînée. Un `Spin` y serait mort de toute façon — `stepLive` appelle `followCarrier`
avant `stepSprite` pour tout ce qui monte sur le porteur, et `followCarrier` réécrit le `CFrame` entier.

**Son porteur est en Sine-InOut, et pas comme celui de la Marque.** La Marque explose sur une mèche et
annonce son arrivée par un paquet séparé : un visuel qui court devant ne coûte rien. Ici l'arrivée **est**
le dégât. Une avance systématique montrerait le trait traversant une cible qui n'a pas encore été touchée,
un retard systématique la blesserait avant que le trait arrive. InOut est nul aux deux bouts et au milieu,
et en retard de 7,25 studs aux quarts : la plus petite erreur honnête que le format sache exprimer. Aucune
marque au sol nulle part, et c'est voulu — le trait n'a rien touché ; la brûlure appartient au paquet `Hit`
que `CombatService` émet là où les dégâts sont réellement tombés. **Et un manque nommé plutôt que caché :**
le visuel parcourt ses soixante-dix studs même quand le serveur a arrêté le trait à vingt, parce que le
paquet part avant que `stepProjectile` résolve. Épingler `Travel` sur la portée est la moitié honnête ;
fermer le trou demande un second paquet à l'arrêt, pas une retouche ici.

---

## `Gilding` — la Dorure (Terre d'Ombre, amélioration)

**Ce qu'il doit faire sentir.** Qu'on est devenu plus dur à effacer. Quarante pour cent de moins sur chaque
coup reçu, l'immunité au recul, quatre secondes — et l'adversaire doit pouvoir le lire, parce que frapper
une dorure sans le savoir est une information retirée au joueur, pas un avantage donné au caster.

**Ce qu'il a remplacé.** Six plaques de Slate en orbite autour du caster, qui s'effritaient. Elles
suivaient le corps, ce qu'une timeline a du mal à faire, mais c'était une coquille de pierre sur un
matériau d'origine — l'armure de tous les utilisateurs de terre de la plateforme — et cette direction n'a
pas de pierre dedans. La Terre d'Ombre est ce qui résiste, et sur une page ce qui résiste est la feuille
d'or : la dorure est ce qu'un copiste pose sur la partie du manuscrit qui doit survivre.

**Comment il est construit.** Deux formes, et la séparation est tout le propos. **L'acte** est court et là
où le caster est : la feuille tirée sur le corps depuis partout (vitesse négative, cent quatre-vingts
degrés, l'inverse d'un sort qui quitte une main), un halo tracé jusqu'à douze studs — deux fois la portée
déclarée, donc l'aura à la taille qu'elle annonce — puis replié sur le corps en Quint-In, le geste du sceau
du lancement employé à l'envers : là pour rester au lieu de partir. **Les quatre secondes** sont sur le
corps et nulle part ailleurs : sept traînées espacées d'une demi-seconde et longues de 0,55, donc l'or est
continu et ne clignote jamais au milieu du buff, parce qu'un adversaire qui décide de s'engager a besoin du
signal à l'instant où il décide. Elles s'amincissent — 2,8 à 1,4 de large, 0,30 à 0,55 d'opacité — et c'est
**ça** l'horloge : la feuille s'use, visiblement, sur le corps, là où sont les quarante pour cent. Et
0,16 + 0,22 + 3,62 = 4,00 seconde, soit `CombatConfig.Status.Gilding.DurationSeconds` à l'image près.

**Le manque est nommé, et c'est lui qui décide de la forme.** `VfxTimeline` n'honore `Context.Follow` que
dans `buildTrail` — la ligne 419 est la seule occurrence du fichier. Un `Sprite`, une `Light`, un `Emitter`
ou un `Mark` posé sur le caster reste où le caster était à cet instant. D'où la seule chose que ce glyphe
ne doit **pas** faire : laisser un anneau de douze studs brûler au sol pendant quatre secondes. C'est la
grammaire que ce jeu emploie déjà pour une zone (Bleed neuf studs, Scorch treize), c'est au mauvais endroit
dès qu'il marche, et le temps restant de l'armure est le travail de l'interface via `status.stoneSkin`. Le
sol ne garde donc qu'une petite empreinte courte — cinq studs et demi, son empreinte à lui, effacée en une
seconde et demie — de l'endroit où il s'est doré. Une aura qui suive demande que le runtime accepte
`Follow` pour tous les genres de couche. Ce n'est pas fait, et ce n'est pas prétendu fait.

---

## `Rupture` — la Rupture (Terre d'Ombre, ultime)

**Ce qu'il doit faire sentir.** Que le sol sous vous n'est plus une surface. Trente-cinq de dégâts, dix-huit
studs autour du caster, la garde brisée, et tout le monde part **en haut**.

**Ce qu'il a remplacé.** Trois cylindres de Slate qui s'étendaient au sol en décalé, quarante particules de
poussière, et une secousse caméra. Trois anneaux qui s'étendent : l'exemple même que la règle donne d'un
effet qu'on collerait dans n'importe quel autre jeu de la plateforme sans que personne le remarque. Aucune
anticipation sur un ultime, aucune lumière, aucune trace, aucune impulsion d'écran. La capacité la plus
bruyante du pigment, et rien à l'écran ne le disait.

**Comment il est construit.** Le mot est le dessin. La page se rompt : la plume est enfoncée à travers le
vélin aux pieds du caster et la déchirure court jusqu'aux studs exactement blessés — un `Mark` de
`CrackWeb` ouvert à trente-six studs, soit deux fois le `Radius` du serveur. Mais elle court en **deux
temps** et non d'un seul élan : trois studs à vingt en 0,14 seconde, puis vingt à trente-six en 0,26. Cet
intervalle est toute la différence avec un anneau qui s'étend — une fracture hésite et repart, un anneau
non. Puis la colonne d'éclats à vingt-huit–cinquante-six studs par seconde contre le `Launch` de soixante
du serveur : les éclats et les corps quittent le sol ensemble. Puis la nappe qui part de côté au ras du
sol, une lumière de trente-quatre studs, le profil « Heavy » et le blanchiment de page — les deux seuls du
fichier à être dépensés ici et sur la détonation.

**Tout part vers le haut, parce que c'est ce que fait le serveur.** Le recul est `Vector3.yAxis * Launch`
et rien d'autre : une gerbe radiale mentirait sur la direction dans laquelle le joueur est sur le point de
partir. Corollaire sur les angles de vue, et c'est la raison pour laquelle il n'y a **aucun** `Sprite`
ici : le plan d'un `Sprite` est perpendiculaire à la visée, il est donc écrit pour la caméra du caster et
absent à quiconque se tient à côté de lui, et un ultime ne peut pas dépenser une couche sur un seul siège.
Tout ce qui porte de l'information est plat — deux marques au sol, qui se lisent pareil de partout — ou
fait de particules en espace monde.
---

# Maison du Vert-de-gris

## `Sweep` — le Balayage (Vert-de-gris, aoe)

**Ce qu'il doit faire sentir.** Une feuille claquée à plat. C'est le glyphe le moins cher du jeu — quinze d'encre, trois secondes, douze dégâts — donc celui qu'un joueur du Vert-de-gris ouvre avec, puis relance sans arrêt. Ses dégâts ne sont pas le sujet : le sujet est les septante studs de poussée et les trente de portance de `GlyphConfig.Params`. C'est un déplacement déguisé en dégât, et il doit se sentir comme tel. Ce n'est **pas** une zone : `GlyphEffects.Sweep` fait une seule passe de dégâts, sans tic, sans durée.

**Ce qu'il a remplacé.** Une boule de matière `ForceField` passant de deux studs à vingt-quatre en fondu, plus vingt-quatre étincelles. Deux fautes dans le même objet : une sphère qui grossit et s'efface est l'effet que tous les jeux Roblox affichent déjà, et `ForceField` est une matière du moteur avec son quadrillage à elle — le glyphe portait donc l'identité de quelqu'un d'autre, dans un jeu dont toute la direction est de ne rien emprunter.

**Comment il est construit.** L'air ne se voit pas, donc le vent n'est jamais dessiné : on ne dessine que ce qu'il déplace, et ici ce qu'il déplace est de l'encre. Un petit trait quitte la main ; un trait huit fois plus grand lui répond au centre de la déflagration, large comme la boîte de dégâts ; l'encre déjà posée sur la page est poussée jusqu'au bord et disparaît ; la poussière est arrachée **vers le haut**, ce qui est exactement la portance que le serveur applique. La trace au sol est l'unique **essuyage** de Vellum : tous les autres glyphes brûlent une marque sur la page, celui-ci pousse l'encre hors d'elle, donc sa trace est un trait de pinceau et non un pâté, et elle dure une seconde là où une brûlure dure deux et demie. Le grand trait est volontairement du `BrushStroke` et non une plaque de `PaperGrain` : le grain de papier est la surface du monde, cinq à vingt-quatre pour cent d'alpha, de bord à bord, sans forme propre (`tools/textures/paper.py`) — dessiné en sprite de vingt-quatre studs, c'est un carré translucide à arêtes vives dont la moitié est enterrée. Le trait, lui, est un rapport de quinze à un aux extrémités sèches : le même carré ne montre qu'une bande d'encre en travers, et tout le reste est transparent.

**Les vingt-quatre studs sont ceux du serveur, et il est joué au centre.** `Params.Radius` vaut 12 : la sphère interrogée fait vingt-quatre studs de large, vingt-trois là où elle coupe le sol. La timeline est jouée sur le **centre** que le serveur a frappé — `packet.Origin + direction * Params.Offset`, que le renderer calcule déjà — et non sur le lanceur, pour que l'empreinte et la trace restent sur la boîte de dégâts quelle que soit l'échelle ; ce sont les couches de la main qui portent les dix studs à l'envers. Et l'anticipation est une **salve** et non un débit : un débit de quarante-quatre sur soixante millièmes fait deux particules et demie, ce qui n'est pas un élan mais une apparition (règle 3).

---

## `Hairline` — le Délié (Vert-de-gris, projectile)

**Ce qu'il doit faire sentir.** Un trait tiré à la règle. Le délié est le trait montant le plus fin d'une plume, et celui-ci est la chose la plus fine et la plus rapide du jeu : cent trente studs par seconde sur soixante de portée, quatorze dégâts, et il évente sa cible pour le prochain glyphe de Cinabre. Il doit se lire comme une ligne tracée, jamais comme une balle.

**Ce qu'il a remplacé.** Une lame : une pièce de trente-cinq centièmes d'épaisseur qui **roulait** sur elle-même en volant, déplacée en `Linear`, derrière une traînée du moteur. La règle 4 de la bible artistique interdit le linéaire et l'ancien rendu l'écrivait noir sur blanc. Une lame qui roule est une arme ; ce glyphe n'est pas une arme, c'est un trait, et un trait ne roule pas.

**Comment il est construit.** La plume se charge d'abord — une salve de seize, pas un débit, puisqu'un débit de trente-quatre sur un dixième de seconde fait trois particules —, puis un `Beam` de trois studs à la main : le bec qui touche la page. Le porteur démarre à `Params.SpawnOffset`, donc les soixante studs qu'il parcourt s'achèvent soixante-quatre studs devant le lanceur, exactement là où `stepProjectile` s'arrête : il compte sa distance depuis le point d'apparition, pas depuis la racine. Aucune montée : le tir est à gravité nulle et un délié ne s'affaisse pas. Le corps du vol est **deux** traînées sur la même texture de pinceau, montées sur le même porteur : un cœur de cinquante-cinq centièmes de stud et un bord sec de 1,6 stud par-dessus. C'est un trait de plume — un centre mouillé dans un bord rompu — là où une traînée fine plus un sillage de poussière est une balle avec de l'échappement, et cela coûte la même chose.

**La courbe est mesurée, et symétrique.** `Sine` `InOut` est, des huit courbes disponibles, celle qui s'écarte le moins de la vitesse constante que le serveur simule : l'écart culmine à un quart et aux trois quarts du vol, six studs en retard sur toute la première moitié, six studs en avance sur toute la seconde, soit quarante-huit millièmes de seconde dans un sens comme dans l'autre. `Quad` `In` resterait toujours en retard, mais de quinze studs à mi-vol, ce qui veut dire être touché par une ligne qui n'est pas arrivée : la pire des deux. Et il ne touche rien, donc il ne marque rien : pas de phase d'impact, pas de trace au sol. Ce qui se passe à l'arrivée appartient à la timeline `Hit`, partagée. Son seul résidu est l'image rémanente de la ligne, décalée de trente-deux studs vers l'avant pour flotter au milieu de son propre trajet — sans ce décalage, une couche de résidu sans porteur à chevaucher est dessinée aux pieds du lanceur, le seul endroit où le trait n'est jamais passé.

---

## `Spiral` — la Spirale (Vert-de-gris, zone)

**Ce qu'il doit faire sentir.** Une page aspirée par un point. C'est la seule zone du jeu qui **attire** : les quatre autres repoussent, brûlent, ralentissent ou étourdissent, celle-ci traîne tout ce qu'elle blesse vers son centre à trente-cinq studs par seconde, quatre fois. Une lecture fausse ici coûte plus cher que partout ailleurs : le joueur qui la prend pour une zone qui pousse court dans le mauvais sens.

**Ce qu'il a remplacé.** Un effet qui disait l'inverse du code là où ça comptait le plus. Il empilait des anneaux `ForceField` en entonnoir et donnait à sa poussière `Acceleration = (0, 14, 0)` : les particules sortaient **par le haut** pendant que le serveur tirait vers l'intérieur. (Ses billes, elles, montaient bien du bord vers l'œil — la seule chose honnête qu'il contenait.) Et une tornade est en plus une image de catalogue, qui projette au lieu de happer.

**Comment il est construit.** Par inversion, mais en ne promettant que les inversions que le moteur sait dessiner. Au sol, les anneaux ne s'ouvrent pas, ils se **referment** — vingt-deux studs de diamètre ramenés à deux, en `Circular` `In`, donc suspendus puis d'un coup —, et il y en a exactement quatre, à zéro, six, douze et dix-huit dixièmes : les instants où `tickZone` tire réellement. Chacun est une couche `Mark`, donc posée à plat, parce qu'une zone se lit d'en haut. En l'air, l'attraction est dessinée comme une **chute** : `buildEmitter` ne règle jamais `EmissionDirection`, donc un émetteur ponctuel à cent quatre-vingts degrés d'ouverture est symétrique et le signe de sa vitesse est invisible — les stries se liraient comme une explosion dans un sens comme dans l'autre. Suspendues à huit et dix studs au-dessus de l'œil, sur un cône de vingt et quelques degrés, la vitesse négative devient une direction que le moteur donne vraiment, et ce qu'il donne est de la matière enfoncée dans un point. Anneaux vers l'intérieur sur la page, tout le reste vers le bas à travers : la zone est un trou dans lequel la page est tirée. La caméra reçoit quatre petites secousses `Dash` sur la même mesure — la traction a donc un rythme qu'on peut compter — et ces secousses ne coûtent rien, une couche `Shake` n'emprunte aucune instance.

**L'emprise ne se resserre jamais, le résidu si.** Le disque au sol monte de dix-neuf à ses vrais vingt-deux studs et s'y tient, ne s'effaçant que par la transparence, parce que `tickZone` frappe au rayon onze aux quatre tics : une zone dont le bord dessiné se referme alors que sa boîte de dégâts ne bouge pas dit au joueur qu'il est sorti quand il ne l'est pas. La contraction appartient aux anneaux, qui sont des événements. Ce qu'elle laisse, en revanche, est un **nœud** : le seul pâté du jeu qui rétrécit en s'effaçant, de huit studs à cinq et demi — c'est permis là et interdit sur l'emprise, parce que plus rien n'est blessé.

---

## `Pounce` — le Poncif (Vert-de-gris, zone)

**Ce qu'il doit faire sentir.** Une page enfouie sous la poudre. La ponce — pierre ponce, os de seiche — est ce qu'on secoue sur le vélin pour préparer la surface et sécher l'encre, et un poncif est le patron piqué à travers lequel on la tamponne. Ce n'est donc pas une tempête de sable, c'est un **versement** sur treize studs de page, trois fois, et tout ce qui est dessous ne garde que sept dixièmes de sa vitesse pendant une seconde et demie. C'est le seul glyphe de l'école qui ne déplace rien : il retire le déplacement. Le mot veut aussi dire cliché, ce qui interdit formellement de le dessiner comme tel.

**Ce qu'il a remplacé.** Un dôme de matière `Sand` grossissant de deux studs à vingt-six en fondu, avec du grain soufflé devant la caméra. La sphère qui grossit est le cas d'échec nommé, mais la faute plus grave est qu'un **dôme** est un abri, donc le vocabulaire de l'Ombre, « ce qui résiste ». L'effet promettait un couvert sur le seul mètre carré du terrain qu'il faut quitter.

**Comment il est construit.** Une ombre douce couvre les vingt-six studs de `Params.Radius` en une demi-seconde, et elle est **visible** pendant qu'elle le fait — quarante-cinq pour cent de transparence, pas quatre-vingts, qui est le réglage d'une couche écrite et jamais vue — parce que le serveur frappe immédiatement et que l'emprise doit être honnête tout de suite. Elle s'efface quand la première poudre vient la remplacer, pour que rien ne disparaisse sans relève. Puis trois versements, à zéro, neuf et dix-huit dixièmes, les intervalles propres du serveur : chacun tombe de sept studs de haut, en vitesse négative sur un cône de cinquante-huit degrés, la seule chose qu'un émetteur de ce format peut affirmer sans mentir — son axe est le haut, donc le bas est la direction qu'il donne réellement. Dessous, une brume basse qui **descend** au lieu de monter, et du grain fin par-dessus, parce qu'une poudre sans grain dur est une fumée et qu'une fumée appartient au Cinabre ou à l'Indigo. Chaque versement élargit la tache au sol d'un cran — douze, dix-sept, vingt-et-un studs — donc la zone paraît compter ses passages.

**Il ne secoue pas la caméra, et ce qu'il laisse n'a pas d'arête.** Aucune secousse, aucun éclair, nulle part : c'est voulu et non oublié. Le glyphe n'applique aucune force — ni poussée, ni portance, ni étourdissement — et une caméra qui sursauterait sur une chute de poudre effacerait la seule différence entre lui et toutes les autres zones. La bible artistique appelle le silence un matériau ; ici c'est le matériau principal. Quant à la trace, c'est un `GradientRadial` et non du `PaperGrain` : le grain de papier est la surface tuilable du monde, sans forme, et sur le sol il donne un carré de pigment à arêtes vives posé sur la texture même dont il est fait. Un disque à bord fondu n'a aucune arête pour se trahir — c'est à ça que ressemble une poudre retombée.

---

# Maison du Orpiment

## `Strike` — la Rature (Orpiment, projectile hitscan)

**Ce qu'il doit faire sentir.** Que c'est déjà arrivé. L'Orpiment ne vole pas, il est déjà là, et c'est
toute l'identité de l'école : le joueur ne doit jamais avoir le temps de voir partir quoi que ce soit. Son
nom français dit l'image exacte — une rature, un trait tiré à travers la page et à travers ce qui s'y
trouvait.

**Ce qu'il a remplacé.** Un éclair segmenté à jitter aléatoire entre le lanceur et la victime, plus un
éclat d'étincelles au bout. Le jitter par segment est l'éclair par défaut de Roblox : collé dans n'importe
quel autre battleground, personne ne l'aurait remarqué, ce qui est exactement le critère d'échec. Il
apparaissait entier, à pleine force, sans aucun avant (règles 3 et 4). Il ne laissait rien au sol (règle
5). Et il n'éclairait rien, donc à trente studs la seule chose qui annonçait le coup était la barre de vie.

**Comment il est construit.** Le trait est **tiré**, pas révélé : un porteur traverse toute la portée du
glyphe en quatre-vingts millisecondes avec une traînée montée dessus. Quatre-vingts millisecondes, c'est
sous le seuil où l'œil suit un objet — ça se lit donc comme déjà là, et pourtant rien n'est apparu, parce
que le trait a été tracé, de la main vers l'avant, dans le sens où va une plume. C'est ainsi qu'un effet
instantané obéit à la règle 3 au lieu de la contredire. Le porteur est déclaré dans la phase **Lancement**
et non dans **Voyage** : il n'y a pas de vol ici, c'est la plume qui traverse la page. La traînée est le
seul type de couche dont la longueur est indépendante de la largeur — un `Beam` fait huit fois sa largeur
par construction, donc un faisceau de soixante-dix studs serait épais de neuf.

**Le dégradé de la traînée s'arrête à 0.42, et c'est la correction qui compte.** Dans ce moteur, la
transparence d'une `Trail` est échantillonnée **sur sa longueur**, pas dans le temps : 0 au point le plus
récent, 1 au plus ancien. Une fin à 1 effaçait donc le trait du côté de la main et ne laissait qu'une tête
brillante qui s'estompe derrière elle — c'est-à-dire le rendu de projectile le plus banal de la plateforme,
et exactement l'usage juste pour la Marque et l'esquive. De 0.1 à 0.42, les soixante-dix studs restent
lisibles, l'extrémité la plus vieille étant la plus sèche : une rature. Il n'a pas d'arc, et cette absence
est l'école ; il n'a ni phase d'impact ni blanchiment, parce que son atterrissage est le paquet `Hit` que
le serveur émet déjà pour le modèle qu'il a blessé.

---

## `Caret` — l'Insertion (Orpiment, mobilité)

**Ce qu'il doit faire sentir.** Une correction. Le corps est **raturé là où il était** et **inséré là où il
arrive** : sur une page, se déplacer est une retouche, et c'est la seule téléportation que cette direction
artistique puisse avoir.

**Ce qu'il a remplacé.** Un éclair à jitter entre les deux extrémités, un éclat d'étincelles identique à
chaque bout, et une boule en `ForceField` à l'arrivée pour la fenêtre d'invulnérabilité. Le `ForceField`
est la bulle d'origine de Roblox et appartient à tous les autres jeux ; l'éclair est l'éclair d'origine.
Mais le vrai défaut est que les deux bouts étaient identiques, et c'en est un défaut **compétitif** : un
joueur qui voit un clignement à trente studs doit savoir instantanément lequel des deux bouts est
l'arrivée, sinon l'effet lui a annoncé un combat sans lui dire où. Rien ne restait au sol, donc un
adversaire qui regardait ailleurs une image perdait l'information entière.

**Comment il est construit.** Les deux extrémités sont des **gestes opposés** dans le même pigment. Le
départ se referme : l'encre est arrachée de la page, un trait se ferme sur la silhouette, la fumée est
aspirée vers l'intérieur du trou. L'arrivée s'ouvre : une marque dépasse vers l'extérieur, l'encre est
projetée vers l'avant en éventail serré — pas en sphère, une sphère d'étincelles étant le scintillement de
téléportation de tous les autres jeux —, la lumière monte. Personne n'a à apprendre ça. Entre les deux, le
caret lui-même : un porteur franchit l'écart en soixante-dix millisecondes avec cinq studs d'arc et une
traînée montée dessus, donc l'encre trace une montée et une descente — le signe typographique du glyphe,
tracé en l'air, d'un seul geste, **par la trajectoire**. Deux cent cinquante studs par seconde avec un arc
marqué ne peut pas être confondu avec l'esquive de la Ligature à quatre-vingts studs par seconde et à
plat, qui est la seule confusion qui coûterait cher.

**Son anticipation n'est pas une charge.** Le serveur téléporte à l'image où il émet : quand le paquet
arrive, le corps est déjà parti. Cette phase est **le trou qu'il a laissé**, en train de se refermer, et
c'est pour ça qu'elle s'effondre vers l'intérieur au lieu de rassembler. Quatre-vingts millisecondes, pour
que l'arrivée ne soit jamais en retard.

**Le voile d'arrivée se termine à l'image exacte où la cible redevient touchable, et c'est une
soustraction.** `IFrameSeconds` vaut 0.4 et part à l'image de l'émission ; la phase de résidu commence
0.18 plus tard (0.08 d'anticipation plus 0.10 de lancement) ; 0.40 − 0.18 = 0.22. C'est une salve unique
dont la durée de vie des particules tient **dans** celle de la couche, parce que la libération d'une
couche détruit toute particule encore en vol : une durée plus courte que la vie des grains ne prolonge pas
le voile, elle le coupe. Si `IFrameSeconds` bouge, ou si l'une des deux phases devant change de longueur,
ce nombre bouge avec elles.

---

## `Watermark` — le Filigrane (Orpiment, zone)

**Ce qu'il doit faire sentir.** Une presse. Un filigrane n'est pas dessiné sur une feuille, il est **pressé
dedans** par la forme et ne se voit que quand la lumière prend le papier. C'est le seul glyphe du jeu qui
ait une raison d'utiliser la texture `PaperGrain` : la marque est une modification de la page elle-même.

**Ce qu'il a remplacé.** Un cylindre qui grandissait jusqu'au rayon, un émetteur d'étincelles continu, et
quatre salves d'éclairs à jitter lancés au hasard vers la circonférence. Il avait la même tête à chaque
instant de sa vie sauf pour les éclairs, qui étaient du bruit et non de l'information, et le crépitement
continu du disque disait « dangereux » sans jamais dire « dangereux **maintenant** ». Le serveur
micro-étourdit par tick, pas en continu.

**Comment il est construit.** En **quatre presses**, à zéro, sept dixièmes, une seconde quatre et deux
secondes une — exactement l'horaire de `tickZone` pour `Ticks = 4` et `TickInterval = 0.7`, dont le premier
tick tombe à l'image où le paquet est émis et qui n'attend l'intervalle qu'**avant** chaque tick suivant.
Les quatre sont **identiques**, volontairement : les quatre ticks sont identiques, et une quatrième presse
dessinée plus lourde promettrait des dégâts que le serveur ne fait pas. Chaque presse est éclairée **par
dessous** : le rendu coupe les ombres de ses lumières, donc une source à un stud sous le sol n'est pas
occultée par lui et la feuille s'éclaire de dos, en contre-jour sur les jambes de tout ce qui se tient
dedans. Une lumière qui pulse au centre d'un disque est le tick de zone standard de la plateforme ; une
page éclairée par derrière **est** un filigrane. La fibre, elle, est projetée assez loin pour être vue par
celui qu'elle menace : une salve qui meurt à deux studs du centre d'une empreinte de vingt-quatre est
invisible depuis le bord, c'est-à-dire depuis l'endroit où se prend la décision de partir.

**Il s'arrête de dessiner le danger à l'image où il s'arrête de le faire.** Le dernier tick qui blesse
tombe à 2.1 ; la phase d'impact dure donc 2.34 — ce tick plus sa presse — et non les 2.8 que porte le
champ `Duration` du paquet, parce que `Ticks × TickInterval` dépasse d'un intervalle entier le dernier tick
du serveur lui-même. Le résidu prend la relève à l'image exacte où l'empreinte lâche, et il est
franchement plus petit qu'elle — treize studs contre vingt-quatre. Un sol qui dit « on ne peut pas se tenir
ici » alors que c'est redevenu vrai est le même mensonge qu'un projectile qui dépasse sa portée, pris dans
l'autre sens. Il n'a par ailleurs ni anticipation (une zone qui blesse à l'image où elle atterrit n'a pas
de fenêtre à télégraphier), ni `Sprite` (un `Sprite` est un plan orienté par la direction du paquet et
deviendrait un mur debout le jour où quelqu'un passerait la direction de visée ; une `Mark` est plate par
construction), ni `Flash` (chaque presse blesse tout le monde dans la zone et chacun de ces coups émet
déjà son propre `PageFlash`).

---

## `Colophon` — le Colophon (Orpiment, ultime)

**Ce qu'il doit faire sentir.** Le dernier mot. Un colophon est l'inscription de fin d'un manuscrit : la
marque qui dit ici s'achève, et par quelle main. C'est la chose la plus lourde de la liste — quatre entrées
d'Orpiment, cinquante-cinq d'encre, vingt-cinq secondes, quarante de dégâts, casse les gardes, six
dixièmes d'étourdissement par maillon — donc l'image doit être une signature, pas la version grosse d'un
petit sort.

**Ce qu'il a remplacé.** Un éclair tombé du ciel sur la première victime, puis des éclairs à jitter qui
chaînaient, chacun avec un éclat et une grosse secousse. C'est l'ultime le plus copié de la plateforme,
donc il avait déjà échoué au critère ; mais le défaut plus grave est qu'il **contredisait le sort**. Le
serveur tire un hitscan vers l'avant depuis la main. Un éclair qui tombe du ciel apprend à tous les
spectateurs que cet ultime vient d'en haut, ce qui est inapprenable et donc inévitable : l'effet enseignait
la mauvaise leçon sur un cooldown de vingt-cinq secondes. Et après avoir étourdi trois personnes six
dixièmes de seconde chacune, il laissait le sol tel qu'il l'avait trouvé.

**Comment il est construit.** Comme une **signature** : un trait large, tiré depuis la main, qui ne se
relève pas. Le trait est un `Beam` parce que la longueur d'un `Beam` vaut huit fois sa largeur par
construction — ce rapport porte le sens : sept studs et demi de large sur soixante de long, c'est une plume
qui appuie, et c'est près de cinq fois la largeur du filet de la Rature pour un glyphe qui ne fait pas tout
à fait le double de dégâts. Cet écart de poids est ce qui empêche un ultime de se lire comme une attaque de
base. Le trait est posé **deux fois**, une passe claire qui se referme d'un coup et une passe plus sèche
qui met une demi-seconde à partir, parce qu'une signature n'est jamais d'un seul passage. Sur le corps, la
marque est **deux traits croisés** : ce qui se trouvait là était une bouffée de fumée à 180 degrés, c'est-à
dire l'impact standard du moteur — et redondant en plus, puisque le paquet `Hit` de cette même victime en
pose déjà une. Deux traits croisés écrits sur un corps sont un colophon ; une bouffée de fumée est à tout
le monde. Le sceau, lui, **double** : c'est le seul glyphe du jeu dont l'anticipation trace un second
`SealRing`, en rotation inverse du sceau de lancement, et c'est une fonction de jeu et non une fioriture —
c'est le seul avertissement que quiconque reçoive qu'un casseur de garde arrive, et il achète deux dixièmes
de seconde. Aucun autre glyphe ne peut l'emprunter.

**La chaîne est un second bloc, `ColophonLink`, joué une fois par saut — et il y a deux sauts, pas trois.**
`ChainCount` vaut 3 et la boucle du serveur compte la première cible du hitscan comme le premier point :
trois corps touchés, donc deux arcs. Une timeline a une seule origine et le serveur choisit les positions
des maillons à l'exécution : la seule façon pour que le chemin dessiné soit le chemin réellement résolu est
un jeu par segment. Rejouer `Colophon` en entier tracerait le sceau doublé à chaque maillon, alors que le
serveur résout toute la chaîne en une image — les arcs doivent être rapides, sinon la deuxième victime est
vue encaisser avant que l'encre ne l'atteigne. Le segment garde donc les proportions du premier trait,
perd la cérémonie, et **garde la marque tenue six dixièmes de seconde** : le serveur étourdit chaque
maillon, pas seulement le premier, et sans cette couche deux corps sur trois sont bloqués six dixièmes de
seconde sans que rien sur eux ne le dise — exactement l'information qu'il faut à un coéquipier pour
convertir l'ultime. Quand tout est fini, le sol porte le chemin entier comme un seul trait brisé, pendant
près de deux secondes : la page a été signée.

---

# L'Effacement

Les sept effets du World Boss sont les seuls du jeu dont le visuel est **une règle** et non une décoration :
six joueurs lisent la peinture au sol et décident où se tenir. D'où trois choses que ne fait aucune autre
timeline. Leur phase d'anticipation prend sa durée **du paquet** (`Phase.Window`) — le serveur attend entre
0,6 et 2 secondes selon l'attaque et selon la phase du combat. Leurs couches se mesurent sur **la forme
que le serveur va frapper** (`SizeFrom`, `SpanFrom`, `OffsetFrom` contre `Radius` et `Reach`), pas sur une
échelle. Et elles sont dessinées avec les quatre textures `Telegraph*`, les seules dont l'encre atteint
le bord du plan (`AssetIds.Ink`) : le pâté s'arrête à 0,53 de son plan, l'onde à 0,81, et une règle
peinte avec eux serait une règle sur six dixièmes du sol.

`tests/BossTelegraph.spec.luau` tient les trois ensemble. Il lit `WorldBossConfig`, reconstruit la forme
de `isInShape`, multiplie la demi-largeur de chaque plan par l'encre de sa texture, et vérifie que la
peinture couvre le disque, l'anneau et — tous les quarts de stud — le cône, sans jamais sous-couvrir ;
que le refuge ne dépasse jamais le vrai rayon, en diagonale comprise ; que chaque avertissement est
lisible dès sa première image ; que la fenêtre se résout sans clamp dans chaque phase du combat et que
l'impact commence à sa fin ; et que chaque forme du serveur a une timeline écrite pour elle. Chaque
assertion a été vue échouer sur un défaut réintroduit avant d'être gardée. Et côté serveur, D-72 : le boss
ne bouge pas pendant qu'il prévient, et les dégâts lisent l'origine figée au début de l'avertissement.

**Le vocabulaire est partagé par les quatre attaques**, parce qu'un boss qu'on apprend est un boss dont la
langue se répète :

| Signe | Ce qu'il dit |
|---|---|
| Le sol **s'éclaire** d'abord (`EndBrightness`), sur toute la fenêtre | la première chose lisible à quarante studs, à travers les effets de six joueurs |
| L'encre inonde le sol qu'il va effacer à 4 %, lisible dès la première image, en `Quad` entrant | le dernier tiers se remplit d'un coup : c'est « maintenant » sans afficher de chiffre |
| Un anneau balaie à vitesse régulière vers le cœur du danger, à partir de 12 % | donc il s'éloigne aussi **de la sortie** : vers le centre pour un disque, vers le boss pour un cône, vers l'extérieur pour un anneau |
| Le grain de la page est tiré **vers** le point du coup | L'Effacement prend en lui là où tout glyphe projette ; les étincelles sont au Cinabre et à l'Orpiment |
| Ce qui reste est du **papier nu, couleur papier** (`BossScour`) | aucun autre effet du jeu ne laisse ça : les glyphes brûlent la page, L'Effacement l'efface |

**Sa couleur.** Rouge pour ce qui touche (la même règle que les dégâts reçus), vert pour le seul endroit
qu'une attaque ne couvre pas, et **vélin** `#E8E0CE` pour le boss lui-même et pour ce qu'il laisse : la
couleur de la page. C'est la seule chose du jeu teintée par le papier et non par un pigment. Ce qui était
là avant était une colonne d'énergie violette, et une colonne d'énergie violette est le visuel le plus
copiable-collable de Roblox.

**Le papier nu est un second jeu.** Une timeline porte une couleur, et l'attaque porte celle du danger ;
`BossScour` est joué par le rendu sur la phase Résidu de l'attaque (`VfxTimelineConfig.phaseAt`), en
vélin, sur le rayon du disque, la portée de l'anneau, ou un pâté à mi-trait pour le cône. Les résidus des
attaques elles-mêmes ne gardent que la fracture et la poussière.

---

## `BossSlam` — le coup plat (disque)

**Ce qu'il doit faire sentir.** Que le sol sous soi est déjà perdu. Vingt-deux studs, 1,2 seconde
d'avertissement, l'attaque la plus fréquente du combat : c'est elle qui enseigne la langue du boss.

**Ce qu'il a remplacé.** Un cylindre couché de 0,4 stud d'épaisseur, teinté rouge, passant de 85 % à 30 %
d'alpha **en linéaire** sur la fenêtre, puis un second cylindre qui s'étendait au rayon. Deux couches, une
interpolation interdite par la règle 4, aucune lumière, et une trace qui n'existait pas : le sol redevenait
propre une demi-seconde après le coup.

**Comment il est construit.** Le disque d'encre monte à 2 × `Radius` de diamètre — donc exactement le
cercle que `isInShape` teste, jusqu'à la dernière ligne de pixels — et l'anneau se referme dessus en
`Sine` entrant-sortant, à un rythme qu'on peut lire à mi-fenêtre, arrivant au centre à l'instant du coup.
Le grain de la page converge depuis onze studs, puis une bouffée de trente sur les 14 % finaux : c'est ce
dernier temps qui fait bouger un joueur, pas le remplissage. À l'impact, l'encre se consume au lieu
d'être coupée, l'onde s'arrête **au rayon** et pas un stud plus loin, la fracture s'ouvre à 1,7 fois le
rayon, et le papier nu vient par-dessus en vélin.

---

## `BossFury` — la même langue, plus fort (disque)

**Ce qu'il doit faire sentir.** Que ce n'est pas le coup plat, **avant** d'avoir choisi où courir.
Trente studs, quarante-cinq dégâts, deux secondes pleines : l'attaque de la troisième phase.

**Ce qu'il a remplacé.** Exactement `BossSlam`, avec un autre nombre en entrée. Rien à l'écran ne
distinguait l'attaque à 28 dégâts de l'attaque à 45. Et ma première version ne valait guère mieux : sa
seconde horloge arrivait aux deux tiers de la fenêtre — 0,42 seconde avant le coup en phase trois,
après que le joueur a dû s'engager.

**Comment il est construit.** Deux horloges concentriques **dès la première image**, qui se referment à
des rythmes différents : l'anneau en balayage régulier, et dedans un `SealRing` qui tourne à 2,2 rad/s et
se referme en `Quart` entrant, donc arrive en dernier. Une silhouette qu'aucune autre attaque n'a, lisible
à l'instant où elle apparaît. Et deux ondes à l'atterrissage au lieu d'une : un front mince en
`Exponential` sortant jusqu'au rayon exact, puis un corps d'encre plus lent qui le dépasse, parce qu'un
coup qui a un front **et** un corps a du poids, là où un seul anneau n'a que de la vitesse.

---

## `BossSweep` — le trait (cône)

**Ce qu'il doit faire sentir.** Qu'une direction est condamnée et que les autres ne le sont pas. C'est la
seule attaque du boss qui n'est pas un disque, et la seule dont on se sauve en marchant de côté.

**Ce qu'il a remplacé.** Cinq pavés rouges de 0,4 stud d'épaisseur dont la largeur était calculée au
**centre** de chaque segment. Un joueur debout dans la moitié extérieure de n'importe quel segment se
tenait dans les dégâts et hors de la peinture, sur toute la longueur du cône.

**Comment il est construit.** C'est la raison pour laquelle le format a appris `Span` : un `Mark` peut
enfin être plus long que large, donc le cône est cinq barres d'encre plein-bord (`TelegraphBar`) posées
bout à bout le long de la portée, chacune large comme le coin l'est **à sa sortie** et non en son milieu.
Toutes couvrent donc plus que les dégâts, jamais moins, et jamais moins que le corps du boss lui-même —
`isInShape` ne referme pas le coin sous 4 studs, parce que se coller au boss n'est pas une esquive, et le
test échantillonne les quarante studs tous les quarts de stud pour le prouver, encre comprise. Elles
s'allument **vers l'extérieur** avec un décalage de 5 % chacune et finissent ensemble : la direction est
lisible avant que la forme soit terminée, et le trait arrive à son propre bout quand le coup tombe. Le
coup lui-même est un seul trait de pinceau sur toute la longueur, plus étroit que le coin : l'avertissement
était la forme, ceci est le poids.

---

## `BossEruption` — l'anneau (et `BossEruptionSafe`)

**Ce qu'il doit faire sentir.** Que la sortie est **à l'intérieur**. C'est la seule attaque du jeu dont on
se sauve en courant vers le danger apparent.

**Ce qu'il a remplacé.** Un disque rouge à la portée extérieure, un disque vert au rayon sûr, et huit
piliers qui montaient du sol à l'impact. Le disque vert était surélevé de 0,15 stud pour ne pas se battre
avec le rouge, ce qui est la bonne idée — mais les deux étaient dans le même effet, et un effet ne porte
qu'une couleur depuis la règle 2.

**Comment il est construit.** Le danger est une seule inondation mesurée sur `Reach`, et son horloge part
du centre vers le bord extérieur : elle traverse la frontière du refuge en chemin, ce qui est exactement ce
qu'elle raconte. Sa matière est posée **sur l'anneau** qu'elle va soulever, mesurée sur la portée, en trois
points — trois, parce que deux se lisent comme une paire et trois comme un anneau —, du grain qui monte
avant le coup et trois colonnes de fumée d'encre après.

**Le refuge est un second jeu.** `BossEruptionSafe` est joué à côté, dans la seule couleur de ce sol qui ne
veut pas dire danger, avec la même fenêtre : le papier nu se remplit et la ligne autour de lui tient
exactement aussi longtemps qu'il reste du temps pour entrer, puis **survit** à l'effacement dessiné autour,
parce que la page garde ce qui n'a pas été effacé. Le disque est un disque (`TelegraphPage`), pas le grain
du monde sur une plaque carrée : un carré de sécurité a des coins à six studs dans les dégâts, et c'est le
seul mensonge de ce sol qui tue. Le test refuse un refuge plus grand que le vrai rayon, diagonale comprise,
et un refuge plus petit que 90 % de lui.

---

## `BossSpawn` — l'arrivée

**Ce qu'il doit faire sentir.** Qu'il faut arrêter ce qu'on fait. Il ne blesse personne : son seul travail
est d'être impossible à manquer et impossible à confondre avec un impact.

**Ce qu'il a remplacé.** Une colonne d'énergie violette qui grossissait, vingt-huit motes, et l'onde de
choc standard. C'est-à-dire l'apparition de boss par défaut de Roblox, teintée.

**Comment il est construit.** À l'envers. Le grain de la page est **aspiré** depuis quatorze studs dans
le point où le boss va tomber — une vraie convergence, depuis une coquille, et non des particules envoyées
« à l'envers » depuis un point (D-70) —, le sceau est **tracé sur place** en tournant plutôt que refermé,
parce que l'anneau qui se referme est l'horloge des attaques et que la première chose que voient six
joueurs ne doit pas leur apprendre qu'elle est inoffensive, et le sol s'assombrit avant de s'éclairer.
C'est le seul effet du jeu à déclencher la pulsation `Erasure` de `LightingConfig` : près de cinq secondes
d'écran **drainé** et non flashé, sur les cinq effets de post-traitement à la fois. Et le seul du boss à
garder une chose empruntée, le `ExplosionBloom` de toute détonation, parce que c'est la seule fois où il
est plus fort qu'elles.

---

## `BossDefeated` — la fin

**Ce qu'il doit faire sentir.** Que c'est rendu. Le seul temps du combat qui appartient aux joueurs qui
regardent plutôt qu'au boss.

**Ce qu'il a remplacé.** Une boule qui se contractait en `Back` puis grossissait à huit fois le rayon en
s'effaçant, plus trente-six éclats.

**Comment il est construit.** Le miroir de l'arrivée : ce qu'il avait pris ressort. Le sceau se referme en
`Quint` entrant sur six dixièmes — il se rassemble, hésite, puis part —, l'onde repart en `Exponential`
sortant à soixante-dix studs et l'encre qu'il avait prise est jetée en retour sur la page. Puis le résidu
fait ce que ne fait aucun autre résidu du jeu : le papier nu s'efface **d'abord**, et l'encre revient
par-dessus — en deux couches, une qui arrive et une qui part, parce qu'une couche ne va jamais que dans
un sens. La page est rendue dans l'autre sens.

---

## Ce qui n'est pas fait

**Le son en couches, encore.** Les six effets jouent un seul `ImpactExplosion`, programmé sur la fin de
l'avertissement par `VfxTimelineConfig.phaseAt` — donc au bon instant, ce qui est le minimum, mais un seul
son, et le son de toute détonation. La passe 5 le construit en entier, et donne au boss le sien.

**Rien ne remplace le corps du boss.** Ces fiches décrivent ce qu'il **fait** ; le boss lui-même est
encore un bloc gris de 8 × 14 × 8 studs construit par `WorldBossService`. C'est la passe 7 (« le monde »)
qui le met en scène, et aucune timeline ne peut le faire à sa place.

**Rien n'a été vu dans un client vivant.** Ni ces sept timelines, ni les dix-neuf glyphes de la passe 4.
Ce que les portes couvrent est dit plus haut ; ce qu'elles ne couvrent pas — une combinaison de valeurs que
le runtime traiterait mal, un décalque à la mauvaise face (D-68, trouvé par relecture et non par porte) —
ne se voit qu'en jouant.
