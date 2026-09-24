"""Runs INSIDE Blender (see generate_all.py): builds every recipe and writes one glTF binary per mesh.

    Blender -b --factory-startup --python-use-system-env --python export_blender.py -- <out dir> [probe]

The geometry comes from recipes.py in Roblox space (Y up, forward -Z). Roblox's importer turns a glTF
half a turn about Y on the way in -- glTF's front is +Z, Roblox's is -Z -- which was measured in Studio:
the drop flew tail first, the ensō's gap faced forward and the sweep ran the wrong way. So a vertex is
written already turned, (-x, y, -z), and the import turns it back. Blender is Z up and its glTF writer
converts to Y up, so that is handed to Blender as (-x, z, y). Normals: a pigment volume gets every normal
pointing up (+Y in the file), the lighting rule of D-114; a scrap of paper keeps its true normals.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import recipes  # noqa: E402  (the path is set on the line above)


def to_blender(v):
    x, y, z = v
    return (-x, z, y)


def build(name: str, mesh) -> bpy.types.Object:
    data = bpy.data.meshes.new(name)
    data.from_pydata([to_blender(v) for v in mesh.verts], [], [list(t) for t in mesh.tris])
    data.validate(clean_customdata=False)
    data.update()
    if mesh.normals == "up":
        # Per loop, so a vertex shared by the front and the back of a double-sided stroke keeps +Y too.
        data.normals_split_custom_set([(0.0, 0.0, 1.0)] * len(data.loops))
    else:
        for polygon in data.polygons:
            polygon.use_smooth = False
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj: bpy.types.Object, path: Path) -> None:
    for other in bpy.context.scene.objects:
        other.select_set(other == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_normals=True,
        export_materials="NONE",
        export_texcoords=False,
        export_yup=True,
    )


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    out = Path(args[0])
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if len(args) > 1 and args[1] == "probe":
        export(build("AxisProbe", recipes.axis_probe()), out / "axis_probe.glb")
        return
    for key, (file_name, recipe, _cap) in recipes.RECIPES.items():
        mesh, _meta = recipe()
        export(build(key, mesh), out / file_name)


main()
