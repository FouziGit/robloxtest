"""The seal: two concentric rings with tick marks between them.

This is the frame a glyph is drawn inside -- the thing that appears under a caster's feet during
Anticipation and closes when the spell fires. docs/ART_BIBLE.md calls the spells seals that hold for a
breath and tear what they are pointed at when they close, so this had to be a drawn object and not a
UI ornament.

Everything here is made of short strokes rather than of circles: the radius wobbles by about one
percent around the ring, and the stroke's weight rises and falls as it goes round, the way a loaded
brush does as it dries. Both effects are small enough that nobody will name them and large enough that
the ring stops looking like a Photoshop shape.

Tick marks are evenly spaced and every fourth is longer and reaches further in. Evenly spaced because
this is the one object in the set that is supposed to look deliberate -- it was inscribed by someone.

    python3 tools/textures/seal.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, circle_noise, draw_segment, output_dir, report, write_white_alpha

SIZE = 512
SEED = 0x5E_A1

OUTER_RADIUS = SIZE * 0.450
INNER_RADIUS = SIZE * 0.370
OUTER_HALF_WIDTH = 3.0
INNER_HALF_WIDTH = 1.4

# Segments per ring. At 288 each chord is about five pixels of a 230-pixel circle, which is under the
# stroke width, so the polygon cannot show as facets.
RING_SEGMENTS = 288
RING_WOBBLE = 0.012

# How faint the driest part of a stroke gets. Below about 0.7 the ring starts to look broken rather
# than drawn.
DRY_LOW = 0.74

TICK_COUNT = 32
MAJOR_EVERY = 4
TICK_HALF_WIDTH = 1.5
MAJOR_HALF_WIDTH = 2.2
# Ticks stop short of both rings, so the marks read as separate strokes instead of welding the two
# rings into one solid band.
TICK_GAP = 7.0
MAJOR_INSET = 16.0


def _draw_ring(canvas: Canvas, radius: float, half_width: float, seed: int) -> None:
    centre = SIZE * 0.5
    step = 2.0 * math.pi / RING_SEGMENTS
    points = []
    for index in range(RING_SEGMENTS + 1):
        angle = index * step
        wobbled = radius + radius * RING_WOBBLE * (circle_noise(angle, seed) * 2.0 - 1.0)
        points.append((centre + math.cos(angle) * wobbled, centre + math.sin(angle) * wobbled))
    for index in range(RING_SEGMENTS):
        # Angle 0 and angle 2*pi land on the same point of the noise circle, so the ring closes on
        # itself with no step in either the radius or the weight.
        weight = DRY_LOW + (1.0 - DRY_LOW) * circle_noise(index * step, seed + 17, radius=4.0)
        draw_segment(canvas, points[index], points[index + 1], (half_width, half_width), weight)


def _draw_ticks(canvas: Canvas) -> None:
    centre = SIZE * 0.5
    for index in range(TICK_COUNT):
        angle = index * (2.0 * math.pi / TICK_COUNT)
        major = index % MAJOR_EVERY == 0
        start = INNER_RADIUS - MAJOR_INSET if major else INNER_RADIUS + TICK_GAP
        end = OUTER_RADIUS - TICK_GAP
        half_width = MAJOR_HALF_WIDTH if major else TICK_HALF_WIDTH
        cosine, sine = math.cos(angle), math.sin(angle)
        draw_segment(
            canvas,
            (centre + cosine * start, centre + sine * start),
            (centre + cosine * end, centre + sine * end),
            (half_width, half_width * 0.62),
            circle_noise(angle, SEED + 41, radius=5.0) * (1.0 - DRY_LOW) + DRY_LOW,
        )


def _build() -> Canvas:
    canvas = Canvas(SIZE, SIZE)
    _draw_ring(canvas, OUTER_RADIUS, OUTER_HALF_WIDTH, SEED)
    _draw_ring(canvas, INNER_RADIUS, INNER_HALF_WIDTH, SEED + 3)
    _draw_ticks(canvas)
    canvas.fade_border(6.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "seal_ring.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
