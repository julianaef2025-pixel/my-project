--[[
	XP SYSTEM — Script (ServerScriptService)
	A separate script: don't paste into the others.

	Earns XP for: drone kills (players + NPCs), killing marked targets,
	recon mark assists, multi-kills, capturing points, defending points,
	building demolition, completed bomber sorties (empty -> rearmed full),
	and the first flight of the day.

	Other scripts report events by firing ServerStorage.XPSignal with
	(userId, eventType) — the small hook edits in the drone/capture
	scripts do exactly that.

	XP saves with DataStore: the game must be PUBLISHED and have
	"Enable Studio Access to API Services" turned on in Game Settings >
	Security for saving to work in Studio tests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")

-- how much each event is worth
local XP_VALUES = {
	kill = 25, -- killed a player with a drone
	npc_kill = 8, -- NPCs are worth less
	marked_kill_bonus = 10, -- extra for killing a recon-marked target
	mark_assist = 15, -- YOUR mark got killed by a teammate
	multikill_bonus = 15, -- 2+ kills from one blast
	capture = 30, -- captured an objective
	defend = 5, -- actively defending your point (rate limited)
	demolition = 3, -- blew a hole in something (rate limited)
	sortie = 20, -- bomber: used all grenades, returned, fully rearmed
	daily = 50, -- first flight of the day
}

-- per-player cooldowns so nothing is farmable (seconds)
local XP_COOLDOWNS = {
	demolition = 4,
	defend = 6,
}

local REASON_LABELS = {
	kill = "DRONE KILL",
	npc_kill = "KILL",
	marked_kill_bonus = "MARKED TARGET",
	mark_assist = "MARK ASSIST",
	multikill_bonus = "MULTI KILL",
	capture = "OBJECTIVE CAPTURED",
	defend = "DEFENDING",
	demolition = "DEMOLITION",
	sortie = "SORTIE COMPLETE",
	daily = "FIRST FLIGHT OF THE DAY",
}

-- XP needed to go from a level to the next one
local function xpForLevel(level)
	return 100 + (level - 1) * 75
end

-- total xp -> level + progress into that level
local function levelFromXP(totalXP)
	local level = 1
	local remaining = totalXP
	while remaining >= xpForLevel(level) do
		remaining -= xpForLevel(level)
		level += 1
	end
	return level, remaining, xpForLevel(level)
end

--------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------

local xpSignal = Instance.new("BindableEvent")
xpSignal.Name = "XPSignal"
xpSignal.Parent = ServerStorage

local xpUpdate = Instance.new("RemoteEvent")
xpUpdate.Name = "XPUpdate"
xpUpdate.Parent = ReplicatedStorage

local xpStore
pcall(function()
	xpStore = DataStoreService:GetDataStore("DroneWarXP_v1")
end)

local data = {} -- [player] = { xp = n, lastDaily = "yyyy-mm-dd" }
local cooldowns = {} -- [player] = { [eventType] = lastTime }
local recentKills = {} -- [userId] = { time, time, ... } for multi-kill detection

local function sendUpdate(player, gained, reasonLabel, leveledUp)
	local d = data[player]
	if not d then
		return
	end
	local level, intoLevel, needed = levelFromXP(d.xp)
	player:SetAttribute("Level", level) -- other systems (drone unlocks) read this
	xpUpdate:FireClient(player, d.xp, level, intoLevel, needed, gained or 0, reasonLabel, leveledUp or false)
end

local function award(userId, eventType)
	local player = Players:GetPlayerByUserId(userId)
	if not player or not data[player] then
		return
	end
	local amount = XP_VALUES[eventType]
	if not amount then
		return
	end

	-- cooldown so demolition/defend can't be farmed
	local cd = XP_COOLDOWNS[eventType]
	if cd then
		cooldowns[player] = cooldowns[player] or {}
		local last = cooldowns[player][eventType]
		local now = os.clock()
		if last and now - last < cd then
			return
		end
		cooldowns[player][eventType] = now
	end

	local before = levelFromXP(data[player].xp)
	data[player].xp += amount
	local after = levelFromXP(data[player].xp)

	sendUpdate(player, amount, REASON_LABELS[eventType] or eventType:upper(), after > before)
end

xpSignal.Event:Connect(function(userId, eventType)
	if typeof(userId) == "number" and typeof(eventType) == "string" then
		award(userId, eventType)
	end
end)

--------------------------------------------------------------------
-- kill detection: humanoids tagged by damageInBlast when they die
--------------------------------------------------------------------

local KILL_CREDIT_WINDOW = 6 -- seconds after the hit that a death still counts

local function onKill(killerId, victimModel, isNPC)
	-- base kill
	award(killerId, isNPC and "npc_kill" or "kill")

	-- marked-target bonus + assist for the recon pilot who marked them
	local markedBy = victimModel:GetAttribute("MarkedByUserId")
	local markedUntil = victimModel:GetAttribute("MarkedUntil")
	if markedBy and markedUntil and os.clock() < markedUntil then
		award(killerId, "marked_kill_bonus")
		if markedBy ~= killerId then
			award(markedBy, "mark_assist")
		end
	end

	-- multi-kill: 2+ kills within a heartbeat of each other
	local now = os.clock()
	recentKills[killerId] = recentKills[killerId] or {}
	table.insert(recentKills[killerId], now)
	local recent = 0
	for i = #recentKills[killerId], 1, -1 do
		if now - recentKills[killerId][i] <= 1.2 then
			recent += 1
		else
			table.remove(recentKills[killerId], i)
		end
	end
	if recent == 2 then -- fires once per burst
		award(killerId, "multikill_bonus")
	end
end

local function hookHumanoid(humanoid, model, isNPC)
	if humanoid:GetAttribute("XPHooked") then
		return
	end
	humanoid:SetAttribute("XPHooked", true)
	humanoid.Died:Once(function()
		local killerId = humanoid:GetAttribute("LastHitBy")
		local hitTime = humanoid:GetAttribute("LastHitTime")
		if killerId and hitTime and os.clock() - hitTime <= KILL_CREDIT_WINDOW then
			-- no XP for blowing yourself up
			local victimPlayer = Players:GetPlayerFromCharacter(model)
			if not (victimPlayer and victimPlayer.UserId == killerId) then
				onKill(killerId, model, isNPC)
			end
		end
	end)
end

-- players
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			hookHumanoid(humanoid, character, false)
		end
	end)
end)

-- NPCs (kept hooked even as they respawn/get added)
task.spawn(function()
	while true do
		local npcs = workspace:FindFirstChild("NPCs")
		if npcs then
			for _, model in npcs:GetChildren() do
				if model:IsA("Model") then
					local humanoid = model:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						hookHumanoid(humanoid, model, true)
					end
				end
			end
		end
		task.wait(4)
	end
end)

--------------------------------------------------------------------
-- sortie + first-flight-of-the-day detection (watches drone attributes)
--------------------------------------------------------------------

local sortieEmpty = {} -- [droneModel] = true once it hit 0 grenades while piloted

task.spawn(function()
	while true do
		task.wait(1)
		local drones = workspace:FindFirstChild("Drones")
		if drones then
			for _, drone in drones:GetChildren() do
				if drone:IsA("Model") then
					local pilotId = drone:GetAttribute("PilotUserId")

					-- first flight of the day
					if pilotId then
						local pilot = Players:GetPlayerByUserId(pilotId)
						if pilot and data[pilot] then
							local today = os.date("!%Y-%m-%d")
							if data[pilot].lastDaily ~= today then
								data[pilot].lastDaily = today
								award(pilotId, "daily")
							end
						end
					end

					-- bomber sortie: 3 -> 0 -> rearmed back to full
					if drone.Name:lower():find("bomber") then
						local ammo = drone:GetAttribute("Grenades")
						if pilotId and ammo == 0 then
							sortieEmpty[drone] = true
						elseif pilotId and sortieEmpty[drone] and ammo == 3 then
							sortieEmpty[drone] = nil
							award(pilotId, "sortie")
						end
					end
				end
			end
		end
		for drone in sortieEmpty do
			if not drone.Parent then
				sortieEmpty[drone] = nil
			end
		end
	end
end)

--------------------------------------------------------------------
-- saving / loading
--------------------------------------------------------------------

local function loadPlayer(player)
	local d = { xp = 0, lastDaily = "" }
	if xpStore then
		local ok, saved = pcall(function()
			return xpStore:GetAsync("player_" .. player.UserId)
		end)
		if ok and typeof(saved) == "table" then
			d.xp = tonumber(saved.xp) or 0
			d.lastDaily = tostring(saved.lastDaily or "")
		end
	end
	data[player] = d
	sendUpdate(player, 0, nil, false)
end

local function savePlayer(player)
	local d = data[player]
	if not d or not xpStore then
		return
	end
	pcall(function()
		xpStore:SetAsync("player_" .. player.UserId, { xp = d.xp, lastDaily = d.lastDaily })
	end)
end

Players.PlayerAdded:Connect(loadPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(loadPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	savePlayer(player)
	data[player] = nil
	cooldowns[player] = nil
end)

-- autosave + save everyone on shutdown
task.spawn(function()
	while true do
		task.wait(120)
		for player in data do
			savePlayer(player)
		end
	end
end)

game:BindToClose(function()
	for player in data do
		savePlayer(player)
	end
end)
