"""The Rubric's bodies: the bud it charges in both hands, the red rule it lets go.

Drawn after the developer's references (docs/vfx/rubric/ref-1.jpg, the line in game; ref-2.jpg, the
model sheet "Cinnabar ink rubric bud & bar"), reconciled with the art bible (DA_ENCRE_3D.md, the Rubric,
K3, K4) and the server (GlyphEffects.Rubric: HitRadius 4, Range 85, SpawnOffset 3, Windup 0.7).

Roblox space: X right, Y up, forward -Z. Three meshes per body, one tone each, cut from one build.

THE BUD (charge: RubricBud / RubricHeart / RubricBudInk; Diameter 2.6, axis Z, pivot at its centre).
A tulip pointed at the target. Its pigment is one closed calyx -- an egg of revolution from the back pole
(the caster's chest) to a neck, scalloped into six lobes (the petals folded in toward the neck), its lip
turned in round a flat receptacle -- so no vellum can show through it with the ink off. Six hooked tips
(K4 tongues) grow out of the neck, long and short alternating (two whorls of three): each rises out of
the neck, flares to the bud's full width and curls back over its own lobe, a comma that trails the +4
spin and stands proud of the silhouette from the side, from three quarters and from behind, with air
under its curl. On the receptacle, inside the neck, the pale heart, pressed flat. The ink: one inverted
hull of the calyx (0.16 stud on the belly, light on the lip), six tapered seams (one brush stroke each,
laid on the calyx's own crease between two lobes: thin at the pole, full on the belly, dry at the neck,
where the notch between two tips takes the line on), the tips' own hulls (0.15 on the face away from the
curl, 0.08 on the face over the heart), and the heart's thin ring (0.1, a flat band on the receptacle,
none at the cleft). The core: the heart, and a warm streak on the back of each lobe (the K4 streak), so
the thrower's views carry pale too.

THE BAR (release). Two pieces, because R1 stretches Z alone and a head stretched with the reach is a
sliver at short reach:
  - the rule (RubricBar / RubricLobes / RubricBarInk; Length 1 along -Z, X/Y in widths, pivot at the
    muzzle): a constant round-belly section, three pale lobes on the crown, and at the muzzle the K3 end:
    a dry tail in three strands (the last 6 %), the outer two flicking up and out -- its gaps and its lift
    lie across the aim, which R1 never scales. Its far end closes to a point exactly on the reach, always
    inside the head's pressed face;
  - the head (RubricHead / RubricHeadInk; X/Y/Z in the same widths, never stretched, pivot on the snout):
    a pressed, bevelled bull's face whose flat plate covers the rule's section and its contour, two lyre
    horns sweeping out, up and in. The timeline lays it at the reach end (Offset {0, 0, 1}, OffsetFrom =
    "Reach", Size as the rule's width), so it keeps its proportions from 3 to 85 studs.
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
    mul,
    norm,
    sliver,
    smoothstep,
    sub,
)

BUD_SEED = 5231
BAR_SEED = 5237


# --- shared pieces -------------------------------------------------------------------------------


def centroid(points):
    return tuple(sum(p[i] for p in points) / len(points) for i in range(3))


def ring_volume(rings, weights, back_tip=None, front_tip=None, back_weight=None, front_weight=None) -> Volume:
    """A closed volume through rings of equal count (each a closed polygon, consistently ordered). An
    end with a tip collapses to that point; an end without one is capped by a fan to its centroid."""
    vol = Volume()
    ids = [[vol.vert(p, w) for p, w in zip(ring, ws)] for ring, ws in zip(rings, weights)]
    n = len(rings[0])
    for r in range(len(ids) - 1):
        a, b = ids[r], ids[r + 1]
        for j in range(n):
            k = (j + 1) % n
            emit(vol.mesh, a[j], a[k], b[k])
            emit(vol.mesh, a[j], b[k], b[j])
    first, last = ids[0], ids[-1]
    w0 = back_weight if back_weight is not None else weights[0][0]
    c0 = vol.vert(back_tip if back_tip is not None else centroid(rings[0]), w0)
    for j in range(n):
        emit(vol.mesh, c0, first[(j + 1) % n], first[j])
    w1 = front_weight if front_weight is not None else weights[-1][0]
    c1 = vol.vert(front_tip if front_tip is not None else centroid(rings[-1]), w1)
    for j in range(n):
        emit(vol.mesh, c1, last[j], last[(j + 1) % n])
    vol.orient_outward()
    return vol


def vertex_normals(mesh: Mesh):
    acc = [(0.0, 0.0, 0.0)] * len(mesh.verts)
    for a, b, c in mesh.tris:
        n = cross(sub(mesh.verts[b], mesh.verts[a]), sub(mesh.verts[c], mesh.verts[a]))
        for v in (a, b, c):
            acc[v] = add(acc[v], n)
    return [norm(n) for n in acc]


def hull(vol: Volume, into: Mesh, floor: float = 0.004, skip=(), normal_skip=None) -> None:
    """The inverted hull: each vertex pushed out along its normal by its weight, wound inside out. A face
    whose three weights are all under `floor`, or that touches a vertex in `skip`, is left out: it lies
    on or inside the body and draws nothing (the cup's floor, the heart's back, a buried root); so is a
    face the push turns into a sliver (strokes.inverted_hull's rule)."""
    mesh = vol.mesh
    skip = set(skip)
    # Normals from the faces that keep their contour: a skipped face (the heart's back on the floor) must
    # not tilt the push into what lies behind it, or the ring hides there.
    kept = Mesh("up")
    kept.verts = mesh.verts
    nskip = skip if normal_skip is None else set(normal_skip)
    kept.tris = [t for t in mesh.tris if not (set(t) & nskip)]
    normals = vertex_normals(kept)
    base = len(into.verts)
    for i, p in enumerate(mesh.verts):
        into.verts.append(add(p, mul(normals[i], vol.weight[i])))
    for a, b, c in mesh.tris:
        if max(vol.weight[a], vol.weight[b], vol.weight[c]) < floor or a in skip or b in skip or c in skip:
            continue
        if sliver(into.verts[a + base], into.verts[b + base], into.verts[c + base]):
            continue  # pressed into a sliver where the hull closes on a point: it covers nothing its neighbours do not
        emit(into, a + base, c + base, b + base)


def tube(control, radius: float, tip: float, sides: int, segs: int, weight: float, tip_weight: float) -> Volume:
    """A tapered tube along a Catmull-Rom path, closed: a root cap and a single-vertex tip; its section
    is carried by parallel transport."""
    line = Polyline(catmull(control, 16))
    centres = [line.at(i / segs) for i in range(segs + 1)]
    tangents = [norm(sub(centres[min(i + 1, segs)], centres[max(i - 1, 0)])) for i in range(segs + 1)]
    side = cross(tangents[0], (0.0, 0.0, 1.0))
    if dot(side, side) < 1e-6:
        side = cross(tangents[0], (1.0, 0.0, 0.0))
    side = norm(side)
    rings, weights = [], []
    for i in range(segs):
        along = tangents[i]
        side = norm(sub(side, mul(along, dot(side, along))))
        up = norm(cross(side, along))
        f = i / segs
        r = radius + (tip - radius) * f**0.9
        rings.append([add(centres[i], add(mul(side, r * math.cos(2 * math.pi * k / sides)), mul(up, r * math.sin(2 * math.pi * k / sides)))) for k in range(sides)])
        weights.append([weight + (tip_weight - weight) * f] * sides)
    return ring_volume(rings, weights, front_tip=centres[-1], front_weight=tip_weight)


def strip(mesh: Mesh, lefts, rights, normals) -> None:
    """A strip between two polylines, facing along the given per-row normals; a row whose two sides meet
    is one vertex, so a pointed end draws no sliver."""
    li, ri = [], []
    for p, q in zip(lefts, rights):
        if math.dist(p, q) < 1e-6:
            v = mesh.vert(p)
            li.append(v)
            ri.append(v)
        else:
            li.append(mesh.vert(p))
            ri.append(mesh.vert(q))
    for i in range(len(li) - 1):
        n = add(normals[i], normals[i + 1])
        if li[i] != ri[i]:
            mesh.tri(li[i], ri[i], li[i + 1] if li[i + 1] != ri[i + 1] else ri[i + 1], n)
        if li[i + 1] != ri[i + 1]:
            mesh.tri(ri[i], ri[i + 1], li[i + 1], n)


# --- the bud (built in studs, Diameter 2.6, then scaled to 1) -------------------------------------

LOBES = 6
PER = 3  # calyx vertices per lobe round the axis: the seam and two on the lobe's back
AROUND = LOBES * PER
# The calyx's meridian, a tulip from the back pole to the neck, then the lip and the receptacle inside
# it: (r, z, scallop depth, hull weight). Back pole at +Z (the caster's chest); the neck opens toward -Z
# (the target). Each scallop between two seams is a petal folded in toward the neck.
CALYX = [
    (0.32, 0.80, 0.012, 0.135),
    (0.62, 0.64, 0.030, 0.14),
    (0.85, 0.38, 0.042, 0.145),
    (0.96, 0.08, 0.050, 0.145),
    (0.94, -0.20, 0.055, 0.145),
    (0.82, -0.46, 0.060, 0.14),
    (0.66, -0.66, 0.060, 0.135),
    (0.58, -0.79, 0.050, 0.12),  # the neck, outside: the tips leave the calyx here
    (0.525, -0.865, 0.030, 0.09),  # the lip's crest
    (0.505, -0.775, 0.000, 0.03),  # the inner wall down to the receptacle's edge: a flat floor behind the heart and its ring
]
NECK = 7  # the ring the tips leave from, where the seams end
POLE_Z = 0.86
POLE_WEIGHT = 0.135
FLOOR_Z = -0.765
CALYX_TWIST = math.radians(-18)  # the lobes wind from the pole to the neck, with the +4 spin's wind
LOBE_SWELL = 0.018  # how much one lobe varies from another (seeded): no perfect symmetry

# The hooked tips (K4 tongues): spines in the tip's meridian plane (r, z) from a foot buried in the neck
# to the point. Each rises out of the neck, flares out to the bud's full width and curls back over its
# own lobe -- a comma that shapes the silhouette from the side, from three quarters and from behind,
# with air under its curl. Long and short alternate (two whorls of three); all trail the +4 spin.
TIP_LONG = [(0.555, -0.72), (0.60, -0.88), (0.66, -1.03), (0.68, -1.16), (0.62, -1.26), (0.53, -1.285), (0.46, -1.21), (0.44, -1.1)]
TIP_SHORT = [(0.545, -0.72), (0.58, -0.86), (0.63, -0.99), (0.64, -1.09), (0.59, -1.17), (0.52, -1.19), (0.47, -1.13), (0.46, -1.04)]
TIP_ROWS = [0.0, 0.1, 0.28, 0.46, 0.64, 0.8, 0.92, 1.0]
TIP_WIDTH = {  # studs across the bud's circumference
    True: [(0.0, 0.52), (0.12, 0.54), (0.4, 0.60), (0.62, 0.50), (0.8, 0.34), (0.92, 0.2), (1.0, 0.0)],
    False: [(0.0, 0.50), (0.12, 0.52), (0.4, 0.56), (0.62, 0.46), (0.8, 0.30), (0.92, 0.18), (1.0, 0.0)],
}
TIP_THICK = [(0.0, 0.08), (0.6, 0.06), (1.0, 0.035)]
TIP_SWEEP = {True: math.radians(24), False: math.radians(20)}
TIP_HULL_OUT = [(0.0, 0.0), (0.08, 0.07), (0.22, 0.135), (0.7, 0.13), (1.0, 0.11)]
TIP_HULL_IN = [(0.0, 0.0), (0.08, 0.04), (0.22, 0.09), (1.0, 0.09)]
TIP_STREAK = (0.28, 0.82)  # the stretch of the tip whose back carries the warm streak (on the flare)
TIP_STREAK_LIFT = 0.012

# The seams: one tapered stroke in each valley of the calyx, from near the pole to the neck, where the
# notch between two tips takes it on.
SEAM_WIDTH = [(0.0, 0.012), (0.2, 0.06), (0.45, 0.095), (0.75, 0.07), (1.0, 0.03)]
SEAM_LIFT = 0.02

# The warm streak on the back of each lobe (Core): half width (studs).
STREAK_HALF = 0.085
STREAK_LIFT = 0.016
STREAK_SPAN = (0.85, 2.1)  # ring indices: the back of the lobe, from near the pole to the belly
STREAK_OFF = 15.0  # degrees off the lobe's crown, so no side or top view looks along it

HEART_HALF = 0.40  # the heart's half width
HEART_Z = -0.79  # its back, just in front of the receptacle
HEART_DEPTH = 0.065  # pressed: a flat face on a bevel
HEART_INK = 0.097  # the heart's own thin ring: the bible's 0.1 stud at Diameter 2.6


def profile(ctrl, s):
    return cosine_curve(ctrl, s)


def lobe_variation():
    rng = Rng(BUD_SEED + 7)
    return [1.0 + LOBE_SWELL * (rng.random() * 2 - 1) for _ in range(LOBES)]


def ring_at(t: float):
    """The calyx's meridian at a continuous ring index t: r, z, scallop depth, twist."""
    t = min(max(t, 0.0), len(CALYX) - 1.0)
    i = min(int(t), len(CALYX) - 2)
    f = t - i
    a, b = CALYX[i], CALYX[i + 1]
    return a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, CALYX_TWIST * min(t, NECK) / NECK


def scallop(phi: float, depth: float, swell) -> float:
    """The radius factor round the calyx at azimuth phi (untwisted): 1 on a lobe's back, 1 - depth in
    the valley between two lobes (the seams are at multiples of 60 degrees)."""
    sector = 2 * math.pi / LOBES
    k = int(math.floor(phi / sector + 1e-9)) % LOBES
    u = (phi % sector) / sector
    centre = 1.0 - abs(2 * u - 1)
    return (1.0 - depth * (1.0 - centre) ** 2) * (1.0 + (swell[k] - 1.0) * math.sin(math.pi * u))


def calyx_point(t: float, phi: float, swell):
    r, z, d, tw = ring_at(t)
    f = scallop(phi, d, swell)
    a = phi + tw
    return (r * f * math.cos(a), r * f * math.sin(a), z)


def calyx_normal(t: float, phi: float, swell):
    e = 1e-3
    pt0, pt1 = calyx_point(t - e, phi, swell), calyx_point(t + e, phi, swell)
    pp0, pp1 = calyx_point(t, phi - e, swell), calyx_point(t, phi + e, swell)
    n = norm(cross(sub(pp1, pp0), sub(pt1, pt0)))
    p = calyx_point(t, phi, swell)
    if dot(n, (p[0], p[1], 0.0)) < 0:
        n = mul(n, -1.0)
    return n


def calyx(swell) -> Volume:
    rings, weights = [], []
    for i, (_r, _z, _d, w) in enumerate(CALYX):
        rings.append([calyx_point(float(i), 2 * math.pi * j / AROUND, swell) for j in range(AROUND)])
        weights.append([w] * AROUND)
    return ring_volume(rings, weights, back_tip=(0.0, 0.0, POLE_Z), front_tip=(0.0, 0.0, FLOOR_Z), back_weight=POLE_WEIGHT, front_weight=0.0)


def tip(k: int) -> Volume:
    """Tip k: a slab whose face follows the bud's circumference (three points across: a low ridge, a
    tent like the Brand's arms), its edges rolled back a little, thinning to a comma's point; its foot
    buried in the neck's wall."""
    long = k % 2 == 0
    line = Polyline(catmull(TIP_LONG if long else TIP_SHORT, 16))
    centre_phi = 2 * math.pi * (k + 0.5) / LOBES + CALYX_TWIST
    rows, weights, backs = [], [], []
    point = None
    for s in TIP_ROWS:
        r, z = line.at(s)
        a = line.at(max(0.0, s - 0.01))
        b = line.at(min(1.0, s + 0.01))
        tr, tz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(tr, tz) or 1.0
        nr, nz = -tz / length, tr / length  # the tip's back: outward at its foot, back toward the caster on the flare
        psi = centre_phi - TIP_SWEEP[long] * smoothstep(0.2, 1.0, s) ** 1.2
        if s >= 1.0:
            point = (r * math.cos(psi), r * math.sin(psi), z)
            break
        half = profile(TIP_WIDTH[long], s) / 2.0 / max(r, 0.2)
        t = profile(TIP_THICK, s)
        wo, wi = profile(TIP_HULL_OUT, s), profile(TIP_HULL_IN, s)

        def at(u: float, inset: float):
            ang = psi + u * half
            er = (math.cos(ang), math.sin(ang), 0.0)
            n3 = add(mul(er, nr), (0.0, 0.0, nz))
            roll = 0.05 * u * u * math.sin(math.pi * min(1.0, s / 0.9))
            return add(add(mul(er, r), (0.0, 0.0, z)), mul(n3, roll - inset))

        rows.append([at(1.0, 0.0), at(0.5, 0.0), at(0.0, 0.0), at(-0.5, 0.0), at(-1.0, 0.0), at(-0.8, t), at(0.8, t)])
        weights.append([wo, wo, wo, wo, wo, wi, wi])
        backs.append(norm(add(mul((math.cos(psi), math.sin(psi), 0.0), nr), (0.0, 0.0, nz))))
    vol = ring_volume(rows, weights, front_tip=point, front_weight=0.1, back_weight=0.0)
    vol.rows = rows
    vol.backs = backs
    return vol


def tip_streak(core: Mesh, vol: Volume, k: int) -> None:
    """The K4 streak on the tip's back -- the face its flare turns toward the caster and up -- a lens laid
    on the face's own ridge rows, well inside its edges, lifted along the back's normal."""
    rows, backs = vol.rows, vol.backs
    span = [i for i, s in enumerate(TIP_ROWS[: len(rows)]) if TIP_STREAK[0] <= s <= TIP_STREAK[1]]
    centre = 0.12 if k % 2 == 0 else -0.08
    pts = []
    for n_i, i in enumerate(span):
        tau = n_i / (len(span) - 1)
        half = 0.42 * math.sin(math.pi * tau) ** 0.85
        ridge, left, right = rows[i][2], rows[i][0], rows[i][4]

        def on(u: float):
            edge = left if u >= 0 else right
            q = add(ridge, mul(sub(edge, ridge), abs(u)))
            return add(q, mul(backs[i], TIP_STREAK_LIFT))

        pts.append([on(centre - half), on(centre), on(centre + half)])
    ids = []
    for n_i, row in enumerate(pts):
        if n_i in (0, len(pts) - 1):
            v = core.vert(row[1])
            ids.append([v, v, v])
        else:
            ids.append([core.vert(p) for p in row])
    for n_i in range(len(pts) - 1):
        a, b = ids[n_i], ids[n_i + 1]
        n = backs[span[n_i]]
        for j in range(2):
            if a[j] != a[j + 1]:
                core.tri(a[j], a[j + 1], b[j + 1] if b[j] != b[j + 1] else b[j], n)
            if b[j] != b[j + 1]:
                core.tri(a[j], b[j + 1], b[j], n)


def heart_outline(count: int):
    pts = []
    for i in range(count):
        t = 2 * math.pi * i / count
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x, y))
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    sx = (max(xs) - min(xs)) / 2
    cy = (max(ys) + min(ys)) / 2
    return [(HEART_HALF * x / sx, HEART_HALF * (y - cy) / sx) for x, y in pts]


def cleft(i: int, n: int) -> float:
    """The ring's weight round the heart: nothing at the cleft, full three vertices on either side."""
    return min(1.0, min(i, n - i) / 3.0)


def heart() -> Volume:
    """The pale heart, pressed: its outline at the back, a bevel, a flat face. No inner ring copies the
    cleft, so nothing runs down into the heart from it."""
    outline = heart_outline(18)
    n = len(outline)
    centre = (0.0, 0.02)
    back = [(x, y, HEART_Z) for x, y in outline]
    face = [(centre[0] + (x - centre[0]) * 0.88, centre[1] + (y - centre[1]) * 0.88, HEART_Z - HEART_DEPTH) for x, y in outline]
    # Thin at the cleft and round it: pushed out there, the two lobes' contours would cross in the notch.
    ring_w = [HEART_INK * cleft(i, n) for i in range(n)]
    face_w = [w * 0.5 for w in ring_w]
    return ring_volume([back, face], [ring_w, face_w], back_tip=(centre[0], centre[1], HEART_Z + 0.005), front_tip=(centre[0], centre[1], HEART_Z - HEART_DEPTH), back_weight=0.0, front_weight=HEART_INK * 0.5)


def heart_ring(ink: Mesh) -> None:
    """The heart's own thin ink: a flat band on the receptacle round the heart's outline, under its edge.
    A hull cannot draw it -- seen from the front, a hull shows only its far side, and the heart's far side
    lies on the floor. Thin to nothing at the cleft, so no spike runs into the notch."""
    outline = heart_outline(18)
    n = len(outline)
    z = HEART_Z + 0.012  # between the heart's back and the floor
    outer = []
    for i, (x, y) in enumerate(outline):
        px, py = outline[i - 1]
        nx_, ny_ = outline[(i + 1) % n]
        tx, ty = nx_ - px, ny_ - py
        length = math.hypot(tx, ty) or 1.0
        ox, oy = ty / length, -tx / length  # outward for the outline's clockwise turn
        if ox * x + oy * (y - 0.02) < 0:
            ox, oy = -ox, -oy
        w = HEART_INK * cleft(i, n)
        outer.append((x + ox * w, y + oy * w, z))
    inner = [(x, y, z) for x, y in outline]
    ids_in = [ink.vert(p) for p in inner]
    ids_out = [ink.vert(p) for p in outer]
    for i in range(n):
        j = (i + 1) % n
        ink.tri(ids_in[i], ids_out[i], ids_out[j], (0.0, 0.0, -1.0))
        ink.tri(ids_in[i], ids_out[j], ids_in[j], (0.0, 0.0, -1.0))


def seams(ink: Mesh, cup: Volume) -> None:
    """Six brush strokes in the valleys between the lobes, one tapered line per joint, laid on the
    calyx's own crease edge and sampled at every ring and half ring, so no straight span dips under a
    ring's ridge (the dashes of the first round)."""
    verts = cup.mesh.verts
    normals = vertex_normals(cup.mesh)
    rng = Rng(BUD_SEED + 11)
    for k in range(LOBES):
        j = PER * k
        start = 0.3 + 0.3 * rng.random()
        grow = 1.0 + 0.12 * (rng.random() * 2 - 1)
        ts = [start] + [float(x) for x in range(1, NECK + 1) if x > start + 0.2]
        lefts, rights, ns = [], [], []
        for i, t in enumerate(ts):
            lo = min(int(t), NECK - 1)
            f = t - lo
            pa, pb = verts[lo * AROUND + j], verts[(lo + 1) * AROUND + j]
            na, nb = normals[lo * AROUND + j], normals[(lo + 1) * AROUND + j]
            p = add(pa, mul(sub(pb, pa), f))
            n = norm(add(mul(na, 1 - f), mul(nb, f)))
            along = norm(sub(pb, pa))
            across = norm(cross(n, along))
            tau = (t - start) / (NECK - start)
            w = profile(SEAM_WIDTH, tau) * grow / 2.0
            base = add(p, mul(n, SEAM_LIFT + 0.15 * w))
            lefts.append(add(base, mul(across, w)))
            rights.append(add(base, mul(across, -w)))
            ns.append(n)
        strip(ink, lefts, rights, ns)


def streaks(core: Mesh, swell) -> None:
    lens_streaks(core, swell, STREAK_SPAN, STREAK_HALF, STREAK_OFF, BUD_SEED + 13)


def lens_streaks(core: Mesh, swell, span, width, off, seed) -> None:
    """A warm lens on the back of each lobe, pointed at both ends (K4's streak). Never on the outer edge:
    it stays on the back dome, behind the belly (the limb seen from behind and from the front), and 15
    degrees off its lobe's crown, so no side or top view looks along it; its rows fall on the calyx's
    rings and half rings, as the seams' do, so no span dips under a ring."""
    rng = Rng(seed)
    for k in range(LOBES):
        crown = 2 * math.pi * (k + 0.5) / LOBES + math.radians(off) + math.radians(4) * (rng.random() * 2 - 1)
        t0 = span[0] + 0.3 * rng.random()
        t1 = span[1] - 0.2 * rng.random()
        ts = [t0] + [h / 2 for h in range(1, 2 * NECK) if t0 + 0.15 < h / 2 < t1 - 0.15] + [t1]
        rows = []
        for i, t in enumerate(ts):
            tau = (t - t0) / (t1 - t0)
            r = ring_at(t)[0]
            half = width * math.sin(math.pi * tau) ** 0.8 * (1.0 + 0.3 * (1 - tau))
            ang = half / max(r, 0.1)
            pts = []
            for u in (-1.0, 0.0, 1.0):
                phi = crown + u * ang + math.radians(4) * tau
                p = calyx_point(t, phi, swell)
                n = calyx_normal(t, phi, swell)
                pts.append((add(p, mul(n, STREAK_LIFT)), n))
            rows.append(pts)
        ids = []
        for i, row in enumerate(rows):
            if i in (0, len(rows) - 1):
                v = core.vert(row[1][0])
                ids.append([v, v, v])
            else:
                ids.append([core.vert(p) for p, _ in row])
        for i in range(len(rows) - 1):
            a, b = ids[i], ids[i + 1]
            n = rows[i][1][1]
            for j in range(2):
                if a[j] != a[j + 1]:
                    core.tri(a[j], a[j + 1], b[j + 1] if b[j] != b[j + 1] else b[j], n)
                if b[j] != b[j + 1]:
                    core.tri(a[j], b[j + 1], b[j], n)


_BUD: dict = {}


def build_bud():
    if "m" in _BUD:
        return _BUD["m"]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    swell = lobe_variation()
    cup = calyx(swell)
    body.merge(cup.mesh)
    # Not the inner wall nor the receptacle (under the heart, seen only through the neck): no contour there.
    inner = range((len(CALYX) - 1) * AROUND, len(CALYX) * AROUND)
    hull(cup, ink, skip=(*inner, len(cup.weight) - 1))
    for k in range(LOBES):
        vol = tip(k)
        body.merge(vol.mesh)
        hull(vol, ink, skip=(*range(7), len(vol.weight) - 2))  # not the foot, buried in the neck
        tip_streak(core, vol, k)
    pale = heart()
    core.merge(pale.mesh)
    heart_ring(ink)
    seams(ink, cup)
    streaks(core, swell)
    reach = max(math.hypot(x, y) for m in (body, core, ink) for x, y, _ in m.verts)
    zs = [z for m in (body, core, ink) for _, _, z in m.verts]
    mid = (max(zs) + min(zs)) / 2
    for m in (body, core, ink):
        m.translate((0.0, 0.0, -mid))
        m.scale(0.5 / reach)
    _BUD["m"] = (body, core, ink)
    _BUD["studs"] = 2 * reach
    _BUD["length"] = (max(zs) - min(zs))
    return _BUD["m"]


def bud_meta() -> dict:
    return {"Reference": "Diameter", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": BUD_SEED}


def rubric_bud():
    return build_bud()[0], bud_meta()


def rubric_heart():
    return build_bud()[1], bud_meta()


def rubric_bud_ink():
    return build_bud()[2], bud_meta()


# --- the bar: the rule (stretched by R1) ---------------------------------------------------------

L0 = 40.0  # nominal reach the rule is built at, in studs
SIDES = 16
RULE_SEGS = 9  # a ring every ~4.3 studs: the contour's side faces stay fat enough to survive the sliver test
SHAFT = (2.62, 0.66, 0.72, 2.6, 2.0)  # half width, top, belly, crown exponent, belly exponent
BAR_HULL = (0.2, 0.15)  # contour under and beside the rule, and over its crown
END_CONE = 0.015  # share of the length over which the far end closes to a point, inside the head
# The K3 end at the muzzle: a dry tail in three strands over the first TAIL of the length; the outer two
# flick up as the brush leaves the page. (x from, x to, how far it runs (share of TAIL), lift, splay), studs.
TAIL = 0.06
TAIL_ROOT = 0.03  # where the rule's full section stops and the strands take over (share of the length)
STRANDS = [(-2.56, -1.08, 0.96, 1.35, -0.55), (-0.80, 0.80, 0.78, 0.0, 0.0), (1.08, 2.56, 0.9, 1.2, 0.5)]  # short of the side, where the section's top and bottom meet
LOBES_AT = [  # (centre, length) as shares of the length; (half width across the crown, offset), studs.
    # Sized so the pale stays under the Cinnabar 12 % at the longest reach, where the lobes stretch and the
    # head does not.
    (-0.2, 0.10, 0.66, 0.2),
    (-0.42, 0.12, 0.76, -0.15),
    (-0.64, 0.085, 0.62, 0.3),
]
LOBE_LIFT = 0.05


def angles():
    return [2 * math.pi * j / SIDES for j in range(SIDES)]


def shaft_section():
    a, top, belly, pt, pb = SHAFT
    pts = []
    for th in angles():
        c, s = math.cos(th), math.sin(th)
        p = pt if s >= 0 else pb
        b = top if s >= 0 else belly
        x = a * math.copysign(abs(c) ** (2 / p), c)
        y = b * math.copysign(abs(s) ** (2 / p), s)
        pts.append((x, y))
    return pts


def shaft_y(x: float, top: bool) -> float:
    a, t, b, pt, pb = SHAFT
    u = min(abs(x) / a, 1.0)
    if top:
        return t * (1 - u**pt) ** (1 / pt)
    return -b * (1 - u**pb) ** (1 / pb)


def bar_weights(n: int, scale: float = 1.0):
    under, crown = BAR_HULL
    return [scale * (under - (under - crown) * max(0.0, math.sin(th))) for th in angles()][:n]


def strand_section(x0: float, x1: float, count: int = 4):
    """The part of the rule's section between x0 and x1, a closed polygon wound like the section
    (counter-clockwise seen from behind): the top from x1 to x0, then the bottom from x0 to x1."""
    top = [(x1 + (x0 - x1) * i / (count - 1), 0.0) for i in range(count)]
    top = [(x, shaft_y(x, True) * 0.94) for x, _ in top]
    bottom = [(x0 + (x1 - x0) * i / (count - 1), 0.0) for i in range(count)]
    bottom = [(x, shaft_y(x, False) * 0.94) for x, _ in bottom]
    # Rounded corners at the strand's cut sides: pull the end points a little in.
    return top + bottom


def rule_studs(tail_at: str = "hand"):
    """The rule in studs at the nominal reach: body, core, ink. The dry tail at the muzzle ("hand",
    the head at the far end) or at the far end ("far", the head at the muzzle)."""
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    shaft = shaft_section()
    if tail_at == "hand":
        z_start, z_full_end = -TAIL_ROOT * L0, -(1.0 - END_CONE) * L0
        apex = (0.0, 0.0, -L0)
        stations = [z_start + (z_full_end - z_start) * i / RULE_SEGS for i in range(RULE_SEGS + 1)]
        rings = [[(x, y, z) for x, y in shaft] for z in stations]
        weights = [bar_weights(SIDES) for _ in stations]
        vol = ring_volume(rings, weights, front_tip=apex, front_weight=0.0)
    else:
        z_start, z_full_end = 0.0, -(1.0 - TAIL_ROOT) * L0
        rings = [[(x, y, z_start + (z_full_end - z_start) * i / RULE_SEGS) for x, y in shaft] for i in range(RULE_SEGS + 1)]
        vol = ring_volume(rings, [bar_weights(SIDES) for _ in rings])
    body.merge(vol.mesh)
    hull(vol, ink)
    strands(body, ink, tail_at)
    lobes(core, shaft)
    return body, core, ink


def strands(body: Mesh, ink: Mesh, tail_at: str) -> None:
    """The dry tail (K3): three strands cut from the rule's section, each thinning to its own point at a
    seeded share of the tail; the outer two lift and splay as the brush leaves the page."""
    sign = 1.0 if tail_at == "hand" else -1.0
    end = 0.0 if tail_at == "hand" else -L0
    root = end - sign * (TAIL_ROOT + 0.02) * L0  # buried in the rule's full section
    taus = [0.0, 0.42, 0.62, 0.78, 0.9]
    for x0, x1, run, lift, splay in STRANDS:
        section = strand_section(x0, x1)
        cx = sum(p[0] for p in section) / len(section)
        cy = sum(p[1] for p in section) / len(section)
        z_tip = end - sign * (1.0 - run) * TAIL * L0
        rings, weights = [], []
        for tau in taus:
            z = root + (z_tip - root) * tau
            # full until it leaves the rule, then thinning toward its point (the pressure released), round
            g = max(0.0, (tau - 0.42) / 0.58)
            f = 1.0 - 0.78 * g**1.4
            dy = lift * g**2.2
            dx = splay * (g**2 + 0.25 * g**5)  # the flick turns out at its end: a hook, not a spike
            rings.append([(cx + (x - cx) * f + dx, cy + (y - cy) * (0.3 + 0.7 * f) + dy, z) for x, y in section])
            w = 0.15 + 0.03 * f
            weights.append([w if y > cy else w + 0.03 for _, y in section])
        tipv = (cx + splay * 1.6, cy + lift * 1.15, z_tip)
        vol = ring_volume(rings, weights, front_tip=tipv, front_weight=0.1, back_weight=0.0)
        body.merge(vol.mesh)
        hull(vol, ink)


def perimeter(section):
    pts = section + [section[0]]
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + math.dist(pts[i - 1], pts[i]))
    return pts, acc


def at_perimeter(pts, acc, s):
    total = acc[-1]
    s = s % total
    for i in range(1, len(acc)):
        if acc[i] >= s:
            f = (s - acc[i - 1]) / max(acc[i] - acc[i - 1], 1e-12)
            p, q = pts[i - 1], pts[i]
            e = (q[0] - p[0], q[1] - p[1])
            length = math.hypot(*e) or 1.0
            n = (e[1] / length, -e[0] / length)  # outward for a counter-clockwise section
            return (p[0] + e[0] * f, p[1] + e[1] * f), n
    return pts[0], (0.0, 1.0)


def lobes(core: Mesh, section) -> None:
    """Three pale lenses on the crown, pointed at both ends: each end row is one vertex (no sliver)."""
    pts, acc = perimeter(section)
    top = acc[SIDES // 4]  # the crown: theta = 90 degrees
    rows, cols = 7, 4
    for zc, length, half, offset in LOBES_AT:
        grid = []
        for i in range(rows):
            t = i / (rows - 1)
            z = (zc + length / 2 - length * t) * L0
            hw = half * math.sin(math.pi * t) ** 0.75
            if i in (0, rows - 1):
                (x, y), n = at_perimeter(pts, acc, top + offset)
                p = ((x + n[0] * LOBE_LIFT, y + n[1] * LOBE_LIFT, z), (n[0], n[1], 0.0))
                grid.append([p] * cols)
                continue
            row = []
            for j in range(cols):
                u = -1 + 2 * j / (cols - 1)
                (x, y), n = at_perimeter(pts, acc, top + offset + u * hw)
                row.append(((x + n[0] * LOBE_LIFT, y + n[1] * LOBE_LIFT, z), (n[0], n[1], 0.0)))
            grid.append(row)
        ids = []
        for i, row in enumerate(grid):
            if i in (0, rows - 1):
                v = core.vert(row[0][0])
                ids.append([v] * cols)
            else:
                ids.append([core.vert(p) for p, _ in row])
        for i in range(rows - 1):
            for j in range(cols - 1):
                n = grid[i][j][1]
                a, b, c, d = ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]
                if a != b:
                    core.tri(a, b, c if c != d else d, n)
                if c != d:
                    core.tri(a, c, d, n)


# --- the bar: the head (never stretched) ---------------------------------------------------------

# Sections of the head, right half from the top centre down (x, y, studs), at their depth z behind the
# snout. Every section contains the rule's section and its contour (|x| <= 2.82 for y in -0.92..0.81),
# so wherever the rule's far end lands inside the head -- 0.09 stud behind the snout at reach 6, 1.3 at
# reach 85 -- neither its pigment nor its ink shows.
HEAD_FRONT = [(0.0, 0.98), (2.55, 0.95), (3.0, 0.5), (2.85, -0.2), (2.1, -1.1), (1.1, -1.9), (0.0, -2.2)]
HEAD_BEVEL = [(0.0, 1.5), (2.75, 1.38), (3.15, 0.78), (3.05, -0.1), (2.3, -1.25), (1.2, -2.05), (0.0, -2.4)]
HEAD_BROW = [(0.0, 1.85), (2.9, 1.66), (3.22, 1.0), (3.05, -0.1), (2.35, -1.3), (1.25, -2.2), (0.0, -2.55)]
HEAD_NAPE = [(0.0, 1.42), (2.6, 1.28), (3.02, 0.45), (2.92, -0.5), (2.05, -1.2), (0.0, -1.48)]
HEAD_STATIONS = [(0.0, HEAD_FRONT), (0.42, HEAD_BEVEL), (1.0, HEAD_BROW), (1.62, HEAD_NAPE), (2.35, None)]
SLEEVE = 1.13  # the head's back closes on the rule at this share of its section
HEAD_HULL = (0.2, 0.15)
# The horns: a tube from inside the brow's top corner, out, up and curling in (the lyre), and back.
HORN = [(2.35, 1.25, 0.9), (2.95, 1.6, 1.05), (3.15, 2.3, 1.3), (2.75, 3.1, 1.6), (2.0, 3.6, 1.95)]
HORN_RADIUS = (0.58, 0.07)
HORN_HULL = (0.15, 0.11)
# Ink creases on the pressed face (x, y pairs, studs): the brow line and the long face's V to the muzzle.
CREASES = [
    ([(-2.45, 1.15), (-1.2, 0.72), (0.0, 0.38)], 0.15),  # the brow, a chevron down from the horns' roots
    ([(2.45, 1.15), (1.2, 0.72), (0.0, 0.38)], 0.15),
    ([(-2.7, 0.1), (-2.0, -0.8), (-1.1, -1.65)], 0.12),  # the long face's cheeks
    ([(2.7, 0.1), (2.0, -0.8), (1.1, -1.65)], 0.12),
    ([(-0.8, -1.8), (0.0, -1.9), (0.8, -1.8)], 0.11),  # the muzzle
    ([(-0.5, -1.97), (-0.32, -2.07)], 0.1),  # the nostrils
    ([(0.5, -1.97), (0.32, -2.07)], 0.1),
]
CREASE_LIFT = 0.006


def star_section(half, scale: float = 1.0):
    """A section given by its right half (top centre to bottom centre), mirrored, sampled on the rule's
    16 angles by casting from its centre: the head's rings then line up with the rule's, vertex for
    vertex, round the sleeve."""
    poly = list(half) + [(-x, y) for x, y in reversed(half[1:-1])]
    pts = []
    for th in angles():
        d = (math.cos(th), math.sin(th))
        best = None
        for i in range(len(poly)):
            p, q = poly[i], poly[(i + 1) % len(poly)]
            e = (q[0] - p[0], q[1] - p[1])
            den = d[0] * e[1] - d[1] * e[0]
            if abs(den) < 1e-12:
                continue
            t = (p[0] * e[1] - p[1] * e[0]) / den
            u = (p[0] * d[1] - p[1] * d[0]) / den
            if t > 0 and -1e-9 <= u <= 1 + 1e-9 and (best is None or t < best):
                best = t
        pts.append((d[0] * best * scale, d[1] * best * scale))
    return pts


def crease(ink: Mesh, points, width: float, samples: int = 9) -> None:
    """A calligraphic line on the flat face (facing -Z), pointed at both ends, fullest past its middle."""
    line = Polyline(catmull(points, 8))
    lefts, rights, ns = [], [], []
    for i in range(samples):
        t = i / (samples - 1)
        x, y = line.at(t)
        a = line.at(max(0.0, t - 0.02))
        b = line.at(min(1.0, t + 0.02))
        along = norm((b[0] - a[0], b[1] - a[1], 0.0))
        across = (-along[1], along[0], 0.0)
        w = width * 0.5 * math.sin(math.pi * t) ** 0.7 * (1.0 + 0.25 * t)
        base = (x, y, -CREASE_LIFT)
        lefts.append(add(base, mul(across, w)))
        rights.append(sub(base, mul(across, w)))
        ns.append((0.0, 0.0, -1.0))
    strip(ink, lefts, rights, ns)


def head_studs():
    """The head in studs: snout plate on z = 0, the nape closing on the rule at z = +2.35."""
    body, ink = Mesh("up"), Mesh("up")
    shaft = shaft_section()
    rings, weights = [], []
    under, crown = HEAD_HULL
    for z, half in HEAD_STATIONS:
        sec = [(x * SLEEVE, y * SLEEVE) for x, y in shaft] if half is None else star_section(half)
        rings.append([(x, y, z) for x, y in sec])
        weights.append([under - (under - crown) * max(0.0, math.sin(th)) for th in angles()])
    weights[0] = [0.17] * SIDES  # the pressed face's rim: its contour stays within a tenth of a stud of the reach
    vol = ring_volume(rings, weights)
    body.merge(vol.mesh)
    hull(vol, ink, skip=(len(vol.weight) - 2,), normal_skip=())  # not the face itself; its normal still tilts the rim's push forward: its hull faces away from every camera
    for sign in (1.0, -1.0):
        horn = tube([(sign * x, y, z) for x, y, z in HORN], HORN_RADIUS[0], HORN_RADIUS[1], 6, 10, HORN_HULL[0], HORN_HULL[1])
        body.merge(horn.mesh)
        hull(horn, ink)
    for points, width in CREASES:
        crease(ink, points, width)
    return body, ink


# --- the bar: normalisation and the shipped meshes -----------------------------------------------

_BAR: dict = {}


def rule_width() -> float:
    """The rule's outer ink width (contour included), in studs: Size draws it at this width. Its widest
    point is the section's side, pushed out by the contour under and beside it."""
    return 2 * (SHAFT[0] + BAR_HULL[0])


def build_bar(tail_at: str = "hand"):
    if tail_at in _BAR:
        return _BAR[tail_at]
    width = rule_width()
    rule = rule_studs(tail_at)
    shipped = []
    for m in rule:
        s = Mesh("up")
        s.verts = [(x / width, y / width, z / L0) for x, y, z in m.verts]
        s.tris = list(m.tris)
        shipped.append(s)
    head = []
    for m in head_studs():
        s = Mesh("up")
        s.verts = [(x / width, y / width, z / width) for x, y, z in m.verts]
        s.tris = list(m.tris)
        head.append(s)
    _BAR[tail_at] = (shipped, head, width)
    return _BAR[tail_at]


def bar_meta() -> dict:
    return {"Reference": "Length", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": BAR_SEED}


def head_meta() -> dict:
    # X, Y and Z in the rule's widths: the timeline sets Size to the rule's Size, never stretched.
    return {"Reference": "Width", "Pivot": [0, 0, 0], "Axis": "Z", "Flat": False, "Seed": BAR_SEED}


def rubric_bar():
    return build_bar()[0][0], bar_meta()


def rubric_lobes():
    return build_bar()[0][1], bar_meta()


def rubric_bar_ink():
    return build_bar()[0][2], bar_meta()


def rubric_head():
    return build_bar()[1][0], head_meta()


def rubric_head_ink():
    return build_bar()[1][1], head_meta()
