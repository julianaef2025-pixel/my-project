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

-- tuning
local MOVE_SPEED = 70 -- studs/sec horizontal
local VERTICAL_SPEED = 40 -- studs/sec up/down
local MOUSE_SENSITIVITY = 0.0035 -- radians per pixel of mouse movement
local MAX_PITCH = math.rad(75)
local BANK_ANGLE = math.rad(20) -- visual roll when strafing
local CAMERA_OFFSET = CFrame.new(0, 0.5, -1) -- camera sits at the front of the drone

local flying = nil -- current drone model
local renderConn = nil
local exitGui = nil

local function makeExitHint()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DroneExitHint"
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -20)
	label.Size = UDim2.new(0, 300, 0, 30)
	label.BackgroundTransparency = 0.5
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Text = "Press X to exit drone"
	label.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function stopFlying(notifyServer)
	if not flying then
		return
	end
	flying = nil

	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if exitGui then
		exitGui:Destroy()
		exitGui = nil
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	camera.CameraType = Enum.CameraType.Custom
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

	flying = drone
	exitGui = makeExitHint()

	-- start from the drone's current heading
	local yaw = math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z)
	local pitch = 0
	local roll = 0
	local currentVelocity = Vector3.zero

	camera.CameraType = Enum.CameraType.Scriptable

	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not drone.Parent or not root.Parent then
			stopFlying(true)
			return
		end

		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

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

		-- FPV camera locked to the drone body
		camera.CFrame = root.CFrame * CAMERA_OFFSET
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
