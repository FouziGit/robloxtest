--!strict
-- How a heavy hit is felt (D-112): the finisher's victim goes limp and gets back up, and the bodies in a
-- heavy hit are printed in ink for a few frames. Both were tried in a live client before being written,
-- and the review that followed measured what the first version got wrong: a fall done on the victim's
-- client alone, which nobody else saw; control back before the body was up; limbs snapped to their pose
-- in one frame; one body printed out of a blast that hit two.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local FeelConfig = require("../src/shared/Config/FeelConfig")
local Harness = require("./harness")
local LightingConfig = require("../src/shared/Config/LightingConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function flat(source: string): string
	return (strip(source):gsub("%s+", " "))
end

-- One top-level function of a file, flattened, or an error: a gate that found nothing would pass.
local function functionIn(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(header .. " is not in " .. path .. ": this gate would check nothing")
	end
	local finish = source:find("\nend\n", start, true)
	if finish == nil then
		error(header .. " has no end in " .. path)
	end
	return (source:sub(start, finish + 4):gsub("%s+", " "))
end

local MOVEMENT = "src/server/Services/MovementService.luau"

describe("a finisher", function()
	it("throws its victim, then lets it fall", function()
		local melee = functionIn("src/server/Services/CombatService.luau", "local function onMelee(")
		local thrown = melee:find("CombatService.knockback(", 1, true)
		local limp = melee:find("movement.ragdoll(targetPlayer, CombatConfig.Hit.RagdollSeconds)", 1, true)
		expect(thrown).never.toBe(nil)
		expect(limp).never.toBe(nil)
		expect((limp :: number) > (thrown :: number)).toBe(true)
		-- Once: a second fall ahead of the throw would drop the body where it stands.
		local _, falls = melee:gsub("movement%.ragdoll%(", "")
		expect(falls).toBe(1)
	end)

	it("is named in its hit, with the body it landed on", function()
		local combat = flat(fs.readFile("src/server/Services/CombatService.luau"))
		expect(combat:find('if kind == "Melee" and tags[1] == "MeleeFinisher" then hitParams.Finisher = true', 1, true)).never.toBe(
			nil
		)
		expect(combat:find("hitParams.Victim = targetModel", 1, true)).never.toBe(nil)
	end)

	it("keeps its victim down long enough to read, and stunned until it is up, never past the ceiling", function()
		local hit = CombatConfig.Hit
		-- Limp for the whole throw: a body that stiffened mid-flight would read as a plank again.
		expect(hit.RagdollSeconds).toBeGreaterThanOrEqual(hit.KnockbackDurationSeconds)
		-- The stand-up measured on an R15 avatar is about 0.2 s.
		expect(hit.RagdollRiseSeconds).toBeGreaterThanOrEqual(0.2)
		expect(hit.RagdollSeconds + hit.RagdollRiseSeconds).toBeGreaterThanOrEqual(
			CombatConfig.Melee.FinisherStunSeconds
		)
		expect(hit.RagdollSeconds + hit.RagdollRiseSeconds).toBeLessThanOrEqual(hit.StunMaxSeconds)
		-- And not much longer than the finisher's own stun: at 0.7 s a finisher into Brand was a follow-up
		-- no dash could escape. One server tick of slack.
		expect(hit.RagdollSeconds + hit.RagdollRiseSeconds).toBeLessThanOrEqual(
			CombatConfig.Melee.FinisherStunSeconds + 0.05 + 1e-9
		)
		local status = CombatConfig.Status
		expect(type(status.RagdollAttribute)).toBe("string")
		expect(status.RagdollLimp).never.toBe(status.RagdollRising)
	end)
end)

describe("a ragdoll", function()
	it("is loosened by the server, where every client sees it, never by a client", function()
		local loosen = functionIn(MOVEMENT, "local function loosenJoints(")
		expect(loosen:find('descendant:IsA("AnimationConstraint") and descendant.Name ~= ROOT_JOINT', 1, true)).never.toBe(
			nil
		)
		local loosened = loosen:find("descendant.IsKinematic = false descendant.MaxTorque = 0", 1, true)
		local saved = loosen:find("Kinematic = descendant.IsKinematic, MaxTorque = descendant.MaxTorque", 1, true)
		expect(loosened).never.toBe(nil)
		expect(saved).never.toBe(nil)
		-- Saved first: saved after, the joint "was" loose, and every body stayed limp until it respawned.
		expect((saved :: number) < (loosened :: number)).toBe(true)
		expect(flat(fs.readFile(MOVEMENT)):find('local ROOT_JOINT = "Root"', 1, true)).never.toBe(nil)
		local ragdoll = functionIn(MOVEMENT, "function MovementService.ragdoll(")
		expect(ragdoll:find("local joints = loosenJoints(character) if #joints == 0 then return end", 1, true)).never.toBe(
			nil
		)
		-- Loosened once per fall: loosened again, a body already down would record itself as loose.
		local _, loosenings = ragdoll:gsub("loosenJoints%(", "")
		expect(loosenings).toBe(1)
		expect(ragdoll:find("character:SetAttribute(RAGDOLL_ATTRIBUTE, CombatConfig.Status.RagdollLimp)", 1, true)).never.toBe(
			nil
		)
		-- A joint a client changes never leaves it: nothing on the client may be what loosens a body.
		local scanned = 0
		local function scan(directory: string)
			for _, name in ipairs(fs.readDir(directory)) do
				local path = directory .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif name:match("%.luau$") then
					scanned += 1
					if strip(fs.readFile(path)):find("IsKinematic%s*=") then
						error(path .. " sets IsKinematic: a client cannot loosen a body anyone else sees")
					end
				end
			end
		end
		scan("src/client")
		expect(scanned).toBeGreaterThan(10)
	end)

	it("keeps its victim stunned until the body is up, and never limp past the ceiling", function()
		local ragdoll = functionIn(MOVEMENT, "function MovementService.ragdoll(")
		expect(ragdoll:find("local limp = math.min(seconds, CombatConfig.Hit.StunMaxSeconds - rise)", 1, true)).never.toBe(
			nil
		)
		expect(ragdoll:find("MovementService.applyStun(player, (fall :: Fall).Until - now + rise)", 1, true)).never.toBe(
			nil
		)
	end)

	it("rises on joints that pull, then goes rigid: never a limb put back in one frame", function()
		local step = functionIn(MOVEMENT, "local function stepFall(")
		expect(
			step:find(
				"fall.Rising = true fall.Until += CombatConfig.Hit.RagdollRiseSeconds strengthenJoints(fall)",
				1,
				true
			)
		).never.toBe(nil)
		expect(step:find("fall.Character:SetAttribute(RAGDOLL_ATTRIBUTE, CombatConfig.Status.RagdollRising)", 1, true)).never.toBe(
			nil
		)
		expect(step:find("if fall.Rising then restoreJoints(fall) state.Fall = nil", 1, true)).never.toBe(nil)
		-- The rise gives the torque back and leaves the joint physical.
		local strengthen = functionIn(MOVEMENT, "local function strengthenJoints(")
		expect(strengthen:find("saved.Joint.MaxTorque = saved.MaxTorque", 1, true)).never.toBe(nil)
		expect(strengthen:find("IsKinematic", 1, true)).toBe(nil)
		local restore = functionIn(MOVEMENT, "local function restoreJoints(")
		expect(restore:find("if saved.Joint.Parent ~= nil then", 1, true)).never.toBe(nil)
		expect(restore:find("saved.Joint.IsKinematic = saved.Kinematic", 1, true)).never.toBe(nil)
		expect(restore:find("fall.Character:SetAttribute(RAGDOLL_ATTRIBUTE, nil)", 1, true)).never.toBe(nil)
		-- The tick advances it, and a death, a respawn or a departure puts the joints back.
		local heartbeat = functionIn(MOVEMENT, "local function onHeartbeat(")
		expect(
			heartbeat:find("local fall = state.Fall if fall ~= nil then stepFall(player, state, fall, now)", 1, true)
		).never.toBe(nil)
		local clear = functionIn(MOVEMENT, "local function clearStatuses(")
		expect(clear:find("state.Fall = nil restoreJoints(fall)", 1, true)).never.toBe(nil)
		-- Except a death: the corpse stays down instead of snapping to its standing pose.
		local movement = flat(fs.readFile(MOVEMENT))
		expect(
			movement:find(
				"characterTrove:Connect(humanoid.Died, function() dropFall(state) clearStatuses(state)",
				1,
				true
			)
		).never.toBe(nil)
		local drop = functionIn(MOVEMENT, "local function dropFall(")
		expect(drop:find("state.Fall = nil fall.Character:SetAttribute(RAGDOLL_ATTRIBUTE, nil)", 1, true)).never.toBe(
			nil
		)
		expect(drop:find("restoreJoints", 1, true)).toBe(nil)
		-- The stun follows the rise that really began, however late the tick that began it.
		expect(step:find("if fall.Until > now then MovementService.applyStun(player, fall.Until - now) end", 1, true)).never.toBe(
			nil
		)
	end)

	it("falls again on a body already down instead of loosening it twice", function()
		local ragdoll = functionIn(MOVEMENT, "function MovementService.ragdoll(")
		expect(ragdoll:find("if fall ~= nil and fall.Character == character then", 1, true)).never.toBe(nil)
		expect(ragdoll:find("fall.Until = math.max(fall.Until, now + limp)", 1, true)).never.toBe(nil)
		expect(ragdoll:find("saved.Joint.MaxTorque = 0 end end fall.Rising = false", 1, true)).never.toBe(nil)
	end)

	it("is followed by the one client that simulates the body, and posed by nobody while it is down", function()
		local controller = flat(fs.readFile("src/client/Controllers/MovementController.luau"))
		expect(
			controller:find(
				"if phase == CombatConfig.Status.RagdollLimp then foundHumanoid:ChangeState(Enum.HumanoidStateType.Physics)",
				1,
				true
			)
		).never.toBe(nil)
		expect(
			controller:find(
				"elseif foundHumanoid:GetState() == Enum.HumanoidStateType.Physics then foundHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)",
				1,
				true
			)
		).never.toBe(nil)
		expect(
			controller:find(
				"characterTrove:Connect(character:GetAttributeChangedSignal(CombatConfig.Status.RagdollAttribute), followFall) followFall()",
				1,
				true
			)
		).never.toBe(nil)
		-- The old command is gone: a phase named on the character is the only way a body falls.
		expect(flat(fs.readFile(MOVEMENT)):find('Kind: "Ragdoll"', 1, true)).toBe(nil)
		local posture = flat(fs.readFile("src/client/Controllers/Posture.luau"))
		expect(posture:find("character:GetAttribute(CombatConfig.Status.RagdollAttribute) ~= nil", 1, true)).never.toBe(
			nil
		)
		expect(posture:find("and not limp then", 1, true)).never.toBe(nil)
	end)
end)

describe("an impact frame", function()
	local frame = functionIn("src/client/Controllers/Feel.luau", "function Feel.impactFrame(")

	it("prints the bodies in ink, briefly, and at least as long as the outline it covers", function()
		local config = FeelConfig.ImpactFrame
		expect(config.Seconds).toBeGreaterThan(0)
		expect(config.Seconds).toBeLessThanOrEqual(0.12)
		expect(config.Seconds).toBeGreaterThanOrEqual(FeelConfig.Flash.Seconds)
		expect(config.MinIntervalSeconds).toBeGreaterThanOrEqual(config.Seconds * 4)
		expect(frame:find("highlight.FillColor = INK", 1, true)).never.toBe(nil)
		expect(frame:find("highlight.FillTransparency = 0 ", 1, true)).never.toBe(nil)
		-- The outline under a print ends with it, whenever the body joined the frame.
		expect(
			frame:find(
				"if entry.Highlight.Adornee == model and entry.Highlight.Name == FLASH_NAME then entry.Remaining = math.min(entry.Remaining, remaining)",
				1,
				true
			)
		).never.toBe(nil)
		expect(flat(fs.readFile("src/client/Controllers/Feel.luau")):find("highlight.Name = FLASH_NAME", 1, true)).never.toBe(
			nil
		)
	end)

	it("prints every body of one blast, each once, and nothing more until the interval", function()
		expect(frame:find("local joining = since < config.Seconds", 1, true)).never.toBe(nil)
		expect(frame:find("if not joining and since < config.MinIntervalSeconds then return end", 1, true)).never.toBe(
			nil
		)
		expect(frame:find("if not joining then impactFrameAt = now end", 1, true)).never.toBe(nil)
		expect(frame:find("local remaining = impactFrameAt + config.Seconds - now", 1, true)).never.toBe(nil)
		expect(frame:find("Remaining = remaining", 1, true)).never.toBe(nil)
		expect(frame:find("model:FindFirstChild(INK_FRAME_NAME) == nil", 1, true)).never.toBe(nil)
		expect(frame:find("highlight.Name = INK_FRAME_NAME", 1, true)).never.toBe(nil)
	end)

	it("lands on a heavy hit or a finisher, for the two people in it only, over the outline", function()
		local hit = functionIn("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Hit = function(")
		local exchange = hit:find("if dealtByMe or takenByMe then", 1, true)
		local outline = hit:find("feel.flash(targetModel,", 1, true)
		local print = hit:find("feel.impactFrame(bodies)", 1, true)
		expect(exchange).never.toBe(nil)
		expect(outline).never.toBe(nil)
		expect(print).never.toBe(nil)
		expect((outline :: number) > (exchange :: number)).toBe(true)
		expect((print :: number) > (outline :: number)).toBe(true)
		-- A dummy and the boss are found by the body the server named.
		expect(hit:find('if typeof(victim) == "Instance" and victim:IsA("Model") then victim', 1, true)).never.toBe(nil)
		expect(hit:find("local finisher = packet.Params ~= nil and packet.Params.Finisher == true", 1, true)).never.toBe(
			nil
		)
		expect(hit:find("if heavy or finisher then local bodies = { targetModel }", 1, true)).never.toBe(nil)
		expect(hit:find("local casterModel = api.CharacterOf(packet.Caster or 0)", 1, true)).never.toBe(nil)
		expect(hit:find("if casterModel ~= nil then table.insert(bodies, casterModel) end", 1, true)).never.toBe(nil)
		local _, calls = hit:gsub("impactFrame%(", "")
		expect(calls).toBe(1)
	end)

	it(
		"obeys the shake switch and the platform's reduced motion, and so does every other motion of the feel",
		function()
			local allowed = functionIn("src/client/Controllers/Feel.luau", "local function motionAllowed(")
			expect(allowed:find("if GuiService.ReducedMotionEnabled then return false end", 1, true)).never.toBe(nil)
			expect(allowed:find("return data.Settings.CameraShake ~= false", 1, true)).never.toBe(nil)
			expect(frame:find("if not motionAllowed() then return end", 1, true)).never.toBe(nil)
			local shake = functionIn("src/client/Controllers/Feel.luau", "function Feel.shake(")
			expect(shake:find("or not motionAllowed() then", 1, true)).never.toBe(nil)
			local punch = functionIn("src/client/Controllers/Feel.luau", "function Feel.fovPunch(")
			expect(punch:find("if degrees == 0 or not motionAllowed() then return end", 1, true)).never.toBe(nil)
			-- And the page flash every hit throws over the whole screen.
			local lighting = functionIn("src/client/Controllers/WorldLighting.luau", "local function motionAllowed(")
			expect(lighting:find("if GuiService.ReducedMotionEnabled then return false end", 1, true)).never.toBe(nil)
			local pulse = functionIn("src/client/Controllers/WorldLighting.luau", "function WorldLighting.pulse(")
			expect(pulse:find("if not motionAllowed() or not postProcessing() then", 1, true)).never.toBe(nil)
		end
	)

	it("drains no colour from the screen: the spells stay the colour of their danger", function()
		-- A frame that desaturated the page would hide every spell for its length (D-108), and the pulses
		-- are summed at full weight against their bands (tests/LightingConfig.spec.luau).
		expect(LightingConfig.Pulses.ImpactFrame).toBe(nil)
		expect(frame:find("pulse", 1, true)).toBe(nil)
	end)
end)
