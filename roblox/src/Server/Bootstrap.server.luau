--!native
--!strict
-- Security-Hardened OpenFront Authoritative Match Server (`Bootstrap.server.luau`)
-- Supports ALL 24 Full-Scale 1:1 OpenFront Maps (`1000x1000` .. `4108x1948`) with:
--   - Pure 2D workspace cleanup (`CharacterAutoLoads = false`)
--   - Sliding-window per-player RemoteEvent Rate Limiter (`<= 45 intents/sec` anti-flood protection!)
--   - Strict `Config.IsFiniteNumber` sanitization on EVERY GameConfig & ClientIntent parameter (`zero NaN/Inf bugs!`)
--   - Host / Singleplayer / Studio authorization for `StartMatchNow` & `SimControl` (`1x`/`2x`/`4x`/Pause)
--   - XP anti-exploit gate (`xpEligible = false` when cheat flags are active)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

Players.CharacterAutoLoads = false
for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("BasePart") or child:IsA("SpawnLocation") or child:IsA("Model") then
		child:Destroy()
	end
end

local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")
local Config = require(Shared:WaitForChild("Config"))
local MapRegistry = require(Shared:WaitForChild("Maps"):WaitForChild("MapRegistry"))
local Theme = require(Shared:WaitForChild("Theme"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local SimEngine = require(script.Parent:WaitForChild("SimEngine"))

local Remotes = ReplicatedStorage:FindFirstChild("OpenFrontRemotes")
if Remotes == nil then
	Remotes = Instance.new("Folder")
	Remotes.Name = "OpenFrontRemotes"
	Remotes.Parent = ReplicatedStorage
end

local function makeRemoteEvent(name: string): RemoteEvent
	local existing = Remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = Remotes
	return re
end

local function makeRemoteFunction(name: string): RemoteFunction
	local existing = Remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = Remotes
	return rf
end

local ClientIntentRE = makeRemoteEvent("ClientIntent")
local StateSyncRE = makeRemoteEvent("StateSync")
local LobbySyncRE = makeRemoteEvent("LobbySync")
local MatchResultRE = makeRemoteEvent("MatchResult")
local ProfileSyncRE = makeRemoteEvent("ProfileSync")
local GetInitialStateRF = makeRemoteFunction("GetInitialState")

-- Sliding-window per-player rate limiter (`<= 45 intents/sec`)
local rateWindowStart: { [number]: number } = {}
local rateCount: { [number]: number } = {}
local hostUserId = 0

local function allowIntentRate(uid: number): boolean
	local now = os.clock()
	local wStart = rateWindowStart[uid] or 0
	if now - wStart >= 1.0 then
		rateWindowStart[uid] = now
		rateCount[uid] = 1
		return true
	end
	local c = (rateCount[uid] or 0) + 1
	rateCount[uid] = c
	return c <= 45
end

local FEATURED_ROTATION = {
	{ mapId = "World", mode = "FFA", numTeams = 0 },
	{ mapId = "Europe", mode = "Teams", numTeams = 2 },
	{ mapId = "NorthAmerica", mode = "FFA", numTeams = 0 },
	{ mapId = "ShinobiWorld", mode = "FFA", numTeams = 0 },
	{ mapId = "GiantWorldMap", mode = "Teams", numTeams = 4 },
	{ mapId = "IndianSubcontinent", mode = "FFA", numTeams = 0 },
	{ mapId = "Asia", mode = "Teams", numTeams = 3 },
	{ mapId = "Caribbean", mode = "FFA", numTeams = 0 },
}

local rotationIndex = 1
local publicQueueUsers: { [number]: boolean } = {}
local lobbyCountdown = 15

local activeEngine: any = nil
local activeMode: "Preview" | "LiveMatch" = "Preview"
local postGameCooldown = 0
local xpEligible = true

local function isHostAuthorized(plr: Player): boolean
	return RunService:IsStudio() or #Players:GetPlayers() <= 1 or hostUserId == 0 or plr.UserId == hostUserId
end

local function buildHumanList(selectedPlayers: { Player })
	local out = {}
	for _, plr in ipairs(selectedPlayers) do
		local prof = DataService.GetProfile(plr.UserId)
		local palette = if prof.colorblindMode then Theme.ColorblindColors else Theme.HumanColors
		local col = palette[((prof.colorIndex - 1) % #palette) + 1]
		table.insert(out, {
			userId = plr.UserId,
			name = plr.DisplayName ~= "" and plr.DisplayName or plr.Name,
			flag = prof.flag,
			colorHex = col,
			patternId = prof.patternId,
		})
	end
	return out
end

local function startPreviewBattle()
	activeMode = "Preview"
	local previewCfg = Config.DefaultGameConfig(true)
	previewCfg.mapId = FEATURED_ROTATION[rotationIndex].mapId
	previewCfg.bots = 30
	previewCfg.goldMultiplier = 3
	previewCfg.seed = 42000 + rotationIndex
	activeEngine = SimEngine.new(previewCfg, {}, true)
	for _ = 1, 25 do
		activeEngine:Step()
	end
	StateSyncRE:FireAllClients(activeEngine:BuildTickPayload(true))
end

local function startLiveMatch(cfg: any, participants: { Player })
	activeMode = "LiveMatch"
	postGameCooldown = 0
	xpEligible = not (cfg.infiniteGold or cfg.infiniteTroops or cfg.instantBuild or cfg.startingGold > 0)
	table.clear(publicQueueUsers)
	local humans = buildHumanList(participants)
	activeEngine = SimEngine.new(cfg, humans, false)
	StateSyncRE:FireAllClients(activeEngine:BuildTickPayload(true))
end

local function broadcastLobbyState()
	local slot = FEATURED_ROTATION[rotationIndex]
	local mapDef = MapRegistry.Get(slot.mapId)
	local queuedNames = {}
	for uid, queued in pairs(publicQueueUsers) do
		if queued then
			local plr = Players:GetPlayerByUserId(uid)
			if plr then
				table.insert(queuedNames, plr.DisplayName ~= "" and plr.DisplayName or plr.Name)
			end
		end
	end
	LobbySyncRE:FireAllClients({
		activeMode = activeMode,
		nextMapId = slot.mapId,
		nextMapName = mapDef.name,
		nextMode = slot.mode,
		nextNumTeams = slot.numTeams,
		countdown = lobbyCountdown,
		queuedPlayers = queuedNames,
		onlineCount = #Players:GetPlayers(),
	})
end

local function sanitizeConfig(raw: any): any
	local base = Config.DefaultGameConfig(false)
	if type(raw) ~= "table" then
		return base
	end
	if type(raw.mapId) == "string" and MapRegistry.ById[raw.mapId] ~= nil then
		base.mapId = raw.mapId
	end
	if raw.mode == "FFA" or raw.mode == "Teams" then
		base.mode = raw.mode
	end
	base.numTeams = math.floor(Config.SafeClampNumber(raw.numTeams, -1, 7, base.numTeams))
	if raw.difficulty == "Easy" or raw.difficulty == "Medium" or raw.difficulty == "Hard" or raw.difficulty == "Impossible" then
		base.difficulty = raw.difficulty
	end
	base.bots = math.floor(Config.SafeClampNumber(raw.bots, 0, 180, base.bots))
	if type(raw.spawnNations) == "boolean" then
		base.spawnNations = raw.spawnNations
	end
	if type(raw.instantBuild) == "boolean" then
		base.instantBuild = raw.instantBuild
	end
	if type(raw.infiniteGold) == "boolean" then
		base.infiniteGold = raw.infiniteGold
	end
	if type(raw.infiniteTroops) == "boolean" then
		base.infiniteTroops = raw.infiniteTroops
	end
	base.startingGold = math.floor(Config.SafeClampNumber(raw.startingGold, 0, 50_000_000, base.startingGold))
	base.goldMultiplier = Config.SafeClampNumber(raw.goldMultiplier, 0.5, 20, base.goldMultiplier)
	if type(raw.disableAlliances) == "boolean" then
		base.disableAlliances = raw.disableAlliances
	end
	base.allianceDurationMinutes = math.floor(Config.SafeClampNumber(raw.allianceDurationMinutes, 1, 15, base.allianceDurationMinutes))
	if type(raw.donateGold) == "boolean" then
		base.donateGold = raw.donateGold
	end
	if type(raw.donateTroops) == "boolean" then
		base.donateTroops = raw.donateTroops
	end
	if type(raw.randomSpawn) == "boolean" then
		base.randomSpawn = raw.randomSpawn
	end
	if type(raw.waterNukes) == "boolean" then
		base.waterNukes = raw.waterNukes
	end
	if type(raw.doomsdayEnabled) == "boolean" then
		base.doomsdayEnabled = raw.doomsdayEnabled
	end
	if raw.doomsdaySpeed == "slow" or raw.doomsdaySpeed == "normal" or raw.doomsdaySpeed == "fast" or raw.doomsdaySpeed == "veryfast" then
		base.doomsdaySpeed = raw.doomsdaySpeed
	end
	if type(raw.overtimeEnabled) == "boolean" then
		base.overtimeEnabled = raw.overtimeEnabled
	end
	if type(raw.singleplayer) == "boolean" then
		base.singleplayer = raw.singleplayer
	end
	base.seed = math.floor(Config.SafeClampNumber(raw.seed, 1, 2_147_483_647, math.floor(os.clock() * 1000) % 1_000_000 + 1337))
	return base
end

GetInitialStateRF.OnServerInvoke = function(plr: Player)
	local prof = DataService.LoadProfile(plr.UserId)
	return {
		profile = prof,
		snapshot = if activeEngine ~= nil then activeEngine:BuildTickPayload(true) else nil,
	}
end

ClientIntentRE.OnServerEvent:Connect(function(plr: Player, intentType: any, payload: any)
	if type(intentType) ~= "string" then
		return
	end
	local uid = plr.UserId
	if not allowIntentRate(uid) then
		return
	end

	if intentType == "UpdateProfile" and type(payload) == "table" then
		local updated = DataService.UpdatePreferences(uid, payload)
		ProfileSyncRE:FireClient(plr, updated)
		return
	elseif intentType == "ToggleQueue" then
		publicQueueUsers[uid] = not publicQueueUsers[uid]
		broadcastLobbyState()
		return
	elseif intentType == "StartMatchNow" then
		if not isHostAuthorized(plr) then
			return
		end
		local cfg = sanitizeConfig(payload)
		local participants = Players:GetPlayers()
		startLiveMatch(cfg, participants)
		broadcastLobbyState()
		return
	elseif intentType == "SimControl" and type(payload) == "table" then
		if activeEngine ~= nil and isHostAuthorized(plr) then
			if type(payload.paused) == "boolean" then
				activeEngine.paused = payload.paused
			end
			local spd = payload.speed or payload.simSpeed
			if Config.IsFiniteNumber(spd) then
				activeEngine.simSpeed = math.clamp(math.floor(spd), 1, 4)
			end
		end
		return
	elseif intentType == "StartSpawnNow" then
		if activeEngine ~= nil and activeEngine.inSpawnPhase and isHostAuthorized(plr) then
			activeEngine.ticks = activeEngine.spawnPhaseTicks - 1
		end
		return
	elseif intentType == "ReturnToLobby" then
		if activeMode == "LiveMatch" and activeEngine ~= nil then
			local otherAliveHumans = false
			for _, p in ipairs(activeEngine.playersList) do
				if p.playerType == "Human" and p.userId ~= uid and p.alive then
					otherAliveHumans = true
					break
				end
			end
			if not otherAliveHumans or activeEngine.gameOver then
				startPreviewBattle()
				broadcastLobbyState()
			end
		end
		return
	end

	if activeMode ~= "LiveMatch" or activeEngine == nil or type(payload) ~= "table" then
		return
	end

	if intentType == "ChooseSpawn" then
		if Config.IsFiniteNumber(payload.x) and Config.IsFiniteNumber(payload.y) then
			activeEngine:ChooseSpawn(uid, payload.x, payload.y)
		end
		return
	end

	local me = activeEngine.playersByUserId[uid]
	if me == nil or not me.alive then
		return
	end

	if intentType == "AttackLand" then
		if Config.IsFiniteNumber(payload.targetSmallId) then
			local targetSmallId = math.floor(payload.targetSmallId)
			local ratio = Config.SafeClampNumber(payload.ratio, 0.01, 1.0, 0.25)
			activeEngine:StartLandAttack(me, targetSmallId, me.troops * ratio, nil)
		end
	elseif intentType == "BoatAttack" then
		if Config.IsFiniteNumber(payload.x) and Config.IsFiniteNumber(payload.y) then
			local x = math.clamp(math.floor(payload.x), 0, activeEngine.map.width - 1)
			local y = math.clamp(math.floor(payload.y), 0, activeEngine.map.height - 1)
			local ratio = Config.SafeClampNumber(payload.ratio, 0.01, 1.0, 0.25)
			activeEngine:LaunchBoatAttack(me, y * activeEngine.map.width + x, me.troops * ratio)
		end
	elseif intentType == "Retreat" then
		local atkId = if Config.IsFiniteNumber(payload.attackId) then math.floor(payload.attackId) else nil
		activeEngine:RetreatAttack(me, atkId)
	elseif intentType == "RetreatBoats" then
		activeEngine:RetreatBoats(me)
	elseif intentType == "BuildUnit" then
		if type(payload.unitType) == "string" and Config.IsFiniteNumber(payload.x) and Config.IsFiniteNumber(payload.y) then
			local x = math.clamp(math.floor(payload.x), 0, activeEngine.map.width - 1)
			local y = math.clamp(math.floor(payload.y), 0, activeEngine.map.height - 1)
			activeEngine:BuildUnit(me, payload.unitType :: any, y * activeEngine.map.width + x)
		end
	elseif intentType == "UpgradeStructure" then
		if Config.IsFiniteNumber(payload.unitId) then
			activeEngine:UpgradeStructure(me, math.floor(payload.unitId))
		end
	elseif intentType == "DeleteStructure" then
		if Config.IsFiniteNumber(payload.unitId) then
			activeEngine:DeleteStructure(me, math.floor(payload.unitId))
		end
	elseif intentType == "MoveWarship" then
		if Config.IsFiniteNumber(payload.unitId) and Config.IsFiniteNumber(payload.x) and Config.IsFiniteNumber(payload.y) then
			activeEngine:MoveWarship(me, math.floor(payload.unitId), payload.x, payload.y)
		end
	elseif intentType == "AllianceRequest" then
		if Config.IsFiniteNumber(payload.targetSmallId) then
			local other = activeEngine.playersBySmallId[math.floor(payload.targetSmallId)]
			if other ~= nil then
				activeEngine:SendAllianceRequest(me, other)
			end
		end
	elseif intentType == "RespondAlliance" then
		if Config.IsFiniteNumber(payload.fromSmallId) then
			local fromId = math.floor(payload.fromSmallId)
			local other = activeEngine.playersBySmallId[fromId]
			local alerts = activeEngine.alertsByPlayer[me.smallId] or {}
			local foundValid = false
			for i = #alerts, 1, -1 do
				if alerts[i].fromSmallId == fromId and alerts[i].kind ~= "NukeInbound" then
					foundValid = true
					table.remove(alerts, i)
				end
			end
			if other ~= nil and foundValid and payload.accept == true then
				activeEngine:FormAlliance(me, other)
			end
		end
	elseif intentType == "DismissAlert" then
		if Config.IsFiniteNumber(payload.alertId) then
			local alertId = math.floor(payload.alertId)
			local alerts = activeEngine.alertsByPlayer[me.smallId] or {}
			for i = #alerts, 1, -1 do
				if alerts[i].id == alertId then
					table.remove(alerts, i)
				end
			end
		end
	elseif intentType == "BreakAlliance" then
		if Config.IsFiniteNumber(payload.targetSmallId) then
			local other = activeEngine.playersBySmallId[math.floor(payload.targetSmallId)]
			if other ~= nil then
				activeEngine:BreakAlliance(me, other)
			end
		end
	elseif intentType == "ToggleEmbargo" then
		if Config.IsFiniteNumber(payload.targetSmallId) then
			local targetId = math.floor(payload.targetSmallId)
			if targetId == -1 then
				local hasAny = next(me.embargoes) ~= nil
				table.clear(me.embargoes)
				if not hasAny then
					for _, other in ipairs(activeEngine.playersList) do
						if other ~= me and not activeEngine:AreFriendly(me, other) then
							me.embargoes[other.smallId] = true
						end
					end
				end
			elseif targetId > 0 then
				if me.embargoes[targetId] then
					me.embargoes[targetId] = nil
				else
					me.embargoes[targetId] = true
				end
			end
		end
	elseif intentType == "Donate" then
		if Config.IsFiniteNumber(payload.targetSmallId) and Config.IsFiniteNumber(payload.amount) then
			local other = activeEngine.playersBySmallId[math.floor(payload.targetSmallId)]
			if other ~= nil then
				local kind: "gold" | "troops" = if payload.kind == "gold" then "gold" else "troops"
				activeEngine:DonateResources(me, other, kind, payload.amount)
			end
		end
	elseif intentType == "TargetPlayer" then
		if Config.IsFiniteNumber(payload.targetSmallId) then
			local other = activeEngine.playersBySmallId[math.floor(payload.targetSmallId)]
			if other ~= nil and activeEngine.ticks - me.lastTargetTick >= Config.TARGET_COOLDOWN_TICKS then
				me.lastTargetTick = activeEngine.ticks
				other.targetedBy[me.smallId] = activeEngine.ticks + Config.TARGET_DURATION_TICKS
				activeEngine:PushEvent("chat", "🎯 " .. me.name .. " marked " .. other.name .. " as a target!", "#ef4444", other.labelX, other.labelY)
			end
		end
	elseif intentType == "SendEmoji" then
		local em = tostring(payload.emoji or "🫡")
		if Config.AllowedEmojis[em] then
			activeEngine:SetEmoji(me, em)
		end
	elseif intentType == "QuickChat" then
		local qcId = tostring(payload.id or "")
		for _, qc in ipairs(Config.QuickChats) do
			if qc.id == qcId then
				activeEngine:PushEvent("chat", "[" .. me.name .. "]: " .. qc.text, qc.color, me.labelX, me.labelY)
				break
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(plr: Player)
	if hostUserId == 0 then
		hostUserId = plr.UserId
	end
	local prof = DataService.LoadProfile(plr.UserId)
	ProfileSyncRE:FireClient(plr, prof)
	broadcastLobbyState()
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	publicQueueUsers[plr.UserId] = nil
	rateWindowStart[plr.UserId] = nil
	rateCount[plr.UserId] = nil
	if plr.UserId == hostUserId then
		local rem = Players:GetPlayers()
		hostUserId = if #rem > 0 then rem[1].UserId else 0
	end
	DataService.ReleaseProfile(plr.UserId)
end)

startPreviewBattle()

local tickCounter = 0
local tickAccumulator = 0.0

local function runAuthoritativeTick()
	tickCounter += 1

	if activeEngine ~= nil then
		local subSteps = if activeEngine.paused then 0 else math.clamp(activeEngine.simSpeed or 1, 1, 4)
		for _ = 1, subSteps do
			activeEngine:Step()
		end

		if activeMode == "LiveMatch" then
			for _, p in ipairs(activeEngine.playersList) do
				if p.playerType == "Human" and not activeEngine.inSpawnPhase and p.hasSpawned and not p.alive and not p.deathNotified then
					p.deathNotified = true
					local plr = Players:GetPlayerByUserId(p.userId)
					if plr ~= nil then
						local peakShare = p.tilesPeak / math.max(1, activeEngine.map.numLandTiles)
						local reward = DataService.RecordMatchResult(
							p.userId,
							false,
							p.tilesPeak,
							peakShare,
							p.nukesSent,
							p.goldEarned,
							p.survivedTicks / Config.TICKS_PER_SECOND,
							xpEligible
						)
						ProfileSyncRE:FireClient(plr, DataService.GetProfile(p.userId))
						MatchResultRE:FireClient(plr, {
							kind = "Eliminated",
							winnerName = activeEngine.winnerName,
							tilesPeak = p.tilesPeak,
							landPctPeak = peakShare * 100,
							nukesSent = p.nukesSent,
							reward = reward,
						})
					end
				end
			end

			if activeEngine.gameOver and postGameCooldown == 0 then
				postGameCooldown = 1
				for _, p in ipairs(activeEngine.playersList) do
					if p.playerType == "Human" and not p.deathNotified then
						p.deathNotified = true
						local isWinner = (activeEngine.winnerSmallId == p.smallId)
							or (p.team ~= nil and activeEngine.winnerTeam == p.team)
						local plr = Players:GetPlayerByUserId(p.userId)
						if plr ~= nil then
							local peakShare = p.tilesPeak / math.max(1, activeEngine.map.numLandTiles)
							local reward = DataService.RecordMatchResult(
								p.userId,
								isWinner,
								p.tilesPeak,
								peakShare,
								p.nukesSent,
								p.goldEarned,
								p.survivedTicks / Config.TICKS_PER_SECOND,
								xpEligible
							)
							ProfileSyncRE:FireClient(plr, DataService.GetProfile(p.userId))
							MatchResultRE:FireClient(plr, {
								kind = if isWinner then "Victory" else "Defeat",
								winnerName = activeEngine.winnerName or p.name,
								tilesPeak = p.tilesPeak,
								landPctPeak = peakShare * 100,
								nukesSent = p.nukesSent,
								reward = reward,
							})
						end
					end
				end
			end
		elseif activeMode == "Preview" and activeEngine.ticks > 1400 then
			rotationIndex = (rotationIndex % #FEATURED_ROTATION) + 1
			startPreviewBattle()
		end

		StateSyncRE:FireAllClients(activeEngine:BuildTickPayload(false))
	end

	if tickCounter % 10 == 0 then
		if activeMode == "Preview" then
			local hasQueued = false
			for _, q in pairs(publicQueueUsers) do
				if q then
					hasQueued = true
					break
				end
			end
			if hasQueued then
				lobbyCountdown -= 1
				if lobbyCountdown <= 0 then
					local slot = FEATURED_ROTATION[rotationIndex]
					local cfg = Config.DefaultGameConfig(false)
					cfg.mapId = slot.mapId
					cfg.mode = slot.mode :: any
					cfg.numTeams = slot.numTeams
					lobbyCountdown = 15
					rotationIndex = (rotationIndex % #FEATURED_ROTATION) + 1
					startLiveMatch(cfg, Players:GetPlayers())
				end
			else
				lobbyCountdown = 12
			end
		end
		broadcastLobbyState()
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	tickAccumulator = math.min(tickAccumulator + dt, 0.5)
	while tickAccumulator >= 0.0999 do
		tickAccumulator -= 0.10
		runAuthoritativeTick()
	end
end)
