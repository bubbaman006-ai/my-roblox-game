--!strict
-- One placement rule shared by both sides: the client uses it to tint the ghost,
-- the server uses it as the real check. The server never trusts the client's answer.

local Config = require(script.Parent.Config)
local Path = require(script.Parent.Path)

export type Bounds = { min: Vector3, max: Vector3 }

local Placement = {}

function Placement.check(
	towerName: string,
	position: Vector3,
	path: Path.Path,
	bounds: Bounds,
	existingTowerPositions: { Vector3 }
): (boolean, string?)
	local def = Config.Towers[towerName]
	if not def then
		return false, "Unknown tower"
	end
	if position.X < bounds.min.X or position.X > bounds.max.X or position.Z < bounds.min.Z or position.Z > bounds.max.Z then
		return false, "Outside the map"
	end
	local radius = math.max(def.size.X, def.size.Z) / 2
	if Path.flatDistanceTo(path, position) < Config.PathHalfWidth + radius then
		return false, "Too close to the path"
	end
	for _, other in existingTowerPositions do
		local flat = Vector3.new(other.X - position.X, 0, other.Z - position.Z)
		if flat.Magnitude < Config.MinTowerSpacing then
			return false, "Too close to another tower"
		end
	end
	return true, nil
end

return Placement
