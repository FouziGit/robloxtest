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


# --- Closed volumes and their contour -------------------------------------------------------------
# A volume that stands up off the floor (the Wash's wave) is drawn in flat tones, so its form reads only
# by its outline: an inverted hull -- the volume pushed out along its normals and wound inside out, so
# from outside only the rim beyond the silhouette shows, as a thick ink contour. These are the pieces
# such a volume is made of: closed lofts and tapered tubes wound outward, ribbons lying on a surface,
# and the hull itself.

# How far over the floor a contour stays. 0.004 of a 16-stud volume is 0.06 studs: far above the depth
# buffer's resolution at any distance a duel is seen from, and invisible as a gap.
FLOOR_CLEARANCE = 0.004


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a: Vec, k: float) -> Vec:
    return (a[0] * k, a[1] * k, a[2] * k)


def lerp(a: Vec, b: Vec, f: float) -> Vec:
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)


def norm(a: Vec) -> Vec:
    length = math.sqrt(dot(a, a))
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (a[0] / length, a[1] / length, a[2] / length)


def smoothstep(a: float, b: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def cosine_curve(ctrl: list[tuple[float, float]], s: float) -> float:
    """A profile through (s, value) pairs, eased between them: no corner where two spans meet."""
    if s <= ctrl[0][0]:
        return ctrl[0][1]
    for i in range(1, len(ctrl)):
        if s <= ctrl[i][0]:
            a, b = ctrl[i - 1], ctrl[i]
            f = (s - a[0]) / (b[0] - a[0])
            f = 0.5 - 0.5 * math.cos(math.pi * f)
            return a[1] + (b[1] - a[1]) * f
    return ctrl[-1][1]


def catmull(points, per: int = 24):
    """Catmull-Rom through `points` (2D or 3D), `per` samples a span, ending on the last point."""
    dim = len(points[0])
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(
                tuple(
                    0.5
                    * (
                        2 * p1[a]
                        + (-p0[a] + p2[a]) * t
                        + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t2
                        + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t3
                    )
                    for a in range(dim)
                )
            )
    out.append(tuple(points[-1]))
    return out


class Polyline:
    """A dense polyline sampled by arc-length fraction: a curve walked at an even pace, however its
    control points were spaced."""

    def __init__(self, points) -> None:
        self.p = points
        self.acc = [0.0]
        for i in range(1, len(points)):
            self.acc.append(self.acc[-1] + math.dist(points[i - 1], points[i]))

    def at(self, s: float):
        target = min(max(s, 0.0), 1.0) * self.acc[-1]
        lo, hi = 1, len(self.p) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if self.acc[mid] < target:
                lo = mid + 1
            else:
                hi = mid
        span = max(self.acc[lo] - self.acc[lo - 1], 1e-12)
        f = (target - self.acc[lo - 1]) / span
        a, b = self.p[lo - 1], self.p[lo]
        return tuple(a[k] + (b[k] - a[k]) * f for k in range(len(a)))


def emit(mesh: Mesh, a: int, b: int, c: int) -> bool:
    """A triangle in the winding given, for a caller that knows which side is out. Degenerates are
    dropped."""
    n = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
    if dot(n, n) < 1e-16:
        return False
    mesh.tris.append((a, b, c))
    return True


class Volume:
    """A closed piece wound outward, with a contour weight per vertex: how far its hull is pushed out
    there -- heavier where the brush pressed, lighter where it lifts."""

    def __init__(self) -> None:
        self.mesh = Mesh("up")
        self.weight: list[float] = []

    def vert(self, p: Vec, weight: float) -> int:
        self.weight.append(weight)
        return self.mesh.vert(p)

    def signed_volume(self) -> float:
        total = 0.0
        for a, b, c in self.mesh.tris:
            pa, pb, pc = self.mesh.verts[a], self.mesh.verts[b], self.mesh.verts[c]
            total += dot(pa, cross(pb, pc)) / 6.0
        return total

    def orient_outward(self) -> None:
        if self.signed_volume() < 0:
            self.mesh.tris = [(a, c, b) for a, b, c in self.mesh.tris]


def loft(vol: Volume, rings: list[list[int]], half: int, tip_cap: bool = True) -> None:
    """Quads between consecutive rings, then a cap at each end. A ring is `half` outer vertices (left to
    right) followed by `half` inner ones (right to left), so the caps are strips across the slab. A ring
    whose inner half is its outer half reversed closes the slab to a knife edge and takes no cap (the
    quads that collapse there are dropped as degenerate, and the edges still pair up)."""
    m = len(rings[0])
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for j in range(m):
            k = (j + 1) % m
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])

    def cap(ring: list[int], reverse: bool) -> None:
        for j in range(half - 1):
            o0, o1 = ring[j], ring[j + 1]
            i1, i0 = ring[m - 2 - j], ring[m - 1 - j]
            quad = (o0, o1, i1, i0) if not reverse else (o1, o0, i0, i1)
            emit(vol.mesh, quad[0], quad[1], quad[2])
            emit(vol.mesh, quad[0], quad[2], quad[3])

    cap(rings[0], True)
    if tip_cap:
        cap(rings[-1], False)


def tube(control: list[Vec], radius: float, segs: int, flat: float = 1.0, weight: float = 0.006) -> Volume:
    """A tapered three-sided tendril along a Catmull-Rom path, closed: a root cap (buried in whatever it
    grows from) and a single-vertex tip. Its section is carried along the path by parallel transport, so
    it never flips where the path turns upright (a scroll); `flat` squashes it vertically; `weight` is
    its contour's base thickness, which thins as the tendril does."""
    vol = Volume()
    line = Polyline(catmull(control, 16))
    centres = [line.at(i / segs) for i in range(segs + 1)]
    tangents = [norm(sub(centres[min(i + 1, segs)], centres[max(i - 1, 0)])) for i in range(segs + 1)]
    side = cross(tangents[0], UP)
    if dot(side, side) < 1e-6:
        side = cross(tangents[0], (1.0, 0.0, 0.0))
    side = norm(side)
    rings = []
    for i in range(segs):
        along = tangents[i]
        side = norm(sub(side, mul(along, dot(side, along))))
        up = norm(cross(side, along))
        r = radius * (1.0 - i / segs) ** 0.75 + 0.0025
        ring = []
        for k in range(3):
            angle = math.pi / 2 + 2 * math.pi * k / 3
            q = add(centres[i], add(mul(up, flat * r * math.sin(angle)), mul(side, r * math.cos(angle))))
            ring.append(vol.vert((q[0], max(q[1], FLOOR_CLEARANCE), q[2]), weight + 0.3 * r))
        rings.append(ring)
    tip = vol.vert(centres[-1], 0.003)
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for j in range(3):
            k = (j + 1) % 3
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    last = rings[-1]
    for j in range(3):
        emit(vol.mesh, last[j], last[(j + 1) % 3], tip)
    first = rings[0]
    emit(vol.mesh, first[0], first[2], first[1])
    vol.orient_outward()
    return vol


def surface_ribbon(mesh: Mesh, surface, path, width: float, lift: float, samples: int, seed: int) -> None:
    """A tapered calligraphic ribbon lying on a surface, pressed in and released like a brush (the
    `pressure` profile): `surface` is (point(s, t), normal(s, t)), `path(tau) -> (s, t)`, and the ribbon
    rides `lift` off it, facing out of it. Never under the floor clearance."""
    point, normal = surface
    points = []
    for i in range(samples):
        tau = 0.03 + 0.94 * i / (samples - 1)
        s, t = path(tau)
        points.append((point(s, t), normal(s, t), tau))
    lefts: list[int] = []
    rights: list[int] = []
    for i, (p, n, tau) in enumerate(points):
        along = norm(sub(points[min(i + 1, samples - 1)][0], points[max(i - 1, 0)][0]))
        across = norm(cross(n, along))
        w = max(pressure(tau, width, 0.18, 0.9, seed), width * 0.22) / 2.0
        base = add(p, mul(n, lift))
        for q, into in ((add(base, mul(across, w)), lefts), (add(base, mul(across, -w)), rights)):
            into.append(mesh.vert((q[0], max(q[1], FLOOR_CLEARANCE), q[2])))
    for i in range(samples - 1):
        mesh.tri(lefts[i], rights[i], lefts[i + 1], points[i][1])
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1], points[i][1])


def sliver(a: Vec, b: Vec, c: Vec, degrees: float = 2.0) -> bool:
    """Whether a triangle's smallest angle is under `degrees`."""
    limit = math.cos(math.radians(degrees))
    for o, p, q in ((a, b, c), (b, c, a), (c, a, b)):
        u, v = sub(p, o), sub(q, o)
        lu, lv = math.sqrt(dot(u, u)), math.sqrt(dot(v, v))
        if lu < 1e-12 or lv < 1e-12 or dot(u, v) / (lu * lv) > limit:
            return True
    return False


def inverted_hull(vol: Volume, into: Mesh) -> None:
    """The contour of a closed volume: every vertex pushed out along its normal by its weight, every
    triangle wound the other way. The faces on the floor stay in: turned over they face up, and their
    pushed-out edge is the outline along the ground seen from above. The whole hull is held
    FLOOR_CLEARANCE over the floor, so that ring never lies in it; a face the clamp presses into a
    sliver on the ring is dropped, since it covers nothing its neighbours do not."""
    mesh = vol.mesh
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        n = face_normal(mesh.verts[a], mesh.verts[b], mesh.verts[c])
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        q = add(p, mul(norm(acc[i]), vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR_CLEARANCE), q[2]))
    for a, b, c in mesh.tris:
        corners = [into.verts[v + base] for v in (a, b, c)]
        if all(q[1] <= FLOOR_CLEARANCE for q in corners) and sliver(*corners):
            continue
        emit(into, a + base, c + base, b + base)
