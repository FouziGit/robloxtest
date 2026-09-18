"""Shared maths and the PNG writer for the Vellum texture pipeline.

Standard library only, on purpose. These generators are the only source of art in the project --
docs/ART_BIBLE.md rules out toolbox models and hand-painted textures, so every mark on screen is
either primitive geometry, light, or one of the PNGs written here -- and a pipeline that needs
`pip install` before it can rebuild an asset is a pipeline that breaks the first time nobody
remembers which version of Pillow it was. No third-party import appears in this directory even
though several are installed on this machine.

The writer emits exactly one format: 8-bit RGBA, non-interlaced, RGB pinned to white, the entire
image carried in the alpha channel. That is not a shortcut, it is art bible rule 2 -- one glyph is
one pigment is one colour -- so a texture ships once and is tinted five ways through
ParticleEmitter.Color or ImageLabel.ImageColor3. Five pigment-coloured copies of every asset would be
five times the download and five chances for one of them to drift off the palette.
"""

from __future__ import annotations

import hashlib
import math
import struct
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MASK64 = (1 << 64) - 1

# Per-file ceiling. A texture is downloaded by every client on join, and art bible rule 8 caps what
# the game is allowed to cost to display; an asset that blows the budget is reduced, not shipped.
MAX_BYTES = 400 * 1024


def output_dir() -> Path:
    """assets/textures, resolved from this file so any working directory works."""
    path = Path(__file__).resolve().parents[2] / "assets" / "textures"
    path.mkdir(parents=True, exist_ok=True)
    return path


class Rng:
    """SplitMix64.

    Not random.Random: the Mersenne Twister stream is stable in practice but is not a documented
    guarantee across interpreters, and these eight lines are. Every generator seeds this explicitly,
    because a generator whose output moves between runs turns every commit into an unreviewable
    binary diff.
    """

    __slots__ = ("_state",)

    def __init__(self, seed: int) -> None:
        self._state = seed & MASK64

    def next_u64(self) -> int:
        self._state = (self._state + 0x9E3779B97F4A7C15) & MASK64
        z = self._state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return (z ^ (z >> 31)) & MASK64

    def random(self) -> float:
        # Top 53 bits, the same construction CPython uses, so the value is exactly representable.
        return (self.next_u64() >> 11) * (1.0 / (1 << 53))

    def uniform(self, low: float, high: float) -> float:
        return low + (high - low) * self.random()


# --- Curves ---------------------------------------------------------------------------------------
# Art bible rule 4: nothing moves linearly. It applies to a gradient too -- a linear ramp shows a
# visible boundary where it meets flat colour (Mach banding), which is why smootherstep and not `t`
# is the default falloff everywhere below.


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    if value < low:
        return low
    if value > high:
        return high
    return value


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def smootherstep01(t: float) -> float:
    """Ken Perlin's quintic: zero first AND second derivative at both ends, so a falloff built on it
    leaves no ring where it reaches zero."""
    t = clamp(t)
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


Point = tuple[float, float]


def distance_to_segment(point: Point, a: Point, b: Point) -> tuple[float, float]:
    """Returns (projection parameter clamped to the segment, distance to it)."""
    px, py = point
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length_squared = dx * dx + dy * dy
    if length_squared <= 0.0:
        return 0.0, math.hypot(px - ax, py - ay)
    t = clamp(((px - ax) * dx + (py - ay) * dy) / length_squared)
    return t, math.hypot(px - (ax + dx * t), py - (ay + dy * t))


# --- Noise ----------------------------------------------------------------------------------------


def _lattice(ix: int, iy: int, seed: int) -> float:
    """Hashed value at an integer lattice point, 0..1. Hashing instead of storing a table is what
    makes `period` possible at no cost: wrapping the indices is all a seamless tile needs."""
    h = (ix * 0x27D4EB2F + iy * 0x165667B1 + seed * 0x9E3779B1) & MASK64
    h ^= h >> 15
    h = (h * 0x2545F4914F6CDD1D) & MASK64
    h ^= h >> 17
    return (h >> 11) * (1.0 / (1 << 53))


def value_noise(x: float, y: float, seed: int, period: int | None = None) -> float:
    """Value noise in lattice units -- one unit is one cell, so the caller scales pixels to cells.

    `period` wraps the lattice, which is the only way to get a texture that tiles: sampling a
    non-periodic field and hoping the seam is invisible fails on a floor made of a hundred copies.
    """
    ix = math.floor(x)
    iy = math.floor(y)
    u = smootherstep01(x - ix)
    v = smootherstep01(y - iy)
    x0, y0 = int(ix), int(iy)
    x1, y1 = x0 + 1, y0 + 1
    if period is not None:
        x0 %= period
        y0 %= period
        x1 %= period
        y1 %= period
    top = lerp(_lattice(x0, y0, seed), _lattice(x1, y0, seed), u)
    bottom = lerp(_lattice(x0, y1, seed), _lattice(x1, y1, seed), u)
    return lerp(top, bottom, v)


def fbm(x: float, y: float, seed: int, octaves: int = 4, period: int | None = None) -> float:
    """Fractal sum, lacunarity 2 and gain 0.5, normalised to 0..1.

    Octave `n` samples a lattice `2**n` times finer, so a tiling field needs its period doubled in
    step -- which means the caller's base period must stay a divisor of the image size through the
    last octave (8 -> 16 -> 32 -> 64 all divide 512).
    """
    total = 0.0
    amplitude = 1.0
    normal = 0.0
    frequency = 1
    for octave in range(octaves):
        octave_period = None if period is None else period * frequency
        total += amplitude * value_noise(x * frequency, y * frequency, seed + octave * 1013, octave_period)
        normal += amplitude
        amplitude *= 0.5
        frequency *= 2
    return total / normal


# --- Canvas ---------------------------------------------------------------------------------------


class Canvas:
    """A single-channel float image, 0..1, which becomes the alpha of the written PNG."""

    __slots__ = ("width", "height", "data")

    def __init__(self, width: int, height: int, value: float = 0.0) -> None:
        self.width = width
        self.height = height
        self.data = [value] * (width * height)

    def max_at(self, x: int, y: int, value: float) -> None:
        """Strokes composite by maximum, never by sum: added strokes turn every junction of a crack
        web into a bright blob, which is the tell of a procedural texture."""
        index = y * self.width + x
        if value > self.data[index]:
            self.data[index] = value

    def fill_from(self, sample) -> None:
        """sample(x, y) -> 0..1 for every pixel. Slow per pixel and clear to read; at these sizes the
        whole pipeline still runs in seconds, and it only ever runs by hand."""
        data = self.data
        index = 0
        for y in range(self.height):
            for x in range(self.width):
                data[index] = sample(x, y)
                index += 1

    def fade_border(self, margin: float) -> None:
        """Forces alpha to zero at the outside edge.

        A particle texture with non-zero alpha on its border shows a hard straight cut where the
        sprite ends, and inside a flipbook sheet it bleeds into the neighbouring frame, which reads
        as a flicker at the exact moment the explosion is loudest.
        """
        if margin <= 0.0:
            return
        data = self.data
        columns = [smootherstep01(min(x + 0.5, self.width - 0.5 - x) / margin) for x in range(self.width)]
        for y in range(self.height):
            row_fade = smootherstep01(min(y + 0.5, self.height - 0.5 - y) / margin)
            if row_fade >= 1.0:
                offset = y * self.width
                for x in range(self.width):
                    column_fade = columns[x]
                    if column_fade < 1.0:
                        data[offset + x] *= column_fade
                continue
            offset = y * self.width
            for x in range(self.width):
                data[offset + x] *= row_fade * columns[x]

    def blit(self, other: Canvas, origin_x: int, origin_y: int) -> None:
        """Copies `other` in. Used to lay flipbook frames into their cells; a copy rather than a
        blend because two frames must never overlap.

        Bounds are asserted rather than clamped. A flat list plus a computed offset fails silently in
        both directions -- a row that runs past the right edge wraps onto the next row's left edge, and
        a negative origin writes from the end of the list -- and the only symptom is a flipbook whose
        frames bleed into each other, which reads as a flicker at the exact moment the explosion is
        loudest. This is a build-time script with no user, so raising is the right answer.
        """
        if origin_x < 0 or origin_y < 0:
            raise ValueError(f"blit origin ({origin_x}, {origin_y}) is negative")
        if origin_x + other.width > self.width or origin_y + other.height > self.height:
            raise ValueError(
                f"blit of {other.width}x{other.height} at ({origin_x}, {origin_y}) "
                f"does not fit in {self.width}x{self.height}"
            )
        for y in range(other.height):
            source = y * other.width
            target = (origin_y + y) * self.width + origin_x
            self.data[target : target + other.width] = other.data[source : source + other.width]

    def to_alpha_bytes(self) -> bytes:
        """Rounds to 8-bit alpha. Values outside 0..1 are clipped here rather than by every caller,
        because compositing by maximum and stamping strengths make overshoot normal and harmless."""
        out = bytearray(len(self.data))
        for index, value in enumerate(self.data):
            if value <= 0.0:
                continue
            out[index] = 255 if value >= 1.0 else int(value * 255.0 + 0.5)
        return bytes(out)


def box_blur(canvas: Canvas, radius: int, passes: int = 1, wrap: bool = False) -> Canvas:
    """Separable running-sum blur. Three passes of a box are a Gaussian to the eye and cost the same
    as one, because the window slides instead of summing. `wrap` is mandatory for a tileable texture:
    a clamped blur flattens the outer `radius` pixels and breaks the seam it was meant to hide."""
    result = Canvas(canvas.width, canvas.height)
    result.data = list(canvas.data)
    for _ in range(passes):
        for y in range(canvas.height):
            offset = y * canvas.width
            row = _blur_line(result.data[offset : offset + canvas.width], radius, wrap)
            result.data[offset : offset + canvas.width] = row
        for x in range(canvas.width):
            column = _blur_line(result.data[x :: canvas.width], radius, wrap)
            result.data[x :: canvas.width] = column
    return result


def _blur_line(values: list[float], radius: int, wrap: bool) -> list[float]:
    count = len(values)
    window = 2 * radius + 1
    out = [0.0] * count
    if wrap:
        total = sum(values[index % count] for index in range(-radius, radius + 1))
        for index in range(count):
            out[index] = total / window
            total += values[(index + radius + 1) % count] - values[(index - radius) % count]
        return out
    total = values[0] * radius + sum(values[: radius + 1])
    last = count - 1
    for index in range(count):
        out[index] = total / window
        total += values[min(index + radius + 1, last)] - values[max(index - radius, 0)]
    return out


# --- Drawing --------------------------------------------------------------------------------------

STROKE_FEATHER = 1.0


def stamp_radial(canvas: Canvas, center: Point, radius: float, strength: float = 1.0) -> None:
    """A soft dot. The building block of every puff, droplet and spatter in the pipeline."""
    cx, cy = center
    x_low = max(0, int(cx - radius) - 1)
    x_high = min(canvas.width - 1, int(cx + radius) + 1)
    y_low = max(0, int(cy - radius) - 1)
    y_high = min(canvas.height - 1, int(cy + radius) + 1)
    for y in range(y_low, y_high + 1):
        for x in range(x_low, x_high + 1):
            distance = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            value = smootherstep01(1.0 - distance / radius) * strength
            if value > 0.0:
                canvas.max_at(x, y, value)


def draw_segment(canvas: Canvas, a: Point, b: Point, widths: Point, strength: float = 1.0) -> None:
    """One anti-aliased stroke of varying half-width, from `widths[0]` at `a` to `widths[1]` at `b`.

    Every drawn line in the pipeline -- cracks, seal rings, tick marks -- is a chain of these, so the
    taper lives here rather than in each generator.
    """
    widest = max(widths) + STROKE_FEATHER + 1.0
    x_low = max(0, int(min(a[0], b[0]) - widest))
    x_high = min(canvas.width - 1, int(max(a[0], b[0]) + widest))
    y_low = max(0, int(min(a[1], b[1]) - widest))
    y_high = min(canvas.height - 1, int(max(a[1], b[1]) + widest))
    for y in range(y_low, y_high + 1):
        for x in range(x_low, x_high + 1):
            t, distance = distance_to_segment((x + 0.5, y + 0.5), a, b)
            half_width = lerp(widths[0], widths[1], t)
            value = smootherstep01((half_width - distance) / STROKE_FEATHER) * strength
            if value > 0.0:
                canvas.max_at(x, y, value)


def circle_noise(angle: float, seed: int, radius: float = 2.0, octaves: int = 3) -> float:
    """Noise sampled along a circle in the lattice, so it closes on itself at angle 0.

    Feeding the angle straight into a 1-D noise leaves a visible discontinuity at -pi, which on a
    blot or a ring is a straight scar pointing left.
    """
    return fbm(math.cos(angle) * radius + 8.0, math.sin(angle) * radius + 8.0, seed, octaves=octaves)


# --- PNG ------------------------------------------------------------------------------------------


def _chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def write_white_alpha(path: Path, canvas: Canvas) -> Path:
    """Writes the canvas as white RGB plus alpha, filter type Sub on every scanline.

    Sub subtracts the pixel four bytes to the left, which turns the three constant white channels
    into runs of zero bytes and the alpha channel into small deltas -- so the filter is chosen here
    rather than searched per line, and the files land small enough to commit without a build step.
    """
    alpha = canvas.to_alpha_bytes()
    width, height = canvas.width, canvas.height
    raw = bytearray()
    for y in range(height):
        row = alpha[y * width : (y + 1) * width]
        line = bytearray(1 + width * 4)
        line[0] = 1
        # The leftmost pixel has no left neighbour, so it keeps absolute values.
        line[1] = 255
        line[2] = 255
        line[3] = 255
        line[4] = row[0]
        previous = row[0]
        offset = 8
        for x in range(1, width):
            value = row[x]
            line[offset] = (value - previous) & 0xFF
            previous = value
            offset += 4
        raw += line
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        PNG_SIGNATURE
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )
    return path


def read_dimensions(path: Path) -> tuple[int, int]:
    """Reads width and height back out of IHDR, so verification measures the file rather than
    repeating what the generator meant to write."""
    head = path.read_bytes()[:24]
    if head[:8] != PNG_SIGNATURE:
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", head[16:24])


def report(paths: list[Path]) -> int:
    """Prints one line per written file and returns how many broke MAX_BYTES.

    The dimensions come from the file's own IHDR and the digest from its bytes, so running a generator
    twice and diffing this table is the whole determinism check -- which is the point of seeding every
    random source explicitly in the first place.
    """
    over_budget = 0
    for path in paths:
        width, height = read_dimensions(path)
        size = path.stat().st_size
        digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
        flag = ""
        if size > MAX_BYTES:
            over_budget += 1
            flag = f"  OVER BUDGET ({MAX_BYTES} bytes)"
        print(f"{path.name:<26} {width:>5}x{height:<5} {size:>8} bytes  {digest}{flag}")
    return over_budget
