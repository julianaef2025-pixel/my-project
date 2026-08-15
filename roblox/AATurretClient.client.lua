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

-- crosshair: ring + cross like a real AA reflector sight
local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.new(0.5, 0, 0.5, 0)
ring.Size = UDim2.new(0, 90, 0, 90)
ring.BackgroundTransparency = 1
ring.Parent = gui
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = Color3.fromRGB(255, 170, 60)
ringStroke.Thickness = 1.5
ringStroke.Transparency = 0.25
ringStroke.Parent = ring
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(0.5, 0)
ringCorner.Parent = ring

local function crossLine(sizeX, sizeY, posX, posY)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.new(0.5, posX, 0.5, posY)
	line.Size = UDim2.new(0, sizeX, 0, sizeY)
	line.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
	line.BackgroundTransparency = 0.2
	line.BorderSizePixel = 0
	line.Parent = gui
	return line
end
crossLine(1, 26, 0, -32) -- top tick
crossLine(1, 26, 0, 32) -- bottom tick
crossLine(26, 1, -32, 0) -- left tick
crossLine(26, 1, 32, 0) -- right tick
crossLine(2, 6, 0, 0) -- center dot

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

-- dark vignette edges so it feels like you're behind a gunsight
local function vignette(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
	f.AnchorPoint = props.anchor
	f.Position = props.pos
	f.Size = props.size
	f.Parent = gui
end
vignette({ anchor = Vector2.new(0.5, 0), pos = UDim2.new(0.5, 0, 0, 0), size = UDim2.new(1, 0, 0, 0) })

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

		local aimRotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch + recoil * 0.02, 0, 0)
		local aimDir = aimRotation.LookVector

		-- gunsight camera: just behind and above the barrel
		local camPos = barrel.Position
			+ aimRotation:VectorToWorldSpace(Vector3.new(0, 1.1, 2.6))
		local shake = recoil > 0
			and Vector3.new((math.random() - 0.5) * recoil * 0.12, (math.random() - 0.5) * recoil * 0.12, 0)
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
				recoil = math.min(recoil + 0.8, 3)
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
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end)
