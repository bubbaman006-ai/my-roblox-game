--!strict
-- Cosmetic effects drawn locally from the server's unreliable "Effect" events.
-- Nothing here affects gameplay, so dropped or malformed events are simply ignored.
--   ("shot", from: Vector3, to: Vector3, color: Color3, splash: number)
--   ("pop",  at: Vector3, color: Color3, size: number)

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Effects = {}

local container = Instance.new("Folder")
container.Name = "LocalEffects"
container.Parent = workspace

local MAX_LIVE = 150 -- cap so a huge late wave can't flood the client with parts

local function fx(props: { [string]: any }, lifetime: number): Part?
	if #container:GetChildren() >= MAX_LIVE then
		return nil
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = container
	Debris:AddItem(p, lifetime)
	return p
end

local function fade(part: Part?, seconds: number, goal: { [string]: any })
	if part then
		goal.Transparency = 1
		TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	end
end

local function shot(from: Vector3, to: Vector3, color: Color3, splash: number)
	local length = (to - from).Magnitude
	if length > 0.1 then
		local tracer = fx({
			Color = color,
			Size = Vector3.new(0.15, 0.15, length),
			CFrame = CFrame.lookAt((from + to) / 2, to),
		}, 0.15)
		fade(tracer, 0.12, { Size = Vector3.new(0.02, 0.02, length) })
	end

	local flash = fx({ Shape = Enum.PartType.Ball, Color = Color3.new(1, 0.95, 0.7), Size = Vector3.one * 0.9, Position = from }, 0.12)
	fade(flash, 0.1, { Size = Vector3.one * 0.2 })

	if splash > 0 then
		local blast = fx({
			Shape = Enum.PartType.Ball,
			Color = color,
			Transparency = 0.3,
			Size = Vector3.one,
			Position = to,
		}, 0.4)
		fade(blast, 0.35, { Size = Vector3.one * splash * 2 })
	else
		local spark = fx({ Shape = Enum.PartType.Ball, Color = color, Size = Vector3.one * 0.6, Position = to }, 0.15)
		fade(spark, 0.12, { Size = Vector3.one * 1.4 })
	end
end

local function pop(at: Vector3, color: Color3, size: number)
	local ring = fx({ Shape = Enum.PartType.Ball, Color = color, Transparency = 0.2, Size = Vector3.one * size, Position = at }, 0.35)
	fade(ring, 0.3, { Size = Vector3.one * size * 2.2 })
	for _ = 1, 5 do
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
		local chunk = fx({
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Size = Vector3.one * size * 0.25,
			Position = at,
		}, 0.5)
		fade(chunk, 0.45, { Position = at + direction * size * 2, Orientation = Vector3.new(180, 90, 0) })
	end
end

function Effects.handle(kind: any, ...: any)
	local a, b, c, d = ...
	if kind == "shot" then
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" and typeof(c) == "Color3" and typeof(d) == "number" then
			shot(a, b, c, d)
		end
	elseif kind == "pop" then
		if typeof(a) == "Vector3" and typeof(b) == "Color3" and typeof(c) == "number" then
			pop(a, b, c)
		end
	end
end

return Effects
