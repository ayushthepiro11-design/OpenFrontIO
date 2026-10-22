--!native
--!strict
-- Exact Full-Scale 1:1 OpenFront Configuration (`packages/engine-lib/src/configuration/Config.ts`,
-- `EngineConfig.ts`, `DoomsdayClock.ts` + unified Server/Client scale functions & NaN sanitizers!)

local Types = require(script.Parent:WaitForChild("Types"))

type Difficulty = Types.Difficulty
type PlayerType = Types.PlayerType
type UnitType = Types.UnitType
type GameConfig = Types.GameConfig
type TerrainKind = Types.TerrainKind

local Config = {}

function Config.IsFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function Config.SafeClampNumber(v: any, minVal: number, maxVal: number, fallback: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return math.clamp(n, minVal, maxVal)
end

-- Core Tick Timing: 100ms per tick = 10 ticks/sec (exact OpenFront constant)
Config.MS_PER_TICK = 100
Config.TICKS_PER_SECOND = 10

Config.PERCENT_TILES_TO_WIN = 80
Config.CITY_TROOP_INCREASE = 250_000
Config.DEFENSE_POST_RANGE = 30
Config.DEFENSE_POST_DEFENSE_BONUS = 5
Config.DEFENSE_POST_SPEED_BONUS = 3
Config.DEFENSE_POST_SHELL_RANGE = 75
Config.DEFENSE_POST_SHELL_RATE = 25

-- Full 1:1 2000px OpenFront structure spacing & rail distances!
Config.STRUCTURE_MIN_DIST = 12
Config.SILO_COOLDOWN_TICKS = 90
Config.SAM_COOLDOWN_TICKS = 90
Config.SAM_MAX_RANGE = 150
Config.TRAIN_STATION_MIN_RANGE = 14
Config.TRAIN_STATION_MAX_RANGE = 135
Config.BOAT_MAX_NUMBER = 3

Config.TRAITOR_DEFENSE_DEBUFF = 0.5
Config.TRAITOR_SPEED_DEBUFF = 0.8
Config.TRAITOR_DURATION_TICKS = 300 -- 30s
Config.RETREAT_MALUS_PERCENT = 25

Config.ALLIANCE_REQUEST_DURATION_TICKS = 200 -- 20s
Config.ALLIANCE_REQUEST_COOLDOWN_TICKS = 150 -- 15s
Config.DONATE_COOLDOWN_TICKS = 100 -- 10s
Config.TARGET_DURATION_TICKS = 100 -- 10s
Config.TARGET_COOLDOWN_TICKS = 150 -- 15s
Config.DELETE_UNIT_COOLDOWN_TICKS = 300 -- 30s
Config.EMOJI_DURATION_TICKS = 50 -- 5s
Config.EMOJI_COOLDOWN_TICKS = 25 -- 2.5s
Config.SPAWN_IMMUNITY_TICKS = 50 -- 5s

Config.WARSHIP_BASE_HP = 1000
Config.WARSHIP_SHELL_DAMAGE = 250
Config.WARSHIP_PATROL_RANGE = 100
Config.WARSHIP_TARGET_RANGE = 130
Config.WARSHIP_SHELL_RATE_TICKS = 20 -- 2.0s
Config.WARSHIP_PASSIVE_HEAL = 2
Config.WARSHIP_PASSIVE_HEAL_RANGE = 120
Config.WARSHIP_MAX_VETERANCY = 3
Config.WARSHIP_VET_BONUS_PCT = 20

function Config.MapScaleFactor(mapWidth: number): number
	return math.clamp(mapWidth / 2000, 0.50, 1.65)
end

function Config.StructureMinDistScaled(mapWidth: number): number
	return math.max(4, math.floor(Config.STRUCTURE_MIN_DIST * Config.MapScaleFactor(mapWidth) + 0.5))
end

function Config.DefensePostRangeScaled(mapWidth: number): number
	return math.max(12, math.floor(Config.DEFENSE_POST_RANGE * Config.MapScaleFactor(mapWidth) + 0.5))
end

function Config.DefensePostShellRangeScaled(mapWidth: number): number
	return math.max(28, math.floor(Config.DEFENSE_POST_SHELL_RANGE * Config.MapScaleFactor(mapWidth) + 0.5))
end

function Config.WarshipRangeScaled(mapWidth: number): number
	return math.max(48, math.floor(Config.WARSHIP_TARGET_RANGE * Config.MapScaleFactor(mapWidth) + 0.5))
end

function Config.DefaultGameConfig(singleplayer: boolean?): GameConfig
	return {
		mapId = "World",
		mode = "FFA",
		numTeams = 0,
		difficulty = "Medium",
		bots = 24,
		spawnNations = true,
		instantBuild = false,
		infiniteGold = false,
		infiniteTroops = false,
		startingGold = 0,
		goldMultiplier = 1,
		disableAlliances = false,
		allianceDurationMinutes = 5,
		donateGold = true,
		donateTroops = true,
		randomSpawn = false,
		waterNukes = false,
		doomsdayEnabled = false,
		doomsdaySpeed = "normal",
		overtimeEnabled = true,
		overtimeStartMinutes = 25,
		singleplayer = if singleplayer ~= nil then singleplayer else false,
		seed = 133701,
	}
end

function Config.SpawnPhaseTicks(cfg: GameConfig): number
	if cfg.singleplayer then
		return 100
	elseif cfg.randomSpawn then
		return 120
	else
		return 160
	end
end

function Config.ConstructionTicks(unitType: UnitType, instantBuild: boolean): number
	if instantBuild then
		return 0
	end
	if unitType == "City" or unitType == "Factory" then
		return 20
	elseif unitType == "Port" or unitType == "DefensePost" then
		return 50
	elseif unitType == "MissileSilo" then
		return 100
	elseif unitType == "SAMLauncher" then
		return 180
	end
	return 0
end

-- Exact independent unit cost curves from EngineConfig.ts
function Config.UnitCost(
	unitType: UnitType,
	ownedCounts: { [string]: number },
	mirvsLaunched: number,
	infiniteGold: boolean,
	isHuman: boolean
): number
	if isHuman and infiniteGold then
		return 0
	end
	local count = ownedCounts[unitType] or 0
	if unitType == "City" then
		return math.min(1_000_000, math.pow(2, count) * 125_000)
	elseif unitType == "Port" then
		return math.min(1_000_000, math.pow(2, count) * 125_000)
	elseif unitType == "Factory" then
		return math.min(1_000_000, math.pow(2, count) * 125_000)
	elseif unitType == "DefensePost" then
		return math.min(250_000, (count + 1) * 50_000)
	elseif unitType == "MissileSilo" then
		return 1_000_000
	elseif unitType == "SAMLauncher" then
		return math.min(3_000_000, (count + 1) * 1_500_000)
	elseif unitType == "Warship" then
		return math.min(1_000_000, (count + 1) * 250_000)
	elseif unitType == "AtomBomb" then
		return 750_000
	elseif unitType == "HydrogenBomb" then
		return 5_000_000
	elseif unitType == "MIRV" then
		return 25_000_000 + mirvsLaunched * 15_000_000
	end
	return 0
end

-- Rational SAM range growth function: 150 - 480 / (level + 5) -> L1=70, L2=81.4, L3=90, L5=102...
function Config.SamRange(level: number): number
	return Config.SAM_MAX_RANGE - 480 / (math.max(1, level) + 5)
end

function Config.SamRangeScaled(level: number, mapWidth: number): number
	return Config.SamRange(level) * Config.MapScaleFactor(mapWidth)
end

-- Exact inner/outer nuke blast radii calibrated cleanly to FULL 1x maps (`1000px..4108px`)!
function Config.NukeRadii(unitType: UnitType, mapWidth: number): (number, number)
	local scale = Config.MapScaleFactor(mapWidth)
	if unitType == "MIRVWarhead" then
		return math.max(5, math.floor(14 * scale + 0.5)), math.max(9, math.floor(22 * scale + 0.5))
	elseif unitType == "AtomBomb" then
		return math.max(7, math.floor(16 * scale + 0.5)), math.max(15, math.floor(34 * scale + 0.5))
	elseif unitType == "HydrogenBomb" then
		return math.max(28, math.floor(76 * scale + 0.5)), math.max(38, math.floor(100 * scale + 0.5))
	end
	return 8, 16
end

function Config.StartingManpower(playerType: PlayerType, cfg: GameConfig): number
	if playerType == "Bot" then
		return 10_000
	elseif playerType == "Nation" then
		if cfg.difficulty == "Easy" then
			return 12_500
		elseif cfg.difficulty == "Medium" then
			return 18_750
		elseif cfg.difficulty == "Hard" then
			return 25_000
		else
			return 31_250
		end
	end
	return if cfg.infiniteTroops then 1_000_000 else 25_000
end

function Config.MaxTroops(
	numTilesOwned: number,
	totalCityLevels: number,
	playerType: PlayerType?,
	cfg: GameConfig?,
	mapWidth: number?
): number
	local pType = playerType or "Human"
	if pType == "Human" and cfg ~= nil and cfg.infiniteTroops then
		return 1_000_000_000
	end
	local sf = math.max(1, (mapWidth or 2000) / 500)
	local logicalTiles = math.max(0, numTilesOwned) / (sf * sf)
	local cityBonus = totalCityLevels * Config.CITY_TROOP_INCREASE
	local base = 2 * (math.pow(logicalTiles, 0.6) * 1000 + 50_000) + cityBonus
	if pType == "Bot" then
		return math.floor(base / 3)
	elseif pType == "Human" then
		return math.floor(base)
	end
	local diff = if cfg ~= nil then cfg.difficulty else "Medium"
	if diff == "Easy" then
		return math.floor(base * 0.5)
	elseif diff == "Medium" then
		return math.floor(base * 0.75)
	elseif diff == "Hard" then
		return math.floor(base)
	else
		return math.floor(base * 1.25)
	end
end

function Config.TroopIncreasePerTick(
	troops: number,
	maxTroops: number,
	playerType: PlayerType?,
	cfg: GameConfig?
): number
	if maxTroops <= 0 or troops >= maxTroops then
		return 0
	end
	local toAdd = (10 + math.pow(math.max(1, troops), 0.73) / 4) * (1 - troops / maxTroops)
	if playerType == "Bot" then
		toAdd *= 0.5
	elseif playerType == "Nation" then
		local diff = if cfg ~= nil then cfg.difficulty else "Medium"
		if diff == "Easy" then
			toAdd *= 0.90
		elseif diff == "Medium" then
			toAdd *= 0.95
		elseif diff == "Impossible" then
			toAdd *= 1.05
		end
	end
	return math.min(maxTroops - troops, math.max(0, toAdd))
end

function Config.GoldPerTick(
	playerType: PlayerType,
	cfg: GameConfig,
	troops: number?,
	tilesOwned: number?,
	cityLevels: number?,
	portLevels: number?,
	factoryLevels: number?
): number
	if playerType == "Human" and cfg.infiniteGold then
		return 10_000_000
	end
	local mult = if playerType == "Bot" then 0.65 else 1.0
	local workers = math.max(0, troops or 0) * 0.30 + math.max(0, tilesOwned or 0) * 2.5
	local infraMult = 1
		+ math.max(0, cityLevels or 0) * 0.18
		+ math.max(0, factoryLevels or 0) * 0.32
		+ math.max(0, portLevels or 0) * 0.15
	return math.floor((140 + workers * 0.016) * infraMult * mult * cfg.goldMultiplier)
end

-- Sigmoid trade ship revenue calibrated across 1000px..4108px maps
function Config.TradeShipGold(dist: number, mapWidth: number, goldMult: number): number
	local debuff = math.max(100, mapWidth * 0.24)
	local baseGold = 75_000 / (1 + math.exp(-0.025 * (dist - debuff))) + 65 * dist
	return math.floor(baseGold * goldMult)
end

function Config.TrainGold(rel: "self" | "team" | "ally" | "other", citiesVisited: number, goldMult: number): number
	local extra = math.max(0, citiesVisited - 9)
	local baseGold = 25_000
	if rel == "ally" then
		baseGold = 35_000
	elseif rel == "self" then
		baseGold = 10_000
	end
	return math.floor(math.max(5_000, baseGold - extra * 5_000) * goldMult)
end

local function sigmoid(x: number, k: number, mid: number): number
	return 1 / (1 + math.exp(-k * (x - mid)))
end

local function largeTerritoryBonus(numTiles: number, depth: number): number
	local safeTiles = math.max(1, numTiles)
	return 1 - depth * sigmoid(math.log(safeTiles), 2.5, math.log(300_000))
end

-- Exact EngineConfig.attackLogic dimensional law (`dA = sf^2 * dA0` on 1:1 full-resolution pixel grids!)
function Config.AttackLogic(
	terrain: TerrainKind,
	attackTroops: number,
	attackerType: PlayerType,
	attackerTiles: number,
	defenderType: PlayerType?,
	defenderTiles: number,
	defenderTroops: number,
	defenderIsTraitor: boolean,
	defenderHasDefensePost: boolean,
	falloutRatio: number?,
	borderSize: number,
	mapWidth: number?
): (number, number, number)
	local sf = math.max(1, (mapWidth or 2000) / 500)
	local areaScale = sf * sf
	local mag = 80
	local tileCost = 16.5
	if terrain == "Highland" then
		mag = 100
		tileCost = 20
	elseif terrain == "Mountain" then
		mag = 120
		tileCost = 25
	end

	if defenderType ~= nil and defenderHasDefensePost then
		mag *= Config.DEFENSE_POST_DEFENSE_BONUS
		tileCost *= Config.DEFENSE_POST_SPEED_BONUS
	end
	if falloutRatio ~= nil then
		local fmod = 3.0 - math.clamp(falloutRatio, 0, 1) * 1.2
		mag *= fmod
		tileCost *= fmod
	end

	local safeBorder = math.max(1, borderSize)
	local safeAtk = math.max(1, attackTroops)
	local logAtkTiles = attackerTiles / areaScale
	local logDefTiles = defenderTiles / areaScale

	if defenderType == nil then
		-- Exact upstream Terra Nullius expansion scaled by radial thickness `sf` + pixel area `areaScale`
		local tickBudget = safeBorder * 5.0 * sf
		local loss = ((mag * 0.08) / areaScale) / (if attackerType == "Bot" then 1.8 else 1.0)
		local frac = math.clamp((1000 * tileCost) / safeAtk, 1.2, 50) / tickBudget
		return loss, 0, frac
	end

	if (attackerType == "Human" or attackerType == "Nation") and defenderType == "Bot" then
		mag *= 0.70
	end

	local largeAtk = largeTerritoryBonus(logAtkTiles * 8, 0.70)
	local largeDef = largeTerritoryBonus(logDefTiles * 8, 0.30)
	local traitorLoss = if defenderIsTraitor then Config.TRAITOR_DEFENSE_DEBUFF else 1.0
	local traitorSpeed = if defenderIsTraitor then Config.TRAITOR_SPEED_DEBUFF else 1.0

	local defLoss = defenderTroops / math.max(1, defenderTiles)
	local troopRatio = defenderTroops / safeAtk
	local atkLoss = (mag * 0.08)
		* traitorLoss
		* math.clamp(troopRatio, 0.45, 2.0)
		* ((0.08 * largeAtk * largeDef) / areaScale + 0.35 * defLoss)

	local speedCost = (math.clamp(troopRatio, 0.22, 6.0) * math.clamp(troopRatio / 20, 1, 50)) / 9.2
	local largeAtkSpeed = largeTerritoryBonus(logAtkTiles * 8, 0.78)
	local tickFrac = (speedCost * tileCost * largeAtkSpeed * largeDef * traitorSpeed * 0.45) / (safeBorder * sf)
	return atkLoss, defLoss, tickFrac
end

function Config.WinPercentageRequired(cfg: GameConfig, elapsedSeconds: number): number
	if not cfg.overtimeEnabled then
		return Config.PERCENT_TILES_TO_WIN
	end
	local past = math.floor(elapsedSeconds) - cfg.overtimeStartMinutes * 60
	if past <= 0 then
		return Config.PERCENT_TILES_TO_WIN
	end
	return math.max(10, Config.PERCENT_TILES_TO_WIN - math.floor((past * 2) / 60))
end

local DOOM_LEVELS_FFA = { 200, 400, 700, 1100, 1700, 2500, 3500 }
local DOOM_LEVELS_TEAM = { 300, 600, 1000, 1500, 2100, 2800, 3500 }

function Config.DoomsdayRequiredShare(cfg: GameConfig, elapsedSeconds: number): number
	if not cfg.doomsdayEnabled then
		return 0
	end
	local grace = 180
	local ramp = 90
	local pause = 30
	if cfg.doomsdaySpeed == "slow" then
		grace, ramp, pause = 300, 150, 45
	elseif cfg.doomsdaySpeed == "fast" then
		grace, ramp, pause = 120, 60, 20
	elseif cfg.doomsdaySpeed == "veryfast" then
		grace, ramp, pause = 60, 30, 10
	end
	if elapsedSeconds <= grace then
		return 0
	end
	local levels = if cfg.mode == "Teams" then DOOM_LEVELS_TEAM else DOOM_LEVELS_FFA
	local t = elapsedSeconds - grace
	local prev = 0
	for i, target in ipairs(levels) do
		if t < ramp then
			return (prev + math.floor(((target - prev) * t) / ramp)) / 10_000
		end
		t -= ramp
		if i < #levels then
			if t < pause then
				return target / 10_000
			end
			t -= pause
		end
		prev = target
	end
	return levels[#levels] / 10_000
end

Config.Emojis = {
	"🤝", "👍", "👎", "🫡", "❤️", "😂", "😡", "💀",
	"🏳️", "☢️", "⚔️", "🛡️", "💰", "🚢", "👑", "🔥",
}

Config.AllowedEmojis = {}
for _, em in ipairs(Config.Emojis) do
	Config.AllowedEmojis[em] = true
end

Config.QuickChats = {
	{ id = "help_me", category = "Help", text = "Help me defend!", color = "#22c55e" },
	{ id = "need_gold", category = "Help", text = "Please send Gold!", color = "#f59e0b" },
	{ id = "need_troops", category = "Help", text = "Need Troops ASAP!", color = "#38bdf8" },
	{ id = "attack_leader", category = "Attack", text = "Team up on #1!", color = "#ef4444" },
	{ id = "alliance_pls", category = "Greet", text = "Alliance? Peace on our border!", color = "#4ade80" },
	{ id = "watch_nuke", category = "Warn", text = "Watch out — Nuke incoming!", color = "#fbbf24" },
	{ id = "gg", category = "Greet", text = "Good game, well fought!", color = "#a855f7" },
	{ id = "no_betray", category = "Warn", text = "Stay loyal! No betrayal!", color = "#f97316" },
}

function Config.XpForNextLevel(level: number): number
	return 500 + level * 350
end

return Config
