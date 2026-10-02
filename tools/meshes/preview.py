#!/usr/bin/env python3
"""A model sheet of generated volumes, before anything is uploaded (D-114 meshes, rendered as the game will).

    python3 tools/meshes/preview.py <sheet.json> <out.png>

The sheet names the recipes to draw together and the role each is drawn in, the way a timeline layers
them: {"pigment": "Indigo", "layers": [{"recipe": "wave_body", "role": "Pigment"}, ...], "title": "..."}.
A recipe is a shipped one -- a function of tools/meshes/recipes.py, or one its RECIPES names from its
own module (wave.py, fireball.py) -- or a function of the file a layer names in "module" (a draft
that is not a shipped recipe yet). Blender renders them flat (one tone per volume,
the lighting rule of D-114) with back faces culled, as Roblox draws a SpecialMesh -- so an inverted hull
shows as the contour it will be in the game, and a face wound the wrong way shows as a hole here first.
Six views, as a model sheet: three quarters, front (the face that comes at you), side, top, and the two
the thrower sees -- from behind, over the shoulder, and low behind.

Needs Blender (BLENDER, else /Applications/Blender.app) and Pillow.
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")

# The skill's palettes (.claude/skills/vellum-vfx/SKILL.md): heated core, pigment, wet, dry; ink is shared.
PALETTES = {
    "Cinnabar": ("F4C8C1", "D93A22", "DB4E37", "B2331E"),
    "Indigo": ("C4CCDF", "2E4A8C", "445C94", "293F73"),
    "Umber": ("D6CCC5", "6B4A2F", "7A5C42", "5A3F29"),
    "Verdigris": ("CEE7DF", "4FA88C", "61AF94", "448B73"),
    "Orpiment": ("F9EDC1", "E8C022", "E8C437", "BE9E1E"),
}
INK = "17150F"
VIEWS = ("three quarters", "front", "side", "top", "behind (thrower)", "low behind")


def role_colour(pigment: str, role: str) -> str:
    core, body, wet, dry = PALETTES[pigment]
    return {"Core": core, "Pigment": body, "Wet": wet, "Dry": dry, "Ink": INK}[role]


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sheet = json.loads(pathlib.Path(sys.argv[1]).read_text())
    out = pathlib.Path(sys.argv[2])
    layers = [
        {"recipe": layer["recipe"], "module": layer.get("module"), "colour": role_colour(sheet["pigment"], layer["role"])}
        for layer in sheet["layers"]
    ]
    with tempfile.TemporaryDirectory() as scratch:
        job = pathlib.Path(scratch) / "job.json"
        job.write_text(json.dumps({"layers": layers, "out": scratch, "size": sheet.get("size", 640)}))
        env = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", ""), "PYTHONHASHSEED": "0"}
        command = [BLENDER, "-b", "--factory-startup", "-noaudio", "--python-use-system-env", "--python", str(HERE / "preview_blender.py"), "--", str(job)]
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=600)
        if result.returncode != 0 or "PREVIEW DONE" not in result.stdout:
            sys.exit(f"Blender failed:\n{result.stdout[-3000:]}\n{result.stderr[-3000:]}")
        frames = [Image.open(pathlib.Path(scratch) / f"view_{i}.png").convert("RGB") for i in range(len(VIEWS))]
    size = frames[0].size[0]
    title_h = 44
    columns = 3
    rows = (len(frames) + columns - 1) // columns
    board = Image.new("RGB", (size * columns, size * rows + title_h), (236, 228, 208))
    draw = ImageDraw.Draw(board)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    draw.text((12, 10), sheet.get("title", out.stem), fill=(23, 21, 15), font=font)
    for i, frame in enumerate(frames):
        x, y = (i % columns) * size, title_h + (i // columns) * size
        board.paste(frame, (x, y))
        draw.rectangle((x, y, x + size - 1, y + size - 1), outline=(23, 21, 15), width=2)
        draw.text((x + 10, y + 8), VIEWS[i], fill=(23, 21, 15), font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    board.save(out)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
