--!strict
-- LocaleService: the language each player reads the server's own words in. The server writes almost none: a
-- message it sends is a Strings key the client translates. What it must write itself is a kick's reason
-- (DataService, AntiCheatService), shown by the engine after the client is gone.
--
-- That language is the one the client reads (Localize): the player's Translator, from
-- LocalizationService:GetTranslatorForPlayerAsync, whose LocaleId follows the language picked in the experience
-- menu. Asked for as the player joins, so that a kick never waits on it. Until it answers, and for good when it
-- cannot be had, Player.LocaleId: the language of the player's Roblox app, the server's view of what the client
-- reads as LocalizationService.RobloxLocaleId (the server's own RobloxLocaleId is the server's, not the player's).

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local log = Log.new("LocaleService")

local LocaleService = {}

-- Each player's Translator, once the platform has given it.
local translators: { [Player]: Translator } = {}

-- The Strings locale ("en", "fr") `player` reads the server's words in.
function LocaleService.of(player: Player): string
	local translator: Translator? = translators[player]
	return Strings.localeFromId(if translator ~= nil then translator.LocaleId else player.LocaleId)
end

-- Yields on the platform's answer, so it runs in its own thread.
local function fetch(player: Player)
	local ok, translator = pcall(function(): Translator
		return LocalizationService:GetTranslatorForPlayerAsync(player)
	end)
	if not ok then
		log.warn(
			"no translator for user %d, the app's language stays (%s): %s",
			player.UserId,
			tostring(player.LocaleId),
			tostring(translator)
		)
		return
	end
	-- A player who left while the platform answered is not kept.
	if player.Parent == Players then
		translators[player] = translator
	end
end

function LocaleService.Init(_deps: any)
	Players.PlayerRemoving:Connect(function(player: Player)
		translators[player] = nil
	end)
end

function LocaleService.Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(fetch, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(fetch, player)
	end
	log.info("started")
end

return LocaleService
