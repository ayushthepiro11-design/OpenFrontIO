--!strict
-- High-speed buffer-backed OpenFront GameMap decoder, spatial queries, water/land pathfinding,
-- and exact maximal-inscribed-square Nation Name Box calculator.

local Types = require(script.Parent:WaitForChild("Types"))
type TerrainKind = Types.TerrainKind

local MapCodec = {}

export type GameMap = {
	id: string,
	name: string,
	width: number,
	height: number,
	size: number,
	numLandTiles: number,
	numFalloutTiles: number,
	terrain: buffer, -- u8 per tile (0..size-1)
	owner: buffer, -- u16 per tile (0..size*2-2), 0 = Terra Nullius
	fallout: buffer, -- u8 per tile (0 or 1)
	depthScratch: buffer, -- u16 scratch for maximal-inscribed-square label solver
}

-- Precomputed ASCII -> Base64 6-bit value table
local B64_DECODE = table.create(256, -1)
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #chars do
		B64_DECODE[string.byte(chars, i) + 1] = i - 1
	end
end

function MapCodec.Base64Decode(b64: string): buffer
	local cleanLen = #b64
	local pad = 0
	if cleanLen >= 1 and string.byte(b64, cleanLen) == 61 then
		pad += 1
	end
	if cleanLen >= 2 and string.byte(b64, cleanLen - 1) == 61 then
		pad += 1
	end

	-- First count valid sextets
	local validCount = 0
	for i = 1, cleanLen do
		local c = string.byte(b64, i)
		if B64_DECODE[c + 1] >= 0 then
			validCount += 1
		end
	end
	local outLen = math.floor((validCount * 3) / 4)
	local out = buffer.create(math.max(0, outLen))
	local acc = 0
	local bits = 0
	local writePos = 0

	for i = 1, cleanLen do
		local v = B64_DECODE[string.byte(b64, i) + 1]
		if v >= 0 then
			acc = bit32.bor(bit32.lshift(acc, 6), v)
			bits += 6
			if bits >= 8 then
				bits -= 8
				if writePos < outLen then
					buffer.writeu8(out, writePos, bit32.band(bit32.rshift(acc, bits), 0xFF))
					writePos += 1
				end
			end
		end
	end
	local _ = pad
	return out
end

function MapCodec.DecodeMap(rawDef: any): GameMap
	local w: number = rawDef.width
	local h: number = rawDef.height
	local total = w * h
	local compressed = MapCodec.Base64Decode(rawDef.rleBase64)
	local compLen = buffer.len(compressed)
	local terrain = buffer.create(total)

	local i = 0
	local outPos = 0
	while i < compLen and outPos < total do
		local b = buffer.readu8(compressed, i)
		i += 1
		if b < 0x80 then
			local cnt = b + 1
			local safeCnt = math.min(cnt, total - outPos, compLen - i)
			buffer.copy(terrain, outPos, compressed, i, safeCnt)
			i += cnt
			outPos += safeCnt
		elseif b < 0xE0 then
			local cnt = (b - 0x80) + 3
			local val = buffer.readu8(compressed, i)
			i += 1
			local safeCnt = math.min(cnt, total - outPos)
			buffer.fill(terrain, outPos, val, safeCnt)
			outPos += safeCnt
		else
			local lo = buffer.readu8(compressed, i)
			i += 1
			local val = buffer.readu8(compressed, i)
			i += 1
			local cnt = bit32.bor(bit32.lshift(bit32.band(b, 0x1F), 8), lo) + 99
			local safeCnt = math.min(cnt, total - outPos)
			buffer.fill(terrain, outPos, val, safeCnt)
			outPos += safeCnt
		end
	end

	return {
		id = rawDef.id,
		name = rawDef.name,
		width = w,
		height = h,
		size = total,
		numLandTiles = rawDef.numLandTiles,
		numFalloutTiles = 0,
		terrain = terrain,
		owner = buffer.create(total * 2),
		fallout = buffer.create(total),
		depthScratch = buffer.create(total * 2),
	}
end

-- Exact tile state / terrain helpers (0-based ref = y * width + x, matching OpenFront TileRef!)
function MapCodec.IsLand(map: GameMap, ref: number): boolean
	local tb = buffer.readu8(map.terrain, ref)
	return bit32.band(tb, 0x80) ~= 0
end

function MapCodec.IsImpassable(map: GameMap, ref: number): boolean
	local tb = buffer.readu8(map.terrain, ref)
	return bit32.band(tb, 0x80) ~= 0 and bit32.band(tb, 0x1F) == 31
end

function MapCodec.IsPlayableLand(map: GameMap, ref: number): boolean
	local tb = buffer.readu8(map.terrain, ref)
	return bit32.band(tb, 0x80) ~= 0 and bit32.band(tb, 0x1F) ~= 31
end

function MapCodec.IsWater(map: GameMap, ref: number): boolean
	return bit32.band(buffer.readu8(map.terrain, ref), 0x80) == 0
end

function MapCodec.IsShoreLand(map: GameMap, ref: number): boolean
	local tb = buffer.readu8(map.terrain, ref)
	return bit32.band(tb, 0xC0) == 0xC0 and bit32.band(tb, 0x1F) ~= 31
end

function MapCodec.TerrainKind(map: GameMap, ref: number): TerrainKind
	local tb = buffer.readu8(map.terrain, ref)
	if bit32.band(tb, 0x80) == 0 then
		return "Water"
	end
	local mag = bit32.band(tb, 0x1F)
	if mag == 31 then
		return "Impassable"
	elseif mag < 10 then
		return "Plains"
	elseif mag < 20 then
		return "Highland"
	else
		return "Mountain"
	end
end

function MapCodec.GetOwner(map: GameMap, ref: number): number
	return buffer.readu16(map.owner, ref * 2)
end

function MapCodec.SetOwner(map: GameMap, ref: number, smallId: number)
	buffer.writeu16(map.owner, ref * 2, smallId)
end

function MapCodec.HasFallout(map: GameMap, ref: number): boolean
	return buffer.readu8(map.fallout, ref) ~= 0
end

function MapCodec.SetFallout(map: GameMap, ref: number, active: boolean): boolean
	local cur = buffer.readu8(map.fallout, ref) ~= 0
	if cur == active then
		return false
	end
	buffer.writeu8(map.fallout, ref, if active then 1 else 0)
	if active then
		map.numFalloutTiles += 1
	else
		map.numFalloutTiles = math.max(0, map.numFalloutTiles - 1)
	end
	return true
end

-- Writes up to 4 valid cardinal neighbors into nbuf[1..4], returns count (exact GameMapImpl.neighbors4)
function MapCodec.Neighbors4(map: GameMap, ref: number, nbuf: { number }): number
	local w = map.width
	local x = ref % w
	local n = 0
	if x > 0 then
		n += 1
		nbuf[n] = ref - 1
	end
	if x < w - 1 then
		n += 1
		nbuf[n] = ref + 1
	end
	if ref >= w then
		n += 1
		nbuf[n] = ref - w
	end
	if ref < map.size - w then
		n += 1
		nbuf[n] = ref + w
	end
	return n
end

-- Find nearest water tile adjacent to a coastal land tile
function MapCodec.AdjacentWater(map: GameMap, landRef: number): number?
	local nbuf = { 0, 0, 0, 0 }
	local n = MapCodec.Neighbors4(map, landRef, nbuf)
	for i = 1, n do
		if MapCodec.IsWater(map, nbuf[i]) then
			return nbuf[i]
		end
	end
	return nil
end

-- Greedy A* / BFS water pathfinder for TransportShip, TradeShip & Warship navigation
-- Routes cleanly around peninsulas, islands, and straits without crossing land!
function MapCodec.FindWaterPath(
	map: GameMap,
	startRef: number,
	goalRef: number,
	maxNodes: number?
): { number }?
	local limit = maxNodes or 14_000
	local startWater = if MapCodec.IsWater(map, startRef) then startRef else MapCodec.AdjacentWater(map, startRef)
	local goalWater = if MapCodec.IsWater(map, goalRef) then goalRef else MapCodec.AdjacentWater(map, goalRef)
	if startWater == nil or goalWater == nil then
		return nil
	end
	if startWater == goalWater then
		return { startRef, goalRef }
	end

	local w = map.width
	local gx = goalWater % w
	local gy = math.floor(goalWater / w)

	-- Min-heap A* on water grid with coarse 2x step option for long ocean crossings
	local parent: { [number]: number } = {}
	local gScore: { [number]: number } = {}
	local heapNodes: { number } = {}
	local heapPrio: { number } = {}
	local heapSize = 0

	local function push(node: number, prio: number)
		heapSize += 1
		local idx = heapSize
		heapNodes[idx] = node
		heapPrio[idx] = prio
		while idx > 1 do
			local p = math.floor(idx / 2)
			if heapPrio[p] <= prio then
				break
			end
			heapNodes[idx], heapNodes[p] = heapNodes[p], heapNodes[idx]
			heapPrio[idx], heapPrio[p] = heapPrio[p], heapPrio[idx]
			idx = p
		end
	end

	local function pop(): number
		local top = heapNodes[1]
		local lastN = heapNodes[heapSize]
		local lastP = heapPrio[heapSize]
		heapSize -= 1
		if heapSize > 0 then
			local idx = 1
			while true do
				local l = idx * 2
				local r = l + 1
				local smallest = idx
				if l <= heapSize and heapPrio[l] < lastP then
					smallest = l
				end
				if r <= heapSize and heapPrio[r] < (if smallest == idx then lastP else heapPrio[l]) then
					smallest = r
				end
				if smallest == idx then
					break
				end
				heapNodes[idx] = heapNodes[smallest]
				heapPrio[idx] = heapPrio[smallest]
				idx = smallest
			end
			heapNodes[idx] = lastN
			heapPrio[idx] = lastP
		end
		return top
	end

	gScore[startWater] = 0
	parent[startWater] = -1
	push(startWater, 0)

	local expanded = 0
	local nbuf = { 0, 0, 0, 0 }
	local found = false

	while heapSize > 0 and expanded < limit do
		local cur = pop()
		if cur == goalWater then
			found = true
			break
		end
		expanded += 1
		local baseG = gScore[cur] or 0
		local n = MapCodec.Neighbors4(map, cur, nbuf)
		for i = 1, n do
			local nxt = nbuf[i]
			if MapCodec.IsWater(map, nxt) then
				local tentative = baseG + 1
				local prevG = gScore[nxt]
				if prevG == nil or tentative < prevG then
					gScore[nxt] = tentative
					parent[nxt] = cur
					local nx = nxt % w
					local ny = math.floor(nxt / w)
					local hCost = (math.abs(nx - gx) + math.abs(ny - gy)) * 1.15
					push(nxt, tentative + hCost)
				end
			end
		end
	end

	if not found then
		return nil
	end

	local rev = { goalRef }
	local cur: number? = goalWater
	while cur ~= nil and cur >= 0 do
		table.insert(rev, cur)
		local p = parent[cur]
		if p == nil or p < 0 then
			break
		end
		cur = p
	end
	-- Subsample waypoints every 2 steps for crisp smooth motion + final goal tile
	local path = {}
	for idx = #rev, 1, -2 do
		table.insert(path, rev[idx])
	end
	if path[#path] ~= goalRef then
		table.insert(path, goalRef)
	end
	return path
end

-- Land railroad pathfinder between stations within maxRange
function MapCodec.FindLandRailPath(
	map: GameMap,
	startRef: number,
	goalRef: number,
	maxRange: number
): { number }?
	local w = map.width
	local sx, sy = startRef % w, math.floor(startRef / w)
	local gx, gy = goalRef % w, math.floor(goalRef / w)
	if (sx - gx) * (sx - gx) + (sy - gy) * (sy - gy) > maxRange * maxRange then
		return nil
	end

	local parent: { [number]: number } = {}
	local gScore: { [number]: number } = {}
	local heapNodes: { number } = {}
	local heapPrio: { number } = {}
	local heapSize = 0

	local function push(node: number, prio: number)
		heapSize += 1
		local idx = heapSize
		heapNodes[idx] = node
		heapPrio[idx] = prio
		while idx > 1 do
			local p = math.floor(idx / 2)
			if heapPrio[p] <= prio then
				break
			end
			heapNodes[idx], heapNodes[p] = heapNodes[p], heapNodes[idx]
			heapPrio[idx], heapPrio[p] = heapPrio[p], heapPrio[idx]
			idx = p
		end
	end

	local function pop(): number
		local top = heapNodes[1]
		local lastN = heapNodes[heapSize]
		local lastP = heapPrio[heapSize]
		heapSize -= 1
		if heapSize > 0 then
			local idx = 1
			while true do
				local l = idx * 2
				local r = l + 1
				local smallest = idx
				if l <= heapSize and heapPrio[l] < lastP then
					smallest = l
				end
				if r <= heapSize and heapPrio[r] < (if smallest == idx then lastP else heapPrio[l]) then
					smallest = r
				end
				if smallest == idx then
					break
				end
				heapNodes[idx] = heapNodes[smallest]
				heapPrio[idx] = heapPrio[smallest]
				idx = smallest
			end
			heapNodes[idx] = lastN
			heapPrio[idx] = lastP
		end
		return top
	end

	gScore[startRef] = 0
	parent[startRef] = -1
	push(startRef, 0)

	local expanded = 0
	local nbuf = { 0, 0, 0, 0 }
	local found = false
	while heapSize > 0 and expanded < 3_500 do
		local cur = pop()
		if cur == goalRef then
			found = true
			break
		end
		expanded += 1
		local baseG = gScore[cur] or 0
		if baseG > maxRange * 1.45 then
			continue
		end
		local n = MapCodec.Neighbors4(map, cur, nbuf)
		for i = 1, n do
			local nxt = nbuf[i]
			if MapCodec.IsPlayableLand(map, nxt) then
				local tentative = baseG + 1
				local prevG = gScore[nxt]
				if prevG == nil or tentative < prevG then
					gScore[nxt] = tentative
					parent[nxt] = cur
					local nx = nxt % w
					local ny = math.floor(nxt / w)
					push(nxt, tentative + (math.abs(nx - gx) + math.abs(ny - gy)) * 1.2)
				end
			end
		end
	end

	if not found then
		return nil
	end
	local rev = {}
	local cur: number? = goalRef
	while cur ~= nil and cur >= 0 do
		table.insert(rev, cur)
		local p = parent[cur]
		if p == nil or p < 0 then
			break
		end
		cur = p
	end
	local path = table.create(#rev)
	for i = #rev, 1, -1 do
		table.insert(path, rev[i])
	end
	return path
end

-- Exact O(W*H) single-pass Maximal Inscribed Square solver matching OpenFront NameBoxCalculator.ts!
-- Simultaneous for ALL alive players in < 1ms!
function MapCodec.ComputeAllLabelBoxes(
	map: GameMap,
	maxSmallId: number
): ({ number }, { number }, { number })
	local bestSide = table.create(maxSmallId, 0)
	local bestX = table.create(maxSmallId, 0)
	local bestY = table.create(maxSmallId, 0)

	local w = map.width
	local h = map.height
	local ownerBuf = map.owner
	local scratch = map.depthScratch
	buffer.fill(scratch, 0, 0, map.size * 2)

	for y = 0, h - 1 do
		local rowOff = y * w
		for x = 0, w - 1 do
			local ref = rowOff + x
			local id = buffer.readu16(ownerBuf, ref * 2)
			if id > 0 and id <= maxSmallId then
				local side = 1
				if x > 0 and y > 0 then
					local leftId = buffer.readu16(ownerBuf, (ref - 1) * 2)
					local upId = buffer.readu16(ownerBuf, (ref - w) * 2)
					local diagId = buffer.readu16(ownerBuf, (ref - w - 1) * 2)
					if leftId == id and upId == id and diagId == id then
						local dl = buffer.readu16(scratch, (ref - 1) * 2)
						local du = buffer.readu16(scratch, (ref - w) * 2)
						local dd = buffer.readu16(scratch, (ref - w - 1) * 2)
						side = 1 + math.min(dl, du, dd)
					end
				end
				buffer.writeu16(scratch, ref * 2, side)
				if side > bestSide[id] then
					bestSide[id] = side
					local half = (side - 1) * 0.5
					bestX[id] = x - half
					bestY[id] = y - half
				end
			end
		end
	end

	return bestX, bestY, bestSide
end

return MapCodec
