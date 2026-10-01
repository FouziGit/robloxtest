"""The Brand's fireball (D-273): a ball wrapped in flat flame ribbons, the body the Brand flies as.

Drawn after the developer's two references (a vortex of hooked flame tongues seen face-on, and a model
sheet of a ball wrapped in peeling flame ribbons), chosen out of two constructions by a judge.

Roblox space: X right, Y up, forward -Z; the game spins it about Z (the flight axis); the thrower sees
it mostly from behind (+Z).

Two families of ribbons (13 in all):
  - seven arms (inner layer): loxodromes from a small dark eye at the front pole to one at the back
    pole, a clean log spiral seen from either end. They stop short of each pole and tuck under a flat
    dark lid, so each pole is a clean polygon instead of a knot of converging ribbons; they are
    sampled evenly in Mercator latitude, so the hard curl near each eye gets as many samples as the
    easy run over the equator; their width follows the room between them, so they never overlap.
  - six bands (outer layer): they cross over the arms round the middle, winding the other way about
    Z, and peel off into flame tongues. Seen from behind, the arms wind out of the eye clockwise and
    so does every tongue, so the thrower sees one clean vortex. A tongue is a comma (narrow where it
    leaves the ball, widest past its middle, then a sharp point with a last hook); as it peels its
    face turns toward the thrower (+Z), so from behind it is a broad blade, not an edge-on needle, and
    its section opens from a tent into a flat slab, whose square corners let its hull stand off
    evenly while it twists. Long and short tongues alternate, tips evenly spaced about Z.

Three meshes, one tone each: fire_body (Pigment: the ribbons), fire_core (Core: the heated streaks, on
each arm and on both faces of each tongue, cut along the ribbon's own triangles), fire_ink (Ink: an
inverted hull round the whole ball, which draws its contour and, seen through the gaps between the
arms, its dark core; the lids of the two eyes; the inverted hull of every band).
"""

from __future__ import annotations

import math

from strokes import Mesh, Rng, fbm

SEED = 4417
ARMS = 7
BANDS = 6

# The arms (radii before the final scale to a 1.0 spinning diameter).
ARM_TOP = 0.395  # the arm's ridge
ARM_RIDGE = 0.022  # how far its edges sit below the ridge
ARM_PITCH = 0.9  # dphi / d(Mercator latitude): the loxodrome's winding
ARM_FILL = 0.8  # share of the gap between two arms' spines that an arm covers
ARM_END = math.radians(10.5)  # colatitude where an arm ends, under the eye's lid
ARM_SAMPLES = 16
ARM_SENSE = 1.0  # +1: azimuth rises from the front eye to the back one

# The eyes: a flat dark lid over each pole, above the ends of the arms.
EYE_RIM = math.radians(13.0)
EYE_SIDES = 16
EYE_Z = 0.392  # height of the lid's rim along Z

# The hull round the ball (inverted; a UV sphere about Z).
HULL_R = 0.424
HULL_SEGMENTS = 20
HULL_RINGS = 8

# The bands.
BAND_TOP = 0.468
HEAD_TOP = 0.41  # the ridge at a band's head: under the ball's contour (HULL_R), so no head stands proud of it
HEAD_RISE = 0.5  # share of the run on the ball over which the ridge rises from HEAD_TOP to BAND_TOP
BAND_DEPTH = 0.04
BAND_SENSE = -1.0  # -1: the bands cross the arms, so from behind every tongue winds out the same way as the arms
ON_SAMPLES = 7  # rows on the ball, head included
CLOSED_BEFORE_PEEL = 2  # segments on the ball, just before the peel, whose bottom is closed
TAIL_SAMPLES = 9  # rows of the peeled tongue, tip included
TWIST = 0.85  # how far a peeled tongue's face turns toward the thrower (+Z)
INSET = 0.03  # how far inside the ball's rim a turned tongue's inner edge runs (seen from behind, no slit)
# Two tongues touched up on the model sheet, by their tips alone (set after the head is placed, so the
# head holds): band 0 trails less toward the thrower, so seen from the side its hooked tip lies on its own
# tongue instead of pinching a sliver of sky against the ball; band 5 hooks 8 degrees less, so seen from
# behind its tip ends clear of the next band's root instead of pinching a lens of sky against it.
TIP_TOUCH = {0: {"sweep": 0.06}, 5: {"hook": math.radians(10)}}

# The band hulls: offsets of the inverted copy.
HULL_SIDE = 0.02
HULL_TOP = 0.02
HULL_BOTTOM = 0.012
HULL_TIP = 0.03

STREAK_LIFT = 0.004


# --- vectors -------------------------------------------------------------------------------------


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


def mean(*points):
    return tuple(sum(p[i] for p in points) / len(points) for i in range(3))


def direction(theta: float, phi: float):
    """Unit vector at colatitude `theta` from +Z (the back pole) and azimuth `phi` about Z."""
    s = math.sin(theta)
    return (s * math.cos(phi), s * math.sin(phi), math.cos(theta))


def smooth(e0: float, e1: float, x: float) -> float:
    u = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def mercator(theta: float) -> float:
    return math.log(math.tan(theta / 2.0))


def colatitude(m: float) -> float:
    return 2.0 * math.atan(math.exp(m))


# --- a ribbon: rows of section corners -----------------------------------------------------------
#
# A section is a counter-clockwise polygon in the (across, normal) plane of its row; the ribbon is
# skinned corner to corner between rows, and each face is wound by its own outward normal in that
# plane, which stays right however flat the section gets toward a tip or however far it twists.


def tent(width: float, depth: float):
    """An arm's section: ridge, left foot, right foot (the bottom is left open on the ball)."""
    h = width / 2.0
    return [(0.0, 0.0), (-h, -depth), (h, -depth)]


def blade(width: float, depth: float, flat: float):
    """A band's section: top right, top left, bottom left, bottom right. On the ball `flat` is 0 and
    the top closes to a ridge (a tent); off the ball it opens to a flat slab, whose square corners let
    the inverted hull stand off evenly all round it while the tongue twists."""
    h = width / 2.0
    return [(flat * h, 0.0), (-flat * h, 0.0), (-h, -depth), (h, -depth)]


def blade_hull(width: float, depth: float, flat: float):
    h = width / 2.0 + HULL_SIDE
    return [(flat * h, HULL_TOP), (-flat * h, HULL_TOP), (-h, -depth - HULL_BOTTOM), (h, -depth - HULL_BOTTOM)]


def place(point, across, normal, corners):
    return [add(point, add(mul(across, x), mul(normal, y))) for x, y in corners]


def quad(mesh: Mesh, a0: int, b0: int, b1: int, a1: int, facing, cross_split: bool = False) -> None:
    """Two triangles split along a0-b1: (a0, b0, b1) and (a0, b1, a1); or, `cross_split`, along b0-a1:
    (a0, b0, a1) and (b0, b1, a1). The streaks rely on the split."""
    if cross_split:
        mesh.tri(a0, b0, a1, facing)
        mesh.tri(b0, b1, a1, facing)
    else:
        mesh.tri(a0, b0, b1, facing)
        mesh.tri(a0, b1, a1, facing)


def skin(mesh: Mesh, rows: list, open_edges: list, inward: bool, cross_edges: tuple = ()) -> list[list[int]]:
    """A ribbon through `rows`, each (point, across, normal, corners) or (tip point,) for a collapsed
    end. Edge e runs from corner e to corner e + 1; `open_edges[k]` lists the edges left out of
    segment k (the bottom, on the ball). `inward` winds it as an inverted hull. The faces of the edges
    in `cross_edges` split along their other diagonal: a slab's bottom runs the opposite way round its
    section from its top, so splitting both the same way would cross their folds wherever the ribbon
    twists, pinching the slab until its own hull shows through the top as a hairline."""
    sides = max(len(row[3]) for row in rows if len(row) == 4)
    ids = []
    for row in rows:
        if len(row) == 1:
            ids.append([mesh.vert(row[0])] * sides)
        else:
            ids.append([mesh.vert(c) for c in place(*row)])
    sign = -1.0 if inward else 1.0
    for k in range(len(rows) - 1):
        full = [row for row in (rows[k], rows[k + 1]) if len(row) == 4]
        across = unit(mul(add(*[row[1] for row in full]) if len(full) == 2 else full[0][1], 1.0))
        normal = unit(mul(add(*[row[2] for row in full]) if len(full) == 2 else full[0][2], 1.0))
        for e in range(sides):
            if e in open_edges[k]:
                continue
            f = e + 1 if e + 1 < sides else 0
            fx = fy = 0.0
            for row in full:
                (x0, y0), (x1, y1) = row[3][e], row[3][f]
                fx += y1 - y0
                fy -= x1 - x0
            facing = add(mul(across, fx), mul(normal, fy))
            r0, r1 = ids[k], ids[k + 1]
            quad(mesh, r0[e], r0[f], r1[f], r1[e], mul(facing, sign), e in cross_edges)
    return ids


def clip(poly, keep):
    """The part of a (u, v) polygon where the linear function `keep` >= 0: one triangle of a slab quad."""
    out = []
    for i, cur in enumerate(poly):
        prev = poly[i - 1]
        fc, fp = keep(*cur), keep(*prev)
        if (fc >= 0) != (fp >= 0):
            s = fp / (fp - fc)
            out.append((prev[0] + (cur[0] - prev[0]) * s, prev[1] + (cur[1] - prev[1]) * s))
        if fc >= 0:
            out.append(cur)
    return out


def streak(core: Mesh, rows: list[list], normals: list, face: tuple[int, int], first: int, last: int, centre: float, spread: float, cross_split: bool = False) -> None:
    """The heated streak over rows first..last of one slope of a ribbon (face = its two corners), a lens
    pointed at both ends, centred `centre` of the way across the slope. It is cut along the slope's own
    triangles and lifted along the interpolated ring normal, so it lies on the face however the ribbon
    twists, with no crack where two of its pieces meet."""
    i, j = face
    band = []
    for k in range(first, last + 1):
        f = math.sin(math.pi * (k - first) / (last - first)) ** 0.8
        band.append((centre - spread * f, centre + spread * f))
    for k in range(first, last):
        a0, b0 = rows[k][i], rows[k][j]
        a1, b1 = rows[k + 1][i], rows[k + 1][j]
        n0, n1 = normals[k], normals[k + 1]
        (s0, s1), (t0, t1) = band[k - first], band[k - first + 1]
        poly = [(s0, 0.0), (s1, 0.0), (t1, 1.0), (t0, 1.0)]
        # u runs from a (0) to b (1). The face splits along a0-b1 into (a0, b0, b1), where u >= v, and
        # (a0, b1, a1), where u <= v; or, cross split, along b0-a1 into (a0, b0, a1), where
        # u + v <= 1, and (b0, b1, a1), where u + v >= 1.
        if cross_split:
            pieces = (
                (lambda u, v: 1.0 - u - v, lambda u, v: add(a0, add(mul(sub(b0, a0), u), mul(sub(a1, a0), v)))),
                (lambda u, v: u + v - 1.0, lambda u, v: add(b1, add(mul(sub(a1, b1), 1.0 - u), mul(sub(b0, b1), 1.0 - v)))),
            )
        else:
            pieces = (
                (lambda u, v: u - v, lambda u, v: add(a0, add(mul(sub(b0, a0), u), mul(sub(b1, b0), v)))),
                (lambda u, v: v - u, lambda u, v: add(a0, add(mul(sub(b1, a1), u), mul(sub(a1, a0), v)))),
            )
        facing = unit(cross(sub(b0, a0), sub(a1, a0)))
        if dot(facing, add(n0, n1)) < 0:
            facing = mul(facing, -1.0)
        for keep, place in pieces:
            piece = clip(poly, keep)
            if len(piece) < 3:
                continue
            ids = []
            for u, v in piece:
                lift = mul(unit(add(mul(n0, 1.0 - v), mul(n1, v))), STREAK_LIFT)
                ids.append(core.vert(add(place(u, v), lift)))
            for m in range(1, len(ids) - 1):
                core.tri(ids[0], ids[m], ids[m + 1], facing)


# --- the arms ------------------------------------------------------------------------------------


def arm_rows(k: int, rng: Rng):
    """Rows of arm `k`, from the front eye to the back one, sampled evenly in Mercator latitude."""
    phase = 2.0 * math.pi * k / ARMS + 0.08 * (rng.random() - 0.5)
    seed = SEED + 97 * k
    m_front = mercator(math.pi - ARM_END)
    m_back = mercator(ARM_END)
    cos_pitch = 1.0 / math.sqrt(1.0 + ARM_PITCH**2)

    def spine(m: float):
        theta = colatitude(m)
        phi = phase + ARM_SENSE * ARM_PITCH * (m_front - m)
        return mul(direction(theta, phi), ARM_TOP), theta

    rows, normals, thetas = [], [], []
    for i in range(ARM_SAMPLES):
        m = m_front + (m_back - m_front) * i / (ARM_SAMPLES - 1)
        p, theta = spine(m)
        a, _ = spine(m - 1e-3)
        b, _ = spine(m + 1e-3)
        tangent = unit(sub(b, a))
        radial = unit(p)
        across = unit(cross(tangent, radial))
        normal = cross(across, tangent)
        spacing = 2.0 * math.pi * ARM_TOP * math.sin(theta) * cos_pitch / ARMS
        wobble = 1.0 + 0.1 * (fbm(3.0 * i / ARM_SAMPLES, 0.3, seed) * 2.0 - 1.0)
        width = ARM_FILL * spacing * wobble
        rows.append((p, across, normal, tent(width, ARM_RIDGE)))
        normals.append(normal)
        thetas.append(theta)
    return rows, normals, thetas


# --- the bands -----------------------------------------------------------------------------------


def band_specs() -> list[dict]:
    """Tips evenly spaced about Z, long and short alternating; the head is placed from the tip."""
    rng = Rng(SEED + 1)
    specs = []
    for k in range(BANDS):
        long = k % 2 == 0
        spec = {
            "long": long,
            "theta_head": math.radians(rng.uniform(116, 124)),
            "theta_peel": math.radians(rng.uniform(80, 86)),
            "on_swirl": math.radians(rng.uniform(42, 50)),
            "peel_at": 0.58 if long else 0.63,
            "lift": 0.16 if long else 0.12,
            "sweep": 0.1 if long else 0.07,
            "hook": math.radians(34 if long else 18),
            # The tongue's rise away from the axis is a half cosine run this far: past 1 the tip hooks
            # back in; a short tongue stops short of it, or its point would tuck behind the rim.
            "curl": 1.12 if long else 0.92,
            "width_on": rng.uniform(0.12, 0.13),
            "width_peak": 0.2 if long else 0.15,
            "seed": SEED + 131 * k,
        }
        tip = 2.0 * math.pi * (k + 0.5) / BANDS + math.radians(4.0) * (rng.random() * 2.0 - 1.0)
        rate = spec["on_swirl"] / spec["peel_at"]
        travel = spec["on_swirl"] + rate * (1.0 - spec["peel_at"]) + spec["hook"]
        spec["phi_head"] = tip - BAND_SENSE * travel
        spec.update(TIP_TOUCH.get(k, {}))
        specs.append(spec)
    return specs


def band_point(spec: dict, t: float):
    """The band's ridge at t (0 head .. 1 tip), and how far it has peeled (0 on the ball .. 1 tip).

    Off the ball the tongue is drawn about Z, as the thrower sees it: it leaves the ball along the
    band's own heading, keeps winding the same way, rises away from the axis (a half cosine that
    overshoots a little, so the tip curls back in: the hook) and trails back toward +Z. Its spine
    also stands off by half its width once its face has turned to the thrower, so the tongue's inner
    edge runs along the ball's rim instead of sinking into it."""
    tp = spec["peel_at"]
    theta_rate = (spec["theta_peel"] - spec["theta_head"]) / tp
    phi_rate = spec["on_swirl"] / tp
    if t <= tp:
        theta = spec["theta_head"] + theta_rate * t
        phi = spec["phi_head"] + BAND_SENSE * phi_rate * t
        return mul(direction(theta, phi), HEAD_TOP + (BAND_TOP - HEAD_TOP) * head_rise(t / tp)), 0.0
    s = (t - tp) / (1.0 - tp)
    run = t - tp
    rho = BAND_TOP * math.sin(spec["theta_peel"])
    z_rate = -BAND_TOP * math.sin(spec["theta_peel"]) * theta_rate  # dz/dt where the band leaves the ball
    phi = spec["phi_head"] + BAND_SENSE * (spec["on_swirl"] + phi_rate * run + spec["hook"] * s**2.5)
    rise = 0.5 * (1.0 - math.cos(spec["curl"] * math.pi * s**1.4))
    rho += spec["lift"] * rise + (0.5 * band_width(spec, t) - INSET) * twist_share(s)
    # The trail back to +Z is modest and spread along the tongue, which runs across the thrower's
    # view rather than at it: a tongue flying at the camera shows foreshortened, and twists too hard
    # about a spine that points where its face should turn.
    z = BAND_TOP * math.cos(spec["theta_peel"]) + z_rate * run * (1.0 - 0.5 * s) + spec["sweep"] * smooth(0.0, 1.0, s)
    return (rho * math.cos(phi), rho * math.sin(phi), z), s


def head_rise(u: float) -> float:
    """How far a band's ridge has risen from its head (0) to its full height (1), at u = t / peel_at."""
    return smooth(0.0, HEAD_RISE, u)


def twist_share(s: float) -> float:
    """How far a peeled tongue has turned its face toward the thrower (0 .. 1)."""
    return smooth(0.0, 0.8, s)


def band_width(spec: dict, t: float) -> float:
    """Pressed in from a point at the head; on the ball a steady stroke; off it a comma, narrow where
    it leaves the ball, widest past the middle of the tongue, then a sharp point."""
    tp = spec["peel_at"]
    if t <= tp:
        u = t / tp
        return spec["width_on"] * math.sin(0.5 * math.pi * min(1.0, u / 0.3)) ** 0.8
    s = (t - tp) / (1.0 - tp)
    peak = 0.55
    if s <= peak:
        return spec["width_on"] + (spec["width_peak"] - spec["width_on"]) * math.sin(0.5 * math.pi * s / peak)
    u = (s - peak) / (1.0 - peak)
    return spec["width_peak"] * math.cos(0.5 * math.pi * u) ** 1.6


def band_ts(spec: dict) -> list[float]:
    tp = spec["peel_at"]
    on = [tp * i / (ON_SAMPLES - 1) for i in range(ON_SAMPLES)]
    tail = [tp + (1.0 - tp) * i / TAIL_SAMPLES for i in range(1, TAIL_SAMPLES + 1)]
    return on + tail


def band_frame(spec: dict, t: float):
    p, s = band_point(spec, t)
    e = 1e-3
    a, _ = band_point(spec, max(0.0, t - e))
    b, _ = band_point(spec, min(1.0, t + e))
    tangent = unit(sub(b, a))
    twist = TWIST * twist_share(s)
    facing = unit(add(mul(unit(p), 1.0 - twist), (0.0, 0.0, twist)))
    normal = unit(sub(facing, mul(tangent, dot(facing, tangent))))
    across = unit(cross(tangent, normal))
    depth = BAND_DEPTH * (1.0 - s * s)
    if s == 0.0:
        # On the ball the depth presses in with the width, so the head closes to a point inside its hull,
        # and with the rise, so the lowered head's hull still clears the arms' ridges (no ink shards).
        depth *= min(1.0, band_width(spec, t) / spec["width_on"], head_rise(t / spec["peel_at"]))
    return p, tangent, across, normal, band_width(spec, t), depth, s


def flat_share(s: float) -> float:
    """How far a peeled tongue's section has opened from a tent to a flat slab (0 .. 1)."""
    return smooth(0.0, 0.35, s)


def build_band(body: Mesh, core: Mesh, ink: Mesh, spec: dict) -> None:
    frames = [band_frame(spec, t) for t in band_ts(spec)]
    count = len(frames)
    rows = [(p, across, normal, blade(width, depth, flat_share(s))) for p, _, across, normal, width, depth, s in frames]
    # The bottom is left open on the ball, except over the last stretch before the peel, which runs
    # past the rim, where the sky would show through the open underside.
    open_edges = [(2,) if k < ON_SAMPLES - 1 - CLOSED_BEFORE_PEEL else () for k in range(count - 1)]
    skin(body, rows, open_edges, inward=False, cross_edges=(2,))
    hull = []
    for i, (p, tangent, across, normal, width, depth, s) in enumerate(frames):
        if i == 0 or i == count - 1:
            outward = mul(tangent, -1.0 if i == 0 else 1.0)
            hull.append((add(sub(p, mul(normal, 0.5 * depth)), mul(outward, HULL_TIP)),))
        else:
            hull.append((p, across, normal, blade_hull(width, depth, flat_share(s))))
    skin(ink, hull, [()] * (count - 1), inward=True, cross_edges=(2,))
    # The streaks run along the tongue where its face has turned to the thrower, not over the turn:
    # one on the top face (seen from behind), one on the bottom (seen from the front).
    corners = [place(*row) for row in rows]
    normals = [f[3] for f in frames]
    tail = [i for i, f in enumerate(frames) if 0.25 <= f[6] <= 0.9]
    streak(core, corners, normals, (0, 1), tail[0], tail[-1], 0.62, 0.22)
    streak(core, corners, [mul(n, -1.0) for n in normals], (2, 3), tail[0], tail[-1], 0.38, 0.22, cross_split=True)


# --- the ball: its hull and its eyes -------------------------------------------------------------


def build_hull(ink: Mesh) -> None:
    """An inverted UV sphere about Z: the ball's contour, and its dark core seen between the arms."""
    back = ink.vert((0.0, 0.0, HULL_R))
    front = ink.vert((0.0, 0.0, -HULL_R))
    grid = []
    for r in range(1, HULL_RINGS):
        theta = math.pi * r / HULL_RINGS
        grid.append([ink.vert(mul(direction(theta, 2 * math.pi * (s + 0.5 * (r % 2)) / HULL_SEGMENTS), HULL_R)) for s in range(HULL_SEGMENTS)])

    def inward(*ids):
        return mul(mean(*(ink.verts[i] for i in ids)), -1.0)

    for s in range(HULL_SEGMENTS):
        n = (s + 1) % HULL_SEGMENTS
        a, b = grid[0][s], grid[0][n]
        ink.tri(back, a, b, inward(back, a, b))
        a, b = grid[-1][s], grid[-1][n]
        ink.tri(front, a, b, inward(front, a, b))
    for r in range(len(grid) - 1):
        for s in range(HULL_SEGMENTS):
            n = (s + 1) % HULL_SEGMENTS
            a, b, c, d = grid[r][s], grid[r][n], grid[r + 1][s], grid[r + 1][n]
            ink.tri(a, b, c, inward(a, b, c))
            ink.tri(b, d, c, inward(b, d, c))


def build_eyes(ink: Mesh) -> None:
    """A flat dark lid over each pole, just above where the arms end: the vortex's clean eye."""
    radius = EYE_Z * math.tan(EYE_RIM)
    for sign in (1.0, -1.0):
        centre = ink.vert((0.0, 0.0, sign * (EYE_Z + 0.004)))
        ring = [ink.vert((radius * math.cos(2 * math.pi * s / EYE_SIDES), radius * math.sin(2 * math.pi * s / EYE_SIDES), sign * EYE_Z)) for s in range(EYE_SIDES)]
        for s in range(EYE_SIDES):
            ink.tri(centre, ring[s], ring[(s + 1) % EYE_SIDES], (0.0, 0.0, sign))


def build_arm(body: Mesh, core: Mesh, k: int, rng: Rng) -> None:
    rows, normals, thetas = arm_rows(k, rng)
    # Open underneath and at both ends: the arm lies on the dark ball and its ends are under the lids.
    skin(body, rows, [(1,)] * (len(rows) - 1), inward=False)
    # Two streaks, one on each hemisphere, on the right slope (right foot to ridge), over the stretch
    # between 28 and 75 degrees from its pole.
    corners = [place(*row) for row in rows]
    for lo, hi in ((math.radians(105), math.radians(152)), (math.radians(28), math.radians(75))):
        span = [i for i, th in enumerate(thetas) if lo <= th <= hi]
        if len(span) >= 3:
            streak(core, corners, normals, (2, 0), span[0], span[-1], 0.5, 0.26)


# --- the three meshes ----------------------------------------------------------------------------

_CACHE: dict = {}


def build() -> tuple[Mesh, Mesh, Mesh]:
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body = Mesh("up")
    core = Mesh("up")
    ink = Mesh("up")
    build_hull(ink)
    build_eyes(ink)
    rng = Rng(SEED)
    for k in range(ARMS):
        build_arm(body, core, k, rng)
    for spec in band_specs():
        build_band(body, core, ink, spec)
    reach = max(math.hypot(x, y) for mesh in (body, core, ink) for x, y, _ in mesh.verts)
    for mesh in (body, core, ink):
        mesh.scale(0.5 / reach)
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta() -> dict:
    return {"Reference": "Diameter", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": SEED}


def fire_body() -> tuple[Mesh, dict]:
    return build()[0], meta()


def fire_core() -> tuple[Mesh, dict]:
    return build()[1], meta()


def fire_ink() -> tuple[Mesh, dict]:
    return build()[2], meta()


if __name__ == "__main__":
    for name, fn in (("body", fire_body), ("core", fire_core), ("ink", fire_ink)):
        mesh, _ = fn()
        low, high = mesh.bounds()
        radial = max(math.hypot(x, y) for x, y, _ in mesh.verts)
        print(f"{name}: {len(mesh.tris)} tris, x {low[0]:.3f}..{high[0]:.3f}  y {low[1]:.3f}..{high[1]:.3f}  z {low[2]:.3f}..{high[2]:.3f}  radial {2 * radial:.4f}")
