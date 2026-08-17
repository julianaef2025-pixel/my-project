--[[
	ROLE SYSTEM — Script (ServerScriptService)
	A separate script: don't paste into the others.
	(If you added the old "GroupTags" script, DELETE that one — this
	replaces it and needs no Roblox group at all.)

	YOU (the game owner) can hand out roles in-game with the Role
	Manager UI (crown button, top right — that's the RoleGiverUI
	LocalScript). Roles save FOREVER (DataStore) and show as a badge
	over the player's head + a colored chat tag.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- people besides you who may hand out roles (exact usernames)
local EXTRA_MANAGERS = {
	-- "TrustedFriend123",
}

-- the roles you can give out (add your own — the UI picks these up)
local ROLES = { "Member", "Development Team", "VIP" }

local roleStore
pcall(function()
	roleStore = DataStoreService:GetDataStore("DroneWarRoles_v1")
end)

-- remotes -------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "RoleRemotes"
remotes.Parent = ReplicatedStorage

local rolesList = Instance.new("StringValue")
rolesList.Name = "RolesList"
rolesList.Value = table.concat(ROLES, "|")
rolesList.Parent = remotes

local assignRemote = Instance.new("RemoteEvent")
assignRemote.Name = "AssignRole"
assignRemote.Parent = remotes

local resultRemote = Instance.new("RemoteEvent")
resultRemote.Name = "RoleResult"
resultRemote.Parent = remotes

-- who is allowed to give roles -----------------------------------------
local function isManager(player)
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	if table.find(EXTRA_MANAGERS, player.Name) then
		return true
	end
	-- Studio testing: you're always the boss in Studio
	if RunService:IsStudio() then
		return true
	end
	return false
end

-- tags ------------------------------------------------------------------
local function colorForRole(roleName)
	local lower = roleName:lower()
	if lower:find("develop") or lower:find("admin") then
		return Color3.fromRGB(255, 90, 90)
	elseif lower:find("vip") then
		return Color3.fromRGB(255, 200, 60)
	elseif lower:find("member") then
		return Color3.fromRGB(110, 220, 130)
	end
	return Color3.fromRGB(190, 195, 200)
end

local function tagCharacter(character, roleName)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local old = head:FindFirstChild("RoleTag")
	if old then
		old:Destroy()
	end
	if not roleName then
		return
	end

	local tag = Instance.new("BillboardGui")
	tag.Name = "RoleTag"
	tag.Size = UDim2.new(0, 130, 0, 22)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 120
	tag.Adornee = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(15, 17, 15)
	label.BackgroundTransparency = 0.35
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = colorForRole(roleName)
	label.Text = roleName:upper()
	label.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = colorForRole(roleName)
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = label

	tag.Parent = head
end

local function applyRole(player, roleName)
	player:SetAttribute("GroupRole", roleName) -- the chat-tag script reads this
	if player.Character then
		task.spawn(tagCharacter, player.Character, roleName)
	end
end

-- load + spawn handling --------------------------------------------------
local function loadRole(player)
	if isManager(player) then
		player:SetAttribute("CanManageRoles", true) -- makes the UI appear
	end
	local roleName
	if roleStore then
		pcall(function()
			roleName = roleStore:GetAsync("role_" .. player.UserId)
		end)
	end
	if typeof(roleName) == "string" then
		applyRole(player, roleName)
	end
	player.CharacterAdded:Connect(function(character)
		local current = player:GetAttribute("GroupRole")
		if current then
			tagCharacter(character, current)
		end
	end)
end

Players.PlayerAdded:Connect(loadRole)
for _, player in Players:GetPlayers() do
	task.spawn(loadRole, player)
end

-- giving / removing roles -------------------------------------------------
assignRemote.OnServerEvent:Connect(function(manager, targetName, roleName)
	if not isManager(manager) then
		return
	end
	if typeof(targetName) ~= "string" or typeof(roleName) ~= "string" then
		return
	end
	targetName = targetName:gsub("%s+", "") -- trim spaces
	if #targetName < 3 then
		resultRemote:FireClient(manager, "type a username first", false)
		return
	end
	if roleName ~= "REMOVE" and not table.find(ROLES, roleName) then
		return
	end

	-- find who they mean: online player first, otherwise ask Roblox
	local targetId, properName
	for _, p in Players:GetPlayers() do
		if p.Name:lower() == targetName:lower()
			or p.DisplayName:lower() == targetName:lower() then
			targetId = p.UserId
			properName = p.Name
			break
		end
	end
	if not targetId then
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(targetName)
		end)
		if ok and id then
			targetId = id
			properName = targetName
		end
	end
	if not targetId then
		resultRemote:FireClient(manager, "no player called '" .. targetName .. "' exists", false)
		return
	end

	-- save forever
	local saved = false
	if roleStore then
		saved = pcall(function()
			if roleName == "REMOVE" then
				roleStore:RemoveAsync("role_" .. targetId)
			else
				roleStore:SetAsync("role_" .. targetId, roleName)
			end
		end)
	end

	-- apply live if they're in the server right now
	local targetPlayer = Players:GetPlayerByUserId(targetId)
	if targetPlayer then
		applyRole(targetPlayer, roleName ~= "REMOVE" and roleName or nil)
	end

	local what = roleName == "REMOVE" and "role removed from " or (roleName .. " given to ")
	local note = saved and "" or " (⚠ not saved — enable Studio API access!)"
	resultRemote:FireClient(manager, "✔ " .. what .. properName .. note, saved)
end)

print("[RoleSystem] ready")
