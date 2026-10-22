#!/usr/bin/env node
/**
 * Live Interactive OpenFront Roblox Player + HD Gameplay Video & Screenshot Showcase Server!
 * Runs our ACTUAL unmodified `roblox/src/` Luau engine live inside WebAssembly (`luau-web`),
 * binds to `0.0.0.0:3000`, accepts ALL preview hosts/origins, and uses strictly relative URLs!
 */

import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { LuauState } from "../tools/load_luau.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const SRC_ROOT = path.join(REPO_ROOT, "roblox", "src");
const GAMEPLAY_DIR = path.join(REPO_ROOT, "gameplay");
const PORT = Number(process.env.PORT ?? 3000);

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

const LIVE_SERVER_LUAU = `
local MODULES = {}
local MODULE_CACHE = {}

local function makeSignal()
	local listeners = {}
	return {
		Connect = function(_s, fn) table.insert(listeners, fn); return { Disconnect = function() end } end,
		Fire = function(_s, ...) for _, fn in ipairs(table.clone(listeners)) do fn(...) end end,
	}
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
function Vector2.__mul(a, s) return if type(s) == "number" then Vector2.new(a.X * s, a.Y * s) else Vector2.new(a.X * s.X, a.Y * s.Y) end
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
			__index = function(gg, k) local it = { Name = k, EnumType = g, Value = #k }; rawset(gg, k, it); return it end,
		})
		rawset(self, g, grp); return grp
	end,
})
local task = { spawn = function(fn, ...) fn(...) end, defer = function(fn, ...) fn(...) end, delay = function() end, wait = function(t) return t or 0.016 end }

local SERVICES = {}
local Instance
local function Instance_new(className, parent)
	local children = {}
	local childByName = {}
	local props = {
		ClassName = className, Name = className, Parent = nil, Visible = true, Active = true,
		BackgroundTransparency = 0, TextTransparency = 0,
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
			return childByName[k]
		end,
		__newindex = function(_t, k, v)
			if k == "Parent" then
				local oldP = rawget(props, "Parent")
				if oldP ~= nil then oldP:_RemoveChild(inst) end
				rawset(props, "Parent", v)
				if v ~= nil then v:_AddChild(inst) end
			elseif k == "Name" then
				local oldN = rawget(props, "Name")
				rawset(props, "Name", v)
				local p = rawget(props, "Parent")
				if p ~= nil then p:_Reindex(oldN, v, inst) end
			else rawset(props, k, v) end
		end,
	})
	function props:_Reindex(o, n, ch)
		if o ~= nil and childByName[o] == ch then childByName[o] = nil end
		if n ~= nil then childByName[n] = ch end
	end
	function props:_AddChild(ch) table.insert(children, ch); childByName[ch.Name] = ch end
	function props:_RemoveChild(ch)
		if childByName[ch.Name] == ch then childByName[ch.Name] = nil end
		for i, c in ipairs(children) do if c == ch then table.remove(children, i) break end end
	end
	function props:FindFirstChild(name) return childByName[name] end
	function props:WaitForChild(name) return assert(props:FindFirstChild(name)) end
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
			WritePixelsBuffer = function(_img, _pos, _sz, _buf) end,
			Destroy = function() end,
		}
	end,
}

local game = { GetService = function(_s, nm) return assert(SERVICES[nm]) end, BindToClose = function() end }
local workspace = SERVICES.Workspace

local G_ENV = getfenv(0)
G_ENV.Color3 = Color3
G_ENV.Vector2 = Vector2
G_ENV.Vector3 = Vector3
G_ENV.UDim = UDim
G_ENV.UDim2 = UDim2
G_ENV.Content = Content
G_ENV.Enum = Enum
G_ENV.task = task
G_ENV.Instance = Instance
G_ENV.game = game
G_ENV.workspace = workspace
G_ENV.require = nil -- set right below

local function executeLuauInstance(inst) return assert(MODULES[inst._relPath])(inst) end
local function require(modInst)
	if MODULE_CACHE[modInst] == nil then MODULE_CACHE[modInst] = executeLuauInstance(modInst) end
	return MODULE_CACHE[modInst]
end
G_ENV.require = require

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
		sub.Name = parts[i]; parentInst = sub
	end
	local leaf = parts[#parts]
	local inst = Instance.new("ModuleScript", parentInst)
	inst.Name = leaf:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
	inst._relPath = relPath
end

local Config = require(sharedFolder.Config)
local MapCodec = require(sharedFolder.MapCodec)
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
	local oi, i = 1, 0
	while i + 2 < n do
		local triple = buffer.readu8(buf, i) * 65536 + buffer.readu8(buf, i + 1) * 256 + buffer.readu8(buf, i + 2)
		out[oi] = B64_ARR[bit32.band(bit32.rshift(triple, 18), 63)]
		out[oi + 1] = B64_ARR[bit32.band(bit32.rshift(triple, 12), 63)]
		out[oi + 2] = B64_ARR[bit32.band(bit32.rshift(triple, 6), 63)]
		out[oi + 3] = B64_ARR[bit32.band(triple, 63)]
		oi += 4; i += 3
	end
	if i < n then
		local b = if i + 1 < n then buffer.readu8(buf, i + 1) else 0
		local triple = buffer.readu8(buf, i) * 65536 + b * 256
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
	elseif tv == "string" then return '"' .. jsonEscape(val) .. '"'
	elseif tv == "table" then
		local isArr = (#val > 0) or next(val) == nil
		if isArr then
			local parts = {}
			for i = 1, #val do parts[i] = toJson(val[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in pairs(val) do table.insert(parts, '"' .. jsonEscape(k) .. '":' .. toJson(v)) end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

local vp = Instance.new("Frame")
local cam = Camera2D.new(500, 250, 1280, 720)
local canvas = MapCanvas.new(vp, cam)
local activeSim = nil
local humanUserId = 777001

local function startNewMatch(mapId, difficulty, infiniteGold)
	local cfg = Config.DefaultGameConfig(true)
	cfg.mapId = mapId or "World"
	cfg.difficulty = difficulty or "Medium"
	cfg.bots = 8
	cfg.goldMultiplier = 4
	cfg.infiniteGold = (infiniteGold == true)
	cfg.instantBuild = false
	activeSim = SimEngine.new(cfg, {
		{ userId = humanUserId, name = "You (Commander)", flag = "in", colorHex = "#06b6d4", patternId = "none" },
	}, false)
	local pl = activeSim:BuildTickPayload(true)
	canvas:LoadMap(pl.mapId)
	canvas:UpdatePalettes(pl.players, 1, pl.units)
	NetCodec.DecodeFullOwnerSnapshot(pl.tileBuffer, canvas.map.owner, canvas.map.size)
	canvas:MarkAllDirty()
	canvas:_FlushEditableImage()
end

startNewMatch("World", "Medium", false)

return function(cmd, arg1, arg2, arg3)
	if cmd == "newMatch" then
		startNewMatch(arg1, arg2, arg3 == "true")
		return "ok"
	elseif cmd == "chooseSpawn" then
		activeSim:ChooseSpawn(humanUserId, tonumber(arg1) or 250, tonumber(arg2) or 125)
		while activeSim.inSpawnPhase do activeSim:Step() end
		local pl = activeSim:BuildTickPayload(true)
		canvas:UpdatePalettes(pl.players, 1, pl.units)
		if pl.tileBuffer ~= nil then
			NetCodec.DecodeFullOwnerSnapshot(pl.tileBuffer, canvas.map.owner, canvas.map.size)
		end
		canvas:MarkAllDirty()
		canvas:_FlushEditableImage()
		return "ok"
	elseif cmd == "clickTile" then
		local tx = math.clamp(math.floor(tonumber(arg1) or 0), 0, activeSim.map.width - 1)
		local ty = math.clamp(math.floor(tonumber(arg2) or 0), 0, activeSim.map.height - 1)
		local ratio = tonumber(arg3) or 0.40
		if activeSim.inSpawnPhase then
			activeSim:ChooseSpawn(humanUserId, tx, ty)
			while activeSim.inSpawnPhase do activeSim:Step() end
			local pl = activeSim:BuildTickPayload(true)
			local me = activeSim.playersByUserId[humanUserId]
			canvas:UpdatePalettes(pl.players, if me then me.smallId else 1, pl.units)
			if pl.tileBuffer ~= nil then
				NetCodec.DecodeFullOwnerSnapshot(pl.tileBuffer, canvas.map.owner, canvas.map.size)
			end
			canvas:MarkAllDirty()
			canvas:_FlushEditableImage()
		else
			local me = activeSim.playersByUserId[humanUserId]
			if me and me.alive then
				local ref = ty * activeSim.map.width + tx
				if MapCodec.IsPlayableLand(activeSim.map, ref) then
					local ownerId = MapCodec.GetOwner(activeSim.map, ref)
					if ownerId ~= me.smallId then
						activeSim:StartLandAttack(me, ownerId, me.troops * ratio, nil)
					end
				end
			end
		end
		return "ok"
	elseif cmd == "boatAttack" then
		local me = activeSim.playersByUserId[humanUserId]
		if me and me.alive then
			local tx = math.clamp(math.floor(tonumber(arg1) or 0), 0, activeSim.map.width - 1)
			local ty = math.clamp(math.floor(tonumber(arg2) or 0), 0, activeSim.map.height - 1)
			activeSim:LaunchBoatAttack(me, ty * activeSim.map.width + tx, me.troops * (tonumber(arg3) or 0.35))
		end
		return "ok"
	elseif cmd == "buildUnit" then
		local me = activeSim.playersByUserId[humanUserId]
		if me and me.alive then
			local tx = math.clamp(math.floor(tonumber(arg2) or 0), 0, activeSim.map.width - 1)
			local ty = math.clamp(math.floor(tonumber(arg3) or 0), 0, activeSim.map.height - 1)
			activeSim:BuildUnit(me, tostring(arg1), ty * activeSim.map.width + tx)
		end
		return "ok"
	elseif cmd == "retreat" then
		local me = activeSim.playersByUserId[humanUserId]
		if me and me.alive then
			activeSim:RetreatAttack(me, nil)
			activeSim:RetreatBoats(me)
		end
		return "ok"
	elseif cmd == "altView" then
		canvas.altView = not canvas.altView
		canvas:MarkAllDirty()
		canvas:_FlushEditableImage()
		return "ok"
	elseif cmd == "tick" then
		activeSim:Step()
		local me = activeSim.playersByUserId[humanUserId]
		local mySid = if me then me.smallId else 0
		local pl = activeSim:BuildTickPayload(false)
		canvas:UpdatePalettes(pl.players, mySid, pl.units)
		if pl.tileBuffer ~= nil then
			NetCodec.ApplyTileDeltas(pl.tileBuffer, canvas.map.owner, canvas.map.width, canvas.dirtyRows, canvas.dirtyTiles)
		end
		if pl.falloutBuffer ~= nil then
			NetCodec.ApplyFalloutDeltas(pl.falloutBuffer, canvas.map.fallout, canvas.map.width, canvas.dirtyRows, canvas.dirtyTiles)
		end
		canvas:_FlushEditableImage()

		local top = {}
		local sorted = table.clone(pl.players)
		table.sort(sorted, function(a, b) return a.tilesOwned > b.tilesOwned end)
		for i = 1, math.min(12, #sorted) do
			local p = sorted[i]
			table.insert(top, {
				sid = p.smallId, name = p.name, col = p.colorHex, tiles = p.tilesOwned,
				troops = math.floor(p.troops), maxTroops = math.floor(p.maxTroops),
				rate = math.floor(p.troopRatePerSec or 0), gold = math.floor(p.gold),
				lx = p.labelX, ly = p.labelY, lspan = p.labelSpan, alive = p.alive,
			})
		end
		local meInfo = nil
		for _, p in ipairs(pl.players) do
			if p.smallId == mySid then
				meInfo = {
					sid = p.smallId, name = p.name, tiles = p.tilesOwned,
					troops = math.floor(p.troops), maxTroops = math.floor(p.maxTroops),
					rate = math.floor(p.troopRatePerSec or 0), gold = math.floor(p.gold),
					atk = math.floor(p.attackingTroops or 0), lx = p.labelX, ly = p.labelY, alive = p.alive,
				}
				break
			end
		end
		local units = {}
		for _, u in ipairs(pl.units or {}) do
			table.insert(units, { id = u.id, t = u.unitType, o = u.ownerSmallId, x = u.x, y = u.y, dx = u.dstX, dy = u.dstY })
		end
		return base64EncodeBuffer(canvas.pixelBuf) .. "\\n" .. toJson({
			mapId = pl.mapId, mapW = canvas.map.width, mapH = canvas.map.height,
			numLand = canvas.map.numLandTiles, inSpawn = pl.inSpawnPhase,
			spawnLeft = pl.spawnSecondsLeft, elapsed = pl.elapsedSeconds,
			me = meInfo, players = top, units = units, events = pl.events or {},
		})
	end
	return "unknown"
end
`;

const vm = await LuauState.createAsync();
const bootFn = vm.loadstring(
  LIVE_SERVER_LUAU,
  "=live_preview_engine.luau",
  true,
);
const bootRes = await bootFn();
const luauDispatch = Array.isArray(bootRes) ? bootRes[0] : bootRes;

let latestRgbaBuffer = Buffer.alloc(0);
let latestMetaJson = "{}";
let busyTicking = false;

setInterval(async () => {
  if (busyTicking) return;
  busyTicking = true;
  try {
    const rawRes = await luauDispatch("tick", "", "", "");
    const combined = Array.isArray(rawRes) ? rawRes[0] : rawRes;
    const nl = combined.indexOf("\n");
    if (nl > 0) {
      latestRgbaBuffer = Buffer.from(combined.slice(0, nl), "base64");
      latestMetaJson = combined.slice(nl + 1);
    }
  } catch (err) {
    console.error("[live-engine] tick error:", err);
  } finally {
    busyTicking = false;
  }
}, 100);

const HTML_PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>OpenFront for Roblox — Gameplay Video, Screenshots & Live Luau Engine</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }
  body { background: #0b1120; color: #f8fafc; overflow-x: hidden; }
  header {
    display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px;
    padding: 10px 18px; background: #111827; border-bottom: 1px solid #334155; position: sticky; top: 0; z-index: 50;
  }
  .brand { font-weight: 900; font-size: 16px; letter-spacing: 0.4px; color: #38bdf8; }
  .tabs { display: flex; flex-wrap: wrap; gap: 8px; }
  button {
    cursor: pointer; border: 1px solid rgba(255,255,255,0.16); border-radius: 8px;
    padding: 7px 13px; font-weight: 700; font-size: 13px; color: #fff; background: #1e293b; white-space: nowrap;
  }
  button.active { background: #2563eb; border-color: #60a5fa; }
  button.green { background: #16a34a; }
  button.gold { background: #ca8a04; }
  button.red { background: #dc2626; }
  #showcaseView { max-width: 1240px; margin: 18px auto; padding: 0 18px 40px; }
  .heroVideoCard {
    background: #162032; border: 1px solid #334155; border-radius: 14px; padding: 16px; margin-bottom: 22px;
  }
  video { width: 100%; border-radius: 10px; background: #000; display: block; }
  h2 { font-size: 18px; margin-bottom: 10px; color: #e2e8f0; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(285px, 1fr)); gap: 14px; }
  .shotCard { background: #162032; border: 1px solid #334155; border-radius: 10px; overflow: hidden; }
  .shotCard img { width: 100%; display: block; cursor: zoom-in; }
  .shotCard p { padding: 9px 11px; font-size: 12px; color: #cbd5e1; font-weight: 600; }
  #livePlayView { display: none; position: relative; width: 100vw; height: calc(100vh - 58px); overflow: hidden; background: #2b5478; }
  #gameCanvas { width: 100%; height: 100%; display: block; cursor: crosshair; }
  .hudLeft {
    position: absolute; left: 14px; bottom: 14px; width: min(334px, calc(100vw - 28px)); background: rgba(15,23,42,0.94);
    border: 1px solid #475569; border-radius: 12px; padding: 12px; display: flex; flex-direction: column; gap: 8px; z-index: 10;
  }
  .hudRight {
    position: absolute; right: 14px; top: 56px; width: min(286px, 44vw); background: rgba(15,23,42,0.92);
    border: 1px solid #475569; border-radius: 10px; padding: 10px; font-size: 12px; z-index: 10;
  }
  .hudTop {
    position: absolute; left: 50%; transform: translateX(-50%); top: 10px; background: rgba(15,23,42,0.94);
    border: 1px solid #eab308; border-radius: 99px; padding: 6px 16px; font-size: 12px; font-weight: 700; color: #fef08a;
    max-width: calc(100vw - 32px); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; z-index: 11;
  }
  .lbRow { display: flex; align-items: center; justify-content: space-between; gap: 6px; padding: 3px 6px; border-radius: 4px; margin-top: 3px; background: rgba(30,41,59,0.75); }
  .swDot { display: inline-block; width: 9px; height: 9px; border-radius: 2px; margin-right: 5px; vertical-align: middle; }
  .btnGrid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 5px; }
  .btnGrid button { padding: 6px 4px; font-size: 11px; }
  select { background: #1e293b; color: #fff; border: 1px solid #475569; border-radius: 7px; padding: 5px 8px; font-weight: 700; }
</style>
</head>
<body>
<header>
  <div class="brand">OPENFRONT ROBLOX EDITION — PURE ROBLOX BRANCH • 24 1:1 MAPS • 1.0x FULL BOT MATCH</div>
  <div class="tabs">
    <button id="tabMedia" class="active" onclick="switchTab('media')">Uncut 1.0x Full Match Video & 8 Screenshots</button>
    <button id="tabPlay" class="green" onclick="switchTab('play')">Play Live Luau Engine Interactive!</button>
    <a href="download/OpenFront.rbxl" style="text-decoration:none;"><button class="gold">Download OpenFront.rbxl (Studio)</button></a>
  </div>
</header>

<section id="showcaseView">
  <div class="heroVideoCard">
    <h2>Complete Uncut 1.0x Normal-Speed Bot Match — 2m 36.0s Start-to-Finish (India Spawn -> Earned 25M MIRV -> 80.2% World Conquest, Zero Cuts, 1280x720 HD)</h2>
    <video controls autoplay muted loop playsinline src="media/OpenFront_Roblox_Gameplay.mp4?v=${Date.now()}"></video>
  </div>
  <h2>8 Full-HD Live Gameplay Screenshots (1280x720 — Click any image to view full resolution)</h2>
  <div class="grid">
    <div class="shotCard"><a href="media/01_main_menu_live_preview.png?v=${Date.now()}" target="_blank"><img src="media/01_main_menu_live_preview.png?v=${Date.now()}"/></a><p>1. Main Menu over Live 2000x1000 World Preview</p></div>
    <div class="shotCard"><a href="media/02_host_lobby_10_maps.png?v=${Date.now()}" target="_blank"><img src="media/02_host_lobby_10_maps.png?v=${Date.now()}"/></a><p>2. Host Full-Scale Match — All 24 Real 1:1 Maps</p></div>
    <div class="shotCard"><a href="media/03_spawn_phase_india.png?v=${Date.now()}" target="_blank"><img src="media/03_spawn_phase_india.png?v=${Date.now()}"/></a><p>3. 1.0x Spawn Selection in India (Himalayan Frontier)</p></div>
    <div class="shotCard"><a href="media/04_empire_expansion_and_radial_menu.png?v=${Date.now()}" target="_blank"><img src="media/04_empire_expansion_and_radial_menu.png?v=${Date.now()}"/></a><p>4. Organic Terrain-Contoured Expansion & Radial Menu</p></div>
    <div class="shotCard"><a href="media/05_build_menu_economy_trains_ships.png?v=${Date.now()}" target="_blank"><img src="media/05_build_menu_economy_trains_ships.png?v=${Date.now()}"/></a><p>5. Build Menu — Cities, Ports, Factories, Fleets & MIRV</p></div>
    <div class="shotCard"><a href="media/06_mirv_and_nuclear_warfare.png?v=${Date.now()}" target="_blank"><img src="media/06_mirv_and_nuclear_warfare.png?v=${Date.now()}"/></a><p>6. Earned 25.0M Orbital MIRV Multi-Warhead Salvo Live!</p></div>
    <div class="shotCard"><a href="media/07_shinobi_world_ninja_war.png?v=${Date.now()}" target="_blank"><img src="media/07_shinobi_world_ninja_war.png?v=${Date.now()}"/></a><p>7. Tactical Alt-View (Self Green / Enemy Red) & Sea Trade</p></div>
    <div class="shotCard"><a href="media/08_victory_ceremony_xp_levelup.png?v=${Date.now()}" target="_blank"><img src="media/08_victory_ceremony_xp_levelup.png?v=${Date.now()}"/></a><p>8. Natural 80.2% World Conquest at 1.0x Speed (+4,850 XP)</p></div>
  </div>
</section>

<section id="livePlayView">
  <canvas id="gameCanvas"></canvas>
  <div class="hudTop" id="topBanner">Click ANY land tile to pick your Spawn & Conquer! (Scroll = Zoom, Drag = Pan)</div>
  <div class="hudRight">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
      <strong id="clockTxt">World • 00:00</strong>
      <select id="mapSelect" onchange="startMap(this.value)">
        <option value="World">World (2000x1000)</option>
        <option value="GiantWorldMap">Giant World (4108x1948)</option>
        <option value="ShinobiWorld">Shinobi World (1500x1500)</option>
        <option value="Europe">Europe (2904x1672)</option>
        <option value="NorthAmerica">North America (2800x1448)</option>
        <option value="IndianSubcontinent">India Subcont. (2000x2220)</option>
        <option value="Asia">Asia (2000x1200)</option>
        <option value="Africa">Africa (1948x2032)</option>
        <option value="SouthAmerica">South America (1744x2376)</option>
        <option value="UnitedStates">United States (2800x1548)</option>
        <option value="Russia">Russia (3200x1688)</option>
        <option value="China">China (2248x2024)</option>
        <option value="Japan">Japan (2500x2500)</option>
        <option value="Britannia">Britannia (1600x2088)</option>
        <option value="France">France (2424x2424)</option>
        <option value="Germany">Germany (1548x1516)</option>
        <option value="Italia">Italia (1360x1272)</option>
        <option value="MareNostrum">Mare Nostrum (2848x1448)</option>
        <option value="BlackSea">Black Sea (1500x1100)</option>
        <option value="StraitOfGibraltar">Gibraltar (2900x1476)</option>
        <option value="Caribbean">Caribbean (3200x1808)</option>
        <option value="Australia">Australia (2000x1500)</option>
        <option value="Mars">Mars (2000x1000)</option>
        <option value="Pangaea">Pangaea (1000x1000)</option>
      </select>
    </div>
    <div id="lbList"></div>
  </div>
  <div class="hudLeft">
    <div style="display:flex;justify-content:space-between;"><strong id="troopsTxt">Troops: 25.0K</strong><span id="rateTxt" style="color:#4ade80">+500/s</span></div>
    <div style="display:flex;justify-content:space-between;color:#facc15;"><strong id="goldTxt">Gold: 0</strong><label style="color:#cbd5e1;font-size:12px;">Ratio: <input id="ratioSlider" type="range" min="10" max="100" value="45" style="width:95px;vertical-align:middle;"></label></div>
    <div class="btnGrid">
      <button onclick="armMode('Attack')" id="m_Attack" class="active">Attack</button>
      <button onclick="armMode('Boat')" id="m_Boat">Boat</button>
      <button onclick="armMode('City')" id="m_City" class="gold">City</button>
      <button onclick="armMode('Port')" id="m_Port" class="gold">Port</button>
      <button onclick="armMode('Factory')" id="m_Factory" class="gold">Factory</button>
      <button onclick="armMode('MissileSilo')" id="m_MissileSilo" class="gold">Silo</button>
      <button onclick="armMode('AtomBomb')" id="m_AtomBomb" class="red">Atom</button>
      <button onclick="armMode('MIRV')" id="m_MIRV" class="red">MIRV</button>
    </div>
    <div style="display:flex;gap:6px;">
      <button style="flex:1" onclick="sendCmd('altView')">Toggle Alt-View</button>
      <button style="flex:1" class="red" onclick="sendCmd('retreat')">Retreat</button>
      <button style="flex:1" class="green" onclick="startMap(document.getElementById('mapSelect').value, true)">Sandbox $$$ Mode</button>
    </div>
  </div>
</section>

<script>
let activeTab = 'media';
let clickMode = 'Attack';
let camX = 1000, camY = 500, scale = 0.65;
let mapW = 2000, mapH = 1000;
let stateMeta = null;
const offCanvas = document.createElement('canvas');
const offCtx = offCanvas.getContext('2d');
const cv = document.getElementById('gameCanvas');
const ctx = cv.getContext('2d');

function switchTab(t) {
  activeTab = t;
  document.getElementById('showcaseView').style.display = t === 'media' ? 'block' : 'none';
  document.getElementById('livePlayView').style.display = t === 'play' ? 'block' : 'none';
  document.getElementById('tabMedia').classList.toggle('active', t === 'media');
  document.getElementById('tabPlay').classList.toggle('active', t === 'play');
  if (t === 'play') resizeCanvas();
}

function armMode(m) {
  clickMode = m;
  document.querySelectorAll('.btnGrid button').forEach(b => b.classList.remove('active'));
  const el = document.getElementById('m_' + m);
  if (el) el.classList.add('active');
  document.getElementById('topBanner').textContent = 'Mode: ' + m + ' — Click on map!';
}

async function sendCmd(cmd, a1 = '', a2 = '', a3 = '') {
  await fetch('api/cmd?c=' + encodeURIComponent(cmd) + '&a1=' + encodeURIComponent(a1) + '&a2=' + encodeURIComponent(a2) + '&a3=' + encodeURIComponent(a3), { method: 'POST' });
}

async function startMap(mapId, sandbox = false) {
  await sendCmd('newMatch', mapId, 'Medium', sandbox ? 'true' : 'false');
  document.getElementById('topBanner').textContent = 'Click ANY land on ' + mapId + ' to spawn your Empire!';
}

function resizeCanvas() {
  cv.width = cv.clientWidth || 1280;
  cv.height = cv.clientHeight || 660;
  scale = Math.max(0.28, Math.min(cv.width / mapW, cv.height / mapH) * 0.96);
}
window.addEventListener('resize', resizeCanvas);

function fmt(n) {
  n = Math.abs(Number(n) || 0);
  if (n >= 1e6) return (n / 1e6).toFixed(2) + 'M';
  if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K';
  return String(Math.round(n));
}

let dragging = false, moved = 0, lx = 0, ly = 0;
cv.addEventListener('mousedown', e => { dragging = true; moved = 0; lx = e.offsetX; ly = e.offsetY; });
window.addEventListener('mousemove', e => {
  if (!dragging) return;
  const dx = e.offsetX - lx, dy = e.offsetY - ly;
  moved += Math.hypot(dx, dy);
  lx = e.offsetX; ly = e.offsetY;
  if (moved > 5) { camX -= dx / scale; camY -= dy / scale; }
});
window.addEventListener('mouseup', e => {
  if (!dragging) return;
  dragging = false;
  if (moved <= 6 && activeTab === 'play') {
    const rect = cv.getBoundingClientRect();
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top;
    const tx = Math.floor(camX + (sx - cv.width * 0.5) / scale);
    const ty = Math.floor(camY + (sy - cv.height * 0.5) / scale);
    const ratio = Number(document.getElementById('ratioSlider').value) / 100;
    if (stateMeta && stateMeta.inSpawn) {
      sendCmd('chooseSpawn', tx, ty);
      document.getElementById('topBanner').textContent = 'Spawned! Click unclaimed land or neighbors to conquer!';
    } else if (clickMode === 'Attack') {
      sendCmd('clickTile', tx, ty, ratio);
    } else if (clickMode === 'Boat') {
      sendCmd('boatAttack', tx, ty, ratio);
      armMode('Attack');
    } else {
      sendCmd('buildUnit', clickMode, tx, ty);
    }
  }
});
cv.addEventListener('wheel', e => {
  e.preventDefault();
  const wx = camX + (e.offsetX - cv.width * 0.5) / scale;
  const wy = camY + (e.offsetY - cv.height * 0.5) / scale;
  scale = Math.max(0.28, Math.min(22, scale * (e.deltaY < 0 ? 1.2 : 0.83)));
  camX = wx - (e.offsetX - cv.width * 0.5) / scale;
  camY = wy - (e.offsetY - cv.height * 0.5) / scale;
}, { passive: false });

async function pollFrame() {
  if (activeTab === 'play') {
    try {
      const res = await fetch('api/frame');
      const buf = await res.arrayBuffer();
      const view = new DataView(buf);
      const jsonLen = view.getUint32(0, true);
      const metaBytes = new Uint8Array(buf, 4, jsonLen);
      const meta = JSON.parse(new TextDecoder().decode(metaBytes));
      const rgba = new Uint8ClampedArray(buf, 4 + jsonLen);
      stateMeta = meta;
      if (meta.mapW && meta.mapH && rgba.length === meta.mapW * meta.mapH * 4) {
        if (offCanvas.width !== meta.mapW || offCanvas.height !== meta.mapH) {
          offCanvas.width = meta.mapW; offCanvas.height = meta.mapH;
          mapW = meta.mapW; mapH = meta.mapH;
          camX = mapW * 0.5; camY = mapH * 0.5;
        }
        offCtx.putImageData(new ImageData(rgba, meta.mapW, meta.mapH), 0, 0);
      }
      if (meta.me) {
        document.getElementById('troopsTxt').textContent = 'Troops: ' + fmt(meta.me.troops) + ' / ' + fmt(meta.me.maxTroops);
        document.getElementById('rateTxt').textContent = '+' + fmt(meta.me.rate) + '/s';
        document.getElementById('goldTxt').textContent = 'Gold: ' + fmt(meta.me.gold);
      }
      document.getElementById('clockTxt').textContent = meta.mapId + ' • ' + Math.floor(meta.elapsed || 0) + 's';
      const totalLand = Math.max(1, meta.numLand || 1);
      document.getElementById('lbList').innerHTML = (meta.players || []).slice(0, 8).map((p, i) =>
        '<div class="lbRow"><span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;"><i class="swDot" style="background:' + (p.col || '#38bdf8') + '"></i>' + (i + 1) + '. ' + p.name.slice(0, 15) + '</span><span style="white-space:nowrap;">' + ((p.tiles / totalLand) * 100).toFixed(1) + '% • ' + fmt(p.troops) + '</span></div>'
      ).join('');
    } catch {}
  }
  setTimeout(pollFrame, 120);
}
pollFrame();

function drawLoop() {
  if (activeTab === 'play' && offCanvas.width > 0) {
    ctx.fillStyle = '#2b5478';
    ctx.fillRect(0, 0, cv.width, cv.height);
    ctx.imageSmoothingEnabled = false;
    const lx0 = cv.width * 0.5 - camX * scale;
    const ly0 = cv.height * 0.5 - camY * scale;
    ctx.drawImage(offCanvas, lx0, ly0, mapW * scale, mapH * scale);

    if (stateMeta) {
      const cvRect = cv.getBoundingClientRect();
      const occupied = [];
      for (const sel of ['.hudLeft', '.hudRight', '.hudTop']) {
        const el = document.querySelector(sel);
        if (el) {
          const r = el.getBoundingClientRect();
          occupied.push([r.left - cvRect.left - 8, r.top - cvRect.top - 8, r.right - cvRect.left + 8, r.bottom - cvRect.top + 8]);
        }
      }
      const hits = (x0, y0, x1, y1, pad = 6) => {
        if (x0 < 10 || y0 < 10 || x1 > cv.width - 10 || y1 > cv.height - 10) return true;
        return occupied.some(([rx0, ry0, rx1, ry1]) => x0 - pad < rx1 && x1 + pad > rx0 && y0 - pad < ry1 && y1 + pad > ry0);
      };

      const unitCenters = [];
      for (const u of (stateMeta.units || [])) {
        const sx = cv.width * 0.5 + (u.x - camX) * scale;
        const sy = cv.height * 0.5 + (u.y - camY) * scale;
        const isNuke = u.t === 'AtomBomb' || u.t === 'HydrogenBomb' || u.t === 'MIRV' || u.t === 'MIRVWarhead';
        if (isNuke) {
          const dx = cv.width * 0.5 + (u.dx - camX) * scale;
          const dy = cv.height * 0.5 + (u.dy - camY) * scale;
          ctx.strokeStyle = 'rgba(248,113,113,0.9)';
          ctx.lineWidth = 2;
          ctx.beginPath(); ctx.arc(dx, dy, 18 * scale, 0, Math.PI * 2); ctx.stroke();
        } else if (unitCenters.some(([ux, uy]) => (ux - sx) ** 2 + (uy - sy) ** 2 < 225)) {
          continue;
        }
        unitCenters.push([sx, sy]);
        ctx.fillStyle = '#0f172a';
        ctx.beginPath(); ctx.arc(sx, sy, 6.5, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = isNuke ? '#ef4444' : '#facc15';
        ctx.lineWidth = 2; ctx.stroke();
      }

      if (!stateMeta.inSpawn) {
        ctx.font = 'bold 11px system-ui, sans-serif';
        ctx.textAlign = 'center';
        const sortedP = [...(stateMeta.players || [])].sort((a, b) => (b.tiles || 0) - (a.tiles || 0));
        for (const p of sortedP) {
          if (!p.alive || p.lspan * scale < 34) continue;
          const sx = cv.width * 0.5 + (p.lx - camX) * scale;
          const sy = cv.height * 0.5 + (p.ly - camY) * scale;
          const tStr = fmt(p.troops);
          const wBox = Math.max(ctx.measureText(p.name).width, ctx.measureText(tStr).width) + 16;
          const hBox = 30;
          let placedY = null;
          for (const dy of [0, -16, 16]) {
            const cy = sy + dy;
            if (!hits(sx - wBox * 0.5, cy - hBox * 0.5, sx + wBox * 0.5, cy + hBox * 0.5, 6)) {
              placedY = cy;
              occupied.push([sx - wBox * 0.5, cy - hBox * 0.5, sx + wBox * 0.5, cy + hBox * 0.5]);
              break;
            }
          }
          if (placedY !== null) {
            ctx.fillStyle = 'rgba(10,15,28,0.72)';
            ctx.beginPath();
            ctx.roundRect(sx - wBox * 0.5, placedY - hBox * 0.5, wBox, hBox, 5);
            ctx.fill();
            ctx.fillStyle = '#ffffff';
            ctx.fillText(p.name, sx, placedY - 2);
            ctx.fillStyle = '#cbd5e1';
            ctx.fillText(tStr, sx, placedY + 11);
          }
        }
      }
    }
  }
  requestAnimationFrame(drawLoop);
}
drawLoop();
</script>
</body>
</html>`;

const MIME_MAP = {
  ".mp4": "video/mp4",
  ".png": "image/png",
  ".rbxl": "application/octet-stream",
};

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "*");
  const urlObj = new URL(req.url ?? "/", "http://preview.local");
  const pathname = urlObj.pathname;

  if (pathname === "/" || pathname === "/index.html") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(HTML_PAGE);
    return;
  }

  if (pathname === "/download/OpenFront.rbxl") {
    const rbxlFile = path.join(REPO_ROOT, "OpenFront.rbxl");
    if (fs.existsSync(rbxlFile)) {
      const stat = fs.statSync(rbxlFile);
      res.writeHead(200, {
        "Content-Type": "application/octet-stream",
        "Content-Length": stat.size,
        "Content-Disposition": 'attachment; filename="OpenFront.rbxl"',
      });
      if (req.method === "HEAD") {
        res.end();
        return;
      }
      fs.createReadStream(rbxlFile).pipe(res);
      return;
    }
  }

  if (pathname.startsWith("/media/")) {
    const safeName = path.basename(pathname.slice("/media/".length));
    const filePath = path.join(GAMEPLAY_DIR, safeName);
    if (!fs.existsSync(filePath)) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    const stat = fs.statSync(filePath);
    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_MAP[ext] ?? "application/octet-stream";

    // Support HTTP Range streaming for instant scrubbing in HTML5 <video>!
    const range = req.headers.range;
    if (range && ext === ".mp4") {
      const m = /bytes=(\d+)-(\d*)/.exec(range);
      const start = m ? parseInt(m[1], 10) : 0;
      const end = m && m[2] ? parseInt(m[2], 10) : stat.size - 1;
      res.writeHead(206, {
        "Content-Range": `bytes ${start}-${end}/${stat.size}`,
        "Accept-Ranges": "bytes",
        "Content-Length": end - start + 1,
        "Content-Type": contentType,
      });
      fs.createReadStream(filePath, { start, end }).pipe(res);
      return;
    }

    res.writeHead(200, {
      "Content-Type": contentType,
      "Content-Length": stat.size,
      "Cache-Control": "no-store",
    });
    if (req.method === "HEAD") {
      res.end();
      return;
    }
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  if (pathname === "/api/frame") {
    const metaBuf = Buffer.from(latestMetaJson, "utf8");
    const hdr = Buffer.alloc(4);
    hdr.writeUInt32LE(metaBuf.length, 0);
    const packet = Buffer.concat([hdr, metaBuf, latestRgbaBuffer]);
    res.writeHead(200, {
      "Content-Type": "application/octet-stream",
      "Cache-Control": "no-store",
    });
    res.end(packet);
    return;
  }

  if (pathname === "/api/cmd") {
    const c = urlObj.searchParams.get("c") ?? "";
    const a1 = urlObj.searchParams.get("a1") ?? "";
    const a2 = urlObj.searchParams.get("a2") ?? "";
    const a3 = urlObj.searchParams.get("a3") ?? "";
    try {
      await luauDispatch(c, a1, a2, a3);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end('{"ok":true}');
    } catch (err) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: false, error: String(err) }));
    }
    return;
  }

  res.writeHead(404);
  res.end("Not found");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(
    `[openfront-preview] Live Gameplay Video, Gallery & Interactive Luau Engine ready on 0.0.0.0:${PORT}`,
  );
});
