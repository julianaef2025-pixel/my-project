--[[
	ROLE GIVER UI — LocalScript (StarterPlayer > StarterPlayerScripts)
	A separate LocalScript: don't paste into the others.

	Only the owner sees this: a little crown button in the top right.
	Click it, type a username, click a role — done. Works together
	with the RoleSystem server script.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("RoleRemotes")
local assignRemote = remotes:WaitForChild("AssignRole")
local resultRemote = remotes:WaitForChild("RoleResult")
local rolesList = remotes:WaitForChild("RolesList")

-- wait until the server says we're allowed to manage roles
while player:GetAttribute("CanManageRoles") ~= true do
	player:GetAttributeChangedSignal("CanManageRoles"):Wait()
end

local ROLES = string.split(rolesList.Value, "|")

local ROLE_COLORS = {
	["Member"] = Color3.fromRGB(110, 220, 130),
	["Development Team"] = Color3.fromRGB(255, 90, 90),
	["VIP"] = Color3.fromRGB(255, 200, 60),
}

local gui = Instance.new("ScreenGui")
gui.Name = "RoleGiver"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

-- crown button, top right (sits under the LV tab)
local crown = Instance.new("TextButton")
crown.Size = UDim2.new(0, 44, 0, 44)
crown.Position = UDim2.new(1, -16, 0, 116)
crown.AnchorPoint = Vector2.new(1, 0)
crown.BackgroundColor3 = Color3.fromRGB(24, 20, 8)
crown.Text = "👑"
crown.TextSize = 22
crown.Font = Enum.Font.GothamBold
crown.BorderSizePixel = 0
crown.Parent = gui
local crownCorner = Instance.new("UICorner")
crownCorner.CornerRadius = UDim.new(0, 12)
crownCorner.Parent = crown
local crownStroke = Instance.new("UIStroke")
crownStroke.Color = Color3.fromRGB(255, 200, 60)
crownStroke.Thickness = 1.5
crownStroke.Transparency = 0.4
crownStroke.Parent = crown

-- the panel
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 250, 0, 118 + #ROLES * 42 + 42)
panel.Position = UDim2.new(1, -16, 0, 170)
panel.AnchorPoint = Vector2.new(1, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 16)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(255, 200, 60)
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.5
panelStroke.Parent = panel
local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new(Color3.fromRGB(30, 32, 24), Color3.fromRGB(14, 16, 12))
panelGradient.Rotation = 110
panelGradient.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 24)
title.Position = UDim2.new(0, 12, 0, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(255, 210, 90)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "👑 ROLE MANAGER"
title.Parent = panel

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -24, 0, 34)
nameBox.Position = UDim2.new(0, 12, 0, 42)
nameBox.BackgroundColor3 = Color3.fromRGB(10, 12, 10)
nameBox.Font = Enum.Font.Code
nameBox.TextSize = 14
nameBox.TextColor3 = Color3.fromRGB(230, 235, 225)
nameBox.PlaceholderText = "type exact username..."
nameBox.PlaceholderColor3 = Color3.fromRGB(110, 115, 105)
nameBox.Text = ""
nameBox.ClearTextOnFocus = false
nameBox.BorderSizePixel = 0
nameBox.Parent = panel
local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 8)
boxCorner.Parent = nameBox
local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Color3.fromRGB(90, 95, 85)
boxStroke.Thickness = 1
boxStroke.Transparency = 0.5
boxStroke.Parent = nameBox

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -24, 0, 30)
statusLabel.Position = UDim2.new(0, 12, 1, -36)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 11
statusLabel.TextColor3 = Color3.fromRGB(160, 165, 155)
statusLabel.TextWrapped = true
statusLabel.Text = "type a name, then click a role"
statusLabel.Parent = panel

local function makeRoleButton(roleName, order, color)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -24, 0, 34)
	button.Position = UDim2.new(0, 12, 0, 86 + (order - 1) * 42)
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(15, 18, 15)
	button.Text = "GIVE " .. roleName:upper()
	button.BorderSizePixel = 0
	button.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		statusLabel.Text = "working..."
		statusLabel.TextColor3 = Color3.fromRGB(160, 165, 155)
		assignRemote:FireServer(nameBox.Text, roleName)
	end)
	return button
end

for order, roleName in ROLES do
	makeRoleButton(roleName, order, ROLE_COLORS[roleName] or Color3.fromRGB(190, 195, 200))
end

-- remove-role button (gray, last)
local removeButton = Instance.new("TextButton")
removeButton.Size = UDim2.new(1, -24, 0, 30)
removeButton.Position = UDim2.new(0, 12, 0, 86 + #ROLES * 42)
removeButton.BackgroundColor3 = Color3.fromRGB(60, 62, 58)
removeButton.Font = Enum.Font.GothamBold
removeButton.TextSize = 12
removeButton.TextColor3 = Color3.fromRGB(220, 222, 218)
removeButton.Text = "REMOVE ROLE"
removeButton.BorderSizePixel = 0
removeButton.Parent = panel
local removeCorner = Instance.new("UICorner")
removeCorner.CornerRadius = UDim.new(0, 8)
removeCorner.Parent = removeButton
removeButton.MouseButton1Click:Connect(function()
	statusLabel.Text = "working..."
	assignRemote:FireServer(nameBox.Text, "REMOVE")
end)

resultRemote.OnClientEvent:Connect(function(message, success)
	statusLabel.Text = message
	statusLabel.TextColor3 = success
		and Color3.fromRGB(120, 210, 130)
		or Color3.fromRGB(255, 130, 90)
end)

crown.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	TweenService:Create(crownStroke, TweenInfo.new(0.15), {
		Transparency = panel.Visible and 0 or 0.4,
	}):Play()
end)
