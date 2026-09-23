"""A scrap of torn paper, for what a page leaves in the air when it is struck or erased.

The kill effects and the Palimpsest aura throw these (docs/DECISIONS.md D-109). A scrap is the one shape
in the game that is neither a stroke nor a blot: a flat piece of the world itself, torn off. So it is a
polygon with straight cut sides and ONE torn side, because a scrap that is torn all round reads as a
leaf or a petal, and one with a single ragged edge reads as paper -- the eye knows which side was ripped.

The torn side is a noisy line with fibres: short hairs of alpha standing off the edge, the way the pulp
of a real tear pulls apart. It is drawn at full opacity and tinted by the emitter, like every texture in
tools/textures/.

    python3 tools/textures/scrap.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import (
    Canvas,
    Rng,
    clamp,
    fbm,
    output_dir,
    report,
    smootherstep01,
    write_white_alpha,
)

SIZE = 128
SEED = 0x5C_4A

# The scrap's corners, as fractions of the sprite: a lopsided quadrilateral, longer than it is wide, so
# it tumbles visibly instead of reading as a square spinning in place.
CORNERS = ((0.24, 0.30), (0.78, 0.12), (0.90, 0.62), (0.12, 0.82))
# The side from corner 2 to corner 3 is the torn one.
TORN_SIDE = 2

# Anti-aliasing on the cut sides, in pixels: a blade leaves a clean edge.
CUT_FEATHER = 1.2
# How far the torn edge wanders inward, in pixels, and how fine its fibres are.
TEAR_DEPTH = 15.0
FIBRE_LENGTH = 5.0
FIBRE_FREQUENCY = 0.55


def _signed_distance(px: float, py: float, a: tuple[float, float], b: tuple[float, float]) -> tuple[float, float]:
    """Distance of (px, py) inside the edge a->b (positive inside, for a clockwise-in-screen polygon), and
    how far along the edge the point projects, 0 to 1."""
    ax, ay = a
    bx, by = b
    ex, ey = bx - ax, by - ay
    length = math.hypot(ex, ey)
    nx, ny = -ey / length, ex / length
    inside = (px - ax) * nx + (py - ay) * ny
    along = ((px - ax) * ex + (py - ay) * ey) / (length * length)
    return inside, along


def _build() -> Canvas:
    corners = [(x * SIZE, y * SIZE) for x, y in CORNERS]
    rng = Rng(SEED)
    fibre_seed = int(rng.uniform(1, 1_000_000))

    def sample(x: int, y: int) -> float:
        px, py = x + 0.5, y + 0.5
        coverage = 1.0
        for index in range(4):
            a = corners[index]
            b = corners[(index + 1) % 4]
            inside, along = _signed_distance(px, py, a, b)
            if index == TORN_SIDE:
                # The tear: an edge pulled inward by low-frequency noise, then roughened by fibres.
                wander = TEAR_DEPTH * fbm(along * 6.0, 0.37, SEED, octaves=4)
                fibres = FIBRE_LENGTH * fbm(along * 90.0 * FIBRE_FREQUENCY, py * 0.02, fibre_seed, octaves=2)
                edge = inside - wander + fibres
                coverage = min(coverage, clamp(smootherstep01(edge / 2.5)))
            else:
                coverage = min(coverage, clamp(smootherstep01(inside / CUT_FEATHER)))
        return coverage

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    return canvas


def generate() -> list[Path]:
    path = output_dir() / "paper_scrap.png"
    write_white_alpha(path, _build())
    return [path]


if __name__ == "__main__":
    report(generate())
