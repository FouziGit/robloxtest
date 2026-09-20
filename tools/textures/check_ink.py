"""Holds AssetIds' ink measurements to the PNGs they describe.

    python3 tools/textures/check_ink.py

src/shared/Config/AssetIds.luau carries, per square texture, how far its ink reaches from the centre in
half-widths (least and most direction). tests/BossTelegraph.spec.luau reads those two numbers to prove
that a boss warning covers the floor the server damages and that a refuge never promises more floor than
the server spares. That proof is only as good as the numbers, and nothing in Lune can decode a PNG cheaply
enough to check them there -- so this does, in the same gate that already proves the PNGs match their
generators. A value in the config that no longer matches the file fails the build and names the key.

A square texture with no measurement fails too: an unmeasured texture cannot be a warning, and the way it
becomes one is somebody adding it to a timeline without coming back here.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from vellum_png import ink_reach, read_dimensions

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "src" / "shared" / "Config" / "AssetIds.luau"
TOLERANCE = 0.006

ENTRY = re.compile(
    r'^\t(\w+) = (texture|flipbook)\("([^"]+)", (\d+)(?:, (\d+))?(?:, (\d+), (\d+))?'
    r"(?:, ([\d.]+), ([\d.]+))?\)",
    re.M,
)


def main() -> int:
    source = CONFIG.read_text()
    entries = ENTRY.findall(source)
    if len(entries) < 12:
        print(f"check_ink: found only {len(entries)} entries in {CONFIG}; the pattern no longer matches")
        return 1
    failures = []
    checked = 0
    for key, kind, path, _w, _h, _c, _r, least, most in entries:
        file = ROOT / path
        width, height = read_dimensions(file)
        square = width == height and kind == "texture"
        if not least:
            if square:
                failures.append(f"{key}: {path} is square and carries no ink measurement")
            continue
        if not square:
            failures.append(f"{key}: {path} is not square, its ink reach is undefined")
            continue
        measured_least, measured_most = ink_reach(file)
        for name, declared, measured in (("least", float(least), measured_least), ("most", float(most), measured_most)):
            if abs(declared - measured) > TOLERANCE:
                failures.append(f"{key}: Ink.{name.capitalize()} is {declared:.3f} in AssetIds and {measured:.3f} in {path}")
        checked += 1
    for failure in failures:
        print(f"check_ink: {failure}")
    if failures:
        print("  Re-measure with tools/textures/vellum_png.ink_reach and paste the numbers into AssetIds.")
        return 1
    print(f"check_ink: {checked} texture(s) measured, all match AssetIds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
