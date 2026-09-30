--!strict
-- Idempotent developer-product receipt processing. Pure module: every side effect is injected, so
-- the decision logic is testable under Lune. Semantics follow MarketplaceService.ProcessReceipt:
--   "PurchaseGranted"  → Roblox charges the player and never sends the receipt again
--   "NotProcessedYet"  → Roblox retries later (player leaves / rejoins, profile not ready, save failed)

export type Receipt = { PlayerId: number, PurchaseId: string, ProductId: number }
export type ProductDef = { Kind: string, Amount: number?, Minutes: number?, Rarity: string? }
export type Decision = "PurchaseGranted" | "NotProcessedYet"

export type Deps = {
	findProduct: (productId: number) -> (string?, ProductDef?),
	getProfile: (userId: number) -> any?, -- live profile data or nil when not loaded
	isRecorded: (data: any, purchaseId: string) -> boolean,
	record: (data: any, purchaseId: string) -> (),
	grant: (data: any, productKey: string, product: ProductDef, receipt: Receipt) -> boolean,
	save: (userId: number) -> boolean, -- persist now; false when the write failed
	log: (message: string) -> (),
}

local ReceiptProcessor = {}

function ReceiptProcessor.process(receipt: Receipt, deps: Deps): (Decision, string)
	local productKey, product = deps.findProduct(receipt.ProductId)
	if productKey == nil or product == nil then
		deps.log("unknown product " .. tostring(receipt.ProductId) .. " for purchase " .. receipt.PurchaseId)
		return "NotProcessedYet", "unknown product"
	end

	local data = deps.getProfile(receipt.PlayerId)
	if data == nil then
		return "NotProcessedYet", "profile not loaded"
	end

	if deps.isRecorded(data, receipt.PurchaseId) then
		return "PurchaseGranted", "already granted"
	end

	local granted = deps.grant(data, productKey, product, receipt)
	if not granted then
		deps.log("grant failed for " .. productKey .. " (" .. receipt.PurchaseId .. ")")
		return "NotProcessedYet", "grant failed"
	end

	-- Record before saving so a retry after a failed save is idempotent (in-memory record wins).
	deps.record(data, receipt.PurchaseId)

	if not deps.save(receipt.PlayerId) then
		deps.log("save failed after granting " .. productKey .. " (" .. receipt.PurchaseId .. "), will retry")
		return "NotProcessedYet", "save failed"
	end

	return "PurchaseGranted", "granted"
end

return ReceiptProcessor
