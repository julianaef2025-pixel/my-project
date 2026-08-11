--[[
	FPV Drone — SERVER script
	Put this in ServerScriptService as a regular Script.

	Drone model setup (in Workspace):
	- Put every drone model inside a Folder in Workspace named "Drones"
	- Each drone model must have a PrimaryPart set (the main body part)
	- All other parts get auto-welded to the PrimaryPart by this script

	While a drone is being flown it is ARMED: hitting anything at speed
	makes it explode on impact, damage everything nearby, and respawn
	at its starting spot after a delay.

	Battery: each drone has ~4 minutes of flight time. When it runs out,
	the motors cut, the drone falls out of the sky and detonates on impact.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- explosion tuning
local IMPACT_SPEED = 25 -- studs/sec needed to detonate (slower touches are ignored)
local BLAST_RADIUS = 14 -- studs
local MAX_DAMAGE = 100 -- damage at the center of the blast (falls off with distance)
local DRONE_RESPAWN_TIME = 10 -- seconds until the drone respawns at its pad

-- battery tuning
local FLIGHT_TIME = 240 -- seconds of flight per battery (4 minutes)
local DEAD_SELF_DESTRUCT = 8 -- if a dead drone lands too softly to detonate, blow it anyway after this many seconds

-- sound
-- NOTE: if the motor is silent in your game, this id may have been moderated —
-- open the Toolbox, search "drone motor loop" or "quadcopter", and paste any id you like here.
local MOTOR_SOUND_ID = "rbxassetid://131961136"

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
		local motor = root:FindFirstChild("DroneMotor")
		if motor then motor:Stop() end
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
		if not drone:GetAttribute("Dead") then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true

			local prompt = root:FindFirstChildWhichIsA("ProximityPrompt")
			if prompt then
				prompt.Enabled = true
			end
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
	if drone:GetAttribute("Dead") or (drone:GetAttribute("Battery") or 0) <= 0 then
		return -- battery is dead, no flying this one
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

	-- spin up the motors
	local motor = root:FindFirstChild("DroneMotor")
	if motor then
		motor:Play()
	end

	-- hand physics to the pilot's client so flying feels responsive
	root.Anchored = false
	root:FindFirstChild("DroneLinearVelocity").Enabled = true
	root:FindFirstChild("DroneAlignOrientation").Enabled = true
	root:SetNetworkOwner(player)

	enterEvent:FireClient(player, drone)
end

-- damage every humanoid (players AND NPCs) caught in the blast, with distance falloff
local function damageInBlast(position)
	local damagedHumanoids = {}
	local overlapParams = OverlapParams.new()
	local parts = workspace:GetPartBoundsInRadius(position, BLAST_RADIUS, overlapParams)
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not damagedHumanoids[humanoid] then
			damagedHumanoids[humanoid] = true
			local targetRoot = humanoid.RootPart or part
			local distance = (targetRoot.Position - position).Magnitude
			local damage = MAX_DAMAGE * math.clamp(1 - distance / BLAST_RADIUS, 0.1, 1)
			humanoid:TakeDamage(damage)
		end
	end
end

local function setupDrone(drone)
	-- keep a clean copy + spawn spot so we can respawn it after it blows up
	local template = drone:Clone()
	local spawnParent = drone.Parent

	local root = getRoot(drone)
	if not root then
		warn("[FPVDrone] Drone model '" .. drone.Name .. "' has no parts, skipping")
		return
	end
	drone.PrimaryPart = root
	local spawnCFrame = root.CFrame

	-- fresh battery (attributes replicate, so the client HUD reads these directly)
	drone:SetAttribute("Battery", FLIGHT_TIME)
	drone:SetAttribute("MaxBattery", FLIGHT_TIME)

	local exploded = false
	local function explode(position)
		if exploded then
			return
		end
		exploded = true

		-- release the pilot before the drone disappears
		local pilotId = drone:GetAttribute("PilotUserId")
		local pilot = pilotId and Players:GetPlayerByUserId(pilotId)
		if pilot then
			exitDrone(pilot)
		end

		local explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = BLAST_RADIUS
		explosion.BlastPressure = 500000
		explosion.DestroyJointRadiusPercent = 0 -- damage is handled by us, not by breaking joints
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace

		damageInBlast(position)

		drone:Destroy()

		task.delay(DRONE_RESPAWN_TIME, function()
			if spawnParent and spawnParent.Parent then
				local newDrone = template:Clone()
				newDrone:PivotTo(spawnCFrame)
				newDrone.Parent = spawnParent -- ChildAdded below re-runs setup on it
			end
		end)
	end

	-- battery empty: motors cut, drone free-falls (still armed, so it blows on impact)
	local function batteryDied()
		if exploded or drone:GetAttribute("Dead") then
			return
		end
		drone:SetAttribute("Dead", true)

		local motor = root:FindFirstChild("DroneMotor")
		if motor then
			motor:Stop()
		end
		local lv = root:FindFirstChild("DroneLinearVelocity")
		local ao = root:FindFirstChild("DroneAlignOrientation")
		if lv then lv.Enabled = false end
		if ao then ao.Enabled = false end
		root.Anchored = false

		-- failsafe: if it landed too softly to detonate, self-destruct anyway
		task.delay(DEAD_SELF_DESTRUCT, function()
			if not exploded and drone.Parent then
				explode(root.Position)
			end
		end)
	end

	-- drains the battery while this player is flying
	local function startBatteryDrain(player)
		task.spawn(function()
			while drone.Parent and drone:GetAttribute("PilotUserId") == player.UserId do
				local battery = drone:GetAttribute("Battery") or 0
				if battery <= 0 then
					batteryDied()
					break
				end
				drone:SetAttribute("Battery", math.max(battery - 0.5, 0))
				task.wait(0.5)
			end
		end)
	end

	local function onTouched(hit)
		if exploded then
			return
		end
		-- only armed while someone is flying it (or after a battery-death fall)
		local pilotId = drone:GetAttribute("PilotUserId")
		if not pilotId and not drone:GetAttribute("Dead") then
			return
		end
		if hit:IsDescendantOf(drone) then
			return
		end
		-- don't detonate on the pilot standing next to the takeoff spot
		local pilot = pilotId and Players:GetPlayerByUserId(pilotId)
		if pilot and pilot.Character and hit:IsDescendantOf(pilot.Character) then
			return
		end
		-- gentle touches don't set it off — it has to be a real impact
		if root.AssemblyLinearVelocity.Magnitude < IMPACT_SPEED then
			return
		end
		explode(root.Position)
	end

	-- weld every other part to the root so the model flies as one assembly,
	-- and make every part an impact trigger
	for _, part in drone:GetDescendants() do
		if part:IsA("BasePart") then
			if part ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = root
				part.Anchored = false
			end
			part.Touched:Connect(onTouched)
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

	-- motor sound everyone nearby can hear (the pilot's client also pitches it with throttle)
	local motorSound = Instance.new("Sound")
	motorSound.Name = "DroneMotor"
	motorSound.SoundId = MOTOR_SOUND_ID
	motorSound.Looped = true
	motorSound.Volume = 0.6
	motorSound.RollOffMinDistance = 10
	motorSound.RollOffMaxDistance = 200
	motorSound.Parent = root

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
		if drone:GetAttribute("PilotUserId") == player.UserId then
			startBatteryDrain(player)
		end
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
