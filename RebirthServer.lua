-- RebirthServer.lua
-- Regular Script — put in ServerScriptService.
-- Handles rebirths: when a player has enough Burgers and clicks the button,
-- their Burgers reset, Rebirths +1, size resets, and from then on they earn
-- more per bite (the burger script reads the Rebirths value).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== SETTINGS =====
local REBIRTH_COST = 100    -- burgers needed for one rebirth
-- ====================

-- RemoteEvent the UI button fires
local rebirthEvent = ReplicatedStorage:FindFirstChild("RebirthEvent")
if not rebirthEvent then
	rebirthEvent = Instance.new("RemoteEvent")
	rebirthEvent.Name = "RebirthEvent"
	rebirthEvent.Parent = ReplicatedStorage
end

-- Make sure every player has a Rebirths counter
local function setupPlayer(player)
	if not player:FindFirstChild("Rebirths") then
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Value = 0
		rebirths.Parent = player
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

-- Handle the rebirth button being clicked
rebirthEvent.OnServerEvent:Connect(function(player)
	local burgers = player:FindFirstChild("Burgers") or player:FindFirstChild("Food")
	local rebirths = player:FindFirstChild("Rebirths")
	if not burgers or not rebirths then return end

	-- server-side check so nobody can cheat the button
	if burgers.Value < REBIRTH_COST then return end

	burgers.Value = 0
	rebirths.Value += 1

	-- reset the body back to normal size
	local character = player.Character
	if character then
		pcall(function()
			character:ScaleTo(1)
		end)
		local belly = character:FindFirstChild("FoodBelly")
		if belly then
			belly.Size = Vector3.new(0.1, 0.1, 0.1)
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
			humanoid.JumpPower = 50
		end
	end

	print("REBIRTH: " .. player.Name .. " is now rebirth " .. rebirths.Value)
end)
