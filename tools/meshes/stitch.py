"""The Stitch's two bodies (D-273 family): the Loop it flies as and the Shackle it closes into.

Drawn after the developer's references (docs/vfx/stitch/ref-1.jpg, in game; ref-2.jpg, the model sheet).

Roblox space: X right, Y up, forward -Z.

The Loop (flight; Reference Length along Z, Axis Z, spun about Z by the runtime): one flat broad-nib
ribbon written in a single stroke -- a short cut tail, the first crossing, the thick downstroke down the
left, the round end, the thin hairline back up the right, the second crossing over the first, and the
long tail drawn out into the needle point that leads. The two crossings make the closed eye of the
loop, and the narrow front of that eye is the dark chas (ink). Where the ribbon goes round the trailing
end it stands up, its face turned back toward the thrower, so from behind it is a broad band, never an
edge-on hair; the loop is also twisted a little about its own axis, so seen from the side it is the
model sheet's slim figure of eight.

The Shackle (catch; Reference Diameter across XZ, Axis Y, pivot the ring's centre): three flat cords
laid as one rope round the caught body, each winding round the others (the three interlocking loops),
bound at four points by a tilted loop of the same ribbon (the knots of the top-down view).

Three meshes per body, one tone each: Pigment (the ribbons), Core (the pale streak along a face, cut
in the ribbon's own triangles), Ink (an inverted hull round every ribbon, a few tapered flow lines on
the faces, and the Loop's dark eye).
"""

from __future__ import annotations

import math

from fireball import clip, place, skin
from strokes import Mesh, Polyline, Rng, catmull, cosine_curve, fbm

LOOP_SEED = 6203
SHACKLE_SEED = 6211


# --- vectors -------------------------------------------------------------------------------------


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


def lerp(a, b, f):
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)


def rect(width: float, thick: float):
    """A flat ribbon's section, counter-clockwise in (across, normal): the top face is edge 0 (corner 0
    to 1, facing +normal), the bottom face edge 2."""
    h, d = width / 2.0, thick / 2.0
    return [(h, d), (-h, d), (-h, -d), (h, -d)]


def bevel(width: float, thick: float, side: float, face: float):
    """A contour's section round a flat ribbon of `width` x `thick`, counter-clockwise: `face` over each
    face and `side` beyond each edge, where its walls slope to a point. A rectangle's thin end walls
    stood edge-on wherever a strand ran away from the eye and drew a fan of hairlines across the face
    behind it; a sloped wall never stands edge-on to a face it encloses. The top is edge 1, the bottom
    edge 4."""
    h, d = width / 2.0, thick / 2.0 + face
    big = h + side
    return [(big, 0.0), (h, d), (-h, d), (-big, 0.0), (-h, -d), (h, -d)]


def lens(mesh: Mesh, rows, normals, face, first: int, last: int, centre: float, spread: float, lift: float, cross_split: bool = False) -> None:
    """fireball.streak with its own lift: a lens pointed at both ends lying on one face of a ribbon, cut
    along the face's own triangles. The pale streaks and the ink flow lines are both drawn with it."""
    i, j = face
    band = []
    for k in range(first, last + 1):
        f = math.sin(math.pi * (k - first) / (last - first)) ** 0.8
        band.append((centre - spread * f, centre + spread * f))
    for k in range(first, last):
        a0, b0 = rows[k][i], rows[k][j]
        a1, b1 = rows[k + 1][i], rows[k + 1][j]
        n0, n1 = normals[k], normals[k + 1]
        (s0, s1), (t0, t1) = band[k - first], band[k - first + 1]
        poly = [(s0, 0.0), (s1, 0.0), (t1, 1.0), (t0, 1.0)]
        if cross_split:
            pieces = (
                (lambda u, v: 1.0 - u - v, lambda u, v, a0=a0, b0=b0, a1=a1: add(a0, add(mul(sub(b0, a0), u), mul(sub(a1, a0), v)))),
                (lambda u, v: u + v - 1.0, lambda u, v, b1=b1, a1=a1, b0=b0: add(b1, add(mul(sub(a1, b1), 1.0 - u), mul(sub(b0, b1), 1.0 - v)))),
            )
        else:
            pieces = (
                (lambda u, v: u - v, lambda u, v, a0=a0, b0=b0, b1=b1: add(a0, add(mul(sub(b0, a0), u), mul(sub(b1, b0), v)))),
                (lambda u, v: v - u, lambda u, v, a0=a0, b1=b1, a1=a1: add(a0, add(mul(sub(b1, a1), u), mul(sub(a1, a0), v)))),
            )
        facing = unit(cross(sub(b0, a0), sub(a1, a0)))
        if dot(facing, add(n0, n1)) < 0:
            facing = mul(facing, -1.0)
        for keep, put in pieces:
            piece = clip(poly, keep)
            if len(piece) < 3:
                continue
            ids = []
            for u, v in piece:
                up = mul(unit(add(mul(n0, 1.0 - v), mul(n1, v))), lift)
                ids.append(mesh.vert(add(put(u, v), up)))
            for m in range(1, len(ids) - 1):
                mesh.tri(ids[0], ids[m], ids[m + 1], facing)


def membrane(mesh: Mesh, lefts, rights, facing) -> None:
    """A two-sided sheet between two rows of points (the dark eye): drawn from both sides, since a
    SpecialMesh culls back faces. Each side has its own copies of the points: a back face on the front's
    own vertices is the same face to Blender, whose mesh validation deletes it."""
    for f in (facing, mul(facing, -1.0)):
        a = [mesh.vert(p) for p in lefts]
        b = [mesh.vert(p) for p in rights]
        for k in range(len(a) - 1):
            mesh.tri(a[k], b[k], b[k + 1], f)
            mesh.tri(a[k], b[k + 1], a[k + 1], f)


# =================================================================================================
# The Loop
# =================================================================================================

# The stroke's control points in the loop's own plane (x, z), in one breath: the short tail's cut end
# (front right), the first crossing, down the left (the thick downstroke), round the trailing end, up
# the right (the hairline), the second crossing over the first, and the long tail out to the needle.
LOOP_CTRL = [
    (0.245, -0.42),  # 0 short tail, cut end (front right)
    (0.135, -0.28),  # 1
    (0.0, -0.11),  # 2 first crossing
    (-0.115, 0.0),  # 3
    (-0.19, 0.12),  # 4 thick downstroke
    (-0.205, 0.25),  # 5
    (-0.165, 0.37),  # 6
    (-0.07, 0.448),  # 7
    (0.035, 0.462),  # 8 the trailing end
    (0.135, 0.415),  # 9
    (0.185, 0.3),  # 10 hairline
    (0.17, 0.14),  # 11
    (0.1, 0.0),  # 12
    (0.0, -0.11),  # 13 second crossing
    (-0.095, -0.235),  # 14
    (-0.12, -0.35),  # 15
    (-0.105, -0.46),  # 16
    (-0.075, -0.565),  # 17 needle point
]
LOOP_PER = 6  # Catmull-Rom samples per span before resampling
LOOP_ROWS = 72
LOOP_CROSS_GAP = 0.034  # how far over (first pass) and under (second) the crossing each pass runs
LOOP_TWIST = math.radians(44)  # the loop plane's turn about Z from its middle to either end
LOOP_STAND = math.radians(60)  # how far the ribbon stands up round the trailing end
LOOP_STAND_SPREAD = (0.34, 0.13)  # how slowly it stands up: along the downstroke, along the hairline
LOOP_THICK = 0.026
LOOP_HULL_SIDE = 0.034  # contour beyond each edge, plus a share of the width (the plein is heavier)
LOOP_HULL_SHARE = 0.05
LOOP_HULL_FACE = 0.018  # contour over each face
LOOP_HULL_TIP = 0.028
EYE_SHARE = 0.54  # how far back from the crossing the dark eye fills the loop
EYE_START = 0.04
CORE_LIFT = 0.011  # the pale off its face: 0.03 stud at a 3.2-stud Length (bible: 0.03 to 0.08)
FLOW_LIFT = 0.014  # the ink flow lines ride just over it
EYE_FILL = 0.8  # share of the room between the two strands' spines the eye spans


def _loop_line():
    dense = catmull(LOOP_CTRL, LOOP_PER)
    line = Polyline(dense)
    total = line.acc[-1]
    marks = [line.acc[i * LOOP_PER] / total for i in range(len(LOOP_CTRL))]
    return line, marks


def _loop_frames():
    line, s = _loop_line()
    s_cross1, s_cross2 = s[2], s[13]
    s_end = s[8]
    width_ctrl = [
        (0.0, 0.085), (s[1], 0.1), (s_cross1, 0.07), (s[3], 0.13), (s[4], 0.175), (s[5], 0.175), (s[6], 0.15),
        (s_end, 0.145), (s[9], 0.12), (s[10], 0.085), (s[11], 0.072), (s[12], 0.065), (s_cross2, 0.06),
        (s[14], 0.1), (s[15], 0.092), (s[16], 0.06), (1.0, 0.0),
    ]
    rows = []
    zs = [p[1] for p in LOOP_CTRL]
    z_mid = 0.5 * (min(zs) + max(zs))
    z_half = 0.5 * (max(zs) - min(zs))
    loop_centre = (0.0, 0.1)

    def point(t: float):
        x, z = line.at(t)
        bump1 = math.exp(-(((t - s_cross1) / 0.07) ** 2)) if t < s_cross1 else math.exp(-(((t - s_cross1) / 0.05) ** 2))
        bump2 = math.exp(-(((t - s_cross2) / 0.05) ** 2)) if t < s_cross2 else math.exp(-(((t - s_cross2) / 0.09) ** 2))
        y = LOOP_CROSS_GAP * (bump1 - bump2)
        alpha = LOOP_TWIST * max(-1.0, min(1.0, (z - z_mid) / z_half))
        ca, sa = math.cos(alpha), math.sin(alpha)
        return (x * ca - y * sa, x * sa + y * ca, z), alpha, (x, z)

    previous_normal = None
    for i in range(LOOP_ROWS + 1):
        t = i / LOOP_ROWS
        p, alpha, (x, z) = point(t)
        a, _, _ = point(max(0.0, t - 1e-3))
        b, _, _ = point(min(1.0, t + 1e-3))
        tangent = unit(sub(b, a))
        plane = (-math.sin(alpha), math.cos(alpha), 0.0)
        outward = unit(cross(tangent, plane))
        local_out = (x - loop_centre[0], z - loop_centre[1])
        world_out = (local_out[0] * math.cos(alpha), local_out[0] * math.sin(alpha), local_out[1])
        if dot(outward, world_out) < 0:
            outward = mul(outward, -1.0)
        # Standing up round the trailing end: the face turns from the loop's plane to face back.
        # Slow on the wide downstroke, quick on the hairline: a fast turn on a wide face folds its quads
        # until, seen at a grazing angle, half of each turns its contour toward the eye (a fan of hairlines).
        spread = LOOP_STAND_SPREAD[0] if t < s_end else LOOP_STAND_SPREAD[1]
        stand = LOOP_STAND * math.exp(-(((t - s_end) / spread) ** 2))
        normal = unit(add(mul(plane, math.cos(stand)), mul(outward, math.sin(stand))))
        normal = unit(sub(normal, mul(tangent, dot(normal, tangent))))
        if previous_normal is not None and dot(normal, previous_normal) < 0:
            normal = mul(normal, -1.0)
        previous_normal = normal
        across = unit(cross(tangent, normal))
        wobble = 1.0 + 0.08 * (fbm(5.0 * t, 0.7, LOOP_SEED) * 2.0 - 1.0)
        width = cosine_curve(width_ctrl, t) * wobble
        # Where the stroke turns tighter than the ribbon is wide in its own plane, its inner edge would
        # fold over itself (a fan of hairlines of hull through the face): the width yields there.
        pa, _, _ = point(max(0.0, t - 0.01))
        pb, _, _ = point(min(1.0, t + 0.01))
        chord = math.dist(pa, pb)
        bend = math.acos(max(-1.0, min(1.0, dot(unit(sub(p, pa)), unit(sub(pb, p))))))
        radius = chord / max(bend, 1e-6)
        flat = abs(dot(across, outward))
        if flat > 1e-3:
            width = min(width, 1.6 * radius / flat)
        thick = LOOP_THICK * min(1.0, 0.45 + 6.0 * width)
        rows.append({"t": t, "p": p, "tangent": tangent, "across": across, "normal": normal, "width": width, "thick": thick})
    return rows, s


def _loop_build():
    frames, s = _loop_frames()
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    n = len(frames)
    # The short tail is cut on the slant: its first row collapses onto one edge.
    first = frames[0]
    cut = add(first["p"], mul(first["across"], 0.5 * first["width"]))
    rows = [(cut,)]
    for f in frames[1:-1]:
        rows.append((f["p"], f["across"], f["normal"], rect(f["width"], f["thick"])))
    rows.append((frames[-1]["p"],))
    skin(body, rows, [()] * (n - 1), inward=False, cross_edges=(2,))

    hull = []
    f0 = frames[0]
    hull.append((add(cut, add(mul(f0["tangent"], -LOOP_HULL_TIP), mul(f0["across"], 0.4 * LOOP_HULL_TIP))),))
    for f in frames[1:-1]:
        side = LOOP_HULL_SIDE + LOOP_HULL_SHARE * f["width"]
        hull.append((f["p"], f["across"], f["normal"], bevel(f["width"], f["thick"], side, LOOP_HULL_FACE)))
    fl = frames[-1]
    hull.append((add(fl["p"], mul(fl["tangent"], LOOP_HULL_TIP)),))
    skin(ink, hull, [()] * (n - 1), inward=True, cross_edges=(4,))

    # Corners of the full rows (indices 1..n-2 of frames), for the streaks and the flow lines.
    corners = [place(*row) for row in rows[1:-1]]
    normals = [f["normal"] for f in frames[1:-1]]
    ts = [f["t"] for f in frames[1:-1]]

    def span(lo: float, hi: float):
        idx = [k for k, t in enumerate(ts) if lo <= t <= hi]
        return idx[0], idx[-1]

    # Pale: one streak down the thick downstroke, one round the trailing end (the face the thrower sees).
    a, b = span(s[3] + 0.01, s[5] + 0.01)
    lens(core, corners, normals, (0, 1), a, b, 0.62, 0.16, CORE_LIFT)
    a, b = span(s[6] + 0.01, s[9])
    lens(core, corners, normals, (0, 1), a, b, 0.45, 0.085, CORE_LIFT)
    # Ink flow lines: tapered lines along the faces, of unequal length, never parallel.
    a, b = span(s[4] - 0.02, s[6] + 0.02)
    lens(ink, corners, normals, (0, 1), a, b, 0.2, 0.07, FLOW_LIFT)
    a, b = span(s[13] + 0.01, s[15] + 0.02)
    lens(ink, corners, normals, (0, 1), a, b, 0.35, 0.08, FLOW_LIFT)

    # The dark eye: the narrow front of the loop, from just behind the crossing back, closing in a
    # round edge -- the chas the stitch is threaded through.
    left_line = [f for f in frames if s[2] <= f["t"] <= s[8]]
    right_line = [f for f in frames if s[8] <= f["t"] <= s[13]][::-1]

    def along(seq, u):
        x = u * (len(seq) - 1)
        k = min(int(x), len(seq) - 2)
        return lerp(seq[k]["p"], seq[k + 1]["p"], x - k)

    eye_rows = 16
    knee = 0.3
    lefts, rights = [], []
    for k in range(eye_rows + 1):
        f = k / eye_rows
        u = EYE_START + (EYE_SHARE - EYE_START) * f
        lp, rp = along(left_line, u), along(right_line, u)
        mid = lerp(lp, rp, 0.5)
        g = EYE_FILL
        if f > knee:
            q = (f - knee) / (1.0 - knee)
            g = EYE_FILL * math.sqrt(max(0.0, 1.0 - q * q))
        lefts.append(lerp(mid, lp, g))
        rights.append(lerp(mid, rp, g))
    membrane(ink, lefts, rights, (0.0, 1.0, 0.0))

    # Normalise: the Length along Z (all three meshes, contour included) is 1, centred on the pivot.
    zs = [v[2] for m in (body, core, ink) for v in m.verts]
    z0, z1 = min(zs), max(zs)
    for m in (body, core, ink):
        m.translate((0.0, 0.0, -0.5 * (z0 + z1)))
        m.scale(1.0 / (z1 - z0))
    return body, core, ink


_CACHE: dict = {}


def _loop():
    if "loop" not in _CACHE:
        _CACHE["loop"] = _loop_build()
    return _CACHE["loop"]


def _loop_meta() -> dict:
    return {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": LOOP_SEED}


def loop_body():
    return _loop()[0], _loop_meta()


def loop_core():
    return _loop()[1], _loop_meta()


def loop_ink():
    return _loop()[2], _loop_meta()
HULL_SIDE = 0.114  # the contour beyond each cord's edge, in studs
ROPE_RR = 0.06  # how far each pass winds out from the rope's centre line, across the ring (radially)
ROPE_RY = 0.26  # ... and up and down: three lanes stacked like the in-game coil, the band about 1 stud
ROPE_TURNS = 1  # turns the cord makes round the rope centre line over its three passes
CORDS = 3
CORD_ROWS = 26
CORD_WIDTH = 0.30
CORD_THICK = 0.16
KNOTS = 4
KNOT_ROWS = 10
KNOT_WIDTH = 0.19
KNOT_THICK = 0.09
KNOT_LEAN = (0.6, 0.95)  # how far a knot's plane leans toward the outside and toward the top
KNOT_ROOM = 0.05  # air between a knot and the rope it binds
KNOT_HULL = 0.1  # beyond each knot edge
KNOT_HULL_FACE = 0.05
BUNDLE_ROWS = 24
BUNDLE_SIDES = 8
RING_R = 1.18  # the rope's centre line: the knots' outer ink lands on TIGHT / 2


def _ring_axes(theta: float):
    radial = (math.cos(theta), 0.0, -math.sin(theta))
    tangent = (-math.sin(theta), 0.0, -math.cos(theta))
    return radial, tangent


def _cord_rows(rng: Rng):
    """One cord laid three times round the ring, turning a third of the way round the rope's centre line
    each time, so the three passes lie side by side as three lanes that slowly change places: the three
    interlocking loops, closed on themselves as one stitch."""
    phase = 0.3 * (rng.random() - 0.5)
    seed = SHACKLE_SEED + 37

    def point(theta: float):
        radial, _ = _ring_axes(theta)
        phi = ROPE_TURNS * theta / CORDS + phase
        wob = 1.0 + 0.1 * (fbm(2.0 * theta / math.pi, 0.4, seed) * 2.0 - 1.0)
        c, s = math.cos(phi), math.sin(phi)
        offset = add(mul(radial, ROPE_RR * c * wob), (0.0, ROPE_RY * s * wob, 0.0))
        # The ellipse's outward normal: the cord's face looks away from the rope's centre line.
        out = unit(add(mul(radial, c / ROPE_RR), (0.0, s / ROPE_RY, 0.0)))
        return add(mul(radial, RING_R), offset), out

    rows = []
    count = CORD_ROWS * CORDS
    for i in range(count):
        theta = 2.0 * math.pi * CORDS * i / count
        p, out = point(theta)
        a, _ = point(theta - 1e-3)
        b, _ = point(theta + 1e-3)
        tangent = unit(sub(b, a))
        normal = unit(sub(out, mul(tangent, dot(out, tangent))))
        across = unit(cross(tangent, normal))
        width = CORD_WIDTH * (1.0 + 0.1 * (fbm(3.0 * i / CORD_ROWS, 0.2, seed) * 2.0 - 1.0))
        rows.append((p, across, normal, width))
    return rows


def _rope_reach():
    """How far the rope (cords and their contour) reaches from its centre line, across and up."""
    across = ROPE_RR + CORD_WIDTH / 2.0 + HULL_SIDE
    up = ROPE_RY * 1.1 + CORD_THICK / 2.0 + HULL_SIDE
    return across, up


def _bundle_hull(mesh: Mesh) -> None:
    """ONE inverted hull round the whole three-pass rope: an ellipse section along the ring, 0.1 stud
    beyond the cords' envelope, so overlapping passes never double into black bars."""
    a, b = _rope_reach()
    section = [(a * math.cos(2 * math.pi * i / BUNDLE_SIDES), b * math.sin(2 * math.pi * i / BUNDLE_SIDES)) for i in range(BUNDLE_SIDES)]
    rows = []
    for i in range(BUNDLE_ROWS + 1):
        theta = 2.0 * math.pi * (i % BUNDLE_ROWS) / BUNDLE_ROWS
        radial, _ = _ring_axes(theta)
        rows.append((mul(radial, RING_R), radial, (0.0, 1.0, 0.0), section))
    skin(mesh, rows, [()] * BUNDLE_ROWS, inward=True)


def _knot_rows(k: int, rng: Rng):
    """A loop bound round the rope, its plane leaning out of the rope's cross-section toward the outside
    and toward the top at once, so that it shows as an open ring from above (the model sheet's
    top-down) and as an oval wrapped round the band from the side (its perspective), never edge-on as a
    bar. It is an ellipse that clears the rope's own section, cut by that leaning plane, all round."""
    theta = 2.0 * math.pi * k / KNOTS + math.radians(7.0) * (rng.random() * 2.0 - 1.0)
    radial, tangent = _ring_axes(theta)
    centre = mul(radial, RING_R)
    # Every knot leans out the same way: one leaning in stood edge-on to a raised eye outside the ring
    # (the thrower's, and the target's), a lone stick across the band.
    out_lean = KNOT_LEAN[0] * (1.0 + 0.2 * (rng.random() * 2.0 - 1.0))
    up_lean = KNOT_LEAN[1] * (1.0 + 0.15 * (rng.random() * 2.0 - 1.0))
    n = unit(add(tangent, add(mul(radial, out_lean), (0.0, up_lean, 0.0))))
    e1 = unit(cross(n, tangent))
    e2 = unit(cross(n, e1))
    reach_across, reach_up = _rope_reach()
    margin = KNOT_THICK * 0.5 + KNOT_ROOM

    def rope_radius(e):
        return 1.0 / math.sqrt((dot(e, radial) / reach_across) ** 2 + (e[1] / reach_up) ** 2)

    a = rope_radius(e1) + margin
    flat = sub(e2, mul(tangent, dot(e2, tangent)))
    s = math.sqrt(dot(flat, flat))
    b = (rope_radius(unit(flat)) + margin) / s
    rows = []
    for i in range(KNOT_ROWS):
        psi = 2.0 * math.pi * i / KNOT_ROWS + 0.4 * k
        p = add(centre, add(mul(e1, a * math.cos(psi)), mul(e2, b * math.sin(psi))))
        d = add(mul(e1, -a * math.sin(psi)), mul(e2, b * math.cos(psi)))
        tangent_k = unit(d)
        out = unit(add(mul(e1, math.cos(psi) / a), mul(e2, math.sin(psi) / b)))
        normal = unit(sub(out, mul(tangent_k, dot(out, tangent_k))))
        across = unit(cross(tangent_k, normal))
        rows.append((p, across, normal, KNOT_WIDTH))
    return rows


def _closed(rows, thick, side, face, mesh, inward):
    out = []
    for p, across, normal, width in rows:
        out.append((p, across, normal, rect(width + 2 * side, thick + 2 * face)))
    out.append(out[0])
    skin(mesh, out, [()] * (len(out) - 1), inward=inward, cross_edges=(2,))
    return out


def _shackle_build():
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    rng = Rng(SHACKLE_SEED)
    rows = _cord_rows(rng)
    knots = [_knot_rows(k, rng) for k in range(KNOTS)]
    built = _closed(rows, CORD_THICK, 0.0, 0.0, body, inward=False)
    _bundle_hull(ink)
    corners = [place(*row) for row in built]
    normals = [row[2] for row in rows] + [rows[0][2]]
    count = len(rows)
    # A pale streak along the cord's face on each pass, between two knots; a flow line on two passes.
    # Streaks stay inside the stretch between two knots (knots sit at rows 6.5, 13, 19.5 of a pass).
    for k, (a, n) in enumerate(((8, 4), (14, 4), (21, 4))):
        start = k * CORD_ROWS + a
        lens(core, corners, normals, (0, 1), start, start + n, 0.5, 0.17, 0.04)
    for start, n, spread in ((9, 3, 0.05), (16, 4, 0.07), (22, 3, 0.04)):
        lens(ink, corners, normals, (0, 1), start + CORD_ROWS * (start % 3), start + CORD_ROWS * (start % 3) + n, 0.18, spread, 0.05)
    for knot in knots:
        _closed(knot, KNOT_THICK, 0.0, 0.0, body, inward=False)
        hull = [(p, ac, nm, bevel(w, KNOT_THICK, KNOT_HULL, KNOT_HULL_FACE)) for p, ac, nm, w in knot]
        hull.append(hull[0])
        skin(ink, hull, [()] * (len(hull) - 1), inward=True)
    reach = max(math.hypot(x, z) for m in (body, core, ink) for x, _, z in m.verts)
    for m in (body, core, ink):
        m.scale(0.5 / reach)
    return body, core, ink


def _shackle():
    if "shackle" not in _CACHE:
        _CACHE["shackle"] = _shackle_build()
    return _CACHE["shackle"]


def _shackle_meta() -> dict:
    return {"Reference": "Diameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": SHACKLE_SEED}


def shackle_body():
    return _shackle()[0], _shackle_meta()


def shackle_core():
    return _shackle()[1], _shackle_meta()


def shackle_ink():
    return _shackle()[2], _shackle_meta()
