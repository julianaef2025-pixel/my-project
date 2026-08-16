--[[
	AA TURRET — CLIENT LocalScript (StarterPlayer > StarterPlayerScripts)
	A separate LocalScript: don't paste into the drone client.

	The gunner experience:
	- gunsight camera looking down the barrel
	- REALISTIC traverse: the gun slews at a limited speed, so you have
	  to lead and track targets — you can't flick like a mouse
	- hold left click to fire, recoil kicks the sight
	- heat gauge: shoot too long and the gun locks up until it cools
	- Z cycles the optics: 1x -> 3x -> 8x
	- range readout to whatever is under the crosshair
	- X gets you off the gun
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("TurretRemotes")
local fireRemote = remotes:WaitForChild("TurretFire")
local aimRemote = remotes:WaitForChild("TurretAim")
local exitRemote = remotes:WaitForChild("TurretExit")
local stateRemote = remotes:WaitForChild("TurretState")

local MOUSE_SENSITIVITY = 0.003
local SLEW_SPEED_YAW = math.rad(80) -- deg/sec the gun can actually turn
local SLEW_SPEED_PITCH = math.rad(55)
local MIN_PITCH = math.rad(-8) -- can't aim into the dirt much
local MAX_PITCH = math.rad(80) -- it's an ANTI-AIR gun, aims way up
local FIRE_INTERVAL = 0.09
local ZOOM_LEVELS = { 70, 26, 10 } -- FOV: 1x, ~3x, ~8x

--------------------------------------------------------------------
-- gunner HUD
--------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "TurretHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- MILITARY OPTIC: black etched reticle (like real glass) with mil
-- ticks, a thin lead ring, and a small illuminated red center dot
local RETICLE_COLOR = Color3.fromRGB(12, 12, 12)

-- circular black mask around the optic (the "looking through a tube" look)
local scopeMask = Instance.new("Frame")
scopeMask.AnchorPoint = Vector2.new(0.5, 0.5)
scopeMask.Position = UDim2.new(0.5, 0, 0.5, 0)
scopeMask.Size = UDim2.new(0, 700, 0, 700)
scopeMask.BackgroundTransparency = 1
scopeMask.Parent = gui
local maskCorner = Instance.new("UICorner")
maskCorner.CornerRadius = UDim.new(0.5, 0)
maskCorner.Parent = scopeMask
local maskStroke = Instance.new("UIStroke")
maskStroke.Color = Color3.fromRGB(5, 5, 5)
maskStroke.Thickness = 900
maskStroke.Transparency = 0.35
maskStroke.Parent = scopeMask

local function etch(sizeX, sizeY, posX, posY, transparency)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.new(0.5, posX, 0.5, posY)
	line.Size = UDim2.new(0, sizeX, 0, sizeY)
	line.BackgroundColor3 = RETICLE_COLOR
	line.BackgroundTransparency = transparency or 0.15
	line.BorderSizePixel = 0
	line.Parent = gui
	return line
end

-- main crosshair: long thin etched lines with a clear gap in the middle
etch(2, 240, 0, -158) -- top
etch(2, 240, 0, 158) -- bottom (bullet-drop scale lives on this one)
etch(240, 2, -158, 0) -- left
etch(240, 2, 158, 0) -- right

-- mil ticks along both axes (every tick = a bit of lead on a mover)
for i = 1, 4 do
	local off = 55 + (i - 1) * 45
	etch(1.5, i == 4 and 18 or 10, off, 0, 0.1) -- right ticks
	etch(1.5, i == 4 and 18 or 10, -off, 0, 0.1) -- left ticks
	etch(i == 4 and 18 or 10, 1.5, 0, off, 0.1) -- drop scale below
	etch(i == 4 and 18 or 10, 1.5, 0, -off, 0.1) -- top ticks
end

-- thin lead ring: put a crossing drone ON this ring, not on the dot
local leadRing = Instance.new("Frame")
leadRing.AnchorPoint = Vector2.new(0.5, 0.5)
leadRing.Position = UDim2.new(0.5, 0, 0.5, 0)
leadRing.Size = UDim2.new(0, 160, 0, 160)
leadRing.BackgroundTransparency = 1
leadRing.Parent = gui
local leadStroke = Instance.new("UIStroke")
leadStroke.Color = RETICLE_COLOR
leadStroke.Thickness = 1.2
leadStroke.Transparency = 0.35
leadStroke.Parent = leadRing
local leadCorner = Instance.new("UICorner")
leadCorner.CornerRadius = UDim.new(0.5, 0)
leadCorner.Parent = leadRing

-- illuminated red center dot (real optics glow so you find it fast)
local pip = Instance.new("Frame")
pip.AnchorPoint = Vector2.new(0.5, 0.5)
pip.Position = UDim2.new(0.5, 0, 0.5, 0)
pip.Size = UDim2.new(0, 4, 0, 4)
pip.BackgroundColor3 = Color3.fromRGB(255, 55, 45)
pip.BorderSizePixel = 0
pip.Parent = gui
local pipCorner = Instance.new("UICorner")
pipCorner.CornerRadius = UDim.new(0.5, 0)
pipCorner.Parent = pip
local pipGlow = Instance.new("UIStroke")
pipGlow.Color = Color3.fromRGB(255, 90, 70)
pipGlow.Thickness = 1
pipGlow.Transparency = 0.5
pipGlow.Parent = pip

-- range to target under the crosshair
local rangeLabel = Instance.new("TextLabel")
rangeLabel.AnchorPoint = Vector2.new(0.5, 0)
rangeLabel.Position = UDim2.new(0.5, 0, 0.5, 56)
rangeLabel.Size = UDim2.new(0, 200, 0, 18)
rangeLabel.BackgroundTransparency = 1
rangeLabel.Font = Enum.Font.Code
rangeLabel.TextSize = 15
rangeLabel.TextColor3 = Color3.fromRGB(255, 170, 60)
rangeLabel.Text = ""
rangeLabel.Parent = gui

-- heat bar
local heatBack = Instance.new("Frame")
heatBack.AnchorPoint = Vector2.new(0.5, 1)
heatBack.Position = UDim2.new(0.5, 0, 1, -46)
heatBack.Size = UDim2.new(0, 260, 0, 10)
heatBack.BackgroundColor3 = Color3.fromRGB(15, 17, 14)
heatBack.BackgroundTransparency = 0.25
heatBack.BorderSizePixel = 0
heatBack.Parent = gui
local heatCorner = Instance.new("UICorner")
heatCorner.CornerRadius = UDim.new(0, 5)
heatCorner.Parent = heatBack

local heatFill = Instance.new("Frame")
heatFill.Size = UDim2.new(0, 0, 1, 0)
heatFill.BackgroundColor3 = Color3.fromRGB(120, 210, 130)
heatFill.BorderSizePixel = 0
heatFill.Parent = heatBack
local heatFillCorner = Instance.new("UICorner")
heatFillCorner.CornerRadius = UDim.new(0, 5)
heatFillCorner.Parent = heatFill

local heatLabel = Instance.new("TextLabel")
heatLabel.AnchorPoint = Vector2.new(0.5, 1)
heatLabel.Position = UDim2.new(0.5, 0, 1, -58)
heatLabel.Size = UDim2.new(0, 300, 0, 16)
heatLabel.BackgroundTransparency = 1
heatLabel.Font = Enum.Font.Code
heatLabel.TextSize = 13
heatLabel.TextColor3 = Color3.fromRGB(200, 205, 195)
heatLabel.Text = "BARREL TEMP"
heatLabel.Parent = gui

-- bottom hint + zoom indicator
local hintLabel = Instance.new("TextLabel")
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 1, -20)
hintLabel.Size = UDim2.new(0, 600, 0, 18)
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.Code
hintLabel.TextSize = 14
hintLabel.TextColor3 = Color3.fromRGB(160, 165, 155)
hintLabel.Text = "HOLD CLICK — FIRE   [Z] OPTICS   [X] DISMOUNT"
hintLabel.Parent = gui

local zoomLabel = Instance.new("TextLabel")
zoomLabel.AnchorPoint = Vector2.new(1, 0)
zoomLabel.Position = UDim2.new(1, -24, 0, 24)
zoomLabel.Size = UDim2.new(0, 100, 0, 22)
zoomLabel.BackgroundTransparency = 1
zoomLabel.Font = Enum.Font.Code
zoomLabel.TextSize = 18
zoomLabel.TextColor3 = Color3.fromRGB(255, 170, 60)
zoomLabel.TextXAlignment = Enum.TextXAlignment.Right
zoomLabel.Text = "1x"
zoomLabel.Parent = gui


--------------------------------------------------------------------
-- gunner mode
--------------------------------------------------------------------
local camera = workspace.CurrentCamera
local manning -- current turret model
local barrel -- its barrel part
local renderConn
local firing = false
local lastClientShot = 0
local yaw, pitch = 0, 0
local targetYaw, targetPitch = 0, 0
local recoil = 0
local zoomIndex = 1
local aimSendClock = 0

local function leaveMode()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	manning = nil
	barrel = nil
	firing = false
	gui.Enabled = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function enterMode(turret, barrelPart)
	manning = turret
	barrel = barrelPart
	gui.Enabled = true
	zoomIndex = 1
	recoil = 0

	-- start aimed wherever the barrel currently points
	local look = barrel.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	targetYaw, targetPitch = yaw, pitch

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = ZOOM_LEVELS[1]
	zoomLabel.Text = "1x"
	scopeMask.Size = UDim2.new(0, 700, 0, 700)
	maskStroke.Transparency = 0.35

	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not manning or not manning.Parent or not barrel.Parent
			or manning:GetAttribute("GunnerUserId") ~= player.UserId then
			leaveMode()
			return
		end

		-- mouse moves the AIM POINT instantly, but the GUN slews to it
		-- at a limited speed — that's the realistic AA feel
		local delta = UserInputService:GetMouseDelta()
		local zoomFactor = camera.FieldOfView / 70 -- finer aim when zoomed
		targetYaw -= delta.X * MOUSE_SENSITIVITY * zoomFactor
		targetPitch = math.clamp(
			targetPitch - delta.Y * MOUSE_SENSITIVITY * zoomFactor,
			MIN_PITCH, MAX_PITCH
		)

		local yawDiff = targetYaw - yaw
		local pitchDiff = targetPitch - pitch
		yaw += math.clamp(yawDiff, -SLEW_SPEED_YAW * dt, SLEW_SPEED_YAW * dt)
		pitch += math.clamp(pitchDiff, -SLEW_SPEED_PITCH * dt, SLEW_SPEED_PITCH * dt)

		-- recoil decays back down
		recoil = math.max(recoil - dt * 4, 0)

		-- tiny breathing sway so the sight never sits perfectly still
		local t = os.clock()
		local swayYaw = math.sin(t * 0.9) * 0.0012
		local swayPitch = math.sin(t * 1.3) * 0.0009

		local aimRotation = CFrame.Angles(0, yaw + swayYaw, 0)
			* CFrame.Angles(pitch + swayPitch + recoil * 0.02, 0, 0)
		local aimDir = aimRotation.LookVector

		-- optic camera: you look THROUGH the gunsight just past the
		-- muzzle, so the turret body never blocks the view
		local halfLength = math.max(barrel.Size.X, barrel.Size.Y, barrel.Size.Z) / 2
		local camPos = barrel.Position
			+ aimDir * (halfLength + 1.2)
			+ aimRotation.UpVector * 0.35
		local shake = recoil > 0
			and Vector3.new(
				(math.random() - 0.5) * recoil * 0.18,
				(math.random() - 0.5) * recoil * 0.18,
				0
			)
			or Vector3.zero
		camera.CFrame = CFrame.lookAt(camPos + shake, camPos + shake + aimDir)

		-- tell the server where the gun points (10x per second)
		aimSendClock += dt
		if aimSendClock >= 0.1 then
			aimSendClock = 0
			aimRemote:FireServer(aimDir)
		end

		-- firing at a fixed rate while the mouse is held
		local overheated = manning:GetAttribute("Overheated") == true
		if firing and not overheated then
			local now = os.clock()
			if now - lastClientShot >= FIRE_INTERVAL then
				lastClientShot = now
				fireRemote:FireServer(aimDir)
				recoil = math.min(recoil + 1.1, 3.5)
				-- the sight jumps up a hair with every round, like real recoil
				targetPitch = math.clamp(targetPitch + 0.0035, MIN_PITCH, MAX_PITCH)
			end
		end

		-- HUD: heat bar
		local heat = manning:GetAttribute("Heat") or 0
		heatFill.Size = UDim2.new(heat / 100, 0, 1, 0)
		if overheated then
			heatFill.BackgroundColor3 = Color3.fromRGB(255, 70, 60)
			heatLabel.Text = "⚠ OVERHEATED — COOLING"
			heatLabel.TextColor3 = Color3.fromRGB(255, 90, 70)
		else
			heatFill.BackgroundColor3 = heat > 65
				and Color3.fromRGB(255, 150, 60)
				or Color3.fromRGB(120, 210, 130)
			heatLabel.Text = "BARREL TEMP"
			heatLabel.TextColor3 = Color3.fromRGB(200, 205, 195)
		end

		-- HUD: range to whatever the crosshair is on
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = { manning }
		if player.Character then
			table.insert(exclude, player.Character)
		end
		rayParams.FilterDescendantsInstances = exclude
		local hit = workspace:Raycast(camPos, aimDir * 1500, rayParams)
		rangeLabel.Text = hit and ("RNG " .. math.floor((hit.Position - camPos).Magnitude) .. "m") or "RNG ---"
	end)
end

stateRemote.OnClientEvent:Connect(function(action, turret, barrelPart)
	if action == "enter" and turret and barrelPart then
		enterMode(turret, barrelPart)
	elseif action == "exit" then
		leaveMode()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not manning then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
	elseif input.KeyCode == Enum.KeyCode.X then
		exitRemote:FireServer()
		leaveMode()
	elseif input.KeyCode == Enum.KeyCode.Z then
		zoomIndex = zoomIndex % #ZOOM_LEVELS + 1
		camera.FieldOfView = ZOOM_LEVELS[zoomIndex]
		zoomLabel.Text = ({ "1x", "3x", "8x" })[zoomIndex]
		-- the optic tube closes in as you magnify, like a real scope
		local maskSize = ({ 700, 580, 490 })[zoomIndex]
		scopeMask.Size = UDim2.new(0, maskSize, 0, maskSize)
		maskStroke.Transparency = ({ 0.35, 0.12, 0.03 })[zoomIndex]
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end)
