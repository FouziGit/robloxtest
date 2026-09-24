---
name: vellum-animation
description: Author, fix or retime a Vellum animation clip (a glyph's cast first, then strikes and reactions) the way an animator works -- key poses, curves, secondary motion, numbers -- keyed on the server's timing, previewed in headless Blender, tested live in Studio before any upload, shipped through .rbxmx -> scripts/upload_assets.py -> AnimationConfig.luau. Use whenever an animation in Vellum is created, judged, compared or changed.
---

# Vellum animation

A clip is right when it arrives **with** the thing it shows, reads from every camera, and never pops.
This skill is the method that got the Brand from "the hand is 2.2 studs behind the body when the spell
leaves" to "the palm is in the seal at 0.06 s" (D-117). Follow it in order; every step has a check.

## What must be open

| For | Needed |
|---|---|
| Keying, checks, build | nothing: `tools/animations/keyed.py` is plain Python |
| Previews | Blender installed (`/Applications/Blender.app`, or `BLENDER=`), **not open**: it runs headless |
| Live test | Roblox Studio on the place, **Rojo connected**, a play session running (Studio MCP) |
| Upload | the developer's **explicit yes**, every time: it publishes to Roblox |

Never open or modify a `.blend` of the project; the tool needs none. No Blender MCP, no third-party
script: everything here is in the repository.

## The timing contract (non-negotiable)

1. **The server decides** when a glyph leaves. Never change a Windup, a cooldown, a hit frame or any
   gameplay number to suit a clip. Ideas that would need one go in a proposal, not in the code.
2. The drawn glyph acts when its timeline has drawn its **Anticipation + Cast** (where a Travel starts;
   for a held throw that is also `Params.Windup`, held together by `tests/Flight.spec.luau`).
3. The clip's `release` key sits **exactly** on that moment. `tests/AnimationConfig.spec.luau` fails
   otherwise. Get every glyph's moment with
   `lune run .claude/skills/vellum-animation/scripts/glyph_timings` (table in references/glyph-timings.md).
4. Moves starts the clip on the Cast packet with a **0.06 s fade**: the first frames are half-weighted.
   A release before ~0.05 s cannot be seen; see references/pitfalls.md for glyphs that act at 0 s.

## The method

Work in a scratch folder (the session scratchpad), never in the repository, for renders.

1. **Measure before touching anything.** Play the glyph in Studio with the current clip and log where
   the hand is at the release (`scripts/studio_test.py hook <clip> before`, below). Write the number
   down: it is the "before".
2. **Key poses first (blocking).** Create `tools/animations/keyed/<name>.json` (copy
   `brand_throw.json`): `name`, `file`, `glyph`, `release`, `hand`, and keys with `"ease": "Hold"`.
   Minimum: rest at 0, the **release** pose, an **overshoot**, the end of a **hold**, a recovery
   breakdown, rest at the end. Angles are Euler degrees, CFrame.Angles order, in the parent part's
   frame; signs are in references/rig-r15.md. Upper body only (UpperTorso, Head, arms) unless the
   developer asks otherwise: the legs keep walking.
   Render: `python3 tools/animations/keyed.py preview <clip.json> <out>` -> one sheet per rig
   (standard R15 and the developer's avatar), columns = keys, rows = front / side / 3-4 / game camera.
   **Look at it**, fix the poses, re-render, until each key reads alone as a silhouette.
3. **Curves.** Replace `Hold` with eases: `Auto` (smooth monotone curve through the keys, the default),
   a named ease where a blow must accelerate into its contact (`QuadIn` into the release) or settle
   (`QuadOut` into the overshoot, `SineInOut` for a moving hold). `Linear` is refused by the tool.
   Render the in-betweens (`preview ... 0 0.033 0.05 ...`) and every frame (`preview ... all` -> GIFs).
4. **Secondary motion.** Overshoot and settle; overlap (the off hand and the wrist arrive a frame or
   two after the lead hand); asymmetry (never mirror both arms); the head keeps the target. Re-render.
5. **Numbers.** `python3 tools/animations/keyed.py check <clip.json>`: fastest turn per 60 fps frame
   (< 40°), start and end within 4° of rest, the hand in front of the body at the release on both rigs.
   It prints the hand's position; keep it near the effect's origin (references/glyph-timings.md).
6. **Build.** `python3 tools/animations/keyed.py all` writes `assets/animations/<file>`; it refuses a
   clip that fails step 5.
7. **Wire it.** In `src/shared/Config/AnimationConfig.luau`: a `Clips` entry
   (`clip("<file>", <seconds>, false, "Action", 1, 0)`) and a `CastByGlyph` line. Moves and Posture need
   nothing else: both ask `AnimationConfig.castClip`. Until uploaded, the glyph keeps the generic cast.
8. **Test live, before any upload** (Client datamodel, play session running):
   - `python3 .claude/skills/vellum-animation/scripts/studio_test.py register <clip.json>` -> run it;
   - `... hook <clip.json> after` -> run it, then cast the glyph with `user_keyboard_input`
     (pigment keys: references/glyph-timings.md), then `screen_capture` within 8 s (the pose is frozen);
   - `... result` -> the hand, frame by frame, from the packet; compare with the `before`;
   - look from the opponent's side by moving **this client's** camera (references/pitfalls.md);
   - `get_console_output`: no error from the game; then `... cleanup`.
9. **Gates.** `./scripts/check.sh` all green (it rebuilds every keyed clip and fails if the committed
   file differs). Stage new files first: an untracked `.rbxmx` fails the gate on purpose.
10. **Document.** One `docs/DECISIONS.md` entry for a new kind of clip or rule; the before/after numbers;
    `docs/PROGRESS.md`. Commit (Conventional Commits) on a branch.
11. **Upload -- only with the developer's yes.** `python3 scripts/upload_assets.py plan` (no network),
    show them the list, then `python3 scripts/upload_assets.py upload`. It writes the id into
    `AnimationConfig.luau`'s UPLOADED block and the lock; commit that. Never type or print the key.

## Done means

- [ ] The release key is on the glyph's moment (test green), and nothing in gameplay changed.
- [ ] Key poses read alone, from the front, the side, 3-4 and the game camera, on both rigs.
- [ ] No linear curve; overshoot, overlap and asymmetry visible in the GIFs.
- [ ] `keyed.py check` OK: no pop, rest at both ends, hand in front at the release.
- [ ] Measured in Studio on a real cast: the hand where the effect starts, at the release; before/after
      numbers written down; console free of game errors; test helpers cleaned up.
- [ ] Legs untouched (a cast on the run keeps its feet), unless asked.
- [ ] `./scripts/check.sh` green; decision and progress written; committed.
- [ ] Upload done **only** after an explicit yes, id committed; or the command left ready.

## The chain

```
tools/animations/keyed/<name>.json  --keyed.py all-->  assets/animations/<file>.rbxmx
      --scripts/upload_assets.py upload (developer's yes)-->  assets/roblox-assets.lock.json
      --> AnimationConfig.luau UPLOADED block --> Clips / CastByGlyph --> castClip --> Moves plays it
```

Retargeted CC0 clips (strikes, guard, flinch) come from `tools/animations/retarget.py` in Blender
through `generate_all.py` + `clips.json`; re-key one by hand with this skill to replace it.

## References

- `references/rig-r15.md` -- axes, joint names, the sign of every useful rotation, the measured rigs.
- `references/export.md` -- KeyframeSequence format, weights, upload and config details.
- `references/glyph-timings.md` -- when each glyph acts, its keys, where its effect starts.
- `references/pitfalls.md` -- what went wrong once and how it was caught.
- `scripts/glyph_timings.luau`, `scripts/studio_test.py` -- the two helpers above.
