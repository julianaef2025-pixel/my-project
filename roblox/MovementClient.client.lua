--[[
	MOVEMENT — CLIENT LocalScript (StarterPlayer > StarterPlayerScripts)
	v2, animation-based. Crouch / sprint / prone.

	SETUP: paste your two animation IDs below! Make them with the
	Animation Editor (Avatar tab), set Priority = Action + Looping ON,
	publish, and copy the numbers into CROUCH_ANIM_ID / PRONE_ANIM_ID.

	On foot:
	- Left Shift (hold) : sprint
	- C (toggle)        : crouch
	- X (toggle)        : prone
	- Jump              : stand up from crouch/prone
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- ▼▼▼ PASTE YOUR ANIMATION IDS HERE ▼▼▼
local CROUCH_ANIM_ID = 0 -- e.g. 123456789012345
local PRONE_ANIM_ID = 0 -- e.g. 123456789012345
-- ▲▲▲ PASTE YOUR ANIMATION IDS HERE ▲▲▲

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local stanceEvent = ReplicatedStorage:WaitForChild("StanceEvent")

local CAMERA_OFFSETS = {
	Stand = Vector3.new(0, 0, 0),
	Crouch = Vector3.new(0, -1, 0),
	Prone = Vector3.new(0, -2, 0),
}
local SPRINT_FOV_BOOST = 8

local stance = "Stand"
local sprinting = false
local baseFOV = 70

if CROUCH_ANIM_ID == 0 or PRONE_ANIM_ID == 0 then
	warn("[Movement] Animation IDs not set! Open the Movement LocalScript and paste your CrouchIdle / ProneIdle animation IDs at the top.")
end

--------------------------------------------------------------------
-- animation tracks (playing them on your own character replicates
-- to every other player automatically)
--------------------------------------------------------------------

local tracks = {} -- Crouch / Prone -> AnimationTrack

local function loadTracks(character)
	tracks = {}
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

	local function load(name, id)
		if id == 0 then
			return
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			tracks[name] = track
		else
			warn("[Movement] Could not load " .. name .. " animation — is the ID right and owned by you?")
		end
	end

	load("Crouch", CROUCH_ANIM_ID)
	load("Prone", PRONE_ANIM_ID)
end

local function playStanceAnimation()
	for name, track in tracks do
		if name == stance then
			if not track.IsPlaying then
				track:Play(0.2)
			end
		else
			track:Stop(0.2)
		end
	end
end

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
-- stance switching
--------------------------------------------------------------------

local function getCharacterBits()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, hrp
end

local function onFoot()
	local _, humanoid, hrp = getCharacterBits()
	return humanoid ~= nil and humanoid.Health > 0 and hrp ~= nil and not hrp.Anchored
end

local function sendStance()
	stanceEvent:FireServer(stance, sprinting)
	playStanceAnimation()

	local _, humanoid = getCharacterBits()
	if humanoid then
		TweenService:Create(humanoid, TweenInfo.new(0.25), {
			CameraOffset = CAMERA_OFFSETS[stance] or Vector3.zero,
		}):Play()
	end
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

-- load animations for each new character, reset stance on respawn
player.CharacterAdded:Connect(function(character)
	stance = "Stand"
	sprinting = false
	loadTracks(character)
	updateIndicator()
end)
if player.Character then
	loadTracks(player.Character)
end
