--[[
	MAIN MENU — SERVER script (ServerScriptService)
	A separate script: don't paste into the drone or NPC scripts.

	Studio setup:
	1. Place two SpawnLocations in the map: name one "BlueSpawn" and the
	   other "RedSpawn" (any name containing blue/red works).
	2. In ServerStorage create a Folder named "DroneTemplates" and put a
	   COPY of each drone model inside it:
	   - your kamikaze drone (any name WITHOUT "Bomber" in it)
	   - your bomber drone (name must contain "Bomber")
	3. Keep the Workspace "Drones" folder — chosen drones spawn into it,
	   so the drone system sets them up automatically.
]]

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DRONE_COOLDOWN = 5 -- seconds between drone requests per player

-- teams -------------------------------------------------------------
local function ensureTeam(name, brickColorName)
	local team = Teams:FindFirstChild(name)
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.TeamColor = BrickColor.new(brickColorName)
		team.AutoAssignable = false
		team.Parent = Teams
	end
	return team
end

local blueTeam = ensureTeam("Blue", "Bright blue")
local redTeam = ensureTeam("Red", "Bright red")

-- bind spawn points: any SpawnLocation with "blue"/"red" in its name
local foundBlue, foundRed = false, false
for _, descendant in workspace:GetDescendants() do
	if descendant:IsA("SpawnLocation") then
		local name = descendant.Name:lower()
		if name:find("blue") then
			descendant.TeamColor = blueTeam.TeamColor
			descendant.Neutral = false
			descendant.AllowTeamChangeOnTouch = false
			foundBlue = true
		elseif name:find("red") then
			descendant.TeamColor = redTeam.TeamColor
			descendant.Neutral = false
			descendant.AllowTeamChangeOnTouch = false
			foundRed = true
		end
	end
end
if not foundBlue then
	warn("[MainMenu] No SpawnLocation with 'Blue' in its name found — add one called BlueSpawn")
end
if not foundRed then
	warn("[MainMenu] No SpawnLocation with 'Red' in its name found — add one called RedSpawn")
end

-- remotes ------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "MenuRemotes"
remotes.Parent = ReplicatedStorage

local teamSelect = Instance.new("RemoteEvent")
teamSelect.Name = "TeamSelect"
teamSelect.Parent = remotes

local droneSelect = Instance.new("RemoteEvent")
droneSelect.Name = "DroneSelect"
droneSelect.Parent = remotes

-- team picking -------------------------------------------------------
teamSelect.OnServerEvent:Connect(function(player, teamName)
	local team
	if teamName == "Blue" then
		team = blueTeam
	elseif teamName == "Red" then
		team = redTeam
	else
		return
	end
	player.Team = team
	player.Neutral = false
	-- respawn at the team's checkpoint
	task.defer(function()
		player:LoadCharacter()
	end)
end)

-- drone delivery -----------------------------------------------------
local templatesFolder = ServerStorage:FindFirstChild("DroneTemplates")
if not templatesFolder then
	warn("[MainMenu] ServerStorage has no 'DroneTemplates' folder — create it and put your drone models inside")
end

local personalDrones = {} -- [player] = their delivered drone model
local lastDroneRequest = {} -- [player] = os.clock() of last delivery

local function matchesKind(model, kind)
	local name = model.Name:lower()
	if kind == "Bomber" then
		return name:find("bomber") ~= nil
	elseif kind == "Recon" then
		return name:find("recon") ~= nil
	elseif kind == "RPG" then
		return name:find("rpg") ~= nil or name:find("rocket") ~= nil
	end
	-- Kamikaze = any drone that isn't one of the special kinds
	return not name:find("bomber") and not name:find("recon")
		and not name:find("rpg") and not name:find("rocket")
end

local function findTemplate(kind)
	if not templatesFolder then
		return nil
	end
	for _, model in templatesFolder:GetChildren() do
		if model:IsA("Model") and matchesKind(model, kind) then
			return model
		end
	end
	return nil
end

-- level requirements (buyable early with Robux via the unlock system)
local LEVEL_REQUIREMENTS = { Kamikaze = 2, Recon = 4, Bomber = 7, RPG = 9 }

droneSelect.OnServerEvent:Connect(function(player, kind)
	if kind ~= "Bomber" and kind ~= "Kamikaze" and kind ~= "Recon" and kind ~= "RPG" then
		return
	end
	-- locked? need the level OR a Robux unlock
	local required = LEVEL_REQUIREMENTS[kind] or 1
	local level = player:GetAttribute("Level") or 1
	local owned = player:GetAttribute("Owns" .. kind) == true
	if level < required and not owned then
		return
	end
	local now = os.clock()
	if lastDroneRequest[player] and now - lastDroneRequest[player] < DRONE_COOLDOWN then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local template = findTemplate(kind)
	if not template then
		warn("[MainMenu] No '" .. kind .. "' drone template found in ServerStorage.DroneTemplates")
		return
	end

	local dronesFolder = workspace:FindFirstChild("Drones")
	if not dronesFolder then
		dronesFolder = Instance.new("Folder")
		dronesFolder.Name = "Drones"
		dronesFolder.Parent = workspace
	end

	-- take back their previous drone if it's still parked and unused
	local old = personalDrones[player]
	if old and old.Parent and not old:GetAttribute("PilotUserId") and not old:GetAttribute("Dead") then
		old:Destroy()
	end

	lastDroneRequest[player] = now

	-- deliver the drone just in front of the player
	local drone = template:Clone()
	drone:SetAttribute("OwnerUserId", player.UserId) -- for friendly markers
	drone:PivotTo(hrp.CFrame * CFrame.new(0, 1, -7))
	drone.Parent = dronesFolder -- the drone system's ChildAdded sets it up
	personalDrones[player] = drone
end)

Players.PlayerRemoving:Connect(function(player)
	lastDroneRequest[player] = nil
	local drone = personalDrones[player]
	personalDrones[player] = nil
	-- clean up their parked, unused drone when they leave
	if drone and drone.Parent and not drone:GetAttribute("PilotUserId") and not drone:GetAttribute("Dead") then
		drone:Destroy()
	end
end)
