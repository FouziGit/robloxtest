"""The Stitch Bridge, east, over the ruled bed: a deck between two ramps, its planks sewn together.

Skins BridgeDeck, BridgeRampWest and BridgeRampEast as one section (the ramps and the deck side by side
along x) pushed out and run across z; and draws the marks Stitch1-3 A/B itself, as thread: an ink cross
over every seam, the thread wrapping down both sides of the deck.

Decor outside the wrap: none.
"""

from __future__ import annotations

import math

from .kit import BOXES, LAYOUT, OUT, TOP, edge_ink, emit, hull, line, meshes, meta, prism, span

DECK, WEST, EAST = "BridgeDeck", "BridgeRampWest", "BridgeRampEast"
_d = BOXES[DECK]
PIVOT = (_d["X"], 0.0, _d["Z"])
STITCHES = sorted({n[:-1] for n in LAYOUT["marks"] if n.startswith("Stitch")})


def _build():
    m = meshes("top", "cover", "ink")
    ink = m["ink"]
    d, w, e = span(DECK, PIVOT), span(WEST, PIVOT), span(EAST, PIVOT)
    h = d[3]
    section = [(w[0], 0.0), (e[1], 0.0), (d[1], h), (d[0], h)]
    skin = prism(section, lambda u, v, t: (u, v, t), d[4], d[5], [0.0, TOP, TOP, TOP], ["bottom", "top", "top", "top"], caps=("cover", "cover"))
    emit(skin, m)
    edge_ink(skin, 0.5, ink)
    hull(skin, 1.1, 0.03, ink)
    top = h + TOP
    z0, z1 = d[4] - OUT, d[5] + OUT
    slope = math.atan2(h, w[1] - w[0])
    # Plank seams: on the deck under every stitch and at the ramps, then every 4 studs down each ramp.
    seams = [LAYOUT["marks"][s + "A"]["X"] - PIVOT[0] for s in STITCHES]
    planks = [d[0] + 5.0 * k for k in range(1, int((d[1] - d[0]) / 5.0)) if all(abs(d[0] + 5.0 * k - s) > 1.0 for s in seams)]
    for x in planks:
        line(ink, (x, top, z0 + 0.3), (x, top, z1 - 0.3), (0, 1, 0), 0.2)
    for x in seams + [d[0] + 0.15, d[1] - 0.15]:
        line(ink, (x, top, z0 + 0.3), (x, top, z1 - 0.3), (0, 1, 0), 0.35)
    for sign, foot, head in ((-1, w[0], w[1]), (1, e[1], e[0])):
        for k in (1, 2):
            x = head + (foot - head) * k / 3
            y = h * (1 - k / 3) + TOP / math.cos(slope)
            n = (sign * math.sin(slope), math.cos(slope), 0.0)
            line(ink, (x, y, z0 + 0.3), (x, y, z1 - 0.3), n, 0.3)
    # The stitches: the layout's cross, as thread, and its loops down both sides of the deck.
    for s in STITCHES:
        for part in "AB":
            mk = LAYOUT["marks"][s + part]
            a = math.radians(mk["Yaw"])
            ux, uz = math.cos(a) * mk["SizeX"] / 2, -math.sin(a) * mk["SizeX"] / 2
            cx, cz = mk["X"] - PIVOT[0], mk["Z"] - PIVOT[2]
            line(ink, (cx - ux, top, cz - uz), (cx + ux, top, cz + uz), (0, 1, 0), mk["SizeZ"], 0.04)
        cx = LAYOUT["marks"][s + "A"]["X"] - PIVOT[0]
        for z, nz in ((z0, -1.0), (z1, 1.0)):
            for dx in (-1.6, 1.6):
                line(ink, (cx + dx, top - 0.05, z), (cx + dx * 0.4, 0.9, z), (0, 0, nz), 0.5)
    return m


_M: dict = {}


def _get(role):
    if not _M:
        _M.update(_build())
    return _M[role], meta()


def bridge_top():
    return _get("top")


def bridge_cover():
    return _get("cover")


def bridge_ink():
    return _get("ink")


MESHES = ("bridge_top", "bridge_cover", "bridge_ink")
