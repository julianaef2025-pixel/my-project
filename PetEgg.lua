-- PetEgg.lua (v2 — ROULETTE EDITION)
-- Regular Script — put INSIDE your egg (Part or Model).
-- Press E -> pay burgers -> roulette spins on screen -> random pet with a
-- burger MULTIPLIER follows you. Needs the HatchRouletteUI LocalScript in StarterGui!

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== SETTINGS =====
local HATCH_COST = 50

-- boost = extra burgers per bite (0.5 = +50%, 2 = +200% = 3x total!)
local PETS = {
	{ name = "Bubble",   color = Color3.fromRGB(120, 200, 255), size = 1.1, rarity = "Common",    boost = 0.25, chance = 28 },
	{ name = "Minty",    color = Color3.fromRGB(120, 255, 160), size = 1.1, rarity = "Common",    boost = 0.25, chance = 28 },
	{ name = "Rocky",    color = Color3.fromRGB(160, 160, 160), size = 1.2, rarity = "Uncommon",  boost = 0.5,  chance = 15 },
	{ name = "Peachy",   color = Color3.fromRGB(255, 170, 120), size = 1.2, rarity = "Uncommon",  boost = 0.5,  chance = 15 },
	{ name = "Sparky",   color = Color3.fromRGB(255, 120, 120), size = 1.3, rarity = "Rare",      boost = 0.75, chance = 6 },
	{ name = "Frosty",   color = Color3.fromRGB(200, 240, 255), size = 1.3, rarity = "Rare",      boost = 0.75, chance = 4 },
	{ name = "Grape",    color = Color3.fromRGB(190, 120, 255), size = 1.4, rarity = "Epic",      boost = 1,    chance = 2.2 },
	{ name = "Shadow",   color = Color3.fromRGB(50, 50, 60),    size = 1.4, rarity = "Epic",      boost = 1,    chance = 1 },
	{ name = "Sunny",    color = Color3.fromRGB(255, 220, 60),  size = 1.6, rarity = "LEGENDARY", boost = 2,    chance = 0.6 },
	{ name = "Galaxy",   color = Color3.fromRGB(120, 60, 255),  size = 1.8, rarity = "MYTHIC",    boost = 3,    chance = 0.2 },
}

local SPIN_TIME = 3.5 -- must match the UI script!
-- ====================

local egg = script.Parent
local eggPart = egg:IsA("BasePart") and egg or (egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart"))
if not eggPart then warn("PetEgg: no part found!") return end

for _, p in (egg:IsA("Model") and egg:GetDescendants() or { egg }) do
	if p:IsA("BasePart") then p.Anchored = true end
end

-- RemoteEvent for telling the client to play the roulette
local hatchEvent = ReplicatedStorage:FindFirstChild("PetHatchEvent")
if not hatchEvent then
	hatchEvent = Instance.new("RemoteEvent")
	hatchEvent.Name = "PetHatchEvent"
	hatchEvent.Parent = ReplicatedStorage
end

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Hatch Pet"
prompt.ObjectText = HATCH_COST .. " 🍔"
prompt.HoldDuration = 0.5
prompt.RequiresLineOfSight = false
prompt.Parent = eggPart

-- ===== WEIGHTED ROLL =====
local totalChance = 0
for _, pet in PETS do totalChance += pet.chance end

local function rollPet()
	local roll = math.random() * totalChance
	local sum = 0
	for i, pet in PETS do
		sum += pet.chance
		if roll <= sum then return i end
	end
	return 1
end

-- ===== BUILD PET =====
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

	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.SmoothPlastic
		eye.Color = Color3.fromRGB(20, 20, 20)
		eye.Size = Vector3.new(0.22, 0.22, 0.22) * petInfo.size
		eye.CanCollide = false
		eye.Massless = true
		eye.CFrame = body.CFrame * CFrame.new(side * petInfo.size * 0.2, petInfo.size * 0.12, -petInfo.size * 0.42)
		eye.Parent = pet
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye
	end

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 130, 0, 40)
	gui.StudsOffset = Vector3.new(0, petInfo.size * 0.8 + 0.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = body

	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, 0, 1, 0)
	tag.BackgroundTransparency = 1
	tag.TextScaled = true
	tag.Font = Enum.Font.FredokaOne
	tag.Text = petInfo.name .. " (+" .. petInfo.boost .. "x 🍔)\n" .. petInfo.rarity
	tag.TextColor3 = (petInfo.rarity == "LEGENDARY" and Color3.fromRGB(255, 200, 40))
		or (petInfo.rarity == "MYTHIC" and Color3.fromRGB(190, 120, 255))
		or Color3.fromRGB(255, 255, 255)
	tag.TextStrokeTransparency = 0.4
	tag.Parent = gui

	if petInfo.rarity == "LEGENDARY" or petInfo.rarity == "MYTHIC" then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(petInfo.color)
		sparkle.LightEmission = 1
		sparkle.Rate = 20
		sparkle.Lifetime = NumberRange.new(0.5, 1)
		sparkle.Speed = NumberRange.new(1, 2)
		sparkle.Size = NumberSequence.new(0.35)
		sparkle.Parent = body
	end

	pet.PrimaryPart = body
	return pet
end

-- ===== FOLLOW =====
local function startFollowing(pet, player)
	local body = pet.PrimaryPart
	local bobT = math.random() * 10

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not pet.Parent or not player.Parent then
			connection:Disconnect()
			if pet.Parent then pet:Destroy() end
			return
		end
		local character = player.Character
		if not character then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		bobT += dt
		local offset = root.CFrame * CFrame.new(-2.5, 1.5 + math.sin(bobT * 2.4) * 0.3, 1)
		body.CFrame = body.CFrame:Lerp(
			CFrame.new(offset.Position, offset.Position + root.CFrame.LookVector),
			math.min(dt * 6, 1)
		)
	end)
end

-- ===== HATCH =====
local busy = {} -- per player

prompt.Triggered:Connect(function(player)
	if busy[player] then return end

	local burgers = player:FindFirstChild("Burgers") or player:FindFirstChild("Food")
	if not burgers or burgers.Value < HATCH_COST then
		prompt.ObjectText = "need " .. HATCH_COST .. " 🍔!"
		task.delay(1.5, function()
			prompt.ObjectText = HATCH_COST .. " 🍔"
		end)
		return
	end

	busy[player] = true
	burgers.Value -= HATCH_COST

	local winIndex = rollPet()
	local petInfo = PETS[winIndex]

	-- send the pet list + winner to the client's roulette UI
	local uiData = {}
	for i, p in PETS do
		uiData[i] = { name = p.name, color = { p.color.R, p.color.G, p.color.B }, rarity = p.rarity, boost = p.boost }
	end
	hatchEvent:FireClient(player, uiData, winIndex)

	-- spawn the pet after the roulette finishes
	task.delay(SPIN_TIME + 1.5, function()
		busy[player] = nil
		if not player.Parent then return end

		-- store the boost so the burger script can use it
		local boostValue = player:FindFirstChild("PetBoost")
		if not boostValue then
			boostValue = Instance.new("NumberValue")
			boostValue.Name = "PetBoost"
			boostValue.Parent = player
		end
		boostValue.Value = petInfo.boost

		local oldPet = workspace:FindFirstChild(player.Name .. "_Pet")
		if oldPet then oldPet:Destroy() end

		local pet = buildPet(petInfo, player.Name)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		pet:PivotTo(root and root.CFrame * CFrame.new(-2.5, 1.5, 1) or eggPart.CFrame * CFrame.new(0, 3, 0))
		pet.Parent = workspace
		startFollowing(pet, player)

		print("PET: " .. player.Name .. " hatched " .. petInfo.name .. " (" .. petInfo.rarity .. ", +" .. petInfo.boost .. "x)")
	end)
end)
