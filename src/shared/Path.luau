--!strict
-- Pure path maths: enemies are stored as "distance travelled along the path",
-- which makes movement cheap and gives towers a free "who is in front" ordering.

export type Path = {
	points: { Vector3 },
	cumulative: { number }, -- cumulative[i] = distance from points[1] to points[i]
	length: number,
}

local Path = {}

function Path.new(points: { Vector3 }): Path
	assert(#points >= 2, "Path needs at least two points")
	local cumulative = { 0 }
	for i = 2, #points do
		cumulative[i] = cumulative[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return { points = points, cumulative = cumulative, length = cumulative[#points] }
end

-- Position and facing direction at a given distance along the path.
function Path.sample(path: Path, distance: number): (Vector3, Vector3)
	local points, cumulative = path.points, path.cumulative
	if distance <= 0 then
		return points[1], (points[2] - points[1]).Unit
	end
	for i = 2, #points do
		if distance <= cumulative[i] then
			local a, b = points[i - 1], points[i]
			local segLength = cumulative[i] - cumulative[i - 1]
			local alpha = if segLength > 0 then (distance - cumulative[i - 1]) / segLength else 0
			return a:Lerp(b, alpha), (b - a).Unit
		end
	end
	local n = #points
	return points[n], (points[n] - points[n - 1]).Unit
end

-- Shortest flat (XZ) distance from a point to the path polyline.
function Path.flatDistanceTo(path: Path, position: Vector3): number
	local p = Vector3.new(position.X, 0, position.Z)
	local best = math.huge
	for i = 2, #path.points do
		local a = Vector3.new(path.points[i - 1].X, 0, path.points[i - 1].Z)
		local b = Vector3.new(path.points[i].X, 0, path.points[i].Z)
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		local t = if lengthSq > 0 then math.clamp((p - a):Dot(ab) / lengthSq, 0, 1) else 0
		best = math.min(best, (p - (a + ab * t)).Magnitude)
	end
	return best
end

return Path
