-- BurgerPickup.lua (v2 — cooler!)
-- Regular Script, inside the burger, next to BurgerFloat.
-- Walk through it: crunch sound + particle burst + squash-pop animation,
-- +1 Burger point, then the burger respawns with a grow-in animation.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- ===== SETTINGS =====
local RESPAWN_TIME = 5           -- seconds until the burger comes back
local EAT_SOUND_ID = "rbxassetid://0" -- PUT A CRUNCH SOUND ID HERE (find one in Toolbox -> Audio, search "eating crunch")
local EAT_ANIMATION_ID = "rbxassetid://0" -- PUT YOUR ANIMATION ID HERE (the number from your published animation)
-- ====================

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

-- Collect every part of the burger so we can hide/show all of them
local allParts = {}
if target:IsA("Model") then
	for _, p in target:GetDescendants() do
		if p:IsA("BasePart") then table.insert(allParts, p) end
	end
else
	allParts = { part }
end

local originalSizes = {}
for _, p in allParts do
	originalSizes[p] = p.Size
end

local function playEatEffects()
	-- Crunch/ding sound
	local sound = Instance.new("Sound")
	sound.SoundId = EAT_SOUND_ID
	sound.Volume = 1
	sound.Parent = part
	sound:Play()
	Debris:AddItem(sound, 3)

	-- Burst of crumbs/sparkles
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
	burst.Parent = part
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
	track.Looped = false          -- play ONCE, no repeating
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
end

local function hideBurger()
	-- Squash up then shrink to nothing (pop!)
	for _, p in allParts do
		local grow = TweenService:Create(p, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalSizes[p] * 1.3,
		})
		grow:Play()
		grow.Completed:Once(function()
			TweenService:Create(p, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Size = originalSizes[p] * 0.01,
				Transparency = 1,
			}):Play()
		end)
	end
end

local function showBurger()
	-- Grow back in with a bouncy overshoot
	for _, p in allParts do
		p.Transparency = 0
		p.Size = originalSizes[p] * 0.01
		TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = originalSizes[p],
		}):Play()
	end
end

local eaten = false

part.Touched:Connect(function(hit)
	if eaten then return end

	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	eaten = true

	-- +1 Burger point
	local burgers = player:FindFirstChild("Food")
	if not burgers then
		burgers = Instance.new("IntValue")
		burgers.Name = "Food"
		burgers.Value = 0
		burgers.Parent = player
	end
	burgers.Value += 1

	playEatAnimation(character)
	playEatEffects()
	hideBurger()

	if RESPAWN_TIME > 0 then
		task.wait(RESPAWN_TIME)
		showBurger()
		eaten = false
	end
end)
