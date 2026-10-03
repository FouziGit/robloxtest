"""Serif (L'Empattement): one letter foot, the body the timeline strikes five times (DA 13.1), drawn from
the developer's references (docs/vfx/serif/ref-1.jpg, the in-game shot; ref-2.jpg, the model sheet).

A slender hexagonal stake, hard-faceted, struck out of the page: a flat face toward the target and one
toward the thrower, a corner on each side, so the target sees three faces and the thrower three. It
leans 6 degrees toward the target, turns 8 degrees as it rises, tapers a little up to the cut, and its
top is cut off by one chisel plane at 35 degrees to its axis, facing the target: from the front a pale
pointed bevel, from behind a pointed top with a short flat ridge. It stands on its serif: four concave
fillets laid on the page, two long across the stroke (X, the left one longer: the hand is not
symmetric, their squared ends bowed a little toward the target) and two short along it (Z), each a
gusset whose knife ridge leaves the shaft tangent and runs out into a thin plank cut square with a
small upturn.
From behind (the thrower): a tapering shaft on its inverted T. From the side: a stake leaning at the
target. From above: the bar across the stroke, the leaning shaft its stem.

Roblox space: X right, Y up, forward (the aim) is -Z. Pivot (0, 0, 0) on the floor under the shaft's
axis, at its root. Reference `Height` = 1: the floor to the highest ink. Axis Y.

Three meshes, one construction, one scale:
  serif_body (Pigment): the shaft and its four fillets, closed volumes wound outward;
  serif_core (Core): the chisel plane, inset and lifted, and a thin liseré up the front-left edge --
      the timeline lays it on the fifth point only;
  serif_ink (Ink): the inverted hull of every volume (heavy at the root and on the foot, lighter at
      the top; on the floor its rim draws the inverted T on the page), the heel of the cut, the facet
      edges and the calligraphic groove on the facet facing the thrower.
"""

from __future__ import annotations

import math

from strokes import (
    FLOOR_CLEARANCE,
    Mesh,
    Volume,
    add,
    cross,
    dot,
    emit,
    face_normal,
    lerp,
    mul,
    norm,
    sliver,
    smoothstep,
    sub,
    surface_ribbon,
)

SEED = 5031
ENVELOPE = 0.46
CAPS = {"body": 300, "core": 60, "ink": 350}
SPHERE_R, SPHERE_Y, POSED, STRIKE_Y = 5.0, 3.0, 1.44 * 5.0, 1.1

# --- the shaft -------------------------------------------------------------------------------------
LEAN = math.radians(6.0)  # toward -Z
TWIST = math.radians(8.0)
YS = (0.0, 0.3, 0.55, 0.75, 0.88, 1.0, 1.12)  # ring heights (before the final scale)
# Half sizes at the root and at the cut: w to the side corners (X), a to the ends of the front face (X),
# b to the ends of the back face (X), d to the front and back faces (Z). The back face is the narrower:
# from behind the cut leaves a pointed top on a short flat, from the front a pointed pale bevel.
ROOT = (0.068, 0.037, 0.02, 0.065)
TOP = (0.06, 0.033, 0.018, 0.057)
# The section, corner by corner: (which half size across, sign, which depth, uneven factor).
# L, FL, FR, R, BR, BL -- the hand's unevenness keeps two neighbouring faces from matching.
SECTION = (("w", -1, 0.0, 1.04), ("a", -1, -1.0, 1.06), ("a", 1, -1.0, 0.94), ("w", 1, 0.0, 0.97), ("b", 1, 1.0, 1.05), ("b", -1, 1.0, 0.95))
L, FL, FR, R, BR, BL = range(6)
CUT_ANGLE = math.radians(35.0)  # between the chisel plane and the axis
CUT_Y = 0.91  # where the plane crosses the axis
CUT_YAW = math.radians(10.0)  # the plane turned toward the front-left: seen from the front, the left and three quarters, never from behind

# --- the foot: four gussets (direction in XZ, height on the shaft, fillet run, plank, thickness root/end,
# stations along the quarter-ellipse fillet). Each is a knife ridge up the shaft that widens to a flat plank.
FINS = (
    ((-1.0, 0.0), 0.25, 0.155, 0.02, 0.125, 0.08, (0.0, 0.22, 0.45, 0.72, 1.0)),
    ((1.0, 0.0), 0.23, 0.135, 0.02, 0.12, 0.076, (0.0, 0.22, 0.45, 0.72, 1.0)),
    ((0.0, -1.0), 0.19, 0.08, 0.015, 0.085, 0.06, (0.0, 0.3, 0.62, 1.0)),
    ((0.0, 1.0), 0.17, 0.064, 0.014, 0.085, 0.062, (0.0, 0.3, 0.62, 1.0)),
)
SWEEP = 0.035  # the long fillets' squared ends bow toward the target: from above, a bracketed serif
PLANK = 0.024  # the plank's height where the fillet lands
BURY = 0.004  # how far inside the shaft's surface each fillet starts
LIP = 0.01  # its upturn at the squared end

# --- contour weights -------------------------------------------------------------------------------
INK_ROOT = 0.035
INK_TOP = 0.02
INK_END = 0.026

# --- the core and the lines ------------------------------------------------------------------------
CORE_LIFT = 0.006
CUT_INSET = 0.95
STRIP = (FL, 0.1, 0.82, 0.03)  # pale liseré: corner, from, to, width
LINE_LIFT = 0.006


def _axis(y: float):
    return (0.0, y, -math.tan(LEAN) * y)


def _half(y: float):
    f = smoothstep(0.0, 0.9, y)
    return tuple(r + (t - r) * f for r, t in zip(ROOT, TOP))


def _corner(y: float, j: int):
    w, a, b, d = _half(y)
    which, sign, depth, uneven = SECTION[j]
    across = {"w": w, "a": a, "b": b}[which] * sign * uneven
    z = depth * d
    angle = TWIST * smoothstep(0.05, 1.0, y)
    c, s = math.cos(angle), math.sin(angle)
    x, z = across * c + z * s, -across * s + z * c
    p = add(_axis(y), (x, 0.0, z))
    return (p[0], y, p[2])


def _cut():
    """The chisel plane: through the axis at CUT_Y, at CUT_ANGLE to the axis, facing the target (-Z) and up."""
    axis = (0.0, math.cos(LEAN), -math.sin(LEAN))
    front = (0.0, -math.sin(LEAN), -math.cos(LEAN))
    n = norm(add(mul(front, math.cos(CUT_ANGLE)), mul(axis, math.sin(CUT_ANGLE))))
    c, s = math.cos(CUT_YAW), math.sin(CUT_YAW)
    n = (n[0] * c + n[2] * s, n[1], -n[0] * s + n[2] * c)
    return _axis(CUT_Y), n


def _shaft():
    origin, n = _cut()
    columns, progress = [], []
    for j in range(6):
        col, prog, prev = [], [], None
        for y in YS:
            q = _corner(y, j)
            f = dot(sub(q, origin), n)
            if f < 0.0:
                col.append(q)
                prog.append(y)
                prev = (q, f, y)
                continue
            pq, pf, py = prev
            k = pf / (pf - f)
            col.append(lerp(pq, q, k))
            prog.append(py + (y - py) * k)
            break
        columns.append(col)
        progress.append(prog)
    vol = Volume()

    def weight(y: float) -> float:
        return INK_ROOT + (INK_TOP - INK_ROOT) * smoothstep(0.1, 0.85, y)

    ids = [[vol.vert(p, weight(y)) for p, y in zip(col, prog)] for col, prog in zip(columns, progress)]
    for j in range(6):
        k = (j + 1) % 6
        cj, ck, pj, pk = ids[j], ids[k], progress[j], progress[k]
        a = b = 0
        while a < len(cj) - 1 or b < len(ck) - 1:
            if a >= len(cj) - 1 or (b < len(ck) - 1 and pk[b + 1] <= pj[a + 1]):
                emit(vol.mesh, cj[a], ck[b], ck[b + 1])
                b += 1
            else:
                emit(vol.mesh, cj[a], ck[b], cj[a + 1])
                a += 1
    bottom = [c[0] for c in ids]
    for j in range(1, 5):
        emit(vol.mesh, bottom[0], bottom[j + 1], bottom[j])
    top = [c[-1] for c in ids]
    for j in range(1, 5):
        emit(vol.mesh, top[0], top[j], top[j + 1])
    vol.orient_outward()
    return vol, columns, progress, top


def _surface_distance(e, y: float) -> float:
    """How far from the axis, along the horizontal direction e, the shaft's surface is at height y."""
    origin = _axis(y)
    ring = [_corner(y, j) for j in range(6)]
    best = 0.0
    for j in range(6):
        p, q = ring[j], ring[(j + 1) % 6]
        # intersect the ray origin + e*s with the edge p-q in XZ
        ex, ez = e
        dx, dz = q[0] - p[0], q[2] - p[2]
        den = ex * (-dz) - ez * (-dx)
        if abs(den) < 1e-12:
            continue
        rx, rz = p[0] - origin[0], p[2] - origin[2]
        s = (rx * (-dz) - rz * (-dx)) / den
        t = (ex * rz - ez * rx) / den
        if s > 0 and -1e-9 <= t <= 1 + 1e-9:
            best = max(best, s)
    return best


def _fin(spec) -> Volume:
    (ex, ez), h0, run, plank, t_root, t_end, steps = spec
    e = (ex, 0.0, ez)
    side = (-ez, 0.0, ex)
    # The fillet starts on the shaft's surface, tangent to it, and its buried root rises steeply into the
    # shaft, so its ridge leaves the shaft's edge without its contour bumping past the shaft's own.
    s1 = _surface_distance((ex, ez), h0) - BURY
    stations = [(0.3 * s1, h0 + 0.06)]
    for f in steps:
        th = f * math.pi / 2
        stations.append((s1 + run - run * math.cos(th), PLANK + (h0 - PLANK) * (1.0 - math.sin(th))))
    reach = s1 + run + plank
    stations.append((reach, PLANK + LIP))
    vol = Volume()
    rings = []
    last = len(stations) - 1
    for i, (s, top) in enumerate(stations):
        g = min(1.0, max(0.0, (s - s1) / (reach - s1)))
        t = t_root + (t_end - t_root) * g
        w = 0.006 + (INK_END - 0.006) * g
        base = add(mul(e, s), (0.0, 0.0, -SWEEP * g * g * abs(ex)))
        rise = min(1.0, max(0.0, (top - PLANK) / (h0 - PLANK)))
        k = t / 2 * (0.06 + 0.88 * (1.0 - rise) ** 1.6)  # a gusset's knife ridge up the shaft, a plank's flat top at the end
        corners = ((-t / 2, 0.0), (t / 2, 0.0), (k, top), (-k, top))
        rings.append([vol.vert(add(add(base, mul(side, c)), (0.0, y, 0.0)), w) for c, y in corners])
    m = 4
    for a, b in zip(rings, rings[1:]):
        for j in range(m):
            k = (j + 1) % m
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    first, end = rings[0], rings[last]
    emit(vol.mesh, first[0], first[2], first[1])
    emit(vol.mesh, first[0], first[3], first[2])
    emit(vol.mesh, end[0], end[1], end[2])
    emit(vol.mesh, end[0], end[2], end[3])
    vol.orient_outward()
    return vol


# --- the contour ---------------------------------------------------------------------------------------


def _hull(vol: Volume, into: Mesh) -> None:
    """strokes.inverted_hull, but a vertex on the floor is pushed out across the floor only, along its
    side faces: the foot's floor faces would otherwise turn its rim's normal down, and the clamp would
    eat the outline the foot draws on the page."""
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    side = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        n = norm(face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c]))
        on_floor = all(mesh.verts[v][1] <= 1e-9 for v in (a, b, c))
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
            if not on_floor:
                side[v] = add(side[v], n)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        if p[1] <= 1e-9 and (side[i][0] ** 2 + side[i][2] ** 2) > 1e-18:
            d = norm((side[i][0], 0.0, side[i][2]))
        else:
            d = norm(acc[i])
        q = add(p, mul(d, vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR_CLEARANCE), q[2]))
    for a, b, c in mesh.tris:
        corners = [into.verts[v + base] for v in (a, b, c)]
        if all(q[1] <= FLOOR_CLEARANCE for q in corners) and sliver(*corners):
            continue
        emit(into, a + base, c + base, b + base)


# --- surfaces on the shaft ----------------------------------------------------------------------------


def _at(points, ys, y):
    for i in range(len(ys) - 1):
        if ys[i] <= y <= ys[i + 1]:
            return lerp(points[i], points[i + 1], (y - ys[i]) / (ys[i + 1] - ys[i]))
    return points[0] if y < ys[0] else points[-1]


def _col(columns, progress, j, y):
    return _at(columns[j], progress[j], min(y, progress[j][-1]))


def _facet(columns, progress, j, k):
    def point(y, t):
        return lerp(_col(columns, progress, j, y), _col(columns, progress, k, y), t)

    def normal(y, t):
        lo, hi = max(y - 0.03, 0.0), y + 0.03
        a, b = _col(columns, progress, j, lo), _col(columns, progress, k, lo)
        c = _col(columns, progress, j, hi)
        if math.dist(a, c) < 1e-9:
            c = a
            a, b = _col(columns, progress, j, lo - 0.06), _col(columns, progress, k, lo - 0.06)
        nrm = norm(cross(sub(b, a), sub(c, a)))
        if dot(nrm, sub(lerp(a, b, 0.5), _axis(max(lo, 0.0)))) < 0:
            nrm = mul(nrm, -1.0)
        return nrm

    return point, normal


def _ridge(mesh, columns, progress, j, lo, hi, widths, lift, samples):
    """A stroke astride the shaft's edge j, from height lo to hi, half on each facet, lifted off both."""
    before, after = (j - 1) % 6, (j + 1) % 6
    left, right = _facet(columns, progress, before, j), _facet(columns, progress, j, after)
    rows = []
    for i in range(samples):
        f = i / (samples - 1)
        y = lo + (hi - lo) * f
        ridge = _col(columns, progress, j, y)
        n_l, n_r = left[1](y, 1.0), right[1](y, 0.0)
        half = 0.5 * widths(f)
        bis = norm(add(n_l, n_r))
        mid = add(ridge, mul(bis, lift / max(dot(bis, n_l), 0.5)))
        a = add(add(ridge, mul(norm(sub(_col(columns, progress, before, y), ridge)), half)), mul(n_l, lift))
        b = add(add(ridge, mul(norm(sub(_col(columns, progress, after, y), ridge)), half)), mul(n_r, lift))
        rows.append((mesh.vert(a), mesh.vert(mid), mesh.vert(b), n_l, n_r))
    for (a0, m0, b0, nl, nr), (a1, m1, b1, _, _) in zip(rows, rows[1:]):
        mesh.tri(a0, m0, m1, nl)
        mesh.tri(a0, m1, a1, nl)
        mesh.tri(m0, b0, b1, nr)
        mesh.tri(m0, b1, m1, nr)


def _below(columns, j, dist):
    col = columns[j]
    left = dist
    for i in range(len(col) - 1, 0, -1):
        seg = math.dist(col[i], col[i - 1])
        if seg >= left:
            return lerp(col[i], col[i - 1], left / seg)
        left -= seg
    return col[0]


def _heel(ink, columns, progress, order, width, per=2):
    """The heel of the cut: ink on the faces just under the chisel plane's lower edges, thickest in
    the middle -- what makes the bevel a plane of its own on a body lit flat."""
    normals = []
    for a, b in zip(order, order[1:]):
        mid = 0.5 * (progress[a][-1] + progress[b][-1]) - 0.05
        normals.append(_facet(columns, progress, a, b)[1](mid, 0.5))
    rows = []
    count = per * (len(order) - 1)
    for i in range(count + 1):
        e = min(i // per, len(order) - 2)
        f = 1.0 if i == count else (i % per) / per
        j, k = order[e], order[e + 1]
        g = i / count
        w = width * math.sin(math.pi * g) ** 0.6 + 0.003
        if f == 0.0 and e > 0:
            nrm = norm(add(normals[e - 1], normals[e]))
            lift = LINE_LIFT / max(dot(nrm, normals[e]), 0.5)
        else:
            nrm, lift = normals[e], LINE_LIFT
        up = lerp(_below(columns, j, 0.004), _below(columns, k, 0.004), f)
        down = lerp(_below(columns, j, 0.004 + w), _below(columns, k, 0.004 + w), f)
        rows.append((ink.vert(add(up, mul(nrm, lift))), ink.vert(add(down, mul(nrm, lift))), nrm))
    for (u0, d0, n0), (u1, d1, _) in zip(rows, rows[1:]):
        ink.tri(u0, d0, d1, n0)
        ink.tri(u0, d1, u1, n0)


# --- the core -------------------------------------------------------------------------------------------


def _pale_cut(core: Mesh, top_points) -> None:
    c = (0.0, 0.0, 0.0)
    for p in top_points:
        c = add(c, mul(p, 1.0 / len(top_points)))
    _, n = _cut()
    ids = [core.vert(add(lerp(c, p, CUT_INSET), mul(n, CORE_LIFT))) for p in top_points]
    for m in range(1, len(ids) - 1):
        core.tri(ids[0], ids[m], ids[m + 1], n)


def _lines(ink: Mesh, columns, progress) -> None:
    def taper(width, start=0.5):
        return lambda f: max(width * (1.0 - f) ** 0.7 * min(1.0, f / 0.15 + start), 0.004)

    # The front: both edges of the face toward the target; the left one goes pale above (the liseré).
    _ridge(ink, columns, progress, FR, 0.01, 0.74, taper(0.022, 1.0), LINE_LIFT, 5)
    _ridge(ink, columns, progress, FL, 0.01, 0.1, taper(0.02, 1.0), LINE_LIFT, 3)
    # Behind: the back-left edge, long; the side: the right corner, shorter.
    _ridge(ink, columns, progress, BL, 0.01, 0.78, taper(0.022, 1.0), LINE_LIFT, 5)
    _ridge(ink, columns, progress, R, 0.22, 0.6, taper(0.016), LINE_LIFT, 4)
    # The groove on the facet facing the thrower (+Z), toward +X, from 0.15 to 0.8.
    surface_ribbon(ink, _facet(columns, progress, R, BR), lambda tau: (0.15 + 0.65 * tau, 0.55 + 0.08 * tau), 0.03, LINE_LIFT, 6, SEED + 7)
    # The heel of the cut, round the front from the left corner to the right one.
    _heel(ink, columns, progress, [L, FL, FR, R], 0.016, 2)


def _floor_patch(ink: Mesh, radius: float = 0.13, n: int = 10) -> None:
    """Ink laid on the floor round the shaft's root: closes the hairline where two gussets' shells meet."""
    c = ink.vert((0.0, FLOOR_CLEARANCE, 0.0))
    ring = [ink.vert((radius * math.cos(2 * math.pi * i / n), FLOOR_CLEARANCE, radius * math.sin(2 * math.pi * i / n))) for i in range(n)]
    for i in range(n):
        ink.tri(c, ring[i], ring[(i + 1) % n], (0.0, 1.0, 0.0))


# --- the three meshes -----------------------------------------------------------------------------------

_CACHE: dict = {}


def _dome(mesh: Mesh) -> float:
    worst = 1e9
    for x, y, z in mesh.verts:
        r = math.hypot(x, z) * POSED
        if r >= SPHERE_R:
            return -1.0
        worst = min(worst, math.sqrt(SPHERE_R**2 - r * r) + SPHERE_Y - y * POSED * STRIKE_Y)
    return worst


def parts():
    shaft, columns, progress, top = _shaft()
    fins = [_fin(spec) for spec in FINS]
    return shaft, columns, progress, top, fins


def build():
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    shaft, columns, progress, top, fins = parts()
    solids = [shaft] + fins
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for vol in solids:
        body.merge(vol.mesh)
    _pale_cut(core, [shaft.mesh.verts[i] for i in top])
    j, lo, hi, width = STRIP
    _ridge(core, columns, progress, j, lo, hi, lambda f: width * (0.35 + 0.65 * math.sin(math.pi * min(f * 1.6, 1.0) / 2) ** 0.8) * (1.0 - 0.7 * f**3), CORE_LIFT, 7)
    for vol in solids:
        _hull(vol, ink)
    _lines(ink, columns, progress)
    _floor_patch(ink)
    peak = max(v[1] for mesh in (body, core, ink) for v in mesh.verts)
    for mesh in (body, core, ink):
        mesh.scale(1.0 / peak)
    problems = []
    for name, mesh in (("body", body), ("core", core), ("ink", ink)):
        if len(mesh.tris) > CAPS[name]:
            problems.append(f"serif {name}: {len(mesh.tris)} triangles, over its cap of {CAPS[name]}")
        reach = max(math.hypot(x, z) for x, _, z in mesh.verts)
        if reach > ENVELOPE:
            problems.append(f"serif {name}: reaches {reach:.4f} across the floor, past {ENVELOPE}")
        if min(v[1] for v in mesh.verts) < 0.0:
            problems.append(f"serif {name}: below the floor")
        if _dome(mesh) < 0.0:
            problems.append(f"serif {name}: out of the server's sphere by {-_dome(mesh):.3f} studs")
    if problems:
        raise ValueError("; ".join(problems))
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta(seed: int) -> dict:
    return {"Reference": "Height", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def serif_body():
    return build()[0], meta(SEED)


def serif_core():
    return build()[1], meta(SEED + 1)


def serif_ink():
    return build()[2], meta(SEED + 2)
