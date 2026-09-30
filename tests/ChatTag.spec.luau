--!strict
-- The VIP tag in the chat (D-202). The VIP pass promised a chat tag that no code drew: there was no
-- TextChatService, no OnIncomingMessage and no PrefixText anywhere in src (docs/QA.md R1).
--
-- Three layers, each run: the pure rule (who wears the tag, its markup), the server marking a Vip owner's
-- Player from the pass cache (the real Passes module), and the client drawing the tag from that mark alone
-- (the real ChatController, in the reader's language).
local ChatConfig = require("../src/shared/Config/ChatConfig")
local ChatTag = require("../src/shared/Pure/ChatTag")
local Engine = require("./engine")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- A Log whose lines a spec reads instead of printing them.
local function recordingLog(): (any, { string })
	local lines: { string } = {}
	local function record(message: string, ...: any)
		local ok, text = pcall(string.format, message, ...)
		table.insert(lines, if ok then text else message)
	end
	local module = {
		new = function(_prefix: string): any
			return {
				info = record,
				warn = record,
				error = record,
				try = function(_context: string, fn: (...any) -> ...any, ...: any): boolean
					return (pcall(fn, ...))
				end,
				succeeded = function(_context: string, fn: (...any) -> ...any, ...: any): boolean
					local ok, result = pcall(fn, ...)
					return ok and result and true or false
				end,
			}
		end,
	}
	return module, lines
end

-- Localize.t for a reader of `locale`.
local function reader(locale: string): (key: string) -> string
	return function(key: string): string
		return Strings.t(key, nil, locale)
	end
end

-- The tag drawn in `words`, in its pigment.
local function tagIn(words: string): string
	return ChatTag.markup(words, ThemeConfig.PigmentOnInk[ChatConfig.VipTag.Pigment])
end

----------------------------------------------------------------
-- The client: the real ChatController over a pretend TextChatService
----------------------------------------------------------------

type Chat = { service: any, world: any, lines: { string }, sender: (userId: number, attribute: any) -> any }

-- `translate` stands for Localize.t in the reader's language.
local function chat(translate: (key: string) -> string, chatVersion: any?): Chat
	local service = Engine.instance("TextChatService")
	service.ChatVersion = chatVersion or roblox.Enum.ChatVersion.TextChatService
	local Log, lines = recordingLog()
	local world = Engine.world({ Services = { TextChatService = service }, Stubs = { ["src/shared/Util/Log"] = Log } })
	local players = world.game:GetService("Players")
	local byId: { [number]: any } = {}
	players.GetPlayerByUserId = function(_self: any, userId: number): any
		return byId[userId]
	end
	local Controller = world.require("src/client/Controllers/ChatController")
	Controller.Init({
		Localize = {
			t = function(key: string, _params: any?): string
				return translate(key)
			end,
		},
	})
	Controller.Start()
	return {
		service = service,
		world = world,
		lines = lines,
		sender = function(userId: number, attribute: any): any
			local player = Engine.instance("Player", players)
			player.UserId = userId
			player:SetAttribute(ChatConfig.VipAttribute, attribute)
			byId[userId] = player
			return player
		end,
	}
end

-- What the chat shows before a message's text, once the controller's callback has run.
local function shown(session: Chat, userId: number?, prefix: string): string
	local callback = session.service.OnIncomingMessage
	assert(type(callback) == "function", "no OnIncomingMessage callback was installed")
	local message = {
		TextSource = if userId ~= nil then { UserId = userId } else nil,
		PrefixText = prefix,
	}
	local properties = callback(message)
	assert(properties ~= nil, "OnIncomingMessage returned nothing")
	local override = properties.PrefixText
	return if override ~= nil then override else prefix
end

----------------------------------------------------------------
-- The server: the real Passes module, marking the Player
----------------------------------------------------------------

local function passes(data: any): (any, any)
	local Log = recordingLog()
	local market = {
		UserOwnsGamePassAsync = function(_self: any, _userId: number, _passId: number): boolean
			return false
		end,
	}
	local world =
		Engine.world({ Services = { MarketplaceService = market }, Stubs = { ["src/shared/Util/Log"] = Log } })
	local Passes = world.require("src/server/Services/MonetizationService/Passes")
	Passes.Init({
		DataService = {
			get = function(_player: any): any
				return data
			end,
			push = function() end,
			saveNow = function(): boolean
				return true
			end,
		},
		Loadout = {
			grantPigment = function(): boolean
				return true
			end,
			setExtraSlots = function(): boolean
				return true
			end,
		},
		Cosmetic = {
			grant = function(): boolean
				return true
			end,
		},
		Analytics = { custom = function() end },
		Notify = { send = function() end },
	})
	local player = Engine.instance("Player", world.game:GetService("Players"))
	player.UserId = 42
	return Passes, player
end

describe("the VIP chat tag", function()
	it("is worn only by a sender the server marked with the boolean true", function()
		expect(ChatTag.wears(true)).toBe(true)
		for _, value in ipairs({ false, "true", 1, "VIP", {} } :: { any }) do
			expect(ChatTag.wears(value)).toBe(false)
		end
		expect(ChatTag.wears(nil)).toBe(false)
		expect(ChatTag.prefix(nil, "Alice", "[T]")).toBeNil()
		expect(ChatTag.prefix("true", "Alice", "[T]")).toBeNil()
		expect(ChatTag.prefix(true, "Alice", "[T]")).toBe("[T] Alice")
		expect(ChatTag.prefix(true, "", "[T]")).toBe("[T]")
	end)

	it("is bold rich text in the pigment's exact colour, its words escaped", function()
		expect(ChatTag.markup("[VIP]", { 232, 192, 34 })).toBe('<font color="#E8C022"><b>[VIP]</b></font>')
		expect(ChatTag.markup("<b>&'\"", { 0, 10, 255 })).toBe(
			'<font color="#000AFF"><b>&lt;b&gt;&amp;&apos;&quot;</b></font>'
		)
	end)

	it("reads its words from Strings in both languages, and its colour from an ink pigment", function()
		for _, locale in ipairs(Strings.Locales) do
			local entry = Strings.Table[ChatConfig.VipTag.Key] :: any
			expect(entry ~= nil and type(entry[locale]) == "string" and entry[locale] ~= "").toBe(true)
		end
		local rgb = ThemeConfig.PigmentOnInk[ChatConfig.VipTag.Pigment]
		expect(rgb).toEqual(ThemeConfig.PigmentOnInk.Orpiment)
	end)

	it("is drawn before a marked sender's name, in the reader's language", function()
		for _, locale in ipairs(Strings.Locales) do
			local session = chat(reader(locale))
			session.sender(7, true)
			expect(shown(session, 7, '<font color="#AABBCC">Alice</font>')).toBe(
				tagIn(Strings.t(ChatConfig.VipTag.Key, nil, locale)) .. ' <font color="#AABBCC">Alice</font>'
			)
		end
		-- Both languages write "[VIP]": a translator that tells them apart proves the words are asked of
		-- Localize, by their key, and escaped on the way.
		local session = chat(function(key: string): string
			return "<fr:" .. key .. ">"
		end)
		session.sender(7, true)
		expect(shown(session, 7, "Alice")).toBe(tagIn("<fr:" .. ChatConfig.VipTag.Key .. ">") .. " Alice")
		expect(shown(session, 7, "Alice")).toContain("&lt;fr:chat.vipTag&gt;")
	end)

	it("is never drawn from anything but the server's mark", function()
		local session = chat(reader("en"))
		session.sender(8, nil)
		session.sender(9, "true")
		session.sender(10, false)
		expect(shown(session, 8, "Bob")).toBe("Bob")
		expect(shown(session, 9, "Eve")).toBe("Eve")
		expect(shown(session, 10, "Dan")).toBe("Dan")
		-- A system message has no TextSource, and a sender who left has no Player.
		expect(shown(session, nil, "")).toBe("")
		expect(shown(session, 404, "Gone")).toBe("Gone")
	end)

	it("follows the mark as the server moves it", function()
		local session = chat(reader("en"))
		local player = session.sender(11, nil)
		expect(shown(session, 11, "Ann")).toBe("Ann")
		player:SetAttribute(ChatConfig.VipAttribute, true)
		expect(shown(session, 11, "Ann")).toBe(tagIn(Strings.t(ChatConfig.VipTag.Key, nil, "en")) .. " Ann")
		player:SetAttribute(ChatConfig.VipAttribute, nil)
		expect(shown(session, 11, "Ann")).toBe("Ann")
	end)

	it("is not installed on the legacy chat, and says so", function()
		local session = chat(reader("en"), roblox.Enum.ChatVersion.LegacyChatService)
		expect(session.service.OnIncomingMessage).toBeNil()
		expect(#session.lines).toBeGreaterThan(0)
	end)
end)

describe("the server's VIP mark", function()
	it("is set on a player whose cache holds Vip as soon as the passes sync", function()
		local data = { Passes = { Vip = true } }
		local Passes, player = passes(data)
		Passes.sync(player)
		expect(player:GetAttribute(ChatConfig.VipAttribute)).toBe(true)
	end)

	it("is absent from a player without Vip, whatever else they own", function()
		local data = { Passes = { LoadoutSlots = true, SkinPack = true } }
		local Passes, player = passes(data)
		player:SetAttribute(ChatConfig.VipAttribute, true)
		Passes.sync(player)
		expect(player:GetAttribute(ChatConfig.VipAttribute)).toBeNil()
	end)

	it("is set the moment Vip enters the cache", function()
		local data = { Passes = {} }
		local Passes, player = passes(data)
		Passes.cache(player, "SkinPack")
		expect(player:GetAttribute(ChatConfig.VipAttribute)).toBeNil()
		Passes.cache(player, "Vip")
		expect(player:GetAttribute(ChatConfig.VipAttribute)).toBe(true)
	end)
end)
