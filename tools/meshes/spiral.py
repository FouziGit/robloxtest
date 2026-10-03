"""The Spiral's body (Verdigris zone, "le Cul-de-lampe"): a whirlpool bowl of ink, 22 studs across.

Drawn after the developer's two references (docs/vfx/spiral/ref-1.jpg, the whirlpool in game beside a
thrower; ref-2.jpg, the model sheet of the "verdigris ink spiral bowl"), the model sheet winning on
shape, the in-game shot on scale, and the art bible (DA_ENCRE_3D, the Spiral; sections 4, 5.3 and 7) on
size, sense of turn and budget.

Server truth (GlyphConfig Spiral, GlyphEffects.Spiral): a zone centred 14 studs ahead, Radius 11,
four ticks 0.6 s apart, each dragging what it harms toward the centre, but never inside
PullMinDistance = 3. So the bowl's outer ink is the harm's edge (OuterDiameter, normalised to 1), the
eye is the calm the pull stops at (an ink disc whose rim, with the dry strands that pour into it, lies
at radius ~2-3), and every arm is a log spiral r = r0 e^(b theta) with b > 0 at every radius, theta from
+X toward -Z: under the timeline's Spin of +2.6 rad/s (counter-clockwise from above) every part of every
arm flows INTO the eye -- a pull, never a push. The model sheet draws its arms the mirror way; the
game's turn wins, so the body is the sheet's mirror.

Roblox space, in studs while built (X right, Y up, forward -Z; the pivot on the floor at the centre),
then scaled once so the outermost ink (the lip's contour) lies exactly 0.5 from the axis.

  - The bowl: a shallow lens of revolution, its floor rising ever steeper from the eye to a rolled lip
    1.37 studs high and only ~0.9 stud wide (its inner undercut draws an ink ring just outside the arms'
    run, as the sheet's thin rim), its outer wall bellying down to a foot on the page.
  - Seven arms (K8): round cords lying on the bowl, from the eye to the lip's foot. Their b is low at
    the eye (0.42: the dry end swirls round it), climbs fast to 1.4 mid-bowl (the arm stands up and runs
    out) and falls to 0.2 at the rim (it lays itself along the lip): the arm's curvature changes sign in
    mid-bowl and again before the rim -- the S of the sheet's arms -- while theta(r) only ever grows.
    Thin and low at the eye, loaded at the rim; a leaning four-corner section (keel, trailing side,
    crest, overhanging leading lip). Each splits at the eye into two dry strands.
    Five end in a hook: the neck runs on to the lip's foot, the stem stands up there, and the cord rolls
    FORWARD over the rim like a breaking crest -- a logarithmic J (rho = R0 e^(-k beta)), ~2.4 studs long
    and wider than tall, open below, its tip curled back in under the crest and drifted in over the
    bowl, free inside the loop and nowhere near its own stem or neck. Its plane runs along the rim
    (turned ~12 deg out from the true tangent) and stands nearly upright (leaned ~10 deg out), so the
    game camera reads it face on at the far rim and still as a curl at the near rim: Spin turns the bowl
    ~360 deg over its life, so every hook passes both. The two other arms end in a low flat comma that
    curls in on the bowl at the lip, under 0.6 stud high -- a crochet still, not a sixth hook.
  - Core: a pale lens straddling each arm's crest, from mid-bowl to the neck -- the sheet's pale cords,
    kept narrow (Verdigris heated drifts toward the ally cyan): <= 6 % of the visible body.
  - Ink: the contour of the lip (inner ring and outer edge), the outer wall and its foot ring on the
    page, every arm, strand, hook and comma; the flat ink eye; seven dry hairlines pouring into the eye
    between the arms, each a log spiral of its own, of unequal lengths.

Budgets (bible section 7): a big body's volume <= 1 800 triangles, <= 3 500 drawn per cast. Every hull
weight >= 0.105 built studs (>= 0.1 stud at the final size, 1.01 stud per built stud at Size 1.924).


Timeline (VfxTimelineConfig, not this mesh): Face = "Ground", SizeFrom = "Radius", Size = 2 sqrt(R^2 - 9)
/ R = 1.924 -- the sphere (centred at root height) touches the page at sqrt(121 - 9) = 10.583 studs, and
1.93 drew the contour 0.03 stud past it. Spin +2.6. The tick link is a PLUNGE (the bible's "plonge comme
une gorgee"): Y x 0.62-0.7 Back Out 0.08-0.12 s landing on the tick, then a Sine rest back to 1 -- never
the generic Y x 1.35-1.45 jump, which would lift the hooks' ink from ~2.9 to ~4 studs, past the waist.
"""

from __future__ import annotations

import math

from strokes import FLOOR_CLEARANCE, Mesh, Rng, fbm, surface_ribbon

SEED = 5209
ARMS = 7
SEGMENTS = 28  # round the bowl

# The bowl's floor: 0.08 + FLOOR_A (r / FLOOR_R)^FLOOR_P, a lens rising ever steeper toward the lip.
FLOOR_A, FLOOR_R, FLOOR_P = 0.98, 9.45, 2.3


def floor_formula(r: float) -> float:
    return 0.08 + FLOOR_A * (max(r, 0.0) / FLOOR_R) ** FLOOR_P


# The bowl's profile (r, y) in studs, from the centre out along the floor of the bowl, over the rolled
# lip and back down the outer wall to the foot on the page. The first INTERIOR points are the floor.
INTERIOR = [(r, round(floor_formula(r), 4)) for r in (0.0, 4.6, 7.6, 9.45)]
LIP = [(9.32, 1.22), (9.76, 1.37), (10.22, 1.19), (10.08, 0.88)]
FOOT = [(9.2, 0.46), (6.6, 0.0)]
PROFILE = INTERIOR + LIP + FOOT
BOWL_HULL_FROM = len(INTERIOR) - 1  # the bowl's contour starts at the lip's foot: inside it, it is never seen
BOWL_WEIGHT = 0.26

# The arms.
EYE_R = 1.95  # the ink eye
ARM_FROM = 2.3  # an arm's dry end, at the eye's rim
ARM_TO = 8.95  # where it reaches the lip's foot and the neck (or the comma) takes over
B_EYE, B_MID, B_RIM = 0.38, 2.2, 0.2  # the log spiral's b: low, high, low -- the S of the sheet's arms
B_RISE = (2.6, 4.3)  # b climbs from B_EYE to B_MID over these radii ...
B_FALL = (5.7, 8.95)  # ... and falls from B_MID to B_RIM over these
ARM_SAMPLES = 10  # rows along an arm, spaced evenly along its length
HALF_WIDTH = 0.47  # loaded, at the rim
HEIGHT = 0.6  # over the bowl's floor at the rim: the crest stands ~1.6 studs off the page
ARM_WEIGHT = (0.12, 0.26, 0.13)  # contour at the eye, at the rim, at a hook's tip
# Leaning section (x across to the leading side, y up): the buried keel, the trailing side, the crest,
# the leading lip that overhangs (the sheet's arm section). Keel-side faces turn down, so the contour
# shows on both sides of a cord seen from above.
ARM_SECTION = [(0.0, -0.15), (-0.97, 0.36), (0.08, 1.0), (0.94, 0.48)]
STRAND_SECTION = [(0.0, -0.35), (-1.0, 0.6), (1.0, 0.6)]
STRAND_WEIGHT = 0.11  # >= 0.1 stud at the final size
CREST_LIFT = 0.05

FLOW_WIDTH = 0.16
FLOW_LIFT = 0.05
FLOW_SAMPLES = 9
EYE_LIFT = 0.05

# The hook: a logarithmic J rolling forward over the rim (the sheet's "logarithmic geometry").
HOOK_FOOT_R = 9.12  # where its stem stands: on the floor at the lip's foot
HOOK_HEADING = 12.0  # degrees: its plane, turned out from the true tangent at the foot
HOOK_LEAN = 10.0  # degrees: its top leaned out over the rim (upright enough to read at the near rim)
HOOK_R0 = 1.0  # the J's radius at the back of the loop, where the stem tops out ...
HOOK_K = 0.2  # ... shrinking by e^(-k beta): the tip curls in tighter than the crest
HOOK_ASPECT = 1.4  # longer along the rim than tall: a crest lying on the rim
HOOK_HEEL = 0.72  # the radius of the heel that turns the cord from the bowl up into the stem
HOOK_SWEEP = 246.0  # degrees from the back of the loop, over the crest, down the front and in
HOOK_DRIFT = 0.95  # how far the tip drifts in toward the bowl, off the plane: it curls INWARD, non-planar
HOOK_LOOP_SAMPLES = 9
HOOK_HALF_WIDTH = (0.38, 0.28, 0.1)  # at the stem, over the crest, at the tip
HOOK_CLEAR = 0.04  # every free row's lowest corner, body and contour, stands this far over the bowl

# The comma that ends a hookless arm: a flat curl lying on the bowl at the lip.
COMMA_R0, COMMA_K = 0.92, 0.2  # its radius of curvature where it leaves the arm, shrinking by e^(-k phi)
COMMA_SWEEP = 235.0  # degrees it turns in toward the eye: open, its tip clear of the arm it ends
COMMA_ROWS = 5
COMMA_HEIGHT = 0.44  # its crest over the floor at most: low, never a sixth hook


# --- vectors -------------------------------------------------------------------------------------


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


def mean(points):
    n = len(points)
    return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n, sum(p[2] for p in points) / n)


def smooth(e0: float, e1: float, x: float) -> float:
    u = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def turn_ccw(v, angle: float):
    """A horizontal vector turned counter-clockwise seen from above (from +X toward -Z) by `angle`."""
    c, s = math.cos(angle), math.sin(angle)
    return (v[0] * c + v[2] * s, 0.0, -v[0] * s + v[2] * c)


def radial(theta: float):
    return (math.cos(theta), 0.0, -math.sin(theta))


def tangential(theta: float):
    """The counter-clockwise tangent at azimuth theta (the sense of the turn)."""
    return (-math.sin(theta), 0.0, -math.cos(theta))


def azimuth(p) -> float:
    return math.atan2(-p[2], p[0])


# --- the bowl's surfaces -------------------------------------------------------------------------


def floor_y(r: float) -> float:
    """Height of the bowl's floor at radius r: the faceted profile itself, so what lies on it lies on
    the triangles the thrower sees, not on a smooth curve under or over them."""
    for (r0, y0), (r1, y1) in zip(INTERIOR, INTERIOR[1:]):
        if r <= r1:
            return y0 + (y1 - y0) * (r - r0) / (r1 - r0)
    return INTERIOR[-1][1]


def floor_slope(r: float) -> float:
    """dy/dr of the smooth floor the profile samples: for normals only."""
    return FLOOR_A * FLOOR_P * max(r, 0.0) ** (FLOOR_P - 1.0) / FLOOR_R**FLOOR_P


def floor_point(r: float, theta: float):
    # The facets sag inside the circle by up to r (1 - cos(pi / SEGMENTS)); lift by that much.
    sag = r * (1.0 - math.cos(math.pi / SEGMENTS)) * floor_slope(r)
    return (r * math.cos(theta), floor_y(r) + sag, -r * math.sin(theta))


def floor_normal(r: float, theta: float):
    s = floor_slope(r)
    return unit((-s * math.cos(theta), 1.0, s * math.sin(theta)))


def profile_top(r: float) -> float:
    """The bowl's highest surface over radius r on the profile: the floor, the lip's undercut step and
    its top -- what a cord crossing the lip must clear."""
    best = -1.0
    for (r0, y0), (r1, y1) in zip(PROFILE, PROFILE[1:]):
        lo, hi = min(r0, r1), max(r0, r1)
        if lo - 1e-9 <= r <= hi + 1e-9:
            y = max(y0, y1) if abs(r1 - r0) < 1e-9 else y0 + (y1 - y0) * (r - r0) / (r1 - r0)
            best = max(best, y)
    return best


def upper_y(r: float) -> float:
    """The faceted bowl's top over radius r at any azimuth: between two of its ring vertices a facet
    lies inside the circle, so a rising wall stands higher there than the profile says at r."""
    return max(profile_top(r), profile_top(r / math.cos(math.pi / SEGMENTS)))


# --- the bowl ------------------------------------------------------------------------------------


def profile_normals(points):
    """Outward normals of the profile (r, y), which runs out along the top and back under: (-dy, dr)."""
    out = []
    for i, _ in enumerate(points):
        acc = [0.0, 0.0]
        for a, b in ((i - 1, i), (i, i + 1)):
            if 0 <= a and b < len(points):
                (r0, y0), (r1, y1) = points[a], points[b]
                length = math.hypot(r1 - r0, y1 - y0) or 1.0
                acc[0] += -(y1 - y0) / length
                acc[1] += (r1 - r0) / length
        length = math.hypot(*acc) or 1.0
        out.append((acc[0] / length, acc[1] / length))
    return out


def revolve(mesh: Mesh, points, inward: bool) -> None:
    """A surface of revolution through the profile `points`, each face wound by the profile's outward
    normal (or against it, for a hull). A point on the axis is one vertex, a fan."""
    rings = []
    for (r, y) in points:
        if r < 1e-9:
            rings.append([mesh.vert((0.0, y, 0.0))] * SEGMENTS)
        else:
            rings.append([mesh.vert((r * math.cos(2 * math.pi * k / SEGMENTS), y, -r * math.sin(2 * math.pi * k / SEGMENTS))) for k in range(SEGMENTS)])
    sign = -1.0 if inward else 1.0
    for i in range(len(points) - 1):
        # The band's own normal (not its vertices' average, which turns an undercut face up and hides
        # its contour): the profile runs out along the top and back under, so (-dy, dr) is outward.
        (r0, y0), (r1, y1) = points[i], points[i + 1]
        length = math.hypot(r1 - r0, y1 - y0) or 1.0
        nr, ny = -(y1 - y0) / length, (r1 - r0) / length
        for k in range(SEGMENTS):
            n = (k + 1) % SEGMENTS
            mid = 2 * math.pi * (k + 0.5) / SEGMENTS
            facing = mul((nr * math.cos(mid), ny, -nr * math.sin(mid)), sign)
            a, b, c, d = rings[i][k], rings[i][n], rings[i + 1][k], rings[i + 1][n]
            mesh.tri(a, b, c, facing)
            mesh.tri(b, d, c, facing)


def bowl_hull_profile():
    """The contour: the lip and the outer wall pushed out along their normals (to be turned inside
    out). Lighter on the inner face of the lip (a line along the rim seen from above), heavy outside."""
    normals = profile_normals(PROFILE)
    hull = []
    for i in range(BOWL_HULL_FROM, len(PROFILE)):
        (r, y), (nr, ny) = PROFILE[i], normals[i]
        weight = BOWL_WEIGHT * (0.9 if i <= len(INTERIOR) else 1.0)
        hull.append((r + nr * weight, max(y + ny * weight, FLOOR_CLEARANCE)))
    return hull


# The lip's contour is the body's outer edge: nothing else may reach past it (the 22-stud ink ring).
LIP_REACH = max(r for r, _ in bowl_hull_profile())
HOOK_INSIDE = 0.06  # how far inside the lip's contour every hook's own contour stays


def build_bowl(body: Mesh, ink: Mesh) -> None:
    revolve(body, PROFILE, inward=False)
    revolve(ink, bowl_hull_profile(), inward=True)


# --- a cord: a lofted section along a path, with its contour -------------------------------------


def section_normals(corners):
    """Outward vertex normals of a convex section (2D), from its two edges' normals."""
    cx = sum(c[0] for c in corners) / len(corners)
    cy = sum(c[1] for c in corners) / len(corners)
    m = len(corners)
    edge = []
    for j in range(m):
        (x0, y0), (x1, y1) = corners[j], corners[(j + 1) % m]
        nx, ny = y1 - y0, -(x1 - x0)
        if nx * ((x0 + x1) / 2 - cx) + ny * ((y0 + y1) / 2 - cy) < 0:
            nx, ny = -nx, -ny
        length = math.hypot(nx, ny) or 1.0
        edge.append((nx / length, ny / length))
    out = []
    for j in range(m):
        ax, ay = edge[j - 1]
        bx, by = edge[j]
        sx, sy = ax + bx, ay + by
        length = math.hypot(sx, sy) or 1.0
        # Pushed so each face stands off by the full weight, not by weight x cos(half the corner).
        stretch = 1.0 / max(0.55, (ax * bx + ay * by + 1.0) / 2.0) ** 0.5
        out.append((sx / length * stretch, sy / length * stretch))
    return out


def cord_frames(centres, hints):
    """(tangent, across, up) per sample. Where a hint is given (the floor's normal) `up` is that
    normal; elsewhere the frame is carried by parallel transport, so it never flips in a curl."""
    count = len(centres)
    frames = []
    across = None
    for i in range(count):
        t = unit(sub(centres[min(i + 1, count - 1)], centres[max(i - 1, 0)]))
        if hints[i] is not None:
            up = unit(sub(hints[i], mul(t, dot(hints[i], t))))
            across = cross(up, t)
        else:
            across = unit(sub(across, mul(t, dot(across, t))))
            up = cross(t, across)
        frames.append((t, across, up))
    return frames


def cord_rings(centres, hints, widths, heights, weights, section, centring=None):
    """The cord's rings of corners and of contour corners (each corner pushed out along its section
    normal by the weight), both ends drawn to a point pushed on along the path; and the frames.
    `centring` (0..1 per row) slides a row's section from its keel on the path (a cord lying on the
    bowl) to its middle on the path (a cord in the air, whose loop keeps its hole open)."""
    frames = cord_frames(centres, hints)
    count = len(centres)
    rings, hull_rings, mids = [], [], []
    for i in range(count):
        t, a, u = frames[i]
        w, h = widths[i], heights[i]
        scaled = [(x * w, y * h) for x, y in section]
        if centring is not None and centring[i] > 0.0:
            mx = sum(x for x, _ in scaled) / len(scaled)
            my = (max(y for _, y in scaled) + min(y for _, y in scaled)) / 2
            scaled = [(x - mx * centring[i], y - my * centring[i]) for x, y in scaled]
        mid = add(centres[i], add(mul(a, sum(x for x, _ in scaled) / len(scaled)), mul(u, sum(y for _, y in scaled) / len(scaled))))
        mids.append(mid)
        if i in (0, count - 1):
            rings.append([mid])
            push = mul(t, -weights[i] if i == 0 else weights[i])
            hull_rings.append([add(mid, push)])
            continue
        rings.append([add(centres[i], add(mul(a, x), mul(u, y))) for x, y in scaled])
        hull = []
        for (x, y), (nx, ny) in zip(scaled, section_normals(scaled)):
            p = add(centres[i], add(mul(a, x + nx * weights[i]), mul(u, y + ny * weights[i])))
            hull.append((p[0], max(p[1], FLOOR_CLEARANCE), p[2]))
        hull_rings.append(hull)
    return rings, hull_rings, mids, frames


def cord(body: Mesh, ink: Mesh, centres, hints, widths, heights, weights, section, centring=None):
    """A closed cord along `centres` and its contour wound inside out. Returns the rings (corner
    positions) and the frames, for the pale."""
    rings, hull_rings, mids, frames = cord_rings(centres, hints, widths, heights, weights, section, centring)
    count = len(centres)
    m = len(section)
    for mesh, ring_list, sign in ((body, rings, 1.0), (ink, hull_rings, -1.0)):
        ids = []
        for ring in ring_list:
            ids.append([mesh.vert(p) for p in ring] * (m if len(ring) == 1 else 1))
        for i in range(count - 1):
            centre = mul(add(mids[i], mids[i + 1]), 0.5)
            for j in range(m):
                k = (j + 1) % m
                a0, b0, a1, b1 = ids[i][j], ids[i][k], ids[i + 1][j], ids[i + 1][k]
                quad = [mesh.verts[v] for v in (a0, b0, a1, b1)]
                facing = mul(sub(mean(quad), centre), sign)
                mesh.tri(a0, b0, b1, facing)
                mesh.tri(a0, b1, a1, facing)
    return rings, frames


def crest(core: Mesh, rings, frames, first: int, last: int, left: float, right: float) -> None:
    """The pale on the crest of a cord over rings first..last: a lens pointed at both ends, straddling
    the ridge (corner 2) from the trailing slope (corner 1) to the leading one (corner 3), lifted off
    it, so pigment shows all round it -- the pale top of the sheet's cords."""
    rows = []
    for k in range(first, last + 1):
        g = max(0.0, math.sin(math.pi * (k - first) / (last - first))) ** 0.7
        trail, ridge, lead = rings[k][1], rings[k][2], rings[k][3]
        lift = mul(frames[k][2], CREST_LIFT)
        a = add(add(ridge, mul(sub(trail, ridge), left * g)), lift)
        b = add(ridge, lift)
        c = add(add(ridge, mul(sub(lead, ridge), right * g)), lift)
        rows.append((core.vert(a), core.vert(b), core.vert(c), frames[k][2]))
    for k in range(len(rows) - 1):
        (a0, b0, c0, n0), (a1, b1, c1, n1) = rows[k], rows[k + 1]
        facing = add(n0, n1)
        core.tri(a0, b0, b1, facing)
        core.tri(a0, b1, a1, facing)
        core.tri(b0, c0, c1, facing)
        core.tri(b0, c1, b1, facing)


# --- the arms ------------------------------------------------------------------------------------


def b_at(r: float, scale: float = 1.0) -> float:
    """The arm's log-spiral b at radius r: low at the eye, high mid-bowl, low at the rim. Always > 0."""
    b = B_EYE + (B_MID - B_EYE) * smooth(*B_RISE, r) - (B_MID - B_RIM) * smooth(*B_FALL, r)
    return b * scale


def turn(r: float, scale: float = 1.0) -> float:
    """theta(r) - theta(ARM_FROM) of a log spiral whose b eases along r: dtheta = dr / (r b) > 0."""
    steps = 96
    total = 0.0
    for i in range(steps):
        x = ARM_FROM + (r - ARM_FROM) * (i + 0.5) / steps
        total += (r - ARM_FROM) / steps / (x * b_at(x, scale))
    return total


def arm_theta(spec: dict, r: float) -> float:
    return spec["phase"] + turn(r, spec["bscale"])


def arm_specs() -> list[dict]:
    """Seven arms whose ends are spread evenly about the bowl, starting half a step off +Z, so the two
    nearest the thrower at spawn (+Z) are the ones that end in a comma, and a hook stands dead ahead.
    Each arm, and each hook, is drawn a little differently (the bible forbids a perfect symmetry)."""
    rng = Rng(SEED)
    specs = []
    for k in range(ARMS):
        end = math.radians(-90.0 + (k + 0.5) * 360.0 / ARMS + rng.uniform(-3.0, 3.0))
        bscale = rng.uniform(0.93, 1.07)
        spec = {
            "k": k,
            "bscale": bscale,
            "phase": end - turn(ARM_TO, bscale),
            "hook": k not in (0, ARMS - 1),
            "scale": rng.uniform(0.92, 1.06),
            "seed": SEED + 31 * k,
            "r0": HOOK_R0 * rng.uniform(0.94, 1.06),
            "aspect": HOOK_ASPECT * rng.uniform(0.93, 1.07),
            "heading": math.radians(HOOK_HEADING + rng.uniform(-3.0, 3.0)),
            "lean": math.radians(HOOK_LEAN + rng.uniform(-3.0, 3.0)),
            "sweep": math.radians(HOOK_SWEEP + rng.uniform(-8.0, 8.0)),
            "drift": HOOK_DRIFT * rng.uniform(0.85, 1.15),
        }
        specs.append(spec)
    return specs


def arm_profile(sr: float, spec: dict):
    """Half-width and height of an arm at sr (0 the eye .. 1 the lip, by radius): dry and low at the
    eye, loaded at the rim -- a stroke pressed harder as it goes out."""
    wobble = 1.0 + 0.08 * (fbm(4.0 * sr, 0.7, spec["seed"]) * 2.0 - 1.0)
    w = (0.07 + (HALF_WIDTH - 0.07) * smooth(0.0, 0.28, sr)) * (0.86 + 0.14 * sr) * spec["scale"] * wobble
    h = (0.1 + (HEIGHT - 0.1) * smooth(0.0, 0.36, sr) * (0.8 + 0.2 * sr)) * spec["scale"]
    return w, h


def arm_radii(spec: dict, count: int) -> list[float]:
    """`count` radii along the arm from ARM_FROM to ARM_TO, evenly spaced along its LENGTH: the arm is
    long where it winds (at the eye, along the rim) and short where it runs straight out."""
    steps = 240
    rs = [ARM_FROM + (ARM_TO - ARM_FROM) * i / steps for i in range(steps + 1)]
    pts = [floor_point(r, arm_theta(spec, r)) for r in rs]
    acc = [0.0]
    for p, q in zip(pts, pts[1:]):
        acc.append(acc[-1] + math.dist((p[0], p[2]), (q[0], q[2])))
    out = []
    j = 0
    for i in range(count):
        target = acc[-1] * i / (count - 1)
        while j < steps - 1 and acc[j + 1] < target:
            j += 1
        f = (target - acc[j]) / max(acc[j + 1] - acc[j], 1e-9)
        out.append(rs[j] + (rs[j + 1] - rs[j]) * min(max(f, 0.0), 1.0))
    return out


def hook_frame(spec: dict, foot):
    """The J's axes at its foot: p its heading (the true tangent turned out over the rim), v its leaned
    'up', n_in level and toward the bowl, along which its tip drifts."""
    th = azimuth(foot)
    e_t, e_r = tangential(th), radial(th)
    heading = spec["heading"]
    p = unit(add(mul(e_t, math.cos(heading)), mul(e_r, math.sin(heading))))
    outward = unit(sub(e_r, mul(p, dot(e_r, p))))
    v = unit(add(mul((0.0, 1.0, 0.0), math.cos(spec["lean"])), mul(outward, math.sin(spec["lean"]))))
    return p, v, mul(outward, -1.0)


def hook_rows(spec: dict, end, tangent, h_end: float, w_end: float, lift: float):
    """The hook: from the arm's end the neck runs on along the bowl to the lip's foot; there the heel
    turns the cord up into the stem, and it rolls forward over the rim, its radius shrinking
    logarithmically, down the front of the crest and in under it, the tip drifted in toward the bowl.
    Rows of (point, half-width, height, hint, centring, kind); `lift` raises the J (lengthening its
    stem) until its free part clears the lip (arm_rows)."""
    e_t = unit((tangent[0], 0.0, tangent[2]))
    # The foot: where the arm's heading, run on, meets the circle r = HOOK_FOOT_R.
    flat = (end[0], 0.0, end[2])
    along = dot(flat, e_t)
    reach = -along + math.sqrt(max(along * along - dot(flat, flat) + HOOK_FOOT_R**2, 0.0))
    th_f = azimuth(add(flat, mul(e_t, reach)))
    foot = floor_point(HOOK_FOOT_R, th_f)
    p, v, n_in = hook_frame(spec, foot)
    rows = []
    # The neck: a quadratic curve whose first leg is the arm's own heading, riding the bowl.
    bend = add(end, mul(e_t, 0.55 * reach))
    for u in (0.5,):
        q = add(add(mul(end, (1 - u) ** 2), mul(bend, 2 * u * (1 - u))), mul(foot, u * u))
        r, th = math.hypot(q[0], q[2]), azimuth(q)
        rows.append([floor_point(r, th), w_end * 0.92, h_end * 0.95, floor_normal(r, th), 0.0, "neck"])
    rows.append([foot, HOOK_HALF_WIDTH[0] * 1.1, h_end * 0.88, floor_normal(HOOK_FOOT_R, th_f), 0.0, "foot"])
    # The heel: a quarter turn from the bowl up into the stem, wide enough that the inside of the bend
    # (the cord's crest side) never folds through itself.
    for t_deg, centring in ((30.0, 0.35), (60.0, 0.7)):
        t = math.radians(t_deg)
        q = add(foot, add(mul(p, HOOK_HEEL * math.sin(t)), mul(v, HOOK_HEEL * (1.0 - math.cos(t)))))
        w = HOOK_HALF_WIDTH[0] * (1.07 - 0.0012 * t_deg)
        rows.append([q, w, 1.12 * w, None, centring, "heel"])
    # The J: beta from the back of the loop (the stem's top, going straight up) over the crest (90),
    # down the front (180) and in under it; rho = R0 e^(-k beta), stretched along p by the aspect.
    r0, aspect = spec["r0"], spec["aspect"]
    start = add(foot, add(mul(p, HOOK_HEEL), mul(v, HOOK_HEEL + lift)))
    centre = add(start, mul(p, aspect * r0))
    sweep = spec["sweep"]
    for j in range(HOOK_LOOP_SAMPLES):
        f = j / (HOOK_LOOP_SAMPLES - 1)
        beta = sweep * f
        rho = r0 * math.exp(-HOOK_K * beta)
        drift = spec["drift"] * smooth(0.25, 1.0, f) ** 1.2
        point = add(centre, add(add(mul(p, -aspect * rho * math.cos(beta)), mul(v, rho * math.sin(beta))), mul(n_in, drift)))
        if beta <= math.pi / 2:
            w = HOOK_HALF_WIDTH[0] + (HOOK_HALF_WIDTH[1] - HOOK_HALF_WIDTH[0]) * smooth(0.0, math.pi / 2, beta)
        else:
            w = HOOK_HALF_WIDTH[1] + (HOOK_HALF_WIDTH[2] - HOOK_HALF_WIDTH[1]) * ((beta - math.pi / 2) / (sweep - math.pi / 2)) ** 1.15
        rows.append([point, w, 1.15 * w, None, 1.0, "loop"])
    return rows


def comma_rows(spec: dict, end, tangent, w_end: float, h_end: float):
    """A hookless arm's end: it runs on along the bowl at the lip and curls in on itself, flat on the
    bowl -- a logarithmic comma (its radius of curvature shrinking by e^(-k phi)), the crochet of a
    stroke that never left the page."""
    heading = unit((tangent[0], 0.0, tangent[2]))
    q = end
    rows = []
    sweep = math.radians(COMMA_SWEEP)
    prev = 0.0
    for j in range(1, COMMA_ROWS + 1):
        f = j / COMMA_ROWS
        phi = sweep * f
        mid = (prev + phi) / 2
        q = add(q, mul(turn_ccw(heading, mid), COMMA_R0 * math.exp(-COMMA_K * mid) * (phi - prev)))
        prev = phi
        r, th = math.hypot(q[0], q[2]), azimuth(q)
        point = floor_point(r, th)
        q = point
        w = w_end * (1.0 - 0.7 * f**0.9)
        h = min(h_end, COMMA_HEIGHT) * (1.0 - 0.5 * f**1.3)
        rows.append([point, w, h, floor_normal(r, th), 0.0, "comma"])
    return rows


def arm_rows(spec: dict):
    """Every row of an arm and its hook or comma: centres, hints, half-widths, heights, contour
    weights, centrings, kinds."""
    centres, hints, widths, heights, weights, centring, kinds = [], [], [], [], [], [], []
    for r in arm_radii(spec, ARM_SAMPLES):
        sr = (r - ARM_FROM) / (ARM_TO - ARM_FROM)
        th = arm_theta(spec, r)
        centres.append(floor_point(r, th))
        hints.append(floor_normal(r, th))
        w, h = arm_profile(sr, spec)
        widths.append(w)
        heights.append(h)
        weights.append(ARM_WEIGHT[0] + (ARM_WEIGHT[1] - ARM_WEIGHT[0]) * smooth(0.0, 0.8, sr))
        centring.append(0.0)
        kinds.append("arm")
    w_end, h_end = widths[-1], heights[-1]
    r_end = ARM_TO
    th_end = arm_theta(spec, r_end)
    # The arm's own heading at its end (its log spiral's tangent), not the last chord's.
    d = 0.02
    tangent = sub(floor_point(r_end, arm_theta(spec, r_end)), floor_point(r_end - d, arm_theta(spec, r_end - d)))
    del th_end

    def assemble(extra):
        n = len(extra)
        return (
            centres + [row[0] for row in extra],
            hints + [row[3] for row in extra],
            widths + [row[1] for row in extra],
            heights + [row[2] for row in extra],
            weights + [ARM_WEIGHT[1] + (ARM_WEIGHT[2] - ARM_WEIGHT[1]) * ((j + 1) / n) ** 1.3 for j in range(n)],
            centring + [row[4] for row in extra],
            kinds + [row[5] for row in extra],
        )

    if not spec["hook"]:
        return assemble(comma_rows(spec, centres[-1], tangent, w_end, h_end))
    def lifted(spec_try):
        # The least lift that sets every free row of the J clear of the bowl (bisection: the frames move).
        low, high = 0.0, 1.5
        if min_free_clearance(*assemble(hook_rows(spec_try, centres[-1], tangent, h_end, w_end, low))) < 0.0:
            for _ in range(28):
                mid = (low + high) / 2
                if min_free_clearance(*assemble(hook_rows(spec_try, centres[-1], tangent, h_end, w_end, mid))) >= 0.0:
                    high = mid
                else:
                    low = mid
            low = high
        return low, assemble(hook_rows(spec_try, centres[-1], tangent, h_end, w_end, low))

    # Turned out over the rim as far as the lip's own contour allows, never past it: the heading is
    # brought in, a degree and a half at a time, until the hook's contour stays inside the 22-stud ring.
    wanted = spec["heading"]
    for step in range(40):
        spec["heading"] = wanted - math.radians(1.5 * step)
        lift, rows = lifted(spec)
        if hook_reach(*rows) <= LIP_REACH - HOOK_INSIDE:
            break
    spec["lift"] = lift
    return rows


FREE_FROM = 3  # the J's rows from this one on (past the crest's rise) are in the air: they clear the bowl


def hook_reach(centres, hints, widths, heights, weights, centring, kinds) -> float:
    """How far from the axis the hook's contour reaches (heel, stem and J)."""
    _, hull_rings, _, _ = cord_rings(centres, hints, widths, heights, weights, ARM_SECTION, centring)
    return max(math.hypot(q[0], q[2]) for i, k in enumerate(kinds) if k in ("heel", "loop") for q in hull_rings[i])


def min_free_clearance(centres, hints, widths, heights, weights, centring, kinds) -> float:
    """How far the lowest corner of any free J row, body or contour, stands over the bowl beneath it
    (minus HOOK_CLEAR), the segments between rows sampled too: < 0 means the crest is in the lip."""
    rings, hull_rings, _, _ = cord_rings(centres, hints, widths, heights, weights, ARM_SECTION, centring)
    loop = [i for i, k in enumerate(kinds) if k == "loop"]
    free = loop[FREE_FROM:]
    worst = math.inf
    for i in free:
        for ring_list in (rings, hull_rings):
            pts = list(ring_list[i])
            prev = ring_list[i - 1]
            if len(prev) == len(ring_list[i]):
                for a, b in zip(prev, ring_list[i]):
                    for f in (0.25, 0.5, 0.75):
                        pts.append(add(mul(a, 1 - f), mul(b, f)))
            for q in pts:
                worst = min(worst, q[1] - upper_y(math.hypot(q[0], q[2])) - HOOK_CLEAR)
    return worst


def build_arm(body: Mesh, core: Mesh, ink: Mesh, spec: dict) -> None:
    centres, hints, widths, heights, weights, centring, kinds = arm_rows(spec)
    rings, frames = cord(body, ink, centres, hints, widths, heights, weights, ARM_SECTION, centring)
    # The pale: from mid-bowl along the crest, closing to its point before the neck turns (a hook's) or
    # before the comma curls (a hookless arm's): in the curls the lens would turn from the viewer.
    first = 3
    last = kinds.index("neck") if spec["hook"] else kinds.index("comma")
    crest(core, rings, frames, first, last, 0.5, 0.36)
    build_strands(body, ink, spec)


def build_strands(body: Mesh, ink: Mesh, spec: dict) -> None:
    """Where the arm thins at the eye it splits: two dry strands peel off beside its own end, run to
    the eye's rim at unequal lengths and fade out there."""
    rng = Rng(spec["seed"] + 7)
    for side in (-1.0, 1.0):
        r_start = rng.uniform(3.9, 4.5)
        r_stop = rng.uniform(2.25, 2.9)
        spread = rng.uniform(0.32, 0.5)
        samples = 3
        centres, hints, widths, heights, weights = [], [], [], [], []
        for i in range(samples):
            f = i / (samples - 1)
            r = r_start + (r_stop - r_start) * f
            sr = (r - ARM_FROM) / (ARM_TO - ARM_FROM)
            w_arm, h_arm = arm_profile(sr, spec)
            offset = side * (0.1 + spread * smooth(0.0, 1.0, f) ** 0.8)
            th = arm_theta(spec, r) + offset / r
            centres.append(floor_point(r, th))
            hints.append(floor_normal(r, th))
            widths.append(max(0.05, 0.55 * w_arm * (1.0 - 0.55 * f)))
            heights.append(0.8 * h_arm * (1.0 - 0.3 * f))
            weights.append(STRAND_WEIGHT)
        cord(body, ink, centres, hints, widths, heights, weights, STRAND_SECTION)


# --- the eye and the flow lines -------------------------------------------------------------------


def build_eye(ink: Mesh) -> None:
    """The flat ink eye: a disc lying on the bowl's floor, its rim a hair uneven (a brush's, not a
    compass's)."""
    sides = 24
    centre = ink.vert((0.0, floor_y(0.0) + EYE_LIFT, 0.0))
    ring = []
    for k in range(sides):
        th = 2 * math.pi * k / sides
        r = EYE_R * (1.0 + 0.05 * (fbm(3.0 * k / sides, 2.3, SEED + 3, period=3) * 2.0 - 1.0))
        p = floor_point(r, th)
        ring.append(ink.vert((p[0], p[1] + EYE_LIFT, p[2])))
    for k in range(sides):
        ink.tri(centre, ring[k], ring[(k + 1) % sides], (0.0, 1.0, 0.0))


def build_flow_lines(ink: Mesh, specs: list[dict]) -> None:
    """Seven dry hairlines between the arms' thinning ends, pressed in on the bowl and released at
    the eye, so they pour into it (the sheet's "dry strands at eye"); each leans off the arms' spiral
    by its own amount, so none runs parallel to an arm or to another, and none is as long as the next."""
    rng = Rng(SEED + 11)
    surface = (floor_point, floor_normal)
    for spec, nxt in zip(specs, specs[1:] + specs[:1]):
        gap = (nxt["phase"] - spec["phase"]) % (2 * math.pi)
        share = rng.uniform(0.4, 0.6)
        r_out = rng.uniform(3.7, 4.8)
        r_in = rng.uniform(2.0, 2.3)
        lean = rng.uniform(-0.3, 0.3)

        def path(tau, spec=spec, gap=gap, share=share, r_out=r_out, r_in=r_in, lean=lean):
            r = r_out + (r_in - r_out) * tau
            base = spec["phase"] + gap * share + turn(r)
            return r, base + lean * (turn(r) - turn(r_out))

        surface_ribbon(ink, surface, path, FLOW_WIDTH * rng.uniform(0.9, 1.15), FLOW_LIFT, FLOW_SAMPLES, SEED + 13 + spec["k"])


# --- the three meshes ----------------------------------------------------------------------------

_CACHE: dict = {}


def build():
    if "meshes" in _CACHE:
        return _CACHE["meshes"]
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    build_bowl(body, ink)
    specs = arm_specs()
    for spec in specs:
        build_arm(body, core, ink, spec)
    build_eye(ink)
    build_flow_lines(ink, specs)
    reach = max(math.hypot(x, z) for mesh in (body, core, ink) for x, _, z in mesh.verts)
    for mesh in (body, core, ink):
        mesh.scale(0.5 / reach)
    _CACHE["meshes"] = (body, core, ink)
    return _CACHE["meshes"]


def meta(seed: int) -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def spiral_bowl():
    return build()[0], meta(SEED)


def spiral_core():
    return build()[1], meta(SEED + 1)


def spiral_ink():
    return build()[2], meta(SEED + 2)
