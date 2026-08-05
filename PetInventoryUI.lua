-- PetInventoryUI.lua
-- LOCALSCRIPT — put in StarterGui.
-- A 🐾 Pets button (bottom left). Click it to open your pet collection —
-- every pet you've ever hatched — and tap any pet to equip it.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local equipEvent = ReplicatedStorage:WaitForChild("EquipPetEvent")

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(110, 220, 110),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	LEGENDARY = Color3.fromRGB(255, 200, 40),
	MYTHIC = Color3.fromRGB(255, 80, 200),
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PetInventory"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== THE 🐾 BUTTON =====
local openButton = Instance.new("TextButton")
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 12, 1, -12)
openButton.Size = UDim2.new(0, 130, 0, 52)
openButton.BackgroundColor3 = Color3.fromRGB(80, 170, 90)
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextScaled = true
openButton.Font = Enum.Font.FredokaOne
openButton.Text = "🐾 Pets"
openButton.Parent = screenGui
Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 14)

local obStroke = Instance.new("UIStroke")
obStroke.Color = Color3.fromRGB(30, 90, 40)
obStroke.Thickness = 3
obStroke.Parent = openButton

-- ===== THE INVENTORY PANEL =====
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 420, 0, 340)
panel.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
panel.Visible = false
panel.Parent = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

local pStroke = Instance.new("UIStroke")
pStroke.Color = Color3.fromRGB(80, 170, 90)
pStroke.Thickness = 3
pStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 44)
title.BackgroundTransparency = 1
title.TextScaled = true
title.Font = Enum.Font.FredokaOne
title.Text = "🐾 My Pets"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -8, 0, 8)
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextScaled = true
closeButton.Font = Enum.Font.FredokaOne
closeButton.Text = "X"
closeButton.Parent = panel
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 10)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 10, 0, 50)
scroll.Size = UDim2.new(1, -20, 1, -60)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.new(0, 92, 0, 110)
layout.CellPadding = UDim2.new(0, 6, 0, 6)
layout.Parent = scroll

-- ===== FILL THE PANEL WITH YOUR PETS =====
local function rebuild()
	for _, child in scroll:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end

	local petsFolder = player:FindFirstChild("Pets")
	if not petsFolder then return end

	local equipped = player:GetAttribute("EquippedPet")

	for _, entry in petsFolder:GetChildren() do
		local rarity = entry:GetAttribute("Rarity") or "Common"
		local boost = entry:GetAttribute("Boost") or 0
		local color = entry:GetAttribute("Color") or Color3.fromRGB(200, 200, 200)
		local isEquipped = (entry.Name == equipped)

		local card = Instance.new("TextButton")
		card.BackgroundColor3 = isEquipped and Color3.fromRGB(60, 90, 60) or Color3.fromRGB(50, 50, 66)
		card.Text = ""
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = RARITY_COLORS[rarity] or Color3.fromRGB(120, 120, 120)
		cStroke.Thickness = isEquipped and 4 or 2
		cStroke.Parent = card

		local icon = Instance.new("Frame")
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 8)
		icon.Size = UDim2.new(0, 44, 0, 44)
		icon.BackgroundColor3 = color
		icon.Parent = card
		Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -4)
		label.Size = UDim2.new(1, -6, 0, 52)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Text = entry.Name .. "\n+" .. boost .. "x 🍔\n" .. (isEquipped and "EQUIPPED" or rarity)
		label.TextColor3 = isEquipped and Color3.fromRGB(140, 255, 140) or (RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255))
		label.Parent = card

		card.Activated:Connect(function()
			equipEvent:FireServer(entry.Name)
			task.wait(0.3)
			rebuild()
		end)
	end
end

-- ===== OPEN / CLOSE =====
openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		rebuild()
		panel.Size = UDim2.new(0, 10, 0, 10)
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 420, 0, 340),
		}):Play()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

-- refresh when your collection or equipped pet changes
player.AttributeChanged:Connect(function(attr)
	if attr == "EquippedPet" and panel.Visible then
		rebuild()
	end
end)
task.spawn(function()
	local petsFolder = player:WaitForChild("Pets", 30)
	if petsFolder then
		petsFolder.ChildAdded:Connect(function()
			if panel.Visible then rebuild() end
		end)
	end
end)
