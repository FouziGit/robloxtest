"""The Fallen Quill, north: a pen pitched across the page, a stair cut down its back, its nib in the page.

Skins QuillStep1-30, QuillRail1-2, QuillLanding and QuillTip. Authored in the quill's own frame -- x
across, z along from its foot (0) to the nib's point, y up -- and placed at Quill (X, Z) turned by
Quill.Yaw, as the layout lays the shaft.
  - The stair: one stepped section between the rails, its treads the walkable tops (chalk), risers bone.
  - The barrel: over each rail a rounded shoulder rising RADIUS above the rail's slope, so the stair runs
    in a groove down the pen's back (ref-1); its flank drops straight to the page, warm-grey below the
    pen's equator. The shoulders taper to the feather end over its first TAPER studs.
  - The landing is the grip (warm grey, ferrule bands), the tip the nib: slit, breather hole, the
    nib's shoulders drawn converging to its point, which runs on as a point drawn on the page.
  - The feather: a serrated vane drooping off each flank, barbed in ink, only as wide as the pen is
    high there, so it hangs above heads.

Decor outside the wrap: the shoulders over the rails' tops (up to RADIUS + TOP high: the rails are not
meant to be walked; the treads are exact), the two vanes, the nib's point on the page.
"""

from __future__ import annotations

import math

from .kit import LAYOUT, OUT, TOP, Solid, edge_ink, emit, hull, line, meshes, meta, polyline, prism, put_polygon

Q = LAYOUT["quill"]
STEPS, RISE, TREAD = int(Q["Steps"]), Q["Rise"], Q["Tread"]
FLIGHT, TOP_Y = STEPS * TREAD, STEPS * RISE
STAIR = Q["Width"] / 2 - Q["RailStuds"]  # the stair's half width
HALF = Q["Width"] / 2
LAND_END = FLIGHT + Q["Landing"]
TIP_END = LAND_END + Q["TipLength"]
SLOPE = TOP_Y / FLIGHT
RADIUS = Q["RailStuds"]
TAPER = 30.0
NIB_OUT = 0.05  # the nib's face is steep: 0.05 out is 0.126 up
_h = math.hypot(Q["TipLength"], TOP_Y)
N_NIB = (0.0, Q["TipLength"] / _h, TOP_Y / _h)


def rail(a: float) -> float:
    return a * SLOPE


def _stair() -> Solid:
    pts = [(0.0, 0.0), (FLIGHT, 0.0), (FLIGHT, TOP_Y)]
    for k in range(STEPS, 0, -1):
        pts += [((k - 1) * TREAD, k * RISE), ((k - 1) * TREAD, (k - 1) * RISE)]
    pts.pop()
    roles, offs = [], []
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        if i == 0:
            roles.append("bottom"), offs.append(0.0)
        elif i == 1:
            roles.append("side"), offs.append(0.0)  # against the landing
        elif a[1] == b[1]:
            roles.append("top"), offs.append(TOP)
        else:
            roles.append("side"), offs.append(OUT)
    return prism(pts, lambda u, v, t: (t, v, u), -STAIR, STAIR, offs, roles, caps=("cover", "cover"), cap_out=(0.0, 0.0))


def _barrel(s: float) -> Solid:
    """One shoulder and flank, lofted along the rail: a section (x, height over the rail, or the page)
    at each ring, the shoulder's height tapering in toward the foot."""
    rings_at = [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, TAPER, FLIGHT]
    angles = [15, 30, 45, 60, 75]
    out_x, in_x = HALF + OUT, STAIR + OUT
    solid = Solid()
    rings = []
    for a in rings_at:
        t = 0.4 + 0.6 * min(1.0, a / TAPER) ** 0.7  # never under a tread's rise over the rail
        y = rail(a)
        sec = [(STAIR, 0.0), (out_x, 0.0), (out_x, y + TOP)]
        sec += [(in_x + RADIUS * math.cos(math.radians(g)), y + TOP + t * RADIUS * math.sin(math.radians(g))) for g in angles]
        sec += [(in_x, y + TOP + t * RADIUS), (in_x, y), (STAIR, y)]
        rings.append([solid.vert((s * x, yy, a)) for x, yy in sec])
    roles = ["bottom", "side", "top"] + ["top"] * (len(angles)) + ["cover", "cover", "cover"]
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(len(r0)):
            k = (j + 1) % len(r0)
            for tri in ([r0[j], r0[k], r1[k]], [r0[j], r1[k], r1[j]]):
                if len({solid.verts[i] for i in tri}) == 3:  # the foot ring meets the page: no slivers
                    solid.poly(tri, roles[j])
    _caps(solid, rings, "side", "cover")
    return solid.orient()


def _caps(solid: Solid, rings, front: str, back: str) -> None:
    """The two end caps of a loft along +z, wound the same way as its sides (ring j -> ring j+1 quads):
    whichever way a ring turns, the front cap is the first ring reversed and the back the last as is,
    so the solid is consistent and orient() can turn it all outward."""
    solid.poly(list(reversed(rings[0])), front)
    solid.poly(rings[-1], back)


def _vane(s: float):
    """A serrated vane drooping off the flank, no wider than 0.35 of the pen's height over the page."""
    za, zb, step, thick = 4.0, 100.0, 2.5, 0.6
    vane = Solid()
    rows = []
    for i in range(int((zb - za) / step) + 1):
        a = za + i * step
        env = 9.0 * math.sin(math.pi * (a - za) / (zb - za)) ** 0.7
        notch = 1.0 - 0.4 * (((a - za) / 9.0) % 1.0)
        o = max(0.5, min(env * notch, 0.35 * rail(a)))
        x_in, yc = s * (HALF + OUT), max(rail(a) - 0.6, 0.7)
        rows.append([vane.vert((x_in, yc, a)), vane.vert((x_in + s * o, yc - 0.45 * o, a)),
                     vane.vert((x_in + s * o, yc - 0.45 * o - thick, a)), vane.vert((x_in, yc - thick, a))])
    for r0, r1 in zip(rows, rows[1:]):
        for k in range(4):
            q = [r0[k], r1[k], r1[(k + 1) % 4], r0[(k + 1) % 4]]
            vane.poly(q[:3], "side")
            vane.poly([q[0], q[2], q[3]], "side")
    _caps(vane, rows, "side", "side")
    return vane.orient(), rows


def _build():
    m = meshes("top", "side", "cover", "ink")
    ink = m["ink"]
    stair = _stair()
    emit(stair, m)
    edge_ink(stair, 0.45, ink)
    hull(stair, 0.6, 0.03, ink)
    for s in (-1.0, 1.0):
        barrel = _barrel(s)
        emit(barrel, m)
        edge_ink(barrel, 0.6, ink)
        hull(barrel, 1.4, 0.03, ink)
        # The flank's shade under the pen's equator, and the equator itself.
        x = s * (HALF + OUT)
        n = (s, 0.0, 0.0)
        lo_a, hi_a = 12.0, FLIGHT
        put_polygon(m["cover"], [(x, 0.0, lo_a), (x, 0.0, hi_a), (x, rail(hi_a) - 4.0, hi_a), (x, rail(lo_a) - 4.0, lo_a)], n, 0.02)
        line(ink, (x, rail(lo_a) - 4.0, lo_a), (x, rail(hi_a) - 4.0, hi_a), n, 0.5, 0.03)
        vane, rows = _vane(s)
        emit(vane, m)
        edge_ink(vane, 0.35, ink)
        hull(vane, 0.5, 0.03, ink)
        for row in rows[2:-2:2]:
            a, b = vane.verts[row[0]], vane.verts[row[1]]
            line(ink, a, (b[0], b[1], b[2] - 3.0), (s * 0.4, 1.0, 0.0), 0.3, 0.06)
    # The grip, and the nib.
    grip = prism([(FLIGHT, 0.0), (LAND_END, 0.0), (LAND_END, TOP_Y), (FLIGHT, TOP_Y)], lambda u, v, t: (t, v, u), -HALF, HALF,
                 [0.0, 0.0, TOP, 0.0], ["bottom", "side", "cover", "cover"], caps=("cover", "cover"))
    emit(grip, m)
    edge_ink(grip, 0.6, ink)
    hull(grip, 1.4, 0.03, ink)
    for a in (FLIGHT + 2.5, LAND_END - 2.5):
        y = TOP_Y + TOP
        line(ink, (-HALF - OUT, y, a), (HALF + OUT, y, a), (0, 1, 0), 0.8)
        for s in (-1.0, 1.0):
            line(ink, (s * (HALF + OUT), y - 0.3, a), (s * (HALF + OUT), 1.0, a), (s, 0, 0), 0.8)
    tip = prism([(LAND_END, 0.0), (TIP_END, 0.0), (LAND_END, TOP_Y)], lambda u, v, t: (t, v, u), -HALF, HALF,
                [0.0, NIB_OUT, 0.0], ["bottom", "cover", "side"], caps=("cover", "cover"))
    emit(tip, m)
    edge_ink(tip, 0.6, ink)
    hull(tip, 1.4, 0.03, ink)

    def face(x, a):
        y = (TIP_END - a) * TOP_Y / Q["TipLength"]
        return (x + N_NIB[0] * NIB_OUT, y + N_NIB[1] * NIB_OUT, a + N_NIB[2] * NIB_OUT)

    point = (0.0, TIP_END - 0.6)
    for s in (-1.0, 1.0):
        line(ink, face(s * (HALF - 1.0), LAND_END + 1.5), face(s * 1.2, TIP_END - 1.0), N_NIB, 0.6)
    line(ink, face(0.0, LAND_END + 9.0), face(0.0, point[1]), N_NIB, 0.5)
    c = LAND_END + 8.0
    put_polygon(ink, [face(0, c - 1.6), face(1.6, c), face(0, c + 1.6), face(-1.6, c)], N_NIB, 0.02)
    # The nib's point, run on as a drawing on the page.
    tri = [(-HALF * 0.6, 0.04, TIP_END + 0.3), (HALF * 0.6, 0.04, TIP_END + 0.3), (0.0, 0.04, TIP_END + 9.0)]
    put_polygon(m["cover"], tri, (0, 1, 0))
    polyline(ink, tri, (0, 1, 0), 0.5, closed=True)
    line(ink, (0.0, 0.04, TIP_END + 0.3), (0.0, 0.04, TIP_END + 6.0), (0, 1, 0), 0.35)
    return m


_M: dict = {}


def _get(role):
    if not _M:
        _M.update(_build())
    return _M[role], meta()


def quill_top():
    return _get("top")


def quill_side():
    return _get("side")


def quill_cover():
    return _get("cover")


def quill_ink():
    return _get("ink")


MESHES = ("quill_top", "quill_side", "quill_cover", "quill_ink")
