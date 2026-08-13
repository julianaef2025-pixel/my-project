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
local LEVEL_REQUIREMENTS = { Kamikaze = 2, Recon = 4, Bomber = 7, RPG = 9 }
local ROBUX_PRICES = { Kamikaze = 5, Recon = 10, Bomber = 15, RPG = 20 }

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
-- 3) SIDE TABS + slide-out drone panel (v2 — the good-looking one)
--------------------------------------------------------------------

local sideTabs = Instance.new("Frame")
sideTabs.Name = "SideTabs"
sideTabs.Size = UDim2.new(0, 52, 0, 210)
sideTabs.Position = UDim2.new(0, 0, 0.5, 0)
sideTabs.AnchorPoint = Vector2.new(0, 0.5)
sideTabs.BackgroundTransparency = 1
sideTabs.Visible = false
sideTabs.Parent = gui

local function makeTab(icon, letters, yOffset, accent)
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0, 44, 0, 96)
	tab.Position = UDim2.new(0, 0, 0, yOffset)
	tab.BackgroundColor3 = COLORS.panel
	tab.BackgroundTransparency = 0.1
	tab.BorderSizePixel = 0
	tab.Text = ""
	tab.AutoButtonColor = false
	tab.Parent = sideTabs
	corner(tab, 10)
	local tabStroke = stroke(tab, accent, 1.5, 0.55)

	local iconLabel = label(tab, icon, UDim2.new(1, 0, 0, 26), UDim2.new(0.5, 0, 0, 6), Vector2.new(0.5, 0), 18, Enum.Font.GothamBold, accent)
	local lettersLabel = label(tab, letters, UDim2.new(1, 0, 1, -34), UDim2.new(0.5, 0, 0, 32), Vector2.new(0.5, 0), 11, Enum.Font.GothamBold, accent)

	tab.MouseEnter:Connect(function()
		TweenService:Create(tab, TweenInfo.new(0.15), { Position = UDim2.new(0, 6, 0, yOffset), BackgroundTransparency = 0 }):Play()
		TweenService:Create(tabStroke, TweenInfo.new(0.15), { Transparency = 0.1 }):Play()
	end)
	tab.MouseLeave:Connect(function()
		TweenService:Create(tab, TweenInfo.new(0.15), { Position = UDim2.new(0, 0, 0, yOffset), BackgroundTransparency = 0.1 }):Play()
		TweenService:Create(tabStroke, TweenInfo.new(0.15), { Transparency = 0.55 }):Play()
	end)

	return tab, tabStroke
end

local dronesTab, dronesTabStroke = makeTab("🛩", "D\nR\nO\nN\nE\nS", 0, COLORS.amber)
local teamsTab = makeTab("⚑", "T\nE\nA\nM\nS", 108, COLORS.dim)

-- slide-out drone panel (CanvasGroup so it can fade as it slides)
local PANEL_HIDDEN = UDim2.new(0, -400, 0.5, 0)
local PANEL_SHOWN = UDim2.new(0, 62, 0.5, 0)

local dronePanel = Instance.new("CanvasGroup")
dronePanel.Name = "DronePanel"
dronePanel.Size = UDim2.new(0, 356, 0, 760)
dronePanel.Position = PANEL_HIDDEN
dronePanel.AnchorPoint = Vector2.new(0, 0.5)
dronePanel.BackgroundColor3 = COLORS.panel
dronePanel.BorderSizePixel = 0
dronePanel.GroupTransparency = 1
dronePanel.Parent = gui
corner(dronePanel, 16)
stroke(dronePanel, COLORS.amber, 1.5, 0.55)
gradient(dronePanel, Color3.fromRGB(30, 36, 30), Color3.fromRGB(16, 20, 16), 115)

-- header
local headerTitle = label(dronePanel, "DRONE ARSENAL", UDim2.new(1, -60, 0, 30), UDim2.new(0, 20, 0, 16), Vector2.new(0, 0), 24, Enum.Font.GothamBlack)
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
gradient(headerTitle, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 160, 150), 90)
local headerSub = label(dronePanel, "choose your loadout, pilot", UDim2.new(1, -60, 0, 16), UDim2.new(0, 20, 0, 46), Vector2.new(0, 0), 13, Enum.Font.Gotham, COLORS.dim)
headerSub.TextXAlignment = Enum.TextXAlignment.Left

local headerLine = Instance.new("Frame")
headerLine.Size = UDim2.new(1, -40, 0, 1)
headerLine.Position = UDim2.new(0, 20, 0, 70)
headerLine.BackgroundColor3 = COLORS.amber
headerLine.BackgroundTransparency = 0.7
headerLine.BorderSizePixel = 0
headerLine.Parent = dronePanel

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.BackgroundColor3 = COLORS.panelLight
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 15
closeButton.TextColor3 = COLORS.dim
closeButton.Text = "✕"
closeButton.BorderSizePixel = 0
closeButton.Parent = dronePanel
corner(closeButton, 15)

-- forward declared so card buttons can write to it
local droneStatus

local droneCards = {} -- [kind] = refs for the refresh loop

local function makeDroneCard(config)
	-- config: kind, name, icon, desc, accent, accentDark, chips, yOffset
	local card = Instance.new("TextButton")
	card.Name = config.kind .. "Card"
	card.Size = UDim2.new(1, -32, 0, 150)
	card.Position = UDim2.new(0.5, 0, 0, config.yOffset)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.BackgroundColor3 = COLORS.panelLight
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.Parent = dronePanel
	corner(card, 12)
	gradient(card, Color3.fromRGB(38, 44, 38), Color3.fromRGB(26, 31, 26), 100)
	local cardStroke = stroke(card, config.accent, 1.5, 0.6)

	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	-- icon badge
	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.new(0, 52, 0, 52)
	iconBox.Position = UDim2.new(0, 14, 0, 14)
	iconBox.BackgroundColor3 = config.accentDark
	iconBox.BorderSizePixel = 0
	iconBox.Parent = card
	corner(iconBox, 10)
	stroke(iconBox, config.accent, 1, 0.5)
	local iconLabel = label(iconBox, config.icon, UDim2.new(1, 0, 1, 0), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), 26)

	-- name + stat chips
	local nameLabel = label(card, config.name, UDim2.new(1, -160, 0, 24), UDim2.new(0, 78, 0, 14), Vector2.new(0, 0), 19, Enum.Font.GothamBlack, config.accent)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	local chipRow = Instance.new("Frame")
	chipRow.Size = UDim2.new(1, -92, 0, 18)
	chipRow.Position = UDim2.new(0, 78, 0, 42)
	chipRow.BackgroundTransparency = 1
	chipRow.Parent = card
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.Parent = chipRow

	for _, chipText in config.chips do
		local chip = Instance.new("TextLabel")
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.new(0, 0, 1, 0)
		chip.BackgroundColor3 = Color3.fromRGB(18, 22, 18)
		chip.BackgroundTransparency = 0.2
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 10
		chip.TextColor3 = config.accent
		chip.Text = " " .. chipText .. " "
		chip.BorderSizePixel = 0
		chip.Parent = chipRow
		corner(chip, 4)
	end

	-- description
	local descLabel = label(card, config.desc, UDim2.new(1, -28, 0, 34), UDim2.new(0, 14, 0, 72), Vector2.new(0, 0), 12, Enum.Font.Gotham, COLORS.dim)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true

	-- bottom row: status text left, action button right
	local statusLabel = label(card, "", UDim2.new(1, -140, 0, 30), UDim2.new(0, 14, 1, -40), Vector2.new(0, 0), 12, Enum.Font.GothamBold, COLORS.dim)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left

	local deployBtn = Instance.new("TextButton")
	deployBtn.Size = UDim2.new(0, 108, 0, 32)
	deployBtn.Position = UDim2.new(1, -12, 1, -10)
	deployBtn.AnchorPoint = Vector2.new(1, 1)
	deployBtn.BackgroundColor3 = config.accent
	deployBtn.Font = Enum.Font.GothamBlack
	deployBtn.TextSize = 14
	deployBtn.TextColor3 = Color3.fromRGB(15, 18, 15)
	deployBtn.Text = "DEPLOY ▸"
	deployBtn.BorderSizePixel = 0
	deployBtn.Visible = false
	deployBtn.Parent = card
	corner(deployBtn, 8)

	-- compact unlock pill (bottom-right, doesn't cover the card)
	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0, 108, 0, 32)
	buyBtn.Position = UDim2.new(1, -12, 1, -10)
	buyBtn.AnchorPoint = Vector2.new(1, 1)
	buyBtn.BackgroundColor3 = Color3.fromRGB(52, 165, 82)
	buyBtn.Font = Enum.Font.GothamBlack
	buyBtn.TextSize = 14
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.Text = "⚡ " .. (ROBUX_PRICES[config.kind] or "?") .. " R$"
	buyBtn.BorderSizePixel = 0
	buyBtn.Visible = false
	buyBtn.Parent = card
	corner(buyBtn, 8)
	stroke(buyBtn, Color3.fromRGB(110, 230, 140), 1, 0.5)

	-- hover: card lifts slightly, stroke brightens
	card.MouseEnter:Connect(function()
		TweenService:Create(cardScale, TweenInfo.new(0.12), { Scale = 1.02 }):Play()
		TweenService:Create(cardStroke, TweenInfo.new(0.12), { Transparency = 0.15 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(cardScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		TweenService:Create(cardStroke, TweenInfo.new(0.12), { Transparency = 0.6 }):Play()
	end)

	buyBtn.MouseButton1Click:Connect(function()
		local productId = ReplicatedStorage:GetAttribute("Product" .. config.kind)
		if productId and productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		elseif droneStatus then
			droneStatus.Text = "⚠ purchase not set up yet"
			droneStatus.TextColor3 = Color3.fromRGB(255, 140, 80)
		end
	end)

	droneCards[config.kind] = {
		card = card,
		scale = cardScale,
		stroke = cardStroke,
		accent = config.accent,
		accentDark = config.accentDark,
		iconBox = iconBox,
		iconLabel = iconLabel,
		nameLabel = nameLabel,
		statusLabel = statusLabel,
		deployBtn = deployBtn,
		buyBtn = buyBtn,
	}
	return card, deployBtn
end

local function isUnlocked(kind)
	local level = player:GetAttribute("Level") or 1
	local required = LEVEL_REQUIREMENTS[kind] or 1
	return level >= required or player:GetAttribute("Owns" .. kind) == true
end

-- restyle every card to match its live locked/unlocked state
local LOCKED_GRAY = Color3.fromRGB(120, 126, 120)
local function refreshCards()
	for kind, c in droneCards do
		local unlocked = isUnlocked(kind)
		c.deployBtn.Visible = unlocked
		c.buyBtn.Visible = not unlocked
		if unlocked then
			c.nameLabel.TextColor3 = c.accent
			c.iconBox.BackgroundColor3 = c.accentDark
			c.iconLabel.TextTransparency = 0
			c.stroke.Color = c.accent
			c.statusLabel.Text = "✓ UNLOCKED"
			c.statusLabel.TextColor3 = Color3.fromRGB(120, 210, 130)
		else
			c.nameLabel.TextColor3 = LOCKED_GRAY
			c.iconBox.BackgroundColor3 = Color3.fromRGB(34, 38, 34)
			c.iconLabel.TextTransparency = 0.45
			c.stroke.Color = LOCKED_GRAY
			c.statusLabel.Text = "🔒 UNLOCKS AT LEVEL " .. (LEVEL_REQUIREMENTS[kind] or 1)
			c.statusLabel.TextColor3 = LOCKED_GRAY
		end
	end
end

task.spawn(function()
	while gui.Parent do
		refreshCards()
		task.wait(1)
	end
end)

local kamikazeCard, kamikazeDeploy = makeDroneCard({
	kind = "Kamikaze",
	name = "FPV KAMIKAZE",
	icon = "💥",
	desc = "One-way attack drone. Fly it straight into the target — detonates on impact.",
	accent = COLORS.amber,
	accentDark = Color3.fromRGB(70, 48, 18),
	chips = { "ONE-WAY", "FAST", "IMPACT WARHEAD" },
	yOffset = 86,
})
local bomberCard, bomberDeploy = makeDroneCard({
	kind = "Bomber",
	name = "BOMBER",
	icon = "💣",
	desc = "Drops grenades from above. F to drop, C for bomb cam, Z to zoom. Rearm at base.",
	accent = COLORS.green,
	accentDark = Color3.fromRGB(30, 55, 30),
	chips = { "3× GRENADES", "BOMB CAM", "REARMS" },
	yOffset = 250,
})
local reconCard, reconDeploy = makeDroneCard({
	kind = "Recon",
	name = "RECON",
	icon = "🔭",
	desc = "Eyes in the sky. C for the stabilized gimbal, Z to zoom, T marks targets, V is thermal.",
	accent = Color3.fromRGB(120, 170, 255),
	accentDark = Color3.fromRGB(25, 38, 70),
	chips = { "7 MIN", "15× ZOOM", "THERMAL", "MARKS" },
	yOffset = 414,
})
local rpgCard, rpgDeploy = makeDroneCard({
	kind = "RPG",
	name = "RPG STRIKER",
	icon = "🚀",
	desc = "Rocket launcher on wings. F fires a rocket straight where you aim — big blast, big hole. Reload at base.",
	accent = Color3.fromRGB(255, 110, 90),
	accentDark = Color3.fromRGB(70, 26, 20),
	chips = { "2× ROCKETS", "AIMED SHOT", "BIG BOOM" },
	yOffset = 578,
})

droneStatus = label(dronePanel, "", UDim2.new(1, -40, 0, 20), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1), 13, Enum.Font.GothamBold, COLORS.green)

--------------------------------------------------------------------
-- behavior
--------------------------------------------------------------------

local panelOpen = false

local function setPanel(open)
	panelOpen = open
	TweenService:Create(dronePanel, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = open and PANEL_SHOWN or PANEL_HIDDEN,
		GroupTransparency = open and 0 or 1,
	}):Play()
	TweenService:Create(dronesTabStroke, TweenInfo.new(0.2), { Transparency = open and 0 or 0.55 }):Play()
	if open then
		droneStatus.Text = ""
		refreshCards()
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
	-- click punch on the card
	local c = droneCards[kind]
	if c then
		TweenService:Create(c.scale, TweenInfo.new(0.08), { Scale = 0.97 }):Play()
		task.delay(0.09, function()
			TweenService:Create(c.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
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

kamikazeDeploy.MouseButton1Click:Connect(function()
	orderDrone("Kamikaze", "✔ kamikaze delivered right in front of you")
end)
bomberDeploy.MouseButton1Click:Connect(function()
	orderDrone("Bomber", "✔ bomber delivered right in front of you")
end)
reconDeploy.MouseButton1Click:Connect(function()
	orderDrone("Recon", "✔ recon delivered right in front of you")
end)
rpgDeploy.MouseButton1Click:Connect(function()
	orderDrone("RPG", "✔ rpg striker delivered right in front of you")
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

	for _, line in LOAD_LINES do
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
