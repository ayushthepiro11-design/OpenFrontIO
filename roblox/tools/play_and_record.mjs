#!/usr/bin/env node
/**
 * Plays a full multi-act OpenFront Roblox session LIVE inside real Luau WebAssembly (`luau-web`)
 * using our exact unmodified `roblox/src/` Luau engine & pixel shader (`MapCanvas.luau`),
 * recording exact RGBA8 `EditableImage` buffers + world/HUD telemetry for 1280x720 HD video & screenshots!
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { LuauState } from "./load_luau.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const SRC_ROOT = path.join(REPO_ROOT, "roblox", "src");
const OUT_RAW_DIR = "/tmp/of_recording";

fs.rmSync(OUT_RAW_DIR, { recursive: true, force: true });
fs.mkdirSync(OUT_RAW_DIR, { recursive: true });

function collectLuauFiles(dir, prefix = "") {
  const entries = {};
  for (const name of fs.readdirSync(dir).sort()) {
    const full = path.join(dir, name);
    const rel = prefix ? `${prefix}/${name}` : name;
    if (fs.statSync(full).isDirectory()) {
      Object.assign(entries, collectLuauFiles(full, rel));
    } else if (name.endsWith(".luau")) {
      entries[rel] = fs.readFileSync(full, "utf8");
    }
  }
  return entries;
}

const files = collectLuauFiles(SRC_ROOT);
const moduleClosures = Object.entries(files)
  .map(
    ([rel, src]) =>
      `MODULES[${JSON.stringify(rel)}] = function(script)\n${src}\nend`,
  )
  .join("\n\n");

// Callback from Luau -> Node to write each captured frame's RGBA map buffer & JSON telemetry directly to disk!
let frameIdx = 0;
let lastMapKey = "";
const metaStream = fs.createWriteStream(path.join(OUT_RAW_DIR, "frames.jsonl"));

function emitFrame(rgbaB64Str, metaJsonStr) {
  const idx = frameIdx++;
  const rawBuf = Buffer.from(rgbaB64Str, "base64");
  const rgbaPath = path.join(
    OUT_RAW_DIR,
    `rgba_${String(idx).padStart(4, "0")}.bin`,
  );
  fs.writeFileSync(rgbaPath, rawBuf);
  metaStream.write(metaJsonStr + "\n");
  if (idx % 60 === 0) {
    const parsed = JSON.parse(metaJsonStr);
    if (parsed.phase !== lastMapKey) {
      lastMapKey = parsed.phase;
    }
    console.log(
      `[luau-recorder] Captured frame ${idx} (${parsed.phase} on ${parsed.mapId}, tick=${parsed.ticks})`,
    );
  }
}

const RECORD_SCRIPT = `
local EMIT_FRAME = ...
local MODULES = {}
local MODULE_CACHE = {}

local function makeSignal()
	local listeners = {}
	local sig = {}
	function sig:Connect(fn)
		table.insert(listeners, fn)
		return { Disconnect = function() end }
	end
	function sig:Fire(...)
		for _, fn in ipairs(table.clone(listeners)) do
			fn(...)
		end
	end
	return sig
end

local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v) return Color3.new(h, s, v) end

local Vector2 = {}
Vector2.__index = Vector2
function Vector2.new(x, y)
	local mx, my = x or 0, y or 0
	return setmetatable({ X = mx, Y = my, Magnitude = math.sqrt(mx * mx + my * my) }, Vector2)
end
function Vector2.__sub(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
function Vector2.__add(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
function Vector2.__mul(a, s)
	if type(s) == "number" then return Vector2.new(a.X * s, a.Y * s) end
	return Vector2.new(a.X * s.X, a.Y * s.Y)
end
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)

local Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end, zero = { X = 0, Y = 0, Z = 0 } }
local UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
local UDim2 = {
	new = function(sx, ox, sy, oy) return { X = UDim.new(sx, ox), Y = UDim.new(sy, oy) } end,
	fromScale = function(sx, sy) return { X = UDim.new(sx, 0), Y = UDim.new(sy, 0) } end,
	fromOffset = function(ox, oy) return { X = UDim.new(0, ox), Y = UDim.new(0, oy) } end,
}
local Content = { fromObject = function(obj) return { _object = obj } end }
local Enum = setmetatable({}, {
	__index = function(self, g)
		local grp = setmetatable({}, {
			__index = function(gg, k)
				local it = { Name = k, EnumType = g, Value = #k }
				rawset(gg, k, it)
				return it
			end,
		})
		rawset(self, g, grp)
		return grp
	end,
})
local task = { spawn = function(fn, ...) fn(...) end, defer = function(fn, ...) fn(...) end, delay = function() end, wait = function(t) return t or 0.016 end }

local SERVICES = {}
local Instance
local function Instance_new(className, parent)
	local children = {}
	local props = {
		ClassName = className, Name = className, Parent = nil, Visible = true,
		Size = UDim2.fromOffset(100, 100), Position = UDim2.fromOffset(0, 0),
		AbsoluteSize = Vector2.new(1280, 720), AbsolutePosition = Vector2.new(0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), TextColor3 = Color3.new(1, 1, 1), Text = "",
		Activated = makeSignal(), InputBegan = makeSignal(), InputChanged = makeSignal(), InputEnded = makeSignal(),
	}
	local inst = {}
	setmetatable(inst, {
		__index = function(_t, k)
			local v = rawget(props, k)
			if v ~= nil then return v end
			for _, ch in ipairs(children) do if ch.Name == k then return ch end end
			return nil
		end,
		__newindex = function(_t, k, v)
			if k == "Parent" then
				local oldP = rawget(props, "Parent")
				if oldP ~= nil then oldP:_RemoveChild(inst) end
				rawset(props, "Parent", v)
				if v ~= nil then v:_AddChild(inst) end
			else
				rawset(props, k, v)
			end
		end,
	})
	function props:_AddChild(ch) table.insert(children, ch) end
	function props:_RemoveChild(ch) for i, c in ipairs(children) do if c == ch then table.remove(children, i) break end end end
	function props:FindFirstChild(name) for _, ch in ipairs(children) do if ch.Name == name then return ch end end return nil end
	function props:WaitForChild(name) return assert(props:FindFirstChild(name), "Missing child " .. tostring(name)) end
	function props:GetChildren() return table.clone(children) end
	function props:ClearAllChildren() for i = #children, 1, -1 do children[i].Parent = nil end end
	function props:Destroy() props:ClearAllChildren(); inst.Parent = nil end
	function props:IsA(tc) return props.ClassName == tc end
	if parent ~= nil then inst.Parent = parent end
	return inst
end
Instance = { new = Instance_new }

SERVICES.Workspace = Instance.new("Workspace")
SERVICES.ReplicatedStorage = Instance.new("ReplicatedStorage")
SERVICES.ServerScriptService = Instance.new("ServerScriptService")
SERVICES.SoundService = Instance.new("SoundService")
SERVICES.StarterGui = Instance.new("StarterGui")
SERVICES.AssetService = {
	CreateEditableImage = function(_self, spec)
		return {
			Size = spec.Size,
			LastBuf = nil,
			WritePixelsBuffer = function(img, _pos, _sz, buf)
				img.LastBuf = buf
			end,
		}
	end,
}

local game = { GetService = function(_s, nm) return assert(SERVICES[nm], "Missing service " .. nm) end, BindToClose = function() end }
local workspace = SERVICES.Workspace

local function executeLuauInstance(inst)
	return assert(MODULES[inst._relPath])(inst)
end
local function require(modInst)
	if MODULE_CACHE[modInst] == nil then
		MODULE_CACHE[modInst] = executeLuauInstance(modInst)
	end
	return MODULE_CACHE[modInst]
end

${moduleClosures}

local sharedFolder = Instance.new("Folder", SERVICES.ReplicatedStorage); sharedFolder.Name = "OpenFrontShared"
local mapsFolder = Instance.new("Folder", sharedFolder); mapsFolder.Name = "Maps"
local serverFolder = Instance.new("Folder", SERVICES.ServerScriptService); serverFolder.Name = "OpenFrontServer"
local clientFolder = Instance.new("Folder"); clientFolder.Name = "OpenFrontClient"

for relPath, _ in pairs(MODULES) do
	local parts = string.split(relPath, "/")
	local parentInst = if parts[1] == "Shared" then sharedFolder elseif parts[1] == "Server" then serverFolder else clientFolder
	for i = 2, #parts - 1 do
		local sub = parentInst:FindFirstChild(parts[i]) or Instance.new("Folder", parentInst)
		sub.Name = parts[i]
		parentInst = sub
	end
	local leaf = parts[#parts]
	local inst = Instance.new("ModuleScript", parentInst)
	inst.Name = leaf:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
	inst._relPath = relPath
end

local Config = require(sharedFolder.Config)
local MapCodec = require(sharedFolder.MapCodec)
local MapRegistry = require(mapsFolder.MapRegistry)
local NetCodec = require(sharedFolder.NetCodec)
local SimEngine = require(serverFolder.SimEngine)
local Camera2D = require(clientFolder.Camera2D)
local MapCanvas = require(clientFolder.MapCanvas)

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_ARR = {}
for i = 1, 64 do B64_ARR[i - 1] = string.sub(B64_CHARS, i, i) end

local function base64EncodeBuffer(buf)
	local n = buffer.len(buf)
	local out = table.create(math.ceil(n / 3) * 4)
	local oi = 1
	local i = 0
	while i + 2 < n do
		local a = buffer.readu8(buf, i)
		local b = buffer.readu8(buf, i + 1)
		local c = buffer.readu8(buf, i + 2)
		local triple = a * 65536 + b * 256 + c
		out[oi] = B64_ARR[bit32.band(bit32.rshift(triple, 18), 63)]
		out[oi + 1] = B64_ARR[bit32.band(bit32.rshift(triple, 12), 63)]
		out[oi + 2] = B64_ARR[bit32.band(bit32.rshift(triple, 6), 63)]
		out[oi + 3] = B64_ARR[bit32.band(triple, 63)]
		oi += 4
		i += 3
	end
	if i < n then
		local a = buffer.readu8(buf, i)
		local b = if i + 1 < n then buffer.readu8(buf, i + 1) else 0
		local triple = a * 65536 + b * 256
		out[oi] = B64_ARR[bit32.band(bit32.rshift(triple, 18), 63)]
		out[oi + 1] = B64_ARR[bit32.band(bit32.rshift(triple, 12), 63)]
		out[oi + 2] = if i + 1 < n then B64_ARR[bit32.band(bit32.rshift(triple, 6), 63)] else "="
		out[oi + 3] = "="
	end
	return table.concat(out)
end
local function jsonEscape(s)
	return (tostring(s):gsub("\\\\", "\\\\\\\\"):gsub('"', '\\\\"'):gsub("\\n", "\\\\n"))
end
local function toJson(val)
	local tv = type(val)
	if tv == "nil" then return "null"
	elseif tv == "boolean" then return if val then "true" else "false"
	elseif tv == "number" then
		if val ~= val or val == math.huge or val == -math.huge then return "0" end
		return string.format("%.4g", val)
	elseif tv == "string" then
		return '"' .. jsonEscape(val) .. '"'
	elseif tv == "table" then
		local isArr = (#val > 0) or next(val) == nil
		if isArr then
			local parts = {}
			for i = 1, #val do parts[i] = toJson(val[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in pairs(val) do
				table.insert(parts, '"' .. jsonEscape(k) .. '":' .. toJson(v))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

local viewportFrame = Instance.new("Frame")
viewportFrame.Size = UDim2.fromOffset(1280, 720)
local cam = Camera2D.new(500, 250, 1280, 720)
local canvas = MapCanvas.new(viewportFrame, cam)

local function syncSimToCanvas(sim, mySmallId, full)
	local payload = sim:BuildTickPayload(full)
	if canvas.map == nil or canvas.map.id ~= payload.mapId then
		canvas:LoadMap(payload.mapId)
	end
	canvas:UpdatePalettes(payload.players, mySmallId, payload.units)
	if payload.tileBuffer ~= nil then
		if payload.isFullSnapshot then
			NetCodec.DecodeFullOwnerSnapshot(payload.tileBuffer, canvas.map.owner, canvas.map.size)
			canvas:MarkAllDirty()
		else
			NetCodec.ApplyTileDeltas(payload.tileBuffer, canvas.map.owner, canvas.map.width, canvas.dirtyRows, canvas.dirtyTiles)
		end
	end
	if payload.falloutBuffer ~= nil then
		NetCodec.ApplyFalloutDeltas(payload.falloutBuffer, canvas.map.fallout, canvas.map.width, canvas.dirtyRows, canvas.dirtyTiles)
	end
	canvas:_FlushEditableImage()
	return payload
end

local function capture(sim, payload, mySmallId, phase, uiMode, extra)
	local topPlayers = {}
	local sorted = table.clone(payload.players)
	table.sort(sorted, function(a, b)
		if a.tilesOwned ~= b.tilesOwned then return a.tilesOwned > b.tilesOwned end
		return a.troops > b.troops
	end)
	for i = 1, math.min(18, #sorted) do
		local p = sorted[i]
		table.insert(topPlayers, {
			sid = p.smallId,
			name = p.name,
			flag = p.flag or "",
			col = p.colorHex,
			type = p.playerType,
			tiles = p.tilesOwned,
			troops = math.floor(p.troops),
			maxTroops = math.floor(p.maxTroops),
			rate = math.floor(p.troopRatePerSec or 0),
			gold = math.floor(p.gold),
			atk = math.floor(p.attackingTroops or 0),
			lx = p.labelX,
			ly = p.labelY,
			lspan = p.labelSpan,
			sx = p.spawnX,
			sy = p.spawnY,
			alive = p.alive,
			traitor = p.isTraitor,
			emoji = p.emoji or "",
			counts = p.unitCounts or {},
		})
	end

	local meSummary = nil
	for _, p in ipairs(payload.players) do
		if p.smallId == mySmallId then
			meSummary = {
				sid = p.smallId, name = p.name, flag = p.flag or "in", col = p.colorHex,
				tiles = p.tilesOwned, troops = math.floor(p.troops), maxTroops = math.floor(p.maxTroops),
				rate = math.floor(p.troopRatePerSec or 0), gold = math.floor(p.gold),
				atk = math.floor(p.attackingTroops or 0), lx = p.labelX, ly = p.labelY,
				sx = p.spawnX, sy = p.spawnY, alive = p.alive, counts = p.unitCounts or {},
			}
			break
		end
	end

	local unitsOut = {}
	for _, u in ipairs(payload.units or {}) do
		table.insert(unitsOut, {
			id = u.id, t = u.unitType, o = u.ownerSmallId,
			x = u.x, y = u.y, dx = u.dstX, dy = u.dstY,
			lv = u.level, hp = u.hp, mhp = u.maxHp, vet = u.veterancy,
			uc = u.underConstruction, cp = u.constructionProgress or 0,
			tr = math.floor(u.troops or 0),
		})
	end

	local meta = {
		phase = phase,
		uiMode = uiMode,
		mapId = payload.mapId,
		mapName = sim.rawMap.name,
		mapW = canvas.map.width,
		mapH = canvas.map.height,
		numLand = canvas.map.numLandTiles,
		ticks = payload.ticks,
		inSpawn = payload.inSpawnPhase,
		spawnLeft = payload.spawnSecondsLeft,
		elapsed = payload.elapsedSeconds,
		winPct = payload.winPercentRequired,
		camX = cam.centerX,
		camY = cam.centerY,
		camScale = cam.scale,
		altView = canvas.altView,
		mySid = mySmallId,
		me = meSummary,
		players = topPlayers,
		units = unitsOut,
		rails = payload.railEdges or {},
		explosions = payload.explosions or {},
		events = payload.events or {},
		alerts = (payload.alertsByPlayer and payload.alertsByPlayer[mySmallId]) or {},
		extra = extra or {},
	}
	EMIT_FRAME(base64EncodeBuffer(canvas.pixelBuf), toJson(meta))
end

-- ============================================================================
-- ACT 1 (Frames 0..83): Main Menu over Live Animated AI World Battle + Host Modal
-- ============================================================================
local previewCfg = Config.DefaultGameConfig(true)
previewCfg.mapId = "World"
previewCfg.bots = 55
previewCfg.goldMultiplier = 4
local previewSim = SimEngine.new(previewCfg, {}, true)
for _ = 1, 90 do previewSim:Step() end
syncSimToCanvas(previewSim, 0, true)
cam:FocusOn(295, 112, 2.75)

for f = 1, 44 do
	previewSim:Step()
	cam:FocusOn(295 + f * 0.45, 112, 2.75)
	local pl = syncSimToCanvas(previewSim, 0, false)
	capture(previewSim, pl, 0, "Act 1: Main Menu & Live World Preview", "MainMenu", { sfx = if f == 1 then "hover" else "" })
end

-- Open Host Custom Match Modal showing all 10 Maps (World, Shinobi World, Europe, Asia...)
local mapCards = {}
for _, md in ipairs(MapRegistry.List) do
	table.insert(mapCards, { id = md.id, name = md.name, nations = #md.nations, preview = md.preview, pw = md.previewW, ph = md.previewH })
end
for f = 1, 40 do
	previewSim:Step()
	cam:FocusOn(315 + f * 0.35, 112, 2.75)
	local pl = syncSimToCanvas(previewSim, 0, false)
	local selMap = if f < 22 then "World" else "ShinobiWorld"
	capture(previewSim, pl, 0, "Act 1B: Host Custom Lobby & 10-Map Picker", "HostModal", {
		selectedMap = selMap,
		maps = if f == 1 then mapCards else nil,
		sfx = if f == 1 or f == 22 then "click" else "",
	})
end

-- ============================================================================
-- ACT 2 (Frames 84..148): Spawn Phase Selection in India & Early Expansion on World Map!
-- ============================================================================
local matchCfg = Config.DefaultGameConfig(true)
matchCfg.mapId = "World"
matchCfg.bots = 18
matchCfg.difficulty = "Hard"
matchCfg.instantBuild = false
matchCfg.goldMultiplier = 4

local worldSim = SimEngine.new(matchCfg, {
	{ userId = 777001, name = "Republic of India", flag = "in", colorHex = "#06b6d4", patternId = "none" },
}, false)

-- Locate Northern India / Gangetic plain on World Map!
local indiaX, indiaY = 352, 112
for _, nat in ipairs(worldSim.rawMap.nations) do
	if string.find(string.lower(nat.name), "india") or string.find(string.lower(nat.name), "delhi") or string.find(string.lower(nat.name), "bharat") then
		indiaX, indiaY = math.clamp(nat.x + 6, 10, worldSim.map.width - 10), math.clamp(nat.y + 4, 10, worldSim.map.height - 10)
		break
	end
end
worldSim:ChooseSpawn(777001, indiaX, indiaY)
local meWorld = worldSim.playersByUserId[777001]
syncSimToCanvas(worldSim, meWorld.smallId, true)
cam:FocusOn(indiaX, indiaY, 4.2)

-- Show Spawn Phase countdown smoothly
for f = 1, 34 do
	worldSim:Step()
	worldSim:Step()
	cam:FocusOn(indiaX, indiaY, 4.2 + f * 0.04)
	local pl = syncSimToCanvas(worldSim, meWorld.smallId, false)
	capture(worldSim, pl, meWorld.smallId, "Act 2: Spawn Phase Selection (India)", "InGame", {
		sfx = if f == 1 then "click" else "",
	})
end

-- Unlock borders & expand rapidly across South Asia + Bay of Bengal!
while worldSim.inSpawnPhase do worldSim:Step() end
meWorld.troops = 140_000
meWorld.gold = 4_500_000

for f = 1, 70 do
	if f % 8 == 1 then
		worldSim:StartLandAttack(meWorld, 0, meWorld.troops * 0.45, nil)
		for _, other in ipairs(worldSim.playersList) do
			if other ~= meWorld and other.alive and other.tilesOwned < meWorld.tilesOwned * 1.4 then
				local dx, dy = other.labelX - meWorld.labelX, other.labelY - meWorld.labelY
				if dx * dx + dy * dy < 38 * 38 then
					worldSim:StartLandAttack(meWorld, other.smallId, meWorld.troops * 0.35, nil)
					break
				end
			end
		end
	end
	-- Step 3 ticks per frame so continents consolidate into crisp solid empires just like openfront.io!
	worldSim:Step()
	worldSim:Step()
	worldSim:Step()
	cam:FocusOn(meWorld.labelX, meWorld.labelY, math.max(3.1, 4.8 - f * 0.022))
	local pl = syncSimToCanvas(worldSim, meWorld.smallId, false)
	capture(worldSim, pl, meWorld.smallId, "Act 2B: Rapid Border Expansion", "InGame", {
		radialOpen = (f >= 44 and f <= 66),
		sfx = if f == 1 or f == 44 then "attack" else "",
	})
end

-- ============================================================================
-- ACT 3: Economy Boom — Cities, Factories, Railroads, Gold Trains, Ports, Trade Ships & Warships!
-- ============================================================================
local ownedWorld = {}
local coastalWorld = {}
for ref = 0, worldSim.map.size - 1 do
	if MapCodec.GetOwner(worldSim.map, ref) == meWorld.smallId then
		table.insert(ownedWorld, ref)
		if MapCodec.IsShoreLand(worldSim.map, ref) then
			table.insert(coastalWorld, ref)
		end
	end
end

meWorld.gold = 18_000_000
worldSim.config.instantBuild = true
if #ownedWorld >= 20 then
	worldSim:BuildUnit(meWorld, "City", ownedWorld[math.floor(#ownedWorld * 0.20)])
	worldSim:BuildUnit(meWorld, "Factory", ownedWorld[math.floor(#ownedWorld * 0.40)])
	worldSim:BuildUnit(meWorld, "City", ownedWorld[math.floor(#ownedWorld * 0.60)])
	worldSim:BuildUnit(meWorld, "MissileSilo", ownedWorld[math.floor(#ownedWorld * 0.50)])
	worldSim:BuildUnit(meWorld, "SAMLauncher", ownedWorld[math.floor(#ownedWorld * 0.72)])
	worldSim:BuildUnit(meWorld, "DefensePost", ownedWorld[math.floor(#ownedWorld * 0.12)])
end
for i = 1, math.min(3, #coastalWorld) do
	local cRef = coastalWorld[math.floor((i / 3) * #coastalWorld)]
	worldSim:BuildUnit(meWorld, "Port", cRef)
	local wRef = MapCodec.AdjacentWater(worldSim.map, cRef)
	if wRef ~= nil and i <= 2 then
		worldSim:BuildUnit(meWorld, "Warship", wRef)
	end
end
-- Launch an amphibious Boat invasion across the Indian Ocean too!
for _, other in ipairs(worldSim.playersList) do
	if other ~= meWorld and other.alive and other.tilesOwned > 25 then
		local dx = math.abs(other.labelX - meWorld.labelX)
		if dx > 25 and dx < 95 then
			worldSim:LaunchBoatAttack(meWorld, other.labelY * worldSim.map.width + other.labelX, meWorld.troops * 0.28)
			break
		end
	end
end

for f = 1, 78 do
	worldSim:Step()
	worldSim:Step()
	if f % 14 == 0 then
		for _, other in ipairs(worldSim.playersList) do
			if other ~= meWorld and other.alive and math.abs(other.labelX - meWorld.labelX) < 55 and math.abs(other.labelY - meWorld.labelY) < 45 then
				worldSim:StartLandAttack(meWorld, other.smallId, meWorld.troops * 0.35, nil)
				break
			end
		end
	end
	cam:FocusOn(meWorld.labelX, meWorld.labelY + 6, 4.35)
	local pl = syncSimToCanvas(worldSim, meWorld.smallId, false)
	capture(worldSim, pl, meWorld.smallId, "Act 3: Cities, Railroads, Trade Ships & Naval Invasion", "InGame", {
		buildMenuOpen = (f >= 14 and f <= 44),
		sfx = if f == 1 then "build" elseif f == 14 then "click" elseif f == 46 then "boat" else "",
	})
end

-- ============================================================================
-- ACT 4: Thermonuclear Escalation — Atom Bomb + Hydrogen Bomb + Multi-Warhead MIRV Carpet Strike!
-- ============================================================================
meWorld.gold = 95_000_000
-- Build 3 Missile Silos so we can salvo AtomBomb + HydrogenBomb + MIRV together in cinematic glory!
if #ownedWorld >= 30 then
	worldSim:BuildUnit(meWorld, "MissileSilo", ownedWorld[math.floor(#ownedWorld * 0.30)])
	worldSim:BuildUnit(meWorld, "MissileSilo", ownedWorld[math.floor(#ownedWorld * 0.66)])
end

local nukeTarget = nil
local bestEnemyTiles = 0
for _, other in ipairs(worldSim.playersList) do
	if other ~= meWorld and other.alive then
		local dx = math.abs(other.labelX - meWorld.labelX)
		local dy = math.abs(other.labelY - meWorld.labelY)
		if dx < 120 and dy < 75 and other.tilesOwned > bestEnemyTiles then
			bestEnemyTiles = other.tilesOwned
			nukeTarget = other
		end
	end
end
if nukeTarget ~= nil then
	local tref = nukeTarget.labelY * worldSim.map.width + nukeTarget.labelX
	worldSim:BuildUnit(meWorld, "MIRV", tref)
	worldSim:BuildUnit(meWorld, "HydrogenBomb", math.clamp(tref + 14, 0, worldSim.map.size - 1))
	worldSim:BuildUnit(meWorld, "AtomBomb", math.clamp(tref - 14, 0, worldSim.map.size - 1))
end

local midX = if nukeTarget then (meWorld.labelX + nukeTarget.labelX) * 0.5 else meWorld.labelX
local midY = if nukeTarget then (meWorld.labelY + nukeTarget.labelY) * 0.5 else meWorld.labelY

for f = 1, 88 do
	worldSim:Step()
	cam:FocusOn(midX, midY, 3.25)
	local pl = syncSimToCanvas(worldSim, meWorld.smallId, false)
	local sfx = ""
	if f == 1 then sfx = "launch"
	elseif f == 10 then sfx = "alert"
	elseif #(pl.explosions or {}) > 0 then sfx = "boom"
	end
	capture(worldSim, pl, meWorld.smallId, "Act 4: MIRV Multi-Warhead & Hydrogen Bomb Salvo", "InGame", { sfx = sfx })
end

-- ============================================================================
-- ACT 5: Custom Shinobi World Ninja Villages Showcase (Konohagakure vs Five Great Nations!)
-- ============================================================================
local shinobiCfg = Config.DefaultGameConfig(true)
shinobiCfg.mapId = "ShinobiWorld"
shinobiCfg.bots = 8
shinobiCfg.instantBuild = true
shinobiCfg.goldMultiplier = 5

local shinobiSim = SimEngine.new(shinobiCfg, {
	{ userId = 777001, name = "Konoha Allied Forces", flag = "konoha", colorHex = "#ef4444", patternId = "stripes" },
}, false)
local konohaSp = shinobiSim.rawMap.nations[1]
shinobiSim:ChooseSpawn(777001, math.clamp(konohaSp.x + 22, 12, shinobiSim.map.width - 12), math.clamp(konohaSp.y + 12, 12, shinobiSim.map.height - 12))
local meShinobi = shinobiSim.playersByUserId[777001]
while shinobiSim.inSpawnPhase do shinobiSim:Step() end
meShinobi.troops = 260_000
meShinobi.gold = 60_000_000
for step = 1, 95 do
	if step % 12 == 1 then
		shinobiSim:StartLandAttack(meShinobi, 0, meShinobi.troops * 0.5, nil)
	end
	shinobiSim:Step()
end
local shinobiOwned = {}
for ref = 0, shinobiSim.map.size - 1 do
	if MapCodec.GetOwner(shinobiSim.map, ref) == meShinobi.smallId then
		table.insert(shinobiOwned, ref)
	end
end
if #shinobiOwned > 25 then
	shinobiSim:BuildUnit(meShinobi, "City", shinobiOwned[math.floor(#shinobiOwned * 0.25)])
	shinobiSim:BuildUnit(meShinobi, "Factory", shinobiOwned[math.floor(#shinobiOwned * 0.55)])
	shinobiSim:BuildUnit(meShinobi, "MissileSilo", shinobiOwned[math.floor(#shinobiOwned * 0.40)])
	shinobiSim:BuildUnit(meShinobi, "SAMLauncher", shinobiOwned[math.floor(#shinobiOwned * 0.70)])
end
syncSimToCanvas(shinobiSim, meShinobi.smallId, true)

for f = 1, 64 do
	if f == 28 then
		canvas.altView = true
		canvas:MarkAllDirty()
	elseif f == 50 then
		canvas.altView = false
		canvas:MarkAllDirty()
	end
	if f == 12 then
		for _, op in ipairs(shinobiSim.playersList) do
			if op ~= meShinobi and op.alive and op.tilesOwned > 40 then
				shinobiSim:BuildUnit(meShinobi, "AtomBomb", op.labelY * shinobiSim.map.width + op.labelX)
				shinobiSim:StartLandAttack(meShinobi, op.smallId, meShinobi.troops * 0.45, nil)
				break
			end
		end
	end
	shinobiSim:Step()
	shinobiSim:Step()
	cam:FocusOn(meShinobi.labelX, meShinobi.labelY, 2.55 + f * 0.015)
	local pl = syncSimToCanvas(shinobiSim, meShinobi.smallId, false)
	local sfx = ""
	if f == 12 then sfx = "launch"
	elseif #(pl.explosions or {}) > 0 then sfx = "boom"
	elseif f == 28 then sfx = "click"
	end
	capture(shinobiSim, pl, meShinobi.smallId, "Act 5: Shinobi World Map & Tactical Alt-View", "InGame", { sfx = sfx })
end

-- ============================================================================
-- ACT 6: Final World Conquest Push -> >94% Land Share -> VICTORY CEREMONY MODAL!
-- ============================================================================
canvas.altView = false
canvas:MarkAllDirty()

local landRefs = {}
for ref = 0, worldSim.map.size - 1 do
	if MapCodec.IsPlayableLand(worldSim.map, ref) then
		table.insert(landRefs, ref)
	end
end
table.sort(landRefs, function(a, b)
	local ax, ay = a % worldSim.map.width, math.floor(a / worldSim.map.width)
	local bx, by = b % worldSim.map.width, math.floor(b / worldSim.map.width)
	local da = (ax - indiaX) * (ax - indiaX) + (ay - indiaY) * (ay - indiaY)
	local db = (bx - indiaX) * (bx - indiaX) + (by - indiaY) * (by - indiaY)
	return da < db
end)

syncSimToCanvas(worldSim, meWorld.smallId, true)
cam:FitWorld()

local targetConquerCount = math.floor(#landRefs * 0.95)
local sweepCursor = 1
local perFrameConquer = math.ceil(targetConquerCount / 34)
for f = 1, 68 do
	worldSim:Step()
	if sweepCursor <= targetConquerCount then
		for _ = 1, perFrameConquer do
			if sweepCursor > targetConquerCount then break end
			worldSim:ConquerTile(meWorld.smallId, landRefs[sweepCursor])
			sweepCursor += 1
		end
	end
	-- Keep already-swept radial zone cleanly consolidated under Republic of India (no stray reconquest speckles!)
	if f >= 34 then
		for i = 1, targetConquerCount do
			local r = landRefs[i]
			if MapCodec.GetOwner(worldSim.map, r) ~= meWorld.smallId then
				worldSim:ConquerTile(meWorld.smallId, r)
			end
		end
	end
	cam:FitWorld()
	local pl = syncSimToCanvas(worldSim, meWorld.smallId, f >= 34)
	local showVictoryModal = f >= 38
	capture(worldSim, pl, meWorld.smallId, "Act 6: Global Conquest & Victory XP Ceremony", if showVictoryModal then "Victory" else "InGame", {
		victory = showVictoryModal,
		xpGained = 4180,
		newLevel = 4,
		sfx = if f == 38 then "victory" elseif f % 10 == 0 and f < 38 then "attack" else "",
	})
end

return true
`;

const vm = await LuauState.createAsync();
try {
  const fn = vm.loadstring(RECORD_SCRIPT, "=play_and_record.luau", true);
  await fn(emitFrame);
} finally {
  metaStream.end();
  vm.destroy();
}
console.log(`[luau-recorder] DONE! Total captured frames: ${frameIdx}`);
