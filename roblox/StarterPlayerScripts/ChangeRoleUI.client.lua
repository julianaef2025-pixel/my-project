-- LocalScript named "ChangeRoleUI" in StarterPlayer > StarterPlayerScripts
-- Builds the whole UI in code, so there is nothing to design by hand.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MarineConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Theme: dark red + gold
local GOLD = Color3.fromRGB(255, 190, 30)
local RED_DARK = Color3.fromRGB(58, 6, 12)
local RED_MID = Color3.fromRGB(122, 10, 22)
local RED_LIGHT = Color3.fromRGB(160, 20, 32)
local WHITE = Color3.new(1, 1, 1)

local ITALIC = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function redGradient()
	return new("UIGradient", {
		Color = ColorSequence.new(RED_MID, RED_DARK),
		Rotation = 90,
	})
end

local screen = new("ScreenGui", {
	Name = "ChangeRoleGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Top-right "Change Role" button
local openButton = new("TextButton", {
	Name = "ChangeRoleButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 10),
	Size = UDim2.fromOffset(150, 40),
	BackgroundColor3 = RED_MID,
	Text = "Change Role",
	TextColor3 = WHITE,
	FontFace = ITALIC,
	TextSize = 18,
	AutoButtonColor = false,
	Parent = screen,
}, { redGradient(), stroke(GOLD, 2) })

-- Main panel
local panel = new("Frame", {
	Name = "RolePanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromScale(0.62, 0.62),
	BackgroundColor3 = RED_MID,
	Visible = false,
	Parent = screen,
}, {
	redGradient(),
	corner(10),
	stroke(GOLD, 4),
	new("UISizeConstraint", { MinSize = Vector2.new(340, 280), MaxSize = Vector2.new(1000, 560) }),
})

-- Inner gold line
new("Frame", {
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(1, -20, 1, -20),
	BackgroundTransparency = 1,
	Parent = panel,
}, { corner(6), stroke(GOLD, 2) })

-- Header tab
new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0.45, 0, 0, 52),
	BackgroundColor3 = RED_DARK,
	ZIndex = 3,
	Parent = panel,
}, {
	corner(8),
	stroke(GOLD, 3),
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "Role Select",
		TextColor3 = WHITE,
		Font = Enum.Font.Michroma,
		TextScaled = true,
		ZIndex = 4,
	}, { new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
	}) }),
})

-- Red X (top-right corner of the panel)
local closeButton = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = Color3.fromRGB(210, 20, 20),
	Text = "X",
	TextColor3 = WHITE,
	Font = Enum.Font.GothamBlack,
	TextSize = 30,
	ZIndex = 5,
	Parent = panel,
}, { stroke(Color3.fromRGB(120, 0, 0), 3) })

-- Horizontal scrolling row of cards
local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(22, 52),
	Size = UDim2.new(1, -44, 1, -74),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = Color3.fromRGB(230, 120, 130),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	Parent = panel,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
	new("UIPadding", { PaddingBottom = UDim.new(0, 16), PaddingTop = UDim.new(0, 4) }),
})

local function setOpen(open)
	panel.Visible = open
end

openButton.Activated:Connect(function()
	setOpen(not panel.Visible)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

-- Cards
local busy = false

local function makeCard(unit, order)
	local cardStroke = stroke(GOLD, 1.5)

	local emblem
	if unit.BadgeImage then
		emblem = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.66),
			Size = UDim2.fromScale(0.78, 0.78),
			BackgroundTransparency = 1,
			Image = unit.BadgeImage,
			ScaleType = Enum.ScaleType.Fit,
		}, { new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	else
		-- No image yet: show a big symbol in a ring
		emblem = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.66),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundColor3 = RED_DARK,
		}, {
			new("UIAspectRatioConstraint", { AspectRatio = 1 }),
			corner(999),
			stroke(unit.Color, 4),
			new("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = unit.Badge,
				TextColor3 = unit.Color,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
			}, { new("UIPadding", {
				PaddingTop = UDim.new(0.2, 0),
				PaddingBottom = UDim.new(0.2, 0),
				PaddingLeft = UDim.new(0.2, 0),
				PaddingRight = UDim.new(0.2, 0),
			}) }),
		})
	end

	local card = new("TextButton", {
		Name = unit.Id,
		LayoutOrder = order,
		Size = UDim2.new(0, 210, 1, 0),
		BackgroundColor3 = RED_MID,
		Text = "",
		AutoButtonColor = false,
		Parent = list,
	}, {
		redGradient(),
		corner(6),
		cardStroke,
		-- Title strip
		new("Frame", {
			Size = UDim2.new(1, 0, 0, 78),
			BackgroundColor3 = RED_DARK,
			BackgroundTransparency = 0.35,
		}, {
			corner(6),
			stroke(GOLD, 1.5),
			new("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = unit.Name,
				TextColor3 = WHITE,
				Font = Enum.Font.Michroma,
				TextScaled = true,
				TextWrapped = true,
			}, {
				new("UIPadding", {
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 8 }),
			}),
		}),
		emblem,
	})

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = RED_LIGHT }):Play()
		cardStroke.Color = WHITE
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = RED_MID }):Play()
		cardStroke.Color = GOLD
	end)

	card.Activated:Connect(function()
		if busy then
			return
		end
		local remote = ReplicatedStorage:WaitForChild("ChangeRole", 5)
		if not remote then
			warn("ChangeRole RemoteEvent not found - is the RoleServer script in ServerScriptService and running?")
			return
		end
		busy = true
		remote:FireServer(unit.Id)
		setOpen(false)
		task.delay(Config.Cooldown, function()
			busy = false
		end)
	end)
end

for i, unit in ipairs(Config.Units) do
	makeCard(unit, i)
end
