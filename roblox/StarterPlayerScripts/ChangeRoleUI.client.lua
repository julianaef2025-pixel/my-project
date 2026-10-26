-- LocalScript named "ChangeRoleUI" in StarterPlayer > StarterPlayerScripts
-- Builds the whole UI in code, so there is nothing to design by hand.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MarineConfig"))
local remote = ReplicatedStorage:WaitForChild("ChangeRole")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DARK = Color3.fromRGB(24, 27, 24)
local CARD = Color3.fromRGB(38, 43, 38)
local ACCENT = Color3.fromRGB(120, 160, 90)

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

local screen = new("ScreenGui", {
	Name = "ChangeRoleGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Top-right button
local openButton = new("TextButton", {
	Name = "ChangeRoleButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 12),
	Size = UDim2.fromOffset(150, 42),
	BackgroundColor3 = DARK,
	Text = "Change Role",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	AutoButtonColor = false,
	Parent = screen,
}, { corner(8), stroke(ACCENT, 2) })

-- Panel
local panel = new("Frame", {
	Name = "RolePanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.6, 0.65),
	BackgroundColor3 = DARK,
	Visible = false,
	Parent = screen,
}, {
	corner(12),
	stroke(ACCENT, 2),
	new("UISizeConstraint", { MinSize = Vector2.new(320, 260), MaxSize = Vector2.new(760, 520) }),
})

new("TextLabel", {
	Size = UDim2.new(1, -70, 0, 44),
	Position = UDim2.fromOffset(16, 8),
	BackgroundTransparency = 1,
	Text = "SELECT YOUR UNIT",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

local closeButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(36, 36),
	BackgroundColor3 = Color3.fromRGB(150, 50, 50),
	Text = "X",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	Parent = panel,
}, { corner(8) })

local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 60),
	Size = UDim2.new(1, -32, 1, -76),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = panel,
}, {
	new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 96),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
})

-- Open / close
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
	local cardStroke = stroke(unit.Color, 2)
	local card = new("TextButton", {
		Name = unit.Id,
		LayoutOrder = order,
		BackgroundColor3 = CARD,
		Text = "",
		AutoButtonColor = false,
		Parent = list,
	}, {
		corner(10),
		cardStroke,
		new("Frame", {
			Name = "Badge",
			Position = UDim2.fromOffset(12, 18),
			Size = UDim2.fromOffset(58, 58),
			BackgroundColor3 = DARK,
		}, {
			corner(29),
			stroke(unit.Color, 3),
			new("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = unit.Badge,
				TextColor3 = unit.Color,
				Font = Enum.Font.GothamBold,
				TextSize = 28,
			}),
		}),
		new("TextLabel", {
			Position = UDim2.fromOffset(82, 12),
			Size = UDim2.new(1, -92, 0, 26),
			BackgroundTransparency = 1,
			Text = unit.Name,
			TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.GothamBold,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		new("TextLabel", {
			Position = UDim2.fromOffset(82, 40),
			Size = UDim2.new(1, -92, 0, 44),
			BackgroundTransparency = 1,
			Text = unit.Description,
			TextColor3 = Color3.fromRGB(180, 185, 180),
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
	})

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(55, 62, 55) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = CARD }):Play()
	end)

	card.Activated:Connect(function()
		if busy then
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
