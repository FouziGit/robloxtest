# When each glyph acts

Regenerate with `lune run .claude/skills/vellum-animation/scripts/glyph_timings` (reads the configs).
"Release" is where a cast clip's release key goes: the end of the glyph timeline's Anticipation + Cast.

| Glyph | Combo | Archetype | Server hold | Release (drawn glyph acts) | Own cast |
|---|---|---|---|---|---|
| Brand | Cinnabar + Cinnabar | Projectile | 0.06 s | 0.06 s, then travels | BrandThrow |
| Wash | Indigo + Indigo | Aoe | none (starts at 0) | 0.10 s, then travels | WashSweep |
| Serif | Umber + Umber | Aoe | none (starts at 0) | 0.03 s | generic |
| Sweep | Verdigris + Verdigris | Aoe | none (starts at 0) | 0.00 s | generic |
| Bleed | Indigo + Cinnabar | Zone | none (starts at 0) | 0.00 s | generic |
| Margin | Indigo + Indigo + Umber | Wall | none (starts at 0) | 0.25 s | generic |
| Scorch | Cinnabar + Cinnabar + Verdigris | Zone | none (starts at 0) | 0.32 s | generic |
| Rupture | Umber + Umber + Umber | Ultimate | none (starts at 0) | 0.07 s | generic |
| Ligature | Cinnabar + Verdigris | Mobility | none (starts at 0) | 0.07 s, then travels | generic |
| Blot | Cinnabar + Cinnabar + Umber | Ultimate | none (starts at 0) | 0.28 s, then travels | generic |
| Binding | Indigo + Verdigris | Counter | none (starts at 0) | 0.22 s | generic |
| Stipple | Umber + Indigo | Projectile | none (starts at 0) | 0.12 s, then travels | generic |
| Gilding | Umber + Verdigris | Buff | none (starts at 0) | 0.38 s | generic |
| Hairline | Verdigris + Cinnabar | Projectile | none (starts at 0) | 0.03 s, then travels | generic |
| Spiral | Verdigris + Verdigris + Indigo | Zone | none (starts at 0) | 0.10 s | generic |
| Pounce | Verdigris + Verdigris + Umber | Zone | none (starts at 0) | 0.12 s | generic |
| Strike | Orpiment + Orpiment | Projectile | none (starts at 0) | 0.21 s | generic |
| Caret | Orpiment + Verdigris | Mobility | none (starts at 0) | 0.18 s | generic |
| Watermark | Orpiment + Orpiment + Umber | Zone | none (starts at 0) | 0.00 s | generic |
| Colophon | Orpiment + Orpiment + Orpiment + Orpiment | Ultimate | none (starts at 0) | 0.38 s | generic |

## Keys

Default keyboard: Cinnabar `J`, Indigo `K`, Umber `L`, Verdigris `H`, Orpiment `U`
(`InputConfig.DefaultKeyboard`; a saved profile may differ). A combo is its pigment keys pressed in
order, ~80 ms apart, e.g. the Brand is `J`, `J`. Wait out the glyph's cooldown between casts.

## Where the effect starts (aim the hand there)

- **Brand**: the drop gathers at `Offset {0, 0.4, 4}` from the caster, along the cast direction (4
  studs ahead, 0.4 above the root) and flies from there (`SpawnOffset` 4).
- **Wash**: the front starts on the floor at `SpawnOffset` 6 studs ahead and sweeps to its range in
  0.8 s; its brush-loading draw-in happens around the caster.
- Others: read the glyph's `Params` in `GlyphConfig.luau` and its timeline's first layers' `Offset` in
  `VfxTimelineConfig.luau`.

## Glyphs that act at 0 s

`Bleed` and `Watermark` have no Anticipation or Cast phase: they act on the packet. A release at 0 is
under the 0.06 s fade-in and cannot be seen. Their clip can only be a follow-through that starts from
rest, which the release test forbids; giving the effect an anticipation first is a VFX decision for
the developer, not something to slip into an animation change.
