"""Runs every generator and reports what landed on disk.

    python3 tools/textures/generate_all.py

Each generator is also runnable on its own; this exists so that a change to vellum_png.py can be
checked against every texture in one go, and so that the report below can be diffed between two
runs. That diff is the determinism test: the digests come from the written bytes, so if any generator
has picked up an unseeded source of randomness, two consecutive runs disagree and it shows here.

Cheapest first, so a mistake in the shared module surfaces in a fraction of a second rather than after
the flipbook has been drawn.
"""

from __future__ import annotations

import brush
import cracks
import explosion
import gradients
import ink
import paper
import scrap
import seal
import shockwave
import smoke
import sparks
import spike
import telegraph
from vellum_png import MAX_BYTES, report

MODULES = (smoke, sparks, spike, ink, scrap, gradients, cracks, shockwave, paper, seal, brush, telegraph, explosion)


def main() -> int:
    paths = []
    for module in MODULES:
        paths.extend(module.generate())
    over_budget = report(paths)
    if over_budget:
        print(f"\n{over_budget} file(s) above the {MAX_BYTES} byte ceiling -- reduce them, do not ship them.")
        return 1
    print(f"\n{len(paths)} textures written, all within {MAX_BYTES} bytes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
