#!/usr/bin/env python3
"""Regenerate every KeyframeSequence in assets/animations/ from the pinned CC0 sources.

    python3 tools/animations/generate_all.py

Needs Blender (BLENDER, else /Applications/Blender.app) and the archives fetched and unpacked by
tools/thirdparty/fetch.py. It is not part of scripts/check.sh: CI has no Blender, so the outputs are
committed like the textures and the sounds, and this is how they are reproduced.
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
CACHE = ROOT / ".cache" / "thirdparty"
OUT = ROOT / "assets" / "animations"
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")


def unpack() -> None:
    for folder in CACHE.iterdir():
        target = folder / "unpacked"
        if target.exists() or not folder.is_dir():
            continue
        for archive in folder.glob("*.zip"):
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(target)


def main() -> int:
    manifest = json.loads((HERE / "clips.json").read_text())
    unpack()
    OUT.mkdir(parents=True, exist_ok=True)
    failures = 0
    for clip in manifest["clips"]:
        source = CACHE / manifest["libraries"][clip["library"]]
        if not source.exists():
            print(f"  missing {source} -- run tools/thirdparty/fetch.py first")
            failures += 1
            continue
        args = [BLENDER, "-b", "--python", str(HERE / "retarget.py"), "--", str(source), clip["action"], str(OUT / clip["file"])]
        if clip.get("loop"):
            args.append("loop")
        result = subprocess.run(args, capture_output=True, text=True)
        line = next((l for l in result.stdout.splitlines() if l.startswith("WROTE")), None)
        if result.returncode != 0 or line is None:
            print(f"  FAILED {clip['file']}: {(result.stderr or result.stdout)[-400:]}")
            failures += 1
        else:
            print("  " + line.replace(str(ROOT) + "/", ""))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
