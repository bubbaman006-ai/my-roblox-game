--!strict
-- Server entry point: builds the map, wires remotes (with validation and rate limits)
-- and drives enemies and towers every frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Map = require(script.Map)
local GameState = require(script.GameState)
local EnemyService = require(script.EnemyService)
local TowerService = require(script.TowerService)
local WaveService = require(script.WaveService)

local map = Map.load()
EnemyService.init(map.path, map.enemiesFolder)
TowerService.init(map)
Net.folder()

local notify = Net.event(Net.Names.Notify)

-- Rate limiting: each player gets a small budget of requests per remote.
local MIN_INTERVAL = 0.15
local lastCall: { [Player]: { [string]: number } } = {}

local function allowed(player: Player, remoteName: string): boolean
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local now = os.clock()
	if now - (calls[remoteName] or 0) < MIN_INTERVAL then
		return false
	end
	calls[remoteName] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < 1e6
end

local function isTowerId(value: any): boolean
	return isFiniteNumber(value) and value == math.floor(value) and value > 0
end

local function canBuild(): boolean
	local phase = GameState.getPhase()
	return phase == "Lobby" or phase == "Intermission" or phase == "Wave"
end

local function report(player: Player, ok: boolean, reason: string?)
	if not ok and reason then
		notify:FireClient(player, reason)
	end
end

Net.event(Net.Names.PlaceTower).OnServerEvent:Connect(function(player, kind, position)
	if not allowed(player, "PlaceTower") or not canBuild() then
		return
	end
	if typeof(kind) ~= "string" or #kind > 32 or typeof(position) ~= "Vector3" then
		return
	end
	if not (isFiniteNumber(position.X) and isFiniteNumber(position.Z)) then
		return
	end
	report(player, TowerService.place(player, kind, position))
end)

Net.event(Net.Names.UpgradeTower).OnServerEvent:Connect(function(player, id)
	if not allowed(player, "UpgradeTower") or not canBuild() or not isTowerId(id) then
		return
	end
	report(player, TowerService.upgrade(player, id))
end)

Net.event(Net.Names.SellTower).OnServerEvent:Connect(function(player, id)
	if not allowed(player, "SellTower") or not canBuild() or not isTowerId(id) then
		return
	end
	report(player, TowerService.sell(player, id))
end)

Net.event(Net.Names.StartGame).OnServerEvent:Connect(function(player)
	if allowed(player, "StartGame") then
		WaveService.requestStart()
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local phase = GameState.getPhase()
	if phase == "Wave" or phase == "Intermission" then
		EnemyService.step(dt)
		TowerService.step(dt)
	end
end)

task.spawn(WaveService.run)
