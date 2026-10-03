"""The Margin's ruled wall (Umber, three meshes: MarginBody, MarginLip, MarginInk), "le filet gras": one broad
pen stroke stood on its edge, dressing the server's slab (14 x 9 x 2.5 studs) recto and verso. Drawn
after the developer's references (docs/vfx/margin/ref-1.jpg in game, ref-2.jpg the model sheet "Umber
ink rule wall"), inside the Part's truth (DA_ENCRE_3D 4.1 and 4.2, and GlyphEffects.Margin: "what
blocks is always exactly what is drawn"): a sheath on the Part to 0.05 stud, to its ends and on both
faces, so the Part can be hidden without leaving any wall that blocks unseen.

Roblox space, built in studs and scaled once at the end: X along the wall, Y up, Z through it. The
caster stands at +Z (the server puts the slab 8 studs ahead of the root), so the thrower sees the +Z
face with the head on the right; the enemy sees the -Z face with the head on the left -- the model
sheet's back and front faces, one drawing seen from both sides.

The pigment (MarginBody), each piece closed and wound outward:
  - the slab: its faces stand 1.15 off the mid plane, so their contour (0.12) lands on 1.27 against
    the Part's 1.25; its ends are vertical rolls whose contour lands 0.04 inside the Part's ends
  - the top bead: a rolled rail along the whole length, 1.18 off the mid plane (its contour on 1.30),
    its rounded ends on +-6.88, so its contour is the outermost line, exactly +-7, and 8.94 high
  - five low bumps on the bead, one over each lobe: the lobes' tops showing over the rail, their
    contour on 9.04; their buried part has no contour weight, so nothing of it pokes out of the bead
  - the foot: a rail on the page, as long and as proud as the bead
  The slab's first and last rows are buried in the foot and the bead and push no contour either.
The sheet draws the round head and the dry tail past the slab's ends. Past the Part they would be a
drawing that does not block, and a Part shortened to make room for them would leave air that blocks:
so they are drawn ON the sheath, the head at its head end, the tail running out at its tail end, and
the face is read by its ink and its pale, the way the sheet draws it (seen face-on a crease has no
silhouette for an inverted hull to outline).
The pale (MarginLip), 0.06 off the surface it lies on: five U lobes hanging from the bead on each face, a
crown (the middle one the widest and deepest), with their ink round them; the five lobes' caps on the
bead's bumps (the sheet's top-down plan and the in-game shot); one bevel under the stroke's upper edge
where it rises into the curl; a crescent on the head's upper rim. Under the school's 6 % of the body
seen from any side.
The ink (MarginInk): the inverted hull of every piece (the contour, 0.12 stud), and on each face, lying
0.10 off it (over the pale, under the contour):
  - the outlines of what is drawn: the creases under the bead and over the foot (out onto the rolls,
    sampled on every facet of the roll so no chord sinks under it); the U round each lobe; the round
    head's crease, a ring open toward the stroke; the head end's roll edge above and below the head,
    which straddles it (the tail end stays open: the dry tail runs out of it)
  - three flow lines (six on the body, of the school's 2 to 7), each out of the head's neck: the
    stroke's upper edge, which crests, dips and rises into the one curl under the last lobe, rolls
    over and comes back under itself; the middle line, under that upper ribbon and then up along the
    dry tail's upper tongue to its tip; and the lower edge, which sags under the swell and runs out
    into the tail's other tongues and back between them to the upper one -- three tongues out of a
    broad fused root, the upper one hooking up, the middle one the shortest and straight, the lower one
    drooping and flicking up. Unequal weights, tapered, never parallel.

Units: the three meshes together span exactly 1 along X (the runtime draws that 14 studs, the slab's
Width), centred on x = 0; y = 0 is the page; nothing is under it nor past the Part by over 0.05 stud.
The pivot is the slab's centre, where the server's packet puts its Origin.
"""

from __future__ import annotations

import math

from strokes import (
    Mesh,
    Polyline,
    Volume,
    add,
    catmull,
    cosine_curve,
    emit,
    face_normal,
    fbm,
    mul,
    norm,
    sliver,
)

SEED = 6143
WIDTH, HEIGHT, THICK = 14.0, 9.0, 2.5
FLOOR = 0.06  # studs: how far over the page the contour's floor ring stays

# --- the sheath: every pigment surface set from the Part and the contour's weight -----------------
W_CONTOUR = 0.12  # the inverted hull's push (studs), within the school's 0.10 - 0.14
HZ = THICK / 2 - 0.1  # the slab's faces (1.15): their contour 0.02 proud of the Part's faces
PROUD = THICK / 2 + 0.05 - W_CONTOUR  # the bead's and the foot's (1.18): their contour on the tolerance
SLAB_END = WIDTH / 2 - W_CONTOUR - 0.04  # the slab's rolled ends: their contour 0.04 inside the Part's ends
RAIL_END = WIDTH / 2 - W_CONTOUR  # the bead's and the foot's rounded ends: their contour on the Part's ends
ROLL = 0.4  # how far in x the vertical roll of each end runs
ROLL_ANGLES = (0, 30, 60, 90)  # its facets, from the end's edge to the face
SLAB_ROWS = (0.45, 0.9, 4.3, 7.7, 8.2)  # bottom (in the foot), the face's own rows, top (in the bead)
SLAB_STATIONS = (-3.2, 0.0, 3.2)  # inner stations of the flat face: no long sliver triangles
FLAT = SLAB_END - ROLL  # the flat face runs to +-FLAT; every decal but the creases stays on it

# The bead: (y, z) round its section, its underside meeting the face at 7.85.
BEAD = ((7.85, HZ), (8.03, PROUD), (8.5, PROUD), (8.74, 0.8), (8.82, 0.0), (8.74, -0.8), (8.5, -PROUD),
        (8.03, -PROUD), (7.85, -HZ))
# Over each lobe the bead swells into a low round bump, the lobe's top showing over the rail: a pillow
# (centre height, half height, half thickness), its top at 8.92 so its contour lands on 9.04; narrow
# enough that its contour never pokes through the bead's sloping sides.
BUMP = (8.56, 0.36, 0.78)
BUMP_POLAR = (40, 80, 125)  # its rings, from the top; only the first stands over the bead
BEAD_PIVOT = (8.35, 0.0)
FOOT = ((0.0, -PROUD), (0.66, -PROUD), (0.84, -1.08), (0.95, -0.86), (0.95, 0.86), (0.84, 1.08), (0.66, PROUD),
        (0.0, PROUD))
FOOT_PIVOT = (0.47, 0.0)
RAIL_STATIONS = (-3.2, 0.0, 3.2)
RAIL_ROUND = 0.45
BEAD_CREASE, FOOT_CREASE = 7.85, 0.75

LIFT_PALE, LIFT_INK = 0.06, 0.10  # decals off the surface: the ink over the pale over the pigment
CREASE_STEP = 0.15  # studs: the creases' longest step on a roll

# --- the drawing on each face, (x, y) with the head at +x -----------------------------------------
HEAD = (4.6, 4.0, 1.7)  # centre and radius of the round head, half the face's height
NECK = 48.0  # degrees either side of the head's -x: where its ring opens wide into the stroke
ROLL_X = 6.15  # the head end's roll edge, drawn above and below the head
# The lobes: (x, half width, how far below the bead), unequal and unevenly spaced, the middle the widest.
LOBES = ((4.05, 0.5, 1.1), (2.15, 0.57, 1.22), (0.1, 0.63, 1.32), (-1.95, 0.56, 1.18), (-3.85, 0.48, 0.98))

# The three flow lines, (control points, width profile [(t, studs)]), each out of the head's neck.
# The upper edge: a crest, a dip, and the rise into the curl under the last lobe, which rolls over and
# comes back under itself, a hook that thins out inside the ribbon it rounds off.
UPPER = ([(3.46, 5.26), (2.95, 5.27), (2.2, 5.5), (1.0, 5.9), (-0.2, 5.85), (-1.3, 5.55), (-2.4, 5.65), (-3.4, 6.15),
          (-4.3, 6.75), (-5.1, 7.2), (-5.75, 7.38), (-6.18, 7.25), (-6.34, 6.92), (-6.2, 6.56), (-5.8, 6.4),
          (-5.25, 6.42), (-4.7, 6.52)],
         [(0.0, 0.16), (0.07, 0.2), (0.25, 0.28), (0.45, 0.2), (0.68, 0.26), (0.8, 0.26), (0.9, 0.2), (1.0, 0.03)])
# The middle line: under the upper ribbon, low under the crest, then up along the dry tail's upper
# tongue to its tip, which hooks up.
TIP1, TIP2, TIP3 = (-6.36, 5.92), (-5.5, 4.3), (-6.38, 3.5)
NOTCH1, NOTCH2 = (-3.6, 4.55), (-3.9, 3.7)  # where the tongues part: a broad root, fused up to there
MID = ([(3.0, 4.42), (2.0, 4.28), (0.6, 4.22), (-0.9, 4.45), (-2.2, 4.85), (-3.4, 5.28), (-4.5, 5.55),
        (-5.4, 5.6), (-6.0, 5.62), TIP1],
       [(0.0, 0.03), (0.2, 0.11), (0.5, 0.13), (0.75, 0.16), (0.9, 0.13), (1.0, 0.03)])
# The lower edge and the dry tail, one line in four brush pieces meeting at the tongues' tips (sharp:
# the pieces meet there at a hair) and notches: the lower edge sags under the swell and runs into the
# lowest tongue, which droops and flicks up; back along its top to its notch; out along the middle
# tongue, the shortest and straight; back to the upper tongue's notch, and out along its underside.
TAIL = (
    ([(3.46, 2.74), (2.95, 2.71), (2.2, 2.48), (1.0, 2.0), (-0.4, 1.7), (-1.8, 1.75), (-3.1, 2.08), (-4.2, 2.3),
      (-5.2, 2.3), (-5.9, 2.48), (-6.25, 2.95), TIP3],
     [(0.0, 0.16), (0.08, 0.2), (0.3, 0.3), (0.6, 0.27), (0.8, 0.22), (0.92, 0.14), (1.0, 0.03)]),
    ([NOTCH2, (-4.8, 3.38), (-5.6, 3.12), (-6.08, 3.15), TIP3], [(0.0, 0.08), (0.45, 0.16), (1.0, 0.03)]),
    ([NOTCH2, (-4.5, 3.9), (-5.05, 4.08), TIP2], [(0.0, 0.08), (0.45, 0.15), (1.0, 0.03)]),
    ([NOTCH1, (-4.4, 4.45), (-5.0, 4.38), TIP2], [(0.0, 0.08), (0.45, 0.15), (1.0, 0.03)]),
    ([NOTCH1, (-4.6, 4.82), (-5.5, 5.08), (-6.08, 5.38), TIP1], [(0.0, 0.08), (0.45, 0.16), (1.0, 0.03)]),
)
# The one bevel: a pale lens under the upper edge where it rises into the curl (t0, t1 along it, drop).
BEVEL = (0.55, 0.78, 0.27)

_CACHE: dict = {}


# --- construction helpers ------------------------------------------------------------------------


def _join(vol: Volume, a: list[int], b: list[int]) -> None:
    m = len(a)
    for j in range(m):
        k = (j + 1) % m
        emit(vol.mesh, a[j], a[k], b[k])
        emit(vol.mesh, a[j], b[k], b[j])


def _cap_start(vol: Volume, ring: list[int], centre: int) -> None:
    m = len(ring)
    for j in range(m):
        emit(vol.mesh, centre, ring[(j + 1) % m], ring[j])


def _cap_end(vol: Volume, ring: list[int], centre: int) -> None:
    m = len(ring)
    for j in range(m):
        emit(vol.mesh, centre, ring[j], ring[(j + 1) % m])


def _normals(mesh: Mesh) -> list:
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        n = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
    return [norm(n) for n in acc]


def _hull(vol: Volume, into: Mesh) -> None:
    """strokes.inverted_hull with the floor clearance in studs."""
    mesh = vol.mesh
    normals = _normals(mesh)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        q = add(p, mul(normals[i], vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR), q[2]))
    for a, b, c in mesh.tris:
        corners = [into.verts[v + base] for v in (a, b, c)]
        if all(q[1] <= FLOOR for q in corners) and sliver(*corners):
            continue
        if max(vol.weight[a], vol.weight[b], vol.weight[c]) <= 0.0:
            continue  # a buried face pushes no contour: it would only lie on its own pigment
        emit(into, a + base, c + base, b + base)


# --- the slab ------------------------------------------------------------------------------------


def _slab_stations() -> list[tuple[float, float]]:
    """(x, half thickness) from the tail's roll to the head's: a quarter ellipse at each end."""
    out = []
    for a in ROLL_ANGLES:
        r = math.radians(a)
        out.append((-SLAB_END + ROLL * (1.0 - math.cos(r)), HZ * math.sin(r)))
    out += [(x, HZ) for x in SLAB_STATIONS]
    for a in reversed(ROLL_ANGLES):
        r = math.radians(a)
        out.append((SLAB_END - ROLL * (1.0 - math.cos(r)), HZ * math.sin(r)))
    return out


def _half(x: float) -> float:
    """The slab's half thickness at x, on its own facets (piecewise linear between stations), so a
    decal laid with it lies on the mesh and never sinks under a chord."""
    st = _slab_stations()
    if x <= st[0][0] or x >= st[-1][0]:
        return 0.0
    for (x0, z0), (x1, z1) in zip(st, st[1:]):
        if x0 <= x <= x1:
            return z0 + (z1 - z0) * (x - x0) / max(x1 - x0, 1e-9)
    return HZ


def _slab() -> Volume:
    """The sheath: a loft along X through the stations, its rows buried in the foot and the bead."""
    vol = Volume()
    rings = []
    # The first and last rows are buried in the foot and the bead: no contour weight, or the hull's
    # bottom and top plates would stand 0.09 past the rails' sides, a hairline along each.
    weights = [0.0] + [W_CONTOUR] * (len(SLAB_ROWS) - 2) + [0.0]
    for x, z in _slab_stations():
        if z <= 1e-9:
            edge = [vol.vert((x, y, 0.0), w) for y, w in zip(SLAB_ROWS, weights)]
            rings.append(edge + list(reversed(edge)))
            continue
        back = [vol.vert((x, y, z), w) for y, w in zip(SLAB_ROWS, weights)]
        front = [vol.vert((x, y, -z), w) for y, w in reversed(list(zip(SLAB_ROWS, weights)))]
        rings.append(back + front)
    for a, b in zip(rings, rings[1:]):
        _join(vol, a, b)
    vol.orient_outward()
    return vol


# --- the bead, its bumps and the foot ------------------------------------------------------------


def _rail(section, pivot, weight) -> Volume:
    """A rail along X with rounded ends: `section` is a closed loop of (y, z); over RAIL_ROUND at each
    end it shrinks toward `pivot` (y, z) on a quarter circle, to a tip vertex on +-RAIL_END."""
    vol = Volume()
    x0, x1, end = -RAIL_END, RAIL_END, RAIL_ROUND
    xs = []
    # The collapsed ring at 90 degrees is the tip vertex itself: a ring of coincident copies would
    # leave its edges unpaired and crack the contour there.
    for a in (66, 32):
        r = math.radians(a)
        xs.append((x0 + end - end * math.sin(r), math.cos(r)))
    xs += [(x0 + end, 1.0)] + [(x, 1.0) for x in RAIL_STATIONS] + [(x1 - end, 1.0)]
    for a in (32, 66):
        r = math.radians(a)
        xs.append((x1 - end + end * math.sin(r), math.cos(r)))
    tip0 = vol.vert((x0, pivot[0], pivot[1]), weight)
    rings = []
    for x, s in xs:
        rings.append([vol.vert((x, pivot[0] + (y - pivot[0]) * s, pivot[1] + (z - pivot[1]) * s), weight) for y, z in section])
    tip1 = vol.vert((x1, pivot[0], pivot[1]), weight)
    _cap_start(vol, rings[0], tip0)
    for a, b in zip(rings, rings[1:]):
        _join(vol, a, b)
    _cap_end(vol, rings[-1], tip1)
    vol.orient_outward()
    return vol


def _bead() -> Volume:
    return _rail(BEAD, BEAD_PIVOT, W_CONTOUR)


def _bump(cx: float, a: float) -> Volume:
    """A lobe's top showing over the bead: a low pillow, its pole up, six-sided. Only its top and its
    first ring stand over the bead; the rest is buried and pushes no contour, so the hull never pokes
    out through the bead's top beside it."""
    vol = Volume()
    yc, ry, rz = BUMP
    rx = 0.95 * a
    top = vol.vert((cx, yc + ry, 0.0), W_CONTOUR)
    bottom = vol.vert((cx, yc - ry, 0.0), 0.0)
    rings = []
    for polar in BUMP_POLAR:
        p = math.radians(polar)
        weight = W_CONTOUR if polar == BUMP_POLAR[0] else 0.0
        rings.append([vol.vert((cx + rx * math.sin(p) * math.cos(2 * math.pi * k / 6 + math.pi / 6), yc + ry * math.cos(p),
                                rz * math.sin(p) * math.sin(2 * math.pi * k / 6 + math.pi / 6)), weight) for k in range(6)])
    _cap_start(vol, rings[0], top)
    for r0, r1 in zip(rings, rings[1:]):
        _join(vol, r0, r1)
    _cap_end(vol, rings[-1], bottom)
    vol.orient_outward()
    return vol


def _foot() -> Volume:
    return _rail(FOOT, FOOT_PIVOT, W_CONTOUR)


# --- the drawing on the faces --------------------------------------------------------------------


def _on_face(side: int, x: float, y: float, lift: float):
    """A point on one face (side -1 the enemy's, +1 the thrower's) lifted along its normal, and the normal."""
    e = 0.01
    slope = (_half(x + e) - _half(x - e)) / (2 * e)
    n = norm((-slope, 0.0, float(side)))
    return add((x, y, side * _half(x)), mul(n, lift)), n


def _brush(mesh: Mesh, side: int, path: Polyline, profile, taus: list[float], lift: float, seed: int) -> None:
    """A calligraphic line lying on one face: its width follows `profile` [(t, studs)] with the hand's
    small unevenness, measured as the face is seen head-on, and every vertex rides `lift` off the face
    along the face's own normal there."""
    centre = [path.at(t) for t in taus]
    lefts, rights = [], []
    for i, tau in enumerate(taus):
        (ax, ay), (bx, by) = centre[max(i - 1, 0)], centre[min(i + 1, len(taus) - 1)]
        length = math.hypot(bx - ax, by - ay) or 1.0
        nx, ny = -(by - ay) / length, (bx - ax) / length
        w = cosine_curve(profile, tau) * (1.0 + 0.1 * (fbm(5.0 * tau, 0.5, seed) * 2.0 - 1.0)) / 2.0
        x, y = centre[i]
        lefts.append(mesh.vert(_on_face(side, x + nx * w, y + ny * w, lift)[0]))
        rights.append(mesh.vert(_on_face(side, x - nx * w, y - ny * w, lift)[0]))
    facing = (0.0, 0.0, float(side))
    for i in range(len(taus) - 1):
        mesh.tri(lefts[i], rights[i], lefts[i + 1], facing)
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1], facing)


def _even(count: int) -> list[float]:
    return [i / (count - 1) for i in range(count)]


def _line(points, per: int = 8) -> Polyline:
    return Polyline(catmull(points, per))


def _fan(mesh: Mesh, side: int, outline: list[tuple[float, float]], centre: tuple[float, float], lift: float) -> None:
    """A flat shape lying on a face: a fan from `centre` through the closed `outline` (x, y)."""
    c = mesh.vert(_on_face(side, centre[0], centre[1], lift)[0])
    ids = [mesh.vert(_on_face(side, x, y, lift)[0]) for x, y in outline]
    facing = (0.0, 0.0, float(side))
    for k in range(len(ids)):
        mesh.tri(c, ids[k], ids[(k + 1) % len(ids)], facing)


def _lobe_outline(spec, top: float, steps: int = 6) -> list[tuple[float, float]]:
    """A lobe's U, as the sheet draws it: from `top` down its sides, round at the bottom, back up."""
    cx, a, depth = spec
    cy = BEAD_CREASE - 0.02 - depth + a * 0.95
    pts = [(cx - a, top), (cx - 0.98 * a, 0.5 * (top + cy))]
    for k in range(steps + 1):
        t = math.pi + math.pi * k / steps
        pts.append((cx + 0.98 * a * math.cos(t), cy + 0.95 * a * math.sin(t)))
    pts += [(cx + 0.98 * a, 0.5 * (top + cy)), (cx + a, top)]
    return pts


def _lobes(core: Mesh, ink: Mesh) -> None:
    """Each lobe on both faces: its pale U, and its ink round it, heaviest at the bottom, up to the
    bead. The pale stops 0.1 under the bead, well inside the crease's ink, so seen steeply from above
    the ink that floats over it never lets its top edge peek out."""
    for i, spec in enumerate(LOBES):
        u = _lobe_outline(spec, BEAD_CREASE - 0.02)
        cx, a, depth = spec
        for side in (-1, 1):
            _fan(core, side, _lobe_outline(spec, BEAD_CREASE - 0.1), (cx, BEAD_CREASE - 0.45 * depth), LIFT_PALE)
            _brush(ink, side, Polyline(u), [(0.0, 0.07), (0.25, 0.12), (0.5, 0.17), (0.75, 0.12), (1.0, 0.07)],
                   _even(len(u)), LIFT_INK, SEED + 20 + 2 * i + side)


def _caps(core: Mesh) -> None:
    """The lobes' caps on the bead: a pale hexagon on each bump's top, a part of the way down its fan,
    lifted along the bump's own normals, with the bump's pigment all round it."""
    for cx, a, _depth in LOBES:
        vol = _bump(cx, a)
        normals = _normals(vol.mesh)
        top, ring = 0, list(range(2, 8))  # the bump's top vertex and its first ring
        pole = vol.mesh.verts[top]
        c = core.vert(add(pole, mul(normals[top], LIFT_PALE)))
        ids = []
        for v in ring:
            p = add(pole, mul(add(vol.mesh.verts[v], mul(pole, -1.0)), 0.85))
            n = norm(add(normals[top], normals[v]))
            ids.append(core.vert(add(p, mul(n, LIFT_PALE))))
        for k in range(len(ids)):
            core.tri(c, ids[k], ids[(k + 1) % len(ids)], (0.0, 1.0, 0.0))


def _crease_taus(path: Polyline) -> list[float]:
    """Steps along a straight crease (x from - to +): the flat face's stations, every facet edge of the
    rolls, and no step over CREASE_STEP on a roll, so each chord lies on one facet."""
    x0, x1 = path.p[0][0], path.p[-1][0]
    xs = {x0, x1}
    stations = [x for x, _z in _slab_stations()]
    xs.update(x for x in stations if x0 < x < x1)
    for a, b in zip(stations, stations[1:]):
        lo, hi = max(a, x0), min(b, x1)
        if hi <= lo or min(abs(a), abs(b)) < FLAT - 1e-6:
            continue  # a span of the flat face: one chord is the face itself
        n = math.ceil((hi - lo) / CREASE_STEP - 1e-9)
        xs.update(lo + (hi - lo) * k / n for k in range(1, n))
    return [(x - x0) / (x1 - x0) for x in sorted(xs)]


def _creases(ink: Mesh) -> None:
    """Under the bead and over the foot, both faces, out onto the rolls."""
    span = SLAB_END - 0.3
    for side in (-1, 1):
        bead = Polyline([(-span, BEAD_CREASE - 0.08), (span, BEAD_CREASE - 0.08)])
        _brush(ink, side, bead, [(0.0, 0.07), (0.008, 0.14), (0.5, 0.17), (0.992, 0.15), (1.0, 0.07)], _crease_taus(bead),
               LIFT_INK, SEED + 3 + side)
        foot = Polyline([(-span, FOOT_CREASE + 0.08), (span, FOOT_CREASE + 0.08)])
        _brush(ink, side, foot, [(0.0, 0.08), (0.008, 0.16), (0.5, 0.2), (0.992, 0.18), (1.0, 0.08)], _crease_taus(foot),
               LIFT_INK, SEED + 5 + side)


def _head(core: Mesh, ink: Mesh) -> None:
    """The round head: a crease ring open toward the stroke (its neck), light at its top and heavy round
    its outer and lower side, its two ends running on into the stroke's upper and lower edges; a pale
    crescent on its upper rim."""
    hx, hy, r = HEAD
    start, sweep = 180.0 - NECK, 360.0 - 2 * NECK
    ring = [(hx + r * math.cos(math.radians(start - sweep * k / 16)), hy + r * math.sin(math.radians(start - sweep * k / 16)))
            for k in range(17)]
    crescent = [(hx + 0.8 * r * math.cos(math.radians(a)), hy + 0.8 * r * math.sin(math.radians(a))) for a in (138, 115, 90, 66, 45)]
    for side in (-1, 1):
        _brush(ink, side, _line(ring), [(0.0, 0.16), (0.2, 0.16), (0.5, 0.25), (0.75, 0.27), (1.0, 0.16)], _even(30),
               LIFT_INK, SEED + 30 + side)
        _brush(core, side, _line(crescent), [(0.0, 0.04), (0.5, 0.17), (1.0, 0.04)], _even(9), LIFT_PALE, SEED + 32 + side)


def _rolls(ink: Mesh) -> None:
    """The head end's roll edge on both faces, above and below the head, which straddles it. The tail
    end has none: the dry tail runs out of it, open."""
    hx, hy, r = HEAD
    reach = math.sqrt(r * r - (ROLL_X - hx) ** 2)
    for side in (-1, 1):
        top = Polyline([(ROLL_X, BEAD_CREASE - 0.1), (ROLL_X + 0.02, hy + reach)])
        _brush(ink, side, top, [(0.0, 0.13), (1.0, 0.09)], _even(4), LIFT_INK, SEED + 34 + side)
        bottom = Polyline([(ROLL_X + 0.02, hy - reach), (ROLL_X, FOOT_CREASE + 0.1)])
        _brush(ink, side, bottom, [(0.0, 0.09), (1.0, 0.14)], _even(4), LIFT_INK, SEED + 36 + side)


def _stroke(core: Mesh, ink: Mesh) -> None:
    """The full stroke and its dry tail, on both faces: three flow lines out of the head's neck."""
    upper = _line(UPPER[0])
    for side in (-1, 1):
        _brush(ink, side, upper, UPPER[1], _even(34), LIFT_INK, SEED + 40 + side)
        _brush(ink, side, _line(MID[0]), MID[1], _even(22), LIFT_INK, SEED + 43 + side)
        for k, (points, profile) in enumerate(TAIL):
            count = 30 if k == 0 else 9
            _brush(ink, side, _line(points), profile, _even(count), LIFT_INK, SEED + 50 + 3 * k + side)
        t0, t1, drop = BEVEL
        bevel = [(x, y - drop) for x, y in (upper.at(t0 + (t1 - t0) * i / 4) for i in range(5))]
        _brush(core, side, _line(bevel), [(0.0, 0.04), (0.4, 0.14), (1.0, 0.04)], _even(10), LIFT_PALE, SEED + 70 + side)


# --- the three meshes ----------------------------------------------------------------------------


def solids() -> list[tuple[str, Volume]]:
    return [("slab", _slab()), ("bead", _bead()), ("foot", _foot())] + [(f"bump{i}", _bump(cx, a)) for i, (cx, a, _d) in enumerate(LOBES)]


def build() -> tuple[Mesh, Mesh, Mesh]:
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for _name, vol in solids():
        body.merge(vol.mesh)
        _hull(vol, ink)
    _creases(ink)
    _lobes(core, ink)
    _caps(core)
    _head(core, ink)
    _rolls(ink)
    _stroke(core, ink)
    xs = [v[0] for mesh in (body, core, ink) for v in mesh.verts]
    factor, shift = 1.0 / (max(xs) - min(xs)), -(max(xs) + min(xs)) / 2.0
    for mesh in (body, core, ink):
        mesh.verts = [((x + shift) * factor, y * factor, z * factor) for x, y, z in mesh.verts]
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta(seed: int) -> dict:
    return {"Reference": "Width", "Pivot": [0, round(HEIGHT / 2 / WIDTH, 6), 0], "Axis": "Y", "Flat": False, "Seed": seed}


def rule_body() -> tuple[Mesh, dict]:
    """The Margin's pigment: the slab sheathing the server's Part, the rolled bead along its top with a
    bump over each lobe, and the foot on the page. Closed and wound outward."""
    return build()[0], meta(SEED)


def rule_lip() -> tuple[Mesh, dict]:
    """The Margin's pale: the five U lobes under the bead and their caps on it, the bevel under the
    stroke's upper edge, the head's crescent."""
    return build()[1], meta(SEED + 1)


def rule_ink() -> tuple[Mesh, dict]:
    """The Margin's ink: every piece's contour, and the drawing lying on both faces."""
    return build()[2], meta(SEED + 2)
