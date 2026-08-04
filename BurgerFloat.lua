-- BurgerFloat.lua (v2 — cooler!)
-- Regular Script, inside the burger (Part or Model).
-- Smooth up/down float + slow spin + gentle tilt + golden sparkles + glow.

local RunService = game:GetService("RunService")

-- ===== SETTINGS =====
local FLOAT_HEIGHT = 1.2   -- studs up/down
local FLOAT_SPEED = 1.2    -- higher = bobs faster
local SPIN_SPEED = 60      -- degrees per second
local TILT = 4             -- degrees of gentle rocking tilt (0 = none)
local SPARKLES = true      -- golden sparkle particles
local GLOW = true          -- warm light under the burger
-- ====================

local target = script.Parent
local part
if target:IsA("BasePart") then
	part = target
elseif target:IsA("Model") then
	part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
end

if not part then
	warn("BurgerFloat: couldn't find a Part to float!")
	return
end

part.Anchored = true
part.CanCollide = false

-- Golden sparkles
if SPARKLES then
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "BurgerSparkles"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60))
	sparkle.LightEmission = 1
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = part
end

-- Warm glow
if GLOW then
	local light = Instance.new("PointLight")
	light.Name = "BurgerGlow"
	light.Color = Color3.fromRGB(255, 180, 80)
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = part
end

-- One smooth animation loop drives float + spin + tilt together
local startCFrame = part.CFrame
local t = 0

RunService.Heartbeat:Connect(function(dt)
	t += dt

	local bob = math.sin(t * FLOAT_SPEED * math.pi) * FLOAT_HEIGHT
	local spin = math.rad(SPIN_SPEED) * t
	local tilt = math.rad(math.sin(t * FLOAT_SPEED * math.pi * 0.5) * TILT)

	part.CFrame = startCFrame
		* CFrame.new(0, bob, 0)
		* CFrame.Angles(tilt, spin, tilt)
end)
