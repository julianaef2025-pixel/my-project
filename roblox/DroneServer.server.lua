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
local DESTRUCTION_RADIUS = 12 -- studs of building destroyed around the impact
local CHUNK_SIZE = 4 -- walls get sliced into chunks about this size
local MAX_CHUNKS = 150 -- per-explosion cap so a big blast can't lag the server
local VAPORIZE_FRAC = 0.45 -- chunks closer than 45% of the radius are destroyed outright (the hole)
local DEBRIS_LIFETIME = 15 -- seconds before rubble cleans itself up (+ up to 10 random)

-- explosion tuning
local IMPACT_SPEED = 25 -- studs/sec needed to detonate (slower touches are ignored)
local BLAST_RADIUS = 10 -- studs
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
	return drone.PrimaryPart or drone:FindFirstChildWhichIsA("BasePart", true)
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
-- attackerUserId tags victims so the XP system can credit kills
local function damageInBlast(position, attackerUserId, radiusOverride)
	local radius = radiusOverride or BLAST_RADIUS
	local damagedHumanoids = {}
	local overlapParams = OverlapParams.new()
	local parts = workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not damagedHumanoids[humanoid] then
			damagedHumanoids[humanoid] = true
			if attackerUserId then
				humanoid:SetAttribute("LastHitBy", attackerUserId)
				humanoid:SetAttribute("LastHitTime", os.clock())
			end
			local targetRoot = humanoid.RootPart or part
			local distance = (targetRoot.Position - position).Magnitude
			local damage = MAX_DAMAGE * math.clamp(1 - distance / radius, 0.1, 1)
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
local function destroyBuildings(position, radiusOverride)
	local radius = radiusOverride or DESTRUCTION_RADIUS
	local overlapParams = OverlapParams.new()
	local touched = workspace:GetPartBoundsInRadius(position, radius, overlapParams)

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
				if reach <= radius then
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
		if distance > radius then
			continue
		end

		local smallEnoughToVaporize = chunk.Size.Magnitude < CHUNK_SIZE * 3
		if distance < radius * VAPORIZE_FRAC and smallEnoughToVaporize then
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
		damageInBlast(position, pilotId)

		-- report the demolition to the XP system
		local xpSignal = game:GetService("ServerStorage"):FindFirstChild("XPSignal")
		if xpSignal and pilotId then
			xpSignal:Fire(pilotId, "demolition")
		end

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
	motorSound.Volume = 0.9
	motorSound.RollOffMode = Enum.RollOffMode.InverseTapered -- ramps up hard as it gets close
	motorSound.RollOffMinDistance = 5
	motorSound.RollOffMaxDistance = 250
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
-- EXPLOSION FX ADD-ON v2
-- Cinematic explosions: fireball, white-hot sparks, shockwave, bang,
-- and the blast "splashes" onto every surface it can see — burning
-- fire patches, black scorch marks and smoke wisps stuck to the
-- floor, walls and ceiling around the impact. Self-contained: it
-- watches for Explosion instances, so drone crashes AND grenades
-- both get the full treatment.
--------------------------------------------------------------------
do
	local TweenService = game:GetService("TweenService")
	local DebrisService = game:GetService("Debris")

	-- if the bang is silent, this id got moderated — search the Toolbox
	-- for "explosion" and paste any sound id you like here
	local BANG_SOUND_ID = "rbxassetid://165969964"
	local SPLASH_RANGE = 16 -- how far the blast reaches out to paint surfaces
	local MAX_PATCHES = 12 -- max fire/scorch patches per explosion (perf cap)
	local SCORCH_LIFETIME = 40 -- seconds scorch marks stay before fading out
	local FIRE_DURATION = 14 -- seconds the crater fire burns
	local SMOKE_DURATION = 25 -- seconds the smoke column keeps rising
	local BURNING_DEBRIS = 5 -- how many rubble chunks catch fire

	-- ray fan: around the horizon, angled down, angled up, straight up/down —
	-- so floors, walls AND ceilings all catch the blast
	local SPLASH_DIRECTIONS = {}
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		table.insert(SPLASH_DIRECTIONS, Vector3.new(math.cos(a), -0.15, math.sin(a)))
	end
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + 0.3
		table.insert(SPLASH_DIRECTIONS, Vector3.new(math.cos(a) * 0.6, -1, math.sin(a) * 0.6))
	end
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + 0.6
		table.insert(SPLASH_DIRECTIONS, Vector3.new(math.cos(a) * 0.5, 1, math.sin(a) * 0.5))
	end
	table.insert(SPLASH_DIRECTIONS, Vector3.new(0, -1, 0))
	table.insert(SPLASH_DIRECTIONS, Vector3.new(0, 1, 0))

	-- a patch of scorch + fire + smoke stuck to a floor, wall or ceiling
	local function surfacePatch(hit)
		local position = hit.Position
		local normal = hit.Normal

		-- black scorch plate laid flat on the surface, random size + spin
		local scorch = Instance.new("Part")
		scorch.Name = "ExplosionScorch"
		scorch.Size = Vector3.new(math.random(4, 8), 0.2, math.random(4, 8))
		scorch.CFrame = CFrame.lookAt(position + normal * 0.1, position + normal)
			* CFrame.Angles(-math.pi / 2, 0, 0)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
		scorch.Color = Color3.fromRGB(25, 22, 20)
		scorch.Material = Enum.Material.Slate
		scorch.Transparency = 0.15
		scorch.Anchored = true
		scorch.CanCollide = false
		scorch.CanQuery = false
		scorch.CanTouch = false
		scorch.CastShadow = false
		scorch.Parent = workspace

		local life = SCORCH_LIFETIME + math.random(0, 15)
		task.delay(life - 5, function()
			if scorch.Parent then
				TweenService:Create(scorch, TweenInfo.new(5), { Transparency = 1 }):Play()
			end
		end)
		DebrisService:AddItem(scorch, life)

		-- most patches keep burning for a while with their own smoke + glow
		if math.random() < 0.8 then
			local burnTime = math.random(6, 14)

			local fire = Instance.new("Fire")
			fire.Size = math.random(4, 9)
			fire.Heat = math.random(6, 12)
			fire.Parent = scorch

			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 120, 30)
			glow.Brightness = 2
			glow.Range = 14
			glow.Parent = scorch

			local wisp = Instance.new("ParticleEmitter")
			wisp.Rate = 4
			wisp.Lifetime = NumberRange.new(2, 4)
			wisp.Speed = NumberRange.new(3, 7)
			wisp.Acceleration = Vector3.new(0, 5, 0)
			wisp.SpreadAngle = Vector2.new(25, 25)
			wisp.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.5),
				NumberSequenceKeypoint.new(1, 6),
			})
			wisp.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			})
			wisp.Color = ColorSequence.new(Color3.fromRGB(60, 55, 50), Color3.fromRGB(120, 115, 110))
			wisp.EmissionDirection = Enum.NormalId.Top
			wisp.Parent = scorch

			task.delay(burnTime, function()
				if fire.Parent then
					fire:Destroy()
				end
				if glow.Parent then
					glow:Destroy()
				end
				if wisp.Parent then
					wisp.Enabled = false
				end
			end)
		end
	end

	-- throw fire/scorch/smoke onto every surface the blast can see
	local function splashSurfaces(position)
		local rayParams = RaycastParams.new()
		local patches = 0
		for _, dir in SPLASH_DIRECTIONS do
			if patches >= MAX_PATCHES then
				break
			end
			local hit = workspace:Raycast(position, dir.Unit * SPLASH_RANGE, rayParams)
			if hit and hit.Instance.Anchored then
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				if not (model and model:FindFirstChildOfClass("Humanoid")) then
					patches += 1
					surfacePatch(hit)
				end
			end
		end
	end

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

		-- expanding fireball of flame particles
		local fireball = Instance.new("ParticleEmitter")
		fireball.Rate = 0
		fireball.Lifetime = NumberRange.new(0.35, 0.8)
		fireball.Speed = NumberRange.new(12, 34)
		fireball.SpreadAngle = Vector2.new(180, 180)
		fireball.LightEmission = 0.9
		fireball.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 4.5),
			NumberSequenceKeypoint.new(1, 12),
		})
		fireball.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		fireball.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(200, 60, 20))
		fireball.Parent = fx
		fireball:Emit(45)

		-- white-hot sparks that arc out and rain down
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 0
		sparks.Lifetime = NumberRange.new(0.5, 1.4)
		sparks.Speed = NumberRange.new(34, 68)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Acceleration = Vector3.new(0, -70, 0)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 150, 50))
		sparks.Parent = fx
		sparks:Emit(70)

		-- shockwave: a glowing sphere that blasts outward and vanishes
		local wave = Instance.new("Part")
		wave.Name = "ExplosionShockwave"
		wave.Shape = Enum.PartType.Ball
		wave.Size = Vector3.new(2, 2, 2)
		wave.Position = position
		wave.Material = Enum.Material.Neon
		wave.Color = Color3.fromRGB(255, 190, 120)
		wave.Transparency = 0.4
		wave.Anchored = true
		wave.CanCollide = false
		wave.CanQuery = false
		wave.CanTouch = false
		wave.CastShadow = false
		wave.Parent = workspace
		TweenService:Create(wave, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * (SPLASH_RANGE * 2),
			Transparency = 1,
		}):Play()
		DebrisService:AddItem(wave, 0.6)

		-- white-orange flash that fades out fast
		local flash = Instance.new("PointLight")
		flash.Color = Color3.fromRGB(255, 170, 60)
		flash.Brightness = 20
		flash.Range = 38
		flash.Parent = fx
		TweenService:Create(flash, TweenInfo.new(0.6), { Brightness = 0, Range = 8 }):Play()

		-- fire burning in the crater
		local fire = Instance.new("Fire")
		fire.Size = 10
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
		smoke.Rate = 18
		smoke.Lifetime = NumberRange.new(4, 8)
		smoke.Speed = NumberRange.new(6, 14)
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

		-- paint fire + scorch + smoke onto the floor, walls and ceiling
		splashSurfaces(position)

		-- burn down: the fire shrinks, then dies; smoke keeps rising a bit longer
		task.delay(FIRE_DURATION * 0.6, function()
			if fire.Parent then
				fire.Size = 5
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

--------------------------------------------------------------------
-- BOMBER DRONE ADD-ON (server)
-- Any drone model whose NAME contains "Bomber" carries grenades.
-- The pilot presses F to drop one. Grenades inherit the drone's
-- speed, arm shortly after release, and explode on impact with the
-- same building destruction + damage as a kamikaze crash (and the
-- explosion FX add-on picks them up automatically).
--------------------------------------------------------------------
do
	local GRENADE_COUNT = 3 -- grenades per battery/respawn
	local GRENADE_BLAST_RADIUS = 9
	local GRENADE_ARM_TIME = 0.35 -- seconds after release before the fuse is live
	local GRENADE_FUSE = 20 -- failsafe: explodes after this long even if it never lands (long enough for very high drops)

	local function isBomber(drone)
		return drone.Name:lower():find("bomber") ~= nil
	end

	local dropEvent = Instance.new("RemoteEvent")
	dropEvent.Name = "DroneDropGrenade"
	dropEvent.Parent = remotes

	-- position is passed in explicitly: at high fall speeds the grenade part
	-- can already be deep underground by the time this runs, so we must
	-- never re-read its Position for the blast location
	local function grenadeExplode(grenade, position)
		if grenade:GetAttribute("Exploded") then
			return
		end
		grenade:SetAttribute("Exploded", true)
		position = position or grenade.Position

		local explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = GRENADE_BLAST_RADIUS
		explosion.BlastPressure = 500000
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace

		local ownerId = grenade:GetAttribute("OwnerUserId")
		destroyBuildings(position)
		damageInBlast(position, ownerId)

		-- report the demolition to the XP system
		local xpSignal = game:GetService("ServerStorage"):FindFirstChild("XPSignal")
		if xpSignal and ownerId then
			xpSignal:Fire(ownerId, "demolition")
		end

		grenade:Destroy()
	end

	dropEvent.OnServerEvent:Connect(function(player, drone)
		-- validate everything: only the pilot of a live bomber with ammo can drop
		if typeof(drone) ~= "Instance" or not drone:IsA("Model") then
			return
		end
		if drone:GetAttribute("PilotUserId") ~= player.UserId then
			return
		end
		if drone:GetAttribute("Dead") then
			return
		end
		if not isBomber(drone) then
			return
		end
		local root = drone.PrimaryPart
		if not root then
			return
		end

		local ammo = drone:GetAttribute("Grenades")
		if ammo == nil then
			ammo = GRENADE_COUNT
		end
		if ammo <= 0 then
			return
		end
		drone:SetAttribute("Grenades", ammo - 1)

		-- the grenade: released under the drone, carrying the drone's speed
		local grenade = Instance.new("Part")
		grenade.Name = "DroneGrenade"
		grenade:SetAttribute("OwnerUserId", player.UserId)
		grenade.Shape = Enum.PartType.Ball
		grenade.Size = Vector3.new(1, 1, 1)
		grenade.Color = Color3.fromRGB(60, 70, 50)
		grenade.Material = Enum.Material.Metal
		grenade.CFrame = root.CFrame * CFrame.new(0, -2.5, 0)
		grenade.AssemblyLinearVelocity = root.AssemblyLinearVelocity
		grenade.CanCollide = true
		grenade.Parent = workspace

		-- server owns the grenade's physics: the pilot's client can't drag
		-- its position around, so the impact point stays accurate
		pcall(function()
			grenade:SetNetworkOwner(nil)
		end)

		-- arm after a beat so it can't blow up on the drone that dropped it
		task.delay(GRENADE_ARM_TIME, function()
			if grenade.Parent then
				grenade.Touched:Connect(function(hit)
					if not hit:IsDescendantOf(drone) then
						grenadeExplode(grenade, grenade.Position)
					end
				end)
			end
		end)

		-- anti-tunneling watcher: from a high drop the grenade falls so fast it
		-- can skip straight through a roof between physics frames, so raycast
		-- along its path every frame and detonate at the exact impact point
		task.spawn(function()
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { grenade, drone }
			local elapsed = 0
			local lastPosition = grenade.Position
			while grenade.Parent and elapsed < GRENADE_FUSE do
				local dt = task.wait()
				elapsed += dt
				local nowPosition = grenade.Position
				if elapsed >= GRENADE_ARM_TIME then
					local step = nowPosition - lastPosition
					if step.Magnitude > 0.1 then
						local hit = workspace:Raycast(lastPosition, step, rayParams)
						if hit then
							-- detonate exactly on the surface the grenade crossed,
							-- no matter how far past it the physics has carried it
							grenadeExplode(grenade, hit.Position + hit.Normal * 0.5)
							break
						end
					end
				end
				lastPosition = nowPosition
			end
			-- fuse ran out without ever landing: blow it anyway
			if grenade.Parent then
				grenadeExplode(grenade)
			end
		end)
	end)

	-- bombers start (and respawn) with a full rack
	local function initBomber(child)
		if child:IsA("Model") and isBomber(child) then
			child:SetAttribute("Grenades", GRENADE_COUNT)
		end
	end
	for _, child in dronesFolder:GetChildren() do
		initBomber(child)
	end
	dronesFolder.ChildAdded:Connect(function(child)
		task.wait()
		initBomber(child)
	end)
end

--------------------------------------------------------------------
-- RECON DRONE ADD-ON (server)
-- Any drone model whose NAME contains "Recon" is a scout: huge
-- battery + signal range and a quiet motor. Its pilot presses T to
-- MARK an enemy — the mark is broadcast to the pilot's whole team
-- (the client add-on draws the red through-wall glow).
--------------------------------------------------------------------
do
	local RECON_BATTERY = 420 -- 7 minutes of flight
	local RECON_SIGNAL = 2200 -- nearly triple the normal link range: fly high, fly far
	local MARK_DURATION = 6 -- seconds a mark stays on a person
	local LOCATION_MARK_DURATION = 20 -- seconds a marked spot on the ground/building stays lit
	local MARK_RANGE = 1000 -- max lasing distance from the drone (high-altitude marking)
	local MARK_COOLDOWN = 2 -- seconds between marks per pilot

	local function isRecon(drone)
		return drone.Name:lower():find("recon") ~= nil
	end

	local markEvent = Instance.new("RemoteEvent")
	markEvent.Name = "DroneMark"
	markEvent.Parent = remotes

	-- upgrade recon drones after the main system sets them up
	task.spawn(function()
		while true do
			for _, drone in dronesFolder:GetChildren() do
				if drone:IsA("Model") and isRecon(drone) and drone.PrimaryPart
					and not drone:GetAttribute("ReconBoosted") then
					drone:SetAttribute("ReconBoosted", true)
					drone:SetAttribute("Battery", RECON_BATTERY)
					drone:SetAttribute("MaxBattery", RECON_BATTERY)
					drone:SetAttribute("SignalRange", RECON_SIGNAL)
					local motor = drone.PrimaryPart:FindFirstChild("DroneMotor")
					if motor then
						motor.Volume = 0.35 -- stealthy: much harder to hear coming
						motor.RollOffMaxDistance = 90
					end
				end
			end
			task.wait(2)
		end
	end)

	local lastMark = {}

	markEvent.OnServerEvent:Connect(function(pilot, target)
		-- validate everything server-side
		local drone = activePilots[pilot]
		if not drone or not isRecon(drone) or drone:GetAttribute("Dead") then
			return
		end
		local root = drone.PrimaryPart
		if not root then
			return
		end
		local now = os.clock()
		if lastMark[pilot] and now - lastMark[pilot] < MARK_COOLDOWN then
			return
		end

		local payload, duration

		if typeof(target) == "Vector3" then
			-- lasing a spot on the ground / a building
			if (target - root.Position).Magnitude > MARK_RANGE then
				return
			end
			payload = target
			duration = LOCATION_MARK_DURATION
		elseif typeof(target) == "Instance" and target:IsA("Model") then
			-- marking a person
			local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
			local targetRoot = target:FindFirstChild("HumanoidRootPart")
				or (targetHumanoid and targetHumanoid.RootPart)
			if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRoot then
				return
			end
			if (targetRoot.Position - root.Position).Magnitude > MARK_RANGE then
				return
			end
			-- no marking your own teammates
			local targetPlayer = Players:GetPlayerFromCharacter(target)
			if targetPlayer and pilot.Team and targetPlayer.Team == pilot.Team then
				return
			end
			-- record the mark so the XP system can pay out assists
			target:SetAttribute("MarkedByUserId", pilot.UserId)
			target:SetAttribute("MarkedUntil", os.clock() + MARK_DURATION)
			payload = target
			duration = MARK_DURATION
		else
			return
		end

		lastMark[pilot] = now

		-- broadcast the mark to the pilot's entire team
		for _, teammate in Players:GetPlayers() do
			if teammate == pilot or (pilot.Team and teammate.Team == pilot.Team) then
				markEvent:FireClient(teammate, payload, duration)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastMark[p] = nil
	end)
end

--------------------------------------------------------------------
-- BOMBER REARM ADD-ON (server)
-- Put invisible zone parts in a Workspace folder named "RearmZones"
-- (one big part at each base). A bomber hovering inside a zone
-- refills one grenade every few seconds, up to full.
--------------------------------------------------------------------
do
	local REFILL_SECONDS = 2.5 -- time per grenade
	local MAX_GRENADES = 3 -- keep in sync with GRENADE_COUNT in the bomber add-on
	local ZONE_SLACK = Vector3.new(2, 8, 2) -- extra room above the zone so hovering counts

	local function isBomber(drone)
		return drone.Name:lower():find("bomber") ~= nil
	end

	local rearmFolder = workspace:FindFirstChild("RearmZones")
	if not rearmFolder then
		rearmFolder = Instance.new("Folder")
		rearmFolder.Name = "RearmZones"
		rearmFolder.Parent = workspace
		warn("[Rearm] Created empty 'RearmZones' folder — put a big Part in it at each base")
	end

	-- make zones invisible + give each a floating hologram tag
	local function setupZone(zone)
		if not zone:IsA("BasePart") then
			return
		end
		zone.Transparency = 1
		zone.CanCollide = false
		zone.Anchored = true

		if not zone:FindFirstChild("RearmTag") then
			local tag = Instance.new("BillboardGui")
			tag.Name = "RearmTag"
			tag.Size = UDim2.new(0, 120, 0, 30)
			tag.StudsOffsetWorldSpace = Vector3.new(0, zone.Size.Y / 2 + 6, 0)
			tag.AlwaysOnTop = false
			tag.MaxDistance = 250
			local text = Instance.new("TextLabel")
			text.Size = UDim2.new(1, 0, 1, 0)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.Code
			text.TextSize = 20
			text.TextColor3 = Color3.fromRGB(120, 220, 140)
			text.TextStrokeTransparency = 0.5
			text.Text = "⟳ REARM"
			text.Parent = tag
			tag.Parent = zone
		end
	end
	for _, zone in rearmFolder:GetChildren() do
		setupZone(zone)
	end
	rearmFolder.ChildAdded:Connect(setupZone)

	local function insideAnyZone(position)
		for _, zone in rearmFolder:GetChildren() do
			if zone:IsA("BasePart") then
				local rel = zone.CFrame:PointToObjectSpace(position)
				local half = zone.Size / 2 + ZONE_SLACK
				if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
					return true
				end
			end
		end
		return false
	end

	local refillProgress = {} -- [drone] = seconds accumulated toward the next grenade

	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, drone in dronesFolder:GetChildren() do
				if drone:IsA("Model") and isBomber(drone) and drone.PrimaryPart
					and drone:GetAttribute("PilotUserId") and not drone:GetAttribute("Dead") then
					local ammo = drone:GetAttribute("Grenades") or 0
					if ammo < MAX_GRENADES and insideAnyZone(drone.PrimaryPart.Position) then
						drone:SetAttribute("Rearming", true)
						refillProgress[drone] = (refillProgress[drone] or 0) + 0.5
						if refillProgress[drone] >= REFILL_SECONDS then
							refillProgress[drone] = 0
							drone:SetAttribute("Grenades", math.min(ammo + 1, MAX_GRENADES))
						end
					else
						if drone:GetAttribute("Rearming") then
							drone:SetAttribute("Rearming", nil)
						end
						refillProgress[drone] = nil
					end
				end
			end
			-- forget drones that no longer exist
			for drone in refillProgress do
				if not drone.Parent then
					refillProgress[drone] = nil
				end
			end
		end
	end)
end

--------------------------------------------------------------------
-- CRATER ADD-ON v2 (server)
-- Real carved craters on Roblox Terrain; on part-based floors it
-- keeps your floor untouched and lays down a crater PATCH instead:
-- scorched disc + dark bowl center + a rim of churned dirt.
-- Patches clean themselves up after PATCH_LIFETIME seconds.
--------------------------------------------------------------------
do
	local CRATER_SCALE = 0.6 -- crater radius = explosion BlastRadius * this
	local MIN_CRATER_RADIUS = 3
	local MAX_CRATER_RADIUS = 8
	local PATCH_LIFETIME = 120 -- seconds crater patches stay on part floors

	local terrain = workspace.Terrain

	local terrainRay = RaycastParams.new()
	terrainRay.FilterType = Enum.RaycastFilterType.Include
	terrainRay.FilterDescendantsInstances = { terrain }

	local floorRay = RaycastParams.new()
	floorRay.FilterType = Enum.RaycastFilterType.Exclude

	local function makeDisc(parent, position, radius, height, color, yNudge)
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(height, radius * 2, radius * 2)
		disc.CFrame = CFrame.new(position + Vector3.new(0, yNudge, 0)) * CFrame.Angles(0, math.random() * math.pi, math.pi / 2)
		disc.Color = color
		disc.Material = Enum.Material.Slate
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Parent = parent
		return disc
	end

	-- fake crater for part-based floors: keeps the floor, looks the part
	local function spawnCraterPatch(position, radius)
		local patch = Instance.new("Model")
		patch.Name = "CraterPatch"

		-- wide scorched ring, then the darker bowl center on top
		makeDisc(patch, position, radius * 1.35, 0.12, Color3.fromRGB(32, 29, 26), 0.06)
		makeDisc(patch, position, radius * 0.75, 0.14, Color3.fromRGB(16, 15, 13), 0.11)

		-- churned dirt rim: rough clods thrown around the edge
		for i = 1, 10 do
			local angle = (i / 10) * math.pi * 2 + math.random() * 0.5
			local dist = radius * (1.05 + math.random() * 0.35)
			local clod = Instance.new("Part")
			local size = 0.6 + math.random() * 1.1
			clod.Size = Vector3.new(size, size * 0.55, size)
			clod.CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * dist, 0.15, math.sin(angle) * dist))
				* CFrame.Angles(math.random() * 0.6, math.random() * math.pi * 2, math.random() * 0.6)
			clod.Color = Color3.fromRGB(58, 45, 33)
			clod.Material = Enum.Material.Ground
			clod.Anchored = true
			clod.CanCollide = false
			clod.CanQuery = false
			clod.CanTouch = false
			clod.CastShadow = false
			clod.Parent = patch
		end

		patch.Parent = workspace
		Debris:AddItem(patch, PATCH_LIFETIME)
	end

	workspace.ChildAdded:Connect(function(child)
		if not child:IsA("Explosion") then
			return
		end
		local radius = math.clamp(child.BlastRadius * CRATER_SCALE, MIN_CRATER_RADIUS, MAX_CRATER_RADIUS)
		local rayOrigin = child.Position + Vector3.new(0, 2, 0)
		local rayDir = Vector3.new(0, -(radius + 10), 0)

		-- terrain under the blast? carve a REAL crater
		local terrainHit = workspace:Raycast(rayOrigin, rayDir, terrainRay)
		if terrainHit then
			local center = terrainHit.Position
			terrain:FillBall(center, radius * 1.3, Enum.Material.Mud)
			terrain:FillBall(center + Vector3.new(0, radius * 0.55, 0), radius, Enum.Material.Air)
			return
		end

		-- otherwise: find the part floor and lay a crater patch on it
		local exclude = {}
		if dronesFolder then
			table.insert(exclude, dronesFolder)
		end
		local npcs = workspace:FindFirstChild("NPCs")
		if npcs then
			table.insert(exclude, npcs)
		end
		for _, plr in Players:GetPlayers() do
			if plr.Character then
				table.insert(exclude, plr.Character)
			end
		end
		floorRay.FilterDescendantsInstances = exclude

		local hit = workspace:Raycast(rayOrigin, rayDir, floorRay)
		-- only on mostly-flat, anchored surfaces (floors, not walls or debris)
		if hit and hit.Normal.Y > 0.65 and hit.Instance.Anchored then
			spawnCraterPatch(hit.Position, radius)
		end
	end)
end

--------------------------------------------------------------------
-- RPG DRONE ADD-ON (server)
-- Any drone model whose NAME contains "RPG" or "Rocket" carries 2
-- rockets. F launches one straight where the drone is aiming: fire
-- tail, hanging smoke trail, launch backblast, and a blast bigger
-- than a grenade. Reloads while hovering in a RearmZone.
--------------------------------------------------------------------
do
	local ROCKET_COUNT = 2
	local ROCKET_SPEED = 180 -- studs/sec
	local ROCKET_GRAVITY = 12 -- slight drop over long shots
	local ROCKET_LIFETIME = 4 -- seconds before it self-detonates mid-air
	local ROCKET_COOLDOWN = 1.5 -- seconds between shots
	local ROCKET_BLAST_RADIUS = 13 -- grenade is 9
	local ROCKET_DESTRUCTION_RADIUS = 16 -- bigger hole than a grenade (12)
	local ROCKET_DAMAGE_RADIUS = 14
	local ROCKET_REARM_SECONDS = 4 -- per rocket, hovering in a RearmZone

	local function isRPG(drone)
		local n = drone.Name:lower()
		return n:find("rpg") ~= nil or n:find("rocket") ~= nil
	end

	local fireEvent = Instance.new("RemoteEvent")
	fireEvent.Name = "DroneFireRocket"
	fireEvent.Parent = remotes

	-- give RPG drones their rockets
	task.spawn(function()
		while true do
			for _, drone in dronesFolder:GetChildren() do
				if drone:IsA("Model") and isRPG(drone) and drone.PrimaryPart
					and drone:GetAttribute("Rockets") == nil then
					drone:SetAttribute("Rockets", ROCKET_COUNT)
				end
			end
			task.wait(2)
		end
	end)

	-- reload rockets while hovering inside a RearmZone
	local reloadProgress = {}
	local function insideRearmZone(position)
		local folder = workspace:FindFirstChild("RearmZones")
		if not folder then
			return false
		end
		for _, zone in folder:GetChildren() do
			if zone:IsA("BasePart") then
				local rel = zone.CFrame:PointToObjectSpace(position)
				local half = zone.Size / 2 + Vector3.new(2, 8, 2)
				if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
					return true
				end
			end
		end
		return false
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, drone in dronesFolder:GetChildren() do
				if drone:IsA("Model") and isRPG(drone) and drone.PrimaryPart
					and drone:GetAttribute("PilotUserId") and not drone:GetAttribute("Dead") then
					local ammo = drone:GetAttribute("Rockets") or 0
					if ammo < ROCKET_COUNT and insideRearmZone(drone.PrimaryPart.Position) then
						drone:SetAttribute("Rearming", true)
						reloadProgress[drone] = (reloadProgress[drone] or 0) + 0.5
						if reloadProgress[drone] >= ROCKET_REARM_SECONDS then
							reloadProgress[drone] = 0
							drone:SetAttribute("Rockets", math.min(ammo + 1, ROCKET_COUNT))
						end
					else
						if drone:GetAttribute("Rearming") and not drone.Name:lower():find("bomber") then
							drone:SetAttribute("Rearming", nil)
						end
						reloadProgress[drone] = nil
					end
				end
			end
			for drone in reloadProgress do
				if not drone.Parent then
					reloadProgress[drone] = nil
				end
			end
		end
	end)

	local function explodeRocket(rocket, position, ownerId)
		if rocket:GetAttribute("Exploded") then
			return
		end
		rocket:SetAttribute("Exploded", true)

		local explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = ROCKET_BLAST_RADIUS
		explosion.BlastPressure = 500000
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace

		destroyBuildings(position, ROCKET_DESTRUCTION_RADIUS)
		damageInBlast(position, ownerId, ROCKET_DAMAGE_RADIUS)

		local xpSignal = game:GetService("ServerStorage"):FindFirstChild("XPSignal")
		if xpSignal and ownerId then
			xpSignal:Fire(ownerId, "demolition")
		end

		rocket:Destroy()
	end

	local lastFire = {}

	fireEvent.OnServerEvent:Connect(function(player, drone, direction)
		-- validate everything
		if typeof(drone) ~= "Instance" or not drone:IsA("Model") then
			return
		end
		if activePilots[player] ~= drone or not isRPG(drone) or drone:GetAttribute("Dead") then
			return
		end
		if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5 or direction.Magnitude > 2 then
			return
		end
		if direction.X ~= direction.X then -- NaN guard
			return
		end
		local root = drone.PrimaryPart
		if not root then
			return
		end
		local now = os.clock()
		if lastFire[player] and now - lastFire[player] < ROCKET_COOLDOWN then
			return
		end
		local ammo = drone:GetAttribute("Rockets") or 0
		if ammo <= 0 then
			return
		end
		drone:SetAttribute("Rockets", ammo - 1)
		lastFire[player] = now

		local dir = direction.Unit
		local spawnPos = root.Position - root.CFrame.UpVector * 1.8 + dir * 2.5

		-- the rocket itself
		local rocket = Instance.new("Part")
		rocket.Name = "DroneRocket"
		rocket.Size = Vector3.new(0.5, 0.5, 2.6)
		rocket.CFrame = CFrame.lookAt(spawnPos, spawnPos + dir)
		rocket.Color = Color3.fromRGB(60, 66, 52)
		rocket.Material = Enum.Material.Metal
		rocket.Anchored = true
		rocket.CanCollide = false
		rocket.CanQuery = false
		rocket.CanTouch = false
		rocket.CastShadow = false

		-- motor flame + hanging smoke trail from the tail
		local tail = Instance.new("Attachment")
		tail.Position = Vector3.new(0, 0, 1.3)
		tail.Parent = rocket

		local flame = Instance.new("ParticleEmitter")
		flame.Rate = 120
		flame.Lifetime = NumberRange.new(0.08, 0.16)
		flame.Speed = NumberRange.new(8, 14)
		flame.LightEmission = 1
		flame.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		flame.Color = ColorSequence.new(Color3.fromRGB(255, 220, 130), Color3.fromRGB(255, 120, 40))
		flame.EmissionDirection = Enum.NormalId.Back
		flame.Parent = tail

		local trail = Instance.new("ParticleEmitter")
		trail.Rate = 90
		trail.Lifetime = NumberRange.new(1.8, 3.2)
		trail.Speed = NumberRange.new(1, 3)
		trail.SpreadAngle = Vector2.new(10, 10)
		trail.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 3.2),
		})
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Color = ColorSequence.new(Color3.fromRGB(180, 180, 175), Color3.fromRGB(120, 120, 115))
		trail.Parent = tail

		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 150, 60)
		glow.Brightness = 3
		glow.Range = 14
		glow.Parent = rocket

		-- rocket hiss (motor sound pitched way up)
		local hiss = Instance.new("Sound")
		hiss.SoundId = MOTOR_SOUND_ID
		hiss.PlaybackSpeed = 2.4
		hiss.Volume = 0.5
		hiss.Looped = true
		hiss.RollOffMaxDistance = 300
		hiss.Parent = rocket
		hiss:Play()

		rocket.Parent = workspace

		-- launch: sharp crack + backblast puff behind the drone
		local crack = Instance.new("Sound")
		crack.SoundId = "rbxassetid://165969964"
		crack.PlaybackSpeed = 1.7
		crack.Volume = 0.7
		crack.RollOffMaxDistance = 500
		crack.Parent = root
		crack:Play()
		Debris:AddItem(crack, 2)

		local backblast = Instance.new("Part")
		backblast.Size = Vector3.new(1, 1, 1)
		backblast.Position = spawnPos - dir * 3
		backblast.Transparency = 1
		backblast.Anchored = true
		backblast.CanCollide = false
		backblast.CanQuery = false
		backblast.CanTouch = false
		backblast.Parent = workspace
		local puff = Instance.new("ParticleEmitter")
		puff.Rate = 0
		puff.Lifetime = NumberRange.new(0.5, 1.1)
		puff.Speed = NumberRange.new(10, 22)
		puff.SpreadAngle = Vector2.new(35, 35)
		puff.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(1, 4.5),
		})
		puff.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		puff.Color = ColorSequence.new(Color3.fromRGB(150, 150, 145))
		puff.EmissionDirection = Enum.NormalId.Back
		puff.Parent = backblast
		backblast.CFrame = CFrame.lookAt(backblast.Position, backblast.Position + dir)
		puff:Emit(25)
		Debris:AddItem(backblast, 2)

		-- server-side flight: stepped raycasts can't tunnel through walls
		task.spawn(function()
			local vel = dir * ROCKET_SPEED
			local pos = spawnPos
			local elapsed = 0
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = { drone, rocket }
			if player.Character then
				table.insert(exclude, player.Character)
			end
			rayParams.FilterDescendantsInstances = exclude

			while rocket.Parent and elapsed < ROCKET_LIFETIME do
				local dt = task.wait()
				elapsed += dt
				vel += Vector3.new(0, -ROCKET_GRAVITY * dt, 0)
				local newPos = pos + vel * dt
				local hit = workspace:Raycast(pos, newPos - pos, rayParams)
				if hit then
					explodeRocket(rocket, hit.Position + hit.Normal * 0.5, player.UserId)
					return
				end
				pos = newPos
				rocket.CFrame = CFrame.lookAt(pos, pos + vel)
			end
			if rocket.Parent then
				explodeRocket(rocket, pos, player.UserId)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastFire[p] = nil
	end)
end

--------------------------------------------------------------------
-- RPG DONKEY ADD-ON (server)
-- Any model in Workspace whose NAME contains "Donkey" becomes a war
-- donkey. No seat needed: the script puts an invisible saddle on its
-- back automatically. Works with a still (anchored) donkey — the RPG
-- tubes inside it (named rpg/rocket/launcher) stay put; on a moving
-- donkey they get welded on. Rider presses F to fire where the
-- camera looks, alternating tubes. 6 rockets, restocks on its own.
--------------------------------------------------------------------
do
	local DONKEY_ROCKETS = 6
	local DONKEY_RELOAD = 6 -- seconds per rocket restock
	local DONKEY_COOLDOWN = 1.2 -- seconds between shots
	local DONKEY_SPEED = 180
	local DONKEY_GRAVITY = 12
	local DONKEY_LIFETIME = 4
	local DONKEY_BLAST_RADIUS = 13
	local DONKEY_DESTRUCTION_RADIUS = 16
	local DONKEY_DAMAGE_RADIUS = 14

	local fireEvent = Instance.new("RemoteEvent")
	fireEvent.Name = "DonkeyFireRocket"
	fireEvent.Parent = remotes

	local function isDonkey(model)
		return model:IsA("Model") and model.Name:lower():find("donkey") ~= nil
	end

	local function nameMatches(inst)
		local n = inst.Name:lower()
		return n:find("rpg") ~= nil or n:find("rocket") ~= nil or n:find("launcher") ~= nil
	end

	local donkeyMuzzles = {} -- [donkey model] = { left tube part, right tube part, ... }

	-- the donkey's biggest part that is NOT an rpg tube = its body
	local function findBody(donkey)
		local body
		for _, p in donkey:GetDescendants() do
			if p:IsA("BasePart") and not nameMatches(p)
				and not (p.Parent and nameMatches(p.Parent))
				and (not body or p.Size.Magnitude > body.Size.Magnitude) then
				body = p
			end
		end
		return body
	end

	-- find the RPG tubes inside the donkey. If the donkey can move
	-- (unanchored), weld them on so they follow; if it's a still prop
	-- (anchored), leave everything exactly where it was placed.
	local function strapOnLaunchers(donkey, weldTo, donkeyMoves)
		local muzzles = {}
		for _, obj in donkey:GetDescendants() do
			-- match "RPG"/"Rocket"/"Launcher" things, but not parts nested
			-- inside an already-matched model (avoids doubles)
			if nameMatches(obj) and not (obj.Parent ~= donkey and nameMatches(obj.Parent)) then
				local parts = {}
				if obj:IsA("BasePart") then
					table.insert(parts, obj)
				else
					for _, p in obj:GetDescendants() do
						if p:IsA("BasePart") then
							table.insert(parts, p)
						end
					end
				end
				local muzzle
				for _, p in parts do
					if donkeyMoves and not p:FindFirstChild("DonkeyWeld") then
						local weld = Instance.new("WeldConstraint")
						weld.Name = "DonkeyWeld"
						weld.Part0 = weldTo
						weld.Part1 = p
						weld.Parent = p
						p.Anchored = false
						p.CanCollide = false
					end
					if not muzzle or p.Size.Magnitude > muzzle.Size.Magnitude then
						muzzle = p -- longest part = the tube itself
					end
				end
				if muzzle then
					table.insert(muzzles, muzzle)
				end
			end
		end
		return muzzles
	end

	local function setupDonkey(donkey)
		if donkey:GetAttribute("DonkeyRPGReady") then
			return
		end
		local body = findBody(donkey)
		if not body then
			return -- empty model, nothing to sit on
		end
		local donkeyMoves = not body.Anchored

		-- no seat? put an invisible saddle on its back so it's rideable
		local seat = donkey:FindFirstChildWhichIsA("VehicleSeat", true)
			or donkey:FindFirstChildWhichIsA("Seat", true)
		if not seat then
			seat = Instance.new("Seat")
			seat.Name = "DonkeySaddle"
			seat.Size = Vector3.new(2, 0.5, 2)
			seat.Transparency = 1
			seat.CanCollide = false
			-- find the donkey's actual back: probe straight down from above
			-- (some models have parts with huge invisible bounding boxes)
			local bbCF, bbSize = donkey:GetBoundingBox()
			local topProbe = RaycastParams.new()
			topProbe.FilterType = Enum.RaycastFilterType.Include
			topProbe.FilterDescendantsInstances = { donkey }
			local probeStart = Vector3.new(bbCF.X, bbCF.Y + bbSize.Y / 2 + 5, bbCF.Z)
			local topHit = workspace:Raycast(probeStart, Vector3.new(0, -(bbSize.Y + 10), 0), topProbe)
			local topY = topHit and topHit.Position.Y or (body.Position.Y + body.Size.Y / 2)
			local flatLook = bbCF.LookVector * Vector3.new(1, 0, 1)
			flatLook = flatLook.Magnitude > 0.1 and flatLook.Unit or Vector3.zAxis
			local saddlePos = Vector3.new(bbCF.X, topY + 0.3, bbCF.Z)
			seat.CFrame = CFrame.lookAt(saddlePos, saddlePos + flatLook)
			seat.Anchored = not donkeyMoves
			if donkeyMoves then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = seat
				weld.Parent = seat
			end
			seat.Parent = donkey
		end
		donkey:SetAttribute("DonkeyRPGReady", true)
		donkey:SetAttribute("Rockets", DONKEY_ROCKETS)
		donkeyMuzzles[donkey] = strapOnLaunchers(donkey, seat, donkeyMoves)
		if #donkeyMuzzles[donkey] == 0 then
			warn("[Donkey] '" .. donkey.Name .. "' has no RPG tubes inside it "
				.. "(name them with rpg/rocket/launcher) — firing from the saddle instead")
		end

		-- saddlebag restock: +1 rocket every DONKEY_RELOAD seconds
		task.spawn(function()
			while donkey.Parent do
				task.wait(DONKEY_RELOAD)
				local ammo = donkey:GetAttribute("Rockets") or 0
				if ammo < DONKEY_ROCKETS then
					donkey:SetAttribute("Rockets", ammo + 1)
				end
			end
			donkeyMuzzles[donkey] = nil
		end)
	end

	-- find donkeys now and keep checking for new ones dropped in later
	task.spawn(function()
		while true do
			for _, model in workspace:GetDescendants() do
				if isDonkey(model) then
					setupDonkey(model)
				end
			end
			task.wait(5)
		end
	end)

	local function explodeDonkeyRocket(rocket, position, ownerId)
		if rocket:GetAttribute("Exploded") then
			return
		end
		rocket:SetAttribute("Exploded", true)

		local explosion = Instance.new("Explosion")
		explosion.Position = position
		explosion.BlastRadius = DONKEY_BLAST_RADIUS
		explosion.BlastPressure = 500000
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Parent = workspace

		destroyBuildings(position, DONKEY_DESTRUCTION_RADIUS)
		damageInBlast(position, ownerId, DONKEY_DAMAGE_RADIUS)

		local xpSignal = game:GetService("ServerStorage"):FindFirstChild("XPSignal")
		if xpSignal and ownerId then
			xpSignal:Fire(ownerId, "demolition")
		end

		rocket:Destroy()
	end

	local lastFire = {}
	local sideFlip = {} -- [donkey] = which tube fired last, so shots alternate

	fireEvent.OnServerEvent:Connect(function(player, donkey, aimPoint)
		-- validate everything (server never trusts the client)
		if typeof(donkey) ~= "Instance" or not isDonkey(donkey) or not donkey.Parent then
			return
		end
		if typeof(aimPoint) ~= "Vector3" or aimPoint.X ~= aimPoint.X
			or aimPoint.Magnitude > 100000 then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seatPart = humanoid and humanoid.SeatPart
		if not seatPart or not seatPart:IsDescendantOf(donkey) then
			return -- only the rider can fire
		end
		local now = os.clock()
		if lastFire[player] and now - lastFire[player] < DONKEY_COOLDOWN then
			return
		end
		local ammo = donkey:GetAttribute("Rockets") or 0
		if ammo <= 0 then
			return
		end
		donkey:SetAttribute("Rockets", ammo - 1)
		lastFire[player] = now

		local tubes = donkeyMuzzles[donkey]
		local muzzle = seatPart
		if tubes and #tubes > 0 then
			sideFlip[donkey] = ((sideFlip[donkey] or 0) % #tubes) + 1
			local tube = tubes[sideFlip[donkey]]
			if tube and tube.Parent then
				muzzle = tube
			end
		end
		-- fly straight at the exact spot the rider's crosshair is on
		local launchBase = muzzle.Position + Vector3.new(0, 1, 0)
		local aim = aimPoint - launchBase
		if aim.Magnitude < 5 then
			return -- aiming at the donkey itself
		end
		local dir = aim.Unit
		local spawnPos = launchBase + dir * 3

		local rocket = Instance.new("Part")
		rocket.Name = "DonkeyRocket"
		rocket.Size = Vector3.new(0.5, 0.5, 2.6)
		rocket.CFrame = CFrame.lookAt(spawnPos, spawnPos + dir)
		rocket.Color = Color3.fromRGB(60, 66, 52)
		rocket.Material = Enum.Material.Metal
		rocket.Anchored = true
		rocket.CanCollide = false
		rocket.CanQuery = false
		rocket.CanTouch = false
		rocket.CastShadow = false

		local tail = Instance.new("Attachment")
		tail.Position = Vector3.new(0, 0, 1.3)
		tail.Parent = rocket

		local flame = Instance.new("ParticleEmitter")
		flame.Rate = 120
		flame.Lifetime = NumberRange.new(0.08, 0.16)
		flame.Speed = NumberRange.new(8, 14)
		flame.LightEmission = 1
		flame.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		flame.Color = ColorSequence.new(Color3.fromRGB(255, 220, 130), Color3.fromRGB(255, 120, 40))
		flame.EmissionDirection = Enum.NormalId.Back
		flame.Parent = tail

		local trail = Instance.new("ParticleEmitter")
		trail.Rate = 90
		trail.Lifetime = NumberRange.new(1.8, 3.2)
		trail.Speed = NumberRange.new(1, 3)
		trail.SpreadAngle = Vector2.new(10, 10)
		trail.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 3.2),
		})
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Color = ColorSequence.new(Color3.fromRGB(180, 180, 175), Color3.fromRGB(120, 120, 115))
		trail.Parent = tail

		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 150, 60)
		glow.Brightness = 3
		glow.Range = 14
		glow.Parent = rocket

		local hiss = Instance.new("Sound")
		hiss.SoundId = MOTOR_SOUND_ID
		hiss.PlaybackSpeed = 2.4
		hiss.Volume = 0.5
		hiss.Looped = true
		hiss.RollOffMaxDistance = 300
		hiss.Parent = rocket
		hiss:Play()

		rocket.Parent = workspace

		-- launch crack + backblast puff behind the tube
		local crack = Instance.new("Sound")
		crack.SoundId = "rbxassetid://165969964"
		crack.PlaybackSpeed = 1.7
		crack.Volume = 0.7
		crack.RollOffMaxDistance = 500
		crack.Parent = muzzle
		crack:Play()
		Debris:AddItem(crack, 2)

		local backblast = Instance.new("Part")
		backblast.Size = Vector3.new(1, 1, 1)
		backblast.CFrame = CFrame.lookAt(spawnPos - dir * 4, spawnPos)
		backblast.Transparency = 1
		backblast.Anchored = true
		backblast.CanCollide = false
		backblast.CanQuery = false
		backblast.CanTouch = false
		backblast.Parent = workspace
		local puff = Instance.new("ParticleEmitter")
		puff.Rate = 0
		puff.Lifetime = NumberRange.new(0.5, 1.1)
		puff.Speed = NumberRange.new(10, 22)
		puff.SpreadAngle = Vector2.new(35, 35)
		puff.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(1, 4.5),
		})
		puff.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		puff.Color = ColorSequence.new(Color3.fromRGB(150, 150, 145))
		puff.EmissionDirection = Enum.NormalId.Back
		puff.Parent = backblast
		puff:Emit(25)
		Debris:AddItem(backblast, 2)

		-- stepped raycast flight so it can't tunnel through walls
		task.spawn(function()
			local vel = dir * DONKEY_SPEED
			local pos = spawnPos
			local elapsed = 0
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = { donkey, rocket }
			if character then
				table.insert(exclude, character)
			end
			rayParams.FilterDescendantsInstances = exclude

			while rocket.Parent and elapsed < DONKEY_LIFETIME do
				local dt = task.wait()
				elapsed += dt
				vel += Vector3.new(0, -DONKEY_GRAVITY * dt, 0)
				local newPos = pos + vel * dt
				local hit = workspace:Raycast(pos, newPos - pos, rayParams)
				if hit then
					explodeDonkeyRocket(rocket, hit.Position + hit.Normal * 0.5, player.UserId)
					return
				end
				pos = newPos
				rocket.CFrame = CFrame.lookAt(pos, pos + vel)
			end
			if rocket.Parent then
				explodeDonkeyRocket(rocket, pos, player.UserId)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastFire[p] = nil
	end)
end

--------------------------------------------------------------------
-- SHOOTABLE DRONES ADD-ON (server)
-- Every drone gets invisible "electronics health" (a hidden
-- Humanoid), so ANY gun that hurts players — ACS, the official kit,
-- anything — can also shoot down drones. One bullet: small airburst
-- pop, the motors die, and it drops burning. Explosions near a
-- drone knock it down too.
--------------------------------------------------------------------
do
	local function shootDown(drone)
		if drone:GetAttribute("ShotDown") then
			return
		end
		drone:SetAttribute("ShotDown", true)

		local root = drone.PrimaryPart or drone:FindFirstChildWhichIsA("BasePart", true)
		if root then
			-- small airburst: pop + flash + sparks, then burning fall
			local pop = Instance.new("Sound")
			pop.SoundId = "rbxassetid://165969964"
			pop.PlaybackSpeed = 1.9
			pop.Volume = 0.9
			pop.RollOffMaxDistance = 450
			pop.Parent = root
			pop:Play()
			Debris:AddItem(pop, 2)

			local burstAttachment = Instance.new("Attachment")
			burstAttachment.Parent = root

			local flash = Instance.new("ParticleEmitter")
			flash.Rate = 0
			flash.Lifetime = NumberRange.new(0.06, 0.14)
			flash.Speed = NumberRange.new(10, 20)
			flash.SpreadAngle = Vector2.new(180, 180)
			flash.LightEmission = 1
			flash.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 2.2),
				NumberSequenceKeypoint.new(1, 0.5),
			})
			flash.Color = ColorSequence.new(Color3.fromRGB(255, 220, 130), Color3.fromRGB(255, 120, 40))
			flash.Parent = burstAttachment
			flash:Emit(10)

			local sparks = Instance.new("ParticleEmitter")
			sparks.Rate = 0
			sparks.Lifetime = NumberRange.new(0.3, 0.7)
			sparks.Speed = NumberRange.new(12, 26)
			sparks.SpreadAngle = Vector2.new(180, 180)
			sparks.LightEmission = 1
			sparks.Size = NumberSequence.new(0.18)
			sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 110))
			sparks.Parent = burstAttachment
			sparks:Emit(16)

			local burnSmoke = Instance.new("ParticleEmitter")
			burnSmoke.Rate = 30
			burnSmoke.Lifetime = NumberRange.new(0.8, 1.6)
			burnSmoke.Speed = NumberRange.new(1, 3)
			burnSmoke.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 2.4),
			})
			burnSmoke.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			burnSmoke.Color = ColorSequence.new(Color3.fromRGB(40, 40, 40))
			burnSmoke.Parent = burstAttachment

			local burnFlame = Instance.new("ParticleEmitter")
			burnFlame.Rate = 18
			burnFlame.Lifetime = NumberRange.new(0.15, 0.35)
			burnFlame.Speed = NumberRange.new(1, 2)
			burnFlame.LightEmission = 1
			burnFlame.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.7),
				NumberSequenceKeypoint.new(1, 0.2),
			})
			burnFlame.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 90, 30))
			burnFlame.Parent = burstAttachment
		end

		-- flying drones: the flight loop cuts the motors when battery dies
		if (drone:GetAttribute("Battery") or 0) > 0 then
			drone:SetAttribute("Battery", 0)
		end

		-- parked drones have no flight loop: knock them over + finish them
		task.delay(0.7, function()
			if not drone.Parent or drone:GetAttribute("Dead") then
				return
			end
			drone:SetAttribute("DeathReason", "battery")
			drone:SetAttribute("Dead", true)
			if root then
				local motor = root:FindFirstChild("DroneMotor")
				if motor then motor:Stop() end
				local lv = root:FindFirstChild("DroneLinearVelocity")
				local ao = root:FindFirstChild("DroneAlignOrientation")
				if lv then lv.Enabled = false end
				if ao then ao.Enabled = false end
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.new(math.random(-6, 6), 4, math.random(-6, 6))
				root.AssemblyAngularVelocity = Vector3.new(
					math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
			end
			task.delay(2.5, function()
				if drone.Parent then
					local at = drone.PrimaryPart or drone:FindFirstChildWhichIsA("BasePart", true)
					local finish = Instance.new("Explosion")
					finish.Position = at and at.Position or Vector3.zero
					finish.BlastRadius = 6
					finish.BlastPressure = 300000
					finish.DestroyJointRadiusPercent = 0
					finish.ExplosionType = Enum.ExplosionType.NoCraters
					finish.Parent = workspace
					drone:Destroy()
				end
			end)
		end)
	end

	local function armDrone(drone)
		if not drone:IsA("Model") then
			return
		end
		-- fresh health every time (respawned clones carry stale copies)
		local old = drone:FindFirstChildOfClass("Humanoid")
		if old then
			old:Destroy()
		end
		drone:SetAttribute("ShotDown", nil)

		-- guns find the health by looking at the HIT PART'S PARENT, so
		-- pull every part out of nested groups up to the drone model
		for _, part in drone:GetDescendants() do
			if part:IsA("BasePart") and part.Parent ~= drone then
				part.Parent = drone
			end
		end

		local electronics = Instance.new("Humanoid")
		electronics.MaxHealth = 100
		electronics.Health = 100
		electronics.BreakJointsOnDeath = false -- don't shatter the welds
		electronics.RequiresNeck = false
		electronics.EvaluateStateMachine = false -- no walking physics, just a health bag
		electronics.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		electronics.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		electronics.Parent = drone

		-- ANY damage from ANY weapon = instant kaboom
		electronics.HealthChanged:Connect(function(health)
			if health < electronics.MaxHealth then
				shootDown(drone)
			end
		end)
	end

	for _, drone in dronesFolder:GetChildren() do
		task.spawn(armDrone, drone)
	end
	dronesFolder.ChildAdded:Connect(function(drone)
		task.wait(0.2) -- let the drone system set it up first
		armDrone(drone)
	end)
end
