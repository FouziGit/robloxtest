"""One brush stroke: thick through the middle, dry at both ends.

The wide sprite of the set, and the one that carries the direction most directly. docs/ART_BIBLE.md
asks for brush marks rather than gradients, and a stroke like this is what a Beam is textured with
when a glyph draws itself in the air -- so this single asset is the difference between a spell that
looks painted and a spell that looks like a laser.

The failure mode to avoid is a smooth double-tapered lozenge with a solid bright core, which is a
chrome lens flare and is indistinguishable from the default sprite of every other Roblox game. Two
numbers cause it, and neither of them is the symmetry:

  * THICKNESS. Fifteen to one, not seven. A mark any wider is a shape with a stroke's silhouette
    rather than a stroke, and it is the fat profile that makes a tapered mark read as a lens.
  * A SOLID BODY. A brush is a bundle of hairs, so discrete bristle lanes run the length of this one,
    each with its own weight and its own gaps, over a noise field stretched fifty-three to one. Where a real
    brush is at its fullest the hairs still show, and the eye reads a gap between hairs faster than it
    reads any amount of noise.

Both ends then go dry by THRESHOLD, not by fading: as the ink runs out the fibre field is cut at a
rising level, so only the strongest hairs survive and the mark breaks into separate streaks.
Multiplying the alpha down instead gives a stroke that dissolves evenly, which is a fade with extra
steps -- and a fade is exactly what this texture exists to avoid.

The head is left slightly wetter than the tail, and the widest point sits a hair before centre. A
stroke that is exactly symmetric reads as a printed bar, because printed bars are the only symmetric
marks anyone has seen; a few percent of asymmetry is enough to break that without turning the sprite
into a one-way mark that cannot be mirrored.

    python3 tools/textures/brush.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import (
    Canvas,
    box_blur,
    clamp,
    fbm,
    output_dir,
    report,
    smootherstep01,
    write_white_alpha,
)

WIDTH = 512
HEIGHT = 128
SEED = 0xB0_05

# Peak half-thickness in pixels: 17 against 512 long is about fifteen to one, which is a stroke.
HALF_THICKNESS = 17.0
# The bow of the spine. A straight axis reads as a printed bar, and a hand does not draw straight.
BOW = 7.0
EDGE_FEATHER = 1.6

# The widest point, and how the mark builds to it and leaves it. Powers below one hold the thickness
# up across the middle instead of letting it fall away from a single peak, which is what makes this a
# stroke with a body rather than two tapers meeting at a point.
PEAK_AT = 0.46
HEAD_POWER = 0.42
TAIL_POWER = 0.48

# Discrete bristles.
BRISTLE_COUNT = 23
BRISTLE_SHARPNESS = 2.1
BRISTLE_DEPTH = 0.78

# The fibre field under the lanes: three cells along the stroke against forty across it, so the noise
# is stretched more than ten to one and reads as hairs rather than as blotches. Three octaves, because
# a single octave of value noise shows its lattice as rectangles the moment it is thresholded.
FIBRE_CELLS_X = 3.0
FIBRE_CELLS_Y = 40.0
FIBRE_OCTAVES = 3
FIBRE_DEPTH = 0.62

# The darkest the inside of the mark ever gets. Not zero: a gap that goes fully transparent turns the
# stroke into separate slivers rather than one mark with hairs in it.
FLOOR = 0.34

# How far out from the middle the ink starts running out, and how high the cut can rise. Not to 1.0: a
# threshold that reaches the top of the noise range erases the tips outright and the stroke ends in
# mid-air rather than running out.
DRY_START = 0.34
DRY_DEPTH = 0.92
# Softness of the cut, in noise units. Sharper than this and the hairs get aliased edges.
DRY_SOFTNESS = 0.13
# The head keeps a little more ink than the tail, the way a stroke does that is put down before it is
# lifted. Both ends still break into hairs; this only decides which one breaks first.
HEAD_WETNESS = 0.86


def _thickness(u: float) -> float:
    """Half-thickness at `u` along the stroke: zero at both ends, widest at PEAK_AT."""
    if u <= 0.0 or u >= 1.0:
        return 0.0
    if u < PEAK_AT:
        return HALF_THICKNESS * (u / PEAK_AT) ** HEAD_POWER
    return HALF_THICKNESS * (1.0 - (u - PEAK_AT) / (1.0 - PEAK_AT)) ** TAIL_POWER


def _bristle_lanes() -> list[tuple[float, float]]:
    """Each lane gets a position across the stroke and a weight of its own, drawn once from the noise
    field so the hairs stay put along the whole mark instead of crawling."""
    lanes = []
    for index in range(BRISTLE_COUNT):
        offset = (index + 0.5) / BRISTLE_COUNT * 2.0 - 1.0
        lanes.append((offset, fbm(index * 0.61, 7.3, SEED ^ 0x51, octaves=2)))
    return lanes


def _build() -> Canvas:
    axis = HEIGHT * 0.5
    fibre_x = FIBRE_CELLS_X / WIDTH
    fibre_y = FIBRE_CELLS_Y / HEIGHT
    lanes = _bristle_lanes()

    def sample(x: int, y: int) -> float:
        # Divided by the width, not by the last index: u must stay strictly inside 0..1 or the powers
        # in _thickness are taken of a negative number.
        u = (x + 0.5) / WIDTH
        thickness = _thickness(u)
        if thickness <= 0.0:
            return 0.0
        # Position across the stroke, normalised to its local width, so the lanes splay with the mark
        # instead of crowding together at the tips.
        across = (y + 0.5 - (axis - math.sin(u * math.pi) * BOW)) / thickness
        body = smootherstep01((1.0 - abs(across)) * thickness / EDGE_FEATHER)
        if body <= 0.0:
            return 0.0

        lane = 0.0
        for offset, weight in lanes:
            nearness = 1.0 - min(abs(across - offset) * BRISTLE_COUNT * 0.5, 1.0)
            if nearness > 0.0:
                lane = max(lane, nearness**BRISTLE_SHARPNESS * weight)

        fibre = fbm(x * fibre_x, y * fibre_y, SEED, octaves=FIBRE_OCTAVES)
        grain = clamp(lane * BRISTLE_DEPTH + fibre * FIBRE_DEPTH)

        # Distance from the middle, so the cut rises toward both tips rather than only toward one.
        from_middle = abs(u - PEAK_AT) / max(PEAK_AT, 1.0 - PEAK_AT)
        dryness = smootherstep01((from_middle - DRY_START) / (1.0 - DRY_START))
        cut_level = dryness * DRY_DEPTH * (HEAD_WETNESS if u < PEAK_AT else 1.0)
        cut = smootherstep01((grain - cut_level) / DRY_SOFTNESS)
        return body * cut * (FLOOR + (1.0 - FLOOR) * grain)

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
