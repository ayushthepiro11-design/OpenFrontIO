--!strict
-- Persistent DataStore profile manager with automatic Studio offline memory fallback

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

type PlayerProfileSave = Types.PlayerProfileSave

local DataService = {}

local STORE_NAME = "OpenFront_PlayerData_v1"
local profileStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		profileStore = result
	end
end

local Profiles: { [number]: PlayerProfileSave } = {}

function DataService.DefaultProfile(userId: number): PlayerProfileSave
	local colorIdx = ((math.abs(userId) % #Theme.HumanColors) + 1)
	return {
		xp = 0,
		level = 1,
		prestige = 0,
		wins = 0,
		gamesPlayed = 0,
		tilesConquered = 0,
		nukesLaunched = 0,
		goldEarnedTotal = 0,
		flag = "in",
		colorIndex = colorIdx,
		patternId = "none",
		defaultAttackRatio = 0.25,
		colorblindMode = false,
		preferScanline2D = false,
		showNames = true,
		soundVolume = 0.7,
	}
end

function DataService.LoadProfile(userId: number): PlayerProfileSave
	if Profiles[userId] then
		return Profiles[userId]
	end
	local base = DataService.DefaultProfile(userId)
	if profileStore ~= nil and userId > 0 then
		local ok, saved = pcall(function()
			return profileStore:GetAsync("u_" .. tostring(userId))
		end)
		if ok and type(saved) == "table" then
			for k, v in pairs(saved) do
				if (base :: any)[k] ~= nil and type(v) == type((base :: any)[k]) then
					(base :: any)[k] = v
				end
			end
		end
	end
	Profiles[userId] = base
	return base
end

function DataService.GetProfile(userId: number): PlayerProfileSave
	return Profiles[userId] or DataService.LoadProfile(userId)
end

function DataService.UpdatePreferences(userId: number, patch: { [string]: any }): PlayerProfileSave
	local prof = DataService.GetProfile(userId)
	if type(patch.flag) == "string" and #patch.flag <= 12 then
		prof.flag = patch.flag
	end
	if type(patch.colorIndex) == "number" then
		prof.colorIndex = math.clamp(math.floor(patch.colorIndex), 1, #Theme.HumanColors)
	end
	if type(patch.patternId) == "string" then
		prof.patternId = patch.patternId
	end
	if type(patch.defaultAttackRatio) == "number" then
		prof.defaultAttackRatio = math.clamp(patch.defaultAttackRatio, 0.05, 1.0)
	end
	if type(patch.colorblindMode) == "boolean" then
		prof.colorblindMode = patch.colorblindMode
	end
	if type(patch.preferScanline2D) == "boolean" then
		prof.preferScanline2D = patch.preferScanline2D
	end
	if type(patch.showNames) == "boolean" then
		prof.showNames = patch.showNames
	end
	if type(patch.soundVolume) == "number" then
		prof.soundVolume = math.clamp(patch.soundVolume, 0, 1)
	end
	return prof
end

export type MatchRewardResult = {
	xpGained: number,
	prevLevel: number,
	newLevel: number,
	prestige: number,
	isVictory: boolean,
}

function DataService.RecordMatchResult(
	userId: number,
	isVictory: boolean,
	tilesPeak: number,
	landPercentPeak: number,
	nukesSent: number,
	goldEarned: number,
	secondsSurvived: number
): MatchRewardResult
	local prof = DataService.GetProfile(userId)
	local prevLevel = prof.level
	prof.gamesPlayed += 1
	prof.tilesConquered += math.max(0, math.floor(tilesPeak))
	prof.nukesLaunched += math.max(0, math.floor(nukesSent))
	prof.goldEarnedTotal += math.max(0, math.floor(goldEarned))
	if isVictory then
		prof.wins += 1
	end

	local rawXp = 120
		+ math.floor(math.min(600, secondsSurvived * 0.8))
		+ math.floor(landPercentPeak * 850)
		+ nukesSent * 45
	if isVictory then
		rawXp = math.floor(rawXp * 2.25 + 500)
	end

	prof.xp += rawXp
	while prof.xp >= Config.XpForNextLevel(prof.level) do
		prof.xp -= Config.XpForNextLevel(prof.level)
		prof.level += 1
		if prof.level > 25 and prof.prestige < 10 then
			prof.level = 1
			prof.prestige += 1
		end
	end

	DataService.SaveProfileAsync(userId)
	return {
		xpGained = rawXp,
		prevLevel = prevLevel,
		newLevel = prof.level,
		prestige = prof.prestige,
		isVictory = isVictory,
	}
end

function DataService.SaveProfileAsync(userId: number)
	local prof = Profiles[userId]
	if prof == nil or profileStore == nil or userId <= 0 then
		return
	end
	local copy = table.clone(prof)
	task.spawn(function()
		pcall(function()
			profileStore:SetAsync("u_" .. tostring(userId), copy)
		end)
	end)
end

function DataService.ReleaseProfile(userId: number)
	DataService.SaveProfileAsync(userId)
	Profiles[userId] = nil
end

return DataService
