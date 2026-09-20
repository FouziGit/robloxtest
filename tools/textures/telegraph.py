"""The four telegraph textures: the only textures in Vellum whose edge is a rule.

L'Effacement's attacks paint the floor the server will damage, and six players read that paint to decide
where to stand. Every other texture here stops its ink well inside its own plane -- the blot at six
tenths of the half-width, the shockwave stroke at eight -- because a residue with a hard edge is a
sticker and a wave with a hard edge is a hoop. A warning is the opposite case. The plane is sized to the
damage, so the ink has to reach the plane: a telegraph drawn with the blot would warn about six tenths
of the floor, and tests/BossTelegraph.spec.luau, which measures the paint against WorldBossConfig, only
means something if the ink it measures goes where the plane goes.

So none of these fade their border, and each is measured by vellum_png.ink_reach before it ships:

  telegraph_disc   a disc of flooding ink, ragged inside and exact at its rim         reaches 1.00
  telegraph_ring   one stroke on the rim, hard on the outside, feathered inward       reaches 1.00
  telegraph_bar    a full-bleed bar of ink, denser toward its two long edges           reaches 1.00 / 1.41
  telegraph_page   a disc of bare page, the one thing the Erasure does not touch      reaches 1.00

The inside is still ink and still paper: value noise rather than flat alpha, so the warning reads as
something spilled and not as a coloured circle laid over the world.

    python3 tools/textures/telegraph.py
"""

from __future__ import annotations

import math
from pathlib import Path

from vellum_png import Canvas, circle_noise, fbm, output_dir, report, smootherstep01, write_white_alpha

SIZE = 512
BAR_SIZE = 256
SEED = 0x7E_1E

# The rim is the rule: the edge sits half a pixel inside the half-width and anti-aliases over one and a
# half pixels, so the last pixel of the plane carries the tail of the ink and nothing runs past it.
# vellum_png.ink_reach measures 0.998 least and 1.004 most; the telegraph test allows two pixels.
EDGE_INSET = 0.5
EDGE_AA = 1.5

# The disc's interior: a floor of alpha plus flooding noise, and a denser band inside the rim so the
# boundary is the darkest thing about it -- it is the boundary a player has to read.
DISC_FLOOR = 0.58
DISC_NOISE = 0.34
DISC_RIM_BAND = 0.09
DISC_RIM_GAIN = 0.32
DISC_NOISE_CELLS = 5

# The ring's stroke, as fractions of the half-width: the outside edge is exact and the inside feathers.
RING_INNER = 0.88
RING_INNER_FEATHER = 0.06
RING_WOBBLE = 0.012

# The bar: full bleed, with the ink gathering toward the two long edges the way a brush loads at the
# sides of a wide stroke, and a dry streak of noise down the middle.
BAR_FLOOR = 0.62
BAR_NOISE = 0.30
BAR_EDGE_GAIN = 0.26
BAR_NOISE_CELLS = 4

# The page disc: paper grain at an opacity a refuge can be read at. paper.py keeps the world's own veil
# under a quarter; this is a shape on the floor, and a shape under half opacity is not a shape.
PAGE_FLOOR = 0.72
PAGE_GRAIN = 0.22
PAGE_FIBRE_CELLS = 10


def _disc_edge(px: float, py: float, half: float) -> float:
    """1 inside the disc, 0 outside, anti-aliased across EDGE_AA pixels at half - EDGE_INSET."""
    return smootherstep01((half - EDGE_INSET - math.hypot(px, py)) / EDGE_AA + 0.5)


def _build_disc() -> Canvas:
    half = SIZE * 0.5
    scale = DISC_NOISE_CELLS / SIZE

    def sample(x: int, y: int) -> float:
        px = x + 0.5 - half
        py = y + 0.5 - half
        edge = _disc_edge(px, py, half)
        if edge <= 0.0:
            return 0.0
        flood = fbm(x * scale, y * scale, SEED, octaves=4)
        value = DISC_FLOOR + DISC_NOISE * flood
        # The rim band, ragged on its inner side by the same noise that floods the interior.
        inner = half * (1.0 - DISC_RIM_BAND * (0.7 + 0.6 * flood))
        value += DISC_RIM_GAIN * smootherstep01((math.hypot(px, py) - inner) / (half - inner))
        return min(value, 1.0) * edge

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    return canvas


def _build_ring() -> Canvas:
    half = SIZE * 0.5

    def sample(x: int, y: int) -> float:
        px = x + 0.5 - half
        py = y + 0.5 - half
        edge = _disc_edge(px, py, half)
        if edge <= 0.0:
            return 0.0
        distance = math.hypot(px, py) / half
        wobble = RING_WOBBLE * (circle_noise(math.atan2(py, px), SEED + 7) * 2.0 - 1.0)
        inner = RING_INNER + wobble
        return smootherstep01((distance - inner) / RING_INNER_FEATHER) * edge

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    return canvas


def _build_bar() -> Canvas:
    scale = BAR_NOISE_CELLS / BAR_SIZE

    def sample(x: int, y: int) -> float:
        # Across is x. The two long edges of the bar are x = 0 and x = BAR_SIZE, where the wedge's
        # boundary is, so the ink loads there.
        across = abs((x + 0.5) / BAR_SIZE * 2.0 - 1.0)
        ink = fbm(x * scale, y * scale, SEED + 13, octaves=4)
        value = BAR_FLOOR + BAR_NOISE * ink + BAR_EDGE_GAIN * smootherstep01((across - 0.55) / 0.45)
        return min(value, 1.0)

    canvas = Canvas(BAR_SIZE, BAR_SIZE)
    canvas.fill_from(sample)
    return canvas


def _build_page() -> Canvas:
    half = SIZE * 0.5
    scale = PAGE_FIBRE_CELLS / SIZE

    def sample(x: int, y: int) -> float:
        px = x + 0.5 - half
        py = y + 0.5 - half
        edge = _disc_edge(px, py, half)
        if edge <= 0.0:
            return 0.0
        grain = fbm(x * scale, y * scale, SEED + 29, octaves=4)
        return (PAGE_FLOOR + PAGE_GRAIN * grain) * edge

    canvas = Canvas(SIZE, SIZE)
    canvas.fill_from(sample)
    return canvas


def generate() -> list[Path]:
    out = output_dir()
    return [
        write_white_alpha(out / "telegraph_disc.png", _build_disc()),
        write_white_alpha(out / "telegraph_ring.png", _build_ring()),
        write_white_alpha(out / "telegraph_bar.png", _build_bar()),
        write_white_alpha(out / "telegraph_page.png", _build_page()),
    ]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
