--[[
	GROUP CHAT TAGS — LocalScript (StarterPlayer > StarterPlayerScripts)
	A separate LocalScript: don't paste into the others.

	Puts the player's group role in front of their chat messages:
	[DEVELOPMENT TEAM] julia: hi
	Works together with the GroupTags server script (which figures out
	everyone's role and stores it on the player).
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local function colorHexForRole(roleName)
	local lower = roleName:lower()
	if lower:find("owner") then
		return "#FFC83C"
	elseif lower:find("develop") or lower:find("admin") then
		return "#FF5A5A"
	elseif lower:find("member") then
		return "#6EDC82"
	end
	return "#BEC3C8"
end

TextChatService.OnIncomingMessage = function(message)
	local source = message.TextSource
	if not source then
		return
	end
	local player = Players:GetPlayerByUserId(source.UserId)
	if not player then
		return
	end
	local roleName = player:GetAttribute("GroupRole")
	if not roleName then
		return
	end
	local properties = Instance.new("TextChatMessageProperties")
	properties.PrefixText = '<font color="' .. colorHexForRole(roleName) .. '">['
		.. roleName:upper() .. ']</font> ' .. message.PrefixText
	return properties
end
