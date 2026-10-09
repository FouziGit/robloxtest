"""The Rupture's crown of downstrokes: a horseshoe band on the page carrying sixteen hooked blades, drawn
from the developer's references (docs/vfx/rupture/ref-1.jpg, the in-game shot; docs/vfx/rupture/ref-2.jpg,
the model sheet).

ref-2 (the model sheet, "Umber Ink Downstroke Crown") decides the shape: a horseshoe band on the page, open at
the rear, carrying all sixteen blades -- 4 tall twisting, 6 medium, 6 rim teeth, the teeth at the band's two
ends; a lens section with a quarter-turn twist (broad across the band at the root, broad in the hook's plane at
the top); every point finishing in a sideways hook; a pale lobe under the hook; torn page flaps and a dark crack
mouth at the roots; a pale liseré up the tall blades and along the band; a hard ink contour. ref-1 (the in-game
shot) decides the scale against the avatar: the tall blades are about twice the avatar, slender stalks flaring
out, each finishing in a crochet hook whose tip tapers to a hair and tucks back into its stalk, the eye between
them a narrow pale slit; the page split into dark cracks running out from the roots.

Server truth (GlyphEffects.Rupture, GlyphConfig): one pass at the thrower's root, Radius 18, a vertical launch.
Reference OuterDiameter = 1 (36 studs): the outer ink falls at r = 0.5 -- the tips of the root cracks, flat on
the page, which run out from the blades' feet to the rim (ref-1's floor). Axis Y, pivot on the floor under the
root, forward (the aim) is -Z.

Margins carry the timeline's Spin (+0.5 rad/s, counter-clockwise seen from above: the crown turns ~6 degrees
toward negative beta by the end of the hold): the negative side closes on the notch, the positive side on the
aim. No piece within 46.5 degrees (negative side) or 42 degrees (positive side) of +Z, hull included; nothing
risen over 1.6 studs within 17 degrees (negative side) or 21.5 degrees (positive side) of the aim; nothing
risen at r < 0.11. Everything under the dome h <= sqrt(18^2 - r^2) + 3 studs with the eruption's 1.1 overshoot.
Every hook trails the spin: it curls toward +beta.

Contour weights after the bible (section 2 and 13.5, Terre d'Ombre 0.10 - 0.14 stud): HULL_MIN..HULL_MAX
reference units, 0.104 - 0.137 stud at the final size, heavier at the roots. Every piece stands on the floor at
FLOOR_CLEARANCE, the height the inverted hull is clamped to, so its foot meets its own ink with no strip under it.

Pale after the bible (Terre d'Ombre, <= 6 % of the drawn body, "un biseau, un liseré"; Core always ringed by
pigment): the slit eye closed by its own hook, a thin liseré on the tall blades' narrow facet, a thin liseré
along the band's top. The torn page flaps are pigment, contoured in ink.

Angles: beta from -Z (the aim) toward +X.

Three meshes from one construction:
  RuptureBody (Pigment) -- the band (closed underneath), the sixteen blades on it, the torn page flaps.
  RuptureCore (Core)    -- the slit eye in every tall and medium hook, the liseré up each tall blade, the
                           band's liseré and its two cut ends.
  RuptureInk  (Ink)     -- an inverted hull per piece, two flow lines riding each tall blade's twist, a dark
                           crack mouth at every tall and medium root, the band's foot and top crease drawn on
                           its walls, and the root cracks running out to the rim.
"""

from __future__ import annotations

import math

from fireball import clip
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
    inverted_hull,
    lerp,
    mul,
    norm,
    pressure,
    smoothstep,
    sub,
)

SEED = 7207
UP = (0.0, 1.0, 0.0)
STUD = 1.0 / 36.0
F = FLOOR_CLEARANCE  # every piece stands here: the floor line of its own hull
HULL_MAX = 0.0038  # 0.137 stud
HULL_MIN = 0.0029  # 0.104 stud

# --- the band (the crown's horseshoe on the page) --------------------------------------------------
RB = 0.27  # centre radius (9.7 studs)
BW = 0.058  # radial width at the floor (2.1 studs)
BH = 0.03  # height (1.08 studs)
B_TOP = 0.72  # the top is this share of the floor width (a chamfered slab)
B_SPAN = 132.0  # degrees each side of the aim
B_SEGS = 18
B_HULL = (0.0038, 0.0032)  # foot, top

# --- the section ----------------------------------------------------------------------------------
RIDGE = 0.35  # the lens ridge sits this share of the half-width off-centre (a broad nib's oblique cut)
LIP = (1.12, 1.25)  # the square lip at the root: this much wider and thicker than the stroke above it
FOOT = (1.2, 1.4)  # flared on the floor ring

LINE_LIFT = 0.0014
EYE_IN = 0.36  # the eye plate runs this share of the local stroke under it (its edge hidden)
EYE_ANGLES = (40, 100, 160, 220, 280)  # degrees round the scroll where the eye plate meets the loop

# Blades, in studs. beta (deg); h height; W/T root width (radial) and thickness; lean (outward at the top of
# the rise); bow (the stalk's counter-curve away from the scroll, mid rise); rho (the scroll's first radius);
# sweep (deg, past a full turn: the tip curls inside its own loop); tight (log-spiral closing per radian).
TALL = [
    {"beta": -49.0, "h": 12.4, "W": 2.3, "T": 1.0, "lean": 1.5, "bow": 0.5, "rho": 1.25, "sweep": 420, "tight": 0.15},
    {"beta": 47.5, "h": 12.0, "W": 2.3, "T": 1.0, "lean": 1.6, "bow": 0.45, "rho": 1.25, "sweep": 410, "tight": 0.15},
    {"beta": 102.0, "h": 11.2, "W": 2.2, "T": 0.95, "lean": 1.6, "bow": 0.5, "rho": 1.2, "sweep": 420, "tight": 0.15},
    {"beta": -101.0, "h": 10.6, "W": 2.2, "T": 0.95, "lean": 1.7, "bow": 0.45, "rho": 1.2, "sweep": 410, "tight": 0.15},
]
MEDIUM = [
    {"beta": -29.5, "h": 6.6, "W": 2.5, "T": 1.1, "lean": 0.8, "bow": 0.35, "rho": 0.85, "sweep": 390, "tight": 0.17},
    {"beta": 31.0, "h": 6.2, "W": 2.45, "T": 1.08, "lean": 0.8, "bow": 0.35, "rho": 0.82, "sweep": 380, "tight": 0.17},
    {"beta": -66.5, "h": 7.8, "W": 2.6, "T": 1.15, "lean": 1.0, "bow": 0.4, "rho": 0.9, "sweep": 390, "tight": 0.17},
    {"beta": 65.0, "h": 7.3, "W": 2.55, "T": 1.12, "lean": 1.0, "bow": 0.4, "rho": 0.88, "sweep": 385, "tight": 0.17},
    {"beta": -84.0, "h": 6.4, "W": 2.45, "T": 1.08, "lean": 0.9, "bow": 0.35, "rho": 0.82, "sweep": 380, "tight": 0.17},
    {"beta": 83.5, "h": 6.9, "W": 2.5, "T": 1.1, "lean": 0.9, "bow": 0.35, "rho": 0.85, "sweep": 390, "tight": 0.17},
]
# The rim teeth stand on the band's two ends: small fins broad along the rim (ref-2's side view), thin across
# it, their tops flicked toward +beta.
TEETH = [
    {"beta": -114.0, "h": 4.0, "W": 1.3, "T": 0.62, "lean": 0.25, "bow": 0.0, "rho": 1.6, "sweep": 38, "tight": 0.0},
    {"beta": 113.5, "h": 3.8, "W": 1.3, "T": 0.62, "lean": 0.25, "bow": 0.0, "rho": 1.6, "sweep": 38, "tight": 0.0},
    {"beta": -121.5, "h": 3.3, "W": 1.15, "T": 0.58, "lean": 0.2, "bow": 0.0, "rho": 1.4, "sweep": 36, "tight": 0.0},
    {"beta": 120.5, "h": 3.1, "W": 1.15, "T": 0.58, "lean": 0.2, "bow": 0.0, "rho": 1.4, "sweep": 36, "tight": 0.0},
    {"beta": -128.0, "h": 2.7, "W": 1.0, "T": 0.54, "lean": 0.2, "bow": 0.0, "rho": 1.2, "sweep": 34, "tight": 0.0},
    {"beta": 127.0, "h": 2.5, "W": 1.0, "T": 0.54, "lean": 0.2, "bow": 0.0, "rho": 1.2, "sweep": 34, "tight": 0.0},
]
ROOT_OUT = 0.004  # the blades stand a little outside the band's centre line, their lips over its outer edge

KINDS = {
    # stations as shares of each part: rise (of the rise's arc), scroll (of the scroll's arc); where the
    # quarter turn is done (share of the rise; a tooth does not turn); hull weights at the root, the scroll's
    # start, two thirds round it, the tip (reference units)
    "tall": {"rise": [0.25, 0.5, 0.75, 1.0], "scroll": [1 / 9, 2 / 9, 3 / 9, 4 / 9, 5 / 9, 6 / 9, 7 / 9, 8 / 9, 0.96], "twist": 0.62, "hull": (0.0038, 0.0034, 0.0031, 0.0029)},
    "middle": {"rise": [0.5, 1.0], "scroll": [1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 0.95], "twist": 0.66, "hull": (0.0037, 0.0033, 0.003, 0.0029)},
    "tooth": {"rise": [1.0], "scroll": [], "twist": 0.0, "hull": (0.0035, 0.0032, 0.0031, 0.0029)},
}
FLAPS = {"tall": 2, "middle": 0, "tooth": 0}
FLAP_HULL = 0.0029

# Root cracks: flat ink on the page from a blade's foot out to the rim -- the page split by the crown (ref-1's
# floor). beta (deg), reach (share of the rim), fork (share of the length, or None).
CRACKS = [
    (-118.0, 0.97, None),
    (-99.0, 1.0, 0.45),
    (-70.0, 0.975, None),
    (-47.0, 0.99, 0.5),
    (-27.0, 0.965, None),
    (31.0, 0.98, None),
    (49.0, 0.995, 0.45),
    (67.0, 0.97, None),
    (100.0, 0.99, 0.5),
    (119.0, 0.975, None),
]
CRACK_W = 0.0115
CRACK_LIFT = F + 0.0005
MIN_ALT = 0.02 * STUD  # a flat ink triangle thinner than this is a sliver, never drawn


def radial(beta: float):
    return (math.sin(beta), 0.0, -math.cos(beta))


def tangent(beta: float):
    """Toward increasing beta: clockwise seen from above (the spin turns the other way)."""
    return (math.cos(beta), 0.0, math.sin(beta))


def band_height_at(p) -> float:
    """The band's top over a floor point (its chamfers included), or the floor off the band."""
    r = math.hypot(p[0], p[2])
    beta = math.degrees(math.atan2(p[0], -p[2]))
    if abs(beta) > B_SPAN:
        return F
    d = abs(r - RB)
    if d <= 0.5 * BW * B_TOP:
        return F + BH
    if d <= 0.5 * BW:
        return F + BH * (0.5 * BW - d) / (0.5 * BW * (1.0 - B_TOP))
    return F


def altitude_ok(a, b, c) -> bool:
    """Whether a flat triangle is wider than a sliver: its smallest altitude over MIN_ALT."""
    n = cross(sub(b, a), sub(c, a))
    area2 = math.sqrt(dot(n, n))
    longest = max(math.dist(a, b), math.dist(b, c), math.dist(c, a))
    return longest > 0 and area2 / longest > MIN_ALT


class Blade:
    """One downstroke: a rise (flaring out, a counter-curve away from its scroll) that rolls over sideways into a
    tight scroll toward +beta, round past a full turn so its hair-fine tip curls inside its own loop, and a lens
    section carried along it, turning a quarter turn so it is broad across the band at the root and broad in the
    scroll's plane at the top: the scroll is a C seen face on, its eye pale round the curled tip."""

    def __init__(self, spec: dict, kind: str, seed: int) -> None:
        self.spec = spec
        self.kind = kind
        self.cfg = KINDS[kind]
        self.seed = seed
        self.beta = math.radians(spec["beta"])
        self.R = radial(self.beta)
        self.C = tangent(self.beta)  # the scroll's direction: trailing the spin
        self.Np = norm(cross(self.C, UP))  # the scroll plane's normal
        self.base = mul(self.R, RB + ROOT_OUT)
        rng = Rng(seed)
        h = spec["h"]
        L, b, rho = spec["lean"], spec["bow"], spec["rho"]
        phi, k = math.radians(spec["sweep"]), spec["tight"]
        wob = 0.12 * (rng.random() - 0.5)
        yc = h - 0.8 * rho if kind != "tooth" else h * 0.82
        # local (a: outward, c: toward the scroll, y: up), studs
        ctrl = [
            (0.0, 0.0, 0.0),
            (0.0, 0.0, 0.07 * yc),
            (0.3 * L, -0.6 * b + wob, 0.3 * yc),
            (0.78 * L, -0.85 * b, 0.56 * yc),
            (L, -0.45 * b, 0.8 * yc),
            (L, 0.0, yc),
        ]
        dense = catmull(ctrl, 14)
        n_rise = len(dense)
        (_, c1, y1), (_, c2, y2) = dense[-2], dense[-1]
        d = math.hypot(c2 - c1, y2 - y1)
        dc, dy = (c2 - c1) / d, (y2 - y1) / d
        cx, cy = c2 + rho * dy, y2 - rho * dc
        psi0 = math.atan2(y2 - cy, c2 - cx)
        steps = max(12, int(spec["sweep"] / 6))
        for i in range(1, steps + 1):
            t = i / steps
            psi = psi0 - phi * t
            r = rho * math.exp(-k * phi * t)
            dense.append((L, cx + r * math.cos(psi), cy + r * math.sin(psi)))
        self.line = Polyline([self.local(p) for p in dense])
        self.s_c = self.line.acc[n_rise - 1] / self.line.acc[-1]
        self.curl_centre = self.local((L, cx, cy))
        self.psi0, self.phi, self.k, self.rho = psi0, phi, k, rho * STUD
        self.stations = self._stations()

    def local(self, p):
        a, c, y = p
        return add(add(self.base, (0.0, F, 0.0)), add(mul(self.R, a * STUD), add((0.0, y * STUD, 0.0), mul(self.C, c * STUD))))

    def x_of(self, s: float) -> float:
        """0..1 up the rise, 1..2 round the scroll."""
        if s <= self.s_c:
            return s / self.s_c
        return 1.0 + (s - self.s_c) / max(1.0 - self.s_c, 1e-9)

    def s_of(self, x: float) -> float:
        if x <= 1.0:
            return x * self.s_c
        return self.s_c + (x - 1.0) * (1.0 - self.s_c)

    def s_at_height(self, y: float) -> float:
        lo, hi = 0.0, self.s_c
        for _ in range(50):
            mid = 0.5 * (lo + hi)
            if self.line.at(mid)[1] < y:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    def _stations(self) -> list[float]:
        lip = self.s_at_height(F + BH + 0.004)
        out = [0.0, lip]
        out += [max(lip + 0.01, self.s_of(f)) for f in self.cfg["rise"]]
        out += [self.s_of(1.0 + f) for f in self.cfg["scroll"]]
        return out

    def width_x(self, x: float) -> float:
        """The broad axis: across the band at the root (the wedge the thrower sees), the scroll's depth at the top."""
        w0, kind = self.spec["W"] * STUD, self.kind
        if kind == "middle":
            return cosine_curve([(0.0, w0), (0.1, 1.0 * w0), (0.6, 0.64 * w0), (1.0, 0.42 * w0), (1.5, 0.26 * w0), (2.0, 0.08 * w0)], x)
        if kind == "tooth":
            # a fin: broad foot, straight taper, flicked at the top
            return cosine_curve([(0.0, w0), (0.12, 0.95 * w0), (1.0, 0.45 * w0), (2.0, 0.04 * w0)], x)
        return cosine_curve([(0.0, w0), (0.12, 1.02 * w0), (0.5, 0.82 * w0), (1.0, 0.59 * w0), (1.5, 0.39 * w0), (2.0, 0.1 * w0)], x)

    def width(self, s: float) -> float:
        return self.width_x(self.x_of(s))

    def thickness_x(self, x: float) -> float:
        """The thin axis: radial at the root, the scroll's visible stroke at the top -- tapering to a hair."""
        t0, kind = self.spec["T"] * STUD, self.kind
        if kind == "middle":
            return cosine_curve([(0.0, t0), (0.6, 0.86 * t0), (1.0, 0.72 * t0), (1.3, 0.58 * t0), (1.6, 0.36 * t0), (1.85, 0.12 * t0), (2.0, 0.0)], x)
        if kind == "tooth":
            return cosine_curve([(0.0, t0), (1.0, 0.68 * t0), (2.0, 0.3 * t0)], x)
        return cosine_curve([(0.0, t0), (0.5, 0.97 * t0), (1.0, 0.95 * t0), (1.25, 0.82 * t0), (1.5, 0.62 * t0), (1.75, 0.34 * t0), (1.92, 0.12 * t0), (2.0, 0.0)], x)

    def thickness(self, s: float) -> float:
        return self.thickness_x(self.x_of(s))

    def hull(self, s: float) -> float:
        w0, w1, w2, w3 = self.cfg["hull"]
        return min(HULL_MAX, max(HULL_MIN, cosine_curve([(0.0, w0), (1.0, w1), (1.66, w2), (2.0, w3)], self.x_of(s))))

    def twist(self, s: float) -> float:
        if self.kind == "tooth":
            return 0.0  # a fin broad along the rim from the page up
        return 0.5 * math.pi * smoothstep(0.03, self.cfg["twist"] * self.s_c, s)

    def frame(self, s: float):
        e = 2e-3
        c = self.line.at(s)
        tau = norm(sub(self.line.at(min(1.0, s + e)), self.line.at(max(0.0, s - e))))
        psi = self.twist(s)
        # the thin axis: radial at the root (the blade broad across the band, facing the crown's middle), in
        # the scroll's plane after the quarter turn (the scroll broad in depth, its thin edge drawing the C)
        n0 = norm(sub(self.R, mul(tau, dot(self.R, tau))))
        n1 = norm(cross(tau, self.Np))
        n = norm(add(mul(n0, math.cos(psi)), mul(n1, math.sin(psi))))
        w = norm(cross(n, tau))
        return c, tau, w, n

    def corners(self, s: float, grow=(1.0, 1.0), floor: float | None = None):
        c, tau, w, n = self.frame(s)
        W, T = self.width(s) * grow[0], self.thickness(s) * grow[1]
        local = [(W / 2.0, 0.0), (-RIDGE * W / 2.0, T / 2.0), (-W / 2.0, 0.0), (RIDGE * W / 2.0, -T / 2.0)]
        pts = [add(c, add(mul(w, x), mul(n, y))) for x, y in local]
        if floor is not None:
            pts = [(p[0], floor, p[2]) for p in pts]
        else:
            pts = [(p[0], max(p[1], F), p[2]) for p in pts]
        return pts, c, tau

    def build(self) -> Volume:
        vol = Volume()
        rings, centres, taus = [], [], []
        for i, s in enumerate(self.stations):
            grow = FOOT if i == 0 else LIP if i == 1 else (1.0, 1.0)
            pts, c, tau = self.corners(s, grow, floor=(F if i == 0 else None))
            weight = self.hull(s)
            rings.append([vol.vert(p, weight) for p in pts])
            centres.append(c)
            taus.append(tau)
        self.rings_pos = [[vol.mesh.verts[v] for v in ring] for ring in rings]
        self.taus = taus
        self.centres = centres
        tip = vol.vert(self.line.at(1.0), HULL_MIN)
        m = vol.mesh
        for r in range(len(rings) - 1):
            a, b = rings[r], rings[r + 1]
            for j in range(4):
                k = (j + 1) % 4
                emit(m, a[j], a[k], b[k])
                emit(m, a[j], b[k], b[j])
        last = rings[-1]
        for j in range(4):
            emit(m, last[j], last[(j + 1) % 4], tip)
        root = rings[0]
        emit(m, root[0], root[2], root[1])
        emit(m, root[0], root[3], root[2])
        if vol.signed_volume() < 0:
            raise AssertionError(f"blade {self.spec['beta']} wound inward")
        return vol

    # --- bands cut on a facet, along the pigment's own triangles (the fireball's streak) ----------
    def facet_normal(self, i: int, j: int, k: int, outward_hint):
        a, b = self.rings_pos[i][j], self.rings_pos[i][k]
        n = norm(cross(sub(b, a), self.taus[i]))
        if dot(n, outward_hint) < 0:
            n = mul(n, -1.0)
        return n

    def on_facet(self, q_rows, facet, u: float, v: float):
        (i0, i1), (j, k) = q_rows, facet
        a0, b0 = self.rings_pos[i0][j], self.rings_pos[i0][k]
        a1, b1 = self.rings_pos[i1][j], self.rings_pos[i1][k]
        if u >= v:
            return add(a0, add(mul(sub(b0, a0), u), mul(sub(b1, b0), v)))
        return add(a0, add(mul(sub(b1, a1), u), mul(sub(a1, a0), v)))

    def cut(self, mesh: Mesh, facet, rows: list[int], band, lift: float) -> None:
        j, k = facet
        normals = [self.facet_normal(i, j, k, sub(lerp(self.rings_pos[i][j], self.rings_pos[i][k], 0.5), self.centres[i])) for i in rows]
        for q in range(len(rows) - 1):
            pair = (rows[q], rows[q + 1])
            (s0, s1), (t0, t1) = band(q), band(q + 1)
            if t1 - t0 < 1e-6 and s1 - s0 < 1e-6:
                continue
            if t1 - t0 < 1e-6:
                poly = [(s0, 0.0), (s1, 0.0), (0.5 * (t0 + t1), 1.0)]
            elif s1 - s0 < 1e-6:
                poly = [(0.5 * (s0 + s1), 0.0), (t1, 1.0), (t0, 1.0)]
            else:
                poly = [(s0, 0.0), (s1, 0.0), (t1, 1.0), (t0, 1.0)]
            for keep in (lambda u, v: u - v, lambda u, v: v - u):
                piece = clip(poly, keep)
                if len(piece) < 3:
                    continue
                pts = []
                for u, v in piece:
                    n = norm(lerp(normals[q], normals[q + 1], v))
                    pts.append(add(self.on_facet(pair, facet, u, v), mul(n, lift)))
                facing = add(normals[q], normals[q + 1])
                for mm in range(1, len(pts) - 1):
                    if altitude_ok(pts[0], pts[mm], pts[mm + 1]):
                        a, b, c = mesh.vert(pts[0]), mesh.vert(pts[mm]), mesh.vert(pts[mm + 1])
                        mesh.tri(a, b, c, facing)

    def flow_line(self, ink: Mesh, facet, rows: list[int], centre: float, drift: float, width: float, seed: int) -> None:
        count = len(rows)
        j, k = facet
        widths = [math.dist(self.rings_pos[i][j], self.rings_pos[i][k]) for i in rows]

        def band(q: int):
            t = q / (count - 1)
            w = max(pressure(min(max(t, 0.02), 0.98), width, 0.22, 0.85, seed), 0.0) * math.sin(math.pi * t) ** 0.6
            half = min(0.36, 0.5 * w / max(widths[q], 1e-6))
            c = centre + drift * t
            return c - half, c + half

        self.cut(ink, facet, rows, band, LINE_LIFT)

    def liseré(self, core: Mesh, rows: list[int], lo: float, hi: float) -> None:
        """The pale liseré (ref-2's blade detail: one pale edge riding the twist): a stripe in the middle of the
        narrow facet (1, 2), ringed by pigment, closing at both ends."""
        count = len(rows)

        def band(q: int):
            t = q / (count - 1)
            f = math.sin(math.pi * t) ** 0.7
            mid = 0.5 * (lo + hi)
            half = 0.5 * (hi - lo) * f
            return mid - half, mid + half

        self.cut(core, (1, 2), rows, band, LINE_LIFT)

    def mouth(self, ink: Mesh, facet, rows: list[int], centre: float, width: float) -> None:
        """The dark crack mouth at the root: a wedge widest at the lip, closing to a point up the blade."""
        count = len(rows)
        j, k = facet
        widths = [math.dist(self.rings_pos[i][j], self.rings_pos[i][k]) for i in rows]

        def band(q: int):
            t = q / (count - 1)
            half = min(0.4, 0.5 * width * (1.0 - t) / max(widths[q], 1e-6))
            return centre - half, centre + half

        self.cut(ink, facet, rows, band, LINE_LIFT)

    # --- the pale eye ----------------------------------------------------------------------------
    def eye(self, core: Mesh) -> list:
        """A flat pale plate in the scroll's plane filling its loop: sampled along the loop's own inner edge only
        (run EYE_IN under the stroke, so no edge of it shows), from just past the stalk round to where the coil
        comes back under it -- never across the open air between the loop and the stalk. The curled tip lies
        over it, so what shows is a pale crescent round the tip, ringed by pigment."""
        pts = []
        for theta in EYE_ANGLES:
            s = self.s_of(1.0 + theta / self.spec["sweep"])
            c, tau, w, n = self.frame(s)
            side = 1.0 if dot(n, sub(self.curl_centre, c)) > 0 else -1.0
            off = self.thickness(s) * (0.5 - EYE_IN)
            pts.append(add(c, mul(n, side * off)))
        # flatten into the scroll's plane
        pts = [sub(p, mul(self.Np, dot(sub(p, self.curl_centre), self.Np))) for p in pts]
        for facing in (self.Np, mul(self.Np, -1.0)):
            ids = [core.vert(p) for p in pts]
            for i in range(1, len(ids) - 1):
                core.tri(ids[0], ids[i], ids[i + 1], facing)
        return pts

    def root_extent(self, direction) -> float:
        """How far the lip reaches from the root centre along a floor direction."""
        pts = self.rings_pos[1]
        c = self.centres[1]
        return max(dot(sub((p[0], 0.0, p[2]), (c[0], 0.0, c[2])), direction) for p in pts)


# --- the band ----------------------------------------------------------------------------------------


def band(seed: int):
    """The crown's horseshoe: a chamfered slab on the page, square-cut at both ends, open toward +Z, and closed
    underneath so its hull turns a floor face up all round."""
    rng = Rng(seed)
    vol = Volume()
    m = vol.mesh
    rings = []
    secs = []
    for j in range(B_SEGS + 1):
        f = j / B_SEGS
        beta = math.radians(-B_SPAN + 2 * B_SPAN * f)
        R = radial(beta)
        r = RB + 0.003 * math.sin(3.1 * f * math.pi + 0.7) + 0.0015 * (rng.random() - 0.5)
        hh = BH * (1.0 + 0.06 * math.sin(5.3 * f * math.pi))
        half = 0.5 * BW
        top = half * B_TOP
        ib = add(mul(R, r - half), (0.0, F, 0.0))
        it = add(mul(R, r - top), (0.0, F + hh, 0.0))
        ot = add(mul(R, r + top), (0.0, F + hh, 0.0))
        ob = add(mul(R, r + half), (0.0, F, 0.0))
        ring = [vol.vert(ib, B_HULL[0]), vol.vert(it, B_HULL[1]), vol.vert(ot, B_HULL[1]), vol.vert(ob, B_HULL[0])]
        rings.append(ring)
        secs.append((ib, it, ot, ob, R, beta))
    for j in range(B_SEGS):
        a, b = rings[j], rings[j + 1]
        mid = mul(add(add(m.verts[a[0]], m.verts[a[3]]), add(m.verts[b[0]], m.verts[b[3]])), 0.25)
        mid = (mid[0], F + BH * 0.3, mid[2])
        for q in range(4):
            k = (q + 1) % 4
            quad = [m.verts[a[q]], m.verts[a[k]], m.verts[b[k]], m.verts[b[q]]]
            facing = sub(mul(add(add(quad[0], quad[1]), add(quad[2], quad[3])), 0.25), mid)
            m.tri(a[q], a[k], b[k], facing)
            m.tri(a[q], b[k], b[q], facing)
    for ring, sign in ((rings[0], -1.0), (rings[-1], 1.0)):
        beta = math.radians(-B_SPAN if sign < 0 else B_SPAN)
        facing = mul(tangent(beta), sign)
        m.tri(ring[0], ring[1], ring[2], facing)
        m.tri(ring[0], ring[2], ring[3], facing)
    vol.orient_outward()
    return vol, secs


def strip(mesh: Mesh, secs, a_of, b_of, facing_of, lift: float) -> None:
    """A strip along the band between two section points (a_of, b_of give them per section), lifted off the
    wall along `facing_of`, one quad a segment."""
    left, right, faces = [], [], []
    for sec in secs:
        fa = facing_of(sec)
        left.append(mesh.vert(add(a_of(sec), mul(fa, lift))))
        right.append(mesh.vert(add(b_of(sec), mul(fa, lift))))
        faces.append(fa)
    for i in range(len(secs) - 1):
        fa = add(faces[i], faces[i + 1])
        mesh.tri(left[i], right[i], right[i + 1], fa)
        mesh.tri(left[i], right[i + 1], left[i + 1], fa)


def wall_normal(p_bot, p_top, R, inward: bool):
    up = norm(sub(p_top, p_bot))
    out = mul(R, -1.0 if inward else 1.0)
    return norm(sub(out, mul(up, dot(out, up))))


def band_core(core: Mesh, secs) -> None:
    """The pale liseré along the top, by its inner edge, and the two pale cut ends (the model sheet's), each
    ringed by pigment."""
    lift = 0.0012
    strip(core, secs, lambda s: lerp(s[1], s[2], 0.1), lambda s: lerp(s[1], s[2], 0.17), lambda s: UP, lift)
    for idx, sign in ((0, -1.0), (len(secs) - 1, 1.0)):
        ib, it, ot, ob, R, beta = secs[idx]
        out = mul(tangent(beta), sign)
        cen = mul(add(add(ib, it), add(ot, ob)), 0.25)
        pts = [add(lerp(p, cen, 0.45), mul(out, lift)) for p in (ib, it, ot, ob)]
        ids = [core.vert(p) for p in pts]
        core.tri(ids[0], ids[1], ids[2], out)
        core.tri(ids[0], ids[2], ids[3], out)


def band_ink(ink: Mesh, secs) -> None:
    """The band's contour where the hull cannot draw it from inside the crown: its foot on the page, inside and
    out, and the crease of its inner wall under the top -- drawn on the walls, so the thrower reads a slab."""
    foot = 0.12  # share of the wall
    crease = 0.11
    lift = 0.0012
    strip(ink, secs, lambda s: s[0], lambda s: lerp(s[0], s[1], foot), lambda s: wall_normal(s[0], s[1], s[4], True), lift)
    strip(ink, secs, lambda s: lerp(s[0], s[1], 1.0 - crease), lambda s: s[1], lambda s: wall_normal(s[0], s[1], s[4], True), lift)
    strip(ink, secs, lambda s: s[3], lambda s: lerp(s[3], s[2], foot), lambda s: wall_normal(s[3], s[2], s[4], False), lift)


# --- torn page flaps ---------------------------------------------------------------------------------


def flap(vol: Volume, A, B, out, tip_hi, tip_lo) -> None:
    """A petal of torn page: hinged A-B, torn into two points -- the high one leaning in against the blade,
    the low one splayed to one side; a thin wedge closed by a back point, so it takes a contour."""
    m = vol.mesh
    Q = add(lerp(A, B, 0.5), mul(out, -0.004))
    Q = (Q[0], max(A[1], B[1]) + 0.004, Q[2])
    ids = [vol.vert(p, FLAP_HULL) for p in (A, B, tip_lo, tip_hi, Q)]
    for f in [(0, 1, 2), (0, 2, 3), (0, 3, 4), (3, 2, 4), (2, 1, 4), (1, 0, 4)]:
        emit(m, ids[f[0]], ids[f[1]], ids[f[2]])


def flaps_for(blade: Blade, seed: int) -> list[Volume]:
    """The torn page at a tall root: one flap toward the crown's inside, one toward its outside, each turned a
    little at random; each hinge end stands on whatever is under it (the band's top, its chamfer, the floor)."""
    rng = Rng(seed)
    out = []
    count = FLAPS[blade.kind]
    if count == 0:
        return out
    c = blade.centres[1]
    c0 = (c[0], 0.0, c[2])
    dirs = [math.pi + 0.6 * (rng.random() - 0.5), 0.6 * (rng.random() - 0.5)][:count]
    for ang in dirs:
        d = norm(add(mul(blade.R, math.cos(ang)), mul(blade.C, math.sin(ang))))
        along = (-d[2], 0.0, d[0])
        ext = blade.root_extent(d)
        dist = ext + 0.006 + 0.004 * rng.random()
        hinge = add(c0, mul(d, dist))
        width = 0.03 + 0.01 * rng.random()
        A = add(hinge, mul(along, 0.5 * width))
        B = add(hinge, mul(along, -0.5 * width))
        A = (A[0], band_height_at(A) + 0.0004, A[2])
        B = (B[0], band_height_at(B) + 0.0004, B[2])
        base_y = max(A[1], B[1])
        hi_y = base_y + 0.026 + 0.012 * rng.random()
        s_hi = blade.s_at_height(hi_y)
        cc = blade.line.at(s_hi)
        ext_hi = max(dot(sub((p[0], 0.0, p[2]), (cc[0], 0.0, cc[2])), d) for p in blade.corners(s_hi)[0])
        tip_hi = add(add((cc[0], hi_y, cc[2]), mul(d, ext_hi + 0.0015)), mul(along, 0.18 * width))
        lo_y = base_y + 0.011 + 0.006 * rng.random()
        tip_lo = add(add((c0[0], lo_y, c0[2]), mul(d, ext + 0.45 * (dist - ext))), mul(along, -0.34 * width))
        vol = Volume()
        flap(vol, A, B, d, tip_hi, tip_lo)
        vol.orient_outward()
        out.append(vol)
    return out


# --- root cracks -------------------------------------------------------------------------------------


def root_cracks(ink: Mesh, seed: int) -> None:
    """Flat dark cracks on the page from the band's outer foot out to the rim, jagged, tapering to a hair, a few
    forked: the page split by the crown's roots (ref-1). Their tips are the body's outer ink at r = 0.5."""
    rng = Rng(seed)
    r0 = RB + 0.5 * BW - 0.004
    for beta_deg, reach, fork in CRACKS:
        beta = math.radians(beta_deg)
        r1 = 0.5 * reach
        n = 5
        pts = []
        for i in range(n + 1):
            t = i / n
            r = r0 + (r1 - r0) * t
            jog = (0.011 * (1 if i % 2 else -1) + 0.006 * (rng.random() - 0.5)) * min(1.0, 2.5 * t) if 0 < i < n else 0.0
            b = beta + jog / r + math.radians(2.0) * (t * t) * (1 if beta_deg >= 0 else -1) * (rng.random() - 0.3)
            pts.append((math.sin(b) * r, CRACK_LIFT, -math.cos(b) * r))
        widths = [CRACK_W * (1.0 - i / n) ** 0.85 * (0.85 + 0.3 * rng.random()) for i in range(n + 1)]
        _ribbon(ink, pts, widths)
        if fork is not None:
            i0 = max(1, min(n - 2, int(round(fork * n))))
            p = pts[i0]
            side = 1.0 if rng.random() > 0.5 else -1.0
            main = norm(sub(pts[i0 + 1], pts[i0]))
            turn = math.radians(32.0) * side
            dirn = (main[0] * math.cos(turn) - main[2] * math.sin(turn), 0.0, main[0] * math.sin(turn) + main[2] * math.cos(turn))
            length = 0.3 * (r1 - r0)
            bp = [p]
            for kk in range(1, 4):
                q = add(p, mul(dirn, length * kk / 3))
                q = add(q, mul((-dirn[2], 0.0, dirn[0]), 0.004 * (1 if kk % 2 else -1)))
                bp.append((q[0], CRACK_LIFT, q[2]))
            bw = [widths[i0] * 0.7 * (1.0 - kk / 3) ** 0.85 for kk in range(4)]
            _ribbon(ink, bp, bw)


def _ribbon(ink: Mesh, pts, widths) -> None:
    lefts, rights = [], []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        d = norm(sub(b, a))
        across = (-d[2], 0.0, d[0])
        w = 0.5 * widths[i]
        if w < 1e-6:
            tip = ink.vert(p)
            lefts.append(tip)
            rights.append(tip)
            continue
        lefts.append(ink.vert(add(p, mul(across, w))))
        rights.append(ink.vert(add(p, mul(across, -w))))
    for i in range(len(pts) - 1):
        if lefts[i] != rights[i]:
            ink.tri(lefts[i], rights[i], lefts[i + 1], UP)
        if rights[i + 1] != lefts[i + 1]:
            ink.tri(rights[i], rights[i + 1], lefts[i + 1], UP)


# --- the three meshes --------------------------------------------------------------------------------

_CACHE: dict = {}


def blades() -> list[Blade]:
    out = []
    for kind, specs in (("tall", TALL), ("middle", MEDIUM), ("tooth", TEETH)):
        for spec in specs:
            out.append(Blade(spec, kind, SEED + 101 * len(out)))
    return out


def rows_where(blade: Blade, lo: float, hi: float) -> list[int]:
    """Station rows (not the foot) whose x (0..1 rise, 1..2 scroll) lies in [lo, hi]."""
    return [i for i, s in enumerate(blade.stations) if i > 0 and lo - 1e-6 <= blade.x_of(s) <= hi + 1e-6]


def build():
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    crown = blades()
    solids = []
    bvol, secs = band(SEED + 400)
    solids.append(("band", bvol))
    for blade in crown:
        solids.append((f"{blade.kind} {blade.spec['beta']:+.0f}", blade.build()))
    for q, blade in enumerate(crown):
        for i, vol in enumerate(flaps_for(blade, SEED + 31 * q)):
            solids.append((f"flap {blade.spec['beta']:+.0f}/{i}", vol))
    counts = {}
    for _, vol in solids:
        body.merge(vol.mesh)
        inverted_hull(vol, ink)
    counts["ink hulls"] = len(ink.tris)
    c0 = len(core.tris)
    band_core(core, secs)
    counts["core band"] = len(core.tris) - c0
    i0 = len(ink.tris)
    band_ink(ink, secs)
    counts["ink band lines"] = len(ink.tris) - i0
    c_eye = c_lis = i_flow = i_mouth = 0
    eyes = {}
    for q, blade in enumerate(crown):
        if blade.kind in ("tall", "middle"):
            a = len(core.tris)
            eyes[f"{blade.kind} {blade.spec['beta']:+.0f}"] = blade.eye(core)
            c_eye += len(core.tris) - a
            b = len(ink.tris)
            blade.mouth(ink, (2, 3), rows_where(blade, 0.0, 0.3 if blade.kind == "tall" else 0.5), 0.55, 0.011)
            i_mouth += len(ink.tris) - b
        if blade.kind == "tall":
            a = len(core.tris)
            blade.liseré(core, rows_where(blade, 0.0, 0.92), 0.4, 0.62)
            c_lis += len(core.tris) - a
            b = len(ink.tris)
            blade.flow_line(ink, (2, 3), rows_where(blade, 0.0, 1.0), 0.3, 0.2, 0.0068, SEED + 11 * q)
            blade.flow_line(ink, (0, 1), rows_where(blade, 0.0, 0.95), 0.4, 0.18, 0.0064, SEED + 15 * q)
            i_flow += len(ink.tris) - b
    counts.update({"core eyes": c_eye, "core liserés": c_lis, "ink flow lines": i_flow, "ink root mouths": i_mouth})
    b = len(ink.tris)
    root_cracks(ink, SEED + 500)
    counts["ink root cracks"] = len(ink.tris) - b
    reach = max(math.hypot(x, z) for mesh in (body, core, ink) for x, _, z in mesh.verts)
    factor = 0.5 / reach
    for mesh in (body, core, ink):
        mesh.scale(factor)
    _CACHE.update(meshes=(body, core, ink), factor=factor, crown=crown, solids=solids, counts=counts, eyes=eyes)
    return _CACHE["meshes"]


def meta(seed: int, reference: str = "OuterDiameter") -> dict:
    """Body and Core are drawn in the Ink's unit (1 = 36 studs) but stop short of the rim, so the test that holds
    every OuterDiameter mesh to the blast's edge applies to the Ink alone."""
    return {"Reference": reference, "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def downstroke_body():
    return build()[0], meta(SEED, "CrownDiameter")


def downstroke_core():
    return build()[1], meta(SEED + 1, "CrownDiameter")


def downstroke_ink():
    return build()[2], meta(SEED + 2)
