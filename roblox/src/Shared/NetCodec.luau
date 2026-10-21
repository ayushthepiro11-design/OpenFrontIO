--!strict
-- Binary network codec matching OpenFront's zbin philosophy:
-- Uses native Luau `buffer` objects for ultra-low bandwidth tile & fallout synchronization!

local NetCodec = {}

-- Encodes changed tile owners into a compact binary buffer:
-- Header: [count: u32]
-- Entry (6 bytes): [tileRef: u32, newOwnerSmallId: u16]
function NetCodec.EncodeTileDeltas(refs: { number }, owners: { number }, count: number): buffer
	local buf = buffer.create(4 + count * 6)
	buffer.writeu32(buf, 0, count)
	local pos = 4
	for i = 1, count do
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
	if buffer.len(buf) < 4 then
		return 0
	end
	local count = buffer.readu32(buf, 0)
	local pos = 4
	local maxPos = buffer.len(buf)
	for _ = 1, count do
		if pos + 6 > maxPos then
			break
		end
		local ref = buffer.readu32(buf, pos)
		local owner = buffer.readu16(buf, pos + 4)
		pos += 6
		buffer.writeu16(ownerBuf, ref * 2, owner)
		if dirtyRows ~= nil then
			local y = math.floor(ref / width)
			dirtyRows[y] = true
			if y > 0 then
				dirtyRows[y - 1] = true
			end
			dirtyRows[y + 1] = true
		end
		if dirtyTiles ~= nil then
			table.insert(dirtyTiles, ref)
		end
	end
	return count
end

-- Encodes fallout tile updates: [count: u32] + [tileRef: u32, state: u8] (5 bytes/entry)
function NetCodec.EncodeFalloutDeltas(refs: { number }, states: { number }, count: number): buffer
	local buf = buffer.create(4 + count * 5)
	buffer.writeu32(buf, 0, count)
	local pos = 4
	for i = 1, count do
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
	if buffer.len(buf) < 4 then
		return 0
	end
	local count = buffer.readu32(buf, 0)
	local pos = 4
	local maxPos = buffer.len(buf)
	for _ = 1, count do
		if pos + 5 > maxPos then
			break
		end
		local ref = buffer.readu32(buf, pos)
		local st = buffer.readu8(buf, pos + 4)
		pos += 5
		buffer.writeu8(falloutBuf, ref, st)
		if dirtyRows ~= nil then
			dirtyRows[math.floor(ref / width)] = true
		end
		if dirtyTiles ~= nil then
			table.insert(dirtyTiles, ref)
		end
	end
	return count
end

-- Encodes full u16 owner buffer via 4-byte RLE [runLen: u16, ownerId: u16] for instant late-join sync
function NetCodec.EncodeFullOwnerSnapshot(ownerBuf: buffer, numTiles: number): buffer
	local runs: { number } = {}
	local vals: { number } = {}
	local nRuns = 0
	local i = 0
	while i < numTiles do
		local v = buffer.readu16(ownerBuf, i * 2)
		local run = 1
		while i + run < numTiles and run < 65535 and buffer.readu16(ownerBuf, (i + run) * 2) == v do
			run += 1
		end
		nRuns += 1
		runs[nRuns] = run
		vals[nRuns] = v
		i += run
	end
	local out = buffer.create(4 + nRuns * 4)
	buffer.writeu32(out, 0, nRuns)
	local pos = 4
	for r = 1, nRuns do
		buffer.writeu16(out, pos, runs[r])
		buffer.writeu16(out, pos + 2, vals[r])
		pos += 4
	end
	return out
end

function NetCodec.DecodeFullOwnerSnapshot(buf: buffer, ownerBuf: buffer, numTiles: number)
	if buffer.len(buf) < 4 then
		return
	end
	local nRuns = buffer.readu32(buf, 0)
	local pos = 4
	local maxPos = buffer.len(buf)
	local outIdx = 0
	for _ = 1, nRuns do
		if pos + 4 > maxPos or outIdx >= numTiles then
			break
		end
		local run = buffer.readu16(buf, pos)
		local val = buffer.readu16(buf, pos + 2)
		pos += 4
		for _ = 1, run do
			if outIdx >= numTiles then
				break
			end
			buffer.writeu16(ownerBuf, outIdx * 2, val)
			outIdx += 1
		end
	end
end

return NetCodec
