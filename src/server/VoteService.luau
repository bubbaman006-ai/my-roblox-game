--!strict
-- Skip-intermission and 2x-speed votes. A vote passes with more than half the server.
-- Each remote call toggles the caller's own vote, so spamming does nothing useful.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameState = require(script.Parent.GameState)

local VoteService = {}

local skipVotes: { [Player]: boolean } = {}
local speedVotes: { [Player]: boolean } = {}

local function countOf(votes: { [Player]: boolean }): number
	local n = 0
	for _ in votes do
		n += 1
	end
	return n
end

local function needed(): number
	return math.floor(#Players:GetPlayers() / 2) + 1
end

local function publish()
	GameState.set("SkipVotes", countOf(skipVotes))
	GameState.set("SpeedVotes", countOf(speedVotes))
	GameState.set("VotesNeeded", needed())
	GameState.set("Speed", if countOf(speedVotes) >= needed() then Config.FastSpeed else 1)
end

local function toggle(votes: { [Player]: boolean }, player: Player)
	votes[player] = if votes[player] then nil else true
	publish()
end

function VoteService.toggleSkip(player: Player)
	if GameState.getPhase() == "Intermission" then
		toggle(skipVotes, player)
	end
end

function VoteService.toggleSpeed(player: Player)
	local phase = GameState.getPhase()
	if phase == "Intermission" or phase == "Wave" then
		toggle(speedVotes, player)
	end
end

function VoteService.skipPassed(): boolean
	return countOf(skipVotes) >= needed()
end

function VoteService.clearSkip()
	table.clear(skipVotes)
	publish()
end

function VoteService.clearAll()
	table.clear(skipVotes)
	table.clear(speedVotes)
	publish()
end

Players.PlayerAdded:Connect(publish)
Players.PlayerRemoving:Connect(function(player)
	skipVotes[player] = nil
	speedVotes[player] = nil
	-- The leaving player still counts in GetPlayers() during this event.
	task.defer(publish)
end)

return VoteService
