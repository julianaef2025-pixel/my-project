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

-- flight tuning: classic direct control. W flies where you're looking
-- (aim down + W = dive), snappy response, no wind or gravity sag.
local MOVE_SPEED = 70 -- studs/sec
local VERTICAL_SPEED = 45 -- studs/sec up/down with Space/Shift
local RESPONSE = 8 -- higher = snappier speed changes
local MOUSE_SENSITIVITY = 0.0035 -- radians per pixel of mouse movement

-- filled in by the on-screen touch controls (bottom of this script);
-- the flight loop adds these on top of the keyboard every frame
local mobile = { forward = 0, strafe = 0, vertical = 0, lookX = 0, lookY = 0 }
local MAX_PITCH = math.rad(75)
local BANK_ANGLE = math.rad(20) -- visual roll when strafing
local FORWARD_TILT = math.rad(10) -- visual nose-down lean when flying forward
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
			-- steer with the mouse or a touch-drag (unless the recon gimbal has it)
			local delta = UserInputService:GetMouseDelta()
			local deltaX = delta.X + mobile.lookX
			local deltaY = delta.Y + mobile.lookY
			mobile.lookX, mobile.lookY = 0, 0
			if reconSight and reconSight.active then
				-- gimbal slew: slower when zoomed in, like a real camera operator
				local slew = MOUSE_SENSITIVITY * (reconSight.fov / 60)
				reconSight.yaw -= deltaX * slew
				reconSight.pitch = math.clamp(reconSight.pitch - deltaY * slew, -math.rad(89), math.rad(25))
			else
				yaw -= deltaX * MOUSE_SENSITIVITY
				pitch = math.clamp(pitch - deltaY * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
			end

			-- movement input: keyboard + the mobile joystick/buttons
			local forward = mobile.forward
			local strafe = mobile.strafe
			local vertical = mobile.vertical
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then forward += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then forward -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then strafe += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then strafe -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vertical += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then vertical -= 1 end
			forward = math.clamp(forward, -1, 1)
			strafe = math.clamp(strafe, -1, 1)
			vertical = math.clamp(vertical, -1, 1)

			-- === classic flight: direct velocity control ===
			-- W flies exactly where the camera looks (aim down = dive),
			-- A/D strafe, Space/Shift up/down — instant and responsive
			local aimRotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)

			local targetVelocity = (aimRotation.LookVector * forward + aimRotation.RightVector * strafe) * MOVE_SPEED
				+ Vector3.new(0, vertical * VERTICAL_SPEED, 0)
			currentVelocity = currentVelocity:Lerp(targetVelocity, math.min(dt * RESPONSE, 1))

			throttleFrac = math.clamp(currentVelocity.Magnitude / MOVE_SPEED, 0, 1)

			-- visual banking + forward lean (looks, not physics)
			local targetRoll = -strafe * BANK_ANGLE
			roll += (targetRoll - roll) * math.min(dt * 8, 1)
			local targetTilt = forward * FORWARD_TILT
			tilt += (targetTilt - tilt) * math.min(dt * 5, 1)

			lv.VectorVelocity = currentVelocity
			ao.CFrame = CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(pitch - tilt, 0, 0)
				* CFrame.Angles(0, 0, roll)

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
		elseif reconSight and reconSight.active then
			-- gyro-stabilized recon gimbal: aim anywhere, zero vibration
			camera.CFrame = CFrame.new(root.Position - Vector3.new(0, 1, 0))
				* CFrame.Angles(0, reconSight.yaw, 0)
				* CFrame.Angles(reconSight.pitch, 0, 0)
			camera.FieldOfView = reconSight.fov
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
	-- X exits the drone EVEN IF a gun system (ACS) grabbed the key —
	-- while flying, leaving the drone always wins
	if input.KeyCode == Enum.KeyCode.X and flying then
		stopFlying(true)
		return
	end
	if gameProcessed then
		return
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
		-- while flying, drone keys win even if a gun system grabbed them
		if gameProcessed and not flying then
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
		-- while flying, drone keys win even if a gun system grabbed them
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
-- RECON DRONE ADD-ON v2 (client)
-- Flying a drone whose name contains "Recon":
--   C = gyro-stabilized GIMBAL camera: mouse aims the camera freely
--       while WASD keeps flying the drone (orbit your target!)
--   Z = gimbal zoom: 1x / 2x / 5x / 15x
--   T = mark what's under the crosshair — people get a moving red
--       mark, ground/buildings get a 20s target-point beacon with
--       live distance, visible to your whole team
--   V = thermal vision: real heat detection (no wallhacks)
-- Needs the reconSight edits in the main flight loop.
--------------------------------------------------------------------
-- deliberately NOT "local": the main flight loop reads this too
reconSight = { active = false, fov = 60, yaw = 0, pitch = 0 }

do
	local Lighting = game:GetService("Lighting")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")

	local markEvent = remotes:WaitForChild("DroneMark")

	local THERMAL_SCAN_RANGE = 500
	local MAX_HEAT_SOURCES = 25
	local MARK_RAY_RANGE = 1200

	local ZOOM_LEVELS = {
		{ fov = 60, label = "1x" },
		{ fov = 30, label = "2x" },
		{ fov = 12, label = "5x" },
		{ fov = 4, label = "15x" },
	}
	local zoomIndex = 1

	local function isReconFlying()
		return flying ~= nil and flying.Parent ~= nil and flying.Name:lower():find("recon") ~= nil
	end

	----------------------------------------------------------------
	-- receiving marks (every teammate's client runs this)
	----------------------------------------------------------------

	-- red beacon planted on a marked spot (ground / building)
	local function createLocationMarker(position, duration)
		local marker = Instance.new("Part")
		marker.Name = "ReconLocationMarker"
		marker.Size = Vector3.new(1, 1, 1)
		marker.Position = position
		marker.Transparency = 1
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Parent = workspace

		-- light column reaching up from the spot
		local column = Instance.new("Part")
		column.Name = "Column"
		column.Shape = Enum.PartType.Cylinder
		column.Size = Vector3.new(36, 1.4, 1.4)
		column.CFrame = CFrame.new(position + Vector3.new(0, 18, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		column.Material = Enum.Material.Neon
		column.Color = Color3.fromRGB(255, 70, 60)
		column.Transparency = 0.6
		column.Anchored = true
		column.CanCollide = false
		column.CanQuery = false
		column.CanTouch = false
		column.CastShadow = false
		column.Parent = marker

		-- pulsing ring at the base
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.3, 8, 8)
		ring.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(255, 70, 60)
		ring.Transparency = 0.3
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Parent = marker

		-- floating tag with live distance
		local tag = Instance.new("BillboardGui")
		tag.Name = "Tag"
		tag.Size = UDim2.new(0, 170, 0, 44)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 39, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 2500
		local tagText = Instance.new("TextLabel")
		tagText.Size = UDim2.new(1, 0, 1, 0)
		tagText.BackgroundTransparency = 1
		tagText.Font = Enum.Font.Code
		tagText.TextSize = 17
		tagText.TextColor3 = Color3.fromRGB(255, 90, 70)
		tagText.TextStrokeTransparency = 0.4
		tagText.Text = "◈ TARGET POINT"
		tagText.Parent = tag
		tag.Parent = marker

		-- pulse the ring and keep the distance readout live
		task.spawn(function()
			local t0 = os.clock()
			while marker.Parent do
				local pulse = (math.sin((os.clock() - t0) * 4) + 1) / 2
				ring.Transparency = 0.2 + pulse * 0.5
				ring.Size = Vector3.new(0.3, 7 + pulse * 3, 7 + pulse * 3)
				local myPos = camera.CFrame.Position
				tagText.Text = string.format("◈ TARGET POINT\n%d studs", math.floor((position - myPos).Magnitude + 0.5))
				task.wait(0.15)
			end
		end)

		Debris:AddItem(marker, duration)
	end

	markEvent.OnClientEvent:Connect(function(target, duration)
		if typeof(target) == "Vector3" then
			createLocationMarker(target, duration or 20)
			return
		end
		if typeof(target) ~= "Instance" or not target.Parent then
			return
		end
		-- person mark: refresh instead of stacking
		local old = target:FindFirstChild("ReconMark")
		if old then
			old:Destroy()
		end
		local oldTag = target:FindFirstChild("ReconMarkTag")
		if oldTag then
			oldTag:Destroy()
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "ReconMark"
		highlight.FillColor = Color3.fromRGB(255, 60, 50)
		highlight.FillTransparency = 0.55
		highlight.OutlineColor = Color3.fromRGB(255, 90, 70)
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = target

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
		tag.Parent = target

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
	-- recon HUD: hints, feedback, gimbal overlay
	----------------------------------------------------------------
	local reconGui = nil
	local feedbackLabel = nil
	local gimbalFrame = nil
	local zoomLabel = nil
	local rangeLabel = nil

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

	local SIGHT_GREEN = Color3.fromRGB(140, 255, 160)

	local function buildReconGui()
		reconGui = Instance.new("ScreenGui")
		reconGui.Name = "DroneReconHud"
		reconGui.ResetOnSpawn = false
		reconGui.IgnoreGuiInset = true
		reconGui.DisplayOrder = 11

		local hints = Instance.new("TextLabel")
		hints.AnchorPoint = Vector2.new(0.5, 1)
		hints.Position = UDim2.new(0.5, 0, 1, -66)
		hints.Size = UDim2.new(0, 560, 0, 24)
		hints.BackgroundTransparency = 1
		hints.Font = Enum.Font.Code
		hints.TextSize = 17
		hints.TextColor3 = Color3.fromRGB(160, 200, 255)
		hints.TextStrokeTransparency = 0.6
		hints.Text = "RECON  ◈  [C] GIMBAL  [Z] ZOOM  [T] MARK  [V] THERMAL"
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

		-- gimbal overlay: fine crosshair, brackets, zoom + range readouts
		gimbalFrame = Instance.new("Frame")
		gimbalFrame.Size = UDim2.new(1, 0, 1, 0)
		gimbalFrame.BackgroundTransparency = 1
		gimbalFrame.Visible = false
		gimbalFrame.Parent = reconGui

		local function sightLine(size, position)
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Size = size
			f.Position = position
			f.BackgroundColor3 = SIGHT_GREEN
			f.BackgroundTransparency = 0.25
			f.BorderSizePixel = 0
			f.Parent = gimbalFrame
			return f
		end

		-- fine cross
		sightLine(UDim2.new(0, 1, 0, 60), UDim2.new(0.5, 0, 0.5, -50))
		sightLine(UDim2.new(0, 1, 0, 60), UDim2.new(0.5, 0, 0.5, 50))
		sightLine(UDim2.new(0, 60, 0, 1), UDim2.new(0.5, -50, 0.5, 0))
		sightLine(UDim2.new(0, 60, 0, 1), UDim2.new(0.5, 50, 0.5, 0))
		sightLine(UDim2.new(0, 4, 0, 4), UDim2.new(0.5, 0, 0.5, 0))
		-- corner brackets
		for _, cx in { -1, 1 } do
			for _, cy in { -1, 1 } do
				sightLine(UDim2.new(0, 34, 0, 2), UDim2.new(0.5, cx * 190, 0.5, cy * 150))
				sightLine(UDim2.new(0, 2, 0, 34), UDim2.new(0.5, cx * 190, 0.5, cy * 150))
			end
		end

		local mode = Instance.new("TextLabel")
		mode.AnchorPoint = Vector2.new(0.5, 0)
		mode.Position = UDim2.new(0.5, 0, 0, 96)
		mode.Size = UDim2.new(0, 520, 0, 24)
		mode.BackgroundTransparency = 1
		mode.Font = Enum.Font.Code
		mode.TextSize = 17
		mode.TextColor3 = SIGHT_GREEN
		mode.TextStrokeTransparency = 0.6
		mode.Text = "◈ GIMBAL — GYRO STABILIZED"
		mode.Parent = gimbalFrame

		zoomLabel = Instance.new("TextLabel")
		zoomLabel.AnchorPoint = Vector2.new(1, 0.5)
		zoomLabel.Position = UDim2.new(1, -40, 0.5, 0)
		zoomLabel.Size = UDim2.new(0, 160, 0, 30)
		zoomLabel.BackgroundTransparency = 1
		zoomLabel.Font = Enum.Font.Code
		zoomLabel.TextSize = 24
		zoomLabel.TextColor3 = SIGHT_GREEN
		zoomLabel.TextStrokeTransparency = 0.6
		zoomLabel.TextXAlignment = Enum.TextXAlignment.Right
		zoomLabel.Text = "ZOOM 1x"
		zoomLabel.Parent = gimbalFrame

		rangeLabel = Instance.new("TextLabel")
		rangeLabel.AnchorPoint = Vector2.new(0, 0.5)
		rangeLabel.Position = UDim2.new(0, 40, 0.5, 0)
		rangeLabel.Size = UDim2.new(0, 200, 0, 30)
		rangeLabel.BackgroundTransparency = 1
		rangeLabel.Font = Enum.Font.Code
		rangeLabel.TextSize = 20
		rangeLabel.TextColor3 = SIGHT_GREEN
		rangeLabel.TextStrokeTransparency = 0.6
		rangeLabel.TextXAlignment = Enum.TextXAlignment.Left
		rangeLabel.Text = "TGT ---"
		rangeLabel.Parent = gimbalFrame

		reconGui.Parent = player:WaitForChild("PlayerGui")
	end

	----------------------------------------------------------------
	-- gimbal control
	----------------------------------------------------------------
	local function setGimbal(active)
		reconSight.active = active
		if gimbalFrame then
			gimbalFrame.Visible = active
		end
		if active then
			-- start the gimbal looking where the camera currently looks
			local look = camera.CFrame.LookVector
			reconSight.yaw = math.atan2(-look.X, -look.Z)
			reconSight.pitch = math.asin(math.clamp(look.Y, -1, 1))
			zoomIndex = 1
			reconSight.fov = ZOOM_LEVELS[1].fov
			if zoomLabel then
				zoomLabel.Text = "ZOOM " .. ZOOM_LEVELS[1].label
			end
		end
	end

	-- live range-to-target readout while the gimbal is up
	task.spawn(function()
		while true do
			task.wait(0.25)
			if reconSight.active and rangeLabel and isReconFlying() then
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local exclude = { flying }
				if player.Character then
					table.insert(exclude, player.Character)
				end
				rayParams.FilterDescendantsInstances = exclude
				local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 3000, rayParams)
				rangeLabel.Text = hit and string.format("TGT %d", math.floor((hit.Position - camera.CFrame.Position).Magnitude + 0.5)) or "TGT ---"
			end
		end
	end)

	----------------------------------------------------------------
	-- HUD lifecycle
	----------------------------------------------------------------
	task.spawn(function()
		while true do
			task.wait(0.25)
			if isReconFlying() then
				if not reconGui then
					buildReconGui()
				end
			elseif reconGui then
				reconGui:Destroy()
				reconGui = nil
				feedbackLabel = nil
				gimbalFrame = nil
				zoomLabel = nil
				rangeLabel = nil
				reconSight.active = false
			end
		end
	end)

	----------------------------------------------------------------
	-- T: mark whatever is under the crosshair (person OR location)
	----------------------------------------------------------------
	local function tryMark()
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = { flying }
		if player.Character then
			table.insert(exclude, player.Character)
		end
		rayParams.FilterDescendantsInstances = exclude

		local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * MARK_RAY_RANGE, rayParams)
		if not hit then
			setFeedback("NO TARGET", Color3.fromRGB(160, 165, 160))
			return
		end

		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			markEvent:FireServer(model)
			setFeedback("◈ TARGET MARKED", Color3.fromRGB(255, 80, 60))
		else
			markEvent:FireServer(hit.Position)
			setFeedback("◈ LOCATION MARKED", Color3.fromRGB(255, 140, 80))
		end
	end

	----------------------------------------------------------------
	-- V: thermal vision
	----------------------------------------------------------------
	local thermalOn = false

	local thermalCC = Instance.new("ColorCorrectionEffect")
	thermalCC.Name = "ReconThermal"
	thermalCC.Enabled = false
	thermalCC.Saturation = -1
	thermalCC.Contrast = 0.55
	thermalCC.Brightness = -0.08
	thermalCC.TintColor = Color3.fromRGB(170, 185, 210)
	thermalCC.Parent = Lighting

	local heatHighlights = {}

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
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
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

		local BODY_FILL = Color3.fromRGB(255, 250, 235)
		local BODY_EDGE = Color3.fromRGB(255, 180, 90)
		local FIRE_FILL = Color3.fromRGB(255, 160, 60)
		local FIRE_EDGE = Color3.fromRGB(255, 120, 30)

		for _, otherPlayer in Players:GetPlayers() do
			local character = otherPlayer ~= player and otherPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and hrp and (hrp.Position - camPos).Magnitude <= THERMAL_SCAN_RANGE then
				seen[character] = true
				count = addHeat(character, BODY_FILL, BODY_EDGE, count)
			end
		end

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

		for _, obj in workspace:GetChildren() do
			if obj:IsA("BasePart")
				and (obj.Name == "ExplosionFX" or obj.Name == "ExplosionScorch" or obj.Name == "DroneGrenade")
				and (obj.Position - camPos).Magnitude <= THERMAL_SCAN_RANGE then
				seen[obj] = true
				count = addHeat(obj, FIRE_FILL, FIRE_EDGE, count)
			end
		end

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
		-- while flying, drone keys win even if a gun system grabbed them
		if not isReconFlying() then
			return
		end
		if input.KeyCode == Enum.KeyCode.T then
			tryMark()
		elseif input.KeyCode == Enum.KeyCode.V then
			setThermal(not thermalOn)
		elseif input.KeyCode == Enum.KeyCode.C then
			setGimbal(not reconSight.active)
		elseif input.KeyCode == Enum.KeyCode.Z and reconSight.active then
			zoomIndex = zoomIndex % #ZOOM_LEVELS + 1
			reconSight.fov = ZOOM_LEVELS[zoomIndex].fov
			if zoomLabel then
				zoomLabel.Text = "ZOOM " .. ZOOM_LEVELS[zoomIndex].label
			end
		end
	end)
end

--------------------------------------------------------------------
-- BOMBER REARM ADD-ON (client)
-- When the bomber is out of grenades: flashing RETURN TO BASE with
-- an arrow pointing at the nearest rearm zone + distance. Inside
-- the zone: a green REARMING indicator while grenades refill.
--------------------------------------------------------------------
do
	local rearmGui = nil
	local statusLabel = nil
	local arrowLabel = nil

	local function isBomberFlying()
		return flying ~= nil and flying.Parent ~= nil and flying.Name:lower():find("bomber") ~= nil
	end

	local function nearestZone(fromPosition)
		local folder = workspace:FindFirstChild("RearmZones")
		if not folder then
			return nil
		end
		local best, bestDist
		for _, zone in folder:GetChildren() do
			if zone:IsA("BasePart") then
				local d = (zone.Position - fromPosition).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = zone, d
				end
			end
		end
		return best, bestDist
	end

	local function buildGui()
		rearmGui = Instance.new("ScreenGui")
		rearmGui.Name = "DroneRearmHud"
		rearmGui.ResetOnSpawn = false
		rearmGui.DisplayOrder = 11

		statusLabel = Instance.new("TextLabel")
		statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		statusLabel.Position = UDim2.new(0.5, 0, 0.34, 0)
		statusLabel.Size = UDim2.new(0, 520, 0, 30)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.GothamBlack
		statusLabel.TextSize = 24
		statusLabel.TextStrokeTransparency = 0.5
		statusLabel.Text = ""
		statusLabel.Parent = rearmGui

		arrowLabel = Instance.new("TextLabel")
		arrowLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		arrowLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
		arrowLabel.Size = UDim2.new(0, 60, 0, 60)
		arrowLabel.BackgroundTransparency = 1
		arrowLabel.Font = Enum.Font.GothamBlack
		arrowLabel.TextSize = 44
		arrowLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
		arrowLabel.TextStrokeTransparency = 0.5
		arrowLabel.Text = "⬆"
		arrowLabel.Visible = false
		arrowLabel.Parent = rearmGui

		rearmGui.Parent = player:WaitForChild("PlayerGui")
	end

	task.spawn(function()
		local clock = 0
		while true do
			task.wait(0.1)
			clock += 0.1

			if not isBomberFlying() then
				if rearmGui then
					rearmGui:Destroy()
					rearmGui = nil
					statusLabel = nil
					arrowLabel = nil
				end
				continue
			end

			if not rearmGui then
				buildGui()
			end

			local drone = flying
			local root = drone.PrimaryPart
			local ammo = drone:GetAttribute("Grenades") or 0
			local rearming = drone:GetAttribute("Rearming") == true

			if rearming then
				statusLabel.Text = "⟳ REARMING GRENADES..."
				statusLabel.TextColor3 = Color3.fromRGB(120, 230, 140)
				statusLabel.TextTransparency = 0
				arrowLabel.Visible = false
			elseif ammo <= 0 and root then
				local zone, dist = nearestZone(root.Position)
				if zone then
					-- flashing RTB warning
					statusLabel.Text = string.format("OUT OF AMMO — RETURN TO BASE (%d studs)", math.floor(dist + 0.5))
					statusLabel.TextColor3 = Color3.fromRGB(255, 90, 60)
					statusLabel.TextTransparency = (math.floor(clock * 3) % 2 == 0) and 0 or 0.6

					-- arrow that points toward the rearm zone relative to your view
					local dir = camera.CFrame:VectorToObjectSpace(zone.Position - root.Position)
					local angle = math.deg(math.atan2(dir.X, -dir.Z))
					arrowLabel.Rotation = angle
					arrowLabel.Visible = true
				else
					statusLabel.Text = "OUT OF AMMO"
					statusLabel.TextColor3 = Color3.fromRGB(255, 90, 60)
					arrowLabel.Visible = false
				end
			else
				statusLabel.Text = ""
				arrowLabel.Visible = false
			end
		end
	end)
end

--------------------------------------------------------------------
-- RPG DRONE ADD-ON (client)
-- Flying a drone whose name contains "RPG" or "Rocket": press F to
-- launch a rocket exactly where you're aiming. HUD shows your two
-- rockets, reload state, and rearm status.
--------------------------------------------------------------------
do
	local fireEvent = remotes:WaitForChild("DroneFireRocket")

	local ROCKET_COOLDOWN = 1.5

	local rpgGui = nil
	local ammoLabel = nil
	local lastShot = 0

	local function isRPGFlying()
		if flying == nil or flying.Parent == nil then
			return false
		end
		local n = flying.Name:lower()
		return n:find("rpg") ~= nil or n:find("rocket") ~= nil
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- while flying, drone keys win even if a gun system grabbed them
		if not isRPGFlying() then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			if os.clock() - lastShot < ROCKET_COOLDOWN then
				return
			end
			lastShot = os.clock()
			-- fire exactly where the FPV camera is aiming
			fireEvent:FireServer(flying, camera.CFrame.LookVector)
		end
	end)

	task.spawn(function()
		local clock = 0
		while true do
			task.wait(0.15)
			clock += 0.15

			if not isRPGFlying() then
				if rpgGui then
					rpgGui:Destroy()
					rpgGui = nil
					ammoLabel = nil
				end
				continue
			end

			if not rpgGui then
				rpgGui = Instance.new("ScreenGui")
				rpgGui.Name = "DroneRPGHud"
				rpgGui.ResetOnSpawn = false
				rpgGui.DisplayOrder = 11

				ammoLabel = Instance.new("TextLabel")
				ammoLabel.AnchorPoint = Vector2.new(0.5, 1)
				ammoLabel.Position = UDim2.new(0.5, 0, 1, -66)
				ammoLabel.Size = UDim2.new(0, 420, 0, 24)
				ammoLabel.BackgroundTransparency = 1
				ammoLabel.Font = Enum.Font.Code
				ammoLabel.TextSize = 18
				ammoLabel.TextColor3 = Color3.fromRGB(255, 190, 120)
				ammoLabel.TextStrokeTransparency = 0.6
				ammoLabel.Parent = rpgGui

				rpgGui.Parent = player:WaitForChild("PlayerGui")
			end

			local rockets = flying:GetAttribute("Rockets") or 0
			local rearming = flying:GetAttribute("Rearming") == true
			local reloading = os.clock() - lastShot < ROCKET_COOLDOWN

			if rearming then
				ammoLabel.Text = "⟳ RELOADING ROCKETS..."
				ammoLabel.TextColor3 = Color3.fromRGB(120, 230, 140)
				ammoLabel.TextTransparency = 0
			elseif rockets <= 0 then
				ammoLabel.Text = "OUT OF ROCKETS — REARM AT BASE"
				ammoLabel.TextColor3 = Color3.fromRGB(255, 90, 60)
				ammoLabel.TextTransparency = (math.floor(clock * 3) % 2 == 0) and 0 or 0.55
			elseif reloading then
				ammoLabel.Text = "ROCKETS " .. string.rep("▰ ", rockets) .. string.rep("▱ ", math.max(2 - rockets, 0)) .. " RELOADING..."
				ammoLabel.TextColor3 = Color3.fromRGB(200, 200, 190)
				ammoLabel.TextTransparency = 0
			else
				ammoLabel.Text = "ROCKETS " .. string.rep("▰ ", rockets) .. string.rep("▱ ", math.max(2 - rockets, 0)) .. " [F] FIRE"
				ammoLabel.TextColor3 = Color3.fromRGB(255, 190, 120)
				ammoLabel.TextTransparency = 0
			end
		end
	end)
end

--------------------------------------------------------------------
-- RPG DONKEY ADD-ON (client)
-- When you sit on anything named "Donkey", a bar pops up at the
-- bottom: press F to fire its side RPGs where your camera is looking.
--------------------------------------------------------------------
do
	local PlayersService = game:GetService("Players")
	local UserInput = game:GetService("UserInputService")
	local Replicated = game:GetService("ReplicatedStorage")

	local localPlayer = PlayersService.LocalPlayer
	local donkeyFire = Replicated:WaitForChild("DroneRemotes"):WaitForChild("DonkeyFireRocket")

	local riding -- the donkey model while sitting on one

	local donkeyGui = Instance.new("ScreenGui")
	donkeyGui.Name = "DonkeyGunner"
	donkeyGui.ResetOnSpawn = false
	donkeyGui.Enabled = false
	donkeyGui.Parent = localPlayer:WaitForChild("PlayerGui")

	local donkeyBar = Instance.new("TextLabel")
	donkeyBar.AnchorPoint = Vector2.new(0.5, 1)
	donkeyBar.Position = UDim2.new(0.5, 0, 1, -16)
	donkeyBar.Size = UDim2.new(0, 460, 0, 36)
	donkeyBar.BackgroundColor3 = Color3.fromRGB(22, 24, 18)
	donkeyBar.BackgroundTransparency = 0.3
	donkeyBar.TextColor3 = Color3.fromRGB(255, 200, 90)
	donkeyBar.Font = Enum.Font.Code
	donkeyBar.TextSize = 20
	donkeyBar.Text = ""
	donkeyBar.Parent = donkeyGui
	local donkeyCorner = Instance.new("UICorner")
	donkeyCorner.CornerRadius = UDim.new(0, 8)
	donkeyCorner.Parent = donkeyBar

	local function refreshDonkeyBar()
		if not riding then
			return
		end
		local ammo = riding:GetAttribute("Rockets") or 0
		donkeyBar.Text = "🫏 RPG DONKEY   [F] FIRE   ROCKETS: "
			.. string.rep("▰", ammo) .. string.rep("▱", math.max(6 - ammo, 0))
		donkeyBar.TextColor3 = ammo > 0
			and Color3.fromRGB(255, 200, 90)
			or Color3.fromRGB(255, 90, 70)
	end

	local function isDonkeyModel(model)
		return model and model.Name:lower():find("donkey") ~= nil
	end

	local function watchSeat(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Seated:Connect(function(active, seat)
			riding = nil
			if active and seat then
				local model = seat:FindFirstAncestorOfClass("Model")
				while model and not isDonkeyModel(model) do
					model = model:FindFirstAncestorOfClass("Model")
				end
				riding = model
			end
			donkeyGui.Enabled = riding ~= nil
			refreshDonkeyBar()
		end)
	end
	if localPlayer.Character then
		task.spawn(watchSeat, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(watchSeat)

	-- keep the ammo readout fresh while riding
	task.spawn(function()
		while true do
			task.wait(0.3)
			if riding then
				refreshDonkeyBar()
			end
		end
	end)

	UserInput.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not riding then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			local cam = workspace.CurrentCamera
			if cam then
				-- find the exact spot the crosshair is on and send that,
				-- so the rocket lands where you're looking
				local origin = cam.CFrame.Position
				local look = cam.CFrame.LookVector
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local exclude = { riding }
				if localPlayer.Character then
					table.insert(exclude, localPlayer.Character)
				end
				rayParams.FilterDescendantsInstances = exclude
				local hit = workspace:Raycast(origin, look * 1000, rayParams)
				local aimPoint = hit and hit.Position or (origin + look * 1000)
				donkeyFire:FireServer(riding, aimPoint)
			end
		end
	end)
end

--------------------------------------------------------------------
-- FRIENDLY DRONE MARKERS (client)
-- Drones flown by YOUR team get a little green dot over them (only
-- you and your teammates see it) so AA gunners don't shoot friends.
--------------------------------------------------------------------
do
	local PlayersService = game:GetService("Players")
	local localPlayer = PlayersService.LocalPlayer

	local function makeTag(root)
		local tag = Instance.new("BillboardGui")
		tag.Name = "FriendlyTag"
		tag.Size = UDim2.new(0, 60, 0, 30)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 1500
		tag.Adornee = root

		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0)
		dot.Position = UDim2.new(0.5, 0, 0, 0)
		dot.Size = UDim2.new(0, 10, 0, 10)
		dot.BackgroundColor3 = Color3.fromRGB(80, 230, 110)
		dot.BorderSizePixel = 0
		dot.Parent = tag
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(0.5, 0)
		dotCorner.Parent = dot
		local dotStroke = Instance.new("UIStroke")
		dotStroke.Color = Color3.fromRGB(10, 40, 15)
		dotStroke.Thickness = 1.5
		dotStroke.Parent = dot

		local tagText = Instance.new("TextLabel")
		tagText.AnchorPoint = Vector2.new(0.5, 0)
		tagText.Position = UDim2.new(0.5, 0, 0, 12)
		tagText.Size = UDim2.new(1, 0, 0, 12)
		tagText.BackgroundTransparency = 1
		tagText.Font = Enum.Font.Code
		tagText.TextSize = 11
		tagText.TextColor3 = Color3.fromRGB(80, 230, 110)
		tagText.TextStrokeTransparency = 0.4
		tagText.Text = "FRIENDLY"
		tagText.Parent = tag

		tag.Parent = root
		return tag
	end

	task.spawn(function()
		while true do
			task.wait(1)
			local folder = workspace:FindFirstChild("Drones")
			if folder then
				for _, drone in folder:GetChildren() do
					if drone:IsA("Model") then
						-- who does this drone belong to? the current pilot,
						-- or whoever ordered it if it's parked
						local ownerId = drone:GetAttribute("PilotUserId")
							or drone:GetAttribute("OwnerUserId")
						local owner = ownerId and PlayersService:GetPlayerByUserId(ownerId)
						local friendly = owner ~= nil
							and localPlayer.Team ~= nil
							and owner.Team == localPlayer.Team
						local root = drone.PrimaryPart
							or drone:FindFirstChildWhichIsA("BasePart", true)
						local tag = root and root:FindFirstChild("FriendlyTag")
						if friendly and root and not tag then
							makeTag(root)
						elseif not friendly and tag then
							tag:Destroy()
						end
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------
-- MOBILE CONTROLS ADD-ON (client)
-- Touch screens get a full drone cockpit while flying:
-- left joystick = move, drag anywhere = look, UP/DOWN = altitude,
-- FIRE/DROP for bomber + RPG, big red EXIT. Appears only on touch
-- devices and only while flying.
--------------------------------------------------------------------
if UserInputService.TouchEnabled then
	local mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = "DroneMobile"
	mobileGui.ResetOnSpawn = false
	mobileGui.DisplayOrder = 60
	mobileGui.Enabled = false
	mobileGui.Parent = player:WaitForChild("PlayerGui")

	-- drag anywhere (not on a button) to look around
	UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
		if gameProcessed or not flying then
			return
		end
		mobile.lookX += touch.Delta.X * 1.4
		mobile.lookY += touch.Delta.Y * 1.4
	end)

	-- left joystick ---------------------------------------------------
	local stickBase = Instance.new("Frame")
	stickBase.AnchorPoint = Vector2.new(0, 1)
	stickBase.Position = UDim2.new(0, 24, 1, -24)
	stickBase.Size = UDim2.new(0, 130, 0, 130)
	stickBase.BackgroundColor3 = Color3.fromRGB(20, 24, 20)
	stickBase.BackgroundTransparency = 0.5
	stickBase.BorderSizePixel = 0
	stickBase.Active = true
	stickBase.Parent = mobileGui
	local baseCorner = Instance.new("UICorner")
	baseCorner.CornerRadius = UDim.new(0.5, 0)
	baseCorner.Parent = stickBase
	local baseStroke = Instance.new("UIStroke")
	baseStroke.Color = Color3.fromRGB(120, 200, 120)
	baseStroke.Transparency = 0.6
	baseStroke.Parent = stickBase

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0.5, 0, 0.5, 0)
	knob.Size = UDim2.new(0, 52, 0, 52)
	knob.BackgroundColor3 = Color3.fromRGB(120, 200, 120)
	knob.BackgroundTransparency = 0.25
	knob.BorderSizePixel = 0
	knob.Parent = stickBase
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0.5, 0)
	knobCorner.Parent = knob

	local stickTouch
	local function moveStick(position)
		local center = stickBase.AbsolutePosition + stickBase.AbsoluteSize / 2
		local offset = Vector2.new(position.X, position.Y) - center
		local radius = stickBase.AbsoluteSize.X / 2
		if offset.Magnitude > radius then
			offset = offset.Unit * radius
		end
		knob.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		mobile.strafe = offset.X / radius
		mobile.forward = -offset.Y / radius
	end
	local function releaseStick()
		stickTouch = nil
		knob.Position = UDim2.new(0.5, 0, 0.5, 0)
		mobile.strafe = 0
		mobile.forward = 0
	end
	stickBase.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not stickTouch then
			stickTouch = input
			moveStick(input.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == stickTouch then
			moveStick(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == stickTouch then
			releaseStick()
		end
	end)

	-- buttons -----------------------------------------------------------
	local function makeButton(text, size, position, color)
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = position
		button.Size = size
		button.BackgroundColor3 = Color3.fromRGB(20, 24, 20)
		button.BackgroundTransparency = 0.4
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 16
		button.TextColor3 = color
		button.Text = text
		button.BorderSizePixel = 0
		button.Active = true
		button.Parent = mobileGui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Transparency = 0.5
		stroke.Parent = button
		return button
	end

	-- altitude: hold UP / DOWN (right side, stacked)
	local upButton = makeButton("▲ UP", UDim2.new(0, 84, 0, 64),
		UDim2.new(1, -24, 1, -178), Color3.fromRGB(120, 200, 255))
	local downButton = makeButton("▼ DOWN", UDim2.new(0, 84, 0, 64),
		UDim2.new(1, -24, 1, -104), Color3.fromRGB(120, 200, 255))

	local function holdable(button, value)
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				mobile.vertical = value
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if mobile.vertical == value then
					mobile.vertical = 0
				end
			end
		end)
	end
	holdable(upButton, 1)
	holdable(downButton, -1)

	-- FIRE / DROP (only shows on bomber + rpg drones)
	local fireButton = makeButton("💥 FIRE", UDim2.new(0, 110, 0, 64),
		UDim2.new(1, -118, 1, -104), Color3.fromRGB(255, 150, 80))
	local mobileLastRocket = 0
	fireButton.MouseButton1Click:Connect(function()
		if not flying then
			return
		end
		local name = flying.Name:lower()
		if name:find("bomber") then
			remotes:WaitForChild("DroneDropGrenade"):FireServer(flying)
		elseif name:find("rpg") or name:find("rocket") then
			if os.clock() - mobileLastRocket >= 1.5 then
				mobileLastRocket = os.clock()
				remotes:WaitForChild("DroneFireRocket"):FireServer(flying, camera.CFrame.LookVector)
			end
		end
	end)

	-- EXIT (top right, red)
	local exitButton = makeButton("✕ EXIT", UDim2.new(0, 84, 0, 44),
		UDim2.new(1, -24, 0, 108), Color3.fromRGB(255, 110, 100))
	exitButton.AnchorPoint = Vector2.new(1, 0)
	exitButton.MouseButton1Click:Connect(function()
		if flying then
			stopFlying(true)
		end
	end)

	-- show while flying, hide when not; FIRE only for armed drones
	task.spawn(function()
		while true do
			task.wait(0.25)
			local isFlying = flying ~= nil
			mobileGui.Enabled = isFlying
			if isFlying then
				local name = flying.Name:lower()
				local armed = name:find("bomber") or name:find("rpg") or name:find("rocket")
				fireButton.Visible = armed ~= nil
				fireButton.Text = name:find("bomber") and "💣 DROP" or "💥 FIRE"
			else
				-- make sure nothing sticks when we hop out
				mobile.forward = 0
				mobile.strafe = 0
				mobile.vertical = 0
				releaseStick()
			end
		end
	end)
end
