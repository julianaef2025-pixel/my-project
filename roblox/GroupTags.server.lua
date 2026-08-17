--[[
	GROUP TAGS — Script (ServerScriptService)
	A separate script: don't paste into the others.

	Shows every player's group role as a floating tag over their head:
	OWNER (gold), your dev roles (red), members (green).

	SETUP: paste your group's ID below (the number from the group's
	web address, e.g. roblox.com/communities/12345678/... -> 12345678)
]]

local Players = game:GetService("Players")

-- ▼▼▼ PASTE YOUR GROUP ID HERE ▼▼▼
local GROUP_ID = 0
-- ▲▲▲ PASTE YOUR GROUP ID HERE ▲▲▲

-- role name (lowercase, part of it is enough) -> tag color
local ROLE_COLORS = {
	{ match = "owner", color = Color3.fromRGB(255, 200, 60) },
	{ match = "develop", color = Color3.fromRGB(255, 90, 90) },
	{ match = "admin", color = Color3.fromRGB(255, 90, 90) },
	{ match = "member", color = Color3.fromRGB(110, 220, 130) },
}
local DEFAULT_COLOR = Color3.fromRGB(190, 195, 200)

local function colorForRole(roleName)
	local lower = roleName:lower()
	for _, entry in ROLE_COLORS do
		if lower:find(entry.match) then
			return entry.color
		end
	end
	return DEFAULT_COLOR
end

local function getRole(player)
	if GROUP_ID == 0 then
		warn("[GroupTags] GROUP_ID not set — paste your group's ID at the top of the script")
		return nil
	end
	local ok, role = pcall(function()
		if player:IsInGroup(GROUP_ID) then
			return player:GetRoleInGroup(GROUP_ID)
		end
		return nil
	end)
	if ok then
		return role
	end
	return nil
end

local function tagCharacter(player, character, roleName)
	local head = character:WaitForChild("Head", 10)
	if not head or head:FindFirstChild("GroupTag") then
		return
	end

	local tag = Instance.new("BillboardGui")
	tag.Name = "GroupTag"
	tag.Size = UDim2.new(0, 130, 0, 22)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.AlwaysOnTop = false
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

local function setupPlayer(player)
	local roleName = getRole(player)
	if not roleName then
		return -- not in the group: no tag
	end
	-- store it so the chat-tag client script can read it too
	player:SetAttribute("GroupRole", roleName)

	if player.Character then
		task.spawn(tagCharacter, player, player.Character, roleName)
	end
	player.CharacterAdded:Connect(function(character)
		tagCharacter(player, character, roleName)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

print("[GroupTags] ready")
