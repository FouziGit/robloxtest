"""Runs INSIDE Blender (see preview.py): renders recipes flat, back faces culled, from the four sheet views.

    Blender -b --factory-startup --python-use-system-env --python preview_blender.py -- <job.json>

Recipes are in Roblox space (X right, Y up, forward -Z). Here they are handed to Blender as (x, -z, y):
a proper rotation, so every triangle keeps the winding Roblox will cull by, and Roblox's forward becomes
Blender's +Y.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import recipes  # noqa: E402  (the path is set on the line above)


def to_blender(v):
    x, y, z = v
    return (x, -z, y)


def colour(hex_code: str) -> tuple[float, float, float, float]:
    # Workbench's object colour is linear; the sheet's colours are sRGB.
    def linear(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (int(hex_code[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return (linear(r), linear(g), linear(b), 1.0)


def main() -> None:
    job = json.loads(Path(sys.argv[sys.argv.index("--") + 1]).read_text())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "FLAT"
    shading.color_type = "OBJECT"
    shading.show_backface_culling = True
    shading.background_type = "VIEWPORT"
    shading.background_color = (0.83, 0.79, 0.69)
    scene.render.resolution_x = job["size"]
    scene.render.resolution_y = job["size"]
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"

    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    for index, layer in enumerate(job["layers"]):
        mesh, _meta = recipe(layer["recipe"], layer.get("module"))()
        data = bpy.data.meshes.new(f"layer{index}")
        data.from_pydata([to_blender(v) for v in mesh.verts], [], [list(t) for t in mesh.tris])
        data.update()
        obj = bpy.data.objects.new(f"layer{index}", data)
        obj.color = colour(layer["colour"])
        scene.collection.objects.link(obj)
        for v in data.vertices:
            low = Vector(map(min, low, v.co))
            high = Vector(map(max, high, v.co))

    centre = (low + high) / 2
    extent = max((high - low).length, 1e-3)
    camera_data = bpy.data.cameras.new("camera")
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    # Blender +Y is Roblox forward: "front" stands ahead of the volume and looks back at its face.
    directions = [
        (Vector((-0.75, 1.0, 0.55)), "PERSP"),
        (Vector((0.0, 1.0, 0.0)), "ORTHO"),
        (Vector((1.0, 0.0, 0.0)), "ORTHO"),
        (Vector((0.0, 0.0, 1.0)), "ORTHO"),
        (Vector((0.15, -1.0, 0.45)), "PERSP"),
        (Vector((-0.5, -1.0, 0.12)), "PERSP"),
    ]
    for i, (direction, kind) in enumerate(directions):
        direction.normalize()
        camera_data.type = kind
        camera_data.ortho_scale = extent * 1.1
        camera_data.lens = 50
        camera_data.clip_end = extent * 20
        camera.location = centre + direction * extent * 2.2
        up = Vector((0.0, 1.0, 0.0)) if abs(direction.z) > 0.99 else Vector((0.0, 0.0, 1.0))
        camera.rotation_euler = look(direction, up)
        scene.render.filepath = str(Path(job["out"]) / f"view_{i}.png")
        bpy.ops.render.render(write_still=True)
    print("PREVIEW DONE")


def recipe(name: str, module: str | None):
    """A shipped recipe -- a function of recipes.py, or one RECIPES names from its own module (the
    wave's, the fireball's) -- or a function of a draft module given by path."""
    if module is None:
        shipped = {entry[1].__name__: entry[1] for entry in recipes.RECIPES.values()}
        return getattr(recipes, name, None) or shipped[name]
    spec = importlib.util.spec_from_file_location(Path(module).stem, module)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return getattr(loaded, name)


def look(direction: Vector, up: Vector):
    # A camera looks down its own -Z with +Y up: aim -Z at the volume, keep the sheet's up on screen.
    forward = -direction
    right = forward.cross(up).normalized()
    true_up = right.cross(forward).normalized()
    basis = Matrix((right, true_up, -forward)).transposed()
    return basis.to_euler()


main()
