#!/usr/bin/env python3
"""Hand-keyed animation clips for Vellum's R15 rig, from key poses to a KeyframeSequence (.rbxmx).

    python3 tools/animations/keyed.py all
    python3 tools/animations/keyed.py build   <clip.json>
    python3 tools/animations/keyed.py check   <clip.json>
    python3 tools/animations/keyed.py preview <clip.json> <out_dir> [t1 t2 ... | all]

The retargeted CC0 clips (retarget.py) are general-purpose motion: slow, even, the same for every glyph.
A battleground cast is authored the way an animator works (docs/DECISIONS.md D-117): key poses first,
then the curves between them, then the secondary motion, then numbers that prove it -- and every step
is looked at (preview renders the poses in Blender, headless, from the front, the side, three quarters
and where the game's camera sits).

A clip file names the joints it drives by their child part (UpperTorso is the Waist, RightUpperArm the
RightShoulder...) and gives, for each key, a time, the ease to the NEXT key, and Euler angles in degrees
(Roblox's CFrame.Angles order: X, then Y, then Z, in the parent part's frame: +X right, +Y up, the
character facing -Z). A joint absent from a key keeps its track going through it. Each angle is a curve,
as in an animation editor's graph: 'Auto' (the default) draws a smooth curve through the keys; a named
ease ('QuadIn', 'SineOut'...) shapes one segment, for a blow that must accelerate into its contact;
'Hold' steps, for the blocking pass. There is no linear.

Only the joints a clip names are keyed. The others -- the legs and the hips, for an upper-body cast -- are
written as weightless placeholders, so the walk or the idle keeps them: measured in Studio, a walking
character's hip went on swinging under an Action clip that did not key it. A cast thrown on the run
therefore never slides its feet.

`all` checks and builds every clip in tools/animations/keyed/ into assets/animations/ (the file each one
names). It is pure Python, no dependency but the rig files in tools/animations/rigs/ (measured from
Studio), so scripts/check.sh runs it and fails when a committed .rbxmx is not what its key poses give.
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CLIPS = HERE / "keyed"
OUT = ROOT / "assets" / "animations"
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")

# The R15 part tree, which a KeyframeSequence's Pose tree mirrors.
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
PARENT = {child: parent for parent, children in TREE.items() for child in children}

# Enum.AnimationPriority values, by name.
PRIORITIES = {"Idle": 0, "Movement": 1, "Action": 2, "Action2": 3, "Action3": 4, "Action4": 5, "Core": 1000}

# ---------------------------------------------------------------------------------------------------
# Small linear algebra: 3x3 matrices as nested tuples, quaternions as (w, x, y, z).
# ---------------------------------------------------------------------------------------------------


def mat_mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def mat_vec(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return ((1, 0, 0), (0, c, -s), (0, s, c))


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def angles(degrees):
    """CFrame.Angles(rx, ry, rz): Rx * Ry * Rz."""
    x, y, z = (math.radians(v) for v in degrees)
    return mat_mul(mat_mul(rot_x(x), rot_y(y)), rot_z(z))


def mat_to_quat(m):
    trace = m[0][0] + m[1][1] + m[2][2]
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        return ((0.25 * s), (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s)
    if m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        return ((m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s)
    if m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        return ((m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s)
    s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
    return ((m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s)


def quat_to_mat(q):
    w, x, y, z = q
    return (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )


def quat_angle(a, b):
    """Degrees between two rotations."""
    dot = abs(sum(p * q for p, q in zip(a, b)))
    return math.degrees(2 * math.acos(min(dot, 1.0)))


IDENTITY = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
QUAT_IDENTITY = (1.0, 0.0, 0.0, 0.0)

# ---------------------------------------------------------------------------------------------------
# Eases. Linear is not one of them: art bible rule 4, nothing moves linearly.
# ---------------------------------------------------------------------------------------------------

BACK = 1.70158


def _in(style, t):
    if style == "Quad":
        return t * t
    if style == "Cubic":
        return t * t * t
    if style == "Quart":
        return t ** 4
    if style == "Sine":
        return 1 - math.cos(t * math.pi / 2)
    if style == "Back":
        return (BACK + 1) * t ** 3 - BACK * t * t
    if style == "Expo":
        return 0.0 if t <= 0 else 2 ** (10 * (t - 1))
    raise ValueError(f"no ease style {style}")


def ease(name: str, t: float) -> float:
    """'Hold' keeps the key until the next one; '<Style><In|Out|InOut>' otherwise. ('Auto', the smooth
    curve through the keys, is not a remap of one segment's time: sample() draws it.)"""
    if name == "Hold":
        return 0.0
    for direction in ("InOut", "Out", "In"):
        if name.endswith(direction):
            style = name[: -len(direction)]
            break
    else:
        raise ValueError(f"no ease {name} (Linear is refused on purpose)")
    t = min(max(t, 0.0), 1.0)
    if direction == "In":
        return _in(style, t)
    if direction == "Out":
        return 1 - _in(style, 1 - t)
    return _in(style, 2 * t) / 2 if t < 0.5 else 1 - _in(style, 2 - 2 * t) / 2


# ---------------------------------------------------------------------------------------------------
# Clips
# ---------------------------------------------------------------------------------------------------


def load_clip(path):
    clip = json.loads(Path(path).read_text())
    keys = sorted(clip["keys"], key=lambda k: k["t"])
    joints = sorted({joint for key in keys for joint in key.get("pose", {})})
    for joint in joints:
        if joint not in PARENT:
            raise SystemExit(f"{path}: {joint} is not an R15 part below the root")
    for key in keys:
        if key.get("ease", "Auto") != "Auto":
            ease(key["ease"], 0.5)  # validates the name
    clip["keys"] = keys
    clip["joints"] = joints
    return clip


def length(clip) -> float:
    return clip["keys"][-1]["t"]


def tracks(clip):
    """Per joint, its keys: (time, Euler degrees, ease to the next). A joint first keyed after 0 starts
    from rest at 0."""
    out = {}
    for joint in clip["joints"]:
        track = []
        for key in clip["keys"]:
            if joint in key.get("pose", {}):
                track.append((key["t"], tuple(key["pose"][joint]), key.get("ease", "Auto")))
        if track[0][0] > 0:
            track.insert(0, (0.0, (0.0, 0.0, 0.0), "Auto"))
        out[joint] = (track, slopes(track))
    return out


def ease_speed(name, at_end):
    """How fast a named ease moves at its start or its end, as a multiple of the segment's average."""
    if name == "Hold":
        return 0.0
    h = 1e-4
    return (ease(name, 1.0) - ease(name, 1.0 - h)) / h if at_end else (ease(name, h) - ease(name, 0.0)) / h


def slopes(track):
    """Per key and channel, the curve's slope there (degrees per second), for the 'Auto' segments beside
    it. Next to a named ease it is that ease's own speed there, so the curve carries on without a jerk.
    Between two Auto segments it is a monotone cubic's (Fritsch-Carlson), the curve an animator gets
    from auto-clamped handles: flat on the first and last key and on a turning point, and never
    overshooting between two keys -- an overshoot is a key someone chose, not a spline ringing."""
    n = len(track)
    out = []
    for i in range(n):
        channel_slopes = []
        incoming = track[i - 1][2] if i > 0 else None
        outgoing = track[i][2] if i < n - 1 else None
        for c in range(3):
            if incoming is not None and incoming != "Auto":
                (t0, v0, _), (t1, v1, _) = track[i - 1], track[i]
                channel_slopes.append((v1[c] - v0[c]) / (t1 - t0) * ease_speed(incoming, True))
                continue
            if outgoing is not None and outgoing != "Auto":
                (t1, v1, _), (t2, v2, _) = track[i], track[i + 1]
                channel_slopes.append((v2[c] - v1[c]) / (t2 - t1) * ease_speed(outgoing, False))
                continue
            if i == 0 or i == n - 1:
                channel_slopes.append(0.0)
                continue
            (t0, v0, _), (t1, v1, _), (t2, v2, _) = track[i - 1], track[i], track[i + 1]
            d0 = (v1[c] - v0[c]) / (t1 - t0)
            d1 = (v2[c] - v1[c]) / (t2 - t1)
            if d0 * d1 <= 0:
                channel_slopes.append(0.0)
            else:
                # Weighted harmonic mean: never steeper than three times either side (no overshoot).
                w0, w1 = 2 * (t2 - t1) + (t1 - t0), (t2 - t1) + 2 * (t1 - t0)
                channel_slopes.append((w0 + w1) / (w0 / d0 + w1 / d1))
        out.append(tuple(channel_slopes))
    return out


def _hermite(v0, v1, m0, m1, span, u):
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * span * m0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * span * m1


def sample(entry, t):
    """A track's rotation at time t, as a quaternion. On a key's own time it is that key, whatever the
    ease before it: a Hold keeps the previous key until then, not through it."""
    track, key_slopes = entry
    if t <= track[0][0]:
        return mat_to_quat(angles(track[0][1]))
    for i in range(len(track) - 1):
        (t0, v0, name), (t1, v1, _) = track[i], track[i + 1]
        if t0 <= t < t1:
            u = (t - t0) / (t1 - t0)
            if name == "Auto":
                span = t1 - t0
                euler = tuple(
                    _hermite(v0[c], v1[c], key_slopes[i][c], key_slopes[i + 1][c], span, u) for c in range(3)
                )
            else:
                k = ease(name, u)
                euler = tuple(v0[c] + (v1[c] - v0[c]) * k for c in range(3))
            return mat_to_quat(angles(euler))
    return mat_to_quat(angles(track[-1][1]))


def pose_at(clip, t, cache=None):
    """Joint -> quaternion at time t (only the keyed joints)."""
    all_tracks = cache if cache is not None else tracks(clip)
    return {joint: sample(track, t) for joint, track in all_tracks.items()}


# ---------------------------------------------------------------------------------------------------
# Rig and forward kinematics
# ---------------------------------------------------------------------------------------------------


def load_rig(name):
    rig = json.loads((HERE / "rigs" / f"{name}.json").read_text())
    joints = {j["part1"]: j for j in rig["joints"]}
    return rig, joints


def world(rig_joints, pose):
    """Part -> (rotation, position) in the HumanoidRootPart's space. part1 = part0 * C0 * T * C1^-1; the
    rig's attachments carry no rotation (measured), so C0 and C1 are offsets."""
    out = {"HumanoidRootPart": (IDENTITY, (0.0, 0.0, 0.0))}

    def place(part):
        joint = rig_joints[part]
        parent_rot, parent_pos = out[PARENT[part]]
        c0 = joint["c0"][:3]
        c1 = joint["c1"][:3]
        q = pose.get(part, QUAT_IDENTITY)
        rot = mat_mul(parent_rot, quat_to_mat(q))
        joint_pos = tuple(p + d for p, d in zip(parent_pos, mat_vec(parent_rot, c0)))
        pos = tuple(j - d for j, d in zip(joint_pos, mat_vec(rot, c1)))
        out[part] = (rot, pos)
        for child in TREE.get(part, []):
            place(child)

    place("LowerTorso")
    return out


# ---------------------------------------------------------------------------------------------------
# KeyframeSequence
# ---------------------------------------------------------------------------------------------------


def _fixed(value):
    """Six decimals, and never '-0.000000': an entry that should be zero comes out of the rotation maths
    as a sign-random crumb whose sign can differ from one machine's libm to another's, and the bytes must
    not (scripts/check.sh rebuilds them on CI)."""
    return "0.000000" if abs(value) < 5e-7 else f"{value:.6f}"


def cframe_xml(m, position=(0.0, 0.0, 0.0)):
    values = [("X", position[0]), ("Y", position[1]), ("Z", position[2])]
    values += [(f"R{i}{j}", m[i][j]) for i in range(3) for j in range(3)]
    body = "".join(f"<{k}>{_fixed(v)}</{k}>" for k, v in values)
    return f'<CoordinateFrame name="CFrame">{body}</CoordinateFrame>'


def keyed_parts(clip):
    """Every part a Pose is written for: the keyed joints and every part on the way down to them."""
    parts = set()
    for joint in clip["joints"]:
        part = joint
        while part is not None:
            parts.add(part)
            part = PARENT.get(part)
    return parts


def pose_xml(part, pose, written, keyed, counter):
    children = [c for c in TREE.get(part, []) if c in written]
    inner = "".join(pose_xml(child, pose, written, keyed, counter) for child in children)
    counter[0] += 1
    rotation = quat_to_mat(pose[part]) if part in keyed else IDENTITY
    # A part on the way down to a keyed joint but not keyed itself weighs nothing: whatever plays under
    # this clip (the walk, the idle) keeps it.
    weight = 1 if part in keyed else 0
    return (
        f'<Item class="Pose" referent="RBX{counter[0]}"><Properties><string name="Name">{part}</string>'
        f'{cframe_xml(rotation)}<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
        f'<float name="Weight">{weight}</float></Properties>{inner}</Item>'
    )


def build(clip, out_path):
    fps = clip.get("fps", 60)
    total = length(clip)
    # Every frame, and the last key exactly: the clip ends on its rest pose, not a frame past it.
    times = [frame / fps for frame in range(math.ceil(total * fps - 1e-9))] + [total]
    cache = tracks(clip)
    keyed = set(clip["joints"])
    written = keyed_parts(clip)
    counter = [0]
    keyframes = []
    for t in times:
        pose = pose_at(clip, t, cache)
        counter[0] += 1
        referent = counter[0]
        keyframes.append(
            f'<Item class="Keyframe" referent="RBX{referent}"><Properties><string name="Name">Keyframe</string>'
            f'<float name="Time">{t:.6f}</float></Properties>'
            f"{pose_xml('HumanoidRootPart', pose, written, keyed, counter)}</Item>"
        )
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">'
        '<Item class="KeyframeSequence" referent="RBX0"><Properties>'
        f'<string name="Name">{clip["name"]}</string>'
        f'<bool name="Loop">false</bool><token name="Priority">{PRIORITIES[clip.get("priority", "Action")]}</token>'
        f"</Properties>{''.join(keyframes)}</Item></roblox>\n"
    )
    Path(out_path).write_text(xml)
    print(f"WROTE {Path(out_path).relative_to(ROOT)}: {len(times)} keyframes, {total:.2f} s at {fps} fps, joints {', '.join(clip['joints'])}")


# ---------------------------------------------------------------------------------------------------
# Checks: numbers that say whether the motion holds together
# ---------------------------------------------------------------------------------------------------


def check(clip):
    """Returns the list of problems (empty when the clip passes) and prints the measurements."""
    problems = []
    cache = tracks(clip)
    total = length(clip)
    first = pose_at(clip, 0.0, cache)
    last = pose_at(clip, total, cache)
    rest_limit = clip.get("checks", {}).get("restDegrees", 4.0)
    for joint in clip["joints"]:
        for label, q in (("starts", first[joint]), ("ends", last[joint])):
            off = quat_angle(q, QUAT_IDENTITY)
            if off > rest_limit:
                problems.append(f"{joint} {label} {off:.1f} deg from rest: it would jump into or out of the clip")
    # The fastest any joint turns in one frame at 60 fps, and where: a spike is a pop.
    frame_limit = clip.get("checks", {}).get("maxDegreesPerFrame", 40.0)
    previous = first
    worst = (0.0, None, 0.0)
    steps = int(round(total * 60))
    for frame in range(1, steps + 1):
        t = frame / 60
        pose = pose_at(clip, t, cache)
        for joint in clip["joints"]:
            turn = quat_angle(previous[joint], pose[joint])
            if turn > worst[0]:
                worst = (turn, joint, t)
        previous = pose
    if worst[0] > frame_limit:
        problems.append(f"{worst[1]} turns {worst[0]:.0f} deg in one 60 fps frame at {worst[2]:.3f} s: a pop")
    # Where the throwing hand is at the release, on both rigs.
    release = clip.get("release")
    hand = clip.get("hand", "RightHand")
    reports = [f"fastest turn {worst[0]:.1f} deg/frame ({worst[1]} at {worst[2]:.3f} s)"]
    if release is not None:
        for rig_name in ("standard", "developer"):
            _, rig_joints = load_rig(rig_name)
            placed = world(rig_joints, pose_at(clip, release, cache))
            _, (x, y, z) = placed[hand]
            reports.append(f"{rig_name}: {hand} at release x {x:+.2f} y {y:+.2f} z {z:+.2f} (-z is forward)")
            if z > -0.5:
                problems.append(f"{rig_name}: the hand is not in front of the body at the release (z {z:+.2f})")
    for line in reports:
        print("  " + line)
    for line in problems:
        print("  PROBLEM " + line)
    print("  OK" if not problems else f"  {len(problems)} problem(s)")
    return problems


# ---------------------------------------------------------------------------------------------------
# Preview: Blender renders of the poses, four angles, on both rigs
# ---------------------------------------------------------------------------------------------------


def preview(clip, out_dir, times=None):
    """Renders the poses at `times` (the keys when none, every 60 fps frame for 'all'): a contact sheet
    per rig for chosen times, a GIF per rig and view for every frame."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    cache = tracks(clip)
    every_frame = times == ["all"]
    if every_frame:
        times = [frame / 60 for frame in range(int(round(length(clip) * 60)) + 1)]
    elif not times:
        times = [key["t"] for key in clip["keys"]]
    job = {"times": times, "rigs": {}}
    for rig_name in ("standard", "developer"):
        rig, rig_joints = load_rig(rig_name)
        frames = []
        for t in times:
            placed = world(rig_joints, pose_at(clip, t, cache))
            frames.append({part: [list(rot[0]) + list(rot[1]) + list(rot[2]), list(pos)] for part, (rot, pos) in placed.items()})
        job["rigs"][rig_name] = {"sizes": {p: v["size"] for p, v in rig["parts"].items()}, "frames": frames}
    job_path = out / "job.json"
    job_path.write_text(json.dumps(job))
    result = subprocess.run(
        [BLENDER, "-b", "--factory-startup", "-noaudio", "--python", str(HERE / "preview_blender.py"), "--", str(job_path), str(out)],
        capture_output=True,
        text=True,
        timeout=900,
    )
    if result.returncode != 0 or "PREVIEW DONE" not in result.stdout:
        raise SystemExit(f"Blender failed:\n{result.stdout[-3000:]}\n{result.stderr[-3000:]}")
    if every_frame:
        gifs(out, len(times), clip["name"])
    else:
        sheet(out, times, clip["name"])


def sheet(out, times, name):
    from PIL import Image, ImageDraw

    views = ("front", "side", "three_quarter", "game")
    for rig_name in ("standard", "developer"):
        tiles = [[Image.open(out / f"{rig_name}_{i}_{view}.png") for view in views] for i in range(len(times))]
        w, h = tiles[0][0].size
        board = Image.new("RGB", (w * len(times), h * len(views) + 24), (240, 236, 226))
        draw = ImageDraw.Draw(board)
        for i, column in enumerate(tiles):
            draw.text((i * w + 6, 4), f"{times[i]:.3f} s", fill=(20, 20, 20))
            for j, tile in enumerate(column):
                board.paste(tile, (i * w, 24 + j * h))
        board.save(out / f"{name}_{rig_name}_sheet.png")
    print(f"SHEETS in {out}")


def gifs(out, count, name):
    """One GIF per rig and view, at the clip's real speed (a 60 fps frame is shown for 1/60 s, rounded
    by the format to 20 ms), then a second of rest so the loop reads as separate throws."""
    from PIL import Image

    for rig_name in ("standard", "developer"):
        for view in ("front", "side", "three_quarter", "game"):
            frames = [Image.open(out / f"{rig_name}_{i}_{view}.png").convert("P") for i in range(count)]
            durations = [20] * (count - 1) + [1000]
            frames[0].save(
                out / f"{name}_{rig_name}_{view}.gif", save_all=True, append_images=frames[1:], duration=durations, loop=0
            )
    print(f"GIFS in {out}")


def build_checked(clip_path):
    clip = load_clip(clip_path)
    print(f"{clip['name']}:")
    if check(clip):
        raise SystemExit(f"refused: {clip_path} does not pass its checks")
    build(clip, OUT / clip["file"])


def main(argv):
    if len(argv) == 2 and argv[1] == "all":
        for clip_path in sorted(CLIPS.glob("*.json")):
            build_checked(clip_path)
        return
    if len(argv) < 3:
        raise SystemExit(__doc__)
    command, clip_path = argv[1], argv[2]
    if command == "build":
        build_checked(clip_path)
        return
    clip = load_clip(clip_path)
    if command == "check":
        raise SystemExit(1 if check(clip) else 0)
    if command == "preview" and len(argv) >= 4:
        times = argv[4:] if argv[4:] == ["all"] else [float(v) for v in argv[4:]] or None
        preview(clip, argv[3], times)
        return
    raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
