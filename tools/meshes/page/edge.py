"""The page's torn edge: the paper's own thickness, torn, under every tab of the deckle (BattlegroundLayout's
Deckle1..n, the band round the page cut in SlotStuds tabs, each torn in by one of Deckle.Tears).

ONE tab drawn in three variants (A, B, C) and reused round the page, a variant per tab in turn; it skins no box --
the tab stays the page's own floor, drawn and colliding -- and lies over it:
  - a lip in vellum just over the tab's top, its outer edge torn: wandering out from the tab's face (never in);
  - the paper's cliff in bone under that edge, dropping DROP studs into the void with a ragged foot, fibrous: its
    face follows the torn edge down, a few ink fibres run down it;
  - the step to the next tab: a cap at each end, as deep as the tab, its contour under-hung outside it, so it is
    drawn where the next tab is torn deeper and hidden under the next tab where it is not.
Ink: the torn edge along the lip and down the face's top, the caps' contours, the fibres.

Drawn for a tab torn 0 in (the whole band): local x along the edge, outward -z, the pivot on the band's inner
edge at the floor's top. BattlegroundLayout.skins turns it to face out and scales its z by (depth + OUT) / (BAND +
OUT), so the cliff stands OUT outside every tab and the tear's wander shrinks with a shallow tab.

Decor outside the wrap: the torn wander (up to WANDER past the tab's face at a whole tab, less at a shallow one,
over the void) and the cliff under the floor (nobody stands in either; no collision).
"""

from __future__ import annotations

import math
import random

from .kit import LAYOUT, OUT, TOP, Mesh, meshes, meta, put_polygon

DECKLE = LAYOUT["map"]["Deckle"]
BAND, SLOT = DECKLE["BandStuds"], DECKLE["SlotStuds"]
HALF = SLOT / 2 + OUT
WANDER = 1.8
DROP = (30.0, 36.0)
LIP_INK, FACE_INK, CAP_INK = 1.0, 0.7, 0.9
# Ink on the cliff stands off its face along -z, which the placement scales: authored large enough to stay clear.
FACE_LIFT = 0.12
SEEDS = {"a": 7301, "b": 7302, "c": 7303}


def _outline(rng):
    """The torn edge: plan points from one end of the tab to the other, each WANDER or less past its face."""
    xs = [-HALF]
    while xs[-1] < HALF - 1.6:
        xs.append(xs[-1] + rng.uniform(0.7, 1.6))
    xs.append(HALF)
    phase, period = rng.uniform(0, 2 * math.pi), rng.uniform(9.0, 16.0)
    pts = []
    for x in xs:
        swell = 0.5 + 0.5 * math.sin(2 * math.pi * x / period + phase)
        wander = WANDER * (0.55 * swell + 0.45 * rng.random())
        pts.append((x, -(BAND + OUT + wander)))
    return pts


def _quad(mesh, pts, facing, lift=0.0):
    put_polygon(mesh, pts, facing, lift)


def _build(seed):
    rng = random.Random(seed)
    m = meshes("body", "side", "ink")
    body, side, ink = m["body"], m["side"], m["ink"]
    edge = _outline(rng)
    foot = [-rng.uniform(*DROP) for _ in edge]
    # The lip: the tab's top from the band's inner edge out to the torn edge.
    put_polygon(body, [(x, TOP, z) for x, z in edge] + [(HALF, TOP, 0.0), (-HALF, TOP, 0.0)], (0.0, 1.0, 0.0))
    # The cliff: down from every stretch of the torn edge to the ragged foot.
    normals = []
    for i in range(len(edge) - 1):
        (ax, az), (bx, bz) = edge[i], edge[i + 1]
        length = math.hypot(bx - ax, bz - az)
        n = ((bz - az) / length, 0.0, -(bx - ax) / length)
        normals.append(n)
        _quad(side, [(ax, TOP, az), (bx, TOP, bz), (bx, foot[i + 1], bz), (ax, foot[i], az)], n)
        # The torn edge in ink: along the lip's top and down the face's.
        _quad(ink, [(ax, TOP, az), (bx, TOP, bz), (bx, TOP, bz + LIP_INK), (ax, TOP, az + LIP_INK)], (0.0, 1.0, 0.0), 0.02)
        _quad(ink, [(ax, TOP, az), (bx, TOP, bz), (bx, TOP - FACE_INK, bz), (ax, TOP - FACE_INK, az)], n, FACE_LIFT)
    # The caps, square to the edge at each end, as deep as the tab.
    for sign, (x, z), low in ((-1, edge[0], foot[0]), (1, edge[-1], foot[-1])):
        n = (float(sign), 0.0, 0.0)
        _quad(side, [(x, TOP, 0.0), (x, TOP, z), (x, low, z), (x, low, 0.0)], n)
        _quad(ink, [(x, TOP, 0.0), (x, TOP, z), (x, TOP - FACE_INK, z), (x, TOP - FACE_INK, 0.0)], n, 0.02)
        # Its contour from above lies outside it, just under the floor's top: under the next tab where that one
        # reaches as far, over the void where it is torn deeper.
        x1 = x + sign * CAP_INK
        _quad(ink, [(x, -0.03, 0.0), (x1, -0.03, 0.0), (x1, -0.03, z), (x, -0.03, z)], (0.0, 1.0, 0.0))
    # Fibres down the face, each on one stretch of it, kinked as torn paper is.
    for _ in range(rng.randint(5, 7)):
        i = rng.randrange(len(edge) - 1)
        (ax, az), (bx, bz) = edge[i], edge[i + 1]
        n = normals[i]
        y, t = TOP - FACE_INK - 0.2, rng.uniform(0.3, 0.7)
        bottom = max(foot[i], foot[i + 1]) * rng.uniform(0.25, 0.75)
        while y > bottom:
            step = rng.uniform(3.0, 7.0)
            t2 = min(0.9, max(0.1, t + rng.uniform(-0.2, 0.2)))
            p = (ax + (bx - ax) * t, y, az + (bz - az) * t)
            q = (ax + (bx - ax) * t2, max(bottom, y - step), az + (bz - az) * t2)
            side_vec = ((bx - ax) * 0.15 / max(1e-6, math.hypot(bx - ax, bz - az)), 0.0, (bz - az) * 0.15 / max(1e-6, math.hypot(bx - ax, bz - az)))
            _quad(ink, [(p[0] - side_vec[0], p[1], p[2] - side_vec[2]), (p[0] + side_vec[0], p[1], p[2] + side_vec[2]),
                        (q[0] + side_vec[0], q[1], q[2] + side_vec[2]), (q[0] - side_vec[0], q[1], q[2] - side_vec[2])], n, FACE_LIFT)
            y, t = q[1], t2
    return m


_M: dict = {}


def _get(variant, role):
    if variant not in _M:
        _M[variant] = _build(SEEDS[variant])
    return _M[variant][role], meta(SEEDS[variant])


def edge_a_body():
    return _get("a", "body")


def edge_a_side():
    return _get("a", "side")


def edge_a_ink():
    return _get("a", "ink")


def edge_b_body():
    return _get("b", "body")


def edge_b_side():
    return _get("b", "side")


def edge_b_ink():
    return _get("b", "ink")


def edge_c_body():
    return _get("c", "body")


def edge_c_side():
    return _get("c", "side")


def edge_c_ink():
    return _get("c", "ink")


MESHES = ("edge_a_body", "edge_a_side", "edge_a_ink", "edge_b_body", "edge_b_side", "edge_b_ink", "edge_c_body", "edge_c_side", "edge_c_ink")
