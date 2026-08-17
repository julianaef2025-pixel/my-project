--[[
	XP HUD — LocalScript (StarterPlayer > StarterPlayerScripts)
	A separate LocalScript: don't paste into the others.

	- Small level tab in the top-right corner with an XP progress bar
	- Floating "+25 DRONE KILL" popups when you earn XP
	- Big LEVEL UP flash when you level
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local xpUpdate = ReplicatedStorage:WaitForChild("XPUpdate")

local GOLD = Color3.fromRGB(255, 200, 80)

--------------------------------------------------------------------
-- build the HUD
--------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "XPHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

-- the little level tab, top-right (under the battery area of drone HUDs)
local tab = Instance.new("Frame")
tab.Name = "LevelTab"
tab.AnchorPoint = Vector2.new(1, 0)
tab.Position = UDim2.new(1, -16, 0, 66)
tab.Size = UDim2.new(0, 170, 0, 58)
tab.BackgroundColor3 = Color3.fromRGB(18, 22, 18)
tab.BackgroundTransparency = 0.25
tab.BorderSizePixel = 0
tab.Parent = gui

local tabCorner = Instance.new("UICorner")
tabCorner.CornerRadius = UDim.new(0, 8)
tabCorner.Parent = tab

local tabStroke = Instance.new("UIStroke")
tabStroke.Color = GOLD
tabStroke.Thickness = 1
tabStroke.Transparency = 0.6
tabStroke.Parent = tab

local levelText = Instance.new("TextLabel")
levelText.Size = UDim2.new(1, -16, 0, 22)
levelText.Position = UDim2.new(0, 8, 0, 4)
levelText.BackgroundTransparency = 1
levelText.Font = Enum.Font.GothamBlack
levelText.TextSize = 17
levelText.TextColor3 = GOLD
levelText.TextXAlignment = Enum.TextXAlignment.Left
levelText.Text = "PVT"
levelText.Parent = tab

-- full rank name in small text under the abbreviation
local rankNameText = Instance.new("TextLabel")
rankNameText.Size = UDim2.new(1, -16, 0, 12)
rankNameText.Position = UDim2.new(0, 8, 0, 26)
rankNameText.BackgroundTransparency = 1
rankNameText.Font = Enum.Font.GothamBold
rankNameText.TextSize = 10
rankNameText.TextColor3 = Color3.fromRGB(170, 175, 170)
rankNameText.TextXAlignment = Enum.TextXAlignment.Left
rankNameText.Text = "PRIVATE"
rankNameText.Parent = tab

local xpText = Instance.new("TextLabel")
xpText.Size = UDim2.new(0, 70, 0, 22)
xpText.Position = UDim2.new(1, -8, 0, 4)
xpText.AnchorPoint = Vector2.new(1, 0)
xpText.BackgroundTransparency = 1
xpText.Font = Enum.Font.Code
xpText.TextSize = 12
xpText.TextColor3 = Color3.fromRGB(170, 175, 170)
xpText.TextXAlignment = Enum.TextXAlignment.Right
xpText.Text = "0 / 100"
xpText.Parent = tab

local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(1, -16, 0, 6)
barBack.Position = UDim2.new(0, 8, 1, -12)
barBack.BackgroundColor3 = Color3.fromRGB(40, 45, 40)
barBack.BorderSizePixel = 0
barBack.Parent = tab

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 3)
barCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = GOLD
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 3)
fillCorner.Parent = barFill

--------------------------------------------------------------------
-- popups
--------------------------------------------------------------------

local popupOffset = 0

local function showPopup(amount, reason)
	popupOffset = (popupOffset + 1) % 4 -- stack a few without overlapping

	local popup = Instance.new("TextLabel")
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.new(0.5, 120, 0.55, popupOffset * 26)
	popup.Size = UDim2.new(0, 320, 0, 26)
	popup.BackgroundTransparency = 1
	popup.Font = Enum.Font.GothamBold
	popup.TextSize = 19
	popup.TextColor3 = GOLD
	popup.TextStrokeTransparency = 0.5
	popup.Text = string.format("+%d XP  %s", amount, reason or "")
	popup.Parent = gui

	-- drift up and fade
	TweenService:Create(popup, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = popup.Position - UDim2.new(0, 0, 0, 56),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.2, function()
		popup:Destroy()
	end)
end

local function showLevelUp(rankName)
	local flash = Instance.new("TextLabel")
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = UDim2.new(0.5, 0, 0.38, 0)
	flash.Size = UDim2.new(0, 600, 0, 60)
	flash.BackgroundTransparency = 1
	flash.Font = Enum.Font.GothamBlack
	flash.TextSize = 12
	flash.TextColor3 = GOLD
	flash.TextStrokeTransparency = 0.3
	flash.Text = "🎖 PROMOTED: " .. tostring(rankName):upper() .. " 🎖"
	flash.Parent = gui

	-- punch in big, hold, fade out
	TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 48,
	}):Play()
	task.delay(1.6, function()
		local fade = TweenService:Create(flash, TweenInfo.new(0.6), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fade.Completed:Once(function()
			flash:Destroy()
		end)
		fade:Play()
	end)

	-- make the tab glow for a moment too
	TweenService:Create(tabStroke, TweenInfo.new(0.2), { Transparency = 0, Thickness = 2 }):Play()
	task.delay(1.6, function()
		TweenService:Create(tabStroke, TweenInfo.new(0.6), { Transparency = 0.6, Thickness = 1 }):Play()
	end)
end

--------------------------------------------------------------------
-- receive updates
--------------------------------------------------------------------

xpUpdate.OnClientEvent:Connect(function(totalXP, level, intoLevel, needed, gained, reason, leveledUp, rankName, rankAbbr, isMaxRank)
	levelText.Text = rankAbbr or ("LV " .. level)
	rankNameText.Text = (rankName or ""):upper()
	xpText.Text = isMaxRank and "MAX RANK" or (intoLevel .. " / " .. needed)
	TweenService:Create(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(isMaxRank and 1 or math.clamp(intoLevel / needed, 0, 1), 0, 1, 0),
	}):Play()

	if gained and gained > 0 then
		showPopup(gained, reason)
	end
	if leveledUp then
		showLevelUp(rankName or ("LEVEL " .. level))
	end
end)
