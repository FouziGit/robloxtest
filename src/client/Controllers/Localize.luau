--!strict
-- Localize: client-side access to Strings, in the language the player reads the experience in. That language is
-- the one Roblox translates the experience into for them: the Translator of
-- LocalizationService:GetTranslatorForPlayerAsync, whose LocaleId follows the language picked in the experience
-- menu. Until the translator answers, and for good when it cannot be had, it is the Roblox app's language
-- (RobloxLocaleId). Strings.localeFromId maps "fr-fr" → "fr", anything else → "en".
--
-- A language changed mid-session fires Changed: the HUD, the screens and the words drawn in the world write
-- themselves again from it, without the player rejoining (E12-S3).

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Log = require(Shared.Util.Log)
local Signal = require(Packages.Signal)
local Strings = require(Shared.Strings)

local log = Log.new("Localize")

export type Params = { [string]: any }

local Localize = {}

-- (locale: string), once the player's language has become another one.
Localize.Changed = Signal.new()

local currentLocale: string = Strings.DefaultLocale

function Localize.locale(): string
	return currentLocale
end

-- The server sends Strings keys as params (e.g. {name = "glyph.Brand.name"}); any string param that is
-- a known key is translated before substitution. Other values pass through untouched.
function Localize.resolveParams(params: Params?): Params?
	if params == nil then
		return nil
	end
	local resolved: Params = {}
	for name, value in pairs(params) do
		if type(value) == "string" and Strings.has(value) then
			-- Pass the surrounding params through: a nested key such as a quest name carries its own
			-- placeholders ("Cast {target} glyphs"), filled from the same payload.
			resolved[name] = Strings.t(value, params, currentLocale)
		else
			resolved[name] = value
		end
	end
	return resolved
end

function Localize.t(key: string, params: Params?): string
	return Strings.t(key, params, currentLocale)
end

-- `key` counting `n`, in the form the player's language gives that count (Strings.plural).
function Localize.plural(key: string, n: number, params: Params?): string
	return Strings.plural(key, n, params, currentLocale)
end

-- The language `localeId` names, taken as the player's when it is another one than theirs.
local function adopt(localeId: string, source: string)
	local locale = Strings.localeFromId(localeId)
	if locale == currentLocale then
		return
	end
	currentLocale = locale
	log.info("locale %s (%s %s)", locale, source, localeId)
	Localize.Changed:Fire(locale)
end

-- Yields on the platform's answer, so it runs in its own thread.
local function followTranslator()
	local ok, translator = pcall(function(): Translator
		return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
	end)
	if not ok then
		log.warn(
			"no translator for this player, the app's language stays (%s): %s",
			currentLocale,
			tostring(translator)
		)
		return
	end
	adopt(translator.LocaleId, "translator")
	translator:GetPropertyChangedSignal("LocaleId"):Connect(function()
		adopt(translator.LocaleId, "translator")
	end)
end

function Localize.Init()
	currentLocale = Strings.localeFromId(LocalizationService.RobloxLocaleId)
end

function Localize.Start()
	log.info("locale %s (app %s)", currentLocale, LocalizationService.RobloxLocaleId)
	task.spawn(followTranslator)
end

return Localize
