"""The Stipple's mud slug: an umber ink mud slug spat across the page, drawn after the developer's two
references (docs/vfx/stipple/ref-1.jpg, the slug in game; ref-2.jpg, its model sheet).

Roblox space: X right, Y up, forward -Z. The slug flies nose first (-Z); the thrower sees it from behind
(+Z) and above, so the bead chain and the forked tail come at the camera and the two pale lobes stand
up on its back like ears.

What it is made of (body units: the slug from nose to tail end is 1 long, before the final scale):
  - the body: a smooth turned teardrop (K6 a), closed all round: a round head forward with a slight
    neck behind it, widest a little further back, tapering to a raised tail. Smooth on purpose: the one
    Umber body without facets (mud, not a boulder).
  - the dark belly: a crescent of ink lying on the closed pigment underneath, lifted off it -- never a
    hole in it, so when the slug collapses and its ink fades first, umber is what is left. A smile under
    the head seen head on, widest under the head and the front of the belly, running out to a point
    before the tail.
  - two wet gloss lobes on its back, left and right of the spine, toed in toward the head and broader
    toward the tail; each stands proud of the body like a pill, its own hull ringing its foot, and each
    carries a pale cap with a band of umber round it.
  - two short squirts forking off the tail in a V (K5), curling up, each ending in a round drop.
  - three detached round beads trailing behind (K6 c), shrinking with distance, each with its own hull
    and a small pale cap.
Three meshes, one tone each: mud_body (Pigment), mud_gloss (Core: lobe caps, the wet spot on the nose,
the bead caps), mud_ink (Ink: every hull, the belly crescent, the flow lines down the tail).

Every thickness the eye must read -- contour, lifts, a flow line's width -- is set in studs at the size
the slug is drawn (LENGTH_STUDS) and turned into body units here, so a change of size re-weights them.
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
    inverted_hull,
    mul,
    norm,
    smoothstep,
    sub,
    surface_ribbon,
)

SEED = 6611
Y_OFF = 1.0  # everything is built this high and dropped back at the end: the strokes helpers clamp at the floor

# --- size --------------------------------------------------------------------------------------------
# The slug, ink included, from the nose's contour to the last bead's, in studs. The in-game reference
# (ref-1) draws it about as long as the character is tall, and 6.2 fits the server's damage sphere
# (HitRadius 4: the furthest point is about 3.1 studs from the pivot, 3.9 with the 1.25 release stretch).
# The model sheet and the bible say 2.6: the developer's call, and this one number re-weights every
# stud thickness below.
LENGTH_STUDS = 6.2
# The body's contour along it, at its vertices (u, studs): loaded on the head, heaviest where the hull's
# facets cut deepest across the skin's (the widening behind the neck), down to the bible's floor on the
# tail's concave taper, where the hull stands off the skin by more than its weight; heavier again on the
# tail's closing cone, whose steep faces keep the least of it. Each was set until the thinnest point of the
# faceted contour, measured on the skin's faces, sat a hair over 0.1 stud.
HULL_STUDS = [(0.0, 0.12), (0.16, 0.12), (0.3, 0.126), (0.42, 0.13), (0.55, 0.132), (0.68, 0.115), (0.8, 0.106), (0.9, 0.11), (1.0, 0.135)]
HULL_TIP_GAIN = 1.3  # the tail cone's tip, over the last ring
HULL_LOBE_STUDS = 0.125  # each lobe's own contour
HULL_SQUIRT_STUDS = 0.135  # each squirt's
HULL_BEAD_STUDS = 0.104  # each bead's, measured at its faces' centres: never under 0.1 stud
CORE_LIFT_STUDS = 0.042  # how far a pale cap rides off its surface (the bible: 0.03 to 0.08)
BELLY_LIFT_STUDS = 0.06  # how far the belly crescent rides off the pigment
FLOW_LIFT_STUDS = 0.045  # and the flow lines
FLOW_WIDTH_STUDS = 0.17  # a flow line's loaded width

# --- the body ------------------------------------------------------------------------------------
NOSE_U = 0.16  # the nose is a quarter ellipse up to here, the crown of the head
# A long slug (ref-2, side: about 3.6 times as long as its head is tall), its back level behind the head
# and falling to the tail, its belly sagging a little under the middle.
TOP = [(0.16, 0.15), (0.3, 0.142), (0.45, 0.132), (0.6, 0.114), (0.73, 0.088), (0.85, 0.052), (0.94, 0.03), (1.0, 0.02)]
BOTTOM = [(0.16, 0.142), (0.3, 0.146), (0.45, 0.15), (0.6, 0.138), (0.73, 0.108), (0.85, 0.058), (0.94, 0.028), (1.0, 0.015)]
# In plan a round head, a neck behind it, the body widest under the lobes (ref-2, top-down).
SIDE = [(0.16, 0.152), (0.28, 0.132), (0.45, 0.176), (0.6, 0.176), (0.73, 0.148), (0.85, 0.094), (0.94, 0.05), (1.0, 0.026)]
RISE = 0.02  # how far the tail's spine rises over the last half
TAIL_TIP = 0.025  # the tail closes in a short cone past u = 1
BODY_SEGS = 18
NOSE_RINGS = 4
TAPER_US = [0.23, 0.3, 0.38, 0.46, 0.55, 0.64, 0.73, 0.82, 0.91, 1.0]
HULL_NOSE_RINGS = 4
HULL_TAPER_US = [0.26, 0.37, 0.49, 0.62, 0.76, 0.89, 1.0]

# --- the belly crescent --------------------------------------------------------------------------
# Behind the head, the crescent's half angle about the bottom (radians), along the body, running out to
# a point before the tail.
BELLY = [(0.3, 0.6), (0.45, 0.72), (0.6, 0.74), (0.75, 0.58), (0.87, 0.32), (0.95, 0.0)]
# Over the nose its edge is set by how the target sees it coming, head on: a smile across the bottom of
# the head, y = -SMILE[0] R + SMILE[1] R (x / SMILE[2] R)^2 (R the head's radius), so from the front it is
# a crescent, thick at the bottom and thinning up both sides -- never a wedge to the nose.
SMILE = (0.7, 0.17, 0.85)
BELLY_COLS = 4

# --- the lobes -----------------------------------------------------------------------------------
LOBE_U = 0.46
LOBE_PHI = math.radians(24)
LOBE_TOE = math.radians(8)  # toed in: their head ends lean toward the spine
LOBE_HALF = (0.155, 0.052, 0.074)  # half length, half width, half height
LOBE_EGG = 0.22  # broader toward the tail
LOBE_FULL = 2.25  # a pill's fullness along it: 2 is an ellipse, more fills out toward blunt ends
LOBE_OFF = 0.095  # how far the lobe's equator stands off the body: its hull rings its foot
LOBE_SINK = 0.042  # how far its ends settle into the back
LOBE_KEEL = 3.0  # how much deeper its underside reaches than its top stands: buried, and left out
LOBE_ROOT = 0.035  # and how much further, the same all along it
LOBE_LEVEL = 0.5  # how far a lobe's top turns from the body's normal toward straight up: its cap sits on top
# Its section, in degrees from its top: dense over the top, where its outline and its gloss are, and open
# underneath, between its last two, which the keel sinks deeper in the body than the lobe's contour is
# thick; and its rings along it, closer toward the ends so they round off.
LOBE_PSIS = (-132, -86, -46, -15, 15, 46, 86, 132)
LOBE_AS = (-0.95, -0.72, -0.28, 0.28, 0.72, 0.95)
LOBE_BURY = 0.004  # a face whose corners all lie deeper than its contour plus this is left out
# The gloss cap: half extent along, half angle across, shift toward the tail, turn toward the outer flank.
CAP = (0.58, math.radians(27), 0.06, math.radians(-6))

# --- squirts and beads ---------------------------------------------------------------------------
SQUIRTS = (
    # control points (x, y over the spine, u), the tube's root radius, the drop's radius
    # one rising into a curl, the other running back flatter and turning up only at its drop
    ([(0.008, -0.002, 0.87), (0.02, 0.008, 0.96), (0.038, 0.026, 1.03), (0.052, 0.05, 1.07), (0.056, 0.078, 1.075)], 0.02, 0.022),
    ([(-0.008, -0.008, 0.87), (-0.024, -0.006, 0.96), (-0.048, 0.0, 1.04), (-0.066, 0.01, 1.09), (-0.074, 0.03, 1.105)], 0.019, 0.021),
)
SQUIRT_SIDES = 7
SQUIRT_RINGS = (0.0, 0.3, 0.58)  # tube rings along the path, before the drop's two
BEADS = (
    # (x, y, u, radius, segments, rings)
    (0.005, -0.026, 1.12, 0.045, 10, 5),
    (-0.007, -0.038, 1.255, 0.034, 8, 4),
    (0.004, -0.047, 1.375, 0.024, 6, 3),
)
BEAD_CAPS = 0  # the beads carry no pale: the Umber's pale is spent on the lobes (6 % at most)
BEAD_CAP = ((-0.35, 0.75, -0.55), math.radians(22))  # where on a bead its pale cap sits, and its half angle
NOSE_SPOT = (0.055, math.radians(22), 0.026, math.radians(14))  # u, phi, half extent along, half angle across

FLOWS = (
    # (u from, u to, phi from, phi to)
    # low on the tail's flanks, under its equator: read from the side, out of the thrower's way
    (0.58, 0.9, math.radians(104), math.radians(84)),
    (0.64, 0.89, math.radians(-100), math.radians(-86)),
)
FLOW_SAMPLES = 7


def _bead_facet_cos(segs: int, rings: int) -> float:
    """How much of a vertex's push a UV sphere's face centre keeps: the hull is pushed along the vertex
    normals, so at a face's centre it stands this share of the weight off the face."""
    return math.cos(math.pi / segs) * math.cos(math.pi / (2 * rings))


def _units_per_stud() -> float:
    """Body units in one stud at LENGTH_STUDS. The slug spans, ink included, from the nose's contour to the
    last bead's: (that span in body units, which itself grows with the contour) = LENGTH_STUDS studs."""
    x, y, u, r, segs, rings = BEADS[-1]
    # the last bead's furthest vertex back: on its rings, at the segment angle nearest straight back
    reach = max(math.sin(math.pi * i / rings) * math.sin(2 * math.pi * j / segs) for i in range(1, rings) for j in range(segs))
    geometric = (u - 0.5) + reach * r + 0.5  # from the nose (z = -0.5) to the bead's back
    bead_w = HULL_BEAD_STUDS / _bead_facet_cos(segs, rings)
    return geometric / (LENGTH_STUDS - HULL_STUDS[0][1] - reach * bead_w)


UNIT = _units_per_stud()
HULL_LOBE = HULL_LOBE_STUDS * UNIT
HULL_SQUIRT = HULL_SQUIRT_STUDS * UNIT
CORE_LIFT = CORE_LIFT_STUDS * UNIT
BELLY_LIFT = BELLY_LIFT_STUDS * UNIT
FLOW_LIFT = FLOW_LIFT_STUDS * UNIT
FLOW_WIDTH = FLOW_WIDTH_STUDS * UNIT


# --- the body's surface --------------------------------------------------------------------------


def _profile(ctrl, u: float) -> float:
    u0, v0 = ctrl[0]
    if u <= u0:
        f = 1.0 - max(u, 0.0) / u0
        return v0 * math.sqrt(max(0.0, 1.0 - f * f))
    return cosine_curve(ctrl, min(u, 1.0))


def _z(u: float) -> float:
    return u - 0.5


def _spine_y(u: float) -> float:
    return RISE * smoothstep(0.5, 1.0, u)


def body_point(u: float, phi: float):
    """The body's surface at u (0 nose .. 1 tail) and phi (0 top, +pi/2 toward +X, pi bottom)."""
    a = _profile(SIDE, u)
    c = math.cos(phi)
    h = _profile(TOP, u) if c >= 0 else _profile(BOTTOM, u)
    return (a * math.sin(phi), Y_OFF + _spine_y(u) + h * c, _z(u))


def body_normal(u: float, phi: float):
    e = 1e-4
    du = sub(body_point(min(u + e, 1.0), phi), body_point(max(u - e, 1e-4), phi))
    dp = sub(body_point(u, phi + e), body_point(u, phi - e))
    return norm(cross(du, dp))


def _depth(p) -> float:
    """How deep a point lies inside the body (negative outside), in body units: the distance to the
    surface along the section's own scaling, close enough for burying checks."""
    x, y, z = p
    u = z + 0.5
    if u <= 0.0 or u >= 1.0:
        return -1.0
    a = _profile(SIDE, u)
    yy = y - Y_OFF - _spine_y(u)
    h = _profile(TOP, u) if yy >= 0 else _profile(BOTTOM, u)
    if a <= 1e-9 or h <= 1e-9:
        return -1.0
    return (1.0 - math.sqrt((x / a) ** 2 + (yy / h) ** 2)) * min(a, h)


def _axis(u: float):
    uc = min(max(u, 0.1), 0.9)
    return (0.0, Y_OFF + _spine_y(uc), _z(uc))


def _body_volume(us: list[float], weight) -> Volume:
    """The body lofted through rings at `us`, closed all round: a nose tip in front and a short cone at
    the tail. Every ring has the same BODY_SEGS equal angles, so the hull's facets run with the skin's."""
    vol = Volume()
    phis = [2.0 * math.pi * j / BODY_SEGS - math.pi for j in range(BODY_SEGS)]
    rings = [[vol.vert(body_point(u, phi), weight(u)) for phi in phis] for u in us]
    nose = vol.vert((0.0, Y_OFF + _spine_y(0.0), _z(0.0)), weight(0.0))
    tail = vol.vert((0.0, Y_OFF + _spine_y(1.0) + 0.002, _z(1.0) + TAIL_TIP), weight(1.0) * HULL_TIP_GAIN)
    m = BODY_SEGS

    def face(a, b, c):
        pa, pb, pc = (vol.mesh.verts[i] for i in (a, b, c))
        centre = tuple((pa[k] + pb[k] + pc[k]) / 3.0 for k in range(3))
        vol.mesh.tri(a, b, c, sub(centre, _axis(centre[2] + 0.5)))

    for r in range(len(rings) - 1):
        ra, rb = rings[r], rings[r + 1]
        for j in range(m):
            k = (j + 1) % m
            face(ra[j], ra[k], rb[k])
            face(ra[j], rb[k], rb[j])
    for j in range(m):
        k = (j + 1) % m
        face(nose, rings[0][j], rings[0][k])
        face(tail, rings[-1][j], rings[-1][k])
    return vol


def _nose_us(count: int) -> list[float]:
    return [NOSE_U * (1.0 - math.cos(0.5 * math.pi * k / count)) for k in range(1, count + 1)]


SKIN_US = _nose_us(NOSE_RINGS) + TAPER_US
HULL_US = _nose_us(HULL_NOSE_RINGS) + HULL_TAPER_US


def _hull_weight(u: float) -> float:
    return cosine_curve(HULL_STUDS, u) * UNIT


# --- the belly crescent --------------------------------------------------------------------------


def _smile_belly(u: float) -> float:
    big = _profile(TOP, NOSE_U)
    a, hb = _profile(SIDE, u), _profile(BOTTOM, u)
    depth, rise, reach = SMILE

    def gap(b: float) -> float:
        x, y = a * math.sin(b), -hb * math.cos(b)
        return y - (-depth * big + rise * big * (x / (reach * big)) ** 2)

    if gap(0.0) >= 0.0:
        return 0.0
    lo, hi = 0.0, 0.5 * math.pi
    if gap(hi) < 0.0:
        return hi
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if gap(mid) < 0.0:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def _belly_half(u: float) -> float:
    if u <= NOSE_U:
        return _smile_belly(u)
    if u >= BELLY[-1][0]:
        return 0.0
    return cosine_curve([(NOSE_U, _smile_belly(NOSE_U))] + BELLY, u)


def _belly_start() -> float:
    lo, hi = 0.0, NOSE_U
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if _smile_belly(mid) > 0.0:
            hi = mid
        else:
            lo = mid
    return hi


def _belly(ink: Mesh) -> None:
    """The dark belly: a crescent of ink lying BELLY_LIFT off the closed pigment underneath. Its rows stand
    on the skin's own rings, so its facets run with the pigment's and the lift holds between them; both
    ends run out to a point on the bottom line."""
    u0, u1 = _belly_start(), BELLY[-1][0]
    us = [u0] + [u for u in SKIN_US if u0 < u < u1] + [u1]
    rows = []
    for i, u in enumerate(us):
        b = _belly_half(u)
        cols = BELLY_COLS if 0 < i < len(us) - 1 else 0
        row = []
        for j in range(cols + 1):
            phi = math.pi - b + 2.0 * b * j / cols if cols else math.pi
            n = body_normal(u, phi)
            row.append((ink.vert(add(body_point(u, phi), mul(n, BELLY_LIFT))), n))
        rows.append(row)
    for i in range(len(rows) - 1):
        ra, rb = rows[i], rows[i + 1]
        if len(ra) == 1:
            for j in range(len(rb) - 1):
                ink.tri(ra[0][0], rb[j][0], rb[j + 1][0], rb[j][1])
        elif len(rb) == 1:
            for j in range(len(ra) - 1):
                ink.tri(ra[j][0], ra[j + 1][0], rb[0][0], ra[j][1])
        else:
            for j in range(len(ra) - 1):
                (a, n), (b, _), (c, _), (d, _) = ra[j], ra[j + 1], rb[j], rb[j + 1]
                ink.tri(a, b, d, n)
                ink.tri(a, d, c, n)


# --- the lobes -----------------------------------------------------------------------------------


def _egg_raw(a: float) -> float:
    return max(0.0, 1.0 - abs(a) ** LOBE_FULL) ** (1.0 / LOBE_FULL) * (1.0 + LOBE_EGG * a)


_EGG_PEAK = max(_egg_raw(i / 200.0) for i in range(-199, 200))


def _egg(a: float) -> float:
    """The lobe's girth along it, 1 at its widest: a pill, full to round ends, broader toward the tail."""
    return _egg_raw(a) / _EGG_PEAK


class Lobe:
    """A gloss lobe: an egg lying along the body's back, its spine riding the surface so it never floats
    off where the body tapers, its equator LOBE_OFF proud of the surface, its keel sunk deep in it."""

    def __init__(self, side: float) -> None:
        self.side = side
        u0, p0 = LOBE_U, side * LOBE_PHI
        e = 1e-3
        du = math.dist(body_point(u0 + e, p0), body_point(u0 - e, p0)) / (2 * e)
        dp = math.dist(body_point(u0, p0 + e), body_point(u0, p0 - e)) / (2 * e)
        length = LOBE_HALF[0]
        # Toward the tail the lobe runs out and away from the spine (it is toed in at the head).
        self.du = length * math.cos(LOBE_TOE) / du
        self.dp = side * length * math.sin(LOBE_TOE) / dp
        self.u0, self.p0 = u0, p0

    def spine(self, a: float):
        u, p = self.u0 + a * self.du, self.p0 + a * self.dp
        rho = _egg(a)
        off = LOBE_OFF * rho - LOBE_SINK * (1.0 - rho)
        n = body_normal(u, p)
        return add(body_point(u, p), mul(n, off)), n

    def _plan(self, a: float):
        return body_point(self.u0 + a * self.du, self.p0 + a * self.dp)

    def frame(self, a: float):
        c, n = self.spine(a)
        e = 1e-3
        # along the line it lies on, on the body: its ends settle in, but its section does not tip with them
        t = norm(sub(self._plan(min(a + e, 1.0)), self._plan(max(a - e, -1.0))))
        n = norm(add(mul(n, 1.0 - LOBE_LEVEL), (0.0, LOBE_LEVEL, 0.0)))
        up = norm(sub(n, mul(t, dot(n, t))))
        across = norm(cross(t, up))
        return c, t, up, across

    def point(self, a: float, psi: float):
        """The lobe's surface at a (-1 head end .. 1 tail end) and psi (0 on top, + toward its outer side).
        Below its equator the keel reaches deeper, into the body."""
        c, _t, up, across = self.frame(a)
        rho = _egg(a)
        w = LOBE_HALF[1] * rho
        h = LOBE_HALF[2] * rho
        s, k = math.sin(psi), math.cos(psi)
        down = 0.0
        if k < 0.0:
            sunk = smoothstep(0.2, 0.9, -k)
            k *= 1.0 + (LOBE_KEEL - 1.0) * sunk
            down = LOBE_ROOT * sunk  # a root that does not thin with the lobe, so its ends are sunk too
        return add(c, add(mul(across, -self.side * w * s), mul(up, h * k - down)))

    def normal(self, a: float, psi: float):
        e = 1e-3
        da = sub(self.point(min(a + e, 0.999), psi), self.point(max(a - e, -0.999), psi))
        dp = sub(self.point(a, psi + e), self.point(a, psi - e))
        n = norm(cross(da, dp))
        c, _t, _up, _across = self.frame(a)
        if dot(n, sub(self.point(a, psi), c)) < 0:
            n = mul(n, -1.0)
        return n

    def volume(self) -> Volume:
        """The lobe, open only underneath along its sunk keel (and less any face sunk deeper than its
        contour is thick): its open edge and its hull's lie in the body."""
        vol = Volume()
        a_s = list(LOBE_AS)
        psis = [math.radians(d) for d in LOBE_PSIS]
        segs = len(psis)
        rings = [[vol.vert(self.point(a, psi), HULL_LOBE) for psi in psis] for a in a_s]
        head = vol.vert(self.spine(-1.0)[0], HULL_LOBE)
        tail = vol.vert(self.spine(1.0)[0], HULL_LOBE)
        centres = [self.frame(a)[0] for a in a_s]
        deep = HULL_LOBE + LOBE_BURY

        def face(a, b, c, centre):
            pa, pb, pc = (vol.mesh.verts[i] for i in (a, b, c))
            if min(_depth(pa), _depth(pb), _depth(pc)) > deep:
                return
            mid = tuple((pa[k] + pb[k] + pc[k]) / 3.0 for k in range(3))
            vol.mesh.tri(a, b, c, sub(mid, centre))

        for r in range(len(rings) - 1):
            centre = tuple((centres[r][k] + centres[r + 1][k]) / 2.0 for k in range(3))
            for j in range(segs - 1):
                k = j + 1
                face(rings[r][j], rings[r][k], rings[r + 1][k], centre)
                face(rings[r][j], rings[r + 1][k], rings[r + 1][j], centre)
        for j in range(segs - 1):
            k = j + 1
            face(head, rings[0][j], rings[0][k], centres[0])
            face(tail, rings[-1][j], rings[-1][k], centres[-1])
        return vol

    def cap(self, core: Mesh) -> None:
        """The pale gloss: an oval over the lobe's top, a band of umber left all round it."""
        half_a, half_psi, shift, turn = CAP
        fracs = (0.0, 0.45, 0.8, 1.0)
        count = 12
        grid = []
        for f in fracs:
            row = []
            for i in range(count if f > 0 else 1):
                ang = 2.0 * math.pi * i / count
                a = shift + half_a * f * math.cos(ang)
                psi = turn + half_psi * f * math.sin(ang)
                p = self.point(a, psi)
                n = self.normal(a, psi)
                row.append((core.vert(add(p, mul(n, CORE_LIFT))), n))
            grid.append(row)
        _polar(core, grid)


def _polar(mesh: Mesh, grid) -> None:
    """Triangles of a polar grid: a centre, then rings of the same count."""
    centre = grid[0][0]
    first = grid[1]
    count = len(first)
    for i in range(count):
        a, na = first[i]
        b, _ = first[(i + 1) % count]
        mesh.tri(centre[0], a, b, na)
    for r in range(1, len(grid) - 1):
        ra, rb = grid[r], grid[r + 1]
        for i in range(count):
            k = (i + 1) % count
            (a, n), (b, _), (c, _), (d, _) = ra[i], ra[k], rb[i], rb[k]
            mesh.tri(a, b, d, n)
            mesh.tri(a, d, c, n)


# --- squirts -------------------------------------------------------------------------------------


def _catmull(points, per: int = 16):
    """Catmull-Rom through `points`, as a function of the share of its length, and that length."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(per):
            t = k / per
            out.append(tuple(0.5 * (2 * p1[a] + (-p0[a] + p2[a]) * t + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t * t + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t ** 3) for a in range(3)))
    out.append(tuple(points[-1]))
    acc = [0.0]
    for i in range(1, len(out)):
        acc.append(acc[-1] + math.dist(out[i - 1], out[i]))

    def at(s: float):
        target = min(max(s, 0.0), 1.0) * acc[-1]
        for i in range(1, len(out)):
            if acc[i] >= target:
                f = (target - acc[i - 1]) / max(acc[i] - acc[i - 1], 1e-12)
                return tuple(out[i - 1][k] + (out[i][k] - out[i - 1][k]) * f for k in range(3))
        return out[-1]

    return at, acc[-1]


def _squirt(control, radius: float, drop: float) -> Volume:
    """A short squirt off the tail: a smooth tube that narrows a little along a curl, then swells into a
    round drop at its end. Its section is carried along by parallel transport, so it never twists. Open
    at its root, which is buried in the tail, and its contour is nothing there: the hull's open end is
    the root itself, buried too."""
    pts = [(x, Y_OFF + _spine_y(u) + y, _z(u)) for x, y, u in control]
    path, length = _catmull(pts)
    vol = Volume()
    sc = 1.0 - drop / length  # the drop's centre: its front touches the path's end

    def tangent(s: float):
        return norm(sub(path(min(s + 0.03, 1.0)), path(max(s - 0.03, 0.0))))

    frames = []
    for s in SQUIRT_RINGS:
        frames.append((path(s), tangent(s), radius * (1.0 - 0.3 * s / SQUIRT_RINGS[-1])))
    t_end = tangent(sc)
    centre = path(sc)
    for theta in (math.radians(118), math.radians(58)):
        # the drop's rings, theta from its tip direction: behind its equator, then ahead of it
        frames.append((add(centre, mul(t_end, drop * math.cos(theta))), t_end, drop * math.sin(theta)))
    side = norm(cross(frames[0][1], (0.0, 1.0, 0.0)))
    rings = []
    for index, (c, t, r) in enumerate(frames):
        side = norm(sub(side, mul(t, dot(side, t))))
        up = norm(cross(side, t))
        w = 0.0 if index == 0 else HULL_SQUIRT
        ring = []
        for k in range(SQUIRT_SIDES):
            ang = math.pi / 2 + 2 * math.pi * k / SQUIRT_SIDES
            ring.append(vol.vert(add(c, add(mul(up, r * math.sin(ang)), mul(side, r * math.cos(ang)))), w))
        rings.append(ring)
    tip = vol.vert(add(centre, mul(t_end, drop)), HULL_SQUIRT)
    centres = [f[0] for f in frames]
    for r in range(len(rings) - 1):
        mid_c = mul(add(centres[r], centres[r + 1]), 0.5)
        for j in range(SQUIRT_SIDES):
            k = (j + 1) % SQUIRT_SIDES
            for tri in ((rings[r][j], rings[r][k], rings[r + 1][k]), (rings[r][j], rings[r + 1][k], rings[r + 1][j])):
                mid = tuple(sum(vol.mesh.verts[v][q] for v in tri) / 3.0 for q in range(3))
                vol.mesh.tri(*tri, sub(mid, mid_c))
    for j in range(SQUIRT_SIDES):
        k = (j + 1) % SQUIRT_SIDES
        tri = (rings[-1][j], rings[-1][k], tip)
        mid = tuple(sum(vol.mesh.verts[v][q] for v in tri) / 3.0 for q in range(3))
        vol.mesh.tri(*tri, sub(mid, centre))
    return vol


# --- beads ---------------------------------------------------------------------------------------


def _bead_centre(bead):
    x, y, u, _r, _s, _n = bead
    return (x, Y_OFF + y, _z(u))


def _bead(bead) -> Volume:
    """A round bead: a small UV sphere, its own hull drawn round it, weighted so that even at its faces'
    centres the contour holds HULL_BEAD_STUDS."""
    _x, _y, _u, radius, segs, rings = bead
    centre = _bead_centre(bead)
    weight = HULL_BEAD_STUDS * UNIT / _bead_facet_cos(segs, rings)
    vol = Volume()
    grid = []
    for i in range(1, rings):
        theta = math.pi * i / rings
        grid.append(
            [
                vol.vert(add(centre, mul((math.sin(theta) * math.cos(2 * math.pi * j / segs), math.cos(theta), math.sin(theta) * math.sin(2 * math.pi * j / segs)), radius)), weight)
                for j in range(segs)
            ]
        )
    top = vol.vert(add(centre, (0.0, radius, 0.0)), weight)
    bottom = vol.vert(add(centre, (0.0, -radius, 0.0)), weight)

    def face(a, b, c):
        mid = tuple(sum(vol.mesh.verts[v][q] for v in (a, b, c)) / 3.0 for q in range(3))
        vol.mesh.tri(a, b, c, sub(mid, centre))

    for j in range(segs):
        k = (j + 1) % segs
        face(top, grid[0][j], grid[0][k])
        face(bottom, grid[-1][j], grid[-1][k])
    for r in range(len(grid) - 1):
        for j in range(segs):
            k = (j + 1) % segs
            a, b, c, d = grid[r][j], grid[r][k], grid[r + 1][j], grid[r + 1][k]
            face(a, b, d)
            face(a, d, c)
    return vol


def _sphere_cap(core: Mesh, centre, radius: float, axis, half: float) -> None:
    axis = norm(axis)
    helper = (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)
    e1 = norm(cross(axis, helper))
    e2 = cross(axis, e1)
    grid = []
    for f in (0.0, 0.55, 1.0):
        row = []
        for i in range(10 if f > 0 else 1):
            ang = 2 * math.pi * i / 10
            th = half * f
            d = norm(add(mul(axis, math.cos(th)), add(mul(e1, math.sin(th) * math.cos(ang)), mul(e2, math.sin(th) * math.sin(ang)))))
            row.append((core.vert(add(centre, mul(d, radius + CORE_LIFT))), d))
        grid.append(row)
    _polar(core, grid)


# --- core and ink details ------------------------------------------------------------------------


def _nose_spot(core: Mesh) -> None:
    u0, p0, du, dp = NOSE_SPOT
    grid = []
    for f in (0.0, 0.6, 1.0):
        row = []
        for i in range(10 if f > 0 else 1):
            ang = 2 * math.pi * i / 10
            u, p = u0 + du * f * math.cos(ang), p0 + dp * f * math.sin(ang)
            n = body_normal(u, p)
            row.append((core.vert(add(body_point(u, p), mul(n, CORE_LIFT))), n))
        grid.append(row)
    _polar(core, grid)


def _flow_lines(ink: Mesh) -> None:
    """Calligraphic lines down the tail's flanks, drawn toward the fork: pressed in, released into the
    tail, unequal and never parallel."""
    surface = (body_point, body_normal)
    for index, (u0, u1, p0, p1) in enumerate(FLOWS):
        def path(tau, u0=u0, u1=u1, p0=p0, p1=p1):
            return u0 + (u1 - u0) * tau, p0 + (p1 - p0) * tau * tau

        surface_ribbon(ink, surface, path, FLOW_WIDTH, FLOW_LIFT, FLOW_SAMPLES, SEED + 20 + index)


# --- the three meshes ----------------------------------------------------------------------------

_CACHE: dict = {}


def build():
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    skin = _body_volume(SKIN_US, _hull_weight)
    hull = _body_volume(HULL_US, _hull_weight)
    lobes = [Lobe(+1.0), Lobe(-1.0)]
    solids = [lobes[0].volume(), lobes[1].volume()]
    solids += [_squirt(c, r, d) for c, r, d in SQUIRTS]
    solids += [_bead(b) for b in BEADS]
    body.merge(skin.mesh)
    for vol in solids:
        body.merge(vol.mesh)
    inverted_hull(hull, ink)
    for vol in solids:
        inverted_hull(vol, ink)
    _belly(ink)
    _flow_lines(ink)
    for lobe in lobes:
        lobe.cap(core)
    _nose_spot(core)
    for bead in BEADS[:BEAD_CAPS]:
        _sphere_cap(core, _bead_centre(bead), bead[3], BEAD_CAP[0], BEAD_CAP[1])
    meshes = (body, core, ink)
    for mesh in meshes:
        mesh.translate((0.0, -Y_OFF, 0.0))
    zs = [v[2] for mesh in meshes for v in mesh.verts]
    factor, shift = 1.0 / (max(zs) - min(zs)), -(max(zs) + min(zs)) / 2.0
    for mesh in meshes:
        mesh.verts = [(x * factor, y * factor, (z + shift) * factor) for x, y, z in mesh.verts]
    _CACHE["meshes"] = meshes
    return meshes


def meta(seed: int) -> dict:
    return {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": seed}


def mud_body() -> tuple[Mesh, dict]:
    return build()[0], meta(SEED)


def mud_gloss() -> tuple[Mesh, dict]:
    return build()[1], meta(SEED + 1)


def mud_ink() -> tuple[Mesh, dict]:
    return build()[2], meta(SEED + 2)
