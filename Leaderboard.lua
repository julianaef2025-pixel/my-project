-- Leaderboard.lua
-- Regular Script — put in ServerScriptService.
-- A physical "TOP EATERS" board showing the top 10 burger-eaters OF ALL TIME.
-- Lifetime totals: rebirths don't erase your score. Saves globally.
--
-- SETUP: insert a Part into your map (this is the board — make it big and flat,
-- like Size 12, 8, 1) and name it exactly: LeaderboardPart
-- Needs "Enable Studio Access to API Services" ON (same as saving).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- ===== SETTINGS =====
local REFRESH_TIME = 60  -- seconds between board updates
local TOP_COUNT = 10     -- how many players to show
-- ====================

local orderedStore = DataStoreService:GetOrderedDataStore("BurgerLeaderboard_v1")

-- ===== FIND OR CREATE THE BOARD =====
local boardPart = workspace:FindFirstChild("LeaderboardPart", true)
if not boardPart then
	warn("Leaderboard: no Part named 'LeaderboardPart' found — creating one near spawn. Move it where you want!")
	boardPart = Instance.new("Part")
	boardPart.Name = "LeaderboardPart"
	boardPart.Size = Vector3.new(12, 8, 1)
	boardPart.Position = Vector3.new(0, 6, -20)
	boardPart.Anchored = true
	boardPart.Color = Color3.fromRGB(40, 40, 55)
	boardPart.Parent = workspace
end

local gui = Instance.new("SurfaceGui")
gui.Face = Enum.NormalId.Front
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 40
gui.Parent = boardPart

local bg = Instance.new("Frame")
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
bg.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0.15, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.Text = "🏆 TOP BURGER EATERS 🍔"
title.TextColor3 = Color3.fromRGB(255, 200, 60)
title.Parent = bg

local list = Instance.new("Frame")
list.Position = UDim2.new(0.05, 0, 0.17, 0)
list.Size = UDim2.new(0.9, 0, 0.8, 0)
list.BackgroundTransparency = 1
list.Parent = bg

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = list

local rows = {}
for i = 1, TOP_COUNT do
	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, 0, 1 / TOP_COUNT, -4)
	row.BackgroundColor3 = (i == 1 and Color3.fromRGB(80, 65, 20))
		or (i == 2 and Color3.fromRGB(60, 60, 70))
		or (i == 3 and Color3.fromRGB(70, 50, 35))
		or Color3.fromRGB(45, 45, 60)
	row.Font = Enum.Font.FredokaOne
	row.TextScaled = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = (i == 1 and Color3.fromRGB(255, 215, 80))
		or (i == 2 and Color3.fromRGB(210, 210, 220))
		or (i == 3 and Color3.fromRGB(220, 150, 100))
		or Color3.fromRGB(255, 255, 255)
	row.Text = "  " .. i .. ".  ---"
	row.LayoutOrder = i
	row.Parent = list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
	rows[i] = row
end

-- ===== TRACK LIFETIME EATEN (rebirths can't erase it) =====
-- watches each player's TotalEaten and adds every INCREASE to a lifetime total
local lifetime = {} -- [player] = number

local function watchPlayer(player)
	-- load their saved lifetime score
	local ok, saved = pcall(function()
		return orderedStore:GetAsync("u_" .. player.UserId)
	end)
	lifetime[player] = (ok and saved) or 0

	local function watchTotal(totalEaten)
		local last = totalEaten.Value
		totalEaten.Changed:Connect(function(newValue)
			if newValue > last then
				lifetime[player] += (newValue - last)
			end
			last = newValue -- rebirth resets just update 'last', no loss
		end)
	end

	local totalEaten = player:FindFirstChild("TotalEaten")
	if totalEaten then
		watchTotal(totalEaten)
	else
		player.ChildAdded:Connect(function(child)
			if child.Name == "TotalEaten" and child:IsA("IntValue") then
				watchTotal(child)
			end
		end)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

-- ===== SAVE SCORES =====
local function saveScore(player)
	local score = lifetime[player]
	if not score or score <= 0 then return end
	pcall(function()
		orderedStore:SetAsync("u_" .. player.UserId, score)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	saveScore(player)
	lifetime[player] = nil
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveScore(player)
	end
end)

-- ===== UPDATE THE BOARD =====
local nameCache = {}

local function getName(userId)
	if nameCache[userId] then return nameCache[userId] end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = (ok and name) or "???"
	return nameCache[userId]
end

local function refreshBoard()
	-- save everyone first so the board includes players currently online
	for _, player in Players:GetPlayers() do
		saveScore(player)
	end

	local ok, pages = pcall(function()
		return orderedStore:GetSortedAsync(false, TOP_COUNT) -- false = biggest first
	end)
	if not ok then
		warn("Leaderboard: couldn't fetch scores (API services on?)")
		return
	end

	local top = pages:GetCurrentPage()
	for i = 1, TOP_COUNT do
		local entry = top[i]
		if entry then
			local userId = tonumber(entry.key:match("%d+"))
			local name = userId and getName(userId) or "???"
			rows[i].Text = "  " .. i .. ".  " .. name .. "  —  " .. entry.value .. " 🍔"
		else
			rows[i].Text = "  " .. i .. ".  ---"
		end
	end
end

task.spawn(function()
	task.wait(3)
	while true do
		refreshBoard()
		task.wait(REFRESH_TIME)
	end
end)
