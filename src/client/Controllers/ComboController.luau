--!strict
-- ComboController: turns element presses into jutsu casts. Feeds the shared ComboResolver, arms the
-- inactivity timer (short extend window when the pending sequence is already a recipe), sends
-- `CastJutsu` with the element sequence and reports resets to the HUD. The server re-validates
-- every sequence; this controller only decides when to send it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local ComboResolver = require(Shared.Pure.ComboResolver)
local ElementConfig = require(Shared.Config.ElementConfig)
local GameConfig = require(Shared.Config.GameConfig)
local JutsuConfig = require(Shared.Config.JutsuConfig)
local Log = require(Shared.Util.Log)
local Signal = require(Packages.Signal)

local log = Log.new("ComboController")

type Deps = { RemoteClient: any, SoundController: any, InputController: any, HudController: any }

local PUSH_SFX = "UiClick"

local ComboController = {}

ComboController.SequenceChanged = Signal.new() -- (sequence: { string })

local remoteClient: any
local soundController: any
local inputController: any
local hudController: any

local resolver = ComboResolver.new(JutsuConfig.recipes(), GameConfig.Combo.MaxLength)
local sequence: { string } = {}
local generation = 0 -- bumped on every change so a stale timer thread does nothing

local function setSequence(next: { string })
	sequence = next
	ComboController.SequenceChanged:Fire(table.clone(next))
end

local function cancelTimer()
	generation += 1
end

local function cast(elements: { string })
	remoteClient.fire("CastJutsu", elements)
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
			cast(pending)
		elseif decision.Action == "Reset" and decision.Reason == "Dissipated" then
			hudController.showLocalToast("hud.combo.dissipated", nil, "Error")
		end
		setSequence({})
	end)
end

local function onAction(actionId: string, began: boolean)
	if not began or not ElementConfig.isElement(actionId) or inputController.isSuspended() then
		return
	end
	local full = table.clone(sequence)
	table.insert(full, actionId)
	local next, decision = ComboResolver.push(resolver, sequence, actionId)
	cancelTimer()
	soundController.play(PUSH_SFX)

	if decision.Action == "Cast" then
		cast(full)
		setSequence({})
	elseif decision.Action == "Wait" then
		setSequence(next)
		armTimer(if decision.Castable then GameConfig.Combo.ExtendWindowSeconds else GameConfig.Combo.TimeoutSeconds)
	else
		if decision.Action == "Reset" and decision.Reason == "NoMatch" then
			hudController.showLocalToast("hud.combo.noMatch", nil, "Error")
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
	log.info("started (%d recipes)", #JutsuConfig.Jutsus)
end

return ComboController
