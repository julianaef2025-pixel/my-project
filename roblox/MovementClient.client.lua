--[[
	MOVEMENT — CLIENT LocalScript (StarterPlayer > StarterPlayerScripts)
	Crouch / sprint / prone. A separate LocalScript: don't paste into others.

	On foot:
	- Left Shift (hold) : sprint
	- C (toggle)        : crouch
	- X (toggle)        : prone
	- Jump              : stand up from crouch/prone

	All keys are ignored while flying a drone (those have their own
	C/X/Shift meanings) — the character is frozen then anyway.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local stanceEvent = ReplicatedStorage:WaitForChild("StanceEvent")

local CAMERA_OFFSETS = {
	Stand = Vector3.new(0, 0, 0),
	Crouch = Vector3.new(0, -1, 0),
	Prone = Vector3.new(0, -2.2, 0),
}
local SPRINT_FOV_BOOST = 8

local stance = "Stand"
local sprinting = false
local baseFOV = 70

--------------------------------------------------------------------
-- tiny stance indicator, bottom-left
--------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "StanceHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15
gui.Parent = player:WaitForChild("PlayerGui")

local indicator = Instance.new("TextLabel")
indicator.AnchorPoint = Vector2.new(0, 1)
indicator.Position = UDim2.new(0, 16, 1, -16)
indicator.Size = UDim2.new(0, 200, 0, 22)
indicator.BackgroundTransparency = 1
indicator.Font = Enum.Font.Code
indicator.TextSize = 16
indicator.TextColor3 = Color3.fromRGB(200, 210, 200)
indicator.TextStrokeTransparency = 0.6
indicator.TextXAlignment = Enum.TextXAlignment.Left
indicator.Text = ""
indicator.Parent = gui

local function updateIndicator()
	if stance == "Crouch" then
		indicator.Text = "▼ CROUCHED"
	elseif stance == "Prone" then
		indicator.Text = "▼▼ PRONE"
	elseif sprinting then
		indicator.Text = "» SPRINTING"
	else
		indicator.Text = ""
	end
end

--------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------

local function getCharacterBits()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, hrp
end

local function onFoot()
	local _, humanoid, hrp = getCharacterBits()
	-- anchored HRP = flying a drone; dead = no
	return humanoid ~= nil and humanoid.Health > 0 and hrp ~= nil and not hrp.Anchored
end

local function sendStance()
	stanceEvent:FireServer(stance, sprinting)
	local _, humanoid = getCharacterBits()
	if humanoid then
		TweenService:Create(humanoid, TweenInfo.new(0.25), {
			CameraOffset = CAMERA_OFFSETS[stance] or Vector3.zero,
		}):Play()
	end
	-- sprint FOV kick (only when the normal camera is in charge, not a drone cam)
	if camera.CameraType == Enum.CameraType.Custom then
		local targetFOV = (sprinting and stance == "Stand") and (baseFOV + SPRINT_FOV_BOOST) or baseFOV
		TweenService:Create(camera, TweenInfo.new(0.3), { FieldOfView = targetFOV }):Play()
	end
	updateIndicator()
end

local function setStance(newStance)
	stance = newStance
	sendStance()
end

--------------------------------------------------------------------
-- input
--------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not onFoot() then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		-- sprinting stands you up
		if stance ~= "Stand" then
			stance = "Stand"
		end
		sendStance()
	elseif input.KeyCode == Enum.KeyCode.C then
		setStance(stance == "Crouch" and "Stand" or "Crouch")
	elseif input.KeyCode == Enum.KeyCode.X then
		setStance(stance == "Prone" and "Stand" or "Prone")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift and sprinting then
		sprinting = false
		if onFoot() then
			sendStance()
		else
			updateIndicator()
		end
	end
end)

-- jumping stands you up from crouch/prone
UserInputService.JumpRequest:Connect(function()
	if stance ~= "Stand" and onFoot() then
		setStance("Stand")
	end
end)

-- reset on respawn
player.CharacterAdded:Connect(function()
	stance = "Stand"
	sprinting = false
	task.wait(0.5)
	if onFoot() then
		sendStance()
	end
	updateIndicator()
end)
