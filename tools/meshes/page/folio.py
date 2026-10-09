"""The Folio Cliffs, north-east: a rock filling the corner, closed books stacked on it, loose ones beside.

Skins FolioRock (+ FolioRockWest, FolioRockSouth), FolioTier1-3 and FolioRampWest/South/1-3 as one
landmark, and FolioLoose1-3 with ONE loose-book mesh scaled per instance.
  - The rock: bone flanks broken into facets and strata in ink, a vellum top; two boulders turned off it.
  - A tier is a closed book lying on its back, spine south (toward the camera of ref-1): page block in
    chalk ruled with page lines on the other three faces, top board and spine in warm grey, the boards'
    edges standing proud round the page block -- cut where a ramp leans on the face, so no board runs
    inside a ramp.
  - A ramp is a book slid against the next level, its slope the spine (chalk, raised bands), its sides
    the covers.

Decor outside the wrap: board rims (top 1.0 out x 1.4 thick, bottom 0.6 out x 0.9 thick; no collision).
"""

from __future__ import annotations

import math
import random

from .kit import BOXES, OUT, TOP, Mesh, box, clip_plan, edge_ink, emit, hull, line, meshes, meta, polyline, prism, span, upright, wedge, moved

ROCKS = ["FolioRock", "FolioRockWest", "FolioRockSouth"]
TIERS = ["FolioTier1", "FolioTier2", "FolioTier3"]
RAMPS = ["FolioRampWest", "FolioRampSouth", "FolioRamp1", "FolioRamp2", "FolioRamp3"]
LOOSE = ["FolioLoose1", "FolioLoose2", "FolioLoose3"]
_r = BOXES["FolioRock"]
PIVOT = (_r["X"], 0.0, _r["Z"])
TOP_BOARD = (1.0, 1.4)
LOW_BOARD = (0.6, 0.9)
PAGE_LINE = 0.3
CONTOUR, CREASE = 1.6, 0.7
SEED = 4471


def _turned(mesh: Mesh, yaw: float, offset) -> Mesh:
    a = math.radians(yaw)
    c, s = math.cos(a), math.sin(a)
    mesh.verts = [(x * c + z * s + offset[0], y + offset[1], -x * s + z * c + offset[2]) for x, y, z in mesh.verts]
    return mesh


def _local(name):
    b = BOXES[name]
    return (b["X"] - PIVOT[0], b["Base"], b["Z"] - PIVOT[2]), b["Yaw"], b["Size"]


def _cracks(ink: Mesh, rng, a, b, y0, y1, every):
    """Facets broken into a rock face from a to b (plan points, the face outward on the left of a -> b
    seen from above with z down), between heights y0 and y1."""
    ax, az = a
    bx, bz = b
    length = math.hypot(bx - ax, bz - az)
    ux, uz = (bx - ax) / length, (bz - az) / length
    normal = (uz, 0.0, -ux)
    t = rng.uniform(2, every)
    while t < length - 2:
        pts = []
        y = y1
        while y > y0 + 0.3:
            pts.append((ax + ux * t + rng.uniform(-1.2, 1.2) * ux, y, az + uz * t + rng.uniform(-1.2, 1.2) * uz))
            y -= rng.uniform(2.5, 5.0)
        pts.append((ax + ux * t, y0 + 0.2, az + uz * t))
        polyline(ink, pts, normal, 0.35)
        if rng.random() < 0.5 and t + 6 < length:
            k = rng.randrange(len(pts))
            end = (ax + ux * (t + rng.uniform(4, 8)), max(y0 + 0.4, pts[k][1] - rng.uniform(1, 4)), az + uz * (t + rng.uniform(4, 8)))
            line(ink, pts[k], end, normal, 0.3)
        t += rng.uniform(every * 0.6, every * 1.3)


def _rock(m, rng):
    ink = m["ink"]
    for name in ROCKS:
        (ox, oy, oz), yaw, (sx, sy, sz) = _local(name)
        if name == ROCKS[0]:
            solid = box(-sx / 2, sx / 2, 0.0, sy, -sz / 2, sz / 2, top="body")
        else:
            # A boulder half sunk in the rock: only what stands outside the rock's own face is drawn.
            a = math.radians(yaw)
            c, s = math.cos(a), math.sin(a)
            hx, hz = sx / 2 + OUT, sz / 2 + OUT
            plan = [(ox + x * c + z * s, oz - x * s + z * c) for x, z in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]
            rx0, rx1, _, _, rz0, rz1 = span(ROCKS[0], PIVOT)
            plan = clip_plan(plan, lambda x, z: rx0 - x if ox <= rx0 + 1e-6 else (z - rz1 if oz >= rz1 - 1e-6 else 1.0))
            solid = prism(plan, upright, 0.0, sy, [0.0] * len(plan), ["side"] * len(plan), caps=("bottom", "body"), cap_out=(0.0, TOP))
        if name == ROCKS[0]:
            solid = moved(solid, yaw, (ox, oy, oz))
        emit(solid, m)
        edge_ink(solid, CREASE, ink)
        hull(solid, CONTOUR, 0.03, ink)
        local = Mesh("up")
        hx, hz = sx / 2 + OUT, sz / 2 + OUT
        corners = [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)]
        for i in range(4):
            _cracks(local, rng, corners[i], corners[(i + 1) % 4], 0.0, sy - 0.4, 11.0 if sx > 60 else 7.0)
        # A stratum part-way up the flanks.
        for i in range(4):
            (ax, az), (bx, bz) = corners[i], corners[(i + 1) % 4]
            y = sy * rng.uniform(0.35, 0.6)
            n = ((bz - az), 0.0, -(bx - ax))
            nl = math.hypot(n[0], n[2])
            line(local, (ax + (bx - ax) * 0.1, y, az + (bz - az) * 0.1), (ax + (bx - ax) * 0.55, y + 0.8, az + (bz - az) * 0.55), (n[0] / nl, 0, n[2] / nl), 0.3)
        _turned(local, yaw, (ox, oy, oz))
        ink.merge(local)


def _ramp_cuts(tier):
    """Where a ramp's high end meets one of the tier's faces: (face, lo, hi) along that face."""
    x0, x1, _, _, z0, z1 = span(tier, PIVOT)
    cuts = []
    for name in RAMPS:
        rx0, rx1, _, _, rz0, rz1 = span(name, PIVOT)
        yaw = BOXES[name]["Yaw"] % 360
        if yaw == 90 and abs(rx1 - x0) < 1e-6:
            cuts.append(("W", rz0 - OUT, rz1 + OUT))
        elif yaw == 180 and abs(rz0 - z1) < 1e-6:
            cuts.append(("S", rx0 - OUT, rx1 + OUT))
    return cuts


def _split(lo, hi, cuts):
    parts = [(lo, hi)]
    for c0, c1 in cuts:
        parts = [p for a, b in parts for p in ((a, min(b, c0)), (max(a, c1), b)) if p[1] - p[0] > 0.01]
    return parts


def _closed_book(m, x0, x1, b, t, z0, z1, cuts=(), contour=CONTOUR, crease=CREASE, floor=0.03, spine="S", under=False):
    """A closed book over the box (x0..x1, b..t, z0..z1): page block, boards proud on three sides, the
    spine on one face. cuts: (face, lo, hi) spans where something leans on the face."""
    ink = m["ink"]
    roles = {"N": "top", "E": "top", "S": "top", "W": "top"}
    roles[spine] = "cover"
    # A loose book may overhang what it lies on: its underside is drawn too, just under its collision.
    block = box(x0, x1, b, t, z0, z1, top="cover", sides=(roles["N"], roles["E"], roles["S"], roles["W"]),
                bottom="cover" if under else "bottom", bottom_out=0.07 if under else 0.0)
    emit(block, m)
    edge_ink(block, crease * 0.65, ink)
    hull(block, contour, floor, ink)
    sx0, sx1, sz0, sz1, top = x0 - OUT, x1 + OUT, z0 - OUT, z1 + OUT, t + TOP
    for (over, thick), y0, y1, bottom, hfloor in ((TOP_BOARD, top - TOP_BOARD[1], top, "cover", -1e9), (LOW_BOARD, b, b + LOW_BOARD[1], "bottom", floor)):
        strips = []
        for face in "NESW":
            if face == spine:
                continue
            lo_z = sz0 - (0.0 if spine == "N" else over)
            hi_z = sz1 + (0.0 if spine == "S" else over)
            spans = _split(lo_z, hi_z, [(c0, c1) for f, c0, c1 in cuts if f == face]) if face in "EW" else \
                _split(sx0, sx1, [(c0, c1) for f, c0, c1 in cuts if f == face])
            for a, c in spans:
                strips.append({"N": (a, c, sz0 - over, sz0), "S": (a, c, sz1, sz1 + over),
                               "W": (sx0 - over, sx0, a, c), "E": (sx1, sx1 + over, a, c)}[face])
        for a, c, d, e in strips:
            s = box(a, c, y0, y1, d, e, top="cover", sides=("cover",) * 4, out=0.0, top_out=0.0, bottom=bottom)
            emit(s, m)
            edge_ink(s, crease * 0.5, ink)
            hull(s, contour * 0.35, hfloor, ink)
    lo, hi = b + LOW_BOARD[1], top - TOP_BOARD[1]
    faces = {"N": ((sx0, sz0), (sx1, sz0), (0, 0, -1)), "S": ((sx0, sz1), (sx1, sz1), (0, 0, 1)),
             "W": ((sx0, sz0), (sx0, sz1), (-1, 0, 0)), "E": ((sx1, sz0), (sx1, sz1), (1, 0, 0))}
    rows = max(2, int((hi - lo) / 2.2))
    for face, ((ax, az), (bx, bz), n) in faces.items():
        if face == spine:
            continue
        along_x = face in "NS"
        parts = _split(ax if along_x else az, bx if along_x else bz, [(c0, c1) for f, c0, c1 in cuts if f == face])
        for k in range(1, rows):
            y = lo + (hi - lo) * k / rows
            for p0, p1 in parts:
                a3 = (p0, y, az) if along_x else (ax, y, p0)
                b3 = (p1, y, az) if along_x else (ax, y, p1)
                line(ink, a3, b3, n, PAGE_LINE)
    # The spine: raised bands near its ends and a title label, clear of any ramp.
    (ax, az), (bx, bz), n = faces[spine]
    along_x = spine in "NS"
    span_lo, span_hi = (ax, bx) if along_x else (az, bz)
    for d in (2.5, 3.7):
        for v in (span_lo + d, span_hi - d):
            p, q = ((v, b + 0.3, az), (v, top - 0.3, az)) if along_x else ((ax, b + 0.3, v), (ax, top - 0.3, v))
            line(ink, p, q, n, 0.45)
    mid, half = (b + top) / 2, min(3.0, (top - b) / 4)
    v0 = span_lo + 0.12 * (span_hi - span_lo)
    v1 = v0 + min(14.0, 0.25 * (span_hi - span_lo))
    label = [(v0, mid - half), (v1, mid - half), (v1, mid + half), (v0, mid + half)]
    polyline(ink, [((v, y, az) if along_x else (ax, y, v)) for v, y in label], n, 0.35, closed=True)


def _ramp(m, name):
    ink = m["ink"]
    (ox, oy, oz), yaw, (sx, sy, sz) = _local(name)
    solid = moved(wedge(sx, sy, sz, top="top", back="side", caps=("cover", "cover"), back_out=0.0), yaw, (ox, oy, oz))
    emit(solid, m)
    edge_ink(solid, 0.5, ink)
    hull(solid, 0.9, oy + (TOP if oy > 0 else 0.0) + 0.03, ink)
    local = Mesh("up")
    slope = math.atan2(sy, sz)
    n = (0.0, math.cos(slope), -math.sin(slope))
    for f in (0.16, 0.2, 0.5, 0.8, 0.84):
        z = -sz / 2 + sz * f
        y = sy * f + TOP / math.cos(slope)
        line(local, (-sx / 2 - OUT + 0.4, y, z), (sx / 2 + OUT - 0.4, y, z), n, 0.45)
    ink.merge(_turned(local, yaw, (ox, oy, oz)))


def _build():
    m = meshes("top", "side", "cover", "body", "ink")
    rng = random.Random(SEED)
    _rock(m, rng)
    for name in TIERS:
        x0, x1, b, t, z0, z1 = span(name, PIVOT)
        _closed_book(m, x0, x1, b, t, z0, z1, _ramp_cuts(name), floor=b + TOP + 0.03)
    for name in RAMPS:
        _ramp(m, name)
    return m


def _build_loose():
    m = meshes("top", "cover", "ink")
    sx, sy, sz = BOXES[LOOSE[0]]["Size"]
    _closed_book(m, -sx / 2, sx / 2, 0.0, sy, -sz / 2, sz / 2, contour=0.9, crease=0.5, floor=TOP + 0.03, spine="S", under=True)
    return m


_M: dict = {}


def _get(key, role):
    if key not in _M:
        _M[key] = _build() if key == "cliffs" else _build_loose()
    return _M[key][role], meta(SEED if key == "cliffs" else 0)


def folio_top():
    return _get("cliffs", "top")


def folio_side():
    return _get("cliffs", "side")


def folio_cover():
    return _get("cliffs", "cover")


def folio_body():
    return _get("cliffs", "body")


def folio_ink():
    return _get("cliffs", "ink")


def loose_book_top():
    return _get("loose", "top")


def loose_book_cover():
    return _get("loose", "cover")


def loose_book_ink():
    return _get("loose", "ink")


MESHES = ("folio_top", "folio_side", "folio_cover", "folio_body", "folio_ink", "loose_book_top", "loose_book_cover", "loose_book_ink")
