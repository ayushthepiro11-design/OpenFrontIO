--!native
--!strict
-- Authoritative Full-Scale 1:1 OpenFront 10Hz Simulation Engine (`SimEngine.luau`)
-- Engineered for ALL 24 full-resolution maps (`1000x1000` .. `4108x1948` = `8,002,384` tiles & up to `107` nations!):
--   - Deterministic `Mulberry32` seeded PRNG (`self:_Rand()`, `self:_RandInt()`) — 0 unseeded `math.random` calls!
--   - Iterative non-recursive concave border fill (`zero stack overflow on huge continents!`)
--   - `32x32` Spatial Hash `UnitGrid` + `SharedWaterCache` (`O(1)` range combat & sea lanes!)
--   - Sparse `activeFalloutRefs` list (`O(crater)` fallout recovery + full `falloutSnapshot` sync!)
--   - Warship TradeShip piracy, Coastal DefensePost shelling, SAM lock reservation, Nuke betrayal!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")

local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local MapCodec = require(Shared:WaitForChild("MapCodec"))
local MapRegistry = require(Shared:WaitForChild("Maps"):WaitForChild("MapRegistry"))
local NetCodec = require(Shared:WaitForChild("NetCodec"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

local AiBrain = require(script.Parent:WaitForChild("AiBrain"))
local Heap = require(script.Parent:WaitForChild("Heap"))

type GameConfig = Types.GameConfig
type UnitType = Types.UnitType

local SimEngine = {}
SimEngine.__index = SimEngine

local TRIBE_PREFIXES = {
	"Iron", "Golden", "Crimson", "Northern", "Eastern", "Western", "Southern", "Alpine",
	"Coastal", "Highland", "Emerald", "Silver", "Obsidian", "Solar", "Azure", "Amber",
	"Granite", "Verdant", "Storm", "Cedar", "Steppe", "Delta", "Canyon", "Cobalt",
}
local TRIBE_SUFFIXES = {
	"Pact", "League", "Duchy", "March", "Clan", "Union", "Guard", "Freehold",
	"Republic", "Order", "Realm", "Barony", "Commune", "Front", "Dominion", "Hold",
}

local CAPTURABLE_STRUCTURES: { [string]: boolean } = {
	City = true,
	Port = true,
	Factory = true,
	DefensePost = true,
	MissileSilo = true,
	SAMLauncher = true,
}

local GRID_SHIFT = 5 -- 32x32 tile spatial buckets!

export type EngineInstance = typeof(setmetatable({} :: any, SimEngine))

function SimEngine:_Rand(): number
	local s = bit32.band((self.rngState :: number) + 0x6D2B79F5, 0xFFFFFFFF)
	self.rngState = s
	local t = bit32.bxor(s, bit32.rshift(s, 15))
	t = bit32.band(t * bit32.bor(1, s), 0xFFFFFFFF)
	t = bit32.band(t + bit32.bxor(t, bit32.band(bit32.bxor(t, bit32.rshift(t, 7)) * bit32.bor(61, t), 0xFFFFFFFF)), 0xFFFFFFFF)
	return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296.0
end

function SimEngine:_RandInt(lo: number, hi: number): number
	if hi <= lo then
		return lo
	end
	return lo + math.floor(self:_Rand() * (hi - lo + 1))
end

function SimEngine.new(cfg: GameConfig, humanConfigs: { any }, isPreview: boolean?): EngineInstance
	local rawDef = MapRegistry.Get(cfg.mapId)
	local map = MapCodec.DecodeMap(rawDef)

	local initSeed = bit32.band(math.floor(cfg.seed or 133701), 0xFFFFFFFF)
	if initSeed == 0 then
		initSeed = 0x9E3779B9
	end

	local self = setmetatable({}, SimEngine) :: any
	self.config = cfg
	self.rngState = initSeed
	self.paused = false
	self.simSpeed = 1
	self.isPreview = isPreview == true
	self.map = map
	self.rawMap = rawDef
	self.ticks = 0
	self.spawnPhaseTicks = if self.isPreview then 1 else Config.SpawnPhaseTicks(cfg)
	self.inSpawnPhase = true
	self.gameOver = false
	self.winnerName = nil :: string?
	self.winnerSmallId = nil :: number?
	self.winnerTeam = nil :: string?
	self.mirvsLaunched = 0

	self.playersList = {}
	self.playersBySmallId = {}
	self.playersByUserId = {}
	self.nextSmallId = 0

	self.attacks = {}
	self.nextAttackId = 0

	self.units = {}
	self.unitsByTile = {} :: { [number]: any }
	self.nextUnitId = 0

	self.gridCols = math.ceil(map.width / 32)
	self.gridRows = math.ceil(map.height / 32)
	self.unitGrid = {} :: { [number]: { any } }
	self.sharedWaterCache = {} :: { [string]: { number } }
	self.waterCacheCount = 0

	self.activeFalloutRefs = {} :: { number }
	self.inFalloutSet = {} :: { [number]: boolean }

	self.railEdges = {} :: { { number } }
	self.railNetworkDirty = false

	self.allianceRequests = {}
	self.nextAlertId = 0
	self.alertsByPlayer = {} :: { [number]: { Types.ActionableAlert } }
	self.events = {} :: { Types.EventFeedItem }
	self.nextEventId = 0
	self.explosions = {} :: { { x: number, y: number, radius: number, kind: string } }

	self.deltaRefs = {} :: { number }
	self.deltaOwners = {} :: { number }
	self.deltaCount = 0

	self.falloutDeltaRefs = {} :: { number }
	self.falloutDeltaStates = {} :: { number }
	self.falloutDeltaCount = 0

	self:_InitParticipants(humanConfigs)
	return self
end

function SimEngine:_GridCellIndex(x: number, y: number): number
	local gx = math.clamp(bit32.rshift(math.max(0, math.floor(x)), GRID_SHIFT), 0, self.gridCols - 1)
	local gy = math.clamp(bit32.rshift(math.max(0, math.floor(y)), GRID_SHIFT), 0, self.gridRows - 1)
	return gy * self.gridCols + gx + 1
end

function SimEngine:_GridInsert(u: any)
	local c = self:_GridCellIndex(u.x, u.y)
	u._gridCell = c
	local bucket = self.unitGrid[c]
	if bucket == nil then
		bucket = {}
		self.unitGrid[c] = bucket
	end
	table.insert(bucket, u)
end

function SimEngine:_GridRemove(u: any)
	local c = u._gridCell or 0
	if c <= 0 then
		return
	end
	local bucket = self.unitGrid[c]
	if bucket ~= nil then
		for i = #bucket, 1, -1 do
			if bucket[i] == u then
				local n = #bucket
				bucket[i] = bucket[n]
				bucket[n] = nil
				break
			end
		end
	end
	u._gridCell = 0
end

function SimEngine:_GridUpdatePos(u: any, nx: number, ny: number)
	u.x = nx
	u.y = ny
	local nc = self:_GridCellIndex(nx, ny)
	if nc ~= u._gridCell then
		self:_GridRemove(u)
		u._gridCell = nc
		local bucket = self.unitGrid[nc]
		if bucket == nil then
			bucket = {}
			self.unitGrid[nc] = bucket
		end
		table.insert(bucket, u)
	end
end

function SimEngine:_ForUnitsInRadius(cx: number, cy: number, radius: number, fn: (any) -> boolean?)
	local minGX = math.clamp(bit32.rshift(math.max(0, math.floor(cx - radius)), GRID_SHIFT), 0, self.gridCols - 1)
	local maxGX = math.clamp(bit32.rshift(math.max(0, math.ceil(cx + radius)), GRID_SHIFT), 0, self.gridCols - 1)
	local minGY = math.clamp(bit32.rshift(math.max(0, math.floor(cy - radius)), GRID_SHIFT), 0, self.gridRows - 1)
	local maxGY = math.clamp(bit32.rshift(math.max(0, math.ceil(cy + radius)), GRID_SHIFT), 0, self.gridRows - 1)
	local rSq = radius * radius
	for gy = minGY, maxGY do
		local base = gy * self.gridCols
		for gx = minGX, maxGX do
			local bucket = self.unitGrid[base + gx + 1]
			if bucket ~= nil then
				for i = 1, #bucket do
					local u = bucket[i]
					if u ~= nil and u.active then
						local dx = u.x - cx
						local dy = u.y - cy
						if dx * dx + dy * dy <= rSq then
							if fn(u) == true then
								return
							end
						end
					end
				end
			end
		end
	end
end

function SimEngine:_CachedWaterPath(startRef: number, goalRef: number, maxNodes: number): { number }?
	local key = tostring(startRef) .. ":" .. tostring(goalRef)
	local cached = self.sharedWaterCache[key]
	if cached ~= nil then
		return cached
	end
	local map = self.map
	local path = MapCodec.FindWaterPath(map, startRef, goalRef, math.min(maxNodes, 2600))
	if path == nil then
		local sw = if MapCodec.IsWater(map, startRef) then startRef else MapCodec.AdjacentWater(map, startRef)
		local dw = if MapCodec.IsWater(map, goalRef) then goalRef else MapCodec.AdjacentWater(map, goalRef)
		if sw ~= nil and dw ~= nil and MapCodec.SameWaterBody(map, sw, dw) then
			local w, h = map.width, map.height
			local sx, sy = sw % w, math.floor(sw / w)
			local gx, gy = dw % w, math.floor(dw / w)
			local dx = gx - sx
			if map.wrapX then
				if dx > w * 0.5 then
					dx -= w
				elseif dx < -w * 0.5 then
					dx += w
				end
			end
			local dy = gy - sy
			local steps = math.max(2, math.ceil(math.sqrt(dx * dx + dy * dy)))
			local built = table.create(steps + 2)
			table.insert(built, startRef)
			for s = 1, steps - 1 do
				local t = s / steps
				local px = sx + dx * t
				if map.wrapX then
					px = px % w
				end
				local ix = math.clamp(math.floor(px + 0.5), 0, w - 1)
				local iy = math.clamp(math.floor(sy + dy * t + 0.5), 0, h - 1)
				table.insert(built, iy * w + ix)
			end
			table.insert(built, goalRef)
			path = built
		end
	end
	if path ~= nil then
		if self.waterCacheCount >= 512 then
			table.clear(self.sharedWaterCache)
			self.waterCacheCount = 0
		end
		self.sharedWaterCache[key] = path
		self.waterCacheCount += 1
	end
	return path
end

function SimEngine:_AssignTeam(index: number, playerType: Types.PlayerType): string?
	local cfg: GameConfig = self.config
	if cfg.mode ~= "Teams" then
		return nil
	end
	if cfg.numTeams == -1 then
		return if playerType == "Human" then "Humans" else "Nations"
	end
	local count = math.clamp(cfg.numTeams, 2, #Theme.TeamOrder)
	return Theme.TeamOrder[((index - 1) % count) + 1]
end

function SimEngine:_AddParticipant(info: {
	userId: number,
	playerType: Types.PlayerType,
	name: string,
	flag: string,
	colorHex: string,
	patternId: string,
	prefX: number,
	prefY: number,
	teamIndex: number,
})
	self.nextSmallId += 1
	local sid = self.nextSmallId
	local team = self:_AssignTeam(info.teamIndex, info.playerType)
	local finalColor = info.colorHex
	if team ~= nil and Theme.TeamColors[team] ~= nil then
		finalColor = Theme.TeamColors[team]
	end

	local aiCadence = 12
	if info.playerType == "Bot" then
		aiCadence = 18
	elseif self.config.difficulty == "Easy" then
		aiCadence = 16
	elseif self.config.difficulty == "Medium" then
		aiCadence = 12
	elseif self.config.difficulty == "Hard" then
		aiCadence = 9
	else
		aiCadence = 6
	end

	local startGold = if info.playerType == "Bot" then 0 else self.config.startingGold
	if info.playerType == "Human" and self.config.infiniteGold then
		startGold = 999_999_999
	end

	local p = {
		smallId = sid,
		userId = info.userId,
		playerType = info.playerType,
		name = info.name,
		flag = info.flag,
		colorHex = finalColor,
		patternId = info.patternId,
		team = team,
		alive = true,
		hasSpawned = false,
		spawnX = info.prefX,
		spawnY = info.prefY,
		labelX = math.max(0, info.prefX),
		labelY = math.max(0, info.prefY),
		labelSpan = 16,
		tilesOwned = 0,
		tilesPeak = 0,
		troops = Config.StartingManpower(info.playerType, self.config),
		gold = startGold,
		goldEarned = startGold,
		isTraitor = false,
		traitorUntilTick = -1,
		isDoomed = false,
		doomWarnStartTick = -1,
		spawnImmunityUntil = 0,
		allies = {} :: { [number]: number },
		embargoes = {} :: { [number]: boolean },
		relations = {} :: { [number]: number },
		targetedBy = {} :: { [number]: number },
		emoji = nil :: string?,
		emojiUntilTick = -1,
		lastDonateTick = -999,
		lastTargetTick = -999,
		lastDeleteTick = -999,
		lastAllianceReqTick = -999,
		lastEmojiTick = -999,
		nukesSent = 0,
		deathNotified = false,
		survivedTicks = 0,
		borderSet = {} :: { [number]: number },
		borderList = {} :: { number },
		unitCounts = {} :: { [string]: number },
		cityLevels = 0,
		portLevels = 0,
		factoryLevels = 0,
		defensePosts = {} :: { any },
		aiCadence = aiCadence,
		aiOffset = sid % aiCadence,
		aiTriggerRatio = 0.50 + ((sid * 7) % 15) / 100,
	}

	table.insert(self.playersList, p)
	self.playersBySmallId[sid] = p
	if info.userId > 0 then
		self.playersByUserId[info.userId] = p
	end
	self.alertsByPlayer[sid] = {}
	return p
end

function SimEngine:_FindRandomUnclaimedLand(minDistSq: number): (number, number)
	local map = self.map
	local w, h = map.width, map.height
	for attempt = 1, 260 do
		local x = self:_RandInt(4, math.max(4, w - 5))
		local y = self:_RandInt(4, math.max(4, h - 5))
		local ref = y * w + x
		if MapCodec.IsPlayableLand(map, ref) and MapCodec.GetOwner(map, ref) == 0 then
			local ok = true
			if attempt < 180 and minDistSq > 0 then
				for _, other in ipairs(self.playersList) do
					if other.spawnX >= 0 then
						local dx = other.spawnX - x
						local dy = other.spawnY - y
						if dx * dx + dy * dy < minDistSq then
							ok = false
							break
						end
					end
				end
			end
			if ok then
				return x, y
			end
		end
	end
	local startRef = self:_RandInt(0, map.size - 1)
	for step = 0, map.size - 1, 7 do
		local ref = (startRef + step) % map.size
		if MapCodec.IsPlayableLand(map, ref) and MapCodec.GetOwner(map, ref) == 0 then
			return ref % w, math.floor(ref / w)
		end
	end
	return math.floor(w / 2), math.floor(h / 2)
end

function SimEngine:_InitParticipants(humanConfigs: { any })
	local teamIdx = 0
	local sf = Config.MapScaleFactor(self.map.width)
	local baseSep = math.max(18, math.floor(26 * sf))

	for _, hc in ipairs(humanConfigs) do
		teamIdx += 1
		local sx, sy = -1, -1
		if self.config.randomSpawn then
			sx, sy = self:_FindRandomUnclaimedLand(baseSep * baseSep)
		end
		self:_AddParticipant({
			userId = hc.userId,
			playerType = "Human",
			name = hc.name,
			flag = hc.flag or "in",
			colorHex = hc.colorHex or Theme.HumanColors[1],
			patternId = hc.patternId or "none",
			prefX = sx,
			prefY = sy,
			teamIndex = teamIdx,
		})
	end

	-- Full-Scale Sovereign Nations (`ALL 72` on World, `71` on NorthAmerica, up to `90` on GiantWorldMap!)
	if self.config.spawnNations then
		local nations = self.rawMap.nations or {}
		local ordered = table.clone(nations)
		table.sort(ordered, function(a, b)
			return (a.strength or 1) > (b.strength or 1)
		end)
		local minSepSq = math.max(100, math.floor(16 * sf) ^ 2)
		local maxNations = if self.isPreview then 48 else 90
		local addedNations = 0
		for _, nat in ipairs(ordered) do
			if addedNations >= maxNations then
				break
			end
			local nx, ny = nat.x, nat.y
			if self.config.randomSpawn or nx < 0 or ny < 0 then
				nx, ny = self:_FindRandomUnclaimedLand(minSepSq)
			end
			local tooClose = false
			for _, existing in ipairs(self.playersList) do
				if existing.spawnX >= 0 then
					local dx = existing.spawnX - nx
					local dy = existing.spawnY - ny
					if dx * dx + dy * dy < minSepSq then
						tooClose = true
						break
					end
				end
			end
			if not tooClose then
				addedNations += 1
				teamIdx += 1
				self:_AddParticipant({
					userId = -addedNations,
					playerType = "Nation",
					name = nat.name,
					flag = nat.flag or "",
					colorHex = Theme.NationColors[((addedNations - 1) % #Theme.NationColors) + 1],
					patternId = "none",
					prefX = nx,
					prefY = ny,
					teamIndex = teamIdx,
				})
			end
		end
	end

	local botTarget = if self.isPreview then 14 else math.clamp(self.config.bots, 0, 120)
	local botSepSq = math.max(400, math.floor(42 * sf) ^ 2)
	for b = 1, botTarget do
		local bx, by = self:_FindRandomUnclaimedLand(botSepSq)
		local bName = TRIBE_PREFIXES[((b - 1) % #TRIBE_PREFIXES) + 1]
			.. " "
			.. TRIBE_SUFFIXES[(math.floor((b - 1) / #TRIBE_PREFIXES) % #TRIBE_SUFFIXES) + 1]
		if b > #TRIBE_PREFIXES then
			bName = bName .. " " .. tostring(math.ceil(b / #TRIBE_PREFIXES))
		end
		teamIdx += 1
		self:_AddParticipant({
			userId = -(1000 + b),
			playerType = "Bot",
			name = bName,
			flag = "",
			colorHex = Theme.BotColors[((b - 1) % #Theme.BotColors) + 1],
			patternId = "none",
			prefX = bx,
			prefY = by,
			teamIndex = teamIdx,
		})
	end
end

function SimEngine:ChooseSpawn(userId: number, x: number, y: number): boolean
	if not self.inSpawnPhase or self.config.randomSpawn then
		return false
	end
	if not Config.IsFiniteNumber(x) or not Config.IsFiniteNumber(y) then
		return false
	end
	local p = self.playersByUserId[userId]
	if p == nil then
		return false
	end
	local ix = math.clamp(math.floor(x), 0, self.map.width - 1)
	local iy = math.clamp(math.floor(y), 0, self.map.height - 1)
	local ref = iy * self.map.width + ix
	if not MapCodec.IsPlayableLand(self.map, ref) then
		return false
	end
	p.spawnX = ix
	p.spawnY = iy
	p.labelX = ix
	p.labelY = iy
	return true
end

local _ENQ_STACK = table.create(32, 0)
local _ENQ_NBUF1 = { 0, 0, 0, 0 }
local _ENQ_NBUF2 = { 0, 0, 0, 0 }

function SimEngine:_UpdateBorderForTile(ref: number)
	local map = self.map
	local ownerBuf = map.owner
	local oid = buffer.readu16(ownerBuf, ref * 2)
	if oid == 0 then
		return
	end
	local p = self.playersBySmallId[oid]
	if p == nil then
		return
	end
	local w = map.width
	local x = ref % w
	local y = (ref - x) / w
	local isBorder = false
	if y == 0 or y == map.height - 1 then
		isBorder = true
	else
		local lx = if x > 0 then x - 1 elseif map.wrapX then w - 1 else -1
		local rx = if x < w - 1 then x + 1 elseif map.wrapX then 0 else -1
		if lx < 0 or rx < 0 then
			isBorder = true
		elseif
			buffer.readu16(ownerBuf, (ref - w) * 2) ~= oid
			or buffer.readu16(ownerBuf, (ref + w) * 2) ~= oid
			or buffer.readu16(ownerBuf, (y * w + lx) * 2) ~= oid
			or buffer.readu16(ownerBuf, (y * w + rx) * 2) ~= oid
		then
			isBorder = true
		end
	end
	local curIdx = p.borderSet[ref]
	if isBorder and curIdx == nil then
		local newIdx = #p.borderList + 1
		p.borderList[newIdx] = ref
		p.borderSet[ref] = newIdx
	elseif (not isBorder) and curIdx ~= nil then
		local lastIdx = #p.borderList
		local lastRef = p.borderList[lastIdx]
		p.borderList[curIdx] = lastRef
		p.borderSet[lastRef] = curIdx
		p.borderList[lastIdx] = nil
		p.borderSet[ref] = nil
	end
end

function SimEngine:ConquerTile(newOwnerId: number, ref: number)
	local map = self.map
	if not MapCodec.IsPlayableLand(map, ref) then
		return
	end
	local oldOwnerId = MapCodec.GetOwner(map, ref)
	if oldOwnerId == newOwnerId then
		return
	end

	if oldOwnerId > 0 then
		local oldP = self.playersBySmallId[oldOwnerId]
		if oldP ~= nil then
			oldP.tilesOwned = math.max(0, oldP.tilesOwned - 1)
			local bIdx = oldP.borderSet[ref]
			if bIdx ~= nil then
				local lastIdx = #oldP.borderList
				local lastRef = oldP.borderList[lastIdx]
				oldP.borderList[bIdx] = lastRef
				oldP.borderSet[lastRef] = bIdx
				oldP.borderList[lastIdx] = nil
				oldP.borderSet[ref] = nil
			end
			if oldP.tilesOwned == 0 and oldP.hasSpawned and oldP.alive then
				oldP.alive = false
			end
		end
	end

	MapCodec.SetOwner(map, ref, newOwnerId)

	if newOwnerId > 0 then
		local newP = self.playersBySmallId[newOwnerId]
		if newP ~= nil then
			newP.tilesOwned += 1
			if newP.tilesOwned > newP.tilesPeak then
				newP.tilesPeak = newP.tilesOwned
			end
		end
		if MapCodec.HasFallout(map, ref) and MapCodec.SetFallout(map, ref, false) then
			self.falloutDeltaCount += 1
			self.falloutDeltaRefs[self.falloutDeltaCount] = ref
			self.falloutDeltaStates[self.falloutDeltaCount] = 0
		end
	end

	local unitOnTile = self.unitsByTile[ref]
	if unitOnTile ~= nil and unitOnTile.active then
		if newOwnerId == 0 then
			self:_RemoveUnit(unitOnTile)
		elseif CAPTURABLE_STRUCTURES[unitOnTile.unitType] then
			self:_TransferStructureOwner(unitOnTile, newOwnerId)
		end
	end

	self.deltaCount += 1
	self.deltaRefs[self.deltaCount] = ref
	self.deltaOwners[self.deltaCount] = newOwnerId

	self:_UpdateBorderForTile(ref)
	local w = map.width
	local x = ref % w
	local y = (ref - x) / w
	local lx = if x > 0 then x - 1 elseif map.wrapX then w - 1 else -1
	if lx >= 0 then
		self:_UpdateBorderForTile(y * w + lx)
	end
	local rx = if x < w - 1 then x + 1 elseif map.wrapX then 0 else -1
	if rx >= 0 then
		self:_UpdateBorderForTile(y * w + rx)
	end
	if y > 0 then
		self:_UpdateBorderForTile(ref - w)
	end
	if y < map.height - 1 then
		self:_UpdateBorderForTile(ref + w)
	end
end

function SimEngine:_FinalizeSpawns()
	local map = self.map
	local w, h = map.width, map.height
	local r = math.max(5, math.floor(7 * Config.MapScaleFactor(w) + 0.5))
	local rSq = r * r

	for _, p in ipairs(self.playersList) do
		if p.spawnX < 0 or p.spawnY < 0 or MapCodec.GetOwner(map, p.spawnY * w + p.spawnX) ~= 0 then
			p.spawnX, p.spawnY = self:_FindRandomUnclaimedLand(160)
		end
		p.labelX = p.spawnX
		p.labelY = p.spawnY
		p.labelSpan = r * 2
		p.hasSpawned = true
		p.spawnImmunityUntil = self.ticks + Config.SPAWN_IMMUNITY_TICKS

		for dy = -r, r do
			for dx = -r, r do
				if dx * dx + dy * dy <= rSq then
					local tx = if map.wrapX then ((p.spawnX + dx) % w) else (p.spawnX + dx)
					local ty = p.spawnY + dy
					if tx >= 0 and tx < w and ty >= 0 and ty < h then
						local ref = ty * w + tx
						if MapCodec.IsPlayableLand(map, ref) and MapCodec.GetOwner(map, ref) == 0 then
							self:ConquerTile(p.smallId, ref)
						end
					end
				end
			end
		end

		if p.tilesOwned == 0 then
			p.alive = false
		end
	end
end

function SimEngine:AreFriendly(a: any, b: any): boolean
	if a == nil or b == nil then
		return false
	end
	if a.smallId == b.smallId then
		return true
	end
	if a.team ~= nil and a.team == b.team then
		return true
	end
	local expTick = a.allies[b.smallId]
	return expTick ~= nil and expTick > self.ticks
end

function SimEngine:GetMaxTroops(p: any): number
	return Config.MaxTroops(p.tilesOwned, p.cityLevels, p.playerType, self.config, self.map.width)
end

function SimEngine:PushEvent(kind: string, text: string, colorHex: string, x: number?, y: number?)
	self.nextEventId += 1
	table.insert(self.events, {
		id = self.nextEventId,
		kind = kind :: any,
		text = text,
		colorHex = colorHex,
		targetX = x,
		targetY = y,
		tick = self.ticks,
	})
	if #self.events > 28 then
		table.remove(self.events, 1)
	end
end

function SimEngine:PushAlert(recipientSmallId: number, alert: Types.ActionableAlert)
	local list = self.alertsByPlayer[recipientSmallId]
	if list == nil then
		return
	end
	for _, existing in ipairs(list) do
		if existing.kind == alert.kind and existing.fromSmallId == alert.fromSmallId and alert.kind ~= "NukeInbound" then
			return
		end
	end
	table.insert(list, alert)
	if #list > 8 then
		table.remove(list, 1)
	end
end

-- Iterative, zero-allocation concave-pocket frontier enqueue (`ZERO GC churn or stack overflow on 8M-pixel maps!`)
function SimEngine:_EnqueueAttackNeighbors(atk: any, rootTile: number, basePrio: number?)
	local map = self.map
	local ownerBuf = map.owner
	local terrainBuf = map.terrain
	local stack = _ENQ_STACK
	local nbuf = _ENQ_NBUF1
	local nbuf2 = _ENQ_NBUF2
	stack[1] = rootTile
	local stackTop = 1
	local iterGuard = 0
	local targetId = atk.targetSmallId
	local attackerId = atk.attackerSmallId
	local pBase = basePrio or self.ticks

	while stackTop > 0 and iterGuard < 24 do
		iterGuard += 1
		local tile = stack[stackTop]
		stackTop -= 1

		local n = MapCodec.Neighbors4(map, tile, nbuf)
		for i = 1, n do
			local nb = nbuf[i]
			if buffer.readu16(ownerBuf, nb * 2) == targetId then
				local tb = buffer.readu8(terrainBuf, nb)
				if bit32.band(tb, 0x80) ~= 0 then
					local ownedByMe = 0
					local nonEnemySides = 0
					local n2 = MapCodec.Neighbors4(map, nb, nbuf2)
					for j = 1, n2 do
						local nb2 = nbuf2[j]
						local o2 = buffer.readu16(ownerBuf, nb2 * 2)
						if o2 == attackerId then
							ownedByMe += 1
							nonEnemySides += 1
						elseif bit32.band(buffer.readu8(terrainBuf, nb2), 0x80) == 0 then
							nonEnemySides += 1
						end
					end
					-- True surrounded 1-tile enclave pocket only (`nonEnemySides >= 4`); never square-fill diagonal arcs!
					if nonEnemySides >= 4 and ownedByMe >= 1 and atk.troops >= 2 then
						self:ConquerTile(attackerId, nb)
						stackTop += 1
						stack[stackTop] = nb
						continue
					end
					local elev = bit32.band(tb, 0x1F)
					local stepCost = if elev >= 20 then 4.2 elseif elev >= 11 then 2.1 else 1.0
					local prio = pBase + stepCost + self:_Rand() * 2.4 - (ownedByMe - 1) * 0.35
					if not atk.inHeap[nb] then
						atk.inHeap[nb] = true
						atk.borderCount += 1
						atk.heap:enqueue(nb, prio)
					elseif ownedByMe >= 3 then
						atk.heap:enqueue(nb, prio)
					end
				end
			end
		end
	end
end

function SimEngine:StartLandAttack(attacker: any, targetSmallId: number, requestedTroops: number, sourceTile: number?)
	if self.inSpawnPhase or not attacker.alive or not Config.IsFiniteNumber(requestedTroops) then
		return
	end
	if targetSmallId == attacker.smallId then
		return
	end
	local targetPlayer = if targetSmallId > 0 then self.playersBySmallId[targetSmallId] else nil
	if targetPlayer ~= nil then
		if not targetPlayer.alive or self:AreFriendly(attacker, targetPlayer) then
			return
		end
		if self.ticks < targetPlayer.spawnImmunityUntil then
			return
		end
	end

	local sendTroops = math.floor(math.min(attacker.troops, math.max(0, requestedTroops)))
	if sendTroops < 5 then
		return
	end
	attacker.troops -= sendTroops

	if targetPlayer ~= nil then
		targetPlayer.embargoes[attacker.smallId] = true
		targetPlayer.relations[attacker.smallId] = math.max(-100, (targetPlayer.relations[attacker.smallId] or 0) - 70)
	end

	for _, existing in ipairs(self.attacks) do
		if existing.active and existing.attackerSmallId == targetSmallId and existing.targetSmallId == attacker.smallId then
			if existing.troops > sendTroops then
				existing.troops -= sendTroops
				return
			else
				sendTroops -= existing.troops
				existing.troops = 0
				existing.active = false
			end
		end
	end

	if sendTroops < 1 then
		return
	end

	if sourceTile == nil then
		for _, existing in ipairs(self.attacks) do
			if
				existing.active
				and not existing.isBoat
				and existing.attackerSmallId == attacker.smallId
				and existing.targetSmallId == targetSmallId
			then
				existing.troops += sendTroops
				for idx = #attacker.borderList, 1, -1 do
					local bRef = attacker.borderList[idx]
					if bRef ~= nil then
						self:_EnqueueAttackNeighbors(existing, bRef)
					end
				end
				return
			end
		end
	end

	self.nextAttackId += 1
	local atk = {
		id = self.nextAttackId,
		attackerSmallId = attacker.smallId,
		targetSmallId = targetSmallId,
		troops = sendTroops,
		active = true,
		retreating = false,
		isBoat = sourceTile ~= nil,
		inHeap = {} :: { [number]: boolean },
		borderCount = 0,
		heap = Heap.new(),
	}

	if sourceTile ~= nil then
		if MapCodec.GetOwner(self.map, sourceTile) == targetSmallId then
			atk.inHeap[sourceTile] = true
			atk.borderCount = 1
			atk.heap:enqueue(sourceTile, self.ticks)
		end
		self:_EnqueueAttackNeighbors(atk, sourceTile)
	else
		for idx = #attacker.borderList, 1, -1 do
			local bRef = attacker.borderList[idx]
			if bRef ~= nil then
				self:_EnqueueAttackNeighbors(atk, bRef)
			end
		end
	end

	if atk.heap:size() == 0 then
		attacker.troops = math.min(self:GetMaxTroops(attacker), attacker.troops + sendTroops)
		return
	end

	table.insert(self.attacks, atk)
end

function SimEngine:RetreatAttack(attacker: any, attackId: number?)
	for _, atk in ipairs(self.attacks) do
		if atk.active and atk.attackerSmallId == attacker.smallId and (attackId == nil or atk.id == attackId) then
			local malus = if atk.targetSmallId > 0 then (Config.RETREAT_MALUS_PERCENT / 100) else 0
			local survivors = math.floor(atk.troops * (1 - malus))
			attacker.troops = math.min(self:GetMaxTroops(attacker), attacker.troops + survivors)
			atk.troops = 0
			atk.active = false
		end
	end
end

function SimEngine:_TileProtectedByDefensePost(defender: any, ref: number): boolean
	local w = self.map.width
	local tx = ref % w
	local ty = math.floor(ref / w)
	local r = Config.DefensePostRangeScaled(w)
	local rSq = r * r
	for _, dp in ipairs(defender.defensePosts) do
		if dp.active and not dp.underConstruction then
			local dx = dp.x - tx
			local dy = dp.y - ty
			if dx * dx + dy * dy <= rSq then
				return true
			end
		end
	end
	return false
end

function SimEngine:_CheckEliminatePocketDefender(attacker: any, defender: any)
	local pocketCap = math.max(60, math.floor(140 * Config.MapScaleFactor(self.map.width)))
	if not defender.alive or defender.tilesOwned >= pocketCap then
		return
	end
	local plunder = if defender.playerType == "Human"
		then math.floor(defender.gold * 0.5)
		else math.floor(defender.gold)
	defender.gold = math.max(0, defender.gold - plunder)
	attacker.gold += plunder
	attacker.goldEarned += plunder

	local map = self.map
	-- Fast O(pocketSize) onion-peel border sweep instead of full 8M pixel scan!
	local guard = 0
	while defender.tilesOwned > 0 and #defender.borderList > 0 and guard < 4096 do
		guard += 1
		local bRef = defender.borderList[1]
		if MapCodec.GetOwner(map, bRef) == defender.smallId then
			self:ConquerTile(attacker.smallId, bRef)
		else
			self:_UpdateBorderForTile(bRef)
		end
	end
	if defender.tilesOwned > 0 then
		for ref = 0, map.size - 1 do
			if MapCodec.GetOwner(map, ref) == defender.smallId then
				self:ConquerTile(attacker.smallId, ref)
			end
		end
	end
	defender.troops = 0
	defender.alive = false

	if defender.playerType ~= "Bot" or attacker.playerType == "Human" then
		local goldTxt = if plunder > 0 then (" (+" .. Format.Gold(plunder) .. "g)") else ""
		self:PushEvent(
			"conquest",
			attacker.name .. " conquered " .. defender.name .. "!" .. goldTxt,
			attacker.colorHex,
			defender.labelX,
			defender.labelY
		)
	end
end

function SimEngine:_TickAttacks()
	local map = self.map
	local nbuf = { 0, 0, 0, 0 }
	local falloutShare = map.numFalloutTiles / math.max(1, map.numLandTiles)

	local writeIdx = 0
	for i = 1, #self.attacks do
		local atk = self.attacks[i]
		if atk.active then
			local attacker = self.playersBySmallId[atk.attackerSmallId]
			local defender = if atk.targetSmallId > 0 then self.playersBySmallId[atk.targetSmallId] else nil

			if attacker == nil or not attacker.alive then
				atk.active = false
			elseif defender ~= nil and (not defender.alive or self:AreFriendly(attacker, defender)) then
				attacker.troops = math.min(self:GetMaxTroops(attacker), attacker.troops + atk.troops)
				atk.active = false
			else
				local borderSize = math.max(8, atk.borderCount + self:_RandInt(0, 5))
				local tickBudget = 1.0
				local safety = 0

				-- Full-Scale 1x Frontier Expansion Throughput (`safety < 3600`!)
				while tickBudget > 0 and safety < 3600 do
					safety += 1
					if atk.troops < 1 then
						atk.active = false
						break
					end
					if atk.heap:size() == 0 then
						attacker.troops = math.min(self:GetMaxTroops(attacker), attacker.troops + atk.troops)
						atk.active = false
						break
					end

					local parentPrio = atk.heap:peekPriority() or self.ticks
					local tile = atk.heap:dequeue()
					if tile == nil then
						break
					end
					atk.inHeap[tile] = nil
					atk.borderCount = math.max(0, atk.borderCount - 1)

					if MapCodec.GetOwner(map, tile) ~= atk.targetSmallId or not MapCodec.IsPlayableLand(map, tile) then
						continue
					end

					local onBorder = atk.isBoat
					if not onBorder then
						local n = MapCodec.Neighbors4(map, tile, nbuf)
						for k = 1, n do
							if MapCodec.GetOwner(map, nbuf[k]) == attacker.smallId then
								onBorder = true
								break
							end
						end
					end
					if not onBorder then
						continue
					end
					atk.isBoat = false

					local hasDP = if defender ~= nil then self:_TileProtectedByDefensePost(defender, tile) else false
					local fRatio = if MapCodec.HasFallout(map, tile) then falloutShare else nil
					local atkLoss, defLoss, frac = Config.AttackLogic(
						MapCodec.TerrainKind(map, tile),
						atk.troops,
						attacker.playerType,
						attacker.tilesOwned,
						if defender ~= nil then defender.playerType else nil,
						if defender ~= nil then defender.tilesOwned else 0,
						if defender ~= nil then defender.troops else 0,
						if defender ~= nil then defender.isTraitor else false,
						hasDP,
						fRatio,
						borderSize,
						map.width
					)

					tickBudget -= math.max(0.0008, frac)
					atk.troops -= atkLoss
					if defender ~= nil then
						defender.troops = math.max(0, defender.troops - defLoss)
					end
					self:ConquerTile(attacker.smallId, tile)
					self:_EnqueueAttackNeighbors(atk, tile, parentPrio)

					if defender ~= nil then
						self:_CheckEliminatePocketDefender(attacker, defender)
						if not defender.alive then
							attacker.troops = math.min(self:GetMaxTroops(attacker), attacker.troops + math.max(0, atk.troops))
							atk.active = false
							break
						end
					end
				end
			end
		end

		if atk.active then
			writeIdx += 1
			self.attacks[writeIdx] = atk
		end
	end
	for j = #self.attacks, writeIdx + 1, -1 do
		self.attacks[j] = nil
	end
end

function SimEngine:LaunchBoatAttack(attacker: any, dstRef: number, requestedTroops: number): boolean
	if self.inSpawnPhase or not attacker.alive or not Config.IsFiniteNumber(requestedTroops) then
		return false
	end
	local map = self.map
	local w = map.width
	if dstRef < 0 or dstRef >= map.size then
		return false
	end
	if MapCodec.IsWater(map, dstRef) then
		local nbuf = { 0, 0, 0, 0 }
		local n = MapCodec.Neighbors4(map, dstRef, nbuf)
		for i = 1, n do
			if MapCodec.IsPlayableLand(map, nbuf[i]) then
				dstRef = nbuf[i]
				break
			end
		end
	end
	if not MapCodec.IsPlayableLand(map, dstRef) then
		return false
	end
	local dstOwnerId = MapCodec.GetOwner(map, dstRef)
	if dstOwnerId == attacker.smallId then
		return false
	end
	local dstPlayer = if dstOwnerId > 0 then self.playersBySmallId[dstOwnerId] else nil
	if dstPlayer ~= nil and self:AreFriendly(attacker, dstPlayer) then
		return false
	end
	if (attacker.unitCounts["TransportShip"] or 0) >= Config.BOAT_MAX_NUMBER then
		return false
	end

	local dstWater = MapCodec.AdjacentWater(map, dstRef)
	if dstWater == nil then
		return false
	end

	local tx, ty = dstRef % w, math.floor(dstRef / w)
	local bestShore: number? = nil
	local bestDistSq = math.huge
	for _, bRef in ipairs(attacker.borderList) do
		if MapCodec.IsShoreLand(map, bRef) then
			local sw = MapCodec.AdjacentWater(map, bRef)
			if sw ~= nil and MapCodec.SameWaterBody(map, sw, dstWater) then
				local bx, by = bRef % w, math.floor(bRef / w)
				local dSq = (bx - tx) * (bx - tx) + (by - ty) * (by - ty)
				if dSq < bestDistSq then
					bestDistSq = dSq
					bestShore = bRef
				end
			end
		end
	end
	if bestShore == nil then
		return false
	end

	local path = self:_CachedWaterPath(bestShore, dstRef, 60_000)
	if path == nil or #path < 2 then
		return false
	end

	local troops = math.floor(math.min(attacker.troops, math.max(0, requestedTroops)))
	if troops < 10 then
		return false
	end
	attacker.troops -= troops

	self:_CreateUnit(attacker, "TransportShip", bestShore % w, math.floor(bestShore / w), {
		dstX = tx,
		dstY = ty,
		dstRef = dstRef,
		path = path,
		pathIdx = 1,
		troops = troops,
		hp = 250,
		maxHp = 250,
	})
	return true
end

function SimEngine:RetreatBoats(attacker: any)
	for _, u in ipairs(self.units) do
		if u.active and u.ownerSmallId == attacker.smallId and u.unitType == "TransportShip" and not u.retreating then
			u.retreating = true
			local rev = {}
			for idx = u.pathIdx, 1, -1 do
				table.insert(rev, u.path[idx])
			end
			u.path = rev
			u.pathIdx = 1
		end
	end
end

function SimEngine:CanPlaceStructureNear(p: any, ref: number): boolean
	if MapCodec.GetOwner(self.map, ref) ~= p.smallId or not MapCodec.IsPlayableLand(self.map, ref) then
		return false
	end
	if self.unitsByTile[ref] ~= nil then
		return false
	end
	local w = self.map.width
	local x, y = ref % w, math.floor(ref / w)
	local minDist = Config.StructureMinDistScaled(w)
	local blocked = false
	self:_ForUnitsInRadius(x, y, minDist, function(u: any)
		if CAPTURABLE_STRUCTURES[u.unitType] then
			blocked = true
			return true
		end
		return false
	end)
	return not blocked
end

function SimEngine:FindFirstOwnedUnit(ownerSmallId: number, unitType: UnitType): any
	for _, u in ipairs(self.units) do
		if u.active and u.ownerSmallId == ownerSmallId and u.unitType == unitType and not u.underConstruction then
			return u
		end
	end
	return nil
end

function SimEngine:_AdjustPlayerStructureStats(p: any, unitType: string, levelDelta: number, unitObj: any, adding: boolean)
	if unitType == "City" then
		p.cityLevels = math.max(0, p.cityLevels + levelDelta)
	elseif unitType == "Port" then
		p.portLevels = math.max(0, p.portLevels + levelDelta)
	elseif unitType == "Factory" then
		p.factoryLevels = math.max(0, p.factoryLevels + levelDelta)
	elseif unitType == "DefensePost" then
		if adding then
			table.insert(p.defensePosts, unitObj)
		else
			for i, dp in ipairs(p.defensePosts) do
				if dp == unitObj then
					table.remove(p.defensePosts, i)
					break
				end
			end
		end
	end
end

function SimEngine:_CreateUnit(owner: any, unitType: UnitType, x: number, y: number, extra: { [string]: any }?): any
	self.nextUnitId += 1
	local buildTicks = Config.ConstructionTicks(unitType, self.config.instantBuild)
	local u: any = {
		id = self.nextUnitId,
		unitType = unitType,
		ownerSmallId = owner.smallId,
		x = x,
		y = y,
		_gridCell = 0,
		srcX = x,
		srcY = y,
		dstX = x,
		dstY = y,
		level = 1,
		hp = 100,
		maxHp = 100,
		veterancy = 0,
		kills = 0,
		underConstruction = buildTicks > 0,
		buildStartTick = self.ticks,
		buildEndTick = self.ticks + buildTicks,
		cooldownUntilTick = 0,
		lastShotTick = 0,
		troops = 0,
		progress = 0,
		active = true,
	}
	if extra ~= nil then
		for k, v in pairs(extra) do
			u[k] = v
		end
	end
	owner.unitCounts[unitType] = (owner.unitCounts[unitType] or 0) + 1
	if CAPTURABLE_STRUCTURES[unitType] then
		local ref = y * self.map.width + x
		self.unitsByTile[ref] = u
		if not u.underConstruction then
			self:_AdjustPlayerStructureStats(owner, unitType, u.level, u, true)
			if unitType == "City" or unitType == "Port" or unitType == "Factory" then
				self.railNetworkDirty = true
			end
		end
	end
	self:_GridInsert(u)
	table.insert(self.units, u)
	return u
end

function SimEngine:_RemoveUnit(u: any)
	if not u.active then
		return
	end
	u.active = false
	self:_GridRemove(u)
	local owner = self.playersBySmallId[u.ownerSmallId]
	if owner ~= nil then
		owner.unitCounts[u.unitType] = math.max(0, (owner.unitCounts[u.unitType] or 1) - 1)
		if CAPTURABLE_STRUCTURES[u.unitType] and not u.underConstruction then
			self:_AdjustPlayerStructureStats(owner, u.unitType, -u.level, u, false)
		end
	end
	if CAPTURABLE_STRUCTURES[u.unitType] then
		local ref = u.y * self.map.width + u.x
		if self.unitsByTile[ref] == u then
			self.unitsByTile[ref] = nil
		end
		if u.unitType == "City" or u.unitType == "Port" or u.unitType == "Factory" then
			self.railNetworkDirty = true
		end
	end
end

function SimEngine:_TransferStructureOwner(u: any, newOwnerId: number)
	local oldOwner = self.playersBySmallId[u.ownerSmallId]
	local newOwner = self.playersBySmallId[newOwnerId]
	if oldOwner == newOwner or newOwner == nil then
		return
	end
	if oldOwner ~= nil then
		oldOwner.unitCounts[u.unitType] = math.max(0, (oldOwner.unitCounts[u.unitType] or 1) - 1)
		if not u.underConstruction then
			self:_AdjustPlayerStructureStats(oldOwner, u.unitType, -u.level, u, false)
		end
	end
	u.ownerSmallId = newOwnerId
	newOwner.unitCounts[u.unitType] = (newOwner.unitCounts[u.unitType] or 0) + 1
	if not u.underConstruction then
		self:_AdjustPlayerStructureStats(newOwner, u.unitType, u.level, u, true)
	end
end

function SimEngine:UpgradeStructure(player: any, unitId: number): boolean
	for _, u in ipairs(self.units) do
		if u.active and u.id == unitId and u.ownerSmallId == player.smallId and CAPTURABLE_STRUCTURES[u.unitType] then
			if u.unitType == "DefensePost" or u.underConstruction or u.level >= 5 then
				return false
			end
			local cost = Config.UnitCost(
				u.unitType,
				player.unitCounts,
				self.mirvsLaunched,
				self.config.infiniteGold,
				player.playerType == "Human"
			)
			if player.gold < cost then
				return false
			end
			player.gold -= cost
			u.level += 1
			self:_AdjustPlayerStructureStats(player, u.unitType, 1, u, false)
			return true
		end
	end
	return false
end

function SimEngine:DeleteStructure(player: any, unitId: number): boolean
	if self.ticks - player.lastDeleteTick < Config.DELETE_UNIT_COOLDOWN_TICKS then
		return false
	end
	for _, u in ipairs(self.units) do
		if u.active and u.id == unitId and u.ownerSmallId == player.smallId and CAPTURABLE_STRUCTURES[u.unitType] then
			player.lastDeleteTick = self.ticks
			self:_RemoveUnit(u)
			return true
		end
	end
	return false
end

function SimEngine:BuildUnit(player: any, unitType: UnitType, targetRef: number): boolean
	if self.inSpawnPhase or not player.alive or not Config.IsFiniteNumber(targetRef) then
		return false
	end
	local map = self.map
	local w, h = map.width, map.height
	targetRef = math.floor(targetRef)
	if targetRef < 0 or targetRef >= map.size then
		return false
	end
	local tx, ty = targetRef % w, math.floor(targetRef / w)
	local cost = Config.UnitCost(
		unitType,
		player.unitCounts,
		self.mirvsLaunched,
		self.config.infiniteGold,
		player.playerType == "Human"
	)
	if player.gold < cost then
		return false
	end

	-- 1. Nuclear Missiles (AtomBomb, HydrogenBomb, MIRV)
	if unitType == "AtomBomb" or unitType == "HydrogenBomb" or unitType == "MIRV" then
		local bestSilo: any = nil
		local bestDist = math.huge
		for _, u in ipairs(self.units) do
			if
				u.active
				and u.ownerSmallId == player.smallId
				and u.unitType == "MissileSilo"
				and not u.underConstruction
				and self.ticks >= u.cooldownUntilTick
			then
				local dx, dy = u.x - tx, u.y - ty
				local d = dx * dx + dy * dy
				if d < bestDist then
					bestDist = d
					bestSilo = u
				end
			end
		end
		if bestSilo == nil then
			return false
		end
		if not self.config.waterNukes and not MapCodec.IsPlayableLand(map, targetRef) then
			local snapped: number? = nil
			for r = 1, 8 do
				for dy = -r, r do
					for dx = -r, r do
						local nx, ny = tx + dx, ty + dy
						if nx >= 0 and nx < w and ny >= 0 and ny < h then
							local cand = ny * w + nx
							if MapCodec.IsPlayableLand(map, cand) then
								snapped = cand
								break
							end
						end
					end
					if snapped ~= nil then
						break
					end
				end
				if snapped ~= nil then
					break
				end
			end
			if snapped == nil then
				return false
			end
			targetRef = snapped
			tx, ty = snapped % w, math.floor(snapped / w)
		end

		player.gold -= cost
		player.nukesSent += 1
		bestSilo.cooldownUntilTick = self.ticks + math.max(15, math.floor(Config.SILO_COOLDOWN_TICKS / bestSilo.level))

		local dist = math.sqrt((bestSilo.x - tx) * (bestSilo.x - tx) + (bestSilo.y - ty) * (bestSilo.y - ty))
		local speed = (if unitType == "MIRV" then 11.0 else 8.0) * Config.MapScaleFactor(w)
		local flightTicks = math.clamp(math.ceil(dist / math.max(3.5, speed)), 20, 140)

		if unitType == "MIRV" then
			self.mirvsLaunched += 1
			local sepY = math.max(4, ty - math.floor(65 * Config.MapScaleFactor(w)))
			local sepX = math.floor((bestSilo.x + tx) * 0.5)
			local nukeUnit = self:_CreateUnit(player, "MIRV", bestSilo.x, bestSilo.y, {
				srcX = bestSilo.x,
				srcY = bestSilo.y,
				dstX = sepX,
				dstY = sepY,
				realTargetX = tx,
				realTargetY = ty,
				targetSmallId = MapCodec.GetOwner(map, targetRef),
				startTick = self.ticks,
				endTick = self.ticks + flightTicks,
			})
			local victimId = MapCodec.GetOwner(map, targetRef)
			local victim = if victimId > 0 then self.playersBySmallId[victimId] else nil
			self:PushEvent(
				"nuke",
				"☄️ " .. player.name .. " LAUNCHED A MIRV" .. (if victim then (" AT " .. victim.name) else "") .. "!",
				"#ef4444",
				tx,
				ty
			)
			if victim ~= nil and victim.smallId ~= player.smallId then
				if player.allies[victim.smallId] ~= nil then
					self:BreakAlliance(player, victim)
				end
				self.nextAlertId += 1
				self:PushAlert(victim.smallId, {
					id = self.nextAlertId,
					kind = "NukeInbound",
					fromSmallId = player.smallId,
					fromName = player.name,
					unitType = "MIRV",
					targetX = tx,
					targetY = ty,
					expiresTick = nukeUnit.endTick,
				})
			end
			return true
		else
			local nukeUnit = self:_CreateUnit(player, unitType, bestSilo.x, bestSilo.y, {
				srcX = bestSilo.x,
				srcY = bestSilo.y,
				dstX = tx,
				dstY = ty,
				startTick = self.ticks,
				endTick = self.ticks + flightTicks,
			})
			local victimId = MapCodec.GetOwner(map, targetRef)
			local victim = if victimId > 0 then self.playersBySmallId[victimId] else nil
			local icon = if unitType == "HydrogenBomb" then "💥" else "☢️"
			local prettyUnit = if unitType == "HydrogenBomb" then "a Hydrogen Bomb" else "an Atom Bomb"
			self:PushEvent(
				"nuke",
				icon .. " " .. player.name .. " launched " .. prettyUnit .. (if victim then (" at " .. victim.name) else "") .. "!",
				"#f97316",
				tx,
				ty
			)
			if victim ~= nil and victim.smallId ~= player.smallId then
				if player.allies[victim.smallId] ~= nil then
					self:BreakAlliance(player, victim)
				end
				self.nextAlertId += 1
				self:PushAlert(victim.smallId, {
					id = self.nextAlertId,
					kind = "NukeInbound",
					fromSmallId = player.smallId,
					fromName = player.name,
					unitType = unitType,
					targetX = tx,
					targetY = ty,
					expiresTick = nukeUnit.endTick,
				})
			end
			return true
		end
	end

	-- 2. Warship
	if unitType == "Warship" then
		local bestPort: any = nil
		local bestDist = math.huge
		for _, u in ipairs(self.units) do
			if u.active and u.ownerSmallId == player.smallId and u.unitType == "Port" and not u.underConstruction then
				local dx, dy = u.x - tx, u.y - ty
				local d = dx * dx + dy * dy
				if d < bestDist then
					bestDist = d
					bestPort = u
				end
			end
		end
		if bestPort == nil then
			return false
		end
		local spawnWater = MapCodec.AdjacentWater(map, bestPort.y * w + bestPort.x)
		if spawnWater == nil then
			return false
		end
		local patrolRef = if MapCodec.IsWater(map, targetRef) then targetRef else spawnWater
		player.gold -= cost
		local wx, wy = spawnWater % w, math.floor(spawnWater / w)
		local path = self:_CachedWaterPath(spawnWater, patrolRef, 30_000) or { spawnWater }
		self:_CreateUnit(player, "Warship", wx, wy, {
			patrolX = patrolRef % w,
			patrolY = math.floor(patrolRef / w),
			path = path,
			pathIdx = 1,
			hp = Config.WARSHIP_BASE_HP,
			maxHp = Config.WARSHIP_BASE_HP,
		})
		return true
	end

	-- 3. Port
	if unitType == "Port" then
		local chosenRef: number? = nil
		if MapCodec.GetOwner(map, targetRef) == player.smallId and MapCodec.IsShoreLand(map, targetRef) then
			chosenRef = targetRef
		else
			for r = 1, 10 do
				for dy = -r, r do
					for dx = -r, r do
						local nx, ny = tx + dx, ty + dy
						if nx >= 0 and nx < w and ny >= 0 and ny < h then
							local cand = ny * w + nx
							if MapCodec.GetOwner(map, cand) == player.smallId and MapCodec.IsShoreLand(map, cand) then
								chosenRef = cand
								break
							end
						end
					end
					if chosenRef ~= nil then
						break
					end
				end
				if chosenRef ~= nil then
					break
				end
			end
		end
		if chosenRef == nil or not self:CanPlaceStructureNear(player, chosenRef) then
			return false
		end
		player.gold -= cost
		self:_CreateUnit(player, "Port", chosenRef % w, math.floor(chosenRef / w), nil)
		return true
	end

	-- 4. Land Structures
	if CAPTURABLE_STRUCTURES[unitType] then
		local chosenRef: number? = nil
		if self:CanPlaceStructureNear(player, targetRef) then
			chosenRef = targetRef
		else
			for r = 1, 18 do
				for dy = -r, r, 2 do
					for dx = -r, r, 2 do
						local nx, ny = tx + dx, ty + dy
						if nx >= 0 and nx < w and ny >= 0 and ny < h then
							local cand = ny * w + nx
							if self:CanPlaceStructureNear(player, cand) then
								chosenRef = cand
								break
							end
						end
					end
					if chosenRef ~= nil then
						break
					end
				end
				if chosenRef ~= nil then
					break
				end
			end
		end
		if chosenRef == nil then
			return false
		end
		player.gold -= cost
		self:_CreateUnit(player, unitType, chosenRef % w, math.floor(chosenRef / w), nil)
		return true
	end

	return false
end

function SimEngine:MoveWarship(player: any, unitId: number, dstX: number, dstY: number): boolean
	local map = self.map
	local ix = math.clamp(math.floor(dstX), 0, map.width - 1)
	local iy = math.clamp(math.floor(dstY), 0, map.height - 1)
	local dstRef = iy * map.width + ix
	if not MapCodec.IsWater(map, dstRef) then
		return false
	end
	for _, u in ipairs(self.units) do
		if u.active and u.id == unitId and u.ownerSmallId == player.smallId and u.unitType == "Warship" then
			local curRef = math.floor(u.y) * map.width + math.floor(u.x)
			local path = self:_CachedWaterPath(curRef, dstRef, 30_000)
			if path ~= nil then
				u.patrolX = ix
				u.patrolY = iy
				u.path = path
				u.pathIdx = 1
				return true
			end
		end
	end
	return false
end

function SimEngine:_DetonateNuke(nuke: any)
	local map = self.map
	local w, h = map.width, map.height
	local cx, cy = math.clamp(math.floor(nuke.dstX), 0, w - 1), math.clamp(math.floor(nuke.dstY), 0, h - 1)
	local innerR, outerR = Config.NukeRadii(nuke.unitType, w)
	local innerSq = innerR * innerR
	local outerSq = outerR * outerR

	table.insert(self.explosions, {
		x = cx,
		y = cy,
		radius = outerR,
		kind = nuke.unitType,
	})

	local hitCountByOwner: { [number]: number } = {}
	local y0 = math.max(0, cy - outerR)
	local y1 = math.min(h - 1, cy + outerR)

	for py = y0, y1 do
		local dy = py - cy
		local rowOff = py * w
		for dxx = -outerR, outerR do
			local dSq = dxx * dxx + dy * dy
			if dSq <= outerSq then
				local px = if map.wrapX then ((cx + dxx) % w) else (cx + dxx)
				if px >= 0 and px < w and (dSq <= innerSq or self:_Rand() < 0.55) then
					local ref = rowOff + px
					if not MapCodec.IsImpassable(map, ref) then
						local prevOwner = MapCodec.GetOwner(map, ref)
						if prevOwner > 0 then
							hitCountByOwner[prevOwner] = (hitCountByOwner[prevOwner] or 0) + 1
							self:ConquerTile(0, ref)
						end
						if MapCodec.IsPlayableLand(map, ref) and MapCodec.SetFallout(map, ref, true) then
							if not self.inFalloutSet[ref] then
								self.inFalloutSet[ref] = true
								table.insert(self.activeFalloutRefs, ref)
							end
							self.falloutDeltaCount += 1
							self.falloutDeltaRefs[self.falloutDeltaCount] = ref
							self.falloutDeltaStates[self.falloutDeltaCount] = 1
						end
					end
				end
			end
		end
	end

	for oid, lostTiles in pairs(hitCountByOwner) do
		local victim = self.playersBySmallId[oid]
		if victim ~= nil and victim.alive then
			local prevTotal = math.max(1, victim.tilesOwned + lostTiles)
			local killFrac = math.min(0.85, (lostTiles / prevTotal) * 3.5)
			victim.troops = math.max(0, math.floor(victim.troops * (1 - killFrac)))
			local sender = self.playersBySmallId[nuke.ownerSmallId]
			if sender ~= nil and sender ~= victim then
				victim.relations[sender.smallId] = -100
			end
		end
	end
end

function SimEngine:_SeparateMIRV(mirvUnit: any)
	local map = self.map
	local w, h = map.width, map.height
	local sender = self.playersBySmallId[mirvUnit.ownerSmallId]
	if sender == nil then
		return
	end
	local targetId = mirvUnit.targetSmallId
	local candidateRefs = {}

	if targetId > 0 then
		local step = math.max(1, math.floor(map.size / 8000))
		for ref = 0, map.size - 1, step do
			if MapCodec.GetOwner(map, ref) == targetId then
				table.insert(candidateRefs, ref)
			end
		end
	end
	if #candidateRefs == 0 then
		local spread = math.max(45, math.floor(90 * Config.MapScaleFactor(w)))
		for _ = 1, 32 do
			local rx = math.clamp(mirvUnit.realTargetX + self:_RandInt(-spread, spread), 0, w - 1)
			local ry = math.clamp(mirvUnit.realTargetY + self:_RandInt(-spread, spread), 0, h - 1)
			if MapCodec.IsPlayableLand(map, ry * w + rx) then
				table.insert(candidateRefs, ry * w + rx)
			end
		end
	end

	if #candidateRefs > 0 then
		local warheadTotal = math.min(36, math.max(10, #candidateRefs))
		for k = 1, warheadTotal do
			local pick = candidateRefs[self:_RandInt(1, #candidateRefs)]
			local wx, wy = pick % w, math.floor(pick / w)
			self:_CreateUnit(sender, "MIRVWarhead", mirvUnit.x, mirvUnit.y, {
				srcX = mirvUnit.x,
				srcY = mirvUnit.y,
				dstX = wx,
				dstY = wy,
				startTick = self.ticks + (k % 8),
				endTick = self.ticks + 18 + (k % 14),
			})
		end
	end
end

function SimEngine:_RebuildRailNetwork()
	self.railNetworkDirty = false
	table.clear(self.railEdges)
	local stations = {}
	for _, u in ipairs(self.units) do
		if
			u.active
			and not u.underConstruction
			and (u.unitType == "City" or u.unitType == "Port" or u.unitType == "Factory")
		then
			table.insert(stations, u)
		end
	end
	for i = 1, #stations do
		stations[i].railLinks = {}
	end
	local sf = Config.MapScaleFactor(self.map.width)
	local minR = math.max(6, math.floor(Config.TRAIN_STATION_MIN_RANGE * sf))
	local maxR = math.max(60, math.floor(Config.TRAIN_STATION_MAX_RANGE * sf))
	local edgeBudget = 0
	for i = 1, #stations do
		if edgeBudget >= 45 then
			break
		end
		local a = stations[i]
		for j = i + 1, #stations do
			local b = stations[j]
			local dx, dy = a.x - b.x, a.y - b.y
			local dSq = dx * dx + dy * dy
			if dSq >= minR * minR and dSq <= maxR * maxR and #a.railLinks < 3 and #b.railLinks < 3 then
				local ownerA = self.playersBySmallId[a.ownerSmallId]
				local ownerB = self.playersBySmallId[b.ownerSmallId]
				if ownerA ~= nil and ownerB ~= nil and not ownerA.embargoes[ownerB.smallId] and not ownerB.embargoes[ownerA.smallId] then
					local path = MapCodec.FindLandRailPath(
						self.map,
						a.y * self.map.width + a.x,
						b.y * self.map.width + b.x,
						maxR
					)
					if path ~= nil and #path >= 2 then
						edgeBudget += 1
						table.insert(self.railEdges, path)
						table.insert(a.railLinks, { dest = b, path = path, forward = true })
						table.insert(b.railLinks, { dest = a, path = path, forward = false })
						if edgeBudget >= 45 then
							break
						end
					end
				end
			end
		end
	end
end

function SimEngine:_TickEconomySpawns()
	if self.ticks % 12 == 0 then
		local openPorts = {}
		for _, u in ipairs(self.units) do
			if u.active and not u.underConstruction and u.unitType == "Port" then
				table.insert(openPorts, u)
			end
		end
		if #openPorts >= 2 then
			for _ = 1, math.min(4, math.ceil(#openPorts / 3)) do
				local srcPort = openPorts[self:_RandInt(1, #openPorts)]
				local dstPort = openPorts[self:_RandInt(1, #openPorts)]
				if srcPort ~= dstPort and self.playersBySmallId[srcPort.ownerSmallId] ~= nil then
					local ownerA = self.playersBySmallId[srcPort.ownerSmallId]
					local ownerB = self.playersBySmallId[dstPort.ownerSmallId]
					if
						ownerA ~= nil
						and ownerB ~= nil
						and not ownerA.embargoes[ownerB.smallId]
						and not ownerB.embargoes[ownerA.smallId]
						and (ownerA.unitCounts["TradeShip"] or 0) < 8
					then
						local w = self.map.width
						local path = self:_CachedWaterPath(srcPort.y * w + srcPort.x, dstPort.y * w + dstPort.x, 45_000)
						if path ~= nil and #path >= 3 then
							local dist = math.sqrt((srcPort.x - dstPort.x) ^ 2 + (srcPort.y - dstPort.y) ^ 2)
							self:_CreateUnit(ownerA, "TradeShip", srcPort.x, srcPort.y, {
								dstX = dstPort.x,
								dstY = dstPort.y,
								dstPort = dstPort,
								dist = dist,
								path = path,
								pathIdx = 1,
								hp = 100,
								maxHp = 100,
							})
						end
					end
				end
			end
		end
	end

	if self.ticks % 16 == 4 then
		for _, u in ipairs(self.units) do
			if
				u.active
				and not u.underConstruction
				and u.unitType == "Factory"
				and u.railLinks ~= nil
				and #u.railLinks > 0
			then
				local owner = self.playersBySmallId[u.ownerSmallId]
				if owner ~= nil and (owner.unitCounts["Train"] or 0) < 6 and self:_Rand() < 0.45 then
					local link = u.railLinks[self:_RandInt(1, #u.railLinks)]
					local orderedPath = {}
					if link.forward then
						for i = 1, #link.path do
							orderedPath[i] = link.path[i]
						end
					else
						for i = #link.path, 1, -1 do
							table.insert(orderedPath, link.path[i])
						end
					end
					self:_CreateUnit(owner, "Train", u.x, u.y, {
						dstX = link.dest.x,
						dstY = link.dest.y,
						destStation = link.dest,
						path = orderedPath,
						pathIdx = 1,
						stops = 1,
					})
				end
			end
		end
	end
end

function SimEngine:_TickUnits()
	local map = self.map
	local w = map.width
	local sf = Config.MapScaleFactor(w)
	local warshipRange = Config.WarshipRangeScaled(w)
	local dpShellRange = Config.DefensePostShellRangeScaled(w)

	for _, u in ipairs(self.units) do
		if not u.active then
			continue
		end
		local owner = self.playersBySmallId[u.ownerSmallId]
		if owner == nil or not owner.alive then
			self:_RemoveUnit(u)
			continue
		end

		if u.underConstruction and self.ticks >= u.buildEndTick then
			u.underConstruction = false
			self:_AdjustPlayerStructureStats(owner, u.unitType, u.level, u, true)
			if u.unitType == "City" or u.unitType == "Port" or u.unitType == "Factory" then
				self.railNetworkDirty = true
			end
		end

		if u.unitType == "TransportShip" then
			local boatStep = math.max(2, math.floor(2.6 * sf + 0.5))
			u.pathIdx = math.min(#u.path, u.pathIdx + boatStep)
			local curRef = u.path[u.pathIdx]
			self:_GridUpdatePos(u, curRef % w, math.floor(curRef / w))
			if u.pathIdx >= #u.path then
				local survivors = u.troops
				self:_RemoveUnit(u)
				if u.retreating then
					owner.troops = math.min(self:GetMaxTroops(owner), owner.troops + survivors)
				else
					local dstOwnerId = MapCodec.GetOwner(map, u.dstRef)
					owner.troops += survivors
					self:StartLandAttack(owner, dstOwnerId, survivors, u.dstRef)
				end
			end
		elseif u.unitType == "TradeShip" then
			local shipStep = math.max(2, math.floor(2.0 * sf + 0.5))
			u.pathIdx = math.min(#u.path, u.pathIdx + shipStep)
			local curRef = u.path[u.pathIdx]
			self:_GridUpdatePos(u, curRef % w, math.floor(curRef / w))
			if u.pathIdx >= #u.path then
				local dstPort = u.dstPort
				local payout = Config.TradeShipGold(u.dist, w, self.config.goldMultiplier)
				owner.gold += payout
				owner.goldEarned += payout
				if dstPort ~= nil and dstPort.active then
					local dstOwner = self.playersBySmallId[dstPort.ownerSmallId]
					if dstOwner ~= nil and dstOwner.alive then
						dstOwner.gold += payout
						dstOwner.goldEarned += payout
					end
				end
				self:_RemoveUnit(u)
			end
		elseif u.unitType == "Train" then
			local stepN = math.max(2, math.floor(3.0 * sf + 0.5))
			u.pathIdx = math.min(#u.path, u.pathIdx + stepN)
			local curRef = u.path[u.pathIdx]
			self:_GridUpdatePos(u, curRef % w, math.floor(curRef / w))
			if u.pathIdx >= #u.path then
				local st = u.destStation
				if st ~= nil and st.active then
					local stOwner = self.playersBySmallId[st.ownerSmallId]
					if stOwner ~= nil and stOwner.alive then
						local rel: "self" | "team" | "ally" | "other" = "other"
						if stOwner.smallId == owner.smallId then
							rel = "self"
						elseif owner.team ~= nil and owner.team == stOwner.team then
							rel = "team"
						elseif self:AreFriendly(owner, stOwner) then
							rel = "ally"
						end
						local gold = Config.TrainGold(rel, u.stops, self.config.goldMultiplier)
						owner.gold += gold
						owner.goldEarned += gold
						if stOwner ~= owner then
							stOwner.gold += gold
							stOwner.goldEarned += gold
						end
					end
				end
				self:_RemoveUnit(u)
			end
		elseif u.unitType == "Warship" then
			local warStep = math.max(2, math.floor(3.0 * sf + 0.5))
			if u.path ~= nil and u.pathIdx < #u.path then
				u.pathIdx = math.min(#u.path, u.pathIdx + warStep)
				local curRef = u.path[u.pathIdx]
				self:_GridUpdatePos(u, curRef % w, math.floor(curRef / w))
			elseif self.ticks % 25 == (u.id % 25) then
				local angle = (self.ticks * 0.09 + u.id) % (math.pi * 2)
				local orbitR = math.max(12, math.floor(24 * sf))
				local ox = math.clamp(math.floor(u.patrolX + math.cos(angle) * orbitR), 0, w - 1)
				local oy = math.clamp(math.floor(u.patrolY + math.sin(angle) * orbitR), 0, map.height - 1)
				local oRef = oy * w + ox
				if MapCodec.IsWater(map, oRef) then
					local pth = MapCodec.FindWaterPath(map, math.floor(u.y) * w + math.floor(u.x), oRef, 1200)
					if pth ~= nil then
						u.path = pth
						u.pathIdx = 1
					end
				end
			end

			if u.hp < u.maxHp and owner.portLevels > 0 then
				u.hp = math.min(u.maxHp, u.hp + Config.WARSHIP_PASSIVE_HEAL)
			end

			-- Spatial O(1) Warship Piracy + Naval Combat!
			if self.ticks - u.lastShotTick >= Config.WARSHIP_SHELL_RATE_TICKS then
				local pirateR2 = math.max(256, (22 * sf) ^ 2)
				self:_ForUnitsInRadius(u.x, u.y, warshipRange, function(target: any)
					if target.ownerSmallId ~= owner.smallId then
						local tOwner = self.playersBySmallId[target.ownerSmallId]
						if tOwner ~= nil and not self:AreFriendly(owner, tOwner) then
							local dx, dy = target.x - u.x, target.y - u.y
							local dSq = dx * dx + dy * dy
							if target.unitType == "TradeShip" and dSq <= pirateR2 then
								local loot = Config.TradeShipGold(target.dist or 100, w, self.config.goldMultiplier)
								owner.gold += loot
								owner.goldEarned += loot
								self:_GrantVeterancyProgress(u, 2)
								self:_RemoveUnit(target)
								return true
							elseif target.unitType == "TransportShip" or target.unitType == "Warship" then
								u.lastShotTick = self.ticks
								local dmg = math.floor(Config.WARSHIP_SHELL_DAMAGE * (1 + u.veterancy * 0.2))
								target.hp -= dmg
								if target.hp <= 0 then
									self:_GrantVeterancyProgress(u, 4)
									self:_RemoveUnit(target)
								end
								return true
							end
						end
					end
					return false
				end)
			end
		elseif u.unitType == "DefensePost" and not u.underConstruction then
			-- Coastal Battery Shelling against hostile amphibious fleets!
			if self.ticks - u.lastShotTick >= Config.DEFENSE_POST_SHELL_RATE then
				self:_ForUnitsInRadius(u.x, u.y, dpShellRange, function(target: any)
					if target.ownerSmallId ~= owner.smallId and (target.unitType == "TransportShip" or target.unitType == "Warship") then
						local tOwner = self.playersBySmallId[target.ownerSmallId]
						if tOwner == nil or not self:AreFriendly(owner, tOwner) then
							u.lastShotTick = self.ticks
							target.hp -= 125
							if target.hp <= 0 then
								self:_RemoveUnit(target)
							end
							return true
						end
					end
					return false
				end)
			end
		elseif u.unitType == "SAMLauncher" and not u.underConstruction then
			-- Spatial O(1) SAM Lock Reservation (`targetedBySam` prevents duplicate interceptor waste!)
			if self.ticks >= u.cooldownUntilTick then
				local samR = Config.SamRangeScaled(u.level, w)
				self:_ForUnitsInRadius(u.x, u.y, samR, function(missile: any)
					if
						not missile.targetedBySam
						and (
							missile.unitType == "AtomBomb"
							or missile.unitType == "HydrogenBomb"
							or missile.unitType == "MIRVWarhead"
						)
					then
						local mOwner = self.playersBySmallId[missile.ownerSmallId]
						if mOwner == nil or not self:AreFriendly(owner, mOwner) then
							missile.targetedBySam = true
							u.cooldownUntilTick = self.ticks + Config.SAM_COOLDOWN_TICKS
							self:_CreateUnit(owner, "SAMMissile", u.x, u.y, {
								srcX = u.x,
								srcY = u.y,
								targetMissile = missile,
								startTick = self.ticks,
								endTick = self.ticks + 8,
							})
							return true
						end
					end
					return false
				end)
			end
		elseif u.unitType == "SAMMissile" then
			local m = u.targetMissile
			if m == nil or not m.active then
				self:_RemoveUnit(u)
			else
				local t = math.clamp((self.ticks - u.startTick) / math.max(1, u.endTick - u.startTick), 0, 1)
				u.progress = t
				self:_GridUpdatePos(u, u.srcX + (m.x - u.srcX) * t, u.srcY + (m.y - u.srcY) * t)
				if t >= 1 then
					self:_RemoveUnit(m)
					self:_RemoveUnit(u)
				end
			end
		elseif
			u.unitType == "AtomBomb"
			or u.unitType == "HydrogenBomb"
			or u.unitType == "MIRV"
			or u.unitType == "MIRVWarhead"
		then
			if self.ticks >= u.startTick then
				local dur = math.max(1, u.endTick - u.startTick)
				local t = math.clamp((self.ticks - u.startTick) / dur, 0, 1)
				u.progress = t
				local arcLift = math.sin(t * math.pi) * (if u.unitType == "MIRV" then 48 else 28)
				self:_GridUpdatePos(
					u,
					u.srcX + (u.dstX - u.srcX) * t,
					math.clamp(u.srcY + (u.dstY - u.srcY) * t - arcLift, 0, map.height - 1)
				)
				if t >= 1 then
					if u.unitType == "MIRV" then
						self:_SeparateMIRV(u)
					else
						self:_DetonateNuke(u)
					end
					self:_RemoveUnit(u)
				end
			end
		end
	end

	if self.ticks % 20 == 0 then
		local writeIdx = 0
		for i = 1, #self.units do
			local u = self.units[i]
			if u.active then
				writeIdx += 1
				self.units[writeIdx] = u
			end
		end
		for j = #self.units, writeIdx + 1, -1 do
			self.units[j] = nil
		end
	end
end

function SimEngine:_GrantVeterancyProgress(warship: any, pts: number)
	warship.kills = (warship.kills or 0) + pts
	local newVet = math.min(Config.WARSHIP_MAX_VETERANCY, math.floor(warship.kills / 12))
	if newVet > warship.veterancy then
		warship.veterancy = newVet
		warship.maxHp = math.floor(Config.WARSHIP_BASE_HP * (1 + newVet * (Config.WARSHIP_VET_BONUS_PCT / 100)))
		warship.hp = math.min(warship.maxHp, warship.hp + 200)
	end
end

function SimEngine:SendAllianceRequest(fromP: any, toP: any): boolean
	if self.config.disableAlliances or not fromP.alive or not toP.alive or self:AreFriendly(fromP, toP) then
		return false
	end
	if self.ticks - fromP.lastAllianceReqTick < 30 then
		return false
	end
	fromP.lastAllianceReqTick = self.ticks

	if toP.playerType == "Nation" then
		local rel = toP.relations[fromP.smallId] or 0
		if not fromP.isTraitor and rel > -30 and self:_Rand() < 0.72 then
			self:FormAlliance(fromP, toP)
			self:SetEmoji(toP, "🤝")
			return true
		else
			self:SetEmoji(toP, "👎")
			return false
		end
	elseif toP.playerType == "Bot" then
		return false
	end

	self.nextAlertId += 1
	self:PushAlert(toP.smallId, {
		id = self.nextAlertId,
		kind = "AllianceRequest",
		fromSmallId = fromP.smallId,
		fromName = fromP.name,
		expiresTick = self.ticks + Config.ALLIANCE_REQUEST_DURATION_TICKS,
	})
	return true
end

function SimEngine:FormAlliance(a: any, b: any)
	local durTicks = math.max(600, self.config.allianceDurationMinutes * 60 * Config.TICKS_PER_SECOND)
	a.allies[b.smallId] = self.ticks + durTicks
	b.allies[a.smallId] = self.ticks + durTicks
	a.embargoes[b.smallId] = nil
	b.embargoes[a.smallId] = nil
	a.relations[b.smallId] = math.min(100, (a.relations[b.smallId] or 0) + 50)
	b.relations[a.smallId] = math.min(100, (b.relations[a.smallId] or 0) + 50)
	self.railNetworkDirty = true
	self:PushEvent("alliance", "🤝 " .. a.name .. " allied with " .. b.name .. "!", "#4ade80", nil, nil)
end

function SimEngine:BreakAlliance(breaker: any, partner: any)
	if breaker.allies[partner.smallId] == nil then
		return
	end
	breaker.allies[partner.smallId] = nil
	partner.allies[breaker.smallId] = nil
	breaker.isTraitor = true
	breaker.traitorUntilTick = self.ticks + Config.TRAITOR_DURATION_TICKS
	partner.relations[breaker.smallId] = -100
	partner.embargoes[breaker.smallId] = true
	for _, other in ipairs(self.playersList) do
		if other ~= breaker then
			other.relations[breaker.smallId] = math.max(-100, (other.relations[breaker.smallId] or 0) - 45)
		end
	end
	self:PushEvent("betrayal", "💀 " .. breaker.name .. " BETRAYED " .. partner.name .. "!", "#ef4444", breaker.labelX, breaker.labelY)
end

function SimEngine:DonateResources(sender: any, recipient: any, kind: "gold" | "troops", amount: number): boolean
	if not sender.alive or not recipient.alive or sender == recipient or not Config.IsFiniteNumber(amount) then
		return false
	end
	if self.ticks - sender.lastDonateTick < 15 then
		return false
	end
	sender.lastDonateTick = self.ticks
	if kind == "gold" and self.config.donateGold then
		local amt = math.floor(math.min(sender.gold, math.max(0, amount)))
		if amt <= 0 then
			return false
		end
		sender.gold -= amt
		recipient.gold += amt
		recipient.relations[sender.smallId] = math.min(100, (recipient.relations[sender.smallId] or 0) + 25)
		self:PushEvent("donate", "💰 " .. sender.name .. " sent " .. Format.Gold(amt) .. " Gold to " .. recipient.name, "#f59e0b", nil, nil)
		return true
	elseif kind == "troops" and self.config.donateTroops then
		local amt = math.floor(math.min(sender.troops * 0.9, math.max(0, amount)))
		if amt <= 0 then
			return false
		end
		sender.troops -= amt
		recipient.troops = math.min(self:GetMaxTroops(recipient), recipient.troops + amt)
		recipient.relations[sender.smallId] = math.min(100, (recipient.relations[sender.smallId] or 0) + 25)
		self:PushEvent("donate", "⚔️ " .. sender.name .. " sent " .. Format.Troops(amt) .. " Troops to " .. recipient.name, "#38bdf8", nil, nil)
		return true
	end
	return false
end

function SimEngine:SetEmoji(player: any, emoji: string)
	if self.ticks - player.lastEmojiTick < Config.EMOJI_COOLDOWN_TICKS then
		return
	end
	player.lastEmojiTick = self.ticks
	player.emoji = emoji
	player.emojiUntilTick = self.ticks + Config.EMOJI_DURATION_TICKS
end

function SimEngine:PickHostileTargetForNuke(p: any): any
	local best: any = nil
	local bestTiles = 0
	for _, other in ipairs(self.playersList) do
		if other.alive and other ~= p and not self:AreFriendly(p, other) and other.playerType ~= "Bot" then
			local rel = p.relations[other.smallId] or 0
			if (rel <= -40 or other.tilesOwned > p.tilesOwned * 1.4) and other.tilesOwned > bestTiles then
				bestTiles = other.tilesOwned
				best = other
			end
		end
	end
	return best
end

function SimEngine:_SweepPocketSpeckles()
	local map = self.map
	local nbuf = { 0, 0, 0, 0 }
	local nbuf2 = { 0, 0, 0, 0 }
	for _, p in ipairs(self.playersList) do
		if p.alive and #p.borderList > 0 then
			local bLen = #p.borderList
			local limit = math.min(bLen, 220)
			local startIdx = ((self.ticks * 13) % bLen) + 1
			for s = 0, limit - 1 do
				local bRef = p.borderList[((startIdx + s - 1) % bLen) + 1]
				if bRef ~= nil and MapCodec.GetOwner(map, bRef) == p.smallId then
					local n = MapCodec.Neighbors4(map, bRef, nbuf)
					for i = 1, n do
						local nb = nbuf[i]
						if MapCodec.IsPlayableLand(map, nb) then
							local nbOwner = MapCodec.GetOwner(map, nb)
							if nbOwner ~= p.smallId then
								local sameCount = 0
								local waterCount = 0
								local n2 = MapCodec.Neighbors4(map, nb, nbuf2)
								for j = 1, n2 do
									local o2 = MapCodec.GetOwner(map, nbuf2[j])
									if o2 == p.smallId then
										sameCount += 1
									elseif not MapCodec.IsPlayableLand(map, nbuf2[j]) then
										waterCount += 1
									end
								end
								if sameCount >= 3 or (sameCount >= 2 and sameCount + waterCount >= 4) then
									self:ConquerTile(p.smallId, nb)
								end
							end
						end
					end
				end
			end
		end
	end
end

function SimEngine:Step()
	if self.gameOver then
		return
	end

	if self.deltaCount > self.map.size * 2 then
		self.deltaCount = 0
	end
	if self.falloutDeltaCount > self.map.size * 2 then
		self.falloutDeltaCount = 0
	end
	if #self.explosions > 64 then
		table.clear(self.explosions)
	end
	self.ticks += 1

	if self.inSpawnPhase then
		if self.ticks >= self.spawnPhaseTicks then
			self.inSpawnPhase = false
			self:_FinalizeSpawns()
			self:PushEvent(
				"info",
				string.format("⚔️ Borders unlocked on %s (%dx%d)!", self.map.name, self.map.width, self.map.height),
				"#38bdf8",
				nil,
				nil
			)
		end
		return
	end

	local elapsedSeconds = (self.ticks - self.spawnPhaseTicks) / Config.TICKS_PER_SECOND
	local doomReqShare = Config.DoomsdayRequiredShare(self.config, elapsedSeconds)

	for _, p in ipairs(self.playersList) do
		if p.alive then
			p.survivedTicks += 1
			local maxT = self:GetMaxTroops(p)
			p.troops += Config.TroopIncreasePerTick(p.troops, maxT, p.playerType, self.config)
			local g = Config.GoldPerTick(
				p.playerType,
				self.config,
				p.troops,
				p.tilesOwned,
				p.cityLevels,
				p.portLevels,
				p.factoryLevels
			)
			p.gold += g
			p.goldEarned += g

			if p.isTraitor and self.ticks >= p.traitorUntilTick then
				p.isTraitor = false
			end
			if p.emoji ~= nil and self.ticks >= p.emojiUntilTick then
				p.emoji = nil
			end

			for allyId, expTick in pairs(p.allies) do
				if self.ticks >= expTick then
					p.allies[allyId] = nil
				elseif expTick - self.ticks == 200 and p.playerType == "Human" then
					local allyP = self.playersBySmallId[allyId]
					if allyP ~= nil and allyP.alive then
						self.nextAlertId += 1
						self:PushAlert(p.smallId, {
							id = self.nextAlertId,
							kind = "AllianceExpiring",
							fromSmallId = allyId,
							fromName = allyP.name,
							expiresTick = expTick,
						})
					end
				end
			end

			for tid, expTick in pairs(p.targetedBy) do
				if self.ticks >= expTick then
					p.targetedBy[tid] = nil
				end
			end

			if doomReqShare > 0 then
				local share = p.tilesOwned / math.max(1, self.map.numLandTiles)
				if share < doomReqShare then
					p.isDoomed = true
					if p.doomWarnStartTick < 0 then
						p.doomWarnStartTick = self.ticks
					elseif self.ticks - p.doomWarnStartTick > 150 then
						local floorT = maxT * 0.05
						if p.troops > floorT then
							p.troops = math.max(floorT, p.troops - maxT * 0.004)
						end
					end
				else
					p.isDoomed = false
					p.doomWarnStartTick = -1
				end
			end
		end
	end

	AiBrain.StepAll(self, self.ticks)

	self:_TickAttacks()
	if self.ticks % 8 == 0 then
		self:_SweepPocketSpeckles()
	end

	if self.railNetworkDirty and self.ticks % 10 == 0 then
		self:_RebuildRailNetwork()
	end
	self:_TickEconomySpawns()
	self:_TickUnits()

	-- Sparse Active Fallout Decay (`O(activeCraters)` instead of scanning `8,002,384` tiles!)
	if #self.activeFalloutRefs > 0 and self.ticks % 12 == 0 then
		local active = self.activeFalloutRefs
		local samples = math.min(#active, 24)
		for _ = 1, samples do
			local idx = self:_RandInt(1, #active)
			local ref = active[idx]
			if MapCodec.HasFallout(self.map, ref) then
				if self:_Rand() < 0.14 and MapCodec.SetFallout(self.map, ref, false) then
					self.falloutDeltaCount += 1
					self.falloutDeltaRefs[self.falloutDeltaCount] = ref
					self.falloutDeltaStates[self.falloutDeltaCount] = 0
					self.inFalloutSet[ref] = nil
					local last = active[#active]
					active[idx] = last
					active[#active] = nil
					if #active == 0 then
						break
					end
				end
			else
				self.inFalloutSet[ref] = nil
				local last = active[#active]
				active[idx] = last
				active[#active] = nil
				if #active == 0 then
					break
				end
			end
		end
	end

	if self.ticks % 10 == 2 then
		local bx, by, bspan = MapCodec.ComputeAllLabelBoxes(self.map, self.nextSmallId)
		for sid = 1, self.nextSmallId do
			local p = self.playersBySmallId[sid]
			if p ~= nil and p.alive and bspan[sid] > 0 then
				p.labelX = bx[sid]
				p.labelY = by[sid]
				p.labelSpan = bspan[sid]
			end
		end
	end

	if self.ticks % 10 == 5 and not self.isPreview then
		local reqPct = Config.WinPercentageRequired(self.config, elapsedSeconds)
		local totalLand = math.max(1, self.map.numLandTiles)
		local aliveCount = 0
		local lastAlive: any = nil
		local teamTiles: { [string]: number } = {}

		for _, p in ipairs(self.playersList) do
			if p.alive and p.tilesOwned > 0 then
				aliveCount += 1
				lastAlive = p
				if p.team ~= nil then
					teamTiles[p.team] = (teamTiles[p.team] or 0) + p.tilesOwned
				else
					local pct = (p.tilesOwned / totalLand) * 100
					if pct >= reqPct then
						self.gameOver = true
						self.winnerSmallId = p.smallId
						self.winnerName = p.name
						break
					end
				end
			end
		end

		if not self.gameOver and self.config.mode == "Teams" then
			for teamName, tCount in pairs(teamTiles) do
				if (tCount / totalLand) * 100 >= reqPct then
					self.gameOver = true
					self.winnerTeam = teamName
					self.winnerName = "Team " .. teamName
					break
				end
			end
		end

		if not self.gameOver and aliveCount <= 1 and self.ticks > self.spawnPhaseTicks + 30 then
			self.gameOver = true
			if lastAlive ~= nil then
				self.winnerSmallId = lastAlive.smallId
				self.winnerTeam = lastAlive.team
				self.winnerName = if lastAlive.team then ("Team " .. lastAlive.team) else lastAlive.name
			else
				self.winnerName = "Stalemate"
			end
		end
	end
end

function SimEngine:BuildTickPayload(includeFullMap: boolean)
	local tileBuf = if includeFullMap
		then NetCodec.EncodeFullOwnerSnapshot(self.map.owner, self.map.size)
		else NetCodec.EncodeTileDeltas(self.deltaRefs, self.deltaOwners, self.deltaCount)
	local falloutBuf = if self.falloutDeltaCount > 0
		then NetCodec.EncodeFalloutDeltas(self.falloutDeltaRefs, self.falloutDeltaStates, self.falloutDeltaCount)
		else nil
	local falloutSnapshot = if includeFullMap
		then NetCodec.EncodeFullFalloutSnapshot(self.map.fallout, self.map.size)
		else nil
	local explosionsOut = table.clone(self.explosions)
	if not includeFullMap then
		self.deltaCount = 0
		self.falloutDeltaCount = 0
		table.clear(self.explosions)
	end

	local outTroops: { [number]: number } = {}
	local activeAttacksList = {}
	for _, atk in ipairs(self.attacks) do
		if atk.active then
			outTroops[atk.attackerSmallId] = (outTroops[atk.attackerSmallId] or 0) + atk.troops
			local ap = self.playersBySmallId[atk.attackerSmallId]
			if ap ~= nil and ap.playerType == "Human" then
				table.insert(activeAttacksList, {
					id = atk.id,
					attackerSmallId = atk.attackerSmallId,
					targetSmallId = atk.targetSmallId,
					troops = math.floor(atk.troops),
					retreating = atk.retreating == true,
					isBoat = atk.isBoat,
				})
			end
		end
	end

	local playersOut = table.create(#self.playersList)
	for i, p in ipairs(self.playersList) do
		local alliesArr = {}
		for aid, _ in pairs(p.allies) do
			table.insert(alliesArr, aid)
		end
		local embArr = {}
		for eid, _ in pairs(p.embargoes) do
			table.insert(embArr, eid)
		end
		local targArr = {}
		for tid, _ in pairs(p.targetedBy) do
			table.insert(targArr, tid)
		end
		local maxT = self:GetMaxTroops(p)
		playersOut[i] = {
			smallId = p.smallId,
			userId = p.userId,
			playerType = p.playerType,
			name = p.name,
			flag = p.flag,
			colorHex = p.colorHex,
			patternId = p.patternId,
			team = p.team,
			alive = p.alive,
			hasSpawned = p.hasSpawned,
			spawnX = p.spawnX,
			spawnY = p.spawnY,
			labelX = p.labelX,
			labelY = p.labelY,
			labelSpan = p.labelSpan,
			tilesOwned = p.tilesOwned,
			troops = math.floor(p.troops),
			maxTroops = maxT,
			troopRatePerSec = math.floor(Config.TroopIncreasePerTick(p.troops, maxT, p.playerType, self.config) * 10),
			attackingTroops = math.floor(outTroops[p.smallId] or 0),
			gold = math.floor(p.gold),
			isTraitor = p.isTraitor,
			isDoomed = p.isDoomed,
			allies = alliesArr,
			embargoes = embArr,
			emoji = p.emoji,
			targetedBy = targArr,
			unitCounts = p.unitCounts,
		}
	end

	local unitsOut = table.create(#self.units)
	for _, u in ipairs(self.units) do
		if u.active then
			local buildProg = 1.0
			if u.underConstruction then
				local dur = math.max(1, u.buildEndTick - u.buildStartTick)
				buildProg = math.clamp((self.ticks - u.buildStartTick) / dur, 0, 1)
			end
			table.insert(unitsOut, {
				id = u.id,
				unitType = u.unitType,
				ownerSmallId = u.ownerSmallId,
				x = u.x,
				y = u.y,
				srcX = u.srcX,
				srcY = u.srcY,
				dstX = u.dstX,
				dstY = u.dstY,
				patrolX = u.patrolX,
				patrolY = u.patrolY,
				level = u.level,
				hp = u.hp,
				maxHp = u.maxHp,
				veterancy = u.veterancy or 0,
				underConstruction = u.underConstruction,
				constructionProgress = buildProg,
				onCooldown = self.ticks < (u.cooldownUntilTick or 0),
				troops = math.floor(u.troops or 0),
				progress = u.progress or 0,
			})
		end
	end

	local elapsedSeconds = math.max(0, (self.ticks - self.spawnPhaseTicks) / Config.TICKS_PER_SECOND)
	return {
		isFullSnapshot = includeFullMap,
		isPreview = self.isPreview,
		mapId = self.map.id,
		ticks = self.ticks,
		inSpawnPhase = self.inSpawnPhase,
		spawnSecondsLeft = math.max(0, (self.spawnPhaseTicks - self.ticks) / Config.TICKS_PER_SECOND),
		elapsedSeconds = elapsedSeconds,
		winPercentRequired = Config.WinPercentageRequired(self.config, elapsedSeconds),
		doomsdayShare = Config.DoomsdayRequiredShare(self.config, elapsedSeconds),
		mirvsLaunched = self.mirvsLaunched,
		simSpeed = self.simSpeed,
		paused = self.paused,
		config = self.config,
		tileBuffer = tileBuf,
		falloutBuffer = falloutBuf,
		falloutSnapshot = falloutSnapshot,
		players = playersOut,
		units = unitsOut,
		attacks = activeAttacksList,
		railEdges = self.railEdges,
		events = self.events,
		explosions = explosionsOut,
		alertsByPlayer = self.alertsByPlayer,
		gameOver = self.gameOver,
		winnerName = self.winnerName,
		winnerSmallId = self.winnerSmallId,
		winnerTeam = self.winnerTeam,
	}
end

return SimEngine
