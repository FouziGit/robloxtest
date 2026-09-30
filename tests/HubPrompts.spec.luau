--!strict
-- The hub's prompt pills and a gate's sign, run (tests/engine.luau): the real HubSignsController, Sticker, Motion
-- and Theme.
--
-- A pedestal's prompt lives for the whole session and shows every time the player walks up to it. Each show
-- used to connect a listener to the prompt's Destroying that its hide never cut: fifty visits to the kiosk,
-- fifty listeners, each holding a pill already destroyed.
local Engine = require("./engine")
local Harness = require("./harness")
local PortalConfig = require("../src/shared/Config/PortalConfig")
local Strings = require("../src/shared/Strings")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- The controller started on a hub as far as the shop kiosk, with `gates` standing in the Workspace beside it and
-- `signs` tagged as gates' signs, its words read through `localize` (each key as itself by default). Returns the
-- world, the prompt service, the kiosk's prompt, the PlayerGui, and the signals that add and remove a sign's tag.
local function setup(gates: { any }?, signs: { any }?, localize: any?)
	local world: any
	local player = Engine.instance("Player")
	local playerGui = Engine.instance("PlayerGui", player)
	playerGui.Name = "PlayerGui"
	local promptService = { PromptShown = Engine.signal() }
	local tags = { Added = Engine.signal(), Removed = Engine.signal() }
	world = Engine.world({
		Stubs = Engine.interfaceStubs(),
		Services = {
			Players = { LocalPlayer = player },
			ProximityPromptService = promptService,
			CollectionService = {
				GetInstanceAddedSignal = function(_self: any, tag: string)
					return if tag == PortalConfig.SignTag then tags.Added else Engine.signal()
				end,
				GetInstanceRemovedSignal = function(_self: any, tag: string)
					return if tag == PortalConfig.SignTag then tags.Removed else Engine.signal()
				end,
				GetTagged = function(_self: any, tag: string): { any }
					return if tag == PortalConfig.SignTag then signs or {} else {}
				end,
			},
		},
	})
	player.Parent = world.game
	local controller = world.require("src/client/Controllers/HubSignsController")
	controller.Init({
		Localize = localize or {
			t = function(key: string): string
				return key
			end,
			Changed = Engine.signal(),
		},
		MenuController = {
			isOpen = function(): boolean
				return false
			end,
			open = function(_screen: string) end,
		},
		InputController = {
			SuspendedChanged = Engine.signal(),
			isSuspended = function(): boolean
				return false
			end,
		},
		ClientData = {
			Changed = Engine.signal(),
			get = function(): any
				return nil
			end,
		},
	})
	-- The hub the server builds, as far as the shop kiosk: its model and the panel the prompt stands on.
	local hub = Engine.instance("Folder")
	hub.Name = "Hub"
	local kiosk = Engine.instance("Model", hub)
	kiosk.Name = "ShopKiosk"
	local panel = Engine.instance("BasePart", kiosk)
	panel.Name = "Panel"
	hub.Parent = world.workspace
	for _, gate in ipairs(gates or {}) do
		gate.Parent = world.workspace
	end
	controller.Start()
	local prompt = panel:FindFirstChildOfClass("ProximityPrompt")
	return world, promptService, prompt, playerGui, tags
end

-- A gate's sign, told where it leads, in a gate named `name`.
local function gateSign(name: string, leadsTo: string): (any, any)
	local gate = Engine.instance("Model")
	gate.Name = name
	local sign = Engine.instance("BasePart", gate)
	sign.Name = PortalConfig.Anchors.Sign
	sign:SetAttribute(PortalConfig.SealAttribute, leadsTo)
	return gate, sign
end

-- Everything this client draws on `part`.
local function drawnOn(playerGui: any, part: any): { any }
	local found = {}
	for _, child in ipairs(playerGui:GetDescendants()) do
		if child:IsA("LayerCollector") and child.Adornee == part then
			table.insert(found, child)
		end
	end
	return found
end

describe("the hub's prompt pills, run", function()
	it("leaves no listener on the prompt once its pill is hidden", function()
		local world, promptService, prompt, playerGui = setup()
		expect(prompt).never.toBeNil()
		local listening = prompt.Destroying:count()
		for _ = 1, 50 do
			promptService.PromptShown:Fire(prompt, roblox.Enum.ProximityPromptInputType.Touch)
			world:advance(0.2)
			prompt.PromptHidden:Fire()
			world:advance(1)
		end
		expect(prompt.Destroying:count()).toBe(listening)
		expect(prompt.PromptHidden:count()).toBe(0)
		-- And the pills themselves went.
		local pills = 0
		for _, child in ipairs(playerGui:GetDescendants()) do
			if string.sub(child.Name, 1, 7) == "Prompt_" then
				pills += 1
			end
		end
		expect(pills).toBe(0)
	end)

	it("still takes a shown pill away with a prompt destroyed under it", function()
		local world, promptService, prompt, playerGui = setup()
		promptService.PromptShown:Fire(prompt, roblox.Enum.ProximityPromptInputType.Touch)
		world:advance(0.2)
		local pill = playerGui:FindFirstChild("HubSigns"):FindFirstChild("Prompt_" .. prompt.Name)
		expect(pill).never.toBeNil()
		prompt:Destroy()
		expect(Engine.destroyed(pill)).toBe(true)
	end)
end)

describe("a gate's sign, run", function()
	it("is written once, in the world's size, on the face that looks where its players come from", function()
		local gate, sign = gateSign("BossPortal", "WorldBoss")
		local _world, _prompts, _prompt, playerGui, tags = setup({ gate }, { sign })
		local drawn = drawnOn(playerGui, sign)
		expect(#drawn).toBe(1)
		local surface = drawn[1]
		expect(surface.ClassName).toBe("SurfaceGui")
		expect(surface.Face.Name).toBe("Front")
		expect(surface.SizingMode.Name).toBe("PixelsPerStud")
		expect(surface:FindFirstChild("Name", true).Text).toBe(PortalConfig.Zones.WorldBoss.NameKey)
		expect(surface:FindFirstChild("Hint", true).Text).toBe(PortalConfig.Zones.WorldBoss.HintKey)
		-- Tagged again, it is not written twice; its tag gone, its words go with it.
		tags.Added:Fire(sign)
		expect(#drawnOn(playerGui, sign)).toBe(1)
		tags.Removed:Fire(sign)
		expect(Engine.destroyed(surface)).toBe(true)
	end)

	it("writes a gate that arrives later, and none outside the Workspace or leading nowhere", function()
		local world, _prompts, _prompt, playerGui, tags = setup()
		local stored, template = gateSign("ReturnPortal", "Return")
		tags.Added:Fire(template)
		expect(#drawnOn(playerGui, template)).toBe(0)
		stored.Parent = world.workspace
		tags.Added:Fire(template)
		expect(#drawnOn(playerGui, template)).toBe(1)
		local nowhere, lost = gateSign("Nowhere", "Nowhere")
		nowhere.Parent = world.workspace
		tags.Added:Fire(lost)
		expect(#drawnOn(playerGui, lost)).toBe(0)
	end)
end)

describe("the hub's words, when the language changes", function()
	it("are written again in the new one: the kiosk's prompt and every gate's sign", function()
		local state = { Locale = "en" }
		local localize = {
			t = function(key: string, params: { [string]: any }?): string
				return Strings.t(key, params, state.Locale)
			end,
			Changed = Engine.signal(),
		}
		local gate, sign = gateSign("BossPortal", "WorldBoss")
		local world, _prompts, prompt, playerGui = setup({ gate }, { sign }, localize)
		expect(prompt.ActionText).toBe(Strings.t("hub.prompt.open", nil, "en"))
		expect(prompt.ObjectText).toBe(Strings.t("shop.title", nil, "en"))
		local zone = PortalConfig.Zones.WorldBoss
		expect(drawnOn(playerGui, sign)[1]:FindFirstChild("Name", true).Text).toBe(Strings.t(zone.NameKey, nil, "en"))
		local panel = prompt.Parent

		state.Locale = "fr"
		localize.Changed:Fire("fr")
		world:advance(0.1)
		expect(Engine.destroyed(prompt)).toBe(true)
		local again = panel:FindFirstChildOfClass("ProximityPrompt")
		assert(again ~= nil, "the kiosk lost its prompt")
		expect(again.ActionText).toBe(Strings.t("hub.prompt.open", nil, "fr"))
		expect(again.ObjectText).toBe(Strings.t("shop.title", nil, "fr"))
		local drawn = drawnOn(playerGui, sign)
		expect(#drawn).toBe(1)
		expect(drawn[1]:FindFirstChild("Name", true).Text).toBe(Strings.t(zone.NameKey, nil, "fr"))
		expect(drawn[1]:FindFirstChild("Hint", true).Text).toBe(Strings.t(zone.HintKey, nil, "fr"))
	end)
end)

return nil
