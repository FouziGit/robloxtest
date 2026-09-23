--!strict
-- CosmeticService: the single writer of ProfileData.Cosmetics. Cosmetics never touch gameplay, but
-- ownership and what is equipped are still decided here: the client only names a catalog entry.
--
-- The server builds no visual. The slots other players must see (Aura, Trail, KillEffect, Title) are
-- published as one replicated string attribute per slot on the character model, named
-- "Cosmetic<Slot>" and holding a CosmeticConfig id (or cleared when the slot is empty); each client
-- reads them and renders them (CosmeticController). A kill effect is an event, not a state: on a kill
-- this service sends the killer's KillEffect as a Vfx packet at the victim. Glyph skins
-- ("Skin:<glyphId>") stay out of the character: GlyphService writes their shade into the cast's packets.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("CosmeticService")

type ProfileData = Types.ProfileData
type CosmeticDef = CosmeticConfig.CosmeticDef
type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	ProfileLoaded: ProfileSignal,
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type VfxPacket = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Params: { [string]: any }?,
}
type VfxApi = { emit: (packet: VfxPacket, reliable: boolean?) -> () }
type KilledSignal = {
	Connect: (self: KilledSignal, fn: (sourceUserId: number, victimModel: Model) -> ()) -> any,
}
type CombatApi = { Killed: KilledSignal }
type Deps = {
	Registry: Registry,
	Vfx: VfxApi,
	Combat: CombatApi,
	DataService: DataApi,
	Notify: NotifyApi,
}
type TroveType = typeof(Trove.new())

-- Attribute name of a broadcast slot: ATTRIBUTE_PREFIX .. slot.
local ATTRIBUTE_PREFIX = "Cosmetic"
local BROADCAST_SLOTS: { string } = { "Aura", "Trail", "KillEffect", "Title" }
local SKIN_PREFIX = "Skin:"

local CosmeticService = {}

-- Fired once per cosmetic actually added to a profile, so the shop can refresh what it shows as owned.
CosmeticService.Granted = Signal.new() -- (player: Player, cosmeticId: string)

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local vfx: VfxApi
local combat: CombatApi

-- Character connections, one Trove per player.
local troves: { [Player]: TroveType } = {}

-- Equipped slot keys: the plain slots of CosmeticConfig.Slots, or "Skin:<glyphId>" for a glyph skin.
local function isSlotKey(slotKey: string): boolean
	if string.sub(slotKey, 1, #SKIN_PREFIX) == SKIN_PREFIX then
		return GlyphConfig.ById[string.sub(slotKey, #SKIN_PREFIX + 1)] ~= nil
	end
	for _, slot in ipairs(CosmeticConfig.Slots) do
		if slot ~= "Skin" and slot == slotKey then
			return true
		end
	end
	return false
end

-- Publishes the broadcast slots on the current character. Called on spawn, on load and on every change;
-- a slot holding an unknown id is published as empty rather than replicated as junk.
local function applyAttributes(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local data = dataService.get(player)
	local equipped = if data ~= nil
		then (data.Cosmetics.Equipped :: any) :: { [string]: string? }
		else {} :: { [string]: string? }
	for _, slot in ipairs(BROADCAST_SLOTS) do
		local cosmeticId = equipped[slot]
		local value: string? = nil
		if cosmeticId ~= nil and CosmeticConfig.ById[cosmeticId] ~= nil then
			value = cosmeticId
		end
		character:SetAttribute(ATTRIBUTE_PREFIX .. slot, value)
	end
end

-- Equips `cosmeticId` in `slotKey`, or empties the slot when `cosmeticId` is "". The section is
-- replicated on every path, including a refusal, so the client never stays pending.
function CosmeticService.equip(player: Player, slotKey: string, cosmeticId: string): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("equip skipped for %s: profile not loaded", player.Name)
		return false
	end
	local equipped = (data.Cosmetics.Equipped :: any) :: { [string]: string? }

	local function reject(reason: string): boolean
		log.warn("equip rejected for %s: %s", player.Name, reason)
		notify.send(player, "cosmetics.notOwned", nil, "Error", "Error")
		dataService.push(player, "Cosmetics")
		return false
	end

	if not isSlotKey(slotKey) then
		return reject("unknown slot " .. slotKey)
	end
	if cosmeticId == "" then
		equipped[slotKey] = nil
		dataService.push(player, "Cosmetics")
		applyAttributes(player)
		notify.send(player, "cosmetics.equipped", { name = "cosmetics.none" }, "Info", "UiClick")
		log.info("%s emptied %s", player.Name, slotKey)
		return true
	end

	local item: CosmeticDef? = CosmeticConfig.ById[cosmeticId]
	if item == nil then
		return reject("unknown cosmetic " .. cosmeticId)
	end
	if table.find(data.Cosmetics.Owned, cosmeticId) == nil then
		return reject(cosmeticId .. " is not owned")
	end
	if CosmeticConfig.slotKey(item) ~= slotKey then
		return reject(cosmeticId .. " does not fit " .. slotKey)
	end

	equipped[slotKey] = cosmeticId
	dataService.push(player, "Cosmetics")
	applyAttributes(player)
	notify.send(player, "cosmetics.equipped", { name = item.NameKey }, "Success", "UiClick")
	log.info("%s equipped %s in %s", player.Name, cosmeticId, slotKey)
	return true
end

-- Grants ownership of `cosmeticId` (battle pass, season reward, shop). Idempotent: false when the
-- player already owns it, the profile is not loaded, or the id is not in the catalog.
function CosmeticService.grant(player: Player, cosmeticId: string): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("grant skipped for %s: profile not loaded", player.Name)
		return false
	end
	if CosmeticConfig.ById[cosmeticId] == nil then
		log.error("unknown cosmetic %s for %s", cosmeticId, player.Name)
		return false
	end
	if table.find(data.Cosmetics.Owned, cosmeticId) ~= nil then
		return false
	end
	table.insert(data.Cosmetics.Owned, cosmeticId)
	dataService.push(player, "Cosmetics")
	CosmeticService.Granted:Fire(player, cosmeticId)
	log.info("%s now owns %s", player.Name, cosmeticId)
	return true
end

-- The shade of the skin `player` wears on `glyphId`, or 0. Read from the profile, never from a client: a
-- skin is something the player owns, and the packets it tints are what every other client draws. The one
-- source for GlyphService (the cast and its effect) and CombatService (the hit it lands).
function CosmeticService.skinShade(player: Player, glyphId: string): number
	local data = dataService.get(player)
	if data == nil then
		return 0
	end
	local equipped = (data.Cosmetics.Equipped :: any) :: { [string]: string? }
	local id = equipped[SKIN_PREFIX .. glyphId]
	local item = if id ~= nil then CosmeticConfig.ById[id] else nil
	if item == nil or item.Slot ~= "Skin" or item.Target ~= glyphId then
		return 0
	end
	return item.Look.Shade or 0
end

-- A kill by a player who wears a KillEffect: the effect is drawn where the victim fell, facing away from
-- the killer. Only a player's character or a training proof: the World Boss is killed by the whole raid,
-- and its last hit already ends on BossDefeated -- one player's cosmetic over it is two endings at once.
-- Training proofs count, because the hub is where a player sees what they bought.
local function onKilled(sourceUserId: number, victimModel: Model)
	if sourceUserId == 0 then
		return
	end
	if
		Players:GetPlayerFromCharacter(victimModel) == nil
		and not CollectionService:HasTag(victimModel, GameConfig.Enemy.Tag)
	then
		return
	end
	local killer = Players:GetPlayerByUserId(sourceUserId)
	local data = if killer ~= nil then dataService.get(killer) else nil
	if data == nil then
		return
	end
	local equipped = (data.Cosmetics.Equipped :: any) :: { [string]: string? }
	local id = equipped.KillEffect
	local item = if id ~= nil then CosmeticConfig.ById[id] else nil
	if item == nil or item.Slot ~= "KillEffect" then
		return
	end
	local root = victimModel:FindFirstChild("HumanoidRootPart") or victimModel.PrimaryPart
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local direction = root.CFrame.LookVector
	local killerCharacter = if killer ~= nil then killer.Character else nil
	local killerRoot = if killerCharacter ~= nil then killerCharacter:FindFirstChild("HumanoidRootPart") else nil
	if killerRoot ~= nil and killerRoot:IsA("BasePart") then
		local away = (root.Position - killerRoot.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude > 1e-3 then
			direction = away.Unit
		end
	end
	vfx.emit({
		Id = "KillEffect",
		Origin = root.Position,
		Direction = direction,
		Caster = sourceUserId,
		Params = { Effect = item.Id },
	}, true)
end

local function onPlayerAdded(player: Player)
	if troves[player] ~= nil then
		return
	end
	local trove = Trove.new()
	troves[player] = trove
	trove:Connect(player.CharacterAdded, function()
		applyAttributes(player)
	end)
	if player.Character ~= nil then
		applyAttributes(player)
	end
end

local function onPlayerRemoving(player: Player)
	local trove = troves[player]
	if trove == nil then
		return
	end
	troves[player] = nil
	trove:Destroy()
end

function CosmeticService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	vfx = deps.Vfx
	combat = deps.Combat
end

function CosmeticService.Start()
	dataService.ProfileLoaded:Connect(function(player: Player)
		applyAttributes(player)
	end)
	combat.Killed:Connect(onKilled)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	registry.on("EquipCosmetic", function(player: Player, slotKey: string, cosmeticId: string)
		CosmeticService.equip(player, slotKey, cosmeticId)
	end)
	log.info("started (%d cosmetics, %d broadcast slots)", #CosmeticConfig.Items, #BROADCAST_SLOTS)
end

return CosmeticService
