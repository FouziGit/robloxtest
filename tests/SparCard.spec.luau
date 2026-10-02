--!strict
-- The practice duel on the Play screen, run (E10-S6): the real PlayScreen, in the player's words (the real Strings,
-- in English), over a queue and an offer the spec sets as the server would push them. The 1v1 card offers the
-- spar once the server does, says what it pays today, and walks out of one being fought; the 3v3 card never
-- does. On the smallest phone its two buttons each fit the card, one under the other.
local Engine = require("./engine")
local Harness = require("./harness")
local Layout = require("./layout")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local Measure = require("./measure")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SPAR = MatchConfig.Spar

local function english(key: string, params: { [string]: any }?): string
	return Strings.t(key, params, "en")
end

type Fixture = {
	screen: any,
	asked: { string },
	queue: any,
	spar: any,
	changed: any,
	height: number,
	width: number,
	textButton: number,
}
-- Where the player stands: queued in the 1v1 or not, the spar offered, one being fought, today's paid spars left.
type State = { Queued: boolean, Offered: boolean, Sparring: boolean, PaidLeft: number }

local function build(state: State, phone: { number }?): Fixture
	local queued, offered, sparring, paidLeft = state.Queued, state.Offered, state.Sparring, state.PaidLeft
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local height = if phone ~= nil then Engine.phone(world, phone[1], phone[2]) else 1080
	local width = if phone ~= nil then height * phone[1] / phone[2] else 1920
	local Screen = world.require("src/ui/screens/PlayScreen")
	local asked: { string } = {}
	local queue = {
		Queued = queued,
		ModeId = if queued then SPAR.QueueModeId else nil,
		WaitedSeconds = 25,
		QueuedCount = 1,
		NeededCount = 2,
	}
	local spar = { Offered = offered, Sparring = sparring, PaidLeft = paidLeft, PaidPerDay = SPAR.PaidPerDay }
	local changed = Engine.signal()
	local screen = Screen.new({
		Localize = { t = english },
		ClientData = {
			get = function(): any
				return nil
			end,
			Changed = Engine.signal(),
		},
		RemoteClient = { fire = function() end },
		InputController = { captureNext = function() end },
		SoundController = { play = function() end },
		HudController = { Notified = Engine.signal() },
		MatchController = {
			QueueChanged = Engine.signal(),
			getQueue = function(): any
				return queue
			end,
			-- A public server, where ranked play counts (E4-S4).
			rankedHere = function(): boolean
				return true
			end,
			joinQueue = function() end,
			leaveQueue = function()
				table.insert(asked, "leaveQueue")
			end,
			SparChanged = changed,
			getSpar = function(): any
				return spar
			end,
			startSpar = function()
				table.insert(asked, "startSpar")
			end,
			leaveSpar = function()
				table.insert(asked, "leaveSpar")
			end,
		},
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	screen:Open()
	world:advance(0.5)
	return {
		screen = screen,
		asked = asked,
		queue = queue,
		spar = spar,
		changed = changed,
		height = height,
		width = width,
		textButton = world.require("src/ui/Theme").Sizes.TextButton,
	}
end

local function card(fixture: Fixture, modeId: string): any
	local found = fixture.screen.Instance:FindFirstChild(modeId, true)
	assert(found ~= nil, "no card for " .. modeId)
	return found
end

local function button(fixture: Fixture, modeId: string, name: string): any
	return card(fixture, modeId):FindFirstChild(name, true)
end

local function press(target: any)
	target.Activated:Fire()
end

describe("the practice duel on the Play screen, run", function()
	it(
		"is offered on the 1v1 card once the server offers it: its pitch, today's pay, and a Spar first in line",
		function()
			local fixture = build({ Queued = true, Offered = true, Sparring = false, PaidLeft = 2 })
			local spar = button(fixture, SPAR.QueueModeId, "Spar")
			assert(spar ~= nil, "the 1v1 card has no Spar button")
			expect(spar.Visible).toBe(true)
			expect(button(fixture, SPAR.QueueModeId, "LeaveSpar").Visible).toBe(false)
			local duel = card(fixture, SPAR.QueueModeId)
			expect(duel:FindFirstChild("Rule", true).Text).toBe(english("spar.pitch"))
			expect(duel:FindFirstChild("Players", true).Text).toBe(
				english("spar.paidLeft", { left = 2, total = SPAR.PaidPerDay })
			)
			press(spar)
			expect(fixture.asked).toEqual({ "startSpar" })
		end
	)

	it("says the day's pay is spent, and still offers it", function()
		local fixture = build({ Queued = true, Offered = true, Sparring = false, PaidLeft = 0 })
		expect(button(fixture, SPAR.QueueModeId, "Spar").Visible).toBe(true)
		expect(card(fixture, SPAR.QueueModeId):FindFirstChild("Players", true).Text).toBe(english("spar.noneLeft"))
	end)

	it("shows nothing of it before the server offers it, and never on the 3v3 card", function()
		local fixture = build({ Queued = true, Offered = false, Sparring = false, PaidLeft = 3 })
		expect(button(fixture, SPAR.QueueModeId, "Spar").Visible).toBe(false)
		local duel = card(fixture, SPAR.QueueModeId)
		expect(duel:FindFirstChild("Rule", true).Text).toBe(english("queue.rule", { rounds = 2 }))
		expect(button(fixture, "Team3v3", "Spar")).toBeNil()
		expect(button(fixture, "Team3v3", "LeaveSpar")).toBeNil()
		-- The server offers it: the card follows at once.
		fixture.spar.Offered = true
		fixture.changed:Fire(fixture.spar)
		expect(button(fixture, SPAR.QueueModeId, "Spar").Visible).toBe(true)
	end)

	it("walks out of a spar being fought, and says a real opponent takes over at the next break", function()
		local fixture = build({ Queued = true, Offered = false, Sparring = true, PaidLeft = 2 })
		local out = button(fixture, SPAR.QueueModeId, "LeaveSpar")
		expect(out.Visible).toBe(true)
		expect(button(fixture, SPAR.QueueModeId, "Spar").Visible).toBe(false)
		expect(card(fixture, SPAR.QueueModeId):FindFirstChild("Rule", true).Text).toBe(english("spar.sparring"))
		press(out)
		expect(fixture.asked).toEqual({ "leaveSpar" })
	end)

	it("fits each of its buttons in the card on the smallest phone, the second under the first", function()
		for _, state in ipairs({
			{ Queued = true, Offered = true, Sparring = false, PaidLeft = 2 },
			{ Queued = true, Offered = false, Sparring = true, PaidLeft = 2 },
		}) do
			local fixture = build(state, { 667, 375 })
			local duel = card(fixture, SPAR.QueueModeId)
			local actions = duel:FindFirstChild("Actions", true)
			expect(actions:FindFirstChildOfClass("UIListLayout").Wraps).toBe(true)
			local normal = duel:FindFirstChild("Normal", true)
			local padding = normal:FindFirstChildOfClass("UIPadding")
			local inner = Measure.widthOf(normal, fixture.width)
				- padding.PaddingLeft.Offset
				- padding.PaddingRight.Offset
			for _, key in ipairs({ "spar.start", "spar.leave", "queue.leave" }) do
				for _, locale in ipairs({ "en", "fr" }) do
					local width = Measure.buttonWidth(Strings.t(key, nil, locale), fixture.textButton, true)
					if width > inner then
						error(("%s (%s) is %.0f wide on a card of %.0f"):format(key, locale, width, inner))
					end
				end
			end
			local found = Layout.check(fixture.screen.Instance, fixture.height)
			if #found > 0 then
				error(table.concat(found, "\n"))
			end
		end
	end)
end)

describe("the client's mirror of the practice duel, run", function()
	local function controller(): (any, { any }, { [string]: (any) -> () })
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local MatchController = world.require("src/client/Controllers/MatchController")
		local sent: { any } = {}
		local heard: { [string]: (any) -> () } = {}
		MatchController.Init({
			RemoteClient = {
				fire = function(name: string, ...: any)
					table.insert(sent, { name, ... })
				end,
				on = function(name: string, handler: (any) -> ())
					heard[name] = handler
				end,
			},
			SoundController = { play = function() end, wantMusic = function() end },
		})
		MatchController.Start()
		return MatchController, sent, heard
	end

	it("asks for a spar only while the server offers one, and to leave one only while fighting it", function()
		local match, sent, heard = controller()
		match.startSpar()
		match.leaveSpar()
		expect(#sent).toBe(0)
		heard.SparChanged({ Offered = true, Sparring = false, PaidLeft = 3, PaidPerDay = 3 })
		expect(match.getSpar().Offered).toBe(true)
		match.startSpar()
		expect(sent).toEqual({ { "StartSpar" } })
		heard.SparChanged({ Offered = false, Sparring = true, PaidLeft = 2, PaidPerDay = 3 })
		match.leaveSpar()
		expect(sent[2]).toEqual({ "LeaveSpar" })
		-- A malformed push changes nothing.
		heard.SparChanged("nonsense")
		expect(match.getSpar().Sparring).toBe(true)
	end)

	it("plays a spar again through the queue it was offered in, and never names a mode no queue plays", function()
		local match, sent = controller()
		match.joinQueue(MatchConfig.Modes.Spar1v1.Id)
		expect(sent).toEqual({ { "JoinQueue", SPAR.QueueModeId } })
		match.joinQueue("WorldBoss")
		match.joinQueue("Nonsense")
		expect(#sent).toBe(1)
	end)
end)

return nil
