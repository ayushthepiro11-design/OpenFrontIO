--!native
--!strict
-- Exact `--!native` port of OpenFront's FlatBinaryHeap.ts with O(1) `peekPriority()`,
-- empty-dequeue safety, and memory trim on `clear()`.

local Heap = {}
Heap.__index = Heap

export type MinHeap = typeof(setmetatable(
	{} :: {
		tiles: { number },
		pri: { number },
		len: number,
	},
	Heap
))

function Heap.new(): MinHeap
	return setmetatable({
		tiles = table.create(512, 0),
		pri = table.create(512, 0),
		len = 0,
	}, Heap)
end

function Heap.size(self: MinHeap): number
	return self.len
end

function Heap.peekPriority(self: MinHeap): number?
	if self.len <= 0 then
		return nil
	end
	return self.pri[1]
end

function Heap.clear(self: MinHeap)
	self.len = 0
	if #self.tiles > 4096 then
		self.tiles = table.create(512, 0)
		self.pri = table.create(512, 0)
	end
end

function Heap.enqueue(self: MinHeap, tile: number, priority: number)
	local idx = self.len + 1
	self.len = idx
	local tiles = self.tiles
	local pri = self.pri
	tiles[idx] = tile
	pri[idx] = priority
	while idx > 1 do
		local parent = bit32.rshift(idx, 1)
		if pri[parent] <= priority then
			break
		end
		tiles[idx] = tiles[parent]
		pri[idx] = pri[parent]
		tiles[parent] = tile
		pri[parent] = priority
		idx = parent
	end
end

function Heap.dequeue(self: MinHeap): number?
	local n = self.len
	if n <= 0 then
		return nil
	end
	local tiles = self.tiles
	local pri = self.pri
	local top = tiles[1]
	local lastTile = tiles[n]
	local lastPri = pri[n]
	n -= 1
	self.len = n
	if n > 0 then
		local idx = 1
		local half = bit32.rshift(n, 1)
		while idx <= half do
			local left = bit32.lshift(idx, 1)
			local right = left + 1
			local smallest = left
			local smallPri = pri[left]
			if right <= n and pri[right] < smallPri then
				smallest = right
				smallPri = pri[right]
			end
			if lastPri <= smallPri then
				break
			end
			tiles[idx] = tiles[smallest]
			pri[idx] = smallPri
			idx = smallest
		end
		tiles[idx] = lastTile
		pri[idx] = lastPri
	end
	return top
end

return Heap
