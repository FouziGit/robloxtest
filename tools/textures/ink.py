"""The ink blot, used as the residue decal a glyph leaves on the ground.

Art bible rule 5: every impact leaves a mark that fades, so the world remembers for a few seconds.
This is that mark. It is a filled shape with a feathered edge rather than a soft blob, because a
decal that is soft all the way through reads as a light patch on the floor, and this has to read as
something spilled.

The outline is irregular by construction: the radius is modulated by noise sampled around a circle, so
no two directions match and nothing about it says "circle scaled by a number". A few satellite
droplets sit outside the body -- ink that landed a moment after the rest.

    python3 tools/textures/ink.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import (
    Canvas,
    Rng,
    circle_noise,
    output_dir,
    report,
    smootherstep01,
    stamp_radial,
    write_white_alpha,
)

SIZE = 256
SEED = 0x1B_10

# Body radius before the lobes, which swing it between 0.72x and 1.32x. That upper bound plus the
# droplets is what fixes the base at a third of the sprite instead of half.
BODY_RADIUS = 0.33
LOBE_LOW = 0.72
LOBE_SPAN = 0.60

# Feather in pixels. Wide enough to anti-alias and to look absorbed into the surface, narrow enough
# that the blot still has an outline.
FEATHER = 7.0

DROPLET_COUNT = 6
DROPLET_SEED = 0x1B_11


def _build() -> Canvas:
    half = SIZE * 0.5
    base = SIZE * BODY_RADIUS

    def sample(x: int, y: int) -> float:
        px = x + 0.5 - half
        py = y + 0.5 - half
        lobe = circle_noise(math.atan2(py, px), SEED)
        edge = base * (LOBE_LOW + LOBE_SPAN * lobe)
        return smootherstep01((edge - math.hypot(px, py)) / FEATHER)

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)

    # Droplets are placed by angle rather than at random in the square, so none of them lands on top
    # of the body where it would be invisible, and none lands in the corner where the border fade
    # would eat half of it.
    rng = Rng(DROPLET_SEED)
    for index in range(DROPLET_COUNT):
        angle = (index + rng.uniform(0.12, 0.88)) * (2.0 * math.pi / DROPLET_COUNT)
        lobe = circle_noise(angle, SEED)
        distance = base * (LOBE_LOW + LOBE_SPAN * lobe) + rng.uniform(4.0, 22.0)
        radius = rng.uniform(2.0, 7.0)
        centre = (half + math.cos(angle) * distance, half + math.sin(angle) * distance)
        stamp_radial(canvas, centre, radius)

    canvas.fade_border(8.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "ink_blot.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
