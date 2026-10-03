"""The Binding's cage (Indigo): six ink cords flaring out of a splash on the floor, twisting round the
caught body and gathered over its head into a knot of two fat rope wraps crossed on a diagonal, under a
crown of pale foam.

Drawn after the developer's two references (docs/vfx/binding/ref-1.jpg, the cage on a caught avatar in
game; ref-2.jpg, the model sheet "Indigo ink binding cords"). The sheet wins on shape, the in-game shot
on scale against the character. Roblox space: X right, Y up, forward -Z; the thrower sees it from
behind (+Z), over the shoulder, about 20 studs away.

Modelled in studs at its placed size round an R15 avatar (legs to 3.2, torso and arms to 5.2, head
top 6.2; arm corners at r 2.06, leg corners at r 1.12), then scaled so the whole body (contour included)
is 1 tall: Reference "Height", pivot (0, 0, 0) on the floor under the cage's axis, axis Y. The cage is
the sheet's 5.2 studs wide; the cords reach the knot just over the head, so the body with its knot and
crown is about 8.2 studs tall, under the dome of the server's 7-stud sphere.

Pieces (each a closed volume wound outward, its inverted hull the ink contour):
  - six cords, lens section (flat face out), loxodromes on the sheet's bulb: roots flaring wide and flat
    into the splash, a neck round the ankles clear of the legs, the bulge round the arms, clear of the
    shoulders, rising steeply into the knot and ending deep inside its plug;
  - the knot: two rope wraps of round (six-sided) section, fatter than a cord, each a tilted ring round
    the plug; tilted against each other they cross on a diagonal in front and behind, one riding over
    the other at each crossing (over in front, under behind, as a rope is wound);
  - the plug: the bundle's core inside the knot, swelling into a boss over it that holds the crown;
  - the crown: five foam petals out of the boss, round clubs with domed heads (ten sides, five rings),
    four splayed long and short in turn round an upright one. Each is a pigment petal whose head wears
    a pale foam shell on its own rings; the pigment under the shell is never seen and is cut away;
  - the splash: a low rosette whose fingers run on from the cords' roots and hook at the rim, two ink
    tongues thrown up between them ending in round pearls, three flat round drops on the floor, and
    three calligraphic flow lines from the roots out.
"""

from __future__ import annotations

import math

from strokes import (
    FLOOR_CLEARANCE,
    Mesh,
    Polyline,
    Rng,
    Volume,
    add,
    catmull,
    cosine_curve,
    cross,
    dot,
    emit,
    fbm,
    inverted_hull,
    mul,
    norm,
    sub,
    surface_ribbon,
)

SEED = 5209
CORDS = 6
CORD_PHASE = math.radians(15.0)  # the first cord's root azimuth

# --- the cage (studs) ---------------------------------------------------------------------------
# The cord's meridian: (radius, height) of its spine, root to its end deep in the knot's plug. The root
# lies flat on the splash and flares out of it; the neck round the ankles keeps the lens clear of the
# R15 legs' corners (r 1.12); the bulge is the sheet's 5.2 studs with the contour; at the arms' top
# (y 5.2) the spine is still at r 2.3, clear of the shoulders' corners (r 2.06) at any yaw; over the
# head it turns in to the knot.
MERIDIAN = [
    (2.12, -0.24),
    (1.82, 0.05),
    (1.56, 0.28),
    (1.42, 0.58),
    (1.4, 0.92),
    (1.6, 1.38),
    (1.98, 1.92),
    (2.28, 2.52),
    (2.41, 3.2),
    (2.42, 4.0),
    (2.38, 4.7),
    (2.33, 5.2),
    (2.2, 5.55),
    (1.82, 5.86),
    (1.36, 6.08),
    (0.92, 6.38),
    (0.56, 6.5),
    (0.38, 6.6),
    (0.32, 6.74),
    (0.3, 6.9),
]
# The angle between a cord and its meridian along it (u, degrees). Steep round the ankles and over the
# shoulders, where six cords must close in on a neck and on the knot whatever their angle; held round
# the body (y 2.5 to 5.2), where the clear gap between two cords stays at least 1.5 studs.
ALPHA = [(0.0, 4.0), (0.04, 8.0), (0.1, 40.0), (0.22, 40.0), (0.29, 30.0), (0.34, 22.0), (0.66, 22.0), (0.73, 34.0), (0.8, 42.0), (0.9, 42.0), (0.96, 30.0), (1.0, 24.0)]
# Width across the cord (studs) along it: wide and flat where it flows out of the splash, 0.38 round
# the body, narrowing into the knot -- and its thickness as a share of the width (a lens).
WIDTH = [(0.0, 0.66), (0.04, 0.5), (0.1, 0.42), (0.18, 0.38), (0.62, 0.38), (0.74, 0.35), (0.86, 0.31), (0.95, 0.26), (1.0, 0.22)]
THICK = 0.62
# Contour weight (studs): heavier where the brush pressed, at the root; never under the bible's 0.1.
CORD_WEIGHT = [(0.0, 0.12), (0.1, 0.1), (1.0, 0.1)]
CORD_RINGS = 11
TURN_COST = 0.55  # studs of arc a radian of turning is worth when the rings are spaced along the cord

# The knot: two wraps round the plug, each a ring tilted out of level. Wrap one rides over wrap two at
# the front crossing and under it behind: its radius swings by ROPE_SWING round its mean.
ROPE_D = 0.36  # the rope's section (round): fatter than a cord's lens is thick (0.2) or wide (0.31)
ROPE_SIDES = 6
ROPE_STATIONS = 10
ROPE_WEIGHT = 0.1
KNOT_FRONT = math.radians(78.0)  # azimuth of the front crossing (front is 90); the back one is opposite
KNOT_Y = 7.06  # height of the two crossings
KNOT_R = 0.58  # the wraps' mean spine radius
KNOT_AMP = 0.24  # how far each wrap climbs and dips round the side: 28 degrees of tilt
ROPE_SWING = 0.23  # (rope + contour) / 2: the one over clears the one under by a contour

# The plug: (radius, height) of the bundle's core, swelling into the boss on top. Its sides lie under
# the wraps (their inner face at r 0.46), so between the wraps only its pigment shows.
PLUG = [(0.0, 6.54), (0.56, 6.59), (0.58, 6.74), (0.54, 7.17), (0.44, 7.34), (0.26, 7.45), (0.0, 7.48)]
PLUG_SIDES = 6
PLUG_WEIGHT = 0.1

# The crown: foam petals out of the boss -- each a club, a neck and a round head.
LOBE_SIDES = 10
LOBE_FLAT = 0.84  # the head's thickness out of the crown, as a share of its width
LOBE_LONG = 1.55  # the head's length along the petal, as a share of its width
LOBE_NECK = (0.04, 0.09)  # (arc length from the root's mouth, radius) of the neck ring, in the boss
LOBE_HEAD = (-72.0, 0.0, 34.0, 66.0)  # the head's rings, by latitude on its ellipsoid: a narrow foot,
# the widest, and a domed top
LOBE_FOAM_FROM = 1  # the foam starts on the head's foot ring, seated in the boss
LOBE_SEAT = 0.03  # how deep in the boss the foot ring sits, at least
LOBE_ROOT_DEPTH = 0.3  # how deep under the boss the petal's root is buried
LOBE_WEIGHT = 0.1
FOAM_LIFT = 0.035  # the pale over its pigment: within the bible's 0.03 to 0.08

# The splash.
POOL_R = 1.98
POOL_H = 0.18  # the bible's 0.04 of the rosette's diameter (about 5 studs)
POOL_WEIGHT = 0.11
FINGER_REACH = (2.42, 2.5, 2.36, 2.52, 2.4, 2.46)  # one finger per cord root
FINGER_HALF = 13.0  # degrees
FINGER_HOOK = -8.0  # the fingers hook against the twist, the way the roots sweep
FLOW_LIFT = 0.035  # a flow line over the splash: the ink floor's own clearance, never closer
# Tongues thrown up between the fingers: (degrees past a root, height, reach, lean sideways).
TONGUES = [(0, 32.0, 0.7, 0.44, 0.1), (3, 26.0, 0.56, 0.38, -0.08)]
PEARL_R = 0.2
# Flat drops on the floor: (degrees past a root, distance, length, width, turn degrees).
DROPS = [(1, 30.0, 2.82, 0.42, 0.22, 12.0), (2, 34.0, 2.74, 0.34, 0.18, -18.0), (4, 28.0, 2.86, 0.38, 0.2, 8.0)]


# --- helpers ------------------------------------------------------------------------------------


def radial(phi: float):
    """The outward unit vector at azimuth phi (counted from +X toward -Z, the bible's sense)."""
    return (math.cos(phi), 0.0, -math.sin(phi))


def closed_loft(rings: list[list], weights: list[float], start, end, start_w: float, end_w: float) -> Volume:
    """A closed volume through rings of points (same count, same sense), each end closed on a point."""
    vol = Volume()
    ids = [[vol.vert(p, w) for p in ring] for ring, w in zip(rings, weights)]
    m = len(rings[0])
    for a, b in zip(ids, ids[1:]):
        for j in range(m):
            k = (j + 1) % m
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    s = vol.vert(start, start_w)
    for j in range(m):
        emit(vol.mesh, s, ids[0][(j + 1) % m], ids[0][j])
    e = vol.vert(end, end_w)
    for j in range(m):
        emit(vol.mesh, ids[-1][j], ids[-1][(j + 1) % m], e)
    vol.orient_outward()
    vol.rings = ids
    return vol


def section(w: float, t: float):
    """The cord's lens section in (across, out) coordinates: two outer corners, an inner apex -- the
    flat face out."""
    return [(-w / 2, t / 3), (w / 2, t / 3), (0.0, -2 * t / 3)]


def stations(points: list, count: int, turn_cost: float) -> list[int]:
    """Indices of `count` samples of a dense polyline, spaced evenly in length plus turning."""
    cost = [0.0]
    for i in range(1, len(points)):
        step = math.dist(points[i - 1], points[i])
        turn = 0.0
        if 0 < i < len(points) - 1:
            u = norm(sub(points[i], points[i - 1]))
            v = norm(sub(points[i + 1], points[i]))
            turn = math.acos(max(-1.0, min(1.0, dot(u, v))))
        cost.append(cost[-1] + step + turn_cost * turn)
    out = []
    j = 0
    for n in range(count):
        target = cost[-1] * n / (count - 1)
        while j < len(cost) - 1 and cost[j] < target:
            j += 1
        out.append(j)
    return out


def round_ball(centre, radius: float, sides: int, turn: float, weight: float, squash: float = 1.0) -> Volume:
    """A round pearl: two rings of `sides` at 30 degrees either side of its equator, the upper turned
    half a step, and a pole over and under -- 4 x sides triangles, round in outline from every side."""
    vol = Volume()
    x, y, z = centre
    rings = []
    for lat, half in ((-30.0, 0.0), (30.0, 0.5)):
        c, s = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        rings.append(
            [
                vol.vert((x + radius * c * math.cos(turn + (k + half) * 2 * math.pi / sides), y + squash * radius * s, z - radius * c * math.sin(turn + (k + half) * 2 * math.pi / sides)), weight)
                for k in range(sides)
            ]
        )
    lo, hi = rings
    bottom = vol.vert((x, y - squash * radius, z), weight)
    top = vol.vert((x, y + squash * radius, z), weight)
    for k in range(sides):
        n = (k + 1) % sides
        emit(vol.mesh, lo[k], lo[n], hi[k])
        emit(vol.mesh, hi[k], lo[n], hi[n])
        emit(vol.mesh, hi[k], hi[n], top)
        emit(vol.mesh, lo[n], lo[k], bottom)
    vol.orient_outward()
    return vol


# --- the cords ----------------------------------------------------------------------------------


def cord_spine(k: int, meridian=None, alpha=None, seed: int = SEED):
    """Dense samples of cord k: (point, u along it, outward surface normal). The cords stand at even
    azimuths -- any jitter there closes one gap round the body, and the gaps are the prisoner's -- and
    differ by a hair in how far they swell and how fast they twist."""
    meridian = meridian or MERIDIAN
    alpha_curve = alpha or ALPHA
    rng = Rng(seed + 31 * k)
    phase = CORD_PHASE + 2 * math.pi * k / CORDS
    swell = 1.0 + rng.uniform(-0.01, 0.01)
    twist = 1.0 + rng.uniform(-0.006, 0.006)
    merid = Polyline(catmull(meridian, 24))
    n = 260
    pts2 = [merid.at(i / n) for i in range(n + 1)]
    # Swell the bulge only: the root and the knot stay where they are.
    pts2 = [(r * (1.0 + (swell - 1.0) * math.sin(math.pi * i / n)), y) for i, (r, y) in enumerate(pts2)]
    phi = phase
    out = []
    for i, (r, y) in enumerate(pts2):
        u = i / n
        if i > 0:
            ds = math.dist(pts2[i - 1], pts2[i])
            alpha = math.radians(cosine_curve(alpha_curve, u)) * twist
            phi += math.tan(alpha) * ds / max(r, 0.2)
        a = pts2[max(i - 1, 0)]
        b = pts2[min(i + 1, n)]
        dr, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dr, dy) or 1.0
        e = radial(phi)
        normal = norm(add(mul(e, dy / length), (0.0, -dr / length, 0.0)))
        out.append((add(mul(e, r), (0.0, y, 0.0)), u, normal))
    return out, phase


def cord_width(k: int, u: float, width=None) -> float:
    """Cord k's width at u: the profile, a hair wider or narrower per cord, and the brush's pressure."""
    wide = 1.0 + Rng(SEED + 7 * k).uniform(-0.03, 0.03)
    return cosine_curve(width or WIDTH, u) * wide * (1.0 + 0.05 * (fbm(4.0 * u, 0.7, SEED + k) * 2.0 - 1.0))


def build_cord(k: int, spine=None, width=None, weight=None, rings_out=None, count=None) -> Volume:
    spine = spine or cord_spine(k)[0]
    weight = weight or CORD_WEIGHT
    pts = [p for p, _, _ in spine]
    idx = stations(pts, (count or CORD_RINGS) + 2, TURN_COST)
    rings, weights = [], []
    for i in idx[1:-1]:
        p, u, n = spine[i]
        t_vec = norm(sub(pts[min(i + 1, len(pts) - 1)], pts[max(i - 1, 0)]))
        n = norm(sub(n, mul(t_vec, dot(n, t_vec))))
        across = norm(cross(t_vec, n))
        w = cord_width(k, u, width)
        ring = [add(p, add(mul(across, x), mul(n, y))) for x, y in section(w, THICK * w + 0.02)]
        rings.append([(q[0], max(q[1], FLOOR_CLEARANCE), q[2]) for q in ring])
        weights.append(cosine_curve(weight, u))
        if rings_out is not None:
            rings_out.append((rings[-1], p, u))
    start = spine[idx[0]][0]
    end = spine[idx[-1]][0]
    if rings_out is not None:
        rings_out.append(([end], end, 1.0))
    return closed_loft(rings, weights, (start[0], max(start[1], FLOOR_CLEARANCE), start[2]), end, weights[0], 0.1)


def root_azimuth(k: int) -> float:
    """Where cord k's root lies on the splash."""
    p = cord_spine(k)[0][0][0]
    return math.atan2(-p[2], p[0])


# --- the knot -----------------------------------------------------------------------------------


def wrap_centre(phi: float, sign: int):
    """Wrap `sign`'s spine at azimuth phi: a ring tilted out of level, crossing the other at the front
    and the back, outside it at the front crossing (sign +1) or behind (sign -1)."""
    d = phi - KNOT_FRONT
    r = KNOT_R + sign * ROPE_SWING * math.cos(d)
    y = KNOT_Y + sign * KNOT_AMP * math.sin(d)
    return add(mul(radial(phi), r), (0.0, y, 0.0))


def build_wrap(sign: int) -> Volume:
    """One wrap: a closed ring of rope, six-sided and round, its stations even round the plug with one
    on each crossing."""
    n = ROPE_STATIONS
    phis = [KNOT_FRONT + 2 * math.pi * i / n for i in range(n)]
    centres = [wrap_centre(phi, sign) for phi in phis]
    vol = Volume()
    ids = []
    for i, phi in enumerate(phis):
        t_vec = norm(sub(wrap_centre(phi + 0.01, sign), wrap_centre(phi - 0.01, sign)))
        out = radial(phi)
        out = norm(sub(out, mul(t_vec, dot(out, t_vec))))
        up = norm(cross(t_vec, out))
        if up[1] < 0:
            up = mul(up, -1.0)
        ring = []
        for s in range(ROPE_SIDES):
            a = 2 * math.pi * s / ROPE_SIDES
            q = add(centres[i], add(mul(out, 0.5 * ROPE_D * math.cos(a)), mul(up, 0.5 * ROPE_D * math.sin(a))))
            ring.append(vol.vert(q, ROPE_WEIGHT))
        ids.append(ring)
    for i in range(n):
        a, b = ids[i], ids[(i + 1) % n]
        for j in range(ROPE_SIDES):
            k = (j + 1) % ROPE_SIDES
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    vol.orient_outward()
    return vol


def lathe(profile: list, sides: int, weight: float, seed: int) -> Volume:
    """A closed volume of revolution through (radius, height) pairs, each end on the axis, a hair out
    of round so it is not turned on a lathe."""
    vol = Volume()
    rng = Rng(seed)
    wobble = [1.0 + rng.uniform(-0.04, 0.04) for _ in range(sides)]
    turn = rng.uniform(0.0, 2 * math.pi)
    rings = []
    for r, y in profile[1:-1]:
        rings.append([vol.vert(add(mul(radial(turn + 2 * math.pi * s / sides), r * wobble[s]), (0.0, y, 0.0)), weight) for s in range(sides)])
    bottom = vol.vert((0.0, profile[0][1], 0.0), weight)
    top = vol.vert((0.0, profile[-1][1], 0.0), weight)
    for a, b in zip(rings, rings[1:]):
        for j in range(sides):
            k = (j + 1) % sides
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    for j in range(sides):
        k = (j + 1) % sides
        emit(vol.mesh, bottom, rings[0][k], rings[0][j])
        emit(vol.mesh, rings[-1][j], rings[-1][k], top)
    vol.orient_outward()
    return vol


# --- the crown ----------------------------------------------------------------------------------


def lobe_specs() -> list[dict]:
    """Five petals splayed round an upright one, low and wide and tall and close in turn, like a hand
    opening; their heads clear of each other's contour, so each petal is drawn on its own."""
    rng = Rng(SEED + 500)
    specs = []
    count = 5
    for k in range(count):
        low = k % 2 == 0
        specs.append(
            {
                "az": KNOT_FRONT + 2 * math.pi * (k + 0.5) / count + math.radians(rng.uniform(-5.0, 5.0)),
                "mouth": (0.16, 7.18),
                "lean": math.radians(rng.uniform(52.0, 56.0) if low else rng.uniform(34.0, 38.0)),
                "length": rng.uniform(0.9, 0.94) if low else rng.uniform(0.98, 1.02),
                "head": rng.uniform(0.24, 0.25) if low else rng.uniform(0.25, 0.26),
            }
        )
    specs.append({"az": KNOT_FRONT, "mouth": (0.0, 7.22), "lean": math.radians(3.0), "length": 0.98, "head": 0.24})
    for spec in specs:
        seat(spec)
    return specs


def plug_radius(y: float) -> float:
    """The plug's radius at height y, at its narrowest wobble (0 outside it)."""
    for (r0, y0), (r1, y1) in zip(PLUG, PLUG[1:]):
        if y0 <= y <= y1:
            return 0.96 * (r0 + (r1 - r0) * (y - y0) / (y1 - y0))
    return 0.0


def seat(spec: dict) -> None:
    """Sink a petal straight down until its foot ring lies LOBE_SEAT inside the boss, so the foam's
    lower edge never opens on the petal's hollow."""
    spec["sink"] = 0.0
    while True:
        rings, _, _ = lobe_rings(spec)
        depth = min(plug_radius(q[1]) - math.hypot(q[0], q[2]) for q in rings[LOBE_FOAM_FROM][0])
        if depth >= LOBE_SEAT or spec["sink"] > 0.5:
            return
        spec["sink"] += 0.01


def lobe_spine(spec: dict, samples: int = 40) -> Polyline:
    """The petal's spine: a quadratic arc out of the boss's mouth, rising and then leaning out."""
    e = radial(spec["az"])
    r0, y0 = spec["mouth"]
    p0 = add(mul(e, r0), (0.0, y0 - spec.get("sink", 0.0), 0.0))
    p1 = add(p0, (0.0, 0.45 * spec["length"], 0.0))
    p2 = add(p0, add(mul(e, spec["length"] * math.sin(spec["lean"])), (0.0, spec["length"] * math.cos(spec["lean"]), 0.0)))
    pts = []
    for i in range(samples + 1):
        v = i / samples
        pts.append(add(add(mul(p0, (1 - v) ** 2), mul(p1, 2 * v * (1 - v))), mul(p2, v * v)))
    return Polyline(pts)


def lobe_frame(spec: dict, line: Polyline, s: float):
    """(point, tangent, side, out) at arc length s along the petal's spine (s may run past either end,
    along the end's tangent)."""
    length = line.acc[-1]
    f = min(max(s / length, 0.0), 1.0)
    p = line.at(f)
    a, b = line.at(max(f - 0.02, 0.0)), line.at(min(f + 0.02, 1.0))
    t = norm(sub(b, a))
    if s < 0.0:
        p = add(p, mul(t, s))
    elif s > length:
        p = add(p, mul(t, s - length))
    e = radial(spec["az"])
    side = norm(cross(t, e))
    out = norm(cross(side, t))
    return p, t, side, out


def lobe_rings(spec: dict, lift: float = 0.0):
    """The petal's rings, root to tip: the neck, then the head's rings on an ellipsoid -- its width
    `head`, its length LOBE_LONG times that, its tip at the spine's end. Each ring is (points, centre),
    `lift` pushing the points off the spine (the foam over its pigment)."""
    line = lobe_spine(spec)
    length = line.acc[-1]
    rho = spec["head"]
    along = LOBE_LONG * rho
    centre_s = length - along
    out_rings = []
    neck_s, neck_r = LOBE_NECK
    plan = [(neck_s, neck_r)]
    for lat in LOBE_HEAD:
        a = math.radians(lat)
        plan.append((centre_s + along * math.sin(a), rho * math.cos(a)))
    for s, rad in plan:
        p, _t, side, out = lobe_frame(spec, line, s)
        ring = []
        for j in range(LOBE_SIDES):
            ang = 2 * math.pi * (j + 0.5) / LOBE_SIDES
            d = add(mul(side, math.cos(ang)), mul(out, LOBE_FLAT * math.sin(ang)))
            q = add(p, mul(d, rad))
            if lift:
                q = add(q, mul(norm(d), lift))
            ring.append(q)
        out_rings.append((ring, p))
    tip_p, tip_t, _, _ = lobe_frame(spec, line, length)
    root = lobe_frame(spec, line, -LOBE_ROOT_DEPTH)[0]
    return out_rings, root, add(tip_p, mul(tip_t, lift))


def build_lobe(spec: dict) -> Volume:
    rings, root, tip = lobe_rings(spec)
    vol = closed_loft([r for r, _ in rings], [LOBE_WEIGHT] * len(rings), root, tip, LOBE_WEIGHT, LOBE_WEIGHT)
    vol.foam_from = LOBE_FOAM_FROM
    return vol


def foam_shell(core: Mesh, spec: dict) -> None:
    """The pale over a petal's head: a shell on the petal's own rings from the head's first ring to the
    tip, lifted off them; its first ring sits on the pigment's, so no seam opens at a grazing angle."""
    rings, _root, tip = lobe_rings(spec, FOAM_LIFT)
    base, _, _ = lobe_rings(spec)
    shell = [base[LOBE_FOAM_FROM]] + rings[LOBE_FOAM_FROM + 1:]
    ids = [[core.vert(q) for q in ring] for ring, _ in shell]
    centres = [c for _, c in shell]
    t = core.vert(tip)
    m = LOBE_SIDES
    for ra, rb, ca, cb in zip(ids, ids[1:], centres, centres[1:]):
        mid = mul(add(ca, cb), 0.5)
        for j in range(m):
            k = (j + 1) % m
            core.tri(ra[j], ra[k], rb[k], sub(core.verts[ra[j]], mid))
            core.tri(ra[j], rb[k], rb[j], sub(core.verts[ra[j]], mid))
    for j in range(m):
        k = (j + 1) % m
        core.tri(ids[-1][j], ids[-1][k], t, sub(core.verts[ids[-1][j]], centres[-1]))


def head_hull(vol: Volume, into: Mesh) -> None:
    """A petal's contour, over its head only: the root and the neck lie in the boss, and so do their
    contour's faces, which nothing can see."""
    head = set()
    for ring in vol.rings[vol.foam_from:]:
        head.update(ring)
    head.add(len(vol.mesh.verts) - 1)  # the tip
    part = Volume()
    part.mesh.verts = vol.mesh.verts
    part.weight = vol.weight
    part.mesh.tris = vol.mesh.tris
    # The normals come from the whole closed petal; only the head's faces are drawn.
    before = len(into.tris)
    inverted_hull(part, into)
    base = len(into.verts) - len(vol.mesh.verts)
    into.tris[before:] = [t for t in into.tris[before:] if all(v - base in head for v in t)]


# --- the splash ---------------------------------------------------------------------------------


def fingers() -> list[tuple[float, float]]:
    """(azimuth, reach) of each finger: one per cord, running on from its root."""
    return [(root_azimuth(k), FINGER_REACH[k]) for k in range(CORDS)]


def pool_radius(theta: float, fing) -> float:
    r = POOL_R * (1.0 + 0.04 * (fbm(1.3 * theta, 0.4, SEED + 600) * 2.0 - 1.0))
    for az, reach in fing:
        d = math.remainder(theta - (az + math.radians(FINGER_HOOK)), 2 * math.pi)
        x = abs(d / math.radians(FINGER_HALF))
        if x < 1.0:
            bump = (1.0 - x**2.4) ** 0.55
            r = max(r, POOL_R + (reach - POOL_R) * bump)
    return r


def pool_point(s: float, theta: float, fing):
    """The splash's top at fraction s of the way out at azimuth theta: a plateau that falls off at its
    rim, swelling and sinking a little round it so its edge is never a straight slab from the side."""
    r = s * pool_radius(theta, fing)
    swell = 0.72 + 0.28 * math.sin(3.0 * theta + 0.7) * math.sin(2.0 * theta + 1.9)
    h = POOL_H * (1.0 - (1.0 - swell) * s / 0.84 if s <= 0.84 else swell * max(0.0, (1.0 - s) / 0.16))
    e = radial(theta)
    return (e[0] * r, max(h, 0.0), e[2] * r)


def pool_thetas(fing) -> list[float]:
    """The rim's azimuths: three across each finger's head, one in each gap."""
    out = []
    order = sorted(math.remainder(az, 2 * math.pi) % (2 * math.pi) for az, _ in fing)
    hook = math.radians(FINGER_HOOK)
    half = math.radians(FINGER_HALF)
    for i, az in enumerate(order):
        nxt = order[(i + 1) % len(order)] + (2 * math.pi if i == len(order) - 1 else 0.0)
        centre = az + hook
        for f in (-0.72, 0.0, 0.72):
            out.append(centre + f * half)
        out.append(0.5 * (centre + 0.72 * half + nxt + hook - 0.72 * half))
    return out


def build_pool(fing) -> Volume:
    vol = Volume()
    thetas = pool_thetas(fing)
    n = len(thetas)
    top = vol.vert((0.0, POOL_H, 0.0), POOL_WEIGHT)
    inner = [vol.vert(pool_point(0.84, t, fing), POOL_WEIGHT) for t in thetas]
    rim = [vol.vert(pool_point(1.0, t, fing), POOL_WEIGHT) for t in thetas]
    bottom = vol.vert((0.0, 0.0, 0.0), POOL_WEIGHT)
    for i in range(n):
        j = (i + 1) % n
        emit(vol.mesh, top, inner[j], inner[i])
        emit(vol.mesh, inner[i], inner[j], rim[j])
        emit(vol.mesh, inner[i], rim[j], rim[i])
        emit(vol.mesh, bottom, rim[i], rim[j])
    vol.orient_outward()
    # The contour is pushed out across the floor at the rim, not down into it: the bottom's one big fan
    # would otherwise outweigh the thin fall of the rim and leave the splash with no outline.
    vol.dirs = {top: (0.0, 1.0, 0.0), bottom: (0.0, -1.0, 0.0)}
    for t, i, r in zip(thetas, inner, rim):
        vol.dirs[i] = norm(add(radial(t), (0.0, 2.0, 0.0)))
        vol.dirs[r] = norm(add(radial(t), (0.0, 0.15, 0.0)))
    return vol


def build_tongue(az: float, height: float, reach: float, lean: float, fing) -> list[Volume]:
    """A tongue of ink thrown up off the splash's rim between two fingers: out of the pool, up and
    out, and a round pearl where the ink runs off its tip."""
    e = radial(az)
    side = (e[2], 0.0, -e[0])
    r0 = 0.8 * pool_radius(az, fing)
    ctrl = [
        add(mul(e, r0), (0.0, 0.06, 0.0)),
        add(mul(e, r0 + 0.1 * reach), (0.0, 0.45 * height, 0.0)),
        add(add(mul(e, r0 + 0.5 * reach), (0.0, 0.85 * height, 0.0)), mul(side, 0.5 * lean)),
        add(add(mul(e, r0 + reach), (0.0, height, 0.0)), mul(side, lean)),
    ]
    line = Polyline(catmull(ctrl, 12))
    rings, weights = [], []
    for f, w in ((0.12, 0.32), (0.45, 0.25), (0.78, 0.19)):
        p = line.at(f)
        t_vec = norm(sub(line.at(min(1.0, f + 0.02)), line.at(max(0.0, f - 0.02))))
        n = norm(sub(e, mul(t_vec, dot(e, t_vec))))
        across = norm(cross(t_vec, n))
        rings.append([add(p, add(mul(across, x), mul(n, y))) for x, y in section(w, 0.62 * w)])
        weights.append(0.1)
    tube = closed_loft(rings, weights, line.at(0.0), line.at(0.96), 0.1, 0.1)
    tip = line.at(1.0)
    t_end = norm(sub(line.at(1.0), line.at(0.94)))
    return [tube, round_ball(add(tip, mul(t_end, 0.06)), PEARL_R, 6, az, 0.1)]


def build_drop(az: float, dist: float, length: float, width: float, turn: float) -> Volume:
    """A flat drop of ink flung onto the floor: a round-ended oval of ten sides, a low dome over the
    page, its contour pushed out across the floor."""
    vol = Volume()
    c = add(mul(radial(az), dist), (0.0, 0.0, 0.0))
    long_dir = radial(az + turn)
    across = (long_dir[2], 0.0, -long_dir[0])
    sides = 10
    rim = []
    for j in range(sides):
        a = 2 * math.pi * j / sides
        # A drop, not an ellipse: fuller at its outer end, where the ink landed.
        bulge = 1.0 + 0.12 * math.cos(a)
        p = add(add(c, mul(long_dir, 0.5 * length * math.cos(a))), mul(across, 0.5 * width * bulge * math.sin(a)))
        rim.append(vol.vert((p[0], 0.045, p[2]), 0.1))
    top = vol.vert((c[0], 0.1, c[2]), 0.1)
    bottom = vol.vert((c[0], 0.0, c[2]), 0.1)
    for j in range(sides):
        k = (j + 1) % sides
        emit(vol.mesh, top, rim[j], rim[k])
        emit(vol.mesh, bottom, rim[k], rim[j])
    vol.orient_outward()
    vol.dirs = {top: (0.0, 1.0, 0.0), bottom: (0.0, -1.0, 0.0)}
    for j, v in enumerate(rim):
        a = 2 * math.pi * j / sides
        d = add(mul(long_dir, math.cos(a)), mul(across, math.sin(a)))
        vol.dirs[v] = norm(add(d, (0.0, 0.3, 0.0)))
    return vol


def flow_lines(ink: Mesh, fing) -> None:
    """Calligraphic strokes on the splash, from three roots out along their fingers."""
    surface = (lambda s, t: pool_point(s, t, fing), lambda s, t: (0.0, 1.0, 0.0))
    for k in (1, 3, 5):
        a0, _ = fing[k]

        def path(tau, a0=a0):
            return 0.5 + 0.4 * tau, a0 + math.radians(FINGER_HOOK) * 1.2 * tau * tau + math.radians(14.0)

        surface_ribbon(ink, surface, path, 0.08, FLOW_LIFT, 7, SEED + 40 * k)


def hull(vol: Volume, into: Mesh) -> None:
    """strokes.inverted_hull, with the push direction of some vertices set by the piece itself."""
    dirs = getattr(vol, "dirs", None)
    if not dirs:
        inverted_hull(vol, into)
        return
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        n = cross(sub(mesh.verts[b], mesh.verts[a]), sub(mesh.verts[c], mesh.verts[a]))
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        d = dirs.get(i, norm(acc[i]))
        q = add(p, mul(d, vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR_CLEARANCE), q[2]))
    for a, b, c in mesh.tris:
        emit(into, a + base, c + base, b + base)


# --- the three meshes ---------------------------------------------------------------------------

_CACHE: dict = {}


def splash() -> list[Volume]:
    """The splash and what it throws: the pool, the tongues and their pearls, the drops."""
    fing = fingers()
    solids = [build_pool(fing)]
    for k, deg, height, reach, lean in TONGUES:
        solids += build_tongue(fing[k][0] + math.radians(deg), height, reach, lean, fing)
    for k, deg, dist, length, width, turn in DROPS:
        solids.append(build_drop(fing[k][0] + math.radians(deg), dist, length, width, math.radians(turn)))
    return solids


def pieces() -> tuple[list[Volume], list[Volume]]:
    """The cage's closed volumes: (pigment, petals)."""
    solids = [build_cord(k) for k in range(CORDS)]
    solids += [build_wrap(+1), build_wrap(-1)]
    solids.append(lathe(PLUG, PLUG_SIDES, PLUG_WEIGHT, SEED + 300))
    solids += splash()
    petals = [build_lobe(s) for s in lobe_specs()]
    return solids, petals


def finish(body: Mesh, core: Mesh, ink: Mesh, cache: dict):
    top = max(v[1] for m in (body, core, ink) for v in m.verts)
    for m in (body, core, ink):
        m.scale(1.0 / top)
    # The contour stays FLOOR_CLEARANCE over the floor in reference units, as every shipped body's does.
    ink.verts = [(x, max(y, FLOOR_CLEARANCE), z) for x, y, z in ink.verts]
    cache["meshes"] = (body, core, ink)
    return cache["meshes"]


def build():
    if _CACHE:
        return _CACHE["meshes"]
    solids, petals = pieces()
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for vol in solids:
        body.merge(vol.mesh)
        hull(vol, ink)
    # A petal's pigment is all under its foam or in the boss, never seen: the pigment mesh carries none
    # of it, and the petal's closed volume is only what its contour is pushed out from.
    for vol, spec in zip(petals, lobe_specs()):
        head_hull(vol, ink)
        foam_shell(core, spec)
    flow_lines(ink, fingers())
    return finish(body, core, ink, _CACHE)


def meta(seed: int) -> dict:
    return {"Reference": "Height", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def cords_body():
    return build()[0], meta(SEED)


def cords_foam():
    return build()[1], meta(SEED + 1)


def cords_ink():
    return build()[2], meta(SEED + 2)

