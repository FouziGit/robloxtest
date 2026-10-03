"""The Colophon's knot -- "la Cadelure" (D-273 method): a broad-nib ribbon
knotted round the signed body, drawn after the developer's two references (docs/vfx/colophon/ref-1.jpg,
the in-game shot, and ref-2.jpg, the model sheet "Orpiment ink cadel knot").

Roblox space, X right, Y up, forward -Z. Built in studs round a standard R15 body (feet at y = 0, hip
3.2, head top 6.2), then scaled by 1/8.5: the reference is `Height`, floor to the top of the tail's ink
= 1 (8.5 studs posed). Pivot (0, 0, 0) on the floor under the root. Axis Y, no spin.

How it turns. The knot is the victim's: it is posed on the victim's root and follows its position AND
its yaw (R2 with yaw), with Spin 0, so it never turns against the body it binds -- the sheet's tight
knot, built clear of the standard R15 body in that body's own frame (0.10 stud of air at least, for
the idle sway). Its front -- the sheet's front view, the X over the chest -- is the victim's front (-Z); its back is the sheet's "from behind: crossed loops and tail read clearly
around victim", the same X with the tail rising over it. (Posed Face = "Aim" with the bible's +1.5 spin, it cut
into the arms of a victim turned 15 degrees from the aim. Following the victim's yaw with
no spin changes the bible's section 5.3 and the Colophon's entry in section 11: a decision to record
in docs/DECISIONS.md when the knot is integrated.)

  - two loops (L and R), each a closed ribbon over a shoulder and under the opposite hand, leaning
    +-35 degrees: the X of their front strands over the chest (thick, pinched where they cross and
    where they pass over the band), a cap over the shoulder beside the head, a hairpin round the thigh
    below the hand, and a back strand as broad as the front one, right behind it along the middle and
    swinging outward near each turn, so every turn curls outward as the sheet draws it. They cross
    twice, L over R in front and R over L behind: a true interlace, the same X from both sides.
  - the waist ellipse: a closed band round the waist and round the arms (it binds them to the body),
    wider than the X, under all four strands, drawn pale on its outer face as the sheet draws it.
  - the paraph tail: a separate stroke, pen down behind the head between the two back strands and
    clear of both; it rises in an S, leans over the head and curls over into an open crook (no closed
    eye) that ends on a pen-lift dot; its ink tops out at 8.5 studs, 2.3 above the head.

Layers, from the body out: the band (0.51 stud off the arms and the torso), the inner strands (0.55 out
of the band), the outer half of each loop (D_SEP, 0.62 farther out) -- far enough everywhere for the
over strand's hull to draw the double contour over the under strand's gold. Every ribbon has a flat box
section, its broad face out, and an inverted hull of the same box 0.15-0.16 stud round it (a box round
a ridged body left the hull's back corners bare and doubled the contour seen at a slant). Three meshes,
one tone each: ColophonBody (Pigment), ColophonCore (Core: the pale thread on every strand, broken where it
runs under, on the waist band and on the tail's belly), ColophonInk (Ink: the hulls, six pen-lift dots,
three calligraphic flow lines). Faces are wound from the section's own frame, never from the geometry, so every volume is closed, unfolded, and clear of the body and of the others.

The geometry is written in the "front frame" -- the victim's chest toward +Z, as the sheet's front view
is drawn -- and turned half a turn about Y at the end, so the chest side lands on Roblox's forward, -Z.
"""

from __future__ import annotations

import math

from strokes import Mesh, Polyline, catmull, fbm

SEED = 5157
TILT = math.radians(35.0)

# --- the two loops (front frame, studs) -------------------------------------------------------------------
YC = 3.95  # height of the crossings, low on the chest
A_TOP = 2.78  # from the crossing up the leaning axis to a cap's apex: beside the head, at its top
A_BOT = 2.62  # and down to a hairpin's apex, below the hand
FLARE = 0.40  # the lower legs flare outward, round the outside of the thighs
D_IN = [(2.40, 1.82), (3.30, 1.56), (4.75, 1.56), (5.60, 1.32)]  # depth of an inner strand by height:
# deeper on the lower legs (they reach it late after the hairpin and must clear the band), 1.56 over the
# band and the chest, easing to 1.32 beside the head
D_SEP = 0.62  # an outer strand (L's front half, R's back half) stands this much farther out
Q = 1.0  # depth = D sin(theta) and run = A cos(theta)^P_U: a turn as round as the loop is deep
P_U = 0.45
SWING = (1.18, 1.00)  # studs: how far a back strand swings outward of its front strand near a cap (and a
# hairpin): past the front strand's width and both contours, so every turn opens into a clean U,
SWING_P = 2.0  # and how late (right behind its front strand along the middle)
FACE_FLAT = 0.20  # a strand's broad face looks out from the spine, its sideways part flattened this much
PINCH = 0.25  # share of the width lost at a crossing of the two loops
PINCH_R = 0.45
PINCH_RING = 0.20  # and lost where a downstroke passes over the waist band
W_STRAND = (0.48, 0.30)  # a strand's width at a cap or a hairpin, plus its swell along the run: the front
# and the back strand alike, so each loop reads as one clean stroke from the front and from behind
LOOP_ROWS = 21

# --- the waist ellipse: the arms-and-torso box (x +-2, z +-0.5) offset by OFF, its corners round arcs -------
RING = {"y": 3.20, "hx": 2.0, "hz": 0.5, "off": 0.51}
W_RING = 0.34
RING_ROWS = 10

# --- the tail (front frame, studs) --------------------------------------------------------------------------
TAIL_CTRL = [  # the slender S, from the pen-down behind the head up to the small curl
    (0.02, 5.72, -1.14),  # pen down behind the head, where the two back strands have spread apart
    (0.14, 6.25, -1.26),  # bows back behind the head...
    (0.18, 6.75, -1.12),
    (0.12, 7.15, -0.80),  # ...and leans forward over it: an S seen from the side
    (0.10, 7.50, -0.55),
    None,  # the curl's first point
]
HOOK_C = (-0.30, 7.816, -0.50)  # the small curl: over to the left and down, round this centre
HOOK_R = (0.42, 0.38)  # radius 0.35-0.45
HOOK_A = (math.radians(-5.0), math.radians(255.0))  # round and down: open, no eye
TAIL_W = [(0.0, 0.30), (0.25, 0.30), (0.60, 0.26), (1.0, 0.22)]
TAIL_FACE = (0.45, 0.0, 1.0)  # the tail turns its broad face to the chest side, a little to the side
TAIL_ROWS = 14

THREAD_LIFT = 0.06  # studs the pale thread and the flow lines stand off the broad face (bible: 0.03-0.08)
DOT_LIFT = 0.085  # the pen-lift dots, above the thread
DOT_R = 0.10


def thickness(w: float) -> float:
    return 0.12 + 0.36 * w


def hull_weight(w: float) -> float:
    """The contour: 0.15 stud, 0.16 on the fullest downstroke (bible, Orpiment 0.15-0.25)."""
    return 0.15 + 0.01 * min(max((w - 0.6) / 0.2, 0.0), 1.0)


# --- vectors -----------------------------------------------------------------------------------------


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
    n = math.sqrt(dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n) if n > 1e-12 else (0.0, 1.0, 0.0)


def spow(c: float, q: float) -> float:
    return math.copysign(abs(c) ** q, c)


def bump(d: float, r: float) -> float:
    return math.exp(-((d / r) ** 2))


def smooth(a: float, b: float, x: float) -> float:
    f = min(max((x - a) / (b - a), 0.0), 1.0)
    return f * f * (3 - 2 * f)


# --- the curves (front frame) ----------------------------------------------------------------------------


def loop_axes(side: int):
    d = (-side * math.sin(TILT), math.cos(TILT), 0.0)  # up the leaning axis: the cap is on -side * X
    e = unit((-side * 1.0, -0.30, 0.0))  # outward at the cap: sideways and a little down, over the arm
    f = unit((side * 1.0, -0.15, 0.0))  # outward at the hairpin: sideways and a little down, under the hand
    return d, e, f


def swing(th: float) -> float:
    """Outward offset (along e) at theta: nothing along the front strand, half at the apex of each
    turn, the full SWING on the back strand near its ends, nothing at its middle."""
    back = 0.5 * (1.0 - math.sin(th))  # 0 on the front strand, 1 on the back one, smoothly through the apex
    c = math.cos(th)
    return (SWING[0] if c >= 0 else SWING[1]) * spow(c, SWING_P) * back


def depth_in(y: float) -> float:
    if y <= D_IN[0][0]:
        return D_IN[0][1]
    for (y0, d0), (y1, d1) in zip(D_IN, D_IN[1:]):
        if y <= y1:
            return d0 + (d1 - d0) * smooth(y0, y1, y)
    return D_IN[-1][1]


def loop_base(side: int, th: float):
    """The loop at theta (front frame): theta 0 is the cap's apex, the front strand runs theta 0..pi down
    to the hairpin, the back strand pi..2 pi back up. The crossings are at pi/2 (front) and 3 pi/2."""
    d, e, f = loop_axes(side)
    c = math.cos(th)
    u = (A_TOP if c >= 0 else A_BOT) * spow(c, P_U)
    out = swing(th)
    if c >= 0:
        off = mul(e, out)
    else:  # the lower legs flare and the hairpin swings outward round the thigh, never up into the hand
        off = mul(f, -out + FLARE * c * c)
    xy = add(add((0.0, YC, 0.0), mul(d, u)), off)
    outer = (math.sin(th) > 0) == (side > 0)  # L's front half and R's back half run outside
    depth = depth_in(xy[1]) + (D_SEP if outer else 0.0)
    return (xy[0], xy[1], depth * spow(math.sin(th), Q))


def solve_theta(side: int, lo: float, hi: float, y: float) -> float:
    """theta in [lo, hi] where the loop's base passes height y (bisection; y is monotonic there)."""
    f_lo = loop_base(side, lo)[1] - y
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        f = loop_base(side, mid)[1] - y
        if (f > 0) == (f_lo > 0):
            lo, f_lo = mid, f
        else:
            hi = mid
    return 0.5 * (lo + hi)


def loop_samples(side: int, dense: int = 1440):
    """(point, width, theta) along a loop from the cap's apex down the front strand: broad along each
    strand, narrower through the turns, pinched where the loops cross and where they pass the band."""
    seed = SEED + (11 if side > 0 else 23)
    crossings = [loop_base(side, 0.5 * math.pi), loop_base(side, 1.5 * math.pi)]
    over_ring = [loop_base(side, solve_theta(side, 0.5 * math.pi, math.pi, RING["y"])),
                 loop_base(side, solve_theta(side, math.pi, 1.5 * math.pi, RING["y"]))]
    pts = []
    for j in range(dense):
        th = 2.0 * math.pi * j / dense
        p = loop_base(side, th)
        s = math.sin(th)
        w = W_STRAND[0] + W_STRAND[1] * abs(s)
        for x in crossings + over_ring:
            w *= 1.0 - (PINCH if x in crossings else PINCH_RING) * bump(math.dist(p, x), PINCH_R)
        w *= 1.0 + 0.06 * (fbm(6.0 * j / dense, 0.4, seed) * 2.0 - 1.0)
        pts.append((p, w, th))
    return pts


def ring_path(dense: int):
    """The box offset by OFF, walked from the front middle (+Z) toward +X: four straight sides and four
    quarter arcs, sampled evenly along its length."""
    k = RING
    hx, hz, r = k["hx"], k["hz"], k["off"]
    pts = []
    # explicit walk: front middle -> front-right corner -> right side -> back-right corner -> back ->
    # back-left corner -> left side -> front-left corner -> front middle
    segs = [
        ((0.0, hz + r), (hx, hz + r)),
        ("arc", (hx, hz), math.pi * 0.5, 0.0),
        ((hx + r, hz), (hx + r, -hz)),
        ("arc", (hx, -hz), 0.0, -math.pi * 0.5),
        ((hx, -hz - r), (-hx, -hz - r)),
        ("arc", (-hx, -hz), -math.pi * 0.5, -math.pi),
        ((-hx - r, -hz), (-hx - r, hz)),
        ("arc", (-hx, hz), math.pi, math.pi * 0.5),
        ((-hx, hz + r), (0.0, hz + r)),
    ]
    lens_ = []
    for s in segs:
        if s[0] == "arc":
            lens_.append(abs(s[3] - s[2]) * r)
        else:
            lens_.append(math.dist(s[0], s[1]))
    total = sum(lens_)
    for j in range(dense):
        t = total * j / dense
        for s, ln in zip(segs, lens_):
            if t <= ln or s is segs[-1]:
                f = min(t / ln, 1.0)
                if s[0] == "arc":
                    a = s[2] + (s[3] - s[2]) * f
                    pts.append((s[1][0] + r * math.cos(a), k["y"], s[1][1] + r * math.sin(a)))
                else:
                    pts.append((s[0][0] + (s[1][0] - s[0][0]) * f, k["y"], s[0][1] + (s[1][1] - s[0][1]) * f))
                break
            t -= ln
    return pts


def ring_samples(dense: int = 2880):
    pts = []
    for j, p in enumerate(ring_path(dense)):
        w = W_RING * (1.0 + 0.06 * (fbm(4.0 * j / dense, 0.7, SEED + 41) * 2 - 1))
        pts.append((p, w, 2.0 * math.pi * j / dense))
    return pts


def profile(ctrl, s):
    for i in range(1, len(ctrl)):
        if s <= ctrl[i][0]:
            a, b = ctrl[i - 1], ctrl[i]
            f = (s - a[0]) / (b[0] - a[0])
            f = 0.5 - 0.5 * math.cos(math.pi * f)
            return a[1] + (b[1] - a[1]) * f
    return ctrl[-1][1]


def hook_point(f: float):
    a = HOOK_A[0] + (HOOK_A[1] - HOOK_A[0]) * f
    r = HOOK_R[0] + (HOOK_R[1] - HOOK_R[0]) * f
    return (HOOK_C[0] + r * math.cos(a), HOOK_C[1] + r * math.sin(a), HOOK_C[2])


def tail_samples(dense: int = 1200):
    # one spline through the S and through the crook every 28 degrees: no seam where they meet. It runs
    # one point past the crook's end and is cut there, so its last span curls as the crook does.
    ctrl = TAIL_CTRL[:-1] + [hook_point(i / 8) for i in range(10)]
    line = Polyline(catmull(ctrl, 40)[: 40 * (len(ctrl) - 2) + 1])  # cut at hook_point(1.0)
    pts = []
    for i in range(dense + 1):
        s = i / dense
        w = profile(TAIL_W, s) * (1.0 + 0.05 * (fbm(5.0 * s, 0.2, SEED + 57) * 2 - 1))
        pts.append((line.at(s), w, s))
    return pts


# --- resampling and frames ---------------------------------------------------------------------------


def choose_rows(pts, closed: bool, count: int, l0: float = 0.9, a0: float = math.radians(30.0), w0: float = 0.35,
                faces=None):
    """`count` indices spread evenly in a measure that grows with length, turning, twist of the broad face
    and width change: long straight runs get few rows, the caps, hairpins and the hook get many."""
    n = len(pts)
    m = [0.0]
    last = n if closed else n - 1
    for i in range(1, last + 1):
        p0, p1 = pts[(i - 1) % n][0], pts[i % n][0]
        pm = pts[(i - 2) % n][0] if (closed or i >= 2) else p0
        t0 = unit(sub(p0, pm)) if (closed or i >= 2) else None
        t1 = unit(sub(p1, p0))
        turn = math.acos(max(-1.0, min(1.0, dot(t0, t1)))) if t0 else 0.0
        dw = abs(pts[i % n][1] - pts[(i - 1) % n][1])
        twist = math.acos(max(-1.0, min(1.0, dot(faces[(i - 1) % n], faces[i % n])))) if faces else 0.0
        m.append(m[-1] + math.dist(p0, p1) / l0 + (turn + twist) / a0 + dw / w0)
    total = m[-1]
    rows = []
    segs = count if closed else count - 1
    k = 0
    for r in range(segs + (0 if closed else 1)):
        target = total * r / segs
        while k < len(m) - 1 and m[k + 1] <= target:
            k += 1
        i = k if (target - m[k]) <= (m[min(k + 1, len(m) - 1)] - target) else k + 1
        rows.append(i % n if closed else min(i, n - 1))
    return rows


class Ribbon:
    """Frames along a stroke, each row: centre p, tangent t, across a, broad-face normal n, width w,
    the section (front tf, back tb) and the hull weight h."""

    def __init__(self, name: str, pts, closed: bool, facing, count: int, l0: float = 0.9, a0: float = math.radians(30.0)) -> None:
        self.name = name
        self.closed = closed
        faces = [facing(p, param) for p, _w, param in pts]
        idx = choose_rows(pts, closed, count, l0, a0, faces=faces)
        n = len(pts)
        self.rows = []
        for i in idx:
            p, w, param = pts[i]
            if closed:
                a, b = pts[(i - 3) % n][0], pts[(i + 3) % n][0]
            else:
                a, b = pts[max(i - 3, 0)][0], pts[min(i + 3, n - 1)][0]
            tangent = unit(sub(b, a))
            face = facing(p, param)
            across = unit(cross(tangent, face))
            normal = unit(cross(across, tangent))
            t = thickness(w)
            self.rows.append({"p": p, "t": tangent, "a": across, "n": normal, "w": w, "tf": 0.35 * t, "tb": 0.65 * t,
                              "h": hull_weight(w), "param": param})

    def body_section(self, row):
        """A flat box, the broad face out: the same shape as its hull, so from any side the contour
        stands the same 0.15 stud off it (a ridged body left the hull's back corners bare)."""
        p, a, n = row["p"], row["a"], row["n"]
        hw = row["w"] / 2
        return [add(p, add(mul(a, x), mul(n, y))) for x, y in ((hw, row["tf"]), (-hw, row["tf"]), (-hw, -row["tb"]), (hw, -row["tb"]))]

    def hull_section(self, row):
        p, a, n, h = row["p"], row["a"], row["n"], row["h"]
        hw = row["w"] / 2 + h
        top, bot = row["tf"] + h, -row["tb"] - h
        return [add(p, add(mul(a, x), mul(n, y))) for x, y in ((hw, top), (-hw, top), (-hw, bot), (hw, bot))]

    @staticmethod
    def face_out(row, e: int):
        """The outward direction of the box section's side e (between corners e and e + 1)."""
        a, n = row["a"], row["n"]
        return [n, mul(a, -1.0), mul(n, -1.0), a][e]


def skin(mesh: Mesh, rib: Ribbon, hull: bool, record: list | None = None) -> None:
    """The ribbon's closed body (outward) or its inverted hull (inward). Wound from the section's own
    frame: a side's triangles face the side's outward direction by construction, whatever the bend,
    so two triangles never share an edge in the same direction. `record` collects (triangle, outward)
    for the fold gate."""
    rows = rib.rows
    rings = [[mesh.vert(c) for c in (rib.hull_section(r) if hull else rib.body_section(r))] for r in rows]
    m = len(rings[0])
    count = len(rows)
    segs = count if rib.closed else count - 1
    # corners run +a+n, -a+n, ...: counter-clockwise seen from -t (a x n = -t), so quad (r0e, r1e, r1f, r0f)
    # faces outward.
    out = []
    for k in range(segs):
        r0, r1 = rings[k], rings[(k + 1) % count]
        for e in range(m):
            f = (e + 1) % m
            nrm = unit(add(Ribbon.face_out(rows[k], e), Ribbon.face_out(rows[(k + 1) % count], e)))
            out.append(((r0[e], r1[e], r1[f]), nrm))
            out.append(((r0[e], r1[f], r0[f]), nrm))
    if not rib.closed:
        for k, d in ((0, -1.0), (count - 1, 1.0)):
            row = rows[k]
            reach = 0.32 * row["w"] + (row["h"] if hull else 0.0)
            centre = add(row["p"], mul(row["n"], (row["tf"] - row["tb"]) / 2))
            tip = mesh.vert(add(centre, mul(row["t"], d * reach)))
            ring = rings[k]
            for e in range(m):
                f = (e + 1) % m
                # the tube uses edge e->f on its last ring and f->e on its first: a cap takes the other way
                tri = (ring[f], ring[e], tip) if d > 0 else (ring[e], ring[f], tip)
                out.append((tri, mul(row["t"], d)))
    for (a, b, c), nrm in out:
        if hull:
            mesh.tris.append((a, c, b))
        else:
            mesh.tris.append((a, b, c))
        if record is not None:
            record.append(((a, c, b) if hull else (a, b, c), mul(nrm, -1.0) if hull else nrm))


def lens(mesh: Mesh, rib: Ribbon, rows_idx: list, share: float, centre: float, lift: float, floor: float = 0.1) -> None:
    """A lens on the broad outer face over the given rows: `share` of the width at its widest, `centre`
    across (-1..1 of the half width). Pale (Core) or dark (an Ink flow line). Never at the outer edge."""
    rows = rib.rows
    if len(rows_idx) < 2:
        return
    acc = [0.0]
    for j in range(1, len(rows_idx)):
        acc.append(acc[-1] + math.dist(rows[rows_idx[j - 1]]["p"], rows[rows_idx[j]]["p"]))
    total = acc[-1] or 1.0
    left, right = [], []
    for j, i in enumerate(rows_idx):
        row = rows[i]
        u = acc[j] / total
        shape = max(math.sin(math.pi * u) ** 0.6, floor)
        half = 0.5 * share * row["w"] * shape
        base = add(row["p"], mul(row["n"], row["tf"] + lift))
        mid = add(base, mul(row["a"], centre * row["w"] / 2))
        left.append(mesh.vert(add(mid, mul(row["a"], half))))
        right.append(mesh.vert(add(mid, mul(row["a"], -half))))
    for j in range(len(rows_idx) - 1):
        n = rows[rows_idx[j]]["n"]
        mesh.tri(left[j], right[j], right[j + 1], n)  # the body quad's own diagonal (+a at j, -a at j + 1)
        mesh.tri(left[j], right[j + 1], left[j + 1], n)


def pen_dot(mesh: Mesh, rib: Ribbon, i: int, r: float, sides: int = 6, slide: float = 0.0) -> None:
    """A pen-lift dot: a flat ink disc on the ribbon's broad outer face at row i (moved `slide` studs
    along the stroke), as the sheet draws them inside the stroke near its end."""
    row = rib.rows[i]
    centre = add(add(row["p"], mul(row["n"], row["tf"] + DOT_LIFT)), mul(row["t"], slide))
    hub = mesh.vert(centre)
    ring = [mesh.vert(add(centre, add(mul(row["a"], r * math.cos(j * 2 * math.pi / sides)), mul(row["t"], r * math.sin(j * 2 * math.pi / sides)))))
            for j in range(sides)]
    for j in range(sides):
        mesh.tri(hub, ring[j], ring[(j + 1) % sides], row["n"])


# --- the knot ------------------------------------------------------------------------------------------


def loop_facing(_side: int):
    def face(p, _th):
        """Out from the spine (the segment y 2.6..5.3 on the axis), its sideways part flattened, so the
        strands over the chest and the back face square out of them and the turns face outward."""
        y = min(max(p[1], 2.6), 5.3)
        return unit((FACE_FLAT * p[0], p[1] - y, p[2]))

    return face


def ring_facing(p, _al):
    """The waist band stands upright, its broad face out of the box it is offset from."""
    k = RING
    q = (min(max(p[0], -k["hx"]), k["hx"]), min(max(p[2], -k["hz"]), k["hz"]))
    return unit((p[0] - q[0], 0.0, p[2] - q[1]))


def tail_facing(_p, _s):
    return unit(TAIL_FACE)


def ribbons():
    return {
        "L": Ribbon("L", loop_samples(1), True, loop_facing(1), LOOP_ROWS, 1.3, math.radians(15.0)),
        "R": Ribbon("R", loop_samples(-1), True, loop_facing(-1), LOOP_ROWS, 1.3, math.radians(15.0)),
        "ring": Ribbon("ring", ring_samples(), True, ring_facing, RING_ROWS, 1.2, math.radians(40.0)),
        "tail": Ribbon("tail", tail_samples(), False, tail_facing, TAIL_ROWS, 0.7, math.radians(26.0)),
    }


def run(rib: Ribbon, pred) -> list:
    """The rows (in stroke order) whose param satisfies pred: one contiguous run, since every range
    asked for lies inside the stroke's own parameter span."""
    return [i for i, r in enumerate(rib.rows) if pred(r["param"])]


def grow(rib: Ribbon, idx: list, n: int) -> list:
    """Extend a run of rows (stroke order, wrapping) to at least n rows so no thread piece is a needle."""
    cnt = len(rib.rows)
    idx = list(idx)
    while len(idx) < n:
        idx = idx + [(idx[-1] + 1) % cnt] if len(idx) % 2 else [(idx[0] - 1) % cnt] + idx
    return idx


def turn_half(m: Mesh) -> None:
    """Front frame -> Roblox: half a turn about Y (a rotation, so every winding is kept)."""
    m.verts = [(-x, y, -z) for x, y, z in m.verts]


_CACHE: dict = {}


def build():
    if "m" in _CACHE:
        return _CACHE["m"]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    ribs = ribbons()
    folds = {"body": [], "hull": []}
    for rib in ribs.values():
        skin(body, rib, hull=False, record=folds["body"])
        skin(ink, rib, hull=True, record=folds["hull"])
    pi = math.pi
    # The pale thread on the spine of every strand, front and back, broken where the strand runs under the
    # other loop (R in front, L behind); the over strand's thread runs through its crossing.
    for side, key in ((1, "L"), (-1, "R")):
        rib = ribs[key]
        for lo, hi, over in ((0.12, 0.66, side > 0), (1.34, 1.88, side < 0)):  # clear of the dots at 0.8, 1.2
            if over:
                lens(core, rib, run(rib, lambda th, lo=lo, hi=hi: lo * pi <= th <= hi * pi), 0.26, 0.0, THREAD_LIFT)
            else:
                mid = 0.5 if lo < 1.0 else 1.5  # the crossing
                for a, b in ((lo, mid - 0.06), (mid + 0.06, hi)):
                    idx = run(rib, lambda th, a=a, b=b: a * pi <= th <= b * pi)
                    idx = grow(rib, idx, 3)
                    lens(core, rib, idx, 0.34, 0.0, THREAD_LIFT, floor=0.6)
    # the waist band, pale as the sheet draws it, and the tail's belly
    ring = ribs["ring"]
    lens(core, ring, list(range(len(ring.rows))) + [0], 0.36, 0.0, THREAD_LIFT, floor=1.0)
    tail = ribs["tail"]
    lens(core, tail, run(tail, lambda s: 0.14 <= s <= 0.62), 0.34, 0.0, THREAD_LIFT)
    # Calligraphic flow lines (ink): a hairline along the edge the nib's corner drags, on the upper part
    # of each downstroke and on the tail's belly.
    for key in ("L", "R"):
        rib = ribs[key]
        lens(ink, rib, run(rib, lambda th: 0.08 * pi <= th <= 0.30 * pi), 0.08, -0.68, THREAD_LIFT)
    lens(ink, tail, run(tail, lambda s: 0.20 <= s <= 0.70), 0.10, -0.55, THREAD_LIFT)
    # Pen-lift dots: at the lower end of every strand (below the band, above the hairpin), front and back,
    # and at both ends of the tail.
    for key in ("L", "R"):
        rib = ribs[key]
        for at in (0.73 * pi, 1.27 * pi):
            i = min(range(len(rib.rows)), key=lambda k: abs(rib.rows[k]["param"] - at))
            pen_dot(ink, rib, i, DOT_R)
    pen_dot(ink, tail, len(tail.rows) - 1, 0.085, slide=-0.10)
    pen_dot(ink, tail, 0, 0.075, slide=0.10)
    top = max(v[1] for m in (body, core, ink) for v in m.verts)
    for m in (body, core, ink):
        turn_half(m)
        m.scale(1.0 / top)
    for rec in folds.values():
        rec[:] = [(tri, (-o[0], o[1], -o[2])) for tri, o in rec]
    _CACHE["m"] = (body, core, ink, top, ribs, folds)
    return _CACHE["m"]


def meta() -> dict:
    return {"Reference": "Height", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": SEED}


def cadel_body():
    return build()[0], meta()


def cadel_core():
    return build()[1], meta()


def cadel_ink():
    return build()[2], meta()
