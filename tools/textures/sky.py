"""The sky: one flat sheet of vellum, laid on all six faces of the skybox.

A Sky whose faces are empty is Roblox's default blue sky, and that blue also lights every surface
through the environment, so the whole game read teal instead of the warm paper of docs/ART_BIBLE.md.
Faces holding the page colour turned the world cream at once (a dark texture turned it dark), so the
texture is the page colour itself: Vellum #E8E0CE, opaque RGB, not the white plus alpha of the others.

Flat on purpose. Six faces have to meet without a seam, and adjacent faces do not share an edge pattern;
a paper grain of one or two levels in 255 would be invisible at sky magnification and could only add a
seam. A tileable grain, if ever wanted, is paper.py's recipe.

    python3 tools/textures/sky.py
"""

from __future__ import annotations

from pathlib import Path

from vellum_png import output_dir, report, write_solid_rgb

SIZE = 512
VELLUM = (232, 224, 206)


def generate() -> list[Path]:
    return [write_solid_rgb(output_dir() / "sky_vellum.png", SIZE, SIZE, VELLUM)]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
