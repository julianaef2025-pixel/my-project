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
	RPG = 0,
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
	print("[Unlocks] Receipt received: product " .. tostring(receiptInfo.ProductId)
		.. " from player " .. tostring(receiptInfo.PlayerId))

	local kind = productToKind[receiptInfo.ProductId]
	if not kind then
		warn("[Unlocks] Product " .. tostring(receiptInfo.ProductId)
			.. " doesn't match any PRODUCT_IDS entry — check the IDs at the top of this script!")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	print("[Unlocks] Product matches drone kind: " .. kind)

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)

	if not unlockStore then
		-- no DataStore access (Studio without API services): grant for this
		-- session so testing works, but it won't survive a rejoin
		warn("[Unlocks] DataStore unavailable — granting " .. kind .. " for this session only. "
			.. "Turn ON Game Settings > Security > 'Enable Studio Access to API Services' for real saving!")
		if player then
			player:SetAttribute("Owns" .. kind, true)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- save FIRST so a crash can't take their Robux without the unlock
	local saved = saveUnlock(receiptInfo.PlayerId, kind)
	if not saved then
		warn("[Unlocks] Saving the unlock FAILED — will retry later (purchase not granted yet)")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	print("[Unlocks] Unlock saved to DataStore")

	if player then
		player:SetAttribute("Owns" .. kind, true)
		print("[Unlocks] " .. player.Name .. " unlocked " .. kind .. " with Robux ✔")
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
