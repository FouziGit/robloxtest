"""The Margin's ruled wall (Umber, three meshes: MarginBody, MarginLip, MarginInk), "le filet gras": one
giant calligraphic brush stroke stood on its edge, as the developer's references draw it
(docs/vfx/margin/ref-1.jpg in game, ref-2.jpg the model sheet "Umber ink rule wall"): a round rolled head
where the brush landed, a full stroke that swells along the wall, a dry tail that splits into three
bristle strands where it ran out, a rolled bead along its top with five pale lobes sitting in it, and
both faces finished, swept by darker ink streaks from the head toward the tail.

Roblox space, built in studs and scaled once at the end: X along the wall, Y up, Z through it. The
caster stands at +Z (the server puts the slab 8 studs ahead of the root), so the thrower sees the +Z
face with the head on the right; the enemy sees the -Z face with the head on the left -- the model
sheet's back and front faces, one drawing seen from both sides.

Inside the Part's truth (DA_ENCRE_3D 4.1 and 4.2, GlyphEffects.Margin): the whole drawing spans the
server's slab, 14 x 9 x 2.5, and its outermost lines lie on the Part to 0.05 stud -- the head's end and
the tail's tips on its ends, the head's dome on its top, the head on its faces. What the stroke gives
up to look like one is on the safe side: the faces swell inside the Part (their contour 0.3 to 0.7
under its faces, so the head and the bead stand proud of them), and the air between the tail's strands
and under its rising lower edge is slab that still blocks. Nothing drawn stands where nothing blocks.

The pigment (MarginBody), each piece closed and wound outward:
  - the head: a vertical roll the full height, an ellipse in plan (1.3 along the wall, 1.18 through it),
    a barrel that swells at mid height so its end reads round from the front, domed on top, the tallest
    thing on the wall
  - the stroke: a loft from inside the head to the tail's root, its section a lens (fullest at mid
    height, drawn in at the top and on the page); past x = -1.8 its lower edge sweeps up and the upper
    edge comes down, and it thins, into the strands' fused root
  - the bead: a rolled rail along the top, out of the head's dome to its rounded end over the tail
  - the dry tail: three bristle strands out of the stroke's root, broad and fused there, flattened
    through the wall -- the upper one hooking up, the middle one the shortest and straight, the lower
    one drooping and flicking up
The pale (MarginLip): the five lobes, closed pillows sitting in the bead (their buried half pushes no
contour), the largest by the head and the smallest by the tail; and on each face, the U of each lobe
hanging from the bead.
The ink (MarginInk): the inverted hull of every piece (the contour, 0.12 stud; thinner toward the
strands' tips), and on each face, lying 0.10 off it: the crease under the bead, the head's crease where
the roll meets the face (bowed, the roll's edge, and lifting before the bead so the two never close into
a frame), the U round each lobe, and four streaks that fall from the bead between the lobes and sweep
along the face into the tail's strands.

Units: the three meshes together span exactly 1 along X (the runtime draws that 14 studs, the slab's
Width), centred on x = 0; y = 0 is the page. The pivot is the slab's centre, where the server's packet
puts its Origin.
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
W_CONTOUR = 0.12  # the inverted hull's push (studs), within the school's 0.10 - 0.14
PROUD = THICK / 2 + 0.05 - W_CONTOUR  # 1.18: the head's flanks, their contour on the tolerance
RAIL_Z = 1.12  # the bead's flanks: the head stays the fattest thing on the wall
TOP = HEIGHT - W_CONTOUR  # 8.88: the head's dome, the tallest thing on the wall, its contour on 9

# --- the head: (y, half length along X, half thickness) rings, bottom to dome ---------------------
HEAD_RX = 1.3
HEAD_X = WIDTH / 2 - W_CONTOUR - HEAD_RX  # its end's contour on the Part's end
HEAD_RINGS = ((0.0, 0.8, PROUD), (1.2, 1.1, PROUD), (4.2, HEAD_RX, PROUD), (7.0, 1.1, PROUD), (8.25, 0.88, 1.08),
              (8.62, 0.66, 0.8), (8.83, 0.34, 0.4))
HEAD_BOW = 0.6  # how far the head's crease bows into the face at mid height: the roll's edge, "("
HEAD_AROUND = 12

# --- the stroke: its lens section and its stations, head (inside it) to the tail's root ----------
SLAB_U = (0.0, 0.06, 0.25, 0.5, 0.75, 0.94, 1.0)  # rows, as a fraction of the section's height
SLAB_Z = (0.55, 0.86, 0.97, 1.0, 0.97, 0.88, 0.55)  # their half thickness, as a fraction of its fullest
EDGE_ROUND = 0.12  # the top and bottom edges' centre, past the last rows
# (x, bottom, top, fullest half thickness)
SLAB = ((HEAD_X, 0.2, 7.95, 0.84), (2.6, 0.2, 7.95, 0.84), (-0.2, 0.2, 7.95, 0.82), (-1.8, 0.2, 7.95, 0.8),
        (-2.8, 0.75, 7.9, 0.76), (-3.5, 1.9, 7.75, 0.6), (-4.0, 2.9, 7.4, 0.35))

# --- the bead: (y, z) round its section, its underside buried in the stroke ----------------------
BEAD = ((7.45, 0.6), (7.62, 1.0), (7.78, RAIL_Z), (8.02, RAIL_Z), (8.2, 0.9), (8.28, 0.45), (8.3, 0.0),
        (8.28, -0.45), (8.2, -0.9), (8.02, -RAIL_Z), (7.78, -RAIL_Z), (7.62, -1.0), (7.45, -0.6))
BEAD_BURIED = (0, 12)  # its underside's two corners, inside the stroke: no contour weight
BEAD_PIVOT = (7.88, 0.0)
BEAD_SPAN = (-4.7, 0.5, HEAD_X, 1.2)  # tail end, its rounding, head end, its rounding (into the dome)
RAIL_STATIONS = (-2.0, 0.6, 3.0)  # inner stations: no long sliver triangles
BEAD_CREASE = 7.35

# --- the dry tail: (control points (x, y), root half height, root half thickness) -----------------
STRANDS = (
    ([(-2.9, 7.0), (-4.2, 7.15), (-5.3, 7.3), (-6.1, 7.55), (-6.65, 7.95), (-6.98, 8.45)], 0.9, 0.5),
    ([(-2.9, 5.5), (-4.3, 5.6), (-5.5, 5.55), (-6.6, 5.7)], 0.9, 0.48),
    ([(-2.9, 3.9), (-4.2, 3.75), (-5.2, 3.4), (-6.0, 3.25), (-6.6, 3.5), (-6.98, 4.0)], 0.9, 0.5),
)
STRAND_RINGS = (0.0, 0.12, 0.26, 0.4, 0.54, 0.67, 0.79, 0.9)  # along each, before its tip vertex
STRAND_AROUND = 6

# --- the lobes: (x, half length), the largest by the head -----------------------------------------
LOBES = ((3.65, 0.85), (1.75, 0.8), (-0.1, 0.75), (-1.85, 0.68), (-3.45, 0.6))
LOBE_Y, LOBE_TOP, LOBE_RZ = 8.1, 8.7, 0.85  # its centre, in the bead; its top, under the head's; its half thickness
LOBE_POLAR = (48, 90, 132)  # its rings, from the top; only the first stands over the bead
LOBE_AROUND = 8
LOBE_DEPTH = (0.6, 0.5)  # how far each U hangs under the bead's crease: a base and so much per stud of half length

LIFT_PALE, LIFT_INK = 0.06, 0.10  # decals off the surface: the ink over the pale over the pigment

# --- the streaks: (control points (x, y), width profile [(t, studs)]), each from the bead between two
# lobes, falling and sweeping along the face into a strand's root, never parallel -------------------
STREAKS = (
    ([(4.55, 7.2), (4.3, 6.2), (3.5, 4.9), (2.2, 4.1), (0.6, 3.9), (-1.0, 3.5), (-2.4, 3.6), (-3.6, 4.2), (-4.6, 4.5)],
     [(0.0, 0.06), (0.12, 0.2), (0.4, 0.27), (0.75, 0.2), (1.0, 0.04)]),
    ([(2.68, 7.2), (2.5, 6.4), (1.7, 5.6), (0.3, 5.3), (-1.2, 4.9), (-2.7, 5.1), (-4.4, 5.75)],
     [(0.0, 0.05), (0.15, 0.16), (0.5, 0.21), (0.8, 0.14), (1.0, 0.04)]),
    ([(0.8, 7.2), (0.6, 6.7), (-0.2, 6.25), (-1.6, 6.15), (-3.0, 6.05), (-4.3, 6.4)],
     [(0.0, 0.05), (0.2, 0.13), (0.55, 0.16), (1.0, 0.04)]),
    ([(-1.0, 7.2), (-1.1, 6.9), (-1.5, 6.6)], [(0.0, 0.04), (0.4, 0.1), (1.0, 0.03)]),
)
STREAK_SAMPLES = (20, 16, 14, 6)

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


def _lerp_table(table, x: float, key: int = 0) -> tuple:
    """A row of `table` interpolated at x along its column `key` (either order), clamped to its ends."""
    rows = sorted(table, key=lambda r: r[key])
    if x <= rows[0][key]:
        return rows[0]
    for r0, r1 in zip(rows, rows[1:]):
        if x <= r1[key]:
            f = (x - r0[key]) / max(r1[key] - r0[key], 1e-9)
            return tuple(a + (b - a) * f for a, b in zip(r0, r1))
    return rows[-1]


# --- the head ------------------------------------------------------------------------------------


def _head() -> Volume:
    vol = Volume()
    angles = [2 * math.pi * k / HEAD_AROUND for k in range(HEAD_AROUND)]
    rings = [[vol.vert((HEAD_X + rx * math.cos(a), y, rz * math.sin(a)), W_CONTOUR) for a in angles]
             for y, rx, rz in HEAD_RINGS]
    bottom = vol.vert((HEAD_X, 0.0, 0.0), W_CONTOUR)
    top = vol.vert((HEAD_X, TOP, 0.0), W_CONTOUR)
    _cap_start(vol, rings[0], bottom)
    for a, b in zip(rings, rings[1:]):
        _join(vol, a, b)
    _cap_end(vol, rings[-1], top)
    vol.orient_outward()
    return vol


def _head_junction(y: float) -> float:
    """Where the head's flank meets the stroke's face at height y (x), the face side of the head."""
    _y, rx, rz = _lerp_table(HEAD_RINGS[:5], y)
    zf = _face_z(HEAD_X - 0.6, y)
    return HEAD_X - rx * math.sqrt(max(0.0, 1.0 - (zf / rz) ** 2))


# --- the stroke ----------------------------------------------------------------------------------


def _station(x: float) -> tuple[float, float, float]:
    _x, bottom, top, full = _lerp_table(SLAB, x)
    return bottom, top, full


def _face_z(x: float, y: float) -> float:
    """The stroke's half thickness at (x, y), on its own facets (linear between rows and stations), so a
    decal laid on it lies on the mesh."""
    bottom, top, full = _station(x)
    u = (y - bottom) / max(top - bottom, 1e-9)
    return full * _lerp_table(list(zip(SLAB_U, SLAB_Z)), min(max(u, 0.0), 1.0))[1]


def _slab() -> Volume:
    vol = Volume()
    rings = []
    for x, bottom, top, full in SLAB:
        rows = [(bottom + u * (top - bottom), full * z) for u, z in zip(SLAB_U, SLAB_Z)]
        ring = [vol.vert((x, bottom - EDGE_ROUND, 0.0), W_CONTOUR)]
        ring += [vol.vert((x, y, z), W_CONTOUR) for y, z in rows]
        ring.append(vol.vert((x, top + EDGE_ROUND, 0.0), W_CONTOUR))
        ring += [vol.vert((x, y, -z), W_CONTOUR) for y, z in reversed(rows)]
        rings.append(ring)
    head = vol.vert((SLAB[0][0], 0.5 * (SLAB[0][1] + SLAB[0][2]), 0.0), W_CONTOUR)
    tail = vol.vert((SLAB[-1][0], 0.5 * (SLAB[-1][1] + SLAB[-1][2]), 0.0), W_CONTOUR)
    _cap_start(vol, rings[0], head)
    for a, b in zip(rings, rings[1:]):
        _join(vol, a, b)
    _cap_end(vol, rings[-1], tail)
    vol.orient_outward()
    return vol


# --- the bead's rail -----------------------------------------------------------------------------


def _rail(section, pivot, span, buried=()) -> Volume:
    """A rail along X with rounded ends: `section` is a closed loop of (y, z); at each end it shrinks
    toward `pivot` (y, z) on a quarter circle, over that end's rounding, to a tip vertex."""
    vol = Volume()
    x0, round0, x1, round1 = span
    xs = []
    # The collapsed ring at 90 degrees is the tip vertex itself: a ring of coincident copies would
    # leave its edges unpaired and crack the contour there.
    for a in (66, 32):
        r = math.radians(a)
        xs.append((x0 + round0 - round0 * math.sin(r), math.cos(r)))
    xs += [(x0 + round0, 1.0)] + [(x, 1.0) for x in RAIL_STATIONS] + [(x1 - round1, 1.0)]
    for a in (32, 66):
        r = math.radians(a)
        xs.append((x1 - round1 + round1 * math.sin(r), math.cos(r)))
    weights = [0.0 if i in buried else W_CONTOUR for i in range(len(section))]
    tip0 = vol.vert((x0, pivot[0], pivot[1]), W_CONTOUR)
    rings = []
    for x, s in xs:
        rings.append([vol.vert((x, pivot[0] + (y - pivot[0]) * s, pivot[1] + (z - pivot[1]) * s), w)
                      for (y, z), w in zip(section, weights)])
    tip1 = vol.vert((x1, pivot[0], pivot[1]), W_CONTOUR)
    _cap_start(vol, rings[0], tip0)
    for a, b in zip(rings, rings[1:]):
        _join(vol, a, b)
    _cap_end(vol, rings[-1], tip1)
    vol.orient_outward()
    return vol


# --- the dry tail --------------------------------------------------------------------------------


def _strand(points, root_y: float, root_z: float) -> Volume:
    """A bristle strand in the wall's plane: a hexagonal section, broad in Y and flattened through the
    wall, tapering to a tip vertex. Its first two rings are buried in the stroke's root and push no
    contour; its contour thins toward the tip, the brush lifting."""
    vol = Volume()
    line = Polyline(catmull(points, 12))
    rings = []
    for i, t in enumerate(STRAND_RINGS):
        (ax, ay), (bx, by) = line.at(max(t - 0.03, 0.0)), line.at(t + 0.03)
        length = math.hypot(bx - ax, by - ay) or 1.0
        nx, ny = -(by - ay) / length, (bx - ax) / length
        cx, cy = line.at(t)
        ry, rz = root_y * (1.0 - t) ** 0.8, root_z * (1.0 - t) ** 0.6
        weight = 0.0 if i < 2 else 0.04 + 0.08 * (1.0 - t) ** 0.5
        ring = []
        for k in range(STRAND_AROUND):
            a = 2 * math.pi * k / STRAND_AROUND
            ring.append(vol.vert((cx + nx * ry * math.cos(a), cy + ny * ry * math.cos(a), rz * math.sin(a)), weight))
        rings.append(ring)
    (rx, ry0) = line.at(0.0)
    root = vol.vert((rx, ry0, 0.0), 0.0)
    tip = vol.vert((*line.at(1.0), 0.0), 0.03)
    _cap_start(vol, rings[0], root)
    for a, b in zip(rings, rings[1:]):
        _join(vol, a, b)
    _cap_end(vol, rings[-1], tip)
    vol.orient_outward()
    return vol


# --- the lobes -----------------------------------------------------------------------------------


def _lobe(cx: float, a: float) -> Volume:
    """A pale pillow sitting in the bead: only its top and its first ring stand over the bead; the rest
    is buried and pushes no contour, so its hull is the ring where it sits in the bead."""
    vol = Volume()
    ry = LOBE_TOP - LOBE_Y
    top = vol.vert((cx, LOBE_TOP, 0.0), W_CONTOUR)
    bottom = vol.vert((cx, LOBE_Y - ry, 0.0), 0.0)
    rings = []
    for polar in LOBE_POLAR:
        p = math.radians(polar)
        weight = W_CONTOUR if polar == LOBE_POLAR[0] else 0.0
        rings.append([vol.vert((cx + a * math.sin(p) * math.cos(2 * math.pi * k / LOBE_AROUND), LOBE_Y + ry * math.cos(p),
                                LOBE_RZ * math.sin(p) * math.sin(2 * math.pi * k / LOBE_AROUND)), weight)
                      for k in range(LOBE_AROUND)])
    _cap_start(vol, rings[0], top)
    for r0, r1 in zip(rings, rings[1:]):
        _join(vol, r0, r1)
    _cap_end(vol, rings[-1], bottom)
    vol.orient_outward()
    return vol


# --- the drawing on the faces --------------------------------------------------------------------


def _on_face(side: int, x: float, y: float, lift: float):
    """A point on one face (side -1 the enemy's, +1 the thrower's), lifted off it."""
    return (x, y, side * (_face_z(x, y) + lift))


def _brush(mesh: Mesh, side: int, path: Polyline, profile, taus: list[float], lift: float, seed: int) -> None:
    """A calligraphic line lying on one face: its width follows `profile` [(t, studs)] with the hand's
    small unevenness, measured as the face is seen head-on."""
    centre = [path.at(t) for t in taus]
    lefts, rights = [], []
    for i, tau in enumerate(taus):
        (ax, ay), (bx, by) = centre[max(i - 1, 0)], centre[min(i + 1, len(taus) - 1)]
        length = math.hypot(bx - ax, by - ay) or 1.0
        nx, ny = -(by - ay) / length, (bx - ax) / length
        w = cosine_curve(profile, tau) * (1.0 + 0.1 * (fbm(5.0 * tau, 0.5, seed) * 2.0 - 1.0)) / 2.0
        x, y = centre[i]
        lefts.append(mesh.vert(_on_face(side, x + nx * w, y + ny * w, lift)))
        rights.append(mesh.vert(_on_face(side, x - nx * w, y - ny * w, lift)))
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
    c = mesh.vert(_on_face(side, centre[0], centre[1], lift))
    ids = [mesh.vert(_on_face(side, x, y, lift)) for x, y in outline]
    facing = (0.0, 0.0, float(side))
    for k in range(len(ids)):
        mesh.tri(c, ids[k], ids[(k + 1) % len(ids)], facing)


def _lobe_outline(cx: float, a: float, top: float, steps: int = 6) -> list[tuple[float, float]]:
    """A lobe's U, as the sheet draws it: from `top` down its sides, round at the bottom, back up."""
    w = 0.85 * a
    cy = BEAD_CREASE - (LOBE_DEPTH[0] + LOBE_DEPTH[1] * a) + w
    pts = [(cx - w, top), (cx - 0.98 * w, 0.5 * (top + cy))]
    for k in range(steps + 1):
        t = math.pi + math.pi * k / steps
        pts.append((cx + 0.98 * w * math.cos(t), cy + w * math.sin(t)))
    pts += [(cx + 0.98 * w, 0.5 * (top + cy)), (cx + w, top)]
    return pts


def _lobes(core: Mesh, ink: Mesh) -> None:
    """Each lobe's U on both faces, hanging from the bead: its pale, and its ink round it, heaviest at
    the bottom."""
    for i, (cx, a) in enumerate(LOBES):
        u = _lobe_outline(cx, a, BEAD_CREASE + 0.02)
        for side in (-1, 1):
            _fan(core, side, _lobe_outline(cx, a, BEAD_CREASE), (cx, BEAD_CREASE - 0.4 * a), LIFT_PALE)
            _brush(ink, side, Polyline(u), [(0.0, 0.07), (0.25, 0.12), (0.5, 0.17), (0.75, 0.12), (1.0, 0.07)],
                   _even(len(u)), LIFT_INK, SEED + 20 + 2 * i + side)


def _creases(ink: Mesh) -> None:
    """Under the bead from the head, and the head's crease where the roll meets the face: heaviest at the
    page, lifting before it reaches the bead, so the two never close into a frame."""
    bead_end = BEAD_SPAN[0] + BEAD_SPAN[1] + 0.3
    head_ys = (0.35, 1.4, 2.8, 4.2, 5.6, 6.5, 6.95)
    for side in (-1, 1):
        xs = [_head_junction(BEAD_CREASE) - 0.1] + [x for x, *_r in SLAB[1:] if x > bead_end] + [bead_end]
        bead = Polyline([(x, BEAD_CREASE) for x in xs])
        _brush(ink, side, bead, [(0.0, 0.2), (0.4, 0.17), (0.9, 0.15), (1.0, 0.06)], _even(len(xs) + 2), LIFT_INK,
               SEED + 3 + side)
        head = _line([(_head_junction(y) - 0.08 - HEAD_BOW * math.sin(math.pi * y / 7.6), y) for y in head_ys])
        _brush(ink, side, head, [(0.0, 0.32), (0.5, 0.3), (0.85, 0.2), (1.0, 0.05)], _even(12), LIFT_INK, SEED + 7 + side)


def _streaks(ink: Mesh) -> None:
    for k, ((points, profile), count) in enumerate(zip(STREAKS, STREAK_SAMPLES)):
        line = _line(points)
        for side in (-1, 1):
            _brush(ink, side, line, profile, _even(count), LIFT_INK, SEED + 40 + 3 * k + side)


# --- the three meshes ----------------------------------------------------------------------------


def solids() -> list[tuple[str, Volume]]:
    pieces = [("head", _head()), ("stroke", _slab()), ("bead", _rail(BEAD, BEAD_PIVOT, BEAD_SPAN, BEAD_BURIED))]
    return pieces + [(f"strand{i}", _strand(*spec)) for i, spec in enumerate(STRANDS)]


def build() -> tuple[Mesh, Mesh, Mesh]:
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for _name, vol in solids():
        body.merge(vol.mesh)
        _hull(vol, ink)
    for cx, a in LOBES:
        vol = _lobe(cx, a)
        core.merge(vol.mesh)
        _hull(vol, ink)
    _lobes(core, ink)
    _creases(ink)
    _streaks(ink)
    xs = [v[0] for mesh in (body, core, ink) for v in mesh.verts]
    factor, shift = 1.0 / (max(xs) - min(xs)), -(max(xs) + min(xs)) / 2.0
    for mesh in (body, core, ink):
        mesh.verts = [((x + shift) * factor, y * factor, z * factor) for x, y, z in mesh.verts]
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta(seed: int) -> dict:
    return {"Reference": "Width", "Pivot": [0, round(HEIGHT / 2 / WIDTH, 6), 0], "Axis": "Y", "Flat": False, "Seed": seed}


def rule_body() -> tuple[Mesh, dict]:
    """The Margin's pigment: the rolled head, the stroke, the bead along its top, and the dry tail's three
    strands. Closed and wound outward."""
    return build()[0], meta(SEED)


def rule_lip() -> tuple[Mesh, dict]:
    """The Margin's pale: the five lobes sitting in the bead, and their U on both faces."""
    return build()[1], meta(SEED + 1)


def rule_ink() -> tuple[Mesh, dict]:
    """The Margin's ink: every piece's contour, and the drawing lying on both faces."""
    return build()[2], meta(SEED + 2)
