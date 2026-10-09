"""Shared geometry for the skins of the Page's landmarks (the Battleground, D-131, D-282, D-283). Pure Python.

The layout's blocks, wedges and cylinders stay as invisible collision; these meshes are the visible
skin over them, drawn like the glyph bodies (tools/meshes/strokes.py): Roblox space -- X right, Y up,
forward -Z -- one flat tone per mesh, and the form read by ink: an inverted hull wound inward (Roblox
culls back faces) and ink bands along every sharp edge, the cel look of the developer's ref-1.

A skin is built as a Solid -- welded vertices and planar polygons, each with a role (its tone) -- so the
hull can push every vertex out along its faces (even thickness) and the edge bands can find the
creases. Then it is cut into one Mesh per role.

The wrap contract every recipe keeps (each draft was proved by a ray fit against the layout at 673fca1;
tests/BattlegroundSkins.spec.luau holds every placed skin's bounds to the boxes it covers):
  - a skin face stands OUT outside the collision face it covers (0.05..0.3), never inside;
  - a walkable top stands TOP over the collision top (<= 0.15);
  - a skin resting on something starts exactly at its base (the floor, the dais, a lower tier).

Every number comes from src/shared/Config/BattlegroundConfig.luau, read here and never written: the layout, and
Map.Skin -- OUT, TOP and the sizes a kind's one mesh is drawn at -- which BattlegroundLayout.skins scales by.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

from strokes import Mesh, add, cross, dot, mul, norm, sub

CONFIG = Path(__file__).resolve().parents[3] / "src" / "shared" / "Config" / "BattlegroundConfig.luau"
LIFT = 0.02  # a decal or an ink line over the face it lies on

Vec = tuple[float, float, float]


# --- the layout (read from the repo's config, never written) -------------------------------------

def _parse_map(text: str) -> dict:
    """BattlegroundConfig.Map as Python: a small reader for the Luau table literal (numbers, strings,
    nested tables; comments and type casts dropped)."""
    body = text[text.index("BattlegroundConfig.Map = ") + len("BattlegroundConfig.Map = "):]
    body = re.sub(r"--[^\n]*", "", body)
    body = re.sub(r"::\s*\{[^{}]*\}|::\s*\w+", "", body)
    tokens = re.findall(r'\{|\}|,|=|"[^"]*"|-?\d+(?:\.\d+)?|\w+', body)
    pos = 0

    def value():
        nonlocal pos
        tok = tokens[pos]
        pos += 1
        if tok == "{":
            keyed, listed = {}, []
            while tokens[pos] != "}":
                if re.fullmatch(r"[A-Za-z_]\w*", tokens[pos]) and tokens[pos + 1] == "=":
                    key = tokens[pos]
                    pos += 2
                    keyed[key] = value()
                else:
                    listed.append(value())
                if tokens[pos] == ",":
                    pos += 1
            pos += 1
            return keyed if keyed else listed
        if tok.startswith('"'):
            return tok[1:-1]
        if tok in ("true", "false"):
            return tok == "true"
        return float(tok)

    return value()


SIDES = [("North", 0, -1), ("South", 0, 1), ("West", -1, 0), ("East", 1, 0)]


def layout() -> dict:
    """Every collision box the skins cover, as BattlegroundLayout builds it (centre, size, yaw), plus
    the marks (flat, non-solid) the skins replace. Local frame: x east, z south, y 0 the floor's top."""
    m = _parse_map(CONFIG.read_text())
    boxes: dict = {}

    def put(name, shape, x, z, base, size, yaw=0.0):
        boxes[name] = {"Name": name, "Shape": shape, "X": x, "Y": base + size[1] / 2, "Z": z,
                       "Size": list(size), "Yaw": yaw, "Base": base}

    dais = m["Dais"]
    stairs = dais["Stairs"]
    half = dais["Size"] / 2
    put("Dais", "Block", 0, 0, 0, [dais["Size"], dais["Height"], dais["Size"]])
    steps = round(dais["Height"] / stairs["Rise"]) - 1
    for name, sx, sz in SIDES:
        for step in range(1, steps + 1):
            out = half + (steps - step + 0.5) * stairs["Tread"]
            size = [stairs["Width"] if sx == 0 else stairs["Tread"], step * stairs["Rise"], stairs["Tread"] if sx == 0 else stairs["Width"]]
            put("Stair%s%d" % (name, step), "Block", sx * out, sz * out, 0, size)
    for c in m["Covers"]:
        put(c["Name"], "Block", c["X"], c["Z"], dais["Height"], [c["SizeX"], m["CoverHeight"], c["SizeZ"]])
    for p in m["Pieces"]:
        put(p["Name"], p["Shape"], p["X"], p["Z"], p["Base"], p["Size"], p.get("Yaw", 0.0))
    for book in m["Books"]:
        prof = book["Profile"]
        run = book["PageWidth"] / (len(prof) - 1)
        for hname, sign, spine in (("West", -1, 90), ("East", 1, -90)):
            for i in range(1, len(prof)):
                outer, inner = prof[i - 1], prof[i]
                x = book["X"] + sign * (book["Valley"] / 2 + book["PageWidth"] - (i - 0.5) * run)
                name = book["Name"] + hname + str(i)
                low = min(outer, inner)
                put(name + "Base", "Block", x, book["Z"], 0, [run, low, book["Length"]])
                if inner != outer:
                    put(name + "Slope", "Wedge", x, book["Z"], low, [book["Length"], abs(inner - outer), run],
                        spine if inner > outer else spine + 180)
    q = m["Quill"]
    yaw = math.radians(q["Yaw"])

    def qat(along, across):
        return (q["X"] + math.sin(yaw) * along + math.cos(yaw) * across, q["Z"] + math.cos(yaw) * along - math.sin(yaw) * across)

    flight, top = q["Steps"] * q["Tread"], q["Steps"] * q["Rise"]
    stair = q["Width"] - 2 * q["RailStuds"]
    for step in range(1, int(q["Steps"]) + 1):
        x, z = qat((step - 0.5) * q["Tread"], 0)
        put("QuillStep%d" % step, "Block", x, z, 0, [stair, step * q["Rise"], q["Tread"]], q["Yaw"])
    for index, sign in ((1, -1), (2, 1)):
        x, z = qat(flight / 2, sign * (stair + q["RailStuds"]) / 2)
        put("QuillRail%d" % index, "Wedge", x, z, 0, [q["RailStuds"], top, flight], q["Yaw"])
    x, z = qat(flight + q["Landing"] / 2, 0)
    put("QuillLanding", "Block", x, z, 0, [q["Width"], top, q["Landing"]], q["Yaw"])
    x, z = qat(flight + q["Landing"] + q["TipLength"] / 2, 0)
    put("QuillTip", "Wedge", x, z, 0, [q["Width"], top, q["TipLength"]], q["Yaw"] + 180)
    a = m["Arcade"]
    ayaw = math.radians(a["Yaw"])

    def aat(along):
        return a["X"] + math.cos(ayaw) * along, a["Z"] - math.sin(ayaw) * along

    bay = a["Pier"] + a["Opening"]
    length = a["Arches"] * bay + a["Pier"]
    pier_h = a["Height"] - a["Beam"]
    for pier in range(int(a["Arches"]) + 1):
        x, z = aat(-length / 2 + a["Pier"] / 2 + pier * bay)
        put("ArcadePier%d" % pier, "Block", x, z, 0, [a["Pier"], pier_h, a["Thickness"]], a["Yaw"])
    x, z = aat(0)
    put("ArcadeBeam", "Block", x, z, pier_h, [length, a["Beam"], a["Thickness"]], a["Yaw"])
    cor = a["Corbel"]
    for arch in range(1, int(a["Arches"]) + 1):
        opening = -length / 2 + arch * a["Pier"] + (arch - 1) * a["Opening"]
        for index, along in ((1, opening + cor["Width"] / 2), (2, opening + a["Opening"] - cor["Width"] / 2)):
            x, z = aat(along)
            put("ArcadeCorbel%d_%d" % (arch, index), "Block", x, z, pier_h - cor["Height"], [cor["Width"], cor["Height"], a["Thickness"]], a["Yaw"])
    c = m["Crater"]
    segments = int(c["Segments"])
    step = 360 / segments
    quarter = segments // 4
    middle = c["OuterRadius"] - c["RimStuds"] / 2
    seg_len = 2 * c["OuterRadius"] * math.sin(math.radians(step / 2))
    for index in range(segments):
        from_axis = index % quarter
        if from_axis < c["BreachSegments"] / 2 or from_axis >= quarter - c["BreachSegments"] / 2:
            continue
        angle = (index + 0.5) * step
        put("CraterRim%d" % index, "Block", c["X"] + math.cos(math.radians(angle)) * middle,
            c["Z"] + math.sin(math.radians(angle)) * middle, 0, [c["RimStuds"], c["Height"], seg_len], -angle)
    marks = {mk["Name"]: dict(mk, Yaw=mk.get("Yaw", 0.0)) for mk in m["Marks"]}
    return {"boxes": boxes, "marks": marks, "map": m, "quill": q, "crater": c, "dais": dais, "arcade": a, "books": m["Books"]}


LAYOUT = layout()
BOXES = LAYOUT["boxes"]
SKIN = LAYOUT["map"]["Skin"]
OUT = SKIN["Out"]  # a skin face's distance outside its collision face
TOP = SKIN["Top"]  # a walkable top's height over the collision top


# --- 2D polygons -------------------------------------------------------------------------------


def area2(pts) -> float:
    return 0.5 * sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(len(pts)))


def offset_polygon(pts, dists):
    """Each edge i (pts[i] -> pts[i+1]) of a CCW polygon moved `dists[i]` to its left (inward; a negative
    distance moves it out), the corners re-mitred where consecutive edges' lines meet."""
    n = len(pts)
    lines = []
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        ex, ey = b[0] - a[0], b[1] - a[1]
        length = math.hypot(ex, ey)
        ex, ey = ex / length, ey / length
        d = dists[i]
        lines.append(((a[0] - ey * d, a[1] + ex * d), (ex, ey)))
    out = []
    for i in range(n):
        (pa, ea), (pb, eb) = lines[i - 1], lines[i]
        den = ea[0] * eb[1] - ea[1] * eb[0]
        if abs(den) < 1e-9:
            out.append(pb)
        else:
            t = ((pb[0] - pa[0]) * eb[1] - (pb[1] - pa[1]) * eb[0]) / den
            out.append((pa[0] + ea[0] * t, pa[1] + ea[1] * t))
    return out


def ear_clip(pts):
    """Triangles (index triples, CCW) of a simple CCW polygon."""
    idx = list(range(len(pts)))
    tris = []

    def convex(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) > 1e-12

    def inside(p, a, b, c):
        d1 = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        d2 = (c[0] - b[0]) * (p[1] - b[1]) - (c[1] - b[1]) * (p[0] - b[0])
        d3 = (a[0] - c[0]) * (p[1] - c[1]) - (a[1] - c[1]) * (p[0] - c[0])
        return d1 >= -1e-12 and d2 >= -1e-12 and d3 >= -1e-12

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if not convex(a, b, c):
                continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            break
        else:
            break  # degenerate rest: fan it
    for k in range(1, len(idx) - 1):
        tris.append((idx[0], idx[k], idx[k + 1]))
    return tris


# --- 3D polygons ---------------------------------------------------------------------------------


def newell(points) -> Vec:
    nx = ny = nz = 0.0
    for i in range(len(points)):
        x0, y0, z0 = points[i]
        x1, y1, z1 = points[(i + 1) % len(points)]
        nx += (y0 - y1) * (z0 + z1)
        ny += (z0 - z1) * (x0 + x1)
        nz += (x0 - x1) * (y0 + y1)
    return norm((nx, ny, nz))


def basis(n: Vec):
    a = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 1.0, 0.0)
    u = norm(cross(a, n))
    return u, cross(n, u)


def triangulate(points):
    """Index triples of a planar 3D polygon, CCW about its own (Newell) normal."""
    if len(points) == 3:
        return [(0, 1, 2)]
    u, v = basis(newell(points))
    return ear_clip([(dot(p, u), dot(p, v)) for p in points])


def lifted(n: Vec, lift: float) -> float:
    """How far along n to lift something so it rises `lift` over a face a foot can stand on: on a steep
    walkable slope a lift along the normal is a much taller step."""
    return lift * n[1] if n[1] > 0.3 else lift


def put_polygon(mesh: Mesh, points, facing: Vec | None = None, lift: float = 0.0) -> None:
    """A flat polygon (a decal) lifted along its normal; turned to face `facing` when given."""
    n = newell(points)
    if facing is not None and dot(n, facing) < 0:
        points = list(reversed(points))
        n = mul(n, -1.0)
    ids = [mesh.vert(add(p, mul(n, lifted(n, lift)))) for p in points]
    for a, b, c in triangulate(points):
        mesh.tris.append((ids[a], ids[b], ids[c]))


def line(mesh: Mesh, a: Vec, b: Vec, n: Vec, width: float, lift: float = LIFT) -> None:
    """An ink line from a to b lying on a face of normal n."""
    side = mul(norm(cross(n, sub(b, a))), width / 2.0)
    put_polygon(mesh, [sub(a, side), sub(b, side), add(b, side), add(a, side)], n, lift)


def polyline(mesh: Mesh, pts, n: Vec, width: float, lift: float = LIFT, closed: bool = False) -> None:
    count = len(pts) if closed else len(pts) - 1
    for i in range(count):
        line(mesh, pts[i], pts[(i + 1) % len(pts)], n, width, lift)


# --- solids ----------------------------------------------------------------------------------------


class Solid:
    """Welded vertices and planar polygons with roles. The role "bottom" is never drawn (it rests on
    something) but still shapes the hull and its ring on the ground."""

    def __init__(self) -> None:
        self.verts: list[Vec] = []
        self.polys: list[tuple[list[int], str]] = []

    def vert(self, p) -> int:
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.verts) - 1

    def poly(self, ids, role: str) -> None:
        """A polygon; corners repeating the previous one's position (a section meeting the page) drop out."""
        ids = [i for k, i in enumerate(ids) if self.verts[i] != self.verts[ids[k - 1]]]
        if len(ids) >= 3:
            self.polys.append((ids, role))

    def points(self, ids):
        return [self.verts[i] for i in ids]

    def orient(self) -> "Solid":
        vol = 0.0
        for ids, _ in self.polys:
            p = self.points(ids)
            for k in range(1, len(p) - 1):
                vol += dot(p[0], cross(p[k], p[k + 1]))
        if vol < 0:
            self.polys = [(list(reversed(ids)), role) for ids, role in self.polys]
        return self


def prism(profile, frame, t0, t1, out, roles, caps=("side", "side"), cap_out=(OUT, OUT)) -> Solid:
    """A collision section (CCW in its (u, v) plane) skinned: edge i pushed out[i] outside and drawn in
    roles[i], extruded along t from t0 - cap_out[0] to t1 + cap_out[1]; frame(u, v, t) -> Roblox point."""
    assert area2(profile) > 0, "profile must be CCW"
    skin = offset_polygon(profile, [-d for d in out])
    s = Solid()
    lo = [s.vert(frame(u, v, t0 - cap_out[0])) for u, v in skin]
    hi = [s.vert(frame(u, v, t1 + cap_out[1])) for u, v in skin]
    n = len(skin)
    for i in range(n):
        j = (i + 1) % n
        s.poly([lo[i], lo[j], hi[j], hi[i]], roles[i])
    s.poly(list(reversed(lo)), caps[0])
    s.poly(hi, caps[1])
    return s.orient()


def moved(solid: Solid, yaw: float, offset) -> Solid:
    """The solid turned by yaw about +Y (as CFrame.Angles(0, yaw, 0)) and moved by offset."""
    a = math.radians(yaw)
    c, s = math.cos(a), math.sin(a)
    solid.verts = [(x * c + z * s + offset[0], y + offset[1], -x * s + z * c + offset[2]) for x, y, z in solid.verts]
    return solid


def wedge(sx, sy, sz, top="top", back="side", caps=("side", "side"), back_out=OUT, top_out=TOP) -> Solid:
    """A Roblox WedgePart's skin, centred on its footprint, its underside at y 0, rising toward +z."""
    section = [(-sz / 2, 0.0), (sz / 2, 0.0), (sz / 2, sy)]
    return prism(section, lambda u, v, t: (t, v, u), -sx / 2, sx / 2, [0.0, back_out, top_out], ["bottom", back, top], caps=caps)


def clip_plan(plan, keep):
    """A plan polygon (CCW (x, z) points) cut to the half-plane keep(x, z) >= 0 (keep is affine)."""
    out = []
    for i in range(len(plan)):
        a, b = plan[i - 1], plan[i]
        fa, fb = keep(*a), keep(*b)
        if fa >= 0:
            out.append(a)
        if (fa >= 0) != (fb >= 0):
            t = fa / (fa - fb)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out[1:] + out[:1] if out else out


def upright(u, v, t) -> Vec:
    """Frame of a plan (x, z) section extruded up y."""
    return (u, t, v)


def box(x0, x1, y0, y1, z0, z1, top="top", sides=("side",) * 4, out=OUT, top_out=TOP, bottom="bottom", bottom_out=0.0) -> Solid:
    """A block skinned out from its collision box; sides are (north, east, south, west)."""
    plan = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    return prism(plan, upright, y0, y1, [out] * 4, list(sides), caps=(bottom, top), cap_out=(bottom_out, top_out))


def emit(solid: Solid, meshes: dict, skip=("bottom",)) -> None:
    """The solid's polygons, cut into the mesh of their role."""
    maps: dict = {}
    for ids, role in solid.polys:
        if role in skip:
            continue
        mesh = meshes[role]
        local = maps.setdefault(role, {})
        out = []
        for i in ids:
            if i not in local:
                local[i] = mesh.vert(solid.verts[i])
            out.append(local[i])
        for a, b, c in triangulate(solid.points(ids)):
            mesh.tris.append((out[a], out[b], out[c]))


def _solve3(m, b):
    det = (
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
    )
    out = []
    for col in range(3):
        mm = [list(row) for row in m]
        for r in range(3):
            mm[r][col] = b[r]
        d = (
            mm[0][0] * (mm[1][1] * mm[2][2] - mm[1][2] * mm[2][1])
            - mm[0][1] * (mm[1][0] * mm[2][2] - mm[1][2] * mm[2][0])
            + mm[0][2] * (mm[1][0] * mm[2][1] - mm[1][1] * mm[2][0])
        )
        out.append(d / det)
    return tuple(out)


def _push(normals, w: float) -> Vec:
    """The offset that moves every face plane through a vertex out by w: least squares over its faces'
    normals, lightly damped so an edge or a single face still gets the minimum-length answer."""
    eps = 1e-4
    m = [[eps if r == c else 0.0 for c in range(3)] for r in range(3)]
    b = [0.0, 0.0, 0.0]
    for n in normals:
        for r in range(3):
            b[r] += w * n[r]
            for c in range(3):
                m[r][c] += n[r] * n[c]
    d = _solve3(m, b)
    length = math.sqrt(dot(d, d))
    # ponytail: an acute toe is mitred at most 1.6 w out, so it ends in a short ink point, not a spike.
    return mul(d, 1.6 * w / length) if length > 1.6 * w else d


def hull(solid: Solid, w: float, floor: float, ink: Mesh) -> None:
    """The solid's contour: every vertex pushed out w along its faces (even thickness), held `floor` high,
    every polygon wound the other way. Its bottom, turned over, is the ink ring round the base."""
    normals = [newell(solid.points(ids)) for ids, _ in solid.polys]
    per: list[list[Vec]] = [[] for _ in solid.verts]
    for k, (ids, _) in enumerate(solid.polys):
        for i in ids:
            if all(dot(normals[k], n) < 0.9995 for n in per[i]):
                per[i].append(normals[k])
    base = len(ink.verts)
    for i, p in enumerate(solid.verts):
        q = add(p, _push(per[i], w))
        ink.verts.append((q[0], max(q[1], floor), q[2]))
    for ids, _ in solid.polys:
        for a, b, c in triangulate(solid.points(ids)):
            ink.tris.append((base + ids[a], base + ids[c], base + ids[b]))


def edge_ink(solid: Solid, c: float, ink: Mesh, lift: float = LIFT, angle: float = 35.0, skip=("bottom",)) -> None:
    """An ink band c wide inside every sharp edge (faces meeting at more than `angle`), on both faces:
    the cel look's line on every crease, not only on the silhouette the hull draws."""
    normals = [newell(solid.points(ids)) for ids, _ in solid.polys]
    owners: dict = {}
    for k, (ids, _) in enumerate(solid.polys):
        for i in range(len(ids)):
            key = (min(ids[i], ids[(i + 1) % len(ids)]), max(ids[i], ids[(i + 1) % len(ids)]))
            owners.setdefault(key, []).append(k)
    limit = math.cos(math.radians(angle))
    for k, (ids, role) in enumerate(solid.polys):
        if role in skip:
            continue
        n = normals[k]
        sharp = []
        for i in range(len(ids)):
            key = (min(ids[i], ids[(i + 1) % len(ids)]), max(ids[i], ids[(i + 1) % len(ids)]))
            others = [o for o in owners[key] if o != k]
            sharp.append(not others or any(dot(normals[o], n) < limit for o in others))
        if not any(sharp):
            continue
        u, v = basis(n)
        pts = solid.points(ids)
        flat = [(dot(p, u), dot(p, v)) for p in pts]
        depth = dot(pts[0], n) + lifted(n, lift)
        for width in (c, c / 2.0):
            inset = offset_polygon(flat, [width if s else 0.0 for s in sharp])
            ok = 0 < area2(inset) < area2(flat) and all(
                (inset[(i + 1) % len(inset)][0] - inset[i][0]) * (flat[(i + 1) % len(flat)][0] - flat[i][0])
                + (inset[(i + 1) % len(inset)][1] - inset[i][1]) * (flat[(i + 1) % len(flat)][1] - flat[i][1])
                > 0
                for i in range(len(flat))
            )
            if ok:
                break
        else:
            continue

        def to3(q):
            return add(add(mul(u, q[0]), mul(v, q[1])), mul(n, depth))

        for i, s in enumerate(sharp):
            if s:
                j = (i + 1) % len(flat)
                quad = [to3(flat[i]), to3(flat[j]), to3(inset[j]), to3(inset[i])]
                put_polygon(ink, quad, n)




def span(name, pivot=(0.0, 0.0, 0.0)):
    """An axis-aligned (or quarter-turned) box as (x0, x1, y0, y1, z0, z1), relative to a pivot."""
    b = BOXES[name]
    sx, sy, sz = b["Size"]
    if abs(b["Yaw"]) % 180 == 90:
        sx, sz = sz, sx
    return (b["X"] - sx / 2 - pivot[0], b["X"] + sx / 2 - pivot[0], b["Base"] - pivot[1], b["Base"] + sy - pivot[1],
            b["Z"] - sz / 2 - pivot[2], b["Z"] + sz / 2 - pivot[2])


def meshes(*roles) -> dict:
    return {role: Mesh("up") for role in roles}


def meta(seed: int = 0) -> dict:
    """A skin's manifest entry: drawn in studs at layout size about its pivot (BattlegroundLayout.skins places it)."""
    return {"Reference": "Layout", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}
