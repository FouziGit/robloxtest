# Registre des assets

Tout ce que le jeu affiche ou joue et qui n'est pas du code, avec sa provenance et sa licence. La règle
de la mission : sources libres de droits **vérifiables**, ou générées par script. Vellum a choisi la
seconde pour la totalité : chaque fichier ci-dessous est produit par un script de `tools/`, commité avec
son résultat, et `scripts/check.sh` régénère et compare les octets à chaque build. La provenance de chaque
fichier est donc le script, et aucun tiers n'a de droit dessus. La **licence** est celle que le propriétaire
du dépôt lui donne — il n'y a pas de fichier `LICENSE` aujourd'hui, et ce n'est pas à ce document de le
choisir ; ce qu'il garantit est que rien ici n'en a une autre.

**Rien ici ne vient de la boîte à outils, d'une banque de sons ou d'un autre jeu.** Quatre identifiants
d'assets d'origine inconnue existaient avant la passe 5 (`rbxassetid://9114428742`, `9125703162`,
`138533090376585`, `137172521077350`) ; ils sont retirés, parce qu'une licence qu'on ne peut pas montrer
est une licence qu'on n'a pas.

## Textures — `tools/textures/` → `assets/textures/`

| Fichier | Générateur | Usage |
|---|---|---|
| `smoke_soft.png` | `smoke.py` | fumée et poussière |
| `spark_streak.png` | `sparks.py` | étincelles, orientées par la vitesse |
| `ink_blot.png` | `ink.py` | pâté d'encre, résidu des glyphes |
| `crack_web.png` | `cracks.py` | fissures d'impact |
| `shockwave_ring.png` | `shockwave.py` | onde qui s'étend |
| `paper_grain.png` | `paper.py` | grain du monde (tuilable) |
| `seal_ring.png` | `seal.py` | sceau tracé au lancement |
| `brush_stroke.png` | `brush.py` | trait de pinceau, `Beam` et traînées |
| `dust_mote.png` | `sparks.py` | motes en suspension |
| `gradient_radial.png`, `gradient_linear.png` | `gradients.py` | dégradés |
| `explosion_flipbook.png` | `explosion.py` | flipbook 8×8 d'une floraison d'encre |
| `telegraph_disc.png`, `telegraph_ring.png`, `telegraph_bar.png`, `telegraph_page.png` | `telegraph.py` | avertissements de L'Effacement, encre au bord du plan |

Déclarées dans `src/shared/Config/AssetIds.luau` avec leur taille et la portée de leur encre
(`tools/textures/check_ink.py` les mesure). Téléversement : `docs/STUDIO_SETUP.md` §7.

## Audio — `tools/audio/` → `assets/audio/`

Synthèse pure (`vellum_wav.py` : oscillateurs polynomiaux, bruit, enveloppes, filtres, délai), 16 bits
mono, déterministe — aucune fonction de la libm sur le chemin par échantillon, pour que deux machines
écrivent les mêmes octets.

| Fichiers | Générateur | Usage |
|---|---|---|
| `{cinnabar,indigo,umber,verdigris}_{attack,body,tail,impact}.wav`, `orpiment_{attack,body,impact}.wav` (19) | `pigments.py` | les voix de chaque pigment, nommées par les timelines ; l'Orpiment ne vole jamais et n'a pas de queue |
| `melee_1..3.wav`, `melee_finisher.wav`, `dash.wav`, `impact_hit.wav`, `block_start.wav`, `impact_block.wav`, `guard_break.wav` | `kit.py` | le kit de mêlée et la garde |
| `boss_arrival.wav`, `boss_warn.wav`, `boss_impact.wav`, `boss_defeat.wav` | `kit.py` | L'Effacement ; `boss_warn` est étiré à la fenêtre d'avertissement |
| `note_{pigment}.wav` (5), `sequence_resolve.wav`, `sequence_fail.wav`, `sequence_dissipate.wav` | `kit.py` | la séquence musicale |
| `ui_click.wav`, `ui_open.wav`, `ui_close.wav`, `ui_error.wav`, `claim.wav`, `level_up.wav`, `tier_up.wav`, `kill.wav`, `match_start.wav`, `match_win.wav`, `match_lose.wav`, `countdown.wav` | `kit.py` | interface et retours personnels |
| `music_hub.wav`, `music_match.wav`, `music_boss.wav` | `music.py` | les trois boucles, 16 kHz, couture par fondu |

Déclarées dans `src/shared/Config/SoundConfig.luau` avec leur durée (lue dans l'en-tête par
`tests/SoundConfig.spec.luau`). Téléversement : `docs/STUDIO_SETUP.md` §7.

## Sources tierces : ce qui pourra entrer, et pourquoi si peu

Rien de tiers n'est dans le dépôt aujourd'hui ; cette section fixe la règle **avant** que quelque chose y
entre. Vérifiée le 2026-09-23 par huit agents, dont trois contradicteurs chargés de trouver la clause qui
interdit ; le détail est dans `docs/DECISIONS.md` D-104.

Le critère qui tranche n'est pas « gratuit » ni « usage commercial autorisé » : **téléverser un fichier
sur Roblox, c'est accorder à Roblox une licence perpétuelle, sous-licenciable à tout utilisateur, qui
couvre l'entraînement de modèles d'apprentissage** (Conditions d'utilisation du 2026-05-19, accord de
licence d'upload audio). On ne peut accorder que ce qu'on a. Une licence qui interdit la sous-licence,
la redistribution isolée ou l'usage pour l'IA rend donc l'upload impossible, même quand elle autorise
les jeux vidéo.

| Retenu | Pourquoi |
|---|---|
| Quaternius *Universal Animation Library* 1 et 2 (versions Standard sur OpenGameArt) | CC0 ; combos de 3 et 4 coups découpés coup par coup. Quaternius publie depuis le 2026-08-28 une licence maison (QAL) qui interdit la redistribution isolée ; les animations Roblox sont de toute façon **Restricted** et ne peuvent plus être en usage libre, ce qui la respecte. Conserver la page et l'empreinte SHA-256 du zip au jour du téléchargement. |
| CMU Graphics Lab Motion Capture Database | « Libre pour tous usages », y compris dans un produit vendu ; seule la revente directe des données est interdite. Surtout de la locomotion et un peu de boxe. |
| Kenney (sons, *Splat Pack*, *Particle Pack*) | CC0, attribution facultative, logo réservé. |
| *100 grunge brushstrokes and splatters* (Dino0040, OpenGameArt) | CC0, aquarelles scannées par l'auteur : le meilleur accord avec la direction encre-sur-vélin. |
| Freesound, **filtré sur CC0** | Idéal pour papier, plume, pinceau. Tenir un journal de provenance par fichier (URL, auteur, date) : le site ne vérifie pas que l'auteur détient les droits. |
| Capture d'animation Roblox (se filmer, moins de 15 s) | La performance du développeur lui-même ; seul moyen d'avoir un geste de sort signature. R15 uniquement. |

| Écarté | Clause bloquante |
|---|---|
| Mixamo | Licence non sous-licenciable, usage pour l'IA interdit. |
| Sonniss GDC, ZapSplat, Mixkit, Soundsnap, Epidemic Sound | Sous-licence et/ou IA interdites. |
| Musique Mixkit, BBC Sound Effects | Jeux vidéo exclus / non commercial. |
| Unity Asset Store, Fab, contenu Epic | Sous-licence et IA interdites ; extraction à empêcher ; contenu réservé à Unreal. |
| Reallusion ActorCore, MoCap Online | Upload vers un tiers interdit ; distribution « binaire uniquement ». |
| Bandai Namco, Ubisoft La Forge, SFU | Non commerciaux, et issus de studios de jeu. |
| Truebones | Distribue gratuitement des contenus extraits de jeux commerciaux : provenance indéfendable. |
| ACCAD (CC BY 3.0) | Meilleure mocap de combat trouvée, mais CC BY 3.0 interdit la sous-licence et les mesures techniques de restriction ; les deux contradicteurs n'ont pas tranché pareil. Écarté tant que le risque n'est pas accepté explicitement. |
| ambientCG, Poly Haven | Légaux (CC0), mais photoréalistes : hors direction artistique. |

Deux contraintes Roblox à connaître avant tout upload : le **quota audio** mensuel dépend de la
vérification d'identité (les pages officielles se contredisent, de 10 à 2 000 ; le lire par l'API avant
d'envoyer les 55 sons), et une image envoyée comme *Decal* renvoie un identifiant de décalque, pas celui
de l'image que `ParticleEmitter.Texture` attend.

## Ce qui n'est pas un asset

Les polices sont celles du moteur. Le corps du boss est un bloc construit par `WorldBossService`. Les
arènes sont construites par `ArenaService`. Aucun modèle importé.
