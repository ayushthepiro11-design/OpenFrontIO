--!strict
-- Pure 2D Browser-Exact OpenFront Renderer for Roblox:
--   Backend 1 (Primary): Native RGBA8 `EditableImage:WritePixelsBuffer` 1px WebGL-identical shader
--   Backend 2 (Auto Fallback): Pooled Per-Row RLE `ScanlineCanvas2D` (zero setup even in unpublished .rbxl!)
--   Plus crisp vector overlays for Structures, Ships, Trains, Railroads, Missiles, Blast Rings,
--   Maximal-Inscribed-Square Nation Labels, and Interactive Viewport Minimap!

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local MapCodec = require(Shared:WaitForChild("MapCodec"))
local MapRegistry = require(Shared:WaitForChild("Maps"):WaitForChild("MapRegistry"))
local Theme = require(Shared:WaitForChild("Theme"))

local UiWidgets = require(script.Parent:WaitForChild("UiWidgets"))

local MapCanvas = {}
MapCanvas.__index = MapCanvas

local UNIT_ICONS: { [string]: string } = {
	City = "🏙️",
	Port = "⚓",
	Factory = "🏭",
	DefensePost = "🛡️",
	MissileSilo = "🚀",
	SAMLauncher = "📡",
	Warship = "🚢",
	TransportShip = "⛴️",
	TradeShip = "💠",
	Train = "🚂",
	AtomBomb = "☢️",
	HydrogenBomb = "💥",
	MIRV = "☄️",
	MIRVWarhead = "🔻",
	SAMMissile = "⚡",
}

export type CanvasInstance = typeof(setmetatable({} :: any, MapCanvas))

function MapCanvas.new(viewportParent: Frame, camera: any): CanvasInstance
	local self = setmetatable({}, MapCanvas) :: any
	self.viewport = viewportParent
	self.camera = camera
	self.map = nil :: MapCodec.GameMap?
	self.rawMap = nil :: any

	self.altView = false
	self.terrainOnly = false
	self.showNames = true
	self.forceScanline = false
	self.usingEditableImage = false
	self.mySmallId = 0
	self.selectedWarshipId = nil :: number?
	self.hoveredOwnerId = 0
	self.armedBuildType = nil :: string?
	self.cursorTileX = 0
	self.cursorTileY = 0

	-- Fast per-smallId color LUTs
	self.pR = {} :: { [number]: number }
	self.pG = {} :: { [number]: number }
	self.pB = {} :: { [number]: number }
	self.borderU32 = {} :: { [number]: number }
	self.borderColor3 = {} :: { [number]: Color3 }
	self.fillColor3 = {} :: { [number]: Color3 }
	self.blendedFillColor3 = {} :: { [number]: Color3 }
	self.patternById = {} :: { [number]: string }
	self.friendlySet = {} :: { [number]: boolean }
	self.embargoSet = {} :: { [number]: boolean }
	self.defendedSet = {} :: { [number]: boolean }
	self.playersById = {} :: { [number]: any }
	self.hudBlockedRects = {} :: { { number } }
	self.hideWorldLabels = false

	-- Surface container transformed by Camera2D
	local mapRoot = Instance.new("Frame")
	mapRoot.Name = "MapSurface"
	mapRoot.BackgroundColor3 = Color3.fromRGB(63, 125, 173)
	mapRoot.BorderSizePixel = 0
	mapRoot.ClipsDescendants = false
	mapRoot.Parent = viewportParent
	self.mapRoot = mapRoot

	local scanTerrainLayer = Instance.new("Folder")
	scanTerrainLayer.Name = "ScanlineTerrain"
	scanTerrainLayer.Parent = mapRoot
	self.scanTerrainLayer = scanTerrainLayer

	local scanTerritoryLayer = Instance.new("Folder")
	scanTerritoryLayer.Name = "ScanlineTerritory"
	scanTerritoryLayer.Parent = mapRoot
	self.scanTerritoryLayer = scanTerritoryLayer

	local pixelImageLabel = Instance.new("ImageLabel")
	pixelImageLabel.Name = "EditableMapImage"
	pixelImageLabel.Size = UDim2.fromScale(1, 1)
	pixelImageLabel.BackgroundTransparency = 1
	pixelImageLabel.BorderSizePixel = 0
	pixelImageLabel.ResampleMode = Enum.ResamplerMode.Pixelated
	pixelImageLabel.Visible = false
	pixelImageLabel.ZIndex = 2
	pixelImageLabel.Parent = mapRoot
	self.pixelImageLabel = pixelImageLabel

	-- Screen-space crisp vector overlay container (never blurs at high zoom!)
	local overlayRoot = Instance.new("Frame")
	overlayRoot.Name = "WorldVectorOverlay"
	overlayRoot.Size = UDim2.fromScale(1, 1)
	overlayRoot.BackgroundTransparency = 1
	overlayRoot.ClipsDescendants = true
	overlayRoot.ZIndex = 5
	overlayRoot.Parent = viewportParent
	self.overlayRoot = overlayRoot

	-- Cursor build preview ring
	local cursorRing = Instance.new("Frame")
	cursorRing.Name = "BuildCursorPreview"
	cursorRing.AnchorPoint = Vector2.new(0.5, 0.5)
	cursorRing.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
	cursorRing.BackgroundTransparency = 0.78
	cursorRing.Visible = false
	cursorRing.ZIndex = 9
	UiWidgets.AddCorner(cursorRing, 999)
	self.cursorRingStroke = UiWidgets.AddStroke(cursorRing, Color3.fromRGB(250, 204, 21), 2, 0.1)
	cursorRing.Parent = overlayRoot
	self.cursorRing = cursorRing

	-- Object pools
	self.scanFramePool = {} :: { Frame }
	self.rowFrames = {} :: { [number]: { Frame } }
	self.dirtyRows = {} :: { [number]: boolean }
	self.dirtyTiles = {} :: { number }
	self.fullDirty = true

	self.unitWidgets = {} :: { [number]: any }
	self.labelWidgets = {} :: { [number]: any }
	self.railFrames = {} :: { Frame }
	self.nukeRings = {} :: { [number]: Frame }
	self.shockwaves = {} :: { { frame: Frame, x: number, y: number, maxR: number, t: number } }
	self.spawnMarkers = {} :: { [number]: Frame }

	self.editableImage = nil :: EditableImage?
	self.pixelBuf = nil :: buffer?

	return self
end

function MapCanvas:_AllocScanFrame(parent: Instance): Frame
	local n = #self.scanFramePool
	local f: Frame
	if n > 0 then
		f = self.scanFramePool[n]
		self.scanFramePool[n] = nil
	else
		f = Instance.new("Frame")
		f.BorderSizePixel = 0
	end
	f.Visible = true
	f.Parent = parent
	return f
end

function MapCanvas:_RecycleRowFrames(y: number)
	local list = self.rowFrames[y]
	if list ~= nil then
		for i = #list, 1, -1 do
			local f = list[i]
			f.Visible = false
			self.scanFramePool[#self.scanFramePool + 1] = f
			list[i] = nil
		end
	end
end

function MapCanvas:LoadMap(mapId: string)
	local rawDef = MapRegistry.Get(mapId)
	local decoded = MapCodec.DecodeMap(rawDef)
	self.rawMap = rawDef
	self.map = decoded
	self.camera:SetMapSize(decoded.width, decoded.height)

	-- Clear previous visual pools
	for y, _ in pairs(self.rowFrames) do
		self:_RecycleRowFrames(y)
	end
	self.scanTerrainLayer:ClearAllChildren()
	for _, uw in pairs(self.unitWidgets) do
		uw.root:Destroy()
	end
	table.clear(self.unitWidgets)
	for _, lw in pairs(self.labelWidgets) do
		lw.root:Destroy()
	end
	table.clear(self.labelWidgets)
	for _, rf in ipairs(self.railFrames) do
		rf:Destroy()
	end
	table.clear(self.railFrames)
	for _, nr in pairs(self.nukeRings) do
		nr:Destroy()
	end
	table.clear(self.nukeRings)
	for _, sm in pairs(self.spawnMarkers) do
		sm:Destroy()
	end
	table.clear(self.spawnMarkers)

	-- Attempt Primary Engine: Native RGBA8 EditableImage!
	self.editableImage = nil
	self.usingEditableImage = false
	if not self.forceScanline then
		local ok, imgOrErr = pcall(function()
			local img = AssetService:CreateEditableImage({
				Size = Vector2.new(decoded.width, decoded.height),
			})
			self.pixelImageLabel.ImageContent = Content.fromObject(img)
			return img
		end)
		if ok and imgOrErr ~= nil then
			self.editableImage = imgOrErr
			self.pixelBuf = buffer.create(decoded.size * 4)
			self.usingEditableImage = true
			self.pixelImageLabel.Visible = true
		end
	end

	if not self.usingEditableImage then
		self.pixelImageLabel.Visible = false
		self:_BuildStaticScanlineTerrain()
	end

	self:MarkAllDirty()
end

function MapCanvas:_BuildStaticScanlineTerrain()
	local map = self.map
	if map == nil then
		return
	end
	local w, h = map.width, map.height
	local terrainBuf = map.terrain
	local rowH = 1 / h

	for y = 0, h - 1 do
		local rowOff = y * w
		local x = 0
		while x < w do
			local tb = buffer.readu8(terrainBuf, rowOff + x)
			local run = 1
			while x + run < w and buffer.readu8(terrainBuf, rowOff + x + run) == tb do
				run += 1
			end
			-- Deep open ocean matches `mapRoot.BackgroundColor3`, so skip pure deep water runs!
			local isLand = bit32.band(tb, 0x80) ~= 0
			local isShore = bit32.band(tb, 0x40) ~= 0
			if isLand or isShore then
				local seg = Instance.new("Frame")
				seg.BorderSizePixel = 0
				seg.BackgroundTransparency = 0
				seg.BackgroundColor3 = Theme.TerrainColor3LUT[tb + 1]
				seg.Position = UDim2.fromScale(x / w, y / h)
				seg.Size = UDim2.fromScale(run / w + 0.0005, rowH + 0.0008)
				seg.ZIndex = 1
				seg.Parent = self.scanTerrainLayer
			end
			x += run
		end
	end
end

function MapCanvas:MarkAllDirty()
	local map = self.map
	if map == nil then
		return
	end
	self.fullDirty = true
	for y = 0, map.height - 1 do
		self.dirtyRows[y] = true
	end
end

function MapCanvas:SetPreferScanline(prefer: boolean)
	if self.forceScanline == prefer then
		return
	end
	self.forceScanline = prefer
	if self.rawMap ~= nil then
		-- Preserve current map ownership & fallout across live renderer switch!
		local prevMap = self.map
		self:LoadMap(self.rawMap.id)
		if prevMap ~= nil and self.map ~= nil and prevMap.size == self.map.size then
			buffer.copy(self.map.owner, 0, prevMap.owner, 0, prevMap.size * 2)
			buffer.copy(self.map.fallout, 0, prevMap.fallout, 0, prevMap.size)
			self:MarkAllDirty()
		end
	end
end

function MapCanvas:UpdatePalettes(players: { any }, mySmallId: number, units: { any }?)
	self.mySmallId = mySmallId
	table.clear(self.friendlySet)
	table.clear(self.embargoSet)
	table.clear(self.playersById)

	local myObj: any = nil
	for _, p in ipairs(players) do
		self.playersById[p.smallId] = p
		if p.smallId == mySmallId then
			myObj = p
		end
	end

	if myObj ~= nil then
		self.friendlySet[mySmallId] = true
		for _, aid in ipairs(myObj.allies or {}) do
			self.friendlySet[aid] = true
		end
		for _, eid in ipairs(myObj.embargoes or {}) do
			self.embargoSet[eid] = true
		end
		if myObj.team ~= nil then
			for _, p in ipairs(players) do
				if p.team == myObj.team then
					self.friendlySet[p.smallId] = true
				end
			end
		end
	end

	for _, p in ipairs(players) do
		local sid = p.smallId
		local r, g, b = Theme.HexToRGB(p.colorHex)
		self.pR[sid], self.pG[sid], self.pB[sid] = r, g, b
		self.fillColor3[sid] = Color3.fromRGB(r, g, b)
		local fr, fg, fb = Theme.BlendTerritoryOverTerrain(190, 210, 142, r, g, b, false)
		self.blendedFillColor3[sid] = Color3.fromRGB(fr, fg, fb)
		local br, bg, bb = Theme.BorderRGB(r, g, b)
		if self.friendlySet[sid] and sid ~= mySmallId then
			bg = math.min(255, bg + 75)
		elseif self.embargoSet[sid] then
			br = math.min(255, br + 85)
		end
		self.borderU32[sid] = Theme.PackRGBA(br, bg, bb, 255)
		self.borderColor3[sid] = Color3.fromRGB(br, bg, bb)
		self.patternById[sid] = p.patternId or "none"
	end
end

-- Exact pixel shader evaluation for a single tile `ref`!
function MapCanvas:_ComputePixelU32(map: MapCodec.GameMap, ref: number): number
	local tb = buffer.readu8(map.terrain, ref)
	if self.terrainOnly then
		return Theme.TerrainU32LUT[tb + 1]
	end
	if buffer.readu8(map.fallout, ref) ~= 0 then
		local x = ref % map.width
		local y = math.floor(ref / map.width)
		return if (x * 7 + y * 13) % 5 == 0 then Theme.FalloutBrightU32 else Theme.FalloutDarkU32
	end
	local oid = buffer.readu16(map.owner, ref * 2)
	if oid == 0 then
		return Theme.TerrainU32LUT[tb + 1]
	end

	local w = map.width
	local x = ref % w
	local isBorder = (x == 0)
		or (x == w - 1)
		or (ref < w)
		or (ref >= map.size - w)
		or (buffer.readu16(map.owner, (ref - 1) * 2) ~= oid)
		or (buffer.readu16(map.owner, (ref + 1) * 2) ~= oid)
		or (buffer.readu16(map.owner, (ref - w) * 2) ~= oid)
		or (buffer.readu16(map.owner, (ref + w) * 2) ~= oid)

	if self.altView then
		if oid == self.mySmallId then
			return if isBorder then Theme.PackRGBA(16, 112, 48, 255) else Theme.Affiliation.SelfU32
		elseif self.friendlySet[oid] then
			return if isBorder then Theme.PackRGBA(161, 98, 7, 255) else Theme.Affiliation.AllyU32
		else
			return if isBorder then Theme.PackRGBA(153, 27, 27, 255) else Theme.Affiliation.EnemyU32
		end
	end

	if isBorder then
		return self.borderU32[oid] or Theme.PackRGBA(30, 30, 30, 255)
	end

	local pr = self.pR[oid] or 180
	local pg = self.pG[oid] or 180
	local pb = self.pB[oid] or 180
	local pat = self.patternById[oid]
	if pat ~= nil and pat ~= "none" then
		local y = math.floor(ref / w)
		if Theme.SamplePatternSecondary(pat, x, y) then
			pr = math.floor(pr * 0.80)
			pg = math.floor(pg * 0.80)
			pb = math.floor(pb * 0.80)
		end
	end
	if self.hoveredOwnerId == oid then
		pr = math.min(255, pr + 26)
		pg = math.min(255, pg + 26)
		pb = math.min(255, pb + 26)
	end

	local tr, tg, tblue = Theme.TerrainByteToRGB(tb)
	local fr, fg, fb = Theme.BlendTerritoryOverTerrain(tr, tg, tblue, pr, pg, pb, false)
	return Theme.PackRGBA(fr, fg, fb, 255)
end

function MapCanvas:_FlushEditableImage()
	local map = self.map
	local img = self.editableImage
	local pbuf = self.pixelBuf
	if map == nil or img == nil or pbuf == nil then
		return
	end

	if self.fullDirty then
		self.fullDirty = false
		table.clear(self.dirtyTiles)
		for ref = 0, map.size - 1 do
			buffer.writeu32(pbuf, ref * 4, self:_ComputePixelU32(map, ref))
		end
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(map.width, map.height), pbuf)
		return
	end

	local nDirty = #self.dirtyTiles
	if nDirty == 0 then
		return
	end

	local w = map.width
	local total = map.size
	for i = 1, nDirty do
		local ref = self.dirtyTiles[i]
		if ref >= 0 and ref < total then
			buffer.writeu32(pbuf, ref * 4, self:_ComputePixelU32(map, ref))
			-- Refresh 4 cardinal neighbors so borders stay 100% single-pixel exact!
			if ref % w > 0 then
				buffer.writeu32(pbuf, (ref - 1) * 4, self:_ComputePixelU32(map, ref - 1))
			end
			if ref % w < w - 1 then
				buffer.writeu32(pbuf, (ref + 1) * 4, self:_ComputePixelU32(map, ref + 1))
			end
			if ref >= w then
				buffer.writeu32(pbuf, (ref - w) * 4, self:_ComputePixelU32(map, ref - w))
			end
			if ref < total - w then
				buffer.writeu32(pbuf, (ref + w) * 4, self:_ComputePixelU32(map, ref + w))
			end
		end
	end
	table.clear(self.dirtyTiles)
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(map.width, map.height), pbuf)
end

-- Per-row RLE Scanline fallback flush (updates ONLY modified rows in < 0.2ms!)
function MapCanvas:_FlushScanlineRows()
	local map = self.map
	if map == nil then
		return
	end
	local w, h = map.width, map.height
	local ownerBuf = map.owner
	local falloutBuf = map.fallout
	local rowH = 1 / h

	for y, isDirty in pairs(self.dirtyRows) do
		if isDirty and y >= 0 and y < h then
			self:_RecycleRowFrames(y)
			if not self.terrainOnly then
				local list = self.rowFrames[y]
				if list == nil then
					list = {}
					self.rowFrames[y] = list
				end
				local rowOff = y * w
				local x = 0
				while x < w do
					local ref = rowOff + x
					local hasF = buffer.readu8(falloutBuf, ref) ~= 0
					local oid = buffer.readu16(ownerBuf, ref * 2)
					if not hasF and oid == 0 then
						x += 1
						continue
					end

					local isBorder = false
					if not hasF and oid > 0 then
						isBorder = (x == 0)
							or (x == w - 1)
							or (y == 0)
							or (y == h - 1)
							or (buffer.readu16(ownerBuf, (ref - 1) * 2) ~= oid)
							or (buffer.readu16(ownerBuf, (ref + 1) * 2) ~= oid)
							or (buffer.readu16(ownerBuf, (ref - w) * 2) ~= oid)
							or (buffer.readu16(ownerBuf, (ref + w) * 2) ~= oid)
					end

					local run = 1
					while x + run < w do
						local nRef = rowOff + x + run
						local nf = buffer.readu8(falloutBuf, nRef) ~= 0
						local noid = buffer.readu16(ownerBuf, nRef * 2)
						if nf ~= hasF or noid ~= oid then
							break
						end
						if not hasF then
							local nb = (x + run == w - 1)
								or (y == 0)
								or (y == h - 1)
								or (buffer.readu16(ownerBuf, (nRef - 1) * 2) ~= oid)
								or (buffer.readu16(ownerBuf, (nRef + 1) * 2) ~= oid)
								or (buffer.readu16(ownerBuf, (nRef - w) * 2) ~= oid)
								or (buffer.readu16(ownerBuf, (nRef + w) * 2) ~= oid)
							if nb ~= isBorder then
								break
							end
						end
						run += 1
					end

					local seg = self:_AllocScanFrame(self.scanTerritoryLayer)
					seg.Position = UDim2.fromScale(x / w, y / h)
					-- Zero transparency (100% opaque pre-blended RGB!) prevents ANY alpha stripe/overlap bleeding!
					seg.BackgroundTransparency = 0
					if hasF then
						seg.Size = UDim2.fromScale(run / w + 0.0005, rowH + 0.0008)
						seg.ZIndex = 4
						seg.BackgroundColor3 = Theme.FalloutColor3
					elseif self.altView then
						seg.Size = UDim2.fromScale(run / w + 0.0005, rowH + 0.0008)
						seg.ZIndex = if isBorder then 4 else 3
						if oid == self.mySmallId then
							seg.BackgroundColor3 = if isBorder then Color3.fromRGB(16, 112, 48) else Theme.Affiliation.SelfFill
						elseif self.friendlySet[oid] then
							seg.BackgroundColor3 = if isBorder then Color3.fromRGB(161, 98, 7) else Theme.Affiliation.AllyFill
						else
							seg.BackgroundColor3 = if isBorder then Color3.fromRGB(153, 27, 27) else Theme.Affiliation.EnemyFill
						end
					elseif isBorder then
						seg.Size = UDim2.fromScale(run / w + 0.0004, rowH + 0.0006)
						seg.ZIndex = 4
						seg.BackgroundColor3 = self.borderColor3[oid] or Color3.fromRGB(45, 55, 72)
					else
						seg.Size = UDim2.fromScale(run / w + 0.0006, rowH + 0.0009)
						seg.ZIndex = 3
						seg.BackgroundColor3 = self.blendedFillColor3[oid] or self.fillColor3[oid] or Color3.fromRGB(180, 180, 180)
					end
					list[#list + 1] = seg
					x += run
				end
			end
		end
	end
	table.clear(self.dirtyRows)
	self.fullDirty = false
end

function MapCanvas:SpawnShockwave(x: number, y: number, radius: number, kind: string)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundColor3 = if kind == "HydrogenBomb"
		then Color3.fromRGB(255, 237, 213)
		else Color3.fromRGB(254, 240, 138)
	ring.BackgroundTransparency = 0.35
	ring.BorderSizePixel = 0
	ring.ZIndex = 12
	UiWidgets.AddCorner(ring, 999)
	UiWidgets.AddStroke(ring, Color3.fromRGB(249, 115, 22), 3, 0.05)
	ring.Parent = self.overlayRoot
	table.insert(self.shockwaves, {
		frame = ring,
		x = x,
		y = y,
		maxR = radius,
		t = 0,
	})
end

function MapCanvas:SetRailEdges(railEdges: { { number } }?)
	for _, rf in ipairs(self.railFrames) do
		rf:Destroy()
	end
	table.clear(self.railFrames)
	local map = self.map
	if map == nil or railEdges == nil then
		return
	end
	local w, h = map.width, map.height
	for _, path in ipairs(railEdges) do
		for i = 1, #path - 3, 3 do
			local r1, r2 = path[i], path[math.min(#path, i + 3)]
			local x1, y1 = (r1 % w + 0.5) / w, (math.floor(r1 / w) + 0.5) / h
			local x2, y2 = (r2 % w + 0.5) / w, (math.floor(r2 / w) + 0.5) / h
			local seg = Instance.new("Frame")
			seg.BorderSizePixel = 0
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.BackgroundColor3 = Theme.RailroadColor3
			seg.BackgroundTransparency = 0.25
			seg.Position = UDim2.fromScale((x1 + x2) * 0.5, (y1 + y2) * 0.5)
			local dx, dy = x2 - x1, y2 - y1
			local len = math.sqrt(dx * dx + dy * dy)
			seg.Size = UDim2.new(len + 0.002, 0, 0, 2)
			seg.Rotation = math.deg(math.atan2(dy * h, dx * w))
			seg.ZIndex = 4
			seg.Parent = self.mapRoot
			table.insert(self.railFrames, seg)
		end
	end
end

-- Runs every RenderStepped (60 FPS) to position canvas, icons, rings, shockwaves & territory labels smoothly!
function MapCanvas:RenderFrame(stateSnapshot: any?, dt: number)
	local map = self.map
	if map == nil then
		return
	end

	-- 1. Flush dirty pixels or scanline rows
	if self.usingEditableImage then
		self:_FlushEditableImage()
	else
		self:_FlushScanlineRows()
	end

	-- 2. Apply Camera2D viewport transform to MapSurface
	local leftPx, topPx, widthPx, heightPx = self.camera:GetCanvasRect()
	self.mapRoot.Position = UDim2.fromOffset(leftPx, topPx)
	self.mapRoot.Size = UDim2.fromOffset(widthPx, heightPx)

	local scale = self.camera.scale
	local viewW, viewH = self.camera.viewW, self.camera.viewH

	-- 3. Armed build cursor preview ring
	if self.armedBuildType ~= nil then
		local sx, sy = self.camera:WorldToScreen(self.cursorTileX + 0.5, self.cursorTileY + 0.5)
		local rTiles = 6
		if self.armedBuildType == "DefensePost" then
			rTiles = Config.DEFENSE_POST_RANGE
		elseif self.armedBuildType == "SAMLauncher" then
			rTiles = Config.SamRange(1) * math.clamp(map.width / 700, 0.55, 1.0)
		elseif self.armedBuildType == "AtomBomb" then
			local _, outer = Config.NukeRadii("AtomBomb", map.width)
			rTiles = outer
		elseif self.armedBuildType == "HydrogenBomb" then
			local _, outer = Config.NukeRadii("HydrogenBomb", map.width)
			rTiles = outer
		elseif self.armedBuildType == "MIRV" then
			rTiles = 48
		end
		local diamPx = math.max(18, rTiles * 2 * scale)
		self.cursorRing.Size = UDim2.fromOffset(diamPx, diamPx)
		self.cursorRing.Position = UDim2.fromOffset(sx, sy)
		self.cursorRing.Visible = true
	else
		self.cursorRing.Visible = false
	end

	if stateSnapshot == nil then
		return
	end

	-- 4. Spawn Phase Markers
	local inSpawn = stateSnapshot.inSpawnPhase == true
	local seenSpawn: { [number]: boolean } = {}
	if inSpawn then
		for _, p in ipairs(stateSnapshot.players or {}) do
			if p.spawnX >= 0 and p.spawnY >= 0 and (p.playerType ~= "Bot" or scale > 3.5) then
				seenSpawn[p.smallId] = true
				local sm = self.spawnMarkers[p.smallId]
				if sm == nil then
					sm = Instance.new("Frame")
					sm.AnchorPoint = Vector2.new(0.5, 0.5)
					sm.BorderSizePixel = 0
					sm.ZIndex = 8
					UiWidgets.AddCorner(sm, 99)
					UiWidgets.AddStroke(sm, Color3.fromRGB(15, 23, 42), 2, 0.1)
					sm.Parent = self.overlayRoot
					self.spawnMarkers[p.smallId] = sm
				end
				local sx, sy = self.camera:WorldToScreen(p.spawnX + 0.5, p.spawnY + 0.5)
				local isMe = p.smallId == self.mySmallId
				local pulse = if isMe then (1 + 0.22 * math.sin(os.clock() * 7)) else 1
				local sz = (if isMe then 16 else 9) * pulse
				sm.BackgroundColor3 = if isMe then Color3.fromRGB(255, 213, 79) else Theme.HexToColor3(p.colorHex)
				sm.Size = UDim2.fromOffset(sz, sz)
				sm.Position = UDim2.fromOffset(sx, sy)
				sm.Visible = sx > -20 and sx < viewW + 20 and sy > -20 and sy < viewH + 20
			end
		end
	end
	for sid, sm in pairs(self.spawnMarkers) do
		if not seenSpawn[sid] then
			sm.Visible = false
		end
	end

	-- Helper for strict screen-space bounding-box non-overlap (with margin pad)
	local placedRects: { { number } } = {}
	for _, hr in ipairs(self.hudBlockedRects) do
		placedRects[#placedRects + 1] = hr
	end
	local function hitsAnyRect(x0: number, y0: number, x1: number, y1: number, pad: number): boolean
		if x0 < 10 or y0 < 10 or x1 > viewW - 10 or y1 > viewH - 10 then
			return true
		end
		for i = 1, #placedRects do
			local r = placedRects[i]
			if x0 - pad < r[3] and x1 + pad > r[1] and y0 - pad < r[4] and y1 + pad > r[2] then
				return true
			end
		end
		return false
	end

	-- 5. Dynamic Nation & Player Labels FIRST (sorted by empire size so big empires win & never overlap!)
	-- Pre-register on-screen unit circle footprints so Country Name Plates float cleanly around capital clusters!
	for _, u in ipairs(stateSnapshot.units or {}) do
		local ux, uy = self.camera:WorldToScreen(u.x + 0.5, u.y + 0.5)
		if ux > -24 and ux < viewW + 24 and uy > -24 and uy < viewH + 24 then
			local hr = math.clamp(scale * 1.6, 7, 13)
			placedRects[#placedRects + 1] = { ux - hr, uy - hr, ux + hr, uy + hr }
		end
	end

	local activeLabelIds: { [number]: boolean } = {}
	if self.showNames and not inSpawn and not self.terrainOnly and not self.hideWorldLabels then
		local candidates = {}
		for _, p in ipairs(stateSnapshot.players or {}) do
			if p.alive and p.tilesOwned > 0 then
				candidates[#candidates + 1] = p
			end
		end
		table.sort(candidates, function(a, b)
			if (a.smallId == self.mySmallId) ~= (b.smallId == self.mySmallId) then
				return a.smallId == self.mySmallId
			end
			return a.tilesOwned > b.tilesOwned
		end)

		local nudges = { 0, -24, 24, -44, 44 }
		for _, p in ipairs(candidates) do
			local boxPx = (p.labelSpan or 4) * scale
			local isMe = p.smallId == self.mySmallId
			if isMe or boxPx >= 34 then
				local sx, sy = self.camera:WorldToScreen(p.labelX + 0.5, p.labelY + 0.5)
				local fontPx = math.clamp(math.floor(boxPx * 0.20), 10, 15)
				local statusPrefix = ""
				if p.emoji ~= nil and p.emoji ~= "" then
					statusPrefix = p.emoji .. " "
				elseif p.isTraitor then
					statusPrefix = "💀 "
				end
				local fullName = statusPrefix .. p.name
				local hasFlag = p.flag ~= nil and p.flag ~= ""
				local estW = math.clamp(math.ceil(#fullName * fontPx * 0.58) + (if hasFlag then 22 else 10), 54, 168)
				local estH = fontPx * 2 + 6

				local chosenY: number? = nil
				for _, dy in ipairs(nudges) do
					local cy = sy + dy
					local x0, y0 = sx - estW * 0.5, cy - estH * 0.5
					local x1, y1 = sx + estW * 0.5, cy + estH * 0.5
					if not hitsAnyRect(x0, y0, x1, y1, 6) then
						chosenY = cy
						placedRects[#placedRects + 1] = { x0, y0, x1, y1 }
						break
					end
				end

				if chosenY ~= nil then
					activeLabelIds[p.smallId] = true
					local lw = self.labelWidgets[p.smallId]
					if lw == nil then
						local container = Instance.new("Frame")
						container.AnchorPoint = Vector2.new(0.5, 0.5)
						container.BackgroundColor3 = Color3.fromRGB(11, 17, 30)
						container.BackgroundTransparency = 0.42
						container.BorderSizePixel = 0
						container.ZIndex = 6
						UiWidgets.AddCorner(container, 5)

						local topRow = Instance.new("Frame")
						topRow.AnchorPoint = Vector2.new(0.5, 1)
						topRow.Position = UDim2.fromScale(0.5, 0.54)
						topRow.Size = UDim2.new(1, -8, 0, 16)
						topRow.BackgroundTransparency = 1
						topRow.Parent = container

						if hasFlag then
							UiWidgets.CreateFlagBadge(topRow, p.flag, UDim2.fromOffset(13, 9), UDim2.new(0, 1, 0.5, -4))
						end

						local nameLbl = Instance.new("TextLabel")
						nameLbl.Position = UDim2.fromOffset(if hasFlag then 17 else 0, 0)
						nameLbl.Size = UDim2.new(1, if hasFlag then -18 else 0, 1, 0)
						nameLbl.BackgroundTransparency = 1
						nameLbl.Font = Enum.Font.GothamBlack
						nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
						nameLbl.TextWrapped = false
						nameLbl.TextXAlignment = if hasFlag then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
						nameLbl.TextColor3 = Color3.new(1, 1, 1)
						nameLbl.TextStrokeColor3 = Color3.fromRGB(10, 15, 28)
						nameLbl.TextStrokeTransparency = 0.15
						nameLbl.Parent = topRow

						local troopLbl = Instance.new("TextLabel")
						troopLbl.AnchorPoint = Vector2.new(0.5, 0)
						troopLbl.Position = UDim2.fromScale(0.5, 0.54)
						troopLbl.Size = UDim2.new(1, -8, 0, 13)
						troopLbl.BackgroundTransparency = 1
						troopLbl.Font = Enum.Font.GothamBold
						troopLbl.TextTruncate = Enum.TextTruncate.AtEnd
						troopLbl.TextWrapped = false
						troopLbl.TextColor3 = Color3.fromRGB(226, 232, 240)
						troopLbl.TextStrokeColor3 = Color3.fromRGB(10, 15, 28)
						troopLbl.TextStrokeTransparency = 0.2
						troopLbl.Parent = container

						container.Parent = self.overlayRoot
						lw = { root = container, nameLbl = nameLbl, troopLbl = troopLbl }
						self.labelWidgets[p.smallId] = lw
					end

					lw.root.Size = UDim2.fromOffset(estW, estH)
					lw.nameLbl.TextSize = fontPx
					lw.nameLbl.Text = fullName
					lw.troopLbl.TextSize = math.max(9, fontPx - 2)
					lw.troopLbl.Text = Format.Troops(p.troops)
					lw.root.Position = UDim2.fromOffset(sx, chosenY)
					lw.root.Visible = true
				end
			end
		end
	end

	for sid, lw in pairs(self.labelWidgets) do
		if not activeLabelIds[sid] then
			lw.root.Visible = false
		end
	end

	-- 6. Structures, Ships, Trains, Nuclear Missiles & Non-Overlapping Unit Badges!
	local activeUnitIds: { [number]: boolean } = {}
	local activeNukeRings: { [number]: boolean } = {}

	for _, u in ipairs(stateSnapshot.units or {}) do
		activeUnitIds[u.id] = true
		local sx, sy = self.camera:WorldToScreen(u.x + 0.5, u.y + 0.5)
		local onScreen = sx > -40 and sx < viewW + 40 and sy > -40 and sy < viewH + 40

		local wObj = self.unitWidgets[u.id]
		if wObj == nil then
			local holder = Instance.new("Frame")
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
			holder.BackgroundTransparency = 0.15
			holder.BorderSizePixel = 0
			holder.ZIndex = 7
			UiWidgets.AddCorner(holder, 99)
			local stroke = UiWidgets.AddStroke(holder, Color3.new(1, 1, 1), 1.5, 0.2)

			local iconLbl = Instance.new("TextLabel")
			iconLbl.Size = UDim2.fromScale(0.84, 0.84)
			iconLbl.AnchorPoint = Vector2.new(0.5, 0.5)
			iconLbl.Position = UDim2.fromScale(0.5, 0.5)
			iconLbl.BackgroundTransparency = 1
			iconLbl.TextScaled = true
			iconLbl.Font = Enum.Font.GothamBold
			iconLbl.TextColor3 = Color3.new(1, 1, 1)
			iconLbl.Text = UNIT_ICONS[u.unitType] or "●"
			iconLbl.Parent = holder

			local badge = Instance.new("TextLabel")
			badge.AnchorPoint = Vector2.new(0.5, 0)
			badge.Position = UDim2.new(0.5, 0, 1, 2)
			badge.Size = UDim2.fromOffset(46, 12)
			badge.BackgroundTransparency = 1
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 9
			badge.TextWrapped = false
			badge.TextTruncate = Enum.TextTruncate.AtEnd
			badge.TextColor3 = Color3.fromRGB(254, 240, 138)
			badge.TextStrokeTransparency = 0.2
			badge.Parent = holder

			local rangeRing: Frame? = nil
			if u.unitType == "SAMLauncher" or u.unitType == "Warship" then
				local rr = Instance.new("Frame")
				rr.AnchorPoint = Vector2.new(0.5, 0.5)
				rr.Position = UDim2.fromScale(0.5, 0.5)
				rr.BackgroundTransparency = 1
				rr.Visible = false
				UiWidgets.AddCorner(rr, 999)
				UiWidgets.AddStroke(
					rr,
					if u.unitType == "SAMLauncher" then Color3.fromRGB(34, 211, 238) else Color3.fromRGB(96, 165, 250),
					1.3,
					0.55
				)
				rr.Parent = holder
				rangeRing = rr
			end

			holder.Parent = self.overlayRoot
			wObj = { root = holder, icon = iconLbl, badge = badge, stroke = stroke, rangeRing = rangeRing }
			self.unitWidgets[u.id] = wObj
		end

		wObj.root.Visible = onScreen and not self.terrainOnly
		if onScreen and not self.terrainOnly then
			local basePx = math.clamp(scale * 3.0, 11, 22)
			if u.unitType == "TradeShip" or u.unitType == "Train" then
				basePx = math.clamp(scale * 2.0, 7, 15)
			elseif u.unitType == "AtomBomb" or u.unitType == "HydrogenBomb" or u.unitType == "MIRV" then
				basePx = math.clamp(scale * 3.4, 14, 26)
			end
			wObj.root.Size = UDim2.fromOffset(basePx, basePx)
			wObj.root.Position = UDim2.fromOffset(sx, sy)
			wObj.stroke.Color = self.fillColor3[u.ownerSmallId] or Color3.new(1, 1, 1)

			local candBadge = ""
			if not self.hideWorldLabels and scale >= 2.8 then
				if u.underConstruction then
					candBadge = string.format("%d%%", math.floor((u.constructionProgress or 0) * 100))
				elseif u.unitType == "TransportShip" then
					candBadge = Format.Troops(u.troops or 0)
				elseif u.unitType == "Warship" and (u.hp or 100) < (u.maxHp or 100) then
					candBadge = string.format("%d%%", math.floor((u.hp / math.max(1, u.maxHp)) * 100))
				elseif (u.level or 1) > 1 then
					candBadge = "Lv" .. tostring(u.level)
				end
			end
			if candBadge ~= "" then
				local bx0, by0 = sx - 22, sy + basePx * 0.5 + 1
				local bx1, by1 = sx + 22, by0 + 12
				if not hitsAnyRect(bx0, by0, bx1, by1, 3) then
					wObj.badge.Text = candBadge
					placedRects[#placedRects + 1] = { bx0, by0, bx1, by1 }
				else
					wObj.badge.Text = ""
				end
			else
				wObj.badge.Text = ""
			end

			if wObj.rangeRing ~= nil then
				if u.unitType == "SAMLauncher" and u.ownerSmallId == self.mySmallId and scale >= 2.6 and not self.hideWorldLabels then
					local dPx = Config.SamRange(u.level or 1) * math.clamp(map.width / 700, 0.55, 1.0) * 2 * scale
					wObj.rangeRing.Size = UDim2.fromOffset(dPx, dPx)
					wObj.rangeRing.Visible = true
				elseif u.unitType == "Warship" and self.selectedWarshipId == u.id then
					local dPx = 84 * scale
					wObj.rangeRing.Size = UDim2.fromOffset(dPx, dPx)
					wObj.rangeRing.Visible = true
				else
					wObj.rangeRing.Visible = false
				end
			end
		end

		-- Draw pulsing red ground target circle for inbound nukes!
		if u.unitType == "AtomBomb" or u.unitType == "HydrogenBomb" or u.unitType == "MIRV" or u.unitType == "MIRVWarhead" then
			activeNukeRings[u.id] = true
			local nr = self.nukeRings[u.id]
			if nr == nil then
				nr = Instance.new("Frame")
				nr.AnchorPoint = Vector2.new(0.5, 0.5)
				nr.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
				nr.BackgroundTransparency = 0.80
				nr.ZIndex = 6
				UiWidgets.AddCorner(nr, 999)
				UiWidgets.AddStroke(nr, Color3.fromRGB(239, 68, 68), 2, 0.15)
				nr.Parent = self.overlayRoot
				self.nukeRings[u.id] = nr
			end
			local _, outerR = Config.NukeRadii(u.unitType, map.width)
			local dPx = math.max(16, outerR * 2 * scale)
			local dxScreen, dyScreen = self.camera:WorldToScreen(u.dstX + 0.5, u.dstY + 0.5)
			nr.Size = UDim2.fromOffset(dPx, dPx)
			nr.Position = UDim2.fromOffset(dxScreen, dyScreen)
			nr.BackgroundTransparency = 0.72 + 0.16 * math.sin(os.clock() * 12)
			nr.Visible = true
		end
	end

	for uid, wObj in pairs(self.unitWidgets) do
		if not activeUnitIds[uid] then
			wObj.root:Destroy()
			self.unitWidgets[uid] = nil
		end
	end
	for uid, nr in pairs(self.nukeRings) do
		if not activeNukeRings[uid] then
			nr:Destroy()
			self.nukeRings[uid] = nil
		end
	end

	-- 7. Shockwave explosion rings
	for i = #self.shockwaves, 1, -1 do
		local sw = self.shockwaves[i]
		sw.t += dt * 1.65
		if sw.t >= 1 then
			sw.frame:Destroy()
			table.remove(self.shockwaves, i)
		else
			local sx, sy = self.camera:WorldToScreen(sw.x + 0.5, sw.y + 0.5)
			local curDiam = math.max(10, sw.maxR * 2 * scale * (0.2 + 0.85 * sw.t))
			sw.frame.Size = UDim2.fromOffset(curDiam, curDiam)
			sw.frame.Position = UDim2.fromOffset(sx, sy)
			sw.frame.BackgroundTransparency = 0.25 + 0.75 * sw.t
		end
	end
end

return MapCanvas
