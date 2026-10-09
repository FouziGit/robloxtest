"""The Cartouche's scrollwork frame (Indigo x4, ultimate): twelve ink leaves round the
cast point, chained round the ring with their tips all one way, each face turned to the centre and the sky,
and on each, at its foot, a volute rolled from the stem's own line -- two clean turns, a pale foam band
along the outer turn and foam lobes on its rim, an ink hollow inside it, a notch between neighbouring
leaves: a frame of pieces, never a solid wall.

Drawn after the developer's two references (docs/vfx/cartouche/ref-1.jpg, the frame in game round a
blocky avatar; ref-2.jpg, the model sheet: profile, top-down, perspective, leaf, "from behind"). The sheet
gives the shape: twelve leaves (its top-down count), ovate and about 1.7 long for 1 wide with a short stem,
thick at the foot and thin at the lip; seen from above they chain round the ring, tips all one way, only a
notch between neighbours, a pale spiral on each near its stem end; "from behind" (the camera inside the
ring) the stem runs into the spiral -- a pale outer band, an ink hollow -- and the blade runs on out of
it. The game shot gives the read: a spiral end with a scalloped pale cap on every leaf, seen from where
the thrower stands. Reconciled with the art bible (section 11, the Cartouche: twelve leaves, 2.6 studs
tall, rolling inward, foam on each roll, an ink hollow, a notch; section 4.3: a ground body stays at 3
studs or under except its points) and with the server (GlyphConfig Cartouche Params.Radius 16, so
OuterDiameter = 32 studs at Size 2; the sphere centred 3 studs over the floor).

To keep the bulk under 3 studs and still fill each 30-degree slot, every leaf leans 55 degrees along the
ring (tips counter-clockwise seen from above), tilts back 50 degrees (its face turned to the centre and
up) and is turned about the vertical so it lies along the ring: the thrower sees every face and every
spiral, and from above the faces chain round the ring, as the sheet's top-down view draws them. The
volute is an Ionic one: a rolled sheet standing on the inner face, its axis the face's own normal, so its
spiral faces the thrower and the sky alike; its tail is the stem's line running up the face into the
outer turn. Only the lip reaches 3 studs.

Roblox space: X right, Y up, forward -Z; angles round the ring from +X toward -Z, leaves at 15 + 30k
degrees, so a notch lies straight ahead of the thrower (where his own head hides the frame) and one
straight behind. Built in studs, then normalised so the outer ink sits exactly 0.5 from the pivot
(Reference "OuterDiameter" = 1), pivot on the floor at the ring's centre, axis Y.

The sphere touches the floor at sqrt(16^2 - 3^2) = 15.72 studs. Here nothing within 0.5 stud of the floor
lies past 14.2 studs: the outer ink reaches 16 only 2.4 to 3 studs up (the leaves lean outward), where the
sphere's radius is 16. So Size 2 is right: the largest Size that keeps every vertex inside the sphere is 1.9998.

Three volumes, one tone each:
  - Pigment: per leaf the blade (a closed slab: flat inner face, a ridge behind, a short stem) and the
    volute (a closed rolled sheet: the tail and two turns, no turn touching another, its far end a knife
    edge inside the blade);
  - Core: on each volute a pale band on its end face along the outer turn's upper side (at least 0.15
    stud wide, pigment on both its sides) and the foam on the rim above it, scalloped into lobes;
  - Ink: the blade's hull (four corners: the knife edges pushed sideways, the inner face's midline and the
    ridge pushed out of either face), the volute's hull (a closed prism on its ring, ear-clipped caps: its
    far cap, just off the face, is the dark seen through the spiral's gaps), the volute's hollow (the
    sheet's inner faces), the midrib and two veins on the inner face.
"""

from __future__ import annotations

import math

from strokes import (
    FLOOR_CLEARANCE,
    Mesh,
    Rng,
    Volume,
    add,
    cosine_curve,
    cross,
    dot,
    emit,
    lerp,
    mul,
    norm,
    smoothstep,
    sub,
    surface_ribbon,
)

SEED = 6223
LEAVES = 12
FIRST_ANGLE = 15.0  # degrees: leaves at 15 + 30k, so a notch lies straight ahead (-Z) and straight behind
OUTER = 15.99  # studs: Params.Radius, where the outer ink lands
REF_STUDS = 32.0  # the reference extent at Size 2
CLEAR = FLOOR_CLEARANCE * REF_STUDS  # 0.128 stud: FLOOR_CLEARANCE is 0.004 of the 32-stud reference

# --- the blade, in its own frame: x across (+x the lower margin once leaned), y up its length, z out of
# its inner face -----------------------------------------------------------------------------------------
STEM_TOP = 0.6  # where the blade begins, up the stem
BLADE_LEN = 6.8  # stem top to tip
BLADE_W = 4.9  # at its widest: 6.4 / 3.76 = 1.7
# The ovate outline, (fraction up the blade, share of the half-width): a cuneate base drawn out of the
# stem, widest a little under halfway, a long taper to the lip.
OUTLINE = [(0.0, 0.07), (0.05, 0.24), (0.13, 0.5), (0.23, 0.76), (0.34, 0.93), (0.44, 1.0), (0.56, 0.96), (0.68, 0.83), (0.8, 0.62), (0.9, 0.38), (0.96, 0.18), (1.0, 0.0)]
STATIONS = [0.16, 0.4, 0.64, 0.86]  # with the stem top and the tip: ten outline points a side
THICK = [(0.0, 0.26), (0.3, 0.18), (0.7, 0.1), (1.0, 0.05)]  # the ridge behind the flat inner face
STEM_HALF = 0.15
HOOK = 0.55  # the lip hooks inward over the last 28%, toward the centre
BOW = 0.4  # the blade bellies back along its length, then hooks: an S, not a plank
CURL = 0.45  # and turns the same way on every leaf
LEAN = 55.0  # degrees along the ring, tips counter-clockwise seen from above
TILT = 50.0  # degrees back: the face turned to the centre and up
FOOT_FLARE = 1.25
ALONG = 0.55  # how much of the blade's run across the ring a turn about the vertical takes back

# --- the volute: a coil standing on the inner face at the leaf's foot, its axis the face's own normal (an
# Ionic volute) -- so its spiral faces the thrower and the sky, as the sheet draws it from above and from
# inside the ring. Its tail is the stem's own line, running up the face into the outer turn.
COIL_U = 0.28  # its eye, up the blade (fraction)
COIL_X = -0.32  # and across, studs (- toward the upper margin), so the tail rises straight from the stem
COIL_LEN = 0.62  # how far it stands off the face
COIL_BACK = -0.015  # its far end, just inside the blade
# The rolled sheet in the face's plane (p across toward the lower margin, q up the blade; angles from +p
# toward +q): from the tail (up the face from the stem) into the outer turn at 0, counter-clockwise round
# and in -- the outer turn in 7 facets, the inner one in 5, two full turns, each turn clear of the next by
# at least 0.1 stud.
OUTER_FACETS, INNER_FACETS = 12, 5
COIL_TURNS = 1.6
COIL_R0 = 0.72  # the sheet's mid-surface at the start of the outer turn
COIL_PITCHES = (0.34, 0.25)  # how far each turn steps in
COIL_TH = (0.23, 0.19, 0.09)  # thickness at the start of the outer turn, after it, at the inner end

# --- ink and core ------------------------------------------------------------------------------------------
HULL_FOOT, HULL_LIP = 0.16, 0.15
COIL_HULL = 0.14
COIL_HULL_FAR = 0.04  # the coil's contour starts this far off the face: its far cap, the hollow, lies on it
CORE_LIFT = 0.04  # bible section 2: Core lifted 0.03-0.08 stud
VEIN_LIFT = 0.035
MIDRIB, VEIN_W = 0.2, 0.12
MIDRIB_FROM, MIDRIB_TO = 0.55, 0.9  # the midrib, from the volute's top to short of the lip
VEINS = ()  # (start up the face, side, rise)
FOAM_FROM, FOAM_TO = 30.0, 330.0  # degrees on the outer turn: its upper side, facet line to facet line
FOAM_DEPTH = (0.22, 0.4)  # down the coil's side from its rim, between the scallops and at their tips
FOAM_RIM = 0.04  # pigment left between the foam and the rim
FOAM_SCALLOPS = 5.0
BAND = (-0.4, 0.36)  # the end-face band, across the sheet (+0.5 its outer side)


def frame(theta: float, lean: float, tilt: float):
    """The leaf's axes in Roblox space at ring angle theta: x across (the lower margin), y up the blade, z
    out of the inner face (toward the centre and up), and the ring's own (ccw tangent, up, outward)."""
    e_r = (math.cos(theta), 0.0, -math.sin(theta))
    e_u = (0.0, 1.0, 0.0)
    e_t = (-math.sin(theta), 0.0, -math.cos(theta))  # counter-clockwise seen from above
    up = add(mul(e_u, math.cos(tilt)), mul(e_r, math.sin(tilt)))
    inner = add(mul(e_r, -math.cos(tilt)), mul(e_u, math.sin(tilt)))
    y_ax = add(mul(up, math.cos(lean)), mul(e_t, math.sin(lean)))
    x_ax = sub(mul(e_t, math.cos(lean)), mul(up, math.sin(lean)))
    # Tilted back, the blade's length would run out across the ring; a turn about the vertical lays it
    # along the ring instead, as the sheet's top-down view chains the leaves.
    swing = -ALONG * math.atan2(dot(y_ax, e_r), dot(y_ax, e_t))

    def turn(v):
        c, s = math.cos(swing), math.sin(swing)
        # About +Y, from e_t toward e_r for a positive swing.
        t, r = dot(v, e_t), dot(v, e_r)
        return add(mul(e_t, t * c - r * s), add(mul(e_r, t * s + r * c), (0.0, v[1], 0.0)))

    return turn(x_ax), turn(y_ax), turn(inner), (e_t, e_u, e_r)


class Leaf:
    def __init__(self, k: int, rng: Rng, r_foot: float) -> None:
        self.k = k
        self.theta = math.radians(FIRST_ANGLE + 30.0 * k)
        self.len = BLADE_LEN * (1.0 + 0.03 * (rng.random() - 0.5) * 2.0)
        self.width = BLADE_W * (1.0 + 0.03 * (rng.random() - 0.5) * 2.0)
        self.lean = math.radians(LEAN + 3.0 * (rng.random() - 0.5) * 2.0)
        self.tilt = math.radians(TILT + 2.0 * (rng.random() - 0.5) * 2.0)
        self.foot = (r_foot * math.cos(self.theta), 0.0, -r_foot * math.sin(self.theta))
        self.x_ax, self.y_ax, self.z_ax, (self.e_t, self.e_u, self.e_r) = frame(self.theta, self.lean, self.tilt)
        self.rings: list[list[tuple[float, float, float]]] = []  # leaf-frame [L, R, B] per station
        self.world: list[list[tuple[float, float, float]]] = []  # the same in Roblox space
        self.weights: list[float] = []

    # The blade -----------------------------------------------------------------------------------------
    def to_world(self, p) -> tuple[float, float, float]:
        x, y, z = p
        return add(self.foot, add(mul(self.x_ax, x), add(mul(self.y_ax, y), mul(self.z_ax, z))))

    def spine(self, u: float) -> tuple[float, float]:
        """(x, z) of the inner face's midline at blade fraction u: the lip hooks in and turns aside."""
        hook = smoothstep(0.72, 1.0, u) ** 1.6
        return CURL * hook, HOOK * hook - BOW * math.sin(math.pi * u)

    def section(self, u: float) -> list[tuple[float, float, float]]:
        y = STEM_TOP + self.len * u
        x0, z0 = self.spine(u)
        hw = max(self.width / 2.0 * cosine_curve(OUTLINE, u), STEM_HALF)
        th = cosine_curve(THICK, u)
        return [(x0 - hw, y, z0), (x0 + hw, y, z0), (x0, y, z0 - th)]

    def build_blade(self) -> Volume:
        vol = Volume()
        stem = [(-STEM_HALF, STEM_TOP, 0.06), (STEM_HALF, STEM_TOP, 0.06), (0.0, STEM_TOP, -0.26)]
        self.rings = [stem] + [self.section(u) for u in STATIONS]
        self.world = [[self.to_world(p) for p in ring] for ring in self.rings]
        # The foot: the stem top's own shape, flared, set flat on the floor round the foot point.
        top = self.world[0]
        centre = mul(add(add(top[0], top[1]), top[2]), 1.0 / 3.0)
        foot = [(self.foot[0] + (p[0] - centre[0]) * FOOT_FLARE, 0.0, self.foot[2] + (p[2] - centre[2]) * FOOT_FLARE) for p in top]
        self.world.insert(0, foot)
        self.rings.insert(0, None)
        heights = [0.0] + [STEM_TOP] + [STEM_TOP + self.len * u for u in STATIONS]
        total = STEM_TOP + self.len
        self.weights = [HULL_FOOT + (HULL_LIP - HULL_FOOT) * smoothstep(0.0, 0.9, h / total) for h in heights]
        # Nothing under the floor: the lower margin is lifted where the lean would take it there.
        self.world = [[(x, max(y, 0.0), z) for x, y, z in ring] for ring in self.world[:1]] + [[(x, max(y, CLEAR + HULL_LIP), z) for x, y, z in ring] for ring in self.world[1:]]
        rings = [[vol.vert(p, 0.0) for p in ring] for ring in self.world]
        x0, z0 = self.spine(1.0)
        self.tip_local = (x0, STEM_TOP + self.len, z0)
        tip = vol.vert(self.to_world(self.tip_local), 0.0)
        for lo, hi in zip(rings, rings[1:]):
            for j in range(3):
                k = (j + 1) % 3
                emit(vol.mesh, lo[j], lo[k], hi[k])
                emit(vol.mesh, lo[j], hi[k], hi[j])
        last = rings[-1]
        for j in range(3):
            emit(vol.mesh, last[j], last[(j + 1) % 3], tip)
        foot_ring = rings[0]
        emit(vol.mesh, foot_ring[2], foot_ring[1], foot_ring[0])  # against the band above it
        vol.orient_outward()
        return vol

    def blade_hull(self, ink: Mesh) -> None:
        """The blade's contour: at every station the knife edges pushed out sideways, the inner face's midline
        pushed out of the face and the ridge pushed out behind it -- so the rim is even seen from the face,
        from behind, from beyond either margin and in profile -- heavier at the foot, lighter at the lip; the
        tip pushed on up its spine; the foot a ring on the floor; wound inward."""
        verts = []
        for index, (ring, weight) in enumerate(zip(self.world, self.weights)):
            if index == 0:
                cx = sum(p[0] for p in ring) / 3.0
                cz = sum(p[2] for p in ring) / 3.0
                pushed = []
                for x, _, z in ring:
                    d = math.hypot(x - cx, z - cz) or 1.0
                    pushed.append((x + (x - cx) / d * weight, CLEAR, z + (z - cz) / d * weight))
                # The inner corner of the foot: between its two knife edges, pushed the same way.
                (lx, _, lz), (rx, _, rz) = pushed[0], pushed[1]
                mx, mz = (lx + rx) / 2.0, (lz + rz) / 2.0
                d = math.hypot(mx - cx, mz - cz) or 1.0
                pushed.insert(1, (mx + (mx - cx) / d * weight * 0.5, CLEAR, mz + (mz - cz) / d * weight * 0.5))
            else:
                left, right, ridge = ring
                side = self.x_ax
                pushed = [
                    add(left, mul(side, -weight)),
                    add(lerp(left, right, 0.5), mul(self.z_ax, weight)),
                    add(right, mul(side, weight)),
                    add(ridge, mul(self.z_ax, -weight)),
                ]
                pushed = [(x, max(y, CLEAR), z) for x, y, z in pushed]
            verts.append([ink.vert(p) for p in pushed])
        a = self.to_world(self.tip_local)
        b = self.to_world((self.spine(0.97)[0], STEM_TOP + self.len * 0.97, self.spine(0.97)[1]))
        tip = ink.vert(add(a, mul(norm(sub(a, b)), HULL_LIP)))
        tris = []
        for lo, hi in zip(verts, verts[1:]):
            for j in range(4):
                k = (j + 1) % 4
                tris += [(lo[j], lo[k], hi[k]), (lo[j], hi[k], hi[j])]
        last = verts[-1]
        tris += [(last[j], last[(j + 1) % 4], tip) for j in range(4)]
        foot = verts[0]
        tris += [(foot[3], foot[2], foot[1]), (foot[3], foot[1], foot[0])]  # against the band above it
        _emit_inward(ink, tris)

    def face_surface(self):
        """(point(s, t), normal(s, t)) of the inner face, flat across each band and piecewise linear on the
        mesh's own vertices: s up the blade (0 the stem top, 1 the last station), t across (-1 the upper
        margin, +1 the lower)."""
        rings = self.world[1:]
        count = len(rings) - 1

        def point(s: float, t: float):
            f = min(max(s, 0.0), 1.0) * count
            i = min(int(f), count - 1)
            g = f - i
            lo, hi = rings[i], rings[i + 1]
            h = (t + 1.0) / 2.0
            return lerp(lerp(lo[0], lo[1], h), lerp(hi[0], hi[1], h), g)

        def normal(s: float, t: float):
            return self.z_ax

        return point, normal

    def veins(self, ink: Mesh) -> None:
        """The midrib from the volute's top up the inner face to the lip, and three side veins sweeping up
        to the margin, never in mirrored pairs."""
        face = self.face_surface()
        rng = Rng(SEED + 7 * self.k)
        surface_ribbon(ink, face, lambda tau: (MIDRIB_FROM + (MIDRIB_TO - MIDRIB_FROM) * tau, 0.03 * math.sin(3.0 * tau)), MIDRIB, VEIN_LIFT, 3, SEED + self.k)
        for s0, side, rise in VEINS:
            s0 += 0.03 * (rng.random() - 0.5)

            def vein(tau, s0=s0, side=side, rise=rise):
                return s0 + rise * tau ** 1.3, side * 0.7 * tau

            surface_ribbon(ink, face, vein, VEIN_W, VEIN_LIFT, 3, SEED + 11 * self.k)

    # The volute -----------------------------------------------------------------------------------------
    def coil_frame(self):
        """The coil's axis A (the face's normal, out of the inner face), its cross-section axes P (across,
        toward the lower margin) and Q (up the blade), and its eye on the face."""
        u = COIL_U
        y = STEM_TOP + self.len * u
        eye = self.to_world((COIL_X, y, self.spine(u)[1]))
        return self.z_ax, self.x_ax, self.y_ax, eye

    @staticmethod
    def coil_samples():
        """(degrees, radius of the mid-surface, thickness) along the spiral."""
        out = []
        outer = [360.0 * i / OUTER_FACETS for i in range(OUTER_FACETS + 1)]
        end = 360.0 * COIL_TURNS
        inner = [360.0 + (end - 360.0) * i / INNER_FACETS for i in range(1, INNER_FACETS + 1)]
        k1, k2 = COIL_PITCHES
        t0, t1, t2 = COIL_TH
        for deg in outer + inner:
            turns = deg / 360.0
            if turns <= 1.0:
                r = COIL_R0 - k1 * turns
                th = t0 + (t1 - t0) * turns
            else:
                r = COIL_R0 - k1 - k2 * (turns - 1.0)
                th = t1 + (t2 - t1) * (turns - 1.0) / (COIL_TURNS - 1.0)
            out.append((deg, r, th))
        return out

    @staticmethod
    def side2(sample, share: float) -> tuple[float, float]:
        """A spiral sample's point (p, q) across the sheet: share +0.5 its outer side."""
        deg, r, th = sample
        a = math.radians(deg)
        rr = r + th * share
        return rr * math.cos(a), rr * math.sin(a)

    def tail(self) -> tuple[tuple[float, float], tuple[float, float]]:
        """The tail's foot (outer side, inner side) in the cross-section: on the stem's top, straight below
        the outer turn's start."""
        y_eye = STEM_TOP + self.len * COIL_U
        p, q = -COIL_X, STEM_TOP - y_eye + 0.05
        th = COIL_TH[0]
        # Across the tail, square to its run up to the start of the outer turn.
        sp, sq = COIL_R0 - p, -q
        length = math.hypot(sp, sq)
        n = (sq / length, -sp / length)  # its right-hand normal: the outer side, as at the turn's start
        return (p + n[0] * th / 2.0, q + n[1] * th / 2.0), (p - n[0] * th / 2.0, q - n[1] * th / 2.0)

    def section2(self) -> list[tuple[tuple[float, float], tuple[float, float]]]:
        """(outer, inner) cross-section points along the whole sheet: the tail's foot, then the spiral."""
        return [self.tail()] + [(self.side2(sm, 0.5), self.side2(sm, -0.5)) for sm in self.coil_samples()]

    def coil_point(self, along: float, pq: tuple[float, float]):
        axis, p, q, eye = self.coil
        x, y, z = add(eye, add(mul(axis, along), add(mul(p, pq[0]), mul(q, pq[1]))))
        return x, max(y, 0.0), z

    def build_coil(self) -> tuple[Volume, set]:
        """The rolled sheet as one closed volume: its outer and inner faces between its far end (a knife edge
        just inside the blade) and its near end (the spiral the thrower sees), the near end's strips, and
        the sheet's start and end edges. Returns the volume and the indices of its triangles that are the
        hollow (the sheet's inner faces, past the tail)."""
        self.coil = self.coil_frame()
        sec = self.section2()
        n = len(sec)
        vol = Volume()
        # The far end, inside the blade, closes to the sheet's mid-surface: a knife edge nobody sees, so it
        # needs no end strips. The near end is the spiral.
        mid = [vol.vert(self.coil_point(COIL_BACK, ((o[0] + i[0]) / 2.0, (o[1] + i[1]) / 2.0)), 0.0) for o, i in sec]
        o0 = i0 = mid
        o1 = [vol.vert(self.coil_point(COIL_LEN, o), 0.0) for o, _ in sec]
        i1 = [vol.vert(self.coil_point(COIL_LEN, i), 0.0) for _, i in sec]
        hollow = set()

        def quad(a, b, c, d, dark):
            for tri in ((a, b, c), (a, c, d)):
                if emit(vol.mesh, *tri) and dark:
                    hollow.add(len(vol.mesh.tris) - 1)

        for j in range(n - 1):
            # The outer face: pigment (seen across the gaps, blue between the dark lines, as the sheet draws it).
            quad(o0[j], o0[j + 1], o1[j + 1], o1[j], False)
            # The inner face: pigment along the tail, then always the hollow.
            quad(i0[j + 1], i0[j], i1[j], i1[j + 1], False)
            quad(o0[j + 1], o0[j], i0[j], i0[j + 1], False)
            quad(o1[j], o1[j + 1], i1[j + 1], i1[j], False)
        quad(i0[0], o0[0], o1[0], i1[0], False)
        quad(o0[-1], i0[-1], i1[-1], o1[-1], False)
        vol.orient_outward()
        return vol, hollow

    def hull_ring(self) -> list[tuple[float, float]]:
        """The coil's contour ring in the cross-section, counter-clockwise: the tail's foot, up its outer side
        into the outer turn, round it to where it comes back beside the tail, and down the tail's inner side
        -- each corner pushed out by the weight (mitred, so the rim is even)."""
        sec = self.section2()
        # Round the outer turn to its last corner before it passes inside the tail, then straight down
        # beside the tail: only a thin notch along the tail is dark, not the face below the coil.
        ring = [sec[0][0]] + [o for o, _ in sec[1:OUTER_FACETS + 1]] + [sec[0][1]]
        m = len(ring)
        area = sum(ring[i][0] * ring[(i + 1) % m][1] - ring[(i + 1) % m][0] * ring[i][1] for i in range(m))
        if area < 0:
            ring = ring[::-1]
        out = []
        for i in range(m):
            a, b, c = ring[i - 1], ring[i], ring[(i + 1) % m]
            normals = []
            for p0, p1 in ((a, b), (b, c)):
                dx, dy = p1[0] - p0[0], p1[1] - p0[1]
                length = math.hypot(dx, dy)
                normals.append((dy / length, -dx / length))  # outward for a counter-clockwise ring
            bx, by = normals[0][0] + normals[1][0], normals[0][1] + normals[1][1]
            bl = math.hypot(bx, by)
            bx, by = bx / bl, by / bl
            cosine = max(bx * normals[0][0] + by * normals[0][1], 0.5)
            out.append((b[0] + bx * COIL_HULL / cosine, b[1] + by * COIL_HULL / cosine))
        return out

    def coil_hull(self, ink: Mesh) -> None:
        """The coil's contour: a closed prism on its ring, from just off the face (its far cap is the dark
        seen through the spiral's gaps, and its rim the outline on the leaf) to past the near end, its end
        caps fanned; wound inward."""
        ring = self.hull_ring()
        rings = []
        for along in (COIL_HULL_FAR, COIL_LEN + COIL_HULL):
            points = [self.coil_point(along, pq) for pq in ring]
            rings.append([ink.vert((x, max(y, CLEAR), z)) for x, y, z in points])
        r0, r1 = rings
        m = len(r0)
        tris = []
        for j in range(m):
            k = (j + 1) % m
            tris += [(r0[j], r0[k], r1[k]), (r0[j], r1[k], r1[j])]
        # The ring is not convex where it turns down beside the tail: its caps are ear-clipped, so no cap
        # triangle reaches outside it.
        for a, b, c in _ear_clip(ring):
            tris += [(r0[a], r0[c], r0[b]), (r1[a], r1[b], r1[c])]
        _emit_inward(ink, tris)

    def strip_at(self, deg: float, share: float) -> tuple[float, float]:
        """The cross-section point at `deg` and `share` across the sheet, on the straight edge between the
        two spiral samples either side (as the mesh is), never on the arc."""
        samples = self.coil_samples()
        for s0, s1 in zip(samples, samples[1:]):
            if s0[0] <= deg <= s1[0]:
                f = (deg - s0[0]) / (s1[0] - s0[0])
                p0, p1 = self.side2(s0, share), self.side2(s1, share)
                return p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f
        raise ValueError(deg)

    def foam(self, core: Mesh) -> None:
        """The foam capping the coil: a pale rim round the upper side of the outer turn, just under its edge,
        its lower edge scalloped into lobes like the wave's caps; each quad flat on one facet, lifted."""
        samples = self.coil_samples()
        rng = Rng(SEED + 31 * self.k)
        phase = rng.uniform(0.0, 6.28)
        facets = [(s0, s1) for s0, s1 in zip(samples, samples[1:]) if FOAM_FROM - 1e-6 <= s0[0] and s1[0] <= FOAM_TO + 1e-6]
        span = FOAM_TO - FOAM_FROM
        for s0, s1 in facets:
            p0, p1 = self.side2(s0, 0.5), self.side2(s1, 0.5)
            dp, dq = p1[0] - p0[0], p1[1] - p0[1]
            length = math.hypot(dp, dq)
            nrm = (dq / length, -dp / length)
            if nrm[0] * (p0[0] + p1[0]) + nrm[1] * (p0[1] + p1[1]) < 0:
                nrm = (-nrm[0], -nrm[1])
            column = []
            for f in (0.0, 1.0):
                deg = s0[0] + (s1[0] - s0[0]) * f
                x = (deg - FOAM_FROM) / span
                lobe = 0.5 + 0.5 * math.cos(2.0 * math.pi * FOAM_SCALLOPS * x + phase)
                ends = math.sin(math.pi * min(max(x, 0.0), 1.0)) ** 0.5  # the cap thins off at both its ends
                depth = (FOAM_DEPTH[0] + (FOAM_DEPTH[1] - FOAM_DEPTH[0]) * lobe) * (0.45 + 0.55 * ends)
                pq = (p0[0] + dp * f + nrm[0] * CORE_LIFT, p0[1] + dq * f + nrm[1] * CORE_LIFT)
                top = core.vert(self.coil_point(COIL_LEN - FOAM_RIM, pq))
                low = core.vert(self.coil_point(COIL_LEN - FOAM_RIM - depth, pq))
                column.append((top, low))
            out = add(mul(self.coil[1], nrm[0]), mul(self.coil[2], nrm[1]))
            for (t0, l0), (t1, l1) in zip(column, column[1:]):
                core.tri(t0, t1, l1, out)
                core.tri(t0, l1, l0, out)

    def end_band(self, core: Mesh) -> None:
        """A pale band on the spiral's near end along the outer turn's upper side -- the foam seen end-on,
        at least 0.15 stud wide -- lifted off the end face, pigment on both its sides."""
        degs = [sm[0] for sm in self.coil_samples() if FOAM_FROM - 1e-6 <= sm[0] <= FOAM_TO + 1e-6]
        along = COIL_LEN + CORE_LIFT
        outer = [core.vert(self.coil_point(along, self.strip_at(d, BAND[1]))) for d in degs]
        inner = [core.vert(self.coil_point(along, self.strip_at(d, BAND[0]))) for d in degs]
        facing = self.coil[0]
        for j in range(len(degs) - 1):
            core.tri(outer[j], outer[j + 1], inner[j + 1], facing)
            core.tri(outer[j], inner[j + 1], inner[j], facing)


def _ear_clip(poly: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    """Triangles (index triples, counter-clockwise) filling a simple counter-clockwise polygon."""

    def cross2(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return cross2(a, b, p) > 0 and cross2(b, c, p) > 0 and cross2(c, a, p) > 0

    left = list(range(len(poly)))
    out = []
    while len(left) > 3:
        for k in range(len(left)):
            i, j, n = left[k - 1], left[k], left[(k + 1) % len(left)]
            a, b, c = poly[i], poly[j], poly[n]
            if cross2(a, b, c) <= 1e-12:
                continue
            if any(inside(poly[m], a, b, c) for m in left if m not in (i, j, n)):
                continue
            out.append((i, j, n))
            left.pop(k)
            break
        else:
            raise ValueError("not a simple polygon")
    out.append(tuple(left))
    return out


def _emit_inward(ink: Mesh, tris) -> None:
    """Emit a closed hull's triangles wound inward (turned inside out), whatever their given winding."""
    total = 0.0
    for a, b, c in tris:
        pa, pb, pc = ink.verts[a], ink.verts[b], ink.verts[c]
        total += dot(pa, cross(pb, pc)) / 6.0
    if total > 0:
        tris = [(a, c, b) for a, b, c in tris]
    for t in tris:
        emit(ink, *t)


_CACHE: dict = {}


def _build_at(r_foot: float, only: int | None):
    rng = Rng(SEED)
    body, core, ink = Mesh("up"), Mesh("up"), Mesh("up")
    leaves = []
    for k in range(LEAVES):
        leaf = Leaf(k, rng, r_foot)
        leaves.append(leaf)
        if only is not None and k != only:
            continue
        blade = leaf.build_blade()
        coil, hollow = leaf.build_coil()
        body.merge(blade.mesh)
        shell, dark = Mesh("up"), Mesh("up")
        shell.verts = dark.verts = coil.mesh.verts
        for index, t in enumerate(coil.mesh.tris):
            (dark if index in hollow else shell).tris.append(t)
        body.merge(shell)
        ink.merge(dark)
        leaf.blade_hull(ink)
        leaf.coil_hull(ink)
        leaf.veins(ink)
        leaf.foam(core)
        leaf.end_band(core)
    return body, core, ink, leaves


def build(only: int | None = None) -> tuple[Mesh, Mesh, Mesh]:
    """The three meshes, built once from one construction and normalised by one scale. The foot radius is
    solved first, so the outer ink lands on 16 studs before normalising (the scale is then ~1 and the
    studs above are true). `only` builds a single leaf at the same scale (a close-up, never shipped)."""
    key = ("meshes", only)
    if key in _CACHE:
        return _CACHE[key]
    if "r_foot" not in _CACHE:
        r_foot = 14.0
        for _ in range(4):
            body, core, ink, _ = _build_at(r_foot, None)
            reach = max(math.hypot(x, z) for mesh in (body, core, ink) for x, _, z in mesh.verts)
            r_foot += OUTER - reach
        _CACHE["r_foot"] = r_foot
        body, core, ink, _ = _build_at(r_foot, None)
        _CACHE["reach"] = max(math.hypot(x, z) for mesh in (body, core, ink) for x, _, z in mesh.verts)
    body, core, ink, _ = _build_at(_CACHE["r_foot"], only)
    scale = 0.5 / _CACHE["reach"]
    for mesh in (body, core, ink):
        mesh.scale(scale)
    _CACHE[key] = (body, core, ink)
    return _CACHE[key]


def meta(seed: int) -> dict:
    return {"Reference": "OuterDiameter", "Pivot": [0, 0, 0], "Axis": "Y", "Flat": False, "Seed": seed}


def scrollwork_body() -> tuple[Mesh, dict]:
    return build()[0], meta(SEED)


def scrollwork_core() -> tuple[Mesh, dict]:
    return build()[1], meta(SEED + 1)


def scrollwork_ink() -> tuple[Mesh, dict]:
    return build()[2], meta(SEED + 2)
