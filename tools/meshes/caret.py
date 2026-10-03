"""The Caret's two bodies (Orpiment, D-273 look): the proofreader's insertion mark, and the departure strike.

Drawn after the developer's in-game shot (docs/vfx/caret/ref-1.jpg; there is no model sheet). The shot is
taken from IN FRONT of the thrower: his face is toward the camera and the departure strike lies far behind
him. It shows the front side of a gold ^ standing between the camera and him -- a thin rising stroke on the
viewer's left (the delie), a heavy falling stroke on the viewer's right (the plein) that lands in a bracketed
serif (a cove into a short square spur, a long concave sweep out to a short square end), a heavy ink contour
all round and under the feet, one pale line down the middle of each stroke (both start above the notch and
run up under the point), and in the serif a pale flourish (an "A" with a flag on its top, a hooked bar, a
base stroke curling up); and, away from it, the departure's horizontal strike, a long thin gold bar whose
tail splits dry in two strands under a pointed ink tail.

The art bible's construction (Caret section): at the arrival a large gold ^ of two K3 strokes, the feet
either side of the thrower (+-2.5 studs = ClearanceRadius), the point above the head, no Spin; at the
departure a horizontal K3 strike, triangle section, across the spot left.

The shot and the bible disagree on size (the shot's ^ is about 11 studs wide round a crouching avatar; the
bible holds the feet to +-2.5 = ClearanceRadius), and the body follows the shot:

  caret_wide_body / caret_wide_core / caret_wide_ink -- the ^, posed at Width 11 studs, 55.5 degrees at the
      point, the gold point at 9.4 and the notch at 8.3 (a standing 6.2-stud avatar's head free in the
      opening), standing 1 stud in front of him (-Z) as in the shot, the delie on the FRONT viewer's left;
      readable from both sides. It needs the bible's +-2.5 amended (to be recorded in docs/DECISIONS.md),
      and it reaches past the server's clearance sphere, into whatever stands 2.5 to 5.5 studs to his sides.
  rature_body / rature_core / rature_ink -- the strike (Width: its length, ink included, is 1, posed at 5
      studs; pivot at its middle, where the thrower's root was; axis Y).

Roblox space: X right, Y up, forward -Z; the thrower's camera is behind (+Z).

The ^ is a letter cut out of a slab. Its outline in the XY plane is the silhouette, a knife edge at z = 0.
Each face is a shallow dish: from the knife edge a bevel rises to a lip, then a short wall steps down onto
the flat floor of the face, a plane that is a little deeper at the feet than at the point. The pale lines
lie on that floor, lifted less than the lip is high, so seen edge-on from any side the lip hides them: the
core is always ringed by pigment and never at the outer edge (bible, section 2). Every ring of the slab
(knife edge, lip, floor) and of the contour (rim, faces) is an offset of the one outline, vertex for
vertex, and is refused if any of its edges turns back or the ring crosses itself or leaves the one
around it: the outline places no vertex inside the reach of a sharp corner's mitre, so no ring folds and
no vertex is drawn onto another. The faces are triangulated by ear clipping, then edge flips to the
fattest triangles. The gold stands on its contour, which runs under the feet as heavy as round them.
The contour is the outline grown by the ink's weight (heavier on the outer edges and the feet, lighter
in the notch, tapering into the point), mitred everywhere: at the notch one simple V wedge, whose faces
close on the rim's own tip, shallow, so that seen from three quarters the near wall of one stroke's
contour does not stand in front of the other stroke; at the point one tip that is the rim's and both
faces' own vertex, so the contour ends in a single point from every angle. The ^ carries no ink flow
lines: the shot draws none (to be logged in DECISIONS).
"""

from __future__ import annotations

import math

from strokes import FLOOR_CLEARANCE, Mesh, Volume, emit, fbm, inverted_hull

WIDE_SEED = 3927

# --- the two builds, in studs ---------------------------------------------------------------------
# A build is the letter's construction at its posed size. The serif's and the flourish's own sizes scale
# with `k` (the letter's height against the bible build's).
BIBLE = {
    "name": "bible",
    "apex_y": 7.5,  # the gold point (7.58 over the floor with the foot lift), over a 6.2-stud head
    "foot_l": -2.36,  # the delie's outer foot (gold)
    "tip_r": 2.36,  # the serif's right tip (gold)
    "delie_w": (0.27, 0.33),  # the delie's width across the stroke: at its foot, at the apex
    "plein_w": 0.58,  # the plein's width across the stroke
    "spur": 0.6,  # how far the serif's left spur reaches past the stem's inner edge
    "sweep": 0.6,  # how far its right sweep reaches past the stem's outer edge
    "fillet_r": 0.34,  # the cove between the stem's inner edge and the spur
    "sweep_y": 1.3,  # where the stem's outer edge leaves its line into the sweep (a sixth of the height, as the shot)
    "spur_h": 0.12,  # the spur's square end
    "tip_h": 0.09,  # the sweep's square end: about a seventh of the stem, as the shot squares it
    "foot_lift": 0.155,  # the gold stands on its contour: the ink under the feet is as heavy as round them
    "bevel": 0.045,  # knife edge to lip, across
    "dish": 0.04,  # lip to floor, across
    "lip": 0.06,  # the lip over the floor
    "lift": 0.03,  # the pale lines over the floor (bible: 0.03 to 0.08): under the lip
    "depth": (0.12, 0.07),  # the floor's half depth at the feet and at the point
    "ink": {"delie_out": 0.14, "delie_in": 0.12, "notch": 0.12, "plein_in": 0.12, "cove": 0.15, "spur": 0.15,
            "floor": 0.15, "tip": 0.13, "sweep": 0.15, "plein_out": 0.15, "foot_d": 0.15},
    "ink_tip": 0.3,  # how far the contour's point stands over the gold point
    "ink_face": 0.85,  # how far the contour's faces grow out in the plane, in weights
    "ink_depth": 0.75,  # how far they stand off the lip, in weights
    "apex_near": 0.5,  # the last outline vertex before the point, on each leg (outside every mitre's reach)
    "legs": (0.3, 0.55, 0.79),  # the other vertices down each outer leg, as shares of its length
    "inner_parts": 4,  # the spans along each inner edge
    "floor_parts": 2,  # the spans along the serif's floor
    "apex_ink_depth": 0.05,  # more depth for the contour's faces beside the point, where they close to it
    "notch_ink_depth": 0.45,  # the depth of the notch wedge's tip, over the floor, in lips
    "k": 1.0,
    "plane_z": 0.9,  # behind the thrower's back: his camera draws it over him
    "mirror": False,  # the delie on the thrower's left
}

WIDE = dict(BIBLE)
WIDE.update({
    "name": "wide",
    "apex_y": 9.2,
    "foot_l": -5.25,
    "tip_r": 5.3,
    "delie_w": (0.33, 0.38),
    "plein_w": 0.68,
    "spur": 0.86,
    "sweep": 0.85,
    "fillet_r": 0.38,
    "sweep_y": 1.65,
    "spur_h": 0.14,
    "tip_h": 0.11,
    "foot_lift": 0.185,
    "bevel": 0.05,
    "dish": 0.045,
    "lip": 0.07,
    "lift": 0.035,
    "depth": (0.14, 0.08),
    "ink": {"delie_out": 0.17, "delie_in": 0.15, "notch": 0.15, "plein_in": 0.15, "cove": 0.18, "spur": 0.18,
            "floor": 0.18, "tip": 0.15, "sweep": 0.18, "plein_out": 0.18, "foot_d": 0.18},
    "ink_tip": 0.36,
    "apex_near": 0.55,
    "legs": (0.24, 0.43, 0.62, 0.81),
    "inner_parts": 5,
    "k": 1.23,
    "plane_z": -1.0,  # in front of him, as the shot stands it
    "mirror": True,  # the delie on the front viewer's left, as the shot reads
})


# --- 2D helpers -----------------------------------------------------------------------------------


def v2sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def v2add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def v2mul(a, k):
    return (a[0] * k, a[1] * k)


def v2len(a):
    return math.hypot(a[0], a[1])


def v2unit(a):
    n = v2len(a) or 1.0
    return (a[0] / n, a[1] / n)


def v2cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def v2dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def lerp2(a, b, f):
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)


def intersect(p, d, q, e):
    """Where the line p + t d meets the line q + s e."""
    t = v2cross(v2sub(q, p), e) / v2cross(d, e)
    return v2add(p, v2mul(d, t))


def bezier(p0, p1, p2, p3, n):
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1.0 - t
        out.append(tuple(u**3 * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t**3 * p3[k] for k in range(2)))
    return out


def area(poly):
    return 0.5 * sum(v2cross(poly[i - 1], poly[i]) for i in range(len(poly)))


def segments_cross(a, b, c, d):
    def orient(p, q, r):
        return v2cross(v2sub(q, p), v2sub(r, p))

    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0) and min(abs(o1), abs(o2), abs(o3), abs(o4)) > 1e-14


def simple(poly) -> bool:
    n = len(poly)
    for i in range(n):
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            if segments_cross(poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n]):
                return False
    return True


def winding(poly, p) -> int:
    wn = 0
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if a[1] <= p[1] < b[1] and v2cross(v2sub(b, a), v2sub(p, a)) > 0:
            wn += 1
        elif b[1] <= p[1] < a[1] and v2cross(v2sub(b, a), v2sub(p, a)) < 0:
            wn -= 1
    return wn


def edge_distance(poly, p) -> float:
    best = 1e9
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        e = v2sub(b, a)
        t = max(0.0, min(1.0, v2dot(v2sub(p, a), e) / max(v2dot(e, e), 1e-18)))
        best = min(best, v2len(v2sub(p, v2add(a, v2mul(e, t)))))
    return best


def inside(poly, p, margin=0.0) -> bool:
    return winding(poly, p) != 0 and edge_distance(poly, p) >= margin


def ear_clip(poly) -> list[tuple[int, int, int]]:
    """Triangles of a simple counter-clockwise polygon, by ear clipping, the fattest ear first."""
    idx = list(range(len(poly)))
    tris = []

    def contains(p, a, b, c):
        return v2cross(v2sub(b, a), v2sub(p, a)) >= -1e-14 and v2cross(v2sub(c, b), v2sub(p, b)) >= -1e-14 and v2cross(v2sub(a, c), v2sub(p, c)) >= -1e-14

    while len(idx) > 3:
        best = None
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if v2cross(v2sub(b, a), v2sub(c, b)) <= 1e-14:
                continue
            if any(contains(poly[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            angles = []
            for o, p, q in ((a, b, c), (b, c, a), (c, a, b)):
                u, v = v2sub(p, o), v2sub(q, o)
                angles.append(math.atan2(abs(v2cross(u, v)), v2dot(u, v)))
            if best is None or min(angles) > best[0]:
                best = (min(angles), k)
        if best is None:
            raise RuntimeError("ear clipping failed: polygon not simple")
        k = best[1]
        tris.append((idx[k - 1], idx[k], idx[(k + 1) % len(idx)]))
        idx.pop(k)
    tris.append(tuple(idx))
    return flip_to_fattest(poly, tris)


def min_angle(a, b, c) -> float:
    out = []
    for o, p, q in ((a, b, c), (b, c, a), (c, a, b)):
        u, v = v2sub(p, o), v2sub(q, o)
        out.append(math.atan2(abs(v2cross(u, v)), v2dot(u, v)))
    return min(out)


def flip_to_fattest(poly, tris):
    """Lawson flips inside the polygon: an inner edge whose two triangles make a convex quad is turned
    when that makes the thinner of the two fatter (the constrained Delaunay triangulation): ear clipping
    alone leaves needles along a straight leg's runs of vertices."""
    tris = [tuple(t) for t in tris]
    for _ in range(200):
        owner = {}
        for t, (a, b, c) in enumerate(tris):
            for u, w in ((a, b), (b, c), (c, a)):
                owner[(u, w)] = t
        changed = False
        for (u, w), t in list(owner.items()):
            s = owner.get((w, u))
            if s is None or s < t:
                continue
            p = next(x for x in tris[t] if x not in (u, w))
            q = next(x for x in tris[s] if x not in (u, w))
            # The quad u -> q -> w -> p must be strictly convex for the flip (p, q) to stay inside it.
            if v2cross(v2sub(poly[q], poly[p]), v2sub(poly[u], poly[p])) >= -1e-14 or v2cross(v2sub(poly[w], poly[p]), v2sub(poly[q], poly[p])) >= -1e-14:
                continue
            before = min(min_angle(*(poly[i] for i in tris[t])), min_angle(*(poly[i] for i in tris[s])))
            n1, n2 = (p, u, q), (p, q, w)
            if v2cross(v2sub(poly[n1[1]], poly[n1[0]]), v2sub(poly[n1[2]], poly[n1[0]])) <= 0:
                n1 = (n1[0], n1[2], n1[1])
            if v2cross(v2sub(poly[n2[1]], poly[n2[0]]), v2sub(poly[n2[2]], poly[n2[0]])) <= 0:
                n2 = (n2[0], n2[2], n2[1])
            after = min(min_angle(*(poly[i] for i in n1)), min_angle(*(poly[i] for i in n2)))
            if after > before + 1e-9:
                tris[t], tris[s] = n1, n2
                changed = True
                break
        if not changed:
            break
    return tris


def ray_chord(poly, i, direction) -> float:
    """How far a ray from vertex i along `direction` runs inside the polygon before it meets an edge that
    does not touch i: the local thickness there."""
    p = poly[i]
    n = len(poly)
    best = 1e9
    for j in range(n):
        if j == i or (j + 1) % n == i:
            continue
        a, b = poly[j], poly[(j + 1) % n]
        e = v2sub(b, a)
        den = v2cross(direction, e)
        if abs(den) < 1e-12:
            continue
        t = v2cross(v2sub(a, p), e) / den
        s = v2cross(v2sub(a, p), direction) / den
        if t > 1e-9 and -1e-9 <= s <= 1 + 1e-9:
            best = min(best, t)
    return best


def corner(poly, i):
    """At vertex i of a counter-clockwise polygon: the outward mitre direction, the cosine of half the turn
    (the mitre's stretch is 1 / that), and whether the corner is convex."""
    a, b, c = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
    e0, e1 = v2unit(v2sub(b, a)), v2unit(v2sub(c, b))
    n0, n1 = (e0[1], -e0[0]), (e1[1], -e1[0])
    s = v2add(n0, n1)
    if v2len(s) < 1e-9:
        return n0, 1.0, True
    m = v2unit(s)
    return m, v2dot(m, n0), v2cross(e0, e1) > 0


def offset_ring(poly, deltas, reflex_cap=None):
    """Every vertex moved off its two edges by deltas[i] (positive out, negative in), mitred. Going in at
    a sharp re-entrant corner (the notch), the mitre's stretch may be capped: there a full mitre runs the
    face's edge far up past the knife edge's, and seen from three quarters the two V's cross in a step."""
    out = []
    for i, p in enumerate(poly):
        m, cos_half, convex = corner(poly, i)
        stretch = 1.0 / max(cos_half, 0.12)
        if reflex_cap is not None and deltas[i] < 0 and not convex:
            stretch = min(stretch, reflex_cap)
        out.append(v2add(p, v2mul(m, deltas[i] * stretch)))
    return out


def inset_budget(poly, deltas, share=0.85):
    """Insets cut back so that no edge is eaten: going in at a convex corner slides the mitre back along
    both its edges by delta x tan(half the turn); the two ends of an edge may eat at most `share` of it."""
    n = len(poly)
    out = list(deltas)
    slide = []
    for i in range(n):
        m, cos_half, convex = corner(poly, i)
        slide.append(math.sqrt(max(1.0 - cos_half * cos_half, 0.0)) / max(cos_half, 0.12) if convex else 0.0)
    for _ in range(8):
        for i in range(n):
            j = (i + 1) % n
            length = v2len(v2sub(poly[j], poly[i]))
            eaten = out[i] * slide[i] + out[j] * slide[j]
            if eaten > share * length:
                f = share * length / eaten
                out[i] *= f if slide[i] > 0 else 1.0
                out[j] *= f if slide[j] > 0 else 1.0
    return out


def check_ring(name, base, ring, around=None, skip=()):
    """Refuse a ring that folds: an edge turned back against (or shrunk to nothing beside) the outline's,
    a ring that crosses itself, or one that leaves the ring it must stay inside."""
    n = len(base)
    for i in range(n):
        j = (i + 1) % n
        eb, er = v2sub(base[j], base[i]), v2sub(ring[j], ring[i])
        if i in skip or j in skip:
            continue
        if v2dot(eb, er) <= 0.08 * v2dot(eb, eb):
            raise RuntimeError(f"{name}: edge {i} turns back ({base[i]} -> {base[j]})")
    if not simple(ring):
        raise RuntimeError(f"{name}: the ring crosses itself")
    if around is not None:
        for i, p in enumerate(ring):
            if i not in skip and not inside(around, p, 1e-6):
                raise RuntimeError(f"{name}: vertex {i} {p} leaves the ring round it")
        for i in range(n):
            for j in range(n):
                if segments_cross(ring[i], ring[(i + 1) % n], around[j], around[(j + 1) % n]):
                    raise RuntimeError(f"{name}: edge {i} crosses the ring round it")


# --- the outline of the ^ -------------------------------------------------------------------------


def caret_outline(B):
    """The gold silhouette in studs, counter-clockwise from the delie's outer foot (the delie on -X), with
    a tag per vertex: which stretch of the letter it belongs to (for the ink's weight)."""
    apex = (0.0, B["apex_y"])
    foot = (B["foot_l"], 0.0)
    stem_out_foot = (B["tip_r"] - B["sweep"], 0.0)
    d_out = v2unit(v2sub(apex, foot))  # up the delie's outer edge
    n_d = (d_out[1], -d_out[0])  # into the delie
    p_out = v2unit(v2sub(stem_out_foot, apex))  # down the plein's outer edge
    n_p = (p_out[1], -p_out[0])  # into the plein
    dw0, dw1 = B["delie_w"]
    d_in_0 = v2add(foot, v2mul(n_d, dw0))
    d_in_dir = v2unit(v2sub(v2add(apex, v2mul(n_d, dw1)), d_in_0))
    foot_in = intersect(d_in_0, d_in_dir, (0.0, 0.0), (1.0, 0.0))
    p_in_0 = v2add(apex, v2mul(n_p, B["plein_w"]))
    notch = intersect(d_in_0, d_in_dir, p_in_0, p_out)
    stem_in_foot = intersect(p_in_0, p_out, (0.0, 0.0), (1.0, 0.0))
    sweep_0 = intersect(apex, p_out, (0.0, B["sweep_y"]), (1.0, 0.0))
    spur_x = stem_in_foot[0] - B["spur"]

    # The spur's bracket: a true arc tangent to the stem's inner edge and to the spur's level top.
    elbow = intersect(p_in_0, p_out, (0.0, B["spur_h"]), (1.0, 0.0))
    u1, u2 = (-p_out[0], -p_out[1]), (-1.0, 0.0)
    half = 0.5 * math.acos(max(-1.0, min(1.0, v2dot(u1, u2))))
    reach = B["fillet_r"] / math.tan(half)
    t1, t2 = v2add(elbow, v2mul(u1, reach)), v2add(elbow, v2mul(u2, reach))
    centre = v2add(elbow, v2mul(v2unit(v2add(u1, u2)), B["fillet_r"] / math.sin(half)))
    a1 = math.atan2(t1[1] - centre[1], t1[0] - centre[0])
    a2 = math.atan2(t2[1] - centre[1], t2[0] - centre[0])
    if a2 > a1:
        a2 -= 2.0 * math.pi
    if t2[0] - spur_x < 2.5 * B["bevel"] + 0.02:
        raise RuntimeError("the spur's top is too short for its bevel")

    pts: list[tuple[float, float]] = []
    tags: list[str] = []

    def put(p, tag):
        pts.append((float(p[0]), float(p[1])))
        tags.append(tag)

    def run(a, b, at, tag):
        """Points strictly between a and b, at the given distances from a (studs)."""
        length = v2len(v2sub(b, a))
        for s in at:
            if not 0.0 < s < length:
                raise RuntimeError(f"a vertex off its edge: {s} of {length}")
            put(lerp2(a, b, s / length), tag)

    def thirds(a, b, parts, tag):
        length = v2len(v2sub(b, a))
        run(a, b, [length * i / parts for i in range(1, parts)], tag)

    near = B["apex_near"]
    put(foot, "foot_d")
    put(foot_in, "foot_d")
    thirds(foot_in, notch, B["inner_parts"], "delie_in")
    put(notch, "notch")
    thirds(notch, t1, B["inner_parts"], "plein_in")
    put(t1, "plein_in")
    cove_arc = []
    for i in range(1, 5):
        a = a1 + (a2 - a1) * i / 5
        cove_arc.append((centre[0] + B["fillet_r"] * math.cos(a), centre[1] + B["fillet_r"] * math.sin(a)))
        put(cove_arc[-1], "cove")
    put(t2, "spur")
    put((spur_x, B["spur_h"]), "spur")  # the spur ends square, as the shot's does
    put((spur_x, 0.0), "spur")
    thirds((spur_x, 0.0), (B["tip_r"], 0.0), B["floor_parts"], "floor")
    put((B["tip_r"], 0.0), "tip")
    put((B["tip_r"], B["tip_h"]), "tip")  # the sweep ends square too, a seventh of the stem
    sweep = bezier((B["tip_r"], B["tip_h"]), (B["tip_r"] - 0.45 * B["sweep"] - 0.25 * B["k"], B["tip_h"] + 0.02 * B["k"]),
                   v2add(sweep_0, v2mul(p_out, 0.55 * B["sweep_y"] / max(-p_out[1], 1e-3))), sweep_0, 6)
    for p in sweep[:-1]:
        put(p, "sweep")
    put(sweep_0, "plein_out")
    plein_len = v2len(v2sub(apex, sweep_0))
    run(sweep_0, apex, [plein_len * (1.0 - f) for f in reversed(B["legs"])] + [plein_len - near], "plein_out")
    apex_index = len(pts)
    put(apex, "apex")
    delie_len = v2len(v2sub(foot, apex))
    run(apex, foot, [near] + [delie_len * f for f in B["legs"]], "delie_out")
    geometry = {"apex": apex, "notch": notch, "d_out": d_out, "n_d": n_d, "p_out": p_out, "n_p": n_p,
                "foot_in": foot_in, "stem_in_foot": stem_in_foot, "stem_out_foot": stem_out_foot,
                "spur_x": spur_x, "sweep_0": sweep_0, "cove": (t1, t2), "apex_index": apex_index}
    return pts, tags, geometry


# --- the slab -------------------------------------------------------------------------------------


class Slab:
    """A letter cut from a slab, in studs: the knife edge (the outline, z = 0), a lip ring and a floor ring
    on each face (offsets of the outline, vertex for vertex), and its contour (rim and faces, also offsets
    of the outline), every ring checked before a triangle is made."""

    def __init__(self, B, outline, tags, apex_index) -> None:
        if not (area(outline) > 0 and simple(outline)):
            raise RuntimeError("the outline is not a simple counter-clockwise polygon")
        self.B = B
        self.outline = outline
        self.tags = tags
        self.apex = apex_index
        n = len(outline)
        # How far each ring may go in: never past a share of the local thickness (the sweep's square end
        # is only a seventh of the stem high).
        room = []
        for i in range(n):
            m, cos_half, _ = corner(outline, i)
            room.append(ray_chord(outline, i, (-m[0], -m[1])) * cos_half)
        floor_in = inset_budget(outline, [min(B["bevel"] + B["dish"], 0.3 * r) for r in room])
        lip_in = [min(B["bevel"], 0.55 * f) for f in floor_in]
        self.lip = offset_ring(outline, [-d for d in lip_in], reflex_cap=1.3)
        self.floor = offset_ring(outline, [-d for d in floor_in], reflex_cap=1.3)
        check_ring("lip", outline, self.lip, around=outline)
        check_ring("floor", outline, self.floor, around=self.lip)
        self.floor_tris = ear_clip(self.floor)
        # The contour: the outline grown by the ink's weight at z = 0 (the rim), and, at each face, grown a
        # little less and lifted off the lip; the point is mitred to `ink_tip` over the gold point, and that
        # one tip is the rim's and both faces' own.
        w = [B["ink"].get(t, 0.0) for t in tags]
        m, cos_half, _ = corner(outline, apex_index)
        w[apex_index] = B["ink_tip"] * cos_half
        self.weights = w
        self.rim = offset_ring(outline, w)
        face_out = [B["ink_face"] * wi - li for wi, li in zip(w, lip_in)]
        self.ink_face = offset_ring(outline, face_out)
        self.ink_face[apex_index] = self.rim[apex_index]
        # The notch: one V wedge. The faces' V closes on the rim's own V (same place in the plane, at the
        # faces' depth), so seen from three quarters the wedge has one tip, not a fork of two.
        notch_index = tags.index("notch")
        self.ink_face[notch_index] = self.rim[notch_index]
        self.notch = notch_index
        check_ring("ink rim", outline, self.rim)
        check_ring("ink face", outline, self.ink_face, around=self.rim, skip=(apex_index, notch_index))
        for i, p in enumerate(outline):
            if i != apex_index and not inside(self.ink_face, p, 1e-6):
                raise RuntimeError(f"the contour's face leaves the gold at {p}")
        self.ink_tris = ear_clip(self.ink_face)

    def depth(self, y: float) -> float:
        """The floor's half depth at height y: a plane, deeper at the feet."""
        d0, d1 = self.B["depth"]
        return d0 + (d1 - d0) * y / self.B["apex_y"]

    def body(self) -> Mesh:
        mesh = Mesh("up")
        B, n = self.B, len(self.outline)
        rim = [mesh.vert((x, y, 0.0)) for x, y in self.outline]
        rings = {}
        for side in (1.0, -1.0):
            # The lip thins into the point, as a blade does, so the contour closing on its one tip keeps
            # its stand-off there.
            lip = [mesh.vert((x, y, side * (self.depth(y) + B["lip"] * (0.25 if i == self.apex else 1.0)))) for i, (x, y) in enumerate(self.lip)]
            floor = [mesh.vert((x, y, side * self.depth(y))) for x, y in self.floor]
            rings[side] = (lip, floor)
        for i in range(n):
            j = (i + 1) % n
            for side, (lip, floor) in rings.items():
                quads = ((rim[i], rim[j], lip[j], lip[i]), (lip[i], lip[j], floor[j], floor[i]))
                for a, b, c, d in quads:
                    tri(mesh, (a, b, c), side > 0)
                    tri(mesh, (a, c, d), side > 0)
        for side, (_, floor) in rings.items():
            for a, b, c in self.floor_tris:
                tri(mesh, (floor[a], floor[b], floor[c]), side > 0)
        return mesh

    def ink(self) -> Mesh:
        """The contour, wound inside out."""
        mesh = Mesh("up")
        B, n = self.B, len(self.outline)
        rim = [mesh.vert((x, y, 0.0)) for x, y in self.rim]
        faces = {}
        for side in (1.0, -1.0):
            ring = []
            for i, (x, y) in enumerate(self.ink_face):
                if i == self.apex:
                    ring.append(rim[i])
                    continue
                oy = self.outline[i][1]
                extra = B["apex_ink_depth"] if (i - self.apex) % n in (1, n - 1) else 0.0
                stand = B["lip"] + B["ink_depth"] * self.weights[i] + extra
                if i == self.notch:
                    # The wedge's tip stays shallow: a deep one, seen from three quarters, stands in front
                    # of the other stroke's bevel and draws a step into the V.
                    stand = B["notch_ink_depth"] * B["lip"]
                ring.append(mesh.vert((x, y, side * (self.depth(oy) + stand))))
            faces[side] = ring
        for i in range(n):
            j = (i + 1) % n
            for side, ring in faces.items():
                for a, b, c in ((rim[i], rim[j], ring[j]), (rim[i], ring[j], ring[i])):
                    if len({a, b, c}) == 3:
                        tri(mesh, (a, b, c), side < 0)
        for side, ring in faces.items():
            for a, b, c in self.ink_tris:
                tri(mesh, (ring[a], ring[b], ring[c]), side < 0)
        return mesh

    def on_floor(self, p, margin: float) -> bool:
        return inside(self.floor, p, margin)


def tri(mesh: Mesh, abc, front: bool) -> None:
    """A triangle in its built winding (front face, wound counter-clockwise seen from +Z) or reversed."""
    a, b, c = abc
    made = emit(mesh, a, b, c) if front else emit(mesh, a, c, b)
    if not made:
        raise RuntimeError(f"a degenerate triangle in the shell: {mesh.verts[a]} {mesh.verts[b]} {mesh.verts[c]}")


def strip(mesh: Mesh, slab: Slab, centre, widths, side: float) -> None:
    """A flat pale strip on the floor of one face along `centre`, lifted off it by the build's `lift`."""
    n = len(centre)
    lefts, rights = [], []
    for i, p in enumerate(centre):
        a, b = centre[max(i - 1, 0)], centre[min(i + 1, n - 1)]
        t = v2unit(v2sub(b, a))
        nrm = (-t[1], t[0])
        for q, into in ((v2add(p, v2mul(nrm, widths[i] / 2.0)), lefts), (v2sub(p, v2mul(nrm, widths[i] / 2.0)), rights)):
            into.append(mesh.vert((q[0], q[1], side * (slab.depth(q[1]) + slab.B["lift"]))))
    facing = (0.0, 0.0, side)
    for i in range(n - 1):
        mesh.tri(lefts[i], rights[i], lefts[i + 1], facing)
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1], facing)


def lens(n, width, start_taper=0.25, end_taper=0.25):
    """Widths of a stroke pressed in and lifted out: a lens, pointed at both ends."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        a = min(1.0, t / start_taper) if start_taper > 0 else 1.0
        b = min(1.0, (1.0 - t) / end_taper) if end_taper > 0 else 1.0
        out.append(width * math.sin(0.5 * math.pi * a) * math.sin(0.5 * math.pi * b))
    return out


# --- the ^ ----------------------------------------------------------------------------------------

_CACHE: dict = {}


def _caret(B):
    if B["name"] in _CACHE:
        return _CACHE[B["name"]]
    k = B["k"]
    pts, tags, g = caret_outline(B)
    lift_y = B["foot_lift"]
    outline = [(x, y + lift_y) for x, y in pts]
    slab = Slab(B, outline, tags, g["apex_index"])
    body, core, ink = slab.body(), Mesh("up"), slab.ink()

    apex, notch = g["apex"], g["notch"]
    n_d, p_out, n_p = g["n_d"], g["p_out"], g["n_p"]
    dw0, dw1 = B["delie_w"]

    def lifted(path):
        return [(x, y + lift_y) for x, y in path]

    def delie_point(f, across):
        """On the delie: f from its foot (0) to the apex (1), `across` its width from the outer edge."""
        o = lerp2((B["foot_l"], 0.0), apex, f)
        return v2add(o, v2mul(n_d, across * (dw0 + (dw1 - dw0) * f)))

    def plein_point(f, across):
        """On the plein: f from the apex (0) down its outer edge to the floor (1)."""
        o = lerp2(apex, g["stem_out_foot"], f)
        return v2add(o, v2mul(n_p, across * B["plein_w"]))

    margin = 0.015 * k

    def fits(path, width, a=0.25, b=0.3):
        """Whether a pale stroke lies on the floor of the face, its whole width and a margin inside it."""
        widths = lens(len(path), width, a, b)
        return all(slab.on_floor(q, 0.5 * w + margin) for q, w in zip(lifted(path)[1:-1], widths[1:-1]))

    def pale(path, width, side, a=0.25, b=0.3):
        if not fits(path, width, a, b):
            raise RuntimeError(f"a pale stroke leaves the floor: {path[0]} .. {path[-1]}")
        strip(core, slab, lifted(path), lens(len(path), width, a, b), side)

    def widest(make, width, lo, hi, a=0.25, b=0.3):
        """The stroke `make(reach)` with the largest reach in [lo, hi] that still lies on the floor."""
        best = None
        for i in range(41):
            reach = lo + (hi - lo) * i / 40
            if fits(make(reach), width, a, b):
                best = reach
        if best is None:
            raise RuntimeError("no room for a pale stroke")
        return make(best)

    stem_mid = lerp2(g["stem_in_foot"], g["stem_out_foot"], 0.5)[0]
    slope = -p_out[0] / p_out[1]

    def stem_c(y):
        return stem_mid - y * slope

    rise = apex[1] - notch[1]
    for side in (1.0, -1.0):
        n = 12
        # The delie's pale line: thin, down its middle, from above the notch (under the point) to a
        # quarter of the way up from its foot, as the shot draws it.
        f0, f1 = 0.22, (notch[1] + 0.2 * rise) / B["apex_y"]
        pale([delie_point(f0 + (f1 - f0) * i / (n - 1), 0.5) for i in range(n)], 0.05 * k, side, 0.3, 0.2)
        # The plein's pale line: down its middle from higher up under the point into the serif.
        g0 = 0.5 * rise / B["apex_y"]
        g1 = 1.0 - 1.3 * k / B["apex_y"]
        pale([plein_point(g0 + (g1 - g0) * i / (n - 1), 0.5) for i in range(n)], 0.075 * k, side, 0.2, 0.25)
        # The serif's flourish, as the shot draws it: under the line, a pale "A" that fills the foot -- its
        # left leg dropping almost straight beside the cove, its right leg spreading over the sweep, a
        # hooked bar off the left leg -- and a base stroke along the foot whose end curls back up.
        top_y = 0.86 * B["sweep_y"]
        top = (stem_c(top_y), top_y)
        m = 7
        base_y = 0.17 * k
        leg_l = widest(lambda r: [lerp2(top, (top[0] - r, base_y + 0.08 * k), i / (m - 1)) for i in range(m)], 0.08 * k, -0.25 * k, 0.25 * k, 0.2, 0.35)
        leg_r = widest(lambda r: [lerp2(top, (top[0] + r, base_y + 0.1 * k), i / (m - 1)) for i in range(m)], 0.08 * k, 0.1 * k, 0.55 * k, 0.2, 0.35)
        pale(leg_l, 0.08 * k, side, 0.2, 0.35)
        pale(leg_r, 0.08 * k, side, 0.2, 0.35)
        # The flag off the top of the "A", as the shot curls it: up and over to the right, then down.
        flag = widest(lambda r: [top, v2add(top, (0.4 * r, 0.035 * k)), v2add(top, (0.8 * r, 0.02 * k)), v2add(top, (r, -0.05 * k))], 0.05 * k, 0.05 * k, 0.2 * k, 0.2, 0.4)
        pale(flag, 0.05 * k, side, 0.2, 0.4)
        hook_at = lerp2(top, leg_l[-1], 0.38)
        hook = [hook_at, v2add(hook_at, (0.07 * k, -0.005 * k)), v2add(hook_at, (0.13 * k, -0.035 * k)), v2add(hook_at, (0.16 * k, -0.085 * k))]
        pale(hook, 0.05 * k, side, 0.2, 0.4)
        x0 = leg_l[-1][0] - 0.03 * k

        def base_stroke(r):
            line = [(x0 + r * i / 6, base_y + 0.01 * k * math.sin(math.pi * i / 6)) for i in range(7)]
            end = line[-1]
            return line + [v2add(end, (0.05 * k, 0.025 * k)), v2add(end, (0.055 * k, 0.08 * k)), v2add(end, (0.01 * k, 0.12 * k))]

        pale(widest(base_stroke, 0.06 * k, 0.2 * k, 0.9 * k, 0.2, 0.3), 0.06 * k, side, 0.2, 0.3)

    meshes = (body, core, ink)
    if B["mirror"]:
        # The delie on the front viewer's left (+X): mirrored, each triangle turned to keep its face.
        for mesh in meshes:
            mesh.verts = [(-x, y, z) for x, y, z in mesh.verts]
            mesh.tris = [(a, c, b) for a, b, c in mesh.tris]
    for mesh in meshes:
        mesh.translate((0.0, 0.0, B["plane_z"]))
    # Normalise: the whole span, ink included, is exactly 1 across X, centred on the pivot.
    xs = [v[0] for mesh in meshes for v in mesh.verts]
    factor, shift = 1.0 / (max(xs) - min(xs)), -(max(xs) + min(xs)) / 2.0
    for mesh in meshes:
        mesh.verts = [((x + shift) * factor, max(y * factor, 0.0), z * factor) for x, y, z in mesh.verts]
    ink.verts = [(x, max(y, FLOOR_CLEARANCE), z) for x, y, z in ink.verts]
    _CACHE[B["name"]] = (body, core, ink, slab, g, factor)
    return _CACHE[B["name"]]


def caret_meta(seed: int) -> dict:
    return {"Reference": "Width", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def caret_wide_body():
    return _caret(WIDE)[0], caret_meta(WIDE_SEED)


def caret_wide_core():
    return _caret(WIDE)[1], caret_meta(WIDE_SEED + 1)


def caret_wide_ink():
    return _caret(WIDE)[2], caret_meta(WIDE_SEED + 2)


# --- the departure's strike -----------------------------------------------------------------------
RATURE_SEED = 3917
R_LEN = 5.0  # studs, ink included
R_H = 0.32  # the triangle's height (studs)
R_B = 0.36  # its base, across Z
R_INK = 0.10
R_HEAD = 0.03  # the pressed head's share of the length
CORE_LIFT = 0.05
INK_LIFT = 0.06  # the strike's ink filets over its slopes
STUD = 1.0 / 5.0


def _tri_ring(vol: Volume, x, h, b, yc, weight, wobble=0.0):
    """A triangle section at x: the ridge up, the base under it across Z."""
    top = vol.vert((x, yc + h * (2.0 / 3.0) + wobble, 0.0), weight)
    left = vol.vert((x, yc - h / 3.0, b / 2.0), weight)
    right = vol.vert((x, yc - h / 3.0, -b / 2.0), weight)
    return [top, left, right]


def _loft_tris(vol: Volume, rings, tip_start=None, tip_end=None):
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for j in range(3):
            k = (j + 1) % 3
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    f = rings[0]
    if tip_start is None:
        emit(vol.mesh, f[0], f[2], f[1])
    else:
        for j in range(3):
            emit(vol.mesh, f[(j + 1) % 3], f[j], tip_start)
    e = rings[-1]
    if tip_end is None:
        emit(vol.mesh, e[0], e[1], e[2])
    else:
        for j in range(3):
            emit(vol.mesh, e[j], e[(j + 1) % 3], tip_end)
    vol.orient_outward()


def _rature():
    if "rature" in _CACHE:
        return _CACHE["rature"]
    S = STUD
    half = (R_LEN / 2.0 - R_INK) * S
    x0, x1 = -half, half
    span = x1 - x0
    h, b = R_H * S, R_B * S
    ink_w = R_INK * S
    vols = []
    # The bar: pressed head, a steady body, then it hands over to the two dry strands.
    bar = Volume()
    stations = [0.0, 0.012, 0.03, 0.06] + [0.06 + (0.95 - 0.06) * i / 10 for i in range(1, 11)]
    rings = []
    for s in stations:
        press = 1.0 + 0.14 * math.sin(math.pi * min(s / (2 * R_HEAD), 1.0)) if s < 2 * R_HEAD else 1.0
        if s == 0.0:
            press = 0.86
        hand = 1.0 + 0.04 * (fbm(5.0 * s, 0.4, RATURE_SEED) * 2.0 - 1.0)
        # Past 90 % the bar thins as the strands take over.
        thin = 1.0 - 0.8 * max(0.0, (s - 0.86) / 0.09) ** 1.5
        kk = press * hand * thin
        w = ink_w * (1.15 if s < 2 * R_HEAD else 1.0)
        rings.append(_tri_ring(bar, x0 + span * s, h * kk, b * kk, 0.0, w))
    _loft_tris(bar, rings)
    vols.append(bar)
    # The dry tail: two strands out of the bar's end, one riding up, one down, each to a point. Each
    # starts at its own station and height inside the bar, from a buried point of its own, so no face of
    # one lies on a face of the other.
    for dy, start, end, rise in ((0.32, 0.855, 1.0, 0.1), (-0.36, 0.87, 0.975, -0.1)):
        strand = Volume()
        rs = []
        steps = 6
        for i in range(steps):
            s = start + (end - start) * i / steps
            f = (s - start) / (end - start)
            size = 0.6 * (1.0 - f) ** 0.8 + 0.04
            yc = rise * h * (1.0 - f) + dy * h * math.sin(0.5 * math.pi * f) ** 1.2
            rs.append(_tri_ring(strand, x0 + span * s, h * size, b * size, yc, ink_w * (1.0 - 0.2 * f)))
        root = strand.vert((x0 + span * (start - 0.012), rise * h, 0.0), ink_w)
        tip = strand.vert((x0 + span * end, dy * h * 1.05, 0.0), ink_w * 1.6)
        _loft_tris(strand, rs, tip_start=root, tip_end=tip)
        vols.append(strand)
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for vol in vols:
        # The strike floats at the thrower's root: lifted clear of the floor while its hull is pushed out
        # (inverted_hull holds every vertex over the floor), then lowered back about its middle.
        vol.mesh.translate((0.0, 1.0, 0.0))
        inverted_hull(vol, ink)
        vol.mesh.translate((0.0, -1.0, 0.0))
        body.merge(vol.mesh)
    ink.translate((0.0, -1.0, 0.0))
    # The pale line on each slope, under the ridge; an ink filet under it on each, of unequal lengths.
    for side, (c0, c1), (i0, i1) in ((1.0, (0.07, 0.82), (0.2, 0.7)), (-1.0, (0.1, 0.78), (0.3, 0.84))):
        _slope_strip(core, x0, span, h, b, side, c0, c1, 0.58, 0.26, CORE_LIFT * S)
        _slope_strip(ink, x0, span, h, b, side, i0, i1, 0.22, 0.16, INK_LIFT * S)
    xs = [v[0] for mesh in (body, core, ink) for v in mesh.verts]
    factor, shift = 1.0 / (max(xs) - min(xs)), -(max(xs) + min(xs)) / 2.0
    for mesh in (body, core, ink):
        mesh.verts = [(-(x + shift) * factor, y * factor, z * factor) for x, y, z in mesh.verts]
        mesh.tris = [(a, c, b) for a, b, c in mesh.tris]
    _CACHE["rature"] = (body, core, ink)
    return _CACHE["rature"]


def _slope_strip(mesh: Mesh, x0, span, h, b, side, s0, s1, up, width_share, lift):
    """A lens-shaped strip on one slope of the triangle (side +1: the +Z slope, the thrower's), from s0 to
    s1 of the length, centred `up` of the way from the base corner to the ridge, `width_share` of the
    slope wide."""
    n = 10
    top = (0.0, h * 2.0 / 3.0)
    base = (side * b / 2.0, -h / 3.0)
    slope = v2sub(top, base)  # (z, y) from the base corner up to the ridge
    nz, ny = v2unit((side * h, b / 2.0))  # the slope's outward normal in the (z, y) plane
    widths = lens(n, width_share, 0.25, 0.3)
    lefts, rights = [], []
    for i in range(n):
        s = s0 + (s1 - s0) * i / (n - 1)
        x = x0 + span * s
        for off, into in ((up + widths[i] / 2.0, lefts), (up - widths[i] / 2.0, rights)):
            zc = base[0] + slope[0] * off + nz * lift
            yc = base[1] + slope[1] * off + ny * lift
            into.append(mesh.vert((x, yc, zc)))
    facing = (0.0, ny, nz)
    for i in range(n - 1):
        mesh.tri(lefts[i], rights[i], lefts[i + 1], facing)
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1], facing)


def rature_meta(seed: int) -> dict:
    return {"Reference": "Width", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def rature_body():
    return _rature()[0], rature_meta(RATURE_SEED)


def rature_core():
    return _rature()[1], rature_meta(RATURE_SEED + 1)


def rature_ink():
    return _rature()[2], rature_meta(RATURE_SEED + 2)
