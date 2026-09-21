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
    knock,
    lowpass,
    noise,
    normalize_rms,
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

# RMS targets per class, in linear full scale. The mix lives here and in SoundConfig's Volumes.
LOUDNESS = {"kit": 0.2, "impact": 0.25, "boss": 0.22, "note": 0.14, "ui": 0.1, "feedback": 0.15}


def finish(buf: Buf, kind: str) -> Buf:
    return declick(normalize_rms(buf, LOUDNESS[kind]))

# The root of every note in the game, and of the loops: A3. The sequence climbs a pentatonic from it.
ROOT = 220.0


# --- Melee kit --------------------------------------------------------------------------------------


def brush_swipe(rng: Rng, seconds: float, low: float, high: float, weight: float) -> Buf:
    """A brush through air and onto the page: noise through a band that sweeps up, and a soft body
    underneath scaled by `weight`."""
    stroke = bandpass(noise(rng, R, seconds), low, 1.1, high).apply(env_ad(R, seconds, 0.01, seconds * 0.35))
    body = lowpass(noise(rng, R, seconds), 400.0).apply(env_ad(R, seconds, 0.005, seconds * 0.25))
    return finish(stroke.add(body, 0.0, weight), "kit")


def melee(rng: Rng, variant: int) -> Buf:
    low = (380.0, 520.0, 700.0)[variant]
    return brush_swipe(rng, 0.2, low, low * 3.2, 0.35)


def melee_finisher(rng: Rng) -> Buf:
    swipe = brush_swipe(rng, 0.32, 300.0, 1400.0, 0.6)
    body = knock(rng, R, 0.32, 140.0, 2.5, 0.07)
    return finish(soft_clip(swipe.add(body, 0.03, 0.8), 1.5), "kit")


def dash(rng: Rng) -> Buf:
    """A dash in Vellum is a stroke, so it is the brush and not a whoosh: the generic swoosh is the
    one sound every game shares, and it would also have been Verdigris's attack a second time."""
    return brush_swipe(rng, 0.36, 400.0, 1800.0, 0.3)


def impact_hit(rng: Rng) -> Buf:
    """Ink slapped onto the page: a short broadband burst with a wet band under it."""
    slap = noise(rng, R, 0.26).apply(env_ad(R, 0.26, 0.001, 0.02))
    wet = bandpass(noise(rng, R, 0.26), 700.0, 1.0, 250.0).apply(env_ad(R, 0.26, 0.003, 0.06))
    page = knock(rng, R, 0.26, 170.0, 2.5, 0.05)
    return finish(soft_clip(slap.add(wet, 0.0, 0.8).add(page, 0.0, 0.6), 1.4), "impact")


def block_start(rng: Rng) -> Buf:
    """Paper stiffening: a short dry rustle and a tone that sets."""
    rustle = highpass(crackle(rng, R, 0.26, 500.0, 0.002, 0.3), 800.0).apply(env_ad(R, 0.26, 0.005, 0.08))
    set_ = tone(R, 0.26, 330.0, 440.0, ((1.0, 1.0), (2.0, 0.25))).apply(env_ad(R, 0.26, 0.02, 0.09))
    return finish(rustle.add(set_, 0.02, 0.45), "kit")


def impact_block(rng: Rng) -> Buf:
    body = knock(rng, R, 0.3, 200.0, 3.0, 0.06)
    tap = bandpass(noise(rng, R, 0.3), 1200.0, 2.0).apply(env_ad(R, 0.3, 0.001, 0.015))
    return finish(soft_clip(body.add(tap, 0.0, 0.6), 1.3), "impact")


def guard_break(rng: Rng) -> Buf:
    """Paper tearing: noise chopped by a fast, irregular tremolo, then the two halves falling."""
    # Two gates at rates that share no period, so the tear is irregular: paper does not tear at 47 Hz.
    tear = bandpass(noise(rng, R, 0.48), 1500.0, 0.7, 600.0).apply(env_hold(R, 0.48, 0.005, 0.25)).apply(tremolo(R, 0.48, 47.0, 0.9)).apply(tremolo(R, 0.48, 11.0, 0.5))
    fibres = crackle(rng, R, 0.48, 60.0, 0.006, 0.8).apply(env_ad(R, 0.48, 0.01, 0.15))
    fall = tone(R, 0.48, 240.0, 90.0).apply(env_ad(R, 0.48, 0.05, 0.12))
    return finish(tear.add(fibres, 0.0, 0.5).add(fall, 0.12, 0.4), "kit")


# --- The Erasure ------------------------------------------------------------------------------------


def boss_arrival(rng: Rng) -> Buf:
    """The page drained: a drone falling through two octaves while the air is pulled in, then a
    crack. Long, because it has the Erasure pulse's five seconds to live in."""
    drone = tone(R, 2.6, 220.0, 55.0, ((1.0, 1.0), (1.5, 0.4), (2.0, 0.3), (2.98, 0.15))).apply(env_hold(R, 2.6, 0.4, 0.5))
    pull = bandpass(noise(rng, R, 2.6), 3000.0, 0.8, 200.0).apply(env_swell(R, 2.6))
    crack = noise(rng, R, 2.6).apply(env_ad(R, 2.6, 0.0005, 0.03))
    out = drone.add(pull, 0.0, 0.5)
    out.add(crack, 2.1, 0.9)
    return finish(soft_clip(echo(out, 0.11, 0.3, 0.5), 1.4), "boss")


def boss_warn(rng: Rng) -> Buf:
    """The telegraph, two seconds long: a tone rising a fifth over intakes of air that come closer and
    closer together -- the Erasure takes in, and a warning that quickens is a warning. The runtime
    stretches it to the window with PlaybackSpeed, so a shorter warning is the same shape, higher and
    faster -- more urgent, which is what a shorter warning is."""
    rise = tone(R, 2.0, 110.0, 165.0, ((1.0, 1.0), (2.0, 0.35), (3.0, 0.15), (4.0, 0.1))).apply(env_swell(R, 2.0))
    out = Buf(R, 2.0).add(rise, 0.0, 1.0)
    gap = 0.32
    t = 0.0
    while t < 1.9:
        intake = bandpass(noise(rng, R, 0.12), 2600.0, 0.9, 500.0).apply(env_ad(R, 0.12, 0.02, 0.04))
        out.add(intake, t, 0.5 + 0.3 * (t / 1.9))
        t += gap
        gap = max(0.08, gap * 0.82)
    return finish(out, "boss")


def boss_impact(rng: Rng) -> Buf:
    """The landing: a struck floor you can hear on a phone, the page tearing irregularly, and then the
    air pulled into the hole -- the Erasure's own gesture, not gravel, which is Umber's."""
    floor = knock(rng, R, 0.9, 95.0, 2.5, 0.2)
    boom = tone(R, 0.9, 90.0, 24.0, ((1.0, 1.0), (2.0, 0.3), (4.0, 0.15))).apply(env_ad(R, 0.9, 0.003, 0.2))
    tear = bandpass(noise(rng, R, 0.9), 1200.0, 0.7, 300.0).apply(env_ad(R, 0.9, 0.002, 0.12)).apply(tremolo(R, 0.9, 38.0, 0.7)).apply(tremolo(R, 0.9, 9.0, 0.5))
    pull = bandpass(noise(rng, R, 0.9), 3000.0, 0.8, 200.0).apply(env_ad(R, 0.9, 0.05, 0.3))
    return finish(soft_clip(echo(floor.add(boom, 0.0, 0.6).add(tear, 0.0, 0.8).add(pull, 0.06, 0.5), 0.047, 0.35, 0.5), 2.0), "boss")


def boss_defeat(rng: Rng) -> Buf:
    """The mirror of the arrival: the drone gathers upward, breaks, and what it took is let go."""
    gather = tone(R, 2.2, 55.0, 220.0, ((1.0, 1.0), (1.5, 0.4), (2.0, 0.3))).apply(env_swell(R, 1.1))
    crack = noise(rng, R, 2.2).apply(env_ad(R, 2.2, 0.0005, 0.04))
    # The release OPENS: the cutoff rises, the opposite of the arrival's pull. What was taken in goes out.
    release = lowpass(noise(rng, R, 2.2), 300.0, 2400.0).apply(env_ad(R, 2.2, 0.01, 0.4))
    out = Buf(R, 2.2).add(gather, 0.0, 1.0)
    out.add(crack, 1.1, 0.9)
    out.add(release, 1.1, 0.7)
    return finish(soft_clip(echo(out, 0.09, 0.3, 0.5), 1.4), "boss")


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
    # The quill, before the string speaks: a twelve-millisecond scratch of nib on paper, the same for
    # all five, so a note is a stroke and the matter under it is the school.
    out.add(bandpass(noise(rng, R, 0.7), 1200.0, 3.0, 3500.0).apply(env_ad(R, 0.7, 0.001, 0.004)), 0.0, 0.3)
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
    return finish(echo(out, 0.09, 0.2, 0.3), "note")


def sequence_resolve(rng: Rng) -> Buf:
    """The phrase resolving: root, fifth and octave struck together and let ring."""
    out = Buf(R, 1.0)
    for steps, gain in ((0, 1.0), (7, 0.7), (12, 0.5)):
        out.add(pluck(R, 1.0, ROOT * semitone(steps), 0.6, rng).apply(env_ad(R, 1.0, 0.001, 0.3)), 0.0, gain)
    return finish(echo(out, 0.12, 0.3, 0.4), "note")


def sequence_fail(rng: Rng) -> Buf:
    """A minor second, the interval that cannot rest, damped fast."""
    out = Buf(R, 0.5)
    out.add(pluck(R, 0.5, ROOT, 0.3, rng).apply(env_ad(R, 0.5, 0.001, 0.09)), 0.0, 1.0)
    out.add(pluck(R, 0.5, ROOT * semitone(1), 0.3, rng).apply(env_ad(R, 0.5, 0.001, 0.09)), 0.0, 0.9)
    out.add(lowpass(noise(rng, R, 0.5), 500.0).apply(env_ad(R, 0.5, 0.002, 0.05)), 0.0, 0.3)
    return finish(out, "note")


def sequence_dissipate(rng: Rng) -> Buf:
    """A sequence that was never finished: a dead pluck in the same instrument -- a note that dried out
    -- rather than a sine powering down."""
    dead = pluck(R, 0.6, ROOT * 0.66, 0.1, rng).apply(env_ad(R, 0.6, 0.001, 0.16))
    dry = highpass(noise(rng, R, 0.6), 2500.0).apply(env_ad(R, 0.6, 0.05, 0.12))
    return finish(dead.add(dry, 0.1, 0.3), "note")


# --- Interface and personal feedback ------------------------------------------------------------------


def ui_click(rng: Rng) -> Buf:
    """A nib tapped on paper: no tone in it, because a tone is the tick-blip of every menu."""
    tick = highpass(noise(rng, R, 0.07), 1800.0).apply(env_ad(R, 0.07, 0.0005, 0.008))
    paper = lowpass(noise(rng, R, 0.07), 900.0).apply(env_ad(R, 0.07, 0.0005, 0.006))
    return finish(tick.add(paper, 0.0, 0.5), "ui")


def ui_open(rng: Rng) -> Buf:
    """A page turned: a rustle that sweeps up and a soft settle."""
    turn = bandpass(noise(rng, R, 0.3), 900.0, 0.8, 2600.0).apply(env_ad(R, 0.3, 0.02, 0.08))
    settle = lowpass(noise(rng, R, 0.3), 700.0).apply(env_ad(R, 0.3, 0.1, 0.05))
    return finish(turn.add(settle, 0.15, 0.5), "ui")


def ui_close(rng: Rng) -> Buf:
    turn = bandpass(noise(rng, R, 0.26), 2400.0, 0.8, 700.0).apply(env_ad(R, 0.26, 0.01, 0.07))
    settle = lowpass(noise(rng, R, 0.26), 500.0).apply(env_ad(R, 0.26, 0.001, 0.03))
    return finish(turn.add(settle, 0.16, 0.7), "ui")


def ui_error(rng: Rng) -> Buf:
    """A dull knock on the desk, not the error buzz."""
    desk = knock(rng, R, 0.3, 170.0, 3.0, 0.07)
    rustle = lowpass(noise(rng, R, 0.3), 600.0).apply(env_ad(R, 0.3, 0.002, 0.03))
    return finish(desk.add(rustle, 0.0, 0.5), "ui")


def claim(rng: Rng) -> Buf:
    """A drop of ink landing in the well: a bright pluck an octave up and a small wet body."""
    drop = pluck(R, 0.34, ROOT * 2.0, 0.85, rng).apply(env_ad(R, 0.34, 0.001, 0.09))
    wet = lowpass(noise(rng, R, 0.34), 1200.0).apply(env_ad(R, 0.34, 0.003, 0.03))
    return finish(drop.add(wet, 0.0, 0.35), "feedback")


def motif(rng: Rng, steps: tuple[int, ...], gap: float, seconds: float, brightness: float = 0.6) -> Buf:
    """Plucks up (or down) a scale, `gap` seconds apart."""
    out = Buf(R, seconds)
    for index, step in enumerate(steps):
        note = pluck(R, seconds - index * gap, ROOT * semitone(step), brightness, rng).apply(env_ad(R, seconds - index * gap, 0.001, 0.25))
        out.add(note, index * gap, 0.8)
    return finish(echo(out, 0.12, 0.25, 0.35), "feedback")


def level_up(rng: Rng) -> Buf:
    return motif(rng, (0, 4, 7, 12), 0.13, 1.0, 0.7)


def tier_up(rng: Rng) -> Buf:
    return motif(rng, (0, 7, 12), 0.11, 0.8, 0.7)


def kill(rng: Rng) -> Buf:
    """The finishing stroke: a heavy brush and the page taking it."""
    stroke = brush_swipe(rng, 0.5, 250.0, 1600.0, 0.7)
    settle = knock(rng, R, 0.5, 110.0, 2.5, 0.14)
    return finish(soft_clip(stroke.add(settle, 0.06, 0.8), 1.4), "feedback")


def match_start(rng: Rng) -> Buf:
    return motif(rng, (0, 7), 0.16, 0.8, 0.5)


def match_win(rng: Rng) -> Buf:
    return motif(rng, (0, 4, 7, 12, 16), 0.12, 1.4, 0.7)


def match_lose(rng: Rng) -> Buf:
    return motif(rng, (12, 8, 5, 0), 0.16, 1.4, 0.3)


def countdown(rng: Rng) -> Buf:
    """A woodblock, the bible's dry percussion -- not the 880 Hz beep of every countdown."""
    return finish(knock(rng, R, 0.16, 1900.0, 9.0, 0.025), "feedback")


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
