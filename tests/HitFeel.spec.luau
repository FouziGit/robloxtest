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
		-- Limp for the whole throw, and some time lying on the ground: measured live, a thrown body lands in
		-- about 0.5 s, and at 0.25 s it often never fell at all.
		expect(hit.RagdollSeconds).toBeGreaterThanOrEqual(hit.KnockbackDurationSeconds)
		expect(hit.RagdollSeconds).toBeGreaterThanOrEqual(0.5 + 0.25)
		-- The stand-up measured on an R15 avatar is about 0.2 s.
		expect(hit.RagdollRiseSeconds).toBeGreaterThanOrEqual(0.2)
		expect(hit.RagdollSeconds + hit.RagdollRiseSeconds).toBeGreaterThanOrEqual(
			CombatConfig.Melee.FinisherStunSeconds
		)
		expect(hit.RagdollSeconds + hit.RagdollRiseSeconds).toBeLessThanOrEqual(hit.StunMaxSeconds)
		-- And up before the attacker's next finisher is ready: a knockdown is a pause, not a lockdown.
		expect(hit.RagdollSeconds + hit.RagdollRiseSeconds).toBeLessThanOrEqual(
			CombatConfig.Melee.FinisherCooldownSeconds
		)
		local status = CombatConfig.Status
		expect(type(status.RagdollAttribute)).toBe("string")
		expect(status.RagdollLimp).never.toBe(status.RagdollRising)
	end)

	it("leaves a body on the ground untouchable until it stands: a knockdown is never a free follow-up", function()
		local damage = functionIn("src/server/Services/CombatService.luau", "function CombatService.ApplyDamage(")
		local refused =
			damage:find("if targetPlayer ~= nil and movement.isDown(targetPlayer) then return result end", 1, true)
		local taken = damage:find("humanoid:TakeDamage(applied)", 1, true)
		expect(refused).never.toBe(nil)
		expect(taken).never.toBe(nil)
		expect((refused :: number) < (taken :: number)).toBe(true)
		-- Before anything the hit would remember or spend.
		expect((refused :: number) < (damage:find("local memory", 1, true) :: number)).toBe(true)
		-- Down means down for the whole fall, limp and rising alike.
		expect(functionIn(MOVEMENT, "function MovementService.isDown(")).toBe(
			"function MovementService.isDown(player: Player): boolean local state = states[player] local fall = if state ~= nil then state.Fall else nil return fall ~= nil and not (fall.Rising and fall.Until <= os.clock()) end "
		)
		-- No glyph picks it, and a projectile flies over it.
		local glyphs = "src/server/Effects/GlyphEffects.luau"
		expect(functionIn(glyphs, "local function isDown(")).toBe(
			"local function isDown(model: Model): boolean return model:GetAttribute(CombatConfig.Status.RagdollAttribute) ~= nil end "
		)
		expect(
			functionIn(glyphs, "local function modelOf("):find(
				"or humanoid.Health <= 0 or isDown(model) then return nil end",
				1,
				true
			)
		).never.toBe(nil)
		local projectile = functionIn(glyphs, "local function stepProjectile(")
		expect(projectile:find("if body == nil or not isDown(body) then break end", 1, true)).never.toBe(nil)
		expect(
			projectile:find(
				"table.insert(filter, body) rayParams.FilterDescendantsInstances = filter ray = Workspace:Raycast(position, step, rayParams)",
				1,
				true
			)
		).never.toBe(nil)
		-- And no timed effect keeps hurting for a caster who is down: Scorch now stops like the others.
		local scorch = functionIn(glyphs, "function GlyphEffects.Scorch(")
		expect(scorch:find("if centre == nil or not casterAlive(ctx) then break end", 1, true)).never.toBe(nil)
	end)

	it("cannot be handed to an ally: there is no friendly fire", function()
		-- A teammate's finisher knocked an ally down on purpose, and a body on the ground is untouchable:
		-- an ult dodged or a low ally saved on demand (found by review, D-113).
		local allow = functionIn("src/server/Services/MatchService.luau", "local function allowDamage(")
		expect(
			allow:find(
				"if teamOfParticipant(sourceActive, source.UserId) == teamOfParticipant(sourceActive, targetPlayer.UserId) then return false end",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("aims every swing and every glyph upright, whatever the root's tilt", function()
		local combat = "src/server/Services/CombatService.luau"
		expect(
			functionIn(combat, "local function trustedCFrame("):find("local observed = upright(root.CFrame)", 1, true)
		).never.toBe(nil)
		local upright = functionIn(combat, "local function upright(")
		expect(upright:find("OriginGuard.facing(look.X, look.Y, look.Z, up.X, up.Z)", 1, true)).never.toBe(nil)
		expect(upright:find("return CFrame.lookAlong(frame.Position, Vector3.new(x, 0, z))", 1, true)).never.toBe(nil)
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
		expect(ragdoll:find("MovementService.applyStun(player, limp + rise)", 1, true)).never.toBe(nil)
	end)

	it("rises on joints that pull, then goes rigid: never a limb put back in one frame", function()
		local step = functionIn(MOVEMENT, "local function stepFall(")
		expect(
			step:find(
				"fall.Rising = true fall.RiseFrom = fall.Until fall.Until += CombatConfig.Hit.RagdollRiseSeconds strengthenJoints(fall, (now - fall.RiseFrom) / CombatConfig.Hit.RagdollRiseSeconds)",
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
		expect(strengthen:find("local strength = math.clamp(progress, 0, 1) ^ 2", 1, true)).never.toBe(nil)
		expect(strengthen:find("saved.Joint.MaxTorque = saved.MaxTorque * strength", 1, true)).never.toBe(nil)
		-- And every tick of the rise gives a little more back.
		expect(
			step:find(
				"if fall.Until > now then if fall.Rising then strengthenJoints(fall, (now - fall.RiseFrom) / CombatConfig.Hit.RagdollRiseSeconds) end return end",
				1,
				true
			)
		).never.toBe(nil)
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

	it("leaves a body already down as it is: nothing can reach it, and loosening it twice would lie", function()
		local ragdoll = functionIn(MOVEMENT, "function MovementService.ragdoll(")
		local guard =
			ragdoll:find("if state.Fall ~= nil then return end local joints = loosenJoints(character)", 1, true)
		expect(guard).never.toBe(nil)
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
