--!strict
-- OpenFront Server Bootstrap:
-- Disables 3D character clutter, initializes Remotes & DataService, runs the live background
-- Preview Battle on the Main Menu, manages Public Lobby Queue + Singleplayer + Custom Host Lobby,
-- processes all ClientIntents at 10Hz, and awards persistent XP / Wins on Match End!

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Pure 2D Browser-Exact Experience: prevent default 3D avatars or baseplates from cluttering memory/screen!
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

-- Create Remotes Folder cleanly in ReplicatedStorage
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

-- Public Lobby Queue State (rotating featured OpenFront maps just like Master.ts!)
local FEATURED_ROTATION = {
	{ mapId = "World", mode = "FFA", numTeams = 0 },
	{ mapId = "ShinobiWorld", mode = "FFA", numTeams = 0 },
	{ mapId = "Europe", mode = "Teams", numTeams = 2 },
	{ mapId = "NorthAmerica", mode = "FFA", numTeams = 0 },
	{ mapId = "Asia", mode = "Teams", numTeams = 3 },
	{ mapId = "Africa", mode = "FFA", numTeams = 0 },
}

local rotationIndex = 1
local publicQueueUsers: { [number]: boolean } = {}
local lobbyCountdown = 15

local activeEngine: any = nil
local activeMode: "Preview" | "LiveMatch" = "Preview"
local postGameCooldown = 0

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
	previewCfg.bots = 40
	previewCfg.goldMultiplier = 3
	activeEngine = SimEngine.new(previewCfg, {}, true)
	-- Fast-forward 25 ticks so the preview map opens with lively borders right away!
	for _ = 1, 25 do
		activeEngine:Step()
	end
	StateSyncRE:FireAllClients(activeEngine:BuildTickPayload(true))
end

local function startLiveMatch(cfg: any, participants: { Player })
	activeMode = "LiveMatch"
	postGameCooldown = 0
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

-- Sanitize custom host GameConfig from client
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
	if type(raw.numTeams) == "number" then
		base.numTeams = math.clamp(math.floor(raw.numTeams), -1, 7)
	end
	if raw.difficulty == "Easy" or raw.difficulty == "Medium" or raw.difficulty == "Hard" or raw.difficulty == "Impossible" then
		base.difficulty = raw.difficulty
	end
	if type(raw.bots) == "number" then
		base.bots = math.clamp(math.floor(raw.bots), 0, 180)
	end
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
	if type(raw.startingGold) == "number" then
		base.startingGold = math.clamp(math.floor(raw.startingGold), 0, 50_000_000)
	end
	if type(raw.goldMultiplier) == "number" then
		base.goldMultiplier = math.clamp(raw.goldMultiplier, 0.5, 20)
	end
	if type(raw.disableAlliances) == "boolean" then
		base.disableAlliances = raw.disableAlliances
	end
	if type(raw.allianceDurationMinutes) == "number" then
		base.allianceDurationMinutes = math.clamp(math.floor(raw.allianceDurationMinutes), 1, 15)
	end
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

	-- Lobby & Profile intents
	if intentType == "UpdateProfile" and type(payload) == "table" then
		local updated = DataService.UpdatePreferences(uid, payload)
		ProfileSyncRE:FireClient(plr, updated)
		return
	elseif intentType == "ToggleQueue" then
		publicQueueUsers[uid] = not publicQueueUsers[uid]
		broadcastLobbyState()
		return
	elseif intentType == "StartMatchNow" then
		local cfg = sanitizeConfig(payload)
		local participants = Players:GetPlayers()
		startLiveMatch(cfg, participants)
		broadcastLobbyState()
		return
	elseif intentType == "ReturnToLobby" then
		-- If singleplayer or all humans dead/finished, return server to Preview Lobby!
		if activeMode == "LiveMatch" then
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

	-- Active Match Gameplay Intents
	if activeMode ~= "LiveMatch" or activeEngine == nil or type(payload) ~= "table" then
		return
	end

	if intentType == "ChooseSpawn" then
		activeEngine:ChooseSpawn(uid, tonumber(payload.x) or 0, tonumber(payload.y) or 0)
		return
	end

	local me = activeEngine.playersByUserId[uid]
	if me == nil or not me.alive then
		return
	end

	if intentType == "AttackLand" then
		local targetSmallId = math.floor(tonumber(payload.targetSmallId) or 0)
		local ratio = math.clamp(tonumber(payload.ratio) or 0.25, 0.01, 1.0)
		activeEngine:StartLandAttack(me, targetSmallId, me.troops * ratio, nil)
	elseif intentType == "BoatAttack" then
		local x = math.clamp(math.floor(tonumber(payload.x) or 0), 0, activeEngine.map.width - 1)
		local y = math.clamp(math.floor(tonumber(payload.y) or 0), 0, activeEngine.map.height - 1)
		local ratio = math.clamp(tonumber(payload.ratio) or 0.25, 0.01, 1.0)
		activeEngine:LaunchBoatAttack(me, y * activeEngine.map.width + x, me.troops * ratio)
	elseif intentType == "Retreat" then
		local atkId = if type(payload.attackId) == "number" then payload.attackId else nil
		activeEngine:RetreatAttack(me, atkId)
	elseif intentType == "RetreatBoats" then
		activeEngine:RetreatBoats(me)
	elseif intentType == "BuildUnit" then
		local unitType = tostring(payload.unitType or "")
		local x = math.clamp(math.floor(tonumber(payload.x) or 0), 0, activeEngine.map.width - 1)
		local y = math.clamp(math.floor(tonumber(payload.y) or 0), 0, activeEngine.map.height - 1)
		activeEngine:BuildUnit(me, unitType :: any, y * activeEngine.map.width + x)
	elseif intentType == "UpgradeStructure" then
		activeEngine:UpgradeStructure(me, math.floor(tonumber(payload.unitId) or 0))
	elseif intentType == "DeleteStructure" then
		activeEngine:DeleteStructure(me, math.floor(tonumber(payload.unitId) or 0))
	elseif intentType == "MoveWarship" then
		activeEngine:MoveWarship(
			me,
			math.floor(tonumber(payload.unitId) or 0),
			tonumber(payload.x) or 0,
			tonumber(payload.y) or 0
		)
	elseif intentType == "AllianceRequest" then
		local other = activeEngine.playersBySmallId[math.floor(tonumber(payload.targetSmallId) or 0)]
		if other ~= nil then
			activeEngine:SendAllianceRequest(me, other)
		end
	elseif intentType == "RespondAlliance" then
		local other = activeEngine.playersBySmallId[math.floor(tonumber(payload.fromSmallId) or 0)]
		local alerts = activeEngine.alertsByPlayer[me.smallId] or {}
		for i = #alerts, 1, -1 do
			if alerts[i].fromSmallId == (if other then other.smallId else -999) and alerts[i].kind ~= "NukeInbound" then
				table.remove(alerts, i)
			end
		end
		if other ~= nil and payload.accept == true then
			activeEngine:FormAlliance(me, other)
		end
	elseif intentType == "DismissAlert" then
		local alertId = math.floor(tonumber(payload.alertId) or 0)
		local alerts = activeEngine.alertsByPlayer[me.smallId] or {}
		for i = #alerts, 1, -1 do
			if alerts[i].id == alertId then
				table.remove(alerts, i)
			end
		end
	elseif intentType == "BreakAlliance" then
		local other = activeEngine.playersBySmallId[math.floor(tonumber(payload.targetSmallId) or 0)]
		if other ~= nil then
			activeEngine:BreakAlliance(me, other)
		end
	elseif intentType == "ToggleEmbargo" then
		local targetId = math.floor(tonumber(payload.targetSmallId) or 0)
		if targetId == -1 then
			-- Embargo All toggle!
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
	elseif intentType == "Donate" then
		local other = activeEngine.playersBySmallId[math.floor(tonumber(payload.targetSmallId) or 0)]
		if other ~= nil then
			local kind: "gold" | "troops" = if payload.kind == "gold" then "gold" else "troops"
			activeEngine:DonateResources(me, other, kind, tonumber(payload.amount) or 0)
		end
	elseif intentType == "TargetPlayer" then
		local other = activeEngine.playersBySmallId[math.floor(tonumber(payload.targetSmallId) or 0)]
		if other ~= nil and activeEngine.ticks - me.lastTargetTick >= 50 then
			me.lastTargetTick = activeEngine.ticks
			other.targetedBy[me.smallId] = activeEngine.ticks + Config.TARGET_DURATION_TICKS
			activeEngine:PushEvent("chat", "🎯 " .. me.name .. " marked " .. other.name .. " as a target!", "#ef4444", other.labelX, other.labelY)
		end
	elseif intentType == "SendEmoji" then
		local em = tostring(payload.emoji or "🫡")
		activeEngine:SetEmoji(me, em)
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
	local prof = DataService.LoadProfile(plr.UserId)
	ProfileSyncRE:FireClient(plr, prof)
	broadcastLobbyState()
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	publicQueueUsers[plr.UserId] = nil
	DataService.ReleaseProfile(plr.UserId)
end)

-- Boot initial live Preview Battle right away!
startPreviewBattle()

-- Main 10Hz Authoritative Fixed-Timestep Tick Loop (zero-drift 0.1000s step matching OpenFront!)
local tickCounter = 0
local tickAccumulator = 0.0

local function runAuthoritativeTick()
	tickCounter += 1

	if activeEngine ~= nil then
		activeEngine:Step()

			if activeMode == "LiveMatch" then
				-- Notify eliminated humans immediately so they get provisional XP / Spectate modal!
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
								p.survivedTicks / Config.TICKS_PER_SECOND
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

				-- Check full Victory!
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
									p.survivedTicks / Config.TICKS_PER_SECOND
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
				-- Cycle preview map every ~2.3 minutes for variety on the home screen!
				rotationIndex = (rotationIndex % #FEATURED_ROTATION) + 1
				startPreviewBattle()
			end

			StateSyncRE:FireAllClients(activeEngine:BuildTickPayload(false))
		end

		-- Once per second: update Public Queue countdown & auto-start when queued players ready!
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
