--!strict
-- The round loop: Lobby -> (Intermission -> Wave) x N -> Victory or GameOver -> reset -> Lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameState = require(script.Parent.GameState)
local EnemyService = require(script.Parent.EnemyService)
local TowerService = require(script.Parent.TowerService)
local VoteService = require(script.Parent.VoteService)
local StatsService = require(script.Parent.StatsService)

local WaveService = {}

local startRequested = false

function WaveService.requestStart()
	if GameState.getPhase() == "Lobby" then
		startRequested = true
	end
end

local function alive(): boolean
	return GameState.getLives() > 0
end

-- Waits `seconds` of game time (sped up by the 2x vote), returning false early if the base falls.
local function waitAlive(seconds: number): boolean
	local remaining = seconds
	while remaining > 0 do
		if not alive() then
			return false
		end
		remaining -= task.wait(math.min(0.1, remaining / GameState.getSpeed())) * GameState.getSpeed()
	end
	return alive()
end

local function intermission()
	GameState.setPhase("Intermission")
	VoteService.clearSkip()
	local remaining = Config.IntermissionSeconds
	while remaining > 0 and not VoteService.skipPassed() do
		GameState.setCountdown(math.ceil(remaining))
		remaining -= task.wait(0.1) * GameState.getSpeed()
	end
	GameState.setCountdown(0)
	VoteService.clearSkip()
end

local function playRound(): "Victory" | "GameOver"
	for waveNumber, wave in Config.Waves do
		intermission()

		GameState.setWave(waveNumber)
		GameState.setPhase("Wave")
		for _, group in wave do
			for _ = 1, group.count do
				if not alive() then
					return "GameOver"
				end
				EnemyService.spawn(group.enemy)
				if not waitAlive(group.interval) then
					return "GameOver"
				end
			end
		end
		while EnemyService.count() > 0 do
			if not waitAlive(0.2) then
				return "GameOver"
			end
		end
		GameState.addCashToAll(Config.WaveClearBonus + waveNumber * 10)
	end
	return "Victory"
end

function WaveService.run()
	while true do
		GameState.setPhase("Lobby")
		startRequested = false
		while not startRequested do
			task.wait(0.25)
		end

		local result = playRound()
		GameState.setPhase(result)
		EnemyService.clear()
		StatsService.roundFinished(result == "Victory", GameState.getWave())
		VoteService.clearAll()
		for remaining = Config.ResetDelaySeconds, 1, -1 do
			GameState.setCountdown(remaining)
			task.wait(1)
		end
		TowerService.clear()
		GameState.resetRound()
	end
end

return WaveService
