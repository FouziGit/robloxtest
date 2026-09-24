"""Renders the poses keyed.py computed, as a box rig, from several angles. Run by keyed.py, inside Blender:

    Blender -b --factory-startup --python tools/animations/preview_blender.py -- <job.json> <out_dir>

The job holds, per rig and per sampled time, every R15 part's rotation and position in the root's space
(Roblox axes: +X right, +Y up, the character facing -Z) and every part's size. Each part is drawn as a box
of its size: an animator reads a pose from its silhouette and its lines of action, and boxes show both
without a mesh or a texture to get in the way. The throwing arm is drawn in cinnabar so it reads at once.

Workbench render: no lights, no sampling, the same image every run.
"""

import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

# Roblox basis -> Blender basis (Blender is Z-up, facing -Y): (x, y, z) -> (-x, z, y). Its own inverse,
# determinant +1: nothing is mirrored.
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))

INK = (0.13, 0.12, 0.11, 1)
VELLUM = (0.86, 0.82, 0.72, 1)
CINNABAR = (0.80, 0.22, 0.12, 1)
FLOOR = (0.93, 0.90, 0.83, 1)

THROWING = {"RightUpperArm", "RightLowerArm", "RightHand"}
HEAD = {"Head"}

# Camera placements in Roblox space, looking at the chest: in front, from the right side, three quarters
# front-right, and where the game's camera sits (behind, above, over the shoulder).
VIEWS = {
    "front": ((0.0, 1.2, -12.0), True),
    "side": ((12.0, 1.2, 0.0), True),
    "three_quarter": ((8.0, 3.0, -8.5), False),
    "game": ((2.0, 4.5, 12.0), False),
}
TILE = (300, 380)


def to_blender(vector):
    return M @ Vector(vector)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    return mat


def box(name, color_mat):
    """A unit cube; its matrix scales it to the part's size every frame."""
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(color_mat)
    return obj


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = TILE
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_object_outline = True
    shading.object_outline_color = (0.05, 0.05, 0.05)
    shading.show_shadows = True
    shading.background_type = "VIEWPORT"
    shading.background_color = (0.95, 0.93, 0.88)
    scene.view_settings.view_transform = "Standard"
    return scene


def camera(scene, name, position, orthographic):
    data = bpy.data.cameras.new(name)
    if orthographic:
        data.type = "ORTHO"
        data.ortho_scale = 8.5
    else:
        data.lens = 40
    cam = bpy.data.objects.new(name, data)
    scene.collection.objects.link(cam)
    cam.location = to_blender(position)
    target = to_blender((0.0, 0.3, 0.0))
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    job = json.loads(open(argv[0]).read())
    out = argv[1]
    scene = setup_scene()
    mats = {
        "ink": material("ink", INK),
        "vellum": material("vellum", VELLUM),
        "cinnabar": material("cinnabar", CINNABAR),
        "floor": material("floor", FLOOR),
    }
    cameras = {name: camera(scene, name, position, ortho) for name, (position, ortho) in VIEWS.items()}

    for rig_name, rig in job["rigs"].items():
        sizes = rig["sizes"]
        parts = {}
        for part in sizes:
            if part == "HumanoidRootPart":
                continue
            mat = mats["cinnabar"] if part in THROWING else mats["ink"] if part in HEAD else mats["vellum"]
            parts[part] = box(f"{rig_name}_{part}", mat)
        floor = None
        for index, frame in enumerate(rig["frames"]):
            lowest = min(
                pos[1] - 0.5 * sizes[part][1] for part, (_, pos) in frame.items() if part.endswith("Foot")
            )
            for part, obj in parts.items():
                rot, pos = frame[part]
                r = Matrix((rot[0:3], rot[3:6], rot[6:9]))
                # A box scaled along the part's own axes: rotation applied in Roblox space, then the basis.
                obj.matrix_world = Matrix.Translation(to_blender(pos)) @ (M @ r @ M).to_4x4() @ Matrix.Diagonal(
                    (sizes[part][0], sizes[part][2], sizes[part][1], 1)
                )
            if floor is None:
                bpy.ops.mesh.primitive_plane_add(size=30)
                floor = bpy.context.active_object
                floor.data.materials.append(mats["floor"])
            floor.location = to_blender((0.0, lowest, 0.0))
            for view, cam in cameras.items():
                scene.camera = cam
                scene.render.filepath = f"{out}/{rig_name}_{index}_{view}.png"
                bpy.ops.render.render(write_still=True)
        for obj in list(parts.values()) + ([floor] if floor else []):
            bpy.data.objects.remove(obj, do_unlink=True)
    print("PREVIEW DONE")


main()
