--!strict
-- Lifetime player stats saved to a DataStore.
--
-- Safety rules this follows:
--   * If loading fails, that player's data is never saved this session (no wiping good data).
--   * Saves use UpdateAsync and apply only what changed this session (deltas), so two
--     servers saving the same player can't overwrite each other's progress.
--   * Retries with backoff, autosaves, and saves everyone on shutdown (BindToClose).
-- In Studio, turn on Game Settings > Security > "Enable Studio Access to API Services" to test saving.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Stats = {
	wins: number,
	kills: number,
	gamesPlayed: number,
	bestWave: number,
}

type Session = {
	loaded: boolean, -- false = load failed; never save
	stored: Stats, -- last known saved values (for display)
	pending: Stats, -- changes not yet saved (counts are deltas, bestWave is a max)
	saving: boolean,
}

local StatsService = {}

local store = DataStoreService:GetDataStore(Config.StatsStoreName)
local sessions: { [Player]: Session } = {}

local function blank(): Stats
	return { wins = 0, kills = 0, gamesPlayed = 0, bestWave = 0 }
end

local function sanitize(raw: any): Stats
	local stats = blank()
	if typeof(raw) == "table" then
		for key in stats do
			local value = raw[key]
			if typeof(value) == "number" and value == value then
				(stats :: any)[key] = value
			end
		end
	end
	return stats
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	local delay = 1
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[Stats] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		if attempt < 4 then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, nil
end

local function display(player: Player, session: Session)
	local leaderstats = player:FindFirstChild("leaderstats")
	local wins = leaderstats and leaderstats:FindFirstChild("Wins")
	if wins and wins:IsA("IntValue") then
		wins.Value = session.stored.wins + session.pending.wins
	end
	player:SetAttribute("BestWave", math.max(session.stored.bestWave, session.pending.bestWave))
	player:SetAttribute("TotalKills", session.stored.kills + session.pending.kills)
end

local function save(player: Player)
	local session = sessions[player]
	if not session or not session.loaded then
		return
	end
	while session.saving do -- let an in-flight save finish, then save what's left
		task.wait(0.1)
	end
	local pending = session.pending
	if pending.wins == 0 and pending.kills == 0 and pending.gamesPlayed == 0 and pending.bestWave == 0 then
		return
	end
	session.saving = true
	session.pending = blank() -- new progress during the save goes into a fresh bucket
	local ok, result = withRetries("save " .. keyFor(player), function()
		return store:UpdateAsync(keyFor(player), function(old)
			local stats = sanitize(old)
			stats.wins += pending.wins
			stats.kills += pending.kills
			stats.gamesPlayed += pending.gamesPlayed
			stats.bestWave = math.max(stats.bestWave, pending.bestWave)
			return stats
		end)
	end)
	session.saving = false
	if ok then
		session.stored = sanitize(result)
	else
		-- Put the unsaved progress back so the next attempt includes it.
		local current = session.pending
		current.wins += pending.wins
		current.kills += pending.kills
		current.gamesPlayed += pending.gamesPlayed
		current.bestWave = math.max(current.bestWave, pending.bestWave)
	end
end

local function onPlayerAdded(player: Player)
	local session: Session = { loaded = false, stored = blank(), pending = blank(), saving = false }
	sessions[player] = session

	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local wins = Instance.new("IntValue")
		wins.Name = "Wins"
		wins.Parent = leaderstats
	end

	local ok, data = withRetries("load " .. keyFor(player), function()
		return store:GetAsync(keyFor(player))
	end)
	if sessions[player] ~= session then
		return -- left while loading
	end
	if ok then
		session.loaded = true
		session.stored = sanitize(data)
	else
		warn("[Stats] Could not load " .. player.Name .. "; stats will not save this session.")
	end
	display(player, session)
end

-- Recording ---------------------------------------------------------------------------

function StatsService.addKill(player: Player?)
	local session = player and sessions[player]
	if player and session then
		session.pending.kills += 1
		display(player, session)
	end
end

-- Call once when a round ends, for everyone still in the server.
function StatsService.roundFinished(won: boolean, waveReached: number)
	for player, session in sessions do
		session.pending.gamesPlayed += 1
		if won then
			session.pending.wins += 1
		end
		session.pending.bestWave = math.max(session.pending.bestWave, waveReached)
		display(player, session)
		task.spawn(save, player)
	end
end

-- Lifecycle -----------------------------------------------------------------------------

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	sessions[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(Config.AutosaveSeconds)
		for player in sessions do
			task.spawn(save, player)
		end
	end
end)

game:BindToClose(function()
	local remaining = 0
	for player in sessions do
		remaining += 1
		task.spawn(function()
			save(player)
			remaining -= 1
		end)
	end
	local deadline = os.clock() + 25
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

return StatsService
