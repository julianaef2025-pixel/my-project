--[[
	DRONE WAR MENU — CLIENT LocalScript (StarterPlayer > StarterPlayerScripts)
	Replaces the old main menu LocalScript. The MainMenu SERVER script stays
	unchanged — this talks to the same TeamSelect/DroneSelect remotes.

	Flow:
	1. Loading screen: DRONE WAR title + animated bar, then fades out
	2. Team select: BLUE / RED cards with live player counts
	3. In game: DRONES tab docked on the left edge — slides out a panel
	   to pick FPV Kamikaze or Bomber; TEAMS tab reopens team select
	   (M also toggles team select)
]]

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

-- drone unlock levels + Robux early-unlock prices (display only —
-- the real price lives on the Developer Product)
local LEVEL_REQUIREMENTS = { Kamikaze = 2, Recon = 4, Bomber = 7 }
local ROBUX_PRICES = { Kamikaze = 5, Recon = 10, Bomber = 15 }

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("MenuRemotes")
local teamSelect = remotes:WaitForChild("TeamSelect")
local droneSelect = remotes:WaitForChild("DroneSelect")

local COLORS = {
	bg = Color3.fromRGB(10, 12, 10),
	panel = Color3.fromRGB(22, 26, 22),
	panelLight = Color3.fromRGB(32, 38, 32),
	text = Color3.fromRGB(235, 235, 225),
	dim = Color3.fromRGB(150, 155, 150),
	blue = Color3.fromRGB(52, 110, 235),
	blueDark = Color3.fromRGB(22, 40, 80),
	red = Color3.fromRGB(220, 55, 50),
	redDark = Color3.fromRGB(75, 22, 20),
	amber = Color3.fromRGB(255, 170, 60),
	green = Color3.fromRGB(120, 200, 110),
}

--------------------------------------------------------------------
-- style helpers
--------------------------------------------------------------------

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = obj
	return c
end

local function stroke(obj, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = obj
	return s
end

local function gradient(obj, c1, c2, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c1, c2)
	g.Rotation = rotation or 90
	g.Parent = obj
	return g
end

local function label(parent, text, size, position, anchor, textSize, font, color)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.AnchorPoint = anchor
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.Gotham
	l.TextSize = textSize
	l.TextColor3 = color or COLORS.text
	l.Text = text
	l.Parent = parent
	return l
end

--------------------------------------------------------------------
-- root gui
--------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DroneWarMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------
-- 1) LOADING SCREEN
--------------------------------------------------------------------

local loading = Instance.new("CanvasGroup")
loading.Name = "Loading"
loading.Size = UDim2.new(1, 0, 1, 0)
loading.BackgroundColor3 = COLORS.bg
loading.BorderSizePixel = 0
loading.Parent = gui

local loadTitle = label(loading, "DRONE WAR", UDim2.new(1, 0, 0, 90), UDim2.new(0.5, 0, 0.1, 0), Vector2.new(0.5, 0), 76, Enum.Font.GothamBlack)
gradient(loadTitle, Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 130, 120), 90)

label(loading, "an fpv warfare experience", UDim2.new(1, 0, 0, 24), UDim2.new(0.5, 0, 0.1, 92), Vector2.new(0.5, 0), 16, Enum.Font.Gotham, COLORS.dim)

local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(0, 420, 0, 6)
barBack.Position = UDim2.new(0.5, 0, 0.58, 0)
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.BackgroundColor3 = Color3.fromRGB(35, 40, 35)
barBack.BorderSizePixel = 0
barBack.Parent = loading
corner(barBack, 3)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = COLORS.amber
barFill.BorderSizePixel = 0
barFill.Parent = barBack
corner(barFill, 3)

local loadStatus = label(loading, "loading battlefield...", UDim2.new(1, 0, 0, 20), UDim2.new(0.5, 0, 0.58, 22), Vector2.new(0.5, 0), 14, Enum.Font.Code, COLORS.dim)

local LOAD_LINES = {
	"loading battlefield...",
	"spinning up rotors...",
	"charging batteries...",
	"arming warheads...",
	"linking video feed...",
	"ready.",
}

--------------------------------------------------------------------
-- 2) TEAM SELECT
--------------------------------------------------------------------

local teamMenu = Instance.new("CanvasGroup")
teamMenu.Name = "TeamMenu"
teamMenu.Size = UDim2.new(1, 0, 1, 0)
teamMenu.BackgroundColor3 = COLORS.bg
teamMenu.BackgroundTransparency = 0.25
teamMenu.BorderSizePixel = 0
teamMenu.Visible = false
teamMenu.Parent = gui

local tsTitle = label(teamMenu, "DRONE WAR", UDim2.new(1, 0, 0, 56), UDim2.new(0.5, 0, 0.08, 0), Vector2.new(0.5, 0), 48, Enum.Font.GothamBlack)
gradient(tsTitle, Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 130, 120), 90)
label(teamMenu, "choose your side", UDim2.new(1, 0, 0, 22), UDim2.new(0.5, 0, 0.08, 58), Vector2.new(0.5, 0), 16, Enum.Font.Gotham, COLORS.dim)

local function makeTeamCard(teamName, accent, accentDark, xScale)
	local card = Instance.new("TextButton")
	card.Name = teamName .. "Card"
	card.Size = UDim2.new(0, 250, 0, 320)
	card.Position = UDim2.new(xScale, 0, 0.52, 0)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = COLORS.panel
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.Parent = teamMenu
	corner(card, 16)
	gradient(card, COLORS.panelLight, accentDark, 130)
	local cardStroke = stroke(card, accent, 2, 0.5)

	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	label(card, "TEAM", UDim2.new(1, 0, 0, 22), UDim2.new(0.5, 0, 0, 38), Vector2.new(0.5, 0), 16, Enum.Font.GothamBold, COLORS.dim)
	local nameLabel = label(card, teamName:upper(), UDim2.new(1, 0, 0, 52), UDim2.new(0.5, 0, 0, 60), Vector2.new(0.5, 0), 46, Enum.Font.GothamBlack, accent)

	-- divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0.6, 0, 0, 2)
	divider.Position = UDim2.new(0.5, 0, 0, 130)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = accent
	divider.BackgroundTransparency = 0.6
	divider.BorderSizePixel = 0
	divider.Parent = card

	local countLabel = label(card, "0 PLAYERS", UDim2.new(1, 0, 0, 34), UDim2.new(0.5, 0, 0, 156), Vector2.new(0.5, 0), 26, Enum.Font.Code, COLORS.text)
	label(card, "spawns at the " .. teamName:lower() .. " checkpoint", UDim2.new(1, -20, 0, 20), UDim2.new(0.5, 0, 0, 196), Vector2.new(0.5, 0), 13, Enum.Font.Gotham, COLORS.dim)

	local joinLabel = label(card, "CLICK TO DEPLOY", UDim2.new(1, 0, 0, 24), UDim2.new(0.5, 0, 1, -46), Vector2.new(0.5, 0), 15, Enum.Font.GothamBold, accent)
	joinLabel.TextTransparency = 0.3

	card.MouseEnter:Connect(function()
		TweenService:Create(cardScale, TweenInfo.new(0.15), { Scale = 1.05 }):Play()
		TweenService:Create(cardStroke, TweenInfo.new(0.15), { Transparency = 0 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(cardScale, TweenInfo.new(0.15), { Scale = 1 }):Play()
		TweenService:Create(cardStroke, TweenInfo.new(0.15), { Transparency = 0.5 }):Play()
	end)

	return card, countLabel
end

local blueCard, blueCount = makeTeamCard("Blue", COLORS.blue, COLORS.blueDark, 0.36)
local redCard, redCount = makeTeamCard("Red", COLORS.red, COLORS.redDark, 0.64)

label(teamMenu, "press M to open this menu again", UDim2.new(1, 0, 0, 18), UDim2.new(0.5, 0, 1, -34), Vector2.new(0.5, 0), 13, Enum.Font.Gotham, COLORS.dim)

-- live team counts
task.spawn(function()
	while gui.Parent do
		local blueTeam = Teams:FindFirstChild("Blue")
		local redTeam = Teams:FindFirstChild("Red")
		local b = blueTeam and #blueTeam:GetPlayers() or 0
		local r = redTeam and #redTeam:GetPlayers() or 0
		blueCount.Text = b .. (b == 1 and " PLAYER" or " PLAYERS")
		redCount.Text = r .. (r == 1 and " PLAYER" or " PLAYERS")
		task.wait(1)
	end
end)

--------------------------------------------------------------------
-- 3) SIDE TABS + slide-out drone panel
--------------------------------------------------------------------

local sideTabs = Instance.new("Frame")
sideTabs.Name = "SideTabs"
sideTabs.Size = UDim2.new(0, 46, 0, 200)
sideTabs.Position = UDim2.new(0, 0, 0.5, 0)
sideTabs.AnchorPoint = Vector2.new(0, 0.5)
sideTabs.BackgroundTransparency = 1
sideTabs.Visible = false
sideTabs.Parent = gui

local function makeTab(text, yOffset, accent)
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0, 42, 0, 86)
	tab.Position = UDim2.new(0, 0, 0, yOffset)
	tab.BackgroundColor3 = COLORS.panel
	tab.BackgroundTransparency = 0.15
	tab.BorderSizePixel = 0
	tab.Font = Enum.Font.GothamBold
	tab.TextSize = 15
	tab.TextColor3 = accent
	tab.Text = text
	tab.Parent = sideTabs
	corner(tab, 8)
	stroke(tab, accent, 1, 0.6)
	return tab
end

local dronesTab = makeTab("🛩", 0, COLORS.amber)
local dronesTabText = label(dronesTab, "D\nR\nO\nN\nE\nS", UDim2.new(1, 0, 1, -30), UDim2.new(0.5, 0, 0, 28), Vector2.new(0.5, 0), 11, Enum.Font.GothamBold, COLORS.amber)
local teamsTab = makeTab("⚑", 96, COLORS.dim)
local teamsTabText = label(teamsTab, "T\nE\nA\nM\nS", UDim2.new(1, 0, 1, -30), UDim2.new(0.5, 0, 0, 28), Vector2.new(0.5, 0), 11, Enum.Font.GothamBold, COLORS.dim)

-- slide-out drone panel
local PANEL_HIDDEN = UDim2.new(0, -340, 0.5, 0)
local PANEL_SHOWN = UDim2.new(0, 56, 0.5, 0)

local dronePanel = Instance.new("Frame")
dronePanel.Name = "DronePanel"
dronePanel.Size = UDim2.new(0, 320, 0, 530)
dronePanel.Position = PANEL_HIDDEN
dronePanel.AnchorPoint = Vector2.new(0, 0.5)
dronePanel.BackgroundColor3 = COLORS.panel
dronePanel.BorderSizePixel = 0
dronePanel.Parent = gui
corner(dronePanel, 14)
stroke(dronePanel, COLORS.amber, 1, 0.5)
gradient(dronePanel, COLORS.panelLight, COLORS.panel, 120)

label(dronePanel, "🛩 DRONE ARSENAL", UDim2.new(1, 0, 0, 34), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0), 22, Enum.Font.GothamBlack)

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 28, 0, 28)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.BackgroundColor3 = COLORS.panelLight
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.TextColor3 = COLORS.dim
closeButton.Text = "✕"
closeButton.BorderSizePixel = 0
closeButton.Parent = dronePanel
corner(closeButton, 6)

local droneCards = {} -- [kind] = { lock = Frame }

local function makeDroneCard(name, desc, accent, yOffset, kind)
	local card = Instance.new("TextButton")
	card.Size = UDim2.new(1, -32, 0, 120)
	card.Position = UDim2.new(0.5, 0, 0, yOffset)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.BackgroundColor3 = COLORS.panelLight
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.Parent = dronePanel
	corner(card, 10)
	local cardStroke = stroke(card, accent, 1.5, 0.6)

	label(card, name, UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 0, 12), Vector2.new(0, 0), 20, Enum.Font.GothamBold, accent).TextXAlignment = Enum.TextXAlignment.Left
	local descLabel = label(card, desc, UDim2.new(1, -24, 0, 54), UDim2.new(0, 12, 0, 42), Vector2.new(0, 0), 13, Enum.Font.Gotham, COLORS.dim)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true

	card.MouseEnter:Connect(function()
		TweenService:Create(cardStroke, TweenInfo.new(0.15), { Transparency = 0 }):Play()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(42, 48, 42) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(cardStroke, TweenInfo.new(0.15), { Transparency = 0.6 }):Play()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = COLORS.panelLight }):Play()
	end)

	-- lock overlay: shown until the level is reached or it's bought with Robux
	local lock = Instance.new("Frame")
	lock.Name = "Lock"
	lock.Size = UDim2.new(1, 0, 1, 0)
	lock.BackgroundColor3 = Color3.fromRGB(10, 12, 10)
	lock.BackgroundTransparency = 0.2
	lock.BorderSizePixel = 0
	lock.ZIndex = 5
	lock.Visible = false
	lock.Parent = card
	corner(lock, 10)

	local lockText = label(lock, "🔒 UNLOCKS AT LEVEL " .. (LEVEL_REQUIREMENTS[kind] or 1),
		UDim2.new(1, -20, 0, 26), UDim2.new(0.5, 0, 0, 22), Vector2.new(0.5, 0), 17, Enum.Font.GothamBold, Color3.fromRGB(225, 225, 215))
	lockText.ZIndex = 6

	local buyButton = Instance.new("TextButton")
	buyButton.Size = UDim2.new(0, 200, 0, 34)
	buyButton.Position = UDim2.new(0.5, 0, 1, -14)
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
	buyButton.Font = Enum.Font.GothamBold
	buyButton.TextSize = 16
	buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyButton.Text = "UNLOCK NOW —  " .. (ROBUX_PRICES[kind] or "?") .. " R$"
	buyButton.BorderSizePixel = 0
	buyButton.ZIndex = 6
	buyButton.Parent = lock
	corner(buyButton, 8)

	buyButton.MouseButton1Click:Connect(function()
		local productId = ReplicatedStorage:GetAttribute("Product" .. kind)
		if productId and productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		else
			lockText.Text = "⚠ purchase not set up yet"
			task.delay(2, function()
				lockText.Text = "🔒 UNLOCKS AT LEVEL " .. (LEVEL_REQUIREMENTS[kind] or 1)
			end)
		end
	end)

	droneCards[kind] = { lock = lock }
	return card
end

local function isUnlocked(kind)
	local level = player:GetAttribute("Level") or 1
	local required = LEVEL_REQUIREMENTS[kind] or 1
	return level >= required or player:GetAttribute("Owns" .. kind) == true
end

-- keep the lock overlays in sync with level / purchases
task.spawn(function()
	while gui.Parent do
		for kind, entry in droneCards do
			entry.lock.Visible = not isUnlocked(kind)
		end
		task.wait(1)
	end
end)

local kamikazeCard = makeDroneCard(
	"💥 FPV KAMIKAZE",
	"One-way attack drone. Fly it straight into the target — it detonates on impact. Fast and agile.",
	COLORS.amber, 64, "Kamikaze"
)
local bomberCard = makeDroneCard(
	"💣 BOMBER",
	"Carries 3 grenades — press F to drop, C for the bomb-sight camera, Z to zoom. Slower but reusable.",
	COLORS.green, 196, "Bomber"
)
local reconCard = makeDroneCard(
	"🔭 RECON",
	"Eyes in the sky. 7-min battery, double range, quiet motor. T marks enemies for your whole team, V is thermal vision.",
	Color3.fromRGB(120, 170, 255), 328, "Recon"
)

local droneStatus = label(dronePanel, "", UDim2.new(1, 0, 0, 22), UDim2.new(0.5, 0, 1, -56), Vector2.new(0.5, 0), 14, Enum.Font.Gotham, COLORS.green)
label(dronePanel, "delivered right in front of you", UDim2.new(1, 0, 0, 18), UDim2.new(0.5, 0, 1, -30), Vector2.new(0.5, 0), 12, Enum.Font.Gotham, COLORS.dim)

--------------------------------------------------------------------
-- behavior
--------------------------------------------------------------------

local panelOpen = false

local function setPanel(open)
	panelOpen = open
	TweenService:Create(dronePanel, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = open and PANEL_SHOWN or PANEL_HIDDEN,
	}):Play()
	if open then
		droneStatus.Text = ""
	end
end

local function showTeamMenu(show)
	if show then
		teamMenu.GroupTransparency = 1
		teamMenu.Visible = true
		TweenService:Create(teamMenu, TweenInfo.new(0.3), { GroupTransparency = 0 }):Play()
		setPanel(false)
	else
		local tween = TweenService:Create(teamMenu, TweenInfo.new(0.3), { GroupTransparency = 1 })
		tween.Completed:Once(function()
			teamMenu.Visible = false
		end)
		tween:Play()
	end
end

local function pickTeam(teamName)
	teamSelect:FireServer(teamName)
	showTeamMenu(false)
	sideTabs.Visible = true
end

blueCard.MouseButton1Click:Connect(function()
	pickTeam("Blue")
end)
redCard.MouseButton1Click:Connect(function()
	pickTeam("Red")
end)

dronesTab.MouseButton1Click:Connect(function()
	setPanel(not panelOpen)
end)
closeButton.MouseButton1Click:Connect(function()
	setPanel(false)
end)
teamsTab.MouseButton1Click:Connect(function()
	showTeamMenu(true)
end)

local function orderDrone(kind, statusText)
	if not isUnlocked(kind) then
		droneStatus.Text = "🔒 reach level " .. (LEVEL_REQUIREMENTS[kind] or 1) .. " or unlock with Robux"
		droneStatus.TextColor3 = Color3.fromRGB(255, 140, 80)
		return
	end
	droneSelect:FireServer(kind)
	droneStatus.Text = statusText
	droneStatus.TextColor3 = COLORS.green
	task.delay(1.2, function()
		if panelOpen then
			setPanel(false)
		end
	end)
end

kamikazeCard.MouseButton1Click:Connect(function()
	orderDrone("Kamikaze", "✔ kamikaze drone delivered!")
end)
bomberCard.MouseButton1Click:Connect(function()
	orderDrone("Bomber", "✔ bomber drone delivered!")
end)
reconCard.MouseButton1Click:Connect(function()
	orderDrone("Recon", "✔ recon drone delivered!")
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		if teamMenu.Visible then
			showTeamMenu(false)
		else
			showTeamMenu(true)
		end
	end
end)

--------------------------------------------------------------------
-- run the loading sequence, then show team select
--------------------------------------------------------------------

task.spawn(function()
	-- cycle status lines while the bar fills
	local barTween = TweenService:Create(barFill, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Size = UDim2.new(1, 0, 1, 0),
	})
	barTween:Play()

	for i, line in LOAD_LINES do
		loadStatus.Text = line
		task.wait(2.8 / #LOAD_LINES)
	end

	-- fade the loading screen away, reveal team select
	teamMenu.GroupTransparency = 1
	teamMenu.Visible = true
	TweenService:Create(teamMenu, TweenInfo.new(0.5), { GroupTransparency = 0 }):Play()
	local fade = TweenService:Create(loading, TweenInfo.new(0.5), { GroupTransparency = 1 })
	fade.Completed:Once(function()
		loading:Destroy()
	end)
	fade:Play()
end)
