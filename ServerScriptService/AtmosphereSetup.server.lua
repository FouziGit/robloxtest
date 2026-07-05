--[[
	AtmosphereSetup — Script (serveur)
	EMPLACEMENT : ServerScriptService (à la racine, à côté de MainServer)

	Habille le monde d'un coup : éclairage, atmosphère, ciel, et effets
	post-traitement (Bloom, rayons de soleil, correction colorimétrique,
	profondeur de champ). Tourne côté serveur -> tout le monde voit pareil.

	Tout est réglable en haut du fichier (CONFIG). Idempotent : relancer le
	jeu ne crée pas de doublons, ça met juste à jour les valeurs.
]]

local Lighting = game:GetService("Lighting")

----------------------------------------------------------------
-- CONFIG (change les chiffres pour ajuster l'ambiance)
----------------------------------------------------------------
local CONFIG = {
	ClockTime = 14.5,                     -- heure du jour (0-24). 6=aube, 18=crépuscule
	GeographicLatitude = 30,
	Brightness = 2.2,
	ExposureCompensation = 0.15,
	ShadowSoftness = 0.35,
	Ambient = Color3.fromRGB(70, 72, 82),
	OutdoorAmbient = Color3.fromRGB(120, 125, 145),
	FogColorLegacy = Color3.fromRGB(190, 200, 215),
}

----------------------------------------------------------------
-- OUTIL : trouve ou crée un objet nommé sous Lighting (anti-doublon)
----------------------------------------------------------------
local function ensure(className, name, parent)
	parent = parent or Lighting
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	if existing then
		existing:Destroy() -- mauvais type sous ce nom : on repart propre
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

----------------------------------------------------------------
-- ÉCLAIRAGE GLOBAL
----------------------------------------------------------------
-- Technology n'est pas toujours modifiable à l'exécution : on tente sans planter.
pcall(function()
	Lighting.Technology = Enum.Technology.Future
end)

Lighting.ClockTime = CONFIG.ClockTime
Lighting.GeographicLatitude = CONFIG.GeographicLatitude
Lighting.Brightness = CONFIG.Brightness
Lighting.ExposureCompensation = CONFIG.ExposureCompensation
Lighting.ShadowSoftness = CONFIG.ShadowSoftness
Lighting.Ambient = CONFIG.Ambient
Lighting.OutdoorAmbient = CONFIG.OutdoorAmbient
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1
Lighting.GlobalShadows = true
Lighting.FogColor = CONFIG.FogColorLegacy -- utilisé si l'Atmosphere est retirée

----------------------------------------------------------------
-- ATMOSPHÈRE (brume volumétrique, remplace le vieux fog)
----------------------------------------------------------------
local atmosphere = ensure("Atmosphere", "Atmosphere")
atmosphere.Density = 0.34
atmosphere.Offset = 0.10
atmosphere.Color = Color3.fromRGB(199, 205, 214)
atmosphere.Decay = Color3.fromRGB(106, 112, 125)
atmosphere.Glare = 0.25
atmosphere.Haze = 1.8

----------------------------------------------------------------
-- CIEL
----------------------------------------------------------------
local sky = ensure("Sky", "Sky")
sky.SunAngularSize = 12
sky.MoonAngularSize = 11
sky.StarCount = 3000 -- visibles seulement de nuit (baisse ClockTime pour voir)

----------------------------------------------------------------
-- POST-TRAITEMENT
----------------------------------------------------------------
local bloom = ensure("BloomEffect", "Bloom")
bloom.Intensity = 0.45
bloom.Size = 24
bloom.Threshold = 1.05

local sunRays = ensure("SunRaysEffect", "SunRays")
sunRays.Intensity = 0.12
sunRays.Spread = 0.6

local colorCorrection = ensure("ColorCorrectionEffect", "ColorCorrection")
colorCorrection.Brightness = 0
colorCorrection.Contrast = 0.12
colorCorrection.Saturation = 0.18
colorCorrection.TintColor = Color3.fromRGB(255, 248, 240)

local depthOfField = ensure("DepthOfFieldEffect", "DepthOfField")
depthOfField.FarIntensity = 0.08 -- très subtil (0 = aucun flou de profondeur)
depthOfField.FocusDistance = 30
depthOfField.InFocusRadius = 45
depthOfField.NearIntensity = 0

print("[AtmosphereSetup] Ambiance visuelle appliquée.")
