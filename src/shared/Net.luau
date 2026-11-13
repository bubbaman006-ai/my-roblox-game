--!strict
-- Remote names in one place. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Names = {
	PlaceTower = "PlaceTower", -- client -> server: (towerName: string, position: Vector3)
	UpgradeTower = "UpgradeTower", -- client -> server: (towerId: number)
	SellTower = "SellTower", -- client -> server: (towerId: number)
	StartGame = "StartGame", -- client -> server: ()
	Notify = "Notify", -- server -> client: (message: string)
}

local FOLDER_NAME = "Remotes"

function Net.folder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		for _, name in Net.Names do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Net.event(name: string): RemoteEvent
	local remote = Net.folder():WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), name .. " is not a RemoteEvent")
	return remote
end

return Net
