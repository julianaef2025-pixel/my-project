-- GameData.lua
-- Regular Script — put in ServerScriptService.
-- SAVES EVERYTHING: Burgers, TotalEaten (your size), Rebirths, pet collection,
-- and which pet you had equipped. Loads it all back when you rejoin.
--
-- IMPORTANT: saving only works if you turn on:
-- File -> Game Settings (or Experience Settings) -> Security ->
-- "Enable Studio Access to API Services" -> ON. Game must be published.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")

local store = DataStoreService:GetDataStore("BurgerGameSave_v1")

-- server-to-server signal so PetEgg can re-equip your saved pet on join
local equipBind = ServerStorage:FindFirstChild("EquipPetBind")
if not equipBind then
	equipBind = Instance.new("BindableEvent")
	equipBind.Name = "EquipPetBind"
	equipBind.Parent = ServerStorage
end

local function makeInt(parent, name, value)
	local v = parent:FindFirstChild(name)
	if not v then
		v = Instance.new("IntValue")
		v.Name = name
		v.Parent = parent
	end
	v.Value = value or 0
	return v
end

-- ===== LOAD =====
local function loadPlayer(player)
	local key = "p_" .. player.UserId
	local ok, data = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn("SAVE: couldn't load data for " .. player.Name)
	end
	data = (ok and data) or {}

	makeInt(player, "Burgers", data.Burgers)
	makeInt(player, "TotalEaten", data.TotalEaten)
	makeInt(player, "Rebirths", data.Rebirths)

	-- pet collection folder (PetEgg fills in the details)
	local petsFolder = player:FindFirstChild("Pets")
	if not petsFolder then
		petsFolder = Instance.new("Folder")
		petsFolder.Name = "Pets"
		petsFolder.Parent = player
	end
	for _, petName in (data.Pets or {}) do
		if not petsFolder:FindFirstChild(petName) then
			local tagValue = Instance.new("StringValue")
			tagValue.Name = petName
			tagValue.Parent = petsFolder
		end
	end

	-- re-equip their saved pet once their character is ready
	if data.Equipped and data.Equipped ~= "" then
		task.delay(1, function()
			if player.Parent then
				equipBind:Fire(player, data.Equipped)
			end
		end)
	end

	print("SAVE: loaded " .. player.Name .. " (burgers " .. (data.Burgers or 0)
		.. ", eaten " .. (data.TotalEaten or 0) .. ", rebirths " .. (data.Rebirths or 0)
		.. ", pets " .. #(data.Pets or {}) .. ")")
end

-- ===== SAVE =====
local function collectData(player)
	local pets = {}
	local petsFolder = player:FindFirstChild("Pets")
	if petsFolder then
		for _, child in petsFolder:GetChildren() do
			table.insert(pets, child.Name)
		end
	end
	local burgers = player:FindFirstChild("Burgers")
	local totalEaten = player:FindFirstChild("TotalEaten")
	local rebirths = player:FindFirstChild("Rebirths")
	return {
		Burgers = burgers and burgers.Value or 0,
		TotalEaten = totalEaten and totalEaten.Value or 0,
		Rebirths = rebirths and rebirths.Value or 0,
		Pets = pets,
		Equipped = player:GetAttribute("EquippedPet") or "",
	}
end

local function savePlayer(player)
	local key = "p_" .. player.UserId
	local data = collectData(player)
	local ok, err = pcall(function()
		store:SetAsync(key, data)
	end)
	if ok then
		print("SAVE: saved " .. player.Name)
	else
		warn("SAVE: failed for " .. player.Name .. ": " .. tostring(err))
	end
end

Players.PlayerAdded:Connect(loadPlayer)
for _, player in Players:GetPlayers() do
	loadPlayer(player)
end

Players.PlayerRemoving:Connect(savePlayer)

-- save everyone if the server shuts down
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		savePlayer(player)
	end
end)

-- autosave every 2 minutes just in case
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in Players:GetPlayers() do
			savePlayer(player)
		end
	end
end)
