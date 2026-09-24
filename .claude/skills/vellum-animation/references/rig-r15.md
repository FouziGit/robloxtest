# The R15 rig, as keyed.py sees it

## Axes and order

- Roblox space: **+X right, +Y up, the character faces −Z**. Blender (previews) is Z-up facing −Y;
  `preview_blender.py` converts with `(x, y, z) -> (−x, z, y)` (a rotation, nothing mirrored).
- A key's angles are **Euler degrees `[rx, ry, rz]`**, `CFrame.Angles` order (Rx·Ry·Rz), in the
  **parent part's frame**. A Pose's CFrame is exactly the joint's `Transform`.
- FK: `part1 = part0 · C0 · Transform · C1⁻¹`. On AJU avatars (AnimationConstraints) the attachments
  carry **no rotation** (measured), so C0/C1 are offsets only: the rig files store positions.

## Joints, by the part a clip names

| Clip key | Joint | Parent part |
|---|---|---|
| `UpperTorso` | Waist | LowerTorso |
| `Head` | Neck | UpperTorso |
| `RightUpperArm` / `LeftUpperArm` | Right/LeftShoulder | UpperTorso |
| `RightLowerArm` / `LeftLowerArm` | Right/LeftElbow | the upper arm |
| `RightHand` / `LeftHand` | Right/LeftWrist | the lower arm |
| `LowerTorso` | Root | HumanoidRootPart (moves the legs too: avoid) |
| legs | Hips, Knees, Ankles | — (leave to locomotion) |

## Signs (measured on the standard rig with `keyed.world`)

| Key | + does | − does |
|---|---|---|
| `RightUpperArm` rx | raises the arm **forward** (90 = horizontal, hand at z −1.7) | swings it back |
| `RightUpperArm` rz | lifts it **outward** to the right (abduction) | brings it across the body |
| `LeftUpperArm` rx | forward | **back** (−40: hand at z +1.1) |
| `LeftUpperArm` rz | across the body | lifts it **outward** to the left |
| `*UpperArm` ry | twists about its long axis (the joint is off-centre: it also swings a little) | |
| `*LowerArm` rx | bends the elbow, forearm forward/up | hyperextends: never |
| `*Hand` rx | tips the hand forward (a flick, with the arm raised: fingers up) | back |
| `UpperTorso` rx | leans back | leans **forward** (−15: head 0.6 stud forward) |
| `UpperTorso` ry | turns the chest left: **right shoulder forward** (a right-hand throw) | left shoulder forward |
| `UpperTorso` rz | raises the right shoulder (side bend to the left) | raises the left |
| `Head` ry | looks left | looks right: counter a torso ry to keep the eyes on the target |

A right-hand throw at the drop in front: torso ry +26, rx −14; arm rx ≈ 90 − (angle below horizontal)
+ |torso rx|; head ry ≈ −0.8 × torso ry.

## Weights: upper body only

A Pose with **Weight 0** leaves its joint to whatever plays underneath. keyed.py writes every part on
the way down to a keyed joint (HumanoidRootPart, LowerTorso) as weight 0, and nothing for the legs.
Measured in Studio on a walking character: weight 0 kept the Root's walk bob (12.7°, 0.21 stud) and the
hip swing; a weight-1 identity LowerTorso froze the Root flat (0°).

## The measured rigs (`tools/animations/rigs/`)

- `standard.json` -- `Players:CreateHumanoidModelFromDescription` with a default description (hip
  height 2.19). The proportions most players have.
- `developer.json` -- the developer's own avatar (hip height 1.89): a very wide torso (3.3 studs) and
  short arms. Its hand sits ~2 studs out to the side; a thrust at the viewer foreshortens to a fist in
  front of the belly.

Re-measure (Client or Server datamodel, a character in the workspace): for each AnimationConstraint or
Motor6D joint, record `name`, `part0`, `part1` and its attachments' positions (`Attachment0.Position`
-> `c0`, `Attachment1.Position` -> `c1`), and each part's `Size`. Keep the JSON shape of the existing
files (`hipHeight`, `rigType`, `parts[name].size`, `joints[]`).
