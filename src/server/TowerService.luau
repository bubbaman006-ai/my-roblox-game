--!strict
-- Placing, upgrading, selling and firing towers. Every request from a client is
-- re-checked here: tower type, position, ownership, price and placement rules.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Placement = require(ReplicatedStorage.Shared.Placement)
local GameState = require(script.Parent.GameState)
local EnemyService = require(script.Parent.EnemyService)
local Map = require(script.Parent.Map)

type Tower = {
	id: number,
	owner: Player,
	kind: string,
	def: Config.TowerDef,
	level: number,
	spent: number,
	position: Vector3, -- on the ground, centre of the footprint
	cooldown: number,
	part: Part,
}

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

local function refreshPart(tower: Tower)
	local stats = tower.def.levels[tower.level]
	tower.part:SetAttribute("Level", tower.level)
	tower.part:SetAttribute("Range", stats.range)
	tower.part:SetAttribute("Spent", tower.spent)
	-- Taller and brighter per level so upgrades read at a glance.
	local size = tower.def.size + Vector3.new(0, (tower.level - 1) * 1, 0)
	tower.part.Size = size
	tower.part.Position = tower.position + Vector3.new(0, size.Y / 2, 0)
	tower.part.Color = tower.def.color:Lerp(Color3.new(1, 1, 1), (tower.level - 1) * 0.2)
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
	part.Material = Enum.Material.SmoothPlastic
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
	}
	refreshPart(tower)
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
	refreshPart(tower)
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

local function tracer(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(0.2, 0.2, length)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = workspace
	Debris:AddItem(beam, 0.08)
end

local function fire(tower: Tower, stats: Config.TowerLevel, target: EnemyService.Enemy)
	local muzzle = tower.part.Position + Vector3.new(0, tower.part.Size.Y / 2, 0)
	tracer(muzzle, target.part.Position, tower.def.color)
	local splash = stats.splash
	if splash then
		local centre = target.position
		for _, enemy in EnemyService.all() do
			if flatDistance(enemy.position, centre) <= splash then
				EnemyService.damage(enemy, stats.damage)
			end
		end
	else
		EnemyService.damage(target, stats.damage)
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
