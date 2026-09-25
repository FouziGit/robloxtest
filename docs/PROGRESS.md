# Progression

Reprise : « continue depuis docs/PROGRESS.md ». Lire ensuite `docs/PLAN.md` (phases), `docs/DECISIONS.md` (D-1 à D-27), `docs/ARCHITECTURE.md` (contrats d'API), `CLAUDE.md` (conventions).

## État global

| Phase | Statut | Commit |
|---|---|---|
| 0 — Audit, plan, conventions | ✅ | `4e14c6f` |
| 1 — Fondations (toolchain, `src/`, ProfileStore, remotes sûrs, services, client, UI) | ✅ | `a8f943d`…`130db43`, correctifs `d72a551` |
| 2 — Cœur du combat + roster 20 glyphes + Orpiment | ✅ | `ca3883a` |
| 3 — Mobile, manette, UI responsive, localisation EN/FR | ✅ | intégrée aux phases 1-2 + `c022f71` (export CSV, garde anti-chaîne en dur) |
| 4 — Hub, arènes, matchmaking, matchs classés, Elo, leaderboards | ✅ | `84d91c7` |
| 5 — World Boss | ✅ | `831a789` |
| 6 — Quêtes, daily, loadout, cosmétiques | ✅ | `831a789` |
| 7 — Monétisation, boutique, analytics | ✅ | `831a789` |
| 8 — Sécurité, performance, polish, docs finales | ✅ | `8eac72b`…`1b160c2` |

## Chiffres

133 fichiers `.luau` hors bibliothèque vendorée, 30 426 lignes, 8 documents, 306 clés de localisation EN/FR, 126 tests Lune sur 20 fichiers de spécification, 7 portes de qualité en CI.

## Ce qui reste à faire par le propriétaire

1. **Créer les game passes et developer products** dans le Creator Dashboard et coller les IDs dans `src/shared/Config/MonetizationConfig.luau` — noms, prix conseillés et emplacements exacts dans `docs/STUDIO_SETUP.md`. Le serveur affiche un `warn` par ID manquant au démarrage et refuse proprement ces achats en attendant.
2. **Publier la place** et cocher *Game Settings → Security → Enable Studio Access to API Services*, sinon rien n'est sauvegardé (ProfileStore le signale dans l'Output).
3. **Aucune `SpawnLocation` ni baseplate ne doit être créée à la main** : `HubService` construit le hub et `HubSpawn` doit rester le seul point de spawn (le service avertit s'il en trouve un autre).
4. Optionnel : secrets `ROBLOX_API_KEY`, `UNIVERSE_ID`, `PLACE_ID` pour la publication automatisée (`.github/workflows/publish.yml`).

## Reste (suite technique possible)

- File d'attente inter-serveurs via `MemoryStoreService` (l'interface de `MatchmakingService` est prête ; aujourd'hui la file est intra-serveur).
- Anti-téléport / anti-speed par comparaison du déplacement attendu et observé (D-13 : les i-frames du dash sont accordées sur la seule décision serveur).
- Caisses ou aléatoire payant : volontairement absents (boutique directe, voir `docs/ECONOMY.md`) ; nécessiteraient `PolicyService` et l'affichage des probabilités.
- Système de spectateur (D-22 : un joueur éliminé attend au hub).
- Découper les trois gros modules, par maintenabilité seulement : `VfxLibrary` (1 851 lignes, un module par famille d'effets), `CombatService` (1 271, le corps-à-corps et la garde sont séparables du cœur de dégâts) et `Effects/GlyphEffects` (1 183, un module par archétype). Aucun effet sur le jeu, mais à faire avant d'ajouter un sixième pigment. `MatchService` (792), `SettingsScreen` (706) et `InputController` (670) sont au-dessus de la limite indicative de 500 lignes sans être problématiques ; `Strings` (554) est une table de données et n'entre pas dans le compte.

## Definition of Done (mission §9)

- [x] Tous les documents de §5 existent et sont à jour ; `CLAUDE.md` à la racine
- [x] `rojo build` OK, format/lint/analyse/tests verts, CI verte sur GitHub
- [x] 1v1 classé et 3v3 jouables de bout en bout (file → match → résultat → Elo → classement → hub)
- [x] World Boss fonctionnel
- [x] 20 glyphes + pigment Orpiment, encre, M1/dash/garde, VFX rendus par le client
- [x] Mobile et manette jouables ; touches par défaut sans conflit QWERTY/AZERTY
- [x] EN par défaut + FR, zéro chaîne en dur (vérifié en CI)
- [x] Game passes, developer products, `ProcessReceipt` idempotent, pass premium, boutique, bonus Premium, analytics
- [x] Aucun TODO/placeholder ; seuls les IDs Roblox restent à renseigner, avec avertissements au démarrage
- [x] Historique git propre en Conventional Commits, tout poussé sur `origin main`
- [x] Passe de durcissement : trois revues adversariales enchaînées. La première a rendu 30 constats retenus (3 critiques, 10 élevés) ; la seconde, lancée sur les correctifs eux-mêmes, en a rendu 21 de plus dont 9 confirmés et 1 critique — une régression introduite par le premier correctif anti-triche. Tout est corrigé, et les décisions dont la conception a changé en route (D-32, D-33) ont été réécrites plutôt que contredites.
- [x] Rapport final dans le chat

## Passe « Identité & Game Feel »

| Phase | Statut | Commit |
|---|---|---|
| 0 — Audit du game feel, bible d'art, plan | ✅ | `266bbf3`, `573a3d7` |
| 1 — Le lexique et le lore | ✅ | `4fc31f6`…`fddeb8b` |
| 2 — `Feel` et `FeelConfig` | ✅ | `14ef09b`, `be45b2f` |
| 3 — Le pipeline VFX | ✅ | `3a7f5ec`…`85a1ef5` |
| 4 — Refonte sort par sort | 🟡 | `2ed31d8`…`0d4db15` — les vingt glyphes sont faits, L'Effacement reste |
| 5 à 9 — audio, UI, monde, boucle d'accroche, performance | ⬜ | — |

### Phase 1 — fait

- Cinq pigments, vingt glyphes, cinq rangs, « encre », vingt-trois cosmétiques, les noms de modules et de fichiers, les clés EN et FR, les documents, et le nom du projet (**Vellum**).
- `DataMigration` version 3 déplace quatre clés de profil et traduit leurs valeurs ; `Pure/LegacyNames.luau` porte les quatre tables de correspondance. `DataService` passe ces tables à la migration — sans ce paramètre un profil V2 se rechargeait vide.
- Trois portes nouvelles : `tests/Lexicon.spec.luau` (quatorze mots interdits dans `src`, `tests` et `docs`, camelCase inclus, plus la vérification des exemptions), `tests/EffectCoverage.spec.luau` (chaque sort atteint son effet serveur et son rendu client), et la preuve de migration étendue aux cosmétiques et aux compteurs.
- Deux noms de DataStore restent volontairement inchangés (D-44).

### Phase 1 — ce que les portes ont attrapé

- `GlyphConfig` réclamait `Effect = "Brand"` quand `GlyphEffects` déclarait encore `Fireball` : **aucun des vingt sorts n'était lançable**, et les sept portes étaient vertes. D'où `tests/EffectCoverage.spec.luau`.
- `Instance.new("Fire")` réécrit en `Instance.new("Cinnabar")` : `Fire` est une classe Roblox, pas un pigment. Selene l'a refusé, pour la deuxième fois.
- Le document de design listait toujours les cinq rangs empruntés et l'économie vendait encore une aura nommée d'après un personnage de la licence, longtemps après que le code fût propre. D'où l'extension du test aux documents. (Ce journal est scanné comme le reste : il décrit les mots refusés sans les écrire, ce qui est la bonne discipline de toute façon.)
- Deux balayages ont réécrit des fichiers qui doivent garder les anciens noms : la colonne « Avant » de l'`ART_BIBLE` et les fixtures de migration. D'où les assertions qui vérifient que les fichiers exemptés contiennent encore ce pour quoi ils sont exemptés.

### Phase 2 — fait

- `Pure/Spring.luau` (Euler semi-implicite à pas fixe, sous-échantillonné pour survivre à une image longue), `Pure/FeelMath.luau` (hit-stop selon les dégâts, atténuation par la distance, courbe d'impulsion normalisée, maintien puis fondu), `Config/FeelConfig.luau` : tous les chiffres, aucun ne touche à l'équilibrage.
- `Controllers/Feel.luau` : hit-stop, secousse par bruit de Perlin, impulsions de champ de vision, contour d'impact, nombres de dégâts, haptique manette, ressorts partagés. Une seule liaison de rendu pour tout.
- Câblé d'abord sur le M1 et l'esquive, puis sur l'impact. Le paquet `Hit` porte maintenant l'attaquant, la victime et la direction du coup.
- Recul et esquive suivent une courbe décroissante à distance totale inchangée.
- `Pure/Spring.luau` remplace `littensy/ripple` (D-47).

### Phase 2 — ce que les portes ont attrapé

- La porte d'analyse ne couvrait que `src/shared`, soit un quart du code et aucun fichier touchant le moteur. Élargie (D-51), elle a immédiatement révélé deux erreurs de type réelles.
- Selene a refusé un helper devenu mort après le passage de la secousse dans `Feel`.

### Phase 3 — fait

- **Textures générées.** `tools/textures/` : générateurs en Python pur (bibliothèque standard seule, y compris l'écriture PNG), douze textures dans `assets/textures/`, toutes blanches à canal alpha pour être teintées par pigment. Déterministes, vérifié en régénérant deux fois et en comparant les octets. Aucune ne vient de la boîte à outils.
- **Palette.** Les cinq pigments prennent les valeurs exactes de l'`ART_BIBLE`, et un test tient chaque paire à distance perceptuelle (D-52).
- **Éclairage.** `LightingConfig` + `WorldLighting` : le monde était sur le ciel et la lumière par défaut de Roblox. Les cinq effets de post-traitement sont déclarés en **décalages depuis le repos**, jamais en valeurs cibles, ce qui rend « jamais permanent » structurel.
- **Pooling.** `Pure/PoolPolicy` (comptabilité testable sans moteur) + `VfxPool` (les instances). Réinitialisation à l'emprunt, jamais au retour.
- **Timelines.** `VfxTimelineConfig` décrit un effet en cinq phases ; `VfxTimeline` les joue sur une seule connexion `Heartbeat`. Trois effets convertis en preuve : le lancement, l'impact et l'esquive.
- **`AssetIds`** centralisé, identifiant vide = pas encore téléversé, avertissement nommant le fichier, jamais de plantage.

### Phase 3 — ce que les portes et la relecture ont attrapé

- Le générateur de trait de pinceau produisait un losange chromé lisible dans n'importe quel autre jeu Roblox. Réécrit : directionnel, quinze pour un, poils discrets, queue qui se casse par seuil et non par fondu. C'est la règle de jugement de la mission appliquée à sa propre sortie.
- Le pool ne connaissait ni `Decal` ni `Beam`, que la timeline emprunte : chaque sceau et chaque brûlure au sol serait sorti sans texture, et aucun trait n'aurait été tracé.
- `VfxPool.acquire` peut refuser au plafond et renvoyer `nil` ; le runtime l'assumait non-nul. Une couche qui n'obtient pas ses instances n'est simplement pas dessinée, ce qui est la dégradation que demande la règle 8.
- `WorldLighting.pulse` ne renvoie rien ; mon runtime testait sa valeur de retour et aurait averti à chaque impact.
- `Trail` et `Light` ne s'unifient pas en Luau : `Trail | Light` n'a aucun membre, donc la branche combinée est une erreur de type et non un raccourci.

### Phase 3 — la relecture adversariale

Six agents ont relu les trois chantiers bâtis en parallèle : 26 constats confirmés, aucun critique. Ce qui en est sorti et qui était un vrai défaut :

- **Rien n'exécutait les générateurs de textures.** Toutes leurs propriétés — déterminisme, dimensions, grille du flipbook, tuilage sans couture — avaient été vérifiées à la main une fois puis laissées sans garde, et le couplage qui s'était déjà cassé une fois survivait sur 0,16 px de marge. `scripts/check.sh` et la CI régénèrent et refusent toute différence (D-60).
- `Canvas.blit` n'avait aucune vérification de bornes et échouait **silencieusement dans les deux sens** : une ligne qui dépasse le bord droit se replie sur le bord gauche de la suivante. C'est exactement le décalage dont dépend le flipbook.
- L'impulsion `Erasure` n'était déclenchée par rien : trois passes de post-traitement vivantes pour aucun retour visuel. Elle part à l'annonce de L'Effacement, ce dont elle porte le nom.
- Deux impulsions simultanées dépassaient une bande que la configuration dit tenir : la saturation atteignait -1,08 et passait le recouvrement collée au plafond de -1, soit un écran entièrement gris que personne n'a choisi. Un impact pendant l'arrivée de L'Effacement n'est pas un cas rare, **c'est** le combat de boss.
- Un joueur ayant coupé la secousse de caméra recevait quand même un blanchiment plein écran à chaque impact proche. Les impulsions obéissent maintenant à ce réglage, le seul contrôle de réduction de mouvement que le profil possède.
- Le test d'éclairage lisait ses seuils dans le fichier qu'il garde : l'édition qu'il prétendait arrêter pouvait élargir la bande en passant.
- `VfxPool.lease` était une API sans appelant. `resetEmitter` oubliait `WindAffectsDrag`, que le constructeur de couches écrit. Le test des plafonds recopiait à la main la liste des classes, donc il ne pouvait pas échouer quand le pool en gagnait une — ce qui était déjà arrivé, en silence, avec `Decal` et `Beam`.

Et deux constats qui me visaient : un changement de code emporté dans un commit étiqueté `docs:`, et un message de commit décrivant un trait de pinceau qui n'a pas été livré. Les deux sont corrigés au registre (D-58, D-59), pas dans l'artefact : la version livrée est meilleure pour son usage réel.

### Phase 4 — fait

- Le format a gagné la phase Voyage qu'il promettait : un **porteur** invisible qui vole, et toute couche qui déclare `Ride` est construite dessus. Il parcourt sa distance en courbe et monte et redescend d'un arc.
- Une couche peut être ancrée au **corps du lanceur** (`Follow`). Plusieurs zones sont recentrées sur lui par le serveur à chaque tick ; un visuel épinglé au point de lancement dessinait une frontière brûlante autour d'un sol vide.
- **Les vingt glyphes** sont des timelines : 26 timelines, 312 couches. L'audit en comptait 72 au total, sans un seul `Beam` ni décalque. Le recensement actuel : 101 émetteurs, 65 traces au sol, 47 lumières, 27 secousses, 26 sprites, 22 traînées, 13 `Beam`, 8 porteurs.
- `VfxLibrary` passe de 1912 à 890 lignes. Tout l'étage impératif — les piques, les plaques de pierre, les barreaux, la gigue des éclairs, quarante-cinq constantes et neuf helpers — est supprimé.
- `docs/VFX_SPECS.md` porte une fiche par effet, par école, en français.
- Six nouvelles portes : ce qui atterrit laisse une trace, chaque glyphe a une lumière, un porteur ne dépasse jamais la portée du sort, tout passager a une monture, toute traînée déclare ce qui la déplace, et aucune couche ne chevauche et ne suit à la fois.

### Phase 4 — L'Effacement, converti

- Le format a appris ce qui lui manquait pour le boss, et rien de plus. **Une phase fenêtrée** (`Window`) prend sa durée du paquet et ses couches se déclarent en fractions ; seule l'anticipation peut l'être. **Une couche mesurée** (`SizeFrom`, `SpanFrom`, `OffsetFrom`) se dimensionne sur le rayon ou la portée que le serveur a envoyés, et n'est pas dessinée si le rendu ne les a pas passés. `Span` rend un plan plus long que large, `EndBrightness` fait monter une lumière, et une trace au sol est orientée par la direction de l'effet — elle ne l'était par rien avant.
- **Huit timelines** : les quatre attaques, le refuge de l'Éruption en vert, le papier nu en vélin (`BossScour`), l'arrivée et la fin. 34 timelines, 419 couches, dont 108 pour le boss ; 131 émetteurs, 111 traces au sol, 60 lumières, 39 secousses, 26 sprites, 22 traînées, 13 `Beam`, 9 éclairs d'écran, 8 porteurs. `VfxLibrary` passe de 912 à 819 lignes ; les six rendus impératifs, leurs helpers, quinze constantes, deux shims de caméra et un type mort sont supprimés.
- **Quatre textures dont l'encre atteint le bord** (`tools/textures/telegraph.py`), et une jauge : `AssetIds.Ink` dit jusqu'où l'encre de chaque texture atteint, `tools/textures/check_ink.py` mesure les PNG dans la porte des textures, et le télégraphe est tenu à son encre et non à son rectangle (D-71).
- **La peinture couvre les dégâts, et un test l'échantillonne.** `tests/BossTelegraph.spec.luau` reconstruit la forme de `isInShape` depuis `WorldBossConfig` et vérifie : couverture du disque, de l'anneau et du cône tous les quarts de stud ; refuge jamais plus grand que le vrai rayon, diagonale comprise ; lisibilité dès la première image ; fenêtre résolue sans clamp dans chaque phase du combat, impact à sa fin ; une timeline par forme ; le rendu passe ce que les données mesurent. Chaque assertion a été vue échouer sur un défaut réintroduit — neuf mutations au total — avant d'être gardée.
- **Le boss ne bouge plus pendant qu'il prévient, et les dégâts lisent l'origine figée** (D-72). Antérieur à la passe : jusqu'à 22 studs entre la peinture et le coup, et un refuge qui glissait sous les pieds.
- **La couleur du boss est le vélin**, et ce qu'il laisse aussi (D-63, D-73).

### Phase 4 — ce que la relecture adversariale a attrapé

Onze agents, quatre lentilles (runtime, identité, lisibilité-comme-règle, contrat), trente-huit constats, trente-cinq debout après réfutation. Les vrais :

- **Les décalques au sol regardaient le sol** (D-68) : `Front` est −Z et mon repère mettait +Z le long de la normale. Latent — aucune texture n'est en ligne —, il aurait éteint les 109 marques du jeu à la première mise en ligne. Aucune porte ne le voit ; une relecture, oui.
- **Une vitesse négative ne convergeait pas** (D-70) : quarante-deux couches demandaient une aspiration et rayonnaient à l'envers. Corrigé dans le runtime sans toucher aux données.
- **Ma porte mesurait le plan, pas l'encre** (D-71) : un Slam de 22 studs peignait 14 studs d'encre.
- **Le budget de couches retirait les avertissements en premier** — les plus vieilles couches de l'écran (D-69). Un avertissement n'est plus jamais retiré, et se dessine nu quand sa texture manque.
- La levée d'une marque était multipliée par la mesure (3,2 studs en l'air sur le trait du Balayage) ; la sonde au sol n'excluait que le personnage local ; une couche `Follow` pouvait déplacer le corps qu'elle suit ; la lumière du Cast était éteinte aux deux bouts depuis sa naissance ; `impactAt` rendait 0 pour un id inconnu, donc un son immédiat pour un visuel absent.
- Sur les données (D-74) : matière du boss en grain de page et non en étincelles, deux horloges de Furie dès la première image, sol allumé d'abord, horloges en balayage régulier, crue lisible dès la première image et consumée à l'impact, sceau de l'arrivée tracé sur place, refuge qui survit, émetteurs de l'Éruption mesurés.
- Deux constats refusés avec leur raison (D-74).
- Le ménage : `AnimateRadiusStuds` sans lecteur (D-75), un commentaire orphelin, et **le boss s'appelle L'Effacement pour le joueur aussi** — les `boss.*`, la saison devenue Volume et le combo devenu Séquence n'avaient jamais quitté le lexique d'avant.

### Phase 4 — ce que la relecture du document a attrapé

- **Quatre rapports d'agents commités dans `docs/VFX_SPECS.md`**, dont deux clôtures de code orphelines qui rendaient toute la section Terre d'Ombre comme un bloc de code (D-67). Retirés. Les deux faits vrais qu'ils contenaient sont corrigés : le joueur qui esquive était **secoué deux fois** (D-65), et six tooltips décrivaient encore leurs glyphes dans le vocabulaire d'avant VELLUM — dont le Colophon sous le nom emprunté de sa divinité, **traduit**, dans les deux langues, alors que le nom original était banni depuis la passe 1. La porte du lexique bannit désormais la traduction aussi (D-66, qui la cite).

### Phase 4 — ce qui a été vu dans un client vivant, et comment

Les **huit timelines du boss ont tourné dans un client vivant**, par le vrai chemin : un place de travail construit avec un script serveur supplémentaire qui émet les six paquets par `VfxBroadcaster.emit` toutes les sept secondes (D-76), joué en session de test, sondé depuis la barre de commande. Sur toute la session : **zéro erreur**, aucun avertissement « measures a layer against a length the renderer did not pass », aucun « follows the caster ». Les sondes ont lu, pendant les fenêtres : le Balayage en cinq barres de 9, 12, 18, 23 et 29 studs de large sur 8 de profondeur, posées à 0,03 stud du sol le long de la direction, l'horloge à 0,13 ; l'Éruption avec sa crue de 92 studs en `255,96,72` et son refuge de 32 en `110,210,150` sur un second jeu ; toutes les plaques couchées (`ZVector = (0,1,0)`) et leur axe long sur la direction de l'effet ; 42 instances rendues au pool. Ce sont les nombres de `WorldBossConfig` multipliés par les données, exactement.

Ce qui n'a **pas** été vu : l'image elle-même. Aucune texture n'est en ligne, donc les avertissements se dessinent en plaques nues et le reste n'est pas dessiné (`docs/STUDIO_SETUP.md` §7), et la caméra de la session ne regardait pas là où les effets tombaient — les sondes voient ce que l'écran ne montrait pas. Et les **dix-neuf glyphes** de la passe 4 n'ont pas été éprouvés en jeu : Studio restaure obstinément sa session et rouvre un place périmé, et je n'ai pas trouvé de chemin fiable pour lui faire charger le fichier construit. Les portes statiques couvrent les clés de texture, les noms de profils, les comptes de couches, les durées, la portée des porteurs et l'ancrage des traînées ; ce qu'elles ne couvrent pas, c'est une combinaison de valeurs que le runtime traiterait mal. C'est une lacune réelle, pas un oubli.

### Phase 5 — fait

- **Cinquante-cinq sons générés par script** (`tools/audio/`), déterministes à l'octet, 3,6 Mo : les voix des cinq pigments (attaque, corps, queue, impact — l'Orpiment n'a pas de queue, rien de lui ne vole), le kit de mêlée et la garde, le boss, la séquence, l'interface, trois boucles. Régénérés et comparés par `scripts/check.sh` et la CI. Aucun asset d'origine extérieure ne reste ; les quatre `rbxassetid` d'origine inconnue et le ping du moteur sont partis (D-77). Chaque fichier est tracé dans `docs/ASSETS.md`.
- **Le son est une couche de timeline** (D-78) : 50 couches `Sound` — l'attaque dans le `Cast` partagé, corps / queue / impact dans les phases de chaque glyphe (la queue **ancrée** au porteur), `BossWarn` ajusté à la fenêtre par `Fit`, `BossImpact`, `BossArrival`, `BossDefeat` avec `Duck`, les deux ultimes qui atterrissent d'eux-mêmes aussi. Le serveur n'envoie plus de `SfxId`. Hauteur ±5 % à chaque jeu, fichiers normalisés en RMS par voix.
- **Deux `SoundGroup`, un arbitre de musique et le ducking** (D-79, D-82) ; **la séquence est une gamme** (D-80) ; **la musique suit l'état** — match, compte à rebours, ouverture, résultat, boss (D-81).
- Sept nouvelles portes (`tests/SoundConfig.spec.luau`, `tests/VfxTimeline.spec.luau`) : durée et format lus dans l'en-tête WAV, trois voix par pigment et une note, chaque glyphe voicé phase par phase **et** atterrissant quelque part, chaque voix configurée atteignable par une timeline, une queue listée après son porteur, avertissement fenêtré audible sur toute sa fenêtre, clés connues. Chacune vue en échec sur un défaut réintroduit.
- **Une relecture adversariale** (D-82) a repris le synthé — repli de phase, clamp de la gamme, stabilité du filtre, normalisation — et une bonne part des recettes : les impacts sont des corps frappés et non le « boum » sub de tous les jeux, audibles sur un téléphone.

### Phase 5 — ce qui n'est pas fait

Rien n'a été **entendu**. Les WAV ne sont pas téléversés (`docs/STUDIO_SETUP.md` §8) et je n'ai pas d'oreille : les formes ont été vérifiées par profils d'énergie (montée du `BossWarn`, décroissance des pincements, absence d'écrêtage et de clic), pas à l'écoute. Le mixage — volumes relatifs, rolloff — est une première proposition à ajuster en jouant.

### Phase 6 — fait

- **L'interface est une page** (D-83) : `ThemeConfig` pur — Vélin, Charbon, les pigments en encre là où ils sont du texte, Merriweather pour les mots et Oswald pour les nombres, `FontFace` partout (31 sites), `Theme.inkOn` par contraste WCAG. Le thème sombre et l'or sont partis ; aucun composant de `src/ui` ni de `src/client` n'écrit un `Color3` ou une police en dehors de `Theme`.
- **Tout bouge sur ressort** (D-84) : `src/ui/Motion.luau`, un `Heartbeat` pour toute l'interface ; `Toast`, `TouchButton`, `Toggle`, `Tabs`, `Button` (qui s'écrase à la pression), `ProgressBar`, `ScreenRoot` (entrée de chaque écran) ; `TweenService` et `Theme.Animation` ne sont plus dans `src/ui`.
- **Le fantôme, les jetons, le compteur, la carte** (D-85) : barre de vie avec fantôme en Cinabre qui rattrape sans jamais dépasser ; jetons de séquence qui poussent et se replient ; compteur `×N` de séquences résolues d'affilée ; carte de résultat composée — score en Oswald à 48 sur un filet d'encre, rang tamponné, monde assombri.
- **Une porte** (`tests/Interface.spec.luau`, 14 tests) : la page aux hexadécimaux de `ART_BIBLE`, l'accent qui est l'encre, le danger qui est le Cinabre exact, chaque rôle de texte à son contraste sur son papier, l'encre qui se lit sur chaque pigment, les polices hors des défauts du moteur et dans leur famille (romane, condensée), les trois presets et leur amortissement, aucun tween, aucune couleur, aucune police hors de `Theme`, et deux gardes de non-vacuité. Treize mutations, treize prises.

### Phase 6 — ce qui n'est pas fait

Rien n'a été **vu**. Le thème, les polices et les ressorts n'ont pas tourné dans un client : le contraste est calculé, pas regardé, et la disponibilité des graisses de Merriweather et d'Oswald sur le moteur est celle de la documentation. Un écran, un jeton qui pousse, une barre qui perd et son fantôme sont les premières choses à regarder en jeu.

### Phase 7 — fait

- **Le monde est la page** (D-86) : `WorldConfig` pur, cinq teintes et un matériau, `Util/Palette` pour la conversion ; hub, arènes et épreuves rebâtis en vélin, os, craie et encre — sceau de craie pour le spawn, filet d'encre au sommet des murs, croix de repérage sur les épreuves. Aucun `Color3` ni `Enum.Material` dans `src/server`.
- **L'Effacement a un corps** (D-87) : figure blanche dans sa coque de contact, bande d'encre dont la hauteur est la phase, `BossPhase` émis et rendu à chaque franchissement (timeline de huit couches), déplacement par `PivotTo`.
- **La page se souvient** (D-88) : empreintes d'encre sous chaque pas, `VfxTimeline.stamp`, budget propre.
- **Une porte** (`tests/WorldConfig.spec.luau`, 12 tests) : teintes jamais colorées, monde clair et encre sombre, la page aux hexadécimaux de la bible, chaque rôle résolu, un matériau, la figure dans la coque, une hauteur de bande par phase et croissante, empreinte qui s'efface sur une texture existante et sous le tiers du budget, aucune couleur ni matériau nommé par un bâtisseur, garde de non-vacuité. Quatorze mutations, quatorze prises ; `EffectCoverage` et `BossTelegraph` étendus à `BossPhase`.

### Phase 7 — ce qui n'est pas fait

`Lighting`, `Atmosphere` et la brume sont ceux de la passe 3 ; pas de ciel (aucun asset vérifié : la raison est dans `LightingConfig.Atmosphere`, passe 3). L'**annonce** et la **montée** de L'Effacement restent ce que les passes 3 et 5 ont fait (pulsation `Erasure`, musique, bandeau, `BossSpawn`) : cette passe a mis en scène le corps et les phases. Rien n'a été **vu** : le monde recoloré, la figure, ses phases et les empreintes n'ont pas tourné dans un client. La géométrie est tenue par des tests ; l'image ne l'est pas.

### Ce que les deux relectures ont changé (passes 6 et 7)

- **Passe 6** (D-89) : le fantôme de la barre de vie passait devant le remplissage à chaque **gain** — donc une bande de Cinabre à chaque soin, à chaque tic de régénération et sur la première image du HUD ; l'entrée d'écran mettait l'échelle sur la zone sûre et laissait une bordure de monde non assombrie (l'entrée est descendue dans `Panel`) ; l'étiquette de barre était du vélin sur du vélin (1,19) ; les libellés du HUD gardaient le contour noir du moteur ; le compteur comptait des lancers que le serveur refuse ; le Cinabre portait six sens sur le HUD. Trente constats, dont les faux refusés avec leur raison.
- **Passe 7** (D-90) : le socle du spawn devenu cylindre faisait **flotter les épreuves à 6,5 studs** et lâchait les joueurs de retour **5,5 studs en l'air** ; chaque marque au sol de L'Effacement était peinte dans la couleur du sol ; la coque de contact faisait 8 studs pour une figure de 4,2 ; la bande sautait avant son anticipation ; l'emblème du hub était un Indigo exact, en permanence.
- Chaque correction a sa porte : contraste de chaque encre contre son papier, figure qui **remplit** sa coque, rôles saturés interdits dans `src/server`, easing des empreintes tenu à ceux des timelines, budget des empreintes qui ne peut plus évincer un résidu de combat, paires de contraste réelles de l'interface.

### Phase 8 — fait

- **Plafond de compétence** (D-91) : annulation de récupération à la ruée (15 encre en plus), enchaînement remboursé (5 encre par lancer d'une chaîne, dans 1,0 s), compteur `×N` **compté par le serveur**, record personnel `Stats.BestChain`, deux quêtes d'exécution (`Chain`, `DashCancel`), et la **matrice outil → contre** des vingt glyphes dans `docs/GAME_DESIGN.md` §5 bis.
- **Boucle courte** : bouton **Rejouer** sur la carte de résultat, et `MatchmakingService` garde le vœu tant que le match tient encore le joueur — un clic, aucun hub à traverser.
- **Progression lisible juste après le duel** : la barre de niveau rejoue le gain depuis là où le joueur était (`ProgressionConfig.rewind`), remplit le niveau précédent quand un niveau est passé, et la prochaine récompense est nommée (`GlyphConfig.nextUnlock`).
- **Note d'exécution** : `Pure/Execution` (précision, échange, bonus de victoire), comptée par `MatchService` depuis `GlyphService.Cast` et `CombatService.Damaged`, tamponnée S/A/B/C sur la carte.
- **Découverte sans texte** : `OnboardingController` montre la recette du premier glyphe en jetons fantômes jusqu'au premier lancer accepté.
- **Portes** : `tests/Execution.spec.luau` (la note ne peut pas être achetée par la victoire, chaque lettre est atteignable par la seule précision) et le bloc « the loop » de `tests/Config.spec.luau` (prix de l'annulation, remboursement inférieur au glyphe le moins cher, rewind exact, prochain déblocage toujours le plus proche).

### Phase 8 — ce qui n'est pas fait

Le point 5 du plan (**social** : spectateur après élimination, emotes, partage) n'est pas livré, à l'exception de la revanche directe qui est la relance en un clic. Le spectateur demande que la caméra suive un coéquipier, donc que `Feel` — qui possède la caméra — apprenne une cible ; les emotes demandent des animations, et le partage une capture. Ce sont trois chantiers séparés, pas une fin de passe : ils sont notés ici plutôt que commencés à moitié. Le point 7 (variable sans être manipulatoire) était déjà tenu par la rotation quotidienne, les quêtes et l'annonce de L'Effacement ; les deux quêtes d'exécution s'y ajoutent.

Rien de la passe 8 n'a été **joué**. Les prix (15 encre pour annuler, 5 rendus par enchaînement, les poids de la note) sont une première proposition : ils sont tenus par des tests d'arithmétique, pas par une main sur un clavier.

### Phase 9 — fait

- **Quatre niveaux graphiques** (D-92) : `QualityConfig` (couches, particules, lumières, post-traitement, empreintes), un onglet **Graphismes** dans les options, le choix stocké dans le profil et validé deux fois (le `Guard` du remote et le service). Le mode **Performance** coupe les cinq effets de post-traitement.
- **Dégradation automatique** : `QualityController` compte les images et descend d'un niveau sous 40 img/s pendant 3 s, en rend un au-dessus de 55 pendant 12 s, jamais au-dessus du choix du joueur. Un seul propriétaire ; `VfxTimeline`, `WorldLighting` et `FootprintController` lisent le niveau à l'usage.
- **Le coût de chaque effet, calculé** (D-94) : `scripts/effect-cost.luau` — 35 timelines, 477 couches, pire effet 11 couches simultanées / 201 particules / 51 instances. `docs/PERFORMANCE.md` cite sa sortie, les plafonds de `tests/EffectCost.spec.luau` sont **dérivés** (moitié du budget plancher, quart d'un plafond de pool), et la densité suit les images par seconde plutôt que le nombre de voisins (D-93).
- **Un duel ne laisse rien derrière lui**, dans la mesure où un test sans moteur peut le prouver : `tests/PoolPolicy.spec.luau` joue 180 effets superposés et exige zéro instance vivante, zéro retour refusé, rien de garé au-dessus du plafond, et plus de 5 000 prêts pour moins de 2 % de créations ; `tests/Loops.spec.luau` déclare les quinze boucles par image du jeu et refuse la seizième.
- **Portes** : 338 tests, 38 fichiers. Vingt et une mutations pour cette passe, toutes prises — dont deux qui ont montré que la porte des lecteurs était trop lâche (une lecture commentée et un nom de champ homonyme), et qui l'ont resserrée.

### Phase 9 — ce qui n'est pas fait

**Aucun nombre d'images par seconde du dépôt ne vient d'un appareil.** Les coûts sont ce que le rendu *va* emprunter et demander ; ce qu'une image prend sur un téléphone donné est l'autre moitié, et elle demande cet appareil. Les seuils 40/55 sont les valeurs usuelles d'un client Roblox mobile, pas une mesure. La dégradation n'a jamais été **vue** descendre ni remonter, et les quatre niveaux n'ont pas été comparés à l'œil : ce sont des budgets tenus par des tests, pas un réglage éprouvé.

### Après les neuf passes — le dernier mot emprunté

La monnaie portait encore le nom de la licence que la passe 1 devait quitter : le lexique de `ART_BIBLE`
n'avait pas de ligne pour l'argent, donc le mot a traversé les neuf passes dans chaque notification de
récompense sans qu'aucune porte le voie. Elle s'appelle le **Folio** (D-95, qui cite l'ancien nom), dans le
code, dans les textes, dans les trois produits, dans les cinq documents et dans le README ; le profil passe
en version 4 et `upgradeToV4` porte le solde d'un joueur sauvegardé dans la nouvelle clé. L'ancien mot est
ajouté à la liste d'interdits de `tests/Lexicon.spec.luau` — la même leçon que D-66 : une liste d'interdits
ne contient que les mots auxquels quelqu'un a pensé. Ce document n'a donc plus le droit de l'écrire, ce qui
est exactement comme ça doit être : la porte a attrapé ce paragraphe avant la relecture.

### Ce que la relecture de la passe 8 a changé (D-96)

Vingt agents, quarante constats. Les graves, tous réels : le socle du spawn **corrigé à moitié** dans la
passe précédente (six épreuves suspendues d'un stud, chaque retour lâché d'un stud et demi) ; le fantôme de
la barre de vie effacé 200 ms après chaque coup par un état poussé cinq fois par seconde ; la note
d'exécution qui punissait les trois réponses structurelles de sa propre matrice ; une précision sans
plancher de volume, donc un seul lancer réussi valait 100 % ; l'annulation qui prenait la ruée d'esquive
entre 10 et 24 encre, sans message ; la relance à treize secondes au lieu de dix, dont sept gelées derrière
une carte déjà fermée.

Tout est corrigé, chaque correction a sa porte quand une porte est possible (cinq nouvelles, cinq mutations
prises), et trois erreurs de la matrice §5 bis sont réécrites — dont deux qui étaient des **dettes
d'équilibrage** déguisées en garanties : deux des trois réponses structurelles sont du même pigment, et
l'Insertion répond à cinq outils dont la recharge est plus longue que la sienne.

La leçon : trois des constats confirmés portaient sur du code écrit dans la passe précédente **pour
corriger une relecture**. Une correction n'est pas finie parce qu'elle a changé le nombre qu'on regardait.

Une dette d'équilibrage de plus, trouvée par la même relecture et corrigée plutôt que notée : le Pâté
retirait 56 points de vie sur une cible marquée, au-dessus du plafond absolu des ultimes (D-97). Il passe à
40, et la porte tient désormais chaque ultime — et la fenêtre de hit-stop — au coup **amplifié** plutôt
qu'au nombre brut.

### Le social de la passe 8, deux points sur quatre de plus

`SpectateController` : un joueur éliminé suit un coéquipier vivant (sujet de caméra posé par `Feel`, jamais
un adversaire), et le menu propose l'invitation native de la plateforme (D-99). Avec la revanche en un clic
déjà livrée, il reste les **emotes** — et elles sont bloquées par les assets, pas reportées : elles
demandent des animations, que ce dépôt ne peut ni produire ni emprunter.

### Ce que la relecture de la passe 9 a changé (D-100)

Quatre graves, tous réels, et la moitié d'entre eux n'existaient que parce que la passe 9 a rendu
**variable** ce qui était constant : l'éviction pouvait retirer un porteur et figer un projectile entier
(inatteignable à 90 couches, courant à 24) ; le seuil de retenue des empreintes valait le budget entier du
niveau Moyen ; un seul gel de trois secondes coûtait un niveau ; et choisir un niveau plus bas en étant
déjà rétrogradé faisait **remonter**.

Le modèle de coût a été refait : il comptait des couches qui ne prennent aucune place du budget et sommait
les instances sur la vie de l'effet pour les comparer à un plafond de simultanéité. Le pire effet passe de
11 couches / 51 instances à **10 / 27**, une porte relit les emprunts dans la source du rendu, et le
plafond de particules est désormais dit **choisi** et non mesuré — parce qu'aucun appareil n'a fait tourner
ce jeu, et que le test l'affirmait mesuré.

`docs/PERFORMANCE.md` dit maintenant **comment** mesurer (Performance Stats, MicroProfiler, l'application
sur un vrai téléphone) et dans quel ordre corriger : c'est le document qu'une personne prendra le premier
jour.

## Passe « Production » (D-109)

Après la comparaison avec les meilleurs battlegrounds. Directive du développeur : « fais tout toi-même » ; la musique et les sons sont les siens. Plan en huit phases dans `docs/PLAN.md`.

| Phase | Statut | Commit |
|---|---|---|
| 1 — Les cosmétiques s'affichent | ✅ | voir le journal git |
| 2 — Artisanat des particules | ✅ | `9af33da` |
| 3 — Le coup se sent (images d'impact, ragdoll) | ✅ | voir le journal git |
| 4 — Des volumes (meshes générés, pièce témoin : la Marque) | ✅ | `a100b84`, `05293fb`, kit et esquisses |
| 5 — Flipbooks procéduraux | ⬜ | — |
| 6 — Le monde réagit | ⬜ | — |
| 7 — Animations | 🔶 | branche `feat/anim-pipeline` (D-117) |
| Passe VFX (punch et lisibilité) | 🔶 | branche `feat/vfx-pass` (D-118…) |
| 8 — Interface et découverte | ⬜ | — |

### Phase 1 — fait

- **Aucun des quarante cosmétiques n'était dessiné**, et le catalogue enfreignait la bible (aura violette, Marque bleue). Redessiné dans les encres de la page, rareté portée par l'artisanat ; un skin est une nuance **mesurée** du pigment de son glyphe (-0,25 à +0,2).
- `CosmeticController` (auras, traînées, titres), la nuance écrite par le serveur dans le lancer, l'effet et le coup, quatre effets de kill en encre sur une nouvelle texture (`paper_scrap.png`, téléversée), l'aura VIP que le pass promettait.
- Un défaut plus ancien corrigé au passage : un attaquant périmé était crédité à la mort suivante du survivant.
- `tests/Cosmetics.spec.luau` ; 24 mutations, 24 échecs. Reste à voir en jeu : la vérification visuelle attend le serveur MCP de Studio (redémarrage de session).

### Phase 2 — fait (D-111)

- **L'encre sèche** : particules, traînées et taches au sol naissent mouillées et sèchent dans leur pigment ; nuance de skin et séchage bridés une seule fois (`PigmentConfig.shade`). Les taches sèchent sur l'horloge de leur sort : une tache en plusieurs maillons ne repâlit plus à chaque jonction (mesuré en jeu).
- **L'étincelle vole la tête devant** et s'étire le long de son vol (VelocityParallel, demi-tour, Squash négatif), vérifié en jeu.
- Les faisceaux défilaient déjà (`TextureSpeed` par défaut, remis par le pool). Les formes d'émission partielles et les flipbooks nets passent en phase 5, où chaque nouvel effet dessine sa texture et sa forme ensemble.
- `tests/ParticleCraft.spec.luau` ; 21 mutations, 21 échecs.

### Phase 3 — fait (D-112)

- **Le finisher fait tomber** : articulations desserrées par le serveur (tous les clients voient la chute), relevé physique, victime étourdie jusqu'à ce qu'elle soit debout.
- **Image d'impact à l'encre** sur les coups lourds et les finishers, pour les corps de l'échange, tous ceux d'une explosion ; mannequins et boss compris ; mouvement réduit respecté.
- **Mouvement réduit** de la plateforme respecté par la secousse, le coup de focale, l'éclair de page et l'image d'impact.
- Trois relectures adversariales ; `tests/HitFeel.spec.luau`, chaque mutation échoue (voir D-112).
- Vu en jeu ensuite (D-113) : la chute passe bien par le serveur ; elle devient un **knockdown lisible** (0,8 s à terre + 0,3 s de relevé), le corps à terre est **intouchable** (et n'est plus une cible), plus de tir ami en 3v3, la force revient progressivement (pire saut 40° au lieu de 106°) et le serveur vise toujours droit.

### Phase 4 — faite (D-114, D-115, D-116)

- **Un seul vol** (`a100b84`) : la Marque dessinée suit la vraie à moins de trois studs et retombe là où elle éclate ; lancer numéroté, `Fizzle`, attente au bout du vol, son de queue gardé.
- **Volumes générés** : sept maillages Blender reproductibles à l'octet, téléversés et résolus ; couche `Mesh` et couche `Debris` ; Explosion (ensō, anneau, couronne, papier) et Marque (goutte, balayage). Vus en jeu, puis relus : sol trouvé sous les mannequins et le boss, jamais par-dessus l'avertissement d'un autre effet, atterrissages sans à-coup (D-114).
- **Verrou sur un adversaire** (D-115, demandé en cours de phase) : clic molette / R3 / disque tactile ; caméra et orientation, adversaires en match, mannequins et boss hors match ; shift-lock retiré. Vu en jeu : orientation exacte, caméra sur la cible, relâché à la mort de la cible et hors de portée.
- **Le kit à l'encre** (D-116) : coup, impact et esquive au charbon, sans lumière ; un croissant de pinceau par coup et par impact ; deux empreintes d'encre du corps le long de l'esquive (une en Moyen, aucune en Bas), plus pâles pour soi, posées là où le corps passe vraiment. Vu en jeu, relu, refait.
- Reste : les phases 5 à 8.

### Phase 7 — en cours (D-117, suivi détaillé : `docs/anim-pipeline-progress.md`)

- **Un lancer par glyphe**, posé à la main sur l'horloge du serveur : la Marque pousse la paume dans le sceau à 0,06 s, l'instant où le serveur la lâche (l'ancien clip générique avait la main 2,2 studs derrière le corps à cet instant, mesuré en jeu). Haut du corps seulement : on lance en courant sans glisser.
- **L'outil** : `tools/animations/keyed.py` (poses clés → courbes → `.rbxmx`, vérifications chiffrées, aperçu Blender sans interface sur deux rigs mesurés dans Studio) ; `check.sh` reconstruit chaque clip depuis ses poses.
- **Le skill `vellum-animation`** (`.claude/skills/`, pointé par `CLAUDE.md`) fait de la méthode celle du projet ; essayé sur le **Lavis**, qui a désormais son propre lancer (deux paumes vers le sol à 0,10 s).
- **En jeu** : les deux clips sont téléversés (accord du développeur) ; chaque clip est chargé à l'apparition du personnage, le premier lancer d'une session ne reste plus vide.
- Reste : les autres glyphes, avec le skill.

### Passe VFX — en cours (D-118, suivi : `docs/vfx/AUDIT.md`)

- **Phase 0** : audit en lecture seule (5 lecteurs) ; causes mesurées : aucune lueur possible, traînée répétée chaque stud, gerbes vers le haut, impact délavé par le flash d'écran (−55 % de saturation), formes posées à plat, sort caché par le corps du lanceur, désynchronisations du Lavis et du Balayage.
- **Phase 1** : horloge d'effets (micro-arrêt d'impact en jeu, ralenti et gel dans Studio) et labo `tools/vfxlab/` ; planches « avant » de la Marque, du Lavis et du Balayage avec diagnostic noté (`docs/vfx/<sort>/`).
- **Phase 2** (D-119) : trois styles prototypés et figés au labo (`docs/vfx/styles/`), retenu « encre vive à cœur chauffé » ; rôles de couche (pigment, cœur, encre), palettes par pigment, halo global laissé tel quel (seuls les cœurs le franchissent).
- **Phase 3** (D-119) : la Marque finale en trois tours de planches (`docs/vfx/brand/`, avant 1/1/2/2/1/4, après 4/4/5/4/4/4) ; éclat dès l'appui, pop des particules, traînée en coin d'encre à trait chaud, impact en étoile avec gerbe d'encre et anneau de choc, gel d'impact sur l'horloge d'effets seulement (jamais sur ce que le serveur chronomètre), réglage « Secousses et flashs » qui bride le cœur. 6 lancers simultanés à 60 i/s dans Studio ; lisible au niveau Performance. `tests/VfxStyle.spec.luau`, 9 mutations, 9 échecs.
- Reste : skill `vellum-vfx` et autres sorts par ordre d'usage (phase 4) ; les 22 autres traînées texturées au pinceau.
