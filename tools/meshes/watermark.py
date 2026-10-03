"""The Watermark's mould (Filigrane, "la Forme"): a papermaker's mould in gold wire laid flat on the page.

Drawn after the developer's in-game shot (docs/vfx/watermark/ref-1.jpg), rectified to a top view by a
camera fitted to the rope's ellipse and the rosette's centre:
  - a twisted two-strand rope at the server's Radius: 36 long slanted strands lying on the floor of the
    rope's hull, each with a roof whose ridge runs down the rope's middle (one crown line round the
    rim) and a pale streak; the floor shows between them as the dark line between two strands;
  - eight volutes in four C-scrolls: a front pair and a back pair, each volute a coil swung out onto
    a big round turn whose free end hooks toward its twin on the axis, and a C down each side whose
    spine runs along the rope and whose two ends coil inward toward the rosette. Every big turn and
    each side spine is a double wire (a second wire peels off inside it, runs ~290 degrees beside it
    and merges back);
  - a rosette of five double drops round a ring, 45 granulation domes laid in arcs in its five gaps,
    and four eyelets between the rosette and the volutes.
Vellum everywhere between the wires, between the turns of each coil too; a pale line on every wire.

Roblox space: X right, Y up, forward -Z; the thrower stands at +Z, Offset studs behind the centre.
Built in studs at the server's Radius (12), then scaled once so the rope's outer ink sits exactly 0.5
from the centre (OuterDiameter); the pivot is on the page under the centre and nothing is under it.
The highest point is the rope's crown, 0.30 stud (K9: at most 0.04 of the diameter, 0.96).

Three meshes, one tone each, stacked GAP apart:
  - pigment (WatermarkWire), at Y_GOLD: every wire as a flat strip, the rope's strands as low roofs,
    the beads as six-sided domes;
  - core (WatermarkGleam), at Y_PALE: a thin pale line inside every wire, a streak on each strand of
    the rope and a fleck over each bead -- always inside the gold, never at its edge;
  - ink (WatermarkInk), at Y_INK: one strip under each wire or pair of wires (its contour, INK past
    the gold, and the MID line between a pair), the floor of the rope's hull (ROPE_HULL past both
    edges), the floor of each bead's hull.

Smoothness, the price of the 1800-triangle cap: no two segments of a big turn or spine meet at more than
19.5 degrees, of a petal's round end at more than 28, of a coil or a hook at more than 50; the ring has 16 sides,
each eyelet 8, each bead 6, the rim 36. At those steps no point of a wire lies more than 0.19 stud from where
the first, finer drawing put it.

The press. Every layer is GAP (0.035 stud) over the one under it, and the strands' streaks and the
bead flecks DETAIL_LIFT over their own faces. The timeline scales Y about the page; with Y kept at or
over PRESS_FLOOR of rest (0.6) every gap stays at or over 0.021 stud. Under it -- the R5 retract to
Y 0.02 -- the ink and the gleam must have faded first, or the gold z-fights with them.

Budget: WatermarkWire 1774, WatermarkGleam 447, WatermarkInk 1222 -- 3443 a cast, each volume under the 1800
of a big body and the cast under the 3500 target. The first drawing's finer steps cost 2777 / 685 / 1973.
"""

from __future__ import annotations

import math

from strokes import Mesh, Rng, fbm

SEED = 6113
UP = (0.0, 1.0, 0.0)

RADIUS = 12.0  # studs: the server's Radius; the rope's outer ink lands here

# Heights over the page (studs; the final scale maps 12 studs to 0.5, and the runtime maps 0.5 back).
GAP = 0.035
Y_INK = 0.06
Y_GOLD = Y_INK + GAP
Y_PALE = Y_GOLD + GAP
DETAIL_LIFT = GAP + 0.005  # the rope's grooves and streaks over its facets, a bead's fleck over its apex
FLECK_LIFT = 0.025  # a bead's fleck over its lit face, along the face's normal
KERB_TOP = 0.30  # the rope's outer ink kerb: stands to crown height so the far rim shows ink from low
Y_RIDGE = 0.30  # the rope's ridge
Y_BEAD = Y_GOLD + 0.075  # a bead's apex: a low dome, never a spike seen from low

# Widths (studs): gold, and the ink each side of it.
INK = 0.10  # the contour of every wire (the bible's floor)
MID = 0.10  # the dark line between two wires of a pair: each wire's own contour, shared
W_LOOP = 0.36  # the big turns (the plein)
W_COMP = 0.3  # the wire that peels off inside a big turn
W_COIL = 0.24  # a coil into its eye (the delie)
W_PETAL = 0.28
W_PETAL_IN = 0.24
W_RING = 0.28
W_EYELET = 0.22
PALE = 0.13  # a pale line's width, as a share of its wire's gold

# Sampling: the sharpest turn between two segments, and the longest segment.
# Each is (the greedy limit, the hard limit): a step over the hard one is split until none is.
BIG = (math.radians(18.0), math.radians(19.5))  # the big turns and spines
TIGHT = (math.radians(26.0), math.radians(28.0))  # the round ends of the petals
COIL = (math.radians(45.0), math.radians(50.0))  # the coils into the eyes and the hooks at the ends of the volutes
MAX_CHORD = 1.6

# --- small vector helpers (2D in the page: (x, z)) -------------------------------------------------


def v2add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def v2sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def v2mul(a, k):
    return (a[0] * k, a[1] * k)


def v2len(a):
    return math.hypot(a[0], a[1])


def v2unit(a):
    n = v2len(a) or 1.0
    return (a[0] / n, a[1] / n)


def lerp2(a, b, f):
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)


def smooth(e0, e1, x):
    u = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def turn_at(a, b, c):
    """The unsigned turn at b between a->b and b->c."""
    u, v = v2sub(b, a), v2sub(c, b)
    if v2len(u) < 1e-12 or v2len(v) < 1e-12:
        return 0.0
    return abs(math.atan2(u[0] * v[1] - u[1] * v[0], u[0] * v[0] + u[1] * v[1]))


def arc_lengths(pts):
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + v2len(v2sub(pts[i], pts[i - 1])))
    return acc


# --- sampling ----------------------------------------------------------------------------------------


def resample(dense, limit_at, max_chord=MAX_CHORD):
    """The kept indices of a dense open path: each segment as long as it can be while the path it
    replaces turns no more than the greedy limit there; then any sample where two segments meet at
    more than the hard limit has the longer of its two segments split, until none does."""
    n = len(dense)
    acc = arc_lengths(dense)
    keep = [0]
    k = 0
    while k < n - 1:
        j = k + 1
        turned = 0.0
        while j < n - 1:
            t = turn_at(dense[j - 1], dense[j], dense[j + 1])
            if turned + t > limit_at(j)[0] or acc[j + 1] - acc[k] > max_chord:
                break
            turned += t
            j += 1
        keep.append(j)
        k = j
    for _ in range(50):
        split = set()
        for m in range(1, len(keep) - 1):
            a, b, c = keep[m - 1], keep[m], keep[m + 1]
            if turn_at(dense[a], dense[b], dense[c]) > limit_at(b)[1]:
                lo, hi = (a, b) if acc[b] - acc[a] >= acc[c] - acc[b] else (b, c)
                if hi - lo > 1:
                    split.add((lo + hi) // 2)
        if not split:
            break
        keep = sorted(set(keep) | split)
    return keep


def mitred(pts, closed):
    """Each sample's normal across the path, (-t_z, t_x), scaled so an offset along it keeps its
    distance from both segments it joins (a mitre, capped at 2.2)."""
    count = len(pts)
    out = []
    for i in range(count):
        if closed:
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % count]
        else:
            a = pts[i - 1] if i > 0 else None
            b = pts[i]
            c = pts[i + 1] if i < count - 1 else None
        normals = []
        for p, q in ((a, b), (b, c)):
            if p is None or q is None:
                continue
            t = v2unit(v2sub(q, p))
            normals.append((-t[1], t[0]))
        n = v2unit(v2add(normals[0], normals[-1]))
        cos = max(n[0] * normals[0][0] + n[1] * normals[0][1], 1.0 / 2.2)
        out.append(v2mul(n, 1.0 / cos))
    return out


# --- strips on the page ------------------------------------------------------------------------------


def strip(mesh: Mesh, pts, normals, lo, hi, y: float, closed=False) -> int:
    """A flat strip between offsets lo[i] and hi[i] along each sample's normal, every face up."""
    a = [mesh.vert((p[0] + n[0] * o, y, p[1] + n[1] * o)) for p, n, o in zip(pts, normals, lo)]
    b = [mesh.vert((p[0] + n[0] * o, y, p[1] + n[1] * o)) for p, n, o in zip(pts, normals, hi)]
    count = len(pts)
    segments = count if closed else count - 1
    for i in range(segments):
        j = (i + 1) % count
        mesh.tri(a[i], b[i], a[j], UP)
        mesh.tri(b[i], b[j], a[j], UP)
    return segments


def pale_line(core: Mesh, pts, centre, widths, us, u0, u1, closed=False) -> None:
    """The pale line of one wire between u0 and u1: PALE of its gold, thinning to 0.3 of that at both
    ends. It is a strip on every other sample of its wire -- a triangle a sample, as half a strip --
    so its corners turn twice the wire's step; thin and well inside the gold (the chord leaves the
    wire's middle by at most 0.06 stud), they do not show, and its two edges stay parallel."""
    idx = [i for i, u in enumerate(us) if u0 - 1e-9 <= u <= u1 + 1e-9]
    if closed and u1 < u0:
        idx = [i for i, u in enumerate(us) if u >= u0] + [i for i, u in enumerate(us) if u <= u1]
    if len(idx) < 3:
        return
    keep = idx[::2] if (len(idx) - 1) % 2 == 0 else idx[::2] + [idx[-1]]
    span = len(keep) - 1
    lp = [pts[i] for i in keep]
    ln = mitred(lp, False)
    half = [PALE * widths[i] / 2.0 * (0.3 + 0.7 * max(0.0, math.sin(math.pi * k / span)) ** 0.5) for k, i in enumerate(keep)]
    c = [centre[i] for i in keep]
    strip(core, lp, ln, [a - h for a, h in zip(c, half)], [a + h for a, h in zip(c, half)], Y_PALE)


class Comp:
    """A second wire laid inside a big turn, on `side` of the main one, between u0 and u1 of it: it
    peels off the main wire, runs MID from it, and merges back (both ends hidden under the main gold)."""

    def __init__(self, u0, u1, side, width=W_COMP, peel=0.12):
        self.u0, self.u1, self.side, self.width, self.peel = u0, u1, side, width, peel


class Wire:
    """One gold wire lying on the page: its samples, the share u (0..1) of its length at each, a width
    profile, an optional closed loop, the wires that run beside it, and where its pale line runs."""

    def __init__(self, pts, us, width, closed=False, comps=(), gleam=(0.15, 0.85), comp_gleam=(0.25, 0.75)):
        self.pts, self.us, self.width, self.closed = pts, us, width, closed
        self.comps = list(comps)
        self.gleam = gleam
        self.comp_gleam = comp_gleam

    def build(self, body: Mesh, core: Mesh, ink: Mesh) -> dict:
        pts, us, closed = self.pts, self.us, self.closed
        normals = mitred(pts, closed)
        widths = [self.width(u) for u in us]
        halves = [w / 2.0 for w in widths]
        zero = [0.0] * len(pts)
        strip(body, pts, normals, [-h for h in halves], halves, Y_GOLD, closed)
        ink_lo = [-h - INK for h in halves]
        ink_hi = [h + INK for h in halves]
        stats = {"samples": len(pts), "gold_samples": len(pts)}
        for comp in self.comps:
            # A comp over a whole closed wire (an inner drop) is closed too, and its own u is the wire's.
            full = closed and comp.u0 <= 0.0 and comp.u1 >= 1.0
            idx = [i for i, u in enumerate(us) if comp.u0 <= u <= comp.u1]
            if len(idx) < 3:
                continue
            centre, lo, hi = [], [], []
            for i in idx:
                t = us[i] if full else (us[i] - comp.u0) / (comp.u1 - comp.u0)
                p = 1.0 if full else smooth(0.0, comp.peel, t) * smooth(1.0, 1.0 - comp.peel, t)
                w = comp.width
                c = comp.side * (halves[i] - w / 2.0 + (MID + w) * p)
                centre.append(c)
                lo.append(c - w / 2.0)
                hi.append(c + w / 2.0)
                if comp.side > 0:
                    ink_hi[i] = max(ink_hi[i], c + w / 2.0 + INK)
                else:
                    ink_lo[i] = min(ink_lo[i], c - w / 2.0 - INK)
            cp = [pts[i] for i in idx]
            cn = [normals[i] for i in idx]
            strip(body, cp, cn, lo, hi, Y_GOLD, full)
            stats["gold_samples"] += len(idx)
            ct = [us[i] if full else (us[i] - comp.u0) / (comp.u1 - comp.u0) for i in idx]
            pale_line(core, cp, centre, [comp.width] * len(idx), ct, self.comp_gleam[0], self.comp_gleam[1])
        # The contour: under the whole wire (or pair), INK past every gold edge. A free end is capped:
        # its last ink sample is moved on past the gold along the path, a little narrower.
        ipts = list(pts)
        if not closed:
            for end, nxt in ((0, 1), (len(pts) - 1, len(pts) - 2)):
                t = v2unit(v2sub(pts[end], pts[nxt]))
                ipts[end] = v2add(pts[end], v2mul(t, INK * 0.9))
                ink_lo[end] *= 0.75
                ink_hi[end] *= 0.75
        strip(ink, ipts, normals, ink_lo, ink_hi, Y_INK, closed)
        if self.gleam is not None:
            pale_line(core, pts, zero, widths, us, self.gleam[0], self.gleam[1], closed)
        return stats


def open_wire(dense, width, limits, **kw) -> Wire:
    """Samples a dense open path: `limits` is a list of (u_end, turn limit), in order."""
    acc = arc_lengths(dense)
    total = acc[-1]

    def limit_at(j):
        u = acc[j] / total
        for u_end, lim in limits:
            if u <= u_end:
                return lim
        return limits[-1][1]

    keep = resample(dense, limit_at)
    return Wire([dense[i] for i in keep], [acc[i] / total for i in keep], width, **kw)


def closed_wire(pts, width, **kw) -> Wire:
    acc = arc_lengths(pts + [pts[0]])
    return Wire(pts, [a / acc[-1] for a in acc[:-1]], width, closed=True, **kw)


# --- the volutes ---------------------------------------------------------------------------------------


def coil_path(eye, centre, R, a_end, loop, sense, r0=0.18, pitch=0.56, turns=1.5, blend=math.radians(130), wobble=0.0, seed=0):
    """A volute from its eye outward: an Archimedean coil round the eye (`turns` turns, `pitch` apart,
    so there is vellum between them), a swing out onto the big turn round `centre` (radius R) over
    `blend` radians, then `loop` radians of the big turn, ending at angle `a_end` about `centre`.
    Angles are (cos a, sin a) in the page (x, z); `sense` -1 mirrors the travel. Dense: one degree.
    Returns the path and the indices where the coil and the swing end."""
    coil = 2.0 * math.pi * turns
    total = coil + blend + loop
    a0 = a_end - sense * total
    pts = []
    steps = int(total / math.radians(1.0))
    k_coil = k_blend = 0
    for k in range(steps + 1):
        th = total * k / steps
        a = a0 + sense * th
        u = (math.cos(a), math.sin(a))
        r_coil = r0 + pitch * th / (2.0 * math.pi)
        s = smooth(coil, coil + blend, th)
        c = lerp2(eye, centre, s)
        rr = r_coil + (R - r_coil) * s
        rr *= 1.0 + wobble * (fbm(th * 0.35, 0.3, seed) * 2.0 - 1.0) * s
        pts.append(v2add(c, v2mul(u, rr)))
        if th <= coil:
            k_coil = k
        if th <= coil + blend:
            k_blend = k
    return pts, k_coil, k_blend


def hook(start, tangent, heading, length, radius, sense, sweep):
    """A free end: a short run that bends smoothly from the path's `tangent` onto `heading`, then a
    curl of `sweep` radians tightening from `radius`, turning the way `sense` says (+1 clockwise seen
    from above). Dense: about one degree."""
    h = v2unit(heading)
    p = v2add(start, v2mul(h, length))
    pts = hermite(start, v2unit(tangent), p, h, 40) + [p]
    right = (-h[1], h[0])
    centre = v2add(p, v2mul(right if sense > 0 else (-right[0], -right[1]), radius))
    a = math.atan2(p[1] - centre[1], p[0] - centre[0])
    steps = max(4, int(math.degrees(sweep)))
    for k in range(1, steps + 1):
        ang = a + sense * sweep * k / steps
        rad = radius * (1.0 - 0.35 * k / steps)
        pts.append((centre[0] + rad * math.cos(ang), centre[1] + rad * math.sin(ang)))
    return pts


def mirrored(wire: Wire, mx: bool, mz: bool) -> Wire:
    if not (mx or mz):
        return wire
    sx, sz = (-1.0 if mx else 1.0), (-1.0 if mz else 1.0)
    wire.pts = [(x * sx, z * sz) for x, z in wire.pts]
    # A mirror flips the travel's handedness, so a companion's side flips with it -- once per mirror.
    if mx != mz:
        for comp in wire.comps:
            comp.side = -comp.side
    return wire


def inside_side(pts, centre, i):
    """+1 when the normal (-t_z, t_x) at sample i points toward `centre`, else -1."""
    t = v2unit(v2sub(pts[i + 1], pts[i - 1]))
    n = (-t[1], t[0])
    d = v2sub(centre, pts[i])
    return 1 if n[0] * d[0] + n[1] * d[1] > 0 else -1


def u_of(dense, k):
    acc = arc_lengths(dense)
    return acc[k] / acc[-1]


def centre_volute(centre, R, eye_pull, seed: int, reach_axis: float = 0.35) -> Wire:
    """A front-right centre volute: coils out clockwise (seen from above) from its eye, swings onto the
    big turn, runs once round it and leaves its inner side (toward the axis) rising, into a hook that
    curls toward the axis, to meet its twin's. A second wire runs inside the big turn for ~290 degrees."""
    cx, cz = centre
    to_axis = v2unit((-cx, -cz))
    eye = v2add(centre, v2mul(to_axis, eye_pull))
    a_end = math.pi + 0.42
    loop = math.radians(325)
    path, k_coil, k_blend = coil_path(eye, centre, R, a_end, loop, +1, wobble=0.02, seed=seed)
    tangent = v2unit(v2sub(path[-1], path[-2]))
    end = path[-1]
    run = 0.6
    lean = max(0.0, min(0.6, (end[0] - reach_axis - 0.3) / run))
    heading = v2unit((tangent[0] - lean, tangent[1]))
    tail = hook(end, tangent, heading, run, 0.34, -1, math.radians(165))
    dense = path + tail
    u_coil = u_of(dense, k_coil)
    u_blend = u_of(dense, k_blend)
    u_loop = u_of(dense, len(path) - 1)

    def width(u):
        w = W_COIL + (W_LOOP - W_COIL) * smooth(u_coil, u_blend, u)
        return w * (0.72 + 0.28 * smooth(1.0, u_loop + 0.02, u))

    # The second wire: from 25 degrees before the swing ends to 30 degrees before the turn ends.
    per_deg = (u_loop - u_blend) / math.degrees(loop)
    comp = Comp(u_blend - 25 * per_deg, u_loop - 30 * per_deg, 0)
    wire = open_wire(dense, width, [(u_coil, COIL), (u_loop, BIG), (1.0, COIL)], comps=[comp], gleam=(0.2, 0.92))
    mid = min(range(1, len(wire.pts) - 1), key=lambda i: abs(wire.us[i] - (comp.u0 + comp.u1) / 2))
    comp.side = inside_side(wire.pts, centre, mid)
    return wire


def hermite(p0, t0, p1, t1, count):
    gap = v2len(v2sub(p1, p0))
    out = []
    for k in range(1, count):
        f = k / count
        h00 = 2 * f**3 - 3 * f**2 + 1
        h10 = f**3 - 2 * f**2 + f
        h01 = -2 * f**3 + 3 * f**2
        h11 = f**3 - f**2
        out.append(
            (
                h00 * p0[0] + h10 * gap * t0[0] + h01 * p1[0] + h11 * gap * t1[0],
                h00 * p0[1] + h10 * gap * t0[1] + h01 * p1[1] + h11 * gap * t1[1],
            )
        )
    return out


def side_c(top_centre, top_R, bot_centre, bot_R, seed: int) -> Wire:
    """The right side's C-scroll: from the back volute's eye it coils out clockwise onto its big turn,
    leaves it down along the rope as the spine, joins the front volute's big turn on its outer side and
    coils into that eye, clockwise still -- both ends curled toward the rosette. The second wire runs
    inside it from ~290 degrees up the back turn, down the spine, to ~290 degrees round the front turn."""
    t_eye = v2add(top_centre, v2mul(v2unit((-top_centre[0], -top_centre[1])), 0.55))
    b_eye = v2add(bot_centre, v2mul(v2unit((-bot_centre[0], -bot_centre[1])), 0.75))
    loop_t, loop_b = math.radians(315), math.radians(305)
    top, kt, kbt = coil_path(t_eye, top_centre, top_R, 0.2, loop_t, +1, wobble=0.02, seed=seed)
    bot, kb, kbb = coil_path(b_eye, bot_centre, bot_R, -0.3, loop_b, -1, wobble=0.02, seed=seed + 7)
    bot = list(reversed(bot))
    t0 = v2unit(v2sub(top[-1], top[-2]))
    t1 = v2unit(v2sub(bot[1], bot[0]))
    gap = v2len(v2sub(bot[0], top[-1]))
    dense = top + hermite(top[-1], t0, bot[0], t1, max(8, int(gap / 0.05))) + bot
    n = len(dense)
    u0 = u_of(dense, kt)
    u_tb = u_of(dense, kbt)
    u_te = u_of(dense, len(top) - 1)
    u_bs = u_of(dense, n - len(bot))
    u_bb = u_of(dense, n - 1 - kbb)
    u1 = u_of(dense, n - 1 - kb)

    def width(u):
        return W_COIL + (W_LOOP - W_COIL) * smooth(u0, u_tb, u) * smooth(u1, u_bb, u)

    per_t = (u_te - u_tb) / math.degrees(loop_t)
    per_b = (u_bb - u_bs) / math.degrees(loop_b)
    comp = Comp(u_te - 290 * per_t, u_bs + 290 * per_b, 0, peel=0.07)
    wire = open_wire(dense, width, [(u0, COIL), (u1, BIG), (1.0, COIL)], comps=[comp], gleam=(0.12, 0.88))
    mid = min(range(1, len(wire.pts) - 1), key=lambda i: abs(wire.us[i] - (u_te + u_bs) / 2))
    comp.side = inside_side(wire.pts, (0.0, 0.0), mid)
    return wire


# --- the rosette ---------------------------------------------------------------------------------------


PETALS = 5
RING_R = 0.68


def drop(base, axis, reach, rho):
    """A drop of wire, closed: pointed at `base`, round at `reach` along `axis`, where it is a circle of
    radius `rho`; its two sides run straight from the point onto that circle, tangent. Each side is one
    segment, the round end steps at most TIGHT."""
    ax = v2unit(axis)
    nx = (-ax[1], ax[0])
    D = reach - rho
    c = v2add(base, v2mul(ax, D))
    a_start = math.pi / 2.0 + math.asin(min(rho / D, 0.999))

    def on_circle(t):
        return v2add(c, v2add(v2mul(ax, rho * math.cos(t)), v2mul(nx, rho * math.sin(t))))

    n_arc = math.ceil(2.0 * a_start / TIGHT[0])
    pts = [base]
    for k in range(n_arc + 1):
        pts.append(on_circle(a_start - 2.0 * a_start * k / n_arc))
    return pts


def rosette(rng: Rng) -> list[Wire]:
    """Five double drops round a ring, one pointing away from the thrower (-Z): each a drop pointed at
    the ring and round at the far end, with a second drop inside it, parallel, MID from it."""
    wires = []
    for k in range(PETALS):
        beta = 2.0 * math.pi * k / PETALS + math.radians(rng.uniform(-2.5, 2.5))
        axis = (math.sin(beta), -math.cos(beta))
        half = math.radians(40.0 + rng.uniform(-1.5, 1.5))
        rho = 1.0 + rng.uniform(-0.03, 0.03)
        # The point sits on the ring's outer edge: its mitred ink stops at the ring's hole.
        base = RING_R + W_RING / 2.0 + 0.01
        reach = base + rho / math.sin(half) + rho
        pts = drop(v2mul(axis, base), axis, reach - base, rho)
        wire = closed_wire(pts, lambda u: W_PETAL, gleam=(0.22, 0.78), comp_gleam=(0.25, 0.75))
        # The inner drop: the outer one's samples, offset inward the whole way round, the point mitred.
        comp = Comp(-1.0, 2.0, 0, width=W_PETAL_IN)
        wire.comps.append(comp)
        comp.side = inside_side(wire.pts + [wire.pts[0]], v2mul(axis, base + rho / math.sin(half)), len(pts) // 2)
        wires.append(wire)
    n = 16
    ring = [(RING_R * math.cos(2 * math.pi * k / n), RING_R * math.sin(2 * math.pi * k / n)) for k in range(n)]
    wires.append(closed_wire(ring, lambda u: W_RING, gleam=(0.55, 0.95)))
    return wires


def eyelet(centre, r=0.34, sides=8) -> Wire:
    pts = [(centre[0] + r * math.cos(2 * math.pi * k / sides), centre[1] + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    return closed_wire(pts, lambda u: W_EYELET, gleam=(0.55, 0.98))


# --- beads ------------------------------------------------------------------------------------------------

BEAD_R = 0.2
BEAD_SIDES = 6
LIGHT = math.atan2(-1.0, -0.35)  # where the light comes from: the far side (-Z), a little left


def bead(body: Mesh, core: Mesh, ink: Mesh, centre) -> None:
    """A grain of gold: a seven-sided dome on the page, a pale fleck over its top, the floor of its
    hull under it as its contour (a heptagon whose flats stand INK past the dome's corners)."""
    cx, cz = centre
    sides = BEAD_SIDES
    # One face is centred on the light, so the fleck lies on a single plane.
    phase = LIGHT + math.pi / sides
    rim_p = [(cx + BEAD_R * math.cos(phase + 2 * math.pi * s / sides), Y_GOLD, cz + BEAD_R * math.sin(phase + 2 * math.pi * s / sides)) for s in range(sides)]
    apex_p = (cx, Y_BEAD, cz)
    rim = [body.vert(p) for p in rim_p]
    apex = body.vert(apex_p)
    for s in range(sides):
        a = phase + 2 * math.pi * (s + 0.5) / sides
        body.tri(rim[s], rim[(s + 1) % sides], apex, (math.cos(a), 1.0, math.sin(a)))
    out = (BEAD_R + INK) / math.cos(math.pi / sides)
    floor = [ink.vert((cx + out * math.cos(phase + 2 * math.pi * s / sides), Y_INK, cz + out * math.sin(phase + 2 * math.pi * s / sides))) for s in range(sides)]
    for s in range(1, sides - 1):
        ink.tri(floor[0], floor[s], floor[s + 1], UP)
    # The fleck lies on the dome's lit face (rim[-1], rim[0], apex), inset from its edges and lifted
    # FLECK_LIFT along that face's normal, so it stays inside the bead's silhouette from every angle.
    r0, r1 = rim_p[-1], rim_p[0]
    e1 = tuple(r1[c] - r0[c] for c in range(3))
    e2 = tuple(apex_p[c] - r0[c] for c in range(3))
    nn = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
    nl = math.sqrt(sum(c * c for c in nn))
    nn = tuple(c / nl for c in nn)
    if nn[1] < 0:
        nn = tuple(-c for c in nn)
    g = []
    for w in ((0.62, 0.2, 0.18), (0.2, 0.62, 0.18), (0.36, 0.36, 0.28)):
        pt = tuple(r0[c] * w[0] + r1[c] * w[1] + apex_p[c] * w[2] + nn[c] * FLECK_LIFT for c in range(3))
        g.append(core.vert(pt))
    core.tri(g[0], g[1], g[2], nn)


def bead_positions(rng: Rng):
    """Granulation in the five gaps between the petals, in rows as the reference lays it: an arc of
    five (six in the two side gaps and the front one) just beyond the petals' round ends, a pair and a
    single tucked deeper into the gap, and a pair further out in the front gap. 45 beads."""
    out = []
    for k in range(PETALS):
        gap = 2.0 * math.pi * (k + 0.5) / PETALS
        wide = k in (1, 2, 3)  # the right, front and left gaps (k = 2 is the one toward the thrower)
        arc = (-27.5, -16.5, -5.5, 5.5, 16.5, 27.5) if wide else (-22, -11, 0, 11, 22)
        rows = [(3.66, arc), (3.13, (-6.2, 6.2)), (2.7, (0,))]
        if k == 2:
            rows.append((4.3, (-7.5, 7.5)))
        for r, offsets in rows:
            for o in offsets:
                a = gap + math.radians(o + rng.uniform(-1.0, 1.0))
                rr = r + rng.uniform(-0.03, 0.03)
                out.append((rr * math.sin(a), -rr * math.cos(a)))
    return out


# --- the rope ---------------------------------------------------------------------------------------------

ROPE_HULL = 0.15  # Orpiment's hull band: the rope is the zone's edge
ROPE_W = 0.88  # the gold's width across the rope: with its hull, 1.18, a little over a double wire
STRANDS = 36  # strand pieces round the rim
ROPE_SLANT = 2.3  # along-rope run of a strand from the outer edge to the inner edge (studs)
STRAND_GAP = 0.07  # the dark line between two strands, square to them
STRAND_CUT = (0.26, 0.18)  # each strand's sharp corner cut back: along the edge (studs), across (share)


def rope(body: Mesh, core: Mesh, ink: Mesh) -> None:
    """Two strands twisted, seen as long slanted strand pieces lying on the floor of the rope's hull.
    Each piece is a slanted band from the outer edge to the inner edge, its two sharp corners cut back.
    Its roof has its ridge down the rope's middle, where the piece crosses it, so the rope's crown is
    one line round the rim, dipping only where two strands meet; nothing stands over it. The floor
    shows between the pieces as the dark line between two strands, and as a dark notch where each
    meets an edge; it runs ROPE_HULL past both edges. The twist rises to the right seen from the
    thrower, as in the reference. A pale streak lies along each strand, on one half of its roof or the
    other in turn, as two strands catch the light."""
    r_go = RADIUS - ROPE_HULL
    r_gi = r_go - ROPE_W
    r_mid = (r_go + r_gi) / 2.0
    n = STRANDS
    step = 2.0 * math.pi / n
    fo = [ink.vert((RADIUS * math.cos(step * k), Y_INK, RADIUS * math.sin(step * k))) for k in range(n)]
    # Outer kerb: an inward-facing ink wall on the outer ink line, up to crown height, so the zone's far
    # edge reads as ink (not gold on vellum) from the thrower's low camera. Its outer edge stays at 12.
    kt = [ink.vert((RADIUS * math.cos(step * k) - 0.06 * math.cos(step * k), KERB_TOP, (RADIUS - 0.06) * math.sin(step * k))) for k in range(n)]
    for k in range(n):
        j = (k + 1) % n
        am = step * (k + 0.5)
        face_in = (-math.cos(am), 0.0, -math.sin(am))
        ink.tri(fo[k], fo[j], kt[k], face_in)
        ink.tri(fo[j], kt[j], kt[k], face_in)
    r_fi = r_gi - ROPE_HULL
    fi = [ink.vert((r_fi * math.cos(step * k), Y_INK, r_fi * math.sin(step * k))) for k in range(n)]
    for k in range(n):
        j = (k + 1) % n
        ink.tri(fi[k], fo[k], fi[j], UP)
        ink.tri(fo[k], fo[j], fi[j], UP)

    def at(s_along, v, y):
        """The page point s studs round the rim (along the rope's middle, clockwise seen from above)
        and v across it (0 outer edge, 1 inner edge), at height y."""
        phi = -s_along / r_mid
        r = r_go - v * ROPE_W
        return (r * math.cos(phi), y, r * math.sin(phi))

    pitch = 2.0 * math.pi * r_mid / n
    sin_t = ROPE_W / math.hypot(ROPE_W, ROPE_SLANT)
    a = (pitch - STRAND_GAP / sin_t) / 2.0  # half a strand's run along the rope, at a constant v
    cut_s, cut_v = STRAND_CUT
    k_cut = cut_s / (2.0 * a)
    rng = Rng(SEED + 900)
    for g in range(n):
        s0 = pitch * g + rng.uniform(-0.03, 0.03)
        q = [
            at(s0 - a + cut_s, 0.0, Y_GOLD),
            at(s0 + a, 0.0, Y_GOLD),
            at(s0 + a + ROPE_SLANT * (1.0 - cut_v), 1.0 - cut_v, Y_GOLD),
            at(s0 + ROPE_SLANT + a - cut_s, 1.0, Y_GOLD),
            at(s0 + ROPE_SLANT - a, 1.0, Y_GOLD),
            at(s0 - a + ROPE_SLANT * cut_v, cut_v, Y_GOLD),
        ]
        rl = at(s0 - a + ROPE_SLANT * 0.5, 0.5, Y_RIDGE)
        rr = at(s0 + a + ROPE_SLANT * 0.5, 0.5, Y_RIDGE)
        ids = [body.vert(p) for p in q]
        il, ir = body.vert(rl), body.vert(rr)
        centre = tuple((rl[c] + rr[c]) / 2.0 for c in range(3))

        def face(*vs):
            pts = [body.verts[v] for v in vs]
            fc = tuple(sum(p[c] for p in pts) / len(pts) for c in range(3))
            body.tri(vs[0], vs[1], vs[2], (fc[0] - centre[0], 0.35, fc[2] - centre[2]))

        face(ids[5], ids[0], il)  # the outer half: the cut corner, the main slope, the far corner
        face(ids[0], ir, il)
        face(ids[0], ids[1], ir)
        face(ir, ids[2], ids[3])  # the inner half, the same way round
        face(ir, ids[3], il)
        face(il, ids[3], ids[4])

        # The streak, inside the main slope of one half: from near the edge toward the ridge, along the
        # strand; its corners stay low enough that the slope plus the lift is under the ridge.
        if g % 2 == 0:
            corner, near, far = q[0], rl, rr  # outer half: (q1, rl, rr)
        else:
            corner, near, far = q[3], rr, rl  # inner half: (q4, rr, rl)

        def on_face(t, d):
            w = (1.0 - t, t * (1.0 - k_cut) - d, t * k_cut + d)
            p = tuple(corner[c] * w[0] + near[c] * w[1] + far[c] * w[2] for c in range(3))
            return (p[0], p[1] + DETAIL_LIFT, p[2])

        g3 = [core.vert(on_face(0.15, 0.0)), core.vert(on_face(0.15, 0.07)), core.vert(on_face(0.8, 0.04))]
        core.tri(g3[0], g3[1], g3[2], UP)


# --- the whole mould ---------------------------------------------------------------------------------------

# Volute centres and big-turn radii, read off the rectified reference (front-right quadrant; the
# other three are mirrors, each with its own small differences).
FRONT_CENTRE = ((3.15, 7.35), 2.62)
BACK_CENTRE = ((3.72, -7.02), 2.66)
SIDE_BACK = ((7.34, -2.72), 2.82)
SIDE_FRONT = ((6.9, 3.46), 2.82)
EYELETS = ((3.45, -3.6), (3.3, 3.35))

_CACHE: dict = {}


def build():
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    rng = Rng(SEED)
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    wires: list[Wire] = []
    for flip_x in (False, True):
        for back in (False, True):
            (c, R) = BACK_CENTRE if back else FRONT_CENTRE
            centre = (c[0] + rng.uniform(-0.08, 0.08), abs(c[1]))
            w = centre_volute(centre, R + rng.uniform(-0.04, 0.04), 0.55 + rng.uniform(-0.08, 0.08), SEED + len(wires))
            wires.append(mirrored(w, flip_x, back))
    for flip_x in (False, True):
        jit = rng.uniform(-0.04, 0.04)
        w = side_c(SIDE_BACK[0], SIDE_BACK[1] + jit, SIDE_FRONT[0], SIDE_FRONT[1] - jit, SEED + 50 + len(wires))
        wires.append(mirrored(w, flip_x, False))
    wires += rosette(rng)
    for ex, ez in EYELETS:
        for sx in (1, -1):
            wires.append(eyelet((sx * (ex + rng.uniform(-0.08, 0.08)), ez + rng.uniform(-0.08, 0.08))))
    for w in wires:
        w.build(body, core, ink)
    beads = bead_positions(rng)
    for p in beads:
        bead(body, core, ink, p)
    rope(body, core, ink)
    reach = max(math.hypot(x, z) for x, _, z in ink.verts)
    for mesh in (body, core, ink):
        mesh.scale(0.5 / reach)
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta() -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": SEED}


def watermark_wire():
    return build()[0], meta()


def watermark_gleam():
    return build()[1], meta()


def watermark_ink():
    return build()[2], meta()
