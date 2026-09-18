"""The paper grain, and the only texture here that has to tile.

It goes on the world surfaces -- the floor and walls of the hub and the arenas -- so it is laid down
as a repeating decal over large flat areas. Anything that repeats visibly at that scale would break
the one thing docs/ART_BIBLE.md sells: a world that looks like a page rather than like plastic.

Two conditions make the seam disappear, and both are load-bearing:

  * every octave's lattice period divides the image size, so the noise is genuinely periodic over 512
    pixels rather than merely similar at the edges (8 -> 16 -> 32 -> 64, and 128 for the speckle);
  * the blur wraps. A clamped blur flattens the outer pixels on all four sides and puts a visible
    frame around every tile -- exactly the artefact the periodic noise was there to avoid.

Alpha stays low. This is a veil over the surface colour, not a layer of its own; at full opacity it
would be scenery competing with the glyphs for attention, which rule 1 forbids.

    python3 tools/textures/paper.py
"""

from __future__ import annotations

from pathlib import Path

from vellum_png import Canvas, box_blur, fbm, output_dir, report, value_noise, write_white_alpha

SIZE = 512
SEED = 0x7A_9E

# Lattice cells across the tile. Both divide 512, and so does every octave the fbm derives from the
# first (16, 32, 64) -- the periodicity is what makes the tile seamless, so these are not free to
# round to a nicer number.
FIBRE_CELLS = 8
FIBRE_OCTAVES = 4
SPECKLE_CELLS = 128

# Fibre carries the large blotches, speckle the tooth of the paper. Weighted toward the fibre because
# pure speckle at this size reads as sensor noise on a photograph.
FIBRE_WEIGHT = 0.68

# Alpha range. Low contrast by instruction and by intent: the useful signal here is a couple of
# percent of variation over a wide surface, and anything stronger turns into visible tiling the moment
# the camera pulls back.
ALPHA_LOW = 0.05
ALPHA_HIGH = 0.24


def _build() -> Canvas:
    fibre_scale = FIBRE_CELLS / SIZE
    speckle_scale = SPECKLE_CELLS / SIZE

    def sample(x: int, y: int) -> float:
        # Sampled on the pixel index rather than its centre, so the field's period is exactly SIZE and
        # the pixel after the last one is the first one.
        fibre = fbm(x * fibre_scale, y * fibre_scale, SEED, octaves=FIBRE_OCTAVES, period=FIBRE_CELLS)
        speckle = value_noise(x * speckle_scale, y * speckle_scale, SEED + 5, period=SPECKLE_CELLS)
        value = FIBRE_WEIGHT * fibre + (1.0 - FIBRE_WEIGHT) * speckle
        return ALPHA_LOW + (ALPHA_HIGH - ALPHA_LOW) * value

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    return box_blur(canvas, radius=1, passes=1, wrap=True)


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "paper_grain.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
