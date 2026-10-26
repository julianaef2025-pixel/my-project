-- Script named "RoleServer" in ServerScriptService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MarineConfig"))

local remote = Instance.new("RemoteEvent")
remote.Name = "ChangeRole"
remote.Parent = ReplicatedStorage

local unitsById = {}
for _, unit in ipairs(Config.Units) do
	unitsById[unit.Id] = unit
end

local profiles = {} -- [Player] = { UnitId, Name, Rank }
local lastChange = {} -- [Player] = os.clock()

local function pick(list)
	return list[math.random(1, #list)]
end

local function makeProfile(unit)
	return {
		UnitId = unit.Id,
		Name = pick(Config.FirstNames) .. " " .. pick(Config.LastNames),
		Rank = pick(unit.Ranks),
	}
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function applyOverheadTag(character, profile)
	local unit = unitsById[profile.UnitId]
	local head = character:WaitForChild("Head", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not (head and humanoid and unit) then
		return
	end

	-- Replace the default Roblox name with ours
	humanoid.DisplayName = profile.Name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local old = head:FindFirstChild("MarineTag")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "MarineTag"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(230, 64)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.MaxDistance = 70
	gui.AlwaysOnTop = false
	gui.Parent = head

	-- Badge
	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(52, 52)
	badge.Position = UDim2.fromOffset(0, 6)
	badge.BackgroundColor3 = Color3.fromRGB(25, 28, 25)
	badge.Parent = gui
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", badge)
	stroke.Color = unit.Color
	stroke.Thickness = 3

	if unit.BadgeImage then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(0.7, 0.7)
		img.Position = UDim2.fromScale(0.15, 0.15)
		img.BackgroundTransparency = 1
		img.Image = unit.BadgeImage
		img.Parent = badge
	else
		local sym = label(badge, {
			Size = UDim2.fromScale(0.6, 0.6),
			Position = UDim2.fromScale(0.2, 0.2),
			Text = unit.Badge,
			TextColor3 = unit.Color,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		sym.Name = "BadgeSymbol"
	end

	-- Name + rank
	local name = label(gui, {
		Size = UDim2.fromOffset(165, 30),
		Position = UDim2.fromOffset(62, 6),
		Text = profile.Name,
		TextColor3 = Color3.new(1, 1, 1),
	})
	name.Name = "MarineName"
	local rank = label(gui, {
		Size = UDim2.fromOffset(165, 22),
		Position = UDim2.fromOffset(62, 36),
		Text = profile.Rank,
		TextColor3 = unit.Color,
		Font = Enum.Font.Gotham,
	})
	rank.Name = "MarineRank"
	for _, l in ipairs({ name, rank }) do
		local s = Instance.new("UIStroke", l)
		s.Thickness = 1.5
		s.Color = Color3.new(0, 0, 0)
	end
end

local function onCharacterAdded(player, character)
	local profile = profiles[player]
	if profile then
		applyOverheadTag(character, profile)
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	profiles[player] = nil
	lastChange[player] = nil
end)

remote.OnServerEvent:Connect(function(player, unitId)
	-- Never trust the client: validate everything
	if typeof(unitId) ~= "string" then
		return
	end
	local unit = unitsById[unitId]
	if not unit then
		return
	end

	local now = os.clock()
	if lastChange[player] and now - lastChange[player] < Config.Cooldown then
		return
	end
	lastChange[player] = now

	local oldCharacter = player.Character
	local oldCFrame = oldCharacter and oldCharacter:GetPivot()

	profiles[player] = makeProfile(unit)
	player:LoadCharacter() -- respawn; CharacterAdded applies the new name/rank/badge

	if Config.KeepPosition and oldCFrame and player.Character then
		player.Character:PivotTo(oldCFrame)
	end
end)
