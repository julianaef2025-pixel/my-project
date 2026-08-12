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

-- flight tuning: real-quad physics. WASD leans the airframe and the tilted
-- rotor thrust is what accelerates the drone — gravity, momentum and air
-- drag are all simulated for real.
local MOUSE_SENSITIVITY = 0.0035 -- radians per pixel of mouse movement
local MAX_PITCH = math.rad(75)
local MAX_LEAN = math.rad(35) -- how far the frame tilts into WASD (tilt = acceleration)
local LEAN_RESPONSE = 6 -- how quickly the frame leans into your input
local GRAVITY_COMP = 0.7 -- 1 = holds altitude perfectly while leaning; lower = sags in hard forward flight like a real quad
local CLIMB_ACCEL = 70 -- extra rotor thrust from Space (studs/sec^2)
local DESCEND_ACCEL = 140 -- thrust cut from Left Shift: a hard, fast drop (studs/sec^2)
local LINEAR_DRAG = 1.2 -- air resistance: sets the top speed and how far momentum carries
local MAX_SPEED = 110 -- hard safety cap, studs/sec (physics tops out ~90 before this)
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

			-- === real-quad physics ===
			-- WASD doesn't move the drone — it LEANS the airframe, and the
			-- tilted rotor thrust is what accelerates it, like a real quad
			local targetLeanPitch = forward * MAX_LEAN
			local targetLeanRoll = -strafe * MAX_LEAN * 0.7
			tilt += (targetLeanPitch - tilt) * math.min(dt * LEAN_RESPONSE, 1)
			roll += (targetLeanRoll - roll) * math.min(dt * LEAN_RESPONSE, 1)

			local heading = CFrame.Angles(0, yaw, 0)

			-- rotor thrust pushes along the leaned frame's up axis
			local leanedFrame = heading * CFrame.Angles(-tilt, 0, roll)
			local thrustDir = leanedFrame.UpVector

			-- hover thrust ~ gravity, with only partial compensation for lean:
			-- hard forward flight sags a little unless you feed in Space,
			-- exactly like a real quad in angle mode
			local gravity = workspace.Gravity
			local uprightness = math.max(thrustDir.Y, 0.4)
			local thrust = gravity * (1 + GRAVITY_COMP * (1 / uprightness - 1))
			if vertical > 0 then
				thrust += CLIMB_ACCEL
			elseif vertical < 0 then
				thrust -= DESCEND_ACCEL
			end

			-- integrate thrust + gravity + air drag: momentum, glide and
			-- drifting turns all come out of this for free
			local accel = thrustDir * thrust
				+ Vector3.new(0, -gravity, 0)
				- currentVelocity * LINEAR_DRAG
			currentVelocity += accel * dt
			if currentVelocity.Magnitude > MAX_SPEED then
				currentVelocity = currentVelocity.Unit * MAX_SPEED
			end

			throttleFrac = math.clamp(currentVelocity.Magnitude / 90, 0, 1)

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
			ao.CFrame = heading
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
		elseif bombSight and bombSight.active then
			-- belly bomb-sight camera: hangs under the drone looking straight down,
			-- screen-up stays lined up with the drone's heading
			camera.CFrame = CFrame.new(root.Position - Vector3.new(0, 1.5, 0))
				* CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(-math.pi / 2, 0, 0)
				* shake
			camera.FieldOfView = bombSight.fov
		else
			camera.CFrame = root.CFrame * CAMERA_OFFSET * shake
			camera.FieldOfView = FPV_FOV
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

--------------------------------------------------------------------
-- BOMB-SIGHT CAMERA ADD-ON (client)
-- Flying a Bomber: press C to toggle the belly camera (straight
-- down with a big crosshair), press Z to cycle zoom (1x / 2x / 4x).
-- NOTE: needs the matching bomb-sight edit in the main flight loop's
-- camera section.
--------------------------------------------------------------------
-- deliberately NOT "local": the main flight loop reads this too
bombSight = { active = false, fov = 60 }

do
	local ZOOM_LEVELS = {
		{ fov = 60, label = "1x" },
		{ fov = 30, label = "2x" },
		{ fov = 14, label = "4x" },
	}
	local zoomIndex = 1
	local sightGui = nil
	local zoomLabel = nil

	local function isBomberFlying()
		return flying ~= nil and flying.Parent ~= nil and flying.Name:lower():find("bomber") ~= nil
	end

	local SIGHT_COLOR = Color3.fromRGB(120, 255, 120)

	local function makeSightFrame(parent, size, position)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = position
		f.BackgroundColor3 = SIGHT_COLOR
		f.BackgroundTransparency = 0.25
		f.BorderSizePixel = 0
		f.Parent = parent
		return f
	end

	local function createSightGui()
		local gui = Instance.new("ScreenGui")
		gui.Name = "DroneBombSight"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 12

		-- big crosshair: four segments with a gap in the middle + a center dot
		makeSightFrame(gui, UDim2.new(0, 3, 0.2, 0), UDim2.new(0.5, 0, 0.5, -140)) -- top
		makeSightFrame(gui, UDim2.new(0, 3, 0.2, 0), UDim2.new(0.5, 0, 0.5, 140)) -- bottom
		makeSightFrame(gui, UDim2.new(0.14, 0, 0, 3), UDim2.new(0.5, -160, 0.5, 0)) -- left
		makeSightFrame(gui, UDim2.new(0.14, 0, 0, 3), UDim2.new(0.5, 160, 0.5, 0)) -- right
		makeSightFrame(gui, UDim2.new(0, 8, 0, 8), UDim2.new(0.5, 0, 0.5, 0)) -- center dot

		-- range tick marks along the vertical line (helps judge the grenade lead)
		for _, offset in { -70, 70 } do
			makeSightFrame(gui, UDim2.new(0, 24, 0, 3), UDim2.new(0.5, 0, 0.5, offset))
		end

		local mode = Instance.new("TextLabel")
		mode.AnchorPoint = Vector2.new(0.5, 0)
		mode.Position = UDim2.new(0.5, 0, 0, 96)
		mode.Size = UDim2.new(0, 520, 0, 24)
		mode.BackgroundTransparency = 1
		mode.Font = Enum.Font.Code
		mode.TextSize = 18
		mode.TextColor3 = SIGHT_COLOR
		mode.TextStrokeTransparency = 0.6
		mode.Text = "BOMB CAM  [C] FPV VIEW  [Z] ZOOM  [F] DROP"
		mode.Parent = gui

		zoomLabel = Instance.new("TextLabel")
		zoomLabel.AnchorPoint = Vector2.new(1, 0.5)
		zoomLabel.Position = UDim2.new(1, -40, 0.5, 0)
		zoomLabel.Size = UDim2.new(0, 160, 0, 30)
		zoomLabel.BackgroundTransparency = 1
		zoomLabel.Font = Enum.Font.Code
		zoomLabel.TextSize = 24
		zoomLabel.TextColor3 = SIGHT_COLOR
		zoomLabel.TextStrokeTransparency = 0.6
		zoomLabel.TextXAlignment = Enum.TextXAlignment.Right
		zoomLabel.Text = "ZOOM 1x"
		zoomLabel.Parent = gui

		gui.Parent = player:WaitForChild("PlayerGui")
		return gui
	end

	local function setSight(active)
		bombSight.active = active
		if active then
			zoomIndex = 1
			bombSight.fov = ZOOM_LEVELS[1].fov
			if not sightGui then
				sightGui = createSightGui()
			end
		else
			if sightGui then
				sightGui:Destroy()
				sightGui = nil
				zoomLabel = nil
			end
		end
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if not isBomberFlying() then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			setSight(not bombSight.active)
		elseif input.KeyCode == Enum.KeyCode.Z and bombSight.active then
			zoomIndex = zoomIndex % #ZOOM_LEVELS + 1
			bombSight.fov = ZOOM_LEVELS[zoomIndex].fov
			if zoomLabel then
				zoomLabel.Text = "ZOOM " .. ZOOM_LEVELS[zoomIndex].label
			end
		end
	end)

	-- drop back to FPV automatically when you exit or lose the drone
	task.spawn(function()
		while true do
			task.wait(0.25)
			if bombSight.active and not isBomberFlying() then
				setSight(false)
			end
		end
	end)
end

--------------------------------------------------------------------
-- RECON DRONE ADD-ON (client)
-- Flying a drone whose name contains "Recon":
--   T = mark the enemy under your crosshair (red glow + tag your
--       whole team can see through walls for ~6 seconds)
--   V = thermal vision: the world goes cold gray, warm bodies,
--       fires and drone motors glow white-hot (real thermal — it
--       detects heat, it does NOT see through walls)
--------------------------------------------------------------------
do
	local Lighting = game:GetService("Lighting")

	local markEvent = remotes:WaitForChild("DroneMark")

	local THERMAL_SCAN_RANGE = 500
	local MAX_HEAT_SOURCES = 25 -- Roblox caps visible Highlights, stay under it

	local function isReconFlying()
		return flying ~= nil and flying.Parent ~= nil and flying.Name:lower():find("recon") ~= nil
	end

	----------------------------------------------------------------
	-- receiving marks (every teammate's client runs this)
	----------------------------------------------------------------
	markEvent.OnClientEvent:Connect(function(character, duration)
		if typeof(character) ~= "Instance" or not character.Parent then
			return
		end
		-- refresh instead of stacking if the target is already marked
		local old = character:FindFirstChild("ReconMark")
		if old then
			old:Destroy()
		end
		local oldTag = character:FindFirstChild("ReconMarkTag")
		if oldTag then
			oldTag:Destroy()
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "ReconMark"
		highlight.FillColor = Color3.fromRGB(255, 60, 50)
		highlight.FillTransparency = 0.55
		highlight.OutlineColor = Color3.fromRGB(255, 90, 70)
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- marks DO show through walls
		highlight.Parent = character

		local tag = Instance.new("BillboardGui")
		tag.Name = "ReconMarkTag"
		tag.Size = UDim2.new(0, 130, 0, 28)
		tag.StudsOffset = Vector3.new(0, 3.6, 0)
		tag.AlwaysOnTop = true
		local tagText = Instance.new("TextLabel")
		tagText.Size = UDim2.new(1, 0, 1, 0)
		tagText.BackgroundTransparency = 1
		tagText.Font = Enum.Font.GothamBlack
		tagText.TextSize = 16
		tagText.TextColor3 = Color3.fromRGB(255, 80, 60)
		tagText.TextStrokeTransparency = 0.4
		tagText.Text = "▼ MARKED"
		tagText.Parent = tag
		tag.Parent = character

		task.delay(duration or 6, function()
			if highlight.Parent then
				highlight:Destroy()
			end
			if tag.Parent then
				tag:Destroy()
			end
		end)
	end)

	----------------------------------------------------------------
	-- recon HUD (hints + mark feedback), shown only while flying recon
	----------------------------------------------------------------
	local reconGui = nil
	local feedbackLabel = nil

	local function setFeedback(text, color)
		if feedbackLabel then
			feedbackLabel.Text = text
			feedbackLabel.TextColor3 = color
			feedbackLabel.TextTransparency = 0
			task.delay(1.2, function()
				if feedbackLabel then
					feedbackLabel.TextTransparency = 1
				end
			end)
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			if isReconFlying() then
				if not reconGui then
					reconGui = Instance.new("ScreenGui")
					reconGui.Name = "DroneReconHud"
					reconGui.ResetOnSpawn = false
					reconGui.DisplayOrder = 11

					local hints = Instance.new("TextLabel")
					hints.AnchorPoint = Vector2.new(0.5, 1)
					hints.Position = UDim2.new(0.5, 0, 1, -66)
					hints.Size = UDim2.new(0, 420, 0, 24)
					hints.BackgroundTransparency = 1
					hints.Font = Enum.Font.Code
					hints.TextSize = 17
					hints.TextColor3 = Color3.fromRGB(160, 200, 255)
					hints.TextStrokeTransparency = 0.6
					hints.Text = "RECON  ◈  [T] MARK TARGET  ◈  [V] THERMAL"
					hints.Parent = reconGui

					feedbackLabel = Instance.new("TextLabel")
					feedbackLabel.AnchorPoint = Vector2.new(0.5, 0.5)
					feedbackLabel.Position = UDim2.new(0.5, 0, 0.6, 0)
					feedbackLabel.Size = UDim2.new(0, 300, 0, 28)
					feedbackLabel.BackgroundTransparency = 1
					feedbackLabel.Font = Enum.Font.GothamBlack
					feedbackLabel.TextSize = 22
					feedbackLabel.TextTransparency = 1
					feedbackLabel.TextStrokeTransparency = 0.5
					feedbackLabel.Text = ""
					feedbackLabel.Parent = reconGui

					reconGui.Parent = player:WaitForChild("PlayerGui")
				end
			elseif reconGui then
				reconGui:Destroy()
				reconGui = nil
				feedbackLabel = nil
			end
		end
	end)

	----------------------------------------------------------------
	-- T: mark whatever is under the crosshair
	----------------------------------------------------------------
	local function tryMark()
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = { flying }
		if player.Character then
			table.insert(exclude, player.Character)
		end
		rayParams.FilterDescendantsInstances = exclude

		local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 320, rayParams)
		if hit then
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				markEvent:FireServer(model)
				setFeedback("◈ TARGET MARKED", Color3.fromRGB(255, 80, 60))
				return
			end
		end
		setFeedback("NO TARGET", Color3.fromRGB(160, 165, 160))
	end

	----------------------------------------------------------------
	-- V: thermal vision
	----------------------------------------------------------------
	local thermalOn = false

	local thermalCC = Instance.new("ColorCorrectionEffect")
	thermalCC.Name = "ReconThermal"
	thermalCC.Enabled = false
	thermalCC.Saturation = -1 -- the cold world loses all its color
	thermalCC.Contrast = 0.55
	thermalCC.Brightness = -0.08
	thermalCC.TintColor = Color3.fromRGB(170, 185, 210)
	thermalCC.Parent = Lighting

	local heatHighlights = {} -- [model or part] = Highlight

	local function clearHeat()
		for _, hl in heatHighlights do
			hl:Destroy()
		end
		table.clear(heatHighlights)
	end

	local function addHeat(target, fillColor, outlineColor, count)
		if heatHighlights[target] then
			return count
		end
		if count >= MAX_HEAT_SOURCES then
			return count
		end
		local hl = Instance.new("Highlight")
		hl.FillColor = fillColor
		hl.FillTransparency = 0.05
		hl.OutlineColor = outlineColor
		hl.OutlineTransparency = 0.4
		hl.DepthMode = Enum.HighlightDepthMode.Occluded -- heat doesn't glow through walls
		hl.Parent = target
		heatHighlights[target] = hl
		return count + 1
	end

	local function updateThermal()
		local camPos = camera.CFrame.Position
		local seen = {}
		local count = 0
		for _ in heatHighlights do
			count += 1
		end

		local BODY_FILL = Color3.fromRGB(255, 250, 235) -- white-hot
		local BODY_EDGE = Color3.fromRGB(255, 180, 90)
		local FIRE_FILL = Color3.fromRGB(255, 160, 60) -- burning-hot orange
		local FIRE_EDGE = Color3.fromRGB(255, 120, 30)

		-- warm bodies: other players
		for _, otherPlayer in Players:GetPlayers() do
			local character = otherPlayer ~= player and otherPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and hrp and (hrp.Position - camPos).Magnitude <= THERMAL_SCAN_RANGE then
				seen[character] = true
				count = addHeat(character, BODY_FILL, BODY_EDGE, count)
			end
		end

		-- warm bodies: NPCs
		local npcs = workspace:FindFirstChild("NPCs")
		if npcs then
			for _, model in npcs:GetChildren() do
				if model:IsA("Model") then
					local humanoid = model:FindFirstChildOfClass("Humanoid")
					local hrp = model:FindFirstChild("HumanoidRootPart")
					if humanoid and humanoid.Health > 0 and hrp and (hrp.Position - camPos).Magnitude <= THERMAL_SCAN_RANGE then
						seen[model] = true
						count = addHeat(model, BODY_FILL, BODY_EDGE, count)
					end
				end
			end
		end

		-- hot spots: fires, burning wreckage, live grenades
		for _, obj in workspace:GetChildren() do
			if obj:IsA("BasePart")
				and (obj.Name == "ExplosionFX" or obj.Name == "ExplosionScorch" or obj.Name == "DroneGrenade")
				and (obj.Position - camPos).Magnitude <= THERMAL_SCAN_RANGE then
				seen[obj] = true
				count = addHeat(obj, FIRE_FILL, FIRE_EDGE, count)
			end
		end

		-- other airborne drones run hot motors
		local drones = workspace:FindFirstChild("Drones")
		if drones then
			for _, d in drones:GetChildren() do
				if d:IsA("Model") and d ~= flying and d:GetAttribute("PilotUserId") and d.PrimaryPart
					and (d.PrimaryPart.Position - camPos).Magnitude <= THERMAL_SCAN_RANGE then
					seen[d] = true
					count = addHeat(d, FIRE_FILL, FIRE_EDGE, count)
				end
			end
		end

		-- cool off anything that left range or died
		for key, hl in heatHighlights do
			if not seen[key] or not key.Parent then
				hl:Destroy()
				heatHighlights[key] = nil
			end
		end
	end

	local function setThermal(on)
		thermalOn = on
		thermalCC.Enabled = on
		if on then
			setFeedback("THERMAL ON", Color3.fromRGB(255, 200, 120))
			updateThermal()
		else
			setFeedback("THERMAL OFF", Color3.fromRGB(160, 165, 160))
			clearHeat()
		end
	end

	-- thermal refresh loop + auto-shutoff when you leave the drone
	task.spawn(function()
		while true do
			task.wait(0.4)
			if thermalOn then
				if isReconFlying() then
					updateThermal()
				else
					thermalOn = false
					thermalCC.Enabled = false
					clearHeat()
				end
			end
		end
	end)

	----------------------------------------------------------------
	-- keys
	----------------------------------------------------------------
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isReconFlying() then
			return
		end
		if input.KeyCode == Enum.KeyCode.T then
			tryMark()
		elseif input.KeyCode == Enum.KeyCode.V then
			setThermal(not thermalOn)
		end
	end)
end
