"""The twenty pigment sounds: five matters, four layers each.

docs/JUICE_PLAN.md phase 5: every glyph becomes attack + body + tail + impact. The layers are per
PIGMENT, not per glyph, because a school is a matter (docs/ART_BIBLE.md: "une couleur ET une matière")
and twenty glyphs with twenty voices would be twenty things to learn instead of five. The timeline of
each glyph names which of its pigment's layers plays in which phase, and pitch varies by five percent
at play time, so two casts of the same glyph are never the same file.

The matters, and what each is made of:
  Cinnabar   what consumes -- fire: a low roar that does not move, sparse pops, a dry drum at the end
  Indigo     what contains -- water: a wet swell, bubbling, drips, a splash on a skin
  Umber      what resists  -- stone: grinding in the mids, a rumble, gravel settling, a dead knock
  Verdigris  what displaces -- air: the one matter whose band MOVES -- an intake, a gust, a wake, a slap
  Orpiment   what strikes  -- the quill: a nib dragged faster, a snap, a fizzle, a crack

Nothing is a sampled instrument and nothing is an engine sound, and no impact is a sine gliding into the
sub-bass -- that is the stock hit of every other game, and on a phone speaker it is silence. Impacts are
struck bodies (vellum_wav.knock), in the mid band where a phone can play them. A player should tell the
school from the matter with their eyes shut, which is free legibility in a six-way fight.

Every attack is exactly the Cast timeline's wind-up long (0.22 s), so it is loudest on the fold and not
after it. Every file is loudness-normalised per voice (RMS), not peak-normalised: a sub and a hiss with
the same peak are twenty decibels apart to the ear, and the one Volume per voice in SoundConfig has to
mean the same thing for all five matters.

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
    knock,
    lowpass,
    noise,
    normalize_rms,
    output_dir,
    report,
    soft_clip,
    tone,
    tremolo,
    write_wav,
)

SEED = 0xA0_D10
ATTACK = 0.22

# RMS targets per voice, in linear full scale (-16, -15, -19, -12 dB). The mix lives here and in
# SoundConfig's one Volume per voice; a builder never sets its own level.
LOUDNESS = {"attack": 0.16, "body": 0.18, "tail": 0.11, "impact": 0.25}


def finish(buf: Buf, layer: str) -> Buf:
    return declick(normalize_rms(buf, LOUDNESS[layer]))


# --- Cinnabar ---------------------------------------------------------------------------------------


def embers(rng: Rng, seconds: float, density: float, decay: float) -> Buf:
    """Sparse pops in the upper mids. Sparse is the point: past forty a second the pops overlap into a
    hiss and the fire is any other noise."""
    return bandpass(crackle(rng, R, seconds, density, 0.006, decay), 2400.0, 1.2)


def cinnabar_attack(rng: Rng) -> Buf:
    # The draw of a fire: low, and it does not move. Air moves; fire does not.
    roar = lowpass(noise(rng, R, ATTACK), 500.0).apply(env_swell(R, ATTACK))
    pops = embers(rng, ATTACK, 40.0, 0.0).apply(env_swell(R, ATTACK))
    return finish(roar.add(pops, 0.0, 0.6), "attack")


def cinnabar_body(rng: Rng) -> Buf:
    pops = embers(rng, 0.55, 28.0, 0.3)
    roar = lowpass(noise(rng, R, 0.55), 600.0).apply(env_hold(R, 0.55, 0.03, 0.15))
    return finish(pops.add(roar, 0.0, 0.45), "body")


def cinnabar_tail(rng: Rng) -> Buf:
    pops = embers(rng, 0.9, 18.0, 0.9).apply(env_ad(R, 0.9, 0.01, 0.35))
    roar = lowpass(noise(rng, R, 0.9), 600.0).apply(env_ad(R, 0.9, 0.01, 0.3))
    return finish(pops.add(roar, 0.0, 0.2), "tail")


def cinnabar_impact(rng: Rng) -> Buf:
    # A dry drum, then the pops of what it lit.
    drum = knock(rng, R, 0.55, 190.0, 4.0, 0.1)
    burst = bandpass(noise(rng, R, 0.55), 1400.0, 0.8, 500.0).apply(env_ad(R, 0.55, 0.002, 0.05))
    pops = embers(rng, 0.55, 40.0, 0.9).apply(env_ad(R, 0.55, 0.02, 0.2))
    return finish(echo(soft_clip(drum.add(burst, 0.0, 0.5).add(pops, 0.04, 0.5), 1.5), 0.031, 0.25, 0.4), "impact")


# --- Indigo -----------------------------------------------------------------------------------------


def indigo_attack(rng: Rng) -> Buf:
    swell = lowpass(lowpass(noise(rng, R, ATTACK), 200.0, 1600.0), 400.0, 2400.0).apply(env_swell(R, ATTACK))
    return finish(swell, "attack")


def indigo_body(rng: Rng) -> Buf:
    bed = lowpass(noise(rng, R, 0.6), 700.0).apply(env_hold(R, 0.6, 0.04, 0.12)).apply(tremolo(R, 0.6, 9.0, 0.5))
    out = Buf(R, 0.6).add(bed, 0.0, 0.5)
    for _ in range(14):
        at = rng.uniform(0.0, 0.5)
        f = rng.uniform(500.0, 1500.0)
        blip = tone(R, 0.07, f, f * 1.8).apply(env_ad(R, 0.07, 0.002, 0.015))
        out.add(blip, at, 0.35)
    return finish(out, "body")


def indigo_tail(rng: Rng) -> Buf:
    wake = lowpass(noise(rng, R, 0.9), 1200.0, 200.0).apply(env_ad(R, 0.9, 0.01, 0.28))
    out = Buf(R, 0.9).add(wake, 0.0, 0.6)
    for _ in range(7):
        at = rng.uniform(0.1, 0.8)
        f = rng.uniform(700.0, 1900.0)
        drip = tone(R, 0.09, f, f * 2.2).apply(env_ad(R, 0.09, 0.002, 0.02))
        out.add(drip, at, 0.3)
    return finish(out, "tail")


def indigo_impact(rng: Rng) -> Buf:
    # Water landing on a stretched skin: a wet band, a low struck body, spray.
    splash = bandpass(noise(rng, R, 0.5), 900.0, 0.9, 300.0).apply(env_ad(R, 0.5, 0.003, 0.1))
    skin = knock(rng, R, 0.5, 150.0, 3.0, 0.09)
    spray = highpass(noise(rng, R, 0.5), 3000.0).apply(env_ad(R, 0.5, 0.01, 0.12))
    return finish(echo(splash.add(skin, 0.0, 0.7).add(spray, 0.02, 0.3), 0.031, 0.25, 0.4), "impact")


# --- Umber ------------------------------------------------------------------------------------------


def gravel(rng: Rng, seconds: float, density: float, decay: float) -> Buf:
    """Sparse low pops: stones settling, never a hiss."""
    return lowpass(crackle(rng, R, seconds, density, 0.008, decay), 700.0)


def umber_attack(rng: Rng) -> Buf:
    grind = bandpass(noise(rng, R, ATTACK), 180.0, 1.6, 320.0).apply(env_swell(R, ATTACK))
    grit = gravel(rng, ATTACK, 40.0, 0.0).apply(env_swell(R, ATTACK))
    return finish(soft_clip(grind.add(grit, 0.0, 0.6), 1.4), "attack")


def umber_body(rng: Rng) -> Buf:
    # The grinding is in the mids -- that is what a phone hears -- and the rumble sits under it.
    grind = bandpass(noise(rng, R, 0.6), 260.0, 1.6).apply(env_hold(R, 0.6, 0.05, 0.15))
    rumble = tone(R, 0.6, 52.0, 48.0, ((1.0, 1.0), (1.5, 0.3), (2.0, 0.2), (4.0, 0.15))).apply(env_hold(R, 0.6, 0.05, 0.15))
    dust = lowpass(noise(rng, R, 0.6), 300.0).apply(env_hold(R, 0.6, 0.05, 0.15))
    return finish(soft_clip(grind.add(rumble, 0.0, 0.7).add(dust, 0.0, 0.35), 1.3), "body")


def umber_tail(rng: Rng) -> Buf:
    stones = gravel(rng, 0.9, 22.0, 0.95).apply(env_ad(R, 0.9, 0.01, 0.3))
    settle = lowpass(noise(rng, R, 0.9), 240.0).apply(env_ad(R, 0.9, 0.01, 0.2))
    return finish(stones.add(settle, 0.0, 0.4), "tail")


def umber_impact(rng: Rng) -> Buf:
    # A dead knock on stone, and what it shook loose.
    stone = knock(rng, R, 0.5, 120.0, 2.5, 0.11)
    click = bandpass(noise(rng, R, 0.5), 2000.0, 1.2).apply(env_ad(R, 0.5, 0.001, 0.008))
    debris = gravel(rng, 0.5, 45.0, 0.95).apply(env_ad(R, 0.5, 0.03, 0.12))
    return finish(echo(soft_clip(stone.add(click, 0.0, 0.5).add(debris, 0.04, 0.5), 1.6), 0.031, 0.25, 0.4), "impact")


# --- Verdigris --------------------------------------------------------------------------------------


def verdigris_attack(rng: Rng) -> Buf:
    intake = highpass(bandpass(noise(rng, R, ATTACK), 600.0, 1.2, 3200.0), 400.0).apply(env_swell(R, ATTACK))
    return finish(intake, "attack")


def verdigris_body(rng: Rng) -> Buf:
    gust = bandpass(noise(rng, R, 0.6), 700.0, 0.9, 1400.0).apply(env_hold(R, 0.6, 0.06, 0.18)).apply(tremolo(R, 0.6, 6.0, 0.35))
    air = lowpass(noise(rng, R, 0.6), 1800.0).apply(env_hold(R, 0.6, 0.06, 0.18))
    return finish(gust.add(air, 0.0, 0.4), "body")


def verdigris_tail(rng: Rng) -> Buf:
    wake = bandpass(noise(rng, R, 0.9), 1600.0, 0.8, 400.0).apply(env_ad(R, 0.9, 0.01, 0.3))
    return finish(wake, "tail")


def verdigris_impact(rng: Rng) -> Buf:
    # A slap of air on the page: the band still moves, downward now, over a shallow struck skin.
    slap = highpass(noise(rng, R, 0.4), 900.0).apply(env_ad(R, 0.4, 0.001, 0.03))
    whoosh = bandpass(noise(rng, R, 0.4), 2200.0, 1.0, 500.0).apply(env_ad(R, 0.4, 0.004, 0.1))
    skin = knock(rng, R, 0.4, 240.0, 2.0, 0.05)
    return finish(echo(slap.add(whoosh, 0.01, 0.8).add(skin, 0.0, 0.5), 0.031, 0.25, 0.4), "impact")


# --- Orpiment ---------------------------------------------------------------------------------------


def orpiment_attack(rng: Rng) -> Buf:
    # The nib dragged faster and faster: a resonant scrape that climbs. Noisy, so it is a scratch and
    # not the sci-fi charge-up a rising sine would be.
    scrape = bandpass(noise(rng, R, ATTACK), 900.0, 6.0, 3600.0).apply(env_swell(R, ATTACK))
    fizz = crackle(rng, R, ATTACK, 700.0, 0.0015, 0.0).apply(env_swell(R, ATTACK))
    return finish(scrape.add(fizz, 0.0, 0.5), "attack")


def orpiment_body(rng: Rng) -> Buf:
    # The snap, and a dry knock where a metal ping would have been. No metal on the page.
    snap = noise(rng, R, 0.16).apply(env_ad(R, 0.16, 0.0005, 0.006))
    click = tone(R, 0.16, 2600.0, 900.0).apply(env_ad(R, 0.16, 0.0005, 0.01))
    dry = knock(rng, R, 0.16, 1900.0, 7.0, 0.012)
    return finish(soft_clip(snap.add(click, 0.0, 0.8).add(dry, 0.004, 0.4), 1.5), "body")


def orpiment_impact(rng: Rng) -> Buf:
    # The crack itself, a struck body under it, and the electrical fizz -- the one place a continuous
    # crackle is right, because a fizz is continuous.
    crack = noise(rng, R, 0.4).apply(env_ad(R, 0.4, 0.0005, 0.012))
    body = knock(rng, R, 0.4, 320.0, 3.0, 0.06)
    fizz = crackle(rng, R, 0.4, 600.0, 0.0015, 0.95).apply(env_ad(R, 0.4, 0.01, 0.09))
    return finish(echo(soft_clip(crack.add(body, 0.003, 0.8).add(fizz, 0.02, 0.4), 1.7), 0.031, 0.25, 0.4), "impact")


LAYERS = ("attack", "body", "tail", "impact")
# Orpiment has no tail. A tail is the voice of a flight, and nothing of the school that strikes at once
# ever flies: its four glyphs have no Travel phase, so a tail for it would be a file nothing can play.
MATTERS = {
    "cinnabar": (cinnabar_attack, cinnabar_body, cinnabar_tail, cinnabar_impact),
    "indigo": (indigo_attack, indigo_body, indigo_tail, indigo_impact),
    "umber": (umber_attack, umber_body, umber_tail, umber_impact),
    "verdigris": (verdigris_attack, verdigris_body, verdigris_tail, verdigris_impact),
    "orpiment": (orpiment_attack, orpiment_body, None, orpiment_impact),
}


def generate() -> list[Path]:
    out = output_dir()
    paths: list[Path] = []
    for index, (matter, builders) in enumerate(MATTERS.items()):
        for layer_index, (layer, build) in enumerate(zip(LAYERS, builders)):
            if build is None:
                continue
            # One stream per file, so editing one sound never moves the bytes of another.
            rng = Rng(SEED + index * 16 + layer_index)
            paths.append(write_wav(out / f"{matter}_{layer}.wav", build(rng)))
    return paths


if __name__ == "__main__":
    raise SystemExit(1 if report(generate()) else 0)
