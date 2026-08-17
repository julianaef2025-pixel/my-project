--[[
	OWNER JOIN ANNOUNCEMENT — Script (ServerScriptService)
	A separate script: don't paste into the others.

	When the game's owner (you) joins, everyone gets a golden banner
	sliding in at the top of their screen: "OWNER HAS JOINED THE GAME".
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- friends/co-owners who should ALSO trigger the banner (exact usernames)
local EXTRA_VIPS = {
	-- "SomeUsername",
}

local BANNER_TIME = 4 -- seconds the banner stays up

local function isOwner(player)
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group
		and player:GetRankInGroup(game.CreatorId) == 255 then
		return true
	end
	return table.find(EXTRA_VIPS, player.Name) ~= nil
end

local function showBanner(toPlayer, ownerName)
	local playerGui = toPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OwnerBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = playerGui

	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -70) -- starts hidden above the screen
	banner.Size = UDim2.new(0, 520, 0, 52)
	banner.BackgroundColor3 = Color3.fromRGB(24, 20, 8)
	banner.BorderSizePixel = 0
	banner.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 60)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = banner

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(45, 36, 12), Color3.fromRGB(20, 16, 6))
	gradient.Rotation = 90
	gradient.Parent = banner

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -20, 1, 0)
	text.Position = UDim2.new(0.5, 0, 0.5, 0)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 20
	text.TextColor3 = Color3.fromRGB(255, 210, 90)
	text.TextStrokeTransparency = 0.7
	text.Text = "👑  THE OWNER " .. ownerName:upper() .. " HAS JOINED THE GAME  👑"
	text.TextScaled = true
	text.Parent = banner
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 20
	textConstraint.Parent = text

	-- little ping so people look up
	local ping = Instance.new("Sound")
	ping.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	ping.Volume = 0.5
	ping.Parent = gui
	ping:Play()

	-- slide in, wait, slide back out
	TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 14),
	}):Play()
	task.delay(BANNER_TIME, function()
		local out = TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -70),
		})
		out.Completed:Once(function()
			gui:Destroy()
		end)
		out:Play()
	end)
end

Players.PlayerAdded:Connect(function(player)
	local ok, owner = pcall(isOwner, player)
	if not ok or not owner then
		return
	end
	-- give their client a second to load, then tell EVERYONE (including them)
	task.wait(1)
	for _, somebody in Players:GetPlayers() do
		task.spawn(showBanner, somebody, player.DisplayName)
	end
end)

print("[OwnerAnnounce] ready")
