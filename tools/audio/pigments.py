"""The twenty pigment sounds: five matters, four layers each.

docs/JUICE_PLAN.md phase 5: every glyph becomes attack + body + tail + impact. The layers are per
PIGMENT, not per glyph, because a school is a matter (docs/ART_BIBLE.md: "une couleur ET une matière")
and twenty glyphs with twenty voices would be twenty things to learn instead of five. The timeline of
each glyph names which of its pigment's layers plays in which phase, and pitch varies by five percent
at play time, so two casts of the same glyph are never the same file.

The matters, and what each is made of:
  Cinnabar   what consumes -- embers: crackle over a hiss that gathers, a low boom at the end
  Indigo     what contains -- water: a wet swell, bubbling, drips, a splash
  Umber      what resists  -- stone: grinding, a rumble, gravel settling, a dead thud
  Verdigris  what displaces -- air: an intake, a gust, a wake, a slap
  Orpiment   what strikes  -- the quill's crack: a charge, a snap, a fizzle, a crack

Nothing is a sampled instrument and nothing is an engine sound. A player should tell the school from
the matter with their eyes shut, which is free legibility in a six-way fight.

    python3 tools/audio/pigments.py
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
    report,
    soft_clip,
    tone,
    tremolo,
    write_wav,
)

SEED = 0xA0_D10


# --- Cinnabar ---------------------------------------------------------------------------------------


def cinnabar_attack(rng: Rng) -> Buf:
    hiss = bandpass(noise(rng, R, 0.34), 300.0, 2.0, 2200.0).apply(env_swell(R, 0.34))
    sub = tone(R, 0.34, 70.0, 95.0).apply(env_swell(R, 0.34))
    return declick(normalize(hiss.add(sub, 0.0, 0.5)))


def cinnabar_body(rng: Rng) -> Buf:
    embers = crackle(rng, R, 0.55, 260.0, 0.003, 0.3)
    bed = lowpass(noise(rng, R, 0.55), 900.0).apply(env_hold(R, 0.55, 0.03, 0.15))
    return declick(normalize(embers.add(bed, 0.0, 0.35)))


def cinnabar_tail(rng: Rng) -> Buf:
    embers = crackle(rng, R, 0.9, 140.0, 0.003, 0.9).apply(env_ad(R, 0.9, 0.01, 0.35))
    hiss = bandpass(noise(rng, R, 0.9), 1800.0, 1.5, 700.0).apply(env_ad(R, 0.9, 0.01, 0.3))
    return declick(normalize(embers.add(hiss, 0.0, 0.3)))


def cinnabar_impact(rng: Rng) -> Buf:
    boom = tone(R, 0.55, 110.0, 38.0, ((1.0, 1.0), (2.0, 0.3))).apply(env_ad(R, 0.55, 0.004, 0.14))
    burst = bandpass(noise(rng, R, 0.55), 1400.0, 0.8, 500.0).apply(env_ad(R, 0.55, 0.002, 0.06))
    embers = crackle(rng, R, 0.55, 200.0, 0.003, 0.9).apply(env_ad(R, 0.55, 0.02, 0.2))
    return declick(normalize(soft_clip(boom.add(burst, 0.0, 0.7).add(embers, 0.05, 0.4), 1.6)))


# --- Indigo -----------------------------------------------------------------------------------------


def indigo_attack(rng: Rng) -> Buf:
    swell = lowpass(lowpass(noise(rng, R, 0.36), 200.0, 1600.0), 400.0, 2400.0).apply(env_swell(R, 0.36))
    return declick(normalize(swell))


def indigo_body(rng: Rng) -> Buf:
    bed = lowpass(noise(rng, R, 0.6), 700.0).apply(env_hold(R, 0.6, 0.04, 0.12)).apply(tremolo(R, 0.6, 9.0, 0.5))
    out = Buf(R, 0.6).add(bed, 0.0, 0.5)
    for _ in range(14):
        at = rng.uniform(0.0, 0.5)
        f = rng.uniform(500.0, 1500.0)
        blip = tone(R, 0.07, f, f * 1.8).apply(env_ad(R, 0.07, 0.002, 0.015))
        out.add(blip, at, 0.35)
    return declick(normalize(out))


def indigo_tail(rng: Rng) -> Buf:
    wake = lowpass(noise(rng, R, 0.9), 1200.0, 200.0).apply(env_ad(R, 0.9, 0.01, 0.28))
    out = Buf(R, 0.9).add(wake, 0.0, 0.6)
    for _ in range(7):
        at = rng.uniform(0.1, 0.8)
        f = rng.uniform(700.0, 1900.0)
        drip = tone(R, 0.09, f, f * 2.2).apply(env_ad(R, 0.09, 0.002, 0.02))
        out.add(drip, at, 0.3)
    return declick(normalize(out))


def indigo_impact(rng: Rng) -> Buf:
    splash = bandpass(noise(rng, R, 0.5), 900.0, 0.9, 300.0).apply(env_ad(R, 0.5, 0.003, 0.1))
    thud = tone(R, 0.5, 120.0, 55.0).apply(env_ad(R, 0.5, 0.003, 0.09))
    spray = highpass(noise(rng, R, 0.5), 3000.0).apply(env_ad(R, 0.5, 0.01, 0.12))
    return declick(normalize(splash.add(thud, 0.0, 0.7).add(spray, 0.02, 0.3)))


# --- Umber ------------------------------------------------------------------------------------------


def umber_attack(rng: Rng) -> Buf:
    grind = bandpass(noise(rng, R, 0.4), 90.0, 1.4, 220.0).apply(env_swell(R, 0.4))
    grit = crackle(rng, R, 0.4, 180.0, 0.002, 0.0).apply(env_swell(R, 0.4))
    return declick(normalize(soft_clip(grind.add(grit, 0.0, 0.5), 1.4)))


def umber_body(rng: Rng) -> Buf:
    rumble = tone(R, 0.6, 52.0, 48.0, ((1.0, 1.0), (1.5, 0.3), (2.0, 0.2))).apply(env_hold(R, 0.6, 0.05, 0.15))
    dust = lowpass(noise(rng, R, 0.6), 300.0).apply(env_hold(R, 0.6, 0.05, 0.15))
    return declick(normalize(soft_clip(rumble.add(dust, 0.0, 0.5), 1.3)))


def umber_tail(rng: Rng) -> Buf:
    gravel = crackle(rng, R, 0.9, 90.0, 0.004, 0.95).apply(env_ad(R, 0.9, 0.01, 0.3))
    settle = lowpass(noise(rng, R, 0.9), 240.0).apply(env_ad(R, 0.9, 0.01, 0.2))
    return declick(normalize(gravel.add(settle, 0.0, 0.4)))


def umber_impact(rng: Rng) -> Buf:
    thud = tone(R, 0.5, 75.0, 28.0, ((1.0, 1.0), (2.0, 0.2))).apply(env_ad(R, 0.5, 0.002, 0.11))
    click = bandpass(noise(rng, R, 0.5), 2000.0, 1.2).apply(env_ad(R, 0.5, 0.001, 0.008))
    debris = crackle(rng, R, 0.5, 240.0, 0.003, 0.95).apply(env_ad(R, 0.5, 0.03, 0.12))
    return declick(normalize(soft_clip(thud.add(click, 0.0, 0.5).add(debris, 0.04, 0.4), 1.8)))


# --- Verdigris --------------------------------------------------------------------------------------


def verdigris_attack(rng: Rng) -> Buf:
    intake = highpass(bandpass(noise(rng, R, 0.3), 600.0, 1.2, 3200.0), 400.0).apply(env_swell(R, 0.3))
    return declick(normalize(intake))


def verdigris_body(rng: Rng) -> Buf:
    gust = bandpass(noise(rng, R, 0.6), 700.0, 0.9, 1400.0).apply(env_hold(R, 0.6, 0.06, 0.18)).apply(tremolo(R, 0.6, 6.0, 0.35))
    air = lowpass(noise(rng, R, 0.6), 1800.0).apply(env_hold(R, 0.6, 0.06, 0.18))
    return declick(normalize(gust.add(air, 0.0, 0.4)))


def verdigris_tail(rng: Rng) -> Buf:
    wake = bandpass(noise(rng, R, 0.9), 1600.0, 0.8, 400.0).apply(env_ad(R, 0.9, 0.01, 0.3))
    return declick(normalize(wake))


def verdigris_impact(rng: Rng) -> Buf:
    slap = highpass(noise(rng, R, 0.4), 900.0).apply(env_ad(R, 0.4, 0.001, 0.03))
    whoosh = bandpass(noise(rng, R, 0.4), 2200.0, 1.0, 500.0).apply(env_ad(R, 0.4, 0.004, 0.1))
    thump = tone(R, 0.4, 140.0, 60.0).apply(env_ad(R, 0.4, 0.002, 0.05))
    return declick(normalize(slap.add(whoosh, 0.01, 0.8).add(thump, 0.0, 0.5)))


# --- Orpiment ---------------------------------------------------------------------------------------


def orpiment_attack(rng: Rng) -> Buf:
    charge = tone(R, 0.26, 420.0, 3100.0, ((1.0, 1.0), (2.01, 0.4), (3.02, 0.2))).apply(env_swell(R, 0.26))
    fizz = crackle(rng, R, 0.26, 700.0, 0.0015, 0.0).apply(env_swell(R, 0.26))
    return declick(normalize(charge.add(fizz, 0.0, 0.5)))


def orpiment_body(rng: Rng) -> Buf:
    snap = noise(rng, R, 0.16).apply(env_ad(R, 0.16, 0.0005, 0.006))
    click = tone(R, 0.16, 2600.0, 900.0).apply(env_ad(R, 0.16, 0.0005, 0.01))
    ring = tone(R, 0.16, 1900.0, 1850.0).apply(env_ad(R, 0.16, 0.002, 0.04))
    return declick(normalize(soft_clip(snap.add(click, 0.0, 0.8).add(ring, 0.004, 0.3), 1.5)))


def orpiment_tail(rng: Rng) -> Buf:
    fizz = crackle(rng, R, 0.6, 900.0, 0.0012, 0.95).apply(env_ad(R, 0.6, 0.005, 0.16))
    whine = tone(R, 0.6, 4200.0, 2600.0).apply(env_ad(R, 0.6, 0.005, 0.1))
    return declick(normalize(highpass(fizz.add(whine, 0.0, 0.15), 1200.0)))


def orpiment_impact(rng: Rng) -> Buf:
    crack = noise(rng, R, 0.4).apply(env_ad(R, 0.4, 0.0005, 0.012))
    thump = tone(R, 0.4, 160.0, 45.0).apply(env_ad(R, 0.4, 0.002, 0.07))
    fizz = crackle(rng, R, 0.4, 600.0, 0.0015, 0.95).apply(env_ad(R, 0.4, 0.01, 0.09))
    return declick(normalize(soft_clip(crack.add(thump, 0.003, 0.9).add(fizz, 0.02, 0.4), 1.7)))


LAYERS = ("attack", "body", "tail", "impact")
MATTERS = {
    "cinnabar": (cinnabar_attack, cinnabar_body, cinnabar_tail, cinnabar_impact),
    "indigo": (indigo_attack, indigo_body, indigo_tail, indigo_impact),
    "umber": (umber_attack, umber_body, umber_tail, umber_impact),
    "verdigris": (verdigris_attack, verdigris_body, verdigris_tail, verdigris_impact),
    "orpiment": (orpiment_attack, orpiment_body, orpiment_tail, orpiment_impact),
}


def generate() -> list[Path]:
    out = output_dir()
    paths: list[Path] = []
    for index, (matter, builders) in enumerate(MATTERS.items()):
        for layer_index, (layer, build) in enumerate(zip(LAYERS, builders)):
            # One stream per file, so editing one sound never moves the bytes of another.
            rng = Rng(SEED + index * 16 + layer_index)
            buf = build(rng)
            paths.append(write_wav(out / f"{matter}_{layer}.wav", echo(buf, 0.031, 0.25, 0.4) if layer == "impact" else buf))
    return paths


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
