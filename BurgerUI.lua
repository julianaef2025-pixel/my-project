-- BurgerUI.lua (v2 — cooler!)
-- LOCALSCRIPT, inside StarterGui.
-- Fancy gradient counter at the top of the screen that BOUNCES when you
-- eat a burger, plus a floating "+1" popup.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ===== BUILD THE UI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BurgerCounter"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "CounterFrame"
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0, 12)
frame.Size = UDim2.new(0, 260, 0, 56)
frame.BackgroundColor3 = Color3.fromRGB(255, 150, 40)
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = frame

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new(
	Color3.fromRGB(255, 190, 60),
	Color3.fromRGB(230, 110, 30)
)
gradient.Rotation = 90
gradient.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 60, 10)
stroke.Thickness = 3
stroke.Parent = frame

local label = Instance.new("TextLabel")
label.Name = "CounterLabel"
label.Size = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.Font = Enum.Font.FredokaOne
label.Text = "🍔 Burgers: 0"
label.Parent = frame

local textStroke = Instance.new("UIStroke")
textStroke.Color = Color3.fromRGB(100, 50, 10)
textStroke.Thickness = 2
textStroke.Parent = label

-- ===== ANIMATIONS =====
local baseSize = frame.Size

local function bounce()
	-- Punch the counter bigger, then spring back
	frame.Size = UDim2.new(0, baseSize.X.Offset * 1.25, 0, baseSize.Y.Offset * 1.25)
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = baseSize,
	}):Play()
end

local function plusOnePopup()
	-- A "+1" that floats up from the counter and fades away
	local popup = Instance.new("TextLabel")
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, math.random(-60, 60), 0, 70)
	popup.Size = UDim2.new(0, 80, 0, 40)
	popup.BackgroundTransparency = 1
	popup.Text = "+1"
	popup.TextColor3 = Color3.fromRGB(120, 255, 120)
	popup.TextScaled = true
	popup.Font = Enum.Font.FredokaOne
	popup.Rotation = math.random(-15, 15)
	popup.Parent = screenGui

	local popupStroke = Instance.new("UIStroke")
	popupStroke.Color = Color3.fromRGB(20, 80, 20)
	popupStroke.Thickness = 2
	popupStroke.Parent = popup

	local tween = TweenService:Create(popup, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = popup.Position + UDim2.new(0, 0, 0, 60),
		TextTransparency = 1,
		Rotation = 0,
	})
	TweenService:Create(popupStroke, TweenInfo.new(0.9), { Transparency = 1 }):Play()
	tween:Play()
	tween.Completed:Once(function()
		popup:Destroy()
	end)
end

-- ===== KEEP THE COUNTER UPDATED =====
local function watchBurgers(burgers)
	label.Text = "🍔 Burgers: " .. burgers.Value
	burgers.Changed:Connect(function(newValue)
		label.Text = "🍔 Burgers: " .. newValue
		bounce()
		plusOnePopup()
	end)
end

local burgers = player:FindFirstChild("Burgers")
if burgers then
	watchBurgers(burgers)
else
	player.ChildAdded:Connect(function(child)
		if child.Name == "Burgers" and child:IsA("IntValue") then
			watchBurgers(child)
		end
	end)
end
