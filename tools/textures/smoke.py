"""Soft particulate: the smoke puff and the dust mote.

Both are the same thing at two scales, which is why they share a script. Every dust cloud, footfall,
residue plume and ink haze in the game is one of these two sprites tinted by the pigment that spawned
it -- Cinnabar smoke and Verdigris smoke are the same PNG.

The puff is deliberately not a clean radial gradient. A perfect gradient reads as a glow, and a glow
belongs to the genre docs/ART_BIBLE.md rejected (direction B, emissive magic in a dark world). A noisy
edge on a cream background reads as pigment dispersing in water, which is the direction that was kept.
The mote is the exception and stays clean: at sixty-four pixels, noise is just dirt.

    python3 tools/textures/smoke.py
"""

from __future__ import annotations

from pathlib import Path

from vellum_png import Canvas, box_blur, fbm, output_dir, report, smootherstep01, write_white_alpha
import math

SMOKE_SIZE = 256
DUST_SIZE = 64
SMOKE_SEED = 0x51_0C
DUST_MARGIN = 5.0

# Four lattice cells across the sprite for the silhouette and ten for the interior. Two scales is the
# minimum that reads as volume: the low one decides which way the puff bulges, the high one keeps the
# inside from looking like a flat wash.
SILHOUETTE_CELLS = 4.0
INTERIOR_CELLS = 10.0

# The lobed radius reaches 1.24x this, so 0.38 puts the widest lobe at 121px of a 128px half-width and
# the border fade covers the rest.
SMOKE_RADIUS = 0.38
SMOKE_MARGIN = 9.0

# The edge is soft over roughly half the radius. Falling off across the whole radius instead would
# make this a radial gradient with extra steps -- there is already a gradient_radial.png for that, and
# the two would be indistinguishable in game.
SMOKE_FEATHER = 0.52


def _build_smoke() -> Canvas:
    half = SMOKE_SIZE * 0.5
    radius = SMOKE_SIZE * SMOKE_RADIUS
    silhouette = SILHOUETTE_CELLS / SMOKE_SIZE
    interior = INTERIOR_CELLS / SMOKE_SIZE

    def sample(x: int, y: int) -> float:
        px = x + 0.5 - half
        py = y + 0.5 - half
        distance = math.hypot(px, py)
        lobe = fbm(x * silhouette, y * silhouette, SMOKE_SEED, octaves=3)
        edge = radius * (0.62 + 0.76 * lobe)
        body = smootherstep01((edge - distance) / (radius * SMOKE_FEATHER))
        grain = 0.52 + 0.48 * fbm(x * interior, y * interior, SMOKE_SEED + 7, octaves=4)
        return body * grain

    canvas = Canvas(SMOKE_SIZE, SMOKE_SIZE)
    canvas.fill_from(sample)
    # One pass, radius one: enough to stop the lattice showing as diamonds, not enough to sand the
    # silhouette back into the gradient this is trying not to be.
    canvas = box_blur(canvas, radius=1, passes=1)
    canvas.fade_border(SMOKE_MARGIN)
    return canvas


def _build_mote() -> Canvas:
    half = DUST_SIZE * 0.5
    radius = DUST_SIZE * 0.42

    def sample(x: int, y: int) -> float:
        distance = math.hypot(x + 0.5 - half, y + 0.5 - half)
        return smootherstep01(1.0 - distance / radius)

    canvas = Canvas(DUST_SIZE, DUST_SIZE)
    canvas.fill_from(sample)
    canvas.fade_border(DUST_MARGIN)
    return canvas


def generate() -> list[Path]:
    target = output_dir()
    return [
        write_white_alpha(target / "smoke_soft.png", _build_smoke()),
        write_white_alpha(target / "dust_mote.png", _build_mote()),
    ]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
