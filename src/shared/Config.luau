--!strict
-- All balance numbers live here. The server is the only side that acts on them;
-- the client reads them just to draw buttons, prices and range previews.

export type TowerLevel = {
	cost: number, -- price to buy (level 1) or to upgrade into this level
	damage: number,
	range: number, -- studs, measured flat (ignores height)
	cooldown: number, -- seconds between shots
	splash: number?, -- radius of area damage around the target, if any
}

export type TowerDef = {
	displayName: string,
	color: Color3,
	size: Vector3,
	levels: { TowerLevel },
}

export type EnemyDef = {
	health: number,
	speed: number, -- studs per second
	reward: number, -- cash given to every player on kill
	livesCost: number, -- lives lost if it reaches the base
	color: Color3,
	size: number,
}

export type SpawnGroup = {
	enemy: string,
	count: number,
	interval: number, -- seconds between spawns in this group
}

export type Wave = { SpawnGroup }

local Config = {}

Config.StartingCash = 300
Config.StartingLives = 100
Config.IntermissionSeconds = 8
Config.WaveClearBonus = 50 -- per player, scaled by wave number below
Config.SellRefund = 0.6 -- fraction of total spent returned on sell
Config.MaxTowersPerPlayer = 40
Config.MinTowerSpacing = 4 -- studs between tower centres
Config.PathHalfWidth = 4 -- towers cannot sit within this (+ tower radius) of the path
Config.ResetDelaySeconds = 10

Config.Towers = {
	Gunner = {
		displayName = "Gunner",
		color = Color3.fromRGB(80, 160, 255),
		size = Vector3.new(3, 4, 3),
		levels = {
			{ cost = 100, damage = 4, range = 16, cooldown = 0.5 },
			{ cost = 120, damage = 7, range = 18, cooldown = 0.45 },
			{ cost = 250, damage = 12, range = 20, cooldown = 0.35 },
		},
	},
	Sniper = {
		displayName = "Sniper",
		color = Color3.fromRGB(120, 220, 120),
		size = Vector3.new(2.5, 6, 2.5),
		levels = {
			{ cost = 250, damage = 30, range = 40, cooldown = 2 },
			{ cost = 300, damage = 60, range = 46, cooldown = 1.8 },
			{ cost = 600, damage = 120, range = 55, cooldown = 1.5 },
		},
	},
	Cannon = {
		displayName = "Cannon",
		color = Color3.fromRGB(255, 140, 60),
		size = Vector3.new(4, 3, 4),
		levels = {
			{ cost = 300, damage = 10, range = 14, cooldown = 1.5, splash = 6 },
			{ cost = 350, damage = 18, range = 15, cooldown = 1.3, splash = 7 },
			{ cost = 700, damage = 32, range = 17, cooldown = 1.1, splash = 8 },
		},
	},
} :: { [string]: TowerDef }

-- Order the buttons appear in on screen.
Config.TowerOrder = { "Gunner", "Sniper", "Cannon" }

Config.Enemies = {
	Basic = { health = 20, speed = 8, reward = 5, livesCost = 1, color = Color3.fromRGB(220, 60, 60), size = 2 },
	Fast = { health = 12, speed = 16, reward = 6, livesCost = 1, color = Color3.fromRGB(255, 220, 60), size = 1.6 },
	Tank = { health = 150, speed = 5, reward = 20, livesCost = 5, color = Color3.fromRGB(120, 60, 160), size = 3 },
	Boss = { health = 2000, speed = 4, reward = 250, livesCost = 50, color = Color3.fromRGB(30, 30, 30), size = 5 },
} :: { [string]: EnemyDef }

Config.Waves = {
	{ { enemy = "Basic", count = 8, interval = 1 } },
	{ { enemy = "Basic", count = 12, interval = 0.8 } },
	{ { enemy = "Basic", count = 10, interval = 0.8 }, { enemy = "Fast", count = 6, interval = 0.6 } },
	{ { enemy = "Fast", count = 15, interval = 0.5 } },
	{ { enemy = "Basic", count = 15, interval = 0.6 }, { enemy = "Tank", count = 2, interval = 3 } },
	{ { enemy = "Tank", count = 5, interval = 2 }, { enemy = "Fast", count = 15, interval = 0.4 } },
	{ { enemy = "Basic", count = 25, interval = 0.4 }, { enemy = "Tank", count = 6, interval = 1.5 } },
	{ { enemy = "Fast", count = 30, interval = 0.3 }, { enemy = "Tank", count = 8, interval = 1.2 } },
	{ { enemy = "Tank", count = 15, interval = 1 }, { enemy = "Fast", count = 20, interval = 0.3 } },
	{ { enemy = "Tank", count = 10, interval = 1 }, { enemy = "Boss", count = 1, interval = 1 } },
} :: { Wave }

return Config
