--!strict
-- Localize: client-side access to Strings. The locale is resolved once from
-- LocalizationService.RobloxLocaleId (Strings.localeFromId maps "fr-fr" → "fr", anything else → "en").

local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local log = Log.new("Localize")

export type Params = { [string]: any }

local Localize = {}

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
			-- placeholders ("Cast {target} jutsus"), filled from the same payload.
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

function Localize.Init()
	currentLocale = Strings.localeFromId(LocalizationService.RobloxLocaleId)
end

function Localize.Start()
	log.info("locale %s", currentLocale)
end

return Localize
