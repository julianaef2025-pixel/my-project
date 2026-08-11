--[[
	NPC PANIC — Script (ServerScriptService)
	A separate script from the drone system: do NOT paste into the drone script.

	Setup:
	- Create a Folder in Workspace named exactly "NPCs"
	- Drag your NPC models into it (each needs a Humanoid + HumanoidRootPart,
	  and their parts must NOT be anchored or they can't walk)

	Behavior:
	- NPCs calmly wander near where you placed them
	- A flying drone within 20 studs, any explosion within 80 studs, or a
	  gunshot signal makes them PANIC: scream in chat bubbles and sprint
	  away from the threat, zigzagging, occasionally diving/jumping
	- Panic is contagious: NPCs near a panicking NPC start panicking too
	- They calm down ~12 seconds after the threat is gone

	Gunshots from your own weapons: fire the BindableEvent this script
	creates in ServerStorage ("NPCGunshotSignal") from your gun script:
	    game.ServerStorage.NPCGunshotSignal:Fire(muzzlePosition)
]]

local ServerStorage = game:GetService("ServerStorage")
local Chat = game:GetService("Chat")

-- hearing
local DRONE_HEAR_RANGE = 20 -- studs: how close a flying drone must be
local EXPLOSION_HEAR_RANGE = 80 -- everyone hears a blast
local GUNSHOT_HEAR_RANGE = 60
local PANIC_SPREAD_RANGE = 15 -- panic jumps between NPCs this close

-- behavior
local PANIC_DURATION = 12 -- seconds of panic after the last scare
local WANDER_RANGE = 25 -- how far from home they stroll
local WALK_SPEED = 8
local PANIC_SPEED = 22

local SCREAMS = {
	"DRONE!!! DRONE!!!",
	"TAKE COVER!!",
	"GET DOWN!! GET DOWN!!",
	"RUN!!!",
	"AAAAAAAAH!!",
	"IT'S RIGHT ABOVE US!!",
	"I HEAR IT!! WHERE IS IT?!",
	"MOVE MOVE MOVE!!",
	"INCOMING!!!",
	"MEDIC!! MEDIC!!",
	"IT'S GONNA DROP SOMETHING!!",
	"DON'T STAND STILL!!",
}

-- your gun scripts can fire this with the shot position
local gunshotSignal = Instance.new("BindableEvent")
gunshotSignal.Name = "NPCGunshotSignal"
gunshotSignal.Parent = ServerStorage

local npcFolder = workspace:WaitForChild("NPCs", 10)
if not npcFolder then
	warn("[NPCPanic] No folder named 'NPCs' found in Workspace — create one and put your NPC models inside it")
	npcFolder = Instance.new("Folder")
	npcFolder.Name = "NPCs"
	npcFolder.Parent = workspace
end

local states = {} -- [model] = state table

local function setupNpc(model)
	if not model:IsA("Model") or states[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return -- not a character rig (decorations etc.), silently skip
	end
	local hrp = humanoid.RootPart
		or model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")
	if not hrp then
		warn("[NPCPanic] '" .. model.Name .. "' has a Humanoid but no parts, skipping")
		return
	end

	-- anchored parts can't walk — free-model NPCs are usually anchored, so unanchor everything
	local unanchored = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Anchored then
			part.Anchored = false
			unanchored += 1
		end
	end

	-- make sure nothing is force-disabling movement
	humanoid.PlatformStand = false
	humanoid.Sit = false
	if humanoid.WalkSpeed <= 0 then
		humanoid.WalkSpeed = WALK_SPEED
	end

	-- server drives the AI so it moves smoothly for everyone
	pcall(function()
		hrp:SetNetworkOwner(nil)
	end)
	humanoid.WalkSpeed = WALK_SPEED

	states[model] = {
		humanoid = humanoid,
		hrp = hrp,
		home = hrp.Position,
		panicUntil = 0,
		threatPos = nil,
		nextMove = 0,
		nextScream = 0,
	}

	print("[NPCPanic] Registered NPC '" .. model.Name .. "'"
		.. (unanchored > 0 and (" (unanchored " .. unanchored .. " parts)") or ""))

	humanoid.Died:Connect(function()
		states[model] = nil
	end)
end

-- scream in a chat bubble above the NPC's head
local function scream(model, state, now)
	if now < state.nextScream then
		return
	end
	state.nextScream = now + 1.5 + math.random() * 2
	local head = model:FindFirstChild("Head") or state.hrp
	local phrase = SCREAMS[math.random(1, #SCREAMS)]
	pcall(function()
		Chat:Chat(head, phrase, Enum.ChatColor.Red)
	end)
end

local function panic(model, state, threatPos, now)
	local firstScare = now > state.panicUntil
	state.panicUntil = now + PANIC_DURATION
	state.threatPos = threatPos
	state.humanoid.WalkSpeed = PANIC_SPEED
	if firstScare then
		state.nextScream = 0 -- scream immediately on the first scare
		state.nextMove = 0
	end
	scream(model, state, now)
end

-- scare every NPC within range of a position (explosions, gunshots)
local function panicAt(position, range)
	local now = os.clock()
	for model, state in states do
		if model.Parent and state.humanoid.Health > 0 then
			if (state.hrp.Position - position).Magnitude <= range then
				panic(model, state, position, now)
			end
		end
	end
end

-- hook up existing and future NPCs (searches the whole folder, even nested groups)
for _, descendant in npcFolder:GetDescendants() do
	setupNpc(descendant)
end
for _, child in npcFolder:GetChildren() do
	setupNpc(child)
end
npcFolder.DescendantAdded:Connect(function(descendant)
	task.wait()
	setupNpc(descendant)
	if descendant:IsA("Humanoid") then
		setupNpc(descendant.Parent)
	end
end)

-- startup report so problems show in the Output window
task.delay(3, function()
	local count = 0
	for _ in states do
		count += 1
	end
	if count == 0 then
		warn("[NPCPanic] 0 NPCs registered! Check: models must be inside the Workspace 'NPCs' folder and each must contain a Humanoid")
	else
		print("[NPCPanic] " .. count .. " NPC(s) active")
	end
end)

-- explosions scare everyone nearby (drone hits, grenades — all of it)
workspace.ChildAdded:Connect(function(child)
	if child:IsA("Explosion") then
		panicAt(child.Position, EXPLOSION_HEAR_RANGE)
	end
end)

-- gunshots from your weapons
gunshotSignal.Event:Connect(function(position)
	if typeof(position) == "Vector3" then
		panicAt(position, GUNSHOT_HEAR_RANGE)
	end
end)

-- collect the positions of every drone that is currently airborne
local function getActiveDronePositions()
	local positions = {}
	local drones = workspace:FindFirstChild("Drones")
	if drones then
		for _, drone in drones:GetChildren() do
			if drone:IsA("Model") and (drone:GetAttribute("PilotUserId") or drone:GetAttribute("Dead")) then
				local root = drone.PrimaryPart
				if root then
					table.insert(positions, root.Position)
				end
			end
		end
	end
	return positions
end

-- main brain loop
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		local dronePositions = getActiveDronePositions()

		for model, state in states do
			if not model.Parent or state.humanoid.Health <= 0 then
				states[model] = nil
				continue
			end

			local myPos = state.hrp.Position

			-- can I hear a drone?
			for _, dronePos in dronePositions do
				if (myPos - dronePos).Magnitude <= DRONE_HEAR_RANGE then
					panic(model, state, dronePos, now)
					break
				end
			end

			local panicking = now < state.panicUntil

			-- panic is contagious: seeing a friend freak out is scary
			if panicking then
				for otherModel, otherState in states do
					if otherModel ~= model
						and now >= otherState.panicUntil
						and otherState.humanoid.Health > 0
						and (otherState.hrp.Position - myPos).Magnitude <= PANIC_SPREAD_RANGE
					then
						panic(otherModel, otherState, state.threatPos or myPos, now)
					end
				end
			end

			-- movement
			if panicking then
				scream(model, state, now)
				if now >= state.nextMove then
					state.nextMove = now + 0.8 + math.random() * 0.6
					-- sprint AWAY from the threat, zigzagging like a scared person
					local awayFrom = state.threatPos or myPos
					local away = myPos - awayFrom
					away = Vector3.new(away.X, 0, away.Z)
					away = away.Magnitude > 0.5 and away.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
					local zigzag = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 14
					state.humanoid:MoveTo(myPos + away * 30 + zigzag)
					-- sometimes dive/jump in blind panic
					if math.random() < 0.25 then
						state.humanoid.Jump = true
					end
				end
			else
				-- calm again: stroll around home
				if state.humanoid.WalkSpeed ~= WALK_SPEED then
					state.humanoid.WalkSpeed = WALK_SPEED
				end
				if now >= state.nextMove then
					state.nextMove = now + 4 + math.random() * 5
					local offset = Vector3.new(
						(math.random() - 0.5) * 2 * WANDER_RANGE,
						0,
						(math.random() - 0.5) * 2 * WANDER_RANGE
					)
					state.humanoid:MoveTo(state.home + offset)
				end
			end
		end
	end
end)
