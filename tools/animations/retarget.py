"""Retarget a Quaternius Universal Animation Library clip onto Roblox's R15 skeleton, as a KeyframeSequence.

Run inside Blender, headless:

    Blender -b --python tools/animations/retarget.py -- <source.glb> <ActionName> <out.rbxmx> [loop]

Why by hand and not through Studio: Roblox's own retargeting (Adaptive Animation) needs a rig and every
clip imported through Studio file dialogs, one at a time, with no record of what was done. This is a
generator like the ones in tools/textures/: same input, same bytes, committed output.

The method, and why each step is there:
  * Both Quaternius libraries share one skeleton geometry (same joint positions and lengths, only the
    bone names differ), in a T-pose. R15 rests with its arms hanging DOWN. So every bone's motion is
    taken as a world-space rotation relative to a calibration pose -- the source rest with the arms
    swung down 90 degrees about the forward axis -- which is what makes "arms by the sides" in the clip
    come out as "arms by the sides" on an R15, instead of 90 degrees off.
  * Blender is Z-up with the character facing -Y; Roblox is Y-up facing -Z with +X to the character's
    right. M below is that change of basis (a proper rotation, determinant +1: nothing is mirrored).
  * An R15 joint's attachments carry no rotation, so a Pose is the child part's rotation relative to
    its parent part. Only the root pose carries a translation (the hips' travel, scaled from metres to
    studs by leg length).
"""

import math
import sys
import xml.sax.saxutils as sx

import bpy
from mathutils import Matrix

# Semantic R15 part -> (UAL1 bone, UAL2 bone). The spine bones between the hips and the chest are not
# mapped one by one: using each mapped bone's WORLD rotation folds everything above it into it.
BONES = {
    "LowerTorso": ("DEF-hips", "pelvis"),
    "UpperTorso": ("DEF-spine.003", "spine_03"),
    "Head": ("DEF-head", "Head"),
    "LeftUpperArm": ("DEF-upper_arm.L", "upperarm_l"),
    "LeftLowerArm": ("DEF-forearm.L", "lowerarm_l"),
    "LeftHand": ("DEF-hand.L", "hand_l"),
    "RightUpperArm": ("DEF-upper_arm.R", "upperarm_r"),
    "RightLowerArm": ("DEF-forearm.R", "lowerarm_r"),
    "RightHand": ("DEF-hand.R", "hand_r"),
    "LeftUpperLeg": ("DEF-thigh.L", "thigh_l"),
    "LeftLowerLeg": ("DEF-shin.L", "calf_l"),
    "LeftFoot": ("DEF-foot.L", "foot_l"),
    "RightUpperLeg": ("DEF-thigh.R", "thigh_r"),
    "RightLowerLeg": ("DEF-shin.R", "calf_r"),
    "RightFoot": ("DEF-foot.R", "foot_r"),
}

# The R15 part tree, which a KeyframeSequence's Pose tree must mirror.
TREE = {
    "HumanoidRootPart": ["LowerTorso"],
    "LowerTorso": ["UpperTorso", "LeftUpperLeg", "RightUpperLeg"],
    "UpperTorso": ["Head", "LeftUpperArm", "RightUpperArm"],
    "LeftUpperArm": ["LeftLowerArm"],
    "LeftLowerArm": ["LeftHand"],
    "RightUpperArm": ["RightLowerArm"],
    "RightLowerArm": ["RightHand"],
    "LeftUpperLeg": ["LeftLowerLeg"],
    "LeftLowerLeg": ["LeftFoot"],
    "RightUpperLeg": ["RightLowerLeg"],
    "RightLowerLeg": ["RightFoot"],
}

LEFT_ARM = {"LeftUpperArm", "LeftLowerArm", "LeftHand"}
RIGHT_ARM = {"RightUpperArm", "RightLowerArm", "RightHand"}

# Blender basis -> Roblox basis: Roblox (x, y, z) = (-Xb, Zb, Yb).
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
M_INV = M.inverted()

# Studs per metre, from leg length: the source hips sit 0.917 m up, an R15's about 2 studs.
STUDS_PER_METRE = 2.0 / 0.917


def rotation_y(degrees: float) -> Matrix:
    return Matrix.Rotation(math.radians(degrees), 3, "Y")


def pick_bones(armature) -> dict:
    names = {b.name for b in armature.data.bones}
    column = 0 if "DEF-hips" in names else 1
    chosen = {part: pair[column] for part, pair in BONES.items()}
    missing = [bone for bone in chosen.values() if bone not in names]
    if missing:
        raise SystemExit(f"skeleton lacks {missing}")
    return chosen


def calibration(part: str) -> Matrix:
    # Arms swung down from the T-pose, about the forward axis (Blender Y): left +90, right -90.
    if part in LEFT_ARM:
        return rotation_y(90)
    if part in RIGHT_ARM:
        return rotation_y(-90)
    return Matrix.Identity(3)


def cframe_xml(name: str, rotation: Matrix, position=(0.0, 0.0, 0.0)) -> str:
    r = rotation
    values = [
        ("X", position[0]), ("Y", position[1]), ("Z", position[2]),
        ("R00", r[0][0]), ("R01", r[0][1]), ("R02", r[0][2]),
        ("R10", r[1][0]), ("R11", r[1][1]), ("R12", r[1][2]),
        ("R20", r[2][0]), ("R21", r[2][1]), ("R22", r[2][2]),
    ]
    body = "".join(f"<{k}>{v:.6f}</{k}>" for k, v in values)
    return f'<CoordinateFrame name="{name}">{body}</CoordinateFrame>'


class Refs:
    def __init__(self):
        self.n = 0

    def next(self) -> str:
        self.n += 1
        return f"RBX{self.n}"


def pose_xml(part: str, poses: dict, refs: Refs) -> str:
    rotation, position = poses.get(part, (Matrix.Identity(3), (0.0, 0.0, 0.0)))
    children = "".join(pose_xml(child, poses, refs) for child in TREE.get(part, []))
    return (
        f'<Item class="Pose" referent="{refs.next()}"><Properties>'
        f'<string name="Name">{part}</string>'
        f"{cframe_xml('CFrame', rotation, position)}"
        '<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
        '<float name="Weight">1</float>'
        f"</Properties>{children}</Item>"
    )


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    source, action_name, out_path = argv[0], argv[1], argv[2]
    loop = len(argv) > 3 and argv[3] == "loop"

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source)
    armature = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    action = bpy.data.actions.get(action_name)
    if action is None:
        raise SystemExit(f"no action {action_name}")
    armature.animation_data.action = action
    bones = pick_bones(armature)
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base

    calibrated = {}
    for part, bone in bones.items():
        rest = armature.data.bones[bone].matrix_local.to_3x3()
        calibrated[part] = (calibration(part) @ rest).inverted()
    hips_bone = bones["LowerTorso"]
    hips_rest = armature.data.bones[hips_bone].head_local.copy()

    start, end = (int(round(v)) for v in action.frame_range)
    keyframes = []
    refs = Refs()
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        world = {}
        for part, bone in bones.items():
            current = armature.pose.bones[bone].matrix.to_3x3()
            delta = current @ calibrated[part]
            world[part] = M @ delta @ M_INV
        world["HumanoidRootPart"] = Matrix.Identity(3)
        poses = {}
        for parent, children in TREE.items():
            for child in children:
                relative = world[parent].inverted() @ world[child]
                poses[child] = (relative, (0.0, 0.0, 0.0))
        travel = armature.pose.bones[hips_bone].head - hips_rest
        shifted = M @ travel * STUDS_PER_METRE
        poses["LowerTorso"] = (poses["LowerTorso"][0], (shifted.x, shifted.y, shifted.z))
        poses["HumanoidRootPart"] = (Matrix.Identity(3), (0.0, 0.0, 0.0))
        time = (frame - start) / fps
        keyframes.append(
            f'<Item class="Keyframe" referent="{refs.next()}"><Properties>'
            f'<string name="Name">Keyframe</string><float name="Time">{time:.6f}</float>'
            f"</Properties>{pose_xml('HumanoidRootPart', poses, refs)}</Item>"
        )

    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">'
        '<Item class="KeyframeSequence" referent="RBX0"><Properties>'
        f'<string name="Name">{sx.escape(action_name)}</string>'
        f'<bool name="Loop">{"true" if loop else "false"}</bool>'
        '<token name="Priority">2</token>'
        f"</Properties>{''.join(keyframes)}</Item></roblox>\n"
    )
    with open(out_path, "w") as handle:
        handle.write(xml)
    print(f"WROTE {out_path} {len(keyframes)} keyframes {(end - start) / fps:.2f}s fps={fps:g}")


main()
