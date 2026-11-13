--!strict
-- The round loop: Lobby -> (Intermission -> Wave) x N -> Victory or GameOver -> reset -> Lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameState = require(script.Parent.GameState)
local EnemyService = require(script.Parent.EnemyService)
local TowerService = require(script.Parent.TowerService)

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

-- Waits up to `seconds`, returning false early if the base falls.
local function waitAlive(seconds: number): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if not alive() then
			return false
		end
		task.wait(math.min(0.1, deadline - os.clock()))
	end
	return alive()
end

local function playRound(): "Victory" | "GameOver"
	for waveNumber, wave in Config.Waves do
		GameState.setPhase("Intermission")
		for remaining = Config.IntermissionSeconds, 1, -1 do
			GameState.setCountdown(remaining)
			task.wait(1)
		end
		GameState.setCountdown(0)

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
		for remaining = Config.ResetDelaySeconds, 1, -1 do
			GameState.setCountdown(remaining)
			task.wait(1)
		end
		TowerService.clear()
		GameState.resetRound()
	end
end

return WaveService
