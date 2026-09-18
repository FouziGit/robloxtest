"""The explosion flipbook: an ink bloom that opens, tears and disperses, as an 8x8 sheet.

Roblox reads FlipbookLayout.Grid8x8 left to right then top to bottom, so frame n lives at column
n % 8, row n // 8, and that ordering is the only thing in this file that is not a taste decision.

The bloom is not a fireball. docs/ART_BIBLE.md puts the world at low saturation and every saturated
pixel inside a glyph, so the explosion that belongs to that world is ink hitting water: a dense core
that opens into a shell, the shell torn into wedges as it expands, and the wedges thinning out. The
sprite is white, so the same sheet is a Cinnabar detonation and an Indigo one depending on the emitter
that plays it.

Cost is why the shape comes from two angular lookup tables rather than from noise sampled per pixel.
A million pixels times an fbm is minutes; the same picture out of a 512-entry table is seconds, and
the table is the same function -- it is sampled around a circle, so it closes on itself exactly.

Each frame is drawn on its own 128-pixel canvas, blurred, faded at its border and then copied into the
sheet. That border fade is not cosmetic: bleed across a cell boundary shows up in game as the next
frame flickering at the edge of this one, at the loudest moment of the effect.

    python3 tools/textures/explosion.py
"""

from __future__ import annotations

import math
from collections import namedtuple
from pathlib import Path

from vellum_png import (
    Canvas,
    Rng,
    box_blur,
    circle_noise,
    lerp,
    output_dir,
    report,
    smootherstep01,
    stamp_radial,
    write_white_alpha,
)

GRID = 8
FRAME_SIZE = 128
SHEET_SIZE = GRID * FRAME_SIZE
FRAME_COUNT = GRID * GRID
SEED = 0xE8_00
TAU = 2.0 * math.pi

# Largest the shell may get. Lobes take it to 1.12x and spatter another 1.12x on top, which puts the
# furthest ink at 59 pixels of a 64-pixel half-frame -- inside the border fade, so nothing ever
# reaches the cell wall.
MAX_RADIUS = FRAME_SIZE * 0.34
FRAME_MARGIN = 4.0

# The first frame is a dense dot, not an empty canvas: art bible rule 3 says nothing appears, so even
# frame zero has to be something growing.
FIRST_RADIUS = 0.16
# 1 - (1 - t) ** 2.6: most of the growth happens in the first third. An explosion that expands evenly
# across its frames looks like a balloon inflating.
OPEN_POWER = 2.6

# The hole opens later than the shell and never catches it, so there is always a wall of ink.
HOLE_START = 0.26
HOLE_MAX = 0.70

# The tear threshold rises through the noise field, cutting the shell into fewer and fewer surviving
# wedges. It starts below the field's floor so the early frames are solid.
TEAR_START = 0.36
TEAR_FLOOR = -0.30
TEAR_MAX = 0.48
TEAR_SOFTNESS = 0.17
# The surviving wedges drift a fifth of a turn over the sheet. Ink dispersing does not hold still, and
# wedges pinned to fixed angles make the last third of the animation look like a stencil.
SWIRL = 0.62

# Global thinning, held back until the last quarter so that all sixty-four cells carry something. Every
# empty frame is a frame of the sheet paid for and not used, and three of them in a row is the effect
# ending early no matter what lifetime the emitter is given.
FADE_START = 0.78
FADE_DEPTH = 0.82

# Edge softness, in pixels plus a share of the current radius: a small bloom with a ten-pixel feather
# is all feather. Both shares are small for a second reason -- late in the animation the shell is only
# a fifth of the radius thick, and two feathers wider than the wall they sit on cancel each other out
# and leave the last frames blank.
FEATHER_OUT = 2.0
FEATHER_OUT_SHARE = 0.10
FEATHER_IN = 3.5
FEATHER_IN_SHARE = 0.10

# Lobes are nearly at full depth from the first frame. Ramping them up with time instead gives a
# perfectly round dot for the first ten frames, and a round dot is a bubble, not a drop of ink.
LOBE_DEPTH = 0.30
ANGLE_STEPS = 512
SPATTER_COUNT = 9

Droplet = namedtuple("Droplet", "angle start lead size")


def _angular_table(seed: int, radius: float) -> list[float]:
    step = TAU / ANGLE_STEPS
    return [circle_noise(index * step, seed, radius=radius) for index in range(ANGLE_STEPS)]


def _sample_table(table: list[float], angle: float) -> float:
    position = (angle % TAU) / TAU * ANGLE_STEPS
    low = int(position)
    return lerp(table[low % ANGLE_STEPS], table[(low + 1) % ANGLE_STEPS], position - low)


def _spatter(rng: Rng) -> list[Droplet]:
    """Droplets thrown clear of the shell. Angles are spread and then jittered rather than drawn at
    random, so none of them overlap into a single lump."""
    return [
        Droplet(
            angle=(index + rng.uniform(0.15, 0.85)) * (TAU / SPATTER_COUNT),
            start=rng.uniform(0.10, 0.34),
            lead=rng.uniform(0.04, 0.12),
            size=rng.uniform(2.2, 4.4),
        )
        for index in range(SPATTER_COUNT)
    ]


def _build_frame(step: int, tables: tuple[list[float], list[float]], droplets: list[Droplet]) -> Canvas:
    lobes, tears = tables
    t = step / (FRAME_COUNT - 1)
    half = FRAME_SIZE * 0.5
    opening = 1.0 - (1.0 - t) ** OPEN_POWER
    outer = MAX_RADIUS * (FIRST_RADIUS + (1.0 - FIRST_RADIUS) * opening)
    hole = outer * HOLE_MAX * smootherstep01((t - HOLE_START) / (1.0 - HOLE_START))
    tear_level = lerp(TEAR_FLOOR, TEAR_MAX, smootherstep01((t - TEAR_START) / (1.0 - TEAR_START)))
    fade = 1.0 - FADE_DEPTH * smootherstep01((t - FADE_START) / (1.0 - FADE_START))
    lobe_gain = LOBE_DEPTH * (0.85 + 0.15 * t)
    feather_out = FEATHER_OUT + outer * FEATHER_OUT_SHARE
    feather_in = FEATHER_IN + hole * FEATHER_IN_SHARE
    reject = outer * (1.0 + lobe_gain) + feather_out + 1.0

    def sample(x: int, y: int) -> float:
        px = x + 0.5 - half
        py = y + 0.5 - half
        distance = math.hypot(px, py)
        if distance > reject:
            return 0.0
        angle = math.atan2(py, px)
        edge = outer * (1.0 + lobe_gain * (_sample_table(lobes, angle) - 0.5))
        value = smootherstep01((edge - distance) / feather_out)
        if value <= 0.0:
            return 0.0
        if hole > 0.0:
            value *= smootherstep01((distance - hole) / feather_in)
        torn = _sample_table(tears, angle + SWIRL * t)
        value *= smootherstep01((torn - tear_level) / TEAR_SOFTNESS)
        return value * fade

    frame = Canvas(FRAME_SIZE, FRAME_SIZE)
    frame.fill_from(sample)

    for droplet in droplets:
        if t < droplet.start:
            continue
        travel = (t - droplet.start) / (1.0 - droplet.start)
        distance = outer * (1.0 + droplet.lead * travel)
        strength = fade * (1.0 - travel) ** 0.7
        centre = (half + math.cos(droplet.angle) * distance, half + math.sin(droplet.angle) * distance)
        stamp_radial(frame, centre, droplet.size * (1.0 - 0.5 * travel), strength)

    frame = box_blur(frame, radius=1, passes=1)
    frame.fade_border(FRAME_MARGIN)
    return frame


def _build() -> Canvas:
    tables = (_angular_table(SEED, 2.0), _angular_table(SEED + 13, 3.5))
    droplets = _spatter(Rng(SEED + 77))
    sheet = Canvas(SHEET_SIZE, SHEET_SIZE)
    for step in range(FRAME_COUNT):
        frame = _build_frame(step, tables, droplets)
        sheet.blit(frame, (step % GRID) * FRAME_SIZE, (step // GRID) * FRAME_SIZE)
    return sheet


def generate() -> list[Path]:
    return [write_white_alpha(output_dir() / "explosion_flipbook.png", _build())]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
