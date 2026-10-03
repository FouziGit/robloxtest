"""The Sweep's body (Le Balayage) drawn after the developer's references: docs/vfx/sweep/ref-2.jpg (the
model sheet "Verdigris ink gust band") and ref-1.jpg (in game).

Three meshes cut from one construction, one flat tone each: gust_body (Pigment), gust_crest (Core, the
pale only), gust_ink (Ink: contour, flow lines, the volutes' spirals). Roblox space: X right, Y up,
forward -Z.

What the sheet draws, kept here:
  - a band lying on the page in a ring sector open toward the thrower (+Z), from -110 degrees (the
    head, -X) to +77 (the end of the tail strand): low at its inner edge (a small wall), rising to a
    raised outer lip whose flat top carries a thin pale line, 0.10 high at the head and 0.06 at the
    tail; loaded at the head, slimmer toward the tail;
  - the head cut square, its end face toward the thrower; two rolled volutes side by side across the
    band at each end (the outer one the bigger), each a short scroll whose spiral faces the band's end
    -- so from behind the thrower, on both flanks, two spirals look at the camera -- with a pale cap on
    the top of the roll, set back from the face; they roll outward (see the choice below);
  - at the tail the inner strands stop at the two volutes (+68) and the outer strand runs on to +77,
    where it splits: three whips come out of its end face, fan apart with clear gaps and run on along
    the arc, unequal (the outer the longest, to about 113 degrees), then each hooks inward in the page
    and rises into an open curl that leans back along the arc and faces the thrower's camera, its tip
    inside its own turn -- never past 120 degrees (the opening stays empty) nor past r 0.5;
  - five uneven flow lines along the arc, each drifting across the band as it goes, out of the
    volutes and lost along the arc.

Two choices are the developer's, not this file's: the roll of the volutes (they roll
outward, mirror to mirror, as the sheet draws them, or all toward -Z, as DA 13.2 reads the push) and the
arc against the pre-turn (13.2's -110 / +110 design arc plus the -0.3 rad pre-turn and Spin +1.5 cross
the 120-degree empty sector at t = 0 and near 0.42 s).

Reference: OuterDiameter = 1 (the outer ink, hull included, in the floor plane, is exactly 0.5 from the
pivot); pivot (0, 0, 0) on the floor at the disc's centre; axis Y. Designed with the arc centred on
-Z, then pre-turned -0.3 rad about Y (Spin +1.5 brings it back on the aim at 0.2 s).
"""

from __future__ import annotations

import math

from strokes import (
    FLOOR_CLEARANCE,
    UP,
    Mesh,
    Polyline,
    Vec,
    Volume,
    add,
    catmull,
    cosine_curve,
    cross,
    dot,
    emit,
    face_normal,
    mul,
    norm,
    sliver,
    smoothstep,
    sub,
)

SEED = 4471
PRE_TURN = -0.3
D = math.pi / 180.0

HEAD, TAIL = -110.0, 77.0  # the band, degrees from the aim (-Z), positive toward +X
R_IN = 0.21
R_OUT = 0.482  # with the foot (0.006) and the contour (0.012) the outer ink lands on 0.5
FOOT = 0.006  # how far the outer wall flares onto the page
LIP_W = 0.030  # the flat top of the lip
INNER_END = 68.0  # where the tail's inner strands stop (the two tail volutes)
STRAND_W = 0.112  # the tail strand's radial width, where the inner strands have stopped


def polar(alpha: float, r: float, y: float) -> Vec:
    a = alpha * D
    return (r * math.sin(a), y, -r * math.cos(a))


def radial(alpha: float) -> Vec:
    a = alpha * D
    return (math.sin(a), 0.0, -math.cos(a))


def tangent(alpha: float) -> Vec:
    a = alpha * D
    return (math.cos(a), 0.0, math.sin(a))


def angle_of(p: Vec) -> float:
    return math.degrees(math.atan2(p[0], -p[2]))


# --- the band --------------------------------------------------------------------------------------


def r_out(a: float) -> float:
    """The outer edge: the full ring, drawn in a little along the tail strand."""
    return R_OUT - 0.02 * smoothstep(40.0, TAIL, a)


def r_in(a: float) -> float:
    """The inner edge: the head loaded (the band widest there), slimmer toward the tail."""
    return R_IN - 0.012 + 0.03 * smoothstep(HEAD, 80.0, a)


def width(a: float) -> float:
    full = r_out(a) - r_in(a)
    return full + (STRAND_W - full) * smoothstep(INNER_END - 4.0, INNER_END + 2.0, a)


def lip(a: float) -> float:
    return 0.10 + (0.06 - 0.10) * (a - HEAD) / (90.0 - HEAD)


def section(a: float) -> list[tuple[float, float]]:
    """(r, y) round the band's section: inner floor, inner top (a low wall), the foot of the lip up the
    ramp, the lip's flat top (inner, outer), the outer foot on the page. The page closes it."""
    ro, w, h = r_out(a), width(a), lip(a)
    ri = ro - w
    k = 0.6 + 0.4 * h / 0.10
    lw = min(LIP_W, 0.3 * w)
    ramp = w - lw
    return [
        (ri, 0.0),
        (ri + 0.004, 0.026 * k),
        (ri + 0.72 * ramp, 0.044 * k),
        (ro - lw, h),
        (ro, 0.97 * h),
        (ro + FOOT, 0.0),
    ]


def band_angles() -> list[float]:
    out = []
    a = HEAD
    while a < TAIL - 1e-6:
        out.append(a)
        # Finer where the tail's inner strands stop.
        step = 3.5 if INNER_END - 6 <= a <= INNER_END + 4 else 12.5
        a = min(TAIL, a + step)
    out.append(TAIL)
    return out


def band_top(a: float, r: float) -> tuple[float, int, float]:
    """Height of the band's top at radius r (on the chain inner top .. lip outer top), the section segment
    it lies on and the fraction along it."""
    pts = section(a)[1:5]
    for i in range(len(pts) - 1):
        (r0, y0), (r1, y1) = pts[i], pts[i + 1]
        if r0 - 1e-9 <= r <= r1 + 1e-9:
            f = (r - r0) / max(r1 - r0, 1e-9)
            return y0 + (y1 - y0) * f, i + 1, f
    return pts[-1][1], 3, 1.0


def band_volume() -> tuple[Volume, list[float], list[list[int]]]:
    vol = Volume()
    angles = band_angles()
    rings = []
    for a in angles:
        heavy = 0.012 - 0.003 * smoothstep(40.0, TAIL, a)
        ring = []
        for j, (r, y) in enumerate(section(a)):
            ring.append(vol.vert(polar(a, r, y), heavy if j else heavy - 0.002))
        rings.append(ring)
    m = 6
    for ra, rb in zip(rings, rings[1:]):
        for j in range(m):
            k = (j + 1) % m
            emit(vol.mesh, ra[j], ra[k], rb[k])
            emit(vol.mesh, ra[j], rb[k], rb[j])
    first, last = rings[0], rings[-1]
    for j in range(m - 2):
        emit(vol.mesh, first[m - 1], first[j + 1], first[j])
        emit(vol.mesh, last[m - 1], last[j], last[j + 1])
    vol.orient_outward()
    return vol, angles, rings


# --- the volutes ------------------------------------------------------------------------------------
# The sheet draws each volute as the end of a rolled scroll: a filled round face (the roll seen end-on)
# with a black spiral line running in from where the sheet tucks under to the eye, a pale cap on top of
# the roll, the roll running back into its strand.

OUTLINE_N = 13  # samples round the face's outline (one turn, the last one at the tuck)
THETA0 = -90.0  # where the sheet tucks in: the bottom of the roll
TUCK = 0.30  # how much smaller the outline is after one turn (the step where the sheet tucks under)
FACE_OUT = 0.009  # the face stands this far proud of the band's end plane, parallel to it
BACKING = 0.004  # the face's ink backing sits this far behind the face: 0.005 in front of the end plane
SPIRAL_LIFT = 0.004  # the ink spiral rides this far off the face
CAP_FROM, CAP_TO = 0.016, 0.050  # the pale cap, along the roll from the face (13.2: <= 0.04 long)
CAP_PHI = (150.0, 210.0)  # ... and round the crest (about 0.045 across, 13.2: <= 0.06)


class Volute:
    """A scroll end lying across the band at one of its ends, its face toward the band's end (`back` is
    the direction, in alpha, the roll runs back into the band), rolling outward: over its top the sheet
    travels toward +u (away from the ring's centre)."""

    def __init__(self, end: float, back: int, r_c: float, r0: float, length: float, top: float) -> None:
        self.end, self.back, self.r_c, self.r0 = end, back, r_c, r0
        # The face's outline in (u outward, v up) about the eye: one turn of a shrinking radius, clockwise
        # (theta decreasing), so the crest moves outward; it ends a step inside its start, at the tuck.
        self.outline = []
        for k in range(OUTLINE_N):
            phi = 2 * math.pi * k / (OUTLINE_N - 1)
            rho = r0 * (1.0 - TUCK * phi / (2 * math.pi))
            theta = THETA0 * D - phi
            self.outline.append((rho * math.cos(theta), rho * math.sin(theta)))
        self.v_c = top - max(v for _, v in self.outline)
        self.root = self.outline[0]
        # The caps fan from a point a little inward of the eye: from the eye itself the tuck (a radial
        # step) is edge-on and its triangle degenerate, which would leave the scroll open there.
        self.hub = (-0.12 * r0, 0.0)
        span = length / r_c / D
        # The face's outward normal (out of the band's end). The face lies on the band's end plane pushed
        # out along it by FACE_OUT -- parallel to it, so it stands as far proud at the bottom of the roll
        # as at the top -- then two stations back in the band (alpha, width scale, height scale): the
        # roll's full size most of the way back (a short cylinder lying across the band, as the sheet
        # draws it), then back in the band, as wide but sunk toward the root, so the roll runs back into
        # its strand -- square from above, never a point.
        self.fn = mul(tangent(end), -float(back))
        self.stations = [(end, 1.0, 1.0), (end + back * span * 0.6, 0.97, 0.95), (end + back * span * 1.45, 0.9, 0.4)]

    def point(self, station: int, uv: tuple[float, float]) -> Vec:
        a, su, sv = self.stations[station]
        bu, bv = self.root
        u = bu + su * (uv[0] - bu)
        v = bv + sv * (uv[1] - bv)
        p = polar(a, self.r_c + u, max(self.v_c + v, 0.0))
        return add(p, mul(self.fn, FACE_OUT)) if station == 0 else p

    def on_face(self, uv: tuple[float, float], lift: float) -> Vec:
        """A point on the face's plane (lift > 0: off it, outward)."""
        return add(polar(self.end, self.r_c + uv[0], max(self.v_c + uv[1], 0.0)), mul(self.fn, FACE_OUT + lift))

    def volume(self) -> tuple[Volume, list[list[int]]]:
        vol = Volume()
        rings, centres = [], []
        for k in range(len(self.stations)):
            w = 0.0095 if k < 2 else 0.006
            rings.append([vol.vert(self.point(k, uv), w) for uv in self.outline])
            if k in (0, len(self.stations) - 1):
                centres.append(vol.vert(self.point(k, self.hub), w))
        n = OUTLINE_N
        for a, b in zip(rings, rings[1:]):
            for j in range(n):
                k = (j + 1) % n
                emit(vol.mesh, a[j], a[k], b[k])
                emit(vol.mesh, a[j], b[k], b[j])
        first, last = rings[0], rings[-1]
        for j in range(n):
            k = (j + 1) % n
            emit(vol.mesh, centres[0], first[k], first[j])
            emit(vol.mesh, centres[-1], last[j], last[k])
        vol.orient_outward()
        return vol, rings


def volutes() -> list[Volute]:
    return [
        # the head: outer (bigger) and inner, their faces at the head's end
        Volute(HEAD, +1, 0.350, 0.050, 0.075, 0.130),
        Volute(HEAD, +1, 0.262, 0.042, 0.062, 0.112),
        # the tail: where the inner strands have stopped (their end slants from INNER_END - 4 to
        # INNER_END + 2, so the faces stand on the plane at INNER_END + 2, clear of all of it), the outer
        # strand running on beside them
        Volute(INNER_END + 2.0, -1, 0.322, 0.046, 0.068, 0.118),
        Volute(INNER_END + 2.0, -1, 0.248, 0.039, 0.056, 0.100),
    ]


def volute_face(ink: Mesh, v: Volute) -> None:
    """On the face: an ink backing BACKING behind it, larger by the contour's weight (the outline the hull
    cannot draw where the band's end face is right behind the scroll), parallel to the band's end and
    0.005 clear of it; the ink spiral from the tuck to the eye, SPIRAL_LIFT off the face. No pale on the
    face: the pale is the cap on the roll's top, set back from the face's edge."""
    fn = v.fn
    rim = []
    for u, w in v.outline:
        rho = math.hypot(u, w)
        f = (rho + 0.009) / max(rho, 1e-9)
        rim.append(ink.vert(v.on_face((u * f, w * f), -BACKING)))
    c = ink.vert(v.on_face(v.hub, -BACKING))
    for j in range(OUTLINE_N):
        ink.tri(c, rim[j], rim[(j + 1) % OUTLINE_N], fn)
    # the spiral line: from the tuck, just inside the outer turn, in to the eye
    turns = 1.3
    steps = 10
    lefts, rights = [], []
    for i in range(steps):
        s = i / (steps - 1)
        psi = 2 * math.pi * turns * s
        rho = v.r0 * (1.0 - TUCK) * (1.0 - 0.72 * s) + 0.002
        theta = THETA0 * D - psi
        d = (math.cos(theta), math.sin(theta))
        w = 0.0078 * (1.0 - 0.3 * s) if s < 0.95 else 0.009
        p = (rho * d[0], rho * d[1])
        lefts.append(ink.vert(v.on_face((p[0] + d[0] * w / 2, p[1] + d[1] * w / 2), SPIRAL_LIFT)))
        rights.append(ink.vert(v.on_face((p[0] - d[0] * w / 2, p[1] - d[1] * w / 2), SPIRAL_LIFT)))
    for i in range(steps - 1):
        ink.tri(lefts[i], rights[i], rights[i + 1], fn)
        ink.tri(lefts[i], rights[i + 1], lefts[i + 1], fn)


def volute_cap(core: Mesh, vol: Volume, rings: list[list[int]], v: Volute) -> None:
    """The pale cap over the top of the roll: from CAP_FROM behind the face to CAP_TO, round the crest
    (CAP_PHI), lifted 0.003 off the roll. Set back from the face, a band of green parts it from the
    face's ink edge, so no pale-ink-pale stripes stack on the top of the scroll."""
    verts = vol.mesh.verts
    crest = [k for k in range(OUTLINE_N) if CAP_PHI[0] - 1e-6 <= 360.0 * k / (OUTLINE_N - 1) <= CAP_PHI[1] + 1e-6]
    a0, a1 = v.point(0, (0.0, 0.0)), v.point(1, (0.0, 0.0))
    length = math.dist(a0, a1)
    rows = []
    for dist in (CAP_FROM, CAP_TO):
        f = dist / length
        axis_pt = add(mul(a0, 1 - f), mul(a1, f))
        row = []
        for k in crest:
            p = add(mul(verts[rings[0][k]], 1 - f), mul(verts[rings[1][k]], f))
            n = norm(sub(p, axis_pt))
            row.append((core.vert(add(p, mul(n, 0.003))), n))
        rows.append(row)
    for k in range(len(crest) - 1):
        (p0, n0), (p1, _), (q1, _), (q0, _) = rows[0][k], rows[0][k + 1], rows[1][k + 1], rows[1][k]
        core.tri(p0, p1, q1, n0)
        core.tri(p0, q1, q0, n0)


# --- the whips ------------------------------------------------------------------------------------

WHIP_INK = 0.006  # the whips' contour, root to tip (13.2: 0.006, 0.14 stud; never under 0.1 stud)


class Whip:
    """A whip out of the tail strand's end face: its root buried in the strand, its lane (control points
    (alpha, r, y)) fanning out and running on along the arc, then a hook turning inward in the page
    (`hook` = (radius, degrees)) and an open curl that rises in a plane tilted `tilt` degrees off the
    page about the hook's heading, leaning back along the arc (away from the thrower) and so facing his
    camera; its radius falls from r0 to r1 over `turn` degrees, so the tip curls inside its own turn."""

    def __init__(self, root, lane, radius, hook, curl, segs) -> None:
        self.root, self.lane, self.radius, self.hook, self.curl, self.segs = root, lane, radius, hook, curl, segs

    def path(self) -> list[Vec]:
        dense = catmull([polar(a, r, y) for a, r, y in self.lane], 16)
        end = dense[-1]
        t0 = sub(dense[-1], dense[-4])
        t0 = norm((t0[0], 0.0, t0[2]))
        inward = mul(radial(angle_of(end)), -1.0)
        side = norm(sub(inward, mul(t0, dot(inward, t0))))
        rb, turn_deg = self.hook
        centre = add(end, mul(side, rb))
        hook = []
        for i in range(1, 13):
            th = turn_deg * D * i / 12
            hook.append(add(centre, add(mul(side, -rb * math.cos(th)), mul(t0, rb * math.sin(th)))))
        e1 = norm(add(mul(t0, math.cos(turn_deg * D)), mul(side, math.sin(turn_deg * D))))
        back = (-e1[2], 0.0, e1[0])
        if dot(back, t0) > 0:
            back = mul(back, -1.0)
        c = self.curl
        e2 = norm(add(mul(back, math.cos(c["tilt"] * D)), mul(UP, math.sin(c["tilt"] * D))))
        p1 = hook[-1]
        r0, r1 = c["r0"], c["r1"]
        mid = add(p1, mul(e2, r0))
        curl = []
        n = 48
        for i in range(1, n + 1):
            th = c["turn"] * D * i / n
            rho = r0 + (r1 - r0) * (i / n) ** 0.85
            curl.append(add(mid, add(mul(e2, -rho * math.cos(th)), mul(e1, rho * math.sin(th)))))
        return dense + hook + curl

    def centres(self) -> list[Vec]:
        line = Polyline(self.path())
        return [polar(*self.root)] + [line.at(i / self.segs) for i in range(self.segs + 1)]

    def volume(self) -> tuple[Volume, set[int], list[int]]:
        """A tapered three-sided tendril along the centres, closed: a root cap and its first ring buried in
        the strand (their hull is not drawn: the whip's outline starts where it leaves the strand's end,
        closed there by a cap on its second ring), and a single-vertex tip; its section carried along by
        parallel transport, squashed to 0.7 high. Returns the volume, the buried vertices and the ring
        where the outline starts."""
        vol = Volume()
        centres = self.centres()
        segs = len(centres) - 1
        acc = [0.0]
        for p, q in zip(centres, centres[1:]):
            acc.append(acc[-1] + math.dist(p, q))
        total = acc[-1]
        tangents = [norm(sub(centres[min(i + 1, segs)], centres[max(i - 1, 0)])) for i in range(segs + 1)]
        side = norm(cross(tangents[0], UP))
        rings = []
        for i in range(segs):
            along = tangents[i]
            side = norm(sub(side, mul(along, dot(side, along))))
            up = norm(cross(side, along))
            s = acc[i] / total
            r = self.radius * (1.0 - s) ** 0.75 + 0.0028
            ring = []
            for k in range(3):
                ang = math.pi / 2 + 2 * math.pi * k / 3
                q = add(centres[i], add(mul(up, 0.7 * r * math.sin(ang)), mul(side, r * math.cos(ang))))
                ring.append(vol.vert((q[0], max(q[1], FLOOR_CLEARANCE), q[2]), WHIP_INK + 0.15 * r))
            rings.append(ring)
        tip = vol.vert(centres[-1], WHIP_INK)
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
        return vol, set(first), rings[1]


def whips() -> list[Whip]:
    """Three whips out of the tail strand's end face, side by side across it: they fan apart (the outer
    peeling outward, the inner inward) with clear gaps, run on along the arc -- the outer the longest,
    the inner the shortest -- then each hooks inward and rises into an open curl leaning back along the
    arc, the outer one the tallest. Never into the opening (|alpha| <= 120) nor past r 0.5."""
    root = TAIL - 2.5
    return [
        # outer: peels outward along the rim, the longest and the tallest
        Whip((root, 0.437, 0.024),
             [(TAIL + 2.0, 0.443, 0.024), (82.0, 0.456, 0.022), (92.0, 0.461, 0.028), (104.0, 0.456, 0.042), (112.0, 0.446, 0.056)],
             0.017, (0.020, 70.0), {"tilt": 66.0, "r0": 0.070, "r1": 0.016, "turn": 275.0}, 24),
        # middle: runs on along the arc
        Whip((root, 0.401, 0.016),
             [(TAIL + 2.0, 0.399, 0.016), (82.0, 0.394, 0.018), (91.0, 0.384, 0.028), (101.0, 0.370, 0.044)],
             0.015, (0.019, 60.0), {"tilt": 56.0, "r0": 0.054, "r1": 0.014, "turn": 270.0}, 20),
        # inner: peels inward, the shortest, its hook curling back low over the page
        Whip((root, 0.371, 0.011),
             [(TAIL + 2.0, 0.360, 0.012), (82.0, 0.336, 0.015), (86.0, 0.318, 0.022), (92.0, 0.296, 0.030)],
             0.013, (0.017, 50.0), {"tilt": 34.0, "r0": 0.044, "r1": 0.011, "turn": 250.0}, 17),
    ]


# --- the contour ----------------------------------------------------------------------------------


def hull(vol: Volume, into: Mesh, skip: set[int] | None = None, start: list[int] | None = None) -> None:
    """strokes.inverted_hull, with each vertex pushed along the average of its faces' UNIT normals (not
    area-weighted: the band's wide floor face would otherwise point every edge vertex at the page and
    leave the band with no outline on the page), and a vertex on the page pushed straight out along it,
    so the outline round the foot is the full weight. A triangle touching a `skip` vertex (a whip's root,
    buried in the strand) is not drawn, and the hull is closed across the `start` ring instead, wound so
    that no one looks into an open tube of ink from the root's side."""
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        n = norm(face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c]))
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        n = norm(acc[i])
        if p[1] <= 1e-6:
            flat = (n[0], 0.0, n[2])
            if flat[0] ** 2 + flat[2] ** 2 > 1e-8:
                n = norm(flat)
        q = add(p, mul(n, vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR_CLEARANCE), q[2]))
    for a, b, c in mesh.tris:
        if skip and (a in skip or b in skip or c in skip):
            continue
        corners = [into.verts[v + base] for v in (a, b, c)]
        if all(q[1] <= FLOOR_CLEARANCE for q in corners) and sliver(*corners):
            continue
        emit(into, a + base, c + base, b + base)
    if start:
        a, b, c = (v + base for v in start)
        centre = tuple(sum(mesh.verts[v][k] for v in start) / 3 for k in range(3))
        root = tuple(sum(mesh.verts[v][k] for v in skip) / len(skip) for k in range(3))
        n = face_normal(into.verts[a], into.verts[b], into.verts[c])
        # an inverted hull faces in: across its first ring, away from the buried root
        if dot(n, sub(centre, root)) < 0:
            b, c = c, b
        emit(into, a, b, c)


# --- strips laid on the band's top -----------------------------------------------------------------


def band_strip(mesh: Mesh, angles, r_of, w_of, lift: float) -> None:
    """A strip on the band's top at radius r_of(alpha), width w_of(alpha) across, lifted along the facet
    it lies on: its samples are the band's own ring angles, so between two of them it lies on one facet."""
    lefts, rights, normals = [], [], []
    for a in angles:
        r = r_of(a)
        w = w_of(a)
        _, seg, _ = band_top(a, r)
        sec = section(a)
        (r0, y0), (r1, y1) = sec[seg], sec[seg + 1]
        along = norm((r1 - r0, y1 - y0, 0.0))  # in (r, y)
        n2 = (-along[1], along[0])  # the facet's normal in (r, y), pointing up/in
        y, _, _ = band_top(a, r)
        rad = radial(a)
        n = norm(add(mul(rad, n2[0]), (0.0, n2[1], 0.0)))
        centre = add(polar(a, r, y), mul(n, lift))
        across = norm(add(mul(rad, along[0]), (0.0, along[1], 0.0)))
        lefts.append(mesh.vert(add(centre, mul(across, -w / 2))))
        rights.append(mesh.vert(add(centre, mul(across, w / 2))))
        normals.append(n)
    for i in range(len(angles) - 1):
        mesh.tri(lefts[i], rights[i], rights[i + 1], normals[i])
        mesh.tri(lefts[i], rights[i + 1], lefts[i + 1], normals[i])


def span_angles(angles: list[float], lo: float, hi: float, extra: tuple[float, ...] = ()) -> list[float]:
    """The band's ring angles strictly inside (lo, hi), none within a degree of either end (no slivers)."""
    inside = sorted({a for a in list(angles) + list(extra) if lo + 1.0 < a < hi - 1.0})
    return [lo] + inside + [hi]


def taper(lo: float, hi: float, w: float, head: float = 0.15, tail: float = 0.45, floor: float = 0.0):
    def f(a: float) -> float:
        s = (a - lo) / (hi - lo)
        k = min(1.0, s / head) if head > 0 else 1.0
        k = min(k, 1.0 if s < 1 - tail else max(floor, (1 - s) / tail))
        return w * max(k, floor)

    return f


# --- the pale and the ink --------------------------------------------------------------------------


def lip_line(core: Mesh, angles: list[float]) -> None:
    """The pale line along the lip's flat top, from the head's end down the tail strand."""
    lo, hi = HEAD + 0.6, TAIL - 2.0
    span = span_angles(angles, lo, hi)
    width_at = taper(lo, hi, 0.0115, head=0.0, tail=0.3, floor=0.3)

    def r_of(a: float) -> float:
        sec = section(a)
        return (sec[3][0] + sec[4][0]) / 2

    band_strip(core, span, r_of, width_at, 0.003)


HEAD_STREAKS = (
    # (radius, from, to): 13.2's two pale streaks on the head's top, 0.018 wide and about 0.12 long,
    # clear of the head volutes' rolls (they run back to -92) and of the flow lines
    (0.338, -88.0, -68.0),
    (0.258, -87.0, -61.0),
)


def head_streaks(core: Mesh, angles: list[float]) -> None:
    for r, lo, hi in HEAD_STREAKS:
        band_strip(core, span_angles(angles, lo, hi), lambda a, r=r: r, taper(lo, hi, 0.018, 0.3, 0.5), 0.003)


FLOW = (
    # (control points (alpha, r) eased between, width): five uneven lines that each drift 0.02 to 0.04
    # across the band as they go, toward or away from their neighbours -- never parallel -- thick where
    # they leave a volute, lost along the arc
    (((-104.0, 0.303), (-60.0, 0.290), (-20.0, 0.280), (10.0, 0.286)), 0.0095),  # out of the head volutes' gap
    (((-108.0, 0.416), (-64.0, 0.437), (-20.0, 0.428), (20.0, 0.404)), 0.0090),  # up the lip's ramp from the head's end, then down it
    (((-32.0, 0.330), (8.0, 0.316), (40.0, 0.298), (66.0, 0.292)), 0.0095),  # into the tail volutes' gap
    (((8.0, 0.358), (40.0, 0.372), (74.0, 0.396)), 0.0085),  # out along the tail strand, drifting out
    (((-56.0, 0.232), (-20.0, 0.254), (24.0, 0.238)), 0.0080),  # a free one, on the inner strand
)


def flow_lines(ink: Mesh, angles: list[float]) -> None:
    for ctrl, w in FLOW:
        lo, hi = ctrl[0][0], ctrl[-1][0]
        if lo < -100:
            f = taper(lo, hi, w, head=0.04, tail=0.3, floor=0.35)  # out of a volute, lost along the arc
        elif hi > 60:
            f = taper(lo, hi, w, head=0.3, tail=0.05, floor=0.35)  # out of nothing, into a volute
        else:
            f = taper(lo, hi, w, head=0.25, tail=0.3, floor=0.35)
        mids = tuple(a for a, _ in ctrl[1:-1])
        band_strip(ink, span_angles(angles, lo, hi, mids), lambda a, ctrl=ctrl: cosine_curve(list(ctrl), a), f, 0.0035)


# --- assembly --------------------------------------------------------------------------------------

_MESHES: dict[str, Mesh] = {}


def _build() -> dict[str, Mesh]:
    if _MESHES:
        return _MESHES
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    band, angles, _ = band_volume()
    solids: list[tuple[Volume, set[int] | None, list[int] | None]] = [(band, None, None)]
    built = []
    for v in volutes():
        vol, rings = v.volume()
        solids.append((vol, None, None))
        built.append((v, vol, rings))
    solids += [w.volume() for w in whips()]
    for vol, skip, start in solids:
        body.merge(vol.mesh)
        hull(vol, ink, skip, start)
    lip_line(core, angles)
    head_streaks(core, angles)
    for v, vol, rings in built:
        volute_cap(core, vol, rings, v)
        volute_face(ink, v)
    flow_lines(ink, angles)
    _drop_unused(ink)
    # OuterDiameter = 1: the furthest ink in the floor plane exactly 0.5 from the pivot.
    reach = max(math.hypot(x, z) for mesh in (body, core, ink) for x, _, z in mesh.verts)
    factor = 0.5 / reach
    c, s = math.cos(PRE_TURN), math.sin(PRE_TURN)
    for mesh in (body, core, ink):
        out = []
        for x, y, z in mesh.verts:
            x, y, z = x * factor, y * factor, z * factor
            out.append((x * c + z * s, max(y, 0.0), -x * s + z * c))
        mesh.verts = out
    _MESHES.update(body=body, core=core, ink=ink)
    return _MESHES


def _drop_unused(mesh: Mesh) -> None:
    """Drops the vertices no triangle uses (the hull of a whip's buried root)."""
    used = sorted({i for t in mesh.tris for i in t})
    if len(used) == len(mesh.verts):
        return
    remap = {old: new for new, old in enumerate(used)}
    mesh.verts = [mesh.verts[i] for i in used]
    mesh.tris = [tuple(remap[i] for i in t) for t in mesh.tris]


def _meta(seed: int) -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def gust_body() -> tuple[Mesh, dict]:
    return _build()["body"], _meta(SEED)


def gust_crest() -> tuple[Mesh, dict]:
    return _build()["core"], _meta(SEED + 1)


def gust_ink() -> tuple[Mesh, dict]:
    return _build()["ink"], _meta(SEED + 2)
