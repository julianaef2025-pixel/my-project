--[[
	UNLOCK SYSTEM — Script (ServerScriptService)
	A separate script: don't paste into the others.

	Handles Robux early-unlocks for drones via Developer Products.
	Purchases are saved permanently with DataStore.

	SETUP (one time, on create.roblox.com):
	1. Open your game on the Creator Hub -> Monetization -> Developer Products
	2. Create three products:
	   - "Unlock FPV Kamikaze"  price 5 Robux
	   - "Unlock Recon Drone"   price 10 Robux
	   - "Unlock Bomber Drone"  price 15 Robux
	3. Copy each product's ID into PRODUCT_IDS below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

-- ▼▼▼ PASTE YOUR DEVELOPER PRODUCT IDS HERE ▼▼▼
local PRODUCT_IDS = {
	Kamikaze = 0, -- e.g. 1234567890
	Recon = 0,
	Bomber = 0,
}
-- ▲▲▲ PASTE YOUR DEVELOPER PRODUCT IDS HERE ▲▲▲

for kind, id in PRODUCT_IDS do
	if id == 0 then
		warn("[Unlocks] Product ID for '" .. kind .. "' not set — create the Developer Product and paste its ID")
	end
	-- publish the ids so the menu client can prompt purchases
	ReplicatedStorage:SetAttribute("Product" .. kind, id)
end

local unlockStore
pcall(function()
	unlockStore = DataStoreService:GetDataStore("DroneWarUnlocks_v1")
end)

-- product id -> drone kind lookup
local productToKind = {}
for kind, id in PRODUCT_IDS do
	if id ~= 0 then
		productToKind[id] = kind
	end
end

local function applyUnlocks(player, unlocks)
	for kind in PRODUCT_IDS do
		player:SetAttribute("Owns" .. kind, unlocks[kind] == true)
	end
end

local function loadUnlocks(player)
	local unlocks = {}
	if unlockStore then
		local ok, saved = pcall(function()
			return unlockStore:GetAsync("player_" .. player.UserId)
		end)
		if ok and typeof(saved) == "table" then
			unlocks = saved
		end
	end
	applyUnlocks(player, unlocks)
end

local function saveUnlock(userId, kind)
	if not unlockStore then
		return false
	end
	local ok = pcall(function()
		unlockStore:UpdateAsync("player_" .. userId, function(old)
			old = typeof(old) == "table" and old or {}
			old[kind] = true
			return old
		end)
	end)
	return ok
end

Players.PlayerAdded:Connect(loadUnlocks)
for _, player in Players:GetPlayers() do
	task.spawn(loadUnlocks, player)
end

-- Robux purchase handling
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local kind = productToKind[receiptInfo.ProductId]
	if not kind then
		-- not one of ours; don't eat someone else's product
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- save FIRST so a crash can't take their Robux without the unlock
	local saved = saveUnlock(receiptInfo.PlayerId, kind)
	if not saved then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player then
		player:SetAttribute("Owns" .. kind, true)
		print("[Unlocks] " .. player.Name .. " unlocked " .. kind .. " with Robux")
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
