"""The Scriptorium's ruins, south-west: the arcade wall, its broken reading desks and stumps.

Skins ArcadePier*, ArcadeBeam and ArcadeCorbel* with one arcade mesh (authored along its own x, placed
at Arcade (X, Z) turned by Arcade.Yaw); Desk* blocks with ONE desk mesh, the tipped Desk* wedges with
ONE tipped-desk mesh, DeskStump* with ONE stump mesh, each scaled per instance so its faces land
exactly OUT outside its own box (scale = (S/2 + OUT) / (REF/2 + OUT) across, (H + TOP) / (REF_H + TOP)
up).
The arcade is one section -- the piers, the beam over them all -- whose every opening closes in a round
arch springing low enough to pass under the corbels (they and the beam's underside sit in its
spandrels), stone courses, voussoirs and a crack ruled in ink.

Decor outside the wrap: the arches' spandrels (inside each opening, from SPRING up; no collision).
"""

from __future__ import annotations

import math

from .kit import BOXES, LAYOUT, OUT, TOP, box, edge_ink, emit, hull, line, meshes, meta, polyline, prism, put_polygon, wedge

A = LAYOUT["arcade"]
BAY = A["Pier"] + A["Opening"]
LENGTH = A["Arches"] * BAY + A["Pier"]
PIER_H = A["Height"] - A["Beam"]
HW = A["Opening"] / 2 - OUT  # an opening's half width, skin to skin
CORBEL_IN = A["Opening"] / 2 - A["Corbel"]["Width"] - OUT  # a corbel's inner face, from the opening's centre
CORBEL_LO = PIER_H - A["Corbel"]["Height"] - OUT
# A round arch of the opening's width, sprung low enough that it passes under both corbels.
SPRING = CORBEL_LO - math.sqrt(HW * HW - CORBEL_IN * CORBEL_IN)
DESKS = sorted(n for n in BOXES if n.startswith("Desk") and not n.startswith("DeskStump") and BOXES[n]["Shape"] == "Block")
TIPPED = sorted(n for n in BOXES if n.startswith("Desk") and BOXES[n]["Shape"] == "Wedge")
STUMPS = sorted(n for n in BOXES if n.startswith("DeskStump"))
DESK_REF = BOXES[DESKS[0]]["Size"]
TIPPED_REF = BOXES[TIPPED[0]]["Size"]
STUMP_REF = BOXES[STUMPS[0]]["Size"]


def _centres():
    return [-LENGTH / 2 + A["Pier"] + (k + 0.5) * A["Opening"] + k * A["Pier"] for k in range(int(A["Arches"]))]


def _section():
    half = LENGTH / 2 + OUT
    pts = [(-half, 0.0)]
    roles = []
    for c in _centres():
        pts += [(c - HW, 0.0), (c - HW, SPRING)]
        roles += ["bottom", "cover"]
        for k in range(1, 12):
            g = math.pi - math.pi * k / 12
            pts.append((c + HW * math.cos(g), SPRING + HW * math.sin(g)))
            roles.append("cover")
        pts += [(c + HW, SPRING), (c + HW, 0.0)]
        roles += ["cover", "cover"]
    pts += [(half, 0.0), (half, A["Height"] + TOP), (-half, A["Height"] + TOP)]
    roles += ["bottom", "side", "top", "side"]
    return pts, roles


def _build_arcade():
    m = meshes("top", "side", "cover", "ink")
    ink = m["ink"]
    pts, roles = _section()
    t = A["Thickness"] / 2
    solid = prism(pts, lambda u, v, w: (u, v, w), -t, t, [0.0] * len(pts), roles)
    emit(solid, m)
    edge_ink(solid, 0.6, ink)
    hull(solid, 1.2, 0.03, ink)
    half = LENGTH / 2 + OUT
    for z, nz in ((-t - OUT, -1.0), (t + OUT, 1.0)):
        n = (0.0, 0.0, nz)
        line(ink, (-half, PIER_H, z), (half, PIER_H, z), n, 0.4)
        piers = [-LENGTH / 2 + k * BAY for k in range(int(A["Arches"]) + 1)]
        for p in piers:
            x0 = max(p - OUT, -half)
            x1 = min(p + A["Pier"] + OUT, half)
            for y in (5.0, 10.0):
                line(ink, (x0, y, z), (x1, y, z), n, 0.3)
        for c in _centres():
            for k in range(2, 11, 2):
                g = math.pi - math.pi * k / 12
                a = (c + HW * math.cos(g), SPRING + HW * math.sin(g))
                b = (c + (HW + 3.5) * math.cos(g), SPRING + (HW + 3.5) * math.sin(g))
                line(ink, (a[0], a[1], z), (b[0], b[1], z), n, 0.3)
        crack = [(-half + 30.0, A["Height"], z), (-half + 28.0, A["Height"] - 3.0, z), (-half + 30.5, A["Height"] - 5.5, z), (-half + 29.0, PIER_H - 1.0, z)]
        polyline(ink, crack, n, 0.4)
    return m


def _desk_decals(m, hx, hz, top, board):
    ink = m["ink"]
    leg = 1.2
    for n, a, b in (((0, 0, -1), (-hx - OUT, -hz - OUT), (hx + OUT, -hz - OUT)), ((1, 0, 0), (hx + OUT, -hz - OUT), (hx + OUT, hz + OUT)),
                    ((0, 0, 1), (hx + OUT, hz + OUT), (-hx - OUT, hz + OUT)), ((-1, 0, 0), (-hx - OUT, hz + OUT), (-hx - OUT, -hz - OUT))):
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length

        def at(t, y):
            return (a[0] + ux * t, y, a[1] + uz * t)

        recess = [at(leg, 0.0), at(length - leg, 0.0), at(length - leg, board - 0.4), at(leg, board - 0.4)]
        put_polygon(m["cover"], recess, n, 0.02)
        polyline(ink, recess[1:] + recess[:1], n, 0.3, 0.04)
        line(ink, at(0.1, board), at(length - 0.1, board), n, 0.35)


def _build_desk():
    m = meshes("top", "side", "cover", "ink")
    ink = m["ink"]
    sx, sy, sz = DESK_REF
    hx, hz = sx / 2, sz / 2
    solid = box(-hx, hx, 0.0, sy, -hz, hz)
    emit(solid, m)
    edge_ink(solid, 0.35, ink)
    hull(solid, 0.6, 0.03, ink)
    top = sy + TOP
    _desk_decals(m, hx, hz, top, top - 1.2)
    bx, bz = 0.28 * hx, 0.32 * hz
    page = [(-bx * 2, top, -bz), (0.0, top, -bz * 1.15), (bx * 2, top, -bz), (bx * 2, top, bz), (0.0, top, bz * 1.15), (-bx * 2, top, bz)]
    polyline(ink, page, (0, 1, 0), 0.25, closed=True)
    line(ink, (0.0, top, -bz * 1.15), (0.0, top, bz * 1.15), (0, 1, 0), 0.25)
    crack = [(-hx - OUT, top, hz * 0.6), (-hx * 0.5, top, hz * 0.15), (-hx * 0.2, top, hz * 0.7), (hx * 0.15, top, hz + OUT)]
    polyline(ink, crack, (0, 1, 0), 0.3)
    return m


def _build_tipped():
    m = meshes("top", "side", "cover", "ink")
    ink = m["ink"]
    sx, sy, sz = TIPPED_REF
    solid = wedge(sx, sy, sz, top="top", back="cover", caps=("side", "side"))
    emit(solid, m)
    edge_ink(solid, 0.35, ink)
    hull(solid, 0.6, 0.03, ink)
    slope = math.atan2(sy, sz)
    n = (0.0, math.cos(slope), -math.sin(slope))

    def on(x, f):
        return (x, sy * f + TOP / math.cos(slope), -sz / 2 + sz * f)

    frame = [on(-sx / 2 + 1.2, 0.15), on(sx / 2 - 1.2, 0.15), on(sx / 2 - 1.2, 0.85), on(-sx / 2 + 1.2, 0.85)]
    polyline(ink, frame, n, 0.3, closed=True)
    # Its legs, seen from under it now it lies tipped: two bars across the back.
    for y in (sy * 0.3, sy * 0.7):
        line(ink, (-sx / 2 - OUT + 0.3, y, sz / 2 + OUT), (sx / 2 + OUT - 0.3, y, sz / 2 + OUT), (0, 0, 1), 0.5)
    return m


def _build_stump():
    m = meshes("top", "side", "ink")
    ink = m["ink"]
    sx, sy, sz = STUMP_REF
    hx, hz = sx / 2, sz / 2
    solid = box(-hx, hx, 0.0, sy, -hz, hz)
    emit(solid, m)
    edge_ink(solid, 0.35, ink)
    hull(solid, 0.6, 0.03, ink)
    for n, a, b in (((0, 0, -1), (-hx, -hz - OUT), (hx, -hz - OUT)), ((1, 0, 0), (hx + OUT, -hz), (hx + OUT, hz)),
                    ((0, 0, 1), (hx, hz + OUT), (-hx, hz + OUT)), ((-1, 0, 0), (-hx - OUT, hz), (-hx - OUT, -hz))):
        for f in (0.33, 0.66):
            p = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
            line(ink, (p[0], 0.4, p[1]), (p[0], sy - 0.8, p[1]), n, 0.3)
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        line(ink, (a[0], sy - 0.6, a[1]), (mid[0], sy - 1.6, mid[1]), n, 0.35)
        line(ink, (mid[0], sy - 1.6, mid[1]), (b[0], sy - 0.5, b[1]), n, 0.35)
    return m


BUILDERS = {"arcade": _build_arcade, "desk": _build_desk, "tipped": _build_tipped, "stump": _build_stump}
_M: dict = {}


def _get(key, role):
    if key not in _M:
        _M[key] = BUILDERS[key]()
    return _M[key][role], meta()


ROLES = {"arcade": ("top", "side", "cover", "ink"), "desk": ("top", "side", "cover", "ink"),
         "tipped": ("top", "side", "cover", "ink"), "stump": ("top", "side", "ink")}
for _k, _rs in ROLES.items():
    for _r in _rs:
        globals()[f"{_k}_{_r}"] = (lambda k=_k, r=_r: _get(k, r))


MESHES = tuple(f"{k}_{r}" for k, rs in ROLES.items() for r in rs)
