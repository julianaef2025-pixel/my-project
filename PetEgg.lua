-- PetEgg.lua
-- Regular Script — put INSIDE your egg (a Part, or a Model from Toolbox).
-- Walk up, press E, pay burgers, hatch a random pet that follows you!

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- ===== SETTINGS =====
local HATCH_COST = 50 -- burgers per hatch

-- The pets! chance = how rare (higher number = more common)
local PETS = {
	{ name = "Bubble",  color = Color3.fromRGB(120, 200, 255), size = 1.2, rarity = "Common",    chance = 50 },
	{ name = "Minty",   color = Color3.fromRGB(120, 255, 160), size = 1.2, rarity = "Common",    chance = 30 },
	{ name = "Peachy",  color = Color3.fromRGB(255, 170, 120), size = 1.4, rarity = "Rare",      chance = 12 },
	{ name = "Grape",   color = Color3.fromRGB(190, 120, 255), size = 1.4, rarity = "Epic",      chance = 6 },
	{ name = "Sunny",   color = Color3.fromRGB(255, 220, 60),  size = 1.7, rarity = "LEGENDARY", chance = 2 },
}
-- ====================

local egg = script.Parent
local eggPart = egg:IsA("BasePart") and egg or (egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart"))
if not eggPart then warn("PetEgg: no part found!") return end

-- anchor the egg so it can't be pushed around
for _, p in (egg:IsA("Model") and egg:GetDescendants() or { egg }) do
	if p:IsA("BasePart") then
		p.Anchored = true
	end
end

-- the "press E" prompt
local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Hatch Pet"
prompt.ObjectText = HATCH_COST .. " 🍔"
prompt.HoldDuration = 0.5
prompt.RequiresLineOfSight = false
prompt.Parent = eggPart

-- ===== PICK A RANDOM PET (weighted by rarity) =====
local totalChance = 0
for _, pet in PETS do
	totalChance += pet.chance
end

local function rollPet()
	local roll = math.random() * totalChance
	local sum = 0
	for _, pet in PETS do
		sum += pet.chance
		if roll <= sum then
			return pet
		end
	end
	return PETS[1]
end

-- ===== BUILD A PET FROM PARTS (no model needed!) =====
local function buildPet(petInfo, ownerName)
	local pet = Instance.new("Model")
	pet.Name = ownerName .. "_Pet"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Material = Enum.Material.SmoothPlastic
	body.Color = petInfo.color
	body.Size = Vector3.new(petInfo.size, petInfo.size, petInfo.size)
	body.CanCollide = false
	body.Anchored = true
	body.Parent = pet

	-- two eyes
	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.SmoothPlastic
		eye.Color = Color3.fromRGB(20, 20, 20)
		eye.Size = Vector3.new(0.22, 0.22, 0.22) * petInfo.size
		eye.CanCollide = false
		eye.Anchored = false
		eye.Massless = true
		eye.CFrame = body.CFrame * CFrame.new(side * petInfo.size * 0.2, petInfo.size * 0.12, -petInfo.size * 0.42)
		eye.Parent = pet
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye
	end

	-- name tag with rarity
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 120, 0, 34)
	gui.StudsOffset = Vector3.new(0, petInfo.size * 0.8 + 0.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = body

	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, 0, 1, 0)
	tag.BackgroundTransparency = 1
	tag.TextScaled = true
	tag.Font = Enum.Font.FredokaOne
	tag.Text = petInfo.name .. "\n" .. petInfo.rarity
	tag.TextColor3 = petInfo.rarity == "LEGENDARY" and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(255, 255, 255)
	tag.TextStrokeTransparency = 0.4
	tag.Parent = gui

	-- legendary pets sparkle!
	if petInfo.rarity == "LEGENDARY" then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 220, 60))
		sparkle.LightEmission = 1
		sparkle.Rate = 15
		sparkle.Lifetime = NumberRange.new(0.5, 1)
		sparkle.Speed = NumberRange.new(1, 2)
		sparkle.Size = NumberSequence.new(0.3)
		sparkle.Parent = body
	end

	pet.PrimaryPart = body
	return pet
end

-- ===== MAKE THE PET FOLLOW ITS OWNER =====
local function startFollowing(pet, player)
	local body = pet.PrimaryPart
	local bobT = math.random() * 10

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local character = player.Character
		if not pet.Parent or not player.Parent then
			connection:Disconnect()
			if pet.Parent then pet:Destroy() end
			return
		end
		if not character then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		bobT += dt
		-- floats beside your left shoulder, bobbing gently
		local offset = root.CFrame * CFrame.new(-2.5, 1.5 + math.sin(bobT * 2.4) * 0.3, 1)
		-- smooth chase (lerp = glides instead of teleporting)
		body.CFrame = body.CFrame:Lerp(
			CFrame.new(offset.Position, offset.Position + root.CFrame.LookVector),
			math.min(dt * 6, 1)
		)
	end)
end

-- ===== HATCH! =====
local hatching = false

prompt.Triggered:Connect(function(player)
	if hatching then return end

	local burgers = player:FindFirstChild("Burgers") or player:FindFirstChild("Food")
	if not burgers or burgers.Value < HATCH_COST then
		prompt.ObjectText = "need " .. HATCH_COST .. " 🍔!"
		task.delay(1.5, function()
			prompt.ObjectText = HATCH_COST .. " 🍔"
		end)
		return
	end

	hatching = true
	burgers.Value -= HATCH_COST

	-- egg shake animation
	local original = eggPart.CFrame
	for i = 1, 6 do
		eggPart.CFrame = original * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 8 or -8))
		task.wait(0.08)
	end
	eggPart.CFrame = original

	-- pop effect
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	burst.LightEmission = 1
	burst.Lifetime = NumberRange.new(0.4, 0.8)
	burst.Speed = NumberRange.new(5, 10)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new(0.5)
	burst.Rate = 0
	burst.Parent = eggPart
	burst:Emit(30)
	game:GetService("Debris"):AddItem(burst, 2)

	-- roll and spawn the pet
	local petInfo = rollPet()

	-- remove their old pet (one pet at a time)
	local oldPet = workspace:FindFirstChild(player.Name .. "_Pet")
	if oldPet then oldPet:Destroy() end

	local pet = buildPet(petInfo, player.Name)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		pet:PivotTo(root.CFrame * CFrame.new(-2.5, 1.5, 1))
	else
		pet:PivotTo(eggPart.CFrame * CFrame.new(0, 3, 0))
	end
	pet.Parent = workspace

	startFollowing(pet, player)

	print("PET: " .. player.Name .. " hatched " .. petInfo.name .. " (" .. petInfo.rarity .. ")")
	hatching = false
end)
