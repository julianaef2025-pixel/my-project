-- GrowOnEat.lua (v2 — works with ANY avatar type, R6 or R15)
-- Put this Script (regular Script) in ServerScriptService.
-- Every food you eat makes your whole character a bit bigger (smoothly).
-- If your avatar is R15, your tummy also bulges out extra.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ===== SETTINGS =====
local GROW_PER_FOOD = 0.05    -- size added per food (0.05 = 5% bigger each bite)
local TUMMY_PER_FOOD = 0.08   -- EXTRA tummy bulge per food (R15 avatars only)
local GROW_TIME = 0.4         -- seconds for the smooth grow animation
local MAX_SCALE = 30          -- biggest you can get (30x normal!)
-- ====================

local function smoothScaleTo(character, targetScale)
	-- Smoothly animate Model:ScaleTo over GROW_TIME seconds
	local startScale = character:GetScale()
	local elapsed = 0
	while elapsed < GROW_TIME do
		elapsed += RunService.Heartbeat:Wait()
		local alpha = math.min(elapsed / GROW_TIME, 1)
		-- ease out so it starts fast and settles gently
		alpha = 1 - (1 - alpha) * (1 - alpha)
		local ok = pcall(function()
			character:ScaleTo(startScale + (targetScale - startScale) * alpha)
		end)
		if not ok then break end
	end
end

local function applySize(player, character, foodCount)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("GrowOnEat: no Humanoid found for " .. player.Name)
		return
	end

	local targetScale = math.min(1 + foodCount * GROW_PER_FOOD, MAX_SCALE)
	print("GrowOnEat: " .. player.Name .. " ate food #" .. foodCount .. " -> scale " .. targetScale)

	-- Extra tummy bulge (only exists on R15 avatars)
	local depth = humanoid:FindFirstChild("BodyDepthScale")
	if depth then
		depth.Value = math.min(1 + foodCount * TUMMY_PER_FOOD, MAX_SCALE)
	end

	task.spawn(smoothScaleTo, character, targetScale)
end

local function watchPlayer(player)
	local function watchFood(food)
		print("GrowOnEat: now watching " .. player.Name .. "'s Food counter")

		food.Changed:Connect(function()
			if player.Character then
				applySize(player, player.Character, food.Value)
			end
		end)

		-- Keep your size when you respawn
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			task.wait(0.5)
			applySize(player, character, food.Value)
		end)
	end

	local food = player:FindFirstChild("Food")
	if food then
		watchFood(food)
	else
		player.ChildAdded:Connect(function(child)
			if child.Name == "Food" and child:IsA("IntValue") then
				watchFood(child)
			end
		end)
	end
end

print("GrowOnEat: script started!")
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
