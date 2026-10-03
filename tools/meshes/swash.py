"""The Swash's blade (Umber), after the developer's two references (docs/vfx/swash/ref-1.jpg, the blade in
game beside a caster; ref-2.jpg, the "Umber Ink Swash Blade" model sheet).

The paraph under a signature, stood up off the page: one calligraphic stroke of umber ink swept along an
arch -- the pen pressed at the left foot, run up a long diagonal, lifted over a top that leans toward the
right foot, set down again steeply there -- open underneath, so the floor shows through it. Middle
forward, horns back: the arch is cambered, its top ahead and its feet behind. Its section is a wedge:
thick on the inside of the arch, thin at its top edge, and the whole of it thick at the foot and thin at
the top. Just inside the top edge, on both faces, runs one pale thread.

The pen work at the feet is drawn as a pen draws it (ref-1): thin strokes, brown wider than their ink.
The left foot carries the paraph: a stroke drops off the outside of the leg, crosses itself, swings out
into a long loop and comes back through the crossing into a small hooked curl -- open, tapering, the
later pass riding over the earlier one at the crossing. Low behind the left foot lies the closed
flourish (a spiral, the sheet's "closed flourish"); the right foot carries one cursive loop with a
hooked tail. A skid of three ink streaks scrapes the page off the left foot, and three whips trail back
off the right leg: the broad S-horn of the band itself (the sheet's side view: it leaves the leg's back
low, dips, and rises behind the band into a hook, carrying the pale thread -- kept behind the band, so
from the front it never shows over the shoulder), and two thin crescent whips that arch up and back over
the leg and fall inside the arch (ref-1). Two loose ink wisps run up the outside of the left leg.

Second form, the slump (the model sheet's "SLUMPED inset"): where the server's front meets a wall the
band falls against it and folds over. Its back leg runs up the wall, its crest rolls over toward the
thrower, and its front leg hangs down again in S-waves; two narrower strands hang from inside the fold,
waving out to either side, the right one bulging where the wall deflected it. All of them drape down
the wall face into a small round pool at its foot. The rest of the ink ran off along the foot of the
wall: a short flat run each way that thins out into a trail of drops, and two splats.

Roblox space: X right, Y up, forward -Z. Built in studs, then scaled: the three meshes of a form span
exactly 1 along X (the runtime draws that the server's Width, 12 studs), centred on x = 0. The pivot
(0, 0, 0) is on the floor under the centre of the server's box; the leading edge is on the box's front
face, z = -Depth / 2 / Width = -0.125, and everything else trails behind it, inside the swept harm.

What the build holds to:
- every sweep's side faces face their own side of the frame: a ring is narrowed where a bend is tighter
  than its half-width (`guard`), and the slump's waves are drawn wider than any band is wide, so no band
  folds over itself;
- nothing is clamped onto the floor after a sweep: a ring that would dip under the floor is lifted whole,
  so no body face lies at y = 0 facing up, and no face is squashed into a sliver;
- the contour stands off every face it surrounds by at least 0.1 stud at the final size (the bible's
  floor): each vertex's push is first drawn smooth from the ring, then lengthened until no face plane at
  that vertex is nearer than its weight. Points are exempt: the single vertex at the end of a hook, a
  whip, a horn or a run carries a lighter weight, as a pen's point does;
- the layers of the slump never pass within a contour's reach of one another, so no contour shows
  through a face it lies behind.
"""

from __future__ import annotations

import math

from strokes import (
    Mesh,
    Polyline,
    Rng,
    Volume,
    add,
    catmull,
    cosine_curve,
    cross,
    dot,
    emit,
    fbm,
    lerp,
    mul,
    norm,
    smoothstep,
    sub,
)

SEED = 6127
WIDTH = 12.0  # the server's Width (GlyphConfig Swash.Params.Width), studs
DEPTH = 3.0  # the server's Depth: the leading edge lies Depth / 2 ahead of the pivot
BACK = (0.0, 0.0, 1.0)  # toward the thrower
UP = (0.0, 1.0, 0.0)
SIDE = (1.0, 0.0, 0.0)
CONTOUR_MIN = 0.1  # studs: the bible's floor for a contour at the final size
TIP_WEIGHT = 0.05  # the single point at the end of a hook, a whip, a horn or a run

# --- the blade's arch --------------------------------------------------------------------------------
# The spine, studs, in the front plane: from the left foot up a long diagonal, over a top that leans
# toward the right foot (about 60 % of the way across, as in both references), and steeply down.
ARCH_SPINE = [(-4.25, 0.0), (-3.62, 1.06), (-2.8, 2.08), (-1.8, 2.97), (-0.6, 3.66), (0.6, 4.01),
              (1.65, 3.87), (2.55, 3.22), (3.2, 2.2), (3.62, 1.12), (3.85, 0.0)]
CAMBER = 0.3  # how far behind the middle the feet stand (z, studs): middle forward, horns back
# Across the arch (studs): its width (plein at the left foot, délié over the top, pressed again at the
# right foot) and its depth along z at the inner edge; the top edge is `wedge` of that: thin.
ARCH = {
    "stations": 42,
    "width": [(0.0, 1.5), (0.14, 1.28), (0.52, 0.96), (0.86, 1.05), (1.0, 1.18)],
    "depth": [(0.0, 1.6), (0.16, 1.25), (0.52, 0.92), (0.84, 1.08), (1.0, 1.32)],
    "wedge": 0.7,
    "toe": (0.6, 0.3),  # the foot's outer edge sweeps out along the floor into a point (left, right)
    "toe_run": 0.055,
    "level": 0.07,  # over this share of the spine at each foot the section turns level onto the floor
    "hull": (0.135, 0.105),  # the contour at the feet and at the top (the sheet's 0.1-0.14): heavier where the pen pressed
    "wobble": 0.05,
}
THREAD = (0.1, 0.87, 0.7, 0.11, 0.035)  # the pale thread: from, to (spine), across (-1 in .. 1 top edge), width, lift

# --- the pen work at the feet ---------------------------------------------------------------------------
# Each stroke is drawn in its own plane as (u, v) studs: u out of the leg, v up the plane; the first point
# lies buried in the leg. A pen's stroke: wider where it runs across the nib, narrower along it, but the
# brown never thinner than its ink on either side (ref-1: the brown is the wider part of every loop), and
# tapering to a point only at its end.
PEN = (0.22, 0.14, 0.12)  # widest, thinnest, depth (studs)
PEN_HULL = (0.12, 0.1)  # the contour at the root and along the rest (studs)
OVER = 0.42  # at a crossing, how much further along the plane's face the later pass rides
# The paraph off the left foot: down out of the leg, across itself, out into a long loop, back through
# the crossing and into a small hooked curl.
PARAPH = [(-0.4, 2.1), (0.15, 1.85), (0.8, 1.1), (1.3, 0.45), (1.95, 0.12), (2.6, 0.42), (2.72, 1.1), (2.25, 1.62),
          (1.5, 1.52), (0.8, 1.1), (0.38, 0.78), (0.28, 0.48), (0.5, 0.3), (0.78, 0.42)]
# The second, smaller loop off the left foot: it crosses the paraph's long loop, a figure-8 with it (ref-1).
PARAPH2 = [(-0.3, 1.3), (0.3, 1.2), (0.95, 1.05), (1.5, 1.35), (1.45, 1.85), (0.95, 1.9), (0.7, 1.45), (0.95, 0.85), (1.45, 0.6)]
# The cursive loop off the right foot: out, up round a loop that crosses its own entry, down to a hook.
CURSIVE = [(-0.4, 0.9), (0.2, 0.95), (0.8, 1.12), (1.38, 1.5), (1.58, 2.0), (1.22, 2.36), (0.74, 2.15), (0.66, 1.58),
           (0.86, 1.05), (1.08, 0.66), (1.4, 0.46), (1.7, 0.58)]
# The closed flourish: a spiral closing in on itself, low behind the left foot.
FLOURISH = [(-0.35, 0.0), (0.25, -0.04), (0.8, -0.02), (1.3, 0.3), (1.4, 0.85), (1.05, 1.25), (0.55, 1.15),
            (0.4, 0.75), (0.65, 0.5), (0.9, 0.65)]
# name, where the root is buried (spine s, across a), the plane's face, the way u runs, the way v runs,
# the stroke, its stations, its scale, the nib's angle. The two outer strokes face up and back, toward
# the thrower's camera over the shoulder: from behind they read as loops beside the caster (the model
# sheet's note), from above as rings, from the front as curls. The closed flourish lies nearly flat.
LOOPS = (
    ("paraph", 0.165, 0.72, (-0.25, 0.62, 0.74), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), PARAPH, 34, 0.82, 35),
    ("paraph2", 0.2, 0.7, (-0.15, 0.7, 0.7), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), PARAPH2, 22, 0.8, 35),
    ("flourish", 0.06, -0.4, (0.1, 0.95, 0.3), (1.0, 0.0, 0.0), (0.0, -0.3, 0.95), FLOURISH, 20, 0.8, -35),
    ("cursive", 0.905, 0.72, (0.25, 0.62, 0.74), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), CURSIVE, 24, 0.78, -35),
)

# The S-horn: the band itself run out of the back of the right leg (the model sheet's side view) -- out
# of the leg low, down into a belly, up behind the band into a hook. Seen from the front, its whole track
# lies inside the band's own silhouette: it rises behind the band, never over the shoulder. Studs.
HORN = [(3.45, 1.7, 0.35), (3.5, 1.42, 1.05), (3.42, 1.22, 1.68), (3.18, 1.58, 2.22), (2.85, 2.35, 2.5),
        (2.52, 3.08, 2.55), (2.28, 3.55, 2.36), (2.2, 3.72, 2.02)]
# The two thin whips: crescents out of the right leg's back that arch up and back over the leg and fall
# inside the arch, unequal and never parallel. Studs; the first point is buried in the leg.
WHIPS = (
    ([(3.25, 2.1, 0.45), (3.12, 2.6, 0.95), (2.78, 3.05, 1.42), (2.27, 3.2, 1.9), (1.72, 2.96, 2.28), (1.32, 2.42, 2.48),
      (0.95, 1.7, 2.62), (0.8, 1.1, 2.6)], 0.14, 14),
    ([(3.55, 1.25, 0.5), (3.42, 1.72, 0.98), (3.06, 2.07, 1.42), (2.62, 2.17, 1.84), (2.22, 1.88, 2.16), (2.0, 1.42, 2.3),
      (2.06, 1.02, 2.2), (2.2, 0.6, 2.1)], 0.12, 12),
)
WHIP_FACE = (0.7, 0.0, 0.7)  # a whip's faces: half to the side, half back -- a ribbon from behind and from the side


def camber(x: float) -> float:
    return CAMBER * (x / 4.0) ** 2


# --- a swept slab -----------------------------------------------------------------------------------


def guard(frames, sections, weights, start: str, end: str, keep: float = 0.3):
    """Narrows a ring wherever the spine bends tighter than the ring is wide, so that every corner still
    moves forward along the spine from one ring to the next: a band never folds over itself on the inside
    of a bend. The contour counts: each corner's offset is lengthened by its weight, so the hull, pushed
    out on the inside of the bend, does not fold over either. Returns each ring's scale, eased over its
    neighbours so a narrowing is a pinch of the pen, not a notch."""
    count = len(frames)
    scale = [1.0] * count
    for _ in range(8):
        for i in range(count - 1):
            if (i == 0 and start == "tip") or (i + 1 == count - 1 and end == "tip"):
                continue
            (p0, r0, d0), (p1, r1, d1) = frames[i], frames[i + 1]
            step = sub(p1, p0)
            length = math.sqrt(dot(step, step))
            if length < 1e-9:
                continue
            t = mul(step, 1.0 / length)
            for (a0, b0), (a1, b1) in zip(sections[i], sections[i + 1]):
                o0 = _reach(mul(add(mul(r0, a0), mul(d0, b0)), scale[i]), weights[i])
                o1 = _reach(mul(add(mul(r1, a1), mul(d1, b1)), scale[i + 1]), weights[i + 1])
                pull = dot(sub(o1, o0), t)
                if length + pull < keep * length:
                    f = (1.0 - keep) * length / -pull
                    scale[i] *= f
                    scale[i + 1] *= f
        eased = []
        for i in range(count):
            near = [scale[j] for j in range(max(0, i - 2), min(count, i + 3))]
            eased.append(min(scale[i], 0.5 * (scale[i] + min(near))))
        scale = eased
    return scale


def _reach(offset, weight: float):
    """A corner's offset from the spine, carried on out to where its contour lies."""
    length = math.sqrt(dot(offset, offset))
    return offset if length < 1e-9 else mul(offset, 1.0 + weight / length)


def _mitre(u, v):
    """The offset that moves two planes (unit normals u, v) out by 1 each, its length held to 2.5."""
    k = 1.0 / max(1.0 + dot(u, v), 0.32)
    return mul(add(u, v), k)


def _pushes(vol: Volume, rings, frames, start: str, end: str) -> None:
    """Each ring vertex's contour direction (for a weight of 1): the mitre of the two side strips it
    lies between, each strip's normal taken across its own width and along the sweep from the rings on
    either side -- smooth from ring to ring, where a hull built from single face normals jitters on a
    thin wavy band -- and the end rings pushed on past their caps. `contour` then lengthens it wherever
    a face at the vertex would stand nearer than the weight."""
    count = len(rings)
    verts = vol.mesh.verts
    for i, ring in enumerate(rings):
        a_, b_ = frames[max(i - 1, 0)][0], frames[min(i + 1, count - 1)][0]
        t = norm(sub(b_, a_))
        if len(set(ring)) == 1:
            vol.push[ring[0]] = mul(t, -1.0) if i == 0 else t
            continue
        m = len(ring)
        p = tuple(sum(verts[v][a] for v in ring) / m for a in range(3))  # the ring's centre, lifted with it
        prev, nxt = rings[max(i - 1, 0)], rings[min(i + 1, count - 1)]
        strips = []
        for j in range(m):
            k = (j + 1) % m
            along = sub(add(verts[nxt[j]], verts[nxt[k]]), add(verts[prev[j]], verts[prev[k]]))
            across = sub(verts[ring[k]], verts[ring[j]])
            n = norm(cross(along, across))
            mid = mul(add(verts[ring[j]], verts[ring[k]]), 0.5)
            if dot(n, sub(mid, p)) < 0:
                n = mul(n, -1.0)
            strips.append(n)
        capped = (i == 0 and start == "cap") or (i == count - 1 and end == "cap")
        cap = (mul(t, -1.0) if i == 0 else t) if capped else (0.0, 0.0, 0.0)
        for j in range(m):
            vol.push[ring[j]] = add(_mitre(strips[j - 1], strips[j]), cap)


def sweep(frames, sections, weights, start: str = "cap", end: str = "cap") -> Volume:
    """A closed slab through rings: frames[i] = (point, r, d), sections[i] = corners (a, b) in (r, d),
    counter-clockwise; `start` / `end` close it with a cap or collapse it to a tip. Rings are narrowed at
    tight bends (`guard`), and a ring that would dip under the floor is lifted whole, never squashed.
    Each vertex also gets its contour's direction (`vol.push`, for a weight of 1), and a tip's vertex is
    recorded (`vol.tips`): the one point a pen's lighter weight is allowed."""
    vol = Volume()
    vol.tips = set()
    rings = []
    count = len(frames)
    scale = guard(frames, sections, weights, start, end)
    for i, ((p, r, d), corners, w) in enumerate(zip(frames, sections, weights)):
        if (i == 0 and start == "tip") or (i == count - 1 and end == "tip"):
            v = vol.vert((p[0], max(p[1], 0.0), p[2]), w)
            vol.tips.add(v)
            rings.append([v] * len(corners))
            continue
        pts = [add(p, mul(add(mul(r, a), mul(d, b)), scale[i])) for a, b in corners]
        lift = max(0.0, -min(q[1] for q in pts))
        rings.append([vol.vert((q[0], q[1] + lift, q[2]), w) for q in pts])
    vol.push = [(0.0, 0.0, 0.0)] * len(vol.mesh.verts)
    _pushes(vol, rings, frames, start, end)
    m = len(rings[0])
    for ra, rb in zip(rings, rings[1:]):
        for j in range(m):
            k = (j + 1) % m
            emit(vol.mesh, ra[j], ra[k], rb[k])
            emit(vol.mesh, ra[j], rb[k], rb[j])
    for ring, w, forward in ((rings[0], weights[0], start == "cap"), (rings[-1], weights[-1], end == "cap")):
        if not forward:
            continue
        centre = tuple(sum(vol.mesh.verts[v][a] for v in ring) / m for a in range(3))
        c = vol.vert(centre, w)
        i = 0 if ring is rings[0] else count - 1
        a_, b_ = frames[max(i - 1, 0)][0], frames[min(i + 1, count - 1)][0]
        t = norm(sub(b_, a_))
        vol.push.append(mul(t, -1.0) if i == 0 else t)
        for j in range(m):
            if ring is rings[0]:
                emit(vol.mesh, c, ring[(j + 1) % m], ring[j])
            else:
                emit(vol.mesh, c, ring[j], ring[(j + 1) % m])
    vol.orient_outward()
    return vol


def path_frames(points, count: int, facing):
    """Frames along a dense polyline at `count` + 1 even stations: d is `facing(u, p, tangent)` made
    square to the tangent, r = tangent x d."""
    line = Polyline(points)
    out = []
    for i in range(count + 1):
        u = i / count
        p = line.at(u)
        a, b = line.at(max(0.0, u - 0.004)), line.at(min(1.0, u + 0.004))
        t = norm(sub(b, a))
        f = facing(u, p, t)
        d = norm(sub(f, mul(t, dot(f, t))))
        out.append((p, norm(cross(t, d)), d))
    return out


def slab(width: float, depth: float):
    h, t = width / 2.0, depth / 2.0
    return [(h, t), (-h, t), (-h, -t), (h, -t)]


class Band:
    """A calligraphic band swept along a spine, its faces toward `face` (default: -z front and +z back):
    the blade's arch, its horn, and the slump's fold, strands and runs. Across it r runs inward (for an
    arch, toward the hollow under it), the top edge is -r and is `wedge` as thick as the inner one."""

    def __init__(self, spine, spec: dict, seed: int) -> None:
        self.line = Polyline(catmull(spine, 24))
        self.spec = spec
        self.seed = seed

    def _face(self, s: float):
        f = self.spec.get("face", BACK)
        return f(s) if callable(f) else f

    def frame(self, s: float):
        p = self.line.at(s)
        a, b = self.line.at(max(0.0, s - 0.003)), self.line.at(min(1.0, s + 0.003))
        t = norm(sub(b, a))
        lv = self.spec.get("level", 0.0)
        l0, l1 = lv if isinstance(lv, tuple) else (lv, lv)
        level = 0.0
        if l0 > 0.0:
            level = max(level, 1.0 - smoothstep(0.0, l0, s))
        if l1 > 0.0:
            level = max(level, smoothstep(1.0 - l1, 1.0, s))
        if level > 0.0:
            t = norm(lerp(t, (0.0, math.copysign(1.0, t[1]), 0.0), level))
        f = self._face(s)
        d = norm(sub(f, mul(t, dot(f, t))))
        return p, norm(cross(t, d)), d

    def toe(self, s: float) -> float:
        run = self.spec.get("toe_run", 0.05)
        return max(1.0 - smoothstep(0.0, run, s), smoothstep(1.0 - run, 1.0, s))

    def half_widths(self, s: float) -> tuple[float, float]:
        """(inner, outer) half-widths: the toe adds to the outer one at each foot."""
        w = cosine_curve(self.spec["width"], s) * (1.0 + self.spec.get("wobble", 0.0) * (fbm(5.0 * s, 0.7, self.seed) - 0.5))
        run = self.spec.get("toe_run", 0.05)
        left, right = self.spec.get("toe", (0.0, 0.0))
        outer = w / 2.0 + left * (1.0 - smoothstep(0.0, run, s)) ** 2 + right * smoothstep(1.0 - run, 1.0, s) ** 2
        return w / 2.0, outer

    def depths(self, s: float) -> tuple[float, float]:
        """(inner, top-edge) half-depths: the top edge thins further into the point of each toe."""
        d = cosine_curve(self.spec["depth"], s) / 2.0
        toe = self.toe(s) if any(self.spec.get("toe", (0.0, 0.0))) else 0.0
        return d, d * self.spec["wedge"] * (1.0 - 0.75 * toe)

    def section(self, s: float):
        wi, wo = self.half_widths(s)
        di, do = self.depths(s)
        return [(wi, di), (-wo, do), (-wo, -do), (wi, -di)]

    def point(self, s: float, a: float, side: int):
        """On the front (side -1) or back (+1) face: a = -1 at the inner edge, +1 at the top edge."""
        p, r, d = self.frame(s)
        wi, wo = self.half_widths(s)
        di, do = self.depths(s)
        inner = add(p, add(mul(r, wi), mul(d, side * di)))
        outer = add(p, add(mul(r, -wo), mul(d, side * do)))
        q = lerp(inner, outer, (a + 1.0) / 2.0)
        return (q[0], max(q[1], 0.0), q[2])

    def normal(self, s: float, a: float, side: int):
        e = 1e-3
        ds = sub(self.point(min(1.0, s + e), a, side), self.point(max(0.0, s - e), a, side))
        da = sub(self.point(s, min(1.0, a + e), side), self.point(s, max(-1.0, a - e), side))
        n = norm(cross(ds, da))
        if dot(n, self.frame(s)[2]) * side < 0:
            n = mul(n, -1.0)
        return n

    def surface(self, side: int):
        return (lambda s, a: self.point(s, a, side)), (lambda s, a: self.normal(s, a, side))

    def weight(self, s: float) -> float:
        if "hull_curve" in self.spec:
            return max(CONTOUR_MIN, cosine_curve(self.spec["hull_curve"], s))
        heavy, light = self.spec["hull"]
        foot = max(1.0 - smoothstep(0.0, 0.35, s), smoothstep(0.7, 1.0, s))
        return max(CONTOUR_MIN, light + (heavy - light) * foot)

    def volume(self) -> Volume:
        count = self.spec["stations"]
        start, end = self.spec.get("ends", ("cap", "cap"))
        frames, sections, weights = [], [], []
        for i in range(count + 1):
            s = i / count
            frames.append(self.frame(s))
            sections.append(self.section(s))
            weights.append(self.weight(s))
        if end == "tip":
            weights[-1] = TIP_WEIGHT
        if start == "tip":
            weights[0] = TIP_WEIGHT
        return sweep(frames, sections, weights, start, end)


# --- ribbons laid on a surface, pen strokes, wisps, streaks, pools ---------------------------------------


def lay(mesh: Mesh, surface, path, width, lift: float, samples: int) -> None:
    """A ribbon lying `lift` off a surface (point(s, a), normal(s, a)): path(tau) -> (s, a)."""
    point, normal = surface
    pts = []
    for i in range(samples):
        tau = i / (samples - 1)
        s, a = path(tau)
        pts.append((point(s, a), normal(s, a), width(tau)))
    lefts, rights = [], []
    for i, (p, n, w) in enumerate(pts):
        along = norm(sub(pts[min(i + 1, samples - 1)][0], pts[max(i - 1, 0)][0]))
        across = norm(cross(n, along))
        base = add(p, mul(n, lift))
        for q, into in ((add(base, mul(across, w / 2.0)), lefts), (add(base, mul(across, -w / 2.0)), rights)):
            into.append(mesh.vert((q[0], max(q[1], 0.05), q[2])))
    for i in range(samples - 1):
        mesh.tri(lefts[i], rights[i], lefts[i + 1], pts[i][1])
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1], pts[i][1])


def lens(peak: float, power: float = 0.7):
    """A width that swells from a point to `peak` and back to a point."""
    return lambda tau: peak * math.sin(math.pi * tau) ** power


def brush(peak: float, attack: float = 0.15):
    """Pressed in fast, released slowly to a point: a brush stroke's width."""
    return lambda tau: peak * min(1.0, tau / attack) ** 0.6 * (1.0 - tau) ** 0.8


def plane_axes(normal, outward, rise):
    """In-plane axes for a stroke whose face is `normal`: u as near `outward` as the plane allows, v as
    near `rise`."""
    n = norm(normal)
    u = norm(sub(outward, mul(n, dot(outward, n))))
    v = norm(cross(n, u))
    if dot(v, rise) < 0:
        v = mul(v, -1.0)
    return u, v


def crossings(points):
    """Where a flat polyline crosses itself: pairs of arc-length fractions (earlier, later)."""
    acc = [0.0]
    for a, b in zip(points, points[1:]):
        acc.append(acc[-1] + math.dist(a, b))
    total = acc[-1]
    found = []
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        for j in range(i + 2, len(points) - 1):
            c, e = points[j], points[j + 1]
            d1, d2 = (b[0] - a[0], b[1] - a[1]), (e[0] - c[0], e[1] - c[1])
            den = d1[0] * d2[1] - d1[1] * d2[0]
            if abs(den) < 1e-12:
                continue
            t = ((c[0] - a[0]) * d2[1] - (c[1] - a[1]) * d2[0]) / den
            s = ((c[0] - a[0]) * d1[1] - (c[1] - a[1]) * d1[0]) / den
            if 0.0 <= t <= 1.0 and 0.0 <= s <= 1.0:
                found.append(((acc[i] + t * (acc[i + 1] - acc[i])) / total, (acc[j] + s * (acc[j + 1] - acc[j])) / total))
    return found


def pen_stroke(root, normal, outward, rise, ctrl, stations: int, scale: float, nib: float) -> Volume:
    """A pen stroke in the plane facing `normal`, through `ctrl` (u, v), its first point at `root` (buried
    in the leg): wide where it runs across the nib, narrower along it, never under PEN's thinnest before
    it tapers to its point (the hook). Where it crosses itself the later pass rides OVER further along the
    face than the earlier one, so the two never meet and the upper one's contour draws across the lower:
    a pen crossing, not a knot. Its contour eases from the root's weight to the rest's, never under the
    bible's 0.1 stud; only the hook's point is lighter."""
    wide, thin, depth = PEN
    heavy, light = PEN_HULL
    u_axis, v_axis = plane_axes(normal, outward, rise)
    plane = norm(normal)
    flat = [(u * scale, v * scale) for u, v in catmull(ctrl, 16)]
    acc = [0.0]
    for a, b in zip(flat, flat[1:]):
        acc.append(acc[-1] + math.dist(a, b))
    over = crossings(flat)
    lo, hi = (over[0][0] + 0.1, over[0][1] - 0.1) if over else (0.0, 1.0)
    u0, v0 = flat[0]
    pts = []
    for (u, v), f in zip(flat, acc):
        f /= acc[-1]
        lift = OVER * (smoothstep(lo, hi, f) - 0.5) if over else 0.0
        pts.append(add(root, add(add(mul(u_axis, u - u0), mul(v_axis, v - v0)), mul(plane, lift + OVER / 2.0 if over else 0.0))))
    frames = path_frames(pts, stations, lambda u, p, t: plane)
    sections, weights = [], []
    for i, (p, r, d) in enumerate(frames):
        u = i / stations
        t = norm(cross(d, r))
        angle = math.atan2(dot(t, v_axis), dot(t, u_axis))
        w = thin + (wide - thin) * abs(math.sin(angle - math.radians(nib))) ** 1.4
        w *= (1.0 - smoothstep(0.84, 1.0, u) ** 1.2) * (0.75 + 0.25 * smoothstep(0.0, 0.1, u))
        sections.append(slab(max(w, 0.03), depth * (1.0 - 0.5 * smoothstep(0.8, 1.0, u))))
        weights.append(max(CONTOUR_MIN, heavy + (light - heavy) * smoothstep(0.05, 0.3, u)))
    weights[-1] = TIP_WEIGHT
    return sweep(frames, sections, weights, start="cap", end="tip")


def whip_volume(ctrl, peak: float, stations: int) -> Volume:
    """A thin whip: a flat crescent swept along a Catmull-Rom path, its faces half to the side and half
    back, swelling from its root (buried in the leg) to `peak` a third of the way out and tapering to a
    point. Its contour is 0.1 stud up to the last ring; only the point is lighter."""
    frames = path_frames(catmull(ctrl, 16), stations, lambda u, p, t: WHIP_FACE)
    sections, weights = [], []
    for i in range(stations + 1):
        u = i / stations
        w = peak * math.sin(math.pi * (0.2 + 0.8 * u)) ** 0.75
        sections.append(slab(max(w, 0.03), max(0.09 * (1.0 - 0.5 * u), 0.03)))
        weights.append(CONTOUR_MIN)
    weights[-1] = TIP_WEIGHT
    return sweep(frames, sections, weights, start="cap", end="tip")


def ink_wisp(mesh: Mesh, ctrl, radius: float, segs: int) -> None:
    """A loose ink stroke in the air, three-sided, pointed at both ends: drawn in the ink's own tone."""
    line = Polyline(catmull(ctrl, 12))
    side = None
    rings = []
    for i in range(segs + 1):
        u = i / segs
        p = line.at(u)
        a, b = line.at(max(0.0, u - 0.01)), line.at(min(1.0, u + 0.01))
        t = norm(sub(b, a))
        if side is None:
            side = norm(cross(t, BACK))
        side = norm(sub(side, mul(t, dot(side, t))))
        up = norm(cross(side, t))
        if i in (0, segs):
            rings.append([mesh.vert(p)] * 3)
            continue
        rad = radius * math.sin(math.pi * u) ** 0.6
        ring = []
        for k in range(3):
            ang = math.pi / 2 + 2 * math.pi * k / 3
            ring.append(mesh.vert(add(p, add(mul(up, rad * math.sin(ang)), mul(side, rad * math.cos(ang))))))
        rings.append(ring)
    for ra, rb in zip(rings, rings[1:]):
        centre = mul(add(add(mesh.verts[ra[0]], mesh.verts[ra[1]]), mesh.verts[ra[2]]), 1 / 3)
        for j in range(3):
            k = (j + 1) % 3
            for tri in ((ra[j], ra[k], rb[k]), (ra[j], rb[k], rb[j])):
                mid = mul(add(add(*(mesh.verts[v] for v in tri[:2])), mesh.verts[tri[2]]), 1 / 3)
                mesh.tri(*tri, sub(mid, centre))


def floor_streak(mesh: Mesh, ctrl, width, lift: float, samples: int, ridge: float = 0.0) -> None:
    """A skid mark on the page: a tapered streak of ink lying `lift` over the floor, facing up; with
    `ridge`, its spine is raised that high at the root and falls to the tip -- a thorn of ink scraped up
    off the page, which shows from the front as well as from above."""
    line = Polyline(catmull(ctrl, 12))
    if ridge > 0.0:
        rows = []
        for i in range(samples):
            tau = i / (samples - 1)
            x, z = line.at(tau)
            a, b = line.at(max(0.0, tau - 0.01)), line.at(min(1.0, tau + 0.01))
            tx, tz = b[0] - a[0], b[1] - a[1]
            length = math.hypot(tx, tz) or 1.0
            nx, nz = -tz / length, tx / length
            w = width(tau) / 2.0
            h = lift + ridge * (1.0 - tau) ** 1.3
            rows.append((mesh.vert((x + nx * w, lift, z + nz * w)), mesh.vert((x, h, z)), mesh.vert((x - nx * w, lift, z - nz * w)), (nx, nz)))
        for (l0, c0, r0, (nx, nz)), (l1, c1, r1, _) in zip(rows, rows[1:]):
            mesh.tri(l0, c0, l1, (nx, 1.0, nz))
            mesh.tri(c0, c1, l1, (nx, 1.0, nz))
            mesh.tri(c0, r0, r1, (-nx, 1.0, -nz))
            mesh.tri(c0, r1, c1, (-nx, 1.0, -nz))
        # The root's end, facing back along the streak toward the foot it was scraped from.
        l0, c0, r0, _ = rows[0]
        mesh.tri(l0, r0, c0, sub(mesh.verts[c0], mesh.verts[rows[1][1]]))
        return
    lefts, rights = [], []
    for i in range(samples):
        tau = i / (samples - 1)
        x, z = line.at(tau)
        a, b = line.at(max(0.0, tau - 0.01)), line.at(min(1.0, tau + 0.01))
        tx, tz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(tx, tz) or 1.0
        nx, nz = -tz / length, tx / length
        w = width(tau) / 2.0
        lefts.append(mesh.vert((x + nx * w, lift, z + nz * w)))
        rights.append(mesh.vert((x - nx * w, lift, z - nz * w)))
    for i in range(samples - 1):
        mesh.tri(lefts[i], rights[i], lefts[i + 1], (0.0, 1.0, 0.0))
        mesh.tri(rights[i], rights[i + 1], lefts[i + 1], (0.0, 1.0, 0.0))


POOL_PROFILE = ((1.0, 0.0), (1.0, 0.45), (0.9, 0.82), (0.68, 1.0))  # (share of the rim's reach, share of height)
DROP_PROFILE = ((1.0, 0.0), (0.78, 0.8))  # a drop is small: a rim and a shoulder


def pool(centre, rx: float, rz: float, height: float, sides: int, seed: int, wall: float | None = None,
         lobes: float = 0.1, profile=POOL_PROFILE) -> Volume:
    """A low round body of ink on the page: a wavering rim, a flat bottom on the floor facing down, and a
    rounded shoulder -- the rim rises steeply, rolls over and flattens into a low dome, so seen from the
    side it is a drop, not a slab. With `wall`, the rim is kept off z = wall by a soft limit: the pool
    flattens against the wall with round corners."""
    vol = Volume()
    rng = Rng(seed)
    x0, _, z0 = centre
    rim = []
    for k in range(sides):
        a = 2.0 * math.pi * k / sides
        wob = 1.0 + lobes * math.sin(3.0 * a + 0.7) + 0.5 * lobes * math.sin(5.0 * a + 2.1) + 0.04 * (rng.random() - 0.5)
        x, z = x0 + rx * math.cos(a) * wob, z0 + rz * math.sin(a) * wob
        if wall is not None:
            # A soft floor at the wall: far from it nothing moves, near it the rim eases flat.
            g = z - wall
            z = wall + 0.5 * (g + math.sqrt(g * g + 0.04))
        rim.append((x, z))
    rings = []
    for share, rise in profile:
        rings.append([vol.vert((x0 + (x - x0) * share, height * rise, z0 + (z - z0) * share), CONTOUR_MIN) for x, z in rim])
    top = vol.vert((x0, height * 1.12, z0), CONTOUR_MIN)
    bottom = vol.vert((x0, 0.0, z0), CONTOUR_MIN)
    m = len(rim)
    for k in range(m):
        j = (k + 1) % m
        emit(vol.mesh, bottom, rings[0][j], rings[0][k])
        for ra, rb in zip(rings, rings[1:]):
            emit(vol.mesh, ra[k], ra[j], rb[j])
            emit(vol.mesh, ra[k], rb[j], rb[k])
        emit(vol.mesh, top, rings[-1][k], rings[-1][j])
    vol.orient_outward()
    return vol


# --- the contour --------------------------------------------------------------------------------------
# FLOOR_CLEARANCE of strokes.py: how far over the floor the contour stays (reference units).
FLOOR = 0.004


def _clear(push, planes, cap: float = 2.6):
    """Lengthens a push (for a weight of 1) until it stands off every plane by at least 1: each time
    along the nearest plane's normal, by what it is short. The smooth push stays where it is enough."""
    d = push
    for _ in range(24):
        worst, short = None, 1e-6
        for n in planes:
            gap = 1.0 - dot(d, n)
            if gap > short:
                worst, short = n, gap
        if worst is None:
            break
        d = add(d, mul(worst, short))
    length = math.sqrt(dot(d, d))
    return d if length <= cap else mul(d, cap / length)


def contour(vol: Volume, into: Mesh) -> None:
    """The inverted hull of strokes.inverted_hull, mitred: each vertex is pushed out along its smooth
    push (`sweep`), lengthened so that every face plane at that vertex stands off by the vertex's weight
    (a pen point excepted); a volume without pushes takes the bisector of its distinct planes. The
    shipped hull sums area-weighted face normals, and on a thin slab (a band, a pen ribbon) the broad
    faces outweigh the narrow edges, so the outline at the silhouette came out at half the weight --
    under the 0.1 stud the bible holds a contour to."""
    mesh = vol.mesh
    push = getattr(vol, "push", None)
    tips = getattr(vol, "tips", set())
    planes: list[list] = [[] for _ in mesh.verts]
    for a, b, c in mesh.tris:
        n = norm(cross(sub(mesh.verts[b], mesh.verts[a]), sub(mesh.verts[c], mesh.verts[a])))
        for v in (a, b, c):
            if all(dot(n, m) < 0.9995 for m in planes[v]):
                planes[v].append(n)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        if not planes[i]:
            into.verts.append(p)
            continue
        if push is not None:
            d = push[i]
        else:
            bis = norm(tuple(sum(n[k] for n in planes[i]) for k in range(3)))
            d = mul(bis, 1.0 / max(min(dot(bis, n) for n in planes[i]), 0.5))
        if i not in tips:
            d = _clear(d, planes[i])
        q = add(p, mul(d, vol.weight[i]))
        into.verts.append((q[0], max(q[1], FLOOR), q[2]))
    for a, b, c in mesh.tris:
        corners = [into.verts[v + base] for v in (a, b, c)]
        # A face the floor clamp pressed into a sliver on the page covers nothing its neighbours do not.
        if all(q[1] <= 1.5 * FLOOR for q in corners) and min(_angles(*corners)) < 2.0:
            continue
        emit(into, a + base, c + base, b + base)


def _angles(a, b, c):
    out = []
    for o, p, q in ((a, b, c), (b, c, a), (c, a, b)):
        u, v = sub(p, o), sub(q, o)
        lu, lv = math.sqrt(dot(u, u)), math.sqrt(dot(v, v))
        if lu < 1e-12 or lv < 1e-12:
            return [0.0]
        out.append(math.degrees(math.acos(max(-1.0, min(1.0, dot(u, v) / (lu * lv))))))
    return out


# --- assembling a form --------------------------------------------------------------------------------


def _scale(meshes, vols, factor: float) -> None:
    for m in meshes:
        m.verts = [(x * factor, y * factor, z * factor) for x, y, z in m.verts]
    for v in vols:
        v.weight = [w * factor for w in v.weight]


def _assemble(solids, edge: Mesh, ink: Mesh) -> tuple[Mesh, Mesh, Mesh, float]:
    """Into reference units (so the hull's floor clearance is the shipped one), the contour of every
    solid, then exactly 1 across X, centred, the floor at y = 0, the leading edge on the box's front.
    Returns the three meshes and the factor the studs were scaled by at the end (should the built span
    come out over 12 studs, the weights are thickened first by as much, so no contour is thinned under
    its weight by the final scale)."""
    _scale([edge, ink] + [v.mesh for v in solids], solids, 1.0 / WIDTH)
    base = [list(vol.weight) for vol in solids]
    for _ in range(3):
        probe = Mesh("up")
        for vol in solids:
            contour(vol, probe)
        xs = [v[0] for m in (edge, ink, probe) for v in m.verts] + [v[0] for vol in solids for v in vol.mesh.verts]
        over = max(1.0, max(xs) - min(xs))
        for vol, weights in zip(solids, base):
            vol.weight = [w * over for w in weights]
    body = Mesh("up")
    for vol in solids:
        body.merge(vol.mesh)
        contour(vol, ink)
    meshes = (body, edge, ink)
    xs = [v[0] for m in meshes for v in m.verts]
    factor, shift = 1.0 / (max(xs) - min(xs)), -(max(xs) + min(xs)) / 2.0
    for m in meshes:
        m.verts = [((x + shift) * factor, y * factor, z * factor) for x, y, z in m.verts]
    front = min(v[2] for m in meshes for v in m.verts)
    dz = -DEPTH / 2.0 / WIDTH - front
    for m in meshes:
        m.verts = [(x, y, z + dz) for x, y, z in m.verts]
    return body, edge, ink, factor


# --- the blade --------------------------------------------------------------------------------------


def _arch() -> Band:
    return Band([(x, y, camber(x)) for x, y in ARCH_SPINE], ARCH, SEED)


def _horn_face(s: float):
    """The horn's faces: to the side at its root, so the side view sees it broad, turning up and back
    toward the thrower's camera as it rises into its hook -- a ribbon's twist, not a blade's."""
    return norm(lerp(SIDE, (0.5, 0.45, 0.74), smoothstep(0.5, 1.0, s)))


def _horn() -> Band:
    """The S-horn: the band run out of the leg's back face, faces to the side, thick-edged on top (where
    the pale thread runs), narrowing to a point at its hook."""
    spec = {"stations": 22, "width": [(0.0, 0.78), (0.35, 0.64), (0.75, 0.48), (1.0, 0.24)],
            "depth": [(0.0, 0.2), (0.6, 0.16), (1.0, 0.11)], "wedge": 0.5, "face": _horn_face,
            "ends": ("cap", "tip"), "hull_curve": [(0.0, 0.13), (0.5, 0.11), (1.0, 0.1)], "wobble": 0.04}
    return Band(HORN, spec, SEED + 10)


def _horn_up(band: Band) -> float:
    """Which way across the horn (a = -1 or +1) is its upper edge."""
    p, r, _ = band.frame(0.5)
    return -1.0 if r[1] > 0 else 1.0


def _blade_parts():
    return _arch(), _horn()


def _blade_solids(arch: Band, horn: Band) -> list:
    solids = [arch.volume()]
    for name, s0, across, face, outward, rise, ctrl, stations, scale, nib in LOOPS:
        if name == "flourish":
            # Low behind the foot, its root in the back face near the inner edge.
            x, y, z = arch.point(s0, across, +1)
            root = (x - 0.2 - 0.35 * scale, y + 0.3, z - 0.2)
        else:
            # Buried in the leg near its outer edge, half way through it.
            root = arch.point(s0, across, 0)
        solids.append(pen_stroke(root, face, outward, rise, ctrl, stations, scale, nib))
    solids.append(horn.volume())
    for ctrl, peak, stations in WHIPS:
        solids.append(whip_volume(ctrl, peak, stations))
    return solids


def _blade_ink(ink: Mesh, arch: Band) -> None:
    # The flow lines: brush striations up from each foot, on both faces, unequal and never parallel.
    for side in (-1, +1):
        for s0, s1, a0, a1, w in ((0.015, 0.21, -0.35, 0.05, 0.13), (0.04, 0.15, 0.3, 0.42, 0.1), (0.8, 0.975, -0.15, -0.45, 0.12)):
            lay(ink, arch.surface(side), lambda tau, s0=s0, s1=s1, a0=a0, a1=a1: (s0 + (s1 - s0) * tau, a0 + (a1 - a0) * tau),
                brush(w), 0.03, 8)
    # The skid: three streaks scraped off the left foot along the page, under the arch and back.
    fx, _, fz = arch.point(0.0, 0.0, 0)
    for dx, dz, length, w in ((0.3, 0.0, 3.9, 0.34), (0.1, 0.35, 2.8, 0.26), (0.45, -0.3, 2.0, 0.22)):
        x0, z0 = fx + dx, fz + dz
        ctrl = [(x0, z0), (x0 + 0.35 * length, z0 + 0.12 * length + dz), (x0 + 0.7 * length, z0 + 0.3 * length + 1.4 * dz),
                (x0 + length, z0 + 0.45 * length + 1.8 * dz)]
        floor_streak(ink, ctrl, brush(w, 0.08), 0.07, 9, ridge=0.3 * w / 0.34)
    # Two loose wisps up the outside of the left leg: the speed of the stroke.
    for off, s_lo, s_hi, radius in ((0.3, 0.2, 0.42, 0.08), (0.55, 0.25, 0.37, 0.06)):
        ctrl = []
        for k in range(5):
            s = s_lo + (s_hi - s_lo) * k / 4
            p, r, d = arch.frame(s)
            _, wo = arch.half_widths(s)
            ctrl.append(add(p, add(mul(r, -(wo + off * math.sin(math.pi * (0.15 + 0.7 * k / 4)))), mul(d, 0.25))))
        ink_wisp(ink, ctrl, radius, 9)


def _blade_edge(edge: Mesh, arch: Band, horn: Band) -> None:
    s0, s1, a, width, lift = THREAD
    for side in (-1, +1):
        lay(edge, arch.surface(side), lambda tau: (s0 + (s1 - s0) * tau, a + 0.04 * math.sin(math.pi * tau)), lens(width, 0.5), lift, 30)
    # The horn carries the thread on, just inside its upper edge, on both faces.
    up = _horn_up(horn)
    for side in (-1, +1):
        lay(edge, horn.surface(side), lambda tau: (0.2 + 0.56 * tau, up * 0.5), lens(0.08, 0.5), 0.03, 16)


_CACHE: dict = {}


def blade() -> tuple[Mesh, Mesh, Mesh, float]:
    if "blade" not in _CACHE:
        arch, horn = _blade_parts()
        edge, ink = Mesh("up"), Mesh("up")
        _blade_edge(edge, arch, horn)
        _blade_ink(ink, arch)
        solids = _blade_solids(arch, horn)
        _CACHE["blade"] = _assemble(solids, edge, ink)
    return _CACHE["blade"]


# --- the slump --------------------------------------------------------------------------------------
# Studs, the wall's face at z = 0, the body on the thrower's side of it (+z), pressed to it. Three layers
# that never come within a contour's reach of one another (0.2 stud and more between faces), so no
# contour ever crosses a face it lies behind: the fold's back leg against the wall, the two strands
# hanging inside the fold, the fold's front leg. The crest rolls over from the back layer to the front
# one round an axis at ROLL_Y, and the strands' tops hang inside that roll.
SLUMP_X = 0.85  # right of the middle, under where the leaning blade's top was: from the thrower's camera
# over the right shoulder the slump then clears the caster even against a wall a few studs ahead
BACK_Z, STRAND_Z, FRONT_Z = 0.19, 0.68, 1.17
ROLL_Y = 3.96
ROLL_R = (FRONT_Z - BACK_Z) / 2.0
ROLL_Z = (FRONT_Z + BACK_Z) / 2.0


def _back_x(y: float) -> float:
    """The back leg, x from SLUMP_X, as it climbs the wall: drifting in toward the crest, waving."""
    calm = 1.0 - smoothstep(2.9, ROLL_Y, y)
    return -1.22 + 0.42 * smoothstep(0.6, ROLL_Y, y) + 0.17 * math.sin(2.0 * math.pi * y / 3.3 + 0.4) * calm


def _front_x(y: float) -> float:
    """The front leg, x from SLUMP_X, as it hangs: S-waves down the wall, wider than the band is wide."""
    calm = 1.0 - smoothstep(3.0, ROLL_Y, y)
    return -0.28 + 0.36 * (1.0 - smoothstep(2.2, ROLL_Y, y)) + 0.22 * math.sin(2.0 * math.pi * y / 3.2 + 1.7) * calm


def _drape_spine():
    """Up the wall, over the rolled crest toward the thrower, and down again: (x, y, z) studs."""
    pts = []
    n = 60
    for k in range(n):
        y = ROLL_Y * k / n
        pts.append((SLUMP_X + _back_x(y), y, BACK_Z))
    xb, xf = _back_x(ROLL_Y), _front_x(ROLL_Y)
    m = 40
    for k in range(m + 1):
        f = k / m
        th = math.pi * (1.0 - f)
        pts.append((SLUMP_X + xb + (xf - xb) * smoothstep(0.0, 1.0, f), ROLL_Y + ROLL_R * math.sin(th), ROLL_Z + ROLL_R * math.cos(th)))
    for k in range(1, n + 1):
        y = ROLL_Y * (1.0 - k / n)
        # Deflected: the foot of the front leg bellies out from the wall as it comes down onto the pool.
        pts.append((SLUMP_X + _front_x(y), y, FRONT_Z + 0.14 * (1.0 - smoothstep(0.0, 1.6, y))))
    line = Polyline(pts)
    return [line.at(k / 120) for k in range(121)]


def _drape_face(band: Band):
    """The fold's faces: out from the roll's axis -- against the wall on the back leg, up over the crest,
    toward the thrower on the front leg."""
    def face(s: float):
        p = band.line.at(s)
        return norm((0.0, max(p[1] - ROLL_Y, 0.0), p[2] - ROLL_Z))
    return face


DRAPE = {"stations": 56, "width": [(0.0, 0.85), (0.12, 0.62), (0.36, 0.72), (0.47, 1.12), (0.6, 1.2), (0.85, 1.22), (1.0, 1.4)],
         "depth": [(0.0, 0.3), (0.5, 0.27), (1.0, 0.3)], "wedge": 0.82, "hull": (0.12, 0.105), "wobble": 0.04,
         "level": 0.035}

# The strands hanging inside the fold, (x from SLUMP_X, y) studs, top to floor: the left one narrow, the
# right one broad and bellied out where the wall deflected it. Their tops hang inside the roll.
STRANDS = (
    ([(-0.62, 4.08), (-0.66, 3.62), (-0.86, 2.92), (-0.98, 2.15), (-0.86, 1.35), (-0.92, 0.62), (-1.08, 0.0)],
     [(0.0, 0.3), (0.2, 0.42), (0.6, 0.5), (1.0, 0.66)]),
    ([(0.05, 4.05), (0.12, 3.58), (0.46, 2.95), (0.96, 2.25), (1.24, 1.45), (1.32, 0.72), (1.55, 0.0)],
     [(0.0, 0.3), (0.25, 0.56), (0.55, 0.9), (0.8, 0.84), (1.0, 0.9)]),
)


def _strand(points, widths, seed: int) -> Band:
    spec = {"stations": 22, "width": widths, "depth": [(0.0, 0.2), (1.0, 0.22)], "wedge": 0.75,
            "hull": (0.11, 0.1), "wobble": 0.05, "level": (0.0, 0.07)}
    return Band([(SLUMP_X + x, y, STRAND_Z) for x, y in points], spec, seed)


class Run(Band):
    """A band lying on the floor: its faces up and down, its spine raised by half its thickness so its
    bottom lies on the page."""

    def frame(self, s: float):
        p, r, d = super().frame(s)
        return (p[0], cosine_curve(self.spec["depth"], s) / 2.0, p[2]), r, d


RUN = {"stations": 12, "width": [(0.0, 0.62), (0.5, 0.42), (1.0, 0.18)], "depth": [(0.0, 0.13), (1.0, 0.08)],
       "wedge": 1.0, "face": UP, "ends": ("cap", "tip"), "hull_curve": [(0.0, 0.11), (1.0, 0.1)], "wobble": 0.03}


def _run_spine(side: int, start: float, end: float, phase: float):
    pts = []
    for k in range(7):
        f = k / 6
        x = SLUMP_X + side * (start + (end - start) * f)
        z = 0.62 + 0.18 * math.sin(2.6 * f + phase) + 0.25 * f
        pts.append((x, 0.0, z))
    return pts


# The trail of drops beyond each run: (x from SLUMP_X, z, radius across, radius along z).
DROPS = ((-4.42, 0.95, 0.27, 0.22), (-5.4, 0.72, 0.21, 0.18), (-6.62, 0.86, 0.16, 0.14),
         (3.72, 1.02, 0.24, 0.2), (4.47, 0.8, 0.19, 0.16), (5.0, 1.05, 0.14, 0.12))


def _slump_parts():
    drape = Band(_drape_spine(), DRAPE, SEED + 50)
    drape.spec = dict(DRAPE, face=_drape_face(drape))
    strands = [_strand(points, widths, SEED + 51 + k) for k, (points, widths) in enumerate(STRANDS)]
    runs = [Run(_run_spine(-1, 1.35, 3.45, 0.6), RUN, SEED + 55), Run(_run_spine(1, 1.75, 3.1, 1.9), RUN, SEED + 56)]
    return drape, strands, runs


def _slump_solids(drape: Band, strands, runs) -> list:
    solids = [drape.volume()] + [s.volume() for s in strands] + [r.volume() for r in runs]
    # The pool at the foot of the wall, round, its back flattened against the wall.
    solids.append(pool((SLUMP_X + 0.12, 0.0, 0.62), 1.78, 1.0, 0.19, 22, SEED + 40, wall=0.04))
    for k, (x, z, rx, rz) in enumerate(DROPS):
        solids.append(pool((SLUMP_X + x, 0.0, z), rx, rz, 0.11, 8, SEED + 60 + k, lobes=0.05, profile=DROP_PROFILE))
    return solids


def slump() -> tuple[Mesh, Mesh, Mesh, float]:
    if "slump" in _CACHE:
        return _CACHE["slump"]
    drape, strands, runs = _slump_parts()
    edge, ink = Mesh("up"), Mesh("up")
    # The pale thread: down the front leg just inside its left edge, from over the crest -- the blade's
    # own, slumped.
    lay(edge, drape.surface(+1), lambda tau: (0.47 + 0.45 * tau, -0.6 + 0.05 * math.sin(math.pi * tau)), lens(0.1, 0.5), 0.035, 34)
    # Flow lines down the front leg and the broad strand, unequal and never parallel.
    for band, s0, s1, a0, a1, w in ((drape, 0.62, 0.9, 0.35, 0.05, 0.12), (drape, 0.78, 0.97, -0.15, 0.3, 0.1),
                                    (strands[1], 0.35, 0.8, -0.3, 0.1, 0.1)):
        lay(ink, band.surface(+1), lambda tau, s0=s0, s1=s1, a0=a0, a1=a1: (s0 + (s1 - s0) * tau, a0 + (a1 - a0) * tau), brush(w), 0.03, 9)
    # Two splats thrown off the foot along the page: the deflected ink.
    for x0, z0, dx, dz, w in ((2.0, 1.75, 0.8, 0.55, 0.22), (-1.95, 1.7, -0.45, 0.7, 0.18)):
        x0 += SLUMP_X
        floor_streak(ink, [(x0, z0), (x0 + 0.5 * dx, z0 + 0.5 * dz), (x0 + dx, z0 + dz)], brush(w, 0.1), 0.07, 6)
    solids = _slump_solids(drape, strands, runs)
    _CACHE["slump"] = _assemble(solids, edge, ink)
    return _CACHE["slump"]


# --- recipes ----------------------------------------------------------------------------------------


def _meta(seed: int) -> dict:
    return {"Reference": "Width", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def swash_body() -> tuple[Mesh, dict]:
    return blade()[0], _meta(SEED)


def swash_edge() -> tuple[Mesh, dict]:
    return blade()[1], _meta(SEED + 1)


def swash_ink() -> tuple[Mesh, dict]:
    return blade()[2], _meta(SEED + 2)


def swash_slump_body() -> tuple[Mesh, dict]:
    return slump()[0], _meta(SEED + 3)


def swash_slump_edge() -> tuple[Mesh, dict]:
    return slump()[1], _meta(SEED + 4)


def swash_slump_ink() -> tuple[Mesh, dict]:
    return slump()[2], _meta(SEED + 5)
