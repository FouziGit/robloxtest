"""The Bleed's pool (Indigo), "la Bavochure", modelled FROM THE DEVELOPER'S REFERENCES
(docs/vfx/bleed/ref-1.jpg, the in-game shot, and ref-2.jpg, the 3D model sheet), reconciled with
DA_ENCRE_3D 13.3 and the server (Radius 9, the pool's centre 12 studs ahead).

Every finger's hook faces the thrower; the drips are fat, the tendril loops open with their tails clear of
their stems, the beads flat-topped, the finger lobes full width, with no slivers. The ring's band and the
tendrils' height are the bible's (13.3), not the paintings' (the paintings' fat donut and tall tendrils
are a question for the developer, as is the tendrils' roll direction).

Roblox space: X right, Y up, forward = -Z = the far arc. Angles theta are counted from +X toward -Z
(counter-clockwise seen from above; a positive Spin turns that way). Units: OuterDiameter = 1 (18 studs);
the outermost ink -- the hooked fingers' contour -- lies exactly on r = 0.5, the server's Radius.
Pivot (0, 0, 0) on the floor at the centre; nothing below the floor.

What the references draw, and how it is built here:
  - A ring of ink, r 0.26 - 0.40, its centre empty. Seen across, it is the sheet's "hard-plane
    meniscus": a steep outer wall (the thick rim of the FRONT view), a low flat brim, then a raised
    inner swell round the hole, which drops back to the floor at an irregular inner foot. Round the
    outside, nine hard planes (the outer wall is a polygon of flat facets).
  - Nine capillary fingers on the near and side arcs, never under the tendrils: each leaves the brim
    as a fat drip over the rim (0.038 - 0.046 wide), swells (0.033 - 0.040) as it runs out over the
    floor, leans with the swirl (+theta) and ends in a hook that stands up, rolls forward, over and
    back, its opening left clear; only the curl tapers (0.030 to 0.011). Each hook turns toward +theta
    and its plane faces the thrower's eye (bible T2): the side fingers roll outward, the near ones
    across, so from behind they frame the pool as curls, never as edges. Every contour touches
    r = 0.5 exactly.
  - Four detached beads between the near fingers: round drops with a flat top (a hexagon on a
    hexagon, half a side apart), never a point.
  - Seven tendrils on the far 160-degree arc: a flared root on the brim, a stem that rises and leans
    in toward the centre, and at its head a loop that rolls over -- the sheet's row of "9"s. The tube
    thins fast through the loop, so the eye is open (about half the loop), and past its far side the
    curl tucks its tail into the bowl, stopping as far round as it can while its contour stays clear
    of the stem's. Every loop turns its flat face to the thrower and rolls the same way (screen-left,
    as both references draw them). Three-sided, as the sheet's TENDRIL SECTION.
  - Pale (Core): a lobe on the crest of every finger (0.015 wide), a lick on the outside of every loop,
    a glint on every bead, and short pointed wet glints on the ring beside the flow lines (both
    references gloss the ring with them).
  - Ink: the contour of every volume, and seven calligraphic flow lines spiralling inward on the
    ring's top, r = r0 * e^(b theta), b > 0, landing and lifting on a point.
"""

from __future__ import annotations

import math

from strokes import (
    FLOOR_CLEARANCE,
    Mesh,
    Polyline,
    Volume,
    add,
    catmull,
    cross,
    dot,
    emit,
    fbm,
    lerp,
    mul,
    norm,
    pressure,
    sliver,
    smoothstep,
    sub,
)

SEED = 9071
UP = (0.0, 1.0, 0.0)
XAXIS = (1.0, 0.0, 0.0)
# The thrower's eye (bible T2), in pool units: 1.5 studs right of the root, 8.5 up, 11.5 behind it, the
# pool's centre 12 studs ahead -- (1.5, 8.5, 23.5) / 18.
CAMERA = (0.083, 0.472, 1.306)


def rad(d: float) -> float:
    return math.radians(d)


def e_r(theta: float):
    return (math.cos(theta), 0.0, -math.sin(theta))


def e_t(theta: float):
    """Unit tangent toward +theta."""
    return (-math.sin(theta), 0.0, -math.cos(theta))


def polar(r: float, theta: float, y: float = 0.0):
    return (r * math.cos(theta), y, -r * math.sin(theta))


def radius_of(p) -> float:
    return math.hypot(p[0], p[2])


# =================================================================================================
# The ring
# =================================================================================================

STATIONS = 18  # every 20 degrees
FACETS = 9  # the outer wall's hard planes: a corner on every other station
FIRST = 4.0  # degrees: the first corner
R_OUT = 0.40
R_IN = 0.262  # the inner foot never comes closer (its contour then stays outside r = 0.25)
IN_SWING = 0.022  # how far out the irregular inner foot wanders
WALL_IN = 0.004  # the outer wall's top, inward of its foot: a steep thick rim
BRIM = 0.044  # where the swell's outer slope would meet a flat brim, from the outer foot
H_WALL = 0.022  # the rim's height (0.4 stud)
H_CREST = (0.030, 0.033)  # the swell's crest (0.56 - 0.61 stud), between these
CREST_AT = 0.52  # where the crest stands, from the inner foot (0) to the step (1)
POOL_WEIGHT = 0.0085  # contour: 0.15 stud
HOLE_WEIGHT = 0.007  # lighter round the hole, whose wall the thrower sees from behind


class Ring:
    def __init__(self) -> None:
        self.vol = Volume()
        self.prof: list[list[int]] = []
        self.geom: list[dict] = []
        n = STATIONS
        raw = []
        for i in range(n):
            th = rad(FIRST) + 2.0 * math.pi * i / n
            raw.append(0.6 * fbm(1.4 * math.cos(th) + 5.0, 1.4 * math.sin(th) + 5.0, SEED, 3)
                       + 0.4 * fbm(4.0 * math.cos(th) + 2.0, 4.0 * math.sin(th) + 2.0, SEED + 3, 2))
        lo, hi = min(raw), max(raw)
        for i in range(n):
            th = rad(FIRST) + 2.0 * math.pi * i / n
            ro = R_OUT if i % 2 == 0 else R_OUT * math.cos(math.pi / FACETS)
            ri = R_IN + IN_SWING * ((raw[i] - lo) / (hi - lo)) ** 1.4
            f = 0.5 + 0.5 * math.sin(3.0 * th + 1.3)
            hc = H_CREST[0] + (H_CREST[1] - H_CREST[0]) * f
            rb = ro - BRIM
            rc = ri + CREST_AT * (rb - ri)
            pts = [
                (ro, 0.0),
                (ro - WALL_IN, H_WALL),
                (rc, hc),
                (ri, 0.0),
            ]
            weights = [POOL_WEIGHT, POOL_WEIGHT, HOLE_WEIGHT, HOLE_WEIGHT]
            ids = [self.vol.vert(polar(r, th, y), w) for (r, y), w in zip(pts, weights)]
            self.prof.append(ids)
            self.geom.append({"theta": th, "r_out": ro, "r_in": ri, "r_brim": rb, "r_crest": rc, "h_crest": hc})
        m = self.vol.mesh
        k = len(self.prof[0])
        for i in range(n):
            a, b = self.prof[i], self.prof[(i + 1) % n]
            for j in range(k):
                jj = (j + 1) % k
                emit(m, a[j], b[j], b[jj])
                emit(m, a[j], b[jj], a[jj])
        self.vol.orient_outward()

    def r_out_at(self, theta: float) -> float:
        """The outer foot's radius at any angle: on the facet's chord."""
        step = 2.0 * math.pi / FACETS
        rel = (theta - rad(FIRST)) % step
        return R_OUT * math.cos(step / 2.0) / math.cos(rel - step / 2.0)


# =================================================================================================
# Tubes: a three-vertex section carried along a centreline, closed by a root cap and a tip vertex
# =================================================================================================


def close_tube(vol: Volume, rings: list[list[int]], tip: int) -> None:
    m = vol.mesh
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for j in range(3):
            k = (j + 1) % 3
            emit(m, a[j], a[k], b[k])
            emit(m, a[j], b[k], b[j])
    last = rings[-1]
    for j in range(3):
        emit(m, last[j], last[(j + 1) % 3], tip)
    first = rings[0]
    emit(m, first[0], first[2], first[1])
    vol.orient_outward()


# =================================================================================================
# Fingers
# =================================================================================================

# (theta deg; body width: the drip's swollen body before the curl; lean: how far it sweeps with the
#  swirl, a share of its reach; hook radius; how far round the hook rolls, degrees; the least the hook's
#  run turns toward +theta from the stem, degrees -- past that the turn is chosen so the curl's face
#  looks at the thrower)
FINGERS = [
    (178.0, 0.036, 0.30, 0.036, 220.0, 8.0),
    (200.0, 0.034, 0.40, 0.034, 210.0, 8.0),
    (224.0, 0.039, 0.12, 0.039, 225.0, 8.0),
    (249.0, 0.035, 0.30, 0.035, 215.0, 8.0),
    (272.0, 0.038, 0.06, 0.037, 220.0, 8.0),
    (295.0, 0.035, 0.35, 0.035, 215.0, 8.0),
    (319.0, 0.040, 0.15, 0.040, 225.0, 8.0),
    (343.0, 0.034, 0.26, 0.034, 210.0, 8.0),
    (6.0, 0.033, 0.12, 0.034, 220.0, 8.0),
]
FINGER_ROOT_IN = 0.030  # the path starts this far inside the outer foot
FINGER_BURY = 0.008  # its first ring stands this far along it, under the brim
FINGER_OUT = 0.008  # the second ring, this far past the outer foot: the drip over the rim
FINGER_EXIT = 1.15  # the drip over the rim, a share of the body's width
ROOT_MARGIN = 0.008  # the buried root's corners stay this far inside the outer foot
DRIP_H = 0.50  # the drip's ridge over the rim, a share of the wall's height: its contour stays under the
#               wall's top, so no ink of the finger shows on the brim
FINGER_SWELL_AT = 0.6  # where the swollen body stands, from the rim (0) to the curl (1)
HOOK_W = (0.030, 0.011)  # the curl's tube where it stands up and at its last ring: the body keeps the
#                          bible's root minimum (0.030) all the way from the rim; only the curl tapers
TURN_MAX = 120.0  # degrees: the hook's run never turns further than this from the stem,
HOOK_OUT = 0.0  # ...nor so far that it runs back toward the ring (its outward share stays above this)
FACE_SLACK = 0.03  # the least turn whose face is within this |cos| of the best the finger can do
FINGER_WEIGHT = (0.0075, 0.0057)  # contour at the neck and at the hook's tip: never under 0.1 stud
FINGER_H = 0.62  # the section's height, a share of its width, along the floor


class Finger:
    """A drip over the rim that runs out over the floor and stands up into a hook at its end: its
    section a low three-sided tent (ridge up, flat on the floor), carried by parallel transport so in
    the hook the ridge turns into the curl. The hook's plane faces the thrower's eye."""

    def __init__(self, ring: Ring, spec) -> None:
        deg, width, lean, hook, roll, turn_min = spec
        self.theta = rad(deg)
        self.width, self.lean, self.hook, self.roll = width, lean, hook, rad(roll)
        self.turn_min = turn_min
        self.ro = ring.r_out_at(self.theta)
        self.ring = ring
        lo, hi = 0.0, 0.2
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            self._build(mid)
            if self.outer() < 0.5:
                lo = mid
            else:
                hi = mid
        self._build(0.5 * (lo + hi))

    def _plane(self, end, d, side):
        """The hook's plane holds its run along the floor, d turned toward +theta (side) by at least the
        finger's least turn; of those runs, the one most square to the eye, and of the planes through
        that run, the one whose normal points straight at the eye -- as each tendril's loop does. Its
        stand-up direction (in the plane, square to the run) is then whatever that asks: leaning back
        over the stem for the near fingers, nearly upright for the side ones."""
        c = norm(sub(CAMERA, add(end, (0.0, self.hook, 0.0))))
        er = e_r(self.theta)
        runs = []
        for i in range(int(round(self.turn_min * 2)), int(TURN_MAX * 2) + 1):
            t = rad(i / 2.0)
            dh = norm(add(mul(d, math.cos(t)), mul(side, math.sin(t))))
            if dot(dh, er) < HOOK_OUT:
                break  # the run would curl back over the ring
            runs.append((math.sqrt(max(0.0, 1.0 - dot(dh, c) ** 2)), t, dh))
        # The least turn that faces the eye within FACE_SLACK of the best this finger can do.
        top = max(r[0] for r in runs)
        _, t, dh = next(r for r in runs if r[0] >= top - FACE_SLACK)
        n = norm(sub(c, mul(dh, dot(dh, c))))
        up = norm(cross(n, dh))
        if up[1] < 0:
            up = mul(up, -1.0)
        self.turn = t
        return dh, n, up

    def _path(self, reach: float):
        er, et = e_r(self.theta), e_t(self.theta)
        base = polar(self.ro, self.theta)

        def at(a: float, b: float):
            return (base[0] + a * er[0] + b * et[0], 0.0, base[2] + a * er[2] + b * et[2])

        lean = self.lean
        L = 0.006 + reach
        stem = [at(-FINGER_ROOT_IN, 0.0), at(0.0, 0.0), at(0.5 * L, 0.2 * lean * L), at(L, lean * L)]
        end, before = stem[-1], stem[-2]
        d = norm(sub(end, before))
        side = (-d[2], 0.0, d[0])
        if dot(side, et) < 0:
            side = mul(side, -1.0)
        dh, n, up = self._plane(end, d, side)
        # The hook: a circle standing on the floor at the stem's end, in the plane facing the eye; it
        # rolls forward, up, over and back toward the stem, tightening.
        centre = add(end, mul(up, self.hook))
        self.hook_centre, self.hook_n, self.hook_dh, self.hook_up = centre, n, dh, up
        pts = list(stem)
        steps = 6
        for i in range(1, steps + 1):
            phi = -0.5 * math.pi + self.roll * i / steps
            rr = self.hook * (1.0 - 0.32 * (i / steps) ** 1.5)
            q = add(centre, add(mul(dh, rr * math.cos(phi)), mul(up, rr * math.sin(phi))))
            pts.append((q[0], max(q[1], 0.0), q[2]))
        return pts, dh

    def _build(self, reach: float) -> None:
        vol = Volume()
        pts, dh = self._path(reach)
        line = Polyline(catmull(pts, 10))
        total = line.acc[-1]
        exit_s = (FINGER_ROOT_IN + FINGER_OUT) / total
        hook_s = line.acc[3 * 10] / total  # where the stem ends and the hook begins
        span = 1.0 - hook_s
        stations = [(FINGER_ROOT_IN - FINGER_BURY) / total, exit_s, exit_s + FINGER_SWELL_AT * (hook_s - exit_s),
                    hook_s, hook_s + 0.26 * span, hook_s + 0.5 * span, hook_s + 0.72 * span, hook_s + 0.9 * span]
        self.stations = stations
        self.hook_s = hook_s
        rings = []
        self.frames = []
        w0 = self.width
        nn = UP
        prev = None
        for k, s in enumerate(stations):
            c = line.at(s)
            a, b = line.at(max(0.0, s - 0.004)), line.at(min(1.0, s + 0.004))
            T = norm(sub(b, a))
            # Parallel transport, in small steps from the last station.
            if prev is not None:
                for j in range(1, 9):
                    sj = prev + (s - prev) * j / 8
                    aj, bj = line.at(max(0.0, sj - 0.004)), line.at(min(1.0, sj + 0.004))
                    Tj = norm(sub(bj, aj))
                    nn = norm(sub(nn, mul(Tj, dot(nn, Tj))))
            nn = norm(sub(nn, mul(T, dot(nn, T))))
            prev = s
            M = norm(cross(T, nn))
            if k == 0:
                # The buried root flares under the brim, but its corners stay inside the wall's facet
                # (ROOT_MARGIN in from the outer foot): a corner outside would lift its contour out
                # through the wall as a spike.
                w, h, wt = 2.0 * w0, 0.019, 0.0012
                for _ in range(40):
                    corners = [add(c, mul(M, -w / 2)), add(c, mul(M, w / 2))]
                    if all(radius_of(q) <= self.ring.r_out_at(math.atan2(-q[2], q[0]) % (2.0 * math.pi)) - ROOT_MARGIN
                           for q in corners):
                        break
                    w *= 0.95
            elif k == 1:
                w, h, wt = FINGER_EXIT * w0, DRIP_H * H_WALL, FINGER_WEIGHT[0] * 0.9
            elif k == 2:
                w, h, wt = w0, FINGER_H * w0, FINGER_WEIGHT[0]
            else:
                f = (s - hook_s) / span
                w = HOOK_W[0] + (HOOK_W[1] - HOOK_W[0]) * f
                h = FINGER_H * w
                wt = FINGER_WEIGHT[0] + (FINGER_WEIGHT[1] - FINGER_WEIGHT[0]) * f
            ring = [
                vol.vert(add(c, mul(M, -w / 2)), wt),
                vol.vert(add(c, mul(nn, h)), wt),
                vol.vert(add(c, mul(M, w / 2)), wt),
            ]
            for idx in ring:
                x, y, z = vol.mesh.verts[idx]
                vol.mesh.verts[idx] = (x, max(y, 0.0), z)
            rings.append(ring)
            self.frames.append({"s": s, "c": c, "M": M, "n": nn, "w": w, "h": h})
        tipc = line.at(1.0)
        tip = vol.vert(tipc, FINGER_WEIGHT[1] * 0.8)
        close_tube(vol, rings, tip)
        self.vol, self.rings, self.line = vol, rings, line

    def outer(self) -> float:
        dirs = push_dirs(self.vol)
        best = 0.0
        for i, p in enumerate(self.vol.mesh.verts):
            if i < 3:
                continue
            q = add(p, mul(dirs[i], self.vol.weight[i]))
            best = max(best, radius_of(q))
        return best

    def facing(self) -> float:
        """|cos| between the hook's plane normal and the line to the eye from the hook's centre: 1 is
        face-on, 0 edge-on."""
        n = norm(cross(self.hook_dh, self.hook_up))
        return abs(dot(n, norm(sub(CAMERA, self.hook_centre))))


# =================================================================================================
# Tendrils
# =================================================================================================

# (theta deg, root r, height (pigment top), loop radius share of height, root thickness, lean toward
#  the centre)
TENDRILS = [
    (27.0, 0.368, 0.108, 0.29, 0.032, 0.020),
    (49.0, 0.366, 0.124, 0.28, 0.036, 0.028),
    (70.0, 0.370, 0.130, 0.27, 0.037, 0.030),
    (92.0, 0.366, 0.127, 0.28, 0.037, 0.032),
    (113.0, 0.369, 0.120, 0.27, 0.035, 0.030),
    (134.0, 0.367, 0.113, 0.28, 0.034, 0.026),
    (155.0, 0.369, 0.104, 0.29, 0.031, 0.022),
]
TENDRIL_WEIGHT = (0.0075, 0.004)
LOOP_RINGS = 9  # rings round the loop, after the root and the rise (the stem between is straight)
LOOP_RHO = (0.36, 0.18)  # the tube's radius where the loop starts and at its last ring, a share of the root's:
#                          the tube thins fast through the loop, so the loop's eye opens
SPIRAL = (190.0, 360.0, 0.25, 0.30)  # past its far side the curl tightens (from, to, degrees; by this share
#                                     of its radius) round a centre that drifts off the stem (this share): its
#                                     tail tucks into the bowl, as the references' 9s do, and leaves the eye open
TURN_RANGE = (240.0, 345.0)  # degrees: the curl rolls as far as it can in this range...
TAIL_CLEAR = 0.0005  # ...while its tail stays this much clear of the rest of the tube, contour included


class Tendril:
    def __init__(self, spec) -> None:
        deg, r0, top, share, thick, lean = spec
        self.theta = rad(deg)
        self.r0, self.top, self.share, self.lean = r0, top, share, lean
        self.rho0 = thick / (2.0 * math.sin(rad(60.0)))
        base = polar(r0, self.theta)
        # The loop's plane: rolling screen-left (-X) as both references draw it, turned a little toward
        # the centre, so its flat face looks at the thrower.
        inward = mul(e_r(self.theta), -1.0)
        self.h = norm(add(mul(XAXIS, -1.0), mul(inward, 0.3)))
        n = (self.h[2], 0.0, -self.h[0])
        to_cam = sub(CAMERA, base)
        if dot(n, to_cam) < 0:
            n = mul(n, -1.0)
        self.n = n
        self.inward = inward
        self.base = base
        scale = 1.0
        for _ in range(30):
            self._fit(scale)
            high = max(v[1] for v in self.vol.mesh.verts)
            if abs(high - top) < 1e-6:
                break
            scale *= top / high

    # ---- the centreline: a stem, then a loop that rolls over toward +u and curls into itself ----------

    def _rr(self, a: float) -> float:
        return self.R * (1.0 - SPIRAL[2] * smoothstep(rad(SPIRAL[0]), rad(SPIRAL[1]), a))

    def _cu(self, a: float) -> float:
        return self.R * (1.0 + SPIRAL[3] * smoothstep(rad(SPIRAL[0]), rad(SPIRAL[1]), a))

    def _point(self, u: float, v: float):
        lean = self.lean * (max(v, 0.0) / self.H) ** 1.5
        return add(self.base, add(add(mul(self.h, u), (0.0, v, 0.0)), mul(self.inward, lean)))

    def _loop_point(self, a: float):
        rr = self._rr(a)
        phi = math.pi - a
        return self._point(self._cu(a) + rr * math.cos(phi), self.cv + rr * math.sin(phi))

    def _rho_loop(self, a: float) -> float:
        f = min(1.0, a / rad(TURN_RANGE[0] + 60.0))
        return self.rho0 * (LOOP_RHO[0] + (LOOP_RHO[1] - LOOP_RHO[0]) * f ** 0.75)

    def _fit(self, scale: float) -> None:
        """The longest roll whose tail stays clear of the stem and of the loop's start."""
        lo, hi = rad(TURN_RANGE[0]), rad(TURN_RANGE[1])
        self._build(scale, hi)
        if self.tail_gap() >= TAIL_CLEAR:
            return
        for _ in range(26):
            mid = 0.5 * (lo + hi)
            self._build(scale, mid)
            if self.tail_gap() >= TAIL_CLEAR:
                lo = mid
            else:
                hi = mid
        self._build(scale, lo)

    def _build(self, scale: float, total: float) -> None:
        vol = Volume()
        self.H = self.top * scale
        self.R = self.share * self.H
        self.cv = self.H - self.R
        self.total = total
        H, R, cv = self.H, self.R, self.cv
        stem_local = [(0.0, 0.0), (0.002, 0.022), (-0.003, 0.55 * (cv - R) + 0.01), (-0.003, cv - 0.6 * R), (0.0, cv)]
        stem = [self._point(u, v) for u, v in catmull(stem_local, 8)]
        steps = max(24, int(math.degrees(total) / 3.0))
        loop = [self._loop_point(total * i / steps) for i in range(steps + 1)]
        line = Polyline(stem[:-1] + loop)
        self.loop_centre = self._point(R, cv)
        # The rings: the root (flared, under the ring's surface), the rise, the stem's middle, then evenly
        # round the loop; a tip vertex closes it.
        v_rise = 0.022
        places = [(self._point(0.0, 0.0), None, 1.5 * self.rho0, 0.0),
                  (self._point(0.002, v_rise), None, self.rho0, v_rise)]
        for j in range(LOOP_RINGS):
            a = total * j / LOOP_RINGS
            places.append((self._loop_point(a), a, self._rho_loop(a), None))
        # Arc-length share of each ring's centre along the dense line, for its contour's taper.
        def share_of(p):
            best = min(range(len(line.p)), key=lambda i: math.dist(line.p[i], p))
            return line.acc[best] / line.acc[-1]

        rings = []
        self.frames = []
        for k, (c, a, rho, v) in enumerate(places):
            s = share_of(c)
            pa, pb = line.at(max(0.0, s - 0.004)), line.at(min(1.0, s + 0.004))
            T = norm(sub(pb, pa))
            nn = norm(sub(self.n, mul(T, dot(self.n, T))))
            M = norm(cross(T, nn))
            wt = TENDRIL_WEIGHT[0] + (TENDRIL_WEIGHT[1] - TENDRIL_WEIGHT[0]) * min(1.0, s / 0.96) ** 1.2
            ring = []
            for alpha in (30.0, 150.0, 270.0):
                al = rad(alpha)
                q = add(c, add(mul(M, rho * math.cos(al)), mul(nn, rho * math.sin(al))))
                ring.append(vol.vert((q[0], max(q[1], 0.0), q[2]), wt))
            rings.append(ring)
            self.frames.append({"s": s, "a": a, "c": c, "T": T, "n": nn, "M": M, "rho": rho, "w": wt})
        tipc = self._loop_point(total)
        tip_w = TENDRIL_WEIGHT[1] * 0.7
        tip = vol.vert(tipc, tip_w)
        self.frames.append({"s": 1.0, "a": total, "c": tipc, "rho": 0.0, "w": tip_w})
        close_tube(vol, rings, tip)
        self.vol, self.rings, self.line = vol, rings, line

    def tail_gap(self) -> float:
        """The narrowest clearance between the tube's tail (the loop past its far side) and any part of
        the tube at least three rings behind it: centre-to-centre distance less both radii (the
        section's circumradius) and the heavier contour. Positive: no contour pokes into the other."""
        fr = self.frames
        cs = [f["c"] for f in fr]

        def seg_pts(i, n=6):
            out = []
            for k in range(n + 1):
                t = k / n
                out.append((lerp(cs[i], cs[i + 1], t), fr[i]["rho"] + (fr[i + 1]["rho"] - fr[i]["rho"]) * t,
                            fr[i]["w"] + (fr[i + 1]["w"] - fr[i]["w"]) * t))
            return out

        worst = 1.0
        for j in range(len(fr) - 1):
            if fr[j]["a"] is None or fr[j]["a"] < rad(180.0):
                continue
            tail = seg_pts(j)
            for i in range(0, j - 2):
                for p, rp, wp in seg_pts(i):
                    for q, rq, wq in tail:
                        worst = min(worst, math.dist(p, q) - rp - rq - max(wp, wq))
        return worst

    def eye(self) -> tuple[float, float]:
        """The loop's eye against its outer size, across the loop through its centre (screen-wise): the
        open gap between the stem side and the far side, and the loop's full width there."""
        fr = [f for f in self.frames if f["a"] is not None]

        def near(a):
            return min(fr, key=lambda f: abs(f["a"] - a))

        f0, f180 = near(0.0), near(math.pi)
        t0 = 0.866 * f0["rho"] + f0["w"]
        t1 = 0.866 * f180["rho"] + f180["w"]
        width = math.dist(f0["c"], f180["c"])
        return width - t0 - t1, width + t0 + t1


# =================================================================================================
# Beads
# =================================================================================================

BEADS = [(187.0, 0.441, 0.0150), (236.0, 0.468, 0.0140), (283.0, 0.458, 0.0155), (331.0, 0.466, 0.0145)]
BEAD_H = 0.014
BEAD_SIDES = 6
BEAD_TOP = 0.58  # the flat top's radius, a share of the foot's: a round drop, never a point
BEAD_WEIGHT = 0.006


class Bead:
    """A round drop of ink: a low hexagonal dome with a flat top, the top's hexagon turned half a side
    from the foot's (its contour rounds it), a pale glint."""

    def __init__(self, theta: float, r: float, radius: float) -> None:
        vol = Volume()
        cx, _, cz = polar(r, theta)
        self.centre = (cx, cz)
        self.radius = radius
        base, top = [], []
        for k in range(BEAD_SIDES):
            a = theta + 2.0 * math.pi * k / BEAD_SIDES
            base.append(vol.vert((cx + radius * math.cos(a), 0.0, cz - radius * math.sin(a)), BEAD_WEIGHT))
        for k in range(BEAD_SIDES):
            a = theta + 2.0 * math.pi * (k + 0.5) / BEAD_SIDES
            rt = BEAD_TOP * radius
            top.append(vol.vert((cx + rt * math.cos(a), BEAD_H, cz - rt * math.sin(a)), BEAD_WEIGHT))
        m = vol.mesh
        for k in range(BEAD_SIDES):
            k1 = (k + 1) % BEAD_SIDES
            emit(m, base[k], base[k1], top[k])
            emit(m, base[k1], top[k1], top[k])
        for k in range(1, BEAD_SIDES - 1):
            emit(m, top[0], top[k], top[k + 1])
            emit(m, base[0], base[k + 1], base[k])
        make_consistent(vol)
        self.vol, self.mid, self.top = vol, base, top


# =================================================================================================
# Helpers: consistent winding, the contour, the drape
# =================================================================================================


def make_consistent(vol: Volume) -> None:
    tris = [list(t) for t in vol.mesh.tris]
    by_edge: dict = {}
    for i, (a, b, c) in enumerate(tris):
        for u, v in ((a, b), (b, c), (c, a)):
            by_edge.setdefault((min(u, v), max(u, v)), []).append(i)
    seen = [False] * len(tris)
    for start in range(len(tris)):
        if seen[start]:
            continue
        seen[start] = True
        stack = [start]
        while stack:
            i = stack.pop()
            a, b, c = tris[i]
            for u, v in ((a, b), (b, c), (c, a)):
                for j in by_edge[(min(u, v), max(u, v))]:
                    if j == i or seen[j]:
                        continue
                    x, y, z = tris[j]
                    if (u, v) in ((x, y), (y, z), (z, x)):
                        tris[j] = [x, z, y]
                    seen[j] = True
                    stack.append(j)
    vol.mesh.tris = [tuple(t) for t in tris]
    vol.orient_outward()


def angle_at(p, q, r) -> float:
    u, v = sub(q, p), sub(r, p)
    lu, lv = math.sqrt(dot(u, u)), math.sqrt(dot(v, v))
    if lu < 1e-12 or lv < 1e-12:
        return 0.0
    return math.acos(max(-1.0, min(1.0, dot(u, v) / (lu * lv))))


def push_dirs(vol: Volume) -> list:
    """Angle-weighted vertex normals (area weighting would turn a flat pool's foot straight down)."""
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        pa, pb, pc = mesh.verts[a], mesh.verts[b], mesh.verts[c]
        n = norm(cross(sub(pb, pa), sub(pc, pa)))
        for v, p, q, r in ((a, pa, pb, pc), (b, pb, pc, pa), (c, pc, pa, pb)):
            acc[v] = add(acc[v], mul(n, angle_at(p, q, r)))
    return [norm(n) for n in acc]


def contour(vol: Volume, into: Mesh) -> None:
    mesh = vol.mesh
    dirs = push_dirs(vol)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        q = add(p, mul(dirs[i], vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR_CLEARANCE), q[2]))
    for a, b, c in mesh.tris:
        corners = [into.verts[v + base] for v in (a, b, c)]
        if all(q[1] <= FLOOR_CLEARANCE for q in corners) and sliver(*corners):
            continue
        emit(into, a + base, c + base, b + base)


class Drape:
    """The highest upward face straight under (x, z)."""

    CELL = 0.02

    def __init__(self, mesh: Mesh) -> None:
        self.faces = []
        self.grid: dict = {}
        for t in mesh.tris:
            a, b, c = (mesh.verts[i] for i in t)
            n = norm(cross(sub(b, a), sub(c, a)))
            if n[1] <= 1e-4:
                continue
            k = len(self.faces)
            self.faces.append((a, b, c, n))
            xs, zs = (a[0], b[0], c[0]), (a[2], b[2], c[2])
            for i in range(math.floor(min(xs) / self.CELL), math.floor(max(xs) / self.CELL) + 1):
                for j in range(math.floor(min(zs) / self.CELL), math.floor(max(zs) / self.CELL) + 1):
                    self.grid.setdefault((i, j), []).append(k)

    def at(self, x: float, z: float):
        best = None
        for k in self.grid.get((math.floor(x / self.CELL), math.floor(z / self.CELL)), ()):
            a, b, c, n = self.faces[k]
            ux, uz = b[0] - a[0], b[2] - a[2]
            vx, vz = c[0] - a[0], c[2] - a[2]
            det = ux * vz - uz * vx
            if abs(det) < 1e-14:
                continue
            px, pz = x - a[0], z - a[2]
            u = (px * vz - pz * vx) / det
            v = (ux * pz - uz * px) / det
            if u < -1e-9 or v < -1e-9 or u + v > 1.0 + 1e-9:
                continue
            y = a[1] + u * (b[1] - a[1]) + v * (c[1] - a[1])
            if best is None or y > best[0][1] + 1e-9 or (y > best[0][1] - 1e-9 and n[1] > best[1][1]):
                best = ((x, y, z), n)
        if best is None:
            raise ValueError(f"nothing to lie on at ({x:.4f}, {z:.4f})")
        return best

    def lifted(self, x: float, z: float, lift: float):
        p, n = self.at(x, z)
        return (p[0], p[1] + lift / max(n[1], 0.35), p[2])


def strip(mesh: Mesh, drape: Drape, rows: list, lift: float) -> None:
    """Rows of XZ points draped on the surface and stitched; a row of one point is a pointed end."""
    ids = [[mesh.vert(drape.lifted(x, z, lift)) for x, z in row] for row in rows]
    for a, b in zip(ids, ids[1:]):
        if len(a) == 1:
            for k in range(len(b) - 1):
                mesh.tri(a[0], b[k + 1], b[k], UP)
            continue
        if len(b) == 1:
            for k in range(len(a) - 1):
                mesh.tri(a[k], a[k + 1], b[0], UP)
            continue
        for k in range(len(a) - 1):
            mesh.tri(a[k], a[k + 1], b[k + 1], UP)
            mesh.tri(a[k], b[k + 1], b[k], UP)


def spiral_rows(th0: float, span: float, r_hi: float, b: float, width: float, rows: int, seed: int, shape=None,
                ease: bool = False):
    """Rows of three XZ points across a log spiral r = r_hi * e^(b (theta - th0)), from its outer,
    loaded end at th0 toward -theta (inward), a brush's pressure across. With ease, the rows crowd
    toward both ends, where the brush is thin, so no triangle there is a sliver."""
    pts = []
    for i in range(rows):
        f = i / (rows - 1)
        if ease:
            f = 0.5 - 0.5 * math.cos(math.pi * f)
        tau = 0.03 + 0.94 * f
        th = th0 - span * tau
        r = r_hi * math.exp(b * (th - th0))
        pts.append((r * math.cos(th), -r * math.sin(th), tau))
    out = []
    for i, (x, z, tau) in enumerate(pts):
        ax, az, _ = pts[max(i - 1, 0)]
        bx, bz, _ = pts[min(i + 1, len(pts) - 1)]
        tx, tz = bx - ax, bz - az
        ln = math.hypot(tx, tz)
        nx, nz = -tz / ln, tx / ln
        if shape is None:
            half = max(pressure(tau, width, 0.18, 0.9, seed), width * 0.26) / 2.0
        else:
            half = width * shape(tau) / 2.0
        out.append([(x + nx * half, z + nz * half), (x, z), (x - nx * half, z - nz * half)])
    return out, pts


# =================================================================================================
# Pale and ink details
# =================================================================================================

CORE_LIFT = 0.0022
LOBE = (0.0165, 0.62, 0.088)  # the finger lobe's width at its fullest, how far out it runs (share of path), its longest


def finger_lobes(core: Mesh, fingers: list[Finger]) -> list[float]:
    """A pale lobe along each finger's crest: from just past the rim, over the drip, out along the
    ridge, a lens straddling it."""
    lengths = []
    for index, fg in enumerate(fingers):
        verts = fg.vol.mesh.verts
        rows = []
        s0 = fg.stations[1]
        longest = LOBE[2] * (0.72 + 0.28 * ((index * 3) % 5) / 4)
        s1 = min(LOBE[1], fg.hook_s, s0 + longest / fg.line.acc[-1])
        count = 4
        length = 0.0
        prev = None
        for i in range(count):
            s = s0 + (s1 - s0) * i / (count - 1)
            # Interpolate the section between the two rings around s.
            k = max(j for j in range(len(fg.stations)) if fg.stations[j] <= s)
            k = min(k, len(fg.stations) - 2)
            f = (s - fg.stations[k]) / (fg.stations[k + 1] - fg.stations[k])
            L = lerp(verts[fg.rings[k][0]], verts[fg.rings[k + 1][0]], f)
            R = lerp(verts[fg.rings[k][1]], verts[fg.rings[k + 1][1]], f)
            G = lerp(verts[fg.rings[k][2]], verts[fg.rings[k + 1][2]], f)
            w_half = max(abs(math.dist(L, G)) / 2.0, 1e-6)
            want = LOBE[0] / 2.0 * math.sin(math.pi * (0.08 + 0.84 * i / (count - 1))) ** 0.7
            share = min(0.62, want / w_half)
            left = lerp(R, L, share)
            right = lerp(R, G, share)
            lift = (0.0, CORE_LIFT, 0.0)
            rows.append([add(left, lift), add(R, add(lift, (0.0, 0.0006, 0.0))), add(right, lift)])
            if prev is not None:
                length += math.dist(prev, R)
            prev = R
        ids = [[core.vert(p) for p in row] for row in rows]
        for a, b in zip(ids, ids[1:]):
            for j in range(2):
                core.tri(a[j], a[j + 1], b[j + 1], UP)
                core.tri(a[j], b[j + 1], b[j], UP)
        lengths.append(length)
    return lengths


LICK = (0.05, 0.85, 74.0, 0.053)  # the lick's inner and outer edge across the camera face (share of the
#                                  face's half-width), the loop angle it centres on (degrees: over the top),
#                                  and its length along the curve (the bible: 0.045 - 0.065)
LICK_ROWS = 4
LICK_LIFT = 0.0025


def _face_point(fr, x: float, lift: float):
    """A point on a ring's camera-facing face (the side between its 30 and 150 degree corners), x from -1
    to 1 across it, lifted off it."""
    return add(fr["c"], add(mul(fr["M"], x * 0.866 * fr["rho"]), mul(fr["n"], 0.5 * fr["rho"] + lift)))


def _lick_rows(td: Tendril, half_span: float):
    """The lick's rows over the loop's top, each on the face between the two rings round it, where the
    tube's own face runs; and its length along its middle."""
    loop = [f for f in td.frames if f["a"] is not None and "M" in f]
    rows = []
    length = 0.0
    prev = None
    for idx in range(LICK_ROWS):
        a = rad(LICK[2]) + half_span * (2.0 * idx / (LICK_ROWS - 1) - 1.0)
        j = max(i for i in range(len(loop) - 1) if loop[i]["a"] <= a)
        f0, f1 = loop[j], loop[j + 1]
        t = (a - f0["a"]) / (f1["a"] - f0["a"])
        c = lerp(f0["c"], f1["c"], t)
        M = lerp(f0["M"], f1["M"], t)
        sign = 1.0 if dot(sub(c, td.loop_centre), M) >= 0 else -1.0
        taper = math.sin(math.pi * (0.1 + 0.8 * idx / (LICK_ROWS - 1))) ** 0.6
        x0 = sign * LICK[0]
        x1 = sign * (LICK[0] + (LICK[1] - LICK[0]) * taper)
        p_in = lerp(_face_point(f0, x0, LICK_LIFT), _face_point(f1, x0, LICK_LIFT), t)
        p_out = lerp(_face_point(f0, x1, LICK_LIFT), _face_point(f1, x1, LICK_LIFT), t)
        p_mid = lerp(p_in, p_out, 0.5)
        rows.append([p_in, p_mid, p_out])
        if prev is not None:
            length += math.dist(prev, p_mid)
        prev = p_mid
    return rows, length


def tendril_licks(core: Mesh, tendrils: list[Tendril]) -> list[float]:
    """A pale lick on each loop's face that looks at the thrower, along the outside of the curve over
    its top: the sheet's pale tendril curves. Its arc is chosen so its length is LICK's."""
    lengths = []
    for td in tendrils:
        lo, hi = rad(10.0), rad(70.0)
        for _ in range(30):
            mid = 0.5 * (lo + hi)
            if _lick_rows(td, mid)[1] < LICK[3]:
                lo = mid
            else:
                hi = mid
        rows, length = _lick_rows(td, 0.5 * (lo + hi))
        ids = [[core.vert(p) for p in row] for row in rows]
        for r0, r1 in zip(ids, ids[1:]):
            for j in range(2):
                core.tri(r0[j], r0[j + 1], r1[j + 1], td.n)
                core.tri(r0[j], r1[j + 1], r1[j], td.n)
        lengths.append(length)
    return lengths


def bead_caps(core: Mesh, beads: list[Bead]) -> None:
    for bead in beads:
        drape = Drape(bead.vol.mesh)
        cx, cz = bead.centre
        ring = []
        for k in range(BEAD_SIDES):
            p = bead.vol.mesh.verts[bead.mid[k]]
            # A glint toward the far side of the dome, off its centre.
            ring.append((cx + (p[0] - cx) * 0.3 - 0.003, cz + (p[2] - cz) * 0.3 - 0.003))
        apex = core.vert(drape.lifted(cx - 0.003, cz - 0.003, CORE_LIFT))
        ids = [core.vert(drape.lifted(x, z, CORE_LIFT)) for x, z in ring]
        for k in range(BEAD_SIDES):
            core.tri(apex, ids[k], ids[(k + 1) % BEAD_SIDES], UP)


# The seven ink flow lines: (theta0 at the outer end, deg; span, deg; r at the outer end; r at the
# inner end; width). b = ln(r_hi / r_lo) / span > 0.
FLOWS = [
    (345.0, 100.0, 0.372, 0.290, 0.015),
    (295.0, 92.0, 0.372, 0.289, 0.016),
    (245.0, 82.0, 0.370, 0.293, 0.015),
    (200.0, 70.0, 0.356, 0.297, 0.014),
    (150.0, 42.0, 0.318, 0.292, 0.014),
    (100.0, 46.0, 0.318, 0.290, 0.014),
    (45.0, 75.0, 0.322, 0.287, 0.014),
]
FLOW_LIFT = 0.0035
FLOW_ROWS = 9

# Pale wet glints on the ring, each beside a flow line on the side the thrower sees: (flow index,
# start share, end share, offset outward, width).
GLINTS = [
    (0, 0.06, 0.48, -0.017, 0.010),
    (1, 0.10, 0.55, -0.017, 0.009),
    (2, 0.05, 0.50, -0.016, 0.009),
    (3, 0.05, 0.45, -0.015, 0.008),
    (6, 0.55, 0.95, 0.016, 0.008),
]
GLINT_LIFT = 0.0030

# Pale gloss along the rim's crest, on the near half the thrower faces (both references light the
# meniscus's edge): (theta start, theta end, deg; width). Drawn along the brim a little inside the
# wall's top, between the fingers' roots.
RIM_GLOSS = [(186.0, 214.0, 0.008), (231.0, 262.0, 0.009), (281.0, 310.0, 0.009), (327.0, 352.0, 0.008)]
RIM_GLOSS_IN = 0.016  # how far inside the outer foot


def rim_gloss(core: Mesh, ring: Ring, drape: Drape) -> None:
    for a0, a1, width in RIM_GLOSS:
        rows = []
        n = 5
        for i in range(n):
            t = i / (n - 1)
            th = rad(a0 + (a1 - a0) * t)
            r = ring.r_out_at(th) - RIM_GLOSS_IN
            half = width / 2.0 * max(0.15, math.sin(math.pi * (0.05 + 0.9 * t))) ** 0.8
            rows.append([polar(r + half, th)[0::2], polar(r - half, th)[0::2]])
        strip(core, drape, rows, GLINT_LIFT)


def flow_lines(ink: Mesh, drape: Drape) -> list[float]:
    lengths = []
    for k, (th0, span, r_hi, r_lo, width) in enumerate(FLOWS):
        span_r = rad(span)
        b = math.log(r_hi / r_lo) / span_r
        rows, pts = spiral_rows(rad(th0), span_r, r_hi, b, width, FLOW_ROWS, SEED + 31 * k)
        # The brush lands and lifts on a point: both ends are single vertices.
        strip(ink, drape, [[rows[0][1]]] + rows[1:-1] + [[rows[-1][1]]], FLOW_LIFT)
        lengths.append(sum(math.dist(p[:2], q[:2]) for p, q in zip(pts, pts[1:])))
    return lengths


def glints(core: Mesh, drape: Drape) -> None:
    for k, (fi, s0, s1, off, width) in enumerate(GLINTS):
        th0, span, r_hi, r_lo, _ = FLOWS[fi]
        span_r = rad(span)
        b = math.log(r_hi / r_lo) / span_r
        a0 = rad(th0) - span_r * s0
        sub_span = span_r * (s1 - s0)
        r_start = r_hi * math.exp(b * (a0 - rad(th0))) + off
        rows, _ = spiral_rows(a0, sub_span, r_start, b, width, 4, SEED + 77 * k,
                              shape=lambda t: max(0.15, math.sin(math.pi * t)) ** 0.8)
        # Pointed at both ends: a wet glint is a lens, and a blunt end there would be a sliver.
        strip(core, drape, [[rows[0][1]]] + [[row[0], row[2]] for row in rows[1:-1]] + [[rows[-1][1]]], GLINT_LIFT)


# =================================================================================================
# The three meshes
# =================================================================================================

_CACHE: dict = {}


def build():
    if _CACHE:
        return _CACHE
    ring = Ring()
    fingers = [Finger(ring, spec) for spec in FINGERS]
    tendrils = [Tendril(spec) for spec in TENDRILS]
    beads = [Bead(rad(d), r, rr) for d, r, rr in BEADS]
    solids = [ring.vol] + [f.vol for f in fingers] + [t.vol for t in tendrils] + [b.vol for b in beads]
    body, sheen, ink = Mesh("up"), Mesh("up"), Mesh("up")
    for vol in solids:
        body.merge(vol.mesh)
    drape = Drape(ring.vol.mesh)
    lobes = finger_lobes(sheen, fingers)
    licks = tendril_licks(sheen, tendrils)
    bead_caps(sheen, beads)
    glints(sheen, drape)
    rim_gloss(sheen, ring, drape)
    for vol in solids:
        contour(vol, ink)
    flows = flow_lines(ink, drape)
    _CACHE.update(body=body, sheen=sheen, ink=ink, ring=ring, fingers=fingers, tendrils=tendrils, beads=beads,
                  lobes=lobes, licks=licks, flows=flows, solids=solids)
    return _CACHE


def meta(seed: int) -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def bleed_pool():
    """BleedPool (Pigment): the ring, nine hooked fingers, seven curling tendrils, four beads."""
    return build()["body"], meta(SEED)


def bleed_sheen():
    """BleedSheen (Core): finger lobes, tendril licks, bead glints, wet glints on the ring."""
    return build()["sheen"], meta(SEED + 1)


def bleed_ink():
    """BleedInk (Ink): every volume's contour and seven inward spiralling flow lines."""
    return build()["ink"], meta(SEED + 2)
