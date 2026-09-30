--!strict
-- ServerKind: which kind of server this is, and whether ranked play counts on it (E4-S4). Pure module: the caller
-- reads game.PrivateServerId and game.PrivateServerOwnerId and hands them over.
--
-- The rule is the one of the DataModel page's own example (read on 30/09/2026): a private server a player bought
-- has an owner; a reserved server (TeleportService:ReserveServer, for a future cross-server queue) has an id and
-- no owner; a public server has neither.

export type Kind = "Public" | "Purchased" | "Reserved"

local ServerKind = {}

function ServerKind.of(privateServerId: string, privateServerOwnerId: number): Kind
	if privateServerOwnerId ~= 0 then
		return "Purchased"
	end
	if privateServerId ~= "" then
		return "Reserved"
	end
	return "Public"
end

-- A server its owner fills with whoever they like -- a second account, a friend who lets them win -- plays
-- unranked. A reserved server is filled by the game itself, and stays ranked.
function ServerKind.ranked(kind: Kind): boolean
	return kind ~= "Purchased"
end

return ServerKind
