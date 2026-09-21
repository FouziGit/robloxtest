--!strict
-- ComboController: turns pigment presses into glyph casts. Feeds the shared ComboResolver, arms the
-- inactivity timer (short extend window when the pending sequence is already a recipe), sends
-- `CastGlyph` with the pigment sequence and reports resets to the HUD. The server re-validates
-- every sequence; this controller only decides when to send it.
--
-- It also plays the sequence. Each press is that pigment's note, and the notes climb a pentatonic as
-- the sequence grows, so a sequence that resolves is a phrase that resolves and one that breaks is a
-- clash (docs/JUICE_PLAN.md phase 5: "la séquence devient musicale"). The scale is the one the music
-- loops are written in (tools/audio/music.py), so a sequence over the music is in tune with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local ComboResolver = require(Shared.Pure.ComboResolver)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local Signal = require(Packages.Signal)

local log = Log.new("ComboController")

type Deps = { RemoteClient: any, SoundController: any, InputController: any, HudController: any }

-- Semitones above the root for the first, second, third... press of a sequence: a pentatonic, so any
-- two consecutive notes agree, and the root an octave up sits where a fifth press would land.
local SCALE = { 0, 2, 4, 7, 9, 12, 14, 16 }
local RESOLVE_SFX = "SequenceResolve"
local FAIL_SFX = "SequenceFail"
local DISSIPATE_SFX = "SequenceDissipate"

local ComboController = {}

ComboController.SequenceChanged = Signal.new() -- (sequence: { string })
-- A sequence that broke: no glyph matched, or it dissipated. The HUD folds its chain counter away on it.
-- There is no signal for the other half on purpose -- a sequence this client resolved is not a cast, and
-- everything that counts casts (the counter, the onboarding) reads the server's own confirmation instead.
ComboController.SequenceBroken = Signal.new()

local remoteClient: any
local soundController: any
local inputController: any
local hudController: any

local resolver = ComboResolver.new(GlyphConfig.recipes(), GameConfig.Combo.MaxLength)
local sequence: { string } = {}
local generation = 0 -- bumped on every change so a stale timer thread does nothing

local function setSequence(next: { string })
	sequence = next
	ComboController.SequenceChanged:Fire(table.clone(next))
end

local function cancelTimer()
	generation += 1
end

-- The pigment's own note, at the scale degree of its place in the sequence.
local function playNote(pigment: string, position: number)
	local steps = SCALE[math.clamp(position, 1, #SCALE)]
	soundController.play("Note" .. pigment, nil, { Pitch = 2 ^ (steps / 12) })
end

local function cast(pigments: { string })
	remoteClient.fire("CastGlyph", pigments)
end

local function armTimer(delay: number)
	generation += 1
	local expected = generation
	task.delay(delay, function()
		if expected ~= generation then
			return
		end
		local pending = sequence
		local decision = ComboResolver.timeout(resolver, pending)
		if decision.Action == "Cast" then
			-- The five two-press glyphs are each a prefix of a longer recipe, so they only ever resolve
			-- here, by the window running out. Their phrase resolves too.
			soundController.play(RESOLVE_SFX)
			cast(pending)
		elseif decision.Action == "Reset" and decision.Reason == "Dissipated" then
			hudController.showLocalToast("hud.combo.dissipated", nil, "Error")
			soundController.play(DISSIPATE_SFX)
			ComboController.SequenceBroken:Fire()
		end
		setSequence({})
	end)
end

local function onAction(actionId: string, began: boolean)
	if not began or not PigmentConfig.isPigment(actionId) or inputController.isSuspended() then
		return
	end
	local full = table.clone(sequence)
	table.insert(full, actionId)
	local next, decision = ComboResolver.push(resolver, sequence, actionId)
	cancelTimer()

	if decision.Action == "Cast" then
		playNote(actionId, #full)
		soundController.play(RESOLVE_SFX)
		cast(full)
		setSequence({})
	elseif decision.Action == "Wait" then
		playNote(actionId, #next)
		setSequence(next)
		armTimer(if decision.Castable then GameConfig.Combo.ExtendWindowSeconds else GameConfig.Combo.TimeoutSeconds)
	else
		if decision.Action == "Reset" and decision.Reason == "NoMatch" then
			hudController.showLocalToast("hud.combo.noMatch", nil, "Error")
			soundController.play(FAIL_SFX)
			ComboController.SequenceBroken:Fire()
		end
		setSequence({})
	end
end

local function onSuspended(value: boolean)
	if not value then
		return
	end
	cancelTimer()
	if #sequence > 0 then
		setSequence({})
	end
end

function ComboController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
	soundController = deps.SoundController
	inputController = deps.InputController
	hudController = deps.HudController
end

function ComboController.Start()
	inputController.Action:Connect(onAction)
	inputController.SuspendedChanged:Connect(onSuspended)
	if #resolver.duplicates > 0 then
		log.warn("duplicate recipes ignored: %s", table.concat(resolver.duplicates, ", "))
	end
	log.info("started (%d recipes)", #GlyphConfig.Glyphs)
end

return ComboController
