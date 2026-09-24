# Export, upload, config

## What keyed.py writes

- A `KeyframeSequence` `.rbxmx`, the same XML as `retarget.py` (Roblox model format, `version="4"`),
  `Loop` false, `Priority` token from the clip (`Action` = 2).
- One `Keyframe` per 60 fps frame **plus the last key exactly** (0.58, not 0.583): the curve is baked,
  so each Pose uses `EasingStyle` 0 between frames -- the motion's shape lives in the bake, not in
  Roblox's easing.
- Pose tree mirrors the R15 part tree from `HumanoidRootPart`. Keyed parts: weight 1. Parts on the
  way down to them: identity, weight 0. Unrelated parts (legs): absent.
- Numbers at six decimals, `-0.000000` written as `0.000000`: the bytes must be identical on every
  machine, because `scripts/check.sh` and CI rebuild the file and fail on any difference.

## Clip file fields (`tools/animations/keyed/<name>.json`)

| Field | Meaning |
|---|---|
| `name` | KeyframeSequence name and the `AnimationConfig.Clips` key |
| `file` | output under `assets/animations/` |
| `glyph` | the glyph whose cast it is (`CastByGlyph[glyph] == name`, tested) |
| `priority`, `fps` | `Action`, 60 |
| `release` | the key time on the glyph's moment (tested against its timeline and Windup) |
| `hand` | the part checked in front of the body at the release |
| `keys[]` | `t`, `ease` (to the next key: `Auto`, `Hold`, `<Quad|Cubic|Quart|Sine|Back|Expo><In|Out|InOut>`), `pose` |
| `checks` (optional) | `restDegrees` (4), `maxDegreesPerFrame` (40) |

## Config

`AnimationConfig.Clips.<Name> = clip("<file>", <seconds = last key>, false, "Action", 1, 0)` and
`AnimationConfig.CastByGlyph.<GlyphId> = "<Name>"`. `tests/AnimationConfig.spec.luau` checks the file
exists, its length and loop flag, that exactly one generator produces it, the release, the weights and
the fallback. Speed stays 1: the clip is keyed at the real pace; speeding it would move the release.

## Upload (only with the developer's explicit yes)

```bash
python3 scripts/upload_assets.py plan      # no network: lists what would go up
python3 scripts/upload_assets.py upload    # Open Cloud; key from .env.local, never printed
```

It records the file's SHA-256 in `assets/roblox-assets.lock.json` and rewrites the `UPLOADED` block of
`AnimationConfig.luau`; `tests/UploadedAssets.spec.luau` holds block, lock and bytes together. A clip
rebuilt after its upload needs `upload --reupload` (a new asset). An animation uploads as a model
(`.rbxmx`, `model/x-rbxm`), owned by the key's creator.
