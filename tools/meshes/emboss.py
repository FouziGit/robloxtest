"""The Emboss (Gaufrage, Umber + Umber + Verdigris): the page pressed out from behind, one low ring round
the caster. Drawn after the developer's model sheet (docs/vfx/emboss/ref-2.jpg, "Umber ink embossed
ring"): a raised bulge with two bevelled steps round an open centre, an outward-leaning lip, and sixteen
pale notches leaning out over the rim -- "not a crown of blades", lower and shorter than the Rupture.

Roblox space: X right, Y up, forward -Z. Built in studs at full size (the server's Radius 13, drawn at
Size 1.97 R: the outer ink at 12.8, 1.65 tall), then scaled once so the outermost ink of the three meshes
sits exactly 0.5 from the pivot: Reference OuterDiameter = 1. The pivot (0, 0, 0) is on the floor under
the caster's root; nothing is below the floor.

Three meshes, one tone each, cut from one construction:
  - emboss_body (Pigment): a closed ring turned on a lathe of SEGS facets (hard edges, flat facets, as the
    sheet's notes ask), and sixteen bevelled lugs lying radially on the lip, each its own closed volume.
  - emboss_bevel (Core): the pale bevel on top of each lug, inset in its top face and lifted -- the only
    pale, always framed by the lug's own umber sides.
  - emboss_ink (Ink): the inverted hull of the ring and of every lug (the contour, and the ring on the
    page at the foot; see `hull`), and seven calligraphic strokes on the sheet's lines -- the dark inner
    bevel round the hole, the bulge's two steps, the lip's crease under the lugs, the rim's top edge --
    broken arcs of unequal length, pressed and released like a brush.

Budgets (art bible section 7, a big body): 1376 / 32 / 1642 triangles, each volume under 1800. Pale:
6.0 % of the body seen from above, 3.4 % from the thrower's camera (Umber: at most 6 %).
"""

from __future__ import annotations

import math

from strokes import (
    Mesh,
    Rng,
    Volume,
    add,
    dot,
    emit,
    fbm,
    FLOOR_CLEARANCE,
    face_normal,
    lerp,
    mul,
    norm,
    pressure,
    sliver,
    sub,
)

SEED = 5216
STUDS = 25.6  # the outer ink's diameter at full size (Size 1.97 x the server's Radius 13)
SEGS = 48  # lathe facets round the ring: three per notch
NOTCHES = 16

# The ring's section, (r, h) in studs, from the hole's foot up the inner wall, over the bulge and down the
# lip to the rim's foot; the floor closes it back to the hole. The bulge is the plateau and its two
# bevelled steps; the lip is gently convex and steepens past its crease into the rim's bevel.
PROFILE = [
    (8.02, 0.0),  # 0 the hole's foot
    (8.10, 1.22),  # 1 the inner wall's top
    (8.42, 1.53),  # 2 the inner bevel, onto the plateau (the sheet's dark band round the hole, 8.1 - 8.4)
    (9.15, 1.53),  # 3 the plateau's outer edge
    (9.30, 1.33),  # 4 the upper step's bevel, down to the ledge
    (9.50, 1.29),  # 5 the ledge
    (9.70, 0.98),  # 6 the lower step's bevel, down onto the lip: the bulge stands a third of the height proud
    (10.65, 0.88),  # 7 the lip
    (11.65, 0.76),  # 8 the lip's crease
    (12.52, 0.55),  # 9 the rim's top
    (12.62, 0.0),  # 10 the rim's foot
]
# The contour's weight at each section point, in studs (art bible: Umber 0.10 - 0.14, never under 0.1):
# heaviest at the foot, where the page is pressed, and on the edges that make the silhouette.
WEIGHTS = [0.14, 0.13, 0.13, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.13, 0.14]
BULGE = range(1, 7)  # the section points that wander a little round the ring (no perfect symmetry)
WANDER = (0.07, 0.035)  # how far they wander, in r and in h

# The lugs (the sheet's "outward-leaning notches"): radial, from INNER out past the rim to OUTER, their
# top flatter than the lip (TOP_SLOPE) so they stand proud of it more and more toward the rim and lean
# out over it (LEAN: how far the top of the outer end overhangs its foot). Half-widths of the top at
# both ends; BEVEL: how much wider each side is at the foot than at the top.
LUG_INNER = 10.30
LUG_OUTER = 12.80
LUG_RISE = 0.20  # how far the inner end stands off the lip
TOP_SLOPE = math.radians(5.0)
LEAN = 0.14
LUG_HALF = (0.21, 0.35)
BEVEL = 0.03
BURY = 0.08  # how deep the lug's foot lies in the lip
LUG_WEIGHT = 0.11

CORE_LIFT = 0.04  # the pale's lift off the lug's top (art bible: 0.03 - 0.08)
CORE_INSET = (0.025, 0.08, 0.17)  # its margin of umber: at the sides, at the inner end, at the outer end
LINE_LIFT = 0.03

# The calligraphic lines: (section segment k -> k+1, where across it, width in studs, from and to in
# degrees round the ring). Five strokes, one per radius.
LINES = [
    # One stroke per radius, each on its own arc offset 72 degrees from its neighbour's, so a radius
    # hands off to the next and never more than three overlap at any angle (bible 1 and 2.2).
    (1, 0.50, 0.36, 0.0, 205.0),  # the hole's edge: the inner bevel
    (3, 0.55, 0.15, 72.0, 262.0),  # the upper step
    (5, 0.45, 0.22, 144.0, 354.0),  # the lower step: the darker wall of the bulge
    (8, 0.10, 0.16, 216.0, 411.0),  # the lip's crease, under the lugs
    (9, 0.10, 0.16, 288.0, 488.0),  # the rim's top edge
]


def ring_point(r: float, h: float, theta: float):
    return (r * math.cos(theta), h, -r * math.sin(theta))


def lip_height(r: float) -> float:
    """The lip's height at radius r (section points 6 to 10, piecewise straight, as the facets are)."""
    pts = PROFILE[6:]
    for (r0, h0), (r1, h1) in zip(pts, pts[1:]):
        if r <= r1:
            f = (r - r0) / (r1 - r0)
            return h0 + (h1 - h0) * max(0.0, f)
    return 0.0


def wander(theta: float, seed: int) -> float:
    """-0.5 .. 0.5, periodic round the ring."""
    return fbm(3.0 + 1.6 * math.cos(theta), 3.0 + 1.6 * math.sin(theta), seed) - 0.5


def build_ring(vol: Volume) -> list[list[int]]:
    grid = []
    for k, (r, h) in enumerate(PROFILE):
        row = []
        for i in range(SEGS):
            theta = 2.0 * math.pi * i / SEGS
            rr, hh = r, h
            if k in BULGE:
                rr += WANDER[0] * wander(theta, SEED)
                hh += WANDER[1] * wander(theta + 1.3, SEED + 1)
            row.append(vol.vert(ring_point(rr, hh, theta), WEIGHTS[k]))
        grid.append(row)
    n = len(grid)
    for k in range(n):
        a, b = grid[k], grid[(k + 1) % n]  # the last band is the floor, from the rim's foot to the hole's
        for i in range(SEGS):
            j = (i + 1) % SEGS
            emit(vol.mesh, a[i], a[j], b[j])
            emit(vol.mesh, a[i], b[j], b[i])
    vol.orient_outward()
    return grid


def build_lug(theta: float, rng: Rng) -> tuple[Volume, list]:
    """One lug: a bevelled bar lying radially on the lip, three stations long (inner end, crease, outer
    end), its section a trapezoid (foot buried in the lip, narrower top), its outer end leaning out over
    the rim. Returns the volume and its top corners per station (left, right)."""
    vol = Volume()
    inner = LUG_INNER + rng.uniform(-0.12, 0.12)
    width = 1.0 + rng.uniform(-0.07, 0.07)
    rise = LUG_RISE + rng.uniform(-0.015, 0.015)
    radial = (math.cos(theta), 0.0, -math.sin(theta))
    across = (-math.sin(theta), 0.0, -math.cos(theta))
    top_inner = lip_height(inner) + rise
    stations = []
    for r_top in (inner, PROFILE[8][0], LUG_OUTER):
        f = (r_top - inner) / (LUG_OUTER - inner)
        lean = LEAN * f * f
        r_foot = r_top - lean
        half = (LUG_HALF[0] + (LUG_HALF[1] - LUG_HALF[0]) * f) * width
        top = top_inner - (r_top - inner) * math.tan(TOP_SLOPE)
        foot = min(lip_height(min(r_foot, PROFILE[9][0])), top) - BURY
        c_top = mul(radial, r_top)
        c_foot = mul(radial, r_foot)
        corners = [
            add(c_foot, add(mul(across, -(half + BEVEL)), (0.0, foot, 0.0))),
            add(c_foot, add(mul(across, half + BEVEL), (0.0, foot, 0.0))),
            add(c_top, add(mul(across, half), (0.0, top, 0.0))),
            add(c_top, add(mul(across, -half), (0.0, top, 0.0))),
        ]
        stations.append([vol.vert(c, LUG_WEIGHT) for c in corners])
    for a, b in zip(stations, stations[1:]):
        for e in range(4):
            f = (e + 1) % 4
            emit(vol.mesh, a[e], a[f], b[f])
            emit(vol.mesh, a[e], b[f], b[e])
    first, last = stations[0], stations[-1]
    emit(vol.mesh, first[0], first[2], first[1])
    emit(vol.mesh, first[0], first[3], first[2])
    emit(vol.mesh, last[0], last[1], last[2])
    emit(vol.mesh, last[0], last[2], last[3])
    vol.orient_outward()
    tops = [(vol.mesh.verts[s[3]], vol.mesh.verts[s[2]]) for s in stations]
    return vol, tops


def lug_bevel(core: Mesh, tops: list) -> None:
    """The pale bevel on a lug's top: the top face inset by a margin of umber, lifted off it."""
    (l0, r0), _, (l1, r1) = tops
    normal = norm(face_normal(l0, r0, r1))
    if normal[1] < 0:
        normal = mul(normal, -1.0)
    side, inner_end, outer_end = CORE_INSET

    def inset(left, right):
        w = math.dist(left, right)
        f = min(0.45, side / w)
        return lerp(left, right, f), lerp(left, right, 1.0 - f)

    a0, b0 = inset(l0, r0)
    a1, b1 = inset(l1, r1)
    length = math.dist(lerp(a0, b0, 0.5), lerp(a1, b1, 0.5))
    g0, g1 = inner_end / length, outer_end / length
    p0, q0 = lerp(a0, a1, g0), lerp(b0, b1, g0)
    p1, q1 = lerp(a0, a1, 1.0 - g1), lerp(b0, b1, 1.0 - g1)
    ids = [core.vert(add(p, mul(normal, CORE_LIFT))) for p in (p0, q0, q1, p1)]
    core.tri(ids[0], ids[1], ids[2], normal)
    core.tri(ids[0], ids[2], ids[3], normal)


def facet_normal(vol: Volume, grid, k: int, i: int):
    """Section segment k's outward normal at the generator of angle i. The section runs clockwise in the
    (r, h) plane (up the hole's wall, over the bulge, down the lip), so outward is its direction turned
    a quarter left: (dr, dh) -> (-dh, dr). (Deciding "outward" against one fixed point inside the band
    flipped the bulge's two steps, which face out and up from above that point: their lines lay face
    down inside the ring for five rounds.)"""
    verts = vol.mesh.verts
    a, b = verts[grid[k][i]], verts[grid[k + 1][i]]
    radial = norm((a[0], 0.0, a[2]))
    dr = math.hypot(b[0], b[2]) - math.hypot(a[0], a[2])
    dh = b[1] - a[1]
    return norm(add(mul(radial, -dh), (0.0, dr, 0.0)))


def ring_line(ink: Mesh, vol: Volume, grid, k: int, across: float, width: float, start: float, stop: float, seed: int) -> None:
    """A calligraphic line lying on section segment k, `across` of the way from point k to k + 1,
    sampled on the lathe's own generators (so it lies on the facets), pressed in and released."""
    i0 = int(round(start / 360.0 * SEGS))
    i1 = int(round(stop / 360.0 * SEGS))
    count = i1 - i0 + 1
    rng = Rng(seed)
    wobble = [rng.uniform(-0.12, 0.12) for _ in range(count)]
    lefts, rights, normals = [], [], []
    verts = vol.mesh.verts
    for m in range(count):
        i = (i0 + m) % SEGS
        a, b = verts[grid[k][i]], verts[grid[k + 1][i]]
        g = norm(sub(b, a))
        seg = math.dist(a, b)
        tau = 0.03 + 0.94 * m / (count - 1)
        w = max(pressure(tau, width, 0.2, 0.55, seed), 0.42 * width)
        f = min(max(across + wobble[m] * width / seg, w / 2 / seg), 1.0 - w / 2 / seg)
        n = facet_normal(vol, grid, k, i)
        centre = add(lerp(a, b, f), mul(n, LINE_LIFT))
        lefts.append(ink.vert(add(centre, mul(g, -w / 2))))
        rights.append(ink.vert(add(centre, mul(g, w / 2))))
        normals.append(n)
    for m in range(count - 1):
        ink.tri(lefts[m], rights[m], lefts[m + 1], normals[m])
        ink.tri(rights[m], rights[m + 1], lefts[m + 1], normals[m])


def corner_angle(p, a, b) -> float:
    u, v = sub(a, p), sub(b, p)
    lu, lv = math.sqrt(dot(u, u)), math.sqrt(dot(v, v))
    if lu < 1e-12 or lv < 1e-12:
        return 0.0
    return math.acos(max(-1.0, min(1.0, dot(u, v) / (lu * lv))))


def hull(vol: Volume, into: Mesh) -> None:
    """strokes.inverted_hull, with each vertex pushed along its ANGLE-weighted normal rather than its
    area-weighted one: on this ring the floor's quads are seven times the rim's, and area weighting
    pushed the rim's foot straight down into the floor clamp, so the contour never showed round the
    foot. A vertex on the floor is pushed out along the page (the clamp holds it over the page anyway):
    the foot of the hull draws the full contour on the page, as the bible asks. Same weights, same
    clamp, same dropped slivers, wound the other way."""
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        pa, pb, pc = mesh.verts[a], mesh.verts[b], mesh.verts[c]
        n = norm(face_normal(pa, pb, pc))
        for v, p, q, r in ((a, pa, pb, pc), (b, pb, pc, pa), (c, pc, pa, pb)):
            acc[v] = add(acc[v], mul(n, corner_angle(p, q, r)))
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        n = norm(acc[i])
        if p[1] <= 1e-6:
            flat = (n[0], 0.0, n[2])
            if dot(flat, flat) > 1e-6:
                n = norm(flat)
        q = add(p, mul(n, vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR_CLEARANCE), q[2]))
    for a, b, c in mesh.tris:
        corners = [into.verts[v + base] for v in (a, b, c)]
        if all(q[1] <= FLOOR_CLEARANCE for q in corners) and sliver(*corners):
            continue
        emit(into, a + base, c + base, b + base)


_CACHE: dict = {}


def build() -> dict[str, Mesh]:
    if _CACHE:
        return _CACHE
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    ring = Volume()
    grid = build_ring(ring)
    solids = [ring]
    rng = Rng(SEED + 7)
    for n in range(NOTCHES):
        theta = 2.0 * math.pi * n / NOTCHES + math.radians(rng.uniform(-1.2, 1.2))
        lug, tops = build_lug(theta, rng)
        solids.append(lug)
        lug_bevel(core, tops)
    lines = Mesh("up")
    for index, (k, across, width, start, stop) in enumerate(LINES):
        ring_line(lines, ring, grid, k, across, width, start, stop, SEED + 20 + index)
    # Into reference units before the hulls: their floor clearance (strokes.FLOOR_CLEARANCE, 0.004 of
    # the reference, 0.1 stud here) is a share of the reference, not studs.
    k = 1.0 / STUDS
    for vol in solids:
        vol.mesh.scale(k)
        vol.weight = [w * k for w in vol.weight]
    core.scale(k)
    lines.scale(k)
    for vol in solids:
        body.merge(vol.mesh)
        hull(vol, ink)
    ink.merge(lines)
    # One uniform scale about the floor pivot for all three: the outermost ink at exactly 0.5.
    reach = max(math.hypot(x, z) for mesh in (body, core, ink) for x, _, z in mesh.verts)
    for mesh in (body, core, ink):
        mesh.scale(0.5 / reach)
    _CACHE.update(body=body, core=core, ink=ink, reach=reach, solids=solids)
    return _CACHE


def meta(seed: int) -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def emboss_body() -> tuple[Mesh, dict]:
    """The Emboss's pigment: the ring and its sixteen lugs."""
    return build()["body"], meta(SEED)


def emboss_bevel() -> tuple[Mesh, dict]:
    """The Emboss's heated core: the pale bevel on each lug's top, the only pale of the body."""
    return build()["core"], meta(SEED + 1)


def emboss_ink() -> tuple[Mesh, dict]:
    """The Emboss's ink: the contour of the ring and of every lug, and the lines of its steps."""
    return build()["ink"], meta(SEED + 2)
