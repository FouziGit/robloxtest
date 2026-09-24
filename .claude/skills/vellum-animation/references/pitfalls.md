# Pitfalls met once, and how they were caught

## Timing

- **Keying the release after the fade.** Moves fades a clip in over 0.06 s; at 0.03 s the clip is at
  half weight. Accelerate into the release (`QuadIn`) so the arm is seen arriving, not appearing.
- **Two blows at the same priority blend.** A strike and a cast both at `Action` were averaged into a
  pose that was neither. Moves now stops the current blow when the next one starts.
- **Gameplay drift.** An anticipation that reads better by moving the release later is a gameplay
  change (the glyph would leave later at every range). Propose it; never apply it with a clip.

## Posing

- **Legs keyed = feet slide.** The retargeted clips key every joint; a cast on the run slid its feet.
  Key the upper body; the tests fail if a keyed clip weights a leg or the LowerTorso.
- **Weight-1 placeholder freezes the root.** An identity LowerTorso pose at weight 1 flattened the walk
  (Root 0° instead of 12.7°). Placeholders are weight 0.
- **A thrust at the viewer foreshortens.** From the front, an arm pointed at the camera is a fist in
  front of the belly, worse on short-armed avatars. What reads from the front is the torso turn, the
  lean and the off hand pulled back; check the front view, not only the side.
- **Twinning.** Both arms mirrored read as a robot. Offset the off hand by a frame or two and give it
  different angles.

## Tooling

- **Hold at a key's own time.** A `Hold` segment must give the NEXT key on its time, not the previous
  one: the first sampler returned the old pose on the key frame (the hand read "behind the body" at the
  release). Fixed; `keyed.py check` would show it as the hand not in front.
- **Mixed eases jerk.** A named ease next to a smooth curve must hand over its own speed, or the curve
  stops dead at the key. `slopes()` matches it.
- **`-0.000000`.** Rotation maths leave sign-random crumbs where a zero should be; formatted, they made
  bytes that could differ between machines. Written as `0.000000`.
- **sed on a pretty-printed JSON** silently matches nothing: keep one key per line (as the clip files
  are) or edit with Python, then confirm with `git diff`.
- **An untracked `.rbxmx` fails `check.sh`** on purpose. `git add` it before running the gates.

## Studio (MCP)

- **A `require` in `execute_luau` is a fresh copy** of the module: changing a config table there does
  not change the running game. Register the clip and play it yourself (`scripts/studio_test.py`).
- **`RegisterKeyframeSequence` ids are this client's only.** The server and other clients keep the
  generic clip; so does `screen_capture` called **with** a camera position -- it showed the idle pose.
  To see another angle, set this client's `workspace.CurrentCamera` (Scriptable, `CFrame.lookAt`) and
  call `screen_capture` without a position. Studio resets the camera type after `execute_luau`, which
  is harmless for one capture; `cleanup` restores it anyway.
- **Studio renders ~15 fps in the background**: `RenderStepped` logs every ~65 ms. Read timing from the
  clip's `TimePosition`, not from how many frames were logged.
- **Freeze to capture.** The capture tool takes a moment; the hook freezes the pose (`AdjustSpeed(0)`)
  for 8 s just after the release, so the capture shows the release pose with the effect already flying.
- **Cooldowns.** A second cast inside the glyph's cooldown is refused silently; wait it out.
- **Console noise that is not an error**: DataStore/leaderboard warnings in Studio without API access,
  missing monetization ids. An error from your own test snippet is yours, not the game's.
