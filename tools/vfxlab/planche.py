#!/usr/bin/env python3
"""Assembles a VFX lab contact sheet: one glyph, its moments in columns, the cameras in rows, the effect
time on every frame.

    python3 tools/vfxlab/planche.py <sheet.json> <transcript.jsonl> <out.jpg>

sheet.json:
    {
      "title": "Brand — before",
      "frames": [
        {"capture": "brand_before_depart_game", "moment": "depart", "view": "game", "t": 0.060},
        ...
      ]
    }

Captures are pulled from the session transcript by their capture_id (captures.py). Columns follow the
order moments first appear in; rows are game, side, impact (whichever are present). A cell with no frame
stays blank. Each frame is cropped of the HUD band at the top and scaled to CELL.
"""

from __future__ import annotations

import io
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import captures  # noqa: E402  (the path is set just above)

VIEWS = ("game", "side", "impact")
CELL = (600, 250)
HEADER = 44
LABEL = 150
PAPER = (240, 236, 226)
INK = (23, 21, 15)
# The captured frame's top band holds the level bar and currency; the bottom its health and ink bars.
CROP_TOP = 0.2
CROP_BOTTOM = 0.1
# And a margin at each side, where there is only floor and sky: the effect is near the middle.
CROP_SIDE = 0.1


def font(size: int):
    for name in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def fit(image: Image.Image) -> Image.Image:
    w, h = image.size
    cropped = image.crop((int(w * CROP_SIDE), int(h * CROP_TOP), int(w * (1 - CROP_SIDE)), int(h * (1 - CROP_BOTTOM))))
    cw, ch = cropped.size
    scale = min(CELL[0] / cw, CELL[1] / ch)
    resized = cropped.resize((int(cw * scale), int(ch * scale)), Image.LANCZOS)
    cell = Image.new("RGB", CELL, PAPER)
    cell.paste(resized, ((CELL[0] - resized.size[0]) // 2, (CELL[1] - resized.size[1]) // 2))
    return cell


def build(sheet: dict, transcript: Path, out: Path) -> list[str]:
    frames = sheet["frames"]
    found = captures.find(transcript, {frame["capture"] for frame in frames})
    moments: list[str] = []
    for frame in frames:
        if frame["moment"] not in moments:
            moments.append(frame["moment"])
    views = [view for view in VIEWS if any(frame["view"] == view for frame in frames)]
    width = LABEL + CELL[0] * len(moments)
    height = HEADER * 2 + CELL[1] * len(views)
    board = Image.new("RGB", (width, height), PAPER)
    draw = ImageDraw.Draw(board)
    draw.text((12, 10), sheet.get("title", ""), fill=INK, font=font(24))
    small = font(18)
    for row, view in enumerate(views):
        draw.text((12, HEADER * 2 + row * CELL[1] + CELL[1] // 2 - 10), view, fill=INK, font=small)
    missing = []
    for column, moment in enumerate(moments):
        x = LABEL + column * CELL[0]
        times = [frame.get("t") for frame in frames if frame["moment"] == moment and frame.get("t") is not None]
        label = moment + (f"  t = {times[0]:.3f} s" if times else "")
        draw.text((x + 10, HEADER + 10), label, fill=INK, font=small)
        for frame in frames:
            if frame["moment"] != moment:
                continue
            capture = frame["capture"]
            if capture not in found:
                missing.append(capture)
                continue
            image = Image.open(io.BytesIO(found[capture][1])).convert("RGB")
            y = HEADER * 2 + views.index(frame["view"]) * CELL[1]
            board.paste(fit(image), (x, y))
    out.parent.mkdir(parents=True, exist_ok=True)
    board.save(out, quality=86)
    return missing


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        raise SystemExit(__doc__)
    sheet = json.loads(Path(argv[1]).read_text())
    missing = build(sheet, Path(argv[2]), Path(argv[3]))
    print(f"WROTE {argv[3]}")
    for capture in missing:
        print(f"MISSING {capture}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
