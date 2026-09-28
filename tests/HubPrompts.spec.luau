--!strict
-- The hub's prompt pills, run (tests/engine.luau): the real HubSignsController, Sticker, Motion and Theme.
--
-- A pedestal's prompt lives for the whole session and shows every time the player walks up to it. Each show
-- used to connect a listener to the prompt's Destroying that its hide never cut: fifty visits to the kiosk,
-- fifty listeners, each holding a pill already destroyed.
local Engine = require("./engine")
local Harness = require("./harness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function setup()
	local world: any
	local player = Engine.instance("Player")
	local playerGui = Engine.instance("PlayerGui", player)
	playerGui.Name = "PlayerGui"
	local promptService = { PromptShown = Engine.signal() }
	world = Engine.world({
		Stubs = Engine.interfaceStubs(),
		Services = {
			Players = { LocalPlayer = player },
			ProximityPromptService = promptService,
			CollectionService = {
				GetInstanceAddedSignal = function()
					return Engine.signal()
				end,
				GetInstanceRemovedSignal = function()
					return Engine.signal()
				end,
				GetTagged = function(): { any }
					return {}
				end,
			},
		},
	})
	player.Parent = world.game
	local controller = world.require("src/client/Controllers/HubSignsController")
	controller.Init({
		Localize = {
			t = function(key: string): string
				return key
			end,
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
	controller.Start()
	local prompt = panel:FindFirstChildOfClass("ProximityPrompt")
	return world, promptService, prompt, playerGui
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

return nil
