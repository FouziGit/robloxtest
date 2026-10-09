"""The Strike's body (Rature, Orpiment, K3 lens): a straight ruled stroke of gold, drawn after the
developer's two references (docs/vfx/strike/ref-1.jpg in game, ref-2.jpg the model sheet).

Roblox space: X right, Y up, forward -Z. The stroke is modelled at its true section for the longest
reach (70 studs) and normalised to Length 1 along -Z, so Size 70 gives the server's section and Span =
Reach stretches it to wherever the ray stopped (R1): the section is constant over everything that
stretches.

  - head (first 3 %): a pressed arrow point, a touch wider than the body, which the two ink fillets
    follow as a chevron;
  - body: a constant lens section, 2.2 studs over its contour and 0.53 thick in gold, with a ridge
    on top and a keel below, its flanks hollowed (the model sheet's end-on view, flattened to the
    bible's thin blade and to the in-game shot's scale against the arm);
  - double fillet: one ink line on each side of the ridge, the whole length, closing into the
    chevron at the head and running up the flick;
  - pale thread on the ridge over the first 60 %: pointed in the chevron, then one even thin line
    (0.1 stud across) that tapers only over its last eighth, like the in-game shot's line;
  - tail (last 5 %): a whip-flick that lifts straight up (a hair of sway), turns its face to the
    thrower, and hooks forward at its point, with two calligraphic flourishes in ink beside it (a
    spiral curl and a crook), flat pen strokes in planes that face the thrower.

The contour is an inverted hull offset corner by corner in the section's own (across, up) frame: 0.2
stud out of each edge, 0.15 over the ridge, keel and flanks, heavier on the pressed head and drawn down
to 0.1 at the flick's point. Every ring of the 58-stud body gets the same offsets on both sides, so
the outline is even and never twists along the stroke.

Never bigger than the harm: the server's box is 6 x 6 studs about the ray (HitRadius 3) from the
muzzle to where the ray stopped, so the flick's ink tops out under 3 studs above the ray, and nothing
reaches past the stop or behind the muzzle.

Three meshes, one tone each: rature_band (Pigment), rature_spine (Core, the pale thread), rature_ink
(Ink: the contour, the double fillet, the two flourishes). Each stays under the 450-triangle cap of a
small repeated piece (K3: 40 to 480).
"""

from __future__ import annotations

import math

from strokes import Mesh, Polyline, Volume, add, catmull, cross, dot, emit, fbm, mul, norm, sub

SEED = 5531
REACH = 70.0  # studs the stroke is modelled at (GlyphConfig Strike Range)

# Section (studs).
HALF = 0.92  # pigment half width: with the contour, 2.2 across
RIDGE = 0.31  # ridge height over the ray
KEEL = 0.22  # keel depth under it
FLANK_X, FLANK_Y = 0.598, 0.22  # the top flank's hollow: its vertex, in shares of the half width and ridge
BELLY_X, BELLY_Y = 0.54, 0.26  # the same under the stroke

# Along (studs of arc).
HEAD = 0.03 * REACH  # the pressed head
SWELL = 1.08  # how much wider than the body the head presses
FLICK_FROM = 0.95 * REACH  # where the lift starts
TAPER_FROM = 0.88 * REACH
TAPER_TO = 0.72  # width share where the flick starts
FLICK_RINGS = 8  # rings over the lift, its point included

# Contour (studs out of the gold, in the section's plane).
HULL_EDGE = 0.2
HULL_TOP = 0.15
HULL_HEAD = 0.24
HULL_TIP = 0.1
HULL_NOSE = 0.3  # how far the contour runs ahead of the head's point, back toward the muzzle

# Double fillet and pale thread.
FILLET_IN = 0.5  # distance in from the body's edge of each fillet's centre line
FILLET_BACK = 0.6 * HEAD  # the fillets' chevron is the head's point drawn again this far back
FILLET_HALF = (0.072, 0.064)  # left, right: two hands, never two identical rules
FILLET_LIFT = 0.04
PALE_HALF = 0.05  # half width of the even thread
PALE_END = 0.6 * REACH
PALE_TAPER = 0.12  # share of the thread that tapers to its end
PALE_LIFT = 0.05

# The flick's spine (studs), from the start of the lift to the point; it hooks forward at the end.
FLICK = [
    (0.0, 0.0, -FLICK_FROM + 3.5),
    (0.0, 0.0, -FLICK_FROM),
    (-0.02, 0.1, -67.5),
    (-0.07, 0.45, -68.3),
    (-0.13, 1.05, -68.8),
    (-0.2, 1.72, -69.05),
    (-0.27, 2.28, -69.28),
    (-0.33, 2.62, -69.62),
    (-0.36, 2.76, -70.0),
]


def _spine() -> tuple[Polyline, float]:
    straight = [(0.0, 0.0, -FLICK_FROM * i / 40) for i in range(40)]
    curve = catmull(FLICK, 20)[20:]  # from the start of the lift on
    line = Polyline(straight + curve)
    return line, line.acc[-1]


def width(a: float, length: float) -> float:
    """Share of the section's half width at arc `a`."""
    if a <= HEAD:
        return SWELL * (a / HEAD) ** 0.85
    if a <= 1.7 * HEAD:
        f = (a - HEAD) / (0.7 * HEAD)
        return SWELL + (1.0 - SWELL) * (0.5 - 0.5 * math.cos(math.pi * f))
    if a <= TAPER_FROM:
        return 1.0
    if a <= FLICK_FROM:
        f = (a - TAPER_FROM) / (FLICK_FROM - TAPER_FROM)
        return 1.0 + (TAPER_TO - 1.0) * (0.5 - 0.5 * math.cos(math.pi * f))
    s = (a - FLICK_FROM) / (length - FLICK_FROM)
    return TAPER_TO * (1.0 - s) ** 1.35


def height(a: float, length: float) -> float:
    return width(a, length) ** 0.65


def stations(length: float) -> list[float]:
    """Where the rings stand: the head's point (0), its pressed arrow, the swell easing back to the
    body, one 58-stud span of constant section, the taper, and the lift to the flick's point."""
    head = [HEAD * f for f in (0.0, 0.3, 0.6, 1.0)]
    head += [HEAD * (1.0 + 0.7 * f) for f in (0.4, 1.0)]
    body = [TAPER_FROM, TAPER_FROM + 0.45 * (FLICK_FROM - TAPER_FROM), FLICK_FROM]
    span = length - FLICK_FROM
    flick = [FLICK_FROM + span * (1.0 - (1.0 - k / FLICK_RINGS) ** 1.3) for k in range(1, FLICK_RINGS + 1)]
    return head + body + flick


class Frames:
    """Centre, across and up along the spine, carried by parallel transport: the flick turns its top
    face to the thrower as it lifts, and never flips."""

    def __init__(self) -> None:
        self.line, self.length = _spine()
        self.cache: dict[float, tuple] = {}

    def at(self, a: float):
        if a in self.cache:
            return self.cache[a]
        # Transport from the start over a fine walk: the frame is a pure function of `a`.
        steps = max(2, int(a / 0.25) + 2)
        across = (1.0, 0.0, 0.0)
        up = (0.0, 1.0, 0.0)
        prev_t = (0.0, 0.0, -1.0)
        for i in range(1, steps + 1):
            b = a * i / steps
            t = self.tangent(b)
            axis = cross(prev_t, t)
            s = math.sqrt(dot(axis, axis))
            if s > 1e-9:
                axis = mul(axis, 1.0 / s)
                angle = math.atan2(s, dot(prev_t, t))
                across = _rotate(across, axis, angle)
                up = _rotate(up, axis, angle)
            prev_t = t
        frame = (self.line.at(a / self.length), across, up, prev_t)
        self.cache[a] = frame
        return frame

    def tangent(self, a: float):
        e = 0.05
        p = self.line.at(max(0.0, a - e) / self.length)
        q = self.line.at(min(self.length, a + e) / self.length)
        return norm(sub(q, p))


def _rotate(v, axis, angle):
    c, s = math.cos(angle), math.sin(angle)
    return add(add(mul(v, c), mul(cross(axis, v), s)), mul(axis, dot(axis, v) * (1.0 - c)))


def section(hw: float, rid: float, kel: float) -> list[tuple[float, float]]:
    """The lens, counter-clockwise seen from behind: right edge, top flank, ridge, top flank, left
    edge, belly, keel, belly."""
    return [
        (hw, 0.0),
        (FLANK_X * hw, FLANK_Y * rid),
        (0.0, rid),
        (-FLANK_X * hw, FLANK_Y * rid),
        (-hw, 0.0),
        (-BELLY_X * hw, -BELLY_Y * kel),
        (0.0, -kel),
        (BELLY_X * hw, -BELLY_Y * kel),
    ]


def outward(poly: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Per corner of a counter-clockwise section, the unit bisector of its two sides' outward normals:
    the direction the contour leaves that corner in, the same on both sides of the ridge."""
    m = len(poly)
    out = []
    for k in range(m):
        (px, py), (cx, cy), (nx, ny) = poly[k - 1], poly[k], poly[(k + 1) % m]
        a = _unit2(cy - py, -(cx - px))
        b = _unit2(ny - cy, -(nx - cx))
        out.append(_unit2(a[0] + b[0], a[1] + b[1]))
    return out


def _unit2(x: float, y: float) -> tuple[float, float]:
    s = math.hypot(x, y)
    return (x / s, y / s)


def top_y(x: float, hw: float, rid: float) -> float:
    """Height of the top of the section at `x` across (|x| <= hw): the facets the mesh is cut in."""
    u = min(abs(x), hw)
    fx = FLANK_X * hw
    if u >= fx:
        return FLANK_Y * rid * (hw - u) / max(hw - fx, 1e-9)
    return FLANK_Y * rid + (1.0 - FLANK_Y) * rid * (fx - u) / max(fx, 1e-9)


def hull_weight(a: float, length: float, corner: int) -> float:
    edge = corner in (0, 4)
    base = HULL_EDGE if edge else HULL_TOP
    if a < 1.7 * HEAD:
        base = base + (HULL_HEAD - HULL_EDGE) * (1.0 - a / (1.7 * HEAD))
    if a > FLICK_FROM:
        s = (a - FLICK_FROM) / (length - FLICK_FROM)
        base = base + (HULL_TIP - base) * s**1.2
    return base


def close_tube(vol: Volume, tip: int, rings: list[list[int]], end: int) -> None:
    """A fan from the point, quads ring to ring, a fan to the end: closed, then wound outward."""
    m = len(rings[0])
    for j in range(m):
        emit(vol.mesh, tip, rings[0][(j + 1) % m], rings[0][j])
    for r in range(len(rings) - 1):
        p, q = rings[r], rings[r + 1]
        for j in range(m):
            k = (j + 1) % m
            emit(vol.mesh, p[j], p[k], q[k])
            emit(vol.mesh, p[j], q[k], q[j])
    for j in range(m):
        emit(vol.mesh, rings[-1][j], rings[-1][(j + 1) % m], end)
    vol.orient_outward()


class Build:
    def __init__(self) -> None:
        self.frames = Frames()
        self.length = self.frames.length

    def point(self, a: float, x: float, y: float):
        c, across, up, _ = self.frames.at(a)
        return add(c, add(mul(across, x), mul(up, y)))

    def dims(self, a: float):
        w = width(a, self.length)
        h = height(a, self.length)
        return HALF * w, RIDGE * h, KEEL * h

    def on_top(self, a: float, x: float, lift: float):
        hw, rid, _ = self.dims(a)
        return self.point(a, x, top_y(x, hw, rid) + lift)

    # -- the blade and its contour ---------------------------------------------------------------

    TIP_Y = 0.03  # the head's point sits a hair over the ray

    def blade(self) -> Volume:
        vol = Volume()
        rings = []
        for a in stations(self.length)[1:-1]:
            hw, rid, kel = self.dims(a)
            rings.append([vol.vert(self.point(a, x, y), 0.0) for x, y in section(hw, rid, kel)])
        tip = vol.vert(self.point(0.0, 0.0, self.TIP_Y), 0.0)
        end = vol.vert(self.point(self.length, 0.0, 0.0), 0.0)
        close_tube(vol, tip, rings, end)
        return vol

    def contour(self) -> Volume:
        """The blade's twin pushed out corner by corner in each ring's (across, up) frame, so both
        edges get the same contour at every ring, and its point and end pushed along the stroke.
        Returned wound outward; `inverted` turns it inside out."""
        vol = Volume()
        rings = []
        for a in stations(self.length)[1:-1]:
            hw, rid, kel = self.dims(a)
            poly = section(hw, rid, kel)
            ring = []
            for k, ((x, y), (dx, dy)) in enumerate(zip(poly, outward(poly))):
                w = hull_weight(a, self.length, k)
                ring.append(vol.vert(self.point(a, x + dx * w, y + dy * w), w))
            rings.append(ring)
        _, _, _, t0 = self.frames.at(0.0)
        tip = vol.vert(sub(self.point(0.0, 0.0, self.TIP_Y), mul(t0, HULL_NOSE)), HULL_NOSE)
        _, _, _, t1 = self.frames.at(self.length)
        end = vol.vert(add(self.point(self.length, 0.0, 0.0), mul(t1, HULL_TIP)), HULL_TIP)
        close_tube(vol, tip, rings, end)
        return vol

    # -- the double fillet -----------------------------------------------------------------------

    def fillet_x(self, a: float) -> float:
        """Each fillet's centre line, out from the ridge: the body's rule (which follows the swell and
        the taper), cut in the head by a nested chevron, the head's own point set FILLET_BACK back,
        so its arms run parallel to the contour as in the model sheet's close-up."""
        hw, _, _ = self.dims(a)
        body = (HALF - FILLET_IN) / HALF * hw
        u = a - FILLET_BACK
        if u >= 1.7 * HEAD:
            return body
        nested = HALF * SWELL * (u / HEAD) ** 0.85 if u > 0 else u
        return min(nested, body)

    def fillet_knee(self) -> float:
        """Where the chevron's arm meets the body's rule."""
        lo, hi = FILLET_BACK, FILLET_BACK + 1.7 * HEAD
        for _ in range(60):
            mid = 0.5 * (lo + hi)
            hw, _, _ = self.dims(mid)
            u = mid - FILLET_BACK
            if HALF * SWELL * (u / HEAD) ** 0.85 < (HALF - FILLET_IN) / HALF * hw:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    def fillets(self, ink: Mesh) -> None:
        st = stations(self.length)
        # The chevron's apex: where the fillet's line meets the ridge.
        apex = next(a / 100 for a in range(1, 400) if self.fillet_x(a / 100) >= 0.0)
        end = FLICK_FROM + 0.82 * (self.length - FLICK_FROM)
        rows = [apex] + [a for a in st if apex < a < end] + [end]
        rows = sorted(set(rows + [self.fillet_knee(), TAPER_FROM - 30.0, TAPER_FROM - 10.0]))
        for side, half in ((-1.0, FILLET_HALF[0]), (1.0, FILLET_HALF[1])):
            lefts, rights = [], []
            for a in rows:
                xc = max(self.fillet_x(a), 0.0)
                # Pressed in at the apex, released toward the flick's point.
                grow = min(1.0, (a - apex) / 0.5 + 0.35)
                fade = 1.0 if a < FLICK_FROM else max(0.0, 1.0 - ((a - FLICK_FROM) / (end - FLICK_FROM)) ** 1.5)
                hw, _, _ = self.dims(a)
                wob = 1.0 + 0.1 * (fbm(a / 9.0, 0.7 * side, SEED + int(side)) * 2.0 - 1.0)
                h = half * grow * max(fade, 0.12) * min(1.0, hw / HALF + 0.25) * wob
                lefts.append(ink.vert(self.on_top(a, side * xc - h, FILLET_LIFT)))
                rights.append(ink.vert(self.on_top(a, side * xc + h, FILLET_LIFT)))
            for i in range(len(rows) - 1):
                _, _, up, _ = self.frames.at(rows[i])
                ink.tri(lefts[i], rights[i], rights[i + 1], up)
                ink.tri(lefts[i], rights[i + 1], lefts[i + 1], up)

    # -- the pale thread -------------------------------------------------------------------------

    def pale(self, core: Mesh) -> None:
        """One even thin line on the ridge: pointed where it starts inside the chevron, constant over
        the body, drawn to a point over its last PALE_TAPER."""
        st = stations(self.length)
        start = next(a / 100 for a in range(1, 600) if self.fillet_x(a / 100) - FILLET_HALF[0] - 0.12 >= 0.06)
        ramp = 1.4  # studs over which it opens out of its point
        fall = PALE_END - PALE_TAPER * (PALE_END - start)
        rows = [start] + [a for a in st if start < a < PALE_END]
        rows += [start + ramp * f for f in (0.35, 1.0)]
        rows += [fall + (PALE_END - fall) * f for f in (0.0, 0.4, 0.75, 1.0)]
        rows = sorted(set(r for r in rows if start <= r <= PALE_END))
        ids = []
        for a in rows:
            room = self.fillet_x(a) - FILLET_HALF[0] - 0.12
            p = min(PALE_HALF, room) * min(1.0, (a - start) / ramp) ** 0.7
            if a > fall:
                p *= (1.0 - (a - fall) / (PALE_END - fall)) ** 0.8
            ids.append([core.vert(self.on_top(a, x, PALE_LIFT)) for x in (-p, 0.0, p)])
        for i in range(len(rows) - 1):
            _, _, up, _ = self.frames.at(rows[i])
            for j in range(2):
                a0, a1, b0, b1 = ids[i][j], ids[i][j + 1], ids[i + 1][j], ids[i + 1][j + 1]
                core.tri(a0, a1, b1, up)
                core.tri(a0, b1, b0, up)

    # -- the flourishes --------------------------------------------------------------------------

    def flourishes(self) -> list[Volume]:
        """The two calligraphic flourishes of the model sheet's tail: a spiral curl out of the left
        edge at the foot of the lift, rising back over the bend, and a crook off the right edge
        higher up that hooks outward and down. Each leaves the flick at a hairline, swells in its
        bowl and ends at a point, and lies in a plane turned only a little off the thrower's view,
        so it reads face-on from behind, is a thin pen line from the side, and keeps its shape when
        a short reach squeezes Z. Nothing goes ahead of the flick: that is past the ray's stop."""
        span = self.length - FLICK_FROM
        up = (0.0, 1.0, 0.0)
        out = []
        for (share, edge, lean, path, rmax, segs), tilt in zip(CURLS, TILTS):
            a = FLICK_FROM + share * span
            hw, rid, _ = self.dims(a)
            root = self.point(a, edge * 0.8 * hw, 0.3 * rid)
            side = norm((edge * math.cos(math.radians(lean)), 0.0, math.sin(math.radians(lean))))
            rise = norm(add(up, tilt))
            pts = [add(root, add(mul(side, p), mul(rise, q))) for p, q in path]
            out.append(swell_tube(pts, rmax, segs, norm(cross(side, rise))))
        return out


def _spiral(centre, r0, r1, turns):
    """A pen's spiral in its plane (out, up): it rises from the root up the side nearest the flick,
    rolls over the top, outward and under, and winds in to `r1` after `turns`."""
    cx, cy = centre
    pts = [(0.0, 0.0), (0.12, 0.42 * cy)]
    n = int(turns * 8) + 1
    for i in range(n + 1):
        f = i / n
        theta = math.pi - f * turns * 2.0 * math.pi
        r = r0 + (r1 - r0) * f
        pts.append((cx + r * math.cos(theta), cy + r * math.sin(theta)))
    return pts


# (share of the flick where it leaves, which edge, how far its plane turns toward the thrower in
# degrees, its path in that plane (out, up) in studs, its thickest radius, its rows)
CURLS = (
    (0.16, -1.0, 18.0, _spiral((0.8, 1.1), 0.56, 0.14, 1.3), 0.16, 15),
    (0.55, 1.0, 12.0, [(0.0, 0.0), (0.14, 0.41), (0.3, 0.8), (0.53, 1.08), (0.78, 1.15), (0.97, 1.03),
                        (1.01, 0.83)], 0.12, 8),
)
# How each flourish's plane leans off the vertical: the spiral out over its edge, the crook a touch
# out and back toward the thrower.
TILTS = ((-0.4, 0.0, 0.08), (0.18, 0.0, 0.12))
FLOURISH_FLAT = 0.45  # thickness across the flourish's plane, as a share of its width in it


def swell_tube(control: list, rmax: float, segs: int, normal, sides: int = 3) -> Volume:
    """A closed tendril along a Catmull-Rom path: a hairline where it leaves, swelling to `rmax`
    past its middle, then drawn out to a point (a pen's flourish, not a rope). Its section is a flat
    triangle, wide in the flourish's plane and FLOURISH_FLAT as thick across it (`normal`)."""
    vol = Volume()
    line = Polyline(catmull(control, 16))
    centres = [line.at(i / segs) for i in range(segs + 1)]
    tangents = [norm(sub(centres[min(i + 1, segs)], centres[max(i - 1, 0)])) for i in range(segs + 1)]
    rings = []
    for i in range(segs):
        along = tangents[i]
        across = norm(sub(normal, mul(along, dot(normal, along))))
        inplane = norm(cross(across, along))
        f = i / segs
        if f < 0.85:
            r = 0.25 * rmax + 0.75 * rmax * math.sin(math.pi * min(1.0, f / 0.85) ** 0.8)
        else:
            r = rmax * 0.25 * (1.0 - (f - 0.85) / 0.15) + 0.01
        r = max(r, 0.012)
        ring = []
        for k in range(sides):
            angle = math.pi / 2 + 2 * math.pi * k / sides
            q = add(centres[i], add(mul(inplane, r * math.sin(angle)), mul(across, FLOURISH_FLAT * r * math.cos(angle))))
            ring.append(vol.vert(q, 0.0))
        rings.append(ring)
    tip = vol.vert(centres[-1], 0.0)
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for j in range(sides):
            k = (j + 1) % sides
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    last = rings[-1]
    for j in range(sides):
        emit(vol.mesh, last[j], last[(j + 1) % sides], tip)
    first = rings[0]
    emit(vol.mesh, first[0], first[2], first[1])
    vol.orient_outward()
    return vol


def inverted(vol: Volume, into: Mesh) -> None:
    """A closed volume wound inside out into `into`: drawn with back faces culled, only the rim that
    stands out of the gold's silhouette shows, as the contour."""
    base = len(into.verts)
    into.verts.extend(vol.mesh.verts)
    for a, b, c in vol.mesh.tris:
        emit(into, a + base, c + base, b + base)


_CACHE: dict = {}


def build() -> tuple[Mesh, Mesh, Mesh]:
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    b = Build()
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    body.merge(b.blade().mesh)
    inverted(b.contour(), ink)
    b.fillets(ink)
    b.pale(core)
    for vol in b.flourishes():
        ink.merge(vol.mesh)
    # Length 1 along -Z over the outer ink, the muzzle at z = 0: never behind the muzzle, never past
    # the stop.
    zs = [v[2] for m in (body, core, ink) for v in m.verts]
    top, bottom = max(zs), min(zs)
    factor = 1.0 / (top - bottom)
    for m in (body, core, ink):
        m.verts = [(x * factor, y * factor, (z - top) * factor) for x, y, z in m.verts]
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta(seed: int) -> dict:
    return {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": seed}


def rature_band():
    return build()[0], meta(SEED)


def rature_spine():
    return build()[1], meta(SEED + 1)


def rature_ink():
    return build()[2], meta(SEED + 2)
