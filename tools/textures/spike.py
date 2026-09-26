"""The ink spike: one stroke flicked straight up off the page, thick at its root and sharp at its tip.

The recipe's "sharp, tapered shapes" (docs/vfx/, D-119) had nothing to be drawn with. A spark is a dash
seen from twenty studs; the brush stroke stretched onto a square stood on end was, in the lab, a grey
smudge. This is the missing shape: a serif struck upright, a spurt of ink, the point of a blow.

It is drawn for a Sprite turned to the camera and grown from nothing. The ROOT SITS ON THE MIDDLE LINE of
the image and the lower half is empty: the plane is centred on the floor, so its lower half is under the
page and whatever the plane grows to, what shows is the spike rising out of the floor, root first.

The body is a wedge whose half-width falls as a power of the height (a spike, not a triangle: the flanks
are concave, so it reads as flicked rather than cut), leaning a little off vertical so it is a gesture
and not a column. The edges go dry the way the brush stroke's ends do -- a fibre field cut at a rising
threshold -- so the silhouette breaks into bristles near the tip instead of fading.

    python3 tools/textures/spike.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, box_blur, clamp, fbm, output_dir, report, smootherstep01, write_white_alpha

SIZE = 256
SEED = 0x5E_21F

# The root, on the middle line, and the tip, near the top edge.
ROOT_Y = 0.5
TIP_Y = 0.035
# Half-width at the root, as a share of the image: a fifth of the height of the spike each side.
ROOT_HALF_WIDTH = 0.1
# Half-width falls as t ** TAPER from the root (t = 1) to the tip (t = 0): above one the flanks are
# concave and most of the height is the thin end.
TAPER = 1.6
# How far the tip leans off the root's vertical, as a share of the image, along a smooth curve.
LEAN = 0.05
# The dry edge: bristle noise stretched along the spike, and how much of the width it may eat.
FIBRE_STRETCH = 9.0
DRY_EDGE = 0.35
# The root spreads into a small pool on the page before it vanishes under it.
ROOT_POOL = 0.035


def _build() -> Canvas:
    root_y = SIZE * ROOT_Y
    tip_y = SIZE * TIP_Y
    height = root_y - tip_y
    centre_x = SIZE * 0.5

    def sample(x: int, y: int) -> float:
        px = x + 0.5
        py = y + 0.5
        if py > root_y + SIZE * ROOT_POOL:
            return 0.0
        # t: 0 at the tip, 1 at the root.
        t = clamp((py - tip_y) / height)
        axis = centre_x + SIZE * LEAN * (1.0 - t) ** 2
        half_width = SIZE * ROOT_HALF_WIDTH * t**TAPER + 0.8
        if py > root_y:
            # Below the root: the pool it stands in, rounding off quickly.
            below = (py - root_y) / (SIZE * ROOT_POOL)
            half_width = SIZE * ROOT_HALF_WIDTH * (1.0 + 0.3 * below) * math.sqrt(max(0.0, 1.0 - below**2))
        across = abs(px - axis) / max(half_width, 1e-6)
        if across >= 1.0:
            return 0.0
        # Bristles: a fibre field stretched along the spike, cutting into the edge more toward the tip.
        fibre = fbm(px / 3.0, py / FIBRE_STRETCH, SEED, octaves=3)
        dryness = DRY_EDGE * (1.0 - t) ** 0.7
        edge = 1.0 - across
        if edge < dryness and fibre < 0.5 + 0.5 * (dryness - edge) / max(dryness, 1e-6):
            return 0.0
        return smootherstep01(min(1.0, edge * half_width / 1.5))

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    canvas = box_blur(canvas, radius=1, passes=1)
    canvas.fade_border(2.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "ink_spike.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
