--!strict
-- The Forgers' tells (D-131, D-133) are the one warning a fight against the page's own writing gives, and like the
-- Erasure's they are rules rather than decoration: a player reads the ink on the floor and steps out of it before
-- the blow lands. So they are held here the way tests/BossTelegraph.spec.luau holds the boss's -- the paint against
-- the floor the server really judges (BattlegroundService's Attacks, BotBrain.inMeleeBox) for every tier BotConfig
-- ships, the window against every wait a Forger can be given, and the server and the renderer against the fields
-- they hand each other. Under-covering fails; over-covering is allowed (a bolt's line is painted through the cover
-- that will stop it, because where it stops is only known when it flies).
local AssetIds = require("../src/shared/Config/AssetIds")
local BotBrain = require("../src/server/Pure/BotBrain")
local BotConfig = require("../src/shared/Config/BotConfig")
local Harness = require("./harness")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Layer = VfxTimelineConfig.Layer

local ID = "ForgerTell"
local ATTACKS = "src/server/Services/BattlegroundService/Attacks.luau"
local SERVICE = "src/server/Services/BattlegroundService/init.luau"
local LIBRARY = "src/client/Controllers/VfxLibrary.luau"
local TIMELINE = "src/client/Controllers/VfxTimeline.luau"
local EPSILON = 1e-6
-- Two pixels of a 256-texture, in half-widths: the anti-aliased rim of a telegraph texture, and the whole
-- tolerance a warning gets (tests/BossTelegraph.spec.luau).
local PIXEL = 2 / 256
-- A warning has to read on its first frame, and be up for most of its window.
local MAX_START_TRANSPARENCY = 0.8
local MAX_PAINT_START = 0.35
-- How finely the judged floor is sampled, in studs: finer than any gap a stud-wide edge rule could hide.
local STEP = 0.1
-- The paint may lift off the page as the blow lands, never lie there after it: floor still inked reads as floor
-- that still hurts.
local MAX_RESIDUE_SECONDS = 0.3

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function fold(source: string): string
	return (source:gsub("%s+", " "))
end

-- A function's body in a file, comments stripped and whitespace folded.
local function body(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return fold(source:sub(start, finish or #source))
end

local function timeline(): VfxTimelineConfig.Timeline
	local found = VfxTimelineConfig.Timelines[ID]
	if found == nil then
		error("no ForgerTell timeline: the Forgers would wind up unannounced")
	end
	return found
end

local function windowedPhase(): VfxTimelineConfig.Phase
	for _, phase in ipairs(timeline().Phases) do
		if phase.Window == true then
			return phase
		end
	end
	error("ForgerTell has no phase whose length comes from the packet")
end

-- The marks a warning is made of: a mark whose size does not change, up early enough to be read, and still there
-- when the blow lands.
local function steadyMarks(): { Layer }
	local marks: { Layer } = {}
	for _, layer in ipairs(windowedPhase().Layers) do
		local moves = layer.EndSize ~= nil and layer.EndSize ~= layer.Size
		if layer.Kind == "Mark" and not moves and layer.At <= MAX_PAINT_START and layer.At + layer.For >= 0.999 then
			table.insert(marks, layer)
		end
	end
	return marks
end

-- Whether `first` appears in `text`, and `later` after it.
local function ordered(text: string, first: string, later: string): boolean
	local at = text:find(first, 1, true)
	return at ~= nil and text:find(later, at + #first, true) ~= nil
end

local function requireAll(text: string, needles: { string }, what: string)
	for _, needle in ipairs(needles) do
		if text:find(needle, 1, true) == nil then
			error(("%s no longer holds: %s"):format(what, needle))
		end
	end
end

-- Every wait a Forger of `tier` can be given before a blow lands, each the window of one tell: the first step of
-- a chain, each step after it, the finisher, and a bolt's wind-up.
local function windowsOf(tier: BotConfig.TierDef): { number }
	local windows: { number } = {}
	local melee = tier.Melee
	for step = 1, #melee.Damage do
		if step == 1 then
			table.insert(windows, melee.WindupSeconds)
		elseif step == #melee.Damage then
			table.insert(windows, melee.FinisherGapSeconds)
		else
			table.insert(windows, melee.ChainGapSeconds)
		end
	end
	local bolt = tier.Bolt
	if bolt ~= nil then
		table.insert(windows, bolt.WindupSeconds)
	end
	return windows
end

local function measure(name: VfxTimelineConfig.Measure?, radius: number, reach: number): number
	if name == "Radius" then
		return radius
	elseif name == "Reach" then
		return reach
	end
	-- Studs, at the play's Scale, which the renderer never sets.
	return 1
end

-- Whether `layer` paints the floor point `across` studs beside the aim and `along` studs along it from the Forger,
-- for a tell measured on `radius` and `reach`: its plane, shrunk to how far its texture's ink really reaches in the
-- direction it reaches least, give or take the texture's anti-aliased rim.
local function paints(layer: Layer, radius: number, reach: number, across: number, along: number): boolean
	local key = layer.Texture
	local asset = if key ~= nil then AssetIds.Textures[key] else nil
	if key ~= nil and (asset == nil or asset.Ink == nil) then
		error(
			("texture %s carries no ink measurement, so nothing can be proven about a warning drawn with it"):format(
				key
			)
		)
	end
	local ink = if asset ~= nil and asset.Ink ~= nil then asset.Ink.Least else 1
	local offset = layer.Offset or { 0, 0, 0 }
	local offsetScale = measure(layer.OffsetFrom, radius, reach)
	local halfWidth = (layer.Size or 0) * measure(layer.SizeFrom, radius, reach) / 2 * (ink + PIXEL)
	local depth = if layer.Span ~= nil
		then layer.Span * measure(layer.SpanFrom, radius, reach)
		else (layer.Size or 0) * measure(layer.SizeFrom, radius, reach)
	local halfDepth = depth / 2 * (ink + PIXEL)
	return math.abs(across - offset[1] * offsetScale) <= halfWidth + EPSILON
		and math.abs(along - offset[3] * offsetScale) <= halfDepth + EPSILON
end

-- Every floor point `judged` says the blow reaches, inside the box it could reach at all, is painted by one of the
-- steady marks of a tell measured on `radius` and `reach`.
local function covers(
	what: string,
	radius: number,
	reach: number,
	extent: number,
	halfWidth: number,
	judged: (across: number, along: number) -> boolean
)
	local marks = steadyMarks()
	expect(#marks).toBeGreaterThanOrEqual(1)
	local sampled = 0
	local along = 0
	while along <= extent + EPSILON do
		local across = -halfWidth
		while across <= halfWidth + EPSILON do
			if judged(across, along) then
				sampled += 1
				local painted = false
				for _, layer in ipairs(marks) do
					if paints(layer, radius, reach, across, along) then
						painted = true
						break
					end
				end
				if not painted then
					error(
						("%s hits %.2f studs beside the aim and %.2f along it, and its tell paints nothing there"):format(
							what,
							across,
							along
						)
					)
				end
			end
			across += STEP
		end
		along += STEP
	end
	-- The sampling reached the blow at all: a judge that refused everything would prove nothing.
	expect(sampled).toBeGreaterThan(20)
end

describe("a Forger's tell", function()
	it("warns for exactly as long as the server waits, for every blow of every tier", function()
		local phase = windowedPhase()
		expect(phase.Name).toBe("Anticipation")
		local count = 0
		for tierId, tier in pairs(BotConfig.Tiers) do
			for _, window in ipairs(windowsOf(tier)) do
				count += 1
				local resolved = VfxTimelineConfig.phaseSeconds(phase, window)
				if math.abs(resolved - window) > EPSILON then
					error(("a %s waits %.3fs and its tell resolves %.3fs"):format(tierId, window, resolved))
				end
				-- The paint lifts off at the moment the blow lands, not at a time the renderer guessed.
				local residue = VfxTimelineConfig.phaseAt(ID, "Residue", window)
				if residue == nil or math.abs(residue - window) > EPSILON then
					error(
						("a %s lands at %.3fs and its tell lifts off at %s"):format(tierId, window, tostring(residue))
					)
				end
			end
		end
		expect(count).toBeGreaterThanOrEqual(6)
		-- A play that lost its window warns for the shortest first wind-up a Forger may show, never less.
		expect(phase.Duration).toBeGreaterThanOrEqual(BotConfig.MinWindupSeconds)
	end)

	it("is readable from its first frame, and lifts off the page as the blow lands", function()
		for _, layer in ipairs(steadyMarks()) do
			if (layer.Transparency or 0) > MAX_START_TRANSPARENCY then
				error(
					("ForgerTell opens at transparency %.2f, invisible for most of its window"):format(
						layer.Transparency or 0
					)
				)
			end
		end
		local residues = 0
		for _, phase in ipairs(timeline().Phases) do
			if phase.Name == "Residue" then
				for _, layer in ipairs(phase.Layers) do
					residues += 1
					expect(layer.At + layer.For).toBeLessThanOrEqual(MAX_RESIDUE_SECONDS)
					if layer.Kind == "Mark" then
						expect(layer.EndTransparency).toBe(1)
					end
				end
			elseif phase.Name ~= "Anticipation" then
				-- The blow is the Melee stroke's and the Strike's: a tell has nothing to land.
				error(("ForgerTell has a %s phase"):format(phase.Name))
			end
		end
		expect(residues).toBeGreaterThanOrEqual(1)
	end)

	it("paints at least the floor a swing hits, for every tier", function()
		-- The server sends the swing's own Range and twice its HalfWidth, and judges the box by inMeleeBox.
		local windup = body(ATTACKS, "function Attacks.windup(")
		expect(windup:find("range, width, clipName = melee.Range, 2 * melee.HalfWidth, MELEE_CHAIN[index]", 1, true)).never.toBe(
			nil
		)
		expect(
			body(ATTACKS, "local function resolveMelee("):find(
				"if BotBrain.inMeleeBox(offset.X, offset.Y, offset.Z, resolve.AimX, resolve.AimZ, melee) then",
				1,
				true
			)
		).never.toBe(nil)
		for tierId, tier in pairs(BotConfig.Tiers) do
			local melee = tier.Melee
			covers(
				tierId .. "'s swing",
				melee.HalfWidth,
				melee.Range,
				melee.Range + 1,
				melee.HalfWidth + 1,
				function(across: number, along: number): boolean
					-- Aimed along +Z: forward is along, the side is across.
					return BotBrain.inMeleeBox(across, 0, along, 0, 1, melee :: any)
				end
			)
		end
	end)

	it("paints at least the floor a bolt hits, from the Forger to past its muzzle's reach", function()
		-- The resolve (Attacks.resolveBolt): one ray from the muzzle, SpawnOffset ahead of the eyes, for Range; a
		-- target is hit within HitRadius of that line and up to Range past the muzzle, each widened by the target's
		-- own radius. The tell is sent measured from the Forger, reach and width both carrying that radius.
		local resolve = body(ATTACKS, "local function resolveBolt(")
		for _, line in ipairs({
			"local start = eyes + aim * bolt.SpawnOffset",
			"local hit = Workspace:Raycast(start, aim * bolt.Range, handle.SightParams)",
			"along >= 0 and along <= reach + REACH.TargetRadiusStuds and aside <= bolt.HitRadius + REACH.TargetRadiusStuds",
		}) do
			if resolve:find(line, 1, true) == nil then
				error("resolveBolt no longer judges what its tell was measured on: " .. line)
			end
		end
		local windup = body(ATTACKS, "function Attacks.windup(")
		for _, line in ipairs({
			"range = bolt.SpawnOffset + bolt.Range + REACH.TargetRadiusStuds",
			"width = 2 * (bolt.HitRadius + REACH.TargetRadiusStuds)",
		}) do
			if windup:find(line, 1, true) == nil then
				error("Attacks.windup no longer measures a bolt's tell on what it hits: " .. line)
			end
		end
		local target = BotConfig.Reach.TargetRadiusStuds
		local bolts = 0
		for tierId, tier in pairs(BotConfig.Tiers) do
			local bolt = tier.Bolt
			if bolt ~= nil then
				bolts += 1
				local reach = bolt.SpawnOffset + bolt.Range + target
				local radius = bolt.HitRadius + target
				covers(
					tierId .. "'s bolt",
					radius,
					reach,
					reach + 1,
					radius + 1,
					function(across: number, along: number): boolean
						-- The server's own two tests, on an unobstructed ray: along the aim from the muzzle, and aside
						-- from the segment it flew.
						local fromMuzzle = along - bolt.SpawnOffset
						local aside = BotBrain.segmentDistance(
							0,
							bolt.SpawnOffset,
							0,
							bolt.SpawnOffset + bolt.Range,
							across,
							along
						)
						return fromMuzzle >= 0
							and fromMuzzle <= bolt.Range + target
							and aside <= bolt.HitRadius + target
					end
				)
			end
		end
		expect(bolts).toBeGreaterThanOrEqual(1)
	end)

	it("is sent what it measures, on the reliable remote, from the floor under the Forger", function()
		local windup = body(ATTACKS, "function Attacks.windup(")
		for _, line in ipairs({
			"Id = Context.TellVfxId,",
			"Origin = groundUnder(bot.Root.Position),",
			"Direction = Vector3.new(attack.AimX, 0, attack.AimZ),",
			"Seconds = window,",
			"Range = range,",
			"Width = width,",
			"Actor = bot.Model,",
			"}, true)",
		}) do
			if windup:find(line, 1, true) == nil then
				error("Attacks.windup no longer sends its tell: " .. line)
			end
		end
	end)

	it("is played the way it is written: the window, the two lengths, the Forger's inks, unlit", function()
		local handler = body(LIBRARY, "VfxLibrary.ForgerTell = function(")
		for _, line in ipairs({
			'api.Timeline.play("ForgerTell", {',
			"Origin = packet.Origin,",
			"Direction = flatDirectionOf(packet),",
			"Color = FORGER_CHALK,",
			"Ink = FORGER_INK,",
			'Window = numberParam(packet, "Seconds", 0),',
			'local width = measureParam(packet, "Width")',
			"Radius = if width ~= nil then width / 2 else nil,",
			'Reach = measureParam(packet, "Range"),',
			"Unlit = true,",
			"Hand = actorHand(packet),",
		}) do
			if handler:find(line, 1, true) == nil then
				error("VfxLibrary.ForgerTell no longer plays the tell the server sent: " .. line)
			end
		end
		-- A length the packet lost is no length: the layers measured by it are left out, never painted at a guess.
		expect(
			body(LIBRARY, "local function measureParam("):find(
				"local value = numberParam(packet, key, 0) return if value > 0 then value else nil",
				1,
				true
			)
		).never.toBe(nil)
		-- The Forger's own inks, and never the Erasure's danger colour.
		local library = fold(strip(fs.readFile(LIBRARY)))
		expect(library:find("local FORGER_INK = Palette.world(WorldConfig.Forgers.Body)", 1, true)).never.toBe(nil)
		expect(library:find("local FORGER_CHALK = Palette.world(WorldConfig.Forgers.Mark)", 1, true)).never.toBe(nil)
		expect(handler:find("ERASURE", 1, true)).toBe(nil)
	end)

	it("never shines, and flashes chalk on ink at the striking hand as the blow comes", function()
		local late = { Ink = 0, Chalk = 0 }
		for _, phase in ipairs(timeline().Phases) do
			for _, layer in ipairs(phase.Layers) do
				if
					layer.Kind == "Light"
					or layer.Glow ~= nil
					or layer.Role == "Core"
					or (layer.Brightness or 1) > 1
				then
					error(
						("ForgerTell / %s draws a %s that shines: a Forger is no glyph"):format(phase.Name, layer.Kind)
					)
				end
				if phase.Window == true and layer.Anchor == "Hand" then
					expect(layer.At).toBeGreaterThanOrEqual(0.75)
					expect(layer.At + layer.For).toBeLessThanOrEqual(1)
					if layer.Role == "Ink" then
						late.Ink += 1
					else
						late.Chalk += 1
					end
				end
			end
		end
		expect(late.Ink).toBeGreaterThanOrEqual(1)
		expect(late.Chalk).toBeGreaterThanOrEqual(1)
	end)

	it("is taken back on every client once its blow is dropped, by a stagger or its Forger's death", function()
		-- The server names whose tell it is, and takes it back on the same reliable remote, so after it.
		requireAll(body(ATTACKS, "function Attacks.windup("), { "Forger = bot.Slot," }, "Attacks.windup")
		requireAll(body(ATTACKS, "function Attacks.retract("), {
			"Id = Context.TellVfxId,",
			"Origin = groundUnder(bot.Root.Position),",
			"Params = { Cancel = true, Forger = bot.Slot },",
			"}, true)",
		}, "Attacks.retract")
		-- A stagger that cut a wind-up takes it back; a Forger that died with one pending does, on its next tick.
		requireAll(
			body(SERVICE, "local function stagger("),
			{ "if cancelled ~= nil then Attacks.retract(bot)" },
			"stagger"
		)
		requireAll(
			body(SERVICE, "local function dropAttack("),
			{ "if bot.Memory.Attack ~= nil then bot.Memory.Attack = nil Attacks.retract(bot) end" },
			"dropAttack"
		)
		local maintain = body(SERVICE, "local function maintain(")
		requireAll(maintain, {
			"if bot.Dead then dropAttack(bot)",
			"Bots.kill(bot, now) dropAttack(bot) Bots.destroy(bot)",
		}, "maintain")
		-- The client ends that Forger's play: nothing of it still to come, nothing of it left on screen.
		local handler = body(LIBRARY, "VfxLibrary.ForgerTell = function(")
		requireAll(handler, {
			'local forger = numberParam(packet, "Forger", 0)',
			"if params ~= nil and params.Cancel == true then local playId = forgerTells[forger] forgerTells[forger] = nil if playId ~= nil then api.Timeline.cancel(playId) end return end",
			'local _, playId = api.Timeline.play("ForgerTell", {',
			"forgerTells[forger] = playId",
		}, "VfxLibrary.ForgerTell")
		expect(ordered(handler, "params.Cancel == true", "api.Timeline.play(")).toBe(true)
		requireAll(body(TIMELINE, "function VfxTimeline.play("), { "return true, playId" }, "VfxTimeline.play")
		requireAll(body(TIMELINE, "function VfxTimeline.cancel("), {
			"if pending[index].PlayId == playId then table.remove(pending, index)",
			"if entry.PlayId == playId then entry.EndsAt = clockOf(entry.Steady)",
			-- Its warning is not heard out either: every sound the play started is stopped.
			"local started = playSounds[playId] if started ~= nil then playSounds[playId] = nil for _, playing in ipairs(started) do if playing.Parent ~= nil then playing:Stop()",
		}, "VfxTimeline.cancel")
		requireAll(body(TIMELINE, "local function activate("), {
			"local started: Sound? = sound.play(key, position,",
			"if started ~= nil then keepSound(item.PlayId, started) end",
		}, "VfxTimeline.activate")
		requireAll(body(TIMELINE, "local function keepSound("), {
			"if kept[index].Parent == nil then table.remove(kept, index) end",
			"if #kept == 0 then playSounds[id] = nil end",
		}, "VfxTimeline.keepSound")
		requireAll(
			body("src/client/Controllers/SoundController.luau", "function SoundController.play("),
			{ "sound:Play() return sound" },
			"SoundController.play"
		)
		requireAll(
			body(TIMELINE, "local function onHeartbeat("),
			{ "if now >= entry.EndsAt and not settle(entry, now) then releaseLive(entry)" },
			"onHeartbeat"
		)
		-- And the next frame does release all of it: only a carrier outlives its end (settle), and a tell has none.
		for _, phase in ipairs(timeline().Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Kind == "Carrier" or layer.Ride == true then
					error(("ForgerTell / %s has a %s a retraction would leave standing"):format(phase.Name, layer.Kind))
				end
			end
		end
	end)
end)
