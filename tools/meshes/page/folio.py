"""The Folio Cliffs, north-east: a rock filling the corner, boulders round its foot, closed books stacked on it at
varied turns and leaning on the tiers' faces, loose ones beside.

Two skins over one pivot, FolioRock's centre on the floor (BattlegroundLayout.skins):
  - FolioRock skins the rock and its boulders FolioRock1..n. The rock: a chalk plateau over bone flanks broken
    into facets and strata in ink. A boulder: a block turned and tipped as its collision is (Yaw, then Pitch about
    its own x), sunk under the floor, its faces cracked in ink; whatever of it lies inside the rock is drawn and
    hidden by the rock.
  - FolioCliffs skins FolioTier1-3, FolioLean1-3 and FolioRamp*. A tier or a leaning book is a closed book built
    in its own frame and turned (and tipped) with it: page block in chalk ruled with page lines on three faces, top
    board and spine in warm grey, the boards' edges standing proud round the page block -- cut where a ramp leans
    on the face, so no board runs inside a ramp. A book that overhangs what it rests on, or leans, has its
    underside drawn too.
  - A ramp is a book slid against the next level, square to the face it climbs: its slope the spine (chalk,
    raised bands), its sides the covers.

FolioLoose1-3 are ONE loose-book mesh scaled per instance.

Decor outside the wrap: board rims (top 1.0 out x 1.4 thick, bottom 0.6 out x 0.9 thick; no collision).
"""

from __future__ import annotations

import math
import random

from .kit import BOXES, OUT, TOP, Mesh, box, edge_ink, emit, hull, line, meshes, meta, polyline, wedge, moved

ROCK = "FolioRock"
BOULDERS = sorted((n for n in BOXES if n.startswith(ROCK) and n != ROCK), key=lambda n: int(n[len(ROCK):]))
TIERS = sorted(n for n in BOXES if n.startswith("FolioTier"))
LEANS = sorted(n for n in BOXES if n.startswith("FolioLean"))
RAMPS = [n for n in BOXES if n.startswith("FolioRamp")]
LOOSE = ["FolioLoose1", "FolioLoose2", "FolioLoose3"]
_r = BOXES[ROCK]
PIVOT = (_r["X"], 0.0, _r["Z"])
TOP_BOARD = (1.0, 1.4)
LOW_BOARD = (0.6, 0.9)
PAGE_LINE = 0.3
CONTOUR, CREASE = 1.6, 0.7
# A boulder's contour, thinner than the rock's: its hull stays under the plateau's top where it hugs the rock.
BOULDER_CONTOUR = 1.1
SEED = 4471


def _turned(mesh: Mesh, yaw: float, offset) -> Mesh:
    a = math.radians(yaw)
    c, s = math.cos(a), math.sin(a)
    mesh.verts = [(x * c + z * s + offset[0], y + offset[1], -x * s + z * c + offset[2]) for x, y, z in mesh.verts]
    return mesh


def _local(name):
    b = BOXES[name]
    return (b["X"] - PIVOT[0], b["Base"], b["Z"] - PIVOT[2]), b["Yaw"], b["Size"]


def _frame(name):
    """A box's own frame (centred on it) -> the skin's: tipped by its Pitch about its own x, turned by its Yaw,
    moved to its centre -- as the engine places the part (CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0))."""
    b = BOXES[name]
    at = (b["X"] - PIVOT[0], b["Y"], b["Z"] - PIVOT[2])
    p, y = math.radians(b["Pitch"]), math.radians(b["Yaw"])
    cp, sp, cy, sy = math.cos(p), math.sin(p), math.cos(y), math.sin(y)

    def xf(v):
        x, h, z = v
        h, z = h * cp - z * sp, h * sp + z * cp
        return (x * cy + z * sy + at[0], h + at[1], -x * sy + z * cy + at[2])

    return xf


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


def _faces(ink: Mesh, rng, sx, sy, sz, every, strata):
    """Cracks over the four faces of a block centred on its own frame, and a stratum part-way up each."""
    hx, hz = sx / 2 + OUT, sz / 2 + OUT
    corners = [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)]
    for i in range(4):
        _cracks(ink, rng, corners[i], corners[(i + 1) % 4], -sy / 2, sy / 2 - 0.4, every)
    if not strata:
        return
    for i in range(4):
        (ax, az), (bx, bz) = corners[i], corners[(i + 1) % 4]
        y = -sy / 2 + sy * rng.uniform(0.35, 0.6)
        n = ((bz - az), 0.0, -(bx - ax))
        nl = math.hypot(n[0], n[2])
        line(ink, (ax + (bx - ax) * 0.1, y, az + (bz - az) * 0.1), (ax + (bx - ax) * 0.55, y + 0.8, az + (bz - az) * 0.55), (n[0] / nl, 0, n[2] / nl), 0.3)


def _block(m, name, rng, contour, crease, every, strata):
    """A rock or a boulder: its box skinned in its own frame, placed as its collision is, inked."""
    ink = m["ink"]
    sx, sy, sz = BOXES[name]["Size"]
    xf = _frame(name)
    solid = box(-sx / 2, sx / 2, -sy / 2, sy / 2, -sz / 2, sz / 2, top="top")
    solid.verts = [xf(v) for v in solid.verts]
    emit(solid, m)
    edge_ink(solid, crease, ink)
    hull(solid, contour, 0.03, ink)
    local = Mesh("up")
    _faces(local, rng, sx, sy, sz, every, strata)
    local.verts = [xf(v) for v in local.verts]
    ink.merge(local)


def _rock(m, rng):
    _block(m, ROCK, rng, CONTOUR, CREASE, 11.0, True)
    for name in BOULDERS:
        _block(m, name, rng, BOULDER_CONTOUR, CREASE * 0.8, 6.0, False)


def _ramp_cuts(book):
    """Where a ramp's high end meets one of the book's faces, in the book's own frame: (face, lo, hi) along it."""
    t = BOXES[book]
    sx, _, sz = t["Size"]
    a = math.radians(t["Yaw"])
    c, s = math.cos(a), math.sin(a)
    cuts = []
    for name in RAMPS:
        r = BOXES[name]
        if abs(r["Base"] - t["Base"]) > 1e-6:
            continue
        dx, dz = r["X"] - t["X"], r["Z"] - t["Z"]
        lx, lz = dx * c - dz * s, dx * s + dz * c
        width, length = r["Size"][0], r["Size"][2]
        turn = (r["Yaw"] - t["Yaw"]) % 360
        if abs(turn - 90) < 1e-6 and abs(lx + sx / 2 + length / 2) < 0.5:
            cuts.append(("W", lz - width / 2 - OUT, lz + width / 2 + OUT))
        elif abs(turn - 180) < 1e-6 and abs(lz - sz / 2 - length / 2) < 0.5:
            cuts.append(("S", lx - width / 2 - OUT, lx + width / 2 + OUT))
    return cuts


def _split(lo, hi, cuts):
    parts = [(lo, hi)]
    for c0, c1 in cuts:
        parts = [p for a, b in parts for p in ((a, min(b, c0)), (max(a, c1), b)) if p[1] - p[0] > 0.01]
    return parts


def _closed_book(m, x0, x1, b, t, z0, z1, cuts=(), contour=CONTOUR, crease=CREASE, floor=0.03, spine="S", under=False, xf=None):
    """A closed book over the box (x0..x1, b..t, z0..z1): page block, boards proud on three sides, the
    spine on one face. cuts: (face, lo, hi) spans where something leans on the face. xf places the book's own
    frame in the skin's (a turn, a tip); `floor` is a height of the skin's."""
    ink = m["ink"]

    def put(solid, crease_w, contour_w, hfloor):
        if xf is not None:
            solid.verts = [xf(v) for v in solid.verts]
        emit(solid, m)
        edge_ink(solid, crease_w, ink)
        hull(solid, contour_w, hfloor, ink)

    roles = {"N": "top", "E": "top", "S": "top", "W": "top"}
    roles[spine] = "cover"
    # A loose book may overhang what it lies on: its underside is drawn too, just under its collision.
    block = box(x0, x1, b, t, z0, z1, top="cover", sides=(roles["N"], roles["E"], roles["S"], roles["W"]),
                bottom="cover" if under else "bottom", bottom_out=0.07 if under else 0.0)
    put(block, crease * 0.65, contour, floor)
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
            put(s, crease * 0.5, contour * 0.35, hfloor)
    lines = Mesh("up")
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
                line(lines, a3, b3, n, PAGE_LINE)
    # The spine: raised bands near its ends and a title label, clear of any ramp.
    (ax, az), (bx, bz), n = faces[spine]
    along_x = spine in "NS"
    span_lo, span_hi = (ax, bx) if along_x else (az, bz)
    for d in (2.5, 3.7):
        for v in (span_lo + d, span_hi - d):
            p, q = ((v, b + 0.3, az), (v, top - 0.3, az)) if along_x else ((ax, b + 0.3, v), (ax, top - 0.3, v))
            line(lines, p, q, n, 0.45)
    mid, half = (b + top) / 2, min(3.0, (top - b) / 4)
    v0 = span_lo + 0.12 * (span_hi - span_lo)
    v1 = v0 + min(14.0, 0.25 * (span_hi - span_lo))
    label = [(v0, mid - half), (v1, mid - half), (v1, mid + half), (v0, mid + half)]
    polyline(lines, [((v, y, az) if along_x else (ax, y, v)) for v, y in label], n, 0.35, closed=True)
    if xf is not None:
        lines.verts = [xf(v) for v in lines.verts]
    ink.merge(lines)


def _book(m, name, **kw):
    """A tier or a leaning book, built in its own frame and placed as its collision is."""
    sx, sy, sz = BOXES[name]["Size"]
    _closed_book(m, -sx / 2, sx / 2, -sy / 2, sy / 2, -sz / 2, sz / 2, _ramp_cuts(name), xf=_frame(name), **kw)


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


def _build_rock():
    m = meshes("top", "side", "ink")
    _rock(m, random.Random(SEED))
    return m


def _build():
    m = meshes("top", "side", "cover", "ink")
    for i, name in enumerate(TIERS):
        # The first lies wholly on the rock; a higher one may overhang the tier under it by a stud or two.
        _book(m, name, floor=BOXES[name]["Base"] + TOP + 0.03, under=i > 0)
    for name in LEANS:
        # Tipped: its low edge sinks into what it rests on and its high end into the face it leans on, so its
        # contour is drawn whole and hidden where it is buried.
        _book(m, name, contour=1.1, crease=0.55, floor=-1e9, spine="W", under=True)
    for name in RAMPS:
        _ramp(m, name)
    return m


def _build_loose():
    m = meshes("top", "cover", "ink")
    sx, sy, sz = BOXES[LOOSE[0]]["Size"]
    _closed_book(m, -sx / 2, sx / 2, 0.0, sy, -sz / 2, sz / 2, contour=0.9, crease=0.5, floor=TOP + 0.03, spine="S", under=True)
    return m


_BUILDERS = {"cliffs": _build, "rock": _build_rock, "loose": _build_loose}
_SEEDS = {"cliffs": 0, "rock": SEED, "loose": 0}
_M: dict = {}


def _get(key, role):
    if key not in _M:
        _M[key] = _BUILDERS[key]()
    return _M[key][role], meta(_SEEDS[key])


def folio_top():
    return _get("cliffs", "top")


def folio_side():
    return _get("cliffs", "side")


def folio_cover():
    return _get("cliffs", "cover")


def folio_ink():
    return _get("cliffs", "ink")


def folio_rock_top():
    return _get("rock", "top")


def folio_rock_side():
    return _get("rock", "side")


def folio_rock_ink():
    return _get("rock", "ink")


def loose_book_top():
    return _get("loose", "top")


def loose_book_cover():
    return _get("loose", "cover")


def loose_book_ink():
    return _get("loose", "ink")


MESHES = ("folio_top", "folio_side", "folio_cover", "folio_ink", "folio_rock_top", "folio_rock_side", "folio_rock_ink",
          "loose_book_top", "loose_book_cover", "loose_book_ink")
