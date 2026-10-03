"""The volumes of phase 4 (D-114), one function per mesh. Each returns the mesh and its manifest entry.

Every shape is a brush stroke that has taken on thickness (art bible rule 9): an open circle, a ring
of two strokes, a splash crown with round beads, a sweep, and two torn scraps of paper.
The glyph bodies modelled as volumes have their own modules: the Wash's tidal wave (wave.py), the
Brand's fireball (fireball.py), and one module per glyph for the rest (D-278), each drawn after the
developer's references in docs/vfx/<glyph>/.
Sizes are in reference units -- the `Reference` extent is exactly 1 -- so the runtime scales a mesh in
studs of that extent, the way a texture is scaled by its plane. `Pivot` is the point the runtime
places, in the same units: the importer recentres a mesh on its bounding box, and the manifest's
bounds are what let the runtime put the pivot back.

Coordinates are Roblox's: X right, Y up, forward is -Z. Every flat mesh lies in the XZ plane.
"""

from __future__ import annotations

import math

import binding
import bleed
import blot
import caret
import cartouche
import colophon
import dagger
import emboss
import fireball
import gilding
import hairline
import hatching
import ligature
import margin
import pounce
import rubric
import rupture
import scorch
import serif
import spiral
import stipple
import stitch
import strike
import swash
import sweep
import volute
import watermark
import wave
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
    "ScrapA": ("paper_scrap_a.glb", scrap_a, 48),
    "ScrapB": ("paper_scrap_b.glb", scrap_b, 48),
    "WaveBody": ("ink_wave_body.glb", wave.wave_body, 1600),
    "WaveCrest": ("ink_wave_crest.glb", wave.wave_crest, 500),
    "WaveInk": ("ink_wave_ink.glb", wave.wave_ink, 1800),
    "FireBody": ("ink_fire_body.glb", fireball.fire_body, 1000),
    "FireCore": ("ink_fire_core.glb", fireball.fire_core, 300),
    "FireInk": ("ink_fire_ink.glb", fireball.fire_ink, 1000),
    "ScorchCrown": ("ink_scorch_crown.glb", scorch.scorch_crown, 1100),
    "ScorchCore": ("ink_scorch_core.glb", scorch.scorch_core, 300),
    "ScorchInk": ("ink_scorch_ink.glb", scorch.scorch_ink, 1200),
    "RuptureBody": ("ink_rupture_body.glb", rupture.downstroke_body, 1500),
    "RuptureCore": ("ink_rupture_core.glb", rupture.downstroke_core, 280),
    "RuptureInk": ("ink_rupture_ink.glb", rupture.downstroke_ink, 1750),
    "HairlineBlade": ("ink_hairline_blade.glb", hairline.wind_blade, 850),
    "HairlineEdge": ("ink_hairline_edge.glb", hairline.wind_edge, 100),
    "HairlineInk": ("ink_hairline_ink.glb", hairline.wind_ink, 900),
    "SerifBody": ("ink_serif_body.glb", serif.serif_body, 300),
    "SerifCore": ("ink_serif_core.glb", serif.serif_core, 60),
    "SerifInk": ("ink_serif_ink.glb", serif.serif_ink, 350),
    "EmbossBody": ("ink_emboss_body.glb", emboss.emboss_body, 1400),
    "EmbossBevel": ("ink_emboss_bevel.glb", emboss.emboss_bevel, 50),
    "EmbossInk": ("ink_emboss_ink.glb", emboss.emboss_ink, 1650),
    "GildingBody": ("ink_gilding_body.glb", gilding.irons_body, 950),
    "GildingCore": ("ink_gilding_core.glb", gilding.irons_core, 150),
    "GildingInk": ("ink_gilding_ink.glb", gilding.irons_ink, 1200),
    "PounceDunes": ("ink_pounce_dunes.glb", pounce.pounce_dunes, 1350),
    "PounceCrest": ("ink_pounce_crest.glb", pounce.pounce_crest, 100),
    "PounceInk": ("ink_pounce_ink.glb", pounce.pounce_ink, 1450),
    "BleedPool": ("ink_bleed_pool.glb", bleed.bleed_pool, 1100),
    "BleedSheen": ("ink_bleed_sheen.glb", bleed.bleed_sheen, 280),
    "BleedInk": ("ink_bleed_ink.glb", bleed.bleed_ink, 1400),
    "SweepBody": ("ink_sweep_body.glb", sweep.gust_body, 1000),
    "SweepCrest": ("ink_sweep_crest.glb", sweep.gust_crest, 250),
    "SweepInk": ("ink_sweep_ink.glb", sweep.gust_ink, 1200),
    "VoluteBody": ("ink_volute_body.glb", volute.volute_body, 500),
    "VoluteEye": ("ink_volute_eye.glb", volute.volute_eye, 200),
    "VoluteInk": ("ink_volute_ink.glb", volute.volute_ink, 750),
    "MarginBody": ("ink_margin_body.glb", margin.rule_body, 1100),
    "MarginLip": ("ink_margin_lip.glb", margin.rule_lip, 500),
    "MarginInk": ("ink_margin_ink.glb", margin.rule_ink, 1800),
    "LigatureBody": ("ink_ligature_body.glb", ligature.tie_body, 1550),
    "LigatureCore": ("ink_ligature_core.glb", ligature.tie_core, 350),
    "LigatureInk": ("ink_ligature_ink.glb", ligature.tie_ink, 1650),
    "StippleBody": ("ink_stipple_body.glb", stipple.mud_body, 950),
    "StippleGloss": ("ink_stipple_gloss.glb", stipple.mud_gloss, 150),
    "StippleInk": ("ink_stipple_ink.glb", stipple.mud_ink, 1000),
    "BlotTeardropBody": ("ink_blot_teardrop_body.glb", blot.teardrop_body, 750),
    "BlotTeardropCore": ("ink_blot_teardrop_core.glb", blot.teardrop_core, 100),
    "BlotTeardropInk": ("ink_blot_teardrop_ink.glb", blot.teardrop_ink, 1000),
    "BlotStarBody": ("ink_blot_star_body.glb", blot.blot_body, 850),
    "BlotStarCore": ("ink_blot_star_core.glb", blot.blot_core, 50),
    "BlotStarInk": ("ink_blot_star_ink.glb", blot.blot_ink, 900),
    "BindingCordsBody": ("ink_binding_cords_body.glb", binding.cords_body, 950),
    "BindingCordsFoam": ("ink_binding_cords_foam.glb", binding.cords_foam, 450),
    "BindingCordsInk": ("ink_binding_cords_ink.glb", binding.cords_ink, 1400),
    "HatchingCutBody": ("ink_hatching_cut_body.glb", hatching.hatch_body, 300),
    "HatchingCutCore": ("ink_hatching_cut_core.glb", hatching.hatch_core, 200),
    "HatchingCutInk": ("ink_hatching_cut_ink.glb", hatching.hatch_ink, 400),
    "HatchingLongBody": ("ink_hatching_long_body.glb", hatching.hatch_long_body, 300),
    "HatchingLongCore": ("ink_hatching_long_core.glb", hatching.hatch_long_core, 200),
    "HatchingLongInk": ("ink_hatching_long_ink.glb", hatching.hatch_long_ink, 400),
    "HatchingFinisherBody": ("ink_hatching_finisher_body.glb", hatching.hatch_finisher_body, 300),
    "HatchingFinisherCore": ("ink_hatching_finisher_core.glb", hatching.hatch_finisher_core, 250),
    "HatchingFinisherInk": ("ink_hatching_finisher_ink.glb", hatching.hatch_finisher_ink, 500),
    "DaggerObelusBody": ("ink_dagger_obelus_body.glb", dagger.obelus_body, 1000),
    "DaggerObelusCore": ("ink_dagger_obelus_core.glb", dagger.obelus_core, 150),
    "DaggerObelusInk": ("ink_dagger_obelus_ink.glb", dagger.obelus_ink, 950),
    "DaggerStrikeBody": ("ink_dagger_strike_body.glb", dagger.strike_body, 100),
    "DaggerStrikeCore": ("ink_dagger_strike_core.glb", dagger.strike_core, 100),
    "DaggerStrikeInk": ("ink_dagger_strike_ink.glb", dagger.strike_ink, 150),
    "SpiralBowl": ("ink_spiral_bowl.glb", spiral.spiral_bowl, 1800),
    "SpiralCore": ("ink_spiral_core.glb", spiral.spiral_core, 1800),
    "SpiralInk": ("ink_spiral_ink.glb", spiral.spiral_ink, 1800),
    "StitchLoopBody": ("ink_stitch_loop_body.glb", stitch.loop_body, 600),
    "StitchLoopCore": ("ink_stitch_loop_core.glb", stitch.loop_core, 100),
    "StitchLoopInk": ("ink_stitch_loop_ink.glb", stitch.loop_ink, 1000),
    "StitchShackleBody": ("ink_stitch_shackle_body.glb", stitch.shackle_body, 950),
    "StitchShackleCore": ("ink_stitch_shackle_core.glb", stitch.shackle_core, 50),
    "StitchShackleInk": ("ink_stitch_shackle_ink.glb", stitch.shackle_ink, 900),
    "ColophonBody": ("ink_colophon_body.glb", colophon.cadel_body, 550),
    "ColophonCore": ("ink_colophon_core.glb", colophon.cadel_core, 100),
    "ColophonInk": ("ink_colophon_ink.glb", colophon.cadel_ink, 600),
    "RubricBud": ("ink_rubric_bud.glb", rubric.rubric_bud, 950),
    "RubricHeart": ("ink_rubric_heart.glb", rubric.rubric_heart, 150),
    "RubricBudInk": ("ink_rubric_bud_ink.glb", rubric.rubric_bud_ink, 900),
    "RubricBar": ("ink_rubric_bar.glb", rubric.rubric_bar, 600),
    "RubricLobes": ("ink_rubric_lobes.glb", rubric.rubric_lobes, 100),
    "RubricBarInk": ("ink_rubric_bar_ink.glb", rubric.rubric_bar_ink, 600),
    "RubricHead": ("ink_rubric_head.glb", rubric.rubric_head, 400),
    "RubricHeadInk": ("ink_rubric_head_ink.glb", rubric.rubric_head_ink, 500),
    "CartoucheBody": ("ink_cartouche_body.glb", cartouche.scrollwork_body, 1750),
    "CartoucheCore": ("ink_cartouche_core.glb", cartouche.scrollwork_core, 500),
    "CartoucheInk": ("ink_cartouche_ink.glb", cartouche.scrollwork_ink, 1250),
    "CaretWideBody": ("ink_caret_wide_body.glb", caret.caret_wide_body, 450),
    "CaretWideCore": ("ink_caret_wide_core.glb", caret.caret_wide_core, 450),
    "CaretWideInk": ("ink_caret_wide_ink.glb", caret.caret_wide_ink, 450),
    "CaretRatureBody": ("ink_caret_rature_body.glb", caret.rature_body, 450),
    "CaretRatureCore": ("ink_caret_rature_core.glb", caret.rature_core, 450),
    "CaretRatureInk": ("ink_caret_rature_ink.glb", caret.rature_ink, 450),
    "StrikeBand": ("ink_strike_band.glb", strike.rature_band, 450),
    "StrikeSpine": ("ink_strike_spine.glb", strike.rature_spine, 450),
    "StrikeInk": ("ink_strike_ink.glb", strike.rature_ink, 450),
    "SwashBody": ("ink_swash_body.glb", swash.swash_body, 1550),
    "SwashEdge": ("ink_swash_edge.glb", swash.swash_edge, 200),
    "SwashInk": ("ink_swash_ink.glb", swash.swash_ink, 1800),
    "SwashSlumpBody": ("ink_swash_slump_body.glb", swash.swash_slump_body, 1400),
    "SwashSlumpEdge": ("ink_swash_slump_edge.glb", swash.swash_slump_edge, 100),
    "SwashSlumpInk": ("ink_swash_slump_ink.glb", swash.swash_slump_ink, 1450),
    "WatermarkWire": ("ink_watermark_wire.glb", watermark.watermark_wire, 1800),
    "WatermarkGleam": ("ink_watermark_gleam.glb", watermark.watermark_gleam, 450),
    "WatermarkInk": ("ink_watermark_ink.glb", watermark.watermark_ink, 1250),
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
