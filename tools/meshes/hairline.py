"""The Hairline's wind sickle (Verdigris): one plein-délié pen stroke flying across the line of flight.

Drawn after the developer's two references (docs/vfx/hairline/ref-1.jpg, the sickle in flight in the
courtyard; ref-2.jpg, the model sheet "Verdigris ink wind sickle"). The sheet wins on shape, the shot on
scale against the avatar.

The body is a single stroke of the pen (art bible K2, the plein-délié crescent). Its spine is written by
its curvature, as a hand writes it: it starts in the eye of a scroll at the top (the head), unwinds a
full turn, runs over the top and down the convex side in a deep C -- the plein, swollen past the middle
-- and rolls into a scroll at the bottom (the tail) about two thirds the size of the top one, as the sheet
draws it. It curves one way all along, so both scrolls roll into the hollow of the C. Its section is a
lens: a sharp leading edge on the convex side (a bevel), a sharp trailing edge inside, thin through -- a
fifth of its width -- so in profile it is the thinnest glyph in the game.

The C stands across the flight, its face to the thrower, so from over the shoulder it is a sickle. It
leans in depth: upright as the timeline's Roll sets it, its top leads (-Z) and its foot trails toward the
thrower (+Z), 0.3 of its height, so from the side it is one straight needle and from above a crescent
with a curl at each tip (the sheet's side and top-down views). Its two ends trail a little behind its
middle besides, and each scroll keeps winding back as it closes, so its turns stand apart in depth and
the contour of each one is drawn over the next from either side (the sheet's "tips curl back toward the
caster").

Three dry whips fray out of the stroke's outer edge where it turns into the bottom scroll, as a dry brush
splits at the end of a stroke. Each is rooted inside the blade, on its middle surface, and leaves it
through the leading edge -- never through a face, and its contour is pushed out in the blade's plane until
it is past the edge, so nothing of it shows on the blade where it splits. Then they fan out below the C,
trailing back toward the thrower as they go: the outer one sweeps out past the convex edge and hooks back
up, against the stroke's turn, as the sheet's longest whip does; the middle one hangs and flicks the same
way; the inner one hangs under the bottom scroll and curls with the stroke. Unequal (1.85, 1.35 and 1.65
studs all told, under the 2-stud cap), each ending in a hook; thin, so their contour is most of them --
black strokes with a thread of green, as the sheet draws them. They fan where the 7-stud sphere has room,
so they read from the front, the three quarters, the side, above and behind -- from behind, out past the
convex edge.

Three meshes, one tone each, from one construction, one scale and one pivot:
  - wind_blade (Pigment): the stroke and its three whips, closed and wound outward.
  - wind_edge (Core): the pale thread, a lens-shaped strip on the leading bevel of each face, lifted
    0.045 stud off it, always inside the pigment (never on the outer edge), over the swollen stretch.
  - wind_ink (Ink): the inverted hull of the stroke and of each whip -- 0.23 stud at the plein, 0.105 at
    every tip and along every whip, never under 0.1 (the bible's Verdigris row and floor, the sheet's
    notes) -- and three calligraphic flow lines in the hollow of the C, lifted 0.04 stud.

Units: every weight, lift, length and radius above is set in final units (studs, over STUDS) and
converted by the stroke's own span before the normalising scale, so what is written here is what ships.
The stroke's two farthest points are exactly 1 apart (Reference "Span": 5.6 studs at runtime); the pivot
(0, 0, 0) is the centre of the smallest sphere round all three meshes, and everything lies within 0.625
of it (the server's 7-stud hit sphere at that size). The widest part of the stroke is about 0.15 (0.85
stud). Roblox space: X right, Y up, forward -Z. Axis Z (the flight); the meshes are modelled with the
chord from tip to tip along Y and the timeline's Roll (-35) tilts them.
"""

from __future__ import annotations

import math

from strokes import (
    Mesh,
    Volume,
    add,
    cosine_curve,
    cross,
    dot,
    emit,
    face_normal,
    fbm,
    mul,
    norm,
    smoothstep,
    sub,
)

SEED = 5603
ROLL = -35.0  # degrees about Z, applied by the timeline; baked only into the *_rolled sheet meshes
STUDS = 5.6  # the span at runtime: final units are studs / STUDS

# --- the stroke ------------------------------------------------------------------------------------
# Curvature along the stroke, by arc-length fraction (head 0 .. tail 1), interpolated in log: tight in
# the eye of the top scroll, unwinding over a full turn, a steady deep C, tightening into the bottom
# scroll -- the top scroll's own profile at about half its size, so the tail curls as tightly but smaller.
KAPPA = [(0.0, 19.0), (0.05, 15.5), (0.1, 11.5), (0.15, 7.6), (0.2, 4.6), (0.27, 2.3), (0.42, 1.65),
         (0.6, 1.75), (0.78, 2.3), (0.86, 6.0), (0.895, 12.5), (0.92, 21.0), (0.945, 30.0), (0.972, 39.0), (1.0, 45.0)]
LENGTH = 2.7  # arc length in construction units (only the curvature's scale)
# Width across the stroke (in construction units, about the final span): a hair in the top eye, the
# scroll's own stroke, swelling over the top into the plein on the convex side past the middle, drying
# into the smaller bottom scroll and a hair in its eye.
WIDTH = [(0.0, 0.014), (0.045, 0.058), (0.13, 0.085), (0.27, 0.13), (0.5, 0.2), (0.6, 0.184), (0.77, 0.1),
         (0.855, 0.05), (0.925, 0.032), (0.972, 0.02), (1.0, 0.01)]
THICK = (0.2, 0.003)  # the lens's thickness: share of the width, plus a floor
TOP_SCROLL = 0.24  # where the top scroll ends (arc-length fraction)
BOTTOM_SCROLL = 0.86  # where the bottom scroll begins
TILT = 0.3  # the C's lean in depth: its top leads (-Z), its foot trails (+Z), per unit of height after the Roll
CAMBER = 0.03  # and how far its two ends trail back (+Z) behind its middle besides
SCROLL_BACK = (0.012, 0.01)  # how far each scroll winds back (+Z) by its eye: top, bottom
STATIONS = 50

# The lens: (across, side) round the ring -- the leading edge (+1, on the convex side), the back face
# (+1: toward the thrower), the trailing edge (-1, in the hollow), the front face. The bevel from 0.62
# to the leading edge carries the pale thread.
SECTION = ((1.0, 0), (0.62, 1), (-0.25, 1), (-1.0, 0), (-0.25, -1), (0.62, -1))

# The contour's weight, in studs at the final size: 0.23 at the plein (the bible's Verdigris row,
# 0.20-0.28), 0.105 at every hair and along every whip (its floor is 0.1).
W_MID = 0.2 / STUDS
W_TIP = 0.102 / STUDS

# --- the whips -------------------------------------------------------------------------------------
# Each whip is written as a pen writes it, in final units (studs): it leaves the stroke's leading edge in
# the blade's own plane, runs straight for `exit`, then sweeps -- turning `bend` degrees in the blade's
# plane and `back` degrees out of it toward the thrower (+Z), so it trails behind the sickle -- and closes
# into a hook: `hook` degrees over its last `hook_len`, its bend tilted `hook_tilt` from the blade's plane
# (0: the hook curls in the plane, read from the front and from behind; 90: it curls toward the thrower,
# read in profile). In-plane turns are signed: + against the stroke's own turn (out, away from the C),
# - with it (round, the way the stroke itself turns into its scrolls).
# (root along the stroke, root across (inside the blade, on its middle plane), angle out of the stroke
# toward its leading edge (degrees), length in studs all told (the sheet's and the bible's cap is 2),
# exit, bend, back, hook_len, hook, hook_tilt, root radius in studs)
WHIPS = (
    (0.69, 0.6, 60.0, 1.9, 0.3, 30.0, 10.0, 0.7, -170.0, 0.0, 0.045),
    (0.75, 0.6, 40.0, 1.7, 0.3, -10.0, 40.0, 0.6, -160.0, 50.0, 0.04),
    (0.8, 0.6, 22.0, 1.8, 0.25, -25.0, 70.0, 0.6, -150.0, 90.0, 0.035),
)
WHIP_BODY = 6  # rings along the exit and the sweep
WHIP_HOOK = 8  # rings along the hook, so it turns smoothly

# --- the pale thread and the flow lines ------------------------------------------------------------
# from, to (along), centre across, half-width at its widest (construction units, so it does not dry up
# with the stroke), and its cap across (it stays on the bevel, from 0.62 to the edge)
THREAD = (0.18, 0.74, 0.5, 0.0045, 0.1)
THREAD_LIFT = 0.07 / STUDS  # the bible's Core lift is 0.03-0.08 stud
# (side, from, to, across at start, across at end, width)
FLOW = (
    (1, 0.3, 0.72, -0.5, -0.42, 0.016),
    (1, 0.5, 0.64, 0.2, -0.05, 0.012),
    (-1, 0.26, 0.66, -0.46, -0.52, 0.016),
)
FLOW_LIFT = 0.04 / STUDS


# --- the spine -------------------------------------------------------------------------------------

_LOGK = [(u, math.log(k)) for u, k in KAPPA]


def _kappa(u: float) -> float:
    return math.exp(cosine_curve(_LOGK, u))


def _spine2d(n: int = 1600):
    """The spine in its own plane, integrated from its curvature: (u, x, y) samples, head first."""
    out = [(0.0, 0.0, 0.0)]
    heading = 0.0
    x = y = 0.0
    for i in range(1, n + 1):
        u0, u1 = (i - 1) / n, i / n
        k = _kappa(0.5 * (u0 + u1))
        dl = LENGTH * (u1 - u0)
        mid = heading + 0.5 * k * dl
        heading += k * dl
        x += math.cos(mid) * dl
        y += math.sin(mid) * dl
        out.append((u1, x, y))
    return out


def _farthest(points):
    best = (0.0, 0, 0)
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            d = math.dist(points[i], points[j])
            if d > best[0]:
                best = (d, i, j)
    return best


def _upright(samples):
    """Turns the spine so its two farthest points lie on Y, the head on top and the C bulging to -X;
    scales it to a span of about 1 (the exact scale is set on the finished meshes)."""
    coarse = samples[:: max(1, len(samples) // 300)]
    d, i, j = _farthest([(x, y) for _, x, y in coarse])
    (_, xa, ya), (_, xb, yb) = coarse[i], coarse[j]
    if coarse[i][0] > coarse[j][0]:
        xa, ya, xb, yb = xb, yb, xa, ya
    # Rotate so b -> a points up (+Y): the head's end is a.
    angle = math.atan2(xa - xb, ya - yb)
    c, s = math.cos(angle), math.sin(angle)
    pts = [(u, (x - xb) * c - (y - yb) * s, (x - xb) * s + (y - yb) * c) for u, x, y in samples]
    # The bulge of the C to -X.
    mid = min(pts, key=lambda p: abs(p[0] - 0.5))
    ends = (pts[0][1] + pts[-1][1]) / 2
    if mid[1] > ends:
        pts = [(u, -x, y) for u, x, y in pts]
    pts = [(u, x / d, y / d) for u, x, y in pts]
    ys = [p[2] for p in pts]
    cy = (max(ys) + min(ys)) / 2
    return [(u, x, y - cy) for u, x, y in pts]


class _Spine:
    def __init__(self) -> None:
        self.flat = _upright(_spine2d())
        n = len(self.flat) - 1
        self.n = n

    def at2(self, u: float):
        f = min(max(u, 0.0), 1.0) * self.n
        i = min(int(f), self.n - 1)
        t = f - i
        _, xa, ya = self.flat[i]
        _, xb, yb = self.flat[i + 1]
        return xa + (xb - xa) * t, ya + (yb - ya) * t

    def depth(self, u: float, x: float, y: float) -> float:
        """+Z, back toward the thrower. The C leans: measured upright after the timeline's Roll, its top
        leads and its foot trails, so from the side it is one straight needle and from above a crescent
        (the sheet's side and top-down views); its ends trail a little behind its middle; and each
        scroll winds back."""
        a = math.radians(ROLL)
        upright = x * math.sin(a) + y * math.cos(a)
        z = TILT * (0.5 - upright)
        z += CAMBER * min(1.0, (y / 0.5) ** 2)
        z += SCROLL_BACK[0] * (1.0 - smoothstep(0.0, TOP_SCROLL, u)) ** 1.2
        z += SCROLL_BACK[1] * smoothstep(BOTTOM_SCROLL, 1.0, u) ** 1.2
        return z

    def point(self, u: float):
        x, y = self.at2(u)
        return (x, y, self.depth(u, x, y))

    def frame(self, u: float):
        """Point, tangent, across (toward the convex, leading edge) and face normal (+Z side)."""
        e = 1.0 / self.n
        p = self.point(u)
        a, b = self.point(max(0.0, u - e)), self.point(min(1.0, u + e))
        tangent = norm(sub(b, a))
        across = norm(cross(tangent, (0.0, 0.0, 1.0)))
        # The C's hollow is on the side its curvature points to; the leading edge is the other side.
        bend = sub(add(a, b), mul(p, 2.0))
        if dot(across, bend) > 0:
            across = mul(across, -1.0)
        normal = norm(cross(across, tangent))
        if normal[2] < 0:
            normal = mul(normal, -1.0)
        return p, tangent, across, normal

    def turn_sign(self) -> float:
        """+1 when the stroke turns counter-clockwise in XY seen from +Z, -1 when clockwise."""
        (xa, ya), (xb, yb), (xc, yc) = self.at2(0.49), self.at2(0.5), self.at2(0.51)
        return 1.0 if (xb - xa) * (yc - yb) - (yb - ya) * (xc - xb) > 0 else -1.0


def _width(u: float) -> float:
    return cosine_curve(WIDTH, u) * (1.0 + 0.06 * (fbm(5.0 * u, 0.3, SEED) * 2.0 - 1.0))


def _weight(w: float) -> float:
    peak = max(v for _, v in WIDTH)
    return W_TIP + (W_MID - W_TIP) * min(1.0, w / peak) ** 4.0


def _stations(spine: _Spine) -> list[float]:
    """Stations spaced by arc length and by turning together, so the scrolls get as many as the C."""
    n = 2000
    acc = [0.0]
    for i in range(1, n + 1):
        u = (i - 0.5) / n
        acc.append(acc[-1] + (1.0 / n) * (1.0 + 0.22 * _kappa(u)))
    out = []
    for k in range(STATIONS + 1):
        target = acc[-1] * k / STATIONS
        j = next(i for i in range(len(acc)) if acc[i] >= target - 1e-12)
        out.append(min(1.0, j / n))
    out[0], out[-1] = 0.0, 1.0
    return out


def _section(frame, w: float, side_u: float, side: int):
    p, _, across, normal = frame
    th = THICK[0] * w + THICK[1]
    h = 0.5 * th * (1.0 - side_u * side_u) * side
    return add(p, add(mul(across, 0.5 * w * side_u), mul(normal, h)))


def _on_face(frame, w: float, across_u: float, side: int, lift: float):
    """A point on the faceted face (side +1 back, -1 front) at `across_u`, lifted off it."""
    faces = sorted([(u, s) for u, s in SECTION if s == side] + [(1.0, 0), (-1.0, 0)])
    for (u0, s0), (u1, s1) in zip(faces, faces[1:]):
        if u0 - 1e-9 <= across_u <= u1 + 1e-9:
            f = (across_u - u0) / (u1 - u0)
            a = _section(frame, w, u0, s0)
            b = _section(frame, w, u1, s1)
            q = add(a, mul(sub(b, a), f))
            # The facet's normal: along the section, out of this face.
            _, tangent, _, _ = frame
            n = norm(cross(tangent, sub(b, a)))
            if dot(n, frame[3]) * side < 0:
                n = mul(n, -1.0)
            return add(q, mul(n, lift))
    raise ValueError(across_u)


# --- the solids ------------------------------------------------------------------------------------


def _blade(spine: _Spine, us: list[float]) -> Volume:
    """The stroke, closed and wound outward; its contour weights are in final units."""
    vol = Volume()
    frames = [spine.frame(u) for u in us]
    widths = [_width(u) for u in us]
    rings = []
    for k in range(1, len(us) - 1):
        wgt = _weight(widths[k])
        rings.append([vol.vert(_section(frames[k], widths[k], u, s), wgt) for u, s in SECTION])
    m = len(SECTION)
    for a, b in zip(rings, rings[1:]):
        for j in range(m):
            jn = (j + 1) % m
            emit(vol.mesh, a[j], a[jn], b[jn])
            emit(vol.mesh, a[j], b[jn], b[j])
    # Each end is a hair: a single point a little past the last ring, in the eye of its scroll.
    head = vol.vert(sub(frames[0][0], mul(frames[0][1], 0.004)), W_TIP)
    tail = vol.vert(add(frames[-1][0], mul(frames[-1][1], 0.004)), W_TIP)
    first, last = rings[0], rings[-1]
    for j in range(m):
        jn = (j + 1) % m
        emit(vol.mesh, head, first[jn], first[j])
        emit(vol.mesh, tail, last[j], last[jn])
    vol.orient_outward()
    return vol


def _whip_path(spine: _Spine, whip, unit: float, steps: int = 240):
    """A whip's centre line, in construction units: out of the leading edge at `out` degrees from the
    stroke, straight for `exit`, then the sweep and the hook, each bending at constant curvature in a
    plane carried along the whip by parallel transport (so a hook's tilt means the same thing however
    far the sweep has turned the whip back toward the thrower). Held on the blade's middle surface for
    as long as it runs inside the blade."""
    u0, across, out, length, exit_, bend_in, back, hook_len, hook, hook_tilt, _ = whip
    sweep = math.copysign(math.hypot(bend_in, back), bend_in if bend_in else 1.0)
    sweep_tilt = math.degrees(math.atan2(back, abs(bend_in)))
    p, tangent, acr, normal = spine.frame(u0)
    w = _width(u0)
    root = add(p, mul(acr, 0.5 * w * across))
    a = math.radians(out)
    t = norm(add(mul(tangent, math.cos(a)), mul(acr, math.sin(a))))
    # The transported frame: `side` in the blade's plane (+ against the stroke's turn, i.e. toward its
    # convex, leading side), `lift` out of it toward the thrower (+Z side of the blade).
    side = norm(sub(acr, mul(t, dot(acr, t))))
    lift = norm(cross(t, side))
    if lift[2] < 0:
        lift = mul(lift, -1.0)
    scale = unit / STUDS
    total = length * scale
    body_end = (length - hook_len) * scale
    exit_end = exit_ * scale
    sweep_k = math.radians(sweep) / max(1e-9, body_end - exit_end)
    hook_k = math.radians(hook) / (0.85 * hook_len * scale)  # ramped in over its first 30 %
    ds = total / steps
    pts = [root]
    q = root
    for i in range(steps):
        s = (i + 0.5) * ds
        if s < exit_end:
            k, tilt = 0.0, 0.0
        elif s < body_end:
            k, tilt = sweep_k * smoothstep(exit_end, exit_end + 0.25 * (body_end - exit_end), s), sweep_tilt
        else:
            k, tilt = hook_k * smoothstep(body_end, body_end + 0.3 * hook_len * scale, s), hook_tilt
        g = math.radians(tilt)
        sign = 1.0 if k >= 0 else -1.0
        bend = norm(add(mul(side, sign * math.cos(g)), mul(lift, math.sin(g))))
        half = add(t, mul(bend, 0.5 * abs(k) * ds))
        q = add(q, mul(norm(half), ds))
        t = norm(add(t, mul(bend, abs(k) * ds)))
        side = norm(sub(side, mul(t, dot(side, t))))
        lift = norm(cross(t, side)) if dot(cross(t, side), lift) >= 0 else mul(norm(cross(t, side)), -1.0)
        pts.append(q)
    return _bury(spine, u0, pts)


def _on_blade(spine: _Spine, u0: float, q):
    """Where a point near a whip's root sits on the blade: (across, in half-widths of the stroke, the
    station's face normal, the offset along it, the stroke's width there), from the nearest station of
    the stroke around u0."""
    best = None
    for i in range(-60, 61):
        u = min(max(u0 + i * 0.00125, 0.0), 1.0)
        c = spine.point(u)
        d = (q[0] - c[0]) ** 2 + (q[1] - c[1]) ** 2 + (q[2] - c[2]) ** 2
        if best is None or d < best[0]:
            best = (d, u)
    c, _, acr, normal = spine.frame(best[1])
    rel = sub(q, c)
    w = _width(best[1])
    return dot(rel, acr) / (0.5 * w), normal, dot(rel, normal), w


def _face_height(a: float, w: float) -> float:
    """How far the faceted lens's faces stand off its middle plane at `a` (half-widths across)."""
    th = THICK[0] * w + THICK[1]
    pts = sorted({(u, 0.5 * th * (1.0 - u * u) * abs(s)) for u, s in SECTION} | {(1.0, 0.0), (-1.0, 0.0)})
    pts = [p for p in pts if p[1] > 0 or abs(p[0]) == 1.0]
    for (a0, h0), (a1, h1) in zip(pts, pts[1:]):
        if a0 <= a <= a1:
            return h0 + (h1 - h0) * (a - a0) / (a1 - a0)
    return 0.0


def _bury(spine: _Spine, u0: float, points):
    """Holds a whip's centre line on the blade's middle surface for as long as it runs inside the
    blade, easing off over half a width past the leading edge: so it leaves through the edge, never
    through a face. Once out, it is free (a whip trailing back behind the face is not pulled onto it)."""
    out = []
    free = False
    for q in points:
        a, normal, h, _ = _on_blade(spine, u0, q)
        free = free or a >= 1.5
        keep = 0.0 if free else 1.0 - smoothstep(1.0, 1.5, a)
        out.append(sub(q, mul(normal, h * keep)))
    return out


def _sink(spine: _Spine, u0: float, q, room: float):
    """A point of a whip (or of its contour) still over the blade's outline, pulled down along the
    face normal until it lies within `room` of the faceted face's height: nothing of a buried root
    can break through the face the thrower sees."""
    a, normal, h, w = _on_blade(spine, u0, q)
    if abs(a) >= 1.0:
        return q
    limit = room * _face_height(a, w)
    if abs(h) <= limit:
        return q
    return sub(q, mul(normal, h - math.copysign(limit, h)))


def _resample_at(points, stations):
    """Points at the given arc lengths along a polyline (construction units)."""
    acc = [0.0]
    for i in range(1, len(points)):
        acc.append(acc[-1] + math.dist(points[i - 1], points[i]))
    out = []
    j = 1
    for target in stations:
        target = min(target, acc[-1])
        while j < len(acc) - 1 and acc[j] < target:
            j += 1
        f = (target - acc[j - 1]) / max(acc[j] - acc[j - 1], 1e-12)
        a, b = points[j - 1], points[j]
        out.append(tuple(a[i] + (b[i] - a[i]) * f for i in range(3)))
    return out, acc[-1]


def _ring_radius(radius: float, f: float, unit: float) -> float:
    """A whip's radius at arc fraction `f`: tapering from `radius` at the root to a hair (0.009 stud)."""
    return radius * (1.0 - f) ** 1.2 + 0.0016 * unit


def _tube(spine: _Spine, u0: float, centres, fracs, radius: float, unit: float, up0) -> Volume:
    """A tapered three-sided whip through `centres`, its section carried by parallel transport from the
    blade's face normal -- one corner in the blade's plane, two above and below it -- a root cap buried
    in the blade and a single-vertex tip. Its contour is W_TIP plus a quarter of its radius (final
    units), never under W_TIP where it can be seen; inside the blade it ramps up from nothing, so the
    buried root's contour stays buried too. Every vertex still over the blade's outline is sunk under
    its face (`_sink`), and so is its contour (`_hull`)."""
    vol = Volume()
    vol.root = (spine, u0)
    vol.sink = []
    segs = len(centres) - 1
    # The root: the rings up to the first whose centre is past the leading edge. Only they are sunk,
    # and only their contour ramps up (from nothing deep inside to full at the edge).
    across = [_on_blade(spine, u0, c)[0] for c in centres]
    out_at = next((i for i, a in enumerate(across) if a >= 1.0), segs)
    tangents = [norm(sub(centres[min(i + 1, segs)], centres[max(i - 1, 0)])) for i in range(segs + 1)]
    up = norm(sub(up0, mul(tangents[0], dot(up0, tangents[0]))))
    rings = []
    for i in range(segs):
        along = tangents[i]
        up = norm(sub(up, mul(along, dot(up, along))))
        side = norm(cross(along, up))
        root = i <= out_at
        r = _ring_radius(radius, fracs[i], unit) * (0.3 + 0.7 * smoothstep(0.3, 1.0, across[i]) if root else 1.0)
        ramp = min(1.0, i / 2.0) * smoothstep(0.55, 1.05, max(across[: i + 1])) if root else 1.0
        ring = []
        for k in range(3):
            angle = 2 * math.pi * k / 3
            q = add(centres[i], add(mul(up, r * math.sin(angle)), mul(side, r * math.cos(angle))))
            ring.append(vol.vert(_sink(spine, u0, q, 0.2) if root else q, (W_TIP + 0.25 * r / unit) * ramp))
            vol.sink.append(root)
        rings.append(ring)
    tip = vol.vert(centres[-1], W_TIP)
    vol.sink.append(False)
    for a, b in zip(rings, rings[1:]):
        for j in range(3):
            k = (j + 1) % 3
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    last = rings[-1]
    for j in range(3):
        emit(vol.mesh, last[j], last[(j + 1) % 3], tip)
    first = rings[0]
    emit(vol.mesh, first[0], first[2], first[1])
    vol.orient_outward()
    return vol


def _whips(spine: _Spine, unit: float) -> list[Volume]:
    """The three whips, each a tube along its centre line; rings spaced evenly along the exit and the
    sweep, and closer along the hook so it turns round smoothly."""
    out = []
    for whip in WHIPS:
        path = _whip_path(spine, whip, unit)
        length, hook_len = whip[3], whip[7]
        body_end = (length - hook_len) / length
        fr = [body_end * i / WHIP_BODY for i in range(WHIP_BODY)]
        fr += [body_end + (1.0 - body_end) * (1.0 - (1.0 - i / WHIP_HOOK) ** 1.15) for i in range(WHIP_HOOK + 1)]
        _, total = _resample_at(path, [0.0])
        centres, _ = _resample_at(path, [f * total for f in fr])
        normal = spine.frame(whip[0])[3]
        out.append(_tube(spine, whip[0], centres, fr, whip[-1] / STUDS * unit, unit, normal))
    return out

# --- the pale thread and the flow lines ------------------------------------------------------------


def _thread(core: Mesh, spine: _Spine, us: list[float], unit: float) -> None:
    """The pale thread on the leading bevel of each face: a lens-shaped strip, lifted THREAD_LIFT, that
    closes to a point at each end (a single vertex there, so its ends are not needles)."""
    lo, hi, centre, widest, cap = THREAD

    def taper(u: float) -> float:
        return math.sin(math.pi * (u - lo) / (hi - lo)) ** 0.7

    span = [u for u in us if lo <= u <= hi]
    # One point at each end: the last station still under the taper's threshold before the strip opens,
    # and the first one after it closes (a run of points would leave all but one of them unused).
    wide = [k for k, u in enumerate(span) if taper(u) >= 0.3]
    span = span[max(0, wide[0] - 1) : wide[-1] + 2]
    for side in (1, -1):
        rows = []
        for u in span:
            f = taper(u)
            frame = spine.frame(u)
            w = _width(u)
            half = min(cap, widest * f / (0.5 * w))
            if f < 0.3:
                c = core.vert(_on_face(frame, w, centre, side, THREAD_LIFT * unit))
                rows.append(((c,), frame[3]))
                continue
            a = _on_face(frame, w, centre - half, side, THREAD_LIFT * unit)
            b = _on_face(frame, w, centre + half, side, THREAD_LIFT * unit)
            rows.append(((core.vert(a), core.vert(b)), frame[3]))
        for (r0, n0), (r1, _) in zip(rows, rows[1:]):
            facing = mul(n0, side)
            if len(r0) == 2 and len(r1) == 2:
                core.tri(r0[0], r0[1], r1[1], facing)
                core.tri(r0[0], r1[1], r1[0], facing)
            elif len(r0) == 1 and len(r1) == 2:
                core.tri(r0[0], r1[0], r1[1], facing)
            elif len(r0) == 2 and len(r1) == 1:
                core.tri(r0[0], r0[1], r1[0], facing)


def _flow_lines(ink: Mesh, spine: _Spine, us: list[float], unit: float) -> None:
    """Calligraphic flow lines in the hollow of the C, lifted FLOW_LIFT off their face: each starts in a
    point, swells in its first third and dries toward its end, where it closes to a point again."""
    for side, lo, hi, c0, c1, width in FLOW:
        gap = 0.4 * (hi - lo) / max(1, sum(1 for u in us if lo <= u <= hi))
        span = [lo] + [u for u in us if lo + gap <= u <= hi - gap] + [hi]
        rows = []
        for k, u in enumerate(span):
            tau = (u - lo) / (hi - lo)
            frame = spine.frame(u)
            w = _width(u)
            c = c0 + (c1 - c0) * tau
            if k in (0, len(span) - 1):
                rows.append(((ink.vert(_on_face(frame, w, c, side, FLOW_LIFT * unit)),), frame[3]))
                continue
            line = width * (math.sin(math.pi * min(1.0, tau / 0.35) / 2.0) ** 0.8) * (1.0 - 0.85 * tau ** 1.6)
            half = max(line, width * 0.18) / w
            lo_u, hi_u = max(-0.97, c - half), min(0.6, c + half)
            a = _on_face(frame, w, lo_u, side, FLOW_LIFT * unit)
            b = _on_face(frame, w, hi_u, side, FLOW_LIFT * unit)
            rows.append(((ink.vert(a), ink.vert(b)), frame[3]))
        for (r0, n0), (r1, _) in zip(rows, rows[1:]):
            facing = mul(n0, side)
            if len(r0) == 2 and len(r1) == 2:
                ink.tri(r0[0], r0[1], r1[1], facing)
                ink.tri(r0[0], r1[1], r1[0], facing)
            elif len(r0) == 1:
                ink.tri(r0[0], r1[0], r1[1], facing)
            else:
                ink.tri(r0[0], r0[1], r1[0], facing)


# --- the contour ----------------------------------------------------------------------------------


def _hull(vol: Volume, into: Mesh, unit: float) -> None:
    """The contour of a closed volume in the air: every vertex pushed out along its normal by its
    weight (final units, so times `unit` here, before the normalising scale), every triangle wound the
    other way (strokes.inverted_hull without its floor: this body never touches the page). A whip's
    contour still over the blade's outline is sunk under the blade's face, as its pigment is."""
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        n = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
    root = getattr(vol, "root", None)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        q = add(p, mul(norm(acc[i]), vol.weight[i] * unit))
        if root is not None and vol.sink[i]:
            q = _sink(root[0], root[1], q, 0.3)
        into.verts.append(q)
    for a, b, c in mesh.tris:
        emit(into, a + base, c + base, b + base)

# --- the three meshes ------------------------------------------------------------------------------

_CACHE: dict = {}


def _centre(points) -> tuple[float, float, float]:
    """Centre of (about) the smallest sphere round the points (Badoiu-Clarkson)."""
    c = tuple(sum(p[k] for p in points) / len(points) for k in range(3))
    for i in range(1, 3000):
        far = max(points, key=lambda p: (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2)
        c = tuple(c[k] + (far[k] - c[k]) / (i + 1) for k in range(3))
    return c


def parts():
    """The construction before the normalising scale: spine, stations, blade, whips and `unit`, the
    stroke's span in construction units (the length that becomes 1)."""
    if "parts" in _CACHE:
        return _CACHE["parts"]
    spine = _Spine()
    us = _stations(spine)
    blade = _blade(spine, us)
    unit, _, _ = _farthest(blade.mesh.verts)
    whips = _whips(spine, unit)
    _CACHE["parts"] = (spine, us, blade, whips, unit)
    return _CACHE["parts"]


def build() -> tuple[Mesh, Mesh, Mesh]:
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    spine, us, blade, whips, unit = parts()
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    body.merge(blade.mesh)
    for vol in whips:
        body.merge(vol.mesh)
    _thread(core, spine, us, unit)
    _hull(blade, ink, unit)
    for vol in whips:
        _hull(vol, ink, unit)
    _flow_lines(ink, spine, us, unit)
    # Exactly 1 between the stroke's two farthest points, by one scale for all three, about the centre
    # of the smallest sphere round them all.
    for mesh in (body, core, ink):
        mesh.scale(1.0 / unit)
    c = _centre([v for mesh in (body, core, ink) for v in mesh.verts])
    for mesh in (body, core, ink):
        mesh.translate(mul(c, -1.0))
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta() -> dict:
    return {"Reference": "Span", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": SEED}


def wind_blade() -> tuple[Mesh, dict]:
    return build()[0], meta()


def wind_edge() -> tuple[Mesh, dict]:
    return build()[1], meta()


def wind_ink() -> tuple[Mesh, dict]:
    return build()[2], meta()
