"""The central place: the raised dais, its four flights of steps, and the low walls and parapets on it.

Skins Dais and Stair<Side>1-6 (one stepped section per flight, run across its width; it replaces the
DaisEdge trims: the edge band drawn here is as wide) and Cover* / Parapet* with ONE wall mesh, drawn
20 long and stretched per instance along its length (a wall along z is turned 90), so its faces land
exactly OUT outside every wall. The dais is chalk, a vellum border ruled twice in ink inside its edge,
its flanks coursed stone; the treads chalk, the risers bone; a wall is coursed masonry.

Decor outside the wrap: none.
"""

from __future__ import annotations

from .kit import BOXES, LAYOUT, OUT, SIDES, SKIN, TOP, box, edge_ink, emit, hull, line, meshes, meta, prism, put_polygon, span

COVERS = sorted(n for n in BOXES if n.startswith("Cover") or n.startswith("Parapet"))
WALL_LEN, WALL_THICK = SKIN["Wall"]["Length"], SKIN["Wall"]["Thickness"]
WALL_H = BOXES[COVERS[0]]["Size"][1]
BORDER = 6.0


def _stairs(m, ink):
    """A flight down the middle of each side, its highest step against the dais."""
    d = LAYOUT["dais"]
    st = d["Stairs"]
    half, n, rise, tread = d["Size"] / 2, round(d["Height"] / st["Rise"]) - 1, st["Rise"], st["Tread"]
    pts = [(half, 0.0), (half + n * tread, 0.0)]
    for k in range(1, n + 1):
        pts += [(half + (n - k + 1) * tread, k * rise), (half + (n - k) * tread, k * rise)]
    roles, offs = [], []
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        if i == 0:
            roles.append("bottom"), offs.append(0.0)
        elif i == len(pts) - 1:
            roles.append("side"), offs.append(0.0)  # against the dais
        elif a[1] == b[1]:
            roles.append("top"), offs.append(TOP)
        else:
            roles.append("side"), offs.append(OUT)
    for _, sx, sz in SIDES:
        frame = (lambda sx, sz: lambda u, v, t: (sx * u + abs(sz) * t, v, sz * u + abs(sx) * t))(sx, sz)
        flight = prism(pts, frame, -st["Width"] / 2, st["Width"] / 2, offs, roles)
        emit(flight, m)
        edge_ink(flight, 0.25, ink)
        hull(flight, 0.7, 0.03, ink)


def _build_dais():
    m = meshes("top", "side", "body", "ink")
    ink = m["ink"]
    x0, x1, y0, y1, z0, z1 = span("Dais")
    solid = box(x0, x1, y0, y1, z0, z1)
    emit(solid, m)
    edge_ink(solid, 0.8, ink)
    hull(solid, 1.6, 0.03, ink)
    _stairs(m, ink)
    top = y1 + TOP
    o = [(x0 - OUT, z0 - OUT), (x1 + OUT, z0 - OUT), (x1 + OUT, z1 + OUT), (x0 - OUT, z1 + OUT)]
    i = [(x0 + BORDER, z0 + BORDER), (x1 - BORDER, z0 + BORDER), (x1 - BORDER, z1 - BORDER), (x0 + BORDER, z1 - BORDER)]
    for k in range(4):
        j = (k + 1) % 4
        put_polygon(m["body"], [(o[k][0], top, o[k][1]), (o[j][0], top, o[j][1]), (i[j][0], top, i[j][1]), (i[k][0], top, i[k][1])], (0, 1, 0), 0.02)
    for inset, width in ((BORDER, 0.5), (BORDER + 1.0, 0.25)):
        c = [(x0 + inset, z0 + inset), (x1 - inset, z0 + inset), (x1 - inset, z1 - inset), (x0 + inset, z1 - inset)]
        for k in range(4):
            j = (k + 1) % 4
            line(ink, (c[k][0], top, c[k][1]), (c[j][0], top, c[j][1]), (0, 1, 0), width, 0.04)
    # The dais's flanks laid in courses of stone.
    for k in range(4):
        (ax, az), (bx, bz) = o[k], o[(k + 1) % 4]
        n = ((bz - az), 0.0, -(bx - ax))
        nl = abs(n[0]) + abs(n[2])
        n = (n[0] / nl, 0.0, n[2] / nl)
        line(ink, (ax, y1 / 2, az), (bx, y1 / 2, bz), n, 0.35)
        length = abs(bx - ax) + abs(bz - az)
        for j in range(1, int(length / 10)):
            f = j * 10 / length
            x, z = ax + (bx - ax) * f, az + (bz - az) * f
            ya, yb = (0.2, y1 / 2) if j % 2 else (y1 / 2, y1 - 0.1)
            line(ink, (x, ya, z), (x, yb, z), n, 0.3)
    return m


def _build_wall():
    m = meshes("top", "side", "ink")
    ink = m["ink"]
    hx, hz = WALL_LEN / 2, WALL_THICK / 2
    solid = box(-hx, hx, 0.0, WALL_H, -hz, hz)
    emit(solid, m)
    edge_ink(solid, 0.4, ink)
    hull(solid, 0.8, TOP + 0.03, ink)
    courses = [WALL_H / 3, 2 * WALL_H / 3]
    joints = [[-6.0, 0.0, 6.0], [-3.0, 3.0], [-6.0, 0.0, 6.0]]
    for z, nz in ((-hz - OUT, -1.0), (hz + OUT, 1.0)):
        n = (0.0, 0.0, nz)
        for y in courses:
            line(ink, (-hx - OUT, y, z), (hx + OUT, y, z), n, 0.3)
        for k, xs in enumerate(joints):
            ya, yb = k * WALL_H / 3, (k + 1) * WALL_H / 3
            for x in xs:
                line(ink, (x, ya + 0.1, z), (x, yb - 0.1, z), n, 0.3)
    for x, nx in ((-hx - OUT, -1.0), (hx + OUT, 1.0)):
        for y in courses:
            line(ink, (x, y, -hz - OUT), (x, y, hz + OUT), (nx, 0.0, 0.0), 0.3)
    return m


_M: dict = {}


def _get(key, role):
    if key not in _M:
        _M[key] = _build_dais() if key == "dais" else _build_wall()
    return _M[key][role], meta()


def dais_top():
    return _get("dais", "top")


def dais_side():
    return _get("dais", "side")


def dais_body():
    return _get("dais", "body")


def dais_ink():
    return _get("dais", "ink")


def wall_top():
    return _get("wall", "top")


def wall_side():
    return _get("wall", "side")


def wall_ink():
    return _get("wall", "ink")


MESHES = ("dais_top", "dais_side", "dais_body", "dais_ink", "wall_top", "wall_side", "wall_ink")
