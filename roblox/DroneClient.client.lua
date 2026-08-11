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
	- Digital HUD: battery, LiPo voltage, flight time, speed, altitude,
	  distance from the pilot, and RSSI signal strength
	- The farther you fly from your pilot, the worse the video link gets:
	  static/glitch lines grow until the feed cuts to SIGNAL LOST and the
	  drone falls out of the sky (range is enforced by the server)
	- LOW BATTERY warning + beeps under 20%; empty battery = BATTERY
	  DEPLETED and you watch the drone drop
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

-- doppler: the drone's buzz shifts pitch as it flies past people (real physics)
SoundService.DopplerScale = 2

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
local ACCEL_RESPONSE = 3.2 -- lower = heavier drone with more momentum/drift
local FORWARD_TILT = math.rad(10) -- the drone noses into its direction of travel like a real quad
local HOVER_WOBBLE = math.rad(1.6) -- gentle wobble while hovering (props fighting gravity)
local WIND_STRENGTH = 3 -- studs/sec of slow wind drift you have to correct for
local CAMERA_OFFSET = CFrame.new(0, 0.5, -1) -- camera sits at the front of the drone

-- FPV camera tuning
local FPV_FOV = 100 -- wide goggle view
local SHAKE_INTENSITY = 0.004 -- motor vibration (radians)
local LOW_BATTERY_FRAC = 0.2 -- warning kicks in below 20%
local INTERFERENCE_START_FRAC = 0.35 -- static starts creeping in at 35% of max signal range
local STATIC_FLOOR = 0.03 -- tiny chance of a stray glitch line even on a perfect link
local STATIC_LINE_COUNT = 14 -- glitch line pool size

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

	-- top-left: REC + flight timer + RSSI
	local rec = makeLabel(gui, "Rec", UDim2.new(0, 200, 0, 24), UDim2.new(0, 20, 0, 16), Vector2.new(0, 0), 18, Enum.TextXAlignment.Left)
	rec.Text = "● REC"
	rec.TextColor3 = Color3.fromRGB(255, 70, 70)

	local timer = makeLabel(gui, "Timer", UDim2.new(0, 200, 0, 22), UDim2.new(0, 20, 0, 42), Vector2.new(0, 0), 16, Enum.TextXAlignment.Left)
	timer.Text = "FLT 04:00"

	local rssi = makeLabel(gui, "Rssi", UDim2.new(0, 220, 0, 22), UDim2.new(0, 20, 0, 66), Vector2.new(0, 0), 16, Enum.TextXAlignment.Left)
	rssi.Text = "RSSI ▮▮▮▮▮ 100%"

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

	-- bottom: speed / distance-from-pilot / altitude / exit hint
	local speed = makeLabel(gui, "Speed", UDim2.new(0, 180, 0, 22), UDim2.new(0, 30, 1, -40), Vector2.new(0, 1), 17, Enum.TextXAlignment.Left)
	speed.Text = "SPD   0"

	local dist = makeLabel(gui, "Dist", UDim2.new(0, 220, 0, 22), UDim2.new(0.5, 0, 1, -40), Vector2.new(0.5, 1), 17)
	dist.Text = "DST    0"

	local alt = makeLabel(gui, "Alt", UDim2.new(0, 180, 0, 22), UDim2.new(1, -30, 1, -40), Vector2.new(1, 1), 17, Enum.TextXAlignment.Right)
	alt.Text = "ALT   0"

	local exitHint = makeLabel(gui, "ExitHint", UDim2.new(0, 300, 0, 20), UDim2.new(0.5, 0, 1, -14), Vector2.new(0.5, 1), 14)
	exitHint.Text = "[X] DISARM / EXIT"
	exitHint.TextTransparency = 0.35

	-- flashing warnings
	local lowBatt = makeLabel(gui, "LowBattery", UDim2.new(0, 400, 0, 34), UDim2.new(0.5, 0, 0.72, 0), Vector2.new(0.5, 0.5), 26)
	lowBatt.Text = "⚠ LOW BATTERY ⚠"
	lowBatt.TextColor3 = Color3.fromRGB(255, 60, 60)
	lowBatt.Visible = false

	local weakSignal = makeLabel(gui, "WeakSignal", UDim2.new(0, 520, 0, 34), UDim2.new(0.5, 0, 0.28, 0), Vector2.new(0.5, 0.5), 26)
	weakSignal.Text = "⚠ WEAK SIGNAL — TURN BACK ⚠"
	weakSignal.TextColor3 = Color3.fromRGB(255, 160, 40)
	weakSignal.Visible = false

	-- pool of horizontal static/glitch lines (video interference)
	local staticLines = {}
	for i = 1, STATIC_LINE_COUNT do
		local line = Instance.new("Frame")
		line.Name = "StaticLine" .. i
		line.Size = UDim2.new(1, 0, 0, 2)
		line.Position = UDim2.new(0, 0, math.random(), 0)
		line.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
		line.BorderSizePixel = 0
		line.ZIndex = 4
		line.Visible = false
		line.Parent = gui
		staticLines[i] = line
	end

	-- full-screen static overlay (shown when the link/battery dies)
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
		rssi = rssi,
		battFill = battFill,
		battText = battText,
		speed = speed,
		dist = dist,
		alt = alt,
		lowBatt = lowBatt,
		weakSignal = weakSignal,
		staticLines = staticLines,
		staticFrame = staticFrame,
		signalLost = signalLost,
		beep = beep,
	}
end

-- draws the glitch lines: intensity 0 = clean feed, 1 = full breakup
local function updateStaticLines(intensity)
	for _, line in hud.staticLines do
		if math.random() < intensity * 0.9 then
			line.Visible = true
			line.Position = UDim2.new(0, 0, math.random(), 0)
			-- lines get thicker the worse the signal is
			line.Size = UDim2.new(1, 0, 0, math.random(1, 2 + math.floor(intensity * 14)))
			line.BackgroundTransparency = 0.15 + math.random() * 0.5
			local shade = 100 + math.random(0, 155)
			line.BackgroundColor3 = Color3.fromRGB(shade, shade, shade)
		else
			line.Visible = false
		end
	end
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

	-- the video link comes from where we're standing (the character is frozen there)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local homePosition = hrp and hrp.Position or root.Position

	-- start from the drone's current heading
	local yaw = math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z)
	local pitch = 0
	local roll = 0
	local tilt = 0 -- forward lean into the direction of travel
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
		local deathReason = drone:GetAttribute("DeathReason")
		local signalRange = drone:GetAttribute("SignalRange") or 800

		-- how bad is the video link? 0 = perfect, 1 = about to drop
		local distance = (root.Position - homePosition).Magnitude
		local interferenceStart = signalRange * INTERFERENCE_START_FRAC
		local interference = math.clamp((distance - interferenceStart) / (signalRange - interferenceStart), 0, 1)
		if dead then
			interference = 1
		end

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

			-- bank into strafes + nose into forward flight, like a real quad
			local targetRoll = -strafe * BANK_ANGLE
			roll += (targetRoll - roll) * math.min(dt * 8, 1)
			local targetTilt = forward * FORWARD_TILT
			tilt += (targetTilt - tilt) * math.min(dt * 5, 1)

			-- where the drone is pointing (yaw + pitch; tilt/roll are the frame leaning)
			local aimRotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)

			local targetVelocity = (aimRotation.LookVector * forward + aimRotation.RightVector * strafe) * MOVE_SPEED
				+ Vector3.new(0, vertical * VERTICAL_SPEED, 0)
			-- momentum: the drone carries its speed and drifts through turns
			currentVelocity = currentVelocity:Lerp(targetVelocity, math.min(dt * ACCEL_RESPONSE, 1))

			throttleFrac = math.clamp(currentVelocity.Magnitude / MOVE_SPEED, 0, 1)

			-- slow wandering wind you have to keep correcting for
			local windT = flightClock * 0.25
			local wind = Vector3.new(
				math.noise(windT, 17.3),
				math.noise(windT, 89.1) * 0.3,
				math.noise(windT, 43.7)
			) * WIND_STRENGTH

			-- hover wobble: props fighting gravity when sitting still
			local wobbleAmount = HOVER_WOBBLE * (1 - throttleFrac * 0.8)
			local wobbleT = flightClock * 2.2
			local wobblePitch = math.noise(wobbleT, 3.7) * wobbleAmount
			local wobbleRoll = math.noise(wobbleT, 9.2) * wobbleAmount

			lv.VectorVelocity = currentVelocity + wind
			ao.CFrame = CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(pitch - tilt + wobblePitch, 0, 0)
				* CFrame.Angles(0, 0, roll + wobbleRoll)

			-- motor sound follows throttle: higher pitch AND louder under load (locally, for the pilot)
			if motorSound then
				motorSound.PlaybackSpeed = 0.85 + throttleFrac * 0.55
				motorSound.Volume = 0.55 + throttleFrac * 0.45
			end
		end

		-- FPV camera locked to the drone body + motor vibration shake
		local t = flightClock * 30
		local shakeAmount = SHAKE_INTENSITY * (0.4 + throttleFrac)
		local shake = CFrame.Angles(
			math.noise(t, 0) * shakeAmount,
			math.noise(0, t) * shakeAmount,
			math.noise(t, t) * shakeAmount
		)
		-- bad signal also makes the video judder with random glitch kicks
		if interference > 0.25 and math.random() < interference * 0.35 then
			local glitch = interference * 0.03
			shake = shake * CFrame.Angles(
				(math.random() - 0.5) * glitch,
				(math.random() - 0.5) * glitch,
				(math.random() - 0.5) * glitch * 2
			)
		end

		if dead and deathReason == "signal" then
			-- link is gone: the feed freezes on the last frame, you don't see the fall
		else
			camera.CFrame = root.CFrame * CAMERA_OFFSET * shake
		end

		---------------------------------------------------------
		-- HUD update
		---------------------------------------------------------
		local speed = root.AssemblyLinearVelocity.Magnitude
		local altitude = math.max(root.Position.Y, 0)

		hud.battFill.Size = UDim2.new(batteryFrac, 0, 1, 0)
		-- 4S LiPo: 16.8V full -> 13.2V empty, and it sags under load like a real pack
		local voltage = 13.2 + 3.6 * batteryFrac - throttleFrac * 0.7
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
		hud.dist.Text = string.format("DST %4d", math.floor(distance + 0.5))

		-- RSSI signal bars
		local strength = 1 - interference
		local bars = math.clamp(math.ceil(strength * 5), dead and 0 or 1, 5)
		hud.rssi.Text = string.format("RSSI %s%s %d%%", string.rep("▮", bars), string.rep("▯", 5 - bars), math.floor(strength * 100 + 0.5))
		if interference > 0.5 then
			hud.rssi.TextColor3 = Color3.fromRGB(255, 90, 60)
		elseif interference > 0.15 then
			hud.rssi.TextColor3 = Color3.fromRGB(255, 200, 60)
		else
			hud.rssi.TextColor3 = Color3.fromRGB(230, 255, 230)
		end

		-- video interference grows with distance (with a tiny glitch floor so the
		-- analog feed never looks perfectly digital-clean)
		updateStaticLines(math.max(interference, STATIC_FLOOR))

		if dead then
			hud.lowBatt.Visible = false
			hud.weakSignal.Visible = false
			hud.signalLost.Text = deathReason == "battery" and "BATTERY DEPLETED" or "SIGNAL LOST"
			hud.signalLost.Visible = math.floor(flightClock * 6) % 3 ~= 0
			hud.staticFrame.BackgroundTransparency = 0.35 + math.random() * 0.4
			hud.battText.Text = deathReason == "battery" and "0%  --.-V" or hud.battText.Text
			if motorSound and motorSound.IsPlaying then
				motorSound:Stop()
			end
		else
			-- weak signal warning once interference is past halfway
			hud.weakSignal.Visible = interference > 0.5 and math.floor(flightClock * 3) % 2 == 0

			if batteryFrac <= LOW_BATTERY_FRAC then
				-- flashing warning + beep once a second
				hud.lowBatt.Visible = math.floor(flightClock * 3) % 2 == 0
				if flightClock - lastBeep >= 1 then
					lastBeep = flightClock
					hud.beep:Play()
				end
			else
				hud.lowBatt.Visible = false
			end
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

--------------------------------------------------------------------
-- BOMBER DRONE ADD-ON (client)
-- While flying a drone whose name contains "Bomber": press F to
-- drop a grenade, with an ammo counter on the HUD.
--------------------------------------------------------------------
do
	local dropEvent = remotes:WaitForChild("DroneDropGrenade")
	local grenadeGui = nil

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F and flying and flying.Name:lower():find("bomber") then
			dropEvent:FireServer(flying)
		end
	end)

	-- small ammo counter that appears only while flying a bomber
	task.spawn(function()
		while true do
			task.wait(0.2)
			local drone = flying
			if drone and drone.Parent and drone.Name:lower():find("bomber") then
				if not grenadeGui then
					grenadeGui = Instance.new("ScreenGui")
					grenadeGui.Name = "DroneGrenadeHud"
					grenadeGui.ResetOnSpawn = false
					grenadeGui.DisplayOrder = 11

					local label = Instance.new("TextLabel")
					label.Name = "Counter"
					label.AnchorPoint = Vector2.new(0.5, 1)
					label.Position = UDim2.new(0.5, 0, 1, -66)
					label.Size = UDim2.new(0, 340, 0, 26)
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.Code
					label.TextSize = 19
					label.TextColor3 = Color3.fromRGB(230, 255, 230)
					label.TextStrokeTransparency = 0.6
					label.Parent = grenadeGui

					grenadeGui.Parent = player:WaitForChild("PlayerGui")
				end

				local ammo = math.clamp(drone:GetAttribute("Grenades") or 3, 0, 9)
				local label = grenadeGui.Counter
				if ammo > 0 then
					label.Text = "GRENADES " .. string.rep("● ", ammo) .. string.rep("○ ", math.max(3 - ammo, 0)) .. " [F] DROP"
					label.TextColor3 = Color3.fromRGB(230, 255, 230)
				else
					label.Text = "GRENADES EMPTY"
					label.TextColor3 = Color3.fromRGB(255, 90, 60)
				end
			elseif grenadeGui then
				grenadeGui:Destroy()
				grenadeGui = nil
			end
		end
	end)
end
