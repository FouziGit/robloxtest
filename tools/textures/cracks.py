"""The crack web: the ground mark under a heavy impact.

Cracks are grown, not drawn. A branch walks outward in short segments, each one turned a little from
the last, and every few segments it can throw a child off at an angle. That is the only way to get the
uneven spacing real fracture has; laying down eight straight spokes gives a wheel, and a wheel is
instantly readable as a decal someone generated.

Widths taper along every branch and children start thinner than their parent, so the eye follows the
web outward from the centre -- which is where the impact was, and the one thing the mark has to say.

Strokes composite by maximum (see vellum_png.draw_segment): summing them would make every junction a
bright dot and the centre a solid blob.

    python3 tools/textures/cracks.py
"""

from __future__ import annotations

import math
from collections import namedtuple
from pathlib import Path

from vellum_png import Canvas, Rng, draw_segment, output_dir, report, stamp_radial, write_white_alpha

SIZE = 512
SEED = 0xC2_AC

# Hard limit on how far a branch may travel from the centre. Past this the border fade would clip a
# crack mid-stroke, which reads as a cut rather than an end.
MAX_RADIUS = SIZE * 0.455

MAIN_BRANCHES = 9
SEGMENTS_PER_BRANCH = 8
MAIN_LENGTH = SIZE * 0.48
MAIN_HALF_WIDTH = 1.9

# Radians a branch may turn per segment. Small: a crack wanders, it does not meander, and above about
# 0.3 the web starts to look like roots.
TURN = 0.20

# A child leaves at this much of an angle, keeps this much of what is left of its parent, and starts
# this much thinner. Depth is capped at two because a third generation at this resolution is under a
# pixel wide and only shows up as noise.
BRANCH_CHANCE = 0.42
BRANCH_ANGLE = (0.42, 0.95)
BRANCH_LENGTH = 0.5
BRANCH_WIDTH = 0.55
MAX_DEPTH = 2

# The impact point itself. Small and faint on purpose -- it tells the eye where the web started
# without becoming the subject of the decal.
CORE_RADIUS = SIZE * 0.028
CORE_STRENGTH = 0.55

Branch = namedtuple("Branch", "origin angle length half_width depth")


def _walk(canvas: Canvas, rng: Rng, branch: Branch) -> list[Branch]:
    """Draws one branch segment by segment and returns the children it threw off."""
    centre = SIZE * 0.5
    x, y = branch.origin
    angle = branch.angle
    step = branch.length / SEGMENTS_PER_BRANCH
    children: list[Branch] = []
    for index in range(SEGMENTS_PER_BRANCH):
        angle += rng.uniform(-TURN, TURN)
        next_x = x + math.cos(angle) * step
        next_y = y + math.sin(angle) * step
        if math.hypot(next_x - centre, next_y - centre) > MAX_RADIUS:
            break
        head = branch.half_width * (1.0 - index / SEGMENTS_PER_BRANCH) ** 0.8
        tail = branch.half_width * (1.0 - (index + 1) / SEGMENTS_PER_BRANCH) ** 0.8
        draw_segment(canvas, (x, y), (next_x, next_y), (max(head, 0.62), max(tail, 0.58)))
        x, y = next_x, next_y
        remaining = branch.length - step * (index + 1)
        if branch.depth < MAX_DEPTH and remaining > step and rng.random() < BRANCH_CHANCE:
            side = 1.0 if rng.random() < 0.5 else -1.0
            children.append(
                Branch(
                    origin=(x, y),
                    angle=angle + side * rng.uniform(*BRANCH_ANGLE),
                    length=remaining * BRANCH_LENGTH,
                    half_width=max(tail * BRANCH_WIDTH, 0.7),
                    depth=branch.depth + 1,
                )
            )
    return children


def _build() -> Canvas:
    canvas = Canvas(SIZE, SIZE)
    centre = SIZE * 0.5
    rng = Rng(SEED)

    # Main branches are spread evenly and then jittered, rather than placed at random: pure random
    # angles leave gaps and clusters, and a web with a bald quarter looks like a mistake.
    pending = [
        Branch(
            origin=(centre, centre),
            angle=index * (2.0 * math.pi / MAIN_BRANCHES) + rng.uniform(-0.18, 0.18),
            length=MAIN_LENGTH * rng.uniform(0.82, 1.0),
            half_width=MAIN_HALF_WIDTH * rng.uniform(0.8, 1.15),
            depth=0,
        )
        for index in range(MAIN_BRANCHES)
    ]
    while pending:
        pending.extend(_walk(canvas, rng, pending.pop()))

    stamp_radial(canvas, (centre, centre), CORE_RADIUS, CORE_STRENGTH)
    canvas.fade_border(10.0)
    return canvas


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "crack_web.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
