"""The Hatching's cuts (Cinnabar + Umber): the burin strokes of a run of hatching, crossing at +-41 degrees
in front of the caster, one per beat -- the strokes an engraver lays to shade a plate.

Drawn after the developer's references (docs/vfx/hatching/ref-1.jpg, ref-2.jpg and ref-3.jpg). Three cuts,
each laid alone on its beat at its own length, in the server's box (GlyphConfig Hatching: Width 6, Height 6,
Range 7: the caster's frame moved Range / 2 ahead, so +-3 about the root in X and Y, from the root to 7
ahead on -Z); nothing of a cut, contour and needles included, comes nearer the box's sides than 0.1 stud:
  - the cut (CUT, 7.4 studs tip to tip): a lens of pigment swollen in the middle and drawn out at both
    ends into ink needles, a ridge a little off the middle line (a burin's V is never quite centred), a
    keel under it, a pale thread on the ridge and two engraved lines on the faces;
  - the long cut (LONG, 7.6): the second regular cut, its bulge further up, its lines elsewhere: beats 1
    and 3 run "/" and 2 and 4 run "\", and no two beats of a pair lay the same stroke;
  - the finisher (FINISHER, 8.2): the last beat's heavier cut, wider and deeper, with three engraved lines.

Three meshes per cut, one tone each: *_body (Pigment: the lens), *_core (Core: the pale thread on the
ridge, cut along the ridge's own triangles), *_ink (Ink: the inverted hull, the contour, and the engraved
lines, tapered, never parallel). Every mesh is built at the length the game lays it, in final studs, so
its contour and lifts are exact there. Roblox space: X right, Y up, forward -Z. Reference Length: the cut
tip to tip, ink needles included, along Z; pivot (0, 0, 0) at its middle.
"""

from __future__ import annotations

import math

from strokes import Mesh, add, cross, dot, emit, fbm, mul, norm, sub

SEED = 5541

# A cut, in final studs (each mesh is built at the length the game lays it, so its contour and lifts are
# exact there). `length` is tip to tip, ink needles included (the Reference); `point` how far the ink runs
# past the pigment's own point; `width` the pigment's swollen middle, edge to edge; `depth` ridge to keel
# there; `peak` where along the pigment the burin pressed hardest (toward the +X end, which every beat
# lays uppermost); the lens is (1 - |2g - 1| ** fill) ** power; `ridge` how far off the middle line the
# ridge runs, as a share of the half width (a burin's V is never quite centred); `tip_half` the half width
# of the last pigment ring, where the pigment closes on its point; `spacing` the rings' step along the cut.
CUT = {
    "length": 7.4,
    # The ink needle: from the pigment's end rings to the ink's points; the pigment closes `close` past them.
    "taper": 0.65,
    "close": 0.06,
    "needle_ease": 1.4,
    "needle_curve": 2.0,
    "width": 0.56,
    "depth": 0.26,
    "peak": 0.67,
    "fill": 2.15,
    "power": 1.8,
    "ridge": 0.16,
    "hull_mid": 0.11,
    "hull_tip": 0.105,
    "tip_half": 0.04,
    "spacing": 0.2,
    # The pale thread on the ridge: from, to (along the pigment), its half width as a share of each facet.
    "thread": (0.08, 0.9, 0.12),
    # The shorter one on the keel, seen by the target.
    "keel_thread": (0.16, 0.8, 0.1),
    # Engraved lines down the thrower's facets: (facet +1 upper / -1 lower, share of the facet from the
    # ridge, from, to (along the pigment), width). Unequal, never parallel: each keeps its share of a facet
    # that narrows toward the needles.
    "lines": ((-1, 0.42, 0.14, 0.78, 0.034), (1, 0.46, 0.3, 0.72, 0.028)),
}

# The second regular cut: longer, its bulge further up, its lines elsewhere -- beats 1 and 3 run "/" and
# 2 and 4 run "\", and no two beats of a pair lay the same stroke.
LONG = dict(
    CUT,
    length=7.6,
    peak=0.72,
    lines=((1, 0.4, 0.2, 0.8, 0.032), (-1, 0.5, 0.34, 0.7, 0.026)),
    thread=(0.1, 0.92, 0.12),
    keel_thread=(0.2, 0.84, 0.1),
)

FINISHER = dict(
    CUT,
    length=8.2,
    width=0.76,
    depth=0.34,
    peak=0.66,
    hull_mid=0.14,
    thread=(0.07, 0.91, 0.11),
    keel_thread=(0.12, 0.84, 0.09),
    lines=((-1, 0.38, 0.12, 0.8, 0.042), (1, 0.42, 0.24, 0.74, 0.036), (-1, 0.72, 0.32, 0.64, 0.028)),
)

SPECS = {"Hatch": (CUT, SEED), "HatchLong": (LONG, SEED + 13), "HatchFinisher": (FINISHER, SEED + 7)}

# The ink needle's rings, as shares of `taper` past the end ring, and the least half width a ring may have
# (a thinner one only makes slivers): the needle closes on its point from the last.
NEEDLE_RINGS = (0.2, 0.4, 0.58, 0.73, 0.85)
NEEDLE_MIN = 0.01

THREAD_LIFT = 0.035
LINE_LIFT = 0.035
MITRE_CAP = 1.05
# A strip's half width never grows faster than this per stud from its point, so its first triangles are
# never slivers.
POINT_RATE = 0.2


# --- one cut -----------------------------------------------------------------------------------------


def _miter(section: list[tuple[float, float]], weight: float) -> list[tuple[float, float]]:
    """A section (counter-clockwise corners in the (y, z) plane) grown outward by `weight`: each side's
    line pushed out along its own normal, each corner where two pushed lines meet -- capped at MITRE_CAP
    weights, so the blade's two sharp edges (whose true mitre would be over two weights) stand off by their
    weight, as the contour seen from above and from behind must, and no corner spikes."""
    count = len(section)
    out = []
    for i in range(count):
        a, b, c = section[i - 1], section[i], section[(i + 1) % count]
        lines = []
        for p, q in ((a, b), (b, c)):
            dy, dz = q[0] - p[0], q[1] - p[1]
            length = math.hypot(dy, dz) or 1.0
            lines.append((dz / length, -dy / length))
        (n1y, n1z), (n2y, n2z) = lines
        det = n1y * n2z - n1z * n2y
        if abs(det) < 1e-12:
            out.append((b[0] + n1y * weight, b[1] + n1z * weight))
            continue
        oy = (weight * n2z - n1z * weight) / det
        oz = (n1y * weight - weight * n2y) / det
        reach = math.hypot(oy, oz)
        if reach > MITRE_CAP * weight:
            oy, oz = oy * MITRE_CAP * weight / reach, oz * MITRE_CAP * weight / reach
        out.append((b[0] + oy, b[1] + oz))
    return out


def _warp(t: float, peak: float) -> float:
    """The cut's own parameter with its widest point moved to `peak`: no corner there, since the lens's
    slope is zero at its middle on both sides."""
    if t <= peak:
        return 0.5 * t / peak
    return 0.5 + 0.5 * (t - peak) / (1.0 - peak)


def _lens(spec: dict, t: float) -> float:
    """The burin's pressure: a swollen middle, (1 - |2g - 1| ** fill) ** power, on a long spindle
    (1 - |2g - 1|) ** spindle that carries the pigment out along the needles -- `needle` of the width."""
    u = abs(2.0 * _warp(t, spec["peak"]) - 1.0)
    swell = max(0.0, 1.0 - u ** spec["fill"]) ** spec["power"]
    spindle = max(0.0, 1.0 - u) ** spec.get("spindle", 1.0)
    k = spec.get("needle", 0.0)
    return (1.0 - k) * swell + k * spindle


def _profile(spec: dict, t: float, seed: int) -> float:
    """0 at both points, 1 at the swollen middle, with the hand's small unevenness."""
    return _lens(spec, t) * (1.0 + 0.04 * (fbm(5.0 * t, 0.7, seed) * 2.0 - 1.0))


def _where(spec: dict, half: float, from_end: bool) -> float:
    """Where along the pigment the lens's half width reaches `half`, from the start or from the end."""
    lo, hi = (0.5, 1.0) if from_end else (0.0, 0.5)
    target = 2.0 * half / spec["width"]
    for _ in range(60):
        mid = (lo + hi) / 2.0
        inside = _lens(spec, mid) >= target
        if from_end:
            lo, hi = (mid, hi) if inside else (lo, mid)
        else:
            lo, hi = (lo, mid) if inside else (mid, hi)
    return (lo + hi) / 2.0


def _layout(spec: dict) -> tuple[float, float, float, float]:
    """Where the pigment's end rings fall along the lens (t0, t1: where it is `tip_half` wide) and how the
    lens maps onto the cut: x = -A + t * S, so the end rings stand `taper` inside each ink point."""
    t0 = _where(spec, spec["tip_half"], False)
    t1 = _where(spec, spec["tip_half"], True)
    edge = spec["length"] / 2.0 - spec["taper"]
    span = 2.0 * edge / (t1 - t0)
    return t0, t1, t0 * span + edge, span


def _stations(spec: dict) -> list[float]:
    """Along the pigment, between its two end rings: a little denser toward the needles, where the width
    turns fastest, and no ring thinner than `tip_half`."""
    t0, t1, _, span = _layout(spec)
    count = max(8, math.ceil((t1 - t0) * span / spec["spacing"]))
    out = []
    for i in range(count + 1):
        u = i / count
        u = u + 0.35 * ((0.5 - 0.5 * math.cos(math.pi * u)) - u)
        out.append(t0 + (t1 - t0) * u)
    return out


def _facet_point(ring: list, side: int, share: float):
    """A point `share` of the way from the ridge (0) to an edge (1) on the front facet of `side`
    (+1 the upper edge, -1 the lower)."""
    edge = ring[0] if side > 0 else ring[2]
    return add(ring[1], mul(sub(edge, ring[1]), share))


def _keel_point(ring: list, side: int, share: float):
    edge = ring[0] if side > 0 else ring[2]
    return add(ring[3], mul(sub(edge, ring[3]), share))


def _facet_normal(ring_a: list, ring_b: list, apex: int, side: int):
    """The outward normal of the facet between the apex (1 ridge, 3 keel) and an edge, between two rings."""
    edge = 0 if side > 0 else 2
    along = sub(ring_b[apex], ring_a[apex])
    across = sub(ring_a[edge], ring_a[apex])
    n = norm(cross(along, across))
    outward = (0.0, 0.0, 1.0) if apex == 1 else (0.0, 0.0, -1.0)
    return n if dot(n, outward) > 0 else mul(n, -1.0)


def _ring_at(rings: list, xs: list[float], x: float) -> list:
    """The pigment's section at `x`, between two rings (its edges are straight between them)."""
    for i in range(len(xs) - 1):
        if xs[i] <= x <= xs[i + 1]:
            f = (x - xs[i]) / (xs[i + 1] - xs[i])
            return [add(mul(a, 1.0 - f), mul(b, f)) for a, b in zip(rings[i], rings[i + 1])]
    raise ValueError("outside the rings")


def _strip_span(xs: list[float], ts: list[float], lo: float, hi: float):
    """A strip from `lo` to `hi` (along the pigment, kept a little inside the end rings): its two points
    (x) and the rings strictly between."""
    lo, hi = max(lo, ts[0] + 0.02), min(hi, ts[-1] - 0.02)
    x_lo = xs[0] + (lo - ts[0]) / (ts[-1] - ts[0]) * (xs[-1] - xs[0])
    x_hi = xs[0] + (hi - ts[0]) / (ts[-1] - ts[0]) * (xs[-1] - xs[0])
    inner = [i for i in range(len(xs)) if x_lo + 0.06 < xs[i] < x_hi - 0.06]
    return x_lo, x_hi, inner


def _fan_strip(mesh: Mesh, rows: list, tip_a, tip_b) -> None:
    """A strip of rows (each a list of vertex ids across it, with the facing it is seen from), closed by a
    point at each end."""
    for k in range(len(rows) - 1):
        (a, na), (b, nb) = rows[k], rows[k + 1]
        facing = add(na, nb)
        for j in range(len(a) - 1):
            mesh.tri(a[j], a[j + 1], b[j + 1], facing)
            mesh.tri(a[j], b[j + 1], b[j], facing)
    for (tip, facing_tip), (row, facing) in ((tip_a, rows[0]), (tip_b, rows[-1])):
        for j in range(len(row) - 1):
            mesh.tri(tip, row[j], row[j + 1], add(facing, facing_tip))


def _thread(core: Mesh, rings: list, xs: list, ts: list, apex: int, span: tuple, seed: int) -> None:
    """A pale lens straddling the ridge (apex 1) or the keel (apex 3): three points a station, on the
    ridge and on each facet, lifted off them; pointed at both ends, never wider than the facet's share."""
    lo, hi, share = span
    x_lo, x_hi, inner = _strip_span(xs, ts, lo, hi)
    if len(inner) < 3:
        return
    point = _facet_point if apex == 1 else _keel_point
    rows = []
    for i in inner:
        tau = (xs[i] - x_lo) / (x_hi - x_lo)
        ring = rings[i]
        nxt, prv = rings[min(i + 1, len(rings) - 1)], rings[max(i - 1, 0)]
        n_up = _facet_normal(prv, nxt, apex, +1)
        n_dn = _facet_normal(prv, nxt, apex, -1)
        mid = norm(add(n_up, n_dn))
        facet = math.dist(ring[apex], ring[0])
        from_point = min(xs[i] - x_lo, x_hi - xs[i])
        half = share * facet * math.sin(math.pi * tau) ** 0.5 * (1.0 + 0.08 * (fbm(4.0 * tau, 2.1, seed) * 2.0 - 1.0))
        u = min(half, POINT_RATE * from_point) / facet
        up = add(point(ring, +1, u), mul(n_up, THREAD_LIFT))
        on = add(ring[apex], mul(mid, THREAD_LIFT))
        dn = add(point(ring, -1, u), mul(n_dn, THREAD_LIFT))
        rows.append(([core.vert(up), core.vert(on), core.vert(dn)], mid))
    tips = []
    for x in (x_lo, x_hi):
        ring = _ring_at(rings, xs, x)
        i = min(range(len(xs)), key=lambda k: abs(xs[k] - x))
        nxt, prv = rings[min(i + 1, len(rings) - 1)], rings[max(i - 1, 0)]
        mid = norm(add(_facet_normal(prv, nxt, apex, +1), _facet_normal(prv, nxt, apex, -1)))
        tips.append((core.vert(add(ring[apex], mul(mid, THREAD_LIFT))), mid))
    _fan_strip(core, rows, tips[0], tips[1])


def _line(ink: Mesh, rings: list, xs: list, ts: list, line: tuple, seed: int) -> None:
    """An engraved burin line down a front facet: pressed in quickly, released slowly into a hair, at a
    fixed share of the facet, so it narrows toward the needles with the cut and never runs parallel to
    its neighbour; a point at each end."""
    side, share, lo, hi, width = line
    x_lo, x_hi, inner = _strip_span(xs, ts, lo, hi)
    if len(inner) < 3:
        return
    rows = []
    for i in inner:
        tau = (xs[i] - x_lo) / (x_hi - x_lo)
        press = 1.0 - (1.0 - min(1.0, tau / 0.2)) ** 2
        w = width * press * (1.0 - 0.7 * tau) * (1.0 + 0.1 * (fbm(5.0 * tau, 1.3, seed) * 2.0 - 1.0))
        from_point = min(xs[i] - x_lo, x_hi - xs[i])
        w = min(max(w, 0.012), 2.0 * POINT_RATE * from_point)
        ring = rings[i]
        nxt, prv = rings[min(i + 1, len(rings) - 1)], rings[max(i - 1, 0)]
        n = _facet_normal(prv, nxt, 1, side)
        base = add(_facet_point(ring, side, share), mul(n, LINE_LIFT))
        edge = ring[0] if side > 0 else ring[2]
        across = norm(sub(edge, ring[1]))
        rows.append(([ink.vert(add(base, mul(across, w / 2))), ink.vert(add(base, mul(across, -w / 2)))], n))
    tips = []
    for x in (x_lo, x_hi):
        ring = _ring_at(rings, xs, x)
        i = min(range(len(xs)), key=lambda k: abs(xs[k] - x))
        nxt, prv = rings[min(i + 1, len(rings) - 1)], rings[max(i - 1, 0)]
        n = _facet_normal(prv, nxt, 1, side)
        tips.append((ink.vert(add(_facet_point(ring, side, share), mul(n, LINE_LIFT))), n))
    _fan_strip(ink, rows, tips[0], tips[1])


def _closed(mesh: Mesh, rings: list[list], head, tail, inward: bool) -> None:
    """A closed spindle through `rings` (four corners each, the same turning order), shut by a point at
    each end, wound outward -- or inward, for a contour."""
    ids = [[mesh.vert(c) for c in ring] for ring in rings]
    first, last = mesh.vert(head), mesh.vert(tail)
    tris = []
    for r in range(len(ids) - 1):
        a, b = ids[r], ids[r + 1]
        for j in range(4):
            k = (j + 1) % 4
            tris += [(a[j], a[k], b[k]), (a[j], b[k], b[j])]
    for j in range(4):
        k = (j + 1) % 4
        tris += [(first, ids[0][k], ids[0][j]), (last, ids[-1][j], ids[-1][k])]
    signed = 0.0
    for a, b, c in tris:
        signed += dot(mesh.verts[a], cross(mesh.verts[b], mesh.verts[c])) / 6.0
    flip = (signed < 0) != inward
    for a, b, c in tris:
        emit(mesh, a, c, b) if flip else emit(mesh, a, b, c)


def _section(spec: dict, x: float, f: float, d: float) -> list:
    h = spec["width"] / 2.0 * f
    ridge_y = spec["ridge"] * h
    return [
        (x, h, 0.0),  # upper edge
        (x, ridge_y, d),  # ridge, toward the thrower
        (x, -h, 0.0),  # lower edge
        (x, 0.5 * ridge_y, -0.8 * d),  # keel, toward the target
    ]


def rings(spec: dict, seed: int):
    """The cut's stations (t along the lens), their x, the pigment's sections and the contour's (each grown
    by its weight), in final studs."""
    _, _, start, span = _layout(spec)
    ts = _stations(spec)
    sections, hulls, xs = [], [], []
    for t in ts:
        f = _profile(spec, t, seed)
        x = -start + t * span
        d = spec["depth"] / 2.0 * f**0.85
        weight = spec["hull_tip"] + (spec["hull_mid"] - spec["hull_tip"]) * _lens(spec, t)
        corners = _section(spec, x, f, d)
        sections.append(corners)
        xs.append(x)
        hulls.append([(x, y, z) for y, z in _miter([(c[1], c[2]) for c in corners], weight)])
    return ts, xs, sections, hulls


def _needle_scale(spec: dict, f: float) -> float:
    """How much of the end ring's contour the needle keeps a share `f` of the way to its point: none lost at
    first (it carries on the flank, no shoulder), then drawn in to a long hair."""
    return max(0.0, 1.0 - f ** spec["needle_ease"]) ** spec["needle_curve"]


def _needle(spec: dict, hull: list, sign: float) -> list:
    """The needle's rings past an end ring (sign -1 the -X end, +1 the +X end), outward from it."""
    x0 = hull[0][0]
    out = []
    for f in NEEDLE_RINGS:
        k = _needle_scale(spec, f)
        if max(abs(p[1]) for p in hull) * k < NEEDLE_MIN:
            break
        out.append([(x0 + sign * f * spec["taper"], p[1] * k, p[2] * k) for p in hull])
    return out


def cut(spec: dict, seed: int) -> tuple[Mesh, Mesh, Mesh, int]:
    """One cut in its own frame (long axis X, centred; the ridge toward +Z), in final studs: the pigment
    volume, its pale threads, its ink (hull and engraved lines), and how many of the ink's first triangles
    are the hull."""
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    reach = spec["length"] / 2.0
    ts, xs, sections, hulls = rings(spec, seed)
    # The pigment closes on its own point `close` past each end ring: still a visible red wedge, not a
    # hair, and well inside the ink's point.
    _closed(body, sections, (xs[0] - spec["close"], 0.0, 0.0), (xs[-1] + spec["close"], 0.0, 0.0), inward=False)
    # The contour: the rings grown by their weight, then each end ring drawn out into the ink's needle,
    # `taper` long, its section shrinking as (1 - (s / taper) ** needle_ease) ** needle_curve -- carrying on
    # the flank at first, then drawn in to a long hair, as a pen line closes on a point -- with no ring under
    # NEEDLE_MIN half width. Round the pigment's own point (`close` along) the contour is still over hull_tip.
    _closed(ink, _needle(spec, hulls[0], -1.0)[::-1] + hulls + _needle(spec, hulls[-1], 1.0), (-reach, 0.0, 0.0), (reach, 0.0, 0.0), inward=True)
    hull_count = len(ink.tris)
    _thread(core, sections, xs, ts, 1, spec["thread"], seed + 1)
    _thread(core, sections, xs, ts, 3, spec["keel_thread"], seed + 2)
    for n, line in enumerate(spec["lines"]):
        _line(ink, sections, xs, ts, line, seed + 3 + n)
    return body, core, ink, hull_count


# --- normalising, placing ----------------------------------------------------------------------------

_CACHE: dict = {}


def _single(name: str) -> tuple[Mesh, Mesh, Mesh, int]:
    """One cut, normalised so its tip-to-tip length, ink needles included, is exactly 1 (it is built at
    the length the game lays it, so nothing in it changes size on the way in)."""
    if name in _CACHE:
        return _CACHE[name]
    spec, seed = SPECS[name]
    body, core, ink, hull_count = cut(spec, seed)
    xs = [v[0] for m in (body, core, ink) for v in m.verts]
    span = max(xs) - min(xs)
    assert abs(span - spec["length"]) < 1e-6, (span, spec["length"])
    for m in (body, core, ink):
        m.verts = [(x / span, y / span, z / span) for x, y, z in m.verts]
    _CACHE[name] = (body, core, ink, hull_count)
    return _CACHE[name]


def _meta(seed: int) -> dict:
    return {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": seed}


def hatch_body() -> tuple[Mesh, dict]:
    return _single("Hatch")[0], _meta(SEED)


def hatch_core() -> tuple[Mesh, dict]:
    return _single("Hatch")[1], _meta(SEED + 1)


def hatch_ink() -> tuple[Mesh, dict]:
    return _single("Hatch")[2], _meta(SEED + 2)


def hatch_long_body() -> tuple[Mesh, dict]:
    return _single("HatchLong")[0], _meta(SEED + 13)


def hatch_long_core() -> tuple[Mesh, dict]:
    return _single("HatchLong")[1], _meta(SEED + 14)


def hatch_long_ink() -> tuple[Mesh, dict]:
    return _single("HatchLong")[2], _meta(SEED + 15)


def hatch_finisher_body() -> tuple[Mesh, dict]:
    return _single("HatchFinisher")[0], _meta(SEED + 7)


def hatch_finisher_core() -> tuple[Mesh, dict]:
    return _single("HatchFinisher")[1], _meta(SEED + 8)


def hatch_finisher_ink() -> tuple[Mesh, dict]:
    return _single("HatchFinisher")[2], _meta(SEED + 9)


def length(beat: dict) -> float:
    return SPECS[beat["Mesh"]][0]["length"]
