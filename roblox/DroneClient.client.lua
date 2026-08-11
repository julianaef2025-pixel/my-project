--[[
	FPV Drone — CLIENT script
	Put this in StarterPlayer > StarterPlayerScripts as a LocalScript.

	Controls while flying:
	- Mouse        : look / steer (yaw + pitch, FPV style)
	- W / S        : forward / backward
	- A / D        : strafe left / right (drone banks into it)
	- Space        : up
	- Left Shift   : down
	- X            : exit the drone

	FPV realism:
	- Wide FOV goggles view + motor-vibration camera shake
	- Digital HUD: battery bar, LiPo voltage, flight time left, speed, altitude
	- LOW BATTERY warning + beeps under 20%
	- When the battery dies: motors cut, SIGNAL LOST static, and you watch it fall
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild("DroneRemotes")
local enterEvent = remotes:WaitForChild("DroneEnter")
local exitEvent = remotes:WaitForChild("DroneExit")

-- flight tuning
local MOVE_SPEED = 70 -- studs/sec horizontal
local VERTICAL_SPEED = 40 -- studs/sec up/down
local MOUSE_SENSITIVITY = 0.0035 -- radians per pixel of mouse movement
local MAX_PITCH = math.rad(75)
local BANK_ANGLE = math.rad(20) -- visual roll when strafing
local CAMERA_OFFSET = CFrame.new(0, 0.5, -1) -- camera sits at the front of the drone

-- FPV camera tuning
local FPV_FOV = 100 -- wide goggle view
local SHAKE_INTENSITY = 0.004 -- motor vibration (radians)
local LOW_BATTERY_FRAC = 0.2 -- warning kicks in below 20%

local flying = nil -- current drone model
local renderConn = nil
local hud = nil
local savedFOV = 70

--------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------

local function makeLabel(parent, name, size, position, anchor, textSize, alignment)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.AnchorPoint = anchor
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(230, 255, 230)
	label.TextStrokeTransparency = 0.6
	label.TextXAlignment = alignment or Enum.TextXAlignment.Center
	label.Parent = parent
	return label
end

local function createHUD()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DroneFPVHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10

	-- center crosshair
	local crosshair = makeLabel(gui, "Crosshair", UDim2.new(0, 40, 0, 40), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), 22)
	crosshair.Text = "+"

	-- top-left: REC + flight timer
	local rec = makeLabel(gui, "Rec", UDim2.new(0, 200, 0, 24), UDim2.new(0, 20, 0, 16), Vector2.new(0, 0), 18, Enum.TextXAlignment.Left)
	rec.Text = "● REC"
	rec.TextColor3 = Color3.fromRGB(255, 70, 70)

	local timer = makeLabel(gui, "Timer", UDim2.new(0, 200, 0, 22), UDim2.new(0, 20, 0, 42), Vector2.new(0, 0), 16, Enum.TextXAlignment.Left)
	timer.Text = "FLT 04:00"

	-- top-right: battery block
	local battFrame = Instance.new("Frame")
	battFrame.Name = "BatteryFrame"
	battFrame.Size = UDim2.new(0, 170, 0, 14)
	battFrame.Position = UDim2.new(1, -20, 0, 20)
	battFrame.AnchorPoint = Vector2.new(1, 0)
	battFrame.BackgroundColor3 = Color3.fromRGB(20, 30, 20)
	battFrame.BackgroundTransparency = 0.3
	battFrame.BorderSizePixel = 1
	battFrame.BorderColor3 = Color3.fromRGB(200, 255, 200)
	battFrame.Parent = gui

	local battFill = Instance.new("Frame")
	battFill.Name = "Fill"
	battFill.Size = UDim2.new(1, 0, 1, 0)
	battFill.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
	battFill.BorderSizePixel = 0
	battFill.Parent = battFrame

	local battText = makeLabel(gui, "BattText", UDim2.new(0, 170, 0, 20), UDim2.new(1, -20, 0, 38), Vector2.new(1, 0), 16, Enum.TextXAlignment.Right)
	battText.Text = "100%  16.8V"

	-- bottom: speed / altitude / exit hint
	local speed = makeLabel(gui, "Speed", UDim2.new(0, 180, 0, 22), UDim2.new(0, 30, 1, -40), Vector2.new(0, 1), 17, Enum.TextXAlignment.Left)
	speed.Text = "SPD   0"

	local alt = makeLabel(gui, "Alt", UDim2.new(0, 180, 0, 22), UDim2.new(1, -30, 1, -40), Vector2.new(1, 1), 17, Enum.TextXAlignment.Right)
	alt.Text = "ALT   0"

	local exitHint = makeLabel(gui, "ExitHint", UDim2.new(0, 300, 0, 20), UDim2.new(0.5, 0, 1, -14), Vector2.new(0.5, 1), 14)
	exitHint.Text = "[X] DISARM / EXIT"
	exitHint.TextTransparency = 0.35

	-- flashing low battery warning
	local lowBatt = makeLabel(gui, "LowBattery", UDim2.new(0, 400, 0, 34), UDim2.new(0.5, 0, 0.72, 0), Vector2.new(0.5, 0.5), 26)
	lowBatt.Text = "⚠ LOW BATTERY ⚠"
	lowBatt.TextColor3 = Color3.fromRGB(255, 60, 60)
	lowBatt.Visible = false

	-- signal-lost static overlay (shown when the battery dies)
	local staticFrame = Instance.new("Frame")
	staticFrame.Name = "Static"
	staticFrame.Size = UDim2.new(1, 0, 1, 0)
	staticFrame.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	staticFrame.BackgroundTransparency = 1
	staticFrame.BorderSizePixel = 0
	staticFrame.ZIndex = 5
	staticFrame.Parent = gui

	local signalLost = makeLabel(staticFrame, "SignalLost", UDim2.new(0, 500, 0, 40), UDim2.new(0.5, 0, 0.45, 0), Vector2.new(0.5, 0.5), 32)
	signalLost.Text = "SIGNAL LOST"
	signalLost.TextColor3 = Color3.fromRGB(255, 255, 255)
	signalLost.ZIndex = 6
	signalLost.Visible = false

	-- low battery beep (built-in Roblox sound, always works)
	local beep = Instance.new("Sound")
	beep.Name = "BatteryBeep"
	beep.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	beep.Volume = 0.7
	beep.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")

	return {
		gui = gui,
		timer = timer,
		battFill = battFill,
		battText = battText,
		speed = speed,
		alt = alt,
		lowBatt = lowBatt,
		staticFrame = staticFrame,
		signalLost = signalLost,
		beep = beep,
	}
end

--------------------------------------------------------------------
-- flight
--------------------------------------------------------------------

local function stopFlying(notifyServer)
	if not flying then
		return
	end
	flying = nil

	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if hud then
		hud.gui:Destroy()
		hud = nil
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = savedFOV
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end

	if notifyServer then
		exitEvent:FireServer()
	end
end

local function startFlying(drone)
	local root = drone.PrimaryPart
	if not root then
		return
	end
	local lv = root:WaitForChild("DroneLinearVelocity", 5)
	local ao = root:WaitForChild("DroneAlignOrientation", 5)
	if not lv or not ao then
		return
	end
	local motorSound = root:FindFirstChild("DroneMotor")

	flying = drone
	hud = createHUD()

	-- start from the drone's current heading
	local yaw = math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z)
	local pitch = 0
	local roll = 0
	local currentVelocity = Vector3.zero
	local lastBeep = 0
	local flightClock = 0

	savedFOV = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FPV_FOV

	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not drone.Parent or not root.Parent then
			stopFlying(true)
			return
		end

		flightClock += dt
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		local maxBattery = drone:GetAttribute("MaxBattery") or 240
		local battery = drone:GetAttribute("Battery") or 0
		local batteryFrac = math.clamp(battery / maxBattery, 0, 1)
		local dead = drone:GetAttribute("Dead") == true

		local throttleFrac = 0

		if not dead then
			-- steer with the mouse
			local delta = UserInputService:GetMouseDelta()
			yaw -= delta.X * MOUSE_SENSITIVITY
			pitch = math.clamp(pitch - delta.Y * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)

			-- movement input
			local forward = 0
			local strafe = 0
			local vertical = 0
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then forward += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then forward -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then strafe += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then strafe -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vertical += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then vertical -= 1 end

			-- bank into strafes for that FPV feel
			local targetRoll = -strafe * BANK_ANGLE
			roll += (targetRoll - roll) * math.min(dt * 8, 1)

			-- where the drone is pointing (yaw + pitch, roll is visual only)
			local aimRotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)

			local targetVelocity = (aimRotation.LookVector * forward + aimRotation.RightVector * strafe) * MOVE_SPEED
				+ Vector3.new(0, vertical * VERTICAL_SPEED, 0)
			currentVelocity = currentVelocity:Lerp(targetVelocity, math.min(dt * 6, 1))

			lv.VectorVelocity = currentVelocity
			ao.CFrame = aimRotation * CFrame.Angles(0, 0, roll)

			throttleFrac = math.clamp(currentVelocity.Magnitude / MOVE_SPEED, 0, 1)

			-- motor pitch follows throttle (locally, for the pilot)
			if motorSound then
				motorSound.PlaybackSpeed = 0.85 + throttleFrac * 0.55
			end
		end

		-- FPV camera locked to the drone body + motor vibration shake
		local t = flightClock * 30
		local shakeAmount = SHAKE_INTENSITY * (0.4 + throttleFrac)
		local shake = CFrame.Angles(
			(math.noise(t, 0) - 0) * shakeAmount,
			(math.noise(0, t) - 0) * shakeAmount,
			(math.noise(t, t) - 0) * shakeAmount
		)
		camera.CFrame = root.CFrame * CAMERA_OFFSET * shake

		---------------------------------------------------------
		-- HUD update
		---------------------------------------------------------
		local speed = root.AssemblyLinearVelocity.Magnitude
		local altitude = math.max(root.Position.Y, 0)

		hud.battFill.Size = UDim2.new(batteryFrac, 0, 1, 0)
		-- 4S LiPo: 16.8V full -> 13.2V empty
		local voltage = 13.2 + 3.6 * batteryFrac
		hud.battText.Text = string.format("%d%%  %.1fV", math.floor(batteryFrac * 100 + 0.5), voltage)

		if batteryFrac > 0.5 then
			hud.battFill.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
		elseif batteryFrac > LOW_BATTERY_FRAC then
			hud.battFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		else
			hud.battFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		end

		local remaining = math.floor(battery + 0.5)
		hud.timer.Text = string.format("FLT %02d:%02d", remaining // 60, remaining % 60)
		hud.speed.Text = string.format("SPD %3d", math.floor(speed + 0.5))
		hud.alt.Text = string.format("ALT %3d", math.floor(altitude + 0.5))

		if dead then
			-- SIGNAL LOST: flickering static while the drone falls
			hud.lowBatt.Visible = false
			hud.signalLost.Visible = math.floor(flightClock * 6) % 3 ~= 0
			hud.staticFrame.BackgroundTransparency = 0.35 + math.random() * 0.4
			hud.battText.Text = "0%  --.-V"
			if motorSound and motorSound.IsPlaying then
				motorSound:Stop()
			end
		elseif batteryFrac <= LOW_BATTERY_FRAC then
			-- flashing warning + beep once a second
			hud.lowBatt.Visible = math.floor(flightClock * 3) % 2 == 0
			if flightClock - lastBeep >= 1 then
				lastBeep = flightClock
				hud.beep:Play()
			end
		else
			hud.lowBatt.Visible = false
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.X and flying then
		stopFlying(true)
	end
end)

enterEvent.OnClientEvent:Connect(startFlying)

-- server kicked us out (death, drone destroyed, etc.)
exitEvent.OnClientEvent:Connect(function()
	stopFlying(false)
end)
