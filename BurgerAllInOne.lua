-- BurgerAllInOne.lua
-- ONE script that does EVERYTHING for a food item.
-- Put this Script (regular Script) inside the burger (Part or Model),
-- and DELETE any other scripts inside the burger (old float/pickup scripts).
--
-- Does: smooth float + spin, sparkles + glow, walk-through pickup,
-- crunch sound, eat animation, +1 Food, character grows, BALL BELLY grows,
-- burger pops away and respawns. No collision glitches.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- ===== SETTINGS =====
local EAT_SOUND_ID = "rbxassetid://0"     -- your crunch sound id
local EAT_ANIMATION_ID = "rbxassetid://0" -- your eat animation id
local RESPAWN_TIME = 5      -- seconds until the burger comes back
local GROW_PER_FOOD = 0.04  -- whole body: 4% bigger per food
local BELLY_PER_FOOD = 0.35 -- belly ball: studs bigger per food
local MAX_SCALE = 30        -- body size cap
-- ====================

local target = script.Parent
local isModel = target:IsA("Model")

-- Collect all parts + make them safe (no physics, no collision = no glitches)
local allParts = {}
if isModel then
	for _, p in target:GetDescendants() do
		if p:IsA("BasePart") then table.insert(allParts, p) end
	end
else
	allParts = { target }
end

if #allParts == 0 then
	warn("Burger: no parts found!")
	return
end

for _, p in allParts do
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
end

local mainPart = isModel and (target.PrimaryPart or allParts[1]) or target

-- Tag this food so every player's own computer animates it smoothly (60fps, no lag)
local CollectionService = game:GetService("CollectionService")
CollectionService:AddTag(target, "FloatingFood")

-- ===== SPARKLES + GLOW =====
local sparkle = Instance.new("ParticleEmitter")
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
sparkle.SpreadAngle = Vector2.new(180, 180)
sparkle.Parent = mainPart

local light = Instance.new("PointLight")
light.Color = Color3.fromRGB(255, 180, 80)
light.Brightness = 1.5
light.Range = 8
light.Parent = mainPart

-- (Floating is now animated on each player's computer by the FoodFloatClient
--  LocalScript in StarterPlayerScripts — that's what makes it perfectly smooth.)
local eaten = false

-- ===== BALL BELLY =====
local function growBelly(character, foodCount)
	local torso = character:FindFirstChild("UpperTorso")   -- R15
		or character:FindFirstChild("Torso")               -- R6
	if not torso then return end

	local belly = character:FindFirstChild("Belly")
	if not belly then
		belly = Instance.new("Part")
		belly.Name = "Belly"
		belly.Shape = Enum.PartType.Ball
		belly.Material = Enum.Material.SmoothPlastic
		belly.Color = torso.Color
		belly.CanCollide = false
		belly.CanQuery = false
		belly.Massless = true
		belly.Size = Vector3.new(1, 1, 1)
		-- stick it to the front-bottom of the torso
		belly.CFrame = torso.CFrame * CFrame.new(0, -torso.Size.Y * 0.25, -torso.Size.Z * 0.35)
		belly.Parent = character

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = belly
		weld.Parent = belly
	end

	-- Belly gets rounder with every food (smooth tween)
	local size = 1 + foodCount * BELLY_PER_FOOD
	TweenService:Create(belly, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, size),
	}):Play()
end

-- ===== WHOLE BODY GROWTH =====
local function growCharacter(character, foodCount)
	local targetScale = math.min(1 + foodCount * GROW_PER_FOOD, MAX_SCALE)
	task.spawn(function()
		local startScale = character:GetScale()
		local elapsed = 0
		while elapsed < 0.4 do
			elapsed += RunService.Heartbeat:Wait()
			local alpha = math.min(elapsed / 0.4, 1)
			alpha = 1 - (1 - alpha) * (1 - alpha)
			local ok = pcall(function()
				character:ScaleTo(startScale + (targetScale - startScale) * alpha)
			end)
			if not ok then break end
		end
	end)
end

-- ===== EAT EFFECTS =====
local function playEatEffects()
	local sound = Instance.new("Sound")
	sound.SoundId = EAT_SOUND_ID
	sound.Volume = 1
	sound.Parent = mainPart
	sound:Play()
	Debris:AddItem(sound, 3)

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(
		Color3.fromRGB(255, 170, 40),
		Color3.fromRGB(180, 90, 30)
	)
	burst.LightEmission = 0.8
	burst.Lifetime = NumberRange.new(0.4, 0.9)
	burst.Speed = NumberRange.new(6, 12)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Rate = 0
	burst.Parent = mainPart
	burst:Emit(40)
	Debris:AddItem(burst, 2)
end

local function playEatAnimation(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = EAT_ANIMATION_ID
	local track = animator:LoadAnimation(anim)
	track.Looped = false
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
end

-- ===== HIDE / SHOW =====
local function setHidden(hidden)
	for _, p in allParts do
		p.Transparency = hidden and 1 or 0
	end
	sparkle.Enabled = not hidden
	light.Enabled = not hidden
end

-- ===== PICKUP =====
local function onTouched(hit)
	if eaten then return end

	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	eaten = true

	local food = player:FindFirstChild("Food")
	if not food then
		food = Instance.new("IntValue")
		food.Name = "Food"
		food.Value = 0
		food.Parent = player
	end
	food.Value += 1

	growCharacter(character, food.Value)
	growBelly(character, food.Value)
	playEatAnimation(character)
	playEatEffects()
	setHidden(true)

	if RESPAWN_TIME > 0 then
		task.wait(RESPAWN_TIME)
		setHidden(false)
		eaten = false
	end
end

for _, p in allParts do
	p.Touched:Connect(onTouched)
end
