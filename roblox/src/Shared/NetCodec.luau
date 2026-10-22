--!native
--!strict
-- Bounds-Hardened Binary Network Codec for Full-Scale 1:1 OpenFront Maps (up to 8M+ tiles!):
--   1. Bounds-verified u32 tile ref + u16 owner delta stream (`EncodeTileDeltas` / `ApplyTileDeltas`)
--   2. Bounds-verified u32 tile ref + u8 fallout delta stream (`EncodeFalloutDeltas` / `ApplyFalloutDeltas`)
--   3. Fast C-speed chunked full-map `owner` AND `fallout` RLE snapshots for instant late-join sync!

local NetCodec = {}

function NetCodec.EncodeTileDeltas(refs: { number }, owners: { number }, count: number): buffer?
	local safeCount = math.clamp(math.floor(count), 0, math.min(#refs, #owners))
	if safeCount <= 0 then
		return nil
	end
	local buf = buffer.create(4 + safeCount * 6)
	buffer.writeu32(buf, 0, safeCount)
	local pos = 4
	for i = 1, safeCount do
		buffer.writeu32(buf, pos, refs[i])
		buffer.writeu16(buf, pos + 4, owners[i])
		pos += 6
	end
	return buf
end

function NetCodec.ApplyTileDeltas(
	buf: buffer,
	ownerBuf: buffer,
	width: number,
	dirtyRows: { [number]: boolean }?,
	dirtyTiles: { number }?
): number
	local bufLen = buffer.len(buf)
	if bufLen < 4 or width <= 0 then
		return 0
	end
	local ownerBytes = buffer.len(ownerBuf)
	local numTiles = math.floor(ownerBytes / 2)
	local maxY = math.max(0, math.floor((numTiles - 1) / width))
	local count = buffer.readu32(buf, 0)
	local pos = 4
	local applied = 0
	for _ = 1, count do
		if pos + 6 > bufLen then
			break
		end
		local ref = buffer.readu32(buf, pos)
		local owner = buffer.readu16(buf, pos + 4)
		pos += 6
		if ref < numTiles then
			buffer.writeu16(ownerBuf, ref * 2, owner)
			applied += 1
			if dirtyRows ~= nil then
				local y = math.floor(ref / width)
				dirtyRows[y] = true
				if y > 0 then
					dirtyRows[y - 1] = true
				end
				if y < maxY then
					dirtyRows[y + 1] = true
				end
			end
			if dirtyTiles ~= nil then
				table.insert(dirtyTiles, ref)
			end
		end
	end
	return applied
end

function NetCodec.EncodeFalloutDeltas(refs: { number }, states: { number }, count: number): buffer?
	local safeCount = math.clamp(math.floor(count), 0, math.min(#refs, #states))
	if safeCount <= 0 then
		return nil
	end
	local buf = buffer.create(4 + safeCount * 5)
	buffer.writeu32(buf, 0, safeCount)
	local pos = 4
	for i = 1, safeCount do
		buffer.writeu32(buf, pos, refs[i])
		buffer.writeu8(buf, pos + 4, states[i])
		pos += 5
	end
	return buf
end

function NetCodec.ApplyFalloutDeltas(
	buf: buffer,
	falloutBuf: buffer,
	width: number,
	dirtyRows: { [number]: boolean }?,
	dirtyTiles: { number }?
): number
	local bufLen = buffer.len(buf)
	if bufLen < 4 or width <= 0 then
		return 0
	end
	local numTiles = buffer.len(falloutBuf)
	local count = buffer.readu32(buf, 0)
	local pos = 4
	local applied = 0
	for _ = 1, count do
		if pos + 5 > bufLen then
			break
		end
		local ref = buffer.readu32(buf, pos)
		local st = buffer.readu8(buf, pos + 4)
		pos += 5
		if ref < numTiles then
			buffer.writeu8(falloutBuf, ref, st)
			applied += 1
			if dirtyRows ~= nil then
				dirtyRows[math.floor(ref / width)] = true
			end
			if dirtyTiles ~= nil then
				table.insert(dirtyTiles, ref)
			end
		end
	end
	return applied
end

-- Fast u32-run RLE [runLen: u32, ownerId: u16] (handles 8M-tile ocean spans in 1 entry instead of 125 u16 chunks!)
function NetCodec.EncodeFullOwnerSnapshot(ownerBuf: buffer, numTiles: number): buffer
	local safeTiles = math.min(numTiles, math.floor(buffer.len(ownerBuf) / 2))
	local runs = table.create(4096, 0)
	local vals = table.create(4096, 0)
	local nRuns = 0
	local i = 0
	while i < safeTiles do
		local v = buffer.readu16(ownerBuf, i * 2)
		local run = 1
		while i + run < safeTiles and buffer.readu16(ownerBuf, (i + run) * 2) == v do
			run += 1
		end
		nRuns += 1
		runs[nRuns] = run
		vals[nRuns] = v
		i += run
	end
	local out = buffer.create(4 + nRuns * 6)
	buffer.writeu32(out, 0, nRuns)
	local pos = 4
	for r = 1, nRuns do
		buffer.writeu32(out, pos, runs[r])
		buffer.writeu16(out, pos + 4, vals[r])
		pos += 6
	end
	return out
end

function NetCodec.DecodeFullOwnerSnapshot(buf: buffer, ownerBuf: buffer, numTiles: number)
	local maxPos = buffer.len(buf)
	if maxPos < 4 then
		return
	end
	local safeTiles = math.min(numTiles, math.floor(buffer.len(ownerBuf) / 2))
	local nRuns = buffer.readu32(buf, 0)
	local pos = 4
	local outIdx = 0
	for _ = 1, nRuns do
		if pos + 6 > maxPos or outIdx >= safeTiles then
			break
		end
		local run = math.min(buffer.readu32(buf, pos), safeTiles - outIdx)
		local val = buffer.readu16(buf, pos + 4)
		pos += 6
		if val == 0 then
			-- Zero Terra Nullius spans run at native C memset speed (`buffer.fill`)!
			buffer.fill(ownerBuf, outIdx * 2, 0, run * 2)
			outIdx += run
		else
			local lo = bit32.band(val, 0xFF)
			local hi = bit32.rshift(val, 8)
			if lo == hi then
				buffer.fill(ownerBuf, outIdx * 2, lo, run * 2)
				outIdx += run
			else
				local pair32 = val + bit32.lshift(val, 16)
				local pairs = math.floor(run / 2)
				local bytePos = outIdx * 2
				for _ = 1, pairs do
					buffer.writeu32(ownerBuf, bytePos, pair32)
					bytePos += 4
				end
				if run % 2 == 1 then
					buffer.writeu16(ownerBuf, bytePos, val)
				end
				outIdx += run
			end
		end
	end
end

-- Full nuclear fallout RLE snapshot for late-joiners (`[nRuns: u32] + [runLen: u32, state: u8]`)
function NetCodec.EncodeFullFalloutSnapshot(falloutBuf: buffer, numTiles: number): buffer?
	local safeTiles = math.min(numTiles, buffer.len(falloutBuf))
	local runs = table.create(256, 0)
	local vals = table.create(256, 0)
	local nRuns = 0
	local hasAny = false
	local i = 0
	while i < safeTiles do
		local v = buffer.readu8(falloutBuf, i)
		if v ~= 0 then
			hasAny = true
		end
		local run = 1
		while i + run < safeTiles and buffer.readu8(falloutBuf, i + run) == v do
			run += 1
		end
		nRuns += 1
		runs[nRuns] = run
		vals[nRuns] = v
		i += run
	end
	if not hasAny then
		return nil
	end
	local out = buffer.create(4 + nRuns * 5)
	buffer.writeu32(out, 0, nRuns)
	local pos = 4
	for r = 1, nRuns do
		buffer.writeu32(out, pos, runs[r])
		buffer.writeu8(out, pos + 4, vals[r])
		pos += 5
	end
	return out
end

function NetCodec.DecodeFullFalloutSnapshot(buf: buffer?, falloutBuf: buffer, numTiles: number): number
	local safeTiles = math.min(numTiles, buffer.len(falloutBuf))
	if buf == nil or buffer.len(buf) < 4 then
		buffer.fill(falloutBuf, 0, 0, safeTiles)
		return 0
	end
	local maxPos = buffer.len(buf)
	local nRuns = buffer.readu32(buf, 0)
	local pos = 4
	local outIdx = 0
	local activeFallout = 0
	for _ = 1, nRuns do
		if pos + 5 > maxPos or outIdx >= safeTiles then
			break
		end
		local run = math.min(buffer.readu32(buf, pos), safeTiles - outIdx)
		local st = buffer.readu8(buf, pos + 4)
		pos += 5
		buffer.fill(falloutBuf, outIdx, st, run)
		if st ~= 0 then
			activeFallout += run
		end
		outIdx += run
	end
	return activeFallout
end

return NetCodec
