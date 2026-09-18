"""The shockwave ring: one stroke of a circle, scaled up over a few frames by whatever spawns it.

The falloff is deliberately asymmetric -- roughly three times longer on the inside than the outside.
A wave leaves a wake behind it and meets still air in front, so the sharp edge has to be the leading
one. Made symmetric, the same ring reads as a hoop sitting in the world rather than as something
travelling outward, and no amount of tweening fixes that because the sprite itself has no direction.

The radius wobbles by about one percent. That is under a conscious threshold, but it is the difference
between a stroke and a compass circle, and docs/ART_BIBLE.md asks for brush everywhere.

    python3 tools/textures/shockwave.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, circle_noise, output_dir, report, smootherstep01, write_white_alpha

SIZE = 512
SEED = 0x50_0C

# Radius, plus the wobble, plus the outer falloff, has to stay inside the half-width with room for the
# border fade: 0.40 + 0.005 + 0.020 of 512 is 218 against a 256 half-width.
RADIUS = SIZE * 0.40
WOBBLE = RADIUS * 0.012

# Falloff distances in pixels, outward and inward.
OUTER_FALLOFF = 7.0
INNER_FALLOFF = 21.0

# How much the stroke thins and thickens around the circle. A stroke of constant weight is a machine
# stroke.
WEIGHT_SPAN = 0.30


def _build() -> Canvas:
    half = SIZE * 0.5

    def sample(x: int, y: int) -> float:
        px = x + 0.5 - half
        py = y + 0.5 - half
        distance = math.hypot(px, py)
        angle = math.atan2(py, px)
        noise = circle_noise(angle, SEED)
        radius = RADIUS + WOBBLE * (noise * 2.0 - 1.0)
        weight = 1.0 - WEIGHT_SPAN * 0.5 + WEIGHT_SPAN * circle_noise(angle, SEED + 31, radius=3.0)
        if distance <= radius:
            return smootherstep01(1.0 - (radius - distance) / (INNER_FALLOFF * weight))
        return smootherstep01(1.0 - (distance - radius) / (OUTER_FALLOFF * weight))

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    canvas.fade_border(8.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "shockwave_ring.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
