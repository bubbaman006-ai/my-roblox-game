--!strict
-- Builds the play area. If you've built your own map in Studio, add
-- Workspace.Map.Waypoints with parts named 1, 2, 3... and this module uses their positions
-- instead of the default path. Ground height is taken from Workspace.Map.Ground when it exists.

local Path = require(game:GetService("ReplicatedStorage").Shared.Path)
local Placement = require(game:GetService("ReplicatedStorage").Shared.Placement)

local Map = {}

local DEFAULT_POINTS = {
	Vector3.new(-55, 0, -50),
	Vector3.new(-55, 0, 20),
	Vector3.new(-20, 0, 20),
	Vector3.new(-20, 0, -30),
	Vector3.new(20, 0, -30),
	Vector3.new(20, 0, 40),
	Vector3.new(55, 0, 40),
}
local DEFAULT_SIZE = 130

local function makePart(props: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function readCustomWaypoints(mapFolder: Instance): { Vector3 }?
	local waypoints = mapFolder:FindFirstChild("Waypoints")
	if not waypoints then
		return nil
	end
	local points = {}
	local index = 1
	while true do
		local part = waypoints:FindFirstChild(tostring(index))
		if not (part and part:IsA("BasePart")) then
			break
		end
		points[index] = part.Position
		index += 1
	end
	return if #points >= 2 then points else nil
end

local function buildDefault(mapFolder: Folder)
	makePart({
		Name = "Ground",
		Size = Vector3.new(DEFAULT_SIZE, 1, DEFAULT_SIZE),
		Position = Vector3.new(0, -0.5, 0),
		Color = Color3.fromRGB(90, 140, 70),
		Material = Enum.Material.Grass,
	}, mapFolder)

	local waypoints = Instance.new("Folder")
	waypoints.Name = "Waypoints"
	waypoints.Parent = mapFolder
	for i, point in DEFAULT_POINTS do
		makePart({
			Name = tostring(i),
			Size = Vector3.new(1, 1, 1),
			Position = point,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		}, waypoints)
		-- Visible road: one slab per segment, plus a pad on each corner so joints look clean.
		if i > 1 then
			local a, b = DEFAULT_POINTS[i - 1], point
			local length = (b - a).Magnitude
			makePart({
				Name = "Road",
				Size = Vector3.new(8, 0.2, length + 8),
				CFrame = CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, 0.1, 0),
				Color = Color3.fromRGB(170, 140, 100),
				Material = Enum.Material.Ground,
				CanCollide = false,
			}, mapFolder)
		end
	end

	local finish = DEFAULT_POINTS[#DEFAULT_POINTS]
	makePart({
		Name = "Base",
		Size = Vector3.new(8, 6, 8),
		Position = finish + Vector3.new(0, 3, 0),
		Color = Color3.fromRGB(60, 90, 200),
		Material = Enum.Material.SmoothPlastic,
	}, mapFolder)
	local start = DEFAULT_POINTS[1]
	makePart({
		Name = "Spawn",
		Size = Vector3.new(8, 0.4, 8),
		Position = start + Vector3.new(0, 0.2, 0),
		Color = Color3.fromRGB(200, 60, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, mapFolder)
end

export type MapInfo = {
	path: Path.Path,
	bounds: Placement.Bounds,
	groundY: number, -- top surface of the ground
	enemiesFolder: Folder,
	towersFolder: Folder,
}

function Map.load(): MapInfo
	local mapFolder = workspace:FindFirstChild("Map")
	if not mapFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = workspace
		buildDefault(folder)
		mapFolder = folder
	end
	assert(mapFolder, "Map folder missing")

	local points = readCustomWaypoints(mapFolder) or DEFAULT_POINTS

	local ground = mapFolder:FindFirstChild("Ground")
	local groundY = 0
	local bounds: Placement.Bounds
	if ground and ground:IsA("BasePart") then
		groundY = ground.Position.Y + ground.Size.Y / 2
		local half = ground.Size / 2
		bounds = { min = ground.Position - half, max = ground.Position + half }
	else
		local half = DEFAULT_SIZE / 2
		bounds = { min = Vector3.new(-half, 0, -half), max = Vector3.new(half, 0, half) }
	end

	-- Path points are flattened onto the ground so enemies and range checks agree.
	local flat = table.create(#points)
	for i, p in points do
		flat[i] = Vector3.new(p.X, groundY, p.Z)
	end

	-- Shared copies so the client can draw the same placement check.
	local shared = Instance.new("Folder")
	shared.Name = "MapInfo"
	for i, p in flat do
		local value = Instance.new("Vector3Value")
		value.Name = tostring(i)
		value.Value = p
		value.Parent = shared
	end
	shared:SetAttribute("BoundsMin", bounds.min)
	shared:SetAttribute("BoundsMax", bounds.max)
	shared:SetAttribute("GroundY", groundY)
	shared.Parent = game:GetService("ReplicatedStorage")

	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
		return f
	end

	return {
		path = Path.new(flat),
		bounds = bounds,
		groundY = groundY,
		enemiesFolder = folder("Enemies"),
		towersFolder = folder("Towers"),
	}
end

return Map
