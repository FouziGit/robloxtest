"""The Gilding's irons (Umber): a collar of upright leather plates round the caster's legs.

Drawn after the developer's two references (docs/vfx/gilding/ref-1.jpg, the collar in game round a
blocky avatar; ref-2.jpg, the model sheet "Umber ink leather irons"). Every drawing of the ring shows
EIGHT plates: the sheet's top-down view puts two in each quadrant with the gaps on the axes, its front
view shows two plates face on and the angled side plates past them with their faces and fleurons in
sight, and the game shot a centre plate, two at 45 degrees and two near edge on. Only the text (the
sheet's label, PROMPTS_DA, the bible) says six. So the body builds the drawings' eight; the text's six is the same plate wider, if the
developer rules for it.

The plate, from the sheet's detail: an elongated hexagon -- a pointed roof, shoulders a quarter of the
way down, long sides tapering to a short chisel point at the foot -- bent along a vertical ridge into
two crisp facets, so from above each plate is a shallow chevron and the ring is round. On its outer face,
from the rim in: a band of umber (the edging is "inset from rim", and the bible keeps the pale off the
outer edge even when the plate is seen at a grazing angle), the pale burnished edging, two ink fillets
with a band of umber between them, the stamped double-diamond fleuron a little below the middle, and the
ridge drawn as two tapered strokes. The collar flares 4 degrees outward, as the sheet's front and side
views draw it. The sheet and the game shot give the scale: 4.8 studs across, 3.2 tall with its top under
the hip, its points just over the floor. Ink and pigment, never gold nor metal: the gold is the
Orpiment's.

Every length below is a stud at the posed size (Diameter 4.8). The ring's radius is solved so its
outermost ink falls exactly 2.4 studs from the axis, so the normalisation only divides by 4.8 and the
contour's 0.10 stud is 0.10 stud in the game.

Roblox space: X right, Y up, forward -Z. The pivot is on the floor under the caster's root; the body
turns about Y (the bible's Spin +0.5) and follows the caster (R2). The eight plates stand at 22.5 + 45k
degrees from forward, so there is a gap in front and one behind: from the
thrower's camera the two back plates face it square, the caster's legs show between them, and the next
plates frame them.

Three meshes, one tone each: irons_body (Pigment: the slabs), irons_core (Core: the pale burnished
edging on each plate's outer face, inset from the rim, always ringed by pigment), irons_ink (Ink: each
plate's inverted hull -- the contour, heavier at the foot -- the two fillets, the stamped fleuron and the
ridge's two calligraphic strokes).
"""

from __future__ import annotations

import math

from strokes import FLOOR_CLEARANCE, Mesh, Rng, add, cross, dot, mul, sub, surface_ribbon

SEED = 6151
DIAMETER = 4.8  # the posed size: every length in this file is a stud at it

# --- the ring: the drawings' eight, and the text's six ---------------------------------------------
# width: across the shoulders; thick: the slab, back face to outer face; cut: how the plate's long sides
# are cut, 0 square to the plate, 1 parallel to the line between neighbours; phase: the first plate's
# angle from forward. The eight's ends are cut parallel: square, their inner corners would cross into the
# neighbour's at any width over 1.1 stud. The six's are cut a little, so its gaps open outward like the
# sheet's top-down view without becoming a crown of separate plates. Each width leaves a narrow, even gap
# of 0.06 stud between neighbouring contours seen from above (0.28 between the umber).
RINGS = {
    8: {"count": 8, "width": 1.402, "thick": 0.30, "cut": 1.0, "phase": 22.5},
    6: {"count": 6, "width": 1.66, "thick": 0.34, "cut": 0.22, "phase": 30.0},
}

# --- the plate -------------------------------------------------------------------------------------
FOOT = 0.19  # height of the chisel point at the foot (its contour then clears the floor by 0.025)
HEIGHT = 2.85  # point to point (the roof's contour then tops out under 3.2)
SHOULDER = 0.75  # the shoulders' height, a share of HEIGHT
WAIST = (0.61, 0.11)  # the lower corners: share of the width, share of HEIGHT
BEND = 0.16  # the outer face's rise toward the ridge, per stud across: two facets 18 degrees apart
LEAN = math.radians(4.0)  # outward, about the foot

# The contour: the hull stands off every face of the slab by this much, heavier at the foot (bible: 0.10
# to 0.14 stud at the final size, never under 0.10).
HULL_FOOT = 0.103
HULL_TOP = 0.102

# The raised rim round the outer face (the sheet's "crisp faceted edges"): its width in from the outline
# and its height over the face. It stands higher than the pale's lift, so on a plate seen at a grazing
# angle the rim hides the pale's outer edge instead of letting the lifted pale slide onto the contour:
# between them stay (RIM height - CORE_LIFT) x sin + RIM width x cos of the angle, never nothing. Seen edge
# on, the contour over the ridge is the rim's height plus the hull's weight, 0.14, the bible's top weight.
RIM = (0.085, 0.038)

# Inside the rim, insets from the plate's outline: the pale edging against the rim's inner wall, then two
# ink fillets with a band of umber between them (the outer fillet tucks 0.005 under the edging so no hair
# of umber shows between them). Both lifts stay under the rim's height.
EDGING = (0.085, 0.13)
FILLET_OUTER = (0.125, 0.141)
FILLET_INNER = (0.19, 0.206)
CORE_LIFT = 0.03
INK_LIFT = 0.035
BAND_PIECE = 20.0  # a band's side is cut into pieces at most this many band widths long: no slivers

# The fleuron: a stamped diamond in a diamond, centred this share of HEIGHT up from the foot.
FLEURON_AT = 0.45
FLEURON = (0.2, 0.2)  # height (share of HEIGHT), width (share of the plate's width)
FLEURON_LINE = (0.022, 0.016)
FLEURON_INNER = 0.5  # the inner diamond's size, a share of the outer one

# The ridge's two strokes, above and below the fleuron (shares of HEIGHT), their weight and samples.
RIDGE_STROKES = ((0.6, 0.86), (0.32, 0.1))
RIDGE_WIDTH = 0.018
RIDGE_SAMPLES = 7


# --- the outline -----------------------------------------------------------------------------------


def outline(width: float, height: float) -> list[tuple[float, float]]:
    """The plate's hexagon in its own plane (u across, v up from the foot), counter-clockwise: the foot's
    point, the right lower corner, the right shoulder, the roof's point, the left shoulder, the left
    lower corner."""
    lw, lh = WAIST
    return [
        (0.0, 0.0),
        (0.5 * lw * width, lh * height),
        (0.5 * width, SHOULDER * height),
        (0.0, height),
        (-0.5 * width, SHOULDER * height),
        (-0.5 * lw * width, lh * height),
    ]


LONG_SIDES = (1, 4)  # the outline's edges from each lower corner to its shoulder


def miters(poly: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """For each corner of a counter-clockwise convex polygon, the vector that moves it 1 off both its
    edges' lines, outward."""
    out = []
    count = len(poly)
    for i in range(count):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % count]
        normals = []
        for a, b in ((p0, p1), (p1, p2)):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            normals.append((dy / length, -dx / length))
        (ax, ay), (bx, by) = normals
        k = 1.0 + ax * bx + ay * by
        out.append(((ax + bx) / k, (ay + by) / k))
    return out


def offset(poly, grow) -> list[tuple[float, float]]:
    """The polygon moved out by `grow` (a number, or a function of v), corner by corner."""
    out = []
    for (u, v), (mu, mv) in zip(poly, miters(poly)):
        g = grow(v) if callable(grow) else grow
        out.append((u + mu * g, v + mv * g))
    return out


def shift_edges(poly, shifts) -> list[tuple[float, float]]:
    """The convex polygon with each edge i (corner i -> i + 1) moved in by shifts[i] along its own normal:
    every new edge stays parallel to the old one, so a wall between the two outlines is one flat face."""
    count = len(poly)
    lines = []
    for i in range(count):
        (ax, ay), (bx, by) = poly[i], poly[(i + 1) % count]
        length = math.hypot(bx - ax, by - ay)
        nx, ny = (by - ay) / length, -(bx - ax) / length
        lines.append((nx, ny, nx * ax + ny * ay - shifts[i]))
    out = []
    for i in range(count):
        a1, b1, c1 = lines[i - 1]
        a2, b2, c2 = lines[i]
        det = a1 * b2 - a2 * b1
        out.append(((c1 * b2 - c2 * b1) / det, (a1 * c2 - a2 * c1) / det))
    return out


def solve3(rows, rhs) -> tuple[float, float, float]:
    """The point on three planes (normals `rows`, offsets `rhs`), by Cramer's rule."""

    def det(m):
        return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])

    d = det(rows)
    return tuple(det([[rhs[r] if c == k else rows[r][c] for c in range(3)] for r in range(3)]) / d for k in range(3))


# --- one plate -------------------------------------------------------------------------------------


class Plate:
    """A plate's frame and dimensions: where it stands on the ring and how its faces lie. Its frame has
    u across, v up the plate from the foot's point, w out of its mid-plane. The plates stand at even
    angles and are all as wide, so every gap is the same; only the height and the lean vary a little,
    the hand's variance, and never past HEIGHT."""

    def __init__(self, ring: dict, k: int, apothem: float, rng: Rng) -> None:
        self.phi = math.radians(ring["phase"]) + 2.0 * math.pi * k / ring["count"]
        self.height = HEIGHT * (1.0 - 0.012 * rng.random())
        self.width = ring["width"]
        self.thick = ring["thick"]
        lean = LEAN + math.radians(0.15) * (rng.random() * 2.0 - 1.0)
        out = (math.sin(self.phi), 0.0, -math.cos(self.phi))
        self.across = (math.cos(self.phi), 0.0, math.sin(self.phi))
        self.up = add(mul((0.0, 1.0, 0.0), math.cos(lean)), mul(out, math.sin(lean)))
        self.normal = add(mul(out, math.cos(lean)), mul((0.0, 1.0, 0.0), -math.sin(lean)))
        self.base = add(mul(out, apothem), (0.0, FOOT, 0.0))
        self.poly = outline(self.width, self.height)
        # The inner face is the outline with its two long sides (the edges that face the neighbours) moved
        # in parallel to themselves by cut x thick x tan(half the angle between plates), so those walls are
        # flat faces leaning that much; the roof's and the foot's walls stay square to the plate.
        narrow = ring["cut"] * self.thick * math.tan(math.pi / ring["count"])
        shifts = [0.0] * len(self.poly)
        for i in LONG_SIDES:
            (au, av), (bu, bv) = self.poly[i], self.poly[(i + 1) % len(self.poly)]
            shifts[i] = narrow * abs(bv - av) / math.hypot(bu - au, bv - av)
        self.back_poly = shift_edges(self.poly, shifts)
        self.ridge = BEND * 0.5 * self.width
        # A face plane moved g off along its own normal moves g * secant along w.
        self.secant = math.sqrt(1.0 + BEND * BEND)
        self.fleuron_seed = SEED + 17 * k

    def world(self, u: float, v: float, w: float):
        return add(self.base, add(mul(self.across, u), add(mul(self.up, v), mul(self.normal, w))))

    def bend(self, u: float) -> float:
        """How far the slab stands out at u: it is bent along its ridge (u = 0) into two planes, so seen
        from above each plate is a shallow chevron, convex outside and hollow inside, and the ring is
        round rather than a polygon. Zero at the shoulders' corners."""
        return self.ridge - BEND * abs(u)

    def front(self, u: float) -> float:
        """The outer face's height over the mid-plane at u."""
        return 0.5 * self.thick + self.bend(u)

    def back(self, u: float) -> float:
        """The inner face's height over the mid-plane at u."""
        return -0.5 * self.thick + self.bend(u)

    def grow(self, v: float) -> float:
        f = min(max(v / self.height, 0.0), 1.0)
        return HULL_FOOT + (HULL_TOP - HULL_FOOT) * f

    def side_out(self, i: int, poly):
        """The outward direction (world) of the side face on edge i -> i + 1."""
        a, b = poly[i], poly[(i + 1) % len(poly)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        nu, nv = dy / length, -dx / length
        return add(mul(self.across, nu), mul(self.up, nv))


def tri(mesh: Mesh, a: int, b: int, c: int, facing) -> None:
    mesh.tri(a, b, c, facing)


def plate_solid(mesh: Mesh, plate: Plate, hull: bool) -> None:
    """The slab, closed: the back face (the narrowed outline), the side walls and the outer face's two
    facets (the outline). As hull: every face of the slab, its outer facets raised to the rim's top,
    moved off along its own normal by the contour's weight, each corner where three of those planes meet,
    wound inside out, so only its rim past the plate's silhouette shows, as thick from every side."""
    n = len(plate.poly)
    back_dir = mul(plate.normal, -1.0)
    if hull:
        back_pts, face_pts = hull_corners(plate)
        back = [mesh.vert(plate.world(*p)) for p in back_pts]
        face = [mesh.vert(plate.world(*p)) for p in face_pts]
    else:
        back = [mesh.vert(plate.world(u, v, plate.back(u))) for u, v in plate.back_poly]
        face = [mesh.vert(plate.world(u, v, plate.front(u))) for u, v in plate.poly]
    sign = -1.0 if hull else 1.0
    # Each face is two facets meeting on the ridge (the foot's point 0 to the roof's point 3): the right
    # facet (foot, right lower, right shoulder, roof) and the left.
    for ring, facing in ((back, back_dir), (face, plate.normal)):
        for a, b, c in ((0, 1, 2), (0, 2, 3), (3, 4, 5), (3, 5, 0)):
            tri(mesh, ring[a], ring[b], ring[c], mul(facing, sign))
    # The walls.
    for i in range(n):
        j = (i + 1) % n
        out = plate.side_out(i, plate.poly)
        tri(mesh, back[i], back[j], face[j], mul(out, sign))
        tri(mesh, back[i], face[j], face[i], mul(out, sign))


def hull_corners(plate: Plate):
    """The hull's corners in the plate's frame (u, v, w): the slab's faces as planes -- each wall through
    its outer and inner edges, each facet of the inner face, each facet of the outer face raised to the
    rim's top -- every one moved off along its own outward normal by the contour's weight where it runs
    (a wall by the weight at its middle, so the foot's walls are the heaviest; a facet by the weight at
    mid-height), and each corner the point where its two walls and its facet meet."""
    n = len(plate.poly)
    front = [(u, v, plate.front(u)) for u, v in plate.poly]
    back = [(u, v, plate.back(u)) for u, v in plate.back_poly]
    walls = []
    for i in range(n):
        j = (i + 1) % n
        normal = cross(sub(front[j], front[i]), sub(back[i], front[i]))
        (au, av), (bu, bv) = plate.poly[i], plate.poly[j]
        if dot(normal, (bv - av, au - bu, 0.0)) < 0.0:
            normal = mul(normal, -1.0)
        normal = mul(normal, 1.0 / math.sqrt(dot(normal, normal)))
        walls.append((normal, dot(normal, front[i]) + plate.grow(0.5 * (av + bv))))
    g = plate.grow(0.5 * plate.height)
    rise = (0.5 * plate.thick + plate.ridge + RIM[1], -0.5 * plate.thick + plate.ridge)
    out = []
    for level, corners in ((1, back), (0, front)):  # (a leaning wall runs on past the rim, which it holds)
        ring = []
        for k, (u, _, _) in enumerate(corners):
            side = 1.0 if u >= -1e-9 else -1.0
            facet = mul((side * BEND, 0.0, 1.0), 1.0 / plate.secant)
            if level == 1:  # the inner face looks the other way
                facet = mul(facet, -1.0)
            offset_d = dot(facet, (0.0, 0.0, rise[level])) + g
            rows = [walls[k - 1][0], walls[k][0], facet]
            ring.append(solve3(rows, [walls[k - 1][1], walls[k][1], offset_d]))
        out.append(ring)
    return out[0], out[1]


def subdivide(outer_poly, inner_poly, limit: float):
    """The two outlines' corners, with each side cut into the same pieces no longer than `limit`, so a
    strip between them is quads of matching corners."""
    n = len(outer_poly)
    outs, ins = [], []
    for i in range(n):
        j = (i + 1) % n
        pieces = max(1, math.ceil(max(math.dist(outer_poly[i], outer_poly[j]), math.dist(inner_poly[i], inner_poly[j])) / limit))
        for k in range(pieces):
            f = k / pieces
            outs.append(tuple(p + (q - p) * f for p, q in zip(outer_poly[i], outer_poly[j])))
            ins.append(tuple(p + (q - p) * f for p, q in zip(inner_poly[i], inner_poly[j])))
    return outs, ins


def rim_solid(mesh: Mesh, plate: Plate) -> None:
    """The raised rim, closed: a flat-topped band standing RIM[1] over the outer face, from the outline in
    by RIM[0], its outer wall flush with the slab's walls and its underside on the face (hidden). Each
    side is cut into pieces no longer than BAND_PIECE times the rim's height, so its walls hold no
    slivers."""
    outs, ins = subdivide(plate.poly, offset(plate.poly, -RIM[0]), BAND_PIECE * RIM[1])
    m = len(outs)
    rings = [
        [mesh.vert(plate.world(u, v, plate.front(u))) for u, v in outs],
        [mesh.vert(plate.world(u, v, plate.front(u) + RIM[1])) for u, v in outs],
        [mesh.vert(plate.world(u, v, plate.front(u) + RIM[1])) for u, v in ins],
        [mesh.vert(plate.world(u, v, plate.front(u))) for u, v in ins],
    ]
    for r in range(4):
        lo, hi = rings[r], rings[(r + 1) % 4]
        for i in range(m):
            j = (i + 1) % m
            if r == 1:
                facing = plate.normal
            elif r == 3:
                facing = mul(plate.normal, -1.0)
            else:  # the outer wall (r = 0) faces out of the outline, the inner wall (r = 2) into it
                (au, av), (bu, bv) = outs[i], outs[j]
                length = math.hypot(bu - au, bv - av)
                side = add(mul(plate.across, (bv - av) / length), mul(plate.up, -(bu - au) / length))
                facing = side if r == 0 else mul(side, -1.0)
            tri(mesh, lo[i], lo[j], hi[j], facing)
            tri(mesh, lo[i], hi[j], hi[i], facing)


def face_ring(mesh: Mesh, plate: Plate, inner: float, outer: float, lift: float) -> None:
    """A band round the outer face between two insets from the plate's outline, lying on its facets.
    Each side is cut into pieces no longer than BAND_PIECE band widths, so a thin band has no sliver
    triangles; every piece lies on one facet, since the outline's corners on the ridge stay on it."""
    outs, ins = subdivide(offset(plate.poly, -inner), offset(plate.poly, -outer), BAND_PIECE * (outer - inner))
    a = [mesh.vert(plate.world(u, v, plate.front(u) + lift)) for u, v in outs]
    b = [mesh.vert(plate.world(u, v, plate.front(u) + lift)) for u, v in ins]
    m = len(a)
    for i in range(m):
        j = (i + 1) % m
        tri(mesh, a[i], a[j], b[j], plate.normal)
        tri(mesh, a[i], b[j], b[i], plate.normal)


def diamond(mesh: Mesh, plate: Plate, centre_v: float, height: float, width: float, line: float, lift: float) -> None:
    """A stamped diamond outline on the ridge, its points up, down and to either side."""
    poly = [(0.0, centre_v - 0.5 * height), (0.5 * width, centre_v), (0.0, centre_v + 0.5 * height), (-0.5 * width, centre_v)]
    inner = offset(poly, -line)
    a = [mesh.vert(plate.world(u, v, plate.front(u) + lift)) for u, v in poly]
    b = [mesh.vert(plate.world(u, v, plate.front(u) + lift)) for u, v in inner]
    for i in range(4):
        j = (i + 1) % 4
        tri(mesh, a[i], a[j], b[j], plate.normal)
        tri(mesh, a[i], b[j], b[i], plate.normal)


def ridge_strokes(mesh: Mesh, plate: Plate) -> None:
    """The ridge drawn in ink, as two tapered strokes of the brush: from under the roof's point down to
    the fleuron, and from under the fleuron down toward the foot."""

    def point(s: float, t: float):
        return plate.world(t, s, plate.front(0.0))

    def normal(s: float, t: float):
        return plate.normal

    for k, (start, end) in enumerate(RIDGE_STROKES):
        a, b = start * plate.height, end * plate.height
        surface_ribbon(mesh, (point, normal), lambda tau, a=a, b=b: (a + (b - a) * tau, 0.0), RIDGE_WIDTH, INK_LIFT, RIDGE_SAMPLES, plate.fleuron_seed + k)


# --- the three meshes ------------------------------------------------------------------------------

_CACHE: dict = {}


def plates(count: int, apothem: float) -> list[Plate]:
    rng = Rng(SEED)
    return [Plate(RINGS[count], k, apothem, rng) for k in range(count)]


def ring(count: int, apothem: float) -> tuple[Mesh, Mesh, Mesh]:
    """The ring in posed studs, its plates' mid-planes `apothem` from the axis at the foot."""
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for plate in plates(count, apothem):
        plate_solid(body, plate, hull=False)
        rim_solid(body, plate)
        plate_solid(ink, plate, hull=True)
        face_ring(core, plate, EDGING[0], EDGING[1], CORE_LIFT)
        face_ring(ink, plate, FILLET_OUTER[0], FILLET_OUTER[1], INK_LIFT)
        face_ring(ink, plate, FILLET_INNER[0], FILLET_INNER[1], INK_LIFT)
        fv = FLEURON_AT * plate.height
        fh, fw = FLEURON[0] * plate.height, FLEURON[1] * plate.width
        diamond(ink, plate, fv, fh, fw, FLEURON_LINE[0], INK_LIFT)
        diamond(ink, plate, fv, FLEURON_INNER * fh, FLEURON_INNER * fw, FLEURON_LINE[1], INK_LIFT)
        ridge_strokes(ink, plate)
    return body, core, ink


def reach(meshes) -> float:
    return max(math.hypot(x, z) for mesh in meshes for x, _, z in mesh.verts)


def solve_apothem(count: int) -> float:
    """The plates' distance from the axis that puts the outermost ink exactly at half the diameter: the
    outermost point moves out one for one with the plates, so a few steps settle it."""
    apothem = 1.8
    for _ in range(8):
        miss = 0.5 * DIAMETER - reach(ring(count, apothem))
        apothem += miss
        if abs(miss) < 1e-9:
            break
    return apothem


def build(count: int = 8) -> tuple[Mesh, Mesh, Mesh]:
    if count in _CACHE:
        return _CACHE[count]
    apothem = solve_apothem(count)
    meshes = ring(count, apothem)
    span = reach(meshes)
    for mesh in meshes:
        mesh.scale(0.5 / span)
        mesh.verts = [(x, max(y, FLOOR_CLEARANCE), z) for x, y, z in mesh.verts]
    _CACHE[count] = meshes
    return meshes


def meta() -> dict:
    return {"Reference": "Diameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": SEED}


# The drawings' eight plates (the default).
def irons_body() -> tuple[Mesh, dict]:
    return build(8)[0], meta()


def irons_core() -> tuple[Mesh, dict]:
    return build(8)[1], meta()


def irons_ink() -> tuple[Mesh, dict]:
    return build(8)[2], meta()
