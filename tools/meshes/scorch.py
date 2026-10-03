"""The Scorch's crown, "le Fleuron": twelve flame tongues standing on a thin ring on the page round the caster.

Drawn from the developer's references (docs/vfx/scorch/ref-1.jpg, the in-game shot, and
docs/vfx/scorch/ref-2.jpg, the model sheet "Cinnabar ink flame crown"). Broad flat S-flame blades, after
the bible (13.4): 0.062-0.085 of the diameter wide at the widest, widest at 60 % of the height, contour
0.10-0.17 stud, streak 0.15-0.8 of the height.

Twelve hooked flame tongues stand on a thin closed ring at the server's radius, long and short
alternating (3.2 and 2.2 studs over the page), every hook curling the same way. Each tongue is a flat
blade drawn as a calligraphic S-flame in its own plane, as the in-game shot draws them: a pinched root on
the ring's inner half, a leaf of a body, then a long neck that tapers as it leans back and rises into a
thin crook. The crook turns over through 180 degrees and ends in a sharp tip that points down and out,
so its mouth stays open. There is no bend out of the blade's plane: a tongue bent in toward the middle
sheared its hook.

The plane leans out 6 degrees (at most 8). Its face is turned 30 degrees from the radial toward the
tangent at the root (the sheet's face turn) and twists back 20 degrees over the height, so every face
shows to the thrower's camera.

Roblox space: X right, Y up, forward -Z. Reference OuterDiameter = 1 (26 studs: Radius 13), axis Y,
pivot (0, 0, 0) on the floor under the thrower's root. The contour of the ring lies on the page at
r = 0.5 and nothing reaches past it (every tongue is fitted to keep its own contour inside 0.4985).

theta counts from +X toward -Z (a positive Spin turns +theta). The game spins the crown at -1.2 rad/s;
every hook curls toward +theta, trailing against the spin.

Three meshes, one tone each, one construction:
  ScorchCrown (Pigment): the ring (46 segments) and the twelve tongues. A tongue's section is a blade
    with one sharp edge and one squared back (three faces, not four): the volume is flat-toned, so the
    section never shows.
  ScorchCore (Core): a pale streak on both faces of every tongue that follows its S (on the outside of
    the body's bend, crossing over to the outside of the neck and the crook), sampled on its own
    stations so its cost does not grow with the tongue's rows, and a hot wire along the ring's top.
  ScorchInk (Ink): the inverted hull of the ring (its outer edge on the page at r = 0.5) and of every
    tongue. No flow line: the references draw none on the tongues, and one tried down the body read as
    a doubled contour.
"""

from __future__ import annotations

import math

from strokes import Mesh, Polyline, Rng, fbm

SEED = 6113
TONGUES = 12
STUD = 1.0 / 26.0

# The ring: a closed thin band on the page (bible 13.4).
RING_IN = 0.466
RING_OUT = 0.494
RING_H = 0.0096
RING_SEGS = 46  # 7.8 degrees a facet: the far arc reads as a curve from the thrower's camera
RING_HULL = 0.5 - RING_OUT  # its outer contour lands on the page at exactly r = 0.5
RING_HULL_TOP = 0.0052
FLOOR = 0.065 * STUD  # how far the ink stays over the page
WIRE = 0.0042  # the hot wire on the ring's top
LIFT = 0.06 * STUD  # how far the core lies off the pigment
WIRE_LIFT = 0.03 * STUD  # the wire over the ring's ridge (0.07 stud over the slopes at its edges)

ROOT_MAX = 0.477  # the tongues' roots, inside the ring's inner half (0.466 - 0.48); see Tongue.fit
LEAN_MAX = math.radians(8.0)
ROOT_Y = 0.35 * RING_H  # buried in the ring


def monotone(ctrl: list, x: float) -> float:
    """A monotone cubic through (x, value) pairs (Fritsch-Carlson): smooth, and never past a control, so
    a heading told to stop turning at a point stops there (a cosine ease paused at every control)."""
    xs = [c[0] for c in ctrl]
    ys = [c[1] for c in ctrl]
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    n = len(xs)
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [d[0]] + [0.0 if d[i - 1] * d[i] <= 0 else (d[i - 1] + d[i]) / 2.0 for i in range(1, n - 1)] + [d[-1]]
    for i in range(n - 1):
        if d[i] == 0.0:
            m[i] = m[i + 1] = 0.0
            continue
        a, b = m[i] / d[i], m[i + 1] / d[i]
        q = a * a + b * b
        if q > 9.0:
            k = 3.0 / math.sqrt(q)
            m[i], m[i + 1] = k * a * d[i], k * b * d[i]
    i = max(j for j in range(n - 1) if xs[j] <= x)
    h = xs[i + 1] - xs[i]
    t = (x - xs[i]) / h
    t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1]


STEP = 0.01  # (studs) the spine is walked in steps this long


def spine(heading: list) -> list:
    """A tongue's spine drawn flat in its own plane (w along the ring toward +theta, h up, in studs),
    walked from the root by its heading: degrees from straight up, positive toward +w, the way the hook
    curls. `heading` is (arc length in studs, degrees) pairs; one point every STEP."""
    length = heading[-1][0]
    n = round(length / STEP)
    pts = [(0.0, 0.0)]
    for i in range(n):
        a = math.radians(monotone(heading, (i + 0.5) * STEP))
        w, h = pts[-1]
        pts.append((w + math.sin(a) * STEP, h + math.cos(a) * STEP))
    return pts


def hook_rows(heading: list, curl: float, spans: int) -> list:
    """The arc lengths of the hook's rows: from the curl's start to the tip in `spans` equal steps of
    turn (the hook turns 172 degrees: 25 a row on a long tongue, 29 on a short one)."""
    end = heading[-1][0]
    h0, h1 = monotone(heading, curl), monotone(heading, end)
    out = []
    for k in range(1, spans):
        goal = h0 + (h1 - h0) * k / spans
        lo, hi = curl, end
        for _ in range(40):
            mid = (lo + hi) / 2.0
            if monotone(heading, mid) < goal:
                lo = mid
            else:
                hi = mid
        out.append(round(lo, 4))
    return out + [end]


# The tongues, in studs, drawn in their own plane: broad flat S-flame blades (the sheet's TONGUE DETAIL
# and SIDE VIEW, the bible's 13.4). Each leaves the ring heading 26 degrees toward +w on a narrow root,
# bows the other way over the belly (toward -w), runs up a short neck, then turns over through 116 degrees
# into a tangential hook toward +w that ends in a sharp tip. "heading" is the spine's heading by arc length
# (degrees from straight up, positive toward +w); "width" the blade's width by arc length: a narrow root
# (0.42 stud), widest at about 60 % of the height (2.0 studs, 0.077 of the diameter, on a long tongue; 1.6,
# 0.062, on a short one), the neck thinned to 0.8 stud where the hook begins, a hook that tapers to the
# tip; "rows" the arc lengths that are rows of the mesh up to the curl's start, then "spans" rows over the
# hook, evenly in turn; "curl" the arc where the hook begins (the body is scaled upright below it, the
# hook rides unscaled so it stays round); "streak" the height share where the pale streak starts and the
# arc where it ends (0.8 of the height, where the hook begins).
_LONG_CURL = 3.0
_LONG_HEADING = [(0.0, 30.0), (0.5, 16.0), (1.0, -6.0), (1.5, -22.0), (2.0, -26.0), (2.5, -14.0), (3.0, 8.0), (3.4, 38.0),
                 (3.7, 66.0), (4.0, 88.0), (4.2, 98.0)]
_SHORT_SCALE = 0.69  # 2.2 over 3.2 studs
_SHORT_HEADING = [(round(a * _SHORT_SCALE, 4), h) for a, h in _LONG_HEADING]
_LONG_WIDTH = [(0.0, 0.4), (0.5, 0.66), (1.0, 1.15), (1.6, 1.72), (2.2, 2.1), (2.7, 1.55), (3.1, 0.95), (3.45, 0.6), (3.75, 0.36),
               (4.0, 0.16), (4.2, 0.0)]
_SHORT_WIDTH = [(round(a * _SHORT_SCALE, 4), w * 0.8) for a, w in _LONG_WIDTH]
_LONG_BODY = [0.0, 0.35, 0.7, 1.05, 1.4, 1.75, 2.1, 2.5, _LONG_CURL]
_SHORT_CURL = round(_LONG_CURL * _SHORT_SCALE, 4)
TONGUE = {
    True: {
        "heading": _LONG_HEADING,
        "width": _LONG_WIDTH,
        "rows": _LONG_BODY + hook_rows(_LONG_HEADING, _LONG_CURL, 5),
        "curl": _LONG_CURL,
        "top": 3.2,
        "streak": (0.15, _LONG_CURL),
    },
    False: {
        "heading": _SHORT_HEADING,
        "width": _SHORT_WIDTH,
        "rows": [round(a * _SHORT_SCALE, 4) for a in _LONG_BODY[:-1]] + [_SHORT_CURL] + hook_rows(_SHORT_HEADING, _SHORT_CURL, 5),
        "curl": _SHORT_CURL,
        "top": 2.2,
        "streak": (0.15, _SHORT_CURL),
    },
}
THICK = (0.18, 0.08)  # (studs) the slab's back at the root and toward the tip
FACE_TURN = math.radians(30.0)  # at the root; the sheet's 30 degrees toward the tangent
# How far the face turns back toward the thrower from root to tip.
TWIST = math.radians(-20.0)
LEAN = math.radians(6.0)  # outward, at most 8 degrees
REACH = 0.4985  # how far out any tongue reaches, contour included (the ring's contour is at 0.5)
# The contour beside the blade: 0.10 stud on the slim parts to 0.17 where the blade is widest, inside the
# bible's 0.1-0.2 stud (0.15-0.2 at the roots, 0.1 at the tips). Over the faces 0.05 to 0.08.
HULL_SIDE = (0.10, 0.17)
HULL_FACE = (0.05, 0.08)  # (studs) over the faces
HULL_TIP = 0.14  # (studs) how far the contour runs past the tip
STREAK_U = (0.6, 0.38)  # where across the face the streak runs (0 the -W edge, 1 the +W edge)
STREAK_SPREAD = 0.1  # its half-width as a share of the face (0.4 stud overall where the blade is widest)
STREAK_STATIONS = 6  # samples down the streak (5 spans, 8 triangles a face)


# --- vectors -------------------------------------------------------------------------------------


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def lerp(a, b, f):
    return add(a, mul(sub(b, a), f))


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


def smooth(e0, e1, x):
    u = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def radial(theta):
    return (math.cos(theta), 0.0, -math.sin(theta))


def tangent(theta):
    return (-math.sin(theta), 0.0, -math.cos(theta))


# --- skinning ------------------------------------------------------------------------------------


def place(point, across, normal, corners):
    return [add(point, add(mul(across, x), mul(normal, y))) for x, y in corners]


def blade(half, depth):
    """A tongue's section, counter-clockwise in (across, normal): the sharp edge (+across), the back's
    top and the back's bottom (-across). Corners 0-1 are the top face, 2-0 the bottom face."""
    return [(half, 0.0), (-half, depth / 2.0), (-half, -depth / 2.0)]


def skin(mesh: Mesh, rows: list, inward: bool, floor: float = 0.0) -> list[list[int]]:
    """A blade through `rows`, each (point, across, normal, corners) or (point,) for a collapsed tip, each
    face wound by its outward normal in the section plane (inverted for a hull). Its first row is left
    open: a tongue's root is buried in the ring, and the triangles go to the crook instead."""
    sides = max(len(row[3]) for row in rows if len(row) == 4)
    ids = []
    for row in rows:
        if len(row) == 1:
            ids.append([mesh.vert(row[0])] * sides)
        else:
            ids.append([mesh.vert((c[0], max(c[1], floor), c[2])) for c in place(*row)])
    sign = -1.0 if inward else 1.0
    for k in range(len(rows) - 1):
        full = [row for row in (rows[k], rows[k + 1]) if len(row) == 4]
        across = unit(add(full[0][1], full[-1][1]))
        normal = unit(add(full[0][2], full[-1][2]))
        for e in range(sides):
            f = (e + 1) % sides
            fx = fy = 0.0
            for row in full:
                (x0, y0), (x1, y1) = row[3][e], row[3][f]
                fx += y1 - y0
                fy -= x1 - x0
            facing = mul(add(mul(across, fx), mul(normal, fy)), sign)
            r0, r1 = ids[k], ids[k + 1]
            mesh.tri(r0[e], r0[f], r1[f], facing)
            mesh.tri(r0[e], r1[f], r1[e], facing)
    return ids


# --- the ring ------------------------------------------------------------------------------------


def ring_section(inset: float, top: float, floor: float):
    """The ring's section in (r, y): a tent, inner foot, ridge, outer foot. The volume is flat-toned, so
    the section never shows, and a tent costs 4 pigment and 6 ink triangles a segment (a band, 6 and 8):
    what it saves buys the ring 46 segments."""
    return [(RING_IN - inset, floor), ((RING_IN + RING_OUT) / 2.0, RING_H + top), (RING_OUT + inset, floor)]


def in_arc(theta: float, arc) -> bool:
    if arc is None:
        return True
    lo, hi = arc
    return lo <= theta <= hi


def build_ring(mesh: Mesh, section, inward: bool, arc=None, bottom: bool = True) -> None:
    rings = []
    for i in range(RING_SEGS):
        theta = 2.0 * math.pi * i / RING_SEGS
        r = radial(theta)
        rings.append([mesh.vert((r[0] * x, y, r[2] * x)) for x, y in section])
    sides = len(section)
    centre_line = [sum(x for x, _ in section) / sides, sum(y for _, y in section) / sides]
    for i in range(RING_SEGS):
        a, b = rings[i], rings[(i + 1) % RING_SEGS]
        mid = (2.0 * math.pi * (i + 0.5)) / RING_SEGS
        if not in_arc(mid, arc):
            continue
        rm = radial(mid)
        for e in range(sides if bottom else sides - 1):
            f = (e + 1) % sides
            (x0, y0), (x1, y1) = section[e], section[f]
            nx, ny = (y1 - y0), -(x1 - x0)  # a normal to the edge in the (r, y) plane, turned outward below
            cx, cy = (x0 + x1) / 2.0 - centre_line[0], (y0 + y1) / 2.0 - centre_line[1]
            if nx * cx + ny * cy < 0:
                nx, ny = -nx, -ny
            facing = (rm[0] * nx, ny, rm[2] * nx)
            if inward:
                facing = mul(facing, -1.0)
            mesh.tri(a[e], a[f], b[f], facing)
            mesh.tri(a[e], b[f], b[e], facing)


def build_wire(core: Mesh, arc=None) -> None:
    mid = (RING_IN + RING_OUT) / 2.0
    left, right = [], []
    for i in range(RING_SEGS):
        r = radial(2.0 * math.pi * i / RING_SEGS)
        left.append(core.vert((r[0] * (mid - WIRE / 2), RING_H + WIRE_LIFT, r[2] * (mid - WIRE / 2))))
        right.append(core.vert((r[0] * (mid + WIRE / 2), RING_H + WIRE_LIFT, r[2] * (mid + WIRE / 2))))
    for i in range(RING_SEGS):
        j = (i + 1) % RING_SEGS
        if not in_arc(2.0 * math.pi * (i + 0.5) / RING_SEGS, arc):
            continue
        core.tri(left[i], right[i], right[j], (0, 1, 0))
        core.tri(left[i], right[j], left[j], (0, 1, 0))


# --- the tongues ---------------------------------------------------------------------------------


def specs() -> list[dict]:
    rng = Rng(SEED)
    out = []
    for k in range(TONGUES):
        long = k % 2 == 0
        out.append(
            {
                "k": k,
                "long": long,
                "theta": 2.0 * math.pi * k / TONGUES + math.radians(2.5) * (rng.random() * 2 - 1),
                "top": TONGUE[long]["top"] * (1.0 - 0.03 * rng.random()),
                "curl": 1.0 + 0.05 * (rng.random() * 2 - 1),
                "turn": FACE_TURN + math.radians(3.0) * (rng.random() * 2 - 1),
                "lean": LEAN * (0.85 + 0.3 * rng.random()),
                "wide": 1.0 + 0.03 * (rng.random() * 2 - 1),
                "seed": SEED + 37 * k,
            }
        )
    return out


class Tongue:
    def __init__(self, spec: dict) -> None:
        self.spec = spec
        shape = TONGUE[spec["long"]]
        # The hook's reach varies a little from tongue to tongue, blended in up the neck.
        top = max(h for _, h in spine(shape["heading"]))
        dense = [(w * (1.0 + (spec["curl"] - 1.0) * smooth(0.4 * top, 0.75 * top, h)), h) for w, h in spine(shape["heading"])]
        self.line = Polyline(dense)
        self.shape = shape
        # Arc lengths (studs, as drawn) to arc fractions of the built spine.
        last = len(dense) - 1

        def frac(arc: float) -> float:
            return self.line.acc[min(last, round(arc / STEP))] / self.line.acc[-1]

        self.frac = frac
        self.stations = [frac(a) for a in shape["rows"]]
        self.widths = [(frac(a), wd) for a, wd in shape["width"]]
        # The body is scaled upright (the hook rides on it unscaled, so it stays round) until the built
        # pigment's top over the page is the tongue's height exactly (3.2 or 2.2 studs at most): the top
        # moves by the neck's height for each unit of the scale, so a few Newton steps settle it.
        self.crook_s = frac(shape["curl"])
        self.neck = shape["rows"].index(shape["curl"])  # the row where the curl begins
        self.neck_h = self.line.at(self.crook_s)[1]
        self.vscale = 1.0
        self.root_r = ROOT_MAX
        self.lean = min(spec["lean"], LEAN_MAX)
        self.fit()
        for _ in range(5):
            built = self.pigment_top()
            self.vscale += (spec["top"] - built) / self.neck_h
            self.fit()

    def pigment_top(self) -> float:
        """The pigment's highest point over the page, in studs."""
        return max(q[1] for row in self.rows(hull=False) for q in (place(*row) if len(row) == 4 else [row[0]])) / STUD

    def reach(self) -> float:
        return max(math.hypot(q[0], q[2]) for row in self.rows(hull=True) for q in (place(*row) if len(row) == 4 else [row[0]]))

    def fit(self) -> None:
        """The root on the ring's inner half and the tongue leaning out as far as the contour allows, up
        to the spec's lean (never past 8 degrees): the farthest point of the tongue's hull stays at or
        inside REACH. If even upright it reaches past, the root moves in instead."""
        want = min(self.spec["lean"], LEAN_MAX)
        self.root_r = ROOT_MAX
        self.lean = want
        if self.reach() > REACH:
            lo, hi = 0.0, want
            for _ in range(30):
                self.lean = (lo + hi) / 2.0
                if self.reach() > REACH:
                    hi = self.lean
                else:
                    lo = self.lean
            self.lean = lo
            for _ in range(3):
                if self.reach() > REACH:
                    self.root_r += REACH - self.reach()

    def plane(self, s: float):
        """The face plane's horizontal axis W and its inward normal N at s. W runs toward +theta and turns
        out by the face turn, so the body, which leans toward -W, leans in toward the thrower and back
        against the hook: from above the twelve tongues are the vanes of a pinwheel reaching in from the
        rim, and the ring's outer edge keeps the contour inside r = 0.5."""
        th = self.spec["theta"]
        phi = self.spec["turn"] + TWIST * s
        R, T = radial(th), tangent(th)
        W = add(mul(T, math.cos(phi)), mul(R, math.sin(phi)))
        N = mul(sub(mul(R, math.cos(phi)), mul(T, math.sin(phi))), -1.0)
        return W, N

    def width(self, s: float) -> float:
        return monotone(self.widths, s) * self.spec["wide"] * (1.0 + 0.04 * (fbm(4.0 * s, 0.2, self.spec["seed"]) * 2 - 1))

    def contour(self, s: float):
        """The contour's weight (studs) beside the blade and over its faces at s: HULL_SIDE (HULL_FACE)
        from the slim parts to the widest."""
        k = smooth(0.5, 1.9, self.width(s))
        side = HULL_SIDE[0] + (HULL_SIDE[1] - HULL_SIDE[0]) * k
        face = HULL_FACE[0] + (HULL_FACE[1] - HULL_FACE[0]) * k
        return side, face

    def flat(self, s: float):
        w, h = self.line.at(s)
        if s <= self.crook_s:
            return w, h * self.vscale
        return w, h - self.neck_h * (1.0 - self.vscale)

    def point(self, s: float):
        """The spine in 3D, in reference units."""
        w, h = self.flat(s)
        th = self.spec["theta"]
        W, N = self.plane(s)
        base = add(mul(radial(th), self.root_r), (0.0, ROOT_Y, 0.0))
        lean = math.tan(self.lean) * h
        # No bend out of the face's plane: one bent in toward the middle sheared the hook (its falling
        # stroke went in further than its rise), and seen face-on the round C flattened into an arch.
        return add(base, add(mul(W, w * STUD), add((0.0, h * STUD, 0.0), mul(radial(th), lean * STUD))))

    def frame(self, s: float):
        p = self.point(s)
        e = 1e-3
        t = unit(sub(self.point(min(1.0, s + e)), self.point(max(0.0, s - e))))
        _, N = self.plane(s)
        n = unit(sub(N, mul(t, dot(N, t))))
        across = unit(cross(t, n))
        return p, t, n, across

    def rows(self, hull: bool):
        out = []
        for i, s in enumerate(self.stations):
            p, t, n, across = self.frame(s)
            if i == len(self.stations) - 1:
                tip = add(p, mul(t, HULL_TIP * STUD)) if hull else p
                out.append((tip,))
                continue
            half = self.width(s) / 2.0
            depth = THICK[0] + (THICK[1] - THICK[0]) * s
            if hull:
                side, face = self.contour(s)
                corners = blade((half + side) * STUD, (depth + 2 * face) * STUD)
                if i == 0:
                    p = sub(p, mul(t, 0.1 * STUD))
            else:
                corners = blade(half * STUD, depth * STUD)
            out.append((p, across, n, corners))
        return out

    def minus_w_is_plus_across(self) -> bool:
        W, _ = self.plane(0.0)
        _, _, _, across = self.frame(0.0)
        return dot(across, W) < 0

    def height_at(self, share: float) -> float:
        """The arc fraction where the spine first reaches `share` of its top (before the crook)."""
        top = max(self.flat(i / 400)[1] for i in range(401))
        for i in range(401):
            if self.flat(i / 400)[1] >= share * top:
                return i / 400
        return 1.0


def streak(core: Mesh, corners: list, normals: list, stations: list, face: tuple[int, int], span: tuple[float, float], share, normal_sign: float) -> None:
    """A pale lens on one face of a tongue over the arc span, pointed at both ends, sampled at its own
    stations: each sample lies on the pigment's face (bilinear between the two rows around it, across
    between the face's two corners) and is lifted off it along the face's normal. `share(s)` is where
    across the face (0 at corner i, 1 at corner j) its middle runs."""
    i, j = face
    ids = []
    s0, s1 = span
    for m in range(STREAK_STATIONS):
        g = m / (STREAK_STATIONS - 1)
        s = s0 + (s1 - s0) * g
        k = max(0, min(len(stations) - 2, next(x for x in range(len(stations) - 1) if stations[x + 1] >= s)))
        v = (s - stations[k]) / (stations[k + 1] - stations[k])
        a = lerp(corners[k][i], corners[k + 1][i], v)
        b = lerp(corners[k][j], corners[k + 1][j], v)
        n = mul(unit(lerp(normals[k], normals[k + 1], v)), normal_sign)
        # Fullest a little under its middle, where the body is widest, as the reference draws it.
        f = math.sin(math.pi * g ** 0.85) ** 0.7
        centre = share(s)
        if f < 1e-6:
            ids.append((core.vert(add(lerp(a, b, centre), mul(n, LIFT))),))
            continue
        lo, hi = centre - STREAK_SPREAD * f, centre + STREAK_SPREAD * f
        ids.append((core.vert(add(lerp(a, b, lo), mul(n, LIFT))), core.vert(add(lerp(a, b, hi), mul(n, LIFT))), n))
    for m in range(len(ids) - 1):
        r0, r1 = ids[m], ids[m + 1]
        n = r0[2] if len(r0) == 3 else r1[2]
        if len(r0) == 1:
            core.tri(r0[0], r1[0], r1[1], n)
        elif len(r1) == 1:
            core.tri(r0[0], r0[1], r1[0], n)
        else:
            core.tri(r0[0], r0[1], r1[1], n)
            core.tri(r0[0], r1[1], r1[0], n)


def build_tongue(body: Mesh, core: Mesh, ink: Mesh, spec: dict) -> None:
    tongue = Tongue(spec)
    rows = tongue.rows(hull=False)
    skin(body, rows, inward=False)
    skin(ink, tongue.rows(hull=True), inward=True, floor=FLOOR)
    sides = len(rows[0][3])
    corners = [place(*row) if len(row) == 4 else [row[0]] * sides for row in rows]
    normals = [row[2] if len(row) == 4 else rows[-2][2] for row in rows]
    low, end = tongue.shape["streak"]
    span = (tongue.height_at(low), tongue.frac(end))
    flip = tongue.minus_w_is_plus_across()
    # Where the streak runs across the tongue, 0 on the edge that starts on the -W side and 1 on the
    # other: along the outside of the lower body's bend, crossing over to the outside of the neck and
    # the crook, as the reference draws it (a pale line that follows the S).
    def edge(s: float) -> float:
        return STREAK_U[0] + (STREAK_U[1] - STREAK_U[0]) * smooth(0.25, 0.6, s)

    # Top face: corner 0 (+across) to corner 1 (-across); bottom face: corner 2 (-across) to 0 (+across).
    def top(s: float) -> float:
        return edge(s) if flip else 1.0 - edge(s)

    streak(core, corners, normals, tongue.stations, (0, 1), span, top, 1.0)
    streak(core, corners, normals, tongue.stations, (2, 0), span, lambda s: 1.0 - top(s), -1.0)


# --- the three meshes ----------------------------------------------------------------------------

_CACHE: dict = {}


def build(arc=None):
    key = ("m", arc)
    if key in _CACHE:
        return _CACHE[key]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    build_ring(body, ring_section(0.0, 0.0, 0.0), inward=False, arc=arc, bottom=False)
    build_ring(ink, ring_section(RING_HULL, RING_HULL_TOP, FLOOR), inward=True, arc=arc)
    build_wire(core, arc)
    for spec in specs():
        if in_arc(spec["theta"], arc):
            build_tongue(body, core, ink, spec)
    _CACHE[key] = (body, core, ink)
    return _CACHE[key]


def meta() -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": SEED}


def scorch_crown():
    return build()[0], meta()


def scorch_core():
    return build()[1], meta()


def scorch_ink():
    return build()[2], meta()
