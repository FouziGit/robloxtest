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
`tests/SoundConfig.spec.luau`). Téléversement : `docs/STUDIO_SETUP.md` §8.

## Ce qui n'est pas un asset

Les polices sont celles du moteur. Le corps du boss est un bloc construit par `WorldBossService`. Les
arènes sont construites par `ArenaService`. Aucun modèle importé.
