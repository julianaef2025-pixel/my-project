--[[
	MOVEMENT — SERVER script (ServerScriptService)   v2, animation-based
	Crouch / sprint / prone. A separate script: don't paste into the others.

	The server only handles SPEED and JUMPING (so exploiters can't
	speed-hack). The poses themselves are real animations played by
	the client — animations on your own character replicate to
	everyone automatically.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STANCES = {
	Stand = { speed = 16, canJump = true },
	Crouch = { speed = 8, canJump = false },
	Prone = { speed = 3.5, canJump = false },
}
local SPRINT_SPEED = 24 -- Left Shift while standing

local stanceEvent = Instance.new("RemoteEvent")
stanceEvent.Name = "StanceEvent"
stanceEvent.Parent = ReplicatedStorage

print("[Movement] server ready")

stanceEvent.OnServerEvent:Connect(function(player, stanceName, sprinting)
	local stance = STANCES[stanceName]
	if not stance then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not hrp then
		return
	end
	-- ignore while flying a drone (the character is frozen then)
	if hrp.Anchored then
		return
	end

	local speed = stance.speed
	if sprinting == true and stanceName == "Stand" then
		speed = SPRINT_SPEED
	end
	humanoid.WalkSpeed = speed
	pcall(function()
		humanoid.UseJumpPower = true
		humanoid.JumpPower = stance.canJump and 50 or 0
	end)

	character:SetAttribute("Stance", stanceName)
end)

-- fresh characters start standing
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:SetAttribute("Stance", "Stand")
	end)
end)
