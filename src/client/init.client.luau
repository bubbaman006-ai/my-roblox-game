--!strict
-- Client: HUD, tower shop, placement ghost and the upgrade/sell panel.
-- The client only asks; the server decides. Prices and checks here are just for display.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Path = require(Shared:WaitForChild("Path"))
local Placement = require(Shared:WaitForChild("Placement"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local gameState = ReplicatedStorage:WaitForChild("GameState")
local towersFolder = workspace:WaitForChild("Towers")
local enemiesFolder = workspace:WaitForChild("Enemies")

local remotes = {
	place = Net.event(Net.Names.PlaceTower),
	upgrade = Net.event(Net.Names.UpgradeTower),
	sell = Net.event(Net.Names.SellTower),
	start = Net.event(Net.Names.StartGame),
	notify = Net.event(Net.Names.Notify),
}

-- Map info shared by the server ------------------------------------------------

local mapInfo = ReplicatedStorage:WaitForChild("MapInfo")
local pathPoints: { Vector3 } = {}
do
	local index = 1
	while true do
		local value = mapInfo:FindFirstChild(tostring(index))
		if not (value and value:IsA("Vector3Value")) then
			break
		end
		pathPoints[index] = value.Value
		index += 1
	end
end
local path = Path.new(pathPoints)
local bounds = {
	min = mapInfo:GetAttribute("BoundsMin") :: Vector3,
	max = mapInfo:GetAttribute("BoundsMax") :: Vector3,
}
local groundY = mapInfo:GetAttribute("GroundY") :: number

-- UI helpers ---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "TowerDefenseHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Text = text
	l.Size = size
	l.Position = position
	l.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = l
	return l
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.Text = text
	b.Size = size
	b.Position = position
	b.Parent = parent
	corner(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.15, 0)
	pad.PaddingBottom = UDim.new(0.15, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = b
	return b
end

-- Top bar: lives, wave, cash, status --------------------------------------------

local topBar = Instance.new("Frame")
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
topBar.BackgroundTransparency = 0.3
topBar.Size = UDim2.new(0.6, 0, 0, 44)
topBar.Position = UDim2.new(0.2, 0, 0, 8)
topBar.Parent = gui
corner(topBar)

local livesLabel = label(topBar, "", UDim2.fromScale(0.22, 0.8), UDim2.fromScale(0.02, 0.1))
local waveLabel = label(topBar, "", UDim2.fromScale(0.22, 0.8), UDim2.fromScale(0.26, 0.1))
local cashLabel = label(topBar, "", UDim2.fromScale(0.22, 0.8), UDim2.fromScale(0.5, 0.1))
local statusLabel = label(topBar, "", UDim2.fromScale(0.24, 0.8), UDim2.fromScale(0.74, 0.1))
livesLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
cashLabel.TextColor3 = Color3.fromRGB(255, 220, 90)

local startButton = button(
	gui,
	"START GAME",
	Color3.fromRGB(40, 170, 80),
	UDim2.fromOffset(220, 56),
	UDim2.new(0.5, -110, 0, 64)
)

local notice = label(gui, "", UDim2.new(0.5, 0, 0, 30), UDim2.new(0.25, 0, 0, 128))
notice.TextColor3 = Color3.fromRGB(255, 200, 120)
notice.TextTransparency = 1
local noticeStroke = notice:FindFirstChildOfClass("UIStroke") :: UIStroke
noticeStroke.Transparency = 1

local function showNotice(text: string)
	notice.Text = text
	notice.TextTransparency = 0
	noticeStroke.Transparency = 0
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5)
	TweenService:Create(notice, info, { TextTransparency = 1 }):Play()
	TweenService:Create(noticeStroke, info, { Transparency = 1 }):Play()
end
remotes.notify.OnClientEvent:Connect(function(message)
	if typeof(message) == "string" then
		showNotice(message)
	end
end)

local function cash(): number
	return (player:GetAttribute("Cash") :: number?) or 0
end

local function refreshTopBar()
	livesLabel.Text = "♥ " .. tostring(gameState:GetAttribute("Lives"))
	waveLabel.Text = string.format("Wave %d/%d", gameState:GetAttribute("Wave") :: number, gameState:GetAttribute("TotalWaves") :: number)
	cashLabel.Text = "$" .. tostring(cash())
	local phase = gameState:GetAttribute("Phase") :: string
	local countdown = gameState:GetAttribute("Countdown") :: number
	if phase == "Lobby" then
		statusLabel.Text = "Build, then start"
	elseif phase == "Intermission" then
		statusLabel.Text = "Next wave " .. countdown
	elseif phase == "Wave" then
		statusLabel.Text = "Defend!"
	elseif phase == "GameOver" then
		statusLabel.Text = "Base lost · " .. countdown
	elseif phase == "Victory" then
		statusLabel.Text = "Victory! · " .. countdown
	end
	startButton.Visible = phase == "Lobby"
end

for _, attribute in { "Lives", "Wave", "Phase", "Countdown" } do
	gameState:GetAttributeChangedSignal(attribute):Connect(refreshTopBar)
end
startButton.Activated:Connect(function()
	remotes.start:FireServer()
end)

-- Tower shop -----------------------------------------------------------------------

local shop = Instance.new("Frame")
shop.BackgroundTransparency = 1
shop.Size = UDim2.new(0, 120 * #Config.TowerOrder, 0, 70)
shop.Position = UDim2.new(0.5, -60 * #Config.TowerOrder, 1, -82)
shop.Parent = gui

local shopButtons: { [string]: TextButton } = {}
local shopStrokes: { [string]: UIStroke } = {}

-- Placement ghost --------------------------------------------------------------------

local function makeRing(): Part
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.75
	return ring
end

local function placeRing(ring: Part, centre: Vector3, range: number)
	ring.Size = Vector3.new(0.15, range * 2, range * 2)
	ring.CFrame = CFrame.new(centre.X, groundY + 0.15, centre.Z) * CFrame.Angles(0, 0, math.rad(90))
end

local ghost = Instance.new("Part")
ghost.Anchored = true
ghost.CanCollide = false
ghost.CanQuery = false
ghost.CanTouch = false
ghost.Transparency = 0.5
ghost.Material = Enum.Material.ForceField
local ghostRing = makeRing()
local selectRing = makeRing()
selectRing.Color = Color3.fromRGB(255, 255, 255)

local placingKind: string? = nil
local ghostValid = false
local ghostPosition = Vector3.zero

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function raycast(ray: Ray): RaycastResult?
	local ignore: { Instance } = { ghost, ghostRing, selectRing, enemiesFolder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	raycastParams.FilterDescendantsInstances = ignore
	return workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
end

local function towerPositions(): { Vector3 }
	local list = {}
	for _, part in towersFolder:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(list, Vector3.new(part.Position.X, groundY, part.Position.Z))
		end
	end
	return list
end

local function stopPlacing()
	placingKind = nil
	ghost.Parent = nil
	ghostRing.Parent = nil
	for _, stroke in shopStrokes do
		stroke.Enabled = false
	end
end

-- Selection panel ---------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.2
panel.Size = UDim2.fromOffset(220, 150)
panel.Position = UDim2.new(1, -232, 0.5, -75)
panel.Visible = false
panel.Parent = gui
corner(panel)

local panelTitle = label(panel, "", UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 8))
local upgradeButton =
	button(panel, "", Color3.fromRGB(60, 120, 220), UDim2.new(1, -16, 0, 44), UDim2.fromOffset(8, 44))
local sellButton = button(panel, "", Color3.fromRGB(200, 70, 60), UDim2.new(1, -16, 0, 44), UDim2.fromOffset(8, 96))

local selected: BasePart? = nil
local selectedConnections: { RBXScriptConnection } = {}

local function deselect()
	selected = nil
	panel.Visible = false
	selectRing.Parent = nil
	for _, c in selectedConnections do
		c:Disconnect()
	end
	table.clear(selectedConnections)
end

local function refreshPanel()
	local part = selected
	if not part then
		return
	end
	local kind = part:GetAttribute("TowerType") :: string
	local level = part:GetAttribute("Level") :: number
	local def = Config.Towers[kind]
	if not def then
		return
	end
	panelTitle.Text = string.format("%s · Lv %d", def.displayName, level)
	local nextLevel = def.levels[level + 1]
	if nextLevel then
		upgradeButton.Text = string.format("Upgrade $%d", nextLevel.cost)
		upgradeButton.BackgroundTransparency = if cash() >= nextLevel.cost then 0 else 0.5
	else
		upgradeButton.Text = "Max level"
		upgradeButton.BackgroundTransparency = 0.5
	end
	local spent = (part:GetAttribute("Spent") :: number?) or 0
	sellButton.Text = string.format("Sell +$%d", math.floor(spent * Config.SellRefund))
	placeRing(selectRing, part.Position, (part:GetAttribute("Range") :: number?) or 0)
end

local function selectTower(part: BasePart)
	deselect()
	stopPlacing()
	selected = part
	panel.Visible = true
	selectRing.Parent = workspace
	table.insert(selectedConnections, part.AttributeChanged:Connect(refreshPanel))
	table.insert(selectedConnections, part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			deselect()
		end
	end))
	refreshPanel()
end

upgradeButton.Activated:Connect(function()
	local part = selected
	if part then
		remotes.upgrade:FireServer(part:GetAttribute("TowerId"))
	end
end)
sellButton.Activated:Connect(function()
	local part = selected
	if part then
		remotes.sell:FireServer(part:GetAttribute("TowerId"))
	end
end)

local function startPlacing(kind: string)
	deselect()
	local def = Config.Towers[kind]
	placingKind = kind
	ghost.Size = def.size
	ghostRing.Parent = workspace
	ghost.Parent = workspace
	for k, stroke in shopStrokes do
		stroke.Enabled = k == kind
	end
end

for i, kind in Config.TowerOrder do
	local def = Config.Towers[kind]
	local b = button(
		shop,
		string.format("[%d] %s\n$%d", i, def.displayName, def.levels[1].cost),
		def.color:Lerp(Color3.new(0, 0, 0), 0.35),
		UDim2.fromOffset(110, 64),
		UDim2.fromOffset((i - 1) * 120 + 5, 3)
	)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Enabled = false
	stroke.Parent = b
	shopButtons[kind] = b
	shopStrokes[kind] = stroke
	b.Activated:Connect(function()
		if placingKind == kind then
			stopPlacing()
		else
			startPlacing(kind)
		end
	end)
end

local function refreshShop()
	for kind, b in shopButtons do
		b.BackgroundTransparency = if cash() >= Config.Towers[kind].levels[1].cost then 0 else 0.5
	end
end

player:GetAttributeChangedSignal("Cash"):Connect(function()
	refreshTopBar()
	refreshShop()
	refreshPanel()
end)

-- Per-frame ghost update ---------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	local kind = placingKind
	if not kind then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local hit = raycast(camera:ViewportPointToRay(mouse.X, mouse.Y))
	if not hit then
		ghost.Transparency = 1
		ghostValid = false
		return
	end
	local def = Config.Towers[kind]
	ghostPosition = Vector3.new(hit.Position.X, groundY, hit.Position.Z)
	local ok = Placement.check(kind, ghostPosition, path, bounds, towerPositions())
	ghostValid = ok and cash() >= def.levels[1].cost
	local color = if ghostValid then Color3.fromRGB(80, 255, 120) else Color3.fromRGB(255, 70, 70)
	ghost.Transparency = 0.5
	ghost.Color = color
	ghost.Position = ghostPosition + Vector3.new(0, def.size.Y / 2, 0)
	ghostRing.Color = color
	placeRing(ghostRing, ghostPosition, def.levels[1].range)
end)

-- Clicks / taps and hotkeys -------------------------------------------------------------

local function handlePointer(screenPosition: Vector3)
	local kind = placingKind
	local hit = raycast(camera:ScreenPointToRay(screenPosition.X, screenPosition.Y))
	if kind then
		if not hit then
			return
		end
		local position = Vector3.new(hit.Position.X, groundY, hit.Position.Z)
		local ok, reason = Placement.check(kind, position, path, bounds, towerPositions())
		if not ok then
			showNotice(reason or "Can't place there")
			return
		end
		remotes.place:FireServer(kind, position)
		if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			stopPlacing()
		end
		return
	end
	local part = hit and hit.Instance
	if part and part:IsDescendantOf(towersFolder) and part:GetAttribute("OwnerId") == player.UserId then
		selectTower(part)
	else
		deselect()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
		handlePointer(input.Position)
	elseif inputType == Enum.UserInputType.MouseButton2 then
		stopPlacing()
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape then
		stopPlacing()
		deselect()
	else
		for i, kind in Config.TowerOrder do
			if input.KeyCode.Value == Enum.KeyCode.One.Value + i - 1 then
				startPlacing(kind)
			end
		end
	end
end)

refreshTopBar()
refreshShop()
