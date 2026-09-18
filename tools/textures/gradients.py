"""The two ramps every beam, trail and glow in the pipeline is built from.

"Linear" names the axis, not the curve. Both of these are smootherstep, because a mathematically
linear ramp shows a visible line where it meets flat colour -- the eye exaggerates the discontinuity
in the first derivative -- and because art bible rule 4 bans linear interpolation outright. A Beam
textured with a truly linear ramp has a seam down the middle of it.

They are the only two textures here with no noise at all: these are the parts the other effects are
multiplied by, so any grain in them would show up in everything at once.

    python3 tools/textures/gradients.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, output_dir, report, smootherstep01, write_white_alpha

SIZE = 256


def _build_radial() -> Canvas:
    half = SIZE * 0.5
    # The radius is exactly the half-width, so alpha reaches zero on the edge midpoints by the curve
    # itself; only the corners need the border fade.
    radius = half

    def sample(x: int, y: int) -> float:
        return smootherstep01(1.0 - math.hypot(x + 0.5 - half, y + 0.5 - half) / radius)

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    canvas.fade_border(3.0)
    return canvas


def _build_linear() -> Canvas:
    last = SIZE - 1

    def sample(x: int, _y: int) -> float:
        return smootherstep01(x / last)

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    return canvas


def generate() -> list[Path]:
    target = output_dir()
    return [
        write_white_alpha(target / "gradient_radial.png", _build_radial()),
        write_white_alpha(target / "gradient_linear.png", _build_linear()),
    ]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
