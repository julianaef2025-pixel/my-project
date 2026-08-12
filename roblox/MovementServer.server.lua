--[[
	MOVEMENT — SERVER script (ServerScriptService)
	Crouch / sprint / prone. A separate script: don't paste into the others.

	The client sends stance requests; the server validates and applies
	them (WalkSpeed, hip height, body tilt) so every player SEES the
	crouch/prone pose, not just the one doing it.

	Works with both R15 and R6 characters.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- stance tuning
local STANCES = {
	Stand = { speed = 16, tilt = 0, hipDelta = 0, canJump = true },
	Crouch = { speed = 8, tilt = -25, hipDelta = -1, canJump = false },
	Prone = { speed = 3.5, tilt = -85, hipDelta = -1.9, canJump = false },
}
local SPRINT_SPEED = 24 -- Left Shift while standing
local TRANSITION = 0.25 -- seconds to blend between poses

local stanceEvent = Instance.new("RemoteEvent")
stanceEvent.Name = "StanceEvent"
stanceEvent.Parent = ReplicatedStorage

-- per-character originals so we can restore them exactly
local originals = {} -- [character] = { hip = n, c0 = CFrame, joint = Motor6D }

local function getRootJoint(character)
	-- R6: Motor6D "RootJoint" inside the HumanoidRootPart
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local r6 = hrp and hrp:FindFirstChild("RootJoint")
	if r6 and r6:IsA("Motor6D") then
		return r6
	end
	-- R15: Motor6D "Root" inside the LowerTorso
	local lower = character:FindFirstChild("LowerTorso")
	local r15 = lower and lower:FindFirstChild("Root")
	if r15 and r15:IsA("Motor6D") then
		return r15
	end
	return nil
end

local function rememberOriginals(character, humanoid)
	if originals[character] then
		return originals[character]
	end
	local joint = getRootJoint(character)
	if not joint then
		return nil
	end
	originals[character] = {
		hip = humanoid.HipHeight,
		c0 = joint.C0,
		joint = joint,
	}
	return originals[character]
end

local function applyStance(character, stanceName, sprinting)
	local stance = STANCES[stanceName]
	if not stance then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not hrp then
		return
	end
	-- ignore while flying a drone (the character is frozen then)
	if hrp.Anchored then
		return
	end
	local orig = rememberOriginals(character, humanoid)
	if not orig or not orig.joint.Parent then
		return
	end

	-- speed & jumping
	local speed = stance.speed
	if sprinting and stanceName == "Stand" then
		speed = SPRINT_SPEED
	end
	humanoid.WalkSpeed = speed
	pcall(function()
		humanoid.UseJumpPower = true
		humanoid.JumpPower = stance.canJump and 50 or 0
	end)

	-- pose: tilt the whole body via the root joint, sink the hips
	humanoid.HipHeight = orig.hip + stance.hipDelta
	TweenService:Create(orig.joint, TweenInfo.new(TRANSITION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = orig.c0 * CFrame.Angles(math.rad(stance.tilt), 0, 0),
	}):Play()

	character:SetAttribute("Stance", stanceName)
end

stanceEvent.OnServerEvent:Connect(function(player, stanceName, sprinting)
	if typeof(stanceName) ~= "string" or not STANCES[stanceName] then
		return
	end
	local character = player.Character
	if character then
		applyStance(character, stanceName, sprinting == true)
	end
end)

-- fresh characters start standing; clean up our memory of old ones
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:SetAttribute("Stance", "Stand")
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				originals[character] = nil
			end
		end)
	end)
end)
