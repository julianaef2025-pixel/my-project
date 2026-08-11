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

local npcFolder = workspace:WaitForChild("NPCs")
local states = {} -- [model] = state table

local function setupNpc(model)
	if not model:IsA("Model") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		return
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

-- hook up existing and future NPCs
for _, model in npcFolder:GetChildren() do
	setupNpc(model)
end
npcFolder.ChildAdded:Connect(function(child)
	task.wait()
	setupNpc(child)
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
