"""The open books: the big one north-west, the little one south-west of the place.

Skins <Book>West/East<i>Base and <i>Slope (the layout's hills: a block and a wedge per stretch of
Profile) and replaces the <Book>Spine marks. Each half-page is one section traced through Profile --
the outer edge, the hill rising to the spine, the curl down into the valley -- pushed out and run along
the book: the page's curve is the collision's own, its facets one flat tone, so only the silhouette and
the ink show it. Head, tail, fore-edge and gutter carry the stack of pages as lines following that
curve; the top page shows two sheet edges; under it all the hard cover shows as a lip round the book
and as the spine's floor down the valley, its gutter stitched in ink.

One recipe, two meshes per role (open_book_*, little_book_*): the profiles differ, so neither is a
scaled copy of the other.

Decor outside the wrap: the cover lip (LIP wide, 0.4 high; no collision).
"""

from __future__ import annotations

from .kit import LAYOUT, OUT, TOP, box, edge_ink, emit, hull, line, meshes, meta, polyline, prism

BOOKS = {"open_book": "OpenBook", "little_book": "LittleBook"}
COVER_H = 0.4
WEIGHTS = {"open_book": (1.6, 0.7, 4.0), "little_book": (1.0, 0.5, 2.5)}  # contour, crease, lip
PAGE_LINE = 0.25


def _book(key):
    return next(b for b in LAYOUT["books"] if b["Name"] == BOOKS[key])


def _sections(book):
    """Each half's section in (x, y) about the book's centre, CCW, with its edges' offsets and roles."""
    prof = book["Profile"]
    run = book["PageWidth"] / (len(prof) - 1)
    outer = book["Valley"] / 2 + book["PageWidth"]
    inner = book["Valley"] / 2
    top = [(-outer + i * run, h) for i, h in enumerate(prof)]
    west = [(-outer, 0.0), (-inner, 0.0)] + list(reversed(top))
    east = [(inner, 0.0), (outer, 0.0)] + [(-x, h) for x, h in top]
    out = []
    for pts in (west, east):
        roles, offs = [], []
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            if a[1] == 0 and b[1] == 0:
                roles.append("bottom"), offs.append(0.0)
            elif abs(a[0] - b[0]) < 1e-9:
                roles.append("side"), offs.append(OUT)
            else:
                roles.append("top"), offs.append(TOP)
        out.append((pts, roles, offs, top if pts is west else [(-x, h) for x, h in top]))
    return out


def _build(key):
    book = _book(key)
    contour, crease, lip = WEIGHTS[key]
    m = meshes("top", "side", "cover", "ink")
    ink = m["ink"]
    half_len = book["Length"] / 2
    z0, z1 = -half_len - OUT, half_len + OUT
    for pts, roles, offs, top in _sections(book):
        solid = prism(pts, lambda u, v, t: (u, v, t), -half_len, half_len, offs, roles)
        emit(solid, m)
        edge_ink(solid, crease, ink)
        hull(solid, contour, COVER_H + 0.03, ink)
        sign = -1.0 if top[0][0] < 0 else 1.0
        # The stack of pages: lines following the page's curve on the head and the tail, level lines on
        # the fore-edge and in the gutter, as deep as the outer edge allows.
        depths = [d for d in (1.0, 2.0, 3.0, 4.0, 5.5, 7.0) if top[0][1] + TOP - d > 0.6]
        for d in depths:
            curve = [(x + sign * (OUT if i == 0 else 0.0), h + TOP - d) for i, (x, h) in enumerate(top)]
            for z, nz in ((z0, -1.0), (z1, 1.0)):
                polyline(ink, [(x, y, z) for x, y in curve], (0, 0, nz), PAGE_LINE)
            ox = top[0][0] + sign * OUT
            line(ink, (ox, top[0][1] + TOP - d, z0), (ox, top[0][1] + TOP - d, z1), (sign, 0, 0), PAGE_LINE)
        ix = top[-1][0] - sign * OUT
        for d in (1.5, 3.0, 4.5, 6.0):
            if top[-1][1] - d > 0.8:
                line(ink, (ix, top[-1][1] - d, z0), (ix, top[-1][1] - d, z1), (-sign, 0, 0), PAGE_LINE)
        # Two sheet edges on the top page, just in from its outer edge.
        (xa, ha), (xb, hb) = top[0], top[1]
        n_len = ((xb - xa) ** 2 + (hb - ha) ** 2) ** 0.5
        n = ((hb - ha) / n_len * sign, abs(xb - xa) / n_len, 0.0)
        for f in (0.12, 0.26):
            x = xa + (xb - xa) * f
            y = ha + (hb - ha) * f + TOP
            line(ink, (x, y, z0 + 1.5), (x, y, z1 - 1.5), n, PAGE_LINE)
    # The cover: a lip round both halves and the spine's floor down the valley.
    outer = book["Valley"] / 2 + book["PageWidth"] + OUT
    inner = book["Valley"] / 2 - OUT
    for a, b, c, d in ((-outer - lip, outer + lip, z0 - lip, z0), (-outer - lip, outer + lip, z1, z1 + lip),
                       (-outer - lip, -outer, z0, z1), (outer, outer + lip, z0, z1), (-inner, inner, z0, z1)):
        emit(box(a, b, 0.0, COVER_H, c, d, top="cover", sides=("cover",) * 4, out=0.0, top_out=0.0), m)
    whole = box(-outer - lip, outer + lip, 0.0, COVER_H, z0 - lip, z1 + lip, top="cover", sides=("cover",) * 4, out=0.0, top_out=0.0)
    edge_ink(whole, crease * 0.6, ink)
    hull(whole, contour * 0.6, 0.03, ink)
    line(ink, (0.0, COVER_H, z0), (0.0, COVER_H, z1), (0, 1, 0), 0.5)
    z = z0 + 3.0
    while z < z1 - 2.0:
        line(ink, (-1.4, COVER_H, z), (1.4, COVER_H, z + 1.2), (0, 1, 0), 0.35)
        z += 6.0
    return m


_M: dict = {}


def _get(key, role):
    if key not in _M:
        _M[key] = _build(key)
    b = _book(key)
    return _M[key][role], meta()


ROLES = {"top": "Top", "side": "Side", "cover": "Cover", "ink": "Ink"}
for _key in BOOKS:
    for _role in ROLES:
        globals()[f"{_key}_{_role}"] = (lambda k=_key, r=_role: _get(k, r))


MESHES = tuple(f"{k}_{r}" for k in BOOKS for r in ROLES)
