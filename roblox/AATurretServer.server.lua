--[[
	AA TURRET — Script (ServerScriptService)
	A separate script: don't paste into the drone scripts.

	Any model in Workspace whose NAME contains "Turret" or "AA" becomes
	a manned anti-air gun:
	- hold E at the turret to man it (you get frozen in the gunner seat)
	- realistic gunner: limited traverse speed, overheating barrel,
	  tracer fire, recoil, zoom optics (handled by the client script)
	- shots hurt players AND chew through drones: enough hits kill a
	  drone's battery and it drops out of the sky
	- explosions damage the turret; destroyed turrets burn and then
	  repair themselves after a while

	Studio setup:
	1. Name your turret model with "Turret" or "AA" in the name.
	2. Name the gun tube part "Barrel" (or "Cannon"/"Gun") — otherwise
	   the longest part is used. The barrel should point along its
	   front (look) direction.
	3. Also install AATurretClient (LocalScript, StarterPlayerScripts).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local FIRE_INTERVAL = 0.09 -- min seconds between shots (~11/sec)
local SHOT_DAMAGE = 9 -- per hit on players/NPCs
local DRONE_HULL = 10 -- hits a drone can take before it drops
local RANGE = 900 -- studs
local HEAT_PER_SHOT = 4.5 -- heat gauge is 0..100
local COOL_RATE = 16 -- heat lost per second while not firing
local OVERHEAT_UNLOCK = 25 -- must cool below this to fire again
local TURRET_HP = 250
local EXPLOSION_DAMAGE = 120 -- per explosion that lands next to it
local REPAIR_TIME = 45 -- seconds a destroyed turret stays dead
local CRACK_SOUND_ID = "rbxassetid://165969964"

-- remotes ------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "TurretRemotes"
remotes.Parent = ReplicatedStorage

local fireRemote = Instance.new("RemoteEvent")
fireRemote.Name = "TurretFire"
fireRemote.Parent = remotes

local aimRemote = Instance.new("UnreliableRemoteEvent")
aimRemote.Name = "TurretAim"
aimRemote.Parent = remotes

local exitRemote = Instance.new("RemoteEvent")
exitRemote.Name = "TurretExit"
exitRemote.Parent = remotes

local stateRemote = Instance.new("RemoteEvent")
stateRemote.Name = "TurretState"
stateRemote.Parent = remotes

-- helpers ------------------------------------------------------------
local function isTurret(model)
	if not model:IsA("Model") then
		return false
	end
	local n = model.Name:lower()
	return n:find("turret") ~= nil or n:find("aa ") ~= nil or n == "aa" or n:sub(1, 3) == "aa_"
end

local function findBarrel(turret)
	local named
	local longest
	for _, p in turret:GetDescendants() do
		if p:IsA("BasePart") then
			local n = p.Name:lower()
			if n:find("barrel") or n:find("cannon") or n:find("gun") then
				if not named or p.Size.Magnitude > named.Size.Magnitude then
					named = p
				end
			end
			if not longest or p.Size.Magnitude > longest.Size.Magnitude then
				longest = p
			end
		end
	end
	return named or longest
end

local function findBase(turret, barrel)
	local base
	for _, p in turret:GetDescendants() do
		if p:IsA("BasePart") and p ~= barrel then
			if not base or p.Size.Magnitude > base.Size.Magnitude then
				base = p
			end
		end
	end
	return base or barrel
end

local turretData = {} -- [turret] = { barrel, base, prompt, tipAttachment, flash, gunner }
local gunners = {} -- [player] = turret

-- entering / exiting -------------------------------------------------
local function exitTurret(player)
	local turret = gunners[player]
	if not turret then
		return
	end
	gunners[player] = nil
	if turret.Parent then
		turret:SetAttribute("GunnerUserId", nil)
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = false
	end
	stateRemote:FireClient(player, "exit")
end

local function enterTurret(player, turret)
	local data = turretData[turret]
	if not data then
		return
	end
	if turret:GetAttribute("GunnerUserId") or turret:GetAttribute("Dead") then
		return -- someone's already on it, or it's wrecked
	end
	if gunners[player] then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- stand the gunner right behind the gun and freeze them there
	local behind = data.barrel.Position - data.barrel.CFrame.LookVector * 4
	hrp.CFrame = CFrame.lookAt(
		Vector3.new(behind.X, hrp.Position.Y, behind.Z),
		Vector3.new(data.barrel.Position.X, hrp.Position.Y, data.barrel.Position.Z)
	)
	hrp.Anchored = true

	gunners[player] = turret
	turret:SetAttribute("GunnerUserId", player.UserId)
	stateRemote:FireClient(player, "enter", turret, data.barrel)
end

-- turret death / repair ----------------------------------------------
local function wreckTurret(turret)
	local data = turretData[turret]
	if not data or turret:GetAttribute("Dead") then
		return
	end
	turret:SetAttribute("Dead", true)
	data.prompt.Enabled = false

	-- kick the gunner off
	for player, t in gunners do
		if t == turret then
			exitTurret(player)
		end
	end

	-- burn: black smoke + fire on the barrel
	local smoke = Instance.new("Smoke")
	smoke.Name = "WreckSmoke"
	smoke.Color = Color3.fromRGB(30, 30, 30)
	smoke.Size = 6
	smoke.RiseVelocity = 8
	smoke.Parent = data.barrel
	local fire = Instance.new("Fire")
	fire.Name = "WreckFire"
	fire.Size = 5
	fire.Heat = 8
	fire.Parent = data.barrel

	local boom = Instance.new("Sound")
	boom.SoundId = CRACK_SOUND_ID
	boom.PlaybackSpeed = 0.6
	boom.Volume = 1
	boom.RollOffMaxDistance = 500
	boom.Parent = data.barrel
	boom:Play()
	Debris:AddItem(boom, 3)

	task.delay(REPAIR_TIME, function()
		if not turret.Parent then
			return
		end
		turret:SetAttribute("Health", TURRET_HP)
		turret:SetAttribute("Heat", 0)
		turret:SetAttribute("Overheated", nil)
		turret:SetAttribute("Dead", nil)
		if smoke.Parent then smoke:Destroy() end
		if fire.Parent then fire:Destroy() end
		data.prompt.Enabled = true
	end)
end

-- setup --------------------------------------------------------------
local function setupTurret(turret)
	if turretData[turret] then
		return
	end
	local barrel = findBarrel(turret)
	if not barrel then
		return
	end
	local base = findBase(turret, barrel)
	barrel.Anchored = true

	turret:SetAttribute("Health", TURRET_HP)
	turret:SetAttribute("Heat", 0)

	-- muzzle attachment at the tip of the barrel for flash + smoke
	local halfLength = math.max(barrel.Size.X, barrel.Size.Y, barrel.Size.Z) / 2
	local tip = Instance.new("Attachment")
	tip.Name = "MuzzleTip"
	tip.Position = Vector3.new(0, 0, -halfLength)
	tip.Parent = barrel

	local flash = Instance.new("ParticleEmitter")
	flash.Name = "MuzzleFlash"
	flash.Rate = 0
	flash.Lifetime = NumberRange.new(0.04, 0.08)
	flash.Speed = NumberRange.new(15, 25)
	flash.LightEmission = 1
	flash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0.4),
	})
	flash.Color = ColorSequence.new(Color3.fromRGB(255, 225, 140), Color3.fromRGB(255, 120, 40))
	flash.Parent = tip

	-- muzzle smoke puff per shot
	local muzzleSmoke = Instance.new("ParticleEmitter")
	muzzleSmoke.Name = "MuzzleSmoke"
	muzzleSmoke.Rate = 0
	muzzleSmoke.Lifetime = NumberRange.new(0.4, 0.9)
	muzzleSmoke.Speed = NumberRange.new(3, 7)
	muzzleSmoke.SpreadAngle = Vector2.new(25, 25)
	muzzleSmoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	muzzleSmoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	muzzleSmoke.Color = ColorSequence.new(Color3.fromRGB(160, 160, 155))
	muzzleSmoke.Parent = tip

	-- heat shimmer smoke that pours off a hot barrel
	local heatSmoke = Instance.new("ParticleEmitter")
	heatSmoke.Name = "HeatSmoke"
	heatSmoke.Rate = 14
	heatSmoke.Enabled = false
	heatSmoke.Lifetime = NumberRange.new(0.6, 1.2)
	heatSmoke.Speed = NumberRange.new(1, 2)
	heatSmoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1.4),
	})
	heatSmoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	heatSmoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 195))
	heatSmoke.Parent = tip

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Man AA Turret"
	prompt.ObjectText = turret.Name
	prompt.HoldDuration = 0.5
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = base

	prompt.Triggered:Connect(function(player)
		enterTurret(player, turret)
	end)

	turretData[turret] = {
		barrel = barrel,
		base = base,
		prompt = prompt,
		tip = tip,
		flash = flash,
		muzzleSmoke = muzzleSmoke,
		heatSmoke = heatSmoke,
		shots = 0,
	}
end

task.spawn(function()
	while true do
		for _, model in workspace:GetDescendants() do
			if isTurret(model) then
				setupTurret(model)
			end
		end
		-- clean up removed turrets
		for turret in turretData do
			if not turret.Parent then
				turretData[turret] = nil
			end
		end
		task.wait(5)
	end
end)

-- cooling loop --------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.2)
		for turret, data in turretData do
			local heat = turret:GetAttribute("Heat") or 0
			if heat > 0 then
				heat = math.max(heat - COOL_RATE * 0.2, 0)
				turret:SetAttribute("Heat", heat)
				if turret:GetAttribute("Overheated") and heat <= OVERHEAT_UNLOCK then
					turret:SetAttribute("Overheated", nil)
				end
			end
			-- a hot barrel visibly smokes
			data.heatSmoke.Enabled = heat > 65
		end
	end
end)

-- aiming: rotate the barrel so everyone sees where it points ----------
aimRemote.OnServerEvent:Connect(function(player, direction)
	local turret = gunners[player]
	local data = turret and turretData[turret]
	if not data then
		return
	end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5
		or direction.Magnitude > 2 or direction.X ~= direction.X then
		return
	end
	local barrel = data.barrel
	barrel.CFrame = CFrame.lookAt(barrel.Position, barrel.Position + direction.Unit)
end)

-- firing ---------------------------------------------------------------
local lastShot = {}

fireRemote.OnServerEvent:Connect(function(player, direction)
	local turret = gunners[player]
	local data = turret and turretData[turret]
	if not data or turret:GetAttribute("Dead") then
		return
	end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5
		or direction.Magnitude > 2 or direction.X ~= direction.X then
		return
	end
	local now = os.clock()
	if lastShot[player] and now - lastShot[player] < FIRE_INTERVAL then
		return
	end
	if turret:GetAttribute("Overheated") then
		return
	end

	-- heat up; lock the gun when it maxes out (steam hiss)
	local heat = (turret:GetAttribute("Heat") or 0) + HEAT_PER_SHOT
	turret:SetAttribute("Heat", math.min(heat, 100))
	if heat >= 100 then
		turret:SetAttribute("Overheated", true)
		local hiss = Instance.new("Sound")
		hiss.SoundId = "rbxassetid://131961136"
		hiss.PlaybackSpeed = 3.2
		hiss.Volume = 0.6
		hiss.RollOffMaxDistance = 120
		hiss.Parent = data.barrel
		hiss:Play()
		Debris:AddItem(hiss, 2)
	end
	lastShot[player] = now

	local dir = direction.Unit
	-- heat makes the gun less accurate, like a real overworked barrel
	local spread = (turret:GetAttribute("Heat") or 0) / 100 * 0.03
	dir = (dir + Vector3.new(
		(math.random() - 0.5) * spread,
		(math.random() - 0.5) * spread,
		(math.random() - 0.5) * spread
	)).Unit

	local origin = data.tip.WorldPosition

	-- muzzle flash + smoke + crack for everyone nearby
	data.flash:Emit(6)
	data.muzzleSmoke:Emit(3)
	local crack = Instance.new("Sound")
	crack.SoundId = CRACK_SOUND_ID
	crack.PlaybackSpeed = 1.3 + math.random() * 0.2
	crack.Volume = 0.6
	crack.RollOffMaxDistance = 600
	crack.Parent = data.barrel
	crack:Play()
	Debris:AddItem(crack, 2)
	-- low thump under the crack so it sounds heavy up close
	local thump = Instance.new("Sound")
	thump.SoundId = CRACK_SOUND_ID
	thump.PlaybackSpeed = 0.55
	thump.Volume = 0.35
	thump.RollOffMaxDistance = 150
	thump.Parent = data.barrel
	thump:Play()
	Debris:AddItem(thump, 3)

	-- eject a brass casing out the side
	local casing = Instance.new("Part")
	casing.Size = Vector3.new(0.12, 0.12, 0.4)
	casing.Color = Color3.fromRGB(190, 150, 60)
	casing.Material = Enum.Material.Metal
	casing.CFrame = data.barrel.CFrame * CFrame.new(0.8, -0.2, 1)
	casing.CanCollide = true
	casing.CanQuery = false
	casing.CanTouch = false
	casing.Parent = workspace
	casing.AssemblyLinearVelocity = data.barrel.CFrame.RightVector * (6 + math.random() * 4)
		+ Vector3.new(0, 5 + math.random() * 3, 0)
	casing.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
	Debris:AddItem(casing, 4)

	-- hitscan with the turret and gunner excluded
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { turret }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(origin, dir * RANGE, rayParams)
	local endPos = hit and hit.Position or (origin + dir * RANGE)

	-- tracer shells: like real AA, every 3rd round glows and you can
	-- watch it FLY to the target (hit is still instant under the hood)
	local distance = (endPos - origin).Magnitude
	data.shots += 1
	if data.shots % 3 == 0 then
		local tracer = Instance.new("Part")
		tracer.Size = Vector3.new(0.18, 0.18, 1.8)
		tracer.CFrame = CFrame.lookAt(origin, endPos)
		tracer.Color = Color3.fromRGB(255, 170, 60)
		tracer.Material = Enum.Material.Neon
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.CanQuery = false
		tracer.CanTouch = false
		tracer.CastShadow = false

		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 170, 60)
		glow.Brightness = 2
		glow.Range = 10
		glow.Parent = tracer

		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.1, 0)
		a0.Parent = tracer
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.1, 0)
		a1.Parent = tracer
		local streak = Instance.new("Trail")
		streak.Attachment0 = a0
		streak.Attachment1 = a1
		streak.Lifetime = 0.12
		streak.LightEmission = 1
		streak.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90))
		streak.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		streak.WidthScale = NumberSequence.new(0.35)
		streak.Parent = tracer

		tracer.Parent = workspace
		local flightTime = distance / 1400 -- shell speed, studs/sec
		TweenService:Create(tracer, TweenInfo.new(flightTime, Enum.EasingStyle.Linear), {
			CFrame = CFrame.lookAt(endPos, endPos + dir),
		}):Play()
		Debris:AddItem(tracer, flightTime + 0.05)
	end

	if not hit then
		return
	end

	-- impact FX: sparks on hard stuff, a dirt kick on ground/terrain
	local sparkHolder = Instance.new("Part")
	sparkHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	sparkHolder.Position = hit.Position
	sparkHolder.Transparency = 1
	sparkHolder.Anchored = true
	sparkHolder.CanCollide = false
	sparkHolder.CanQuery = false
	sparkHolder.CanTouch = false
	sparkHolder.Parent = workspace
	local hitGround = hit.Instance:IsA("Terrain") or hit.Normal.Y > 0.7
	local impactFX = Instance.new("ParticleEmitter")
	impactFX.Rate = 0
	if hitGround then
		impactFX.Lifetime = NumberRange.new(0.4, 0.9)
		impactFX.Speed = NumberRange.new(6, 14)
		impactFX.SpreadAngle = Vector2.new(40, 40)
		impactFX.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1.8),
		})
		impactFX.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		impactFX.Color = ColorSequence.new(Color3.fromRGB(115, 90, 65))
	else
		impactFX.Lifetime = NumberRange.new(0.15, 0.4)
		impactFX.Speed = NumberRange.new(8, 20)
		impactFX.SpreadAngle = Vector2.new(60, 60)
		impactFX.LightEmission = 1
		impactFX.Size = NumberSequence.new(0.2)
		impactFX.Color = ColorSequence.new(Color3.fromRGB(255, 200, 110))
	end
	impactFX.Parent = sparkHolder
	impactFX:Emit(hitGround and 12 or 8)
	Debris:AddItem(sparkHolder, 1.5)

	-- 1) players / NPCs
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(SHOT_DAMAGE)
		model:SetAttribute("LastHitBy", player.UserId)
		model:SetAttribute("LastHitTime", os.clock())
		return
	end

	-- 2) drones: chip away the hull; a dead hull kills the battery
	--    and the drone drops out of the sky (the drone system handles
	--    the fall + explosion by itself)
	local dronesFolder = workspace:FindFirstChild("Drones")
	local droneModel = model
	while droneModel and droneModel.Parent ~= dronesFolder do
		droneModel = droneModel:FindFirstAncestorOfClass("Model")
	end
	if droneModel and dronesFolder and droneModel.Parent == dronesFolder then
		local hull = droneModel:GetAttribute("Hull")
		if hull == nil then
			hull = DRONE_HULL
		end
		hull -= 1
		droneModel:SetAttribute("Hull", hull)
		if hull <= 0 and (droneModel:GetAttribute("Battery") or 0) > 0 then
			droneModel:SetAttribute("Battery", 0) -- flight loop cuts the motors

			-- small realistic airburst: sharp pop, flash, sparks — then
			-- the drone burns and drops (the drone system handles the fall)
			local root = droneModel.PrimaryPart
				or droneModel:FindFirstChildWhichIsA("BasePart", true)
			if root then
				local pop = Instance.new("Sound")
				pop.SoundId = CRACK_SOUND_ID
				pop.PlaybackSpeed = 1.9
				pop.Volume = 0.9
				pop.RollOffMaxDistance = 450
				pop.Parent = root
				pop:Play()
				Debris:AddItem(pop, 2)

				local burstAttachment = Instance.new("Attachment")
				burstAttachment.Parent = root

				local burstFlash = Instance.new("ParticleEmitter")
				burstFlash.Rate = 0
				burstFlash.Lifetime = NumberRange.new(0.06, 0.14)
				burstFlash.Speed = NumberRange.new(10, 20)
				burstFlash.SpreadAngle = Vector2.new(180, 180)
				burstFlash.LightEmission = 1
				burstFlash.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 2.2),
					NumberSequenceKeypoint.new(1, 0.5),
				})
				burstFlash.Color = ColorSequence.new(Color3.fromRGB(255, 220, 130), Color3.fromRGB(255, 120, 40))
				burstFlash.Parent = burstAttachment
				burstFlash:Emit(10)

				local burstSparks = Instance.new("ParticleEmitter")
				burstSparks.Rate = 0
				burstSparks.Lifetime = NumberRange.new(0.3, 0.7)
				burstSparks.Speed = NumberRange.new(12, 26)
				burstSparks.SpreadAngle = Vector2.new(180, 180)
				burstSparks.LightEmission = 1
				burstSparks.Size = NumberSequence.new(0.18)
				burstSparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 110))
				burstSparks.Parent = burstAttachment
				burstSparks:Emit(16)

				-- it burns on the way down: black smoke + flame flicker
				local burnSmoke = Instance.new("ParticleEmitter")
				burnSmoke.Name = "ShotDownSmoke"
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
				burnFlame.Name = "ShotDownFlame"
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
		end
	end
end)

-- explosions hurt turrets ----------------------------------------------
workspace.ChildAdded:Connect(function(child)
	if not child:IsA("Explosion") then
		return
	end
	for turret, data in turretData do
		if turret.Parent and not turret:GetAttribute("Dead") then
			local distance = (data.base.Position - child.Position).Magnitude
			if distance <= child.BlastRadius + 10 then
				local hp = (turret:GetAttribute("Health") or TURRET_HP) - EXPLOSION_DAMAGE
				turret:SetAttribute("Health", math.max(hp, 0))
				if hp <= 0 then
					wreckTurret(turret)
				end
			end
		end
	end
end)

-- leaving / dying / exit key -------------------------------------------
exitRemote.OnServerEvent:Connect(exitTurret)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				exitTurret(player)
			end)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	exitTurret(player)
	lastShot[player] = nil
end)

print("[AATurret] ready")
