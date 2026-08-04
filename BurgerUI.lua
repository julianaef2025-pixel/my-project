-- BurgerUI.lua
-- Put this LOCALSCRIPT inside StarterGui.
-- It shows a "🍔 Burgers: X" label at the top of the screen
-- and updates it whenever you collect a burger.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Build the UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BurgerCounter"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "CounterLabel"
label.AnchorPoint = Vector2.new(0.5, 0)          -- anchor at top-center
label.Position = UDim2.new(0.5, 0, 0, 10)        -- middle of screen, 10px from top
label.Size = UDim2.new(0, 250, 0, 50)
label.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
label.BackgroundTransparency = 0.3
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.Font = Enum.Font.FredokaOne
label.Text = "🍔 Burgers: 0"
label.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = label

-- Keep the label updated
local function watchBurgers(burgers)
	label.Text = "🍔 Burgers: " .. burgers.Value
	burgers.Changed:Connect(function(newValue)
		label.Text = "🍔 Burgers: " .. newValue
	end)
end

local burgers = player:FindFirstChild("Burgers")
if burgers then
	watchBurgers(burgers)
else
	-- The counter gets created the first time you eat a burger
	player.ChildAdded:Connect(function(child)
		if child.Name == "Burgers" and child:IsA("IntValue") then
			watchBurgers(child)
		end
	end)
end
