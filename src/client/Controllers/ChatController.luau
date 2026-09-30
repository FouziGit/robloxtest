--!strict
-- ChatController: the VIP tag in the chat (D-209). The VIP pass sells a chat tag; this draws it in Roblox's
-- own TextChatService chat, with no chat interface of ours: every message whose sender owns the pass shows,
-- before the sender's name, the tag in this reader's language, in Orpiment (ChatConfig.VipTag).
--
-- Who wears it is the server's word alone. MonetizationService marks a Vip owner's Player with
-- ChatConfig.VipAttribute, and the tag is read from that attribute on the Player the message's TextSource
-- names: the engine fills TextSource.UserId, not the sender. An attribute a client sets never leaves that
-- client, so one that marks itself is tagged on its own screen and on nobody else's. The message's text is
-- never read.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChatConfig = require(Shared.Config.ChatConfig)
local ChatTag = require(Shared.Pure.ChatTag)
local Log = require(Shared.Util.Log)
local ThemeConfig = require(Shared.Config.ThemeConfig)

local log = Log.new("ChatController")

type Deps = { Localize: { t: (key: string, params: { [string]: any }?) -> string } }

local ChatController = {}

local localize: { t: (key: string, params: { [string]: any }?) -> string }
-- The tag's rich text, built once in Start, when Localize knows the reader's language.
local tag = ""

-- The VIP attribute of the sender of `message`, as this client sees it: nil for a system message, which has
-- no TextSource, and for a sender no longer in the server.
local function senderAttribute(message: TextChatMessage): any
	local source: TextSource? = message.TextSource
	if source == nil then
		return nil
	end
	local sender = Players:GetPlayerByUserId(source.UserId)
	if sender == nil then
		return nil
	end
	return sender:GetAttribute(ChatConfig.VipAttribute)
end

-- TextChatService.OnIncomingMessage: called for every message this client shows, its own included, and it
-- must not yield. Properties left unset keep what the chat drew.
function ChatController.onIncomingMessage(message: TextChatMessage): TextChatMessageProperties
	local properties = Instance.new("TextChatMessageProperties")
	local prefix = ChatTag.prefix(senderAttribute(message), message.PrefixText, tag)
	if prefix ~= nil then
		properties.PrefixText = prefix
	end
	return properties
end

function ChatController.Init(deps: Deps)
	localize = deps.Localize
end

function ChatController.Start()
	tag = ChatTag.markup(localize.t(ChatConfig.VipTag.Key), ThemeConfig.PigmentOnInk[ChatConfig.VipTag.Pigment])
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		log.warn("this place runs the legacy chat, which has no OnIncomingMessage: no VIP tag is drawn")
		return
	end
	TextChatService.OnIncomingMessage = ChatController.onIncomingMessage
	log.info("VIP tag drawn in the chat")
end

return ChatController
