#!/usr/bin/env python3
"""Prints the Luau that tests a keyed clip live in Studio, before anything is uploaded. Each command
prints one snippet, to run with the Studio MCP's execute_luau in the **Client** datamodel of a play
session:

    python3 .claude/skills/vellum-animation/scripts/studio_test.py register <clip.json>
    python3 .claude/skills/vellum-animation/scripts/studio_test.py hook <clip.json> before|after [freeze]
    python3 .claude/skills/vellum-animation/scripts/studio_test.py result
    python3 .claude/skills/vellum-animation/scripts/studio_test.py cleanup

register  builds the clip's KeyframeSequence from the committed .rbxmx (rotations as quaternions, four
          decimals) and registers it with KeyframeSequenceProvider: a temporary id, this client only,
          nothing published. The id is kept in ReplicatedStorage.__AnimTest.
hook      listens to the glyph's real Cast packet (VfxReliable). "before" measures whatever Moves plays
          today; "after" stops the generic cast clip and plays the registered one, with Moves' fade. Both
          log, every rendered frame for 0.3 s, the clip time, its weight and the throwing hand in the
          root's space (-Z is forward), and freeze the pose at `freeze` seconds of clip (default: the
          release plus 0.05) for 8 s so a screen capture can see it.
result    returns the log of the last cast.
cleanup   disconnects the hook, restores the camera and removes the helpers.

The registered clip exists on this client only: the server and every other client see the generic
cast, and so does a screen_capture given a camera position (it is not drawn from this client). To look
from another angle, move this client's camera (see references/pitfalls.md).
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "animations"))

import keyed  # noqa: E402  (the path is set just above)


def frames_of(rbxmx: Path):
    """(time, {part: (x, y, z, w)}) for every keyframe, weighted poses only."""
    seq = ET.parse(rbxmx).getroot().find("Item")
    out = []
    for keyframe in seq.findall("Item"):
        t = float(keyframe.find("Properties/float[@name='Time']").text)
        pose = {}
        for item in keyframe.iter("Item"):
            if item.get("class") != "Pose":
                continue
            props = item.find("Properties")
            if float(props.find("float[@name='Weight']").text) == 0:
                continue
            cf = props.find("CoordinateFrame")
            rotation = [[float(cf.find(f"R{i}{j}").text) for j in range(3)] for i in range(3)]
            w, x, y, z = keyed.mat_to_quat(rotation)
            pose[props.find("string[@name='Name']").text] = (x, y, z, w)
        out.append((t, pose))
    return out


def register(clip_path: str) -> str:
    clip = keyed.load_clip(clip_path)
    frames = frames_of(keyed.OUT / clip["file"])
    joints = clip["joints"]
    rows = []
    for t, pose in frames:
        values = ",".join("%.4f,%.4f,%.4f,%.4f" % pose[j] for j in joints)
        rows.append("{%s,%s}" % (round(t, 4), values))
    parents = ", ".join(f'{j} = "{keyed.PARENT[j]}"' for j in joints)
    chain = sorted(keyed.keyed_parts(clip) - set(joints) - {"HumanoidRootPart"})
    return f"""local J = {{{",".join(repr(j) for j in joints)}}}
local CHAIN = {{{",".join(repr(p) for p in chain)}}}
local F = {{{",".join(rows)}}}
local KSP = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PARENT = {{ {parents}, {", ".join(f'{p} = "{keyed.PARENT[p]}"' for p in chain)} }}
local seq = Instance.new("KeyframeSequence")
seq.Loop = false
seq.Priority = Enum.AnimationPriority.{clip.get("priority", "Action")}
for _, row in ipairs(F) do
	local kf = Instance.new("Keyframe")
	kf.Time = row[1]
	local poses = {{}}
	local root = Instance.new("Pose")
	root.Name = "HumanoidRootPart"
	root.Weight = 0
	root.Parent = kf
	poses.HumanoidRootPart = root
	for _, name in ipairs(CHAIN) do
		local pose = Instance.new("Pose")
		pose.Name = name
		pose.Weight = 0
		poses[name] = pose
	end
	for i, name in ipairs(J) do
		local b = 1 + (i - 1) * 4
		local pose = Instance.new("Pose")
		pose.Name = name
		pose.Weight = 1
		pose.CFrame = CFrame.new(0, 0, 0, row[b + 1], row[b + 2], row[b + 3], row[b + 4])
		poses[name] = pose
	end
	for _, name in ipairs(CHAIN) do
		poses[name].Parent = poses[PARENT[name]]
	end
	for _, name in ipairs(J) do
		poses[name].Parent = poses[PARENT[name]]
	end
	kf.Parent = seq
end
local holder = ReplicatedStorage:FindFirstChild("__AnimTest") or Instance.new("StringValue")
holder.Name = "__AnimTest"
holder.Value = KSP:RegisterKeyframeSequence(seq)
holder.Parent = ReplicatedStorage
return "{clip["name"]} registered: " .. holder.Value .. ", " .. #seq:GetKeyframes() .. " keyframes"
"""


def hook(clip_path: str, mode: str, freeze: float | None) -> str:
    clip = keyed.load_clip(clip_path)
    freeze_at = round(freeze if freeze is not None else clip["release"] + 0.05, 4)
    return f"""local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AnimationConfig = require(ReplicatedStorage.Shared.Config.AnimationConfig)
local generic = AnimationConfig.clipFor("Cast")
local GENERIC = if generic ~= nil then generic.Id else nil
local GLYPH, HAND, MODE, FREEZE = "{clip["glyph"]}", "{clip.get("hand", "RightHand")}", "{mode}", {freeze_at}
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("VfxReliable")
local result = ReplicatedStorage:FindFirstChild("__AnimTestResult") or Instance.new("StringValue")
result.Name = "__AnimTestResult"
result.Value = "waiting for a " .. GLYPH .. " cast"
result.Parent = ReplicatedStorage
if _G.__animTestConn then
	_G.__animTestConn:Disconnect()
end
_G.__animTestConn = remote.OnClientEvent:Connect(function(packet)
	if type(packet) ~= "table" or packet.Id ~= "Cast" or packet.Caster ~= player.UserId then
		return
	end
	if type(packet.Params) ~= "table" or packet.Params.GlyphId ~= GLYPH then
		return
	end
	local at = os.clock()
	local character = player.Character
	local animator = character.Humanoid.Animator
	local root = character.HumanoidRootPart
	task.defer(function()
		local track
		for _, playing in ipairs(animator:GetPlayingAnimationTracks()) do
			if playing.Animation and playing.Animation.AnimationId == GENERIC then
				if MODE == "after" then
					playing:Stop(0)
				else
					track = playing
				end
			end
		end
		if MODE == "after" then
			local animation = Instance.new("Animation")
			animation.AnimationId = ReplicatedStorage.__AnimTest.Value
			track = animator:LoadAnimation(animation)
			track:Play(0.06, 1, 1)
		end
		if track == nil then
			result.Value = "no cast clip was playing"
			return
		end
		local speed = track.Speed
		local lines = {{}}
		local frozen = false
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local since = os.clock() - at
			local hand = root.CFrame:PointToObjectSpace(character[HAND].Position)
			if since <= 0.3 then
				table.insert(lines, string.format("%.3f s  clip %.3f  weight %.2f  hand x %+.2f y %+.2f z %+.2f",
					since, track.TimePosition, track.WeightCurrent, hand.X, hand.Y, hand.Z))
			end
			if not frozen and track.TimePosition >= FREEZE then
				frozen = true
				track:AdjustSpeed(0)
				table.insert(lines, string.format("frozen at clip %.3f for 8 s", track.TimePosition))
				task.delay(8, function()
					track:AdjustSpeed(speed)
				end)
			end
			if since > 0.35 then
				connection:Disconnect()
				result.Value = table.concat(lines, "\\n")
			end
		end)
	end)
end)
return "hooked " .. MODE .. " on " .. GLYPH .. "; cast it now"
"""


RESULT = """return game:GetService("ReplicatedStorage"):FindFirstChild("__AnimTestResult") and game:GetService("ReplicatedStorage").__AnimTestResult.Value or "no test ran"
"""

CLEANUP = """local ReplicatedStorage = game:GetService("ReplicatedStorage")
if _G.__animTestConn then
	_G.__animTestConn:Disconnect()
	_G.__animTestConn = nil
end
workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
for _, name in ipairs({ "__AnimTest", "__AnimTestResult" }) do
	local helper = ReplicatedStorage:FindFirstChild(name)
	if helper then
		helper.Parent = nil
	end
end
return "cleaned"
"""


def main(argv):
    if len(argv) >= 3 and argv[1] == "register":
        print(register(argv[2]))
    elif len(argv) >= 4 and argv[1] == "hook" and argv[3] in ("before", "after"):
        print(hook(argv[2], argv[3], float(argv[4]) if len(argv) > 4 else None))
    elif len(argv) == 2 and argv[1] == "result":
        print(RESULT)
    elif len(argv) == 2 and argv[1] == "cleanup":
        print(CLEANUP)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
