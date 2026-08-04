-- BurgerFloat.lua
-- Put this Script INSIDE your burger Part (or the PrimaryPart of a burger Model).
-- It makes the burger float smoothly up and down forever, and adds a slow spin.

local TweenService = game:GetService("TweenService")

local burger = script.Parent

-- ===== SETTINGS (change these to taste) =====
local FLOAT_HEIGHT = 1.5   -- how many studs it moves up and down
local FLOAT_TIME = 1.5     -- seconds for one up (or down) movement
local SPIN = true          -- set to false if you don't want it to rotate
local SPIN_TIME = 4        -- seconds for one full rotation
-- ============================================

-- The burger must not fall or get pushed around
burger.Anchored = true
burger.CanCollide = false

local startCFrame = burger.CFrame

-- Smooth up/down float (Sine easing = very smooth, reverses and repeats forever)
local floatInfo = TweenInfo.new(
	FLOAT_TIME,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1,      -- repeat forever
	true     -- reverse back down after going up
)

local floatTween = TweenService:Create(burger, floatInfo, {
	Position = burger.Position + Vector3.new(0, FLOAT_HEIGHT, 0)
})
floatTween:Play()

-- Optional slow spin
if SPIN then
	task.spawn(function()
		local RunService = game:GetService("RunService")
		while burger.Parent do
			local dt = RunService.Heartbeat:Wait()
			-- rotate around Y axis, keep the floating position from the tween
			burger.CFrame = CFrame.new(burger.Position)
				* (burger.CFrame - burger.Position)
				* CFrame.Angles(0, math.rad(360 / SPIN_TIME) * dt, 0)
		end
	end)
end
