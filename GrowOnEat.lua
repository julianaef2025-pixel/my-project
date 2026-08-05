-- GrowOnEat.lua
-- Put this Script (regular Script) in ServerScriptService.
-- Every food you eat makes your character a tiny bit bigger,
-- and your tummy (body depth) grows out a little extra.
-- Works for ALL food (burgers, fries, anything that adds to the "Food" value).
--
-- IMPORTANT: your game must use R15 avatars for body scaling to work.
-- Home tab -> Game Settings -> Avatar -> Avatar Type -> set to R15.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- ===== SETTINGS =====
local GROW_PER_FOOD = 0.04    -- overall size added per food (0.04 = 4% bigger each bite)
local TUMMY_PER_FOOD = 0.08   -- EXTRA tummy (belly depth) per food
local GROW_TIME = 0.4         -- seconds for the smooth grow animation
local MAX_SCALE = 30          -- biggest you can get (30 = 30x normal, basically map-sized!)
-- ====================

local function applySize(character, foodCount)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Overall body size (everything grows together)
	local bodyScale = math.min(1 + foodCount * GROW_PER_FOOD, MAX_SCALE)
	-- Tummy sticks out extra (depth = front-to-back)
	local tummyScale = math.min(bodyScale + foodCount * TUMMY_PER_FOOD, MAX_SCALE)

	local goals = {
		BodyHeightScale = bodyScale,
		BodyWidthScale = bodyScale,
		HeadScale = bodyScale,
		BodyDepthScale = tummyScale,
	}

	for name, value in goals do
		local scaleValue = humanoid:FindFirstChild(name)
		if scaleValue then
			TweenService:Create(scaleValue, TweenInfo.new(GROW_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Value = value,
			}):Play()
		end
	end
end

local function watchPlayer(player)
	local function watchFood(food)
		-- Grow every time they eat
		food.Changed:Connect(function()
			if player.Character then
				applySize(player.Character, food.Value)
			end
		end)

		-- If they die/respawn, put their size back
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			task.wait(0.5) -- let the character finish loading
			applySize(character, food.Value)
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

-- Watch everyone, including players already in the game
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
