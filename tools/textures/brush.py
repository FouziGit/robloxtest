"""One brush stroke: loaded at the start, running dry at the end.

The wide sprite of the set, and the one that carries the direction most directly. docs/ART_BIBLE.md
asks for brush marks rather than gradients, and a stroke like this is what a Beam is textured with
when a glyph draws itself in the air -- so this single asset is the difference between a spell that
looks painted and a spell that looks like a laser.

The first version of this file failed on exactly that. Its profile was thick (7:1) and symmetric with
a wide plateau, and its fibre modulated only a fifth of the body, so it rendered as a smooth
double-tapered lozenge with a solid bright core: a chrome lens flare, indistinguishable from the
default sprite of any other Roblox game. It is worth writing down because the intent was already
right and the numbers were what made it wrong.

What makes it a stroke and not a lozenge:

  * It is DIRECTIONAL. A hand puts the brush down with pressure and lifts it off; the head is fat and
    wet, the tail is thin and broken. A symmetric mark reads as a printed bar because printed bars
    are the only symmetric marks anyone has seen.
  * It is THIN. Fifteen to one, not seven. A stroke wider than that is a shape with a stroke's
    silhouette rather than a stroke.
  * Its body is never solid. Discrete bristle lanes run the length of it, each with its own weight
    and its own gaps, over a stretched noise field. Where a real brush is full, the hairs still show.
  * The tail goes dry by THRESHOLD, not by fading. As the ink runs out the fibre field is cut at a
    rising level, so only the strongest hairs survive and the mark breaks into separate streaks.
    Multiplying the alpha down instead gives a stroke that dissolves evenly, which is a fade with
    extra steps -- and a fade is exactly what this texture exists to avoid.

    python3 tools/textures/brush.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, box_blur, clamp, fbm, output_dir, report, smootherstep01, write_white_alpha

WIDTH = 512
HEIGHT = 128
SEED = 0xB0_05

# Peak half-thickness in pixels: 17 of 512 long is about fifteen to one, which is a stroke. The
# previous 36 was seven to one, which is a leaf.
HALF_THICKNESS = 17.0
# The bow of the spine. A straight axis reads as a printed bar, and a hand does not draw straight.
BOW = 7.0
EDGE_FEATHER = 1.6

# Where along the stroke the brush is heaviest. Early, because pressure is highest just after it
# lands and never returns.
PEAK_AT = 0.17
# How fast the head fills in, and how slowly the tail gives up. The asymmetry between these two is
# the single most important number in the file.
HEAD_POWER = 0.55
TAIL_POWER = 1.35

# Discrete bristles. A brush is a bundle of hairs, and the eye reads the gaps between them faster
# than it reads any amount of noise.
BRISTLE_COUNT = 23
BRISTLE_SHARPNESS = 2.1
# How much of the ink a lane's own weight contributes. With FIBRE_DEPTH below, a pixel on a strong
# lane and high in the fibre field sums past one and clamps, which is what puts a hair at full
# opacity; everything between the hairs falls back toward FLOOR.
BRISTLE_DEPTH = 0.78

# The fibre field under the lanes: one cell along the stroke against forty across it, so the noise is
# stretched forty to one and reads as hairs rather than as blotches. Three octaves, because a single
# octave of value noise shows its lattice as rectangles the moment it is thresholded.
FIBRE_CELLS_X = 3.0
FIBRE_CELLS_Y = 40.0
FIBRE_OCTAVES = 3
# The darkest the inside of the mark ever gets. Not zero: a gap that goes fully transparent turns the
# stroke into separate slivers rather than one mark with hairs in it.
FLOOR = 0.34
FIBRE_DEPTH = 0.62

# Where the ink starts running out, along the stroke, and how high the cut can rise. Not to 1.0: a
# threshold that reaches the top of the noise range erases the tip outright and the stroke ends in
# mid-air rather than running out.
DRY_START = 0.42
DRY_DEPTH = 0.92
# Softness of the cut, in noise units. Sharper than this and the hairs get aliased edges.
DRY_SOFTNESS = 0.13
# The head is wet, but not perfectly: a little dryness there keeps it from being a solid cap.
HEAD_DRYNESS = 0.12


def _thickness(u: float) -> float:
    """Half-thickness at `u` along the stroke, 0 at both ends, peaking at PEAK_AT."""
    if u <= 0.0 or u >= 1.0:
        return 0.0
    if u < PEAK_AT:
        return HALF_THICKNESS * (u / PEAK_AT) ** HEAD_POWER
    return HALF_THICKNESS * (1.0 - (u - PEAK_AT) / (1.0 - PEAK_AT)) ** TAIL_POWER


def _build() -> Canvas:
    axis = HEIGHT * 0.5
    fibre_x = FIBRE_CELLS_X / WIDTH
    fibre_y = FIBRE_CELLS_Y / HEIGHT
    # Each lane gets its own weight and its own centre, drawn once from the noise field so the result
    # stays deterministic and the lanes stay put along the whole stroke, the way hairs do.
    lanes = []
    for index in range(BRISTLE_COUNT):
        offset = (index + 0.5) / BRISTLE_COUNT * 2.0 - 1.0
        weight = fbm(index * 0.61, 7.3, SEED ^ 0x51, octaves=2)
        lanes.append((offset, weight))

    def sample(x: int, y: int) -> float:
        # Divided by the width, not by the last index: u must stay strictly inside 0..1 or the powers
        # above are taken of a negative number.
        u = (x + 0.5) / WIDTH
        thickness = _thickness(u)
        if thickness <= 0.0:
            return 0.0
        across = (y + 0.5 - (axis - math.sin(u * math.pi) * BOW)) / thickness
        body = smootherstep01((1.0 - abs(across)) * thickness / EDGE_FEATHER)
        if body <= 0.0:
            return 0.0

        # Which bristle this pixel belongs to, and how strongly. Lanes are spaced across the stroke's
        # own width, so they splay with it instead of crowding at the tip.
        lane = 0.0
        for offset, weight in lanes:
            nearness = 1.0 - min(abs(across - offset) * BRISTLE_COUNT * 0.5, 1.0)
            if nearness > 0.0:
                lane = max(lane, nearness**BRISTLE_SHARPNESS * weight)

        fibre = fbm(x * fibre_x, y * fibre_y, SEED, octaves=FIBRE_OCTAVES)
        grain = clamp(lane * 0.75 + fibre * 0.55)

        dryness = HEAD_DRYNESS + (1.0 - HEAD_DRYNESS) * smootherstep01((u - DRY_START) / (1.0 - DRY_START))
        cut = smootherstep01((grain - dryness * DRY_DEPTH) / DRY_SOFTNESS)
        # The strongest hairs have to reach full opacity somewhere, or the whole sprite is a grey wash
        # and a Beam textured with it looks like fog. Subtracting both the lane and the fibre shortfall
        # independently caps the peak at about six tenths, which is what the first pass at this did.
        # Adding them and clamping means a pixel that is both on a strong lane and high in the fibre
        # field arrives at 1, while everything between the hairs still falls to a third.
        depth = FLOOR + (1.0 - FLOOR) * clamp(lane * BRISTLE_DEPTH + fibre * FIBRE_DEPTH)
        return body * cut * depth

    canvas = Canvas(WIDTH, HEIGHT)
    canvas.fill_from(sample)
    # One pass at radius one only: enough to take the stair-stepping off a hair, not enough to close
    # the gaps between hairs, which are the whole point.
    canvas = box_blur(canvas, radius=1, passes=1)
    canvas.fade_border(3.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "brush_stroke.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
