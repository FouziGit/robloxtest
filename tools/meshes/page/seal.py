"""The Field of Seals, south: wax discs, and the ink blots drawn on the page.

Skins Seal1-9 with ONE seal mesh, and replaces the marks Blot1-3 with ONE blot mesh. The seal is drawn
at a reference size (D_REF across, H_REF high) and each instance is scaled so its skin lands exactly
OUT outside its own cylinder and TOP over its own top: scale = ((R + OUT) / (R_REF + OUT),
(H + TOP) / (H_REF + TOP), same as x). The disc is a 32-gon whose faces stand OUT outside the circle;
its top a chalk ring round a warm-grey pressed face, an ink ring and a stamped star; at its foot the
wax spread over the page, lumpy, 0.25 high.

Decor outside the wrap: the wax spread (1.3-2.6 studs past the disc, 0.12 high at reference size); a seal stacked
on another (Seal*Top) uses the same recipe without it (seal_stacked_*).
"""

from __future__ import annotations

import math

from .kit import OUT, SKIN, TOP, edge_ink, emit, hull, line, meshes, meta, polyline, prism, upright

D_REF, H_REF = SKIN["Seal"]["Diameter"], SKIN["Seal"]["Height"]
SPREAD_H = 0.12  # under 0.15 even scaled: a stacked seal's foot may lie on a walkable top
BLOT_REF = SKIN["BlotStuds"]
SIDES = 32


def _ring(radius_fn, count, phase=0.0):
    return [(radius_fn(2 * math.pi * (k + phase) / count) * math.cos(2 * math.pi * (k + phase) / count),
             radius_fn(2 * math.pi * (k + phase) / count) * math.sin(2 * math.pi * (k + phase) / count)) for k in range(count)]


def _build_seal(spread_wax: bool):
    m = meshes("top", "side", "cover", "ink")
    ink = m["ink"]
    r = D_REF / 2
    apothem = r + OUT
    disc_plan = _ring(lambda a: apothem / math.cos(math.pi / SIDES), SIDES, 0.5)
    disc = prism(disc_plan, upright, 0.0, H_REF, [0.0] * SIDES, ["side"] * SIDES, caps=("bottom", "top"), cap_out=(0.0, TOP))
    solids = [(disc, 0.45, 0.7, (SPREAD_H if spread_wax else TOP) + 0.03)]
    if spread_wax:
        plan = _ring(lambda a: r + 1.8 + 0.5 * math.sin(5 * a + 0.7) + 0.3 * math.sin(11 * a + 2.1), 40)
        spread = prism(plan, upright, 0.0, SPREAD_H, [0.0] * 40, ["cover"] * 40, caps=("bottom", "cover"), cap_out=(0.0, 0.0))
        solids.append((spread, 0.35, 0.5, 0.03))
    for solid, c, w, floor in solids:
        emit(solid, m)
        edge_ink(solid, c, ink)
        hull(solid, w, floor, ink)
    top = H_REF + TOP
    face = 0.62 * r
    pressed = prism(_ring(lambda a: face, 32), upright, top, top + 0.02, [0.0] * 32, ["cover"] * 32, caps=("bottom", "cover"), cap_out=(0.0, 0.0))
    emit(pressed, m)
    polyline(ink, [(x, top + 0.02, z) for x, z in _ring(lambda a: face, 40)], (0, 1, 0), 0.45, 0.02, closed=True)
    for k in range(3):
        a = math.pi * k / 3 + 0.3
        tip = (0.62 * face * math.cos(a), 0.62 * face * math.sin(a))
        line(ink, (tip[0], top + 0.02, tip[1]), (-tip[0], top + 0.02, -tip[1]), (0, 1, 0), 0.6, 0.02)
    # The wax's rim: a second ring just in from the edge, where the wax rolled when it was pressed.
    polyline(ink, [(x, top, z) for x, z in _ring(lambda a: r - 1.6 + 0.25 * math.sin(7 * a), 40)], (0, 1, 0), 0.3, 0.02, closed=True)
    return m


def _build_blot():
    m = meshes("ink")
    r = BLOT_REF / 2
    main = _ring(lambda a: r * (1.3 + 0.15 * math.sin(3 * a + 1.0) + 0.1 * math.sin(7 * a + 2.0)), 36)
    parts = [main]
    for a, dist, size in ((0.4, 1.9, 0.22), (1.9, 1.75, 0.14), (3.6, 2.1, 0.18), (5.0, 1.8, 0.12)):
        cx, cz = r * dist * math.cos(a), r * dist * math.sin(a)
        parts.append([(cx + x, cz + z) for x, z in _ring(lambda t: r * size, 10)])
    for plan in parts:
        n = len(plan)
        emit(prism(plan, upright, 0.0, 0.05, [0.0] * n, ["ink"] * n, caps=("bottom", "ink"), cap_out=(0.0, 0.0)), m)
    return m


_M: dict = {}


def _get(key, role):
    if key not in _M:
        _M[key] = {"seal": lambda: _build_seal(True), "stacked": lambda: _build_seal(False), "blot": _build_blot}[key]()
    return _M[key][role], meta()


def seal_top():
    return _get("seal", "top")


def seal_side():
    return _get("seal", "side")


def seal_cover():
    return _get("seal", "cover")


def seal_ink():
    return _get("seal", "ink")


def blot_ink():
    return _get("blot", "ink")


def seal_stacked_top():
    return _get("stacked", "top")


def seal_stacked_side():
    return _get("stacked", "side")


def seal_stacked_cover():
    return _get("stacked", "cover")


def seal_stacked_ink():
    return _get("stacked", "ink")


MESHES = ("seal_top", "seal_side", "seal_cover", "seal_ink", "blot_ink", "seal_stacked_top", "seal_stacked_side", "seal_stacked_cover", "seal_stacked_ink")
