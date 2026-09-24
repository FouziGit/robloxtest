"""The volumes of phase 4 (D-114), one function per mesh. Each returns the mesh and its manifest entry.

Every shape is a brush stroke that has taken on thickness (art bible rule 9): an open circle, a ring
of two strokes, a splash crown with round beads, a sweep, a thrown drop, two torn scraps of paper.
Sizes are in reference units -- the `Reference` extent is exactly 1 -- so the runtime scales a mesh in
studs of that extent, the way a texture is scaled by its plane. `Pivot` is the point the runtime
places, in the same units: the importer recentres a mesh on its bounding box, and the manifest's
bounds are what let the runtime put the pivot back.

Coordinates are Roblox's: X right, Y up, forward is -Z. Every flat mesh lies in the XZ plane.
"""

from __future__ import annotations

import math

from strokes import Mesh, Rng, fbm, octahedron, ribbon, stroke


def _normalise_outer(mesh: Mesh) -> None:
    """Scales a mesh centred on the origin so its outermost ink sits exactly 0.5 from the centre: a
    diameter of 1, the reference a ring is sized by -- a blast's edge, not the stroke's spine."""
    reach = max(math.hypot(x, z) for x, _, z in mesh.verts)
    mesh.scale(0.5 / reach)


def enso() -> tuple[Mesh, dict]:
    """One open brush circle, drawn in one breath: a loaded start, pressure falling off, a dry tail in
    three strands, and the gap behind (+Z), toward the thrower."""
    seed = 1107
    mesh = Mesh("up")
    start = math.radians(270 + 19)
    sweep = math.radians(322)

    def path(t: float) -> tuple[float, float]:
        angle = start + sweep * t
        radius = 0.5 + 0.015 * (fbm(3.0 * t, 1.5, seed) * 2.0 - 1.0)
        return (radius * math.cos(angle), -radius * math.sin(angle))

    stroke(mesh, path, 72, 0.085, 0.10, 0.40, 0.80, 3, seed)
    _normalise_outer(mesh)
    mesh.double_sided()
    return mesh, {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": True, "Seed": seed}


def split_ring() -> tuple[Mesh, dict]:
    """A thin ring made of two strokes, each tapered at both ends: the fast second ring of a blast."""
    seed = 1102
    mesh = Mesh("up")
    rng = Rng(seed)
    for arc in range(2):
        span = math.radians(150 * (1.0 + 0.1 * (rng.random() - 0.5)))
        first = math.radians(arc * 180 + 15) + 0.2 * (rng.random() - 0.5)
        samples = 36
        points = []
        widths = []
        for i in range(samples):
            t = i / (samples - 1)
            angle = first + span * t
            points.append((0.5 * math.cos(angle), -0.5 * math.sin(angle)))
            widths.append(0.05 * math.sin(math.pi * t) ** 0.6)
        ribbon(mesh, points, widths, lift=0.08)
    _normalise_outer(mesh)
    mesh.double_sided()
    return mesh, {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": True, "Seed": seed}


def crescent() -> tuple[Mesh, dict]:
    """A brush sweep across the front: 150 degrees of a circle, thick in its leading third, dry at the
    end in two strands, banking a little as it goes so it has depth without standing up."""
    seed = 3301
    mesh = Mesh("up")
    start = math.radians(165)
    sweep = math.radians(150)

    def path(t: float) -> tuple[float, float]:
        angle = start - sweep * t
        return (0.5 * math.cos(angle), -0.5 * math.sin(angle))

    stroke(mesh, path, 40, 0.13, 0.35, 0.9, 0.7, 2, seed, lift=0.2)
    mesh.double_sided()
    # The circle's diameter is the reference: the sweep is sized by the reach it covers.
    return mesh, {"Reference": "CircleDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": True, "Seed": seed}


def crown() -> tuple[Mesh, dict]:
    """An ink splash crown, the Edgerton milk drop in pigment: a low flared wall, nine uneven stalks
    ending in ROUND beads, three of them already detached. Round, never pointed -- pointed tongues in
    Cinnabar read as fire. Its base is the reference: the runtime sizes it inside the blast."""
    seed = 2203
    mesh = Mesh("up")
    rng = Rng(seed)
    wall = Mesh("up")
    segments = 36
    height = 0.18
    flare = math.radians(10)
    top_radius = 0.5 + height * math.tan(flare)
    bottom: list[int] = []
    top: list[int] = []
    for i in range(segments):
        angle = 2 * math.pi * i / segments
        c, s = math.cos(angle), -math.sin(angle)
        lip = height * (0.85 + 0.3 * fbm(4.0 * i / segments, 2.5, seed))
        bottom.append(wall.vert((0.5 * c, 0.0, 0.5 * s)))
        top.append(wall.vert((top_radius * c, lip, top_radius * s)))
    for i in range(segments):
        j = (i + 1) % segments
        outward = (math.cos(2 * math.pi * (i + 0.5) / segments), 0.0, -math.sin(2 * math.pi * (i + 0.5) / segments))
        wall.tri(bottom[i], bottom[j], top[i], outward)
        wall.tri(bottom[j], top[j], top[i], outward)
    wall.double_sided()
    mesh.merge(wall)

    stalks = Mesh("up")
    lean = math.radians(12)
    detached = {1, 4, 7}
    for index in range(9):
        angle = math.radians(index * 40 + 7 * (rng.random() * 2 - 1))
        c, s = math.cos(angle), -math.sin(angle)
        base = (top_radius * c, height * 0.9, top_radius * s)
        rise = (math.sin(lean) * c, math.cos(lean), math.sin(lean) * s)
        tangent = (-s, 0.0, c)
        length = 0.35 + 0.27 * rng.random() - height
        steps = 4
        left: list[int] = []
        right: list[int] = []
        for k in range(steps + 1):
            t = k / steps
            point = tuple(base[a] + rise[a] * length * t for a in range(3))
            half = (0.06 + (0.035 - 0.06) * t) / 2.0
            left.append(stalks.vert(tuple(point[a] + tangent[a] * half for a in range(3))))
            right.append(stalks.vert(tuple(point[a] - tangent[a] * half for a in range(3))))
        radial = (c, 0.0, s)
        for k in range(steps):
            stalks.tri(left[k], right[k], left[k + 1], radial)
            stalks.tri(right[k], right[k + 1], left[k + 1], radial)
        tip = tuple(base[a] + rise[a] * length for a in range(3))
        bead = 0.045 + 0.015 * rng.random()
        lift = 0.06 + 0.04 * rng.random() if index in detached else bead * 0.6
        octahedron(mesh, (tip[0] + rise[0] * lift, tip[1] + rise[1] * lift, tip[2] + rise[2] * lift), bead)
    stalks.double_sided()
    mesh.merge(stalks)
    return mesh, {"Reference": "BaseDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def drop() -> tuple[Mesh, dict]:
    """The thrown drop: a lathed teardrop, round head forward (-Z), the last 30 % of its tail split into
    three bristles splaying 9 to 15 degrees -- a loaded brush tip in flight, not a flame. Its length is
    the reference and its head's centre the pivot, which is what rides the projectile."""
    seed = 4409
    mesh = Mesh("up")
    rng = Rng(seed)
    sides = 8
    head = 0.26
    rings: list[list[int]] = []
    profile: list[tuple[float, float]] = []
    for k in range(1, 4):
        a = (math.pi / 2) * (1 - k / 3)
        profile.append((-head * math.sin(a), head * math.cos(a)))
    tail_length = 1.0 - head
    for k in range(1, 7):
        s = k / 6 * 0.7
        profile.append((tail_length * s, head * (1 - s) ** 1.6))
    tip = mesh.vert((0.0, 0.0, -head))
    for z, radius in profile:
        ring = []
        for j in range(sides):
            angle = 2 * math.pi * j / sides
            ring.append(mesh.vert((radius * math.cos(angle), radius * math.sin(angle), z)))
        rings.append(ring)
    centre = (0.0, 0.0, 0.0)

    def outward(*indices: int):
        vs = [mesh.verts[i] for i in indices]
        return tuple(sum(v[a] for v in vs) / len(vs) - centre[a] for a in range(3))

    for j in range(sides):
        k = (j + 1) % sides
        mesh.tri(tip, rings[0][j], rings[0][k], outward(tip, rings[0][j], rings[0][k]))
    for r in range(len(rings) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            a, b, c, d = rings[r][j], rings[r][k], rings[r + 1][j], rings[r + 1][k]
            mesh.tri(a, b, c, outward(a, b, c))
            mesh.tri(b, d, c, outward(b, d, c))
    last = rings[-1]
    end_z = profile[-1][0]
    cap = mesh.vert((0.0, 0.0, end_z))
    for j in range(sides):
        k = (j + 1) % sides
        mesh.tri(cap, last[j], last[k], (0.0, 0.0, 1.0))

    bristles = Mesh("up")
    for index in range(3):
        splay = math.radians((9 + 6 * rng.random()) * (index - 1))
        start_z = end_z
        points = []
        widths = []
        for k in range(5):
            t = k / 4
            along = tail_length * 0.3 * t
            points.append((math.sin(splay) * along + (index - 1) * 0.02, start_z + math.cos(splay) * along))
            widths.append(0.06 * (1 - t))
        ribbon(bristles, points, widths, lift=0.0)
    bristles.double_sided()
    mesh.merge(bristles)
    return mesh, {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": seed}


def scrap(seed: int, columns: int, rows: int, fold_degrees: float, torn_points: int) -> tuple[Mesh, dict]:
    """A scrap of the page: a 1 x 0.68 sheet, three edges cut and one torn, folded along its middle.
    True normals, not the flat tone of the pigment volumes: the flicker of a tumbling sheet catching
    the light is what reads as paper."""
    mesh = Mesh("true")
    rng = Rng(seed)
    width, depth = 1.0, 0.68
    fold = math.radians(fold_degrees)
    tear = [0.05 * (rng.random() * 2 - 1) for _ in range(torn_points)]
    grid: list[list[int]] = []
    for r in range(rows + 1):
        row = []
        for c in range(columns + 1):
            u = c / columns
            x = (u - 0.5) * width
            z = (r / rows - 0.5) * depth
            if r == rows:
                # The torn edge: sampled between the seeded tear points.
                position = u * (torn_points - 1)
                i = min(int(position), torn_points - 2)
                f = position - i
                z += tear[i] * (1 - f) + tear[i + 1] * f
            y = 0.0
            if x > 0:
                y = x * math.sin(fold)
                x = x * math.cos(fold)
            row.append(mesh.vert((x, y, z)))
        grid.append(row)
    for r in range(rows):
        for c in range(columns):
            a, b, d, e = grid[r][c], grid[r][c + 1], grid[r + 1][c], grid[r + 1][c + 1]
            mesh.tri(a, b, d)
            mesh.tri(b, e, d)
    mesh.double_sided()
    return mesh, {"Reference": "LongSide", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": True, "Seed": seed}


def scrap_a() -> tuple[Mesh, dict]:
    return scrap(5501, 4, 3, 16, 7)


def scrap_b() -> tuple[Mesh, dict]:
    return scrap(5502, 3, 3, 24, 5)


# Key -> (file name, recipe, triangle cap). The key is the MeshConfig key a timeline names.
RECIPES = {
    "Enso": ("ink_enso.glb", enso, 450),
    "SplitRing": ("ink_split_ring.glb", split_ring, 450),
    "Crescent": ("ink_crescent.glb", crescent, 450),
    "Crown": ("ink_crown.glb", crown, 450),
    "Drop": ("ink_drop.glb", drop, 450),
    "ScrapA": ("paper_scrap_a.glb", scrap_a, 48),
    "ScrapB": ("paper_scrap_b.glb", scrap_b, 48),
}


def axis_probe() -> Mesh:
    """Never shipped. Three arms of length 1, 2 and 3 along right (+X), up (+Y) and forward (-Z): one
    imported MeshSize read in Studio gives both the axis mapping and the importer's unit scale."""
    mesh = Mesh("true")
    half = 0.05
    for end in ((1.0, 0.0, 0.0), (0.0, 2.0, 0.0), (0.0, 0.0, -3.0)):
        lo = [min(0.0, end[a]) if end[a] != 0 else -half for a in range(3)]
        hi = [max(0.0, end[a]) if end[a] != 0 else half for a in range(3)]
        corners = [mesh.vert((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
        centre = tuple((lo[a] + hi[a]) / 2 for a in range(3))
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        for f in faces:
            a, b, c, d = (corners[i] for i in f)
            quad_centre = tuple(sum(mesh.verts[i][k] for i in (a, b, c, d)) / 4 for k in range(3))
            out = tuple(quad_centre[k] - centre[k] for k in range(3))
            mesh.tri(a, b, c, out)
            mesh.tri(a, c, d, out)
    return mesh
