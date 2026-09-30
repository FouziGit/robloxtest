--!strict
-- The chat tag the VIP pass sells (pass.vip.desc, docs/ECONOMY.md §4; D-202). Pure data, read by the server,
-- which marks who wears the tag, and by every client, which draws it.

local ChatConfig = {}

-- The attribute MonetizationService (Passes) sets on the Player of a Vip owner, from the pass cache, and
-- clears when the pass leaves it. The server's value is the only one another client ever sees: a client that
-- sets it on its own Player changes its own screen and nobody else's. ChatController draws the tag from this
-- attribute and from nothing else.
ChatConfig.VipAttribute = "VellumVip"

-- The tag drawn before the sender's name in the chat window: its words (a Strings key, read in the reader's
-- language) and the pigment it is inked in, looked up in ThemeConfig.PigmentOnInk, the colour a pigment takes
-- over ink, because the chat window is a dark plate. Orpiment, the gold of the five pigments, and never the
-- Primary gold: the chat stays on screen in a fight, where no value colour enters (docs/ART_BIBLE.md rule 11).
ChatConfig.VipTag = {
	Key = "chat.vipTag",
	Pigment = "Orpiment",
}

return ChatConfig
