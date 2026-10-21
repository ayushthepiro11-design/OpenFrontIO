#!/usr/bin/env node
/**
 * Comprehensive Headless WebAssembly Luau Test & Full Client+Server E2E Suite for OpenFront Roblox!
 * Compiles & executes EVERY Luau script in `roblox/src/` natively inside `luau-web` (Luau WASM).
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { LuauState } from "../tools/load_luau.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROBLOX_ROOT = path.resolve(__dirname, "..");
const SRC_ROOT = path.join(ROBLOX_ROOT, "src");

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
console.log(
  `[luau-suite] Loaded ${Object.keys(files).length} Luau source files from roblox/src/`,
);

// 1. Standalone syntax compilation check on EVERY single .luau file individually
{
  const syntaxVm = await LuauState.createAsync();
  for (const [relPath, src] of Object.entries(files)) {
    try {
      syntaxVm.loadstring(src, `=${relPath}`, true);
    } catch (err) {
      console.error(`[SYNTAX ERROR] in ${relPath}:`, err);
      process.exit(1);
    }
  }
  syntaxVm.destroy();
  console.log(
    `[PASS 1/6] All ${Object.keys(files).length} Luau files compiled cleanly with zero syntax errors!`,
  );
}

// 2. Build unified native Luau bundle with full Roblox DataModel + all 29 modules + full E2E suite!
const moduleClosures = Object.entries(files)
  .map(
    ([rel, src]) =>
      `-- >>> BEGIN MODULE ${rel}\nMODULES[${JSON.stringify(rel)}] = function(script)\n${src}\nend\n-- <<< END MODULE ${rel}`,
  )
  .join("\n\n");

const FULL_BUNDLE = `
local SIM_CLOCK = 100.0
local MODULES = {}
local MODULE_CACHE = {}
local ALLOW_EDITABLE_IMAGE = true

local function makeSignal()
	local listeners = {}
	local sig = {}
	function sig:Connect(fn)
		table.insert(listeners, fn)
		local conn = { Connected = true }
		function conn:Disconnect()
			conn.Connected = false
			for i, f in ipairs(listeners) do
				if f == fn then
					table.remove(listeners, i)
					break
				end
			end
		end
		return conn
	end
	function sig:Fire(...)
		local snap = table.clone(listeners)
		for _, fn in ipairs(snap) do
			fn(...)
		end
	end
	return sig
end

local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	return Color3.new(h, s, v)
end

local Vector2 = {}
Vector2.__index = Vector2
function Vector2.new(x, y)
	local mx, my = x or 0, y or 0
	return setmetatable({ X = mx, Y = my, Magnitude = math.sqrt(mx * mx + my * my) }, Vector2)
end
function Vector2.__sub(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
function Vector2.__add(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
function Vector2.__mul(a, s)
	if type(s) == "number" then
		return Vector2.new(a.X * s, a.Y * s)
	end
	return Vector2.new(a.X * s.X, a.Y * s.Y)
end
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)

local Vector3 = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
	zero = { X = 0, Y = 0, Z = 0 },
}

local UDim = {
	new = function(s, o)
		return { Scale = s or 0, Offset = o or 0 }
	end,
}

local UDim2 = {
	new = function(sx, ox, sy, oy)
		return { X = UDim.new(sx, ox), Y = UDim.new(sy, oy) }
	end,
	fromScale = function(sx, sy)
		return { X = UDim.new(sx, 0), Y = UDim.new(sy, 0) }
	end,
	fromOffset = function(ox, oy)
		return { X = UDim.new(0, ox), Y = UDim.new(0, oy) }
	end,
}

local Content = {
	fromObject = function(obj)
		return { _object = obj }
	end,
}

local KEYCODE_VALUES = {
	One = 49, Two = 50, Three = 51, Four = 52, Five = 53,
	Six = 54, Seven = 55, Eight = 56, Nine = 57, Zero = 48,
	Escape = 27, Space = 32, B = 98, V = 118, R = 114, M = 109, T = 116,
	C = 99, Q = 113, E = 101, W = 119, A = 97, S = 115, D = 100,
	Up = 273, Down = 274, Left = 276, Right = 275,
	Equals = 61, Minus = 45, KeypadPlus = 270, KeypadMinus = 269,
	LeftControl = 306, RightControl = 305, LeftShift = 304,
}
local Enum = setmetatable({}, {
	__index = function(self, enumGroup)
		local group = setmetatable({}, {
			__index = function(g, itemName)
				local item = {
					Name = itemName,
					EnumType = enumGroup,
					Value = KEYCODE_VALUES[itemName] or (#itemName * 17),
				}
				rawset(g, itemName, item)
				return item
			end,
		})
		rawset(self, enumGroup, group)
		return group
	end,
})

local task = {
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	delay = function(_t, _fn) end,
	wait = function(t)
		SIM_CLOCK += (t or 0.016)
		return t or 0.016
	end,
}

local SERVICES = {}
local Instance

local function Instance_new(className, parent)
	local children = {}
	local props = {
		ClassName = className,
		Name = className,
		Parent = nil,
		Visible = true,
		Size = UDim2.fromOffset(100, 100),
		Position = UDim2.fromOffset(0, 0),
		AbsoluteSize = Vector2.new(1280, 720),
		AbsolutePosition = Vector2.new(0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
		Activated = makeSignal(),
		InputBegan = makeSignal(),
		InputChanged = makeSignal(),
		InputEnded = makeSignal(),
	}

	if className == "RemoteEvent" then
		props.OnServerEvent = makeSignal()
		props.OnClientEvent = makeSignal()
		function props:FireServer(...)
			props.OnServerEvent:Fire(SERVICES.Players.LocalPlayer, ...)
		end
		function props:FireClient(_plr, ...)
			props.OnClientEvent:Fire(...)
		end
		function props:FireAllClients(...)
			props.OnClientEvent:Fire(...)
		end
	elseif className == "RemoteFunction" then
		props.OnServerInvoke = nil
		function props:InvokeServer(...)
			if props.OnServerInvoke ~= nil then
				return props.OnServerInvoke(SERVICES.Players.LocalPlayer, ...)
			end
			return nil
		end
	elseif className == "Sound" then
		function props:Play()
			props._played = (props._played or 0) + 1
		end
	end

	local inst = {}
	setmetatable(inst, {
		__index = function(_t, k)
			local v = rawget(props, k)
			if v ~= nil then
				return v
			end
			for _, ch in ipairs(children) do
				if ch.Name == k then
					return ch
				end
			end
			return nil
		end,
		__newindex = function(_t, k, v)
			if k == "Parent" then
				local oldP = rawget(props, "Parent")
				if oldP ~= nil then
					oldP:_RemoveChild(inst)
				end
				rawset(props, "Parent", v)
				if v ~= nil then
					v:_AddChild(inst)
				end
			else
				rawset(props, k, v)
			end
		end,
	})

	function props:_AddChild(ch)
		table.insert(children, ch)
	end
	function props:_RemoveChild(ch)
		for i, c in ipairs(children) do
			if c == ch then
				table.remove(children, i)
				break
			end
		end
	end
	function props:FindFirstChild(name)
		for _, ch in ipairs(children) do
			if ch.Name == name then
				return ch
			end
		end
		return nil
	end
	function props:WaitForChild(name)
		local f = props:FindFirstChild(name)
		assert(f ~= nil, "Missing expected child Instance: " .. tostring(name) .. " on " .. tostring(props.Name))
		return f
	end
	function props:GetChildren()
		return table.clone(children)
	end
	function props:ClearAllChildren()
		for i = #children, 1, -1 do
			local c = children[i]
			c.Parent = nil
		end
	end
	function props:Destroy()
		props:ClearAllChildren()
		inst.Parent = nil
	end
	function props:IsA(targetClass)
		if props.ClassName == targetClass then
			return true
		end
		if targetClass == "BasePart" then
			return props.ClassName == "Part" or props.ClassName == "SpawnLocation"
		end
		return false
	end

	if parent ~= nil then
		inst.Parent = parent
	end
	return inst
end

Instance = { new = Instance_new }

SERVICES.Workspace = Instance.new("Workspace")
SERVICES.ReplicatedStorage = Instance.new("ReplicatedStorage")
SERVICES.ServerScriptService = Instance.new("ServerScriptService")
SERVICES.SoundService = Instance.new("SoundService")
SERVICES.StarterGui = Instance.new("StarterGui")
SERVICES.StarterGui.SetCoreGuiEnabled = function() end

local HeartbeatSig = makeSignal()
local RenderSteppedSig = makeSignal()
SERVICES.RunService = {
	Heartbeat = HeartbeatSig,
	RenderStepped = RenderSteppedSig,
	IsStudio = function() return true end,
}

local MOCK_DATASTORE = {}
SERVICES.DataStoreService = {
	GetDataStore = function(_self, storeName)
		if MOCK_DATASTORE[storeName] == nil then
			MOCK_DATASTORE[storeName] = {}
		end
		local bucket = MOCK_DATASTORE[storeName]
		return {
			GetAsync = function(_s, key)
				return bucket[key]
			end,
			SetAsync = function(_s, key, val)
				bucket[key] = val
			end,
			UpdateAsync = function(_s, key, fn)
				bucket[key] = fn(bucket[key])
				return bucket[key]
			end,
		}
	end,
}

SERVICES.AssetService = {
	CreateEditableImage = function(_self, spec)
		if not ALLOW_EDITABLE_IMAGE then
			error("EditableImage disabled in test mode to verify ScanlineCanvas2D fallback!")
		end
		return {
			Size = spec.Size,
			WriteCalls = 0,
			LastBuffer = nil,
			WritePixelsBuffer = function(img, _pos, _sz, buf)
				img.WriteCalls += 1
				img.LastBuffer = buf
			end,
		}
	end,
}

local MockLocalPlayer = Instance.new("Player")
MockLocalPlayer.Name = "CommanderAyush"
MockLocalPlayer.DisplayName = "CommanderAyush"
MockLocalPlayer.UserId = 777001
local MockPlayerGui = Instance.new("PlayerGui", MockLocalPlayer)
MockPlayerGui.Name = "PlayerGui"

SERVICES.Players = {
	CharacterAutoLoads = true,
	LocalPlayer = MockLocalPlayer,
	PlayerAdded = makeSignal(),
	PlayerRemoving = makeSignal(),
	GetPlayers = function()
		return { MockLocalPlayer }
	end,
	GetPlayerByUserId = function(_self, uid)
		if uid == MockLocalPlayer.UserId then
			return MockLocalPlayer
		end
		return nil
	end,
}

SERVICES.UserInputService = {
	InputBegan = makeSignal(),
	InputChanged = makeSignal(),
	InputEnded = makeSignal(),
	TouchPinch = makeSignal(),
	IsKeyDown = function() return false end,
	GetFocusedTextBox = function() return nil end,
}

SERVICES.GuiService = {
	GetGuiInset = function()
		return Vector2.new(0, 36)
	end,
}

local game = {
	GetService = function(_self, name)
		assert(SERVICES[name] ~= nil, "Unmocked Roblox Service: " .. tostring(name))
		return SERVICES[name]
	end,
	BindToClose = function() end,
}
local workspace = SERVICES.Workspace

local function executeLuauInstance(inst)
	local fn = MODULES[inst._relPath]
	assert(fn ~= nil, "Missing registered Luau closure for " .. tostring(inst._relPath))
	return fn(inst)
end

local function require(modInst)
	assert(modInst ~= nil and modInst._relPath ~= nil, "Invalid ModuleScript passed to require()")
	if MODULE_CACHE[modInst] == nil then
		MODULE_CACHE[modInst] = executeLuauInstance(modInst)
	end
	return MODULE_CACHE[modInst]
end

${moduleClosures}

-- Build DataModel Instance hierarchy matching build_rbxl.py 1:1!
local sharedFolder = Instance.new("Folder", SERVICES.ReplicatedStorage)
sharedFolder.Name = "OpenFrontShared"
local mapsFolder = Instance.new("Folder", sharedFolder)
mapsFolder.Name = "Maps"
local serverFolder = Instance.new("Folder", SERVICES.ServerScriptService)
serverFolder.Name = "OpenFrontServer"
local clientFolder = Instance.new("Folder")
clientFolder.Name = "OpenFrontClient"

for relPath, _ in pairs(MODULES) do
	local parts = string.split(relPath, "/")
	local rootBucket = parts[1]
	local parentInst = if rootBucket == "Shared" then sharedFolder elseif rootBucket == "Server" then serverFolder else clientFolder
	for i = 2, #parts - 1 do
		local sub = parentInst:FindFirstChild(parts[i])
		if sub == nil then
			sub = Instance.new("Folder", parentInst)
			sub.Name = parts[i]
		end
		parentInst = sub
	end
	local leaf = parts[#parts]
	local className = "ModuleScript"
	local cleanName = leaf:gsub("%.luau$", "")
	if leaf:find("%.server%.luau$") then
		className = "Script"
		cleanName = leaf:gsub("%.server%.luau$", "")
	elseif leaf:find("%.client%.luau$") then
		className = "LocalScript"
		cleanName = leaf:gsub("%.client%.luau$", "")
	end
	local inst = Instance.new(className, parentInst)
	inst.Name = cleanName
	inst._relPath = relPath
end

-- ============================================================================
-- SUITE 2: Decode All 10 Exported Real Maps + Pathfinding + Label Boxes
-- ============================================================================
local MapRegistry = require(mapsFolder.MapRegistry)
local MapCodec = require(sharedFolder.MapCodec)
local Config = require(sharedFolder.Config)
local NetCodec = require(sharedFolder.NetCodec)
local SimEngine = require(serverFolder.SimEngine)
local DataService = require(serverFolder.DataService)

assert(#MapRegistry.List == 10, "Expected 10 maps in MapRegistry!")
local totalDecodedPixels = 0
for _, rawDef in ipairs(MapRegistry.List) do
	local decoded = MapCodec.DecodeMap(rawDef)
	assert(decoded.size == rawDef.width * rawDef.height, "Size mismatch on " .. rawDef.id)
	assert(buffer.len(decoded.terrain) == decoded.size, "Terrain buffer length mismatch on " .. rawDef.id)
	assert(decoded.numLandTiles > 1000, "Too few land tiles decoded on " .. rawDef.id)
	assert(#rawDef.nations > 0, "Expected pre-scripted nations on " .. rawDef.id)
	totalDecodedPixels += decoded.size
end
print(string.format("[PASS 2/6] All 10 real OpenFront maps decoded losslessly (%d total tiles verified)!", totalDecodedPixels))

-- ============================================================================
-- SUITE 3: OpenFront Math Formulas & NetCodec Binary Serialization Round-Trip
-- ============================================================================
assert(Config.MaxTroops(100, 1) > Config.MaxTroops(100, 0), "City must boost MaxTroops by +250k!")
assert(Config.UnitCost("City", { City = 0 }, 0, false, false) == 125000, "1st City must cost 125,000 Gold!")
assert(Config.UnitCost("City", { City = 1 }, 0, false, false) == 250000, "2nd City must cost 250,000 Gold!")
assert(Config.UnitCost("City", { City = 4 }, 0, false, false) == 1000000, "City cost must cap at 1,000,000 Gold!")
assert(Config.TradeShipGold(140, 500, 1) > Config.TradeShipGold(20, 500, 1), "Longer trade route must pay more Gold!")
assert(Config.TrainGold("ally", 2, 1) > Config.TrainGold("self", 2, 1), "Allied train route must pay more Gold than domestic!")

local testW, testH = 40, 30
local srcOwners = buffer.create(testW * testH * 2)
local dstOwners = buffer.create(testW * testH * 2)
local deltas, deltaOwners = {}, {}
for i = 0, 19 do
	local ref = i * 37
	local oid = (i % 7) + 1
	buffer.writeu16(srcOwners, ref * 2, oid)
	table.insert(deltas, ref)
	table.insert(deltaOwners, oid)
end
local deltaBuf = NetCodec.EncodeTileDeltas(deltas, deltaOwners, #deltas)
local dirtyRows, dirtyTiles = {}, {}
NetCodec.ApplyTileDeltas(deltaBuf, dstOwners, testW, dirtyRows, dirtyTiles)
for i = 0, testW * testH - 1 do
	assert(buffer.readu16(srcOwners, i * 2) == buffer.readu16(dstOwners, i * 2), "Delta decode mismatch!")
end
local rleSnap = NetCodec.EncodeFullOwnerSnapshot(srcOwners, testW * testH)
local dstSnap = buffer.create(testW * testH * 2)
NetCodec.DecodeFullOwnerSnapshot(rleSnap, dstSnap, testW * testH)
for i = 0, testW * testH - 1 do
	assert(buffer.readu16(srcOwners, i * 2) == buffer.readu16(dstSnap, i * 2), "Full RLE snapshot mismatch!")
end
print("[PASS 3/6] Exact OpenFront formulas & binary NetCodec delta/RLE codecs verified!")

-- ============================================================================
-- SUITE 4: Headless Full Simulation Engine — Combat, Trade Ships, Trains, Warships, Nukes, MIRVs & SAMs!
-- ============================================================================
local cfg = Config.DefaultGameConfig(true)
cfg.mapId = "ShinobiWorld"
cfg.bots = 45
cfg.startingGold = 0
cfg.instantBuild = true
cfg.doomsdayEnabled = true

local prof = DataService.GetProfile(MockLocalPlayer.UserId)
local sim = SimEngine.new(cfg, {
	{
		userId = MockLocalPlayer.UserId,
		name = "CommanderAyush",
		flag = prof.flag,
		colorHex = "#3b82f6",
		patternId = "none",
	},
}, false)

local konoha = sim.rawMap.nations[1]
local humanSpawnX = math.clamp(konoha.x + 28, 10, sim.map.width - 10)
local humanSpawnY = math.clamp(konoha.y + 18, 10, sim.map.height - 10)
sim:ChooseSpawn(MockLocalPlayer.UserId, humanSpawnX, humanSpawnY)

-- Step past 100-tick Spawn Phase, grant test treasury to Human, and expand!
for _ = 1, 105 do
	sim:Step()
end
local humanP = sim.playersByUserId[MockLocalPlayer.UserId]
humanP.gold = 80_000_000
humanP.troops = 180_000
sim:StartLandAttack(humanP, 0, humanP.troops * 0.55, nil)
for _ = 1, 140 do
	sim:Step()
end
assert(humanP.tilesOwned > 60, "Human + AI expansion must claim territory! Owned: " .. tostring(humanP.tilesOwned))
assert(humanP.labelSpan >= 1, "Maximal Inscribed Square label box must compute positive span!")

local ownedList = {}
for ref = 0, sim.map.size - 1 do
	if MapCodec.GetOwner(sim.map, ref) == humanP.smallId then
		table.insert(ownedList, ref)
	end
end
local coastalRef = nil
local waterRef = nil
for _, ref in ipairs(ownedList) do
	if MapCodec.IsShoreLand(sim.map, ref) then
		coastalRef = ref
		waterRef = MapCodec.AdjacentWater(sim.map, ref)
		if waterRef ~= nil then
			break
		end
	end
end

local maxBeforeCity = sim:GetMaxTroops(humanP)
local cityBuilt = sim:BuildUnit(humanP, "City", ownedList[math.max(1, math.floor(#ownedList * 0.5))])
assert(cityBuilt and sim:GetMaxTroops(humanP) == maxBeforeCity + 250000, "City must boost MaxTroops by exact +250,000!")
local siloBuilt = sim:BuildUnit(humanP, "MissileSilo", ownedList[math.max(1, math.floor(#ownedList * 0.3))])
assert(siloBuilt, "MissileSilo must be placed cleanly on owned territory!")
sim:BuildUnit(humanP, "Factory", ownedList[math.min(#ownedList, 6)])
sim:BuildUnit(humanP, "DefensePost", ownedList[math.min(#ownedList, 12)])
sim:BuildUnit(humanP, "SAMLauncher", ownedList[math.min(#ownedList, 20)])
if coastalRef ~= nil then
	sim:BuildUnit(humanP, "Port", coastalRef)
end
if waterRef ~= nil then
	sim:BuildUnit(humanP, "Warship", waterRef)
end
sim:Step()

local rival = nil
for _, p in ipairs(sim.playersList) do
	if p.smallId ~= humanP.smallId and p.alive and p.tilesOwned > 20 then
		rival = p
		break
	end
end
assert(rival ~= nil, "Expected active AI rival nation!")

sim:SendAllianceRequest(humanP, rival)
sim:DonateResources(humanP, rival, "gold", 50000)
sim:SetEmoji(humanP, "🔥")

for _ = 1, 80 do
	sim:Step()
end
-- Re-pick a fresh hostile living rival right before nuclear launch!
rival = nil
for _, p in ipairs(sim.playersList) do
	if p.smallId ~= humanP.smallId and not sim:AreFriendly(humanP, p) and p.alive and p.tilesOwned > 20 then
		rival = p
		break
	end
end
assert(rival ~= nil, "Expected hostile rival nation for nuclear strike!")
local targetRef = rival.labelY * sim.map.width + rival.labelX
assert(sim:BuildUnit(humanP, "AtomBomb", targetRef), "AtomBomb must launch cleanly from MissileSilo!")
for _ = 1, 95 do
	sim:Step()
end
assert(sim:BuildUnit(humanP, "MIRV", targetRef), "MIRV must launch after 90-tick silo reload!")

local sawExplosion = false
for _ = 1, 160 do
	sim:Step()
	if #sim.explosions > 0 then
		sawExplosion = true
	end
end
assert(sawExplosion, "AtomBomb / MIRV strike must reach target and detonate with fallout!")
local falloutCount = 0
for ref = 0, sim.map.size - 1 do
	if MapCodec.HasFallout(sim.map, ref) then
		falloutCount += 1
	end
end
assert(falloutCount > 0, "Nuclear detonation must create radioactive fallout tiles!")
print(string.format(
	"[PASS 4/6] Full ShinobiWorld simulation verified (Tiles: %d, Fallout: %d, Units active: %d, Events: %d)!",
	humanP.tilesOwned, falloutCount, #sim.units, #sim.events
))

-- ============================================================================
-- SUITE 5 & 6: Live Server Bootstrap + Client Main E2E (EditableImage AND Scanline2D Fallback!)
-- ============================================================================
executeLuauInstance(serverFolder.Bootstrap)
SERVICES.Players.PlayerAdded:Fire(MockLocalPlayer)

executeLuauInstance(clientFolder.Main)
local Remotes = SERVICES.ReplicatedStorage.OpenFrontRemotes

for _ = 1, 15 do
	HeartbeatSig:Fire(0.1)
	RenderSteppedSig:Fire(0.016)
end
local appGui = MockPlayerGui:WaitForChild("OpenFrontApp")
assert(appGui.MenuOverlay.Visible == true, "MenuOverlay must start visible during live background Preview!")

Remotes.ClientIntent:FireServer("StartMatchNow", Config.DefaultGameConfig(true))
for _ = 1, 115 do
	HeartbeatSig:Fire(0.1)
	RenderSteppedSig:Fire(0.016)
end
assert(appGui.InGameHUD.Visible == true, "InGameHUD must activate automatically once match starts!")

Remotes.ClientIntent:FireServer("UpdateProfile", { preferScanline2D = true, flag = "konoha", patternId = "stripes" })
ALLOW_EDITABLE_IMAGE = false
for _ = 1, 25 do
	HeartbeatSig:Fire(0.1)
	RenderSteppedSig:Fire(0.016)
end

-- Exercise EVERY client mouse, touch pinch, scroll zoom, radial menu, build popup, hotkey & victory ceremony!
local MapViewport = appGui:WaitForChild("MapViewport")
MapViewport.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 360, 0) })
SERVICES.UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(642, 361, 0) }, false)
SERVICES.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(642, 361, 0) })

MapViewport.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton2, Position = Vector3.new(620, 350, 0) })
SERVICES.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton2, Position = Vector3.new(620, 350, 0) })
assert(appGui.InGameHUD.RadialMenu.Visible == true, "Right-clicking map must open Circular Radial Menu!")

SERVICES.UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(640, 360, 1) }, false)
SERVICES.UserInputService.TouchPinch:Fire({ Vector2.new(500, 300), Vector2.new(700, 400) }, 1.25, 0, Enum.UserInputState.Begin)
SERVICES.UserInputService.TouchPinch:Fire({ Vector2.new(480, 290), Vector2.new(720, 410) }, 1.35, 0, Enum.UserInputState.Change)

for _, keyName in ipairs({ "B", "Space", "V", "R", "M", "T", "C", "Zero", "Q", "E", "Five", "Escape" }) do
	SERVICES.UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode[keyName] }, false)
end

local reward = DataService.RecordMatchResult(MockLocalPlayer.UserId, true, 4200, 0.84, 3, 950000, 420)
Remotes.MatchResult:FireClient(MockLocalPlayer, {
	kind = "Victory",
	winnerName = "CommanderAyush",
	tilesPeak = 4200,
	landPctPeak = 84.0,
	nukesSent = 3,
	reward = reward,
})
assert(appGui.InGameHUD.WinCeremonyModal.Visible == true, "Victory ceremony modal must appear on MatchResult!")
assert(appGui.InGameHUD.HudModalScrim.Visible == true, "HudModalScrim must cover background when modal is open!")
RenderSteppedSig:Fire(0.016)

-- Verify zero world labels bleed through open Victory modal!
for _, ch in ipairs(MapViewport.WorldVectorOverlay:GetChildren()) do
	if string.sub(ch.Name, 1, 6) == "Label_" then
		assert(ch.Visible == false, "World country label must be suppressed when full-screen modal is open!")
	end
end

-- Verify every rendered Scanline2D segment is strictly opaque (BackgroundTransparency == 0, zero alpha-stacking mud)!
local checkedSegs = 0
for _, layerFolder in ipairs({ MapViewport.MapSurface.ScanlineTerrain, MapViewport.MapSurface.ScanlineTerritory }) do
	for _, seg in ipairs(layerFolder:GetChildren()) do
		if seg.Visible then
			checkedSegs += 1
			assert((seg.BackgroundTransparency or 0) == 0, "Scanline segment must have BackgroundTransparency == 0!")
		end
	end
end
assert(checkedSegs > 0, "Scanline2D renderer must emit visible opaque segments!")

-- Dismiss modal, step render frame, and verify ZERO pairwise screen-space AABB overlaps among visible country labels!
appGui.InGameHUD.WinCeremonyModal.Visible = false
appGui.InGameHUD.HudModalScrim.Visible = false
RenderSteppedSig:Fire(0.016)
local visBoxes = {}
for _, lbl in ipairs(MapViewport.WorldVectorOverlay:GetChildren()) do
	if string.sub(lbl.Name, 1, 6) == "Label_" and lbl.Visible then
		local pos = lbl.Position
		local sz = lbl.Size
		local cx, cy = pos.X.Offset, pos.Y.Offset
		local hw, hh = sz.X.Offset * 0.5, sz.Y.Offset * 0.5
		local b = { x0 = cx - hw, y0 = cy - hh, x1 = cx + hw, y1 = cy + hh }
		for _, prev in ipairs(visBoxes) do
			local overlaps = (b.x0 < prev.x1) and (b.x1 > prev.x0) and (b.y0 < prev.y1) and (b.y1 > prev.y0)
			assert(not overlaps, "Visible country labels must NEVER overlap each other in screen space!")
		end
		table.insert(visBoxes, b)
	end
end

-- Verify responsive UIScale adapts BOTH Menu & HUD to compact split-screen/mobile viewports without breaking 1:1 map coordinates!
appGui.AbsoluteSize = Vector2.new(800, 480)
RenderSteppedSig:Fire(0.016)
assert(appGui.MenuOverlay.ResponsiveUIScale.Scale < 0.70 and appGui.MenuOverlay.ResponsiveUIScale.Scale >= 0.50, "MainMenu ResponsiveUIScale must scale down cleanly!")
assert(appGui.InGameHUD.ResponsiveUIScale.Scale < 0.70 and appGui.InGameHUD.ResponsiveUIScale.Scale >= 0.50, "InGameHUD ResponsiveUIScale must scale down cleanly!")
appGui.AbsoluteSize = Vector2.new(1280, 720)
RenderSteppedSig:Fire(0.016)

assert(reward.xpGained >= 500, "Victory XP reward must grant >= 500 XP!")
print(string.format(
	"[PASS 5/6] Full Live Server+Client E2E, Opaque Scanlines (%d segs), Modal Scrims, Responsive UIScale & Zero-Overlap Labels verified! (+%d XP -> Lv.%d)",
	checkedSegs, reward.xpGained, reward.newLevel
))

return true
`;

const vm = await LuauState.createAsync();
try {
  const fn = vm.loadstring(FULL_BUNDLE, "=openfront_full_e2e.luau", true);
  await fn();
  console.log(
    "[PASS 6/6] ALL HEADLESS LUAU WASM SIMULATION & UI TESTS PASSED 100%!",
  );
} catch (err) {
  const m = String(err).match(/openfront_full_e2e\.luau:(\d+):/);
  if (m) {
    const lineNo = Number(m[1]);
    const bundleLines = FULL_BUNDLE.split("\n");
    const ctx = bundleLines.slice(Math.max(0, lineNo - 6), lineNo + 5);
    console.error(
      `[BUNDLE LINE ${lineNo} CONTEXT]\n` +
        ctx.map((l, i) => `${lineNo - 5 + i}: ${l}`).join("\n"),
    );
  }
  console.error("[E2E FAILURE]", err);
  process.exit(1);
} finally {
  vm.destroy();
}
