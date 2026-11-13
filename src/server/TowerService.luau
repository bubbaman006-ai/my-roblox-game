--!strict
-- Placing, upgrading, selling and firing towers. Every request from a client is
-- re-checked here: tower type, position, ownership, price and placement rules.
--
-- Each tower is a base Part (holds the attributes the client reads) with decorative
-- child parts: a body, a turret head that turns to face its target, a barrel, and one
-- glowing band per upgrade level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Placement = require(ReplicatedStorage.Shared.Placement)
local Net = require(ReplicatedStorage.Shared.Net)
local GameState = require(script.Parent.GameState)
local EnemyService = require(script.Parent.EnemyService)
local Map = require(script.Parent.Map)

local effect = Net.unreliable(Net.UnreliableNames.Effect)

type Tower = {
	id: number,
	owner: Player,
	kind: string,
	def: Config.TowerDef,
	level: number,
	spent: number,
	position: Vector3, -- on the ground, centre of the footprint
	cooldown: number,
	part: Part, -- base plinth; carries the attributes
	head: Part?, -- turret that rotates
	barrelLength: number,
}

-- Shape of each tower type's visuals.
type Look = {
	body: Enum.PartType,
	headSize: Vector3,
	barrel: Vector3, -- size of the barrel (Z = length)
}
local LOOKS: { [string]: Look } = {
	Gunner = { body = Enum.PartType.Cylinder, headSize = Vector3.new(2, 1.2, 2), barrel = Vector3.new(0.4, 0.4, 1.8) },
	Sniper = { body = Enum.PartType.Block, headSize = Vector3.new(1.4, 1, 1.6), barrel = Vector3.new(0.3, 0.3, 3.6) },
	Cannon = { body = Enum.PartType.Block, headSize = Vector3.new(2.6, 2.6, 2.6), barrel = Vector3.new(1, 1, 1.8) },
}
local DEFAULT_LOOK: Look = { body = Enum.PartType.Block, headSize = Vector3.new(2, 1, 2), barrel = Vector3.new(0.4, 0.4, 1.5) }

local TowerService = {}

local map: Map.MapInfo
local towers: { [number]: Tower } = {}
local nextId = 0

function TowerService.init(info: Map.MapInfo)
	map = info
end

local function ownedCount(player: Player): number
	local n = 0
	for _, tower in towers do
		if tower.owner == player then
			n += 1
		end
	end
	return n
end

local function positions(): { Vector3 }
	local list = {}
	for _, tower in towers do
		table.insert(list, tower.position)
	end
	return list
end

local function piece(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function build(tower: Tower)
	local base = tower.part
	for _, child in base:GetChildren() do
		if child:IsA("BasePart") then
			child:Destroy()
		end
	end

	local def = tower.def
	local look = LOOKS[tower.kind] or DEFAULT_LOOK
	local stats = def.levels[tower.level]
	local ground = tower.position
	local footprint = math.max(def.size.X, def.size.Z)
	local dark = def.color:Lerp(Color3.new(0, 0, 0), 0.5)
	local bright = def.color:Lerp(Color3.new(1, 1, 1), (tower.level - 1) * 0.15)

	-- Plinth (the logical tower part).
	base.Size = Vector3.new(footprint, 0.8, footprint)
	base.Position = ground + Vector3.new(0, 0.4, 0)
	base.Color = dark
	base.Material = Enum.Material.Slate
	base:SetAttribute("Level", tower.level)
	base:SetAttribute("Range", stats.range)
	base:SetAttribute("Spent", tower.spent)

	-- Body grows a stud per level.
	local bodyHeight = def.size.Y - 0.8 + (tower.level - 1)
	local bodyWidth = footprint * 0.7
	local bodyCentre = ground + Vector3.new(0, 0.8 + bodyHeight / 2, 0)
	if look.body == Enum.PartType.Cylinder then
		piece(base, {
			Name = "Body",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(bodyHeight, bodyWidth, bodyWidth),
			CFrame = CFrame.new(bodyCentre) * CFrame.Angles(0, 0, math.rad(90)),
			Color = bright,
		})
	else
		piece(base, { Name = "Body", Size = Vector3.new(bodyWidth, bodyHeight, bodyWidth), Position = bodyCentre, Color = bright })
	end

	-- One neon band per level.
	for i = 1, tower.level do
		piece(base, {
			Name = "Band",
			Size = Vector3.new(bodyWidth + 0.15, 0.2, bodyWidth + 0.15),
			Position = ground + Vector3.new(0, 0.8 + i * 0.6, 0),
			Color = Color3.new(1, 1, 1):Lerp(def.color, 0.4),
			Material = Enum.Material.Neon,
		})
	end

	-- Turret head + barrel. The barrel is welded and unanchored so moving the head moves both.
	local headCentre = ground + Vector3.new(0, 0.8 + bodyHeight + look.headSize.Y / 2, 0)
	local facing = if tower.head then tower.head.CFrame.LookVector else Vector3.new(0, 0, -1)
	local head = piece(base, {
		Name = "Head",
		Shape = if tower.kind == "Cannon" then Enum.PartType.Ball else Enum.PartType.Block,
		Size = look.headSize,
		CFrame = CFrame.lookAt(headCentre, headCentre + facing),
		Color = dark:Lerp(bright, 0.5),
	})
	local barrel = piece(base, {
		Name = "Barrel",
		Anchored = false,
		Massless = true,
		Size = look.barrel,
		CFrame = head.CFrame * CFrame.new(0, 0, -(look.headSize.Z / 2 + look.barrel.Z / 2) + 0.2),
		Color = Color3.fromRGB(40, 40, 45),
		Material = Enum.Material.Metal,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = barrel
	weld.Parent = barrel

	tower.head = head
	tower.barrelLength = look.headSize.Z / 2 + look.barrel.Z - 0.2
end

-- Returns (ok, reason). Position Y from the client is ignored.
function TowerService.place(player: Player, kind: string, requested: Vector3): (boolean, string?)
	local def = Config.Towers[kind]
	if not def then
		return false, "Unknown tower"
	end
	if ownedCount(player) >= Config.MaxTowersPerPlayer then
		return false, "Tower limit reached"
	end
	local position = Vector3.new(requested.X, map.groundY, requested.Z)
	local ok, reason = Placement.check(kind, position, map.path, map.bounds, positions())
	if not ok then
		return false, reason
	end
	local cost = def.levels[1].cost
	if not GameState.trySpend(player, cost) then
		return false, "Not enough cash"
	end

	nextId += 1
	local part = Instance.new("Part")
	part.Name = kind
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("TowerId", nextId)
	part:SetAttribute("TowerType", kind)
	part:SetAttribute("OwnerId", player.UserId)

	local tower: Tower = {
		id = nextId,
		owner = player,
		kind = kind,
		def = def,
		level = 1,
		spent = cost,
		position = position,
		cooldown = 0,
		part = part,
		head = nil,
		barrelLength = 1,
	}
	build(tower)
	part.Parent = map.towersFolder
	towers[tower.id] = tower
	return true, nil
end

local function ownedTower(player: Player, id: number): Tower?
	local tower = towers[id]
	if tower and tower.owner == player then
		return tower
	end
	return nil
end

function TowerService.upgrade(player: Player, id: number): (boolean, string?)
	local tower = ownedTower(player, id)
	if not tower then
		return false, "Not your tower"
	end
	local nextLevel = tower.def.levels[tower.level + 1]
	if not nextLevel then
		return false, "Already max level"
	end
	if not GameState.trySpend(player, nextLevel.cost) then
		return false, "Not enough cash"
	end
	tower.level += 1
	tower.spent += nextLevel.cost
	build(tower)
	return true, nil
end

local function destroy(tower: Tower)
	towers[tower.id] = nil
	tower.part:Destroy()
end

function TowerService.sell(player: Player, id: number): (boolean, string?)
	local tower = ownedTower(player, id)
	if not tower then
		return false, "Not your tower"
	end
	GameState.addCash(player, math.floor(tower.spent * Config.SellRefund))
	destroy(tower)
	return true, nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function fire(tower: Tower, stats: Config.TowerLevel, target: EnemyService.Enemy)
	local targetPosition = target.part.Position
	local muzzle = tower.part.Position
	local head = tower.head
	if head then
		local centre = head.Position
		local flatTarget = Vector3.new(targetPosition.X, centre.Y, targetPosition.Z)
		if (flatTarget - centre).Magnitude > 0.05 then
			head.CFrame = CFrame.lookAt(centre, flatTarget)
		end
		muzzle = (head.CFrame * CFrame.new(0, 0, -tower.barrelLength)).Position
	end

	local splash = stats.splash
	effect:FireAllClients("shot", muzzle, targetPosition, tower.def.color, splash or 0)
	if splash then
		local centre = target.position
		for _, enemy in EnemyService.all() do
			if flatDistance(enemy.position, centre) <= splash then
				EnemyService.damage(enemy, stats.damage, tower.owner)
			end
		end
	else
		EnemyService.damage(target, stats.damage, tower.owner)
	end
end

function TowerService.step(dt: number)
	for _, tower in towers do
		tower.cooldown -= dt
		if tower.cooldown <= 0 then
			local stats = tower.def.levels[tower.level]
			-- Target the enemy furthest along the path ("first") within range.
			local best: EnemyService.Enemy? = nil
			for _, enemy in EnemyService.all() do
				if flatDistance(enemy.position, tower.position) <= stats.range then
					if best == nil or enemy.distance > best.distance then
						best = enemy
					end
				end
			end
			if best then
				fire(tower, stats, best)
				tower.cooldown = stats.cooldown
			else
				tower.cooldown = 0 -- ready to fire the moment something walks in
			end
		end
	end
end

function TowerService.clear()
	for _, tower in towers do
		destroy(tower)
	end
end

Players.PlayerRemoving:Connect(function(player)
	for _, tower in towers do
		if tower.owner == player then
			destroy(tower)
		end
	end
end)

return TowerService
