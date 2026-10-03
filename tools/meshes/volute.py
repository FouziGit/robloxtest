"""The Volute's coil (Indigo + Umber, charged melee): a flat indigo ribbon wound round a pale eye, with more air than ink.

Drawn after the developer's two references (docs/vfx/volute/ref-2.jpg, the model sheet: a faceted
log spiral of 2.5 turns, "Wide Gaps (Open Air)", a pale eye, an outer turn ending in a hook; ref-1.jpg,
the in-game shot, for its scale against the avatar and its thick ink contour).

The sheet's spiral, traced in polar coordinates round the eye, is two arms wound like a yin-yang, both
travelling counter-clockwise outward on the sheet:
  - the main arm: its tail is a sliver tucked against the eye, it wraps the eye for 150 degrees while
    it loads into the sheet's fat head at the right of the eye, lifts off at the upper right (the V
    notch), and winds out 1.75 turns more, dry and thin, to a hook that curls back toward the centre
    round a hole of paper;
  - the comma: its root is a sliver tucked under the main arm's lift-off, it wraps the eye's top and
    left side, lifts off at the lower left and runs half a turn out to a sickle that floats in its gap.
Each arm is a slab of hard facets (a polygon of ~15 sides a turn), thick where it leaves the eye.

The laps carry 14-16 px of pigment, a shade under the sheet's
15-20, so that once inked the gaps are about as wide as the bands, and the slab is thinner so they stay
open further off-axis. The ink contour stays 9.8 px (0.1 stud at 6 studs): the air is paid in
pigment share, which drops under the bible's 60 % -- that is the developer's call (a DECISIONS entry).
The sickle tapers to a blade, the hook curls round a real hole, every hull wall that lies over another
stroke's pigment is held under that pigment's face (no seam at the lift-off, under the Spin), the
tail's ink point sinks into the eye's ring, and the flow lines are brush strokes that cross the band.

Roblox space: X right, Y up, forward -Z; the coil lies in the XY plane and the game spins it about Z.
The face that comes at the target (-Z) is the sheet's FRONT view; the thrower (+Z) sees its mirror,
where the arms wind clockwise outward, so the charge's Spin of -10 (clockwise from behind) makes them
flow in toward the eye: a coil that winds itself up (bible 5.3).

Three meshes, one tone each: volute_body (Pigment: the two arms), volute_eye (Core: the domed eye),
volute_ink (Ink: the inverted hull of each arm and of the eye, and the flow lines on both faces).
"""

from __future__ import annotations

import math

from strokes import Mesh, catmull, fbm, pressure

SEED = 5591

# Units while building: pixels of the model sheet's front view (ref-2.jpg, eye at 339, 455), so every
# key below reads against the trace. Normalised at the end: the farthest ink from the eye is 0.5.
CONTOUR = 6.0  # the ink contour all round, in the plane and over each face: 0.064 stud at 6 studs
EYE_R = 31.0  # the pale eye: the sheet's, 62 px across
EYE_DEPTH = 0.78  # its dome along Z, a share of its radius: it stands out of both faces, but edge-on
#                   the pale stays under Indigo's 10 % cap
EYE_HULL = CONTOUR  # its ink ring
EYE_BAND = EYE_R + EYE_HULL + 1.0  # where an arm that hugs the eye has its inner edge
HULL_SIDE = CONTOUR  # the arms' contour, in the plane
HULL_FACE = CONTOUR  # and over each face: the outline of the slab seen edge-on
HULL_TIP = 8.0  # past a pointed end
HOOK_TIP = 5.0  # past the hook's blunt end
TAIL_SINK = 0.7  # the main arm's tail: its ink point sinks this far into the eye's ring (share of the ring)
STEP = 24.0  # degrees between facets
CLEAR = 1.5  # a hull wall over another stroke's pigment stays this far under that pigment's face
REACH = HULL_SIDE + 2.0  # ... and so does one that comes this close to it: anywhere in its contour

# (theta degrees, counter-clockwise on the sheet; centre radius; pigment width). A centre of 0 hugs the
# eye. Centres are the sheet's own (the middle of each band's pigment along its arm),
# but for the outer end, which runs out a little past the sheet so the hook's curl has room inside it.
# Widths are the sheet's too: where an arm hugs the eye its outer edge is the sheet's; where it is free
# it is the sheet's 19-21 px of pigment, loaded where it leaves the eye and drying toward the hook.
# Between two laps that leaves 35-40 px of paper, the sheet's "Wide Gaps (Open Air)".
MAIN = [
    (252, 0, 0), (268, 0, 7), (295, 0, 11), (325, 0, 15), (352, 0, 21), (372, 0, 31), (387, 0, 40),
    (403, 0, 54), (415, 83, 40), (427, 97, 31), (440, 107, 26), (455, 114, 23), (480, 118.5, 21),
    (510, 119.5, 21), (540, 124.5, 21), (570, 133.5, 21), (600, 145, 21), (630, 158, 21),
    (660, 167.5, 21), (690, 178, 21), (720, 191, 21), (750, 193.5, 21), (780, 194, 21), (810, 194, 21),
    (840, 190.5, 20), (870, 189, 20), (900, 194, 20), (930, 203, 20), (960, 216, 20), (990, 233, 19),
    (1015, 245, 19), (1030, 251.5, 19), (1044, 258, 19),
]
COMMA = [
    (12, 0, 0), (26, 0, 6), (50, 0, 11), (90, 0, 16), (135, 0, 19), (180, 0, 25), (205, 0, 32),
    (218, 0, 38), (232, 63, 34), (246, 73, 28), (262, 82, 23), (282, 92.5, 21), (300, 100, 19),
    (330, 109, 18), (360, 121, 16), (380, 129, 12), (398, 136.5, 6), (416, 142, 0),
]
HOOK_RADIUS = 24.0  # the curl at the main arm's end, on its centre line, where it leaves the arm
HOOK_TIGHTEN = 0.85  # the share of that radius left where the curl ends (never under the band's half plus its contour)
HOOK_CURL = 200.0  # degrees the end curls through: past a half turn, so the claw hangs back beside the arm
HOOK_THIN = 0.3  # the share of its width the claw loses before its point
HOOK_LEG = 18.0  # the point past the curl
HOOK_STEPS = 9


def thickness(width: float) -> float:
    """The slab: nearly as deep as the band is wide, the sheet's side view (a rod about 18 px deep under
    its contour where a lap is 21 wide), deeper where the arm is loaded, never thinner than 14."""
    return min(20.0, max(14.0, 0.85 * width))


# --- the arms' centre lines ----------------------------------------------------------------------


def dense(keys):
    """Catmull-Rom through (theta, radius, width) keys, a hugging key's radius filled in first, so the
    arm leaves the eye on a smooth curve instead of a jump from 0."""
    pts = [(float(t), max(float(r), EYE_BAND + w / 2.0), float(w)) for t, r, w in keys]
    return catmull(pts, 24)


def at_theta(line, theta: float):
    for i in range(1, len(line)):
        if line[i][0] >= theta:
            a, b = line[i - 1], line[i]
            f = (theta - a[0]) / max(b[0] - a[0], 1e-9)
            return tuple(a[k] + (b[k] - a[k]) * f for k in range(3))
    return line[-1]


def rows(keys, step: float) -> int:
    return max(2, round((keys[-1][0] - keys[0][0]) / step))


def samples(keys, step: float):
    """(x, y, width) along an arm at facet steps, sheet space (x right, y up, pixels)."""
    line = dense(keys)
    t0, t1 = keys[0][0], keys[-1][0]
    count = rows(keys, step)
    out = []
    for i in range(count + 1):
        theta = t0 + (t1 - t0) * i / count
        _, r, w = at_theta(line, theta)
        w = max(0.0, w) * (1.0 + 0.06 * (fbm(theta / 90.0, 0.4, SEED) * 2.0 - 1.0))
        r = max(r, EYE_BAND + w / 2.0)
        a = math.radians(theta)
        out.append((r * math.cos(a), r * math.sin(a), w))
    return out


def hook(points):
    """The main arm's end: a claw that curls in toward the centre, its radius tightening as it goes (the
    sheet's hook, round a narrow slot of paper), and closes in a short point."""
    (x0, y0, w0), (x1, y1, _) = points[-1], points[-2]
    heading = math.atan2(y0 - y1, x0 - x1)  # turning left (counter-clockwise) curls it inward
    x, y = x0, y0
    total = math.radians(HOOK_CURL)
    sub = 8
    dphi = total / (HOOK_STEPS * sub)
    out = []
    for k in range(HOOK_STEPS):
        for j in range(sub):
            f = (k * sub + j + 0.5) / (HOOK_STEPS * sub)
            r = HOOK_RADIUS * (1.0 - (1.0 - HOOK_TIGHTEN) * f)
            x += r * dphi * math.cos(heading + dphi / 2.0)
            y += r * dphi * math.sin(heading + dphi / 2.0)
            heading += dphi
        out.append((x, y, w0 * (1.0 - HOOK_THIN * (k + 1) / HOOK_STEPS)))
    ex, ey, w1 = out[-1]
    hx, hy = math.cos(heading), math.sin(heading)
    for d, f in ((0.55, 0.72), (1.0, 0.0)):
        out.append((ex + hx * HOOK_LEG * d, ey + hy * HOOK_LEG * d, w1 * f))
    return out


# --- skinning ------------------------------------------------------------------------------------


def to_roblox(x: float, y: float, z: float):
    """Sheet space to Roblox: the sheet's front view is the face toward -Z, seen from -Z."""
    return (-x, y, z)


def frames(points):
    out = []
    n = len(points)
    for i, (x, y, w) in enumerate(points):
        ax, ay, _ = points[max(i - 1, 0)]
        bx, by, _ = points[min(i + 1, n - 1)]
        tx, ty = bx - ax, by - ay
        length = math.hypot(tx, ty) or 1.0
        tx, ty = tx / length, ty / length
        out.append(((x, y), (tx, ty), (-ty, tx), w))
    return out


def half_thick(points):
    return [thickness(w) / 2.0 for _, _, w in points]


def outline(points):
    """The pigment's footprint in the plane, one polygon a facet (a triangle where an end is a point),
    each with the lower of its two rows' face heights."""
    fr = frames(points)
    hp = half_thick(points)
    edges = []
    for (x, y), _, (nx, ny), w in fr:
        a = w / 2.0
        edges.append(((x + nx * a, y + ny * a), (x - nx * a, y - ny * a)))
    polys = []
    for i in range(len(edges) - 1):
        (l0, r0), (l1, r1) = edges[i], edges[i + 1]
        poly = [l0, l1, r1, r0]
        polys.append((i, poly, min(hp[i], hp[i + 1])))
    return polys


def _inside(p, poly) -> bool:
    x, y = p
    hit = False
    n = len(poly)
    for k in range(n):
        (x1, y1), (x2, y2) = poly[k], poly[(k + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def _distance(p, poly) -> float:
    if _inside(p, poly):
        return 0.0
    best = 1e9
    n = len(poly)
    for k in range(n):
        (x1, y1), (x2, y2) = poly[k], poly[(k + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        span = dx * dx + dy * dy
        f = 0.0 if span < 1e-12 else max(0.0, min(1.0, ((p[0] - x1) * dx + (p[1] - y1) * dy) / span))
        best = min(best, math.hypot(p[0] - x1 - f * dx, p[1] - y1 - f * dy))
    return best


def ceiling(p, own: str, row: int, own_face: float, footprints) -> float | None:
    """How high a hull wall at `p` may stand: under the face of any other stroke's pigment that covers
    it -- one at least as thick as this stroke, so the thinner of two strokes is the one tucked under
    -- and that it lies over or comes within REACH of (the other arm; or this arm's own far-off facets,
    as in the hook's curl). A wall within REACH of a pigment's edge stands inside that pigment's own
    contour: taller than its face, it would show over the pigment as a hairline from an oblique view."""
    top = None
    for name, polys in footprints.items():
        for j, poly, face in polys:
            if name == own and abs(j - row) <= 3:
                continue
            if face < own_face - 0.25:
                continue
            if _distance(p, poly) <= REACH:
                cap = max(0.5, face - CLEAR)
                top = cap if top is None else min(top, cap)
    return top


def walls(points, side: float, face: float, own=None, footprints=None):
    """Each row's two wall corners in the sheet (None for a pointed end) and their heights over the
    slab's middle: the face height, or lower where `ceiling` holds the wall under another stroke.
    Each facet of wall is sampled along its length, and both its corners come down to the lowest
    ceiling found, so a wall never steps up over a face between two corners that are clear of it."""
    fr = frames(points)
    hp = half_thick(points)
    spots = []
    for (x, y), _, (nx, ny), w in fr:
        a = w / 2.0 + side
        spots.append(None if w <= 1e-6 else ((x + nx * a, y + ny * a), (x - nx * a, y - ny * a)))
    heights = [None if spot is None else [hp[i] + face, hp[i] + face] for i, spot in enumerate(spots)]
    if footprints is not None:
        for i in range(len(spots) - 1):
            for s in (0, 1):
                ends = [spots[j][s] if spots[j] is not None else None for j in (i, i + 1)]
                if ends[0] is None and ends[1] is None:
                    continue
                p0 = ends[0] or ends[1]
                p1 = ends[1] or ends[0]
                low = None
                for q in range(9):
                    f = q / 8.0
                    top = ceiling((p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f), own, i,
                                  min(hp[i], hp[i + 1]), footprints)
                    if top is not None:
                        low = top if low is None else min(low, top)
                if low is not None:
                    for j in (i, i + 1):
                        if heights[j] is not None:
                            heights[j][s] = min(heights[j][s], low)
    return fr, spots, heights


def skin(mesh: Mesh, points, side: float, face: float, tips, inward: bool, own=None, footprints=None) -> None:
    """A slab along the points: a rectangle section of the point's width (plus `side`) by its
    thickness (plus `face`); an end of zero width is a single vertex, `tips[0]`/`tips[1]` past the first
    and last rows (a distance along the arm, or a point in the sheet). With `footprints`, every wall
    is held under the face of any other stroke's pigment it lies over or comes NEAR (`walls`)."""
    fr, spots, heights = walls(points, side, face, own, footprints)
    rows_ = []
    for i, ((x, y), (tx, ty), (nx, ny), w) in enumerate(fr):
        if w <= 1e-6:
            tip = tips[0] if i == 0 else tips[1]
            if isinstance(tip, tuple):
                rows_.append([mesh.vert(to_roblox(tip[0], tip[1], 0.0))])
            else:
                sign = -1.0 if i == 0 else 1.0
                rows_.append([mesh.vert(to_roblox(x + sign * tx * tip, y + sign * ty * tip, 0.0))])
            continue
        a = w / 2.0 + side
        hl, hr = heights[i]
        corners = [(a, hl), (-a, hr), (-a, -hr), (a, -hl)]
        rows_.append([mesh.vert(to_roblox(x + nx * u, y + ny * u, v)) for u, v in corners])
    sign = -1.0 if inward else 1.0

    def facing(i, e):
        (_, _), (tx, ty), (nx, ny), _ = fr[i]
        n = [(0, 0, 1), (-nx, -ny, 0), (0, 0, -1), (nx, ny, 0)][e]
        x, y, z = to_roblox(n[0], n[1], n[2])
        return (sign * x, sign * y, sign * z)

    for i in range(len(rows_) - 1):
        r0, r1 = rows_[i], rows_[i + 1]
        for e in range(4):
            f = (e + 1) % 4
            a0, b0 = r0[e % len(r0)], r0[f % len(r0)]
            a1, b1 = r1[e % len(r1)], r1[f % len(r1)]
            fc = facing(i, e)
            mesh.tri(a0, b0, b1, fc)
            mesh.tri(a0, b1, a1, fc)
    for i, back in ((0, True), (len(rows_) - 1, False)):
        ring = rows_[i]
        if len(ring) < 4:
            continue
        (_, _), (tx, ty), _, _ = fr[i]
        d = to_roblox(-tx if back else tx, -ty if back else ty, 0.0)
        d = (sign * d[0], sign * d[1], sign * d[2])
        mesh.tri(ring[0], ring[1], ring[2], d)
        mesh.tri(ring[0], ring[2], ring[3], d)


def sphere(mesh: Mesh, radius: float, depth: float, segments: int, rings: int, inward: bool) -> None:
    """A dome round the eye: `radius` in the plane, `depth` along Z, poles on Z."""
    top = mesh.vert((0.0, 0.0, depth))
    bottom = mesh.vert((0.0, 0.0, -depth))
    grid = []
    for r in range(1, rings):
        th = math.pi * r / rings
        grid.append([mesh.vert((radius * math.sin(th) * math.cos(2 * math.pi * (s + 0.5 * (r % 2)) / segments),
                                radius * math.sin(th) * math.sin(2 * math.pi * (s + 0.5 * (r % 2)) / segments),
                                depth * math.cos(th))) for s in range(segments)])
    sign = -1.0 if inward else 1.0

    def out(*ids):
        c = [sum(mesh.verts[i][k] for i in ids) / len(ids) for k in range(3)]
        return (sign * c[0], sign * c[1], sign * c[2])

    for s in range(segments):
        n = (s + 1) % segments
        mesh.tri(top, grid[0][s], grid[0][n], out(top, grid[0][s], grid[0][n]))
        mesh.tri(bottom, grid[-1][s], grid[-1][n], out(bottom, grid[-1][s], grid[-1][n]))
    for r in range(len(grid) - 1):
        for s in range(segments):
            n = (s + 1) % segments
            a, b, c, d = grid[r][s], grid[r][n], grid[r + 1][s], grid[r + 1][n]
            mesh.tri(a, b, c, out(a, b, c))
            mesh.tri(b, d, c, out(b, d, c))


# --- the flow lines -----------------------------------------------------------------------------
# (arm, from, to (theta on the arm, degrees), offset at each end (share of the half width, + is the
# arm's left: inward), peak width px). The bible's floor of two strokes a face, each a brush stroke
# that reads from the game camera (0.12-0.13 stud at its peak at 6 studs, 9.4 px a tenth of a stud):
# both lie where the arms are loaded -- the head and the comma's lift-off -- pressed in at their outer
# end and released toward the eye, the way the coil winds itself up under the charge's Spin, each
# crossing its band on a slant, of unequal lengths, never parallel. The back face (the thrower's) gets
# its own pair, so the two faces are not one stamp.
FLOW_FRONT = (("main", 412, 362, -0.7, 0.55, 12.0), ("comma", 254, 220, 0.7, -0.75, 11.0))
FLOW_BACK = (("main", 398, 344, 0.6, -0.65, 12.0), ("comma", 274, 238, 0.7, -0.7, 11.0))
FLOW_LIFT = 2.5  # off the face: 0.027 stud at 6 studs, clear of the face from every camera
FLOW_FLOOR = 0.22  # the thinnest a stroke gets, a share of its peak (surface_ribbon's)
FLOW_ATTACK = 0.2  # pressed in over the first fifth
FLOW_RELEASE = 0.55  # and eased off to 45 % at the end: a stroke that holds its weight across the band
FLOW_MARGIN = 1.5  # px kept between a stroke and its band's edge
FLOW_SAMPLES = 14


def on_arm(points, fi: float):
    """Position, unit normal (the arm's left), width and face height at fractional row `fi`: the centre
    runs straight between rows, so the line stays on the facet it lies on, and the normal turns from one
    row's to the next as the pigment's own corners do, so a stroke never folds at a facet's corner."""
    i = max(0, min(int(math.floor(fi)), len(points) - 2))
    f = min(max(fi - i, 0.0), 1.0)
    a, b = points[i], points[i + 1]
    fr = frames(points)
    (_, _), _, (n0x, n0y), _ = fr[i]
    (_, _), _, (n1x, n1y), _ = fr[i + 1]
    nx, ny = n0x + (n1x - n0x) * f, n0y + (n1y - n0y) * f
    length = math.hypot(nx, ny) or 1.0
    w = a[2] + (b[2] - a[2]) * f
    h = (thickness(a[2]) + (thickness(b[2]) - thickness(a[2])) * f) / 2.0
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f), (nx / length, ny / length), w, h


def flow(ink: Mesh, points, keys, t0, t1, o0, o1, width, side: float, seed: int) -> None:
    """A tapered ink stroke lying on one face of an arm (side +1: the thrower's face, +Z)."""
    count = rows(keys, STEP)
    k0, k1 = keys[0][0], keys[-1][0]
    lefts, rights = [], []
    for i in range(FLOW_SAMPLES):
        tau = 0.03 + 0.94 * i / (FLOW_SAMPLES - 1)
        theta = t0 + (t1 - t0) * tau
        (x, y), (nx, ny), w, h = on_arm(points, (theta - k0) / (k1 - k0) * count)
        half = max(pressure(tau, width, FLOW_ATTACK, FLOW_RELEASE, seed), width * FLOW_FLOOR) / 2.0
        room = w / 2.0 - FLOW_MARGIN
        half = min(half, room)
        centre = (o0 + (o1 - o0) * tau) * w / 2.0
        centre = max(-(room - half), min(room - half, centre))
        z = side * (h + FLOW_LIFT)
        lefts.append(ink.vert(to_roblox(x + nx * (centre + half), y + ny * (centre + half), z)))
        rights.append(ink.vert(to_roblox(x + nx * (centre - half), y + ny * (centre - half), z)))
    facing = (0.0, 0.0, side)
    for i in range(FLOW_SAMPLES - 1):
        ink.tri(lefts[i], rights[i], lefts[i + 1], facing)
        ink.tri(rights[i], rights[i + 1], lefts[i + 1], facing)


# --- the three meshes ----------------------------------------------------------------------------

_CACHE: dict = {}


def arms():
    main = samples(MAIN, STEP)
    main += hook(main)
    comma = samples(COMMA, STEP)
    return {"main": main, "comma": comma}


def tail_tip(points):
    """Where the main arm's tail ends its ink: sunk into the eye's ring, a little behind the pigment's
    point, so the contour closes into the ring instead of sticking out of it as a spike."""
    (x, y, _), (x1, y1, _) = points[0], points[1]
    r = EYE_R + TAIL_SINK * EYE_HULL
    a = math.atan2(y, x)
    back = math.atan2(y1, x1) - a  # the direction of travel, in angle
    a -= math.copysign(HULL_TIP / math.hypot(x, y), back)  # HULL_TIP behind the point, along the ring
    return (r * math.cos(a), r * math.sin(a))


def build():
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body, eye, ink = Mesh("up"), Mesh("up"), Mesh("up")
    strokes_ = arms()
    footprints = {name: outline(points) for name, points in strokes_.items()}
    tips = {"main": ((0.0, 0.0), (tail_tip(strokes_["main"]), HOOK_TIP)),
            "comma": ((0.0, 0.0), (HULL_TIP, HULL_TIP))}
    for name, points in strokes_.items():
        skin(body, points, 0.0, 0.0, tips[name][0], inward=False)
        skin(ink, points, HULL_SIDE, HULL_FACE, tips[name][1], inward=True, own=name, footprints=footprints)
    keys = {"main": MAIN, "comma": COMMA}
    n = 0
    for side, lines in ((-1.0, FLOW_FRONT), (1.0, FLOW_BACK)):
        for name, t0, t1, o0, o1, width in lines:
            flow(ink, strokes_[name], keys[name], t0, t1, o0, o1, width, side, SEED + 11 * n)
            n += 1
    sphere(eye, EYE_R, EYE_R * EYE_DEPTH, 14, 7, inward=False)
    sphere(ink, EYE_R + EYE_HULL, EYE_R * EYE_DEPTH + EYE_HULL, 14, 7, inward=True)
    reach = max(math.hypot(x, y) for mesh in (body, eye, ink) for x, y, _ in mesh.verts)
    for mesh in (body, eye, ink):
        mesh.scale(0.5 / reach)
    _CACHE["meshes"] = (body, eye, ink)
    return _CACHE["meshes"]


def meta() -> dict:
    return {"Reference": "Diameter", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": SEED}


def volute_body():
    return build()[0], meta()


def volute_eye():
    return build()[1], meta()


def volute_ink():
    return build()[2], meta()
