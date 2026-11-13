--!strict
-- Round-wide state (lives, wave, phase) and per-player cash.
-- Everything is replicated through attributes, so the client only ever reads it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Phase = "Lobby" | "Intermission" | "Wave" | "GameOver" | "Victory"

local GameState = {}

local stateFolder = Instance.new("Folder")
stateFolder.Name = "GameState"
stateFolder:SetAttribute("Phase", "Lobby")
stateFolder:SetAttribute("Lives", Config.StartingLives)
stateFolder:SetAttribute("Wave", 0)
stateFolder:SetAttribute("TotalWaves", #Config.Waves)
stateFolder:SetAttribute("Countdown", 0)
stateFolder:SetAttribute("Speed", 1)
stateFolder:SetAttribute("SkipVotes", 0)
stateFolder:SetAttribute("SpeedVotes", 0)
stateFolder:SetAttribute("VotesNeeded", 1)
stateFolder.Parent = ReplicatedStorage

local cash: { [Player]: number } = {}

-- Round state -----------------------------------------------------------------

function GameState.getPhase(): Phase
	return stateFolder:GetAttribute("Phase") :: Phase
end

function GameState.setPhase(phase: Phase)
	stateFolder:SetAttribute("Phase", phase)
end

function GameState.getLives(): number
	return stateFolder:GetAttribute("Lives") :: number
end

function GameState.loseLives(amount: number)
	stateFolder:SetAttribute("Lives", math.max(0, GameState.getLives() - amount))
end

function GameState.setWave(wave: number)
	stateFolder:SetAttribute("Wave", wave)
end

function GameState.setCountdown(seconds: number)
	stateFolder:SetAttribute("Countdown", seconds)
end

function GameState.getWave(): number
	return stateFolder:GetAttribute("Wave") :: number
end

function GameState.getSpeed(): number
	return stateFolder:GetAttribute("Speed") :: number
end

-- Generic setter for the small vote/speed attributes VoteService owns.
function GameState.set(attribute: string, value: number)
	stateFolder:SetAttribute(attribute, value)
end

-- Cash ------------------------------------------------------------------------

local function sync(player: Player)
	local amount = cash[player] or 0
	player:SetAttribute("Cash", amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Cash")
	if value and value:IsA("IntValue") then
		value.Value = amount
	end
end

function GameState.getCash(player: Player): number
	return cash[player] or 0
end

function GameState.addCash(player: Player, amount: number)
	if cash[player] == nil then
		return -- player is leaving
	end
	cash[player] += math.floor(amount)
	sync(player)
end

function GameState.addCashToAll(amount: number)
	for player in cash do
		GameState.addCash(player, amount)
	end
end

-- Returns true and deducts only if the player can afford it.
function GameState.trySpend(player: Player, amount: number): boolean
	local current = cash[player]
	if current == nil or amount < 0 or current < amount then
		return false
	end
	cash[player] = current - amount
	sync(player)
	return true
end

function GameState.resetRound()
	stateFolder:SetAttribute("Lives", Config.StartingLives)
	stateFolder:SetAttribute("Wave", 0)
	stateFolder:SetAttribute("Countdown", 0)
	for player in cash do
		cash[player] = Config.StartingCash
		sync(player)
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local value = Instance.new("IntValue")
	value.Name = "Cash"
	value.Parent = leaderstats
	leaderstats.Parent = player
	cash[player] = Config.StartingCash
	sync(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	cash[player] = nil
end)

return GameState
