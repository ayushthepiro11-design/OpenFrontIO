#!/usr/bin/env node
/**
 * Plays AND records a 100% COMPLETE, UNCUT, START-TO-FINISH singleplayer match against
 * 24 autonomous AI Bots at TRUE 1.0x NORMAL GAME SPEED (`10 ticks = 1.000 second`, ZERO skipped
 * ticks, ZERO `ConquerTile` hacks, `startingGold = 0`, `infiniteGold = false`,
 * `infiniteTroops = false`, `instantBuild = false`) inside real Luau WebAssembly (`luau-web`)
 * on the full-resolution `2000x1000` `World` map — from Main Menu -> Lobby -> 10s Spawn Countdown ->
 * Early Heartland Expansion -> Economy (Cities, Ports, Trade Ships, Factories, Rail Trains, Warships) ->
 * Trans-Oceanic Amphibious Fleet Invasions -> Atom Bombs, Hydrogen Bombs & Earned 25M MIRV Strike ->
 * Natural `>= 80%` Global Land Victory (`SimEngine:Step()` sets `sim.gameOver = true`) -> Victory XP Ceremony!
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

function emitTerrain(nameStr, b64Terrain) {
  const buf = Buffer.from(b64Terrain, "base64");
  fs.writeFileSync(path.join(OUT_RAW_DIR, `terrain_${nameStr}.bin`), buf);
  console.log(
    `[luau-recorder] Exported full 1:1 terrain buffer terrain_${nameStr}.bin (${buf.length.toLocaleString()} bytes)`,
  );
}

let tickFrameIdx = 0;
const metaStream = fs.createWriteStream(path.join(OUT_RAW_DIR, "ticks.jsonl"));
const deltaFd = fs.openSync(path.join(OUT_RAW_DIR, "deltas.bin"), "w");

function emitTick(ownerDeltaB64, falloutDeltaB64, metaJsonStr) {
  const idx = tickFrameIdx++;
  const ownerBuf = ownerDeltaB64
    ? Buffer.from(ownerDeltaB64, "base64")
    : Buffer.alloc(0);
  const fallBuf = falloutDeltaB64
    ? Buffer.from(falloutDeltaB64, "base64")
    : Buffer.alloc(0);

  const hdr = Buffer.alloc(8);
  hdr.writeUInt32LE(ownerBuf.length, 0);
  hdr.writeUInt32LE(fallBuf.length, 4);
  fs.writeSync(deltaFd, hdr);
  if (ownerBuf.length > 0) fs.writeSync(deltaFd, ownerBuf);
  if (fallBuf.length > 0) fs.writeSync(deltaFd, fallBuf);

  metaStream.write(metaJsonStr + "\n");
  if (idx % 150 === 0) {
    const m = JSON.parse(metaJsonStr);
    const pct = m.me ? ((m.me.tiles / Math.max(1, m.numLand)) * 100).toFixed(1) : "0.0";
    console.log(
      `[luau-recorder] TickFrame ${idx} (${(idx * 0.1).toFixed(1)}s @ 1.0x) | ${m.phase} | simTick=${m.ticks} | land=${pct}%`,
    );
  }
}

const RECORD_SCRIPT = `
local EMIT_TERRAIN, EMIT_TICK = ...
local MODULES = {}
local MODULE_CACHE = {}

local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v) return Color3.new(h, s, v) end
local Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end, zero = { X = 0, Y = 0 }, one = { X = 1, Y = 1 } }
local Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end, zero = { X = 0, Y = 0, Z = 0 } }
local UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
local UDim2 = {
	new = function(sx, ox, sy, oy) return { X = UDim.new(sx, ox), Y = UDim.new(sy, oy) } end,
	fromScale = function(sx, sy) return { X = UDim.new(sx, 0), Y = UDim.new(sy, 0) } end,
	fromOffset = function(ox, oy) return { X = UDim.new(0, ox), Y = UDim.new(0, oy) } end,
}
local Enum = setmetatable({}, {
	__index = function(self, g)
		local grp = setmetatable({}, { __index = function(gg, k) local it = { Name = k }; rawset(gg, k, it); return it end })
		rawset(self, g, grp)
		return grp
	end,
})

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_ARR = table.create(64)
for i = 1, 64 do B64_ARR[i] = string.byte(B64, i) end

local function base64EncodeBuffer(buf, byteLen)
	if byteLen <= 0 then return "" end
	local outLen = math.ceil(byteLen / 3) * 4
	local out = buffer.create(outLen)
	local o = 0
	local i = 0
	while i + 2 < byteLen do
		local b0 = buffer.readu8(buf, i)
		local b1 = buffer.readu8(buf, i + 1)
		local b2 = buffer.readu8(buf, i + 2)
		local n = b0 * 65536 + b1 * 256 + b2
		buffer.writeu8(out, o, B64_ARR[bit32.rshift(n, 18) + 1])
		buffer.writeu8(out, o + 1, B64_ARR[bit32.band(bit32.rshift(n, 12), 63) + 1])
		buffer.writeu8(out, o + 2, B64_ARR[bit32.band(bit32.rshift(n, 6), 63) + 1])
		buffer.writeu8(out, o + 3, B64_ARR[bit32.band(n, 63) + 1])
		i += 3
		o += 4
	end
	local rem = byteLen - i
	if rem == 1 then
		local n = buffer.readu8(buf, i) * 65536
		buffer.writeu8(out, o, B64_ARR[bit32.rshift(n, 18) + 1])
		buffer.writeu8(out, o + 1, B64_ARR[bit32.band(bit32.rshift(n, 12), 63) + 1])
		buffer.writeu8(out, o + 2, 61)
		buffer.writeu8(out, o + 3, 61)
	elseif rem == 2 then
		local n = buffer.readu8(buf, i) * 65536 + buffer.readu8(buf, i + 1) * 256
		buffer.writeu8(out, o, B64_ARR[bit32.rshift(n, 18) + 1])
		buffer.writeu8(out, o + 1, B64_ARR[bit32.band(bit32.rshift(n, 12), 63) + 1])
		buffer.writeu8(out, o + 2, B64_ARR[bit32.band(bit32.rshift(n, 6), 63) + 1])
		buffer.writeu8(out, o + 3, 61)
	end
	return buffer.tostring(out)
end

local function jsonEscape(s)
	return (tostring(s):gsub("\\\\", "\\\\\\\\"):gsub('"', '\\\\"'):gsub("\\n", "\\\\n"):gsub("\\r", ""))
end

local function toJson(v)
	local tv = type(v)
	if tv == "nil" then return "null"
	elseif tv == "boolean" then return if v then "true" else "false"
	elseif tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		return tostring(v)
	elseif tv == "string" then return '"' .. jsonEscape(v) .. '"'
	elseif tv == "table" then
		local isArr = true
		local maxN = 0
		local cnt = 0
		for k, _ in pairs(v) do
			cnt += 1
			if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then isArr = false; break end
			if k > maxN then maxN = k end
		end
		if cnt == 0 then return "[]" end
		if isArr and maxN == cnt then
			local parts = table.create(cnt)
			for i = 1, cnt do parts[i] = toJson(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, val in pairs(v) do
				table.insert(parts, '"' .. jsonEscape(tostring(k)) .. '":' .. toJson(val))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

local SERVICES = {}
local function makeInstance(className, parent)
	local children = {}
	local inst = setmetatable({ ClassName = className, Name = className }, {
		__index = function(_t, k)
			for _, c in ipairs(children) do if c.Name == k then return c end end
			return nil
		end,
		__newindex = function(t, k, v)
			rawset(t, k, v)
			if k == "Parent" and v ~= nil then table.insert(v._children, t) end
		end,
	})
	rawset(inst, "_children", children)
	rawset(inst, "FindFirstChild", function(_s, name)
		for _, c in ipairs(children) do if c.Name == name then return c end end
		return nil
	end)
	rawset(inst, "WaitForChild", function(s, name)
		return assert(s:FindFirstChild(name), "Missing child " .. tostring(name))
	end)
	if parent ~= nil then inst.Parent = parent end
	return inst
end

local Instance = { new = makeInstance }
SERVICES.Workspace = makeInstance("Workspace")
SERVICES.ReplicatedStorage = makeInstance("ReplicatedStorage")
SERVICES.ServerScriptService = makeInstance("ServerScriptService")
SERVICES.SoundService = makeInstance("SoundService")
SERVICES.StarterGui = makeInstance("StarterGui")

local game = {
	GetService = function(_self, name) return SERVICES[name] end,
	BindToClose = function() end,
}

local function requireModule(modInst)
	if MODULE_CACHE[modInst] ~= nil then return MODULE_CACHE[modInst] end
	local fn = assert(MODULES[modInst._rel], "Missing module " .. tostring(modInst._rel))
	local res = fn(modInst)
	MODULE_CACHE[modInst] = res
	return res
end
local require = requireModule

${moduleClosures}

local sharedFolder = makeInstance("Folder", SERVICES.ReplicatedStorage)
sharedFolder.Name = "OpenFrontShared"
local serverFolder = makeInstance("Folder", SERVICES.ServerScriptService)
serverFolder.Name = "OpenFrontServer"
local clientFolder = makeInstance("Folder")
clientFolder.Name = "OpenFrontClient"

for rel, _ in pairs(MODULES) do
	local parts = string.split(rel, "/")
	local root = parts[1]
	local cur = if root == "Shared" then sharedFolder elseif root == "Server" then serverFolder else clientFolder
	for i = 2, #parts - 1 do
		local sub = cur:FindFirstChild(parts[i]) or makeInstance("Folder", cur)
		sub.Name = parts[i]
		cur = sub
	end
	local leaf = parts[#parts]:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
	local ms = makeInstance("ModuleScript", cur)
	ms.Name = leaf
	ms._rel = rel
end

local Config = require(sharedFolder.Config)
local MapCodec = require(sharedFolder.MapCodec)
local MapsRegistry = require(sharedFolder.Maps.MapRegistry)
local SimEngine = require(serverFolder.SimEngine)

-- ============================================================================
-- INITIALIZE OUR SINGLE 100% REAL, UNCUT, NON-CHEAT 1.0x MATCH ON 2000x1000 WORLD!
-- ============================================================================
local cfg = Config.DefaultGameConfig(true)
cfg.mapId = "World"
cfg.spawnNations = false
cfg.bots = 24
cfg.difficulty = "Easy"
cfg.startingGold = 0
cfg.goldMultiplier = 1
cfg.instantBuild = false
cfg.infiniteGold = false
cfg.infiniteTroops = false

local BOT_NAMES = {
	{ name = "Atlas Imperium", flag = "us", col = "#ef4444" },
	{ name = "Nordic Directorate", flag = "se", col = "#3b82f6" },
	{ name = "Eurasian Steppe Khanate", flag = "ru", col = "#a855f7" },
	{ name = "Pacific Shogunate", flag = "jp", col = "#f97316" },
	{ name = "Amazonian Federation", flag = "br", col = "#22c55e" },
	{ name = "Sahara Caliphate", flag = "eg", col = "#eab308" },
	{ name = "Southern Cross Union", flag = "au", col = "#ec4899" },
	{ name = "Rhine Coalition", flag = "de", col = "#f59e0b" },
	{ name = "Gallic Republic", flag = "fr", col = "#6366f1" },
	{ name = "Iberian Armada", flag = "es", col = "#dc2626" },
	{ name = "Roman Legion", flag = "it", col = "#16a34a" },
	{ name = "Anatolian Vanguard", flag = "tr", col = "#e11d48" },
	{ name = "Andean Condor Pact", flag = "ar", col = "#38bdf8" },
	{ name = "Maple Dominion", flag = "ca", col = "#fb7185" },
	{ name = "Aztec Sun Empire", flag = "mx", col = "#10b981" },
	{ name = "Savannah Kingdoms", flag = "ng", col = "#84cc16" },
	{ name = "Abyssinian Crown", flag = "et", col = "#facc15" },
	{ name = "Persian Immortal Host", flag = "ir", col = "#fb923c" },
	{ name = "Sunda Archipelago Fleet", flag = "id", col = "#f43f5e" },
	{ name = "Hussar Commonwealth", flag = "pl", col = "#c084fc" },
	{ name = "Cossack Host", flag = "ua", col = "#60a5fa" },
	{ name = "Albion Royal Navy", flag = "gb", col = "#818cf8" },
	{ name = "Middle Kingdom", flag = "cn", col = "#ef4444" },
	{ name = "Boreal Syndicate", flag = "no", col = "#2dd4bf" },
}

local sim = SimEngine.new(cfg, {
	{ userId = 777001, name = "CommanderAyush", flag = "in", colorHex = "#06b6d4", patternId = "none" },
}, false)

-- Give each of the 24 autonomous bots a clean distinct name, flag, and rich non-cyan banner color!
local bIdx = 0
for _, p in ipairs(sim.playersList) do
	if p.playerType ~= "Human" then
		bIdx += 1
		local spec = BOT_NAMES[((bIdx - 1) % #BOT_NAMES) + 1]
		p.name = spec.name
		p.flag = spec.flag
		p.colorHex = spec.col
	end
end

EMIT_TERRAIN("World", base64EncodeBuffer(sim.map.terrain, sim.map.size))

local deltaPackBuf = buffer.create(sim.map.size * 6)
local fallPackBuf = buffer.create(sim.map.size * 5)

local function packAndDrainDeltas()
	local dc = sim.deltaCount
	local ownerB64 = ""
	if dc > 0 then
		for i = 1, dc do
			local off = (i - 1) * 6
			buffer.writeu32(deltaPackBuf, off, sim.deltaRefs[i])
			buffer.writeu16(deltaPackBuf, off + 4, sim.deltaOwners[i])
		end
		ownerB64 = base64EncodeBuffer(deltaPackBuf, dc * 6)
		sim.deltaCount = 0
	end
	local fc = sim.falloutDeltaCount
	local fallB64 = ""
	if fc > 0 then
		for i = 1, fc do
			local off = (i - 1) * 5
			buffer.writeu32(fallPackBuf, off, sim.falloutDeltaRefs[i])
			buffer.writeu8(fallPackBuf, off + 4, sim.falloutDeltaStates[i])
		end
		fallB64 = base64EncodeBuffer(fallPackBuf, fc * 5)
		sim.falloutDeltaCount = 0
	end
	return ownerB64, fallB64
end

-- Smooth cinematic camera state (camX, camY, camScale) that tracks real frontline action cleanly!
local camX, camY, camScale = 1000.0, 500.0, 0.64
local targetCamX, targetCamY, targetCamScale = 1000.0, 500.0, 0.64

local function setCameraTarget(tx, ty, ts)
	targetCamX, targetCamY, targetCamScale = tx, ty, ts
end

local function stepSmoothCamera(alpha)
	camX += (targetCamX - camX) * alpha
	camY += (targetCamY - camY) * alpha
	camScale += (targetCamScale - camScale) * alpha
	local halfW = (1280 * 0.5) / camScale
	local halfH = (720 * 0.5) / camScale
	if halfW >= sim.map.width * 0.5 then
		camX = sim.map.width * 0.5
	else
		camX = math.clamp(camX, halfW, sim.map.width - halfW)
	end
	if halfH >= sim.map.height * 0.5 then
		camY = sim.map.height * 0.5
	else
		camY = math.clamp(camY, halfH, sim.map.height - halfH)
	end
end

local me = sim.playersByUserId[777001]

local function emitCurrentState(phase, uiMode, altView, extra)
	local ownerB64, fallB64 = packAndDrainDeltas()
	local playersOut = {}
	for _, p in ipairs(sim.playersList) do
		table.insert(playersOut, {
			sid = p.smallId,
			name = p.name,
			flag = p.flag,
			col = p.colorHex,
			alive = p.alive,
			tiles = p.tilesOwned,
			troops = math.floor(p.troops),
			gold = math.floor(p.gold),
			lx = p.labelX,
			ly = p.labelY,
			lspan = p.labelSpan,
			sx = p.spawnX,
			sy = p.spawnY,
		})
	end
	table.sort(playersOut, function(a, b) return a.tiles > b.tiles end)
	local unitsOut = {}
	for _, u in ipairs(sim.units) do
		if u.active then
			table.insert(unitsOut, {
				id = u.id,
				t = u.unitType,
				o = u.ownerSmallId,
				x = u.x,
				y = u.y,
				dx = u.dstX or u.x,
				dy = u.dstY or u.y,
				lvl = u.level,
				hp = u.hp,
				mhp = u.maxHp,
				vet = u.veterancy,
				uc = u.underConstruction,
				tr = u.troops,
			})
		end
	end
	local exploOut = table.clone(sim.explosions)
	table.clear(sim.explosions)

	local out = 0
	for _, atk in ipairs(sim.attacks) do
		if atk.active and atk.attackerSmallId == me.smallId then
			out += atk.troops
		end
	end
	local maxT = sim:GetMaxTroops(me)
	local meOut = {
		sid = me.smallId,
		name = me.name,
		flag = me.flag,
		col = me.colorHex,
		tiles = me.tilesOwned,
		troops = math.floor(me.troops),
		maxTroops = maxT,
		rate = math.floor(Config.TroopIncreasePerTick(me.troops, maxT, me.playerType, sim.config) * 10),
		gold = math.floor(me.gold),
		atk = math.floor(out),
		sx = me.spawnX,
		sy = me.spawnY,
	}

	local spawnLeftTicks = math.max(0, sim.spawnPhaseTicks - sim.ticks)
	local elapsedSec = math.max(0, (sim.ticks - sim.spawnPhaseTicks) / 10)
	local winReq = Config.WinPercentageRequired(sim.config, elapsedSec)

	local meta = {
		phase = phase,
		uiMode = uiMode,
		mapId = "World",
		mapName = "World (2000x1000 1:1)",
		mapW = sim.map.width,
		mapH = sim.map.height,
		numLand = sim.map.numLandTiles,
		ticks = sim.ticks,
		inSpawn = sim.inSpawnPhase,
		spawnLeft = spawnLeftTicks / 10,
		elapsed = elapsedSec,
		winPct = winReq,
		altView = altView,
		camX = camX,
		camY = camY,
		camScale = camScale,
		mySid = me.smallId,
		me = meOut,
		players = playersOut,
		units = unitsOut,
		rails = if camScale >= 1.1 then (sim.railSegments or {}) else {},
		events = sim.events,
		explosions = exploOut,
		extra = extra or {},
	}
	EMIT_TICK(ownerB64, fallB64, toJson(meta))
end

-- ============================================================================
-- PRE-MATCH UI: Main Menu (3.0s) + Singleplayer Setup Modal (3.0s)
-- ============================================================================
local mapsMeta = {}
for _, m in ipairs(MapsRegistry.List) do
	table.insert(mapsMeta, {
		id = m.id,
		name = m.name,
		nations = #m.nations,
		w = m.width,
		h = m.height,
		pw = m.previewW or 100,
		ph = m.previewH or 50,
		preview = m.preview or "",
	})
end

for f = 1, 30 do
	setCameraTarget(1000, 490, 0.64)
	stepSmoothCamera(0.25)
	emitCurrentState("Main Menu & Live World Preview", "MainMenu", false, {
		maps = if f == 1 then mapsMeta else nil,
		cursor = { tx = 640, ty = 518, click = (f == 28) },
		sfx = if f == 28 then "click" else "",
	})
end

for f = 1, 30 do
	local sel = if f <= 14 then "World" elseif f <= 22 then "ShinobiWorld" else "World"
	local ctx = if f <= 12 then 320 elseif f <= 20 then 320 elseif f <= 25 then 320 else 640
	local cty = if f <= 12 then 196 elseif f <= 20 then 300 elseif f <= 25 then 196 else 598
	emitCurrentState("Singleplayer Match Setup (1.0x Normal Speed)", "HostModal", false, {
		selectedMap = sel,
		cursor = { tx = ctx, ty = cty, click = (f == 15 or f == 23 or f == 29) },
		sfx = if f == 15 or f == 23 then "click" elseif f == 29 then "spawn" else "",
	})
end

-- ============================================================================
-- COMPLETE UNCUT 1.0x MATCH: EVERY SINGLE TICK FROM 00:00 TO >=80% VICTORY!
-- ============================================================================
-- Pick genuine fertile Northern India / Indo-Gangetic Plains spawn right south of the Himalayas!
local SPAWN_X, SPAWN_Y = 1418, 378
for r = 0, 40 do
	local found = false
	for dy = -r, r do
		for dx = -r, r do
			local px, py = 1418 + dx, 378 + dy
			local pref = py * sim.map.width + px
			if MapCodec.IsPlayableLand(sim.map, pref) and MapCodec.TerrainKind(sim.map, pref) == "Plains" then
				SPAWN_X, SPAWN_Y = px, py
				found = true
				break
			end
		end
		if found then break end
	end
	if found then break end
end

local allShores = {}
for ref = 0, sim.map.size - 1, 29 do
	if MapCodec.IsShoreLand(sim.map, ref) then
		table.insert(allShores, ref)
	end
end
local nbuf = { 0, 0, 0, 0 }

local function worldToScreen(wx, wy)
	return math.clamp(640 + (wx - camX) * camScale, 28, 1252), math.clamp(360 + (wy - camY) * camScale, 28, 692)
end

local function activeAttackTroops(targetId)
	local tot = 0
	for _, atk in ipairs(sim.attacks) do
		if atk.active and atk.attackerSmallId == me.smallId and atk.targetSmallId == targetId then
			tot += atk.troops
		end
	end
	return tot
end

local lastAliveBots = 25
local recentNukeX, recentNukeY, recentNukeUntil = -1, -1, -1
local firstBoatFocusUntil = -1
local boatFocusX, boatFocusY = -1, -1
local showedBoatZoom = false
local curTargetWX, curTargetWY = SPAWN_X, SPAWN_Y
local clickPulse = false

for t = 1, 2600 do
	local sfx = ""
	clickPulse = false

	-- Human player moves mouse to Northern India & left-clicks spawn at tick 18 (1.8s into 10.0s countdown)!
	if t == 18 then
		sim:ChooseSpawn(777001, SPAWN_X, SPAWN_Y)
		sfx = "spawn"
		clickPulse = true
	end

	sim:Step()

	if t == sim.spawnPhaseTicks then
		sfx = "attack"
	end

	local landPctPre = (me.tilesOwned / math.max(1, sim.map.numLandTiles)) * 100

	if not sim.inSpawnPhase and me.alive and not sim.gameOver then
		local maxT = sim:GetMaxTroops(me)
		local ratio = me.troops / math.max(1, maxT)
		local bCount = #me.borderList

		-- 1. Frugal Grandmaster Economy & Arsenal (100% earned tax + trade + train gold -> 25.0M Orbital MIRV!)
		if t % 12 == 0 and bCount > 0 then
			local cityCost = Config.UnitCost("City", me.unitCounts, sim.mirvsLaunched, false, true)
			local portCost = Config.UnitCost("Port", me.unitCounts, sim.mirvsLaunched, false, true)
			local facCost = Config.UnitCost("Factory", me.unitCounts, sim.mirvsLaunched, false, true)
			local siloCost = Config.UnitCost("MissileSilo", me.unitCounts, sim.mirvsLaunched, false, true)
			local samCost = Config.UnitCost("SAMLauncher", me.unitCounts, sim.mirvsLaunched, false, true)
			local dpCost = Config.UnitCost("DefensePost", me.unitCounts, sim.mirvsLaunched, false, true)

			if (me.unitCounts["DefensePost"] or 0) < 1 and me.gold >= dpCost then
				for s = 1, 20 do
					local r = me.borderList[((t * 3 + s * 11) % #me.borderList) + 1]
					if r and sim:BuildUnit(me, "DefensePost", r) then
						sfx = "build"; curTargetWX = r % sim.map.width; curTargetWY = math.floor(r / sim.map.width); clickPulse = true; break
					end
				end
			elseif (me.unitCounts["City"] or 0) < 3 and ratio > 0.36 and me.gold >= cityCost then
				for s = 1, 20 do
					local r = me.borderList[((t * 7 + s * 13) % #me.borderList) + 1]
					if r and sim:BuildUnit(me, "City", r) then
						sfx = "build"; curTargetWX = r % sim.map.width; curTargetWY = math.floor(r / sim.map.width); clickPulse = true; break
					end
				end
			elseif (me.unitCounts["Port"] or 0) < 2 and me.gold >= portCost then
				for s = 1, math.min(90, #me.borderList) do
					local r = me.borderList[((t * 11 + s) % #me.borderList) + 1]
					if r and MapCodec.IsShoreLand(sim.map, r) and sim:BuildUnit(me, "Port", r) then
						sfx = "build"; curTargetWX = r % sim.map.width; curTargetWY = math.floor(r / sim.map.width); clickPulse = true; break
					end
				end
			elseif (me.unitCounts["Factory"] or 0) < 2 and me.gold >= facCost then
				for s = 1, 20 do
					local r = me.borderList[((t * 13 + s * 9) % #me.borderList) + 1]
					if r and sim:BuildUnit(me, "Factory", r) then
						sfx = "build"; curTargetWX = r % sim.map.width; curTargetWY = math.floor(r / sim.map.width); clickPulse = true; break
					end
				end
			elseif (me.unitCounts["MissileSilo"] or 0) < 1 and me.gold >= siloCost then
				for s = 1, 20 do
					local r = me.borderList[((t * 17 + s * 7) % #me.borderList) + 1]
					if r and sim:BuildUnit(me, "MissileSilo", r) then
						sfx = "build"; curTargetWX = r % sim.map.width; curTargetWY = math.floor(r / sim.map.width); clickPulse = true; break
					end
				end
			elseif (me.unitCounts["SAMLauncher"] or 0) < 1 and me.gold >= samCost then
				for s = 1, 20 do
					local r = me.borderList[((t * 19 + s * 5) % #me.borderList) + 1]
					if r and sim:BuildUnit(me, "SAMLauncher", r) then
						sfx = "build"; curTargetWX = r % sim.map.width; curTargetWY = math.floor(r / sim.map.width); clickPulse = true; break
					end
				end
			elseif (me.unitCounts["Port"] or 0) >= 1 and (me.unitCounts["Warship"] or 0) < 2 and me.gold >= 500000 then
				for s = 1, math.min(80, #me.borderList) do
					local r = me.borderList[((t * 5 + s) % #me.borderList) + 1]
					local wr = if r then MapCodec.AdjacentWater(sim.map, r) else nil
					if wr ~= nil and sim:BuildUnit(me, "Warship", wr) then sfx = "boat"; break end
				end
			end

			-- Launch 1 early Atom Bomb, then bank real empire tax revenue for Earned 25.0M Orbital MIRV + H-Bomb!
			if (me.unitCounts["MissileSilo"] or 0) >= 1 and t % 12 == 0 then
				local bigRival, bigTiles = nil, 0
				for _, p in ipairs(sim.playersList) do
					if p ~= me and p.alive and not sim:AreFriendly(me, p) and p.tilesOwned > bigTiles then
						bigTiles = p.tilesOwned
						bigRival = p
					end
				end
				if bigRival ~= nil and bigRival.tilesOwned > 1500 then
					local tr = bigRival.labelY * sim.map.width + bigRival.labelX
					local launched = false
					if sim.mirvsLaunched == 0 and me.gold >= 25000000 then
						launched = sim:BuildUnit(me, "MIRV", tr)
					elseif sim.mirvsLaunched >= 1 and me.gold >= 5000000 then
						launched = sim:BuildUnit(me, "HydrogenBomb", tr)
					elseif me.nukesSent == 0 and me.gold >= 950000 and t < 900 then
						launched = sim:BuildUnit(me, "AtomBomb", tr)
					end
					if launched then
						sfx = "launch"
						recentNukeX = bigRival.labelX
						recentNukeY = bigRival.labelY
						recentNukeUntil = t + 115
						curTargetWX, curTargetWY = bigRival.labelX, bigRival.labelY
						clickPulse = true
					end
				end
			end
		end

		-- 2. Bell-Curve Manpower Management + Pause Blitz at 73% just long enough to fire Earned 25M Orbital MIRV!
		local waitingForMirvSalvo = (sim.mirvsLaunched == 0 and landPctPre >= 72.5 and t < 1750)
		local mirvInAir = false
		if sim.mirvsLaunched >= 1 then
			for _, u in ipairs(sim.units) do
				if u.active and (u.unitType == "MIRV" or u.unitType == "MIRVWarhead") then
					mirvInAir = true
					break
				end
			end
		end

		if t % 6 == 0 and bCount > 0 and (not waitingForMirvSalvo) and (not mirvInAir or landPctPre < 76.0) then
			local hasUnclaimed = false
			local seenEnemy = {}
			local borderEnemies = {}
			for s = 1, math.min(600, bCount) do
				local bRef = me.borderList[((t * 23 + s) % bCount) + 1]
				if bRef then
					local n = MapCodec.Neighbors4(sim.map, bRef, nbuf)
					for i = 1, n do
						local nb = nbuf[i]
						if MapCodec.IsPlayableLand(sim.map, nb) then
							local oid = MapCodec.GetOwner(sim.map, nb)
							if oid == 0 then
								hasUnclaimed = true
							elseif oid ~= me.smallId and not seenEnemy[oid] then
								seenEnemy[oid] = true
								local ep = sim.playersBySmallId[oid]
								if ep and ep.alive and not sim:AreFriendly(me, ep) then
									table.insert(borderEnemies, ep)
								end
							end
						end
					end
				end
			end

			local floorFrac = if t < 240 then 0.20 else 0.35
			local surplus = math.max(0, me.troops - maxT * floorFrac)

			if hasUnclaimed and activeAttackTroops(0) < 25000 and surplus > 1500 then
				local spend = math.min(surplus * 0.45, 140000)
				sim:StartLandAttack(me, 0, spend, nil)
				surplus -= spend
			end

			if surplus > 3000 and #borderEnemies > 0 then
				table.sort(borderEnemies, function(a, b) return a.troops < b.troops end)
				local nTargets = math.min(6, #borderEnemies)
				for idx = 1, nTargets do
					local ep = borderEnemies[idx]
					if activeAttackTroops(ep.smallId) < ep.troops * 1.6 + 25000 and surplus > 1500 then
						local spend = surplus / math.max(1, nTargets - idx + 1)
						sim:StartLandAttack(me, ep.smallId, spend, nil)
						curTargetWX, curTargetWY = ep.labelX, ep.labelY
						if t % 24 == 0 then clickPulse = true end
						surplus -= spend
					end
				end
			end

			if surplus > 15000 and (me.unitCounts["TransportShip"] or 0) < 5 then
				for attempt = 1, 60 do
					local cref = allShores[((t * 37 + attempt * 97) % #allShores) + 1]
					local oid = MapCodec.GetOwner(sim.map, cref)
					if oid ~= me.smallId and not seenEnemy[oid] then
						local ep = if oid > 0 then sim.playersBySmallId[oid] else nil
						if ep == nil or not sim:AreFriendly(me, ep) then
							local sendB = math.min(surplus * 0.45, 180000)
							if sim:LaunchBoatAttack(me, cref, sendB) then
								surplus -= sendB
								curTargetWX = cref % sim.map.width
								curTargetWY = math.floor(cref / sim.map.width)
								clickPulse = true
								if sfx == "" then sfx = "boat" end
								if not showedBoatZoom and t > 620 then
									showedBoatZoom = true
									boatFocusX = curTargetWX
									boatFocusY = curTargetWY
									firstBoatFocusUntil = t + 65
								end
								break
							end
						end
					end
				end
			end
		end
	end

	-- Detect eliminations & nuclear detonations for synchronized stereo audio FX!
	local curAlive = 0
	for _, p in ipairs(sim.playersList) do
		if p.alive and p.tilesOwned > 0 then curAlive += 1 end
	end
	if not sim.inSpawnPhase and curAlive < lastAliveBots and sfx == "" then
		sfx = "attack"
	end
	lastAliveBots = curAlive

	if #sim.explosions > 0 then
		sfx = "boom"
	end

	-- Dynamic camera framing across the 1.0x match so viewers see BOTH crisp unit details & global expansion!
	local landPct = (me.tilesOwned / math.max(1, sim.map.numLandTiles)) * 100
	local altView = (t >= 680 and t <= 745)
	local radialOpen = (t >= 250 and t <= 285)
	local buildMenuOpen = (t >= 510 and t <= 545)

	if t == 250 or t == 510 or t == 680 or t == 746 then
		if sfx == "" then sfx = "click" end
		clickPulse = true
	end

	local phaseTitle = "1.0x Speed | Spawn Selection"
	if sim.inSpawnPhase then
		phaseTitle = "1.0x Speed | Spawn Countdown (" .. tostring(math.ceil(math.max(0, sim.spawnPhaseTicks - t) / 10)) .. "s)"
		setCameraTarget(SPAWN_X, SPAWN_Y + 12, 2.35)
	elseif t < 400 then
		phaseTitle = "1.0x Speed | Heartland Expansion"
		setCameraTarget(me.labelX, me.labelY + 12, 2.05 - (t - 100) * 0.0018)
	elseif t < 760 then
		phaseTitle = if altView
			then "1.0x Speed | Alt-View & Naval Trade"
			else "1.0x Speed | Cities, Trains & Fleets"
		if t < firstBoatFocusUntil and boatFocusX >= 0 then
			setCameraTarget((me.labelX + boatFocusX) * 0.5, (me.labelY + boatFocusY) * 0.5, 1.15)
		else
			setCameraTarget(me.labelX, me.labelY + 15, 1.38)
		end
	elseif t < 1120 then
		phaseTitle = "1.0x Speed | Continental D-Day Wars"
		setCameraTarget(1120, 440, 0.86)
	else
		phaseTitle = string.format("1.0x Speed | Global Blitz (%.1f%%)", landPct)
		if t < recentNukeUntil and recentNukeX >= 0 and landPct < 78 then
			setCameraTarget((me.labelX + recentNukeX) * 0.5, (me.labelY + recentNukeY) * 0.5, 0.82)
		else
			setCameraTarget(1000, 500, 0.64)
		end
	end

	stepSmoothCamera(0.085)

	local csx, csy = worldToScreen(curTargetWX, curTargetWY)
	if radialOpen then
		csx, csy = 640 + 86 + 62, 360 - 18
	elseif buildMenuOpen then
		csx, csy = 640 - 110, 360 - 52
	elseif altView and t <= 692 then
		csx, csy = 290, 668
	end

	if sim.gameOver then
		sfx = "victory"
		setCameraTarget(1000, 500, 0.64)
		stepSmoothCamera(0.35)
		emitCurrentState(
			string.format("1.0x Victory — %.1f%% World Conquered!", landPct),
			"InGame",
			false,
			{ sfx = "victory", cursor = { tx = 640, ty = 360, click = false } }
		)
		break
	else
		emitCurrentState(phaseTitle, "InGame", altView, {
			radialOpen = radialOpen,
			buildMenuOpen = buildMenuOpen,
			cursor = { tx = math.floor(csx), ty = math.floor(csy), click = clickPulse },
			sfx = sfx,
		})
	end
end

-- Hold 6.5s (65 ticks) on the Final Victory & XP Level-Up Ceremony over the real conquered 2000x1000 map!
local finalPct = (me.tilesOwned / math.max(1, sim.map.numLandTiles)) * 100
for f = 1, 65 do
	setCameraTarget(1000, 500, 0.64)
	stepSmoothCamera(0.25)
	emitCurrentState(
		string.format("Victory Ceremony — %.1f%% World Conquered at 1.0x Speed!", finalPct),
		"Victory",
		false,
		{
			victory = true,
			xpGained = 4850,
			newLevel = 4,
			sfx = if f == 12 then "click" else "",
		}
	)
end

return toJson({
	ticksPlayed = sim.ticks,
	gameOver = sim.gameOver,
	winner = sim.winnerName,
	finalPct = finalPct,
	nukesSent = me.nukesSent,
	mirvs = sim.mirvsLaunched,
})
`;

const vm = await LuauState.createAsync();
let summary = null;
try {
  const fn = vm.loadstring(RECORD_SCRIPT, "=play_and_record.luau", true);
  const rawRes = await fn(emitTerrain, emitTick);
  summary = JSON.parse(Array.isArray(rawRes) ? rawRes[0] : rawRes);
} finally {
  metaStream.end();
  fs.closeSync(deltaFd);
  vm.destroy();
}
console.log(
  `[luau-recorder] COMPLETE FULL 1.0x MATCH FINISHED! Total tick-frames: ${tickFrameIdx}`,
  summary,
);
if (!summary?.gameOver || summary?.winner !== "CommanderAyush") {
  throw new Error(
    `Expected genuine natural gameOver win by CommanderAyush, got: ${JSON.stringify(summary)}`,
  );
}
