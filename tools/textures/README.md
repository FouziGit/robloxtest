# Textures générées

Les douze PNG de `assets/textures/` ne viennent de nulle part : ils sont **écrits par les scripts de ce
dossier**. Aucun asset de la boîte à outils Roblox, aucune image téléchargée, aucun pack sous licence
floue — `docs/JUICE_PLAN.md` le dit en une ligne, la provenance douteuse est une cause classique de
suppression de jeu, et `docs/ART_BIBLE.md` part de toute façon du principe qu'il n'y a pas d'artiste
sur ce projet.

## Ce que chaque texture sert à faire

| Fichier | Taille | À quoi ça sert |
|---|---|---|
| `smoke_soft.png` | 256×256 | Fumée, poussière, nuées d'encre. Le bord est bruité : un dégradé propre se lit comme une lueur, et la lueur appartient à la direction rejetée. |
| `dust_mote.png` | 64×64 | Grain de poussière, étincelle froide, particule d'ambiance. Volontairement propre — à 64 pixels, du bruit n'est que de la saleté. |
| `spark_streak.png` | 128×128 | Étincelles. Tête à gauche, traîne vers +X, parce que Roblox étire une particule sur son axe X : dessinée dans l'autre sens, l'émetteur tire à l'envers. |
| `ink_blot.png` | 256×256 | Décalque de résidu au sol. Règle 5 de l'`ART_BIBLE` : chaque impact laisse une trace qui s'efface. |
| `crack_web.png` | 512×512 | Marque d'impact lourd au sol. Fissures qui poussent et se ramifient, jamais des rayons réguliers. |
| `shockwave_ring.png` | 512×512 | Onde de choc, agrandie image par image. Le fondu intérieur est trois fois plus long que l'extérieur : c'est ce qui donne un sens de déplacement au sprite lui-même. |
| `paper_grain.png` | 512×512 | Grain des surfaces du monde. **Seule texture qui se répète** : périodique par construction, flou circulaire, aucune couture. |
| `seal_ring.png` | 512×512 | Le sceau tracé sous le lanceur pendant l'Anticipation. Deux anneaux et des graduations, dessinés au trait et non au compas. |
| `brush_stroke.png` | 512×128 | Coup de pinceau : épais au milieu, sec aux deux bouts. C'est ce qui texture les `Beam` quand un glyphe se dessine. |
| `gradient_radial.png` | 256×256 | Dégradé blanc centre → transparent bord. Brique de base des lueurs et des halos. |
| `gradient_linear.png` | 256×256 | Dégradé blanc en +X → transparent en -X. « Linéaire » désigne l'axe, pas la courbe : les deux dégradés sont en smootherstep, parce qu'une rampe réellement linéaire laisse une arête visible là où elle rejoint l'aplat. |
| `explosion_flipbook.png` | 1024×1024 | Planche 8×8 de 64 images de 128 px, pour `ParticleEmitter` en `FlipbookLayout.Grid8x8` (lecture gauche → droite, haut → bas). Une floraison d'encre qui s'ouvre, se déchire en quartiers et se disperse. |

## Régénérer

```bash
python3 tools/textures/generate_all.py   # les douze
python3 tools/textures/smoke.py          # une famille seule
```

Aucune installation. **Bibliothèque standard uniquement** : pas de Pillow, pas de numpy, même s'ils
sont présents sur la machine de développement. L'écriture PNG (zlib + struct, RGBA8 non entrelacé) et
les maths partagées — bruit de valeur, fbm, courbes, flou, composition, tracé de traits — tiennent
dans `vellum_png.py`. Un pipeline qui exige un `pip install` avant de pouvoir reconstruire un asset est
un pipeline qui cesse de fonctionner le jour où personne ne se souvient de la version.

`generate_all.py` affiche, pour chaque fichier, les dimensions **relues dans l'en-tête IHDR du PNG**,
la taille et l'empreinte SHA-256. Deux exécutions successives doivent produire exactement le même
tableau.

## Les règles que le pipeline tient

- **Blanc + alpha.** Le RVB est fixé à 255 et toute l'image vit dans le canal alpha. Règle 2 de
  l'`ART_BIBLE` : un glyphe = un pigment = une couleur. Une texture est livrée une fois et teintée cinq
  fois par `ParticleEmitter.Color` ou `ImageColor3`. Cinq copies colorées de chaque asset, ce serait
  cinq fois le téléchargement et cinq occasions qu'une d'elles dérive de la palette.
- **Déterminisme.** Toute source aléatoire est semée explicitement, via le SplitMix64 de
  `vellum_png.py` plutôt que via `random`. Un générateur dont la sortie bouge d'une exécution à l'autre
  transforme chaque commit en un diff binaire que personne ne peut relire.
- **PNG commités.** Les images sont dans git, donc la CI ne régénère jamais rien et n'a besoin de rien.
  Les pixels sont reproductibles partout ; les octets compressés dépendent de la version de zlib de la
  machine, ce qui est précisément la raison pour laquelle on commite le résultat plutôt que la recette.
- **400 Ko par fichier.** Plafond appliqué par `generate_all.py`, qui sort en code d'erreur au-delà. Un
  asset qui dépasse est réduit, pas livré. Le plus gros aujourd'hui est la planche d'explosion, à
  181 Ko.
- **Un script par famille.** Chaque script est autonome et n'importe que `vellum_png`.

## Ajouter une texture

Créer `tools/textures/<famille>.py`, exposer `generate() -> list[Path]` qui écrit dans
`vellum_png.output_dir()`, et l'ajouter à `MODULES` dans `generate_all.py`. Ne pas dupliquer de maths :
si une courbe ou un tracé sert à deux générateurs, il va dans `vellum_png.py`.
