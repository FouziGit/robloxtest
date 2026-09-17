-- Command Bar — Réorganise les 3 zones autour du spawn (exécuter en mode ÉDITION, pas en Play)
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local GROUND_Y = 0 -- hauteur du sol (haut de la Baseplate par défaut)
local CLEAR_RADIUS = 70 -- rayon gardé libre autour du spawn (les mannequins sont à r=26)
-- ExtraShift décale la zone latéralement (en studs) pour éviter tout
-- chevauchement en coin si les packs sont très larges.
local ZONES = {
	{ Folder = "Map_Simulator", Direction = Vector3.new(0, 0, -1), ExtraShift = Vector3.zero }, -- nord
	{ Folder = "Map_Forest", Direction = Vector3.new(-1, 0, 0), ExtraShift = Vector3.new(0, 0, 90) }, -- ouest, poussé au sud
	{ Folder = "Rocks_Pack", Direction = Vector3.new(1, 0, 0), ExtraShift = Vector3.new(0, 0, 90) }, -- est, poussé au sud
}

ChangeHistoryService:SetWaypoint("AvantReorganisation")

-- Dossier parent commun pour un Explorer propre : workspace.Map
local mapRoot = workspace:FindFirstChild("Map")
if mapRoot == nil then
	mapRoot = Instance.new("Folder")
	mapRoot.Name = "Map"
	mapRoot.Parent = workspace
end

for _, zone in ipairs(ZONES) do
	local folder = workspace:FindFirstChild(zone.Folder) or mapRoot:FindFirstChild(zone.Folder)
	if folder == nil then
		warn(("[Reorg] ❌ %s introuvable — pack non installé ?"):format(zone.Folder))
		continue
	end

	-- Si un ancien run a planté en cours de route, déballe son reliquat d'abord.
	local stale = folder:FindFirstChild("_Carrier")
	if stale ~= nil then
		for _, child in ipairs(stale:GetChildren()) do
			child.Parent = folder
		end
		stale:Destroy()
	end

	-- Emballe le contenu dans un Model temporaire pour le déplacer d'un seul bloc
	local carrier = Instance.new("Model")
	carrier.Name = "_Carrier"
	carrier.Parent = folder
	for _, child in ipairs(folder:GetChildren()) do
		if child ~= carrier then
			child.Parent = carrier
		end
	end

	local cf, size = carrier:GetBoundingBox()
	if size.Magnitude < 0.001 then
		warn(("[Reorg] ⚠️ %s est vide, ignoré."):format(zone.Folder))
	else
		-- Distance = rayon libre + demi-taille du pack dans la direction choisie
		local dir = zone.Direction
		local halfAlong = math.abs(dir.X) * size.X / 2 + math.abs(dir.Z) * size.Z / 2
		local distance = CLEAR_RADIUS + halfAlong
		-- Posé au sol : le bas du bounding box affleure GROUND_Y
		local target = Vector3.new(dir.X * distance, GROUND_Y + size.Y / 2, dir.Z * distance)
			+ (zone.ExtraShift or Vector3.zero)

		carrier.WorldPivot = cf -- pivot = centre du bounding box
		carrier:PivotTo(CFrame.new(target) * cf.Rotation)

		print(
			("[Reorg] ✅ %s → centre (%.0f, %.0f, %.0f) | taille %.0f × %.0f × %.0f"):format(
				zone.Folder,
				target.X,
				target.Y,
				target.Z,
				size.X,
				size.Y,
				size.Z
			)
		)
	end

	-- Déballe, puis range le dossier sous workspace.Map
	for _, child in ipairs(carrier:GetChildren()) do
		child.Parent = folder
	end
	carrier:Destroy()
	folder.Parent = mapRoot
end

ChangeHistoryService:SetWaypoint("ApresReorganisation")
print("[Reorg] Terminé. Ctrl+Z pour tout annuler. Ajuste CLEAR_RADIUS / GROUND_Y en haut et relance si besoin.")
