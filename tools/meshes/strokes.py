"""Brush-stroke geometry for the generated volumes (D-114). Pure Python, standard library only.

Every mesh is built here in ROBLOX space -- X right, Y up, forward is -Z -- as a list of vertices and
triangles, and export_blender.py only hands the result to Blender for the glTF writer. Keeping the
geometry out of Blender is what lets generate_all.py count triangles, measure bounds and write the
manifest without a Blender process, and what keeps a recipe reviewable as arithmetic.

A volume here is a brush stroke that has taken on thickness (art bible rule 9): a ribbon whose width
follows a pressure profile, that splits into dry strands at its tail. The profile is the one the
texture generators already draw with, and the noise is theirs too (tools/textures/vellum_png.py), so
a ring on the floor and the brush texture on a trail come from the same hand.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "textures"))

from vellum_png import Rng, fbm  # noqa: E402  (the path is set on the line above)

Vec = tuple[float, float, float]
UP: Vec = (0.0, 1.0, 0.0)


class Mesh:
    """Vertices and triangles. `normals` is "up" (every vertex normal is +Y, the lighting rule of D-114:
    the whole volume takes one flat tone, like a mark on the floor) or "true" (computed from the faces,
    for the paper scraps, whose flicker as they tumble is what reads as paper)."""

    def __init__(self, normals: str = "up") -> None:
        self.verts: list[Vec] = []
        self.tris: list[tuple[int, int, int]] = []
        self.normals = normals

    def vert(self, v: Vec) -> int:
        self.verts.append((float(v[0]), float(v[1]), float(v[2])))
        return len(self.verts) - 1

    def tri(self, a: int, b: int, c: int, facing: Vec = UP) -> None:
        """A triangle wound so its face normal points along `facing` (counter-clockwise seen from there,
        the front face for Roblox and glTF alike). Degenerate triangles are dropped."""
        n = face_normal(self.verts[a], self.verts[b], self.verts[c])
        if dot(n, n) < 1e-18:
            return
        if dot(n, facing) < 0:
            b, c = c, b
        self.tris.append((a, b, c))

    def merge(self, other: "Mesh") -> None:
        base = len(self.verts)
        self.verts.extend(other.verts)
        self.tris.extend((a + base, b + base, c + base) for a, b, c in other.tris)

    def double_sided(self) -> None:
        """Every triangle again, the other way round, on its own copies of the vertices. A SpecialMesh has
        no DoubleSided switch, and a flat stroke seen from below would otherwise not be drawn at all. The
        copies are not a detail: a back face on the front's own vertices is the same face to Blender,
        whose mesh validation deleted every one of them -- the ensō lost half its triangles and the
        crown its whole wall seen from inside (found by counting the exported file)."""
        base = len(self.verts)
        self.verts.extend(list(self.verts))
        self.tris.extend((a + base, c + base, b + base) for a, b, c in list(self.tris))

    def scale(self, factor: float) -> None:
        self.verts = [(x * factor, y * factor, z * factor) for x, y, z in self.verts]

    def translate(self, offset: Vec) -> None:
        self.verts = [(x + offset[0], y + offset[1], z + offset[2]) for x, y, z in self.verts]

    def bounds(self) -> tuple[Vec, Vec]:
        xs, ys, zs = zip(*self.verts)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def face_normal(a: Vec, b: Vec, c: Vec) -> Vec:
    return cross(sub(b, a), sub(c, a))


def attack(t: float, a: float) -> float:
    """How far a brush has pressed down `t` into its stroke: fast, then settled -- never a hard start."""
    x = min(t / a, 1.0) if a > 0 else 1.0
    return 1.0 - (1.0 - x) ** 2


def pressure(t: float, width: float, a: float, release: float, seed: int) -> float:
    """Width of a stroke at `t` (0..1): pressed in over `a`, eased off by `release` toward the end, with
    the hand's small unevenness. The same profile the brush textures are drawn with."""
    return width * attack(t, a) * (1.0 - release * t) * (1.0 + 0.12 * (fbm(6.0 * t, 0.5, seed) * 2.0 - 1.0))


def ribbon(
    mesh: Mesh,
    centre: list[tuple[float, float]],
    widths: list[float],
    lift: float = 0.0,
    offsets: list[float] | None = None,
) -> None:
    """A strip along `centre` (points in the XZ plane) with the given widths, two triangles a segment,
    banked across its width by `lift` x width: a stroke is not a sheet of glass, and a mesh with no
    height at all is a degenerate box to the importer. `offsets` shifts each sample across the stroke
    (a dry strand runs beside the spine, not on it)."""
    count = len(centre)
    lefts: list[int] = []
    rights: list[int] = []
    for i, (x, z) in enumerate(centre):
        ax, az = centre[max(i - 1, 0)]
        bx, bz = centre[min(i + 1, count - 1)]
        tx, tz = bx - ax, bz - az
        length = math.hypot(tx, tz) or 1.0
        nx, nz = -tz / length, tx / length
        shift = offsets[i] if offsets is not None else 0.0
        cx, cz = x + nx * shift, z + nz * shift
        half = widths[i] / 2.0
        lefts.append(mesh.vert((cx + nx * half, lift * widths[i], cz + nz * half)))
        rights.append(mesh.vert((cx - nx * half, 0.0, cz - nz * half)))
    for i in range(count - 1):
        mesh.tri(lefts[i], rights[i], lefts[i + 1])
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1])


def stroke(
    mesh: Mesh,
    path,
    samples: int,
    width: float,
    a: float,
    release: float,
    dry_from: float,
    strands: int,
    seed: int,
    lift: float = 0.08,
) -> None:
    """One brush stroke along `path(t) -> (x, z)`: loaded while it presses, dry at its tail, where it
    splits into `strands` that run out one after the other (their widths sum to 85 % of the stroke,
    gaps of 8 % between them) at seeded points between 90 % and 100 % of the length."""
    rng = Rng(seed)
    wet_steps = max(2, int(samples * dry_from))
    wet = [dry_from * i / (wet_steps - 1) for i in range(wet_steps)]
    ribbon(mesh, [path(t) for t in wet], [pressure(t, width, a, release, seed) for t in wet], lift)
    if strands <= 0:
        return
    share = 0.85 / strands
    gap = 0.08
    span = strands * share + (strands - 1) * gap
    dry_steps = max(2, samples - wet_steps + 1)
    for strand in range(strands):
        ends = 0.9 + 0.1 * rng.random()
        across = -span / 2.0 + share / 2.0 + strand * (share + gap)
        ts = [dry_from + (ends - dry_from) * i / (dry_steps - 1) for i in range(dry_steps)]
        full = [pressure(t, width, a, release, seed) for t in ts]
        # Each strand thins to nothing at its own end, and sits `across` of the full width from the spine.
        widths = [w * share * (1.0 - ((t - dry_from) / (ends - dry_from)) ** 1.5) for w, t in zip(full, ts)]
        offsets = [w * across for w in full]
        ribbon(mesh, [path(t) for t in ts], widths, lift, offsets)


def octahedron(mesh: Mesh, centre: Vec, radius: float) -> None:
    """A bead: eight triangles, which is as round as a drop of ink needs to be at this size."""
    x, y, z = centre
    points = [
        mesh.vert((x + radius, y, z)),
        mesh.vert((x - radius, y, z)),
        mesh.vert((x, y + radius, z)),
        mesh.vert((x, y - radius, z)),
        mesh.vert((x, y, z + radius)),
        mesh.vert((x, y, z - radius)),
    ]
    px, nx, py, ny, pz, nz = points
    for a in (px, nx):
        for b in (py, ny):
            for c in (pz, nz):
                va, vb, vc = mesh.verts[a], mesh.verts[b], mesh.verts[c]
                outward = sub(((va[0] + vb[0] + vc[0]) / 3, (va[1] + vb[1] + vc[1]) / 3, (va[2] + vb[2] + vc[2]) / 3), centre)
                mesh.tri(a, b, c, outward)
