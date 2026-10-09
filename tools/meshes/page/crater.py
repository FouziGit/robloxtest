"""The Inkwell Crater, west: a rim of blocks round a pool, broken by four breaches.

Skins CraterRim*. The rim between two breaches is one arc: the plan of its blocks (each a chord of the
24-gon, so the union is the polygon between an outer and an inner 24-gon, cut square at the
breaches) pushed out OUT and raised to the rim's top. One mesh, four instances turned a quarter each.
The pool inside is a flat warm-grey wash with two ink ripples (one instance, centred).

Decor outside the wrap: none on the rim; the pool is a floor mark 0.04 high.
"""

from __future__ import annotations

import math

from .kit import LAYOUT, OUT, TOP, edge_ink, emit, hull, meshes, meta, polyline, prism, upright

C = LAYOUT["crater"]
SEG = int(C["Segments"])
STEP = 2 * math.pi / SEG
QUARTER = SEG // 4
KEPT = [i for i in range(QUARTER) if C["BreachSegments"] / 2 <= i < QUARTER - C["BreachSegments"] / 2]
R_OUT = C["OuterRadius"] + OUT
R_IN = C["OuterRadius"] - C["RimStuds"] - OUT
HALF_LEN = C["OuterRadius"] * math.sin(STEP / 2) + OUT


def _dir(a):
    return (math.cos(a), math.sin(a))


def _at(a, r, t):
    """Radial r and tangential t from a block whose centre lies at angle a (layout: x = cos, z = sin)."""
    c, s = _dir(a)
    return (r * c - t * s, r * s + t * c)


def _plan():
    angles = [(i + 0.5) * STEP for i in KEPT]
    outer = [_at(angles[0], R_OUT, -HALF_LEN)]
    outer += [_at(a + STEP / 2, R_OUT / math.cos(STEP / 2), 0) for a in angles[:-1]]
    outer.append(_at(angles[-1], R_OUT, HALF_LEN))
    inner = [_at(angles[-1], R_IN, HALF_LEN)]
    inner += [_at(a + STEP / 2, R_IN / math.cos(STEP / 2), 0) for a in reversed(angles[:-1])]
    inner.append(_at(angles[0], R_IN, -HALF_LEN))
    roles = ["side"] * (len(outer) - 1) + ["side"] + ["cover"] * (len(inner) - 1) + ["side"]
    return outer + inner, roles, angles


def _build_arc():
    m = meshes("top", "side", "cover", "ink")
    ink = m["ink"]
    plan, roles, angles = _plan()
    height = C["Height"]
    rim = prism(plan, upright, 0.0, height, [0.0] * len(plan), roles, caps=("bottom", "top"), cap_out=(0.0, TOP))
    emit(rim, m)
    edge_ink(rim, 0.7, ink)
    hull(rim, 1.6, 0.03, ink)
    top = height + TOP
    for k, a in enumerate(angles):
        c, s = _dir(a)
        n = (c, 0.0, s)

        def face(t, y):
            x, z = _at(a, R_OUT, t)
            return (x, y, z)

        # A crack down the outer face, and a torn ink edge along the top's inner rim.
        sign = 1 if k % 2 else -1
        crack = [face(sign * 2.0, top - 0.3), face(sign * -0.5, top - 2.2), face(sign * 1.2, top - 3.6), face(sign * -0.3, 1.2)]
        polyline(ink, crack, n, 0.4)
        torn = []
        for j in range(7):
            t = -HALF_LEN + 0.6 + (2 * HALF_LEN - 1.2) * j / 6
            x, z = _at(a, R_IN + (0.55 if j % 2 else 1.25), t)
            torn.append((x, top, z))
        polyline(ink, torn, (0, 1, 0), 0.4)
    return m


def _build_pool():
    m = meshes("cover", "ink")
    r = R_IN - 0.15
    sides = 48
    plan = [(r * math.cos(2 * math.pi * k / sides), r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    pool = prism(plan, upright, 0.0, 0.04, [0.0] * sides, ["cover"] * sides, caps=("bottom", "cover"), cap_out=(0.0, 0.0))
    emit(pool, m)
    for radius in (0.7 * r, 0.42 * r):
        ring = [(radius * math.cos(2 * math.pi * k / 40), 0.04, radius * math.sin(2 * math.pi * k / 40)) for k in range(40)]
        polyline(m["ink"], ring, (0, 1, 0), 0.6, closed=True)
    return m


_M: dict = {}


def _get(key, role):
    if key not in _M:
        _M[key] = _build_arc() if key == "arc" else _build_pool()
    return _M[key][role], meta()


def crater_arc_top():
    return _get("arc", "top")


def crater_arc_side():
    return _get("arc", "side")


def crater_arc_cover():
    return _get("arc", "cover")


def crater_arc_ink():
    return _get("arc", "ink")


def crater_pool_cover():
    return _get("pool", "cover")


def crater_pool_ink():
    return _get("pool", "ink")


MESHES = ("crater_arc_top", "crater_arc_side", "crater_arc_cover", "crater_arc_ink", "crater_pool_cover", "crater_pool_ink")
