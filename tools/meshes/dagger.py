"""The Dagger's obelus: a verdigris dagger cross planted point-down, and the strike-out it leaves.

Drawn after the developer's two references (docs/vfx/dagger/ref-1.jpg, the in-game shot; ref-2.jpg, the
model sheet): a teardrop pommel on a small collar, a spindle grip on a ferrule, a crossguard whose arms
narrow and step out into serifed knobs either side of a diamond boss, a langet pointing down onto a narrow
ricasso with sloped shoulders, then a diamond-section pen blade tapering to the point, which enters the
page in a splash with a small dark hole. The pale is one thread on a facet beside the blade's ridge, on
both faces. Second form (the sheet's STRIKE-OUT inset): a vertical triangular-section pen stroke, pressed
in at the head, pointed at the foot, that crosses out the spot the caster left.

How the pieces and their contours are built:
- The contour is `hull()`, not strokes.inverted_hull: each vertex is pushed along its ANGLE-weighted
  normal, so a wide face never swallows a narrow one (the strike's flat back pushed its side edges
  backward and its outline vanished on one side). A volume may mitre its pushes (the strike, the splash's
  floor ring, so a sharp edge keeps its full contour), and a hull face the push turns over is dropped.
- The crossguard is ONE loft from knob to knob, the boss a swell at its middle: no arm root is buried
  in a boss, so no hull of a buried root shows as shards or as a line across the ricasso. Each knob steps
  out of a narrow neck, so seen end-on (the sheet's side view) the knob's own contour hugs it: otherwise the knob's sides are edge-on there and the ring seen is the neck's hull, a pigment gap away.
- A ring buried in another volume carries a contour weight near zero (the blade's top, the ferrule's and
  the grip's ends, the collar's top, the pommel's foot): its hull stays inside what buries it.
- The splash is one slab (a pool and five petals, two of them ending in a drop) with three loose drops:
  no tongue's hull wall rises through the pool, and the slab's top is never copied into the hull. The
  hole sits on the slab's top, lifted off it.
- Weights are written in studs at the posed height and hold after the normalisation (a hull divided by the ink's top would fall under 0.1 stud).
- The pale threads ride a facet off the ridge, never the ridge itself: seen from the side the ridge is
  the outline, and the pale must never touch it. The strike's thread is narrower (under 6 % seen).

Scale: Height = 6 studs for both forms (the sheet's "6 studs", one player). Contours never under
0.1 stud, Core and Ink overlays lifted 0.03 stud off their surface.

Roblox space: X right, Y up, forward -Z; the guard spans X, so the thrower (behind, +Z) sees the
cross face-on. Pivot (0, 0, 0) on the floor under the point; Height = 1 (ink included); nothing below
the floor.
"""

from __future__ import annotations

import math

from strokes import (
    FLOOR_CLEARANCE,
    Mesh,
    Rng,
    Volume,
    add,
    dot,
    emit,
    face_normal,
    fbm,
    mul,
    norm,
    sliver,
    sub,
)

SEED = 6311
STRIKE_SEED = 6331

# --- the size these are posed at ---------------------------------------------------------------------

HEIGHT_STUDS = 6.0  # ObelusBody/Core/Ink and StrikeBody/Core/Ink, Height in the timeline
CONTOUR = 0.1015  # studs: the lightest visible contour (bible: never under 0.1), a hair over it
LIFT_STUDS = 0.03  # studs: every Core and Ink overlay rides this far off its surface
BURIED = 0.0015  # mesh units: the weight of a ring buried in another volume (its hull stays inside it)

# The normalisation divides every mesh by the ink's top, so a weight written in studs is multiplied by
# that top first (build() measures it, then builds again with it).
_K = 1.0


def st(studs: float) -> float:
    """A length in studs at the posed height, in pre-normalisation mesh units."""
    return studs / HEIGHT_STUDS * _K


# --- profiles (model units: the point on the floor, the pommel's tip near 1) ------------------------

# The blade: (y, half width across X, half thickness along Z). The sheet's front view, measured: a long
# taper that falls fast under the shoulders and slowly down to a short point; a narrow ricasso under
# the guard, with sloped shoulders out to the full width. The ring at 0.652 is the last one under the
# guard; the one at 0.668 is buried in the boss.
BLADE = [
    (0.000, 0.0, 0.0),
    (0.014, 0.0040, 0.0045),
    (0.030, 0.0080, 0.0075),
    (0.055, 0.0135, 0.0110),
    (0.095, 0.0192, 0.0142),
    (0.170, 0.0242, 0.0160),
    (0.290, 0.0302, 0.0174),
    (0.410, 0.0348, 0.0187),
    (0.470, 0.0388, 0.0194),
    (0.540, 0.0428, 0.0200),
    (0.590, 0.0452, 0.0205),
    (0.606, 0.0452, 0.0205),
    (0.637, 0.0290, 0.0180),
    (0.652, 0.0285, 0.0180),
    (0.668, 0.0280, 0.0180),
]
BLADE_HULL = (CONTOUR, 0.107)  # studs: at the point, at the broad of the blade
BLADE_BURIED_FROM = 0.660  # rings above this lie inside the boss
BLADE_SCALE = 1.2  # the blade's width against the sheet's measure (the in-game shot's: 1.18)

GUARD_Y = 0.681
GUARD_LEN = 0.183  # each arm, from the axis
GUARD_RISE = 0.003  # the ends turn up or down a hair, each its own way (no perfect symmetry)
# The crossguard, one loft. Stations along each half from the axis: (s, half height, half depth, weight
# factor). At the axis the bar swells into the boss, a diamond seen from above (its depth falls about
# linearly to the bar's), deep enough that the ferrule and its contour stand on it. Out along the arm the
# bar is about 0.6 of the grip's width (both references), narrows to a neck, then steps out into the knob:
# the step is a flat ring facing the boss, which end-on carries the knob's contour (its weight is raised,
# since a 90-degree corner pushes its hull only 0.7 of the weight sideways). The knob rounds off into a
# small flat end. The section is a rounded square (flat faces up, down, front and back): end-on a block.
GUARD = [
    (0.00, 0.0228, 0.0440, 1.0),
    (0.10, 0.0212, 0.0306, 1.0),
    (0.22, 0.0172, 0.0150, 1.0),
    (0.74, 0.0134, 0.0105, 1.0),
    (0.835, 0.0120, 0.0090, 1.0),
    (0.858, 0.0117, 0.0087, 1.0),
    (0.858, 0.0248, 0.0212, 1.4),
    (0.945, 0.0252, 0.0216, 1.0),
    (0.978, 0.0226, 0.0193, 1.0),
    (1.000, 0.0155, 0.0132, 1.0),
]
GUARD_CORNER = 10.0  # degrees either side of each 45-degree corner: the section's 8 vertices
# The langet on each face of the ricasso: an ink V pointing down the blade, (top y, tip y, half width).
LANGET = (0.667, 0.618, 0.024)

# Round turned parts: (y, radius across X); Z radius is X times the ratio. A ring inside the next part
# (or the boss) gets the buried weight: index lists below.
FERRULE = [(0.700, 0.0240), (0.708, 0.0268), (0.718, 0.0222)]
GRIP = [(0.716, 0.0215), (0.765, 0.0256), (0.810, 0.0236), (0.850, 0.0170), (0.884, 0.0122)]
COLLAR = [(0.881, 0.0130), (0.892, 0.0172), (0.904, 0.0125)]
POMMEL = [(0.902, 0.0118), (0.910, 0.0218), (0.924, 0.0288), (0.940, 0.0305), (0.960, 0.0262), (0.983, 0.0148)]
POMMEL_TIP = 0.998
POMMEL_DEPTH = 0.86
TURN_SIDES = 8
SMALL_SIDES = 6
TURN_HULL = CONTOUR

# The pale thread on one facet of each face, beside the ridge: (top y, bottom y, inner u, outer u), u the
# share of the half width out from the ridge. Inner u keeps the lifted thread inside the ridge's outline
# seen from the side; it rides the -X facet on both faces (the facet the three-quarters view, the
# thrower's and the low view behind all look into, and the side view does not).
THREAD = (0.598, 0.15, 0.36, 0.60)

# The splash on the floor round the point: one slab. A pool, five petals (long and short, never in step),
# two of them necked into a drop at the end, and three loose drops.
POOL_R = 0.050
POOL_TOP = 0.0105  # the dome over the point
EDGE_H = (0.0074, 0.0066, 0.0060)  # top edge height at the pool, mid petal, petal tip
INSET = 0.0015  # the top edge sits this far inside the floor's outline (steep walls)
# (axis angle in degrees, reach, root half angle in radians, mid half width, tip radius, hook in radians)
PETALS = [
    (14.0, 0.118, 0.40, 0.0105, 0.0125, 0.16),
    (92.0, 0.086, 0.36, 0.0110, 0.0100, -0.12),
    (158.0, 0.128, 0.42, 0.0098, 0.0130, 0.20),
    (226.0, 0.092, 0.38, 0.0112, 0.0100, -0.10),
    (298.0, 0.110, 0.40, 0.0100, 0.0118, 0.14),
]
ARC_POINTS = 2  # pool outline points between two petals
DROPS = [(60.0, 0.112, 0.0110), (196.0, 0.150, 0.0100), (262.0, 0.122, 0.0125)]  # angle, distance, radius
HOLE_R = 0.020


# --- small helpers --------------------------------------------------------------------------------


def interp(table, y, col):
    """Linear interpolation of column `col` of a (y, ...) table at y."""
    if y <= table[0][0]:
        return table[0][col]
    for a, b in zip(table, table[1:]):
        if y <= b[0]:
            f = (y - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 0.0
            return a[col] + (b[col] - a[col]) * f
    return table[-1][col]


def wobble(x: float, y: float, seed: int, amount: float) -> float:
    """1 +- amount, the hand's unevenness."""
    return 1.0 + amount * (fbm(x, y, seed) * 2.0 - 1.0)


def closed_loft(rings, weights, bottom=None, top=None, bottom_w=None, top_w=None) -> Volume:
    """A closed volume through rings of equal size (consistently ordered), with a fan cap at each end:
    on the ring's centroid, or on an apex point when given. Wound outward."""
    vol = Volume()
    ids = [[vol.vert(p, w) for p in ring] for ring, w in zip(rings, weights)]
    n = len(rings[0])
    for r in range(len(ids) - 1):
        a, b = ids[r], ids[r + 1]
        for j in range(n):
            k = (j + 1) % n
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])

    def centroid(ring):
        return tuple(sum(p[i] for p in ring) / len(ring) for i in range(3))

    first, last = ids[0], ids[-1]
    i0 = vol.vert(bottom if bottom is not None else centroid(rings[0]), bottom_w if bottom_w is not None else weights[0])
    for j in range(n):
        emit(vol.mesh, i0, first[(j + 1) % n], first[j])
    i1 = vol.vert(top if top is not None else centroid(rings[-1]), top_w if top_w is not None else weights[-1])
    for j in range(n):
        emit(vol.mesh, i1, last[j], last[(j + 1) % n])
    vol.orient_outward()
    return vol


def lathe(profile, sides: int, depth: float, weights, phase: float = 0.0, bottom=None, top=None, top_w=None) -> Volume:
    rings = []
    for y, r in profile:
        rings.append([(r * math.cos(phase + 2 * math.pi * k / sides), y, depth * r * math.sin(phase + 2 * math.pi * k / sides)) for k in range(sides)])
    return closed_loft(rings, weights, bottom=bottom, top=top, top_w=top_w)


def turned_weights(count: int, buried: tuple[int, ...]) -> list[float]:
    full = st(TURN_HULL)
    return [BURIED if i in buried else full for i in range(count)]


def strip(mesh: Mesh, lefts, rights, facing) -> None:
    """Quads between two rails of points, every face turned toward `facing`."""
    for i in range(len(lefts) - 1):
        a, b = mesh.vert(lefts[i]), mesh.vert(rights[i])
        c, d = mesh.vert(rights[i + 1]), mesh.vert(lefts[i + 1])
        mesh.tri(a, b, c, facing)
        mesh.tri(a, c, d, facing)


def hull(vol: Volume, into: Mesh, mitre: float = 1.0, mitre_at=None, open_top: bool = False) -> None:
    """The inverted hull, as strokes.inverted_hull draws it (pushed out, wound the other way, held
    FLOOR_CLEARANCE over the floor, floor slivers dropped), with three changes. Each vertex is pushed along
    its ANGLE-weighted normal, so a wide face does not outweigh a narrow one at a shared edge. The push may
    be mitred: lengthened so that every face round the vertex moves out by the full weight, up to `mitre`
    times the weight (`mitre_at`, when given, names the vertices that may; the others are not). A hull face
    the push turned over (more than 90 degrees from its source) is dropped: it outlines nothing. And
    `open_top` drops the copies of the faces that look straight up, for a slab lying on the page: turned
    over they face down and are never seen, and pushed they can fold back up over the slab."""
    mesh = vol.mesh
    count = len(mesh.verts)
    acc = [(0.0, 0.0, 0.0)] * count
    around: list[list] = [[] for _ in range(count)]
    for a, b, c in mesh.tris:
        pa, pb, pc = mesh.verts[a], mesh.verts[b], mesh.verts[c]
        n = face_normal(pa, pb, pc)
        if dot(n, n) < 1e-24:
            continue
        unit = norm(n)
        for v, p, q, r in ((a, pa, pb, pc), (b, pb, pc, pa), (c, pc, pa, pb)):
            u, w = norm(sub(q, p)), norm(sub(r, p))
            angle = math.acos(max(-1.0, min(1.0, dot(u, w))))
            acc[v] = add(acc[v], mul(unit, angle))
            around[v].append(unit)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        n = norm(acc[i])
        reach = vol.weight[i]
        if mitre > 1.0 and (mitre_at is None or i in mitre_at):
            least = min((dot(n, f) for f in around[i]), default=1.0)
            reach = reach / max(least, 1.0 / mitre)
        q = add(p, mul(n, reach))
        into.verts.append((q[0], max(q[1], FLOOR_CLEARANCE), q[2]))
    for a, b, c in mesh.tris:
        corners = [into.verts[v + base] for v in (a, b, c)]
        if all(q[1] <= FLOOR_CLEARANCE for q in corners) and sliver(*corners):
            continue
        before = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
        if dot(before, before) < 1e-24:
            continue
        before = norm(before)
        if open_top and before[1] > 0.95:
            continue
        after = face_normal(*corners)
        if dot(after, after) > 1e-24 and dot(before, norm(after)) < 0.0:
            continue
        emit(into, a + base, c + base, b + base)


# --- the dagger ------------------------------------------------------------------------------------


def blade_section(y: float):
    """Half width and half thickness at y, with the hand's unevenness (a hair, never a wobble)."""
    broad = 1.0 + (BLADE_SCALE - 1.0) * min(1.0, max(0.0, (y - 0.04) / 0.4)) ** 0.8
    w = interp(BLADE, y, 1) * broad * wobble(4.0 * y, 0.3, SEED, 0.03)
    t = interp(BLADE, y, 2)
    return w, t


def on_blade(x: float, y: float, face: int, lift: float):
    """A point of the blade's face (face -1: front, -Z; +1: back) at x across, lifted along its facet."""
    w, t = blade_section(y)
    x = max(-w, min(w, x))
    z = t * (1.0 - abs(x) / w) if w > 0 else 0.0
    n = norm(((1.0 if x >= 0 else -1.0) * t, 0.0, face * w))
    return add((x, y, face * z), mul(n, lift))


def blade_volume() -> Volume:
    rings, weights = [], []
    ys = [row[0] for row in BLADE[1:]]
    for y in ys:
        w, t = blade_section(y)
        # The left edge leans a hair more than the right: no perfect symmetry.
        lean = 0.0006 * math.sin(7.0 * y)
        rings.append([(-w + lean, y, 0.0), (0.0, y, -t), (w + lean, y, 0.0), (0.0, y, t)])
        broad = min(1.0, y / 0.45)
        weight = st(BLADE_HULL[0] + (BLADE_HULL[1] - BLADE_HULL[0]) * broad)
        weights.append(BURIED if y > BLADE_BURIED_FROM else weight)
    return closed_loft(rings, weights, bottom=(0.0, 0.0, 0.0), bottom_w=st(BLADE_HULL[0]), top_w=BURIED)


def guard_ring(x: float, yc: float, h: float, d: float) -> list:
    """A rounded-square section across the bar: two vertices near each 45-degree corner, on the square."""
    ring = []
    for j in range(4):
        for sign in (-1.0, 1.0):
            a = math.radians(45.0 + 90.0 * j + sign * GUARD_CORNER)
            c, sn = math.cos(a), math.sin(a)
            k = 1.0 / max(abs(c), abs(sn))
            ring.append((x, yc + h * sn * k, d * c * k))
    return ring


def guard_volume(rng: Rng) -> Volume:
    """The crossguard, one loft from the left knob's end to the right one's, through the boss."""
    shape = {}
    for side in (-1, 1):
        length = GUARD_LEN * (1.0 + 0.015 * (rng.random() * 2.0 - 1.0))
        rise = GUARD_RISE * (rng.random() * 2.0 - 1.0)
        shape[side] = (length, rise)
    rows = [(-1, row) for row in reversed(GUARD[1:])] + [(1, row) for row in GUARD]
    rings, weights = [], []
    for side, (s, h, d, factor) in rows:
        length, rise = shape[side]
        x = side * s * length
        rings.append(guard_ring(x, GUARD_Y + rise * s * s, h, d))
        weights.append(st(CONTOUR) * factor)
    return closed_loft(rings, weights)


def langet(ink: Mesh, face: int) -> None:
    """The langet's V in ink on one face of the ricasso: two tapered strokes from under the boss's
    corners down to a point on the ridge, thicker at the top where the pen pressed."""
    top, tip, half = LANGET
    steps = 6
    lift = st(LIFT_STUDS)
    for sign in (-1.0, 1.0):
        lefts, rights = [], []
        for i in range(steps + 1):
            f = i / steps
            y = top + (tip - top) * f
            x = sign * half * (1.0 - f) ** 1.15
            width = 0.0062 * (1.0 - 0.75 * f)
            lefts.append(on_blade(x - sign * width / 2, y, face, lift))
            rights.append(on_blade(x + sign * width / 2, y, face, lift))
        strip(ink, lefts, rights, (0.0, 0.0, face))


def thread(core: Mesh, face: int) -> None:
    """The pale thread on the -X facet of one face, off the ridge; a lens pointed at both ends."""
    top, bottom, u_in, u_out = THREAD
    lift = st(LIFT_STUDS)
    steps = 14
    rows = []
    mid, half = (u_in + u_out) / 2, (u_out - u_in) / 2
    for i in range(steps + 1):
        f = i / steps
        y = top + (bottom - top) * f
        w, _ = blade_section(y)
        spread = half * math.sin(math.pi * f) ** 0.6
        rows.append(tuple(on_blade(-u * w, y, face, lift) for u in (mid - spread, mid, mid + spread)))
    for j in range(2):
        strip(core, [r[j] for r in rows], [r[j + 1] for r in rows], (0.0, 0.0, face))


# --- the splash ----------------------------------------------------------------------------------------


def _polar(angle: float, r: float):
    return (r * math.cos(angle), -r * math.sin(angle))


def splash_outline():
    """The slab's outline, counter-clockwise seen from above, as (x, z, top height, petal tag) points,
    and its triangulation: the pool polygon (root and arc points) fanned from the centre, each petal a
    strip from its root to its tip's centre, its round end fanned from there."""
    rng = Rng(SEED + 11)
    pts = []  # (x, z, edge height)
    pool_ids = []  # indices into pts of the pool polygon, in order
    petal_parts = []  # per petal: (root R id, side R ids..., tip ids, side L ids..., root L id, tip centre)
    order = sorted(PETALS, key=lambda p: p[0])
    for k, (deg, reach, root_half, mid_half, tip_r, hook) in enumerate(order):
        a = math.radians(deg)
        nxt = order[(k + 1) % len(order)]
        # Root points on the pool's rim, either side of the axis.
        rim = POOL_R * wobble(math.cos(a) * 2 + 3, math.sin(a) * 2, SEED + 5, 0.08)
        root_r = len(pts)
        pts.append((*_polar(a - root_half, rim), EDGE_H[0]))
        # Out along the petal: the mid station, the tip's centre (hooked sideways), the round end.
        mid_dist = rim + 0.5 * (reach - tip_r - rim)
        ma = a + hook * 0.35
        mc = _polar(ma, mid_dist)
        ta = a + hook
        tc = _polar(ta, reach - tip_r)
        # Out along the axis, and its left seen from above (counter-clockwise): the side the outline
        # comes back down after rounding the tip.
        def frame(angle):
            return (math.cos(angle), -math.sin(angle)), (-math.sin(angle), -math.cos(angle))

        (mx, mz), ((ux, uz), (lx, lz)) = mc, frame(ma)
        mid_r = len(pts)
        pts.append((mx - lx * mid_half, mz - lz * mid_half, EDGE_H[1]))
        (tx, tz), ((ux, uz), (lx, lz)) = tc, frame(ta)
        tip_ids = []
        for deg2 in (-90.0, -45.0, 0.0, 45.0, 90.0):
            g = math.radians(deg2)
            dx, dz = ux * math.cos(g) + lx * math.sin(g), uz * math.cos(g) + lz * math.sin(g)
            tip_ids.append(len(pts))
            pts.append((tx + dx * tip_r, tz + dz * tip_r, EDGE_H[2]))
        (mx, mz), ((ux, uz), (lx, lz)) = mc, frame(ma)
        mid_l = len(pts)
        pts.append((mx + lx * mid_half, mz + lz * mid_half, EDGE_H[1]))
        root_l = len(pts)
        pts.append((*_polar(a + root_half, rim), EDGE_H[0]))
        petal_parts.append((root_r, mid_r, tip_ids, mid_l, root_l, (tx, tz)))
        pool_ids += [root_r, root_l]
        # The pool's rim on to the next petal.
        a0, a1 = a + root_half, math.radians(nxt[0]) - nxt[2]
        if a1 < a0:
            a1 += 2 * math.pi
        for j in range(ARC_POINTS):
            g = a0 + (a1 - a0) * (j + 1) / (ARC_POINTS + 1)
            r = POOL_R * wobble(math.cos(g) * 2 + 3, math.sin(g) * 2, SEED + 5, 0.08) * (1.0 + 0.04 * (rng.random() - 0.5))
            pool_ids.append(len(pts))
            pts.append((*_polar(g, r), EDGE_H[0]))
    return pts, pool_ids, petal_parts


def splash_volume() -> Volume:
    """The splash: one slab lying on the page, walls nearly upright, its top a low dome to the point."""
    pts, pool_ids, petals = splash_outline()
    n = len(pts)
    # Outline order: the points were appended counter-clockwise already.
    outline = list(range(n))
    # Inset the top edge along the outline's inward normal.
    def inward(i):
        p, q, r = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
        e1 = norm((q[0] - p[0], 0.0, q[1] - p[1]))
        e2 = norm((r[0] - q[0], 0.0, r[1] - q[1]))
        # Counter-clockwise seen from above (x right, -z up): the inside is to the left of travel.
        n1 = (-e1[2], e1[0])
        n2 = (-e2[2], e2[0])
        m = norm((n1[0] + n2[0], 0.0, n1[1] + n2[1]))
        return (-m[0], -m[2])

    vol = Volume()
    floor_w = st(CONTOUR)
    top_w = st(CONTOUR)
    floor = [vol.vert((x, 0.0, z), floor_w) for x, z, _ in pts]
    tops = []
    for i, (x, z, h) in enumerate(pts):
        ix, iz = inward(i)
        tops.append(vol.vert((x + ix * INSET, h, z + iz * INSET), top_w))
    up, down = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)
    m = vol.mesh
    # Walls, each facing out.
    for i in outline:
        j = (i + 1) % n
        # Facing: the outward normal of the segment (to the right of travel, seen from above).
        e = norm((pts[j][0] - pts[i][0], 0.0, pts[j][1] - pts[i][1]))
        facing = (-e[2], 0.3, e[0])
        m.tri(floor[i], floor[j], tops[j], facing)
        m.tri(floor[i], tops[j], tops[i], facing)
    # The pool polygon, fanned from the centre: the dome over the point on top, flat underneath.
    c_top = vol.vert((0.0, POOL_TOP, 0.0), top_w)
    c_floor = vol.vert((0.0, 0.0, 0.0), floor_w)
    ring = pool_ids
    for k in range(len(ring)):
        a, b = ring[k], ring[(k + 1) % len(ring)]
        m.tri(c_top, tops[a], tops[b], up)
        m.tri(c_floor, floor[a], floor[b], down)
    # Each petal: root edge to the mid, the mid to the tip's centre, the round end fanned from it.
    for root_r, mid_r, tip_ids, mid_l, root_l, (tx, tz) in petals:
        t_top = vol.vert((tx, EDGE_H[2] + 0.0006, tz), top_w)
        t_floor = vol.vert((tx, 0.0, tz), floor_w)
        for layer, centre, facing in ((tops, t_top, up), (floor, t_floor, down)):
            m.tri(layer[root_r], layer[mid_r], layer[mid_l], facing)
            m.tri(layer[root_r], layer[mid_l], layer[root_l], facing)
            m.tri(layer[mid_r], layer[tip_ids[0]], centre, facing)
            m.tri(layer[mid_r], centre, layer[mid_l], facing)
            m.tri(layer[mid_l], centre, layer[tip_ids[-1]], facing)
            for a, b in zip(tip_ids, tip_ids[1:]):
                m.tri(centre, layer[a], layer[b], facing)
    vol.orient_outward()
    vol.floor_ring = set(floor)
    return vol


def drop_volume(centre, radius: float) -> Volume:
    """A loose drop of the splash: a low round bead, its foot outline mitred like the slab's."""
    x, _, z = centre
    sides = 6
    base, wall = [], []
    for k in range(sides):
        a = 2 * math.pi * k / sides + x * 40.0
        base.append((x + radius * math.cos(a), 0.0, z + radius * math.sin(a)))
        wall.append((x + 0.8 * radius * math.cos(a), radius * 0.6, z + 0.8 * radius * math.sin(a)))
    w = st(CONTOUR)
    vol = closed_loft([base, wall], [w, w], top=(x, radius * 0.78, z), bottom_w=w, top_w=w)
    vol.floor_ring = set(range(sides)) | {len(vol.mesh.verts) - 2}
    return vol


def splash_volumes() -> list[Volume]:
    vols = [splash_volume()]
    for deg, dist, radius in DROPS:
        a = math.radians(deg)
        vols.append(drop_volume((dist * math.cos(a), 0.0, -dist * math.sin(a)), radius))
    return vols


def surface_y(mesh: Mesh, x: float, z: float) -> float:
    """The height of the highest upward face of `mesh` over (x, z)."""
    best = None
    for a, b, c in mesh.tris:
        pa, pb, pc = mesh.verts[a], mesh.verts[b], mesh.verts[c]
        n = face_normal(pa, pb, pc)
        if n[1] <= 1e-12:
            continue
        d = (pb[2] - pc[2]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[2] - pc[2])
        if abs(d) < 1e-18:
            continue
        l1 = ((pb[2] - pc[2]) * (x - pc[0]) + (pc[0] - pb[0]) * (z - pc[2])) / d
        l2 = ((pc[2] - pa[2]) * (x - pc[0]) + (pa[0] - pc[0]) * (z - pc[2])) / d
        l3 = 1.0 - l1 - l2
        if min(l1, l2, l3) < -1e-9:
            continue
        y = l1 * pa[1] + l2 * pb[1] + l3 * pc[1]
        best = y if best is None else max(best, y)
    if best is None:
        raise ValueError(f"no top over ({x:.4f}, {z:.4f})")
    return best


def hole(ink: Mesh, splash: Volume) -> None:
    """The dark where the point enters the page: a small ragged disc of ink on the slab's dome, lifted."""
    sides = 10
    lift = st(LIFT_STUDS)
    centre = ink.vert((0.0, surface_y(splash.mesh, 0.0, 0.0) + lift, 0.0))
    ring = []
    for k in range(sides):
        a = 2 * math.pi * k / sides
        r = HOLE_R * wobble(math.cos(a) + 5, math.sin(a), SEED + 9, 0.3)
        x, z = r * math.cos(a), -r * math.sin(a)
        ring.append(ink.vert((x, surface_y(splash.mesh, x, z) + lift, z)))
    for k in range(sides):
        ink.tri(centre, ring[k], ring[(k + 1) % sides], (0.0, 1.0, 0.0))


# --- assembly --------------------------------------------------------------------------------------

_CACHE: dict = {}


def _assemble() -> tuple[Mesh, Mesh, Mesh]:
    rng = Rng(SEED)
    splash = splash_volumes()
    solids = [
        (blade_volume(), {}),
        (guard_volume(rng), {}),
        (lathe(FERRULE, SMALL_SIDES, 1.0, turned_weights(len(FERRULE), (0,))), {}),
        (lathe(GRIP, TURN_SIDES, 1.0, turned_weights(len(GRIP), (0, len(GRIP) - 1)), phase=math.pi / 8), {}),
        (lathe(COLLAR, SMALL_SIDES, 1.0, turned_weights(len(COLLAR), (len(COLLAR) - 1,))), {}),
        (lathe(POMMEL, TURN_SIDES, POMMEL_DEPTH, turned_weights(len(POMMEL), (0,)), phase=math.pi / 8, top=(0.0, POMMEL_TIP, 0.0), top_w=st(TURN_HULL)), {}),
    ] + [(vol, {"mitre": 1.45, "mitre_at": vol.floor_ring, "open_top": True}) for vol in splash]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for vol, how in solids:
        body.merge(vol.mesh)
        hull(vol, ink, **how)
    for face in (-1, 1):
        thread(core, face)
        langet(ink, face)
    hole(ink, splash[0])
    return body, core, ink


def _normalised(assemble, key: str) -> tuple[Mesh, Mesh, Mesh]:
    """Build, measure the top, build again with the weights multiplied by it, and scale to Height 1."""
    global _K
    if key in _CACHE:
        return _CACHE[key]
    _K = 1.0
    meshes = assemble()
    _K = max(v[1] for mesh in meshes for v in mesh.verts)
    meshes = assemble()
    top = max(v[1] for mesh in meshes for v in mesh.verts)
    for mesh in meshes:
        mesh.scale(1.0 / top)
    _K = 1.0
    _CACHE[key] = meshes
    return meshes


def build() -> tuple[Mesh, Mesh, Mesh]:
    return _normalised(_assemble, "dagger")


def meta(seed: int) -> dict:
    return {"Reference": "Height", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def obelus_body() -> tuple[Mesh, dict]:
    return build()[0], meta(SEED)


def obelus_core() -> tuple[Mesh, dict]:
    return build()[1], meta(SEED + 1)


def obelus_ink() -> tuple[Mesh, dict]:
    return build()[2], meta(SEED + 2)


# --- the strike-out --------------------------------------------------------------------------------

STRIKE_W = 0.062  # half width across X
STRIKE_RIDGE = 0.032  # the ridge, toward the thrower (+Z)
STRIKE_BACK = 0.014  # the flat back, toward -Z
STRIKE_POINT = 0.25  # the V taper over the foot
STRIKE_KINK = 0.45  # where in the V the facets kink (the nib's shoulder)
STRIKE_HULL = (0.165, 0.195)  # studs: at the foot's point, at the head
STRIKE_POINT_HULL = 0.105  # studs: the very point
STRIKE_MITRE = 1.3  # the side edges are 143 degrees: an unmitred push leaves 0.57 of the weight beside them
# The pale thread on the -X facet of the ridge: (top y, bottom y, inner u, outer u), u the share of the
# facet's width out from the ridge. Narrow: under 6 % of what is seen from behind.
STRIKE_THREAD = (0.60, 0.07, 0.17, 0.39)
STRIKE_LINES = (-0.58, 0.46)  # the facet lines' u, on the -X facet (outside the thread) and the +X facet


def strike_section(y: float):
    """Half width, ridge depth, back depth at y: a pointed foot, a constant body, a pressed head."""
    if y < STRIKE_POINT:
        # A straight V to the point (the inset's outline); the facets' break is drawn by the ink ticks.
        g = y / STRIKE_POINT
        return STRIKE_W * g, STRIKE_RIDGE * (0.3 + 0.7 * g), STRIKE_BACK * (0.3 + 0.7 * g)
    head = max(0.0, (y - 0.9) / 0.1)
    w = STRIKE_W * (1.0 + 0.1 * head) * wobble(3.0 * y, 0.7, STRIKE_SEED, 0.025)
    return w, STRIKE_RIDGE, STRIKE_BACK


def on_ridge_facet(x: float, y: float, lift: float):
    """A point on the ridge side of the strike (toward +Z) at x across, lifted along its facet."""
    w, rz, bz = strike_section(y)
    u = min(1.0, abs(x) / w) if w > 0 else 0.0
    z = rz + (-bz - rz) * u
    s = 1.0 if x >= 0 else -1.0
    n = norm((s * (rz + bz), 0.0, w))
    return add((x, y, z), mul(n, lift))


def _strike_assemble() -> tuple[Mesh, Mesh, Mesh]:
    ys = [0.03, 0.06, STRIKE_POINT * STRIKE_KINK, 0.18, STRIKE_POINT, 0.42, 0.62, 0.80, 0.90, 0.96]
    rings, weights = [], []
    for y in ys:
        w, rz, bz = strike_section(y)
        rings.append([(-w, y, -bz), (0.0, y, rz), (w, y, -bz)])
        # Heavy down the V, where the inset pools its ink, and heavier still at the pressed head.
        f = 0.0 if y <= STRIKE_POINT else (y - STRIKE_POINT) / (1.0 - STRIKE_POINT)
        weights.append(st(STRIKE_HULL[0] + (STRIKE_HULL[1] - STRIKE_HULL[0]) * f))
    # The head: the nib's square start, cut on a slant (high on the left, low on the right).
    w, rz, bz = strike_section(0.99)
    slant = 0.03
    rings.append([(-w, 1.0, -bz), (0.0, 1.0 - slant / 2, rz), (w, 1.0 - slant, -bz)])
    weights.append(st(STRIKE_HULL[1]))
    vol = closed_loft(rings, weights, bottom=(0.0, 0.010, 0.004), bottom_w=st(STRIKE_POINT_HULL))
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    body.merge(vol.mesh)
    hull(vol, ink, mitre=STRIKE_MITRE)
    lift = st(LIFT_STUDS)
    # The pale thread on the ridge's -X facet, off the ridge: a lens from under the head to near the point.
    top, bottom, u_in, u_out = STRIKE_THREAD
    steps = 14
    rows = []
    mid, half = (u_in + u_out) / 2, (u_out - u_in) / 2
    for i in range(steps + 1):
        f = i / steps
        y = top + (bottom - top) * f
        w, rz, bz = strike_section(y)
        # Broadest where the nib's point begins, the inset's pale ridge, fading up the stroke.
        spread = half * math.sin(math.pi * f ** 1.4) ** 0.6
        rows.append(tuple(on_ridge_facet(-u * w, y, lift) for u in (mid - spread, mid, mid + spread)))
    for j in range(2):
        strip(core, [r[j] for r in rows], [r[j + 1] for r in rows], (0.0, 0.0, 1.0))
    # Two ink lines down the ridge's facets, either side of the ridge, meeting at the point: the inset's
    # nib, its pale ridge framed by the facets' edges.
    for u0 in STRIKE_LINES:
        sign = 1.0 if u0 > 0 else -1.0
        lefts, rights = [], []
        steps = 12
        for i in range(steps + 1):
            f = i / steps
            y = 0.95 + (0.02 - 0.95) * f
            w, rz, bz = strike_section(y)
            u = abs(u0) + 0.05 * math.sin(2.5 * f + (0.6 if sign > 0 else 0.0))
            width = 0.0055 * (0.35 + 0.65 * math.sin(math.pi * min(1.0, 0.1 + f)) ** 0.6)
            for into, du in ((lefts, -0.5), (rights, 0.5)):
                into.append(on_ridge_facet(sign * (u * w + du * width), y, lift))
        strip(ink, lefts, rights, (0.0, 0.0, 1.0))
    # A short tick across each facet where the point begins: the nib's shoulder, the inset's chevron.
    for sign in (-1.0, 1.0):
        lefts, rights = [], []
        for i in range(4):
            f = i / 3
            u = 0.95 - 0.3 * f
            y = STRIKE_POINT * (0.98 - 0.12 * f)
            w, rz, bz = strike_section(y)
            width = 0.0045 * (1.0 - 0.6 * f)
            for into, dy in ((lefts, -0.5), (rights, 0.5)):
                p = on_ridge_facet(sign * u * w, y + dy * width, lift)
                into.append(p)
        strip(ink, lefts, rights, (0.0, 0.0, 1.0))
    return body, core, ink


def strike_build() -> tuple[Mesh, Mesh, Mesh]:
    return _normalised(_strike_assemble, "strike")


def strike_body() -> tuple[Mesh, dict]:
    return strike_build()[0], meta(STRIKE_SEED)


def strike_core() -> tuple[Mesh, dict]:
    return strike_build()[1], meta(STRIKE_SEED + 1)


def strike_ink() -> tuple[Mesh, dict]:
    return strike_build()[2], meta(STRIKE_SEED + 2)
