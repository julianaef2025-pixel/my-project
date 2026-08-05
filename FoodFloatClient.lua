-- FoodFloatClient.lua
-- LOCALSCRIPT — put it in StarterPlayerScripts
-- (Explorer -> StarterPlayer -> StarterPlayerScripts -> right-click -> Insert Object -> LocalScript)
--
-- Animates EVERY tagged food item on YOUR computer at full framerate.
-- This is what makes the floating buttery smooth instead of laggy:
-- the server doesn't move burgers at all anymore, your own game client does.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- ===== SETTINGS =====
local FLOAT_HEIGHT = 1.2   -- studs it floats up
local FLOAT_SPEED = 1.2    -- bob speed
local SPIN_SPEED = 60      -- degrees per second
-- ====================

local foods = {}  -- [instance] = startPivot

local function addFood(item)
	if foods[item] then return end
	-- random start offset so a row of burgers doesn't bob in perfect sync
	foods[item] = {
		pivot = item:IsA("Model") and item:GetPivot() or item.CFrame,
		offset = math.random() * math.pi * 2,
	}
end

local function removeFood(item)
	foods[item] = nil
end

-- Pick up foods that already exist + any added later
for _, item in CollectionService:GetTagged("FloatingFood") do
	addFood(item)
end
CollectionService:GetInstanceAddedSignal("FloatingFood"):Connect(addFood)
CollectionService:GetInstanceRemovedSignal("FloatingFood"):Connect(removeFood)

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	for item, data in foods do
		if not item.Parent then
			foods[item] = nil
			continue
		end
		local wave = t * FLOAT_SPEED * math.pi + data.offset
		local bob = (math.sin(wave) + 1) * 0.5 * FLOAT_HEIGHT
		local spin = math.rad(SPIN_SPEED) * t + data.offset
		local newPivot = data.pivot * CFrame.new(0, bob, 0) * CFrame.Angles(0, spin, 0)
		if item:IsA("Model") then
			item:PivotTo(newPivot)
		else
			item.CFrame = newPivot
		end
	end
end)
