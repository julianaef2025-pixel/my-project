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

	Signal: the video/control link comes from the pilot's position. Fly
	past SIGNAL_RANGE for more than SIGNAL_GRACE seconds and the link is
	lost — same result, the drone drops out of the sky.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- destruction tuning (what happens to buildings at the impact point)
local DESTRUCTION_RADIUS = 16 -- studs of building destroyed around the impact
local CHUNK_SIZE = 4 -- walls get sliced into chunks about this size
local MAX_CHUNKS = 150 -- per-explosion cap so a big blast can't lag the server
local VAPORIZE_FRAC = 0.45 -- chunks closer than 45% of the radius are destroyed outright (the hole)
local DEBRIS_LIFETIME = 15 -- seconds before rubble cleans itself up (+ up to 10 random)

-- explosion tuning
local IMPACT_SPEED = 25 -- studs/sec needed to detonate (slower touches are ignored)
local BLAST_RADIUS = 14 -- studs
local MAX_DAMAGE = 100 -- damage at the center of the blast (falls off with distance)
local DRONE_RESPAWN_TIME = 10 -- seconds until the drone respawns at its pad

-- battery tuning
local FLIGHT_TIME = 240 -- seconds of flight per battery (4 minutes)
local DEAD_SELF_DESTRUCT = 8 -- if a dead drone lands too softly to detonate, blow it anyway after this many seconds

-- signal tuning
local SIGNAL_RANGE = 800 -- studs from the pilot before the link drops (interference starts well before this)
local SIGNAL_GRACE = 2 -- seconds you can stay out of range before losing the drone

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
local dronesFolder -- assigned at the bottom of the script, needed by the destruction code

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

--------------------------------------------------------------------
-- building destruction
--------------------------------------------------------------------

-- what the blast is allowed to break
local function isDestructible(part)
	if not part:IsA("BasePart") then
		return false
	end
	if part.Name == "Baseplate" or part:IsA("SpawnLocation") or part:IsA("Seat") then
		return false -- never delete the map floor or spawns
	end
	if part:GetAttribute("Indestructible") then
		return false -- opt-out: set this attribute on anything you want blast-proof
	end
	if dronesFolder and part:IsDescendantOf(dronesFolder) then
		return false -- don't eat other parked drones
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return false -- players/NPCs take damage instead, they don't shatter
	end
	local size = part.Size
	if math.max(size.X, size.Y, size.Z) > 100 then
		return false -- map-sized parts (huge floors etc.) don't crumble
	end
	return true
end

-- strip welds so a flung chunk doesn't drag the rest of the wall with it
local function breakWelds(part)
	for _, child in part:GetChildren() do
		if child:IsA("WeldConstraint") or child:IsA("JointInstance") then
			child:Destroy()
		end
	end
end

-- turn one flat wall part into two halves along its longest axis
local function splitInHalf(part)
	local size = part.Size
	local halfSize, offset
	if size.X >= size.Y and size.X >= size.Z then
		halfSize = Vector3.new(size.X / 2, size.Y, size.Z)
		offset = CFrame.new(size.X / 4, 0, 0)
	elseif size.Y >= size.Z then
		halfSize = Vector3.new(size.X, size.Y / 2, size.Z)
		offset = CFrame.new(0, size.Y / 4, 0)
	else
		halfSize = Vector3.new(size.X, size.Y, size.Z / 2)
		offset = CFrame.new(0, 0, size.Z / 4)
	end

	local a = part:Clone()
	a.Size = halfSize
	a.CFrame = part.CFrame * offset
	a.Parent = part.Parent

	local b = part:Clone()
	b.Size = halfSize
	b.CFrame = part.CFrame * offset:Inverse()
	b.Parent = part.Parent

	part:Destroy()
	return a, b
end

-- puff of dust/smoke at the impact point
local function impactSmoke(position)
	local smokePart = Instance.new("Part")
	smokePart.Name = "ImpactSmoke"
	smokePart.Size = Vector3.new(1, 1, 1)
	smokePart.Position = position
	smokePart.Transparency = 1
	smokePart.Anchored = true
	smokePart.CanCollide = false
	smokePart.CanQuery = false
	smokePart.CanTouch = false

	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 0
	smoke.Lifetime = NumberRange.new(1.5, 3)
	smoke.Speed = NumberRange.new(8, 25)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 12),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 85, 80), Color3.fromRGB(140, 135, 130))
	smoke.Parent = smokePart

	smokePart.Parent = workspace
	smoke:Emit(45)
	Debris:AddItem(smokePart, 8)
end

-- the main destruction pass: voxelize what the blast touches, vaporize the
-- center, fling the rest as physical rubble
local function destroyBuildings(position)
	local overlapParams = OverlapParams.new()
	local touched = workspace:GetPartBoundsInRadius(position, DESTRUCTION_RADIUS, overlapParams)

	-- collect what we're allowed to break
	local queue = {}
	for _, part in touched do
		if isDestructible(part) then
			table.insert(queue, part)
		end
	end

	-- slice big parts down into chunk-sized pieces (only plain block Parts can
	-- be sliced — MeshParts/Unions get flung whole instead)
	local chunkBudget = MAX_CHUNKS
	local chunks = {}
	while #queue > 0 do
		local part = table.remove(queue)
		local size = part.Size
		local maxAxis = math.max(size.X, size.Y, size.Z)
		if part.ClassName == "Part" and maxAxis > CHUNK_SIZE * 1.6 and chunkBudget > 0 then
			chunkBudget -= 1
			local a, b = splitInHalf(part)
			for _, half in {a, b} do
				-- halves that still touch the blast keep splitting; the rest
				-- stay anchored in place — that's the surviving wall
				local reach = (half.Position - position).Magnitude - half.Size.Magnitude / 2
				if reach <= DESTRUCTION_RADIUS then
					table.insert(queue, half)
				end
			end
		else
			table.insert(chunks, part)
		end
	end

	-- vaporize the center, fling the edges
	for _, chunk in chunks do
		if not chunk.Parent then
			continue
		end
		local distance = (chunk.Position - position).Magnitude
		if distance > DESTRUCTION_RADIUS then
			continue
		end

		local smallEnoughToVaporize = chunk.Size.Magnitude < CHUNK_SIZE * 3
		if distance < DESTRUCTION_RADIUS * VAPORIZE_FRAC and smallEnoughToVaporize then
			chunk:Destroy() -- the hole in the wall
		else
			breakWelds(chunk)
			chunk.Anchored = false
			chunk.CanCollide = true

			local direction = chunk.Position - position
			direction = direction.Magnitude > 0.01 and direction.Unit or Vector3.yAxis
			chunk.AssemblyLinearVelocity = direction * math.random(30, 70)
				+ Vector3.new(0, math.random(15, 35), 0)
			chunk.AssemblyAngularVelocity = Vector3.new(
				math.random(-12, 12),
				math.random(-12, 12),
				math.random(-12, 12)
			)

			-- rubble cleans itself up so the server doesn't drown in parts
			Debris:AddItem(chunk, DEBRIS_LIFETIME + math.random(0, 10))
		end
	end

	impactSmoke(position)
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

	-- fresh battery + link info (attributes replicate, so the client HUD reads these directly)
	drone:SetAttribute("Battery", FLIGHT_TIME)
	drone:SetAttribute("MaxBattery", FLIGHT_TIME)
	drone:SetAttribute("SignalRange", SIGNAL_RANGE)

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

		destroyBuildings(position)
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

	-- power/link gone: motors cut, drone free-falls (still armed, so it blows on impact)
	-- reason is "battery" or "signal" — the client HUD shows a different message for each
	local function loseControl(reason)
		if exploded or drone:GetAttribute("Dead") then
			return
		end
		drone:SetAttribute("DeathReason", reason)
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

	-- drains the battery + enforces signal range while this player is flying
	local function startFlightLoop(player)
		task.spawn(function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			-- the link comes from wherever the pilot is standing (they're frozen there)
			local homePosition = hrp and hrp.Position or root.Position
			local outOfRangeTime = 0

			while drone.Parent and drone:GetAttribute("PilotUserId") == player.UserId do
				local battery = drone:GetAttribute("Battery") or 0
				if battery <= 0 then
					loseControl("battery")
					break
				end

				-- signal range check (server-enforced so nobody can cheat past it)
				local distance = (root.Position - homePosition).Magnitude
				if distance > SIGNAL_RANGE then
					outOfRangeTime += 0.5
					if outOfRangeTime >= SIGNAL_GRACE then
						loseControl("signal")
						break
					end
				else
					outOfRangeTime = 0
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
		-- only armed while someone is flying it (or after a power-loss fall)
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
			startFlightLoop(player)
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
dronesFolder = workspace:WaitForChild("Drones")
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

--------------------------------------------------------------------
-- EXPLOSION FX ADD-ON
-- Realistic bang, flash, crater fire, burning debris and a rising
-- smoke column on every explosion in the game. Self-contained: it
-- watches for Explosion instances, so it needs no other changes.
--------------------------------------------------------------------
do
	local TweenService = game:GetService("TweenService")
	local DebrisService = game:GetService("Debris")

	-- if the bang is silent, this id got moderated — search the Toolbox
	-- for "explosion" and paste any sound id you like here
	local BANG_SOUND_ID = "rbxassetid://165969964"
	local FIRE_DURATION = 12 -- seconds the crater burns
	local SMOKE_DURATION = 18 -- seconds the smoke column keeps rising
	local BURNING_DEBRIS = 4 -- how many rubble chunks catch fire

	local function explosionFX(position)
		-- invisible anchor part that holds all the effects
		local fx = Instance.new("Part")
		fx.Name = "ExplosionFX"
		fx.Size = Vector3.new(1, 1, 1)
		fx.Position = position
		fx.Transparency = 1
		fx.Anchored = true
		fx.CanCollide = false
		fx.CanQuery = false
		fx.CanTouch = false
		fx.Parent = workspace

		-- BANG: loud up close, audible far across the map, a bit different every time
		local bang = Instance.new("Sound")
		bang.SoundId = BANG_SOUND_ID
		bang.Volume = 2
		bang.PlaybackSpeed = 0.9 + math.random() * 0.25
		bang.RollOffMinDistance = 30
		bang.RollOffMaxDistance = 1200
		bang.Parent = fx
		bang:Play()

		-- white-orange flash that fades out fast
		local flash = Instance.new("PointLight")
		flash.Color = Color3.fromRGB(255, 170, 60)
		flash.Brightness = 15
		flash.Range = 40
		flash.Parent = fx
		TweenService:Create(flash, TweenInfo.new(0.6), { Brightness = 0, Range = 8 }):Play()

		-- fire burning in the crater
		local fire = Instance.new("Fire")
		fire.Size = 12
		fire.Heat = 15
		fire.Parent = fx

		-- flickery orange glow from the fire while it burns
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 120, 30)
		glow.Brightness = 3
		glow.Range = 25
		glow.Parent = fx

		-- thick rising smoke column
		local smoke = Instance.new("ParticleEmitter")
		smoke.Rate = 12
		smoke.Lifetime = NumberRange.new(3, 6)
		smoke.Speed = NumberRange.new(6, 12)
		smoke.Acceleration = Vector3.new(0, 4, 0)
		smoke.SpreadAngle = Vector2.new(15, 15)
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-20, 20)
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 5),
			NumberSequenceKeypoint.new(1, 16),
		})
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.7, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Color = ColorSequence.new(Color3.fromRGB(40, 38, 35), Color3.fromRGB(110, 105, 100))
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Parent = fx

		-- set a few pieces of flying rubble on fire
		local overlapParams = OverlapParams.new()
		local nearby = workspace:GetPartBoundsInRadius(position, 12, overlapParams)
		local lit = 0
		for _, part in nearby do
			if lit >= BURNING_DEBRIS then
				break
			end
			if not part.Anchored and part.Name ~= "ExplosionFX" then
				local debrisFire = Instance.new("Fire")
				debrisFire.Size = 4
				debrisFire.Heat = 8
				debrisFire.Parent = part
				DebrisService:AddItem(debrisFire, 6 + math.random(0, 4))
				lit += 1
			end
		end

		-- burn down: the fire shrinks, then dies; smoke keeps rising a bit longer
		task.delay(FIRE_DURATION * 0.6, function()
			if fire.Parent then
				fire.Size = 6
			end
		end)
		task.delay(FIRE_DURATION, function()
			if fire.Parent then
				fire:Destroy()
			end
			if glow.Parent then
				glow:Destroy()
			end
		end)
		task.delay(SMOKE_DURATION, function()
			if smoke.Parent then
				smoke.Enabled = false
			end
		end)
		DebrisService:AddItem(fx, SMOKE_DURATION + 8)
	end

	-- hook: run the FX every time an explosion goes off anywhere in the game
	workspace.ChildAdded:Connect(function(child)
		if child:IsA("Explosion") then
			explosionFX(child.Position)
		end
	end)
end
