#!/usr/bin/env python3
"""Regenerate every volume in assets/meshes/ (D-114).

    python3 tools/meshes/generate_all.py            # the shipped meshes, then the manifest
    python3 tools/meshes/generate_all.py --probe    # the axis probe only, into .cache/meshes/

Needs Blender (BLENDER, else /Applications/Blender.app). Not part of scripts/check.sh: CI has no
Blender, so the .glb files and the manifest are committed like the textures and the sounds, and this is
how they are reproduced. It exports twice, into the repository and into a scratch directory, from two
separate Blender processes, and fails unless both runs are byte-identical: a generator whose output
moves between runs turns every commit into an unreviewable binary diff and every upload into a new
asset. It also fails a mesh over its triangle cap or over MAX_BYTES, writes assets/meshes/manifest.json,
and rewrites the manifest block of src/shared/Config/MeshConfig.luau from it, so the runtime and the
files cannot disagree about a mesh's bounds.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
OUT = ROOT / "assets" / "meshes"
PROBE_OUT = ROOT / ".cache" / "meshes"
CONFIG = ROOT / "src" / "shared" / "Config" / "MeshConfig.luau"
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
MAX_BYTES = 200_000
BEGIN = "-- BEGIN MESH MANIFEST"
END = "-- END MESH MANIFEST"

sys.path.insert(0, str(HERE))

import recipes  # noqa: E402  (the path is set on the line above)


def run_blender(out: pathlib.Path, probe: bool = False) -> str:
    # A clean environment: nothing of the caller's Python leaks into Blender's, and a fixed hash seed
    # so nothing that iterates a set or a dict of strings can reorder the file between runs.
    env = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", ""), "PYTHONHASHSEED": "0"}
    command = [BLENDER, "-b", "--factory-startup", "-noaudio", "--python-use-system-env", "--python", str(HERE / "export_blender.py"), "--", str(out)]
    if probe:
        command.append("probe")
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        sys.exit(f"Blender failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    version = subprocess.run([BLENDER, "--version"], capture_output=True, text=True, env=env).stdout.splitlines()
    return version[0].strip() if version else "unknown"


def glb_triangles(path: pathlib.Path) -> int:
    """Triangles in a glTF binary's first primitive, read from its JSON chunk: what the file really
    carries, whatever the recipe built."""
    data = path.read_bytes()
    length = int.from_bytes(data[12:16], "little")
    document = json.loads(data[20 : 20 + length])
    primitive = document["meshes"][0]["primitives"][0]
    return document["accessors"][primitive["indices"]]["count"] // 3


def lua_number(value: float) -> str:
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def lua_vector(values) -> str:
    return "{ " + ", ".join(lua_number(v) for v in values) + " }"


def write_block(manifest: dict) -> None:
    lines = [BEGIN, "local MANIFEST: { [string]: Entry } = {"]
    for key, entry in sorted(manifest["meshes"].items()):
        lines.append(f"\t{key} = {{")
        lines.append(f'\t\tSource = "{entry["Source"]}",')
        lines.append(f'\t\tTris = {entry["Tris"]},')
        lines.append(f'\t\tMin = {lua_vector(entry["Min"])},')
        lines.append(f'\t\tMax = {lua_vector(entry["Max"])},')
        lines.append(f'\t\tPivot = {lua_vector(entry["Pivot"])},')
        lines.append(f'\t\tReference = "{entry["Reference"]}",')
        lines.append(f'\t\tAxis = "{entry["Axis"]}",')
        lines.append(f'\t\tFlat = {"true" if entry["Flat"] else "false"},')
        lines.append("\t},")
    lines.append("}")
    lines.append(END)
    text = CONFIG.read_text()
    start = text.index(BEGIN)
    end = text.index(END, start) + len(END)
    CONFIG.write_text(text[:start] + "\n".join(lines) + text[end:])


def main() -> int:
    if "--probe" in sys.argv[1:]:
        run_blender(PROBE_OUT, probe=True)
        print(f"wrote {(PROBE_OUT / 'axis_probe.glb').relative_to(ROOT)}")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    version = run_blender(OUT)
    with tempfile.TemporaryDirectory() as scratch:
        run_blender(pathlib.Path(scratch))
        for key, (file_name, _recipe, _cap) in recipes.RECIPES.items():
            first = (OUT / file_name).read_bytes()
            second = (pathlib.Path(scratch) / file_name).read_bytes()
            if first != second:
                sys.exit(f"{file_name} is not reproducible: two Blender runs wrote different bytes")

    manifest: dict = {"blender": version, "meshes": {}}
    for key, (file_name, recipe, cap) in recipes.RECIPES.items():
        mesh, meta = recipe()
        tris = len(mesh.tris)
        path = OUT / file_name
        size = path.stat().st_size
        written = glb_triangles(path)
        if written != tris:
            # Blender validates a mesh on the way in and drops what it considers duplicate faces; the
            # file must carry every triangle the recipe built, or a double-sided stroke is one-sided.
            sys.exit(f"{key}: the recipe built {tris} triangles and the file carries {written}")
        if tris > cap:
            sys.exit(f"{key}: {tris} triangles, over its cap of {cap}")
        if size > MAX_BYTES:
            sys.exit(f"{key}: {size} bytes, over {MAX_BYTES}")
        low, high = mesh.bounds()
        manifest["meshes"][key] = {
            "Source": str(path.relative_to(ROOT)),
            "Tris": tris,
            "Min": [round(v, 4) for v in low],
            "Max": [round(v, 4) for v in high],
            "Pivot": meta["Pivot"],
            "Reference": meta["Reference"],
            "Axis": meta["Axis"],
            "Flat": meta["Flat"],
            "Normals": mesh.normals,
            "Seed": meta["Seed"],
            "Bytes": size,
            "Sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        print(f"  {key:10s} {tris:4d} tris  {size:6d} bytes  {file_name}")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    write_block(manifest)
    print(f"{len(manifest['meshes'])} meshes, reproducible, manifest written ({version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
