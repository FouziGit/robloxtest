"""The Pounce's raked dunes (Verdigris + Verdigris + Umber): the page dusted through a pricked stencil and
raked into broken rings of low dunes, drawn after the developer's two references (docs/vfx/pounce/ref-1.jpg,
the zone in game; ref-2.jpg, the model sheet "Verdigris ink pounce dunes").

Roblox space: X right, Y up, forward -Z; the pivot (0, 0, 0) is on the floor under the zone's centre. The
body lies on the page and never turns (no Spin): the server's zone (Radius 13, centred Offset 14 ahead of the
thrower) is a sphere whose disc on the floor is sqrt(13^2 - 3^2) = 12.65 studs; the outer ink (the hull
of the base, contour included) is exactly 0.5 from the pivot, so the runtime's OuterDiameter puts the
contour on that disc. Nothing stands higher than 1 stud at that size (0.0395 of the reference).

What it is, after the model sheet's top view (which rules the shape) and the in-game shot (which rules
the scale against the avatar):
  - the base: the dusted page, one flat disc 0.16 stud thick with a chamfered rim and the heavy
    contour all round it (its hull's floor ring seen from above, its rim seen from the thrower);
  - three rings of broken dune arcs (K9, dune profile): four on the outer ring, four on the middle
    one, one on the inner, the gaps staggered ring to ring, at the sheet's own angles. Every arc is one
    rake stroke, drawn clockwise seen from above: a loaded blunt head, an even body, a dry tail that
    tapers to a point over its last fifth and hooks a little in toward the centre. Its section is a
    dune: a short apron on the windward side (toward the centre), a long gentle windward slope up to
    the crest (where the pale line lies), and a steep lee face outward;
  - the pricked pattern: two dotted curves of small round heaps of powder that close the inner ring
    after its one arc, the dots dwindling along each curve.

Three meshes, one tone each: pounce_dunes (Pigment: the base, the arcs, the heaps), pounce_crest (Core:
one pale line along each crest, a lens cut along the crest's own triangles, lifted, pigment all round
it), pounce_ink (Ink: the inverted hull of every piece -- heavy on the base's rim (0.28 stud seen from
above), heavier on the lee side of each dune than on its windward foot, so every arc is a pale bar in a
dark outline from above and a pale crest over a dark line from the thrower -- and five calligraphic
flow lines, hairlines lying along the windward apron of five dunes, the rake's own line).

Not followed from the in-game shot: its two rows of pricks near the rim. The model sheet rules the shape
and puts the pricked pattern on the inner ring, closing it after its one arc; the bible counts two
dotted curves, so that dotted ring is broken in two.
"""

from __future__ import annotations

import math

from strokes import (
    Mesh,
    Rng,
    Volume,
    add,
    cross,
    emit,
    face_normal,
    fbm,
    mul,
    norm,
    sliver,
    smoothstep,
    sub,
    surface_ribbon,
)

SEED = 6203

# --- the base: the dusted page --------------------------------------------------------------------
BASE_H = 0.0062  # the page's thickness (0.16 stud): a sheet of dust, the dunes are the relief
R_BOT = 0.489  # the chamfer's foot, on the floor
R_TOP = 0.479  # the chamfer's top edge
DISC_SEGS = 52
DISC_WOBBLE = 0.006  # the rim is dusted, not turned on a lathe
DISC_WEIGHT = 0.0072  # the heavy contour: with the chamfer it covers, 0.28 stud from above at the final size
FLOOR = 0.0025  # how far over the floor a contour's floor ring lies (0.06 stud)
CLEAR = 0.0022  # how far over the page a dune's or a heap's floor ring lies

# --- the dunes --------------------------------------------------------------------------------------
# The section, from the windward foot (toward the centre) to the lee foot (outward): across in widths,
# up in heights, contour weight. The windward foot is buried in the page, so the slope melts into it.
SECTION = [
    (-0.50, 0.00, 0.0040),  # windward foot, on the page
    (-0.40, 0.66, 0.0040),  # the short apron's top
    (-0.26, 0.93, 0.0044),  # the crest's face begins (flat: about 6 degrees, so the pale reads from the game camera)
    (0.16, 1.00, 0.0058),  # the crest's edge, over the lee
    (0.21, 0.52, 0.0072),  # the lee face's shoulder
    (0.30, 0.00, 0.0086),  # lee foot, on the page: the lee drops steep under the crest
]
CREST_FACE = (2, 3)
CREST_LIFT = 0.0022  # the pale line rides 0.055 stud off the crest

# The arcs, after the model sheet's top view: angles in degrees counter-clockwise from +X seen from above
# (the image's own angles, up = forward), from the head (blunt, loaded) to the tail (dry, hooked).
# r is the crest's radius as a share of R_TOP; drift how much it grows head to tail.
ARCS = [
    # the outer ring
    {"head": 88, "tail": 8, "r": 0.860, "W": 0.0314, "H": 0.0200, "drift": -0.013},
    {"head": 180, "tail": 100, "r": 0.865, "W": 0.0300, "H": 0.0200, "drift": 0.010},
    {"head": 272, "tail": 201, "r": 0.875, "W": 0.0314, "H": 0.0200, "drift": -0.015},
    {"head": 357, "tail": 278, "r": 0.880, "W": 0.0307, "H": 0.0200, "drift": 0.007},
    # the middle ring
    {"head": 132, "tail": 53, "r": 0.655, "W": 0.0293, "H": 0.0262, "drift": 0.015},
    {"head": 41, "tail": -34, "r": 0.665, "W": 0.0278, "H": 0.0262, "drift": -0.010},
    {"head": 219, "tail": 145, "r": 0.670, "W": 0.0293, "H": 0.0262, "drift": 0.013},
    {"head": 314, "tail": 233, "r": 0.685, "W": 0.0286, "H": 0.0262, "drift": -0.015},
    # the inner ring's one arc
    {"head": 185, "tail": 102, "r": 0.480, "W": 0.0264, "H": 0.0278, "drift": 0.015},
]
HOOK = 0.12  # how far in a tail hooks, in widths
SEG_LEN = 0.052  # target length of a segment along an arc

# --- the pricked pattern ------------------------------------------------------------------------------
# Two dotted curves on the inner ring, after the inner arc's tail: (from, to) degrees, dots.
DOTS = [(86.0, -42.0, 16), (-55.0, -168.0, 14)]
DOT_R = 0.0088  # a heap's radius (0.22 stud)
DOT_H = 0.0080  # its height over the page
DOT_SIDES = 5
DOT_WEIGHT = 0.0042
DOT_RING = 0.480  # share of R_TOP

# --- the flow lines -----------------------------------------------------------------------------------
# The flow lines: a calligraphic hairline lying along the windward slope of five dunes, the way the rake
# went -- (arc index, from, to (shares of the arc), across the slope (0 the windward foot, 1 the first
# corner up, 2 the crest's flat), width).
TAILS = [0, 2, 4, 6, 8]  # arcs whose ink carries on past the pigment
TAIL_SPAN = 8.5  # degrees of ring the tail covers
TAIL_WIDTH = 0.0046
FLOW_LIFT = 0.0018


# --- helpers ------------------------------------------------------------------------------------------


def polar(deg: float, r: float) -> tuple[float, float]:
    """(x, z) of a point `deg` counter-clockwise from +X seen from above, `r` from the pivot."""
    a = math.radians(deg)
    return r * math.cos(a), -r * math.sin(a)


class Piece(Volume):
    """A closed volume wound outward, with a contour weight and a floor for its hull per vertex."""

    def __init__(self) -> None:
        super().__init__()
        self.floor: list[float] = []

    def vert(self, p, weight: float, floor: float = FLOOR) -> int:
        self.floor.append(floor)
        return super().vert(p, weight)


def check_closed(vol: Volume) -> None:
    """Every edge shared by exactly two triangles, once each way: a closed, consistently wound piece."""
    edges: dict = {}
    for a, b, c in vol.mesh.tris:
        for e in ((a, b), (b, c), (c, a)):
            edges[e] = edges.get(e, 0) + 1
    for (a, b), n in edges.items():
        if n != 1 or edges.get((b, a), 0) != 1:
            raise ValueError(f"open or folded edge {(a, b)}: {n} / {edges.get((b, a), 0)}")


def flat_up(mesh: Mesh, a: int, b: int, c: int) -> bool:
    n = norm(face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c]))
    return n[1] > 0.95


def hull(vol: Piece, into: Mesh) -> None:
    """strokes.inverted_hull with a floor per vertex: a dune's lee foot and a heap's foot are held a hair
    over the page, so their pushed-out floor ring is the dark line round them seen from above; the
    windward foot is left in the page, where its ring is hidden and the slope melts into the page."""
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        # Unit normals, not area-weighted: a rim vertex between the wide floor of the base and its narrow
        # chamfer must be pushed out across the page, not down into it.
        n = norm(face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c]))
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        q = add(p, mul(norm(acc[i]), vol.weight[i]))
        into.verts.append((q[0], max(q[1], vol.floor[i]), q[2]))
    for a, b, c in mesh.tris:
        if flat_up(mesh, a, b, c):
            continue  # an up-facing face's hull copy faces down: no camera above the page sees it
        corners = [into.verts[v + base] for v in (a, b, c)]
        floors = [vol.floor[v] for v in (a, b, c)]
        if all(q[1] <= f + 1e-9 for q, f in zip(corners, floors)) and sliver(*corners):
            continue
        emit(into, a + base, c + base, b + base)


def streak(core: Mesh, rows, normals, face, first: int, last: int, centre: float, spread: float, lift: float) -> None:
    """The pale lens over rows first..last of one face of a loft (fireball.streak, with its lift): cut
    along the face's own triangles (split along a0-b1) and lifted along the interpolated normal."""
    i, j = face
    band = []
    for k in range(first, last + 1):
        f = 0.45 + 0.55 * math.sin(math.pi * (k - first) / (last - first)) ** 0.5
        band.append((centre - spread * f, centre + spread * f))

    for k in range(first, last):
        a0, b0 = rows[k][i], rows[k][j]
        a1, b1 = rows[k + 1][i], rows[k + 1][j]
        n0, n1 = normals[k], normals[k + 1]
        (s0, s1), (t0, t1) = band[k - first], band[k - first + 1]
        poly = [(s0, 0.0), (s1, 0.0), (t1, 1.0), (t0, 1.0)]
        def place(u, v):
            p0 = add(a0, mul(sub(b0, a0), u))
            p1 = add(a1, mul(sub(b1, a1), u))
            return add(p0, mul(sub(p1, p0), v))

        ids = []
        for u, v in poly:
            up = norm(add(mul(n0, 1.0 - v), mul(n1, v)))
            ids.append(core.vert(add(place(u, v), mul(up, lift))))
        facing = norm(add(n0, n1))
        for m in range(1, len(ids) - 1):
            core.tri(ids[0], ids[m], ids[m + 1], facing)


# --- the base ----------------------------------------------------------------------------------------


def disc_radius(deg: float) -> float:
    return 1.0 + DISC_WOBBLE * (2.0 * fbm(3.0 * math.cos(math.radians(deg)) + 4.1, 3.0 * math.sin(math.radians(deg)) + 7.3, SEED) - 1.0)


def build_base() -> Piece:
    """The dusted page: a flat disc on the floor, chamfered at its rim, closed underneath (its hull's floor
    ring is the contour on the ground)."""
    vol = Piece()
    centre_top = vol.vert((0.0, BASE_H, 0.0), DISC_WEIGHT)
    centre_bot = vol.vert((0.0, 0.0, 0.0), DISC_WEIGHT)
    top, bot = [], []
    for k in range(DISC_SEGS):
        deg = 360.0 * k / DISC_SEGS
        f = disc_radius(deg)
        x, z = polar(deg, R_TOP * f)
        top.append(vol.vert((x, BASE_H, z), DISC_WEIGHT))
        x, z = polar(deg, R_BOT * f)
        bot.append(vol.vert((x, 0.0, z), DISC_WEIGHT))
    for k in range(DISC_SEGS):
        n = (k + 1) % DISC_SEGS
        emit(vol.mesh, centre_top, top[n], top[k])
        emit(vol.mesh, top[k], top[n], bot[n])
        emit(vol.mesh, top[k], bot[n], bot[k])
        emit(vol.mesh, centre_bot, bot[k], bot[n])
    vol.orient_outward()
    check_closed(vol)
    return vol


# --- the dunes -----------------------------------------------------------------------------------------


class Arc:
    """One rake stroke: its path on the page, its width and height along it."""

    def __init__(self, spec: dict, index: int) -> None:
        self.spec = spec
        self.seed = SEED + 31 * index
        span = abs(spec["tail"] - spec["head"])
        length = math.radians(span) * spec["r"] * R_TOP
        self.segs = max(6, round(length / SEG_LEN))

    def centre(self, s: float) -> tuple[float, float]:
        spec = self.spec
        deg = spec["head"] + (spec["tail"] - spec["head"]) * s
        r = spec["r"] * R_TOP * (1.0 + spec["drift"] * (s - 0.5))
        hook = HOOK * spec["W"] * smoothstep(0.62, 1.0, s) ** 2
        return polar(deg, r - hook)

    def frame(self, s: float):
        """(x, z) on the crest line, the outward unit vector across the arc (in the page)."""
        e = 1e-3
        ax, az = self.centre(max(0.0, s - e))
        bx, bz = self.centre(min(1.0, s + e))
        tx, tz = bx - ax, bz - az
        length = math.hypot(tx, tz) or 1.0
        nx, nz = tz / length, -tx / length
        cx, cz = self.centre(s)
        if nx * cx + nz * cz < 0:
            nx, nz = -nx, -nz
        return (cx, cz), (nx, nz)

    def width(self, s: float) -> float:
        wobble = 1.0 + 0.05 * (2.0 * fbm(2.5 * s, 0.7, self.seed) - 1.0)
        head = 0.80 + 0.20 * smoothstep(0.0, 0.10, s)
        tail = 1.0 - 0.70 * smoothstep(0.80, 1.0, s)  # blunt end: the ink tail carries the taper
        return self.spec["W"] * head * tail * wobble

    def height(self, s: float) -> float:
        wobble = 1.0 + 0.05 * (2.0 * fbm(2.5 * s, 2.3, self.seed + 5) - 1.0)
        peak = 0.40 + 0.60 * math.sin(math.pi * s) ** 0.8  # each arc rises to one peak
        return self.spec["H"] * peak * wobble


def station(u: float) -> float:
    """Where the u-th share of a loft's rings stands along its arc: closer together at the head and the
    tail, where the stroke presses in and lifts off, sparser over the even middle."""
    return u - 0.30 * math.sin(2.0 * math.pi * u) / (2.0 * math.pi)


def order_of(pivot: int) -> list[int]:
    m = len(SECTION)
    return [(pivot + j) % m for j in range(m)]


def build_dune(arc: Arc):
    """A dune along an arc, lofted through the section; its head capped, its tail closed to a point.
    Returns the piece, the corner positions of every ring and the crest face's normal at each."""
    vol = Piece()
    rings, positions, normals = [], [], []
    segs = arc.segs
    for i in range(segs):
        s = station(i / segs)
        (cx, cz), (nx, nz) = arc.frame(s)
        w, h = arc.width(s), arc.height(s)
        taper = 0.55 + 0.45 * (w / arc.spec["W"])
        ring, pos = [], []
        for k, (across, up, weight) in enumerate(SECTION):
            y = BASE_H + up * h
            p = (cx + nx * across * w, y, cz + nz * across * w)
            floor = BASE_H + CLEAR if up == 0.0 else FLOOR
            ring.append(vol.vert(p, max(0.004, weight * taper), floor))
            pos.append(p)
        rings.append(ring)
        positions.append(pos)
        a, b = pos[CREST_FACE[0]], pos[CREST_FACE[1]]
        along = (-nz, 0.0, nx)
        n = norm(cross(sub(b, a), along))
        if n[1] < 0:
            n = mul(n, -1.0)
        normals.append(n)
    m = len(SECTION)
    for r0, r1 in zip(rings, rings[1:]):
        for e in range(m):
            f = (e + 1) % m
            emit(vol.mesh, r0[e], r0[f], r1[f])
            emit(vol.mesh, r0[e], r1[f], r1[e])
    last = rings[-1]
    for j in range(1, m - 1):
        emit(vol.mesh, last[order_of(4)[0]], last[order_of(4)[j]], last[order_of(4)[j + 1]])
    # The head: a fan from the lee shoulder (the lee face is concave there; every other corner sees it).
    head = rings[0]
    pivot = 4
    order = [(pivot + j) % m for j in range(m)]
    for j in range(1, m - 1):
        emit(vol.mesh, head[order[0]], head[order[j + 1]], head[order[j]])
    vol.orient_outward()
    check_closed(vol)
    return vol, positions, normals


# --- the pricked pattern ------------------------------------------------------------------------------


def build_heap(x: float, z: float, scale: float, seed: int) -> Piece:
    """A small round heap of powder: a low drum whose top ring is turned half a step from its foot, so its
    sides fold into ten facets and it reads round from the low camera, not as a tent; closed below."""
    vol = Piece()
    rng = Rng(seed)
    r = DOT_R * scale
    h = DOT_H * scale
    turn = rng.random() * math.pi
    sides = DOT_SIDES
    foot, top = [], []
    for k in range(sides):
        a = turn + 2 * math.pi * k / sides
        foot.append(vol.vert((x + r * math.cos(a), BASE_H - 0.0006, z + r * math.sin(a)), DOT_WEIGHT, BASE_H + CLEAR))
    for k in range(sides):
        a = turn + 2 * math.pi * (k + 0.5) / sides
        top.append(vol.vert((x + 0.62 * r * math.cos(a), BASE_H + h, z + 0.62 * r * math.sin(a)), DOT_WEIGHT))
    for k in range(sides):
        n = (k + 1) % sides
        emit(vol.mesh, foot[k], foot[n], top[k])
        emit(vol.mesh, foot[n], top[n], top[k])
    for k in range(1, sides - 1):
        emit(vol.mesh, foot[0], foot[k + 1], foot[k])
        emit(vol.mesh, top[0], top[k], top[k + 1])
    vol.orient_outward()
    check_closed(vol)
    return vol


def heaps() -> list[Piece]:
    out = []
    radius = DOT_RING * R_TOP
    for c, (start, end, count) in enumerate(DOTS):
        for k in range(count):
            t = k / (count - 1)
            deg = start + (end - start) * t
            x, z = polar(deg, radius)
            out.append(build_heap(x, z, 1.0, SEED + 100 * c + k))
    return out


def flows(ink: Mesh, arcs: list[Arc]) -> None:
    """The dry ink tails: a hairline carrying five arcs' dark line past the end of their pigment, along the
    ring, pressed in and lifted off like a brush -- the way the model sheet's arcs trail off."""
    for n, index in enumerate(TAILS):
        arc = arcs[index]
        ex, ez = arc.centre(1.0)
        radius = math.hypot(ex, ez)
        end = math.degrees(math.atan2(-ez, ex))
        sign = 1.0 if arc.spec["tail"] > arc.spec["head"] else -1.0

        def point(tau, _t, end=end, radius=radius, sign=sign):
            x, z = polar(end + sign * (-1.5 + TAIL_SPAN * tau), radius)
            return (x, BASE_H, z)

        def normal(_tau, _t):
            return (0.0, 1.0, 0.0)

        surface_ribbon(ink, (point, normal), lambda tau: (tau, 0.0), TAIL_WIDTH, FLOW_LIFT, 9, SEED + 7 + n)


# --- the three meshes --------------------------------------------------------------------------------

_CACHE: dict = {}


def build() -> tuple[Mesh, Mesh, Mesh]:
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body, crest, ink = Mesh("up"), Mesh("up"), Mesh("up")
    pieces: list[Piece] = [build_base()]
    arcs = [Arc(spec, i) for i, spec in enumerate(ARCS)]
    for arc in arcs:
        vol, positions, normals = build_dune(arc)
        pieces.append(vol)
        n = len(positions)
        first, last = 2, n - 3
        streak(crest, positions, normals, CREST_FACE, first, last, 0.50, 0.465, CREST_LIFT)
    pieces += heaps()
    for vol in pieces:
        hull(vol, ink)
        vol.mesh.tris = [t for t in vol.mesh.tris if norm(face_normal(*(vol.mesh.verts[v] for v in t)))[1] > -0.95]  # no camera sees a bottom
        body.merge(vol.mesh)
    flows(ink, arcs)
    reach = max(math.hypot(x, z) for mesh in (body, crest, ink) for x, _, z in mesh.verts)
    for mesh in (body, crest, ink):
        mesh.scale(0.5 / reach)
    _CACHE["meshes"] = (body, crest, ink)
    return _CACHE["meshes"]


def meta(seed: int) -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def pounce_dunes() -> tuple[Mesh, dict]:
    return build()[0], meta(SEED)


def pounce_crest() -> tuple[Mesh, dict]:
    return build()[1], meta(SEED + 1)


def pounce_ink() -> tuple[Mesh, dict]:
    return build()[2], meta(SEED + 2)
