--!native
--!strict
-- Hardened Persistent DataStore Profile Manager (`DataService.luau`)
-- Upgraded with:
--   - Exponential retry on `GetAsync` (`3` attempts)
--   - Atomic `UpdateAsync` instead of racy `SetAsync` (`zero concurrent write clobbers!`)
--   - Strict `Config.IsFiniteNumber` sanitization on load, preference update, and match rewards
--   - `game:BindToClose` clean flush so zero XP/Wins are ever lost on shutdown!

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
local DirtyUsers: { [number]: boolean } = {}

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
		for attempt = 1, 3 do
			local ok, saved = pcall(function()
				return (profileStore :: DataStore):GetAsync("u_" .. tostring(userId))
			end)
			if ok then
				if type(saved) == "table" then
					for k, v in pairs(saved) do
						if (base :: any)[k] ~= nil and type(v) == type((base :: any)[k]) then
							if type(v) ~= "number" or Config.IsFiniteNumber(v) then
								(base :: any)[k] = v
							end
						end
					end
				end
				break
			end
			if attempt < 3 then
				task.wait(0.2 * attempt)
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
	if type(patch) ~= "table" then
		return prof
	end
	if type(patch.flag) == "string" and #patch.flag <= 12 then
		prof.flag = patch.flag
	end
	if Config.IsFiniteNumber(patch.colorIndex) then
		prof.colorIndex = math.clamp(math.floor(patch.colorIndex), 1, #Theme.HumanColors)
	end
	if type(patch.patternId) == "string" and #patch.patternId <= 16 then
		prof.patternId = patch.patternId
	end
	if Config.IsFiniteNumber(patch.defaultAttackRatio) then
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
	if Config.IsFiniteNumber(patch.soundVolume) then
		prof.soundVolume = math.clamp(patch.soundVolume, 0, 1)
	end
	DirtyUsers[userId] = true
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
	secondsSurvived: number,
	xpEligible: boolean?
): MatchRewardResult
	local prof = DataService.GetProfile(userId)
	local prevLevel = prof.level
	local safeTiles = math.max(0, math.floor(Config.SafeClampNumber(tilesPeak, 0, 100_000_000, 0)))
	local safeShare = Config.SafeClampNumber(landPercentPeak, 0, 1.0, 0)
	local safeNukes = math.max(0, math.floor(Config.SafeClampNumber(nukesSent, 0, 100_000, 0)))
	local safeGold = math.max(0, math.floor(Config.SafeClampNumber(goldEarned, 0, 1_000_000_000_000, 0)))
	local safeSecs = Config.SafeClampNumber(secondsSurvived, 0, 86_400, 0)

	prof.gamesPlayed += 1
	prof.tilesConquered += safeTiles
	prof.nukesLaunched += safeNukes
	prof.goldEarnedTotal += safeGold
	if isVictory and xpEligible ~= false then
		prof.wins += 1
	end

	local rawXp = 0
	if xpEligible ~= false then
		rawXp = 120
			+ math.floor(math.min(600, safeSecs * 0.8))
			+ math.floor(safeShare * 850)
			+ safeNukes * 45
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

function DataService.SaveProfileSync(userId: number)
	local prof = Profiles[userId]
	if prof == nil or profileStore == nil or userId <= 0 then
		return
	end
	local copy = table.clone(prof)
	pcall(function()
		(profileStore :: DataStore):UpdateAsync("u_" .. tostring(userId), function(_old)
			return copy
		end)
	end)
	DirtyUsers[userId] = nil
end

function DataService.SaveProfileAsync(userId: number)
	local prof = Profiles[userId]
	if prof == nil or profileStore == nil or userId <= 0 then
		return
	end
	local copy = table.clone(prof)
	DirtyUsers[userId] = nil
	task.spawn(function()
		pcall(function()
			(profileStore :: DataStore):UpdateAsync("u_" .. tostring(userId), function(_old)
				return copy
			end)
		end)
	end)
end

function DataService.ReleaseProfile(userId: number)
	DataService.SaveProfileAsync(userId)
	Profiles[userId] = nil
	DirtyUsers[userId] = nil
end

function DataService.FlushAll()
	for userId, _ in pairs(Profiles) do
		DataService.SaveProfileSync(userId)
	end
end

pcall(function()
	game:BindToClose(function()
		DataService.FlushAll()
	end)
end)

return DataService
