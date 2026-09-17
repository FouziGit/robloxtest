--!strict
-- NotifyService: server → client toasts. A payload carries a Strings key plus params and the client
-- localizes it, so no player-facing text is ever assembled on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local log = Log.new("NotifyService")

export type Kind = "Info" | "Success" | "Error"
export type Params = { [string]: any }
export type Payload = { Key: string, Params: Params?, Kind: Kind, Sfx: string? }

type Registry = {
	fire: (name: string, player: Player, ...any) -> (),
	fireAll: (name: string, ...any) -> (),
}
type Deps = { Registry: Registry }

local NotifyService = {}

local registry: Registry

local function payload(key: string, params: Params?, kind: Kind?, sfx: string?): Payload
	if not Strings.has(key) then
		log.warn("unknown Strings key %s", key)
	end
	return { Key = key, Params = params, Kind = kind or "Info", Sfx = sfx }
end

function NotifyService.send(player: Player, key: string, params: Params?, kind: Kind?, sfx: string?)
	if player.Parent ~= Players then
		return
	end
	registry.fire("Notify", player, payload(key, params, kind, sfx))
end

function NotifyService.sendAll(key: string, params: Params?, kind: Kind?, sfx: string?)
	registry.fireAll("Notify", payload(key, params, kind, sfx))
end

function NotifyService.Init(deps: Deps)
	registry = deps.Registry
end

function NotifyService.Start()
	log.info("started")
end

return NotifyService
