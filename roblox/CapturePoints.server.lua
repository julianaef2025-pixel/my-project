--[[
	CAPTURE POINTS — SERVER script (ServerScriptService)
	A separate script: don't paste into the other scripts.

	Studio setup:
	- Create a Folder in Workspace named exactly "CapturePoints"
	- Put a flat Part where each objective should be, named "A", "B", "C"
	  (any number of points works — names become the letters shown)
	- The part's size sets the capture zone (its footprint), min radius 8

	How it plays:
	- Stand on a point to capture it for your team (faster with teammates)
	- Both teams present = contested, progress freezes
	- Defenders standing on their own point drain enemy progress
	- Captured points earn your team +1 score every few seconds
	- Beacon pillar + billboard + score HUD all update live, with a
	  capture animation when a point flips
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CAPTURE_TIME = 8 -- seconds for 1 player to flip a point
local MAX_CAPTURE_BOOST = 3 -- extra teammates speed it up, capped at this many
local DECAY_RATE = 12 -- progress lost per second when nobody is capturing
local SCORE_INTERVAL = 5 -- seconds between score ticks
local SCORE_PER_POINT = 1

local COLORS = {
	Neutral = Color3.fromRGB(170, 170, 170),
	Blue = Color3.fromRGB(60, 120, 255),
	Red = Color3.fromRGB(255, 70, 60),
}

local pointsFolder = workspace:WaitForChild("CapturePoints", 10)
if not pointsFolder then
	warn("[CapturePoints] No 'CapturePoints' folder in Workspace — create it and add parts named A, B, C")
	return
end

local teamScores = { Blue = 0, Red = 0 }
local points = {} -- list of point state tables

--------------------------------------------------------------------
-- build the beacon + billboard on each zone part
--------------------------------------------------------------------

local function buildPoint(zone)
	local radius = math.max(zone.Size.X, zone.Size.Z) / 2
	radius = math.max(radius, 8)
	local center = zone.Position

	zone.Anchored = true
	zone.CanCollide = true

	-- glowing base ring
	local ring = Instance.new("Part")
	ring.Name = "CaptureRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(center + Vector3.new(0, zone.Size.Y / 2 + 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Material = Enum.Material.Neon
	ring.Color = COLORS.Neutral
	ring.Transparency = 0.45
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = zone

	-- light pillar reaching into the sky
	local pillar = Instance.new("Part")
	pillar.Name = "CapturePillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(60, 2.5, 2.5)
	pillar.CFrame = CFrame.new(center + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	pillar.Material = Enum.Material.Neon
	pillar.Color = COLORS.Neutral
	pillar.Transparency = 0.55
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Parent = zone

	-- floating billboard: big letter + capture progress bar
	local board = Instance.new("BillboardGui")
	board.Name = "CaptureBoard"
	board.Size = UDim2.new(0, 120, 0, 110)
	board.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	board.AlwaysOnTop = true
	board.MaxDistance = 400
	board.Parent = zone

	local scale = Instance.new("UIScale")
	scale.Parent = board

	local letter = Instance.new("TextLabel")
	letter.Name = "Letter"
	letter.Size = UDim2.new(1, 0, 0, 70)
	letter.BackgroundTransparency = 1
	letter.Font = Enum.Font.GothamBlack
	letter.TextSize = 62
	letter.TextColor3 = COLORS.Neutral
	letter.TextStrokeTransparency = 0.4
	letter.Text = zone.Name
	letter.Parent = board

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Size = UDim2.new(1, -20, 0, 10)
	barBack.Position = UDim2.new(0, 10, 0, 78)
	barBack.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	barBack.BackgroundTransparency = 0.3
	barBack.BorderSizePixel = 0
	barBack.Parent = board

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = COLORS.Neutral
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack

	return {
		zone = zone,
		name = zone.Name,
		center = center,
		radius = radius,
		ring = ring,
		pillar = pillar,
		boardScale = scale,
		letter = letter,
		barFill = barFill,
		owner = "Neutral",
		capturingTeam = nil,
		progress = 0, -- 0..100 toward capturingTeam
	}
end

for _, zone in pointsFolder:GetChildren() do
	if zone:IsA("BasePart") then
		table.insert(points, buildPoint(zone))
	end
end
table.sort(points, function(a, b)
	return a.name < b.name
end)
if #points == 0 then
	warn("[CapturePoints] The CapturePoints folder has no parts — add parts named A, B, C")
	return
end
print("[CapturePoints] " .. #points .. " objective(s) ready")

--------------------------------------------------------------------
-- capture animation when a point flips
--------------------------------------------------------------------

local function playCaptureAnimation(point, teamName)
	local color = COLORS[teamName]

	-- pillar floods with the new color and pulses bright
	point.pillar.Color = color
	point.ring.Color = color
	point.letter.TextColor3 = color
	TweenService:Create(point.pillar, TweenInfo.new(0.3), { Transparency = 0.15 }):Play()
	task.delay(0.5, function()
		TweenService:Create(point.pillar, TweenInfo.new(1.2), { Transparency = 0.55 }):Play()
	end)

	-- expanding shockwave ring on the ground
	local pulse = point.ring:Clone()
	pulse.Name = "CapturePulse"
	pulse.Transparency = 0.2
	pulse.Parent = workspace
	TweenService:Create(pulse, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, point.radius * 6, point.radius * 6),
		Transparency = 1,
	}):Play()
	Debris:AddItem(pulse, 1)

	-- billboard letter punches big then settles
	TweenService:Create(point.boardScale, TweenInfo.new(0.15), { Scale = 1.5 }):Play()
	task.delay(0.2, function()
		TweenService:Create(point.boardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

--------------------------------------------------------------------
-- score HUD (top of every player's screen)
--------------------------------------------------------------------

local hudLabels = {} -- [player] = TextLabel

local function buildHud(player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CaptureHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 8)
	label.Size = UDim2.new(0, 420, 0, 26)
	label.BackgroundColor3 = Color3.fromRGB(15, 18, 15)
	label.BackgroundTransparency = 0.35
	label.Font = Enum.Font.Code
	label.TextSize = 18
	label.RichText = true
	label.TextColor3 = Color3.fromRGB(230, 230, 230)
	label.Text = ""
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	gui.Parent = player:WaitForChild("PlayerGui")
	hudLabels[player] = label
end

local function colorHex(color)
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function updateHud()
	local letters = {}
	for _, point in points do
		table.insert(letters, string.format('<font color="%s">%s</font>', colorHex(COLORS[point.owner]), point.name))
	end
	local text = string.format(
		'<font color="%s">BLUE %d</font>   %s   <font color="%s">%d RED</font>',
		colorHex(COLORS.Blue), teamScores.Blue,
		table.concat(letters, " "),
		colorHex(COLORS.Red), teamScores.Red
	)
	for player, label in hudLabels do
		if label.Parent then
			label.Text = text
		else
			hudLabels[player] = nil
		end
	end
end

Players.PlayerAdded:Connect(buildHud)
for _, player in Players:GetPlayers() do
	buildHud(player)
end
Players.PlayerRemoving:Connect(function(player)
	hudLabels[player] = nil
end)

--------------------------------------------------------------------
-- capture logic
--------------------------------------------------------------------

-- count alive players of each team standing on the point
local function countTeams(point)
	local blue, red = 0, 0
	for _, player in Players:GetPlayers() do
		local team = player.Team and player.Team.Name
		if team == "Blue" or team == "Red" then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and hrp then
				local offset = hrp.Position - point.center
				local flat = Vector2.new(offset.X, offset.Z)
				if flat.Magnitude <= point.radius and math.abs(offset.Y) <= 12 then
					if team == "Blue" then
						blue += 1
					else
						red += 1
					end
				end
			end
		end
	end
	return blue, red
end

local function updatePointVisuals(point)
	local barColor = point.capturingTeam and COLORS[point.capturingTeam] or COLORS[point.owner]
	point.barFill.BackgroundColor3 = barColor
	point.barFill.Size = UDim2.new(math.clamp(point.progress / 100, 0, 1), 0, 1, 0)
end

task.spawn(function()
	local scoreClock = 0
	while true do
		local dt = task.wait(0.25)
		scoreClock += dt

		for _, point in points do
			local blue, red = countTeams(point)
			local attackers, attackerTeam
			if blue > 0 and red == 0 then
				attackers, attackerTeam = blue, "Blue"
			elseif red > 0 and blue == 0 then
				attackers, attackerTeam = red, "Red"
			end

			if attackerTeam and attackerTeam ~= point.owner then
				-- enemies capturing
				if point.capturingTeam ~= attackerTeam then
					point.capturingTeam = attackerTeam
					point.progress = 0
				end
				local speed = (100 / CAPTURE_TIME) * math.min(attackers, MAX_CAPTURE_BOOST)
				point.progress += speed * dt
				if point.progress >= 100 then
					point.owner = attackerTeam
					point.capturingTeam = nil
					point.progress = 0
					playCaptureAnimation(point, attackerTeam)
				end
			elseif attackerTeam and attackerTeam == point.owner then
				-- defenders on their own point: wipe enemy progress fast
				point.progress = math.max(point.progress - DECAY_RATE * 3 * dt, 0)
				if point.progress <= 0 then
					point.capturingTeam = nil
				end
			elseif blue > 0 and red > 0 then
				-- contested: progress freezes
			else
				-- empty: progress slowly decays
				point.progress = math.max(point.progress - DECAY_RATE * dt, 0)
				if point.progress <= 0 then
					point.capturingTeam = nil
				end
			end

			updatePointVisuals(point)
		end

		-- owned points earn score
		if scoreClock >= SCORE_INTERVAL then
			scoreClock = 0
			for _, point in points do
				if point.owner == "Blue" then
					teamScores.Blue += SCORE_PER_POINT
				elseif point.owner == "Red" then
					teamScores.Red += SCORE_PER_POINT
				end
			end
		end

		updateHud()
	end
end)
