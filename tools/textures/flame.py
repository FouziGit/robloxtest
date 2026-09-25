"""The ink flame: a tongue of fire drawn with a brush, three licks rising off one belly.

The burning glyphs (Ligature's pools, Scorch's ring) were drawn as stains: a flat blot on the floor is a
puddle, however hot its colour, and a player reads a puddle as ground, not as fire (D-123). A flame is
something that STANDS and moves upward. Nothing in the kit could draw one -- the spike is a single rigid
stroke and the smoke is a cloud -- so this is the missing shape.

It is drawn for a ParticleEmitter kept upright to the world (VfxConfig.UprightTextures): each particle is
one tongue, born fat, rising, shrinking and swaying (the layer's Sway), and a stream of them is a fire.
The belly sits low in the image and the licks fill the top, so a particle's centre is inside the body of
the flame and the licks read above it.

Each lick is a teardrop whose half-width grows as a power of the distance from its tip (concave flanks,
a sharp point) and rounds off at the bottom; its axis bends in an S so it reads as moving air and not as
a cut-out. The edges near the tips go dry like the spike's -- a fibre field cut at a rising threshold --
so a tongue breaks into bristles where a real flame breaks into flickers.

    python3 tools/textures/flame.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, box_blur, clamp, fbm, output_dir, report, smootherstep01, write_white_alpha

SIZE = 256
SEED = 0xF1_A3E

# Each lick: its tip and the bottom of its belly (x, y as shares of the image), the belly's half-width as
# a share of the image, and how far its axis bends sideways at mid-height. The main lick, and two smaller
# ones leaning out of its belly: three points of different heights are what separates a flame from a drop.
LICKS = (
    ((0.53, 0.05), (0.50, 0.93), 0.2, 0.06),
    ((0.16, 0.34), (0.43, 0.86), 0.1, -0.07),
    ((0.84, 0.43), (0.58, 0.85), 0.09, 0.06),
)
# Half-width grows as u ** TAPER from the tip (u = 0) to the widest point: above one the flanks are concave.
TAPER = 1.5
# Where along the lick it is widest; below that it rounds off into the belly.
WIDEST = 0.78
# The dry edge: bristle noise stretched along the lick, and how much of the width it may eat at the tip.
FIBRE_STRETCH = 8.0
DRY_EDGE = 0.4


def _lick(px: float, py: float, tip: tuple[float, float], base: tuple[float, float], radius: float, bend: float) -> float:
    tip_x, tip_y = tip[0] * SIZE, tip[1] * SIZE
    base_x, base_y = base[0] * SIZE, base[1] * SIZE
    if py < tip_y or py > base_y:
        return 0.0
    # u: 0 at the tip, 1 at the bottom of the belly.
    u = (py - tip_y) / (base_y - tip_y)
    axis = tip_x + (base_x - tip_x) * u + SIZE * bend * math.sin(math.pi * u) * (1.0 - u * 0.5)
    if u <= WIDEST:
        half_width = SIZE * radius * (u / WIDEST) ** TAPER + 0.8
    else:
        below = (u - WIDEST) / (1.0 - WIDEST)
        half_width = SIZE * radius * math.sqrt(max(0.0, 1.0 - below**2))
    across = abs(px - axis) / max(half_width, 1e-6)
    if across >= 1.0:
        return 0.0
    fibre = fbm(px / 3.0, py / FIBRE_STRETCH, SEED, octaves=3)
    dryness = DRY_EDGE * clamp(1.0 - u / WIDEST) ** 0.8
    edge = 1.0 - across
    if edge < dryness and fibre < 0.5 + 0.5 * (dryness - edge) / max(dryness, 1e-6):
        return 0.0
    return smootherstep01(min(1.0, edge * half_width / 1.5))


def _build() -> Canvas:
    def sample(x: int, y: int) -> float:
        px = x + 0.5
        py = y + 0.5
        return max(_lick(px, py, tip, base, radius, bend) for tip, base, radius, bend in LICKS)

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    canvas = box_blur(canvas, radius=1, passes=1)
    canvas.fade_border(2.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "ink_flame.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
