"""The Wash's tidal wave (Indigo + Indigo): sheets of ink in three meshes drawn together, one per role,
all cut from one construction so they line up exactly -- the pigment volumes, the pale foam and
highlights, and the ink (the contour, the flow lines and the dark of the barrel). The wave is lit flat
like every volume (D-114), so it reads by silhouette, pale shapes and ink alone.

The front sheet is a thick slab lofted along a spine in the side plane (u forward = -z, v up) that
rises off the floor, curls over forward and hangs down into a hook: thick where it flares onto the
floor, thin at the lip. The indigo body itself is the crest. Under the overhang is the barrel, the
hollow the hook curls round, and it is ink: a sheet across it at the wave's middle and one across each
of its open ends, buried in the curl all round, so from the side and from a three-quarter view the
crest is an indigo hook round a dark hollow. Across, the curl's flanks close in on the barrel and
round off over it, so the crest stands highest in the middle; the lip peels, hanging the whole hook in
the middle and stopping on the rise at the shoulders, so the barrel is open at both ends. The back
and the top of the curl are one smooth sheet; over its front the curl rises into five round lobes,
the middle one the widest, standing out between sharp creases down to the lip, whose one edge is
their round lower edges. The pale is only on the lobes' outer faces, a cap on each from over the
crest down to that edge -- the outer rim of the hook seen from the side, a crown of pale-tipped
lobes seen from the front, a row of round caps along the lip seen from above.

Behind it two more sheets are DRAPED, each on the back of the one in front: a layer's face is that
back surface itself, a hair off it, so there is no gap between the sheets to see through, and its own
back is laid on one tidal envelope, the long rising arc from the tail to the crest. Each layer shows
only as a ridge on the slope, ending in a small lip under a pale foam rim. Nothing is a solid core:
sheets over sheets, tendrils over them.

Units: the three meshes together span exactly 1 along X (the runtime draws that 16 studs, the damage
sphere's diameter), centred on x = 0; the pivot (0, 0, 0) is on the floor under the sphere's centre;
nothing is below the floor. The lip hangs over the sphere's leading edge, z = -0.5.
"""

from __future__ import annotations

import math

from strokes import (
    Mesh,
    Polyline,
    Rng,
    Vec,
    Volume,
    add,
    catmull,
    cosine_curve,
    cross,
    dot,
    emit,
    fbm,
    inverted_hull,
    lerp,
    loft,
    mul,
    norm,
    smoothstep,
    sub,
    surface_ribbon,
    tube,
)

WAVE_SEED = 7731
_ENVELOPE = (-0.56, 0.10, 0.55, 2.2)  # tail u, crest u, crest v, how the slope steepens toward the crest

_FRONT = {
    # The spine: up off the floor, over the crest, forward and down into the lip, which tucks back under.
    "pts": [(0.07, 0.0), (0.074, 0.1), (0.086, 0.2), (0.112, 0.3), (0.16, 0.4), (0.228, 0.48), (0.315, 0.53),
            (0.386, 0.53), (0.435, 0.5), (0.455, 0.45), (0.455, 0.409), (0.451, 0.385)],
    # Where the lip ends along the spine: (the middle lobe's end, how much shorter the creases between
    # lobes run, how much shorter the flanks run, and how that grows across). The curl peels: only the
    # middle hangs the whole hook, the shoulders stop on the rise, so the barrel is open at both ends.
    "lip": (1.0, 0.05, 0.2, 2.0),
    # The creases across the lip, from the left: the lobes between them, the middle one the widest and
    # the others smaller down the shoulders, a crown of foam rather than a row of equal teeth.
    "creases": (-1.0, -0.66, -0.26, 0.26, 0.66, 1.0),
    # The lobes are the curl's own shape: each one stands out from the barrel's axis by the first share
    # and between two the curl closes in on it by the second, coming in over these spine fractions -- the
    # back and the top of the curl one smooth sheet, the lobes rising over its front down to the lip, so
    # the crown and the lip's edge are a row of round lobes seen from the front, one hook from the side.
    "lobe": (0.1, 0.16, 0.66, 0.84),
    # Down the hanging lip the lobes stop standing out over these spine fractions and only the creases
    # go on: the lip hangs no further forward than the damage's rim.
    "release": (0.74, 0.9),
    "h": [(0, 0.26), (0.25, 0.15), (0.5, 0.13), (0.66, 0.12), (0.84, 0.065), (1.0, 0.014)],
    "fo": 0.09,  # the flare of the back onto the floor
    "fi": 0.10,  # and of the face
    # (waist, floor, how fast the foot's flare falls off with height, how much wider the crest is).
    "width": (0.27, 0.48, 0.07, 0.07),
    # The curl's flanks: the barrel's axis (u, v), how much the outermost section shrinks toward it,
    # how that grows across, and the spine fractions over which it comes in (none on the trunk, all of
    # it over the crest).
    "barrel": (0.3, 0.41),
    "shrink": 0.12,
    "flank_power": 2.4,
    "flank_in": (0.26, 0.58),
    # Over the barrel's axis the flanks close in across too, up to this share at the crest's top: the
    # crest's shoulders round off, seen from the front and from behind.
    "round": 0.3,
    "sweep": 0.03,
    # Columns over the curl, to a lobe: each one round, every crease a column. The trunk, smooth across,
    # takes only the creases and the middle; the loft stations from `fine` on take the curl's.
    "per_lobe": 4,
    "fine": 0.7,
    "segs": 14,
}

# The foam on the lobes: each lobe's cap is round at the top, over the crest (`top`, a loft station: the
# lip's edge is station 1 in every column), and runs down its face to `bottom`, a hair short of the
# lip's edge, so its lower end follows the lobe's round edge; `share` of the lobe's own width. One per
# lobe, from the left, those on the shoulders starting lower; its corners rounded by these shares of a
# station, at the top and at the bottom; how far off the curl.
_FOAM_CAPS = ((0.79, 0.985, 0.78), (0.77, 0.985, 0.8), (0.76, 0.985, 0.8), (0.77, 0.985, 0.8), (0.79, 0.985, 0.78))
_FOAM_ROUND = (0.04, 0.02)
_FOAM_LIFT = 0.005

_CAP_X = 0.2  # how far out to each side the two sheets closing the barrel's ends stand
_CAP_FROM = 0.33  # where on the face, along the loft's stations, the barrel's hollow begins
_CAP_BURY = 0.008  # how deep in the curl their edges lie: past the sag of the loft's facets
_SHADE = (0.6, 0.84, 0.5)  # the overhang's underside in ink: from, to (spine fractions), how far across
_SHADE_LIFT = 0.007  # how far off the barrel's face that ink lies, past the same sag

_LAYER_PEEL = 0.7  # the layer's s where its face leaves the sheet in front and its lip begins
_LAYER_GAP = 0.005  # how far a layer's face lies off the back it is draped on

# The draped layers, front to back. `peel` and `tip` are the heights on the sheet in front where the lip
# leaves it and where it ends; `arch` how much lower down the slope the lip runs at the flanks, so the
# ridge is an arch; `tw` the share of the sheet in front the layer covers across, at its foot and at its
# lip; `inset` how far inside the envelope its back stays at the floor, below `under`, where the next
# layer covers it.
_LAYERS = [
    {"peel": 0.34, "tip": 0.43, "arch": 0.25, "tw": (0.72, 0.56), "inset": 0.19, "under": 0.15,
     "lip_lift": 0.026, "lip_th": 0.04, "cols": 7, "stations": [0.0, 0.1, 0.24, 0.4, 0.56, 0.7, 0.8, 0.9, 1.0]},
    {"peel": 0.18, "tip": 0.25, "arch": 0.2, "tw": (0.72, 0.56), "inset": 0.0, "under": 0.0,
     "lip_lift": 0.022, "lip_th": 0.034, "cols": 7, "stations": [0.0, 0.12, 0.28, 0.46, 0.62, 0.74, 0.87, 1.0]},
]


def _envelope(v: float) -> float:
    """Where the back slope stands (u, forward) at height v: low and long at the tail, steepening into
    the crest, as the reference's side view draws it."""
    tail, crest, top, power = _ENVELOPE
    return tail + (crest - tail) * (max(v, 0.0) / top) ** (1.0 / power)


class _Front:
    """The front sheet: a slab lofted along a spine, its curl's flanks closed in on the barrel."""

    def __init__(self, spec: dict) -> None:
        self.spec = spec
        self.spine = Polyline(catmull(spec["pts"]))
        self.body = spec["lip"][0]
        # Running maximum of the spine's height: the width follows how high the wave has risen, not
        # how far down the lip has curled back.
        self._vmax = []
        top = 0.0
        for i in range(201):
            top = max(top, self.spine.at(i / 200)[1])
            self._vmax.append(top)

    def frame(self, s: float):
        e = 0.003
        a = self.spine.at(max(0.0, s - e))
        b = self.spine.at(min(1.0, s + e))
        tu, tv = b[0] - a[0], b[1] - a[1]
        length = math.hypot(tu, tv) or 1.0
        return self.spine.at(s), (tu / length, tv / length)

    def half_width(self, s: float) -> float:
        waist, floor, decay, crest = self.spec["width"]
        v = self._vmax[min(200, max(0, int(round(s * 200))))]
        return waist + (floor - waist) * math.exp(-v / decay) + crest * smoothstep(0.26, 0.44, v)

    def flank(self, s: float, t: float) -> float:
        """How far the section at (s, t) is scaled toward the barrel's axis."""
        spec = self.spec
        return 1.0 - spec["shrink"] * smoothstep(*spec["flank_in"], s) * abs(t) ** spec["flank_power"]

    def point(self, s: float, t: float, side: int) -> Vec:
        """A point of the outer (side = +1, the back, the top and the lip's front) or inner (side = -1,
        the face and the barrel) surface at spine fraction s and across fraction t in [-1, 1]."""
        spec = self.spec
        (u, v), (tu, tv) = self.frame(s)
        # The outer side is to the left of the spine's direction; near the floor it turns horizontal so
        # the slab stands on y = 0.
        b = smoothstep(0.0, 0.12, s)
        nu, nv = -1.0 + (1.0 - tv) * b, tu * b
        length = math.hypot(nu, nv) or 1.0
        nu, nv = nu / length, nv / length
        lens = 0.35 + 0.65 * (1.0 - t * t)
        wobble = 1.0 + 0.10 * (fbm(3.0 * s + 1.7, 2.0 * t + 3.1, WAVE_SEED) - 0.5)
        h = cosine_curve(spec["h"], s) * lens * wobble
        base = (1.0 - smoothstep(0.0, 0.22, s)) ** 2
        flare = (spec["fo"] if side > 0 else spec["fi"]) * base * (0.25 + 0.75 * (1.0 - t * t))
        off = side * (h / 2.0 + flare)
        pu, pv = u + nu * off, v + nv * off
        # The flanks of the curl close in on the barrel's axis, and over it they close in across too:
        # the crest is highest in the middle and its shoulders round off, while the hollow stays open.
        # Over the curl's front each lobe stands out from that axis and each crease closes in on it.
        k = self.flank(s, t) * self.relief(s, t)
        cu, cv = spec["barrel"]
        pu, pv = cu + k * (pu - cu), cv + k * (pv - cv)
        pu -= spec["sweep"] * t * t * smoothstep(0.05, 0.6, s)
        across = 1.0 - spec["round"] * smoothstep(cv, cv + 0.2, pv) * smoothstep(*spec["flank_in"], s)
        return (t * self.half_width(s) * across, max(pv, 0.0), -pu)

    def normal(self, s: float, t: float, side: int) -> Vec:
        """The outward normal of a surface (finite differences), pointing away from the slab."""
        e = 1e-3
        ds = sub(self.point(min(1.0, s + e), t, side), self.point(max(0.0, s - e), t, side))
        dt = sub(self.point(s, t + e, side), self.point(s, t - e, side))
        n = norm(cross(ds, dt))
        if dot(n, sub(self.point(s, t, side), self.point(s, t, -side))) < 0:
            n = mul(n, -1.0)
        return n

    def back(self, s: float, t: float) -> Vec:
        return self.point(s, t, +1)

    def back_normal(self, s: float, t: float) -> Vec:
        return self.normal(s, t, +1)

    def lobe(self, t: float) -> float:
        """1 on a lobe's middle, 0 in the crease between two (and past the last): round lobes meeting in
        sharp creases."""
        for a, b in zip(self.spec["creases"], self.spec["creases"][1:]):
            if a <= t <= b:
                return max(0.0, math.sin(math.pi * (t - a) / (b - a))) ** 0.5
        return 0.0

    def relief(self, s: float, t: float) -> float:
        """How far the section at (s, t) stands from the barrel's axis for its lobe: out on a lobe over
        the crest, in in a crease down to the lip, nothing on the back of the curl."""
        out, crease, first, last = self.spec["lobe"]
        lobe = self.lobe(t)
        out *= 1.0 - smoothstep(*self.spec["release"], s)
        return 1.0 + (out * lobe - crease * (1.0 - lobe)) * smoothstep(first, last, s)

    def column(self, s: float, t: float) -> float:
        """The spine fraction a loft station s stands at in column t: each column runs to its own lip
        end -- each lobe furthest at its middle, the creases shorter, the flanks shorter still -- the
        stations over the curl stretching toward it, and those of the lobes only over the curl's own
        columns, so the trunk's rings stay level."""
        _, crease, flank, power = self.spec["lip"]
        stretch = -flank * abs(t) ** power * smoothstep(0.3, self.body, s)
        scallop = crease * (1.0 - self.lobe(t))
        return s + stretch - scallop * smoothstep(self.spec["fine"], self.body, s)

    def columns(self, s: float) -> list[float]:
        """The columns across at loft station s: the trunk's, or the curl's, which hold the trunk's."""
        creases = self.spec["creases"]
        if s < self.spec["fine"]:
            return sorted(set(creases) | {0.0})
        per_lobe = self.spec["per_lobe"]
        out = [a + (b - a) * k / per_lobe for a, b in zip(creases, creases[1:]) for k in range(per_lobe)]
        return out + [creases[-1]]

    def stations(self) -> list[float]:
        """Spine fractions from the floor to the lip, denser where the sheet turns: round the curl, and
        in the fillets of the foot, where the face and the back flare onto the floor -- a facet that
        bridges a fillet would stand over the strokes lying in it."""
        end, count, fine = self.body, self.spec["segs"], 400

        def direction(i: int, side: int) -> tuple[float, float]:
            a = self.point(end * max(i - 1, 0) / fine, 0.0, side)
            b = self.point(end * min(i + 1, fine) / fine, 0.0, side)
            du, dv = a[2] - b[2], b[1] - a[1]
            length = math.hypot(du, dv) or 1.0
            return du / length, dv / length

        cost = [0.0]
        prev = [direction(0, side) for side in (+1, -1)]
        for i in range(1, fine + 1):
            cur = [direction(i, side) for side in (+1, -1)]
            turn = max(math.acos(max(-1.0, min(1.0, p[0] * c[0] + p[1] * c[1]))) for p, c in zip(prev, cur))
            cost.append(cost[-1] + end / fine + 0.18 * turn)
            prev = cur
        out = []
        for k in range(count + 1):
            target = cost[-1] * k / count
            j = 1
            while j < fine and cost[j] < target:
                j += 1
            f = (target - cost[j - 1]) / max(cost[j] - cost[j - 1], 1e-12)
            out.append(end * (j - 1 + min(max(f, 0.0), 1.0)) / fine)
        out[0], out[-1] = 0.0, end
        return out


class _Layer:
    """A sheet draped on the back of the sheet in front: its face is that back surface (_LAYER_GAP off
    it) from the floor up to `peel`, then lifts off it into a lip that curls up the slope to `tip`; its
    own back is laid on the tidal envelope. Across, it thins to a lens at its flanks, where it tapers
    into the sheet under it."""

    def __init__(self, spec: dict, front) -> None:
        self.spec = spec
        self.front = front
        self._cache: dict = {}
        heights = [(front.back(i / 300, 0.0)[1], i / 300) for i in range(301)]
        self.sf_peel = next(s for v, s in heights if v >= spec["peel"])
        self.sf_tip = next(s for v, s in heights if v >= spec["tip"])
        self._th = [self._solve(i / 100) for i in range(101)]

    @staticmethod
    def lens(t: float) -> float:
        return 0.3 + 0.7 * (1.0 - t * t) ** 0.8

    def _on_front(self, s: float, t: float):
        key = ("f", s, t)
        if key not in self._cache:
            if s <= _LAYER_PEEL:
                sf = self.sf_peel * s / _LAYER_PEEL
            else:
                sf = self.sf_peel + (self.sf_tip - self.sf_peel) * (s - _LAYER_PEEL) / (1.0 - _LAYER_PEEL)
            a, b = self.spec["tw"]
            # The lip is an arch: at the flanks it runs lower down the slope than in the middle.
            sf, tf = sf * (1.0 - self.spec["arch"] * t * t), t * (a + (b - a) * smoothstep(0.0, 1.0, s))
            self._cache[key] = (self.front.back(sf, tf), self.front.back_normal(sf, tf))
        return self._cache[key]

    def face(self, s: float, t: float) -> Vec:
        p, n = self._on_front(s, t)
        bump = smoothstep(_LAYER_PEEL - 0.08, 0.9, s) - 0.6 * smoothstep(0.9, 1.0, s)
        q = add(p, mul(n, _LAYER_GAP + self.spec["lip_lift"] * bump * self.lens(t)))
        return (q[0], 0.0 if s <= 0.0 else max(q[1], 0.0), q[2])

    def direction(self, s: float, t: float) -> Vec:
        """Which way the back stands off the face: back along the floor at the foot, combed toward the
        tail at the flanks too (so the foot's outline is one round tongue, not a polygon pushed out
        sideways at every column), along the normal higher up."""
        _, n = self._on_front(s, t)
        flat = norm(lerp(norm((n[0], 0.0, n[2])), (0.0, 0.0, 1.0), 0.5))
        return norm(lerp(flat, n, smoothstep(0.05, 0.6, s)))

    def _solve(self, s: float) -> float:
        """The thickness at t = 0 that puts the back on the envelope (less the inset), by bisection."""
        f, d = self.face(s, 0.0), self.direction(s, 0.0)
        inset, under = self.spec["inset"], self.spec["under"]

        def g(th: float) -> float:
            v = f[1] + d[1] * th
            target = _envelope(v) + (inset * (1.0 - smoothstep(0.0, under, v)) if inset else 0.0)
            return -f[2] - d[2] * th - target

        if g(0.0) <= 0.0:
            return 0.0
        lo, hi = 0.0, 0.8
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            if g(mid) > 0.0:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    def thickness(self, s: float) -> float:
        if s <= _LAYER_PEEL:
            i = s * 100
            j = min(int(i), 99)
            th = self._th[j] + (self._th[j + 1] - self._th[j]) * (i - j)
            return max(th, self.spec["lip_th"] * (0.6 + 0.4 * smoothstep(0.3, _LAYER_PEEL, s)))
        # Over the lip it thins to the knife edge of the tip.
        peel = max(self._th[round(_LAYER_PEEL * 100)], self.spec["lip_th"])
        return peel * (1.0 - ((s - _LAYER_PEEL) / (1.0 - _LAYER_PEEL)) ** 1.6)

    def back(self, s: float, t: float) -> Vec:
        key = ("b", s, t)
        if key not in self._cache:
            q = add(self.face(s, t), mul(self.direction(s, t), self.thickness(s) * self.lens(t)))
            self._cache[key] = (q[0], 0.0 if s <= 0.0 else max(q[1], 0.0), q[2])
        return self._cache[key]

    def back_normal(self, s: float, t: float) -> Vec:
        key = ("n", s, t)
        if key not in self._cache:
            e = 1e-3
            ds = sub(self.back(min(1.0, s + e), t), self.back(max(0.0, s - e), t))
            dt = sub(self.back(s, min(1.0, t + e)), self.back(s, max(-1.0, t - e)))
            n = norm(cross(ds, dt))
            if dot(n, sub(self.back(s, t), self.face(s, t))) < 0:
                n = mul(n, -1.0)
            self._cache[key] = n
        return self._cache[key]


def _surface(sheet, side: int = +1):
    """(point(s, t), normal(s, t)) of a sheet's back (side +1) or, for the front sheet, its face (-1)."""
    if isinstance(sheet, _Front):
        return (lambda s, t: sheet.point(s, t, side)), (lambda s, t: sheet.normal(s, t, side))
    return sheet.back, sheet.back_normal


def _contour_caps(front: _Front, s: float) -> tuple[float, float]:
    """How far the contour may be pushed at spine fraction s on the outer and on the inner side: under
    half the local radius of whichever side is concave (inside the curl, or in the fillet of the foot),
    or the hull would fold on itself there. From the spine's own curvature, scaled by how far the
    flanks close in on the barrel."""
    e = 0.02
    (_, t0), (_, t1) = front.frame(max(0.0, s - e)), front.frame(min(1.0, s + e))
    turn = math.asin(max(-1.0, min(1.0, t0[0] * t1[1] - t0[1] * t1[0])))
    if abs(turn) < 1e-6:
        return 1.0, 1.0
    arc = (min(1.0, s + e) - max(0.0, s - e)) * front.spine.acc[-1]
    radius = arc / abs(turn) * (1.0 - front.spec["shrink"])
    tight = max(0.004, 0.45 * (radius - cosine_curve(front.spec["h"], s) / 2.0))
    # A left turn bends the outer side in; a right turn (the curl) bends the inner side in.
    return (tight, 1.0) if turn > 0 else (1.0, tight)


def _zip(vol: Volume, a: list[tuple[int, float]], b: list[tuple[int, float]]) -> None:
    """The band between two rings round the slab, of any sizes: each a list of (vertex, where it stands
    round the ring, from 0 up), both starting on the outer side's left edge. Every step advances the
    ring whose next edge comes first (by its middle), so every vertex of both is a corner (no T-junction,
    no hole), a vertex of the coarser ring fans to the finer one's on both its sides, and two rings of
    one size are joined in the quads of `loft`, split along the same diagonal."""
    i = j = 0
    na, nb = len(a), len(b)

    def middle(ring, k, n):
        here = ring[k][1] if k < n else 1.0
        return 0.5 * (here + (ring[k + 1][1] if k + 1 < n else 1.0))

    while i < na or j < nb:
        if j >= nb or (i < na and middle(a, i, na) < middle(b, j, nb)):
            emit(vol.mesh, a[i][0], a[(i + 1) % na][0], b[j % nb][0])
            i += 1
        else:
            emit(vol.mesh, a[i % na][0], b[(j + 1) % nb][0], b[j][0])
            j += 1


def _front_volume(front: _Front) -> Volume:
    stations = front.stations()
    caps = [_contour_caps(front, s) for s in stations]
    # Each station takes the tightest cap of itself and its neighbours: pushes that jump from one ring
    # to the next would pull the thin quads of the lip into slivers.
    caps = [
        tuple(min(caps[j][side] for j in range(max(0, i - 1), min(len(caps), i + 2))) for side in (0, 1))
        for i in range(len(caps))
    ]
    vol = Volume()
    rings = []
    for index, s in enumerate(stations):
        # Heavier at the foot, lighter into the lip: the brush lifts as the stroke curls.
        weight = 0.013 + 0.007 * (1.0 - s / front.body)
        # Each column runs to its own lip end: the stations near the lip stretch toward it.
        ts = front.columns(s)
        columns = [(front.column(s, t), t) for t in ts]
        # Where each vertex stands round the ring: the outer side left to right, then the inner side
        # back, each a hair short of half the ring so the flanks' edges are steps of their own.
        where = [0.49 * (t + 1.0) / 2.0 for t in ts] + [0.5 + 0.49 * (1.0 - t) / 2.0 for t in reversed(ts)]
        if index == len(stations) - 1:
            # The lip ends in a knife edge on the spine.
            edge = [mul(add(front.point(cs, t, +1), front.point(cs, t, -1)), 0.5) for cs, t in columns]
            edge = [vol.vert(p, weight) for p in edge]
            rings.append(list(zip(edge + list(reversed(edge)), where)))
            continue
        outer, inner = min(weight, caps[index][0]), min(weight, caps[index][1])
        ring = [vol.vert(front.point(cs, t, +1), outer) for cs, t in columns]
        ring += [vol.vert(front.point(cs, t, -1), inner) for cs, t in reversed(columns)]
        rings.append(list(zip(ring, where)))
    for a, b in zip(rings, rings[1:]):
        _zip(vol, a, b)
    # The foot, on the floor: a strip across from the outer side to the inner.
    foot = [v for v, _ in rings[0]]
    m = len(foot)
    for j in range(m // 2 - 1):
        emit(vol.mesh, foot[j + 1], foot[j], foot[m - 1 - j])
        emit(vol.mesh, foot[j + 1], foot[m - 1 - j], foot[m - 2 - j])
    vol.orient_outward()
    return vol


def _layer_volume(layer: _Layer) -> Volume:
    cols = layer.spec["cols"]
    ts = [-1.0 + 2.0 * j / (cols - 1) for j in range(cols)]
    stations = layer.spec["stations"]
    vol = Volume()
    rings = []
    for index, s in enumerate(stations):
        weight = 0.013 + 0.006 * (1.0 - s)
        if index == len(stations) - 1:
            edge = [vol.vert(mul(add(layer.back(s, t), layer.face(s, t)), 0.5), weight) for t in ts]
            rings.append(edge + list(reversed(edge)))
            continue
        # The face's contour is buried in the sheet in front; the same weight on both sides keeps the
        # hull's floor ring and its knife edges from shearing into slivers.
        ring = [vol.vert(layer.back(s, t), weight) for t in ts]
        ring += [vol.vert(layer.face(s, t), weight) for t in reversed(ts)]
        rings.append(ring)
    loft(vol, rings, cols, tip_cap=False)
    vol.orient_outward()
    return vol


def _on_crest(crest: Mesh, front: _Front, s: float, t: float, lift: float) -> tuple[int, Vec]:
    """A vertex on the curl's outer face at spine fraction s and across fraction t, lifted, and the
    face's normal there."""
    n = front.normal(s, t, +1)
    return crest.vert(add(front.point(s, t, +1), mul(n, lift))), n


def _quads(mesh: Mesh, grid: list[list[tuple[int, Vec]]]) -> None:
    """Two triangles a cell of a grid of (vertex, the normal of the surface it lies on), each facing
    out of that surface."""
    for i in range(len(grid) - 1):
        for j in range(len(grid[i]) - 1):
            (a, n), (b, _), (c, _), (d, _) = grid[i][j], grid[i][j + 1], grid[i + 1][j], grid[i + 1][j + 1]
            mesh.tri(a, b, c, n)
            mesh.tri(b, d, c, n)


def _foam_caps(crest: Mesh, front: _Front) -> None:
    """The foam on the crest: on every lobe a pale cap, round over the top of the lobe and running down
    its face to its round edge -- the light blue of the reference's crest, a crown of pale-tipped lobes
    seen from the front and a row of round caps along the lip from above, only where the curl faces out,
    so from the side it is the outer rim of the hook. Each is its own, the indigo of the creases between
    them: no band joins them."""
    rise, fall = _FOAM_ROUND
    across = [math.sin(0.5 * math.pi * k / 3) for k in range(-3, 4)]
    down = (0.0, 0.15, 0.32, 0.5, 0.68, 0.85, 1.0)
    creases = front.spec["creases"]
    for (a, b), (top, bottom, share) in zip(zip(creases, creases[1:]), _FOAM_CAPS):
        centre, half = (a + b) / 2.0, share * (b - a) / 2.0
        grid = []
        for f in down:
            row = []
            for k in across:
                bend = 1.0 - math.sqrt(max(0.0, 1.0 - k * k))
                first, last = top + rise * bend, bottom - fall * bend
                t = centre + half * k
                row.append(_on_crest(crest, front, front.column(first + (last - first) * f, t), t, _FOAM_LIFT))
            grid.append(row)
        _quads(crest, grid)


def _foam_rim(mesh: Mesh, layer: _Layer, lift: float, seed: int) -> None:
    """The pale rim along a layer's lip: a band across it, from under the tip down the curl, its lower
    edge scalloped -- foam on a ridge, not a row of teeth."""
    rng = Rng(seed)
    count, reach = 11, 0.8
    lobes = 3.0 + rng.random()
    phase = rng.uniform(0.0, 6.28)
    rows = []
    for i in range(count):
        t = -reach + 2.0 * reach * i / (count - 1)
        scallop = 0.5 + 0.5 * math.cos(lobes * math.pi * t + phase)
        lo = 0.955 - (0.07 + 0.06 * scallop) * (0.35 + 0.65 * (1.0 - (abs(t) / reach) ** 3))
        row = []
        for s in (lo, 0.5 * (lo + 0.985), 0.985):
            n = layer.back_normal(s, t)
            row.append((mesh.vert(add(layer.back(s, t), mul(n, lift))), n))
        rows.append(row)
    _quads(mesh, rows)


def _cap_rim(front: _Front, x0: float) -> list[Vec]:
    """Where the plane x = x0 cuts the barrel's face, from the face below the hollow round the hook to
    the lip's edge, a hair inside the curl: the edge of a flat sheet across the barrel."""
    rim = []
    count = 12
    for i in range(count + 1):
        station = _CAP_FROM + (front.body - _CAP_FROM) * i / count
        side = -1 if i < count else 0

        def at(t: float, station=station, side=side) -> Vec:
            s = front.column(station, t)
            if side == 0:
                return mul(add(front.point(s, t, +1), front.point(s, t, -1)), 0.5)
            return front.point(s, t, -1)

        # The column whose face stands at x0, by bisection (the curl's own end where it never does).
        lo, hi = 0.0, math.copysign(1.0, x0)
        if x0 == 0.0 or abs(at(hi)[0]) <= abs(x0):
            lo = hi
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            if abs(at(mid)[0]) < abs(x0):
                lo = mid
            else:
                hi = mid
        t = 0.5 * (lo + hi)
        p = at(t)
        n = front.normal(front.column(station, t), t, -1)
        inward = norm((0.0, n[1], n[2]))
        rim.append((x0, p[1] - _CAP_BURY * inward[1], p[2] - _CAP_BURY * inward[2]))
    return rim


def _barrel(ink: Mesh, front: _Front) -> None:
    """The hollow under the overhang, in ink: flat sheets across the barrel whose edges are buried in
    the curl all round the hook and close across the mouth under the lip -- one at the wave's middle,
    seen from both sides, and one across each open end, facing out of it, its mouth bowed down. From
    the side, or from a three-quarter view into an end, the crest is an indigo hook round a dark
    hollow; from the front every one is edge on, behind the lip. And the underside of the overhang,
    behind the hanging middle of the lip, where only a look up into the barrel finds it."""
    cu, cv = front.spec["barrel"]
    for x0, bow in ((0.0, 0.02), (-_CAP_X, -0.05), (_CAP_X, -0.05)):
        rim = _cap_rim(front, x0)
        # Across the mouth, from the lip's end back to the face, bowed.
        a, b = rim[-1], rim[0]
        for i in range(1, 5):
            q = lerp(a, b, i / 5)
            rim.append((x0, q[1] + bow * math.sin(math.pi * i / 5), q[2]))
        sheet = Mesh("up")
        centre = sheet.vert((x0, cv, -cu))
        ring = [sheet.vert(p) for p in rim]
        for i in range(len(ring)):
            sheet.tri(centre, ring[i], ring[(i + 1) % len(ring)], (1.0 if x0 >= 0.0 else -1.0, 0.0, 0.0))
        if x0 == 0.0:
            # The middle one is seen from both sides.
            sheet.double_sided()
        ink.merge(sheet)
    first, last, across = _SHADE
    rows, cols = 3, 3
    grid = []
    for i in range(rows + 1):
        s = first + (last - first) * i / rows
        row = []
        for j in range(cols + 1):
            t = -across + 2.0 * across * j / cols
            n = front.normal(s, t, -1)
            row.append((ink.vert(add(front.point(s, t, -1), mul(n, _SHADE_LIFT))), n))
        grid.append(row)
    _quads(ink, grid)


def _along(surface, path, radius: float, count: int, sink: float) -> list[Vec]:
    """`count` points of `path(tau) -> (s, t)` on a surface, lifted by `radius` less `sink`: the spine of
    a tendril lying along it, partly sunk into it."""
    point, normal = surface
    out = []
    for i in range(count):
        s, t = path(i / (count - 1))
        out.append(add(point(s, t), mul(normal(s, t), radius - sink)))
    return out


def _tendrils(front: _Front, layers: list[_Layer]) -> list[Volume]:
    tail = _surface(layers[-1])
    out = []
    # Trailing whips: out of the tail's back slope near the floor and off it, trailing straight back a
    # little over the floor toward the thrower, converging like a wake and wavering only gently. Partly
    # attached, never splayed nor hooked: from behind they are the wave's wake, not legs.
    # (across the tail, x at the end, z at the end, radius, waver, its phase)
    whips = ((-0.5, -0.07, 0.86, 0.02, 0.014, 0.0), (0.02, 0.01, 0.97, 0.024, -0.018, 1.2),
             (0.52, 0.08, 0.8, 0.019, 0.012, 2.1))
    for t0, x_end, length, radius, amp, phase in whips:
        roots = _along(tail, lambda tau, t0=t0: (0.26 - 0.2 * tau, t0), radius, 3, 0.006)
        x0, y0, z0 = roots[-1]
        points = list(roots)
        for f in (0.2, 0.42, 0.64, 0.84, 1.0):
            x = x0 + (x_end - x0) * f + amp * math.sin(2.4 * math.pi * f + phase) * f
            points.append((x, 0.02 + (y0 - 0.02) * (1.0 - f) ** 2, z0 + (length - z0) * f))
        out.append(tube(points, radius, 8, 0.55))
    # The flank scrolls: a stream out of the tail's flank runs forward along the foot, rises outside the
    # flank and rolls over inward into a curl -- the side curls of the reference's front view, fed by
    # the flow behind them, so from behind they are a stream running round the side and never a pair of
    # ears. Not a pair either: the left one larger and higher than the right.
    for side, rise, reach in ((-1.0, 0.64, 1.0), (1.0, 0.54, 0.96)):
        scroll = [(0.25, 0.03, 0.3), (0.37, 0.04, 0.16), (0.445, 0.05, 0.04), (0.47, 0.1, -0.035),
                  (0.462, 0.15, -0.06), (0.435, 0.19, -0.07), (0.398, 0.185, -0.07), (0.384, 0.152, -0.07),
                  (0.402, 0.132, -0.07), (0.42, 0.148, -0.07)]
        scroll = [(side * (x if i < 2 else 0.37 + (x - 0.37) * reach), 0.03 + (y - 0.03) * (1.0 if i < 2 else rise), z)
                  for i, (x, y, z) in enumerate(scroll)]
        out.append(tube(scroll, 0.026 if side < 0 else 0.022, 13))
    # Wrap tendrils: one across the face from the left foot up toward the barrel, one across the tail's
    # back from its right flank up toward its lip -- the swirl of the reference, thinner than a sheet.
    face = _surface(front, -1)
    across_face = _along(face, lambda tau: (0.04 + 0.26 * tau, -0.92 + 1.25 * tau - 0.2 * tau * tau), 0.011, 7, 0.003)
    across_tail = _along(tail, lambda tau: (0.06 + 0.8 * tau, 0.9 - 1.35 * tau), 0.01, 7, 0.003)
    out.append(tube(across_face, 0.013, 7, weight=0.004))
    out.append(tube(across_tail, 0.012, 7, weight=0.004))
    return out


def _flow_lines(ink: Mesh, front: _Front, layers: list[_Layer]) -> None:
    """The calligraphic flow lines: on the front sheet's back, up to the crest, each in line with a
    crease between two lobes, the middle two the highest; on its face, from the toe up to the barrel;
    across the layers' backs, sweeping diagonally with the swirl and stopping short of the foam rims.
    Every one rides over any pale stroke it could cross, and under the contour, so it never pokes out of
    the silhouette."""
    rng = Rng(WAVE_SEED + 2)
    creases = front.spec["creases"][1:-1]
    _, _, first, last = front.spec["lobe"]
    for g in creases:
        # Up the back to the crest, each in line with a crease, the middle two the furthest.
        lo = layers[0].sf_tip + 0.02
        hi = (0.72 if abs(g) < 0.5 else 0.68) - 0.03 * rng.random()
        bend = rng.uniform(-0.06, 0.06)

        def groove(tau, g=g, lo=lo, hi=hi, bend=bend):
            # Free on the slope, and in its crease where the lobes come in.
            s = lo + (hi - lo) * tau
            return s, g + bend * math.sin(math.pi * tau) * (1.0 - smoothstep(first, last, s))

        surface_ribbon(ink, _surface(front), groove, 0.018, 0.011, 8, WAVE_SEED + 3)
    # (across at the toe, how far it sweeps across, where it starts: the left one above the wrap that
    # crosses the face low, so the two never lie together)
    for t0, sweep, lo in ((-0.7, 0.2, 0.12), (-0.25, 0.12, 0.04), (0.2, -0.1, 0.04), (0.66, -0.22, 0.04)):
        hi = 0.3 + 0.04 * rng.random()

        def rising(tau, t0=t0, sweep=sweep, lo=lo, hi=hi):
            return lo + (hi - lo) * tau, t0 + sweep * tau * tau

        surface_ribbon(ink, _surface(front, -1), rising, 0.018, 0.012, 7, WAVE_SEED + 4)
    sweeps = (((0.78, -0.42, 0.78, 0.022), (0.2, -0.36, 0.8, 0.024), (-0.42, -0.3, 0.76, 0.02)),
              ((0.62, -0.4, 0.78, 0.022), (-0.1, -0.34, 0.8, 0.022)))
    for index, layer in enumerate(layers):
        # Each layer's lines start above the layer draped over it, never under its thin flanks.
        clear = 0.0
        if index + 1 < len(layers):
            over = _LAYERS[index + 1]["tip"] + 0.03
            clear = next(i / 100 for i in range(101) if layer.back(i / 100, 0.0)[1] >= over)
        for t0, sweep, s_hi, width in sweeps[index]:
            s_lo = max(0.08 + 0.05 * rng.random(), clear)

            def swirl(tau, t0=t0, sweep=sweep, s_lo=s_lo, s_hi=s_hi):
                return s_lo + (s_hi - s_lo) * tau, t0 + sweep * tau + 0.06 * math.sin(3.0 * tau)

            surface_ribbon(ink, _surface(layer), swirl, width, 0.012, 7, WAVE_SEED + 5 + index)


def _highlights(crest: Mesh, front: _Front, layers: list[_Layer]) -> None:
    """The pale strokes: refraction streaks on the face (the reference's light blue), wide streaks on
    the backs the thrower sees -- wide enough to read at game distance from the over-the-shoulder
    camera -- the foam rim on every layer's lip, and the foam cap on every lobe of the crest. Each rides
    far enough off its sheet to clear the sag of the facets under it."""
    for t0, lo, hi, width in ((-0.46, 0.08, 0.27, 0.022), (0.04, 0.12, 0.3, 0.024), (0.5, 0.07, 0.25, 0.022)):
        def face(tau, lo=lo, hi=hi, t0=t0):
            s = lo + (hi - lo) * tau
            return s, t0 + 0.05 * math.sin(6.0 * s)

        surface_ribbon(crest, _surface(front, -1), face, width, 0.008, 7, WAVE_SEED + 1)
    for t0, sweep, lo, hi, width in ((0.52, -0.38, 0.3, 0.66, 0.036), (-0.1, -0.32, 0.28, 0.64, 0.036)):
        def back(tau, t0=t0, sweep=sweep, lo=lo, hi=hi):
            return lo + (hi - lo) * tau, t0 + sweep * tau + 0.06 * math.sin(3.0 * tau)

        surface_ribbon(crest, _surface(layers[0]), back, width, 0.007, 7, WAVE_SEED + 3)
    for index, layer in enumerate(layers):
        _foam_rim(crest, layer, 0.012, WAVE_SEED + 11 + index)
    _foam_caps(crest, front)


def _wave_parts():
    front = _Front(_FRONT)
    layers = []
    for spec in _LAYERS:
        layers.append(_Layer(spec, layers[-1] if layers else front))
    solids = [_front_volume(front)] + [_layer_volume(layer) for layer in layers] + _tendrils(front, layers)
    return front, layers, solids


_WAVE: dict[str, Mesh] = {}


def _wave() -> dict[str, Mesh]:
    """The three meshes of the wave, built once: they share one construction and one scale."""
    if _WAVE:
        return _WAVE
    front, layers, solids = _wave_parts()
    body, crest, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for vol in solids:
        body.merge(vol.mesh)
    _highlights(crest, front, layers)
    for vol in solids:
        inverted_hull(vol, ink)
    _flow_lines(ink, front, layers)
    _barrel(ink, front)
    # Exactly 1 across X, centred, by one uniform scale about the floor pivot for all three: each keeps
    # its own bounds in the manifest, and the runtime puts them back together with one Size.
    xs = [v[0] for mesh in (body, crest, ink) for v in mesh.verts]
    factor, shift = 1.0 / (max(xs) - min(xs)), -(max(xs) + min(xs)) / 2.0
    for mesh in (body, crest, ink):
        mesh.verts = [((x + shift) * factor, y * factor, z * factor) for x, y, z in mesh.verts]
    _WAVE.update(body=body, crest=crest, ink=ink)
    return _WAVE


def _wave_meta(seed: int) -> dict:
    return {"Reference": "Width", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def wave_body() -> tuple[Mesh, dict]:
    """The Wash's pigment: three sheets of ink curling into one tidal wave -- the front sheet rising
    into the crest and hanging over the barrel in a hook, its front in lobes down to the lip, two
    layers draped down its back into the long tail -- and the tendrils: three whips trailing back off
    the tail as its wake, two streams running round the foot into side curls, two thin wraps across the
    face and the tail for the swirl. Closed and wound outward, so it reads from every side, from behind
    too, where the thrower sees it leave."""
    return _wave()["body"], _wave_meta(WAVE_SEED)


def wave_crest() -> tuple[Mesh, dict]:
    """The Wash's heated core: the foam cap on every lobe of the crest, from over its top down to the
    lip, the foam rim on every layer's lip, and the refraction streaks on the face and the backs.
    The only pale of the wave, so it goes where the reference puts its light blue and nowhere else --
    the foam edge, never the body of the crest."""
    return _wave()["crest"], _wave_meta(WAVE_SEED + 1)


def wave_ink() -> tuple[Mesh, dict]:
    """The Wash's ink: the contour of every sheet and tendril (an inverted hull, so only its rim past
    the silhouette shows, thick at the foot and thin at the lip, with its ring on the ground), the
    calligraphic flow lines lying on the sheets, and the dark of the barrel under the overhang. A
    flat-lit volume reads by this or not at all."""
    return _wave()["ink"], _wave_meta(WAVE_SEED + 2)
