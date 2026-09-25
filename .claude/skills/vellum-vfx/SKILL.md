---
name: vellum-vfx
description: Create, fix, judge or compare a Vellum visual effect (a glyph's cast, flight, impact, residue; a hit; the kit) the way it was done for the Brand (D-119) -- live ink with a heated core, three beats, seen frame by frame in the Studio lab, scored on a grid, iterated at least twice, before/after sheets. Use whenever a VfxTimelineConfig timeline or the VfxTimeline renderer changes.
---

# Vellum VFX

An effect is right when a player reads **who, what and where** in a single frame from the camera they
actually have, and the hit feels like a hit. It is never judged in code: it is judged in the lab, frozen,
from three cameras. This is the method that took the Brand from 1/1/2/2/1/4 to 4/4/5/4/4/4.

## The contract (non-negotiable)

1. **No gameplay, no server timing.** Damage frames, windups, speeds, radii, cooldowns stay. The server
   sends `{Id, Origin, Direction, Caster, Params}`; the client draws. Anything that would move or affect
   a target is a separate decision, proposed in `docs/DECISIONS.md`, never slipped into a visual.
2. **Draw the truth.** A flight rides one Carrier at the server's speed (`tests/Flight.spec.luau`); a
   warning fills the server's window; a burst is the radius the server used. Such plays are **steady**
   (`VfxTimelineConfig.steady`): the impact freeze never holds them.
3. **One system.** Timelines are data (`src/shared/Config/VfxTimelineConfig.luau`), drawn by
   `VfxTimeline` on its one Heartbeat, pooled (`VfxPool`), budgeted (`QualityConfig`). Improve that; never
   build a second renderer, never hard-code a colour or a `LightEmission`.

## The recipe

**Three beats**, each where the eye already is:

| Beat | What | Numbers that worked |
|---|---|---|
| Born in the hand | automatic for every glyph: the local `Tap` on the press, then the shared `Cast` (blot of pigment, hot core, seal that snaps open and folds) **at the hand** (`Anchor = "Hand"`, Offset `{0.8, 0.8, 0.2}`: outside the body, seen past the shoulder). The glyph adds only its own release gesture (sparks `Emit = "Aim"`, an ink crescent) | blot 0.3→2.2, core 0.2→0.9, `Pop` 0.25, life 0.1-0.16 s; seal 0.08 + fold 0.08 s |
| Flight / wave | the body of the spell in pigment; a **bare tapered ribbon** of ink behind it and a hot line inside; embers and beads shed | ink ribbon 1.1→0.05, core 0.5→0.02, `Ribbon` 0.12-0.2 s, **no texture** |
| Impact | strongest beat: hot flash that pops, ring of pigment face-on to the thrower, star of hot sparks, **vertical geyser of ink** (clears the thrower's head), beads that fall (`Weight`), crown/ensō on the floor, scraps | flash 1→5 `Pop` 0.3, ring 1→18 in 0.25 s Quart Out, star 24 @ 26-52 st/s, geyser 12 @ Spread 35 |
| Trace | a burn that dries: pigment blot over ink cracks, embers rising | marks 2.6-3 s, embers 0.7 s |

**Layers, by role** (`Role`; never a colour -- every role derives from the caster's pigment and skin):

| Role | Rendered as | Rules |
|---|---|---|
| `Pigment` (default) | the pigment, wet then drying | the body of everything |
| `Core` | pigment heated 72 % toward white, cooling into it; may `Glow` (<= `VfxConfig.MaxGlow`) and `Brightness` > 1 | **only** a core shines; small, central, never alone in its phase (a pale core on vellum is a pale smudge); never pure white (rule 7) |
| `Ink` | the page's charcoal | contour, geyser, trail, cracks: what detaches a pale effect from a pale floor |

**Palettes** (heated core / pigment / wet / dry; ink is always `#17150F`):
Cinabre `#F4C8C1 #D93A22 #DB4E37 #B2331E` · Indigo `#C4CCDF #2E4A8C #445C94 #293F73` ·
Terre d'Ombre `#D6CCC5 #6B4A2F #7A5C42 #5A3F29` · Vert-de-gris `#CEE7DF #4FA88C #61AF94 #448B73` ·
Orpiment `#F9EDC1 #E8C022 #E8C437 #BE9E1E`. Gold belongs to Orpiment only.

**Motion**: nothing linear (rule 4); pop 0 -> 120 % -> 100 % (`Pop`, `VfxConfig.PopOvershoot`); stretch
along motion (`Squash` on `SparkStreak`, the drop's `Stretch`); spin (`Spin`, `Jitter` for variation);
sparks along the aim (`Emit = "Aim"`), a geyser straight up, never a narrow burst up by accident.
**Shapes**: sharp and tapered. No identical parallel strokes, no grey uniform cloud (smoke that drifts
over a target reads as dirt: short lives, `Weight`, or nothing).

**Feel** (automatic, check it): the impact freeze (`Feel.hitStop` -> `VfxClock.hold`, 0.04-0.09 s from
0.04 s after the hit, effect clock only), the target's outline (`Feel.flash`), shake, page flash (it
bites, it never bleaches). **Power scaling**: ultimates are the same recipe larger and longer (`Scale`,
more layers in the budget), not a different language. **Accessibility**: "Shakes and flashes" off
calms cores (`VfxConfig.Calm`), shakes and flashes -- nothing to add, but never bypass `glowOf` /
`brightnessOf`. **Performance**: peak <= 12 layers per timeline, <= 400 particles, 4x in every pool
(`tests/EffectCost.spec.luau`); lights and flourishes drop on low tiers -- the effect must still read.

## The method

1. **Audit.** `lune run .claude/skills/vellum-vfx/scripts/style_audit` -- where each glyph stands.
   Read its timeline, its server effect (`GlyphEffects`), when damage lands vs when the visual lands.
2. **Before sheet.** In the lab (below): cast, depart, travel, impact, +0.1, +0.3, end; game / side /
   impact cameras. `docs/vfx/<glyph>/avant.json` + `planche.py`. Diagnose each frame in a table.
3. **Score** on the grid (below). Write it in `docs/vfx/<glyph>/README.md`.
4. **Rewrite** the timeline to the recipe, within the tests (4+ layers, anticipation, residue, a light,
   a mark on every impact, voices, peak and particle ceilings). `./scripts/check.sh`.
5. **Sync and look.** Stop play, sync, start play, shoot the moments again. Fix the **weakest criterion
   first**. At least **two rounds**, each with its sheet (`tour1`, `tour2`...) and scores.
6. **Stress and tiers.** `stress {glyph, count = 6}` and `{..., quality = "Performance"}`; a frame at
   the Performance tier must still read.
7. **Before/after sheet** (`avant-apres.json`, rows `avant` / `apres`, same moments).
8. **Tests and docs.** A rule the lab taught goes into `tests/VfxStyle.spec.luau` (or the spec that owns
   it) and is proved by mutation. `docs/DECISIONS.md` for a new rule, `docs/PROGRESS.md`,
   `docs/PERFORMANCE.md` table (`lune run scripts/effect-cost -- --table`). Commit on the VFX branch.

## The lab (Studio only, never in a published game: D-118)

Needs: Studio open on the place, the Studio MCP, `tools/vfxlab/VfxLab.client.luau` in
StarterPlayerScripts (`tools/vfxlab/vfxlab.project.json`). Without Rojo connected, serve `src` and
`tools/vfxlab` on localhost and pull them in Edit (`HttpService`, local copy only;
`ScriptEditorService:UpdateSourceAsync` for `VfxTimelineConfig`, over 200 000 characters).

In the Client datamodel: `local lab = game.ReplicatedStorage.VfxLab`
- `lab:Invoke("aim", {dummy = 1, distance = 20})`, then **wait 2 s** (the server must see the new facing,
  or the first throw flies sideways);
- `lab:Invoke("shoot", {glyph = "Brand", moment = "impact", offset = 0.04, slow = 0.02})` -- moments
  `cast depart travel impact impact+0.1 impact+0.3 end`; `slow` 0.01 for any frame with a **trail** (a
  trail ages in real time while frozen), 0.02-0.05 for impacts, 0.1 otherwise;
- `lab:Invoke("view", {name = "game" | "side" | "impact"})`, then `screen_capture` (no camera params);
- `lab:Invoke("resume", {})`, `task.wait(4)` before the next shot (leftovers pollute frames);
- `lab:Invoke("stress", {glyph = "Brand", count = 6, quality = "High"})` -> frame times, peak layers.

Sheets: `python3 tools/vfxlab/planche.py <sheet.json> <session transcript .jsonl> <out.jpg>` (frames by
capture id; `view` rows, or `row` labels for comparisons).

## Scoring grid (/5, per glyph, per round)

| Criterion | 1 | 3 | 5 |
|---|---|---|---|
| Lisibilité | nothing reads from the game camera | each beat reads from one camera | who / what / where in one frame, every camera |
| Contraste | pale on pale, lost on the floor | reads on vellum, lost on the training ring | ink and pigment detach it on every floor |
| Couleur du pigment | grey, white or another school | the pigment, but washed or muddy | its school at a glance, heated core, dry trace |
| Dynamisme | appears, drifts, linear | eased, some stretch | pop, stretch, spin, anticipation -> release -> impact |
| Impact | same weight as the flight | a burst | the strongest frame: freeze, ring, star, geyser, outline |
| Performance | over a ceiling | within ceilings | within ceilings, 6 at once at 60 fps, reads at the Performance tier |

## Pitfalls (each cost a round)

- A texture on a **Trail** is stretched over its whole length: the brush stroke rendered as a faint
  smudge. Bare ribbons with a `WidthScale` taper read as clean wedges.
- A **core alone** is invisible on vellum; a **global** freeze desyncs server-timed plays (steady clock).
- The **game camera** puts a target straight ahead behind the caster's head: make the impact rise.
- Changing `Trail.Lifetime` mid-life wipes the ribbon (the lab sets it once, at build).
- A `ParticleEmitter` with no `EmissionDirection` fires **up**; pale sparks vanish on a pale floor.
- Sparks at twenty studs are grey dashes, and a brush stroke on a square plane is a smudge: for a spike,
  a serif, a spurt, use `InkSpike` on a `Sprite` with `Face = "Camera"`, centred on the floor (its root is
  the image's middle line, so it rises out of the page as it grows).
- A plane that faces the aim is a hairline to everyone beside it: `Face = "Camera"` for rings and spikes.
- A hitscan or a step is as long as the server says, not as the glyph's range: `TravelFrom = "Reach"`
  with the packet's Range passed as `Reach` (D-126). A "renderer contract" in a comment is not one.
- Where a glyph hurts is the server's, not the packet's `Origin`: read `GlyphEffects` (the Sweep sends
  the caster and an offset; the Wash hurts at the rim of a sphere, not at its centre).
- A frequent or pale core (a hit, Verdigris) stays under the bloom threshold (`Brightness` < 1.6): bloomed
  it fogs a fight, and heated Verdigris turns cyan -- an ally's colour (rule 7).
- A new texture: `tools/textures/<family>.py` + `generate_all.py`, measure a square one
  (`check_ink.py`), `python3 scripts/upload_assets.py upload --only=<png>`; it renders once moderated.
- Background Studio drops under 40 fps and the auto quality turns lights off: the lab pins the tier.
- A **fire** is not a stain: a blot on the floor reads as a puddle ("les flammes c'est des flaques", D-123).
  `InkFlame` on an Emitter (kept upright: `VfxConfig.UprightTextures`), `Sway` 8-16, over an `Area` (a
  stroke) or its rim (`Ring`, at the server's radius), size 3 -> 0.3, a Core heart low in it, Ink soot above.
- A **status on a body** (armour, buff) is drawn as the body: an `Outline` layer (Highlight, ink contour,
  pigment wash, Occluded) for the server's whole duration; particles on a body vanish into it (D-125).
- The engine **thins a `Rate`** by its automatic quality (80 flames/s showed 5 in real time; the slow lab
  showed 40): anything whose density is its meaning is `Driven` (emitted by the renderer, D-124). Judge
  dense effects at `slow = 1` too.
