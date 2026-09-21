"""The three loops: the hub, the match, and the Erasure.

Generated, like everything else, so their licence is this file. They are drones with plucks rather
than songs, because a battleground's music is heard for hours under a hundred other sounds, and a
melody heard for hours is a melody hated by the second one. The same root as the sequence notes
(kit.ROOT, A3) and the same pentatonic, so a sequence played over the music is in tune with it: the
plan's "la séquence devient musicale" is only true if the two agree on a key.

Each loop is made seamless by blending its tail into its head (vellum_wav.loopable) and is not
declicked -- a fade to zero at the loop point is a gap every twenty-four seconds -- and rendered at
16 kHz: a drone has nothing above eight kilohertz worth the largest download the client makes.

    python3 tools/audio/music.py
"""

from __future__ import annotations

from pathlib import Path

from vellum_wav import (
    RATE_MUSIC as R,
    Buf,
    Rng,
    bandpass,
    crackle,
    echo,
    env_ad,
    loopable,
    lowpass,
    noise,
    normalize,
    output_dir,
    pluck,
    report,
    semitone,
    soft_clip,
    tone,
    tremolo,
    write_wav,
)

SEED = 0x30_5E
ROOT = 220.0
LENGTH = 26.0
CROSSFADE = 2.0

# The pentatonic the sequence climbs, as semitones from the root, over two octaves.
PENTATONIC = (0, 2, 4, 7, 9, 12, 14, 16, 19, 21)


def drone(seconds: float, freq: float, gain: float, breadth: float) -> Buf:
    """Three detuned partial stacks, so the drone moves without anything in it moving."""
    out = Buf(R, seconds)
    for detune, g in ((1.0, 1.0), (1.0 + breadth, 0.6), (1.0 - breadth, 0.6)):
        out.add(tone(R, seconds, freq * detune, freq * detune, ((1.0, 1.0), (2.0, 0.35), (3.0, 0.12), (0.5, 0.5))), 0.0, g)
    return lowpass(out, 900.0).scale(gain)


def sparse_plucks(rng: Rng, seconds: float, count: int, octave: int, brightness: float, gain: float, low: float = 0.0) -> Buf:
    """Notes of the pentatonic at unrepeating times, never two within the same second, so the loop
    has no bar to count and nothing to anticipate."""
    out = Buf(R, seconds)
    times: list[float] = []
    while len(times) < count:
        t = rng.uniform(0.5, seconds - 2.5)
        if all(abs(t - other) > 1.0 for other in times):
            times.append(t)
    times.sort()
    for t in times:
        step = PENTATONIC[int(rng.random() * len(PENTATONIC))] + 12 * octave
        length = rng.uniform(1.6, 2.4)
        note = pluck(R, length, ROOT * semitone(step) * (0.5 if low > rng.random() else 1.0), brightness, rng).apply(env_ad(R, length, 0.002, 0.55))
        out.add(note, t, gain * rng.uniform(0.6, 1.0))
    return out


def hub(rng: Rng) -> Buf:
    """Calm. The page at rest: a low drone, a slow breath of air across it, and a pluck now and then."""
    out = Buf(R, LENGTH)
    out.add(drone(LENGTH, ROOT * 0.5, 0.5, 0.004), 0.0, 1.0)
    breath = lowpass(noise(rng, R, LENGTH), 500.0).apply(tremolo(R, LENGTH, 0.09, 0.85))
    out.add(breath, 0.0, 0.06)
    out.add(sparse_plucks(rng, LENGTH, 9, 1, 0.45, 0.35, 0.3), 0.0, 1.0)
    return normalize(loopable(echo(out, 0.37, 0.35, 0.3), CROSSFADE), 0.8)


def match(rng: Rng) -> Buf:
    """Tense. The same drone a fifth up with a pulse under it -- a heartbeat, not a drum kit -- and
    plucks that come closer together."""
    out = Buf(R, LENGTH)
    out.add(drone(LENGTH, ROOT * 0.5 * semitone(7), 0.4, 0.006), 0.0, 1.0)
    beat = 0.6
    t = 0.0
    while t < LENGTH - 0.3:
        thump = tone(R, 0.25, 62.0, 40.0).apply(env_ad(R, 0.25, 0.002, 0.06))
        out.add(thump, t, 0.55)
        out.add(thump, t + 0.17, 0.3)
        t += beat
    out.add(sparse_plucks(rng, LENGTH, 16, 1, 0.65, 0.3), 0.0, 1.0)
    grain = crackle(rng, R, LENGTH, 6.0, 0.003, 0.0)
    out.add(bandpass(grain, 1800.0, 1.0), 0.0, 0.25)
    return normalize(loopable(echo(out, 0.3, 0.3, 0.25), CROSSFADE), 0.8)


def boss(rng: Rng) -> Buf:
    """The Erasure. A drone an octave below the hub's, a tone that rises a tritone and falls back over
    the loop, and a dry crackle: the page drying out under something that is not ink."""
    out = Buf(R, LENGTH)
    out.add(drone(LENGTH, ROOT * 0.25, 0.7, 0.008), 0.0, 1.0)
    half = LENGTH * 0.5
    out.add(tone(R, half, ROOT * 0.5, ROOT * 0.5 * semitone(6), ((1.0, 1.0), (2.0, 0.3))).apply(env_ad(R, half, 4.0, 60.0)), 0.0, 0.2)
    out.add(tone(R, half, ROOT * 0.5 * semitone(6), ROOT * 0.5, ((1.0, 1.0), (2.0, 0.3))).apply(env_ad(R, half, 4.0, 60.0)), half, 0.2)
    dry = crackle(rng, R, LENGTH, 14.0, 0.004, 0.0)
    out.add(bandpass(dry, 1200.0, 1.2), 0.0, 0.3)
    out.add(sparse_plucks(rng, LENGTH, 5, 0, 0.2, 0.3, 0.6), 0.0, 1.0)
    return normalize(soft_clip(loopable(echo(out, 0.5, 0.4, 0.35), CROSSFADE), 1.2), 0.8)


def generate() -> list[Path]:
    out = output_dir()
    return [
        write_wav(out / "music_hub.wav", hub(Rng(SEED))),
        write_wav(out / "music_match.wav", match(Rng(SEED + 1))),
        write_wav(out / "music_boss.wav", boss(Rng(SEED + 2))),
    ]


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
