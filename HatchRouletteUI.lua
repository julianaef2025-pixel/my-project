-- HatchRouletteUI.lua
-- LOCALSCRIPT — put in StarterGui.
-- Plays the spinning roulette when you hatch an egg: a reel of pets whooshes
-- past, slows down, and lands on your prize with a big reveal.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPIN_TIME = 3.5 -- must match PetEgg script!

local player = Players.LocalPlayer
local hatchEvent = ReplicatedStorage:WaitForChild("PetHatchEvent")

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(110, 220, 110),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	LEGENDARY = Color3.fromRGB(255, 200, 40),
	MYTHIC = Color3.fromRGB(255, 80, 200),
}

hatchEvent.OnClientEvent:Connect(function(pets, winIndex)
	-- ===== BUILD THE ROULETTE SCREEN =====
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HatchRoulette"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- dark background
	local dim = Instance.new("Frame")
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Parent = screenGui
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.4 }):Play()

	-- the window where tiles scroll past
	local TILE = 130
	local windowFrame = Instance.new("Frame")
	windowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	windowFrame.Position = UDim2.new(0.5, 0, 0.45, 0)
	windowFrame.Size = UDim2.new(0, TILE * 5, 0, TILE + 20)
	windowFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	windowFrame.ClipsDescendants = true
	windowFrame.Parent = screenGui
	Instance.new("UICorner", windowFrame).CornerRadius = UDim.new(0, 16)

	local wStroke = Instance.new("UIStroke")
	wStroke.Color = Color3.fromRGB(255, 200, 60)
	wStroke.Thickness = 4
	wStroke.Parent = windowFrame

	-- the moving strip of tiles
	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(0, 0, 1, 0)
	strip.Parent = windowFrame

	-- build ~30 tiles of random pets, with THE WINNER at slot 26
	local WIN_SLOT = 26
	local NUM_TILES = 30
	for i = 1, NUM_TILES do
		local petIndex = (i == WIN_SLOT) and winIndex or math.random(1, #pets)
		local pet = pets[petIndex]

		local tile = Instance.new("Frame")
		tile.Position = UDim2.new(0, (i - 1) * TILE + 5, 0, 10)
		tile.Size = UDim2.new(0, TILE - 10, 1, -20)
		tile.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
		tile.Parent = strip
		Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 12)

		local tStroke = Instance.new("UIStroke")
		tStroke.Color = RARITY_COLORS[pet.rarity] or Color3.fromRGB(120, 120, 120)
		tStroke.Thickness = 3
		tStroke.Parent = tile

		-- the pet "icon" (colored ball)
		local icon = Instance.new("Frame")
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 8)
		icon.Size = UDim2.new(0, 55, 0, 55)
		icon.BackgroundColor3 = Color3.new(pet.color[1], pet.color[2], pet.color[3])
		icon.Parent = tile
		Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.AnchorPoint = Vector2.new(0.5, 1)
		nameLabel.Position = UDim2.new(0.5, 0, 1, -6)
		nameLabel.Size = UDim2.new(1, -8, 0, 34)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.FredokaOne
		nameLabel.Text = pet.name .. "\n+" .. pet.boost .. "x"
		nameLabel.TextColor3 = RARITY_COLORS[pet.rarity] or Color3.fromRGB(255, 255, 255)
		nameLabel.Parent = tile
	end

	-- center pointer
	local pointer = Instance.new("Frame")
	pointer.AnchorPoint = Vector2.new(0.5, 0)
	pointer.Position = UDim2.new(0.5, 0, 0, -4)
	pointer.Size = UDim2.new(0, 6, 1, 8)
	pointer.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	pointer.ZIndex = 5
	pointer.Parent = windowFrame
	Instance.new("UICorner", pointer).CornerRadius = UDim.new(0, 3)

	-- ===== SPIN! =====
	-- move the strip so the winner tile ends up centered under the pointer
	-- (with a tiny random offset so it doesn't land dead-center every time)
	local windowCenter = TILE * 5 / 2
	local winnerCenter = (WIN_SLOT - 1) * TILE + TILE / 2
	local wobble = math.random(-25, 25)
	local finalX = -(winnerCenter - windowCenter) + wobble

	strip.Position = UDim2.new(0, 0, 0, 0)
	local spin = TweenService:Create(strip,
		TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, finalX, 0, 0) }
	)
	spin:Play()

	spin.Completed:Wait()

	-- ===== REVEAL =====
	local won = pets[winIndex]
	local rarityColor = RARITY_COLORS[won.rarity] or Color3.fromRGB(255, 255, 255)

	local reveal = Instance.new("TextLabel")
	reveal.AnchorPoint = Vector2.new(0.5, 0.5)
	reveal.Position = UDim2.new(0.5, 0, 0.72, 0)
	reveal.Size = UDim2.new(0, 10, 0, 10)
	reveal.BackgroundTransparency = 1
	reveal.Font = Enum.Font.FredokaOne
	reveal.TextScaled = true
	reveal.Text = "🎉 " .. won.rarity .. "! " .. won.name .. " (+" .. won.boost .. "x 🍔)"
	reveal.TextColor3 = rarityColor
	reveal.TextStrokeTransparency = 0.3
	reveal.Parent = screenGui

	TweenService:Create(reveal,
		TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 620, 0, 80) }
	):Play()

	-- flash the winner's stroke gold
	TweenService:Create(wStroke, TweenInfo.new(0.3), { Color = rarityColor, Thickness = 6 }):Play()

	task.wait(1.5)

	-- fade everything out
	TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(reveal, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	windowFrame.Visible = false
	task.wait(0.45)
	screenGui:Destroy()
end)
