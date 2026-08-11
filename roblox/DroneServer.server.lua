--[[
	FPV Drone — SERVER script
	Put this in ServerScriptService as a regular Script.

	Drone model setup (in Workspace):
	- Put every drone model inside a Folder in Workspace named "Drones"
	- Each drone model must have a PrimaryPart set (the main body part)
	- All other parts get auto-welded to the PrimaryPart by this script
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes the client script talks to
local remotes = Instance.new("Folder")
remotes.Name = "DroneRemotes"
remotes.Parent = ReplicatedStorage

local enterEvent = Instance.new("RemoteEvent")
enterEvent.Name = "DroneEnter"
enterEvent.Parent = remotes

local exitEvent = Instance.new("RemoteEvent")
exitEvent.Name = "DroneExit"
exitEvent.Parent = remotes

local activePilots = {} -- [player] = drone model

local function getRoot(drone)
	return drone.PrimaryPart or drone:FindFirstChildWhichIsA("BasePart")
end

local function exitDrone(player)
	local drone = activePilots[player]
	if not drone then
		return
	end
	activePilots[player] = nil
	drone:SetAttribute("PilotUserId", nil)

	local root = getRoot(drone)
	if root and root.Parent then
		local lv = root:FindFirstChild("DroneLinearVelocity")
		local ao = root:FindFirstChild("DroneAlignOrientation")
		if lv then lv.Enabled = false end
		if ao then ao.Enabled = false end
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true

		local prompt = root:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			prompt.Enabled = true
		end
	end

	-- unfreeze the character
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = false
	end

	-- tell the client to release the camera (in case the exit was server-forced)
	exitEvent:FireClient(player)
end

local function enterDrone(player, drone)
	if activePilots[player] then
		return -- already flying something
	end
	if drone:GetAttribute("PilotUserId") then
		return -- someone else is flying this one
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not hrp then
		return
	end

	local root = getRoot(drone)
	if not root then
		return
	end

	drone:SetAttribute("PilotUserId", player.UserId)
	activePilots[player] = drone

	local prompt = root:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end

	-- freeze the pilot's character where they stand
	hrp.Anchored = true

	-- hand physics to the pilot's client so flying feels responsive
	root.Anchored = false
	root:FindFirstChild("DroneLinearVelocity").Enabled = true
	root:FindFirstChild("DroneAlignOrientation").Enabled = true
	root:SetNetworkOwner(player)

	enterEvent:FireClient(player, drone)
end

local function setupDrone(drone)
	local root = getRoot(drone)
	if not root then
		warn("[FPVDrone] Drone model '" .. drone.Name .. "' has no parts, skipping")
		return
	end
	drone.PrimaryPart = root

	-- weld every other part to the root so the model flies as one assembly
	for _, part in drone:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
			part.Anchored = false
		end
	end
	root.Anchored = true -- parked until someone flies it

	local attachment = Instance.new("Attachment")
	attachment.Name = "DroneAttachment"
	attachment.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DroneLinearVelocity"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Enabled = false
	lv.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "DroneAlignOrientation"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = attachment
	ao.MaxTorque = math.huge
	ao.MaxAngularVelocity = math.huge
	ao.Responsiveness = 100
	ao.CFrame = root.CFrame.Rotation
	ao.Enabled = false
	ao.Parent = root

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fly Drone"
	prompt.ObjectText = drone.Name
	prompt.HoldDuration = 1 -- hold E for a second
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function(player)
		enterDrone(player, drone)
	end)
end

-- kick the pilot out if they die or leave
local function watchCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			exitDrone(player)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
end)

Players.PlayerRemoving:Connect(exitDrone)
exitEvent.OnServerEvent:Connect(exitDrone)

-- set up every drone in the Workspace "Drones" folder
local dronesFolder = workspace:WaitForChild("Drones")
for _, drone in dronesFolder:GetChildren() do
	if drone:IsA("Model") then
		setupDrone(drone)
	end
end
dronesFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		task.wait() -- let all its parts stream in
		setupDrone(child)
	end
end)
