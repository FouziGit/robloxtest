"""The Ligature's burning tie (DA_ENCRE_3D, lot 2): a cinnabar ribbon laid along the dash, a loaded head
where the dash starts, five burning knots on the server's five pools, and a dry tail that splits into
bristles where the dash ends. Drawn after the developer's two references (docs/vfx/ligature/ref-1.jpg, the
in-game shot; ref-2.jpg, the model sheet).

Roblox space: X right, Y up, forward -Z (the dash). Built in studs, then scaled by 1/26: Reference
`Length` = 1 is the server's trail, from -5 to +21 studs along the dash (pools at 0, 4, 8, 12, 16, radius
5). Pivot (0, 0, 0): the cast origin on the floor (Face "Aim", Offset -3). Axis Y.

Three meshes, one tone each, one construction, one scale and one pivot:
  LigatureBody (Pigment): the ribbon; the loaded head, a lobed dome of wet pigment over the ribbon's start; the
    dry bristles of the tail; the tongues of the five knots (3 or 4 a knot): a G-crozier traced off
    ref-1 and flame licks after ref-2's front view.
  LigatureCore (Core): a pale streak on both faces of every tongue, held 0.1 stud inside its pigment.
  LigatureInk (Ink): the inverted hull of every tongue and of the ribbon; the head's one dark hollow (its
    loaded core), its contour on the page, its drips and its round splatter beads; a thin broken ring
    round each knot's root; three calligraphic flow lines; the contour under every bristle and the dry
    hairs between them.

Settled by review: bristle tips wound up; every tongue contour at 0.1 stud or more,
outlines drawn so the offset never folds; the pale 0.1 stud inside its pigment; pools narrowed to a
broken contour-width ring with no crest; a red loaded head with a smaller ink core; ten thin combed
bristles in a narrow fan; flame licks that point up; the G traced off ref-1 with a round mouth.
"""

from __future__ import annotations

import math

from strokes import Mesh, Rng, catmull, fbm

SEED = 2609
STUD = 1.0 / 26.0
Z_HEAD, Z_TAIL = 5.0, -21.0  # the server's trail ends (studs, along -Z forward)

# The five knots: (z of the server's pool, height of the knot in studs, tongues).
KNOTS = [(0.0, 4.5, 4), (-4.0, 4.0, 4), (-8.0, 3.2, 4), (-12.0, 2.5, 3), (-16.0, 2.0, 3)]

FLOOR = 0.06  # how far the ink stays over the page (studs)
RIB_H = 0.30  # the ribbon's top over the page
# The pigment's edges on the page stand just over its contour's foot (FLOOR): the hull's turned-up floor
# face must lie under the pigment everywhere, or it covers the stroke's thin edge in black.
EDGE = FLOOR + 0.04
BRISTLE_Y = FLOOR + 0.025  # a bristle's edges: over its contour, under the ribbon's foot (EDGE)
RIB_START, RIB_END = 3.8, -18.0
RIB_HULL = 0.16  # the ribbon's contour (its foot on the page): the bible's Cinnabar 0.15 - 0.20
CONTOUR_MIN = 0.1  # the bible's floor for any contour, at final size
LIFT = 0.035  # a decal of ink over whatever it lies on

# Tongues.
MAIN_YAW = math.radians(35.0)  # the main tongue's plane, turned from the dash toward +X
W_ROOT, W_TIP = 0.15, 0.10  # a tongue's contour: heavier at the root, light at the tips and in the mouth
HULL_DEPTH = 0.35  # how far (in contour weights) the hull stands off a tongue's faces
STREAK_LIFT = 0.04
LENS_MARGIN = 0.1  # the pale stays this far (studs) inside its tongue's pigment edge

FOLDS: list = []  # every contour weight eased under the bible's floor (must stay empty)


# --- small vector helpers ------------------------------------------------------------------------


def mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def unit2(x, y):
    length = math.hypot(x, y) or 1.0
    return (x / length, y / length)


def smooth(e0, e1, x):
    u = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


# --- 2D polygons ---------------------------------------------------------------------------------


def signed_area(poly):
    return 0.5 * sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(len(poly)))


def area2(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def inside_tri(p, a, b, c):
    d1, d2, d3 = area2(a, b, p), area2(b, c, p), area2(c, a, p)
    return d1 > -1e-12 and d2 > -1e-12 and d3 > -1e-12


def min_angle(a, b, c):
    out = math.pi
    for o, p, q in ((a, b, c), (b, c, a), (c, a, b)):
        u = (p[0] - o[0], p[1] - o[1])
        v = (q[0] - o[0], q[1] - o[1])
        lu, lv = math.hypot(*u), math.hypot(*v)
        if lu < 1e-12 or lv < 1e-12:
            return 0.0
        out = min(out, math.acos(max(-1.0, min(1.0, (u[0] * v[0] + u[1] * v[1]) / (lu * lv)))))
    return out


def triangulate(poly):
    """Ear clipping of a counter-clockwise simple polygon, best ear first (the fattest triangle), then
    diagonals flipped wherever that fattens the thinner of two triangles."""
    idx = list(range(len(poly)))
    tris = []
    while len(idx) > 3:
        best = None
        n = len(idx)
        for k in range(n):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % n]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if area2(a, b, c) <= 1e-12:
                continue
            if any(inside_tri(poly[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            q = min_angle(a, b, c)
            if best is None or q > best[0]:
                best = (q, k)
        if best is None:
            # A collinear or tangled vertex: drop the flattest one and go on.
            k = min(range(n), key=lambda k: abs(area2(poly[idx[k - 1]], poly[idx[k]], poly[idx[(k + 1) % n]])))
            idx.pop(k)
            continue
        k = best[1]
        tris.append((idx[k - 1], idx[k], idx[(k + 1) % n]))
        idx.pop(k)
    if len(idx) == 3 and area2(*(poly[i] for i in idx)) > 1e-12:
        tris.append(tuple(idx))
    return flip_fattest(poly, tris)


def flip_fattest(poly, tris):
    """Flips a diagonal shared by two triangles wherever the other diagonal makes the thinner of the two
    fatter, until none does: greedy ears can leave a sliver they could not avoid."""
    tris = [tuple(t) for t in tris]
    for _ in range(300):
        edges = {}
        for ti, t in enumerate(tris):
            for k in range(3):
                edges[(t[k], t[(k + 1) % 3])] = (ti, t[(k + 2) % 3])
        flipped = False
        for (a, b), (ti, c) in edges.items():
            if (b, a) not in edges:
                continue
            tj, d = edges[(b, a)]
            if ti > tj:
                continue
            if area2(poly[a], poly[d], poly[c]) <= 1e-12 or area2(poly[d], poly[b], poly[c]) <= 1e-12:
                continue
            now = min(min_angle(poly[a], poly[b], poly[c]), min_angle(poly[b], poly[a], poly[d]))
            then = min(min_angle(poly[a], poly[d], poly[c]), min_angle(poly[d], poly[b], poly[c]))
            if then > now + 1e-6:
                tris[ti], tris[tj] = (a, d, c), (d, b, c)
                flipped = True
                break
        if not flipped:
            break
    return tris


def ccw(poly):
    return poly if signed_area(poly) > 0 else list(reversed(poly))


def seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / (ax * ax + ay * ay or 1.0)))
    return math.dist(p, (a[0] + ax * t, a[1] + ay * t))


def edge_dist(p, poly):
    return min(seg_dist(p, poly[i - 1], poly[i]) for i in range(len(poly)))


def inside(p, poly):
    x, y = p
    c = False
    for i in range(len(poly)):
        a, b = poly[i - 1], poly[i]
        if (a[1] > y) != (b[1] > y):
            xi = a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if xi > x:
                c = not c
    return c


def offset_outline(poly, weights, convex_limit=1.8, concave_limit=1.4):
    """Each vertex pushed out along its mitre by its weight. A weight is eased wherever the pushed outline
    would fold back on itself; the outlines are drawn so that it never has to (FOLDS records any)."""
    n = len(poly)
    normals = []
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        normals.append(unit2(dy, -dx))
    mitres = []
    for i in range(n):
        n1, n2 = normals[i - 1], normals[i]
        m = unit2(n1[0] + n2[0], n1[1] + n2[1])
        cos = max(m[0] * n1[0] + m[1] * n1[1], 1e-3)
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]
        convex = area2(a, b, c) > 0
        k = min(1.0 / cos, convex_limit if convex else concave_limit)
        mitres.append((m[0] * k, m[1] * k))
    w = list(weights)
    short = 0.6 * sum(weights) / len(weights)
    for _ in range(40):
        pushed = [(p[0] + m[0] * wi, p[1] + m[1] * wi) for p, m, wi in zip(poly, mitres, w)]
        changed = False
        for i in range(n):
            j = (i + 1) % n
            sx, sy = poly[j][0] - poly[i][0], poly[j][1] - poly[i][1]
            if sx * sx + sy * sy < short * short:
                continue
            px, py = pushed[j][0] - pushed[i][0], pushed[j][1] - pushed[i][1]
            if px * sx + py * sy < 0.25 * (sx * sx + sy * sy):
                w[i] *= 0.85
                w[j] *= 0.85
                changed = True
        if not changed:
            break
    if min(w) < CONTOUR_MIN - 1e-9:
        FOLDS.append((min(w), [i for i, x in enumerate(w) if x < CONTOUR_MIN - 1e-9]))
    return [(p[0] + m[0] * wi, p[1] + m[1] * wi) for p, m, wi in zip(poly, mitres, w)], w


# --- a flat tongue: a polygon slab standing in a vertical plane ----------------------------------


class Frame:
    """A vertical sheet: `origin` (studs), `u` a horizontal unit direction, v is +Y, `n` its normal. With a
    `bend` radius the sheet is rolled about a vertical axis on its n side, so seen from above a tongue is
    a curled stroke, not a plank."""

    def __init__(self, origin, yaw_dir, bend=0.0):
        self.o = origin
        self.u = yaw_dir
        self.n = (-yaw_dir[2], 0.0, yaw_dir[0])
        self.bend = bend

    def at(self, p, depth=0.0):
        u, v = p
        if self.bend:
            t = u / self.bend
            along = self.bend * math.sin(t) - depth * math.sin(t)
            off = self.bend * (1.0 - math.cos(t)) + depth * math.cos(t)
        else:
            along, off = u, depth
        return (self.o[0] + self.u[0] * along + self.n[0] * off, self.o[1] + v, self.o[2] + self.u[2] * along + self.n[2] * off)

    def to3(self, d2):
        return (self.u[0] * d2[0], d2[1], self.u[2] * d2[0])


def clamp_floor(p):
    return (p[0], max(p[1], FLOOR), p[2])


def slab(body: Mesh, ink: Mesh, frame: Frame, poly, thickness, weights):
    """The tongue's pigment (front and back faces, and its edge walls) and its inverted hull. Returns the
    counter-clockwise outline and its contour weights."""
    poly = list(poly)
    weights = list(weights)
    if signed_area(poly) < 0:
        poly.reverse()
        weights.reverse()
    tris = triangulate(poly)
    n = frame.n
    half = thickness / 2.0
    front = [body.vert(frame.at(p, half)) for p in poly]
    back = [body.vert(frame.at(p, -half)) for p in poly]
    for a, b, c in tris:
        body.tri(front[a], front[b], front[c], n)
        body.tri(back[a], back[b], back[c], mul(n, -1.0))
    count = len(poly)
    for i in range(count):
        j = (i + 1) % count
        dx, dy = poly[j][0] - poly[i][0], poly[j][1] - poly[i][1]
        out = frame.to3((dy, -dx))
        body.tri(front[i], front[j], back[j], out)
        body.tri(front[i], back[j], back[i], out)
    hull, w = offset_outline(poly, weights)
    # Off the faces the contour stands well less than past the outline: it only shows edge-on, and a deep
    # hull would show as a black flank on every tongue seen at a slant.
    hf = [ink.vert(clamp_floor(frame.at(q, half + HULL_DEPTH * wi))) for q, wi in zip(hull, w)]
    hb = [ink.vert(clamp_floor(frame.at(q, -half - HULL_DEPTH * wi))) for q, wi in zip(hull, w)]
    # The hull's faces get their own triangles: the pigment's, moved out with their points, can thin to
    # slivers where the mitres turn.
    hull_tris = triangulate(hull) if signed_area(hull) > 0 else []
    if len(hull_tris) != count - 2:
        hull_tris = tris
    for a, b, c in hull_tris:
        ink.tri(hf[a], hf[b], hf[c], mul(n, -1.0))
        ink.tri(hb[a], hb[b], hb[c], n)
    for i in range(count):
        j = (i + 1) % count
        dx, dy = hull[j][0] - hull[i][0], hull[j][1] - hull[i][1]
        inward = frame.to3((-dy, dx))
        ink.tri(hf[i], hf[j], hb[j], inward)
        ink.tri(hf[i], hb[j], hb[i], inward)
    return poly, w


def lens_on_faces(core: Mesh, frame: Frame, lens, thickness):
    """A pale lens lying on both faces of a tongue, lifted off each."""
    lens = ccw(lens)
    tris = triangulate(lens)
    for sign in (1.0, -1.0):
        depth = sign * (thickness / 2.0 + STREAK_LIFT)
        ids = [core.vert(frame.at(p, depth)) for p in lens]
        for a, b, c in tris:
            core.tri(ids[a], ids[b], ids[c], mul(frame.n, sign))


def fit_lens(spine, half_widths, outline, margin=LENS_MARGIN):
    """A pale lens along `spine` (studs), as wide as `half_widths` asks wherever its tongue leaves room for
    it `margin` inside the pigment's edge, shorter where it does not. None if no lens fits."""
    pts, ws = [], []
    for p, hw in zip(spine, half_widths):
        if not inside(p, outline):
            continue
        room = edge_dist(p, outline) - margin
        if room < 0.015:
            continue
        pts.append(p)
        ws.append(min(hw, room))
    if len(pts) < 4:
        return None
    ws[0] = ws[-1] = 0.0
    for _ in range(30):
        normals = []
        for i in range(len(pts)):
            a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
            t = unit2(b[0] - a[0], b[1] - a[1])
            normals.append((-t[1], t[0]))
        left = [(p[0] + nn[0] * w, p[1] + nn[1] * w) for p, nn, w in zip(pts, normals, ws)]
        right = [(p[0] - nn[0] * w, p[1] - nn[1] * w) for p, nn, w in zip(pts, normals, ws)]
        lens = [pts[0]] + left[1:-1] + [pts[-1]] + list(reversed(right[1:-1]))
        bad = False
        for i in range(1, len(pts) - 1):
            probes = [left[i], right[i], ((left[i][0] + left[i - 1][0]) / 2, (left[i][1] + left[i - 1][1]) / 2),
                      ((right[i][0] + right[i - 1][0]) / 2, (right[i][1] + right[i - 1][1]) / 2)]
            if any(not inside(q, outline) or edge_dist(q, outline) < margin for q in probes):
                ws[i] *= 0.8
                bad = True
        if not bad:
            return lens
    return lens


# --- the main tongue: the G-crozier of ref-1 -----------------------------------------------------

# Traced off the in-game shot (ref-1, the red inside the ink), u forward (the hook's side), v up, height 1.
# A comma standing on its narrow root, its belly low on the front, its stem rising on the back into a
# crown that curls forward and down into a needle; a lip off the front rises under it: the G. The mouth
# is the ink-free hole between them, a third of the tongue's height. Four spans with matching ends
# (root, crown, hook tip, lip tip, root), so the two tracings blend point for point.
# The tall G (ref-1's first knot): slim, a sharp spur pointing up into the mouth.
G_BIG = (
    [(0.005, 0.0), (0.03, 0.07), (0.048, 0.16), (0.042, 0.25), (0.02, 0.32), (-0.02, 0.39), (-0.09, 0.47),
     (-0.135, 0.53), (-0.162, 0.61), (-0.166, 0.70), (-0.15, 0.785), (-0.125, 0.845), (-0.09, 0.9),
     (-0.055, 0.948), (-0.015, 0.985), (0.025, 1.0)],
    [(0.025, 1.0), (0.065, 0.995), (0.098, 0.972), (0.117, 0.94), (0.122, 0.905), (0.103, 0.86)],
    [(0.103, 0.86), (0.094, 0.9), (0.08, 0.928), (0.058, 0.945), (0.03, 0.95), (0.0, 0.94), (-0.028, 0.915),
     (-0.047, 0.87), (-0.058, 0.81), (-0.06, 0.745), (-0.05, 0.685), (-0.025, 0.635), (0.01, 0.605),
     (0.045, 0.595), (0.072, 0.603), (0.09, 0.625), (0.098, 0.66), (0.095, 0.70), (0.085, 0.745)],
    [(0.085, 0.745), (0.11, 0.715), (0.135, 0.68), (0.16, 0.625), (0.178, 0.565), (0.188, 0.51),
     (0.19, 0.405), (0.177, 0.305), (0.14, 0.2), (0.105, 0.135), (0.06, 0.06), (0.005, 0.0)],
)
# The small G (ref-1's last knot): stubbier, a rounder and wider mouth, its hook a thin arm the ink all
# but swallows, a blunt lip whose contour makes its point.
G_SMALL = (
    [(0.005, 0.0), (-0.005, 0.05), (0.014, 0.12), (0.012, 0.19), (-0.01, 0.28), (-0.07, 0.38), (-0.17, 0.48),
     (-0.225, 0.56), (-0.25, 0.64), (-0.248, 0.72), (-0.218, 0.82), (-0.16, 0.915), (-0.095, 0.975),
     (-0.03, 1.0)],
    [(-0.03, 1.0), (0.035, 0.998), (0.085, 0.975), (0.118, 0.94), (0.13, 0.9), (0.118, 0.858)],
    [(0.118, 0.858), (0.106, 0.885), (0.08, 0.905), (0.04, 0.917), (0.0, 0.912), (-0.045, 0.89),
     (-0.088, 0.85), (-0.113, 0.8), (-0.12, 0.74), (-0.108, 0.675), (-0.068, 0.62), (-0.015, 0.585),
     (0.035, 0.565), (0.083, 0.565), (0.118, 0.585), (0.134, 0.622)],
    [(0.134, 0.622), (0.164, 0.64), (0.182, 0.6), (0.192, 0.53), (0.192, 0.42), (0.175, 0.3), (0.14, 0.19),
     (0.09, 0.1), (0.04, 0.035), (0.005, 0.0)],
)
G_KINDS = ("out", "out", "mouth", "out")
# The pale streak (ref-1): up the belly from low on the front, across the stem, to under the crown.
G_STREAK_BIG = [(0.072, 0.17), (0.093, 0.27), (0.083, 0.36), (0.04, 0.45), (-0.02, 0.52), (-0.07, 0.585),
                (-0.097, 0.65), (-0.105, 0.72)]
G_STREAK_SMALL = [(0.06, 0.2), (0.068, 0.27), (0.04, 0.35), (-0.02, 0.43), (-0.09, 0.5), (-0.15, 0.57),
                  (-0.18, 0.63), (-0.19, 0.7)]
G_STREAK_W = [0.0, 0.016, 0.026, 0.032, 0.03, 0.022, 0.012, 0.0]
# How far each knot's G is from the tall tracing to the small one (ref-1 measures its five knots 0.355,
# 0.37, 0.39, 0.40 and 0.44 of their height across).
G_BLEND = [0.0, 0.15, 0.45, 0.8, 1.0]


def resample_curvy(points, count, bias=0.45):
    """`count` points along a Catmull-Rom through `points`, ends kept, spaced by a mix of arc length and
    turning: a hook or a mouth gets the points it needs, a straight run does not."""
    dense = catmull(points, 16)
    m = len(dense)
    seg = [math.dist(dense[i], dense[i + 1]) for i in range(m - 1)]
    turn = [0.0] * m
    for i in range(1, m - 1):
        a = math.atan2(dense[i][1] - dense[i - 1][1], dense[i][0] - dense[i - 1][0])
        b = math.atan2(dense[i + 1][1] - dense[i][1], dense[i + 1][0] - dense[i][0])
        turn[i] = abs((b - a + math.pi) % (2 * math.pi) - math.pi)
    total_len = sum(seg) or 1.0
    total_turn = sum(turn) or 1.0
    acc = [0.0]
    for i in range(m - 1):
        acc.append(acc[-1] + (1 - bias) * seg[i] / total_len + bias * 0.5 * (turn[i] + turn[i + 1]) / total_turn)
    out = []
    for k in range(count):
        target = acc[-1] * k / (count - 1)
        j = 1
        while j < m - 1 and acc[j] < target:
            j += 1
        span = max(acc[j] - acc[j - 1], 1e-12)
        f = min(max((target - acc[j - 1]) / span, 0.0), 1.0)
        a, b = dense[j - 1], dense[j]
        out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    out[0], out[-1] = tuple(points[0]), tuple(points[-1])
    return out


def crozier(k: int, height: float, top: float):
    """Knot k's G in studs: (u, v) from its root on the pool (v = 0) to its top (v = top), a kind per point
    ('out' or 'mouth', where the contour is light), and the pale's spine and half-widths."""
    t = G_BLEND[k]
    counts = (8, 5, 16, 6) if height >= 3.0 else (7, 5, 14, 6)
    poly, kinds = [], []
    for big, small, count, kind in zip(G_BIG, G_SMALL, counts, G_KINDS):
        a, b = resample_curvy(big, count), resample_curvy(small, count)
        pts = [(p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t) for p, q in zip(a, b)]
        poly += pts[:-1]
        kinds += [kind] * (len(pts) - 1)
    poly = [(u * top, v * top) for u, v in poly]
    # Mouth points closer than a contour weight would fold the offset: keep one of each such pair.
    keep = [0]
    for i in range(1, len(poly)):
        if kinds[i] == "mouth" and math.dist(poly[i], poly[keep[-1]]) < 0.11 and i < len(poly) - 1:
            continue
        keep.append(i)
    poly, kinds = [poly[i] for i in keep], [kinds[i] for i in keep]
    spine = [((p[0] + (q[0] - p[0]) * t) * top, (p[1] + (q[1] - p[1]) * t) * top) for p, q in zip(G_STREAK_BIG, G_STREAK_SMALL)]
    widths = [w * top * (1.0 + 0.3 * t) for w in G_STREAK_W]
    return poly, kinds, spine, widths


# --- the side tongues: flame licks after ref-2's front view --------------------------------------

# A lick: a teardrop that swells outward (+u) low down, narrows into a neck and rises to a sharp tip that
# points up, a last flick outward at the very top. (u, v) in units of its height; root at v = 0.
LICK_OUTER = [(0.0, 0.0), (0.1, 0.05), (0.2, 0.15), (0.265, 0.29), (0.285, 0.42), (0.265, 0.55), (0.21, 0.68),
              (0.155, 0.8), (0.135, 0.9), (0.16, 1.0)]
LICK_INNER = [(0.16, 1.0), (0.108, 0.935), (0.083, 0.83), (0.075, 0.71), (0.062, 0.57), (0.03, 0.43), (-0.015, 0.29),
              (-0.045, 0.15), (-0.04, 0.0)]


def _u_at(poly, v):
    for i in range(1, len(poly)):
        a, b = poly[i - 1], poly[i]
        lo, hi = min(a[1], b[1]), max(a[1], b[1])
        if lo - 1e-9 <= v <= hi + 1e-9 and hi > lo:
            return a[0] + (b[0] - a[0]) * (v - a[1]) / (b[1] - a[1])
    return poly[-1][0]


def lick(h: float, points: int, lean: float, belly: float):
    """A side tongue in studs (u outward, v up, h its height): its outline, a kind per point and the pale's
    spine and half-widths. `lean` tips its top outward a little; `belly` swells it across."""
    outer = resample_curvy(LICK_OUTER, (points + 2) // 2, 0.3)
    inner = resample_curvy(LICK_INNER, points - (points + 2) // 2 + 1, 0.3)

    def shape(p):
        u, v = p
        return ((u * belly + (lean - 1.0) * 0.25 * v * v) * h, v * h)

    poly = [shape(p) for p in outer + inner[1:-1]] + [shape(inner[-1])]
    kinds = ["out"] * len(poly)
    spine, widths = [], []
    for i in range(9):
        v = 0.1 + 0.72 * i / 8
        uo, ui = _u_at(LICK_OUTER, v), _u_at(LICK_INNER, v)
        spine.append(shape((0.56 * uo + 0.44 * ui, v)))
        widths.append(0.17 * (uo - ui) * belly * h * math.sin(math.pi * (i + 0.5) / 9.0) ** 0.5)
    return poly, kinds, spine, widths


# --- the ribbon on the page ----------------------------------------------------------------------


def pool_radius(height):
    return 0.35 + 0.28 * height


def centre_x(z):
    """The dash is straight; the hand is not: a small S between the pools, none on them."""
    return 0.14 * math.sin(math.pi * z / 4.0)


def base_half_width(z):
    t = min(max((1.0 - z) / 17.0, 0.0), 1.0)
    return 2.3 - 1.35 * t**0.8


def half_widths(z):
    w = base_half_width(z)
    for kz, height, _ in KNOTS:
        need = pool_radius(height) + 0.3
        bump = max(0.0, need - base_half_width(kz))
        w += bump * math.exp(-(((z - kz) / (0.8 * pool_radius(height))) ** 2))
    left = w * (1.0 + 0.05 * (fbm(0.35 * z, 0.3, SEED + 11) * 2.0 - 1.0))
    right = w * (1.0 + 0.05 * (fbm(0.35 * z, 0.3, SEED + 12) * 2.0 - 1.0))
    # The start rounds off under the head; the end runs dry into a point the bristles leave from.
    start = math.sqrt(max(0.0, 1.0 - ((z - (RIB_START - 1.4)) / 1.4) ** 2)) if z > RIB_START - 1.4 else 1.0
    end = 1.0 - 0.8 * smooth(-16.9, RIB_END, z)
    k = max(start, 0.35) * end
    return left * k, right * k


def rib_height(z):
    """The ribbon's top: the brush lifts as it runs dry."""
    return RIB_H - 0.1 * smooth(-16.6, RIB_END, z)


def ribbon_top(x, z):
    """The ribbon's top over the page at (x, z): flat over its middle half, sloping to its edges."""
    if z > RIB_START or z < RIB_END:
        return 0.0
    left, right = half_widths(z)
    c = centre_x(z)
    top = rib_height(z)
    if c - 0.5 * left <= x <= c + 0.5 * right:
        return top
    if x < c - left or x > c + right:
        return 0.0
    if x < c - 0.5 * left:
        return EDGE + (top - EDGE) * (x - (c - left)) / (0.5 * left)
    return EDGE + (top - EDGE) * ((c + right) - x) / (0.5 * right)


def ribbon_zs():
    zs = []
    z = RIB_START
    while z > RIB_END + 1e-6:
        zs.append(z)
        near = min(abs(z - kz) for kz, _, _ in KNOTS)
        if z > RIB_START - 1.6 or z < -16.4:
            step = 0.7
        elif near < 1.9:
            step = 1.3
        else:
            step = 1.5
        z -= step
    if RIB_END - zs[-1] > -0.25:
        zs.pop()
    zs.append(RIB_END)
    return zs


def build_ribbon(body: Mesh, ink: Mesh):
    """A low slab on the page, four corners a section: the edges on the page, the middle half flat. Its
    hull's foot lies on the page as the ribbon's contour."""
    zs = ribbon_zs()
    rings = []
    hull_rings = []
    for z in zs:
        left, right = half_widths(z)
        c = centre_x(z)
        top = rib_height(z)
        rings.append([body.vert((c - left, EDGE, z)), body.vert((c - 0.5 * left, top, z)),
                      body.vert((c + 0.5 * right, top, z)), body.vert((c + right, EDGE, z))])
        w = RIB_HULL
        hull_rings.append([(c - left - w, FLOOR, z), (c - 0.5 * left - 0.3 * w, top + w, z),
                           (c + 0.5 * right + 0.3 * w, top + w, z), (c + right + w, FLOOR, z)])
    up = (0.0, 1.0, 0.0)
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        facings = [(-1.0, 0.8, 0.0), up, (1.0, 0.8, 0.0), (0.0, -1.0, 0.0)]
        for e in range(4):
            f = (e + 1) % 4
            body.tri(a[e], a[f], b[f], facings[e])
            body.tri(a[e], b[f], b[e], facings[e])
    for ring, sign in ((rings[0], 1.0), (rings[-1], -1.0)):
        body.tri(ring[0], ring[1], ring[2], (0.0, 0.0, sign))
        body.tri(ring[0], ring[2], ring[3], (0.0, 0.0, sign))
    # The hull: pushed out, wound inward, its ends pushed past the caps.
    first = [(p[0], p[1], p[2] + RIB_HULL) for p in hull_rings[0]]
    last = [(p[0], p[1], p[2] - RIB_HULL) for p in hull_rings[-1]]
    hull_rings = [first] + hull_rings + [last]
    ids = [[ink.vert(p) for p in ring] for ring in hull_rings]
    for r in range(len(ids) - 1):
        a, b = ids[r], ids[r + 1]
        facings = [(1.0, -0.8, 0.0), (0.0, -1.0, 0.0), (-1.0, -0.8, 0.0), (0.0, 1.0, 0.0)]
        for e in range(4):
            f = (e + 1) % 4
            ink.tri(a[e], a[f], b[f], facings[e])
            ink.tri(a[e], b[f], b[e], facings[e])
    for ring, sign in ((ids[0], -1.0), (ids[-1], 1.0)):
        ink.tri(ring[0], ring[1], ring[2], (0.0, 0.0, sign))
        ink.tri(ring[0], ring[2], ring[3], (0.0, 0.0, sign))


# --- the head: a loaded dome of wet pigment, its dark core, drips and splatter -------------------

HEAD_C = (0.0, 2.75)
HEAD_SIDES = 16
HEAD_ACROSS, HEAD_ALONG = 2.2, 1.75  # its half-width across the dash and its half-length along it
CORE_SHARE = 0.56  # the loaded core's reach, in shares of the head's


def head_radius(phi):
    """The loaded head: round lobes, wider across the dash than along it. phi from +X toward +Z (back)."""
    ellipse = 1.0 / math.sqrt((math.cos(phi) / HEAD_ACROSS) ** 2 + (math.sin(phi) / HEAD_ALONG) ** 2)
    lobe = (0.5 + 0.5 * math.sin(5.0 * phi + 0.4)) ** 2
    return ellipse * (1.0 + 0.11 * lobe + 0.05 * (fbm(phi * 1.6, 0.4, SEED + 21) * 2.0 - 1.0))


def head_top(f):
    """The dome's top over the ribbon's, at a share f of the way out to the rim."""
    return RIB_H + 0.06 + 0.3 * (1.0 - f * f)


HEAD_MID = 0.62  # the dome's middle ring, in shares of the way out to the rim


def head_ring():
    """The dome's two rings, (x, z, y) a point: the middle one and the rim (on the ribbon or the page)."""
    if "head" not in _CACHE:
        mid, rim = [], []
        for k in range(HEAD_SIDES):
            phi = 2.0 * math.pi * k / HEAD_SIDES
            r = head_radius(phi)
            x, z = HEAD_C[0] + HEAD_MID * r * math.cos(phi), HEAD_C[1] + HEAD_MID * r * math.sin(phi)
            mid.append((x, z, head_top(HEAD_MID)))
            x, z = HEAD_C[0] + r * math.cos(phi), HEAD_C[1] + r * math.sin(phi)
            rim.append((x, z, max(ribbon_top(x, z) + 0.06, EDGE)))
        _CACHE["head"] = (mid, rim)
    return _CACHE["head"]


def _bary_y(p, a, b, c):
    d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(d) < 1e-12:
        return None
    l1 = ((b[1] - c[1]) * (p[0] - c[0]) + (c[0] - b[0]) * (p[1] - c[1])) / d
    l2 = ((c[1] - a[1]) * (p[0] - c[0]) + (a[0] - c[0]) * (p[1] - c[1])) / d
    l3 = 1.0 - l1 - l2
    if min(l1, l2, l3) < -1e-9:
        return None
    return l1 * a[2] + l2 * b[2] + l3 * c[2]


def dome_y(x, z):
    """The head dome's top at (x, z), read off its own triangles; None off the dome."""
    mid, rim = head_ring()
    centre = (HEAD_C[0], HEAD_C[1], head_top(0.0))
    for k in range(HEAD_SIDES):
        j = (k + 1) % HEAD_SIDES
        for a, b, c in ((centre, mid[k], mid[j]), (mid[k], rim[k], rim[j]), (mid[k], rim[j], mid[j])):
            y = _bary_y((x, z), a, b, c)
            if y is not None:
                return y
    return None


def under(x, z):
    """What a decal lies on at (x, z): the ribbon, and the head's dome over it."""
    y = ribbon_top(x, z)
    d = dome_y(x, z)
    return y if d is None else max(y, d)


def build_head(body: Mesh, ink: Mesh):
    """The head: a lobed dome of pigment (closed under), its contour on the page and the ribbon, and its
    one dark hollow -- the loaded core -- lying on the dome."""
    up, down = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)
    top = body.vert((HEAD_C[0], head_top(0.0), HEAD_C[1]))
    ring_mid, ring_rim = head_ring()
    mid = [body.vert((x, y, z)) for x, z, y in ring_mid]
    rim = [body.vert((x, y, z)) for x, z, y in ring_rim]
    bottom = body.vert((HEAD_C[0], EDGE, HEAD_C[1]))
    for k in range(HEAD_SIDES):
        j = (k + 1) % HEAD_SIDES
        body.tri(top, mid[k], mid[j], up)
        body.tri(mid[k], rim[k], rim[j], up)
        body.tri(mid[k], rim[j], mid[j], up)
        body.tri(bottom, rim[j], rim[k], down)
    # The contour: a band of ink round the rim, from under the pigment to past it.
    inner, outer = [], []
    for k in range(HEAD_SIDES):
        phi = 2.0 * math.pi * k / HEAD_SIDES
        r = head_radius(phi)
        for rr, into in ((r - 0.12, inner), (r + RIB_HULL, outer)):
            x, z = HEAD_C[0] + rr * math.cos(phi), HEAD_C[1] + rr * math.sin(phi)
            y = max(ribbon_top(x, z) + LIFT, FLOOR)
            into.append(ink.vert((x, y, z)))
    for k in range(HEAD_SIDES):
        j = (k + 1) % HEAD_SIDES
        ink.tri(inner[k], outer[k], outer[j], up)
        ink.tri(inner[k], outer[j], inner[j], up)
    # The loaded core: a lobed pool of ink on the dome, a little back from its middle.
    sides = 14
    cx, cz = HEAD_C[0] - 0.05, HEAD_C[1] + 0.12
    centre = ink.vert((cx, under(cx, cz) + LIFT, cz))
    ring = []
    for k in range(sides):
        phi = 2.0 * math.pi * k / sides
        r = CORE_SHARE * head_radius(phi) * (1.0 + 0.1 * math.sin(4.0 * phi + 1.3))
        x, z = cx + r * math.cos(phi), cz + r * math.sin(phi)
        ring.append(ink.vert((x, under(x, z) + LIFT, z)))
    for k in range(sides):
        ink.tri(centre, ring[k], ring[(k + 1) % sides], up)


def flat_strip(ink: Mesh, points, widths, lift, floor=None):
    """A tapered strip of ink lying on whatever is under it (the page, the ribbon, the head). A zero last
    width ends it on a point (one triangle, no sliver)."""
    count = len(points)
    lefts, rights = [], []
    for i, (x, z) in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, count - 1)]
        tx, tz = unit2(b[0] - a[0], b[1] - a[1])
        nx, nz = -tz, tx
        h = widths[i] / 2.0
        if h <= 1e-9:
            v = ink.vert((x, floor if floor is not None else max(under(x, z) + lift, FLOOR), z))
            lefts.append(v)
            rights.append(v)
            continue
        for sx, into in ((1.0, lefts), (-1.0, rights)):
            px, pz = x + nx * h * sx, z + nz * h * sx
            into.append(ink.vert((px, floor if floor is not None else max(under(px, pz) + lift, FLOOR), pz)))
    up = (0.0, 1.0, 0.0)
    for i in range(count - 1):
        if lefts[i] != rights[i]:
            ink.tri(lefts[i], rights[i], lefts[i + 1], up)
        if rights[i + 1] != lefts[i + 1]:
            ink.tri(rights[i], rights[i + 1], lefts[i + 1], up)


def bead(ink: Mesh, x, z, r):
    """A round bead of ink on the page: a low eight-sided dome."""
    y0 = max(under(x, z) + 0.0, FLOOR)
    top = ink.vert((x, y0 + 0.45 * r, z))
    ring = [ink.vert((x + r * math.cos(2 * math.pi * k / 8), y0, z + r * math.sin(2 * math.pi * k / 8))) for k in range(8)]
    for k in range(8):
        ink.tri(top, ring[k], ring[(k + 1) % 8], (0.0, 1.0, 0.0))


def build_drips_and_splatter(ink: Mesh):
    rng = Rng(SEED + 31)
    # Drips: the loaded core runs forward down the dome and along the ribbon.
    for x0, length, width in ((-1.0, 2.1, 0.42), (0.85, 2.6, 0.38), (-0.15, 1.5, 0.34)):
        z0 = HEAD_C[1] - 0.6
        pts, widths = [], []
        for i in range(6):
            s = i / 5
            pts.append((x0 + 0.15 * math.sin(2.2 * s + x0), z0 - length * s))
            widths.append(width * (1.0 - s) ** 0.7)
        flat_strip(ink, pts, widths, LIFT + 0.01)
    # Splatter: round beads flung round the back and the sides of the head.
    for phi_deg, gap, r in ((-28, 0.55, 0.26), (22, 0.85, 0.2), (62, 0.6, 0.24), (118, 0.7, 0.2), (158, 0.95, 0.28), (205, 0.5, 0.22)):
        phi = math.radians(phi_deg + 6.0 * (rng.random() - 0.5))
        d = head_radius(phi) + RIB_HULL + gap
        x, z = HEAD_C[0] + d * math.cos(phi), HEAD_C[1] + d * math.sin(phi)
        reach = math.hypot(x, z)
        if reach > 4.75 - r:
            x, z = x * (4.75 - r) / reach, z * (4.75 - r) / reach
        bead(ink, x, z, r)


# --- the pools and the flow lines ----------------------------------------------------------------


def build_pools(ink: Mesh):
    """The server's five burning pools: a thin broken ring of ink round each knot's root, two brush arcs
    of uneven sweep, open where the dash runs through."""
    for k, (kz, height, _) in enumerate(KNOTS):
        rng = Rng(SEED + 41 + k)
        r0 = pool_radius(height)
        c = (centre_x(kz), kz)
        arcs = [(math.radians(-62 + 10 * rng.random()), math.radians(64 + 12 * rng.random())),
                (math.radians(112 + 12 * rng.random()), math.radians(252 + 10 * rng.random()))]
        for a0, a1 in arcs:
            segs = 7 if height >= 3.0 else 5
            pts, widths = [], []
            for i in range(segs + 1):
                s = i / segs
                a = a0 + (a1 - a0) * s
                r = r0 * (1.0 + 0.04 * math.sin(3.0 * a + k))
                pts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))
                widths.append(0.0 if i == segs else (0.1 + 0.09 * math.sin(math.pi * min(s, 0.999)) ** 0.7))
            flat_strip(ink, pts, widths, LIFT)


def build_flow_lines(ink: Mesh):
    """Three calligraphic lines along the dash, of unequal lengths, never parallel."""
    lines = [
        ([(1.1, 0.9), (1.25, -1.8), (0.95, -4.6), (0.7, -6.6)], 0.2),
        ([(-1.0, -2.6), (-0.75, -6.0), (-0.55, -9.5), (-0.8, -13.2)], 0.17),
        ([(0.75, -9.4), (0.5, -11.8), (0.4, -14.6)], 0.15),
    ]
    for ctrl, width in lines:
        pts = catmull(ctrl, 3)
        n = len(pts)
        widths = [width * max(0.2, math.sin(math.pi * min(1.0, (0.03 + 0.94 * i / (n - 1)) / 0.98)) ** 0.7) for i in range(n)]
        widths[-1] = 0.0
        flat_strip(ink, [(p[0], p[1]) for p in pts], widths, LIFT)


# --- the dry tail --------------------------------------------------------------------------------


def bristle(body: Mesh, ink: Mesh, ctrl, width, height, segs, weight):
    """A dry bristle lying on the page: a low tent (two faces up, one down) tapering to a point, closed at
    its root, and the contour under it -- a strip of ink on the page a weight wider on each side and a
    weight past its tip."""
    dense = catmull(ctrl, 12)
    acc = [0.0]
    for i in range(1, len(dense)):
        acc.append(acc[-1] + math.dist(dense[i - 1], dense[i]))
    pts = []
    for k in range(segs + 1):
        target = acc[-1] * k / segs
        j = 1
        while j < len(acc) - 1 and acc[j] < target:
            j += 1
        f = min(max((target - acc[j - 1]) / max(acc[j] - acc[j - 1], 1e-12), 0.0), 1.0)
        a, b = dense[j - 1], dense[j]
        pts.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    rows, tangents = [], []
    for i, (x, z) in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, segs)]
        tx, tz = unit2(b[0] - a[0], b[1] - a[1])
        tangents.append((tx, tz))
        nx, nz = -tz, tx
        s = i / segs
        h = 0.5 * width * (1.0 - s) ** 0.85
        y = height * (1.0 - s) ** 0.6
        if i == segs:
            rows.append([body.vert((x, BRISTLE_Y, z))] * 3)
            continue
        rows.append([body.vert((x + nx * h, BRISTLE_Y, z + nz * h)), body.vert((x, BRISTLE_Y + y, z)),
                     body.vert((x - nx * h, BRISTLE_Y, z - nz * h))])
    for r in range(segs):
        a, b = rows[r], rows[r + 1]
        for e in range(3):
            f = (e + 1) % 3
            if e == 2:
                facing = (0.0, -1.0, 0.0)
            else:
                pa, pf = body.verts[a[e]], body.verts[a[f]]
                facing = ((pa[0] + pf[0]) / 2 - pts[r][0], 1.0, (pa[2] + pf[2]) / 2 - pts[r][1])
            body.tri(a[e], a[f], b[f], facing)
            if b[e] != b[f]:
                body.tri(a[e], b[f], b[e], facing)
    tx, tz = tangents[0]
    body.tri(rows[0][0], rows[0][1], rows[0][2], (-tx, 0.0, -tz))
    # The contour on the page.
    tip = pts[-1]
    tx, tz = tangents[-1]
    under_pts = pts + [(tip[0] + tx * weight * 1.2, tip[1] + tz * weight * 1.2)]
    widths = [width * (1.0 - i / segs) ** 0.85 + 2.0 * weight * (1.0 - 0.25 * i / segs) for i in range(segs + 1)] + [0.0]
    flat_strip(ink, under_pts, widths, 0.0, floor=FLOOR)


def build_tail(body: Mesh, ink: Mesh):
    """The dry tail: past the last pool the brush runs dry and the ribbon's end splits into thin bristles,
    combed one way in a narrow fan, of uneven lengths; dry hairs of pure ink lie between them."""
    rng = Rng(SEED + 51)
    count = 10
    roots = []
    for i in range(count):
        f = (i + 0.5) / count * 2.0 - 1.0
        x0 = 0.78 * f + 0.05 * (rng.random() - 0.5)
        z0 = -16.2 - 0.6 * rng.random()
        angle = math.radians(17.0) * f + math.radians(2.5) * (rng.random() - 0.5)
        # Uneven lengths: the middle ones reach the trail's end, the outer ones fall short, unevenly.
        short = 1.4 * abs(f) ** 1.4 + 0.9 * rng.random() * (0.3 + abs(f))
        end_z = Z_TAIL + short
        length = (z0 - end_z) / math.cos(angle)
        x1, z1 = x0 + length * math.sin(angle), z0 - length * math.cos(angle)
        # Combed: every bristle bows the same way (toward +X), by its own amount, so none crosses another.
        bow = 0.12 + 0.14 * rng.random()
        nx, nz = math.cos(angle), math.sin(angle)
        ctrl = [(x0, z0)]
        for t in (0.3, 0.6, 0.85):
            px, pz = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
            b = bow * math.sin(math.pi * t)
            ctrl.append((px + nx * b, pz + nz * b))
        ctrl.append((x1, z1))
        width = 0.17 + 0.12 * rng.random()
        bristle(body, ink, ctrl, width, 0.05, 5, CONTOUR_MIN)
        roots.append((x0, z0, x1, z1, bow, angle))
    # Dry hairs of pure ink between some neighbours.
    for i in (1, 3, 6, 8):
        a, b = roots[i], roots[i + 1]
        x0, z0 = (a[0] + b[0]) / 2, -17.4 - 0.4 * rng.random()
        x1, z1 = (a[2] + b[2]) / 2, max(a[3], b[3]) + 0.5 + 0.6 * rng.random()
        angle = (a[5] + b[5]) / 2
        bow = (a[4] + b[4]) / 2
        nx, nz = math.cos(angle), math.sin(angle)
        pts = []
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            px, pz = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
            bb = bow * math.sin(math.pi * t)
            pts.append((px + nx * bb, pz + nz * bb))
        widths = [0.11 * (1.0 - t) ** 0.6 for t in (0.0, 0.25, 0.5, 0.75)] + [0.0]
        flat_strip(ink, pts, widths, 0.0, floor=FLOOR + 0.004)


# --- the knots -----------------------------------------------------------------------------------


def contour_weights(poly, kinds, top):
    return [W_TIP if kind == "mouth" else W_ROOT + (W_TIP - W_ROOT) * min(1.0, max(0.0, p[1] / top)) for p, kind in zip(poly, kinds)]


def lick_frames(tongues):
    """The side licks: (direction of the lick's u in the page, from +X toward +Z, degrees; its height as a
    share of the knot's). Leaning out on both sides of the crozier's faces, as in ref-2's front and side
    views; never in the crozier's own plane."""
    if tongues == 4:
        return [(35.0, 0.74), (215.0, 0.8), (150.0, 0.58)]
    return [(35.0, 0.74), (215.0, 0.8)]


def build_knot(body: Mesh, core: Mesh, ink: Mesh, k: int, kz: float, height: float, tongues: int):
    rng = Rng(SEED + 101 * k)
    cx = centre_x(kz)
    base_y = under(cx, kz) + 0.02
    thickness = 0.1 + 0.008 * height

    # The main tongue: the crozier, its plane turned from the dash toward +X so it shows a face both to
    # the side and to the thrower behind; its hook curls forward, down the dash (ref-1).
    yaw = MAIN_YAW + math.radians(6.0) * (rng.random() - 0.5)
    u = (math.sin(yaw), 0.0, -math.cos(yaw))
    frame = Frame((cx, base_y, kz), u, 1.1 * height)
    top = height - base_y
    outline, kinds, spine, widths = crozier(k, height, top)
    outline, _ = slab(body, ink, frame, outline, thickness, contour_weights(outline, kinds, top))
    lens = fit_lens(spine, widths, outline)
    if lens:
        lens_on_faces(core, frame, lens, thickness)

    # The side licks: flames leaning out from the knot's centre, their tips pointing up.
    points = 11 if height >= 3.0 else 10
    for theta_deg, ratio in lick_frames(tongues):
        theta = math.radians(theta_deg + 8.0 * (rng.random() - 0.5))
        h = top * (ratio + 0.05 * (rng.random() - 0.5))
        r = (math.cos(theta), 0.0, math.sin(theta))
        origin = (cx + r[0] * 0.14 * height, base_y, kz + r[2] * 0.14 * height)
        f = Frame(origin, r, 1.8 * h)
        belly = 1.0 + 0.15 * (4.5 - height) / 2.5
        shape, lk, lspine, lwidths = lick(h, points, 1.0 + 0.12 * rng.random(), belly)
        shape, _ = slab(body, ink, f, shape, thickness * 0.9, contour_weights(shape, lk, h))
        lens = fit_lens(lspine, lwidths, shape)
        if lens:
            lens_on_faces(core, f, lens, thickness * 0.9)


# --- the three meshes ----------------------------------------------------------------------------

_CACHE: dict = {}


def build():
    if _CACHE:
        return _CACHE["meshes"]
    FOLDS.clear()
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    build_ribbon(body, ink)
    build_tail(body, ink)
    build_head(body, ink)
    build_drips_and_splatter(ink)
    build_pools(ink)
    build_flow_lines(ink)
    for k, (kz, height, tongues) in enumerate(KNOTS):
        build_knot(body, core, ink, k, kz, height, tongues)
    meshes = (body, core, ink)
    # The trail is exactly the server's: the head's back at +5, the tail's tip at -21. Only the head's
    # and the tail's own stretches are eased onto those ends; the pools stay where the server puts them.
    zs = [v[2] for m in meshes for v in m.verts]
    zmax, zmin = max(zs), min(zs)
    for m in meshes:
        out = []
        for x, y, z in m.verts:
            if z > 2.0:
                z = 2.0 + (z - 2.0) * (Z_HEAD - 2.0) / (zmax - 2.0)
            elif z < -17.0:
                z = -17.0 + (z + 17.0) * (Z_TAIL + 17.0) / (zmin + 17.0)
            out.append(reach_clamp(x, y, z))
        m.verts = [(x * STUD, y * STUD, z * STUD) for x, y, z in out]
    _CACHE["meshes"] = meshes
    return meshes


def reach_clamp(x, y, z):
    """Never past the harm: a point beyond 5 studs (across the page) of every pool is drawn back onto the
    nearest pool's reach."""
    kz = min((k for k, _, _ in KNOTS), key=lambda k: abs(z - k))
    d = math.hypot(x, z - kz)
    if d > 5.0:
        x, z = x * 5.0 / d, kz + (z - kz) * 5.0 / d
    return (x, y, z)


def meta(seed):
    return {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def tie_body():
    return build()[0], meta(SEED)


def tie_core():
    return build()[1], meta(SEED + 1)


def tie_ink():
    return build()[2], meta(SEED + 2)
