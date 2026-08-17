--[[
	ROLE GIVER UI — LocalScript (StarterPlayer > StarterPlayerScripts)
	A separate LocalScript: don't paste into the others.

	Owner-only "PERSONNEL" terminal, styled like military field gear.
	Small tab on the right edge opens it; the panel is centered on the
	right side of the screen so it always fits — PC and mobile.
	Works together with the RoleSystem server script.
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

-- field-gear palette: olive drab, stencil text, hard corners
local INK = Color3.fromRGB(214, 219, 189) -- pale stencil
local OLIVE = Color3.fromRGB(88, 96, 58)
local PANEL_BG = Color3.fromRGB(26, 28, 20)
local ROW_BG = Color3.fromRGB(36, 39, 28)

local ROLE_STRIPES = {
	["Member"] = Color3.fromRGB(106, 170, 90),
	["Development Team"] = Color3.fromRGB(196, 90, 66),
	["VIP"] = Color3.fromRGB(203, 166, 76),
}

local gui = Instance.new("ScreenGui")
gui.Name = "RoleGiver"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

-- edge tab: a slim stencil tab hugging the right edge, mid-screen
local tab = Instance.new("TextButton")
tab.AnchorPoint = Vector2.new(1, 0.5)
tab.Position = UDim2.new(1, 0, 0.5, -140)
tab.Size = UDim2.new(0, 30, 0, 110)
tab.BackgroundColor3 = PANEL_BG
tab.Text = ""
tab.BorderSizePixel = 0
tab.Parent = gui
local tabCorner = Instance.new("UICorner")
tabCorner.CornerRadius = UDim.new(0, 6)
tabCorner.Parent = tab
local tabStroke = Instance.new("UIStroke")
tabStroke.Color = OLIVE
tabStroke.Thickness = 1
tabStroke.Parent = tab
local tabText = Instance.new("TextLabel")
tabText.Size = UDim2.new(0, 100, 0, 24)
tabText.Position = UDim2.new(0.5, 0, 0.5, 0)
tabText.AnchorPoint = Vector2.new(0.5, 0.5)
tabText.Rotation = 90
tabText.BackgroundTransparency = 1
tabText.Font = Enum.Font.Code
tabText.TextSize = 13
tabText.TextColor3 = INK
tabText.Text = "PERSONNEL"
tabText.Parent = tab

-- the panel: vertically CENTERED on the right, so it can never hang
-- off the bottom of any screen
local ROW_HEIGHT = 40
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -40, 0.5, 0)
panel.Size = UDim2.new(0, 232, 0, 128 + (#ROLES + 1) * (ROW_HEIGHT + 6) + 34)
panel.BackgroundColor3 = PANEL_BG
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 6)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = OLIVE
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

-- header strip, like a stenciled crate label
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 34)
header.BackgroundColor3 = OLIVE
header.BorderSizePixel = 0
header.Parent = panel
local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 6)
headerCorner.Parent = header
local headerText = Instance.new("TextLabel")
headerText.Size = UDim2.new(1, -16, 1, 0)
headerText.Position = UDim2.new(0, 10, 0, 0)
headerText.BackgroundTransparency = 1
headerText.Font = Enum.Font.Code
headerText.TextSize = 14
headerText.TextColor3 = Color3.fromRGB(20, 22, 14)
headerText.TextXAlignment = Enum.TextXAlignment.Left
headerText.Text = "★ PERSONNEL — ROLE ORDERS"
headerText.Parent = header

local subText = Instance.new("TextLabel")
subText.Size = UDim2.new(1, -24, 0, 14)
subText.Position = UDim2.new(0, 12, 0, 40)
subText.BackgroundTransparency = 1
subText.Font = Enum.Font.Code
subText.TextSize = 11
subText.TextColor3 = Color3.fromRGB(130, 136, 108)
subText.TextXAlignment = Enum.TextXAlignment.Left
subText.Text = "SOLDIER NAME:"
subText.Parent = panel

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -24, 0, 34)
nameBox.Position = UDim2.new(0, 12, 0, 56)
nameBox.BackgroundColor3 = Color3.fromRGB(16, 17, 12)
nameBox.Font = Enum.Font.Code
nameBox.TextSize = 14
nameBox.TextColor3 = INK
nameBox.PlaceholderText = "username_here"
nameBox.PlaceholderColor3 = Color3.fromRGB(94, 100, 76)
nameBox.Text = ""
nameBox.ClearTextOnFocus = false
nameBox.BorderSizePixel = 0
nameBox.Parent = panel
local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 4)
boxCorner.Parent = nameBox
local boxStroke = Instance.new("UIStroke")
boxStroke.Color = OLIVE
boxStroke.Thickness = 1
boxStroke.Parent = nameBox

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -24, 0, 28)
statusLabel.Position = UDim2.new(0, 12, 1, -32)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 11
statusLabel.TextColor3 = Color3.fromRGB(130, 136, 108)
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "> awaiting orders"
statusLabel.Parent = panel

-- role rows: dark bars with a colored rank stripe on the left
local function makeRoleRow(labelText, order, stripeColor, roleValue)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -24, 0, ROW_HEIGHT)
	row.Position = UDim2.new(0, 12, 0, 100 + (order - 1) * (ROW_HEIGHT + 6))
	row.BackgroundColor3 = ROW_BG
	row.Text = ""
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.Parent = panel
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 4)
	rowCorner.Parent = row

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 5, 1, 0)
	stripe.BackgroundColor3 = stripeColor
	stripe.BorderSizePixel = 0
	stripe.Parent = row
	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 4)
	stripeCorner.Parent = stripe

	local rowText = Instance.new("TextLabel")
	rowText.Size = UDim2.new(1, -20, 1, 0)
	rowText.Position = UDim2.new(0, 16, 0, 0)
	rowText.BackgroundTransparency = 1
	rowText.Font = Enum.Font.Code
	rowText.TextSize = 13
	rowText.TextColor3 = INK
	rowText.TextXAlignment = Enum.TextXAlignment.Left
	rowText.Text = labelText
	rowText.Parent = row

	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(48, 52, 38) }):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = ROW_BG }):Play()
	end)
	row.MouseButton1Click:Connect(function()
		statusLabel.Text = "> transmitting..."
		statusLabel.TextColor3 = Color3.fromRGB(130, 136, 108)
		assignRemote:FireServer(nameBox.Text, roleValue)
	end)
	return row
end

for order, roleName in ROLES do
	makeRoleRow("ASSIGN: " .. roleName:upper(), order,
		ROLE_STRIPES[roleName] or Color3.fromRGB(140, 145, 130), roleName)
end
makeRoleRow("✕ STRIP ROLE", #ROLES + 1, Color3.fromRGB(90, 92, 86), "REMOVE")

resultRemote.OnClientEvent:Connect(function(message, success)
	statusLabel.Text = "> " .. message
	statusLabel.TextColor3 = success
		and Color3.fromRGB(140, 200, 120)
		or Color3.fromRGB(220, 130, 90)
end)

tab.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	TweenService:Create(tabStroke, TweenInfo.new(0.15), {
		Color = panel.Visible and INK or OLIVE,
	}):Play()
end)
