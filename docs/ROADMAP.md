# Vellum — la route vers la v2.1.0, puis la vie en ligne

*Écrit le 30/09/2026 à partir de la branche `feat/vfx-pass` (commit `ab993fa`), de `docs/PROGRESS.md`, `docs/QA.md`, `docs/PUBLISH.md`, du code et des pages web listées en fin de document. Le fichier `backlog.json`, à côté de celui-ci, contient exactement les mêmes épopées, stories, sessions et outils, dans un format que Claude relit.*

## 1. En un écran

### Où en est le jeu

- **Le jeu est riche et bien testé hors du moteur.** 28 glyphes, un hub à portails, du 1v1 et du 3v3 classés, le Champ de bataille contre les Faussaires, l'Effacement programmé, un pass de 50 paliers, des quêtes, une boutique tournante. `lune run tests/run` donne **1 785 tests verts dans 121 fichiers de spec** (relancé le 30/09/2026).
- **Mais tout vit encore sur une branche.** `feat/vfx-pass` a **266 commits** d'avance sur `main` : 352 fichiers, +74 117 / −7 894 lignes (`git diff --shortstat origin/main...feat/vfx-pass`). La PR #2 est ouverte, il n'existe aucun tag, et `main` n'est pas protégé (`gh api …/branches/main/protection` répond « Branch not protected »).
- **Rien n'a encore tourné pour de vrai.** Aucune sauvegarde sur un vrai DataStore, aucun match à plus de deux personnes, aucun téléphone, aucun son écouté (PROGRESS:173, :363, :454).
- **L'argent n'est pas branché.** Les 14 ids de passes et de produits valent 0. Trois promesses de vente ne sont pas tenues (R1, R8, R10 dans QA §12), un Premium acheté deux fois ne livre rien (R11) et un TierSkip peut boucler sans fin (R2).
- **Le classé est fragile.** Un redémarrage de serveur peut débiter les deux joueurs (R3), quitter évite la défaite (R4), deux comptes peuvent se farmer mutuellement, et le garde de mouvement ne fait qu'observer.
- **89 assets sur 91 sont approuvés** par la modération (2 textures encore « Reviewing »). Le dépôt GitHub est **public** : le code de l'anti-triche, seuils compris, est lisible par tous.

### Ce qui bloque la publication

1. **Le questionnaire de maturité.** Sans lui, Roblox restreint la jouabilité du jeu pour tous les joueurs.
2. **La PR #2** : relire le serveur, fusionner, poser un tag, protéger `main`.
3. **Un univers de test séparé** (Vellum-Test) avec ses propres produits : depuis le 30/05/2026, Roblox ne vend plus le produit d'un autre jeu.
4. **Les ids de vente**, collés seulement après avoir corrigé tout ce qui fait payer sans livrer (R1, R2, R8, R10, R11, R12, R14).
5. **Un classé honnête** : pas de débit au redémarrage, pas de farm, pas d'étourdissement sans fin, pas de chute de l'Effacement dans un duel, pas de classé en serveur privé acheté.
6. **Le vrai moteur et de vrais humains** : la sauvegarde vue sur un vrai DataStore, un test de fumée automatique, un playtest à 6-10 personnes, deux vrais téléphones, les 55 sons écoutés.
7. **Les labos Studio que le projet s'impose** : signal des Faussaires, 12 vérifications du garde, 18 objets vendus, 11 nouvelles chronologies, et 91 assets approuvés.
8. **Voir et répondre dès le jour 1** : entonnoir d'accueil, économie, équilibre des glyphes, Error Report réglé, et une réponse prête à une demande d'effacement de données.
9. **Une porte automatique** (`release-check`) qui refuse de publier si l'un de ces points manque.

Au total : **60 stories avant publication**, réparties en **20 sessions**. 8 ne peuvent être faites que par toi, 31 se font ensemble, 21 par Claude seul.

### Les 5 prochaines sessions

| # | Ce que Claude fait | Ce que tu fais | Ce que tu obtiens |
|---|---|---|---|
| 1 | Prépare les questions de décision avec options et recommandation ; épingle les types Roblox ; remplace les numéros de ligne périmés de PUBLISH et QA | Séance de décisions (1 à 2 h), questionnaire de maturité (20 min), choix du propriétaire du jeu | Chaque choix bloquant a son numéro D ; le jeu a son libellé de maturité |
| 2 | Relit les 40 fichiers serveur de la PR #2 en trois tranches et corrige les constats graves, chacun avec son test | Crée Vellum-Test et sa clé ; active le New Device Simulator et le MCP de Studio | Un serveur relu là où l'argent et les données se jouent |
| 3 | Fusionne après ton accord, protège `main`, sépare test et production, coupe Studio des vraies données | Valides la fusion ; colles les secrets dans GitHub | `main` redevient le jeu ; publier vers le test ne peut plus toucher la production |
| 4 | Tag VIP, TierSkip, Premium reçu deux fois, Folios rendus, test d'unicité des ids | Rien d'obligatoire (tu peux regarder le tag VIP à deux clients) | 5 écarts de vente fermés, chacun par un test prouvé |
| 5 | Promesses R8 et R10, panne de DataStore visible, compte développeur à armes égales | Crées 4 passes et 10 produits dans les deux univers ; crées le groupe et le Discord | `0 missing ids` au démarrage ; une communauté prête pour le playtest |

## 2. Comment lire ce plan

- **Phases.** P0 : avant la publication, bloque la v2.1.0. P1 : le lancement et les premières semaines. P2 : le premier mois, pour faire revenir. P3 : la croissance.
- **Responsable.** « Claude », « toi », ou « Claude et toi » quand il faut ton compte, tes yeux, ton accord ou un choix de jeu.
- **Effort.** S : quelques heures. M : une session. L : deux ou trois sessions. XL : une semaine ou plus.
- **Critères d'acceptation.** Chacun se vérifie par une commande, un test, une capture ou une ligne de journal. Une story n'est finie que quand tous ses critères sont vrais.
- **« Prouvé par mutation ».** On remet volontairement le défaut, on voit le test échouer, puis on retire le défaut. C'est la règle du projet : un test qu'on n'a jamais vu échouer ne prouve rien.

**Les mots qui reviennent**

| Mot | Ce que ça veut dire ici |
|---|---|
| Elo | La note de niveau du classé, qui monte ou descend après chaque match. |
| DataStore, ProfileStore | Le stockage des profils chez Roblox, et la bibliothèque qui le verrouille pour qu'un profil ne soit ouvert que sur un serveur à la fois. |
| Reçu, `ProcessReceipt` | Le message que Roblox envoie au serveur après un achat en Robux ; tant que le serveur ne répond pas « livré », Roblox le renvoie. |
| CI | Les vérifications que GitHub lance à chaque envoi de code (les cinq portes de `scripts/check.sh`). |
| Tag | Une étiquette posée sur un commit, pour publier et revenir en arrière vers une version précise. |
| Spec, Lune | Un fichier de tests, et l'outil qui les exécute sur ton Mac sans Roblox. |
| Luau Execution | Un service Roblox qui exécute un script dans le vrai moteur, sur une place publiée, sans écran. |
| Webhook | Un message que Roblox envoie tout seul vers une adresse que tu choisis (un salon Discord, par exemple). |
| D-number, R-number | Une décision de `docs/DECISIONS.md` (D-202 et suivantes à venir) ; un écart connu de `docs/QA.md` §12. |
| Vellum-Test | Une copie privée du jeu, dans un univers séparé, où l'on peut tout casser sans toucher aux vrais joueurs. |

## 3. Les 20 sessions jusqu'à la v2.1.0

Une session vaut à peu près une journée de travail de Claude ; tes tâches se font en parallèle. L'ordre respecte toutes les dépendances : aucune story ne passe avant celles dont elle dépend.

| # | Session | Stories | Ce que tu obtiens à la fin |
|---|---|---|---|
| 1 | Trancher et préparer | E1-S3, E1-S1, E1-S4, E2-S4, E2-S5 | Chaque choix qui bloque le code a son D-number (D-202 et suivants), le questionnaire de maturité est envoyé, le propriétaire de l'expérience est fixé. Côté code, les types Roblox sont épinglés à luau-lsp 1.69.0 et PUBLISH.md et QA.md citent des fonctions au lieu de numéros de ligne périmés, chaque règle tenue par un spec prouvé par mutation. |
| 2 | Relire le serveur là où l'argent et les données se jouent | E2-S1, E5-S1, E6-S1 | Les 40 fichiers de src/server de la PR #2 sont relus en trois tranches par /code-review au niveau high ; chaque constat critique ou haut confirmé est corrigé avec son test, le reste est en tickets. Pendant ce temps, tu crées Vellum-Test (Limited > Playtesters) et sa clé, et tu actives le New Device Simulator et le MCP de Studio. |
| 3 | Fusionner, protéger main, séparer test et production | E2-S8, E2-S2, E2-S7, E5-S2 | Après ton accord, la PR #2 est fusionnée (0 commit d'avance), la CI est verte sur main, le tag pre-device-qa est posé et main exige la CI. MonetizationConfig a une table d'ids par univers, publish.yml publie vers test ou prod par deux environnements GitHub (prod attend ton approbation), et Studio n'écrit plus jamais dans les vraies données. |
| 4 | Plus un Robux perdu | E3-S1, E3-S2, E3-S3, E3-S7, E3-S8 | R1, R2, R11, R12 et R14 sont fermés dans QA §12, chacun avec un test nommé et prouvé par mutation : le VIP a son tag dans le chat (capture à deux clients), TierSkip ne boucle plus, un Premium reçu deux fois est compensé, un cosmétique raté rend ses Folios, et deux ids identiques font échouer la CI. |
| 5 | Des promesses tenues, et les produits créés | E3-S9, E3-S6, E3-S5, E3-S4, E20-S1 | R6, R8 et R10 sont fermés : les textes de vente disent ce que le code donne, une panne de DataStore suspend les achats Robux et prévient les joueurs, le compte développeur joue le classé à armes égales. En fin de journée, tu crées les 4 passes et 10 produits dans les deux univers, le démarrage affiche 0 missing ids, et le groupe et le Discord existent. |
| 6 | Le classé ne ment plus au redémarrage | E4-S1, E4-S2, E4-S5 | R3, R4, R13 et R15 sont fermés : un redémarrage annule le match sans toucher l'Elo, quitter un duel ou faire planter son serveur compte comme une défaite au chargement suivant, et les temps de recharge repartent à zéro à chaque manche. La migration de profil monte d'une version, aller-retour vert. |
| 7 | Le classé ne se farme plus | E4-S3, E4-S4, E4-S8 | La boucle compte principal + alt jouée 20 fois ne rapporte plus d'Elo et reste sous le plafond de Folios, alors qu'une série honnête de revanches garde tout son Elo. Un serveur privé acheté est non classé, un serveur réservé reste classé. Un gel réseau de 8 s ne coûte plus de frappe Origin. |
| 8 | Un combat juste | E4-S10, E4-S12, E4-S6 | Les étourdissements sont datés et respectés, la grâce décidée empêche les enchaînements sans fin (spec Empattement, Rupture, Filigrane), tomber de l'arène de l'Effacement ramène au hub au lieu de tomber dans un duel, et les corps ne se projettent plus entre eux si tu l'as choisi. |
| 9 | Le jeu tourne dans le vrai moteur | E6-S2, E6-S4 | Le test de fumée à 1 serveur et 2 clients passe sur main (10 écrans ouverts, un 1v1 joué jusqu'au bout) et échoue quand on réintroduit SafeZoneOffsetsChanged. QA.md commence par le registre de tout ce que Lune ne peut pas voir, avec un outil et un responsable par ligne. |
| 10 | La sauvegarde sur un vrai DataStore | E5-S3 | L'essai Luau Execution est fait en premier ; s'il passe, l'aller-retour de profil par saveNow, le vol de session, la double écriture de classement et un reçu factice tournent sur Vellum-Test depuis un job CI manuel, et une première spec Jest-Lua exécute ApplyDamage dans le moteur. C'est la première fois que la sauvegarde tourne pour de vrai. |
| 11 | Chaque Folio et chaque glyphe comptés | E8-S2, E8-S1, E8-S4, E8-S7 | Un spec prouve que chaque Folio gagné ou dépensé produit un seul événement valide, que les champs personnalisés sont ceux que Roblox lit, que les événements de match, de file et de boss existent, et que l'équilibre des 28 glyphes se lit en 2 événements, sous les plafonds de Roblox. |
| 12 | Entonnoir, journaux lisibles, streaming | E8-S3, E8-S5, E6-S7 | L'entonnoir d'accueil en 8 étapes est figé, les journaux n'ont plus de nom de joueur et restent sous 50 avertissements uniques par jour, les règles de l'Error Report sont prêtes à coller, et StreamingEnabled est épinglé avec des téléportations pré-streamées. Tu joues Vellum-Test avec un compte neuf ; le lendemain, l'entonnoir apparaît dans le Dashboard. |
| 13 | Labo : Faussaires, garde de mouvement, modération | E7-S2, E7-S6, E7-S1 | Le signal des Faussaires a ses planches en deux tours (PROGRESS:373 fermé), les 12 vérifications du garde sont vues avec deux clients et MovementAudit coûte moins de 0,5 ms, et les 91 assets sont approuvés. |
| 14 | Server Authority à l'essai, puis l'arène fermée | E4-S11, E4-S7 | L'essai borné de Server Authority sur une copie dit « adopter maintenant », « plus tard » ou « non » ; selon la réponse, soit QA §11 étape 7 est rejetée par le moteur, soit l'enveloppe d'arène renvoie les voleurs et les noclips avec 0 faux positif sur 331 scénarios. Le garde a un mode par zone. |
| 15 | Labo des cosmétiques vendus, tableau de bord | E7-S4, E8-S6 | Les 18 objets vendus sont vus depuis la caméra de jeu en Élevé et en Performance, six auras sur un corps comprises. ECONOMY.md nomme les vues du Dashboard à lire à J1, J7 et J30, et tu as une capture de chacune sur Vellum-Test. |
| 16 | Labo des 11 chronologies du second roster | E7-S3 | Les 11 glyphes ont planches, deuxième tour, stress à 6 lancers et lecture au niveau Performance ; ou, si tu l'as décidé, ils sont verrouillés pour la sortie et reviennent en P1. |
| 17 | Le jeu sur chaque écran | E6-S3, E6-S6, E7-S5 | Les planches des 7 profils d'écran sont dans docs/devices/, chaque élément de STUDIO_SETUP §11 est vu ou corrigé, un téléphone modeste démarre en qualité moyenne, et le skill vellum-device-qa rend tout cela rejouable. |
| 18 | De vrais humains, de vrais téléphones, de vrais sons | E20-S2, E5-S4, E6-S5, E20-S3 | Le playtest à 6-10 testeurs couvre le World Boss, les portails, l'anti-triche et un 3v3 ; la passe à deux comptes couvre QA §0-§5, §7 et §10 avec de vrais achats sur Vellum-Test ; les deux téléphones sont mesurés contre la cible de 30 images/s ; les 55 sons sont écoutés et réglés. |
| 19 | Effacement, fiche du jeu, porte de sortie | E20-S4, E1-S2, E2-S3 | Une demande d'effacement se traite en une commande testée sur Vellum-Test, la page du jeu a son icône, ses vignettes et ses textes EN/FR, et release-check refuse toute publication incomplète, chaque règle prouvée par mutation. |
| 20 | Publier la v2.1.0 | E2-S6 | Le tag v2.1.0 passe release-check, part d'abord sur Vellum-Test, puis sur Vellum avec ton approbation ; tous les serveurs sont migrés et la passe courte QA §13 est notée. Ensuite commence la P1 : E9 (interrupteurs en direct, support), E10 et E16 (personne n'attend seul, combat sans file), E14 (premières minutes). |

## 4. Les épopées et leurs stories

### P0 — Avant la publication (bloque la v2.1.0)

9 épopées, 60 stories, dans l'ordre où les faire.

#### E1 — Fiche du jeu, conformité et décisions du développeur

*But : Faire ce que seul ton compte Roblox peut faire avant la sortie, et trancher par écrit les choix de jeu que Claude ne doit pas faire à ta place.*

**E1-S1 — Remplir le questionnaire de maturité et de conformité**  
Responsable : toi · Effort : S · Dépend de : rien

- Creator Dashboard > l'expérience > Configure > Questionnaire : le questionnaire est envoyé ; le libellé obtenu (Minimal ou Mild attendu) est noté avec la date dans docs/PUBLISH.md §6.1, capture rangée dans docs/publish/.
- Les réponses décrivent ce que le jeu montre : combat fantastique, violence légère, aucun sang réaliste, chat texte Roblox activé, aucun autre texte saisi par les joueurs (PUBLISH.md §6.1 et §6.7).
- PUBLISH.md §6.1 dit de renvoyer le questionnaire à chaque changement de contenu : sans lui, Roblox restreint la jouabilité de l'expérience pour tous les joueurs (page content-maturity, lue le 30/09/2026).

**E1-S2 — Fiche du jeu : icône, vignettes, nom et description en anglais et en français**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3, E1-S4, E3-S1

- Claude rédige nom et description EN/FR qui ne promettent que ce qui existe (aucun mode non livré, aucun tag VIP avant E3-S1) et produit depuis Studio au moins 6 captures 16:9 (un glyphe, un duel, l'Effacement, le hub, les portails, le Champ de bataille) rangées dans docs/store/.
- La personne qui dessine l'icône est celle choisie en E1-S3 ; 3 propositions d'icône 512×512 sont posées à côté des icônes de 3 battlegrounds du genre sur une même planche, et ton choix est écrit dans PUBLISH.md §6.3.
- Tu téléverses l'icône et au moins 3 vignettes ; la page de Vellum-Test puis celle de Vellum les affichent en anglais et en français, sans image cassée ; les textes validés sont copiés dans PUBLISH.md §6.3-6.4.

**E1-S3 — Séance de décisions (une à deux heures), écrite dans DECISIONS.md**  
Responsable : Claude et toi · Effort : M · Dépend de : rien

- Argent et comptes : une entrée D-202 et suivantes, raison en deux lignes, pour : propriétaire de l'expérience (compte 3721321390 ou groupe) ; dépôt GitHub public (il l'est : gh repo view) ou privé ; drapeaux développeur en classé et sort du profil développeur (R6, PUBLISH §4.3-4.4) ; option TierSkip (refus dès le palier 46, ou texte « jusqu'à 5 ») ; prompts contextuels R8 branchés ou retirés ; promesse Premium R10 (changer le code ou la doc) ; politique quand Roblox rembourse un achat ; qui dessine l'icône.
- Classé et triche : serveurs privés gratuits, payants ou fermés ; âge de compte minimum ; seuil N de matchs classés par paire et par jour (E4-S3) ; direction anti-triche (enveloppe d'arène, essai de Server Authority, ou les deux dans cet ordre) ; corps de joueurs qui se traversent ; mode du garde par zone ; réapparition après Humanoid supprimé (D-139).
- Combat : grâce d'étourdissement (PROGRESS:395) ; retour au hub plutôt que la mort en tombant de l'arène de l'Effacement (K2, D-138) ; recharge accélérée promise pour la Cartouche (D-140) ; sortir sans les 11 glyphes du second roster si leur labo n'est pas fini à temps.
- Lancement : file inter-serveurs par MemoryStore (PROGRESS:32) ou regroupement des joueurs par le matchmaking Roblox (E10) ; où vont les compteurs d'exploitation (Error Report seul, RoSentry, ou Supabase via HttpService et un secret Roblox) ; console cochée ou non ; traduction automatique et langues suivantes.
- Claude prépare chaque question avec 2 ou 3 options, leur coût et sa recommandation ; tu tranches ; chaque story qui en dépend cite le numéro D dans son commit.

**E1-S4 — Choisir le propriétaire de l'expérience et l'appliquer**  
Responsable : Claude et toi · Effort : S · Dépend de : E1-S3

- La décision de E1-S3 est appliquée avant toute création de passe ou de produit (E3-S4), avant la fiche (E1-S2) et avant le groupe communautaire (E20-S1).
- Si c'est ton compte : PUBLISH.md §5.2 est coché (l'expérience et les 91 assets appartiennent au compte 3721321390, assets/roblox-assets.lock.json:2-3).
- Si c'est un groupe : le groupe existe, les 91 assets sont renvoyés à son nom par scripts/upload_assets.py avec ton accord explicite, le lock est commité, tests/UploadedAssets.spec.luau est vert et python3 scripts/upload_assets.py status montre 91 Approved.

#### E2 — Une version publiable

*But : Avoir un main relu là où l'argent et les données se jouent, étiqueté, protégé, séparé entre test et production, et une porte automatique qui refuse toute publication incomplète.*

**E2-S1 — Relecture ciblée et bornée du serveur de la PR #2**  
Responsable : Claude et toi · Effort : L · Dépend de : rien

- Périmètre écrit en tête du rapport : les 40 fichiers de src/server modifiés par la PR #2 (git diff --name-only origin/main...feat/vfx-pass -- src/server), en trois tranches : argent et données (MonetizationService, DataService, CurrencyService, ShopService, RankingService, LeaderboardService, MatchService), sécurité (Security/, AntiCheatService, MovementService, RemoteRegistry), puis le reste.
- Chaque tranche passe par /code-review au niveau high ; seuls les constats confirmés de gravité critique ou haute (perte de données ou d'argent, triche, plantage) sont corrigés ici, chacun dans un commit atomique avec son test, les cinq portes vertes ; les autres deviennent des tickets du suivi (voir Outils).
- Durée bornée à deux sessions : ce qui n'est pas relu à la fin devient un ticket, pas un retard de fusion.

**E2-S8 — Fusionner la PR #2**  
Responsable : Claude et toi · Effort : S · Dépend de : E2-S1

- Tu valides la fusion ; après, git rev-list --count origin/main..feat/vfx-pass donne 0 (266 aujourd'hui) et gh pr view 2 --json state donne MERGED.
- gh run list --branch main --limit 1 montre la CI verte sur le commit de fusion.
- Le reste de la PR (src/ui, src/client, src/shared, tests, docs) est relu après la fusion, en E12-S6.

**E2-S2 — Poser un repère et protéger main**  
Responsable : Claude et toi · Effort : S · Dépend de : E2-S8

- Le tag pre-device-qa pointe sur le commit de fusion et apparaît dans git ls-remote --tags origin.
- gh api repos/FouziGit/robloxtest/branches/main/protection ne répond plus « Branch not protected » (réponse du 30/09/2026) et exige le check CI ; réglage posé par Claude avec ton accord, gratuit tant que le dépôt est public (à revoir si E1-S3 le rend privé).
- CLAUDE.md §Git dit : une branche courte par lot, jamais plus de 30 commits ou 3 jours d'avance sur main.

**E2-S7 — Deux univers, deux jeux d'ids, deux environnements de publication**  
Responsable : Claude et toi · Effort : M · Dépend de : E5-S1, E1-S3

- MonetizationConfig range les ids par univers (clé game.GameId) : une table Test (Vellum-Test) et une table Prod ; un GameId inconnu refuse tous les achats avec un seul warn (spec Lune). Raison : Roblox a coupé la vente d'un produit d'un autre jeu le 30/05/2026 (page developer-products, lue le 30/09/2026), donc Vellum-Test a besoin de ses propres produits.
- Deux GitHub Environments, test et prod, apparaissent dans gh api repos/FouziGit/robloxtest/environments, chacun avec ses secrets ROBLOX_API_KEY, UNIVERSE_ID et PLACE_ID ; prod exige ton approbation et n'accepte que les tags v*.
- publish.yml prend la cible (test ou prod) en entrée et utilise l'environnement correspondant ; un lancement vers prod depuis une branche est refusé par GitHub (essai noté dans PUBLISH.md §8).

**E2-S3 — Porte de sortie automatique : scripts/release-check**  
Responsable : Claude · Effort : M · Dépend de : E3-S3, E2-S7

- lune run scripts/release-check échoue si : un id de la table Prod manque ou se répète ; un drapeau de DeveloperConfig est vrai sans fichier d'autorisation qui cite son D-number ; GameConfig.Version diffère du tag de la réf (sans le v) ou égale le tag v* précédent ; la réf n'est pas un tag v* atteignable depuis origin/main ; le lock d'assets contient un état autre que Approved ; le mode du garde n'est pas celui décidé pour la sortie.
- Chaque règle est prouvée par mutation dans tests/ReleaseCheck.spec.luau (défaut réintroduit, échec vu, défaut retiré).
- publish.yml lance ./scripts/check.sh puis release-check avant l'envoi ; un lancement sur une branche non taguée échoue à la porte ; PUBLISH.md §1.4 décrit ce que la porte vérifie désormais.

**E2-S4 — Épingler les définitions de types Roblox à la version de luau-lsp**  
Responsable : Claude · Effort : S · Dépend de : rien

- .github/workflows/ci.yml:29 et scripts/setup.sh téléchargent globalTypes.d.luau depuis le tag 1.69.0 de luau-lsp (rokit.toml:9) au lieu de la branche main ; l'adresse répond 200 à curl -fsSI.
- Un spec lit la version dans rokit.toml et dans les deux URL et échoue si elles divergent (prouvé en changeant l'une des trois).

**E2-S5 — PUBLISH.md et QA.md citent des noms de fonction, plus des numéros de ligne périmés**  
Responsable : Claude · Effort : S · Dépend de : rien

- Toute référence fichier.luau:NNN de PUBLISH.md et QA.md est accompagnée du nom de la fonction ou de la constante visée.
- tests/DocRefs.spec.luau refuse une référence par numéro de ligne nu dans ces deux docs, prouvé par mutation.
- Les mentions périmées disparaissent : « 12 commits d'avance » (PUBLISH §1.1) et « au commit c0b6687 » dans le titre de QA §12.

**E2-S6 — Publier la v2.1.0**  
Responsable : Claude et toi · Effort : S · Dépend de : toutes les autres stories P0 (59)

- GameConfig.Version vaut 2.1.0, le tag v2.1.0 est sur origin/main et release-check est vert sur ce tag.
- publish.yml vers test en Saved : la place ouverte affiche [Bootstrap] Vellum v2.1.0 ready et 0 missing ids ; puis vers prod en Published, avec ton approbation dans GitHub.
- Tous les serveurs passent à la nouvelle version (Restart servers for updates, PUBLISH §8.5), puis la passe courte QA §13 est faite et notée dans docs/qa/.

#### E3 — Des achats justes

*But : Chaque Robux dépensé livre exactement ce qui est promis, même pendant une panne de DataStore, et aucun texte ne promet ce que le code ne donne pas.*

**E3-S1 — Poser le tag VIP dans le chat (R1)**  
Responsable : Claude et toi · Effort : S · Dépend de : rien

- Le serveur pose un attribut répliqué Vip sur le Player depuis Passes ; un handler client TextChatService.OnIncomingMessage ajoute le tag coloré du Theme, libellé par Strings.t en EN et FR.
- La fonction pure qui construit le préfixe est testée sous Lune ; retirer le branchement du handler fait échouer un spec (mutation).
- Dans Studio à deux clients, le tag n'apparaît que pour l'expéditeur VIP (capture dans docs/qa/) ; R1 est fermé dans QA §12 ; Strings, STUDIO_SETUP, ECONOMY et la description du pass que tu recopies dans le Dashboard disent la même chose.

**E3-S2 — Un TierSkip ne boucle plus jamais (R2, R14)**  
Responsable : Claude · Effort : S · Dépend de : E1-S3

- L'option choisie en E1-S3 est appliquée (recommandation : refuser la fenêtre d'achat dès le palier 46 et garder « cinq paliers » dans le texte).
- Test Lune : deux reçus TierSkip5 au palier 49 donnent PurchaseGranted deux fois, avec 1 palier puis une compensation en Folios (constante TierSkipCompensationFolios dans MonetizationConfig) et une notification EN/FR.
- Remettre le return false de Receipts fait échouer le test (mutation) ; R2 et R14 sont fermés dans QA §12 ; PUBLISH §3.5 ne demande plus de retirer TierSkip5.

**E3-S3 — Test d'unicité des ids, par univers**  
Responsable : Claude · Effort : S · Dépend de : E2-S7

- Config.spec échoue si deux ids non nuls se répètent entre Passes et Products d'une même table d'univers, ou si le Kind d'un produit ne correspond pas à sa clé.
- Dupliquer un id à la main fait échouer le test (mutation).

**E3-S4 — Créer les 4 passes et les 10 produits dans les deux univers, puis donner les ids**  
Responsable : toi · Effort : M · Dépend de : E1-S4, E2-S7, E3-S1, E3-S2, E3-S3, E3-S7, E3-S9

- Dans Vellum-Test puis dans Vellum : 4 passes et 10 produits, noms et prix de PUBLISH.md §3.2.
- Tu donnes à Claude la liste « clé = id » par univers ; Claude la colle ; au démarrage de chaque univers : [MonetizationService] started (4 passes, 10 products, 0 missing ids).
- Chaque id est comparé à la main au Dashboard et coché dans PUBLISH §3.2 ; le test d'unicité est vert.

**E3-S5 — Le compte développeur joue le classé avec le loadout acheté (R6)**  
Responsable : Claude et toi · Effort : S · Dépend de : E1-S3

- Test Lune : en file ou en match classé, le compte développeur est limité aux emplacements achetés ; UnlimitedSlots ne s'applique qu'au hub.
- Le commentaire DeveloperConfig.luau:24-25 dit ce que fait le code ; R6 est fermé ; la décision E1-S3 est citée.
- Le sort du profil développeur (cosmétiques obtenus avec les Folios illimités, passes de test en cache : PUBLISH §4.3) est appliqué comme décidé.

**E3-S6 — Une panne de DataStore devient visible et suspend les achats Robux**  
Responsable : Claude · Effort : S · Dépend de : rien

- Spec Lune avec un ProfileStore factice : OnCriticalToggle(true) envoie une seule fois « sauvegarde retardée » (EN/FR) à chaque joueur et PromptPurchase refuse les achats Robux ; BuyCosmetic reste permis ; OnCriticalToggle(false) rétablit et prévient.
- OnError produit un warn avec le magasin et la clé ; OnOverwrite produit une erreur ; chaque branche prouvée par mutation.

**E3-S7 — Un PremiumPass reçu deux fois est compensé (R11)**  
Responsable : Claude · Effort : S · Dépend de : rien

- Test Lune : un reçu PremiumPass pour un joueur déjà Premium donne une compensation en Folios (constante dans MonetizationConfig) et une notification EN/FR, puis PurchaseGranted ; aujourd'hui il ne donne rien (Receipts.luau:132-139, branche PremiumPass de grantProduct).
- Retirer la compensation fait échouer le test (mutation) ; R11 est fermé dans QA §12.

**E3-S8 — Des Folios rendus si l'attribution d'un cosmétique échoue (R12)**  
Responsable : Claude · Effort : S · Dépend de : rien

- Si cosmetic.grant échoue après currency.trySpend dans l'achat en Folios de ShopService (ShopService.luau:308-313), le prix exact est rendu sans multiplicateur VIP, une ligne log.error nomme l'article, et le joueur lit « achat annulé, Folios rendus » en EN et FR.
- Spec Lune avec un CosmeticService qui échoue : solde final égal au solde initial ; mutation prouvée ; R12 est fermé.

**E3-S9 — Ce que la boutique promet est ce que le code donne (R8, R10)**  
Responsable : Claude et toi · Effort : S · Dépend de : E1-S3

- R8, selon E1-S3 : soit MonetizationService.maybePrompt a un appelant par ligne de ECONOMY.md §5, avec les règles « jamais dans les 3 premières minutes, au plus un toutes les 5 min, jamais en match » tenues par des specs ; soit maybePrompt, CloseLossHealthFraction et ces lignes de ECONOMY §5 sont retirés (grep ne trouve plus maybePrompt dans src).
- R10 : ECONOMY.md:102 et DailyRewardService disent la même chose du bonus Premium, et ce bonus suit PlayerMembershipChanged (un joueur qui devient Premium en jeu le reçoit sans rejoindre, spec Lune).
- Chaque ligne du tableau PUBLISH.md §11 est vraie ou retirée ; R8 et R10 sont fermés dans QA §12.

#### E4 — Un classé honnête

*But : L'Elo (la note de niveau du classé), les classements et leurs récompenses ne se gagnent qu'en jouant : pas de débit injuste au redémarrage, pas de farm à deux comptes, pas d'étourdissement sans fin, pas de victoire en volant.*

**E4-S1 — Arrêt du serveur : le match classé est annulé, le message est neutre (R3, R15)**  
Responsable : Claude · Effort : M · Dépend de : rien

- DataService.isClosing() est vrai dès le premier BindToClose.
- Tests Lune avec un ProfileStore factice pour les deux ordres (PlayerRemoving avant et après la libération du profil) : aucun Elo ne bouge, une clé « serveur qui redémarre » remplace kick.sessionElsewhere, un événement MatchVoided est journalisé ; chaque test prouvé par mutation.
- R3 et R15 sont fermés ; PUBLISH §8.4 n'impose plus les heures creuses pour cette raison.

**E4-S2 — Mise en jeu au début du match : quitter ne sauve plus d'une défaite (R4)**  
Responsable : Claude · Effort : M · Dépend de : E4-S1

- MatchService écrit Rank.Pending au début d'un match classé ; applyResult l'efface.
- Tests Lune : vol de session → défaite ; crash sans libération → défaite au chargement suivant ; arrêt propre (Void) → aucun changement.
- DataMigration.CurrentVersion augmente et l'aller-retour de migration est vert ; R4 est fermé.

**E4-S3 — Fin du farm à deux comptes, sans punir les revanches honnêtes**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3

- Un forfait avant MatchConfig.MinPlayedSeconds (proposition 30 s) ou sans aucun dégât échangé devient Void : le quitteur est débité, le survivant n'a ni Elo ni quête MatchWin.
- Au-delà de N matchs classés de la même paire de UserId dans la journée UTC (N choisi en E1-S3, proposition 5), l'Elo de la paire ne bouge plus et ses Folios passent à ×0,25 ; un plafond quotidien de Folios de match existe, sur le modèle de BotConfig.Credit.DailyFolioCap.
- Spec Lune qui joue 20 fois la boucle « compte principal + alt, l'alt part au compte à rebours » : 0 Elo gagné, Folios au plus égaux au plafond ; une série honnête de 5 revanches par Rejouer avec des dégâts échangés garde tout son Elo.
- Âge de compte minimum appliqué si E1-S3 l'a choisi (Player.AccountAge, spec) ; entrée D et docs/ECONOMY.md mis à jour.

**E4-S4 — Classé désactivé dans les serveurs privés achetés**  
Responsable : Claude · Effort : S · Dépend de : E1-S3

- Un serveur privé acheté (game.PrivateServerOwnerId ~= 0) joue en non classé : aucune écriture d'Elo ni de classement S1_*, récompenses réduites ; un serveur réservé (PrivateServerId non vide et PrivateServerOwnerId == 0, pour une future file inter-serveurs) reste classé. Règle tirée de l'exemple de la page DataModel (lue le 30/09/2026).
- Tests Lune pour les trois cas : public, privé acheté, réservé.
- La file affiche « Non classé en serveur privé » en EN et FR.

**E4-S5 — Les temps de recharge repartent à zéro à chaque manche (R13)**  
Responsable : Claude · Effort : S · Dépend de : rien

- GlyphService expose une remise à zéro appelée par MatchService à la préparation de chaque manche et à l'entrée en match.
- Test Lune : un glyphe lancé à la fin de la manche 1 est prêt au début de la manche 2 ; retirer l'appel fait échouer le test.
- R13 est fermé, QA §7.2 est mis à jour.

**E4-S6 — Les corps des joueurs ne se poussent plus : fin du fling**  
Responsable : Claude et toi · Effort : S · Dépend de : E1-S3

- Un groupe de collision Characters, non collidable avec lui-même, est posé sur chaque BasePart au CharacterAdded et au DescendantAdded ; un spec le vérifie ; Faussaires et Effacement restent en Default.
- Les scénarios de contact de movementsim sont mis à jour ; dans Studio à deux clients (StudioTestService), deux joueurs se traversent et un finisher projette toujours ; l'étape est ajoutée à QA §7.
- Décision D citée (le ressenti est ton choix en E1-S3).

**E4-S7 — L'arène fermée aux tricheurs de mouvement avant d'ouvrir les classements**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3, E4-S11, E7-S6

- La direction décidée après l'essai E4-S11 est appliquée : si Server Authority est adopté pour la sortie, cette story se réduit à rejouer QA §11 étape 7 ; sinon l'enveloppe d'arène est construite.
- Enveloppe : dans movementsim, un corps au-dessus du plafond de l'arène pendant 1,5 s est renvoyé à son pad, un noclip dans un couvert est renvoyé, et les 331 scénarios honnêtes donnent 0 renvoi.
- MovementGuardConfig passe d'un seul Mode (MovementGuardConfig.luau:18) à ModeByZone {Hub, Arena, Battleground, Boss}, tenu par Config.spec ; LiveConfig (E9-S1) reprend exactement cette forme ; l'arène ne passe en Correct qu'après E7-S6.
- PUBLISH.md reçoit la ligne : classements et récompenses de saison ouverts seulement si l'enveloppe, Correct en arène ou Server Authority est actif.

**E4-S8 — Les vérifications d'origine des boucles serveur ne frappent plus les joueurs honnêtes**  
Responsable : Claude · Effort : S · Dépend de : rien

- Une nouvelle fonction CombatService.currentOrigin (même position, sans violation comptée) sert à la charge, au Roussi (Scorch), à Stitch et à Hatching ; CombatService.trustedOrigin (CombatService.luau:692) reste pour le lancer et la mêlée.
- Spec : un canal Scorch traversé par un gel réseau de 1,2 à 8 s donne 0 frappe Origin ; une origine truquée au lancer frappe toujours ; mutation prouvée.

**E4-S10 — Un étourdissement juste : pas d'enchaînement sans fin, respecté par le serveur**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3

- MovementService date chaque étourdissement (début et fin) et MovementService.clearStun envoie une fin que le client applique (aujourd'hui Seconds = 0, que le client ignore : D-139) ; spec du message.
- Si E1-S3 retient la grâce d'étourdissement : un étourdissement de glyphe ne prolonge jamais celui qui court et ne tombe pas dans la demi-seconde qui suit sa fin ; un spec enchaîne Empattement, Rupture et Filigrane sur une même cible et mesure l'étourdissement continu maximal, sous la valeur décidée.
- MovementAudit journalise un corps qui marche pendant un étourdissement daté (spec, mode Observe) ; une entrée D remplace la ligne « respect de l'étourdissement » de D-139.

**E4-S11 — Essai borné de Server Authority sur une copie de la place**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3, E6-S2, E5-S1

- Durée bornée à deux sessions, sur une branche et une copie de la place dans Vellum-Test, jamais sur la place publique.
- Workspace.AuthorityMode = Server (ce mode règle aussi StreamingEnabled : annonce du 09/07/2026, lue le 30/09/2026) ; un rapport liste ce qui casse : dash, projection, étourdissement, ragdoll, gestes (les emotes personnalisées ne sont pas prises en charge), plus de 8 pistes d'animation.
- QA §11 étape 7 (CFrame += 60 vers le haut) est rejouée et son résultat noté ; un duel à deux clients est joué ; une entrée D dit « adopter pour la sortie », « adopter plus tard (E13-S3) » ou « non ».

**E4-S12 — Tomber de l'arène de l'Effacement ramène au hub (K2)**  
Responsable : Claude · Effort : S · Dépend de : E1-S3

- Selon ton accord en E1-S3 (D-138 l'attend) : un joueur dont la racine passe sous le plan de l'arène de l'Effacement est ramené au hub, jamais tué et jamais posé dans un duel plus bas.
- Spec : un corps qui tombe de l'arène du boss n'atteint aucun pad ni plan de match (tests/MovementGates.spec.luau) ; mutation prouvée ; la ligne K2 de PROGRESS:384 passe en « fait ».

#### E5 — Des données sûres, testées sur un vrai DataStore

*But : Avant le premier joueur, la sauvegarde, les reçus et les classements ont tourné pour de vrai, sans jamais toucher aux données de production.*

**E5-S1 — Créer l'univers privé Vellum-Test et sa clé Open Cloud**  
Responsable : toi · Effort : S · Dépend de : rien

- Un univers Vellum-Test publie la même place ; Configure > Settings > Audience est réglé sur Limited > Playtesters (page publish-experiences-and-places, lue le 30/09/2026), donc invisible du public ; l'accès aux API n'est activé que sur lui.
- Une clé Open Cloud limitée à Vellum-Test, avec les droits universe.place.luau-execution-session:write et publication de places, est rangée par toi dans .env.local ; git check-ignore -v .env.local la montre ignorée (.gitignore:35) ; la clé ne passe jamais par le chat.
- STUDIO_SETUP §2 dit sur quel univers activer l'accès aux API, ce qui met fin à la contradiction avec PUBLISH §4.1.

**E5-S2 — Studio n'écrit plus dans les vraies données (R5, R9)**  
Responsable : Claude · Effort : S · Dépend de : rien

- Dans Studio, DataService ouvre ProfileStore.Mock sauf drapeau serveur explicite, et une ligne de log dit lequel.
- LeaderboardService ignore tout UserId ≤ 0 ; tests Lune pour les deux règles, prouvés par mutation.
- Un test Studio à plusieurs clients laisse les classements S1_* intacts ; R5 et R9 sont fermés ; STUDIO_SETUP.md:32 ne contredit plus PUBLISH §4.1.

**E5-S3 — Le chemin de l'argent testé dans le vrai moteur (Luau Execution)**  
Responsable : Claude et toi · Effort : L · Dépend de : E5-S1, E2-S7

- Essai d'abord, une demi-journée : une tâche Luau Execution sur Vellum-Test requiert elle-même DataService et ProfileStore (dans une tâche, les scripts de la place ne se lancent pas et la physique ne tourne pas : page luau-execution, lue le 30/09/2026) et fait un aller-retour de profil ; si l'essai échoue, une entrée D dit pourquoi et la story s'arrête là.
- scripts/cloud_check.py construit, publie sur Vellum-Test et lance des tâches qui : (a) font un aller-retour de profil par DataMigration avec la confirmation de saveNow ; (b) ouvrent deux sessions par deux tâches simultanées (10 permises par place) et observent le vol ; (c) écrivent deux fois une clé d'OrderedDataStore en moins de 6 s ; (d) passent un reçu factice par ReceiptProcessor.
- Au moins une spec Jest-Lua sous tests/engine-specs/ construit ses propres personnages, puis exécute ApplyDamage et une fin de manche de MatchService.
- Un job CI manuel, dans l'environnement test, est vert ; un échec bloque PUBLISH §1.

**E5-S4 — Passe QA à deux comptes sur Vellum-Test publié**  
Responsable : toi · Effort : M · Dépend de : E5-S1, E5-S2, E3-S4

- Avec ton compte et un compte secondaire, sur Vellum-Test publié : QA §0 à §5, §7 et §10, dont un vrai achat de chaque passe et de chaque produit de la table Test (QA §3).
- Un rapport daté docs/qa/<date>-deux-comptes.md donne OK ou KO par étape, avec une capture ou une ligne de log ; chaque KO est ouvert en R16 et suivants dans QA §12.
- En tête de QA.md, un tableau affecte chaque section : §6, §6 bis et §11 au playtest (E20-S2), §8 et §9 aux téléphones (E6-S5), §13 après publication (E2-S6).

#### E6 — Le jeu vu dans le vrai moteur et sur téléphone

*But : Qu'un démarrage cassé, un HUD qui couvre les pouces ou un téléphone à 8 images/s soient vus par nous, pas par les joueurs.*

**E6-S1 — Activer le New Device Simulator et le MCP de Studio**  
Responsable : toi · Effort : S · Dépend de : rien

- Studio : File > Beta Features > New Device Simulator est coché et Studio redémarré.
- Studio : Assistant > … > Manage MCP Servers > Enable Studio as MCP server est activé (page studio/mcp, lue le 30/09/2026).
- Depuis execute_luau du MCP, StudioDeviceSimulatorService:GetDeviceListAsync() renvoie une liste (méthodes en Plugin Security d'après la référence lue le 30/09/2026) ; sortie rangée dans docs/devices/.

**E6-S2 — Test de fumée automatique dans le moteur**  
Responsable : Claude et toi · Effort : M · Dépend de : E6-S1

- tools/smoke/smoke.luau démarre 1 serveur et 2 clients par StudioTestService (8 clients au plus) : toutes les lignes « [X] started » attendues en 20 s sur les deux clients, aucune ligne warn ou error venant d'un contrôleur ou d'un écran.
- VirtualInput ouvre et ferme les 10 écrans ; les deux clients jouent un 1v1 jusqu'à MatchEnded ; un résumé PASS/FAIL s'affiche.
- Remettre SafeZoneOffsetsChanged dans ScreenRoot le fait échouer (mutation) ; scripts/check.sh --engine le lance quand Studio est ouvert.

**E6-S3 — Labo d'appareils scripté et skill vellum-device-qa**  
Responsable : Claude et toi · Effort : L · Dépend de : E6-S1, E6-S2

- tools/devicelab/capture.luau produit des planches dans docs/devices/<profil>/ pour 844×390 et 667×375 à 0,68, iPad 1180×820, 1080p, 1440p, et fr-fr sur les deux téléphones : HUD du hub, HUD de combat, toasts, 10 écrans, chaque onglet de la Boutique ; billboards capturés depuis la fenêtre.
- Chaque élément 1-25 et A-H de STUDIO_SETUP §11 est marqué vu ou KO ; les KO qui empêchent de lire un texte ou de faire une action sont corrigés ici sous leur D-number, les autres deviennent des tickets ; durée bornée à trois sessions.
- La recette devient le skill .claude/skills/vellum-device-qa/, écrit avec skill-creator.

**E6-S4 — Registre de ce que Lune ne peut pas voir, en tête de QA.md**  
Responsable : Claude · Effort : S · Dépend de : rien

- Un tableau (élément, pourquoi Lune ne peut pas le voir, outil, responsable, statut, dernier commit vu) liste les comportements jamais observés : billboards, ragdoll, Faussaires, STUDIO_SETUP §10, TouchGui/JumpButton, polices iOS/Android, CanvasGroup, UIStroke sous UIScale.
- Chaque ligne a un outil et un responsable ; le test de fumée journalise si JumpButton a été trouvé ou si le repli a joué.

**E6-S5 — Passe sur un vrai Android d'entrée de gamme et un vrai iPhone**  
Responsable : toi · Effort : L · Dépend de : E5-S1, E6-S3

- Sur Vellum-Test, le protocole de PERFORMANCE.md est joué en Élevé puis en Performance, avec un changement de qualité en plein combat à 6 lancers ; fps p50/p10 et mémoire sont écrits dans PERFORMANCE.md avec le nom des appareils.
- Cible : p10 ≥ 30 images/s au niveau Performance sur l'Android d'entrée de gamme pendant ce combat ; sinon, correction avant la sortie, ou décision écrite de décocher cette classe d'appareil (PUBLISH §6.2).
- QA §8 et §9 sont passées ; les seuils 40/55 de QualityConfig.Auto sont remplacés par des valeurs tirées des mesures.

**E6-S6 — Qualité de départ choisie selon l'appareil**  
Responsable : Claude et toi · Effort : M · Dépend de : rien

- Spec QualityController : un appareil tactile seul de hauteur ≤ 430 démarre en Medium, un SavedQualityLevel bas démarre en Low, le choix du joueur reste le plafond.
- L'émission Driven ne dépasse jamais 2× ce que le moteur dessinerait.
- Vérifié dans Studio que SavedQualityLevel se lit depuis un LocalScript ; sinon il est ajouté à EngineOnlyApi RESERVED.

**E6-S7 — StreamingEnabled décidé, téléportations pré-streamées**  
Responsable : Claude · Effort : M · Dépend de : rien

- Workspace est épinglé dans default.project.json avec des $properties choisies et notées dans DECISIONS ; si E4-S11 adopte Server Authority, StreamingEnabled vaut vrai (ce mode l'impose).
- Un seul helper de téléportation serveur pré-streame ; MatchService, Encounter et HubService l'utilisent (aujourd'hui seul BattlegroundService.enter appelle RequestStreamAroundAsync).
- Un test Lune désérialise build/Vellum.rbxl, vérifie les valeurs et échoue si l'épingle est retirée ; check.sh le lance après le build (l'arrivée de 6 vrais joueurs sur les pads est un critère du playtest E20-S2).

#### E7 — Les portes Studio que le projet s'est fixées

*But : Fermer chaque ligne « Reste, dans Studio avant de publier » de PROGRESS.md avec sa planche ou sa capture, dans l'ordre du risque : Faussaires, garde de mouvement, objets vendus, puis les nouvelles chronologies.*

**E7-S1 — Modération des assets : 91 sur 91 approuvés**  
Responsable : toi · Effort : S · Dépend de : rien

- python3 scripts/upload_assets.py status, lancé par Claude, montre 91 Approved et 0 Reviewing (le 30/09/2026 : 89 Approved, 2 Reviewing, ink_flame.png et ink_spike.png).
- Si un asset est Rejected : tu fais appel depuis le Creator Dashboard, ou Claude le régénère et le renvoie avec ton accord.
- Le lock est commité ; la partie modération de R7 est fermée.

**E7-S2 — Labo du signal des Faussaires (bloquant d'après PROGRESS:373)**  
Responsable : Claude et toi · Effort : M · Dépend de : rien

- Planches avant/après dans docs/vfx/forger-tell/, notes sur les six critères du skill vellum-vfx, au moins deux tours, une entrée D.
- Les vérifications de PROGRESS:373 sont faites : marche et arrêt, chute du corps, poussée d'une projection, poteaux des portiques qui n'accrochent ni joueurs ni boss ; la ligne passe en « fait ».

**E7-S3 — Labo des 11 chronologies du second roster (lots A à C)**  
Responsable : Claude et toi · Effort : L · Dépend de : E7-S2

- docs/vfx/lotA à lotC contiennent planches, notes du deuxième tour, le stress à 6 lancers à 60 fps et la lecture au niveau Performance.
- Les vérifications à deux joueurs de PROGRESS:394 (racine pendant la Chaînette, Paraphe contre un saut, Obèle vers un rebord…) sont faites dans Studio à deux clients (StudioTestService) ; la ligne PROGRESS:394 passe en « fait ».
- Si E1-S3 a choisi de sortir sans ces 11 glyphes faute de temps : ils sont verrouillés par config pour la sortie (spec), et cette story sort du chemin de la v2.1.0 par une entrée D.

**E7-S4 — Labo des 18 cosmétiques vendus (lots D à F)**  
Responsable : Claude et toi · Effort : L · Dépend de : rien

- docs/vfx/lotD à lotF contiennent les planches depuis la caméra de jeu et un corps à six auras en Élevé et en Performance.
- Ce que Lune ne voit pas (Emit après déplacement de l'attache, sceau et flaque au sol, hauteur tirée de HipHeight) est vu ; les lignes PROGRESS:422 et :436 passent en « fait ».

**E7-S5 — Test de fumée UI de dix minutes et hypothèses A à H**  
Responsable : Claude et toi · Effort : M · Dépend de : E6-S2, E6-S3

- Le test de fumée de STUDIO_SETUP §11 est coché avec sa date.
- Les hypothèses A-H et celles de §12.1 (UIStroke sous UIScale, polices, réglages GuiService, CanvasGroup…) ont une réponse dans DECISIONS.md ; les lignes PROGRESS:410 et :413 passent en « fait ».

**E7-S6 — Les 12 vérifications du garde de mouvement (STUDIO_SETUP §10)**  
Responsable : Claude et toi · Effort : M · Dépend de : E6-S2

- Chaque point de STUDIO_SETUP §10 est vu avec StudioTestService à 2 clients et des routes VirtualInput (bords, portails, projections, réapparition, double saut), ou sur une vraie session.
- Le coût de MovementAudit au MicroProfiler est sous 0,5 ms (§10.10).
- La ligne PROGRESS:383 passe en « fait » ; seulement ensuite le passage en Correct est décidé et écrit.

#### E8 — Voir le jeu vivant dès le premier joueur

*But : Les joueurs de la semaine de lancement n'arrivent qu'une fois : chaque indicateur de ECONOMY.md §8 et l'équilibre des 28 glyphes doivent être lisibles dès le jour 1, et une vraie erreur ne doit pas se noyer dans le bruit.*

**E8-S1 — Chaque Folio gagné ou dépensé est journalisé à la source**  
Responsable : Claude · Effort : M · Dépend de : rien

- CurrencyService.add et trySpend émettent l'événement d'économie (raison → type de transaction et itemSku) ; les deux doublons de ShopService et Receipts sont retirés.
- Spec Lune avec un RobloxAnalytics factice : chaque source et chaque puits de Folios émet exactement un événement aux clés valides.

**E8-S2 — Des champs personnalisés que Roblox lit vraiment**  
Responsable : Claude · Effort : S · Dépend de : rien

- Un helper fields(a, b, c) écrit CustomField01 à 03 en chaînes ; tous les appels personnalisés passent par lui.
- grep ne trouve plus {product= ni {pass= dans les appels d'analytics ; un spec refuse toute autre clé.

**E8-S3 — Entonnoir d'accueil figé, fait d'étapes qui existent déjà**  
Responsable : Claude et toi · Effort : M · Dépend de : E5-S1

- LogOnboardingFunnelStepEvent en 8 étapes aux numéros contigus : profil prêt, première touche, premier glyphe lancé (Stats.GlyphsCast 0 → 1), première Épreuve vaincue, premier portail ou première file, premier combat fini, première quête réclamée, premier niveau gagné.
- Un spec fige noms et numéros ; un commentaire dit qu'on ne renumérote jamais : toute étape future (la Première page, E14-S1) va dans un entonnoir séparé (LogFunnelStepEvent), pour que les cohortes restent comparables.
- progression() est appelé à chaque niveau et à chaque palier du pass (spec).
- Les événements ne partent que d'un serveur publié, jamais de Studio, et mettent jusqu'à 24 h à apparaître (page custom-events, lue le 30/09/2026) : tu joues Vellum-Test publié avec un compte neuf, puis tu confirmes l'entonnoir dans le Dashboard le lendemain (capture).

**E8-S4 — Événements de match, de file et de boss**  
Responsable : Claude · Effort : S · Dépend de : E8-S2

- MatchEnded (mode, issue, durée), MatchFormed, QueueTimedOut (mode, attente), MatchVoided et BossEnded existent et sont couverts par un spec.
- Un test compte les noms d'événements personnalisés et échoue au-delà de 100 (plafond Roblox).

**E8-S5 — Des journaux lisibles à grande échelle, et l'Error Report réglé**  
Responsable : Claude et toi · Effort : M · Dépend de : rien

- Log.error signale au niveau erreur sans casser l'appelant ; une entrée D l'écrit (CLAUDE.md dit pcall → warn).
- Gabarits fixes côté serveur et côté client, données après « | », jamais de nom de joueur dans un warn ou une erreur : un spec exécute chaque gabarit de MovementAudit, AntiCheatService et des contrôleurs client ; verdicts du garde et frappes RateLimit journalisés seulement aux seuils 1/10/100.
- docs/OPS.md liste les règles de regroupement de l'Error Report (100 au plus, regex ou texte exact) ; tu les crées dans le Dashboard ; une journée sur Vellum-Test produit moins de 50 avertissements uniques (plafond Roblox : 500 erreurs et 500 avertissements uniques par tranche de 6 h, page error-report lue le 30/09/2026).
- PUBLISH §10.1 dit de lire l'Error Report plutôt que F9 sur un seul serveur.

**E8-S6 — Le tableau de bord du lancement**  
Responsable : Claude et toi · Effort : S · Dépend de : E8-S1, E8-S3, E8-S4, E8-S7

- docs/ECONOMY.md reçoit une section « Tableau de bord » qui nomme les vues du Creator Dashboard à lire à J1, J7 et J30 (rétention, entonnoir, économie, équilibre des glyphes, Error Report).
- Tu confirmes sur Vellum-Test publié que chaque événement apparaît (une capture par vue, rangée dans docs/ops/).

**E8-S7 — Télémétrie d'équilibrage des 28 glyphes**  
Responsable : Claude · Effort : S · Dépend de : E8-S2

- En fin de match, un événement personnalisé GlyphMatch par joueur et par glyphe utilisé : CustomField01 = glyphe, 02 = mode, 03 = issue, valeur = dégâts infligés ; un second, GlyphPick, compte les glyphes équipés à l'entrée en file.
- Spec Lune : 2 noms d'événements seulement, au plus 28 × 2 × 2 = 112 combinaisons de champs (Roblox en permet 8 000), aucune autre clé que CustomField01-03.
- E8-S6 nomme la vue qui donne taux de choix, taux de victoire et dégâts par glyphe.

#### E20 — De vrais humains avant la sortie : communauté, playtest, son, droit à l'effacement

*But : Voir le jeu joué par six à dix vraies personnes, l'entendre enfin, et savoir répondre à une demande d'effacement de données avant le premier joueur public.*

**E20-S1 — Groupe Roblox, titre et serveur Discord**  
Responsable : toi · Effort : S · Dépend de : E1-S4

- Le groupe Roblox existe (ou le groupe propriétaire choisi en E1-S4) ; le titre « Ex-libris du Cercle » est donné par IsInGroup au join (spec écrit par Claude, texte EN/FR).
- Un serveur Discord avec Bloxlink (vérification des comptes, rôle lié au groupe) et trois salons : #annonces, #bugs (gabarit de rapport écrit par Claude), #retours ; le lien est sur la page du jeu.

**E20-S2 — Playtest fermé de 6 à 10 testeurs sur Vellum-Test**  
Responsable : Claude et toi · Effort : M · Dépend de : E5-S1, E5-S2, E20-S1, E6-S2, E6-S7, E8-S3

- Vellum-Test en Audience Limited > Playtesters ; 6 à 10 testeurs ajoutés, dont au moins 3 qui n'ont jamais vu le jeu ; deux séances de 45 min annoncées sur Discord.
- Claude prépare le déroulé, un formulaire de retour de 10 questions au plus et lit les journaux serveur après chaque séance.
- Le rapport docs/qa/<date>-playtest.md couvre QA §6 (World Boss), §6 bis (portails, Faussaires), §11 (anti-triche à plusieurs) et un 3v3 complet ; 6 joueurs arrivent sur les pads d'une arène sans chute (E6-S7) ; pour chaque nouveau testeur, le temps jusqu'au premier glyphe lancé est noté ; chaque KO devient R16 et suivants.

**E20-S3 — Écouter et régler les 55 sons**  
Responsable : Claude et toi · Effort : M · Dépend de : rien

- Claude ajoute une planche d'écoute dans Studio (tools/soundboard) qui joue chacun des 55 sons de SoundConfig à son volume, avec son nom (55 fichiers .wav dans assets/roblox-assets.lock.json).
- Tu écoutes au haut-parleur d'un téléphone puis au casque ; docs/audio/ecoute-<date>.md donne pour chaque son OK, trop fort, trop faible ou à refaire ; PROGRESS:173 (« Rien n'a été entendu ») passe en « fait ».
- SoundConfig reçoit les volumes réglés (et la portée des sons 3D là où le client la pose) ; une entrée D ; tu décides si les préparations des Faussaires ont leur propre son (PROGRESS:374).

**E20-S4 — Droit à l'effacement : procédure et script**  
Responsable : Claude et toi · Effort : M · Dépend de : E5-S1

- docs/SUPPORT.md décrit la procédure : la demande arrive par le webhook Right to Erasure, qui donne le UserId et les GameIds (page webhook-notifications, lue le 30/09/2026) ; qui la traite ; sous quel délai.
- scripts/support.py erase <userId> supprime la clé du profil (magasin de DataService), celle du magasin legacy (readLegacy, DataService.luau:187) et les lignes S1_* du joueur, par l'API Open Cloud « Delete Data Store Entry » (référence lue le 30/09/2026) ; la suppression dans un OrderedDataStore est vérifiée dans la référence avant d'écrire le code.
- Essai sur Vellum-Test avec un compte de test : après erase, le profil repart à neuf et le joueur n'est plus dans les classements ; si un puits externe existe (E9-S4), la procédure le couvre aussi.
- Tu abonnes le webhook vers une destination que tu choisis (salon Discord privé ou adresse de support).

### P1 — Le lancement et les premières semaines

7 épopées, 41 stories, dans l'ordre où les faire.

#### E9 — Semaine de lancement : réagir sans republier, sans tomber

*But : Couper un glyphe cassé, changer le mode du garde, restaurer un profil ou survivre à un bug sans redémarrer tous les serveurs.*

**E9-S1 — LiveConfig : des interrupteurs en direct par ConfigService**  
Responsable : Claude et toi · Effort : M · Dépend de : E5-S1, E4-S7

- Seules des clés en liste blanche et typées surchargent Config : movement_guard_mode_by_zone (JSON de même forme que MovementGuardConfig.ModeByZone, E4-S7), disabled_glyphs, disabled_modes, disabled_products, multiplicateurs de récompense ; la valeur du code est gardée avec un warn si la clé manque ou est invalide.
- Tests Lune avec un instantané factice : liste blanche, validation, repli.
- Tu crées les clés dans le Creator Dashboard ; sur Vellum-Test, changer le mode de l'arène change la ligne de mode de MovementAudit en moins d'une minute, sans redémarrage (Roblox annonce 15 s à 1 min : page configs, lue le 30/09/2026).

**E9-S2 — Un joueur ou un match qui plante n'arrête plus tout le tick**  
Responsable : Claude · Effort : M · Dépend de : rien

- Chaque pas par joueur et par match des boucles de CombatService, MovementService, PortalService et MatchService passe par log.try avec un compteur d'échecs consécutifs.
- Spec : un état ou un mode qui lève laisse tourner les autres ; le match fautif est annulé en 1 s au plus et son arène libérée ; au plus 1 ligne de log par élément et par 10 s.

**E9-S3 — Un serveur à moitié démarré renvoie ses joueurs ailleurs**  
Responsable : Claude · Effort : S · Dépend de : rien

- DataService, CombatService, MatchService, MonetizationService et AntiCheatService sont marqués critiques dans le Bootstrap.
- Spec avec un service factice qui lève : joueurs présents et entrants expulsés avec une clé localisée « erreur serveur, rejoins » ; un échec non critique garde le serveur ouvert.

**E9-S4 — OpsMetrics : compteurs anti-triche et garde agrégés hors de la console**  
Responsable : Claude et toi · Effort : M · Dépend de : E8-S5, E1-S3

- Un seul accumulateur Heartbeat compte frappes, verdicts du garde, expulsions et échecs de chargement ; toutes les 5 min, une ligne de synthèse par serveur (joueurs présents compris).
- Envoi vers le puits choisi en E1-S3 ; s'il est externe, HttpService est activé et l'adresse et la clé viennent de HttpService:GetSecret (secret créé par toi dans le Dashboard, absent en test local : page secrets, lue le 30/09/2026), jamais du dépôt ; aucun nom, UserId haché.
- Spec : 600 frappes RateLimit produisent au plus 4 lignes de log et la synthèse garde les comptes par règle ; une requête « would-strike pour 1 000 minutes-joueur, par règle, sur 7 jours » répond à la décision Correct/Enforce.

**E9-S5 — Les remotes serveur→client comptent les abus**  
Responsable : Claude · Effort : S · Dépend de : rien

- RemoteRegistry.create branche un puits sur chaque RemoteEvent et UnreliableRemoteEvent serveur→client, qui appelle reportAbuse(…, wrong direction, Schema).
- Spec : chaque événement serveur→client a exactement un puits, et un FireServer dessus produit une frappe Schema.

**E9-S6 — Humanoid supprimé : réapparition automatique**  
Responsable : Claude et toi · Effort : S · Dépend de : E1-S3

- Si l'Humanoid ne revient pas en 0,5 s : LoadCharacter au hub ou au Champ de bataille, retour au hub depuis l'arène du boss, et une frappe Schema.
- Spec : exactement une réapparition et une frappe ; la mort normale est intacte ; ton accord (D-139, E1-S3) est cité.

**E9-S7 — Caches élagués et écart d'entraînement qui survit au changement de serveur**  
Responsable : Claude · Effort : S · Dépend de : rien

- Spec à 1 000 joueurs classés simulés : lastRating et settled ne dépassent pas les participants vivants ; names est plafonné à 500 (LRU).
- LastPaidAt de l'entraînement de l'Effacement est dans la section Daily du profil et tient après un rejoin simulé.

**E9-S8 — Le juge de mouvement et l'IA des bots ne partent plus chez les clients**  
Responsable : Claude · Effort : S · Dépend de : rien

- src/server/Pure est mappé sous ServerScriptService, et les modules de src/shared/Pure que seul le serveur requiert (MovementGuard, OriginGuard, BotBrain et les autres, liste établie par un grep des require) y sont déplacés.
- Un test Lune qui désérialise build/Vellum.rbxl ne trouve ni MovementGuard, ni OriginGuard, ni BotBrain sous ReplicatedStorage ; une porte refuse un module de src/shared/Pure que ni src/client ni src/ui ne requiert.
- CLAUDE.md §Structure et DECISIONS sont mis à jour ; l'entrée D note que, tant que le dépôt reste public (E1-S3), les seuils restent lisibles sur GitHub.

**E9-S9 — Remboursements et restauration d'un profil**  
Responsable : Claude et toi · Effort : M · Dépend de : E20-S4, E1-S3

- scripts/support.py inspect <userId> lit un profil sans l'écrire ; revisions <userId> liste ses versions (« List Data Store Entry Revisions », référence lue le 30/09/2026) ; restore <userId> <version> refuse si le profil a une session ouverte, puis restaure après ta confirmation.
- Le webhook Transaction Refunded est abonné ; la politique de E1-S3 (retirer ou non les Folios d'un pack remboursé) s'applique par support.py refund, jamais automatiquement.
- PUBLISH §9.3 (« ce qui ne revient pas ») renvoie à cette procédure ; un essai de restauration sur Vellum-Test est noté dans docs/SUPPORT.md.

#### E10 — Personne n'attend seul

*But : À faible population, chaque pression sur Jouer mène à un combat, l'activité la plus sûre n'est plus la plus payante, et le catalogue dure.*

**E10-S1 — Regrouper les premiers joueurs : réglage du matchmaking Roblox**  
Responsable : toi · Effort : S · Dépend de : E9-S4

- Creator Hub > Matchmaking : une configuration personnalisée relève le poids Occupancy (2 par défaut) à la valeur fixée avec Claude ; capture rangée dans PUBLISH §6.5, avant la sortie.
- Après la sortie, la ligne de synthèse serveur (E9-S4) donne la part de serveurs à un seul joueur ; elle est comparée entre deux semaines, avec et sans le réglage, et notée dans ECONOMY.md.

**E10-S2 — Attribut serveur RankedWaiting pour diriger les arrivants**  
Responsable : Claude et toi · Effort : S · Dépend de : E10-S1

- Le nom exact de MatchmakingService:SetServerAttribute est vérifié dans la référence ; le service Roblox est aliasé pour ne pas heurter notre module MatchmakingService.
- L'attribut est mis à jour à chaque changement de file (spec avec stub) ; tu crées le signal personnalisé dans le Creator Hub.

**E10-S3 — Plafonner les Épreuves du hub**  
Responsable : Claude · Effort : S · Dépend de : rien

- Folios des Épreuves via DailyCap à 40 par jour ; XP pleine pour 25 kills par jour puis 25 % ; DummyKill ne nourrit plus le pass ; rien n'est payé sans glyphe ou dash dans les 60 s.
- Un toast EN/FR une fois par jour au plafond ; tests DailyCap réutilisés.

**E10-S4 — Simulateur de rythme dans les portes de qualité**  
Responsable : Claude · Effort : M · Dépend de : E10-S3

- scripts/pacing.luau lit les vraies configs et joue 4 profils (20 min/j solo, 20 min/j PvP, 60 min/j PvP, fermier d'Épreuves) sur 60 jours : minutes jusqu'aux niveaux 5/10/20/40, jour de fin du pass, Folios à J7/J30, jour où le catalogue est complet.
- tests/Pacing.spec.luau : l'XP/h des Épreuves reste sous 30 % de celle des matchs ; retirer le plafond de E10-S3 le fait échouer ; check.sh le lance.
- Export CSV repris dans un classeur d'économie (skill xlsx) rangé dans docs/economy/.

**E10-S5 — Le pass dure un Volume, pas une semaine**  
Responsable : Claude et toi · Effort : S · Dépend de : E10-S4

- Tu valides le nouveau coût des paliers ; Pacing.spec : le profil 20 min/j finit le pass entre J28 et J42, le profil 60 min/j après J14.
- GAME_DESIGN.md:97 et BattlepassConfig donnent les chiffres calculés par le simulateur, plus d'estimation à la main.

**E10-S6 — Duel d'épreuve contre un Faussaire pendant la file**  
Responsable : Claude · Effort : L · Dépend de : rien

- Après 20 s seul en file 1v1, la carte Jouer propose un premier-à-2 non classé contre un Faussaire Duelliste ; le joueur reste en file et un humain qui arrive prend la main à la pause de manche.
- 3 duels payés par jour via DailyCap, à 50 % des récompenses ; un spec prouve qu'un spar n'écrit jamais Rank.Modes.
- Dans Studio à 1 joueur, le premier coup porté arrive au plus 30 s après Jouer ; textes EN/FR.

**E10-S7 — Duel rapide pour les nouveaux, classé au niveau 10**  
Responsable : Claude · Effort : M · Dépend de : rien

- Les 5 premiers matchs (Stats.MatchesPlayed < 5) sont non classés, avec une fenêtre d'écart de 300 au plus jusqu'à 120 s.
- Spec : un joueur de moins de 5 matchs n'est jamais apparié à plus de 400 d'écart avant 120 s ; niveau et rang adverses affichés sur l'écran d'annonce du match.

**E10-S8 — Escarmouche 3v3 complétée par des Faussaires**  
Responsable : Claude · Effort : M · Dépend de : E10-S6, E16-S2

- Après 60 s avec au moins 2 humains en file 3v3, les sièges vides sont remplis par des Faussaires, en non classé, récompenses réduites.
- Spec : 2 humains forment une escarmouche en 75 s au plus ; 6 humains forment le 3v3 classé exactement comme aujourd'hui.

**E10-S9 — L'Effacement invite au lieu d'aspirer**  
Responsable : Claude · Effort : M · Dépend de : E16-S1

- Un toast « Rejoindre l'Effacement » de 20 s et un portail qui brille ; un joueur en file ou engagé au Champ de bataille n'est pas déplacé sans accepter (spec Admission).
- WorldBossConfig range un intervalle par taille de serveur, aux valeurs que tu valides (proposition : 40 min sous 4 joueurs, 20 min au-delà) ; Config.spec tient les deux valeurs.

**E10-S10 — Des quêtes qu'un joueur seul peut finir, et une relance gratuite par jour**  
Responsable : Claude · Effort : M · Dépend de : rien

- Chaque quête porte Needs = Solo ou Players ; PoolRevision 3 garantit au moins 2 quêtes Solo par tirage (spec sur 365 jours et 52 semaines) ; les anciennes révisions restent épinglées.
- Une relance gratuite par jour, validée par le serveur, jamais sur une quête réclamée ni vers une quête déjà tirée (tests).
- Les nouvelles entrées (Since = 3) ont chacune exactement un producteur (D-28) ; textes EN/FR.

**E10-S11 — Un catalogue qui dure : profondeur mesurée**  
Responsable : Claude et toi · Effort : M · Dépend de : E10-S4

- Le simulateur (E10-S4) donne le jour où un joueur à 60 min/jour possède tout le catalogue : 41 cosmétiques dans CosmeticConfig, rotation 2/2/1/1 par jour (ShopConfig.luau:17).
- Pacing.spec tient : catalogue complet après J60 à 60 min/jour ; sinon, un plan de contenu (nombre d'objets par Volume, par emplacement et rareté) est écrit dans ECONOMY.md et validé par toi.
- Chaque nouvel objet suit le skill vellum-vfx (labo, deux tours).

#### E16 — Du combat sans file

*But : À deux ou trois sur un serveur, un combat en quelques secondes sans file, et plus de pause du classé pendant l'Effacement.*

**E16-S1 — Des règles de dégâts par zone, et plus de pause du classé pendant l'Effacement**  
Responsable : Claude · Effort : M · Dépend de : rien

- L'emplacement unique de CombatService devient une règle par zone (Hub aucune, Match participants, Boss jamais entre joueurs, Page de garde membres) ; une entrée D remplace D-25.
- La pause de matchmaking pendant l'Effacement est supprimée ; un spec prouve qu'un match se forme pendant l'événement ; QA §5.10 et §6.5 passent toujours.

**E16-S2 — La Page de garde : mêlée libre derrière un troisième portail**  
Responsable : Claude · Effort : L · Dépend de : E16-S1

- Une page de 120 studs générée en code, un troisième portail dont le dégagement est testé dans Hub.spec, 6 sceaux d'arrivée et un retour.
- Protection 4 s, réapparition en 3 s au sceau le plus loin ; XP 60 et 5 Folios par kill sous DailyCap (100 par jour) ; Manicule à 3 kills ; rien n'est payé après 3 morts contre le même tueur en 10 min (specs).
- Deux joueurs passent du hub au premier coup en 10 s au plus ; streaming vérifié comme PUBLISH §6.8.

#### E14 — Les premières minutes

*But : Apprendre le combo, le dash et les portails sans lire, et faire de chaque déblocage un vrai moment, pendant que les premières cohortes arrivent.*

**E14-S1 — La Première page en 6 étapes**  
Responsable : Claude et toi · Effort : M · Dépend de : E8-S3, E10-S6

- 6 étapes décidées par le serveur (lancer Brand, enchaîner, dash, vaincre une Épreuve avec un glyphe, entrer dans un portail, gagner un combat), suivies dans un entonnoir séparé FirstPage (LogFunnelStepEvent) : l'entonnoir figé de E8-S3 ne change pas.
- La récompense du jour s'ouvre après l'étape 1.
- Validé avec des joueurs neufs (playtest ou premiers joueurs publics) : la médiane jusqu'à l'étape 5 est sous 3 minutes dans l'entonnoir FirstPage.

**E14-S2 — Les Exercices au Pupitre**  
Responsable : Claude · Effort : L · Dépend de : rien

- Par glyphe, un exercice de recette, plus des exercices de kit (enchaînement de 4, dash-cancel, chaîne de 3), en trois grades Brouillon, Mise au net, Calligraphie.
- Les grades sont comptés par le serveur à partir des événements de GlyphService et CombatService, et payés une seule fois (specs).

**E14-S3 — Un déblocage arrive dans la main, et trois Carnets de loadout**  
Responsable : Claude · Effort : M · Dépend de : E14-S2

- Un compte « Nouveau » dans Claimables (badge sur Menu et Équipement) ; le toast propose Essayer (ouvre l'exercice) et Équiper.
- 3 loadouts sauvegardés, jamais changés pendant une manche ; LoadoutService refuse un Carnet qui contient un glyphe verrouillé ou trop d'emplacements (tests) ; textes EN/FR.

#### E11 — Performance mesurée et bornée

*But : Des budgets chiffrés côté serveur et côté client, tenus par des tests, et des mesures qui remontent des serveurs vivants.*

**E11-S1 — Coût du tick serveur mesuré, en test et en production**  
Responsable : Claude et toi · Effort : M · Dépend de : E9-S4

- Un label debug.profilebegin/end par système ; un TickMeter pur donne p50/p95/max par minute, la mémoire totale et le nombre de joueurs, exportés par OpsMetrics.
- PERFORMANCE.md reçoit une section Serveur dont les budgets sont fixés d'après la première capture (proposition de départ : p95 total < 4 ms à 12 joueurs, MovementAudit < 0,5 ms comme STUDIO_SETUP §10.10), tenus par la logique pure sous Lune.
- Tu ranges une capture MicroProfiler serveur (F9 > MicroProfiler > onglet Server, 60 images au plus, sur une partie où tu as les droits d'édition : page microprofiler, lue le 30/09/2026) : 8 clients, 10 Faussaires, un entraînement contre l'Effacement.

**E11-S2 — Télémétrie de fps côté client**  
Responsable : Claude · Effort : M · Dépend de : E8-S2

- Toutes les 60 s, le client envoie p50/p10 fps et le niveau de qualité par un remote avec Guard et limite de débit.
- Le serveur borne les valeurs et journalise un événement (classe d'appareil, niveau, mode) ; spec Lune.

**E11-S3 — Endurance mémoire de 15 minutes**  
Responsable : Claude et toi · Effort : M · Dépend de : E6-S2

- tools/soak/ lance 1 serveur et 4 clients StudioTestService qui enchaînent CastGlyph et Dash pendant 15 min, avec un CSV toutes les 30 s (mémoire, InstanceCount, VfxPool.stats).
- Après 2 min d'échauffement, la mémoire croît de moins de 1 Mo par minute et les instances restent à ±5 % ; résultats dans PERFORMANCE.md.

**E11-S4 — Budget global de particules**  
Responsable : Claude · Effort : M · Dépend de : rien

- Chaque niveau de QualityConfig a un budget Particles ; VfxTimeline éclaircit l'émission Driven ou en rafale au-delà.
- Spec : 6 × Scorch plus six auras portées restent sous le budget à chaque niveau ; un émetteur sans frein fait échouer.
- La ligne PERFORMANCE.md:151 est générée par scripts/effect-cost.

**E11-S5 — Budget d'objets par écran**  
Responsable : Claude · Effort : S · Dépend de : rien

- tests/ScreenBudget.spec.luau construit chaque écran et chaque onglet de la Boutique à 844×390 avec un profil maximal : au plus 400 objets, le Pass au plus 700.
- Le tableau mesuré est écrit dans PERFORMANCE.md ; ajouter 300 cadres à un écran fait échouer.

#### E12 — Finitions d'entrée, de langue et d'interface

*But : Que les appareils mixtes, la manette, le changement de langue et l'Effacement programmé donnent un écran propre, et que le reste de la PR soit relu.*

**E12-S1 — Un seul module décide si l'appareil est tactile**  
Responsable : Claude et toi · Effort : M · Dépend de : rien

- src/client/Controllers/InputMode.luau s'appuie sur UserInputService.PreferredInput (repli sur Theme.touchOnly) et émet Changed ; Theme, HudController, InputController et les indices le consomment.
- Les specs TouchCluster, HudFit et BottomStack couvrent tactile + clavier, tactile + manette et clavier → tactile ; une porte refuse toute autre lecture de TouchEnabled.
- Tu vérifies une fois sur un portable tactile ou un iPad avec clavier.

**E12-S2 — HUD en mode combat pendant l'Effacement programmé**  
Responsable : Claude · Effort : S · Dépend de : rien

- HudController écoute TravelController.FightChanged.
- HudPlace.spec : FightChanged(true) sans Travelled cache MetaCluster et retient les récompenses, prouvé par mutation ; la ligne PROGRESS:409 est fermée.

**E12-S3 — Langue suivie en direct et pluriels corrects**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3

- La langue vient de GetTranslatorForPlayerAsync (repli RobloxLocaleId) côté client et serveur ; changer la langue en jeu ré-étiquette le HUD et les écrans sans rejoindre (Studio Test > Locale).
- Strings.plural(key, n) existe et une porte refuse les gabarits « {n} <nom>s » ; « slots » est traduit.
- Ta décision sur la traduction automatique et sur es / pt-BR (E1-S3) est appliquée.

**E12-S4 — Navigation à la manette auditée**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3

- Un audit du graphe de sélection rapporte 0 action principale inaccessible sur les 10 écrans et aucun SelectedObject nil après reconstruction d'une liste.
- DPad et ButtonB sont pilotés par le MCP ; tu fais une passe au Controller Emulator sur la liste STUDIO_SETUP §11 ; la décision console (E1-S3) est appliquée.

**E12-S5 — Les restes de l'interface**  
Responsable : Claude et toi · Effort : S · Dépend de : rien

- Le reste de C9 est fait (dégâts reçus « −87 », étiquette d'état : PROGRESS:411, D-156), avec l'appel de VfxLibrary.Hit et son épingle dans Afterimage.spec changés ensemble.
- La ligne des deux prix d'une carte du jour tient dans sa place (388 pour 374 aujourd'hui, PROGRESS:475), tenu par LayoutRules ; l'icône Check sans appelant est retirée (le code mort est interdit par CLAUDE.md).
- Tu choisis une seule façon pour le balancement du bouton Récupérer et pour l'éclat d'une récupération (PROGRESS:411) ; l'autre copie est supprimée.

**E12-S6 — Relecture après fusion de l'interface, du client et du partagé**  
Responsable : Claude · Effort : M · Dépend de : E2-S8

- Les fichiers de src/ui (68), src/client (20) et src/shared (49) modifiés par la PR #2 passent par /code-review au niveau medium, par tranches.
- Les constats confirmés de gravité haute sont corrigés avec un test ; les autres deviennent des tickets du suivi.

#### E19 — Les dettes des glyphes

*But : Chaque glyphe fait ce que sa fiche dit, s'arrête quand il doit, et l'écran d'équipement dit vrai.*

**E19-S1 — Les zones à ticks s'arrêtent avec leur lanceur**  
Responsable : Claude · Effort : M · Dépend de : rien

- Bavure, Roussi, Spirale, Poncif et Filigrane cessent de dessiner quand leur lanceur les arrête ; l'horloge des glyphes à ticks ne gèle plus (PROGRESS:395) ; les ticks du Roussi suivent la même règle (D-139).
- Un spec par glyphe, prouvé par mutation ; planches avant/après au labo selon vellum-vfx, deux tours.

**E19-S2 — Rature, Insertion, Filigrane et la dérive de la Rubrique**  
Responsable : Claude et toi · Effort : M · Dépend de : E1-S3

- La fuite latérale de la Rature, le vol à plat de l'Insertion et le bord au sceau du Filigrane sont corrigés ou gardés par une entrée D (PROGRESS:395).
- La dérive tolérée de la Rubrique (6 studs, D-141) est tranchée avec toi ; aucun chiffre de gameplay ne bouge sans ton accord ; labo deux tours.

**E19-S3 — Hachures et écran d'équipement**  
Responsable : Claude · Effort : S · Dépend de : rien

- Le dernier trait des Hachures (5 dégâts) a son image d'impact.
- L'écran d'équipement montre les dégâts totaux d'un glyphe à plusieurs coups (Cartouche : 48 avec son sceau et ses ticks, PROGRESS:388) et plus un seul coup (28) ; spec d'affichage.

**E19-S4 — Cartouche : la recharge accélérée promise (D-140)**  
Responsable : Claude et toi · Effort : S · Dépend de : E1-S3

- Tu confirmes ce qui avait été promis ; la recharge accélérée est faite, ou la promesse est retirée par une entrée D.
- Config.spec tient toujours les budgets de l'ultime (48).

**E19-S5 — Rubrique : un clip de lancer**  
Responsable : Claude et toi · Effort : S · Dépend de : rien

- Un clip keyé selon le skill vellum-animation, qui lâche à 0,7 s (PROGRESS:395).
- Tu donnes ton accord explicite avant l'envoi sur Roblox ; AnimationConfig.spec est vert.

### P2 — Le premier mois : faire revenir

3 épopées, 9 stories, dans l'ordre où les faire.

#### E13 — Un anti-triche qui se souvient

*But : Qu'un tricheur expulsé ne revienne pas propre, que les classements soient purgés, et porter Server Authority si l'essai l'a validé.*

**E13-S1 — Historique d'expulsions et escalade vers BanAsync**  
Responsable : Claude et toi · Effort : M · Dépend de : E9-S4, E1-S3

- Meta.Security.Kicks (anneau de 20) est écrit avant chaque Kick.
- Un module pur d'escalade testé sous Lune : la 3e expulsion Schema en 7 jours appelle un BanAsync factice (1 jour) ; RateLimit et Origin n'escaladent jamais.
- Durées, seuils et voie d'appel choisis par toi et écrits dans DECISIONS.

**E13-S2 — Purge des classements et commande de bannissement**  
Responsable : Claude et toi · Effort : S · Dépend de : E13-S1

- Un bannissement retire les lignes S1_* du UserId (spec avec Players factice).
- Une commande serveur réservée au développeur bannit et débannit par UserId ; les seuils vivent dans GameConfig et ne s'appliquent qu'une fois le garde sorti d'Observe.

**E13-S3 — Porter Server Authority sur la place (si l'essai E4-S11 a dit « plus tard »)**  
Responsable : Claude et toi · Effort : XL · Dépend de : E4-S11

- Sur une branche et une place copie : dash, projection, étourdissement et ragdoll portés en BindToSimulation, InputController en InputAction.
- QA §11 étape 7 est rejetée par le moteur ; un duel honnête à 150 ms est jugé inchangé, y compris sur téléphone.
- Une entrée D dit « adopté » avec tout ce qui a cassé ; si E4-S11 a dit « non », cette story est fermée par une entrée D.

#### E15 — Revenir demain, revenir la semaine prochaine

*But : Donner des raisons de revenir depuis l'extérieur du jeu, et une saison qui a une fin datée.*

**E15-S1 — Calendrier de 28 jours et Signet**  
Responsable : Claude · Effort : M · Dépend de : rien

- Tests DailyStreak : un jour raté avec un Signet continue, sans Signet repart à 1, le jour 28 est donné une seule fois.
- Cosmétiques non vendables aux jours 7, 14, 21 et 28 ; compteur de série dans le HUD du hub.

**E15-S2 — Notifications et badges**  
Responsable : Claude et toi · Effort : M · Dépend de : rien

- L'invite d'opt-in arrive après le premier niveau, jamais en combat ni dans les 3 premières minutes ; les données de lancement ouvrent le bon écran ; un test tient la limite d'une notification par jour.
- Tu crées les gabarits EN/FR (99 caractères au plus) dans Engagement > Notifications une fois les 100 visites atteintes (page experience-notifications, lue le 30/09/2026), et les badges ; leurs ids sont validés au démarrage avec un warn par id manquant.

**E15-S3 — Des Volumes datés qui basculent seuls**  
Responsable : Claude et toi · Effort : M · Dépend de : E10-S5

- SeasonConfig liste {Id, NameKey, StartsAt, EndsAt} en UTC ; SeasonId et PreviousSeasonId sont déduits de l'horloge.
- Specs : bascule S1 → S2 une seule fois, récompenses de saison payées une fois, profil chargé pendant la bascule sûr, EndsAt d'un Volume égal au StartsAt du suivant.
- Compte à rebours sur le Pass, le Classement et le Résultat ; la table S2 est écrite avec toi avant la fin de S1.

#### E21 — Jouer ensemble

*But : Entrer en file entre amis, défier quelqu'un, regarder un combat et s'exprimer sans parler.*

**E21-S1 — Atelier (groupe) et Cartel (défi en duel)**  
Responsable : Claude et toi · Effort : L · Dépend de : E10-S6

- Player.PartyId et un « Faire équipe » en jeu : un groupe entre en file d'un bloc ; spec : un groupe de 2 plus 4 solos reste toujours dans la même équipe.
- Un Cartel accepté lance un premier-à-2 non classé sous DailyCap qui n'écrit jamais Rank ; test Studio à 2 clients ; textes EN/FR.

**E21-S2 — La Tribune et les règles du Scriptorium privé**  
Responsable : Claude et toi · Effort : M · Dépend de : E21-S1, E4-S4, E16-S2

- Un tableau au hub liste les défis et les séries en cours ; Regarder suit le combat sans quitter le hub ; un classé ne se regarde pas depuis la file du même mode.
- En serveur privé acheté : récompenses d'Épreuve, de spar et de Page de garde divisées par deux ; le propriétaire peut ouvrir ou fermer la Page de garde et choisir le mode proposé en spar (1v1 ou 3v3), rien d'autre (spec) ; ta décision gratuit ou payant (E1-S3) est appliquée.

**E21-S3 — Les Gestes : emplacement, roue, gestes gratuits et pose de victoire**  
Responsable : Claude et toi · Effort : M · Dépend de : E4-S11

- Slot Gesture avec 8 emplacements et une roue sur B, L1 ou un disque tactile au hub ; inutilisable en combat ou en manche (spec Cosmetics).
- 4 ou 5 gestes gratuits retargetés depuis les bibliothèques CC0 déjà épinglées, 2 gestes signés keyés selon le skill vellum-animation ; AnimationConfig.spec étendu ; compatibilité vérifiée si Server Authority est adopté (les emotes personnalisées n'y sont pas prises en charge).
- Aucun envoi sur Roblox sans ton accord explicite.

### P3 — La croissance

2 épopées, 10 stories, dans l'ordre où les faire.

#### E17 — Objectifs longs et temps forts

*But : Garder les vétérans après le niveau 40 et rythmer l'année par des événements programmés sans republier.*

**E17-S1 — Maîtrise des glyphes (rangs I à V)**  
Responsable : Claude · Effort : L · Dépend de : E14-S2

- Un module pur donne l'XP de maîtrise par glyphe ; le rang III débloque la teinte du glyphe, le rang V un titre et un sceau.
- Les Épreuves ne comptent qu'en Exercices (spec) ; 28 pistes longues.

**E17-S2 — Jalons de 45 à 100 et l'Ex-libris des succès**  
Responsable : Claude · Effort : M · Dépend de : rien

- Test : nextReward(level) n'est jamais nil pour les niveaux 1 à 99 ; la carte Résultat nomme toujours la prochaine récompense.
- Les succès à vie sont donnés une seule fois, par le serveur (specs) ; textes EN/FR.

**E17-S3 — Le Registre du mois**  
Responsable : Claude · Effort : M · Dépend de : E16-S2

- Un classement mensuel des kills (Page de garde et matchs) ; le top 10 reçoit un titre qui expire (spec d'expiration).

**E17-S4 — Les Heures : un calendrier d'événements piloté par données**  
Responsable : Claude et toi · Effort : M · Dépend de : E9-S1

- Un module pur EventCalendar dit ce qui est actif à un instant t ; la liste {Id, NameKey, StartsAt, EndsAt, Kind, Params} vient d'une valeur JSON de LiveConfig (100 000 caractères au plus d'après la page configs), donc un nouvel événement ne demande aucun déploiement.
- Multiplicateurs plafonnés à ×4, jamais de chiffre de dégâts du classé touché (specs).
- Tu crées la clé JSON dans le Dashboard ; sur Vellum-Test, un événement programmé change quêtes, boutique et bannière à l'heure dite.

**E17-S5 — Le Lutrin et les codes Errata**  
Responsable : Claude · Effort : M · Dépend de : E17-S4

- Un lutrin au hub et une bannière du Menu montrent l'événement en cours et le suivant.
- Un remote RedeemCode avec Guard, limite de débit et expulsion ; un code par profil, stocké dans Meta, avec expiration (specs).

**E17-S6 — Le calendrier du Volume I**  
Responsable : Claude et toi · Effort : S · Dépend de : E17-S4

- Proposition à valider avec toi, écrite dans docs/ECONOMY.md : un week-end Double Encre (Folios de match ×2) le premier week-end de chaque mois, une Nuit de l'Effacement chaque vendredi de 19 h à 21 h UTC (intervalle 10 min), une semaine d'un pigment (quêtes d'un seul pigment) chaque troisième semaine.
- Chaque ligne validée est une entrée du JSON LiveConfig ; un spec EventCalendar la rejoue sur le Volume entier sans chevauchement interdit.

**E17-S7 — Se faire voir : vignettes et une première campagne**  
Responsable : Claude et toi · Effort : M · Dépend de : E8-S6, E1-S2

- Après 30 jours de données (E8-S6), deux jeux de vignettes sont comparés sur le taux de clic du Dashboard, et le meilleur est gardé.
- Une première campagne d'expériences sponsorisées est lancée par toi dans l'Ads Manager (crédits achetés en Robux dès 13 ans ou par carte dès 18 ans : page ads-manager, lue le 30/09/2026), avec un budget fixé à l'avance ; résultat noté dans ECONOMY.md.

#### E18 — Du code qui tient la distance

*But : Des tests qui vérifient le comportement plutôt que l'orthographe, et des fichiers qu'on peut encore modifier sans conflit.*

**E18-S1 — Tests de source par symbole, et un cliquet**  
Responsable : Claude · Effort : M · Dépend de : rien

- tests/support/source.luau offre symbol(groupe, nom) ; les épingles de HudController, InputController et ShopScreen y passent.
- Un spec cliquet compte les specs qui lisent src et refuse toute hausse.

**E18-S2 — Découper les gros fichiers UI**  
Responsable : Claude · Effort : L · Dépend de : E18-S1

- src/ui/Build.luau remplace les ~40 copies de own/label/list/blank ; HudController tombe à 450 lignes au plus (898 aujourd'hui, PROGRESS:411), InputController à 400 au plus (768).
- tests/FileSize.spec.luau tient une liste d'exceptions qui ne peut que rétrécir ; les 9 fichiers UI en sortent sans changer d'assertion hors carte des symboles ; LayoutRules et HudBudget inchangés.

**E18-S3 — Sortir la logique de décision des services en modules purs**  
Responsable : Claude · Effort : L · Dépend de : rien

- La porte de dégâts, le calcul des récompenses et la résolution de manche et de série vivent dans des modules Pure exécutés sous Lune.
- Chaque épingle de texte remplacée est supprimée ; chaque nouveau test est prouvé par un défaut réintroduit.

## 5. Ce que toi seul peux faire

Claude ne peut ni se connecter à ton compte Roblox, ni créer un compte, ni coller une clé secrète, ni écouter un son, ni tenir un téléphone. Voici, dans l'ordre des sessions, tout ce qui passe par toi. Une règle vaut partout : **une clé API ou un mot de passe ne passe jamais par le chat**. Tu la colles toi-même là où c'est indiqué, et tu renvoies seulement « fait ».

### Session 1 — Trancher (1 à 2 h) · E1-S3, E1-S1, E1-S4

1. **Séance de décisions.** Claude t'envoie une liste numérotée de questions, chacune avec 2 ou 3 options, leur coût et sa recommandation. Tu réponds dans le chat, par exemple `D1 : B, D2 : A, D3 : recommandation`. Claude écrit les entrées D-202 et suivantes et te les fait relire.
2. **Questionnaire de maturité.** Ouvre create.roblox.com/dashboard/creations > clique sur Vellum > **Configure > Questionnaire**. Réponds d'après ce que le jeu montre : combat fantastique, violence légère, aucun sang réaliste, pas de peur, pas d'humour grossier, pas de romance ; chat texte Roblox activé ; aucun autre texte écrit par les joueurs. Envoie.
   **Tu renvoies :** le libellé obtenu (Minimal ou Mild attendu) et une capture glissée dans le chat.
3. **Propriétaire du jeu.** Si tu gardes ton compte (le plus simple : les 91 assets y sont déjà), rien à faire. Si tu choisis un groupe, dis-le : Claude te guide écran par écran le moment venu (ce chemin n'a pas été vérifié ici) et renvoie les assets au nom du groupe, un envoi à la fois, avec ton accord.

### Session 2 — Créer le terrain de test · E5-S1, E6-S1

4. **Créer Vellum-Test.** Claude construit `build/Vellum.rbxl`. Ouvre-le dans Studio, puis **File > Publish to Roblox As… > Create new experience**, nom « Vellum-Test ».
5. **La rendre invisible.** Dashboard > Vellum-Test > **Configure > Settings > Audience > Limited > Playtesters**.
6. **L'accès aux API, sur Vellum-Test seulement.** Dans Studio, Vellum-Test ouverte : **File > Experience Settings > Security > Enable Studio Access to API Services**. Jamais sur Vellum.
7. **La clé Open Cloud.** Dashboard > **Open Cloud > API Keys > Create API Key**, nom `vellum-test-ci`, accès limité à Vellum-Test : exécution Luau (`universe.place.luau-execution-session:write`) et publication de places ; expiration de 90 jours. Copie la clé, puis dans le Terminal : `open -e /Users/fouzi/Desktop/robloxtest/.env.local` et ajoute une ligne `ROBLOX_TEST_API_KEY=` suivie de la clé. Enregistre. Ce fichier est ignoré par git (`.gitignore:35`).
   **Tu renvoies :** l'identifiant d'univers et l'identifiant de place de Vellum-Test (visibles dans l'adresse de la page ou le menu « … » de la tuile), et « clé posée ». Jamais la clé.
8. **Outils de Studio.** **File > Beta Features > New Device Simulator** (coche, puis redémarre Studio). Puis **Assistant > … > Manage MCP Servers > Enable Studio as MCP server**.
   **Tu renvoies :** « Studio prêt ».

### Session 3 — Fusionner et séparer · E2-S8, E2-S2, E2-S7

9. **Valider la fusion.** Lis le résumé de relecture de la session 2 (constats corrigés, tickets ouverts). Si ça te va, écris « fusionne ». Claude fusionne la PR #2 et pose la protection de `main`.
10. **Les secrets de publication.** Claude crée les environnements `test` et `prod` dans GitHub. Toi : github.com/FouziGit/robloxtest > **Settings > Environments > test > Add environment secret**, trois fois : `ROBLOX_API_KEY` (la clé de Vellum-Test), `UNIVERSE_ID`, `PLACE_ID`. Même chose dans `prod` avec une clé Open Cloud créée pour Vellum (droit de publication de places, univers Vellum seul). Dans `prod`, **Required reviewers** : toi.
    **Tu renvoies :** « secrets posés ».

### Session 5 — Vendre et rassembler · E3-S4, E20-S1

11. **Passes et produits, dans les deux univers.** Dashboard > Vellum-Test > **Monetization > Passes** : crée les 4 passes (VIP 399, LoadoutSlots 199, Orpiment 299, SkinPack 249 R$) ; **Monetization > Developer Products** : crée les 10 produits de `docs/PUBLISH.md` §3.2, noms et prix du tableau. Recommence dans Vellum. Pour la description du VIP, copie le texte que Claude te donne (le même que le jeu).
    **Tu renvoies :** deux listes `Clé = id`, une par univers, par exemple `Vip = 123456789`. Claude les colle et vérifie `0 missing ids` au démarrage.
12. **Groupe et Discord.** Crée le groupe Roblox (si ce n'est pas déjà le propriétaire), puis un serveur Discord avec les salons `#annonces`, `#bugs`, `#retours`. Ajoute le bot Bloxlink et lie-le au groupe. Colle le lien d'invitation Discord sur la page du jeu.
    **Tu renvoies :** le nom du groupe et « Discord prêt ».

### Session 12 — Voir les premiers chiffres · E8-S3, E8-S5

13. **Jouer comme un inconnu.** Avec un compte que tu crées toi-même (Claude ne crée pas de compte), rejoins Vellum-Test publié et joue 10 minutes. Le lendemain, ouvre l'analytique de Vellum-Test et cherche l'entonnoir « Onboarding ».
    **Tu renvoies :** une capture de l'entonnoir.
14. **Règles de l'Error Report.** Claude écrit `docs/OPS.md` avec la liste des règles de regroupement. Ouvre la page Error Report de Vellum-Test et crée-les une par une, dans l'ordre.
    **Tu renvoies :** « règles posées ».

### Sessions 13 à 17 — Les labos Studio · E7, E6-S3

15. **Garder Studio visible.** Pendant ces sessions, laisse Studio ouvert sur la place et le Mac déverrouillé : un écran verrouillé a déjà bloqué les captures (PROGRESS:413, :465). Si tu t'absentes, tu peux lancer `caffeinate -d` dans un Terminal et le fermer au retour.
16. **Modération.** Si `upload_assets.py status` montre un asset **Rejected**, fais appel depuis la page de l'asset dans le Dashboard, ou dis à Claude de le régénérer (il le renverra avec ton accord).
17. **Juger les planches.** Claude te montre les planches avant/après ; tu dis « garde », « refais » ou « trop fort », selon les six critères du skill vellum-vfx.

### Session 18 — De vrais humains, de vrais téléphones, de vrais sons · E20-S2, E5-S4, E6-S5, E20-S3

18. **Playtest.** Dans l'écran d'audience de Vellum-Test, donne la permission de test à 6 à 10 comptes, dont au moins 3 qui n'ont jamais vu le jeu. Annonce deux créneaux de 45 min dans `#annonces` avec le formulaire de retour que Claude prépare. Pendant la séance, suis le déroulé ; Claude lit les journaux ensuite.
    **Tu renvoies :** l'heure de début et de fin de chaque séance, et les réponses du formulaire.
19. **Passe à deux comptes.** Avec ton compte et ton compte secondaire, sur Vellum-Test : `docs/QA.md` §0 à §5, §7 et §10, dont un achat de chaque passe et de chaque produit (le §0 de QA.md dit quel compte sert à quoi).
    **Tu renvoies :** OK ou KO par étape, avec une capture pour chaque KO.
20. **Téléphones.** Sur un Android d'entrée de gamme et un iPhone ancien, rejoins Vellum-Test et suis le protocole de `docs/PERFORMANCE.md` : un combat à 6 lancers en qualité Élevée, puis en Performance, et un changement de qualité en plein combat. Relève les images par seconde et la mémoire dans la console développeur (sur téléphone, tape `/console` dans le chat).
    **Tu renvoies :** le nom de chaque appareil et ses chiffres.
21. **Les sons.** Claude ouvre la planche d'écoute dans Studio ; tu écoutes chaque son au haut-parleur du téléphone puis au casque, et tu dis « OK », « trop fort », « trop faible » ou « à refaire ».

### Session 19 — La vitrine et la conformité · E1-S2, E20-S4

22. **Fiche du jeu.** Choisis l'icône parmi les trois propositions. Dashboard > Vellum > **Configure** : téléverse l'icône et au moins 3 vignettes, colle nom et description en anglais ; onglet **Localization** : nom et description en français.
23. **Webhooks.** Dans les réglages de webhooks du Creator Hub, abonne « Right to Erasure » et « Transaction Refunded » vers la destination choisie en session 1 (un salon Discord privé, par exemple).
    **Tu renvoies :** « webhooks abonnés ».

### Session 20 — Publier · E2-S6

24. **Approuver la production.** Quand Claude lance la publication vers `prod`, GitHub t'envoie une demande : **Actions > le run > Review deployments > Approve and deploy**.
25. **Migrer les serveurs.** Dashboard > Vellum > la place > **Restart servers for updates** (PUBLISH §8.5), puis la passe courte de `docs/QA.md` §13.
    **Tu renvoies :** OK ou KO par étape de §13.

### Après la sortie (P1 et P2)

- **Matchmaking** (E10-S1) : Creator Hub > Matchmaking, relever le poids Occupancy à la valeur fixée ensemble ; capture.
- **Interrupteurs en direct** (E9-S1, E17-S4) : créer dans le Dashboard les clés que Claude te liste (configs d'expérience).
- **Secret du puits d'exploitation** (E9-S4, si externe) : Dashboard > **Secrets > Create Secret**, domaine limité à l'adresse du puits.
- **Capture serveur** (E11-S1) : dans une partie, console (Ctrl+F9 ou Cmd+F9) > **MicroProfiler > Server > Begin server recording**, puis dépose le fichier.
- **Notifications** (E15-S2) : après 100 visites, **Engagement > Notifications**, gabarits EN/FR de 99 caractères au plus.
- **Publicité** (E17-S7) : après 30 jours de données, une première campagne dans l'Ads Manager, avec un budget fixé à l'avance.

## 6. Outils à installer ou à activer

Ce qui fait le plus de différence : le MCP de Studio avec StudioTestService et le simulateur d'appareil (voir le jeu sans deuxième joueur), Luau Execution (voir la sauvegarde tourner avant les joueurs), l'Error Report et l'analytique (voir le jeu vivant), et deux vrais téléphones. Tout le reste est gratuit ou optionnel.

### À activer maintenant (avant la publication)

**Serveur MCP intégré à Roblox Studio** — Permet à Claude de piloter Studio : lire et chercher les scripts, exécuter du Luau, lancer et arrêter le jeu, lire la console, capturer la vue, simuler clavier et souris.  
Pourquoi pour Vellum : C'est l'outil du labo VFX, du test de fumée, du labo d'appareils et des 12 vérifications du garde de mouvement (E6, E7).  
Coût : Gratuit, inclus dans Studio. · Claude peut le piloter : oui  
Mise en place : Studio : Assistant > … > Manage MCP Servers > Enable Studio as MCP server. Déjà connecté dans cette session (outils mcp__Roblox_Studio__*). Garder Studio ouvert sur la place et l'écran du Mac déverrouillé : PROGRESS.md:413 et :465 montrent qu'un écran verrouillé bloque les captures.  
Lien : https://create.roblox.com/docs/studio/mcp

**StudioTestService et VirtualInput** — API de test de Studio annoncées le 28/05/2026 : un serveur avec jusqu'à 8 clients lancé par script, des joueurs ajoutés en cours, et des entrées souris et clavier traitées comme du vrai matériel.  
Pourquoi pour Vellum : Test de fumée à 2 clients (E6-S2), routes du garde de mouvement (E7-S6), endurance mémoire (E11-S3), sans second joueur humain.  
Coût : Gratuit. · Claude peut le piloter : oui  
Mise en place : Studio à jour ; Claude les appelle par execute_luau du MCP.  
Lien : https://devforum.roblox.com/t/new-studio-testing-apis-and-assistant-improvements/4657854

**StudioDeviceSimulatorService, New Device Simulator et Controller Emulator** — Simulation d'appareil pilotable par script : choisir un appareil, une résolution, une densité, une orientation, créer des profils (méthodes en Plugin Security).  
Pourquoi pour Vellum : Rend possible le labo d'appareils (E6-S3) que PROGRESS.md:454 croyait impossible (« ne se commande pas par script »).  
Coût : Gratuit (bêta). · Claude peut le piloter : oui  
Mise en place : Studio : File > Beta Features > New Device Simulator, puis redémarrer Studio (E6-S1).  
Lien : https://create.roblox.com/docs/reference/engine/classes/StudioDeviceSimulatorService

**Open Cloud — Luau Execution** — Exécute un script Luau sans écran sur une version d'une place, avec accès aux DataStores ; 5 minutes par tâche, 10 tâches simultanées par place, scripts de 4 Mo ; ni physique ni scripts de la place lancés d'office.  
Pourquoi pour Vellum : Seul moyen de faire tourner ProfileStore, saveNow, les reçus et les classements sur le vrai moteur avant la sortie (E5-S3).  
Coût : Aucun prix indiqué dans la documentation lue. · Claude peut le piloter : oui  
Mise en place : Univers privé Vellum-Test et clé limitée au droit universe.place.luau-execution-session:write, rangée par toi dans .env.local (E5-S1).  
Lien : https://create.roblox.com/docs/en-us/cloud/reference/features/luau-execution.md

**Roblox/place-ci-cd-demo** — Exemple officiel de CI : build Rojo, envoi, tests par Luau Execution, publication.  
Pourquoi pour Vellum : Modèle pour scripts/cloud_check.py et le job CI manuel (E5-S3).  
Coût : Gratuit, licence MIT. Dépôt archivé (dernier envoi le 17/09/2024, d'après l'API GitHub) : à lire comme modèle, pas à utiliser comme dépendance. · Claude peut le piloter : oui  
Mise en place : Rien à installer ; Claude lit et adapte.  
Lien : https://github.com/Roblox/place-ci-cd-demo

**Jest-Lua** — Adaptation de Jest pour Luau, qui ne tourne que dans le moteur Roblox.  
Pourquoi pour Vellum : Specs de moteur (tests/engine-specs/) exécutées par Luau Execution, pour ce que Lune ne peut pas faire tourner (E5-S3).  
Coût : Gratuit, licence MIT ; dernière version v3.10.0 (23/12/2024, d'après l'API GitHub). · Claude peut le piloter : oui  
Mise en place : JestGlobals = jsdotlua/jest-globals@3.10.0 en dépendance de développement dans wally.toml.  
Lien : https://github.com/jsdotlua/jest-lua

**Error Report de Roblox** — Erreurs et avertissements Luau des serveurs et des clients, presque en direct, avec pile d'appels ; jusqu'à 100 règles de regroupement (regex ou texte exact) ; au plus 500 erreurs et 500 avertissements uniques par tranche de 6 h.  
Pourquoi pour Vellum : Le premier outil de suivi d'erreurs à brancher : gratuit, sans intégration, il remplace la surveillance de F9 sur un seul serveur (PUBLISH §10.1, E8-S5).  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Creator Dashboard de l'expérience ; tu colles les règles de docs/OPS.md que Claude écrit.  
Lien : https://create.roblox.com/docs/production/analytics/error-report

**Creator Analytics : événements personnalisés, entonnoirs, économie** — Jusqu'à 100 événements personnalisés par jeu, envoyés seulement depuis le serveur d'un jeu publié (jamais de Studio ni du client), agrégés chaque jour : jusqu'à 24 h avant de les voir.  
Pourquoi pour Vellum : Lire la rétention, l'entonnoir d'accueil, l'équilibre des Folios et celui des glyphes dès la semaine de lancement (E8).  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Claude écrit le code ; tu joues Vellum-Test publié avec un compte neuf et tu lis le Dashboard (Claude ne peut pas s'y connecter).  
Lien : https://create.roblox.com/docs/production/analytics/custom-events

**Webhooks Roblox (effacement, remboursements)** — Notifications envoyées à une adresse de ton choix : Right to Erasure (UserId et GameIds), Transaction Refunded, abonnements.  
Pourquoi pour Vellum : Répondre à une demande d'effacement (E20-S4) et savoir quand un achat est remboursé (E9-S9).  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Tu abonnes les deux notifications vers un salon Discord privé ou une adresse que tu choisis ; Claude écrit la procédure et le script de traitement.  
Lien : https://create.roblox.com/docs/cloud/webhooks/webhook-notifications

**Open Cloud — entrées de DataStore** — API pour lire, modifier, supprimer une entrée de DataStore et lister ses versions.  
Pourquoi pour Vellum : Base du script de support : effacer un joueur, relire, restaurer ou compenser un profil (E20-S4, E9-S9).  
Coût : Gratuit. · Claude peut le piloter : oui  
Mise en place : Une clé Open Cloud avec les droits de lecture et d'écriture des DataStores de l'univers concerné, rangée dans .env.local.  
Lien : https://create.roblox.com/docs/cloud/reference/DataStoreEntry

**Audience Limited > Playtesters** — Réglage d'accès qui ouvre une expérience à des testeurs choisis sans la rendre publique ni visible.  
Pourquoi pour Vellum : Faire jouer 6 à 10 personnes à Vellum-Test avant la sortie (E20-S2).  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Creator Dashboard > Configure > Settings > Audience > Limited > Playtesters, puis donner la permission de test aux comptes choisis.  
Lien : https://create.roblox.com/docs/production/publishing/publish-experiences-and-places

**GitHub Environments et main protégé** — Des secrets séparés pour test et prod, une approbation obligatoire avant la prod, des règles de tags, et un main qui exige la CI.  
Pourquoi pour Vellum : Publier sur Vellum-Test sans risque pour Vellum, et ne jamais publier une branche non relue (E2-S2, E2-S7). Gratuit car le dépôt est public ; en privé, il faut GitHub Team (4 $ par utilisateur et par mois d'après la page de prix lue).  
Coût : Gratuit tant que le dépôt est public. · Claude peut le piloter : oui  
Mise en place : Claude les crée par gh api avec ton accord ; tu colles toi-même les secrets dans Settings > Environments.  
Lien : https://docs.github.com/en/actions/deployment/targeting-different-environments/managing-environments-for-deployment

**Server Authority** — Mode sorti le 09/07/2026 où le serveur fait autorité sur le mouvement, avec prédiction côté client ; il règle aussi StreamingEnabled ; le code de mouvement doit passer par BindToSimulation et InputAction ; emotes personnalisées non prises en charge.  
Pourquoi pour Vellum : Fermerait dans le moteur ce que le garde en Observe laisse ouvert (E4-S11 essai, E13-S3 portage).  
Coût : Gratuit, à activer volontairement (Workspace.AuthorityMode). · Claude peut le piloter : oui  
Mise en place : Uniquement sur une branche et une copie de la place dans Vellum-Test.  
Lien : https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993

**Bloxlink** — Bot Discord qui relie les comptes Roblox et Discord et donne des rôles selon le groupe, les passes ou les badges ; verrous de groupe et d'âge.  
Pourquoi pour Vellum : Communauté et testeurs reliés au jeu dès le playtest (E20-S1).  
Coût : La page lue ne donne pas de prix ; l'installation de base ne mentionne aucun paiement. · Claude peut le piloter : non, c'est toi  
Mise en place : Tu l'ajoutes à ton serveur Discord et tu lies le groupe Roblox.  
Lien : https://devforum.roblox.com/t/bloxlink-a-roblox-discord-bot/758400

**Audacity** — Éditeur audio libre pour macOS (Apple Silicon et Intel), version 4.0.0.  
Pourquoi pour Vellum : Écouter, comparer et couper les 55 sons générés quand l'un sonne mal (E20-S3) ; Claude les régénère ensuite depuis tools/audio.  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Télécharger depuis audacityteam.org ; aucun réglage.  
Lien : https://www.audacityteam.org/download/

**Suivi du backlog : GitHub Issues et Projects, ou Notion** — Un ticket par story, avec son état, son responsable et ses critères ; Claude les crée depuis backlog.json par gh ou par le MCP Notion déjà connecté.  
Pourquoi pour Vellum : Rendre le plan vivant : chaque session ferme des tickets, les constats de relecture deviennent des tickets (E2-S1, E12-S6).  
Coût : Gratuit. · Claude peut le piloter : oui  
Mise en place : Tu choisis : GitHub (le dépôt est public, donc les tickets le seront aussi) ou Notion (privé). Claude crée les tickets avec ton accord.  
Lien : https://github.com/FouziGit/robloxtest/issues

**Skills /code-review et bmad-code-review** — Relecture adversariale d'un diff (niveaux low à max) et relecture à trois couches (Blind Hunter, Edge Case Hunter, Acceptance Auditor).  
Pourquoi pour Vellum : Relire le serveur de la PR #2 avant fusion (E2-S1), le reste après (E12-S6), puis chaque branche de lot.  
Coût : Inclus dans Claude Code. · Claude peut le piloter : oui  
Mise en place : Déjà installés.  
Lien : /Users/fouzi/.claude/skills/bmad-code-review

**Skill skill-creator** — Écrire et valider un nouveau skill Claude.  
Pourquoi pour Vellum : Transformer la recette du labo d'appareils en skill vellum-device-qa, à côté de vellum-vfx (E6-S3).  
Coût : Inclus. · Claude peut le piloter : oui  
Mise en place : Déjà installé.  
Lien : /Users/fouzi/.claude/skills/skill-creator

**Deux vrais téléphones : un Android d'entrée de gamme et un iPhone ancien** — Mesure réelle des images par seconde, de la mémoire, de la chauffe et du toucher.  
Pourquoi pour Vellum : Aucun chiffre de PERFORMANCE.md ne vient d'un appareil (docs/PERFORMANCE.md:276-296) ; Studio ne reproduit ni la mémoire ni la chauffe (page test-on-hardware, lue par l'audit précédent).  
Coût : Prix d'achat des appareils, non chiffré ici ; un appareil emprunté suffit. · Claude peut le piloter : non, c'est toi  
Mise en place : Jouer sur Vellum-Test avec le protocole de PERFORMANCE.md (E6-S5).  
Lien : https://create.roblox.com/docs/en-us/performance-optimization/test-on-hardware

### Au lancement

**Experience configs (ConfigService)** — Valeurs changées en direct sans republier : texte, nombre, booléen ou JSON (100 000 caractères au plus), 1 000 configs actives, propagation en 15 s à 1 min, lecture côté serveur seulement ; configs conditionnelles pour des tests A/B (pays, langue, ancienneté…).  
Pourquoi pour Vellum : Interrupteurs de la semaine de lancement (E9-S1) et calendrier d'événements sans déploiement (E17-S4).  
Coût : Aucun prix indiqué dans la documentation lue. · Claude peut le piloter : non, c'est toi  
Mise en place : Tu crées les clés dans le Creator Dashboard ; Claude écrit le module LiveConfig et ses tests.  
Lien : https://create.roblox.com/docs/production/configs

**Secrets d'expérience (HttpService:GetSecret)** — Clés rangées chez Roblox, lisibles par le serveur, qui ne s'impriment jamais, limitées à des domaines ; absentes en test local.  
Pourquoi pour Vellum : Seule façon propre de donner une clé à un puits externe (RoSentry ou Supabase, E9-S4) sans la mettre dans un dépôt public.  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Creator Dashboard > Secrets > Create Secret, par le propriétaire du jeu ; jamais collé dans le chat.  
Lien : https://create.roblox.com/docs/cloud-services/secrets

**Matchmaking configurable de Roblox** — Ajuster le poids des signaux (dont Occupancy, 2 par défaut) et créer des signaux personnalisés à partir d'attributs de serveur.  
Pourquoi pour Vellum : Regrouper les premiers joueurs sur les mêmes serveurs pour que le classé se remplisse (E10-S1, E10-S2).  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Configuration dans le Creator Hub par toi ; Claude publie l'attribut de serveur.  
Lien : https://create.roblox.com/docs/matchmaking/customize-matchmaking

**MicroProfiler (captures serveur)** — Capture du serveur, 60 images au plus, depuis la console d'une partie où tu as les droits d'édition.  
Pourquoi pour Vellum : Chiffrer le coût du tick à 12 joueurs et fixer les budgets serveur de PERFORMANCE.md (E11-S1, E7-S6).  
Coût : Gratuit. · Claude peut le piloter : non, c'est toi  
Mise en place : Console développeur (Ctrl+F9 ou Cmd+F9) > MicroProfiler > onglet Server > Begin server recording ; tu déposes le fichier dans le dépôt.  
Lien : https://create.roblox.com/docs/performance-optimization/microprofiler

**Skill xlsx** — Produire un vrai classeur Excel avec formules et graphiques.  
Pourquoi pour Vellum : Classeur d'économie à partir du CSV du simulateur de rythme, pour régler pass, Folios, quêtes et catalogue (E10-S4, E10-S11).  
Coût : Inclus. · Claude peut le piloter : oui  
Mise en place : Déjà installé.  
Lien : /Users/fouzi/.claude/skills/xlsx

**Rappels J1, J7, J30 (skill schedule)** — Tâches planifiées de Claude Code qui se lancent seules à une date.  
Pourquoi pour Vellum : Relire le Dashboard à J1, J7 et J30 après la sortie (E8-S6) et relancer les labos oubliés.  
Coût : Inclus dans Claude Code. · Claude peut le piloter : oui  
Mise en place : Tu dis « rappelle-moi à J+1 de lire le tableau de bord » après la publication ; Claude crée la tâche.  
Lien : skill anthropic-skills:schedule (installé dans Claude Code)

### Plus tard, ou en option

**Notifications d'expérience** — Notifications hors du jeu : 100 visites minimum, une par joueur et par jour, 99 caractères, joueurs de 13 ans et plus qui ont accepté ; envoi par Open Cloud ou par le paquet Luau.  
Pourquoi pour Vellum : Le seul canal natif pour faire revenir un joueur à J1 et J7 (E15-S2).  
Coût : Aucun prix indiqué dans la documentation lue. · Claude peut le piloter : non, c'est toi  
Mise en place : Tu crées les gabarits dans Engagement > Notifications une fois les 100 visites atteintes ; Claude branche l'envoi.  
Lien : https://create.roblox.com/docs/production/promotion/experience-notifications

**RoSentry (option, après l'Error Report)** — Suivi d'erreurs pour Roblox : regroupement, contexte joueur, alertes, et un serveur MCP qui laisse Claude lire les erreurs de production. Publié le 03/08/2026.  
Pourquoi pour Vellum : Si l'Error Report ne suffit plus (alertes, historique) ; puits possible de E9-S4.  
Coût : Gratuit « pour l'instant » d'après l'auteur. Le dépôt boshyxd/rosentry-public n'a pas de licence détectée par l'API GitHub : l'héberger soi-même n'est pas clairement permis. · Claude peut le piloter : oui  
Mise en place : Tu crées le compte et la clé (rangée en secret Roblox) ; Claude relit le SDK avant intégration (données envoyées, aucun nom de joueur).  
Lien : https://devforum.roblox.com/t/rosentry-performant-web-based-error-tracking-free-open-source/4774479

**Supabase (option, déjà connecté par MCP)** — Base Postgres hébergée, déjà branchée dans cet espace de travail.  
Pourquoi pour Vellum : Puits des compteurs agrégés OpsMetrics : une requête SQL répond à la décision Correct/Enforce (E9-S4).  
Coût : Offre gratuite : 500 Mo, 2 projets actifs, mise en pause après une semaine d'inactivité ; Pro à partir de 25 $ par mois. · Claude peut le piloter : oui  
Mise en place : Un projet et une table créés par Claude avec ton accord ; clé rangée en secret Roblox, jamais dans le dépôt.  
Lien : https://supabase.com/pricing

**Ads Manager de Roblox (après 30 jours de données)** — Expériences sponsorisées sur la page d'accueil et dans la recherche ; crédits achetés en Robux dès 13 ans ou par carte dès 18 ans (5 $ prélevés à la première campagne par carte).  
Pourquoi pour Vellum : Première acquisition payante une fois l'accueil et la rétention mesurés (E17-S7).  
Coût : Budget fixé par toi. · Claude peut le piloter : non, c'est toi  
Mise en place : Creator Hub > Ads Manager ; le moyen de paiement ne change plus après publication d'une campagne.  
Lien : https://create.roblox.com/docs/production/promotion/ads-manager

## 7. Sources

### Pages web lues pour cette révision (30/09/2026)

| Adresse | Ce qu'elle a établi |
|---|---|
| https://create.roblox.com/docs/production/promotion/content-maturity | Sans questionnaire, Roblox restreint la jouabilité pour tous ; chemin Configure > Questionnaire ; les quatre libellés (E1-S1). |
| https://create.roblox.com/docs/production/monetization/developer-products | Vente d'un produit d'un autre jeu coupée depuis le 30/05/2026 ; NotProcessedYet relivre au prochain passage du joueur (E2-S7, E3-S2). |
| https://create.roblox.com/docs/reference/engine/classes/DataModel | Exemple officiel : PrivateServerOwnerId ~= 0 pour un serveur privé acheté, 0 pour un serveur réservé (E4-S4). |
| https://create.roblox.com/docs/en-us/cloud/reference/features/luau-execution.md | 5 min par tâche, 10 tâches simultanées, 4 Mo ; ni physique ni scripts de la place ; accès aux DataStores ; droit `universe.place.luau-execution-session:write` ; renvoi vers place-ci-cd-demo (E5-S3). |
| https://create.roblox.com/docs/cloud/reference/features/luau-execution | Page des points d'accès, peu de détails (non utilisée comme preuve). |
| https://create.roblox.com/docs/production/analytics/custom-events | Événements seulement depuis le serveur d'un jeu publié ; jusqu'à 24 h de délai ; 100 événements au plus (E8). |
| https://create.roblox.com/docs/production/analytics/error-report | 500 erreurs et 500 avertissements uniques par tranche de 6 h ; 100 règles de regroupement ; retirer les identifiants variables (E8-S5). |
| https://create.roblox.com/docs/production/configs | ConfigService côté serveur seulement ; 15 s à 1 min ; 1 000 configs ; JSON de 100 000 caractères ; configs conditionnelles (E9-S1, E17-S4). |
| https://create.roblox.com/docs/cloud-services/secrets | HttpService:GetSecret, secrets absents en test local, limités à des domaines (E9-S4). |
| https://create.roblox.com/docs/cloud/webhooks/webhook-notifications | Webhooks Right to Erasure (UserId, GameIds) et Transaction Refunded (E20-S4, E9-S9). |
| https://create.roblox.com/docs/cloud/reference/DataStoreEntry | Get, Update, Delete Data Store Entry et List Data Store Entry Revisions (E20-S4, E9-S9). |
| https://create.roblox.com/docs/cloud/guides/data-stores | Guide Open Cloud des DataStores ; ne décrit ni suppression ni versions (non utilisé comme preuve). |
| https://create.roblox.com/docs/production/publishing/publish-experiences-and-places | Audience Limited > Playtesters pour faire jouer des testeurs sans ouvrir au public (E5-S1, E20-S2). |
| https://create.roblox.com/docs/production/monetization/private-servers | Activer et fixer le prix des serveurs privés ; rien sur leur détection par le code (E1-S3). |
| https://create.roblox.com/docs/reference/engine/classes/StudioDeviceSimulatorService | Méthodes de simulation d'appareil, toutes en Plugin Security (E6-S1, E6-S3). |
| https://devforum.roblox.com/t/new-studio-testing-apis-and-assistant-improvements/4657854 | StudioTestService (8 clients), VirtualInput, StudioDeviceSimulatorService, annoncés le 28/05/2026, pilotables par script et par MCP (E6). |
| https://create.roblox.com/docs/studio/mcp | Outils du MCP de Studio et chemin d'activation ; la page ne parle pas de l'ancien serveur open source (E6-S1). |
| https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993 | Server Authority sorti le 09/07/2026 ; règle StreamingEnabled ; BindToSimulation et InputAction ; emotes personnalisées non prises en charge (E4-S11). |
| https://create.roblox.com/docs/performance-optimization/microprofiler | Capture serveur de 60 images au plus, depuis la console, avec droits d'édition (E11-S1). |
| https://create.roblox.com/docs/production/promotion/experience-notifications | 100 visites, 1 par jour, 99 caractères, 13 ans et plus, Engagement > Notifications (E15-S2). |
| https://create.roblox.com/docs/production/promotion/ads-manager | Expériences sponsorisées ; crédits en Robux dès 13 ans ou par carte dès 18 ans (E17-S7). |
| https://docs.github.com/en/actions/deployment/targeting-different-environments/managing-environments-for-deployment | Environnements, relecteurs obligatoires, secrets par environnement ; en dépôt privé, réservé aux offres payantes (E2-S7). |
| https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches | Protections possibles d'une branche (checks, relectures) ; la page ne dit pas clairement quelles offres (E2-S2). |
| https://github.com/pricing | GitHub Team à 4 $ par utilisateur et par mois ; en privé, l'offre gratuite n'a pas les règles de protection (E1-S3). |
| https://devforum.roblox.com/t/rosentry-performant-web-based-error-tracking-free-open-source/4774479 | RoSentry, gratuit « pour l'instant », serveur MCP, publié le 03/08/2026. |
| https://devforum.roblox.com/t/bloxlink-a-roblox-discord-bot/758400 | Bloxlink : liaison des comptes et rôles selon groupe, passes, badges ; aucun prix sur la page. |
| https://supabase.com/pricing | Offre gratuite (500 Mo, 2 projets, pause après une semaine) et Pro à 25 $ par mois. |
| https://www.audacityteam.org/download/ | Audacity 4.0.0, gratuit, macOS Apple Silicon et Intel. |

Adresses essayées qui ont répondu 404, donc non utilisées : `create.roblox.com/docs/cloud/reference/features/data-stores`, `create.roblox.com/docs/production/publishing/publish-experiences`, `create.roblox.com/docs/production/promotion/thumbnail-personalization`, `create.roblox.com/docs/production/promotion/experience-thumbnails`.

### Pages lues par l'audit précédent (même semaine), reprises sans relecture

| Adresse | Ce qu'elle a établi |
|---|---|
| https://create.roblox.com/docs/production/analytics/custom-fields | Seules les clés CustomField01 à 03 sont lues ; valeurs en texte ; 8 000 combinaisons au plus (E8-S2, E8-S7). |
| https://create.roblox.com/docs/production/analytics/funnel-events | LogOnboardingFunnelStepEvent et LogFunnelStepEvent, étapes contiguës, côté serveur (E8-S3, E14-S1). |
| https://create.roblox.com/docs/production/analytics/economy-events | Événements d'économie et leurs trois champs personnalisés (E8-S1). |
| https://create.roblox.com/docs/reference/engine/classes/AnalyticsService | Signatures des fonctions d'analytique (E8). |
| https://create.roblox.com/docs/matchmaking/scoring | Poids par défaut (Occupancy 2) ; les serveurs pleins sont favorisés (E10-S1). |
| https://create.roblox.com/docs/matchmaking/customize-matchmaking | Poids réglables, 2 signaux personnalisés et 5 attributs de serveur au plus (E10-S1, E10-S2). |
| https://create.roblox.com/docs/matchmaking/attributes-and-signals | MatchmakingService:SetServerAttribute (E10-S2). |
| https://create.roblox.com/docs/reference/engine/classes/Players#BanAsync | Champs de BanAsync (E13-S1). |
| https://create.roblox.com/docs/scripting/events/remote | Messages de remote non écoutés mis en file puis jetés (E9-S5). |
| https://create.roblox.com/docs/en-us/projects/server-authority.md | AuthorityMode = Server, BindToSimulation, InputAction (E4-S11, E13-S3). |
| https://create.roblox.com/docs/en-us/performance-optimization/test-on-hardware | Ce que Studio ne reproduit pas d'un vrai appareil (E6-S5). |
| https://create.roblox.com/docs/reference/engine/classes/SocialService | Groupes d'amis (PartyId) pour former les équipes (E21-S1). |
| https://www.roblox.com/games/10449761463/The-Strongest-Battlegrounds | Roue d'emotes sur B dans le battleground de référence (E21-S3). |

### Vérifications faites dans le dépôt (lecture seule, 30/09/2026)

| Commande ou fichier | Résultat |
|---|---|
| `git rev-list --count origin/main..HEAD` ; `git diff --shortstat origin/main...HEAD` | 266 commits ; 352 fichiers, +74 117 / −7 894 |
| `git diff --name-only origin/main...HEAD`, groupé par dossier | tests 99, src/ui 68, docs 54, src/shared 49, src/server 40, src/client 20 |
| `lune run tests/run` | 1 785 réussis, 0 échec, 121 fichiers de spec |
| `gh repo view` ; `gh api …/branches/main/protection` | dépôt PUBLIC ; « Branch not protected » |
| `gh api repos/Roblox/place-ci-cd-demo` ; `gh api repos/jsdotlua/jest-lua/releases/latest` ; `gh api repos/boshyxd/rosentry-public` | archivé, dernier envoi 17/09/2024, MIT ; v3.10.0 du 23/12/2024 ; aucune licence détectée |
| `assets/roblox-assets.lock.json` | 91 assets : 89 Approved, 2 Reviewing ; 55 fichiers .wav |
| `src/shared/Config/CosmeticConfig.luau`, `ShopConfig.luau:17` | 41 cosmétiques ; rotation 2/2/1/1 par jour |
| `MonetizationService/Receipts.luau:132-139`, `ShopService.luau` (achat en Folios), `MonetizationService/init.luau:46` | R11, R12 et R8 toujours présents |
| `DataService.luau:187` et `:237` | magasin legacy et AddUserId : les données d'un joueur vivent à plusieurs endroits |
| `.github/workflows/ci.yml:29`, `scripts/setup.sh`, `rokit.toml:9` | types Roblox pris sur la branche main de luau-lsp alors que l'outil est en 1.69.0 |
| `.github/workflows/publish.yml` | un seul jeu de secrets, aucune porte de sortie |
| `docs/DECISIONS.md` D-138 à D-140, `docs/PROGRESS.md:173, 363, 373, 374, 383, 384, 394, 395, 409-413, 422, 436, 454, 475` | dettes de combat, labos et vérifications encore dus |
