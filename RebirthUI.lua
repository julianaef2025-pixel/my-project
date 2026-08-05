-- RebirthUI.lua
-- LOCALSCRIPT — put in StarterGui.
-- Shows a Rebirth button (with progress) and your rebirth count.
-- Button glows when you can afford a rebirth; click it to rebirth.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REBIRTH_COST = 100 -- must match RebirthServer!

local player = Players.LocalPlayer
local rebirthEvent = ReplicatedStorage:WaitForChild("RebirthEvent")

-- ===== BUILD UI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RebirthUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- rebirth count (top right corner)
local countLabel = Instance.new("TextLabel")
countLabel.AnchorPoint = Vector2.new(1, 0)
countLabel.Position = UDim2.new(1, -12, 0, 12)
countLabel.Size = UDim2.new(0, 170, 0, 44)
countLabel.BackgroundColor3 = Color3.fromRGB(90, 40, 150)
countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
countLabel.TextScaled = true
countLabel.Font = Enum.Font.FredokaOne
countLabel.Text = "⭐ Rebirths: 0"
countLabel.Parent = screenGui
Instance.new("UICorner", countLabel).CornerRadius = UDim.new(0, 12)

-- rebirth button (left side, middle)
local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(0, 0.5)
button.Position = UDim2.new(0, 12, 0.5, 0)
button.Size = UDim2.new(0, 190, 0, 64)
button.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.TextScaled = true
button.Font = Enum.Font.FredokaOne
button.Text = "⭐ REBIRTH\n0/" .. REBIRTH_COST .. " 🍔"
button.Parent = screenGui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 60)
stroke.Thickness = 3
stroke.Parent = button

-- ===== KEEP UI UPDATED =====
local burgersValue, rebirthsValue

local function refresh()
	local burgers = burgersValue and burgersValue.Value or 0
	local rebirths = rebirthsValue and rebirthsValue.Value or 0

	countLabel.Text = "⭐ Rebirths: " .. rebirths
	button.Text = "⭐ REBIRTH\n" .. math.min(burgers, REBIRTH_COST) .. "/" .. REBIRTH_COST .. " 🍔"

	if burgers >= REBIRTH_COST then
		-- READY: glowing gold
		button.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
		stroke.Color = Color3.fromRGB(150, 100, 0)
		button.Text = "⭐ REBIRTH READY!\nclick me!"
	else
		-- not yet: gray
		button.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		stroke.Color = Color3.fromRGB(60, 60, 60)
	end
end

local function hook(name, setter)
	local v = player:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		setter(v)
		v.Changed:Connect(refresh)
		refresh()
	end
	player.ChildAdded:Connect(function(child)
		if child.Name == name and child:IsA("IntValue") then
			setter(child)
			child.Changed:Connect(refresh)
			refresh()
		end
	end)
end

hook("Burgers", function(v) burgersValue = v end)
hook("Food", function(v) burgersValue = burgersValue or v end) -- fallback name
hook("Rebirths", function(v) rebirthsValue = v end)

-- ===== CLICK =====
button.Activated:Connect(function()
	local burgers = burgersValue and burgersValue.Value or 0
	if burgers >= REBIRTH_COST then
		rebirthEvent:FireServer()
		-- little celebration pop
		local base = button.Size
		button.Size = UDim2.new(0, base.X.Offset * 1.2, 0, base.Y.Offset * 1.2)
		TweenService:Create(button, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Size = base,
		}):Play()
	else
		-- shake "no" if clicked too early
		local basePos = button.Position
		for i = 1, 3 do
			button.Position = basePos + UDim2.new(0, 6, 0, 0)
			task.wait(0.04)
			button.Position = basePos - UDim2.new(0, 6, 0, 0)
			task.wait(0.04)
		end
		button.Position = basePos
	end
end)

refresh()
