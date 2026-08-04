-- BurgerFloat.lua
-- Put this Script (regular Script, NOT LocalScript) inside your burger.
-- Works whether the burger is a single Part OR a Model.

local TweenService = game:GetService("TweenService")

-- ===== SETTINGS =====
local FLOAT_HEIGHT = 1.5   -- studs up/down
local FLOAT_TIME = 1.5     -- seconds per up (or down) movement
-- ====================

-- Figure out which part to move (handles Part or Model)
local target = script.Parent
local part

if target:IsA("BasePart") then
	part = target
elseif target:IsA("Model") then
	part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
end

if not part then
	warn("BurgerFloat: couldn't find a Part to float! Put the script inside a Part or a Model with parts.")
	return
end

print("BurgerFloat: running on", part:GetFullName())

part.Anchored = true
part.CanCollide = false

local floatInfo = TweenInfo.new(
	FLOAT_TIME,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1,      -- repeat forever
	true     -- reverse back down
)

local floatTween = TweenService:Create(part, floatInfo, {
	Position = part.Position + Vector3.new(0, FLOAT_HEIGHT, 0)
})
floatTween:Play()
