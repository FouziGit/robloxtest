"""Everything that is not a pigment: the melee kit, the guard, the boss, the sequence, the interface,
and the personal feedback.

Every one of these replaces either a sound the engine ships (rbxasset://sounds/electronicpingshort.wav
at nine different speeds was most of the game's audio) or an asset whose licence nobody could show.
The rule from docs/ART_BIBLE.md holds here as it does for the eye: paper, brush, ink and the quill,
nothing that would pass unnoticed in another game.

The sequence notes are plucks -- a quill touching the page -- one per pigment, in that pigment's matter.
ComboController plays them up a scale as a sequence grows, so a resolved sequence is a phrase and a
broken one is a clash (SequenceFail is a minor second, the interval that cannot rest).

    python3 tools/audio/kit.py
"""

from __future__ import annotations

from pathlib import Path

from vellum_wav import (
    RATE_SFX as R,
    Buf,
    Rng,
    bandpass,
    crackle,
    declick,
    echo,
    env_ad,
    env_hold,
    env_swell,
    highpass,
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

SEED = 0x1C_17

# The root of every note in the game, and of the loops: A3. The sequence climbs a pentatonic from it.
ROOT = 220.0


# --- Melee kit --------------------------------------------------------------------------------------


def brush_swipe(rng: Rng, seconds: float, low: float, high: float, weight: float) -> Buf:
    """A brush through air and onto the page: noise through a band that sweeps up, and a soft body
    underneath scaled by `weight`."""
    stroke = bandpass(noise(rng, R, seconds), low, 1.1, high).apply(env_ad(R, seconds, 0.01, seconds * 0.35))
    body = lowpass(noise(rng, R, seconds), 400.0).apply(env_ad(R, seconds, 0.005, seconds * 0.25))
    return declick(normalize(stroke.add(body, 0.0, weight)))


def melee(rng: Rng, variant: int) -> Buf:
    low = (380.0, 520.0, 700.0)[variant]
    return brush_swipe(rng, 0.2, low, low * 3.2, 0.35)


def melee_finisher(rng: Rng) -> Buf:
    swipe = brush_swipe(rng, 0.32, 300.0, 1400.0, 0.6)
    thump = tone(R, 0.32, 130.0, 50.0).apply(env_ad(R, 0.32, 0.002, 0.07))
    return declick(normalize(soft_clip(swipe.add(thump, 0.03, 0.8), 1.5)))


def dash(rng: Rng) -> Buf:
    whoosh = bandpass(noise(rng, R, 0.36), 500.0, 0.9, 2600.0).apply(env_ad(R, 0.36, 0.02, 0.1))
    air = lowpass(noise(rng, R, 0.36), 1500.0).apply(env_ad(R, 0.36, 0.01, 0.12))
    return declick(normalize(whoosh.add(air, 0.0, 0.5)))


def impact_hit(rng: Rng) -> Buf:
    """Ink slapped onto the page: a short broadband burst with a wet band under it."""
    slap = noise(rng, R, 0.26).apply(env_ad(R, 0.26, 0.001, 0.02))
    wet = bandpass(noise(rng, R, 0.26), 700.0, 1.0, 250.0).apply(env_ad(R, 0.26, 0.003, 0.06))
    thud = tone(R, 0.26, 150.0, 70.0).apply(env_ad(R, 0.26, 0.002, 0.05))
    return declick(normalize(soft_clip(slap.add(wet, 0.0, 0.8).add(thud, 0.0, 0.6), 1.4)))


def block_start(rng: Rng) -> Buf:
    """Paper stiffening: a short dry rustle and a tone that sets."""
    rustle = highpass(crackle(rng, R, 0.26, 500.0, 0.002, 0.3), 800.0).apply(env_ad(R, 0.26, 0.005, 0.08))
    set_ = tone(R, 0.26, 330.0, 440.0, ((1.0, 1.0), (2.0, 0.25))).apply(env_ad(R, 0.26, 0.02, 0.09))
    return declick(normalize(rustle.add(set_, 0.02, 0.45)))


def impact_block(rng: Rng) -> Buf:
    thud = tone(R, 0.3, 200.0, 90.0, ((1.0, 1.0), (3.0, 0.15))).apply(env_ad(R, 0.3, 0.002, 0.06))
    knock = bandpass(noise(rng, R, 0.3), 1200.0, 2.0).apply(env_ad(R, 0.3, 0.001, 0.015))
    return declick(normalize(soft_clip(thud.add(knock, 0.0, 0.6), 1.3)))


def guard_break(rng: Rng) -> Buf:
    """Paper tearing: noise chopped by a fast, irregular tremolo, then the two halves falling."""
    tear = bandpass(noise(rng, R, 0.48), 1500.0, 0.7, 600.0).apply(env_hold(R, 0.48, 0.005, 0.25)).apply(tremolo(R, 0.48, 47.0, 0.9))
    fibres = crackle(rng, R, 0.48, 900.0, 0.0015, 0.8).apply(env_ad(R, 0.48, 0.01, 0.15))
    fall = tone(R, 0.48, 240.0, 90.0).apply(env_ad(R, 0.48, 0.05, 0.12))
    return declick(normalize(tear.add(fibres, 0.0, 0.5).add(fall, 0.12, 0.4)))


# --- The Erasure ------------------------------------------------------------------------------------


def boss_arrival(rng: Rng) -> Buf:
    """The page drained: a drone falling through two octaves while the air is pulled in, then a
    crack. Long, because it has the Erasure pulse's five seconds to live in."""
    drone = tone(R, 2.6, 220.0, 55.0, ((1.0, 1.0), (1.5, 0.4), (2.0, 0.3), (2.98, 0.15))).apply(env_hold(R, 2.6, 0.4, 0.5))
    pull = bandpass(noise(rng, R, 2.6), 3000.0, 0.8, 200.0).apply(env_swell(R, 2.6))
    crack = noise(rng, R, 2.6).apply(env_ad(R, 2.6, 0.0005, 0.03))
    out = drone.add(pull, 0.0, 0.5)
    out.add(crack, 2.1, 0.9)
    return declick(normalize(soft_clip(echo(out, 0.11, 0.3, 0.5), 1.4)))


def boss_warn(rng: Rng) -> Buf:
    """The telegraph, two seconds long: a tone rising a fifth with a pulse that quickens. The runtime
    stretches it to the window with PlaybackSpeed, so a shorter warning is the same shape, higher and
    faster -- more urgent, which is what a shorter warning is."""
    rise = tone(R, 2.0, 110.0, 165.0, ((1.0, 1.0), (2.0, 0.35), (3.0, 0.15))).apply(env_swell(R, 2.0))
    pulse = tone(R, 2.0, 55.0, 82.0).apply(env_swell(R, 2.0)).apply(tremolo(R, 2.0, 4.0, 0.8))
    grain = crackle(rng, R, 2.0, 120.0, 0.003, -0.8).apply(env_swell(R, 2.0))
    return declick(normalize(rise.add(pulse, 0.0, 0.7).add(grain, 0.0, 0.35)))


def boss_impact(rng: Rng) -> Buf:
    boom = tone(R, 0.9, 90.0, 24.0, ((1.0, 1.0), (2.0, 0.3))).apply(env_ad(R, 0.9, 0.003, 0.2))
    tear = bandpass(noise(rng, R, 0.9), 1200.0, 0.7, 300.0).apply(env_ad(R, 0.9, 0.002, 0.12)).apply(tremolo(R, 0.9, 38.0, 0.7))
    debris = crackle(rng, R, 0.9, 260.0, 0.003, 0.95).apply(env_ad(R, 0.9, 0.04, 0.25))
    return declick(normalize(soft_clip(echo(boom.add(tear, 0.0, 0.8).add(debris, 0.06, 0.5), 0.047, 0.35, 0.5), 2.0)))


def boss_defeat(rng: Rng) -> Buf:
    """The mirror of the arrival: the drone gathers upward, breaks, and what it took is let go."""
    gather = tone(R, 2.2, 55.0, 220.0, ((1.0, 1.0), (1.5, 0.4), (2.0, 0.3))).apply(env_swell(R, 1.1))
    crack = noise(rng, R, 2.2).apply(env_ad(R, 2.2, 0.0005, 0.04))
    release = lowpass(noise(rng, R, 2.2), 2400.0, 300.0).apply(env_ad(R, 2.2, 0.01, 0.4))
    out = Buf(R, 2.2).add(gather, 0.0, 1.0)
    out.add(crack, 1.1, 0.9)
    out.add(release, 1.1, 0.7)
    return declick(normalize(soft_clip(echo(out, 0.09, 0.3, 0.5), 1.4)))


# --- The sequence -----------------------------------------------------------------------------------

PIGMENT_NOTE = {
    # Each pigment's note carries its matter: the brightness of the pluck and what is mixed under it.
    "cinnabar": (0.75, "embers"),
    "indigo": (0.35, "water"),
    "umber": (0.2, "stone"),
    "verdigris": (0.55, "air"),
    "orpiment": (0.95, "quill"),
}


def sequence_note(rng: Rng, pigment: str) -> Buf:
    brightness, matter = PIGMENT_NOTE[pigment]
    note = pluck(R, 0.7, ROOT, brightness, rng).apply(env_ad(R, 0.7, 0.001, 0.22))
    out = Buf(R, 0.7).add(note, 0.0, 1.0)
    if matter == "embers":
        out.add(crackle(rng, R, 0.7, 120.0, 0.002, 0.9).apply(env_ad(R, 0.7, 0.005, 0.1)), 0.0, 0.25)
    elif matter == "water":
        out.add(lowpass(noise(rng, R, 0.7), 900.0).apply(env_ad(R, 0.7, 0.01, 0.06)), 0.0, 0.3)
    elif matter == "stone":
        out.add(tone(R, 0.7, ROOT * 0.5, ROOT * 0.5).apply(env_ad(R, 0.7, 0.002, 0.12)), 0.0, 0.4)
    elif matter == "air":
        out.add(bandpass(noise(rng, R, 0.7), 1800.0, 1.0, 600.0).apply(env_ad(R, 0.7, 0.01, 0.1)), 0.0, 0.25)
    else:
        out.add(noise(rng, R, 0.7).apply(env_ad(R, 0.7, 0.0005, 0.004)), 0.0, 0.5)
    return declick(normalize(echo(out, 0.09, 0.2, 0.3)))


def sequence_resolve(rng: Rng) -> Buf:
    """The phrase resolving: root, fifth and octave struck together and let ring."""
    out = Buf(R, 1.0)
    for steps, gain in ((0, 1.0), (7, 0.7), (12, 0.5)):
        out.add(pluck(R, 1.0, ROOT * semitone(steps), 0.6, rng).apply(env_ad(R, 1.0, 0.001, 0.3)), 0.0, gain)
    return declick(normalize(echo(out, 0.12, 0.3, 0.4)))


def sequence_fail(rng: Rng) -> Buf:
    """A minor second, the interval that cannot rest, damped fast."""
    out = Buf(R, 0.5)
    out.add(pluck(R, 0.5, ROOT, 0.3, rng).apply(env_ad(R, 0.5, 0.001, 0.09)), 0.0, 1.0)
    out.add(pluck(R, 0.5, ROOT * semitone(1), 0.3, rng).apply(env_ad(R, 0.5, 0.001, 0.09)), 0.0, 0.9)
    out.add(lowpass(noise(rng, R, 0.5), 500.0).apply(env_ad(R, 0.5, 0.002, 0.05)), 0.0, 0.3)
    return declick(normalize(out))


def sequence_dissipate(rng: Rng) -> Buf:
    """A sequence that was never finished: the last note bending down and drying out."""
    fall = tone(R, 0.6, ROOT, ROOT * 0.66, ((1.0, 1.0), (2.0, 0.3))).apply(env_ad(R, 0.6, 0.01, 0.16))
    dry = highpass(noise(rng, R, 0.6), 2500.0).apply(env_ad(R, 0.6, 0.05, 0.12))
    return declick(normalize(fall.add(dry, 0.1, 0.3)))


# --- Interface and personal feedback ------------------------------------------------------------------


def ui_click(rng: Rng) -> Buf:
    tick = highpass(noise(rng, R, 0.07), 1800.0).apply(env_ad(R, 0.07, 0.0005, 0.008))
    tap = tone(R, 0.07, 1400.0, 900.0).apply(env_ad(R, 0.07, 0.0005, 0.012))
    return declick(normalize(tick.add(tap, 0.0, 0.5)))


def ui_open(rng: Rng) -> Buf:
    """A page turned: a rustle that sweeps up and a soft settle."""
    turn = bandpass(noise(rng, R, 0.3), 900.0, 0.8, 2600.0).apply(env_ad(R, 0.3, 0.02, 0.08))
    settle = lowpass(noise(rng, R, 0.3), 700.0).apply(env_ad(R, 0.3, 0.1, 0.05))
    return declick(normalize(turn.add(settle, 0.15, 0.5)))


def ui_close(rng: Rng) -> Buf:
    turn = bandpass(noise(rng, R, 0.26), 2400.0, 0.8, 700.0).apply(env_ad(R, 0.26, 0.01, 0.07))
    settle = lowpass(noise(rng, R, 0.26), 500.0).apply(env_ad(R, 0.26, 0.001, 0.03))
    return declick(normalize(turn.add(settle, 0.16, 0.7)))


def ui_error(rng: Rng) -> Buf:
    dull = tone(R, 0.3, 180.0, 150.0, ((1.0, 1.0), (1.5, 0.5))).apply(env_ad(R, 0.3, 0.005, 0.07))
    knock = lowpass(noise(rng, R, 0.3), 600.0).apply(env_ad(R, 0.3, 0.002, 0.03))
    return declick(normalize(dull.add(knock, 0.0, 0.5)))


def claim(rng: Rng) -> Buf:
    """A drop of ink landing in the well: a bright pluck an octave up and a small wet body."""
    drop = pluck(R, 0.34, ROOT * 2.0, 0.85, rng).apply(env_ad(R, 0.34, 0.001, 0.09))
    wet = lowpass(noise(rng, R, 0.34), 1200.0).apply(env_ad(R, 0.34, 0.003, 0.03))
    return declick(normalize(drop.add(wet, 0.0, 0.35)))


def motif(rng: Rng, steps: tuple[int, ...], gap: float, seconds: float, brightness: float = 0.6) -> Buf:
    """Plucks up (or down) a scale, `gap` seconds apart."""
    out = Buf(R, seconds)
    for index, step in enumerate(steps):
        note = pluck(R, seconds - index * gap, ROOT * semitone(step), brightness, rng).apply(env_ad(R, seconds - index * gap, 0.001, 0.25))
        out.add(note, index * gap, 0.8)
    return declick(normalize(echo(out, 0.12, 0.25, 0.35)))


def level_up(rng: Rng) -> Buf:
    return motif(rng, (0, 4, 7, 12), 0.13, 1.0, 0.7)


def tier_up(rng: Rng) -> Buf:
    return motif(rng, (0, 7, 12), 0.11, 0.8, 0.7)


def kill(rng: Rng) -> Buf:
    """The finishing stroke: a heavy brush and the page taking it."""
    stroke = brush_swipe(rng, 0.5, 250.0, 1600.0, 0.7)
    settle = tone(R, 0.5, 110.0, 70.0, ((1.0, 1.0), (2.0, 0.2))).apply(env_ad(R, 0.5, 0.01, 0.14))
    return declick(normalize(soft_clip(stroke.add(settle, 0.06, 0.8), 1.4)))


def match_start(rng: Rng) -> Buf:
    return motif(rng, (0, 7), 0.16, 0.8, 0.5)


def match_win(rng: Rng) -> Buf:
    return motif(rng, (0, 4, 7, 12, 16), 0.12, 1.4, 0.7)


def match_lose(rng: Rng) -> Buf:
    return motif(rng, (12, 8, 5, 0), 0.16, 1.4, 0.3)


def countdown(rng: Rng) -> Buf:
    tick = tone(R, 0.16, 880.0, 870.0).apply(env_ad(R, 0.16, 0.001, 0.03))
    wood = bandpass(noise(rng, R, 0.16), 1500.0, 2.5).apply(env_ad(R, 0.16, 0.0005, 0.01))
    return declick(normalize(tick.add(wood, 0.0, 0.6)))


BUILDERS = {
    "melee_1": lambda rng: melee(rng, 0),
    "melee_2": lambda rng: melee(rng, 1),
    "melee_3": lambda rng: melee(rng, 2),
    "melee_finisher": melee_finisher,
    "dash": dash,
    "impact_hit": impact_hit,
    "block_start": block_start,
    "impact_block": impact_block,
    "guard_break": guard_break,
    "boss_arrival": boss_arrival,
    "boss_warn": boss_warn,
    "boss_impact": boss_impact,
    "boss_defeat": boss_defeat,
    "note_cinnabar": lambda rng: sequence_note(rng, "cinnabar"),
    "note_indigo": lambda rng: sequence_note(rng, "indigo"),
    "note_umber": lambda rng: sequence_note(rng, "umber"),
    "note_verdigris": lambda rng: sequence_note(rng, "verdigris"),
    "note_orpiment": lambda rng: sequence_note(rng, "orpiment"),
    "sequence_resolve": sequence_resolve,
    "sequence_fail": sequence_fail,
    "sequence_dissipate": sequence_dissipate,
    "ui_click": ui_click,
    "ui_open": ui_open,
    "ui_close": ui_close,
    "ui_error": ui_error,
    "claim": claim,
    "level_up": level_up,
    "tier_up": tier_up,
    "kill": kill,
    "match_start": match_start,
    "match_win": match_win,
    "match_lose": match_lose,
    "countdown": countdown,
}


def generate() -> list[Path]:
    out = output_dir()
    paths: list[Path] = []
    for index, (name, build) in enumerate(BUILDERS.items()):
        paths.append(write_wav(out / f"{name}.wav", build(Rng(SEED + index))))
    return paths


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
