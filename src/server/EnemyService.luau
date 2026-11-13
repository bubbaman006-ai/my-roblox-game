--!strict
-- Enemies are anchored parts the server slides along the path every frame.
-- Their position is "distance travelled", which towers use to target the leader.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Path = require(ReplicatedStorage.Shared.Path)
local Net = require(ReplicatedStorage.Shared.Net)
local GameState = require(script.Parent.GameState)
local StatsService = require(script.Parent.StatsService)

local effect = Net.unreliable(Net.UnreliableNames.Effect)

export type Enemy = {
	id: number,
	kind: string,
	def: Config.EnemyDef,
	health: number,
	distance: number,
	position: Vector3,
	part: Part,
	bar: Frame,
	alive: boolean,
}

local EnemyService = {}

local path: Path.Path
local folder: Folder
local enemies: { [number]: Enemy } = {}
local count = 0
local nextId = 0

function EnemyService.init(mapPath: Path.Path, enemiesFolder: Folder)
	path = mapPath
	folder = enemiesFolder
end

local function makeHealthBar(part: Part): Frame
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(50, 6)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = part
	return fill
end

local function remove(enemy: Enemy)
	if not enemy.alive then
		return
	end
	enemy.alive = false
	enemies[enemy.id] = nil
	count -= 1
	enemy.part:Destroy()
end

function EnemyService.spawn(kind: string)
	local def = Config.Enemies[kind]
	assert(def, "Unknown enemy " .. kind)
	nextId += 1

	local part = Instance.new("Part")
	part.Name = kind
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * def.size
	part.Color = def.color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part:SetAttribute("EnemyId", nextId)

	local start = Path.sample(path, 0)
	local enemy: Enemy = {
		id = nextId,
		kind = kind,
		def = def,
		health = def.health,
		distance = 0,
		position = start,
		part = part,
		bar = makeHealthBar(part),
		alive = true,
	}
	part.Position = start + Vector3.new(0, def.size / 2, 0)
	part.Parent = folder
	enemies[enemy.id] = enemy
	count += 1
end

-- `source` is the player whose tower dealt the hit; they get credit for the kill.
function EnemyService.damage(enemy: Enemy, amount: number, source: Player?)
	if not enemy.alive then
		return
	end
	enemy.health -= amount
	if enemy.health <= 0 then
		GameState.addCashToAll(enemy.def.reward)
		StatsService.addKill(source)
		effect:FireAllClients("pop", enemy.part.Position, enemy.def.color, enemy.def.size)
		remove(enemy)
	else
		enemy.bar.Size = UDim2.fromScale(enemy.health / enemy.def.health, 1)
	end
end

function EnemyService.step(dt: number)
	for _, enemy in enemies do
		enemy.distance += enemy.def.speed * dt
		if enemy.distance >= path.length then
			GameState.loseLives(enemy.def.livesCost)
			remove(enemy)
		else
			local position, direction = Path.sample(path, enemy.distance)
			enemy.position = position
			local lifted = position + Vector3.new(0, enemy.def.size / 2, 0)
			enemy.part.CFrame = CFrame.lookAt(lifted, lifted + direction)
		end
	end
end

-- Iterate live enemies (don't keep references across frames: they may die).
function EnemyService.all(): { [number]: Enemy }
	return enemies
end

function EnemyService.count(): number
	return count
end

function EnemyService.clear()
	for _, enemy in enemies do
		remove(enemy)
	end
end

return EnemyService
