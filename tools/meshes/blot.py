"""The Blot's two bodies (lot 4, custom body): the Teardrop it flies as, and the Star it bursts into.

Drawn after the developer's two references (docs/vfx/blot/ref-1.jpg, an in-game shot of the teardrop
diving over a courtyard; ref-2.jpg, a model sheet of the teardrop and of the star).

Roblox space: X right, Y up, forward -Z.

The Teardrop (flight form; Reference "Length", axis Z, spun at -2.5 about Z by the runtime):
  - a head of cinnabar ink cut into flat planes: rings of seven corners, each ring turned half a facet
    from the last, so its faces are a gem's triangles and its outline a polygon, never a ball; a flat
    facet at the nose, outlined in ink; blunt and round in front, drawn out late into a tail that rises
    a little toward the neck;
  - a wet pale lobe on top (Core): an ellipsoid half sunk in the head, with its own contour;
  - a dark keel under the front half (Ink): a narrow crescent cut out of the head's own facets and
    lifted off them, never a slab, so it reads the same whichever way the spin has rolled it;
  - two calligraphic cuts along the upper flanks, cut out of the facets the same way;
  - five thin whips, each from its own root round the lower half of the tail, splaying apart at once:
    seen from the front a fan of legs under the head, from the side a fountain, turning a little about
    Z all the same way (they trail against the spin), unequal, each ending in a round bead with its own
    contour -- never a point.
  Length = 1 is the whole body, contour included, nose to the farthest bead.

The Star (burst form; Reference "OuterDiameter", axis Y): nine slim faceted arms out of a small hub --
three rising, three level, three falling, turned and jittered so no two cross from the thrower's seat,
the front or the side -- each a four-faced spike tapering straight to a stem with
a round bead whose OUTER INK lies on the sphere of radius 0.5: drawn 2 x BlastRadius = 20 studs,
nothing of it lies beyond the blast. The three rising arms carry a pale streak (Core); the other six an
ink crease down their ridge.

Three meshes for each form, one tone each: Pigment (the volumes), Core (the pale only), Ink (the
inverted hulls, the keel, the cuts, the creases).
"""

from __future__ import annotations

import math

from strokes import (
    Mesh,
    Polyline,
    Rng,
    Volume,
    add,
    catmull,
    cross,
    dot,
    emit,
    face_normal,
    mul,
    norm,
    smoothstep,
    sub,
)

SEED = 5281
_CACHE: dict = {}

# --- shared pieces -------------------------------------------------------------------------------


def mean(points):
    n = len(points)
    return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n, sum(p[2] for p in points) / n)


def hull(vol: Volume, into: Mesh) -> None:
    """The contour of a closed volume, even all round: every vertex pushed out along its averaged normal
    far enough that each face round it stands off by the vertex's weight (a hard corner goes further,
    up to 1.8 x), every triangle wound the other way. No floor: these bodies fly."""
    mesh = vol.mesh
    faces: list[list] = [[] for _ in mesh.verts]
    for a, b, c in mesh.tris:
        n = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
        if dot(n, n) < 1e-24:
            continue
        unit = norm(n)
        for v in (a, b, c):
            faces[v].append(unit)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        around = faces[i]
        if not around:
            into.verts.append(p)
            continue
        n = norm(mean(around))
        reach = max(min(dot(n, f) for f in around), 1.0 / 1.8)
        into.verts.append(add(p, mul(n, vol.weight[i] / reach)))
    for a, b, c in mesh.tris:
        emit(into, a + base, c + base, b + base)


_ICO_T = (1.0 + math.sqrt(5.0)) / 2.0
_ICO_V = [(-1, _ICO_T, 0), (1, _ICO_T, 0), (-1, -_ICO_T, 0), (1, -_ICO_T, 0), (0, -1, _ICO_T), (0, 1, _ICO_T),
          (0, -1, -_ICO_T), (0, 1, -_ICO_T), (_ICO_T, 0, -1), (_ICO_T, 0, 1), (-_ICO_T, 0, -1), (-_ICO_T, 0, 1)]
_ICO_F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
          (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
          (8, 6, 7), (9, 8, 1)]


def rotate(v, axis, angle):
    """Rodrigues: `v` turned `angle` about the unit `axis`."""
    c, s = math.cos(angle), math.sin(angle)
    return add(add(mul(v, c), mul(cross(axis, v), s)), mul(axis, dot(axis, v) * (1.0 - c)))


def icosahedron_bead(centre, radius: float, weight: float, axis=(0.0, 1.0, 0.0), spin: float = 0.0) -> Volume:
    """A small faceted ball (20 faces), a five-fold axis along `axis`: the star's hub."""
    vol = Volume()
    verts = [norm(v) for v in _ICO_V]
    v0 = verts[0]
    turn = cross(v0, axis)
    if dot(turn, turn) > 1e-12:
        angle = math.acos(max(-1.0, min(1.0, dot(v0, axis))))
        turn = norm(turn)
    else:
        angle, turn = 0.0, (0.0, 1.0, 0.0)
    ids = [vol.vert(add(centre, mul(rotate(rotate(v, turn, angle), axis, spin), radius)), weight) for v in verts]
    for a, b, c in _ICO_F:
        vol.mesh.tri(ids[a], ids[b], ids[c], sub(mean([vol.mesh.verts[ids[i]] for i in (a, b, c)]), centre))
    return vol


def uv_bead(centre, radius: float, weight: float, axis, spin: float = 0.0, segments: int = 6, rings: int = 5) -> Volume:
    """A round bead for a tight budget: 6 x 5 with every other ring turned half a step, 48 faces, whose
    outline is a 12-gon down its axis and near a 10-gon across it -- round, never a nut."""
    vol = Volume()
    axis = norm(axis)
    side = cross(axis, (0.0, 1.0, 0.0))
    if dot(side, side) < 1e-6:
        side = cross(axis, (1.0, 0.0, 0.0))
    side = rotate(norm(side), axis, spin)
    other = cross(axis, side)
    poles = [vol.vert(add(centre, mul(axis, radius)), weight), vol.vert(add(centre, mul(axis, -radius)), weight)]
    grid = []
    for i in range(1, rings):
        theta = math.pi * i / rings
        row = []
        for k in range(segments):
            phi = 2.0 * math.pi * (k + 0.5 * (i % 2)) / segments
            d = add(mul(axis, math.cos(theta)), mul(add(mul(side, math.cos(phi)), mul(other, math.sin(phi))), math.sin(theta)))
            row.append(vol.vert(add(centre, mul(d, radius)), weight))
        grid.append(row)

    def out(*ids):
        return sub(mean([vol.mesh.verts[i] for i in ids]), centre)

    for k in range(segments):
        n = (k + 1) % segments
        vol.mesh.tri(poles[0], grid[0][k], grid[0][n], out(poles[0], grid[0][k], grid[0][n]))
        vol.mesh.tri(poles[1], grid[-1][k], grid[-1][n], out(poles[1], grid[-1][k], grid[-1][n]))
    for i in range(len(grid) - 1):
        for k in range(segments):
            n = (k + 1) % segments
            a, b, c, d = grid[i][k], grid[i][n], grid[i + 1][k], grid[i + 1][n]
            if i % 2 == 0:
                vol.mesh.tri(a, b, c, out(a, b, c))
                vol.mesh.tri(b, d, c, out(b, d, c))
            else:
                vol.mesh.tri(a, b, d, out(a, b, d))
                vol.mesh.tri(a, d, c, out(a, d, c))
    return vol


def cord(control, radius, weight, segs: int, sides: int = 4, twist: float = 0.0) -> Volume:
    """A tapered cord along a Catmull-Rom path, closed at both ends; `radius(u)` and `weight(u)` over
    u = 0 (root) .. 1 (end). Its section is carried by parallel transport, so it never flips."""
    vol = Volume()
    line = Polyline(catmull(control, 16))
    centres = [line.at(i / segs) for i in range(segs + 1)]
    tangents = [norm(sub(centres[min(i + 1, segs)], centres[max(i - 1, 0)])) for i in range(segs + 1)]
    side = cross(tangents[0], (0.0, 1.0, 0.0))
    if dot(side, side) < 1e-6:
        side = cross(tangents[0], (1.0, 0.0, 0.0))
    side = norm(side)
    rings = []
    for i in range(segs + 1):
        u = i / segs
        along = tangents[i]
        side = norm(sub(side, mul(along, dot(side, along))))
        up = norm(cross(side, along))
        r = radius(u)
        ring = []
        for k in range(sides):
            angle = twist + 2.0 * math.pi * k / sides
            q = add(centres[i], add(mul(up, r * math.sin(angle)), mul(side, r * math.cos(angle))))
            ring.append(vol.vert(q, weight(u)))
        rings.append(ring)
    for r in range(segs):
        a, b = rings[r], rings[r + 1]
        mid = mul(add(centres[r], centres[r + 1]), 0.5)
        for j in range(sides):
            k = (j + 1) % sides
            for tri in ((a[j], a[k], b[k]), (a[j], b[k], b[j])):
                vol.mesh.tri(*tri, sub(mean([vol.mesh.verts[t] for t in tri]), mid))
    for ring, end, facing, u in ((rings[0], centres[0], mul(tangents[0], -1.0), 0.0), (rings[-1], centres[-1], tangents[-1], 1.0)):
        tip = vol.vert(add(end, mul(facing, 0.3 * radius(u))), weight(u))
        for j in range(sides):
            vol.mesh.tri(ring[j], ring[(j + 1) % sides], tip, facing)
    return vol


def ribbon_on(mesh: Mesh, points, normals, widths) -> None:
    """A flat strip through `points`, lying across each point's `normal`, `widths` wide, facing out."""
    count = len(points)
    lefts, rights = [], []
    for i in range(count):
        along = norm(sub(points[min(i + 1, count - 1)], points[max(i - 1, 0)]))
        across = norm(cross(normals[i], along))
        half = widths[i] / 2.0
        lefts.append(mesh.vert(add(points[i], mul(across, half))))
        rights.append(mesh.vert(add(points[i], mul(across, -half))))
    for i in range(count - 1):
        facing = add(normals[i], normals[i + 1])
        mesh.tri(lefts[i], rights[i], lefts[i + 1], facing)
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1], facing)


# --- decals: ink cut out of a faceted surface and lifted off it -----------------------------------


def wrap(a: float) -> float:
    """An angle in (-pi, pi]."""
    return (a + math.pi) % (2.0 * math.pi) - math.pi


def area2(poly) -> float:
    return sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))


def clip_convex(poly, clipper):
    """Sutherland-Hodgman: `poly` is [(point2, weights)], `clipper` a counter-clockwise convex polygon.
    The weights (barycentric) are carried along the cuts."""
    out = list(poly)
    count = len(clipper)
    for i in range(count):
        a, b = clipper[i], clipper[(i + 1) % count]
        ex, ey = b[0] - a[0], b[1] - a[1]
        if ex * ex + ey * ey < 1e-18:
            continue

        def side(p):
            return ex * (p[1] - a[1]) - ey * (p[0] - a[0])

        src, out = out, []
        if not src:
            break
        for j in range(len(src)):
            p, q = src[j], src[(j + 1) % len(src)]
            dp, dq = side(p[0]), side(q[0])
            if dp >= 0.0:
                out.append(p)
            if (dp >= 0.0) != (dq >= 0.0):
                t = dp / (dp - dq)
                point = (p[0][0] + (q[0][0] - p[0][0]) * t, p[0][1] + (q[0][1] - p[0][1]) * t)
                out.append((point, tuple(x + (y - x) * t for x, y in zip(p[1], q[1]))))
    return out


def min_angle(a, b, c) -> float:
    worst = math.pi
    for o, p, q in ((a, b, c), (b, c, a), (c, a, b)):
        u, v = sub(p, o), sub(q, o)
        lu, lv = math.sqrt(dot(u, u)), math.sqrt(dot(v, v))
        if lu < 1e-12 or lv < 1e-12:
            return 0.0
        worst = min(worst, math.acos(max(-1.0, min(1.0, dot(u, v) / (lu * lv)))))
    return worst


def fill_convex(mesh: Mesh, ids: list[int], facing) -> None:
    """A convex polygon in triangles, ear by ear, always the ear whose worst angle is the widest: no
    slivers where a cut skims a corner. Points on a straight edge are dropped first (the lift along an
    edge is one vector, so the neighbour's edge stays straight through them: no crack)."""
    ids = list(ids)
    changed = True
    while changed and len(ids) > 3:
        changed = False
        for i in range(len(ids)):
            a, b, c = mesh.verts[ids[i - 1]], mesh.verts[ids[i]], mesh.verts[ids[(i + 1) % len(ids)]]
            u, v = sub(b, a), sub(c, b)
            lu, lv = math.sqrt(dot(u, u)), math.sqrt(dot(v, v))
            if lu < 1e-6 or lv < 1e-6 or dot(u, v) / (lu * lv) > math.cos(math.radians(0.5)):
                del ids[i]
                changed = True
                break
    while len(ids) >= 3:
        if len(ids) == 3:
            mesh.tri(ids[0], ids[1], ids[2], facing)
            return
        best, pick = -1.0, 0
        for i in range(len(ids)):
            m = min_angle(mesh.verts[ids[i - 1]], mesh.verts[ids[i]], mesh.verts[ids[(i + 1) % len(ids)]])
            if m > best:
                best, pick = m, i
        mesh.tri(ids[pick - 1], ids[pick], ids[(pick + 1) % len(ids)], facing)
        del ids[pick]


def weld(mesh: Mesh, first_vert: int, first_tri: int, tolerance: float) -> None:
    """Merge the points added since `first_vert` that lie within `tolerance` of each other, and drop the
    triangles that collapse: the pieces of one mark become one strip, and a cut that skims a facet's
    corner leaves no sliver."""
    keep: dict = {}
    remap = {}
    cell = tolerance
    for v in range(first_vert, len(mesh.verts)):
        p = mesh.verts[v]
        key = tuple(int(math.floor(c / cell)) for c in p)
        found = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for w in keep.get((key[0] + dx, key[1] + dy, key[2] + dz), ()):
                        if math.dist(mesh.verts[w], p) < tolerance:
                            found = w
                            break
                    if found is not None:
                        break
                if found is not None:
                    break
            if found is not None:
                break
        if found is None:
            keep.setdefault(key, []).append(v)
            remap[v] = v
        else:
            remap[v] = found
    tris = []
    for a, b, c in mesh.tris[first_tri:]:
        a, b, c = remap.get(a, a), remap.get(b, b), remap.get(c, c)
        if a != b and b != c and a != c:
            n = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
            if dot(n, n) > 1e-16:
                tris.append((a, b, c))
    # Where the stroke thins to its point, the merge can leave a crumb cut off from the strip: the stroke
    # ends where it stays whole.
    parent = {v: v for t in tris for v in t}

    def find(v):
        while parent[v] != v:
            parent[v] = parent[parent[v]]
            v = parent[v]
        return v

    for a, b, c in tris:
        for u, v in ((a, b), (b, c)):
            parent[find(u)] = find(v)
    area: dict = {}
    for t in tris:
        n = face_normal(*(mesh.verts[v] for v in t))
        area[find(t[0])] = area.get(find(t[0]), 0.0) + math.sqrt(dot(n, n)) / 2.0
    largest = max(area.values(), default=0.0)
    mesh.tris[first_tri:] = [t for t in tris if area[find(t[0])] >= 0.05 * largest]


class Facets:
    """A faceted volume with each vertex's (s, angle) on the body it was cut from, so a mark drawn in
    (s, angle) can be cut out of its triangles and lifted off them."""

    def __init__(self, vol: Volume, params: list, band: list[int]) -> None:
        mesh = vol.mesh
        self.verts, self.tris, self.params, self.band = mesh.verts, mesh.tris, params, band
        self.normals = [norm(face_normal(*(mesh.verts[i] for i in t))) for t in mesh.tris]
        self.at_vert: list[list[int]] = [[] for _ in mesh.verts]
        self.at_edge: dict = {}
        for n, (a, b, c) in enumerate(mesh.tris):
            for v in (a, b, c):
                self.at_vert[v].append(n)
            for u, v in ((a, b), (b, c), (c, a)):
                self.at_edge.setdefault((min(u, v), max(u, v)), []).append(n)

    def lift(self, t: int, weights, amount: float):
        """Where a point of triangle t goes when lifted `amount` off every face it touches: along its
        face's normal inside it, along the faces' mean (pushed further, so each stays `amount` off) on an
        edge or a corner, so the pieces of a mark meet without a crack."""
        ids = self.tris[t]
        zero = [k for k in range(3) if weights[k] < 1e-9]
        if len(zero) >= 2:
            around = self.at_vert[ids[[k for k in range(3) if k not in zero][0]]]
        elif len(zero) == 1:
            u, v = (ids[k] for k in range(3) if k != zero[0])
            around = self.at_edge[(min(u, v), max(u, v))]
        else:
            around = [t]
        normals = [self.normals[n] for n in around]
        n = norm(mean(normals))
        reach = max(min(dot(n, f) for f in normals), 0.5)
        return mul(n, amount / reach)

    def decal(self, into: Mesh, polygon, centre: float, amount: float) -> None:
        """Cut the convex `polygon` [(s, angle - centre)] out of the band's triangles, lifted `amount`."""
        if area2(polygon) < 0:
            polygon = polygon[::-1]
        smin, smax = min(p[0] for p in polygon), max(p[0] for p in polygon)
        amin, amax = min(p[1] for p in polygon), max(p[1] for p in polygon)
        for t in self.band:
            ids = self.tris[t]
            local = []
            for k, v in enumerate(ids):
                s, a = self.params[v]
                weights = [0.0, 0.0, 0.0]
                weights[k] = 1.0
                local.append(((s, wrap(a - centre)), tuple(weights)))
            if max(abs(p[0][1]) for p in local) > 2.4:
                continue
            if max(p[0][0] for p in local) < smin or min(p[0][0] for p in local) > smax:
                continue
            if max(p[0][1] for p in local) < amin or min(p[0][1] for p in local) > amax:
                continue
            if area2([p[0] for p in local]) < 0:
                local = local[::-1]
            cut = clip_convex(local, polygon)
            if len(cut) < 3:
                continue
            corners = [self.verts[i] for i in ids]
            made = []
            for _, w in cut:
                p = add(add(mul(corners[0], w[0]), mul(corners[1], w[1])), mul(corners[2], w[2]))
                made.append(into.vert(add(p, self.lift(t, w, amount))))
            fill_convex(into, made, self.normals[t])


# --- the Teardrop ---------------------------------------------------------------------------------
# Built in studs (head 4.2 from nose to neck), then scaled to Length = 1.

HEAD_STUDS = 4.2
HEAD_R = 0.98  # the head's radius at its widest
HEAD_FLAT = 0.93  # its height over its width
HEAD_SIDES = 7
NOSE_Z = -0.95  # the nose; the pivot (z = 0) is the head's widest ring
# (s from nose 0 to neck 1, radius / HEAD_R): blunt and round in front, drawn out late into the tail.
# Few rings, so the planes are long and the outline kinks where they meet, as cut, not turned.
HEAD_PROFILE = [(0.0, 0.46), (0.06, 0.8), (0.17, 0.97), (0.32, 1.0), (0.5, 0.86), (0.68, 0.64), (0.85, 0.42), (1.0, 0.25)]
TAIL_RISE = 0.55  # how far the spine rises from the head to the neck
HEAD_WEIGHT = (0.15, 0.16, 0.11)  # contour at the nose, the widest, the neck (studs)
NOSE_LINE = 0.07  # the ink round the nose facet
INK_LIFT = 0.025  # how far the keel, the cuts and the nose line stand off the facets (studs)
CUT_SAMPLES = 14  # stations along a cut
WELD = (0.02, 0.018)  # points of one mark closer than this are one point (studs) -- the keel, a cut: no slivers, no cracks

# The lobe: (s of its centre, half length forward, half length back, half width, half height, how far its
# top stands over the head, tilt up toward the tail in degrees). A pigment dome sunk in the head, with its
# own contour like every volume; the pale (Core) is a cap cut out of its upper facets and lifted LOBE_LIFT
# off them, down to LOBE_CAP degrees from its crown, so a band of cinnabar rings it where the dome meets
# the head: the pale is always inside the pigment and the ink (bible §2), never a pale volume of its own.
LOBE = (0.38, 0.76, 0.98, 0.42, 0.54, 0.66, 6.0)
LOBE_WEIGHT = 0.12
LOBE_RINGS = (24.0, 50.0, 70.0, 88.0, 128.0)  # the dome's rings, degrees down from its crown
LOBE_CAP = 3  # the pale covers the crown down to this ring (index in LOBE_RINGS): 88 degrees
LOBE_SEGMENTS = 10
LOBE_LIFT = 0.04  # studs, the bible's 0.03-0.08

# The whips: (bead x, bead y -- across and up, absolute, the flight axis at x = y = 0; how far behind the
# neck the bead hangs; the root's s on the tail; how far the cord turns about the neck from root to bead
# (degrees, all one way: against the spin); how high it lifts before it droops; how late it droops (the
# power of its fall); its thickness). Like the model sheet, every cord leaves the tip of the risen tail,
# runs back and falls late into a bead below the head: from the side a willow, from the front five legs
# under the head, from above five cords trailing and parting. From the thrower's seat each is a curved
# spoke turning the same way, a whirl, never parallel fingers; and the lower a bead hangs the farther
# back it trails, so the five land at five heights on the thrower's screen, never one row. Five roots,
# lengths, turns, lifts and falls: no two alike.
WHIPS = ((-1.45, -1.25, 2.4, 0.88, 12.0, 0.45, 1.8, 1.0),
         (-0.62, -2.3, 3.0, 0.97, 28.0, 0.2, 1.05, 0.9),
         (0.12, -2.75, 4.15, 0.92, 16.0, 0.35, 1.9, 1.1),
         (0.98, -1.7, 4.0, 0.99, 24.0, 0.65, 2.6, 0.85),
         (1.6, -0.85, 3.5, 0.86, 30.0, 1.0, 2.3, 1.0))
WHIP_WOBBLE = 14.0  # degrees, the largest swing of a cord's S about its even turn
WHIP_PART = 1.2  # how early the cords part sideways (the power of their spread; their fall has its own)
WHIP_R = (0.055, 0.035)  # cord radius at the root, at the end (studs): a thread of cinnabar in its contour
WHIP_WEIGHT = 0.1  # the cords' contour: the bible's floor, never less
BEAD_R = 0.27
BEAD_WEIGHT = 0.1
# The ink cut into the facets: start angle (degrees, 90 = the top, 270 = the belly), s from, s to, width
# (studs), turn (degrees, the whips' way). Two long cuts on the upper flanks; under the front half, the
# dark belly as three hatches of unequal length and turn, never parallel -- shading drawn with the brush,
# never a slab, never an eye, whichever way the spin has rolled it. Five flow lines in all (bible: 2-7).
FLANK_CUTS = ((30.0, 0.08, 0.78, 0.09, 18.0), (156.0, 0.11, 0.68, 0.08, 22.0))
BELLY_HATCH = ((262.0, 0.08, 0.56, 0.13, 24.0), (232.0, 0.17, 0.43, 0.075, 14.0), (296.0, 0.22, 0.63, 0.07, 32.0))
# The nose: an open stroke along part of the flat facet's rim (from, to: fractions of its perimeter, from
# the right going under), tapered at both ends -- a cut, not a bolt head.
NOSE_STROKE = (0.52, 0.93)


def head_frame(s: float):
    """Spine centre and radius of the head at s."""
    z = NOSE_Z + HEAD_STUDS * s
    y = TAIL_RISE * smoothstep(0.2, 1.0, s)
    return (0.0, y, z), HEAD_R * profile(s)


def profile(s: float) -> float:
    for i in range(1, len(HEAD_PROFILE)):
        s0, r0 = HEAD_PROFILE[i - 1]
        s1, r1 = HEAD_PROFILE[i]
        if s <= s1:
            return r0 + (r1 - r0) * (s - s0) / (s1 - s0)
    return HEAD_PROFILE[-1][1]


def head_weight(s: float) -> float:
    nose, mid, neck = HEAD_WEIGHT
    if s < 0.225:
        return nose + (mid - nose) * s / 0.225
    return mid + (neck - mid) * (s - 0.225) / 0.775


def build_head(rng: Rng):
    """The faceted head, as Facets (each corner's (s, angle) kept for the marks cut out of it); and the
    nose facet's corners and centre, for its ink."""
    vol = Volume()
    params: list = []
    rings = []
    step = 2.0 * math.pi / HEAD_SIDES
    for i, (s, _) in enumerate(HEAD_PROFILE):
        centre, r = head_frame(s)
        offset = 0.5 * step * (i % 2) - math.pi / 2.0
        ring = []
        for k in range(HEAD_SIDES):
            angle = offset + step * k
            wobble = 1.0 + 0.045 * (rng.random() * 2.0 - 1.0)
            p = (centre[0] + r * wobble * math.cos(angle), centre[1] + HEAD_FLAT * r * wobble * math.sin(angle), centre[2])
            ring.append(vol.vert(p, head_weight(s)))
            params.append((s, angle))
        rings.append((centre, ring))
    for i in range(len(rings) - 1):
        (c0, r0), (c1, r1) = rings[i], rings[i + 1]
        mid = mul(add(c0, c1), 0.5)
        # P: the ring at the even offset; Q: the one half a facet on.
        p, q = (r0, r1) if i % 2 == 0 else (r1, r0)
        for k in range(HEAD_SIDES):
            n = (k + 1) % HEAD_SIDES
            for tri in ((p[k], p[n], q[k]), (q[k], p[n], q[n])):
                vol.mesh.tri(*tri, sub(mean([vol.mesh.verts[t] for t in tri]), mid))
    band = list(range(len(vol.mesh.tris)))
    # A flat facet at the nose; a short point at the neck, buried in the whips' roots.
    centre, ring = rings[0]
    nose = vol.vert(centre, head_weight(0.0))
    params.append(None)
    for k in range(HEAD_SIDES):
        vol.mesh.tri(ring[k], ring[(k + 1) % HEAD_SIDES], nose, (0.0, 0.0, -1.0))
    centre, ring = rings[-1]
    tail = vol.vert(add(centre, (0.0, 0.0, 0.25)), HEAD_WEIGHT[2])
    params.append(None)
    for k in range(HEAD_SIDES):
        vol.mesh.tri(ring[k], ring[(k + 1) % HEAD_SIDES], tail, (0.0, 0.0, 1.0))
    return vol, Facets(vol, params, band), [vol.mesh.verts[v] for v in rings[0][1]], rings[0][0]


def build_nose_stroke(ink: Mesh, corners, centre) -> None:
    """An open stroke of ink along part of the nose facet's rim, INK_LIFT in front of it and inside its
    rim, swelling from nothing to NOSE_LINE and back: the facet reads cut, never a bolt head."""
    n = len(corners)
    lo, hi = NOSE_STROKE
    lift = (0.0, 0.0, -INK_LIFT)
    samples = 12
    outer, inner = [], []
    for i in range(samples + 1):
        f = i / samples
        at = (lo + (hi - lo) * f) * n
        k = int(math.floor(at)) % n
        g = at - math.floor(at)
        rim = add(mul(corners[k], 1.0 - g), mul(corners[(k + 1) % n], g))
        towards = sub(centre, rim)
        reach = math.sqrt(dot(towards, towards))
        w = NOSE_LINE * math.sin(math.pi * f) ** 0.7
        o = add(rim, mul(towards, 0.04))
        outer.append(ink.vert(add(o, lift)))
        inner.append(ink.vert(add(add(o, mul(towards, w / reach)), lift)))
    for i in range(samples):
        ink.tri(outer[i], outer[i + 1], inner[i + 1], (0.0, 0.0, -1.0))
        ink.tri(outer[i], inner[i + 1], inner[i], (0.0, 0.0, -1.0))


def build_cuts(ink: Mesh, facets: Facets, cuts) -> None:
    """Calligraphic cuts in the facets: each from `lo` to `hi` along the head, starting at its angle and
    turning about Z the way the whips spiral, swelling early and drying out, unequal, never parallel. Each
    is a strip of small convex pieces, every piece cut out of the facets and lifted off them."""
    for start, lo, hi, width, turn in cuts:
        samples = CUT_SAMPLES
        spine = []
        for i in range(samples):
            f = i / (samples - 1)
            s = lo + (hi - lo) * f
            angle = math.radians(start + turn * f * f)
            w = width * max(math.sin(math.pi * (0.04 + 0.92 * f)), 0.0) ** 0.6 * (1.0 - 0.45 * f)
            spine.append((s, angle, w))
        centre = spine[samples // 2][1]
        lefts, rights = [], []
        for i, (s, angle, w) in enumerate(spine):
            # Across the strip, in studs: s runs HEAD_STUDS a unit, the angle the radius there.
            r = HEAD_R * profile(s)
            s0, a0, _ = spine[max(i - 1, 0)]
            s1, a1, _ = spine[min(i + 1, samples - 1)]
            dx, dy = (s1 - s0) * HEAD_STUDS, wrap(a1 - a0) * r
            length = math.hypot(dx, dy)
            nx, ny = -dy / length, dx / length
            half = w / 2.0
            da = wrap(angle - centre)
            lefts.append((s + nx * half / HEAD_STUDS, da + ny * half / r))
            rights.append((s - nx * half / HEAD_STUDS, da - ny * half / r))
        first_vert, first_tri = len(ink.verts), len(ink.tris)
        for i in range(samples - 1):
            for piece in ((lefts[i], rights[i], rights[i + 1]), (lefts[i], rights[i + 1], lefts[i + 1])):
                if abs(area2(list(piece))) > 1e-12:
                    facets.decal(ink, list(piece), centre, INK_LIFT)
        weld(ink, first_vert, first_tri, WELD[1])


def lobe_volume():
    """The lobe's dome, a crown pole up: rings LOBE_RINGS degrees down from the crown, each an egg in
    plan (longer behind, toward the tail), every other ring turned half a step, so it is cut, not turned;
    tilted up toward the tail and placed on the head. Returns the volume and the triangles of the cap."""
    s, front_l, back_l, half_w, half_h, stand, tilt = LOBE
    centre, r = head_frame(s)
    top = centre[1] + HEAD_FLAT * r
    c = (0.0, top + stand - half_h, centre[2])
    tilt = math.radians(tilt)
    vol = Volume()
    crown = vol.vert((0.0, half_h, 0.0), LOBE_WEIGHT)
    rings = []
    for i, theta in enumerate(LOBE_RINGS):
        th = math.radians(theta)
        row = []
        for k in range(LOBE_SEGMENTS):
            phi = 2.0 * math.pi * (k + 0.5 * (i % 2)) / LOBE_SEGMENTS
            along = math.sin(phi)
            reach = back_l if along > 0.0 else front_l
            row.append(vol.vert((half_w * math.sin(th) * math.cos(phi), half_h * math.cos(th), reach * math.sin(th) * along), LOBE_WEIGHT))
        rings.append(row)
    foot = vol.vert((0.0, -half_h, 0.0), LOBE_WEIGHT)

    def out(*ids):
        return mean([vol.mesh.verts[i] for i in ids])

    cap = []
    for k in range(LOBE_SEGMENTS):
        n = (k + 1) % LOBE_SEGMENTS
        vol.mesh.tri(crown, rings[0][k], rings[0][n], out(crown, rings[0][k], rings[0][n]))
        cap.append(len(vol.mesh.tris) - 1)
    for i in range(len(rings) - 1):
        for k in range(LOBE_SEGMENTS):
            n = (k + 1) % LOBE_SEGMENTS
            a, b, cc, d = rings[i][k], rings[i][n], rings[i + 1][k], rings[i + 1][n]
            if i % 2 == 0:
                pair = ((a, b, d), (a, d, cc))
            else:
                pair = ((a, b, cc), (b, d, cc))
            for tri in pair:
                vol.mesh.tri(*tri, out(*tri))
                if i < LOBE_CAP:
                    cap.append(len(vol.mesh.tris) - 1)
    for k in range(LOBE_SEGMENTS):
        n = (k + 1) % LOBE_SEGMENTS
        vol.mesh.tri(foot, rings[-1][k], rings[-1][n], out(foot, rings[-1][k], rings[-1][n]))
    placed = []
    for x, y, z in vol.mesh.verts:
        placed.append(add(c, (x, y * math.cos(tilt) - z * math.sin(tilt), y * math.sin(tilt) + z * math.cos(tilt))))
    vol.mesh.verts = placed
    return vol, cap


def skin(vol: Volume, tris: list[int], lift: float, into: Mesh) -> None:
    """The triangles `tris` of a closed volume again, every corner pushed out along its averaged normal so
    each face round it stands `lift` off: a skin that follows the facets exactly, wound outward."""
    mesh = vol.mesh
    faces: list[list] = [[] for _ in mesh.verts]
    for a, b, c in mesh.tris:
        n = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
        if dot(n, n) < 1e-24:
            continue
        for v in (a, b, c):
            faces[v].append(norm(n))
    made: dict = {}
    for t in tris:
        a, b, c = mesh.tris[t]
        ids = []
        for v in (a, b, c):
            if v not in made:
                n = norm(mean(faces[v]))
                reach = max(min(dot(n, f) for f in faces[v]), 0.5)
                made[v] = into.vert(add(mesh.verts[v], mul(n, lift / reach)))
            ids.append(made[v])
        into.tris.append(tuple(ids))


def whip_control(spec, rng: Rng):
    """Control points of a whip: sunk in the tail near its tip, out through the surface, then back along
    the flight and down into its bead, in turn and reach about the neck: its bearing turns steadily (the
    spiral, against the spin), its reach grows late (it runs back first and falls at the end, a willow),
    with a small lift on the way."""
    bx, by, trail, root_s, turn, lift, fall, _ = spec
    centre, r = head_frame(root_s)
    neck, _ = head_frame(1.0)
    rho_b, phi_b = math.hypot(bx, by - neck[1]), math.atan2(by - neck[1], bx)
    phi0 = phi_b - math.radians(turn)
    radial = (math.cos(phi0), HEAD_FLAT * math.sin(phi0), 0.0)
    root = (centre[0] + 0.4 * r * radial[0], centre[1] + 0.4 * r * radial[1], centre[2] - 0.12)
    exit_ = (centre[0] + 1.0 * r * radial[0], centre[1] + 1.0 * r * radial[1], centre[2] + 0.04)
    rho_e = math.hypot(exit_[0], exit_[1] - neck[1])
    z_b = neck[2] + trail
    wobble = math.radians(WHIP_WOBBLE) * (0.6 + 0.4 * rng.random())
    phase = 2.0 * math.pi * rng.random()
    points = [root, exit_]
    count = 8
    for i in range(1, count + 1):
        u = i / count
        # Across, the cords part early (from above they splay like the sheet's); down, they fall late.
        across = rho_e + (rho_b - rho_e) * u**WHIP_PART
        down = rho_e + (rho_b - rho_e) * u**fall
        # A slow S of its own about the even turn (seeded phase): two cords never run side by side.
        phi = phi0 + (phi_b - phi0) * u + wobble * math.sin(2.0 * math.pi * u + phase) * 4.0 * u * (1.0 - u)
        z = exit_[2] + (z_b - exit_[2]) * (1.0 - (1.0 - u) ** 1.35)
        # The lift peaks a third of the way and is gone at the bead: the sheet's fountain arc.
        y = neck[1] + down * math.sin(phi) + lift * math.sin(math.pi * u**0.7) * (1.0 - u) ** 0.6 / 0.79
        points.append((across * math.cos(phi), y, z))
    return points


def _teardrop():
    if "teardrop" in _CACHE:
        return _CACHE["teardrop"]
    rng = Rng(SEED)
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    head, facets, nose_corners, nose_centre = build_head(rng)
    lobe, cap = lobe_volume()
    solids = [head, lobe]
    for spec in WHIPS:
        control = whip_control(spec, rng)
        thick = spec[-1]
        r0, r1 = WHIP_R
        whip = cord(control, lambda u: thick * (r0 + (r1 - r0) * smoothstep(0.0, 0.8, u)), lambda u: WHIP_WEIGHT, 8, 3, rng.random())
        solids.append(whip)
        solids.append(uv_bead(control[-1], BEAD_R * (0.94 + 0.12 * rng.random()), BEAD_WEIGHT, sub(control[-1], control[-2]), rng.random()))
    for vol in solids:
        body.merge(vol.mesh)
        hull(vol, ink)
    skin(lobe, cap, LOBE_LIFT, core)
    build_cuts(ink, facets, FLANK_CUTS + BELLY_HATCH)
    build_nose_stroke(ink, nose_corners, nose_centre)
    zs = [v[2] for mesh in (body, core, ink) for v in mesh.verts]
    factor = 1.0 / (max(zs) - min(zs))
    for mesh in (body, core, ink):
        mesh.scale(factor)
    _CACHE["teardrop"] = (body, core, ink)
    return _CACHE["teardrop"]


# --- the Star -------------------------------------------------------------------------------------
# Built at its final scale: Diameter 1 (20 studs), the outer ink of every bead on the sphere of radius 0.5.

STAR_SEED = SEED + 17
HUB_R = 0.042
HUB_WEIGHT = 0.009
STAR_BEAD_R = 0.032
STAR_BEAD_WEIGHT = 0.009
BEAD_CENTRE = 0.5 - STAR_BEAD_R - STAR_BEAD_WEIGHT  # the bead's outer ink touches 0.5
ARM_WIDE = 0.072  # an arm's half-width where it leaves the centre
ARM_DEEP = 0.056  # its half-depth there
ARM_NECK = 0.006  # its half-width at the bead
ARM_STATIONS = (-0.03, 0.14, 0.28, 0.39, BEAD_CENTRE)  # its rings, closer toward the stem
ARM_WEIGHT = (0.0095, 0.0075)
STREAK_LIFT = 0.002
CREASE = (0.011, 0.0015)  # an ink crease's half-width at its widest, its lift
# (elevation, azimuth from +X toward -Z), degrees: three rising, three level, three falling, the falling
# triad turned 52-64 degrees off the rising one (antiprism-like), so straight down or straight up the nine
# bearings and beads all part; turned and jittered by a seeded search until no two arms cross from the
# victim's spot, the thrower's seat near and far, the side, the three quarters, above, below, under the
# burst or from a ground bystander, and none points at a viewer (star_search_v4.py, seed 31337).
ARM_DIRS = [(53.8, 74.2), (39.7, 183.6), (51.8, 317.0), (5.6, 115.8), (-5.4, 218.9), (4.2, 338.4), (-44.4, 131.1),
            (-46.6, 263.7), (-37.8, 10.3)]


def arm_dir(el: float, az: float):
    el, az = math.radians(el), math.radians(az)
    return (math.cos(el) * math.cos(az), math.sin(el), -math.cos(el) * math.sin(az))


def arm_frame(d, roll: float):
    across = cross(d, (0.0, 1.0, 0.0))
    if dot(across, across) < 1e-6:
        across = (1.0, 0.0, 0.0)
    across = norm(across)
    up = norm(cross(across, d))
    if up[1] < 0:
        up = mul(up, -1.0)
    return rotate(across, d, roll), rotate(up, d, roll)


def arm_half(rho: float, scale: float) -> tuple[float, float]:
    """Half-width and half-depth at `rho` from the centre: ARM_WIDE x ARM_DEEP at the centre, then a
    straight taper to the stem at the bead (a pyramid, a compass point)."""
    f = max(0.0, 1.0 - rho / BEAD_CENTRE)
    return ARM_NECK + (ARM_WIDE * scale - ARM_NECK) * f, ARM_NECK + (ARM_DEEP * scale - ARM_NECK) * f


def build_arm(d, roll: float, scale: float):
    """A four-faced spike along `d`: diamond rings (corners: across+, up, across-, down) from inside the
    hub to the bead's centre, tapering straight to a thin stem the bead hides. The rings close in toward
    the bead, so the contour stays even to the very stem and no face is a sliver."""
    vol = Volume()
    across, up = arm_frame(d, roll)
    rings = []
    for rho in ARM_STATIONS:
        w, h = arm_half(rho, scale)
        c = mul(d, rho)
        weight = ARM_WEIGHT[0] + (ARM_WEIGHT[1] - ARM_WEIGHT[0]) * max(rho, 0.0) / BEAD_CENTRE
        corners = [add(c, mul(across, w)), add(c, mul(up, h)), add(c, mul(across, -w)), add(c, mul(up, -h))]
        rings.append(([vol.vert(p, weight) for p in corners], corners, rho))
    for i in range(len(rings) - 1):
        a, _, ra = rings[i]
        b, _, rb = rings[i + 1]
        mid = mul(d, 0.5 * (ra + rb))
        for j in range(4):
            k = (j + 1) % 4
            for tri in ((a[j], a[k], b[k]), (a[j], b[k], b[j])):
                vol.mesh.tri(*tri, sub(mean([vol.mesh.verts[t] for t in tri]), mid))
    root = vol.vert(mul(d, -0.045), ARM_WEIGHT[0])
    tip = vol.vert(mul(d, BEAD_CENTRE + 0.01), ARM_WEIGHT[1])
    for ring, end, facing in ((rings[0][0], root, mul(d, -1.0)), (rings[-1][0], tip, d)):
        for j in range(4):
            vol.mesh.tri(ring[j], ring[(j + 1) % 4], end, facing)
    return vol, rings


def face_at(rings, j: int, k: int, rho: float, f: float):
    """The point `f` of the way from corner j to corner k of the arm's face, at `rho`."""
    m = 0
    while m < len(rings) - 2 and rho > rings[m + 1][2]:
        m += 1
    (_, ca, ra), (_, cb, rb) = rings[m], rings[m + 1]
    g = (rho - ra) / max(rb - ra, 1e-9)
    pj = add(mul(ca[j], 1 - g), mul(cb[j], g))
    pk = add(mul(ca[k], 1 - g), mul(cb[k], g))
    return add(mul(pj, 1 - f), mul(pk, f))


def face_normal_out(rings, j, k, d, rho: float):
    """The outward normal of the face between corners j and k, near `rho` (the face is folded once
    along its diagonal; take the half that point lies on)."""
    a0, a1 = face_at(rings, j, k, rho - 0.02, 0.0), face_at(rings, j, k, rho + 0.02, 0.0)
    b0 = face_at(rings, j, k, rho, 1.0)
    n = norm(cross(sub(a1, a0), sub(b0, a0)))
    if dot(n, sub(face_at(rings, j, k, rho, 0.5), mul(d, rho))) < 0:
        n = mul(n, -1.0)
    return n


def streak(core: Mesh, rings, d, j: int, k: int, lo: float, hi: float, centre: float, spread: float) -> None:
    """A pale lens on the arm's face between corners j and k, pointed at both ends, `centre` of the way
    across it, `spread` of the face's width either side at its widest."""
    samples = 8
    lefts, rights, normals = [], [], []
    for i in range(samples):
        f = i / (samples - 1)
        rho = lo + (hi - lo) * f
        half = spread * math.sin(math.pi * f) ** 0.7
        n = face_normal_out(rings, j, k, d, rho)
        normals.append(n)
        lefts.append(core.vert(add(face_at(rings, j, k, rho, centre - half), mul(n, STREAK_LIFT))))
        rights.append(core.vert(add(face_at(rings, j, k, rho, centre + half), mul(n, STREAK_LIFT))))
    for i in range(samples - 1):
        n = add(normals[i], normals[i + 1])
        core.tri(lefts[i], rights[i], rights[i + 1], n)
        core.tri(lefts[i], rights[i + 1], lefts[i + 1], n)


def crease(ink: Mesh, rings, d, j: int, k: int, lo: float, hi: float) -> None:
    """An ink crease along the ridge (corner j) on the face toward corner k: tapered at both ends, its
    width absolute, so it reads the same on a broad arm and a slim one."""
    half, lift = CREASE
    samples = 8
    points, widths, normals = [], [], []
    for i in range(samples):
        f = i / (samples - 1)
        rho = lo + (hi - lo) * f
        n = face_normal_out(rings, j, k, d, rho)
        ridge = face_at(rings, j, k, rho, 0.0)
        other = face_at(rings, j, k, rho, 1.0)
        w = half * math.sin(math.pi * (0.08 + 0.84 * f)) ** 0.6 * (1.0 - 0.5 * f)
        towards = norm(sub(other, ridge))
        points.append(add(add(ridge, mul(towards, w + 0.002)), mul(n, lift)))
        widths.append(2.0 * w)
        normals.append(n)
    ribbon_on(ink, points, normals, widths)


def _star():
    if "star" in _CACHE:
        return _CACHE["star"]
    rng = Rng(STAR_SEED)
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    solids = [icosahedron_bead((0.0, 0.0, 0.0), HUB_R, HUB_WEIGHT, norm((0.3, 1.0, 0.2)), 0.4)]
    arms = []
    for el, az in ARM_DIRS:
        d = arm_dir(el, az)
        roll = math.radians(45.0 + 15.0 * (rng.random() * 2.0 - 1.0))
        scale = 1.0 + 0.1 * (rng.random() * 2.0 - 1.0)
        vol, rings = build_arm(d, roll, scale)
        arms.append((el, d, rings))
        solids.append(vol)
        solids.append(uv_bead(mul(d, BEAD_CENTRE), STAR_BEAD_R, STAR_BEAD_WEIGHT, d, rng.random()))
    for vol in solids:
        body.merge(vol.mesh)
        hull(vol, ink)
    for el, d, rings in arms:
        if el > 20.0:
            streak(core, rings, d, 1, 0, 0.14, 0.37, 0.45, 0.27)
        else:
            crease(ink, rings, d, 1, 0, 0.14, 0.4)
    # One uniform scale for all three, so the farthest ink -- a bead's contour -- lies exactly on 0.5.
    reach = max(math.sqrt(dot(v, v)) for mesh in (body, core, ink) for v in mesh.verts)
    for mesh in (body, core, ink):
        mesh.scale(0.5 / reach)
    _CACHE["star"] = (body, core, ink)
    return _CACHE["star"]


def _teardrop_meta() -> dict:
    return {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": SEED}


def _star_meta() -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": STAR_SEED}


def teardrop_body() -> tuple[Mesh, dict]:
    return _teardrop()[0], _teardrop_meta()


def teardrop_core() -> tuple[Mesh, dict]:
    return _teardrop()[1], _teardrop_meta()


def teardrop_ink() -> tuple[Mesh, dict]:
    return _teardrop()[2], _teardrop_meta()


def blot_body() -> tuple[Mesh, dict]:
    return _star()[0], _star_meta()


def blot_core() -> tuple[Mesh, dict]:
    return _star()[1], _star_meta()


def blot_ink() -> tuple[Mesh, dict]:
    return _star()[2], _star_meta()
