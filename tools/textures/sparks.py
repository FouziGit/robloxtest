"""The spark streak.

One bright head with a tail running to +X. Roblox stretches a particle along its velocity on the X
axis, so a sprite drawn head-left, tail-right is the one that survives being stretched: the head stays
a head at any speed and only the tail lengthens. Drawn the other way round the emitter looks like it
is firing backwards, and no amount of emitter tuning fixes it.

There is no glow and no lens flare here. docs/ART_BIBLE.md rule 1 puts every saturated pixel inside a
glyph, and a flare is the one particle that always bleeds outside the shape it came from.

    python3 tools/textures/sparks.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, box_blur, output_dir, report, smootherstep01, write_white_alpha

SIZE = 128

# The head sits a sixth in rather than on the edge, so the sprite still has a head after Roblox
# squeezes it at low speed, and the tail owns the remaining five sixths.
HEAD_X = 0.17
TAIL_X = 0.96
HEAD_RADIUS = 0.07
ROOT_HALF_WIDTH = 0.05

# The tail narrows as (1 - u) ** 1.7: faster than linear, so most of the sprite is the thin end and
# the thick part stays short enough to still read as a spark rather than a comma.
TAIL_TAPER = 1.7
# and fades as (1 - u) ** 0.6: slower than the taper, because a tail that thins and dims at the same
# rate disappears twice and ends up looking cut off.
TAIL_FADE = 0.6

# Floor on the half-width. Below about a pixel the anti-aliasing has nothing to work with and the tip
# breaks into dashes.
MIN_HALF_WIDTH = 0.7


def _build() -> Canvas:
    head_x = SIZE * HEAD_X
    tail_x = SIZE * TAIL_X
    axis_y = SIZE * 0.5
    head_radius = SIZE * HEAD_RADIUS
    root_half_width = SIZE * ROOT_HALF_WIDTH
    span = tail_x - head_x

    def sample(x: int, y: int) -> float:
        px = x + 0.5
        py = y + 0.5
        value = smootherstep01(1.0 - math.hypot(px - head_x, py - axis_y) / head_radius)
        u = (px - head_x) / span
        if 0.0 <= u <= 1.0:
            half_width = root_half_width * (1.0 - u) ** TAIL_TAPER + MIN_HALF_WIDTH
            tail = smootherstep01(1.0 - abs(py - axis_y) / half_width) * (1.0 - u) ** TAIL_FADE
            if tail > value:
                value = tail
        return value

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    canvas = box_blur(canvas, radius=1, passes=1)
    canvas.fade_border(4.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "spark_streak.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
