--!strict
-- The VIP tag of the chat (D-202), as pure logic: who wears it, and the rich text that draws it before a
-- sender's name. No require and no Roblox global: ChatController hands in what it read from the engine (the
-- sender's attribute, the reader's words, the pigment) and puts the result on the message.

export type Rgb = { number }

local ChatTag = {}

-- The five characters rich text reads as markup. The tag's words come from Strings, never from a player, but
-- a translation is free text all the same: one of these left bare would break the line or open a tag of its
-- own.
local ESCAPES: { [string]: string } = {
	["&"] = "&amp;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	['"'] = "&quot;",
	["'"] = "&apos;",
}

function ChatTag.escape(text: string): string
	return (string.gsub(text, "[&<>\"']", ESCAPES))
end

-- True when a sender wears the tag. `attribute` is ChatConfig.VipAttribute on the sender's Player as this
-- client sees it, nil for a system message or a sender who has left. Only the boolean the server writes
-- counts: anything else, the string "true" included, is no tag.
function ChatTag.wears(attribute: any): boolean
	return attribute == true
end

-- The tag's rich text: its words, escaped, in bold and in `rgb` (0..255 each).
function ChatTag.markup(words: string, rgb: Rgb): string
	return string.format('<font color="#%02X%02X%02X"><b>%s</b></font>', rgb[1], rgb[2], rgb[3], ChatTag.escape(words))
end

-- The prefix a message shows: the tag, a space, then the prefix the chat gave it (the sender's name, already
-- drawn and escaped by the chat, so left untouched). Nil when the sender wears no tag: the message then keeps
-- the prefix the chat drew.
function ChatTag.prefix(attribute: any, current: string, tag: string): string?
	if not ChatTag.wears(attribute) then
		return nil
	end
	if current == "" then
		return tag
	end
	return tag .. " " .. current
end

return ChatTag
