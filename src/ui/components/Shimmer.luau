--!strict
-- Shimmer: the sweep of light across gold leaf (D-147) -- a Legendary's ribbon and card, the Codex seal, the
-- seventh day. A sheet-coloured shine over the whole of what it is laid on, the Shimmer gradient swept across
-- it, a pause, the next sweep. One of the few animated gradients a screen may have: a screen sweeps
-- Theme.Budget.MaxAnimatedGradients of them at most, and one asked for past that stays still (named once in
-- the log), like a splat past its budget. None under reduced motion or on the lowest graphics tier.
--
-- The shine takes no input: laid over a card, the buttons under it still take the clicks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Log"))
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Shimmer = {
	-- The shine, or nil where the player asked for no motion or the lowest quality.
	Instance: Frame?,
	Destroy: (self: Shimmer) -> (),
}

local Shimmer = {}

local log = Log.new("Shimmer")

-- The shimmers sweeping on each screen (its LayerCollector), by gradient, and the screens already named
-- for asking past their budget.
local sweepingOn: { [Instance]: { [Instance]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local overBudget: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- A shine over the whole of `host`, rounded by `corner`, drawn at `zIndex`.
function Shimmer.new(host: GuiObject, corner: UDim, zIndex: number): Shimmer
	local trove = Trove.new()

	local function destroy(_self: Shimmer)
		trove:Destroy()
	end

	if UiPrefs.reducedMotion() or UiPrefs.lowQuality() then
		return { Instance = nil, Destroy = destroy }
	end

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Theme.Colors.PanelRaised
	shine.Size = UDim2.fromScale(1, 1)
	shine.ZIndex = zIndex
	shine.Active = false
	shine.Interactable = false
	Theme.corner(shine, corner)
	local gradient = Theme.gradient("Shimmer")
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = shine
	trove:Add(shine)

	-- One sweep, a pause, the next; only while the host is on a screen the player has open, and again when it
	-- comes back. A closed screen is disabled, not destroyed (ScreenRoot): the host is still in the DataModel,
	-- and without the Enabled test it swept for the rest of the session.
	local running = true
	local sweeping = false
	local watched: LayerCollector? = nil
	local watching: RBXScriptConnection? = nil
	local claimed: Instance? = nil
	local function unwatch()
		local connection = watching
		if connection ~= nil then
			connection:Disconnect()
			watching = nil
		end
	end
	-- Gives back this shimmer's place on its screen's budget.
	local function unclaim()
		local layer = claimed
		claimed = nil
		local onLayer = if layer ~= nil then sweepingOn[layer] else nil
		if onLayer ~= nil then
			onLayer[gradient] = nil
		end
	end
	-- Takes a place on the budget of `layer`, unless its shimmers have them all.
	local function claim(layer: Instance): boolean
		if claimed == layer then
			return true
		end
		unclaim()
		local onLayer = sweepingOn[layer] or {}
		sweepingOn[layer] = onLayer
		local count = 0
		for other in pairs(onLayer) do
			if other:IsDescendantOf(layer) then
				count += 1
			else
				onLayer[other] = nil
			end
		end
		if count >= Theme.Budget.MaxAnimatedGradients then
			if not overBudget[layer] then
				overBudget[layer] = true
				log.warn(
					"%s asked for more than %d shimmers: the extra ones stay still",
					layer:GetFullName(),
					Theme.Budget.MaxAnimatedGradients
				)
			end
			return false
		end
		onLayer[gradient] = true
		claimed = layer
		return true
	end
	trove:Add(function()
		running = false
		unwatch()
		unclaim()
		Motion.cancel(gradient)
	end)
	local function shown(): boolean
		if not gradient:IsDescendantOf(game) then
			return false
		end
		local layer = host:FindFirstAncestorWhichIsA("LayerCollector") :: LayerCollector?
		return layer ~= nil and layer.Enabled
	end
	local function sweep()
		local layer = host:FindFirstAncestorWhichIsA("LayerCollector")
		if not running or not shown() or layer == nil or not claim(layer) then
			sweeping = false
			unclaim()
			return
		end
		sweeping = true
		Motion.set(gradient, { Offset = Vector2.new(-1, 0) })
		Motion.to(gradient, { Offset = Vector2.new(1, 0) }, "Ui", function()
			task.delay(Theme.Timing.ShimmerPauseSeconds, sweep)
		end)
	end
	local function resume()
		if running and not sweeping and shown() then
			sweep()
		end
	end
	trove:Connect(host.AncestryChanged, function()
		local layer = host:FindFirstAncestorWhichIsA("LayerCollector") :: LayerCollector?
		if layer ~= watched then
			watched = layer
			unwatch()
			if layer ~= nil then
				watching = layer:GetPropertyChangedSignal("Enabled"):Connect(resume)
			end
		end
		resume()
	end)

	shine.Parent = host
	-- Already on a screen: the host's ancestry will not change to say so.
	if host:IsDescendantOf(game) then
		local layer = host:FindFirstAncestorWhichIsA("LayerCollector") :: LayerCollector?
		watched = layer
		if layer ~= nil then
			watching = layer:GetPropertyChangedSignal("Enabled"):Connect(resume)
		end
		resume()
	end

	return { Instance = shine, Destroy = destroy }
end

return Shimmer
