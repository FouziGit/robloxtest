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

- **Cinquante-six sons générés par script** (`tools/audio/`), déterministes à l'octet, 3,7 Mo : les vingt voix des cinq pigments (attaque, corps, queue, impact), le kit de mêlée et la garde, le boss, la séquence, l'interface, trois boucles. Régénérés et comparés par `scripts/check.sh` et la CI. Aucun asset d'origine extérieure ne reste ; les quatre `rbxassetid` d'origine inconnue et le ping du moteur sont partis (D-77). Chaque fichier est tracé dans `docs/ASSETS.md`.
- **Le son est une couche de timeline** (D-78) : 43 couches `Sound` — l'attaque dans le `Cast` partagé, corps / queue / impact dans les phases de chaque glyphe, `BossWarn` ajusté à la fenêtre par `Fit`, `BossImpact`, `BossArrival`, `BossDefeat` avec `Duck`. Le serveur n'envoie plus de `SfxId`. Hauteur ±5 % à chaque jeu.
- **Deux `SoundGroup` et le ducking** (D-79) ; **la séquence est une gamme** (D-80) ; **la musique suit l'état** — match, compte à rebours, ouverture, résultat, boss (D-81).
- Cinq nouvelles portes (`tests/SoundConfig.spec.luau`, `tests/VfxTimeline.spec.luau`) : durée et format lus dans l'en-tête WAV, quatre voix par pigment, un son par phase de chaque glyphe, avertissement fenêtré audible sur toute sa fenêtre, clés connues. Chacune vue en échec sur un défaut réintroduit.

### Phase 5 — ce qui n'est pas fait

Rien n'a été **entendu**. Les WAV ne sont pas téléversés (`docs/STUDIO_SETUP.md` §8) et je n'ai pas d'oreille : les formes ont été vérifiées par profils d'énergie (montée du `BossWarn`, décroissance des pincements, absence d'écrêtage et de clic), pas à l'écoute. Le mixage — volumes relatifs, rolloff — est une première proposition à ajuster en jouant.
