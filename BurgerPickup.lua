-- BurgerPickup.lua
-- Put this Script (regular Script) inside the burger, NEXT TO the BurgerFloat script.
-- When a player walks through the burger: +1 Burger point, burger disappears,
-- then it comes back after RESPAWN_TIME seconds.

local Players = game:GetService("Players")

-- ===== SETTINGS =====
local RESPAWN_TIME = 5   -- seconds until the burger comes back (set to 0 for never coming back)
-- ====================

-- Find the part (works for a Part or a Model)
local target = script.Parent
local part
if target:IsA("BasePart") then
	part = target
elseif target:IsA("Model") then
	part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
end

if not part then
	warn("BurgerPickup: couldn't find a Part!")
	return
end

local eaten = false

part.Touched:Connect(function(hit)
	if eaten then return end

	-- Was it a player that touched us?
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	eaten = true

	-- Make sure the player has a "Burgers" counter, then add 1
	local burgers = player:FindFirstChild("Burgers")
	if not burgers then
		burgers = Instance.new("IntValue")
		burgers.Name = "Burgers"
		burgers.Value = 0
		burgers.Parent = player
	end
	burgers.Value += 1

	-- Hide the burger
	if target:IsA("Model") then
		for _, p in target:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = 1
			end
		end
	else
		part.Transparency = 1
	end

	-- Bring it back after a while
	if RESPAWN_TIME > 0 then
		task.wait(RESPAWN_TIME)
		if target:IsA("Model") then
			for _, p in target:GetDescendants() do
				if p:IsA("BasePart") then
					p.Transparency = 0
				end
			end
		else
			part.Transparency = 0
		end
		eaten = false
	end
end)
