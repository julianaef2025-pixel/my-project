-- BurgerFinal.lua — THE WORKING VERSION (confirmed in-game!)
-- One regular Script inside each food item (Part or Model).
-- Float + spin + tilt, sparkles + glow, walk-through pickup, crunch sound,
-- eat animation (cached), +1 Burgers, body grows, forward-bulging ball belly,
-- smooth heavy mode, respawn, preload. No lag.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- ===== BURGER SETTINGS =====
local EAT_SOUND_ID = "rbxassetid://86520922837471"
local EAT_ANIMATION_ID = "rbxassetid://112891304467100"
local RESPAWN_TIME = 5
local FLOAT_HEIGHT = 1
local FLOAT_SPEED = 0.8
local SPIN_SPEED = 60
local TILT = 4
-- ===== GROW SETTINGS =====
local BELLY_PER_FOOD = 0.15   -- how fast the belly fills per burger
local BELLY_START = 1         -- belly size after first bite
local MAX_BELLY = 2.2         -- belly max (compared to body) — can never cover you
local HEIGHT_PER_FOOD = 0.03  -- body grows 3% per burger, together with the belly
local REBIRTH_BOOST = 0.5     -- each rebirth = +50% burgers per bite AND +50% faster growing
local HEAVY_MODE = true       -- slowly get heavier (smooth, no stutter)
-- NO SIZE LIMIT — eat forever, grow forever!
-- =========================

local target = script.Parent

-- all parts: anchored, walk-through (no bumping)
local allParts = {}
if target:IsA("Model") then
	for _, p in target:GetDescendants() do
		if p:IsA("BasePart") then table.insert(allParts, p) end
	end
else
	allParts = { target }
end
if #allParts == 0 then warn("Burger: no parts!") return end

for _, p in allParts do
	p.Anchored = true
	p.CanCollide = false
end

local mainPart = (target:IsA("Model") and (target.PrimaryPart or allParts[1])) or target

local originalSizes = {}
for _, p in allParts do
	originalSizes[p] = p.Size
end

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

-- ===== FLOAT + SPIN + TILT (whole burger moves together) =====
local startPivot = target:IsA("Model") and target:GetPivot() or target.CFrame
local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	local bob = (math.sin(t * FLOAT_SPEED * math.pi) + 1) * 0.5 * FLOAT_HEIGHT
	local spin = math.rad(SPIN_SPEED) * t
	local tilt = math.rad(math.sin(t * FLOAT_SPEED * math.pi * 0.5) * TILT)
	local pos = startPivot * CFrame.new(0, bob, 0) * CFrame.Angles(tilt, spin, tilt)
	if target:IsA("Model") then
		target:PivotTo(pos)
	else
		target.CFrame = pos
	end
end)

-- ===== BELLY (bulges FORWARD like a real gut, capped, moves with you) =====
local function getBelly(character, torso)
	local belly = character:FindFirstChild("FoodBelly")
	local weld
	if not belly then
		belly = Instance.new("Part")
		belly.Name = "FoodBelly"
		belly.Shape = Enum.PartType.Ball
		belly.Material = Enum.Material.SmoothPlastic
		belly.Color = torso.Color
		belly.CanCollide = false
		belly.CanQuery = false
		belly.Massless = true
		belly.Size = Vector3.new(0.1, 0.1, 0.1)

		weld = Instance.new("Weld")
		weld.Name = "BellyWeld"
		weld.Part0 = torso
		weld.Part1 = belly
		weld.C0 = CFrame.new(0, -torso.Size.Y * 0.25, 0)
		weld.Parent = belly

		belly.Parent = character
	else
		weld = belly:FindFirstChild("BellyWeld")
	end
	return belly, weld
end

-- ===== GROWING (one cheap step per bite = NO LAG) =====
local function growPlayer(player, character, foodCount)
	if foodCount <= 0 then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- rebirths make you grow faster (and there is NO size cap)
	local rebirths = player:FindFirstChild("Rebirths")
	local boost = 1 + (rebirths and rebirths.Value or 0) * REBIRTH_BOOST
	local targetScale = 1 + foodCount * HEIGHT_PER_FOOD * boost
	pcall(function()
		character:ScaleTo(targetScale)
	end)

	-- belly fills, capped, pushed forward out of your tummy
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso then
		local fill = math.min(BELLY_START + foodCount * BELLY_PER_FOOD, MAX_BELLY)
		local size = fill * targetScale
		local belly, weld = getBelly(character, torso)
		local forward = torso.Size.Z * 0.2 + size * 0.3

		TweenService:Create(belly,
			TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = Vector3.new(size, size * 0.85, size) }
		):Play()
		if weld then
			TweenService:Create(weld,
				TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ C0 = CFrame.new(0, -torso.Size.Y * 0.25, -forward) }
			):Play()
		end
	end

	-- heavier, but SMOOTHLY (tweened, so no sudden stutter feeling)
	if HEAVY_MODE then
		TweenService:Create(humanoid, TweenInfo.new(0.6), {
			WalkSpeed = math.max(16 - foodCount * 0.2, 8),
			JumpPower = math.max(50 - foodCount * 0.6, 25),
		}):Play()
	end
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
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 170, 40), Color3.fromRGB(180, 90, 30))
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

-- ===== ANIMATION (cached = loads ONCE, no stutter on later bites) =====
local cachedTracks = {}

local function playEatAnimation(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	local track = cachedTracks[animator]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = EAT_ANIMATION_ID
		track = animator:LoadAnimation(anim)
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Action
		cachedTracks[animator] = track
	end
	track:Play()
end

-- ===== HIDE / SHOW =====
local function hideBurger()
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
	sparkle.Enabled = false
	light.Enabled = false
end

local function showBurger()
	for _, p in allParts do
		p.Transparency = 0
		TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = originalSizes[p],
		}):Play()
	end
	sparkle.Enabled = true
	light.Enabled = true
end

-- ===== PICKUP (any part of the burger works) =====
local eaten = false

local function onTouched(hit)
	if eaten then return end

	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	eaten = true

	local burgers = player:FindFirstChild("Burgers")
	if not burgers then
		burgers = Instance.new("IntValue")
		burgers.Name = "Burgers"
		burgers.Value = 0
		burgers.Parent = player
	end
	-- rebirths + pets multiply your burgers per bite
	local rebirths = player:FindFirstChild("Rebirths")
	local petBoost = player:FindFirstChild("PetBoost")
	local multiplier = (1 + (rebirths and rebirths.Value or 0) * 0.5) * (1 + (petBoost and petBoost.Value or 0))
	local amount = math.ceil(multiplier)
	burgers.Value += amount

	-- TotalEaten controls your SIZE and never goes down (spending burgers won't shrink you)
	local totalEaten = player:FindFirstChild("TotalEaten")
	if not totalEaten then
		totalEaten = Instance.new("IntValue")
		totalEaten.Name = "TotalEaten"
		totalEaten.Parent = player
	end
	totalEaten.Value += amount

	growPlayer(player, character, totalEaten.Value)
	playEatAnimation(character)
	playEatEffects()
	hideBurger()

	if RESPAWN_TIME > 0 then
		task.wait(RESPAWN_TIME)
		showBurger()
		eaten = false
	end
end

for _, p in allParts do
	p.Touched:Connect(onTouched)
end

-- ===== PRELOAD (no first-bite freeze) =====
task.spawn(function()
	local s = Instance.new("Sound")
	s.SoundId = EAT_SOUND_ID
	local a = Instance.new("Animation")
	a.AnimationId = EAT_ANIMATION_ID
	game:GetService("ContentProvider"):PreloadAsync({ s, a })
end)
