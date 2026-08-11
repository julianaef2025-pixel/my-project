--[[
	MAIN MENU — CLIENT LocalScript (StarterPlayer > StarterPlayerScripts)
	A separate LocalScript: don't paste into the drone LocalScript.

	- Shows a simple main menu when you join
	- TEAM BLUE / TEAM RED: join that team and spawn at its checkpoint
	- DRONES: pick FPV KAMIKAZE or BOMBER — it gets delivered in front of you
	- Press M to reopen the menu any time
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("MenuRemotes")
local teamSelect = remotes:WaitForChild("TeamSelect")
local droneSelect = remotes:WaitForChild("DroneSelect")

--------------------------------------------------------------------
-- build the menu
--------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MainMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100

-- dark backdrop
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(12, 14, 12)
backdrop.BackgroundTransparency = 0.25
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

-- centered panel
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 340, 0, 380)
panel.BackgroundColor3 = Color3.fromRGB(22, 26, 22)
panel.BorderSizePixel = 0
panel.Parent = backdrop

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 54)
title.Position = UDim2.new(0, 0, 0, 18)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 34
title.TextColor3 = Color3.fromRGB(235, 235, 225)
title.Text = "⚔ WARZONE ⚔"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, 0, 0, 20)
subtitle.Position = UDim2.new(0, 0, 0, 66)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 14
subtitle.TextColor3 = Color3.fromRGB(150, 155, 150)
subtitle.Text = "pick a side"
subtitle.Parent = panel

local function makeButton(parent, text, color, yOffset)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -48, 0, 52)
	button.Position = UDim2.new(0, 24, 0, yOffset)
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = text
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

-- main buttons
local blueButton = makeButton(panel, "TEAM BLUE", Color3.fromRGB(40, 90, 200), 104)
local redButton = makeButton(panel, "TEAM RED", Color3.fromRGB(190, 45, 45), 168)
local dronesButton = makeButton(panel, "🛩 DRONES", Color3.fromRGB(60, 65, 60), 232)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, 0, 0, 20)
hint.Position = UDim2.new(0, 0, 1, -32)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 13
hint.TextColor3 = Color3.fromRGB(130, 135, 130)
hint.Text = "press M to open this menu again"
hint.Parent = panel

-- drones sub-panel (hidden until DRONES is pressed)
local dronePanel = Instance.new("Frame")
dronePanel.Name = "DronePanel"
dronePanel.Size = UDim2.new(1, 0, 1, 0)
dronePanel.BackgroundColor3 = Color3.fromRGB(22, 26, 22)
dronePanel.BorderSizePixel = 0
dronePanel.Visible = false
dronePanel.Parent = panel

local dronePanelCorner = Instance.new("UICorner")
dronePanelCorner.CornerRadius = UDim.new(0, 12)
dronePanelCorner.Parent = dronePanel

local droneTitle = Instance.new("TextLabel")
droneTitle.Size = UDim2.new(1, 0, 0, 54)
droneTitle.Position = UDim2.new(0, 0, 0, 18)
droneTitle.BackgroundTransparency = 1
droneTitle.Font = Enum.Font.GothamBlack
droneTitle.TextSize = 26
droneTitle.TextColor3 = Color3.fromRGB(235, 235, 225)
droneTitle.Text = "🛩 PICK YOUR DRONE"
droneTitle.Parent = dronePanel

local kamikazeButton = makeButton(dronePanel, "💥 FPV KAMIKAZE", Color3.fromRGB(140, 90, 30), 104)
local bomberButton = makeButton(dronePanel, "💣 BOMBER", Color3.fromRGB(70, 100, 60), 168)
local backButton = makeButton(dronePanel, "← BACK", Color3.fromRGB(55, 58, 55), 232)

local droneStatus = Instance.new("TextLabel")
droneStatus.Size = UDim2.new(1, 0, 0, 20)
droneStatus.Position = UDim2.new(0, 0, 1, -56)
droneStatus.BackgroundTransparency = 1
droneStatus.Font = Enum.Font.Gotham
droneStatus.TextSize = 14
droneStatus.TextColor3 = Color3.fromRGB(140, 220, 140)
droneStatus.Text = ""
droneStatus.Parent = dronePanel

gui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------
-- behavior
--------------------------------------------------------------------

local function setMenuOpen(open)
	backdrop.Visible = open
	if open then
		dronePanel.Visible = false
		droneStatus.Text = ""
	end
end

blueButton.MouseButton1Click:Connect(function()
	teamSelect:FireServer("Blue")
	setMenuOpen(false)
end)

redButton.MouseButton1Click:Connect(function()
	teamSelect:FireServer("Red")
	setMenuOpen(false)
end)

dronesButton.MouseButton1Click:Connect(function()
	dronePanel.Visible = true
end)

backButton.MouseButton1Click:Connect(function()
	dronePanel.Visible = false
end)

kamikazeButton.MouseButton1Click:Connect(function()
	droneSelect:FireServer("Kamikaze")
	droneStatus.Text = "Kamikaze drone delivered in front of you!"
	task.delay(1, function()
		setMenuOpen(false)
	end)
end)

bomberButton.MouseButton1Click:Connect(function()
	droneSelect:FireServer("Bomber")
	droneStatus.Text = "Bomber drone delivered in front of you!"
	task.delay(1, function()
		setMenuOpen(false)
	end)
end)

-- reopen with M
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		setMenuOpen(not backdrop.Visible)
	end
end)

-- menu is open when you first join
setMenuOpen(true)
