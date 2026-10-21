--!strict
-- Port of OpenFront NationExecution + TribeExecution AI behaviors:
-- Expansion across Terra Nullius, opportunistic border wars, traitor dogpiling,
-- amphibious TransportShip island invasions, full structure economy (Cities, Ports,
-- Factories, Defense Posts, Silos, SAMs, Warships), nuclear retaliation, alliances & emojis!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")
local Config = require(Shared:WaitForChild("Config"))
local MapCodec = require(Shared:WaitForChild("MapCodec"))

local AiBrain = {}

-- Find an interior owned tile far enough from other structures
local function pickOwnedTile(engine: any, p: any, requireShore: boolean): number?
	local map = engine.map
	local w = map.width
	local borderList = p.borderList
	if requireShore then
		-- Scan player's shore border tiles first
		local count = #borderList
		if count == 0 then
			return nil
		end
		local startIdx = math.random(1, count)
		for step = 0, math.min(count - 1, 90) do
			local ref = borderList[((startIdx + step - 1) % count) + 1]
			if MapCodec.GetOwner(map, ref) == p.smallId and MapCodec.IsShoreLand(map, ref) then
				if engine:CanPlaceStructureNear(p, ref) then
					return ref
				end
			end
		end
		return nil
	end

	-- Pick near player's label box center or random owned border inward step
	local lx = math.clamp(math.floor(p.labelX), 0, w - 1)
	local ly = math.clamp(math.floor(p.labelY), 0, map.height - 1)
	for _ = 1, 24 do
		local ox = math.clamp(lx + math.random(-22, 22), 0, w - 1)
		local oy = math.clamp(ly + math.random(-22, 22), 0, map.height - 1)
		local ref = oy * w + ox
		if MapCodec.GetOwner(map, ref) == p.smallId and MapCodec.IsPlayableLand(map, ref) then
			if engine:CanPlaceStructureNear(p, ref) then
				return ref
			end
		end
	end
	return nil
end

local function runNationEconomyAndWarships(engine: any, p: any)
	local cfg = engine.config
	local isHuman = false
	-- Check unit priorities based on gold & current counts
	local cities = p.unitCounts["City"] or 0
	local ports = p.unitCounts["Port"] or 0
	local factories = p.unitCounts["Factory"] or 0
	local posts = p.unitCounts["DefensePost"] or 0
	local silos = p.unitCounts["MissileSilo"] or 0
	local sams = p.unitCounts["SAMLauncher"] or 0
	local warships = p.unitCounts["Warship"] or 0

	-- 1. Early Port on coast for Trade Ship income!
	if ports < 2 and p.tilesOwned > 45 then
		local portCost = Config.UnitCost("Port", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
		if p.gold >= portCost then
			local shoreRef = pickOwnedTile(engine, p, true)
			if shoreRef ~= nil then
				engine:BuildUnit(p, "Port", shoreRef)
				return
			end
		end
	end

	-- 2. Cities for max troop cap scaling
	if cities <= factories + 1 and p.tilesOwned > 35 then
		local cityCost = Config.UnitCost("City", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
		if p.gold >= cityCost * 1.05 then
			local ref = pickOwnedTile(engine, p, false)
			if ref ~= nil then
				engine:BuildUnit(p, "City", ref)
				return
			end
		end
	end

	-- 3. Factories to spawn railroad Trains between Cities & Ports
	if factories < 3 and cities >= 1 and p.tilesOwned > 80 then
		local facCost = Config.UnitCost("Factory", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
		if p.gold >= facCost * 1.1 then
			local ref = pickOwnedTile(engine, p, false)
			if ref ~= nil then
				engine:BuildUnit(p, "Factory", ref)
				return
			end
		end
	end

	-- 4. Defense Post on frontier borders
	if posts < math.min(5, math.floor(p.tilesOwned / 220) + 1) and #p.borderList > 8 then
		local dpCost = Config.UnitCost("DefensePost", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
		if p.gold >= dpCost * 1.25 then
			local bRef = p.borderList[math.random(1, #p.borderList)]
			if bRef ~= nil and engine:CanPlaceStructureNear(p, bRef) then
				engine:BuildUnit(p, "DefensePost", bRef)
				return
			end
		end
	end

	-- 5. Naval power: build Warships if we own a Port
	if ports >= 1 and warships < 3 and cfg.difficulty ~= "Easy" then
		local wsCost = Config.UnitCost("Warship", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
		if p.gold >= wsCost * 1.2 then
			local portUnit = engine:FindFirstOwnedUnit(p.smallId, "Port")
			if portUnit ~= nil then
				local waterRef = MapCodec.AdjacentWater(engine.map, portUnit.y * engine.map.width + portUnit.x)
				if waterRef ~= nil then
					engine:BuildUnit(p, "Warship", waterRef)
					return
				end
			end
		end
	end

	-- 6. Nuclear deterrence: SAM Launcher & Missile Silo!
	if sams < 2 and p.tilesOwned > 150 then
		local samCost = Config.UnitCost("SAMLauncher", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
		if p.gold >= samCost then
			local ref = pickOwnedTile(engine, p, false)
			if ref ~= nil then
				engine:BuildUnit(p, "SAMLauncher", ref)
				return
			end
		end
	end

	if silos < 1 and p.tilesOwned > 180 and cfg.difficulty ~= "Easy" then
		local siloCost = Config.UnitCost("MissileSilo", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
		if p.gold >= siloCost then
			local ref = pickOwnedTile(engine, p, false)
			if ref ~= nil then
				engine:BuildUnit(p, "MissileSilo", ref)
				return
			end
		end
	end

	-- 7. Launch Nukes or MIRV when holding a Silo and hostile against strong rivals!
	if silos >= 1 then
		local bestEnemy = engine:PickHostileTargetForNuke(p)
		if bestEnemy ~= nil then
			local mirvCost = Config.UnitCost("MIRV", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
			local hCost = Config.UnitCost("HydrogenBomb", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
			local aCost = Config.UnitCost("AtomBomb", p.unitCounts, engine.mirvsLaunched, cfg.infiniteGold, isHuman)
			local targetRef = math.clamp(math.floor(bestEnemy.labelY), 0, engine.map.height - 1) * engine.map.width
				+ math.clamp(math.floor(bestEnemy.labelX), 0, engine.map.width - 1)
			if p.gold >= mirvCost and bestEnemy.tilesOwned > 600 then
				engine:BuildUnit(p, "MIRV", targetRef)
			elseif p.gold >= hCost and math.random() < 0.45 then
				engine:BuildUnit(p, "HydrogenBomb", targetRef)
			elseif p.gold >= aCost * 1.15 then
				engine:BuildUnit(p, "AtomBomb", targetRef)
			end
		end
	end
end

function AiBrain.StepAll(engine: any, tick: number)
	local map = engine.map
	local nbuf = { 0, 0, 0, 0 }

	for _, p in ipairs(engine.playersList) do
		if not p.alive or p.playerType == "Human" then
			continue
		end
		if tick % p.aiCadence ~= p.aiOffset then
			continue
		end

		local maxT = engine:GetMaxTroops(p)
		local troopFrac = p.troops / math.max(1, maxT)

		-- Inspect bordering owners
		local bordersTerraNullius = false
		local neighborCounts: { [number]: number } = {}
		local shoreTiles: { number } = {}
		local bLen = #p.borderList
		local sampleCount = math.min(bLen, 48)
		if sampleCount > 0 then
			local startIdx = math.random(1, bLen)
			for s = 0, sampleCount - 1 do
				local bRef = p.borderList[((startIdx + s - 1) % bLen) + 1]
				if MapCodec.GetOwner(map, bRef) == p.smallId then
					local n = MapCodec.Neighbors4(map, bRef, nbuf)
					for i = 1, n do
						local nb = nbuf[i]
						if MapCodec.IsPlayableLand(map, nb) then
							local oid = MapCodec.GetOwner(map, nb)
							if oid == 0 then
								bordersTerraNullius = true
							elseif oid ~= p.smallId then
								neighborCounts[oid] = (neighborCounts[oid] or 0) + 1
							end
						elseif MapCodec.IsWater(map, nb) and #shoreTiles < 8 then
							table.insert(shoreTiles, bRef)
						end
					end
				end
			end
		end

	-- Priority 1: Sweep ALL adjacent unclaimed Terra Nullius smoothly & rapidly first!
	if bordersTerraNullius and p.troops > 250 and troopFrac > 0.08 then
		local ratio = if p.playerType == "Nation" then 0.44 else 0.30
		engine:StartLandAttack(p, 0, math.floor(p.troops * ratio))
		continue
	end

		-- Nations build structures, propose alliances & react with emojis
		if p.playerType == "Nation" then
			runNationEconomyAndWarships(engine, p)

			-- Occasionally propose an alliance to a peaceful neighboring Human player!
			if not engine.config.disableAlliances and math.random() < 0.04 then
				for nid, _ in pairs(neighborCounts) do
					local other = engine.playersBySmallId[nid]
					if
						other ~= nil
						and other.alive
						and other.playerType == "Human"
						and not engine:AreFriendly(p, other)
						and (p.relations[nid] or 0) > -20
					then
						engine:SendAllianceRequest(p, other)
						break
					end
				end
			end
		end

		-- Priority 2: Attack weakest / hostile / Traitor neighbor if army reserve healthy
		local reserveThreshold = if p.playerType == "Bot" then 0.58 else p.aiTriggerRatio
		if troopFrac >= reserveThreshold then
			local bestTarget: any = nil
			local bestScore = -1e9
			for nid, _ in pairs(neighborCounts) do
				local other = engine.playersBySmallId[nid]
				if other ~= nil and other.alive and not engine:AreFriendly(p, other) then
					local rel = p.relations[nid] or 0
					local score = (p.troops / math.max(500, other.troops)) * 50 - rel * 0.6
					if other.isTraitor then
						score += 120 -- Dogpile traitors just like NationExecution!
					end
					if other.playerType == "Bot" then
						score += 35
					end
					if score > bestScore then
						bestScore = score
						bestTarget = other
					end
				end
			end

			if bestTarget ~= nil and (bestScore > 28 or troopFrac > 0.86) then
				local sendFrac = if p.playerType == "Bot" then 0.20 else 0.30
				engine:StartLandAttack(p, bestTarget.smallId, math.floor(p.troops * sendFrac))
				if p.playerType == "Nation" and bestTarget.isTraitor and math.random() < 0.25 then
					engine:SetEmoji(p, "😡")
				end
				continue
			end

			-- Priority 3: Naval Amphibious Landing across water channels when landlocked!
			if p.playerType == "Nation" and #shoreTiles > 0 and troopFrac > 0.72 and math.random() < 0.35 then
				local srcShore = shoreTiles[math.random(1, #shoreTiles)]
				local sx = srcShore % map.width
				local sy = math.floor(srcShore / map.width)
				for _ = 1, 14 do
					local tx = math.clamp(sx + math.random(-75, 75), 0, map.width - 1)
					local ty = math.clamp(sy + math.random(-75, 75), 0, map.height - 1)
					local tref = ty * map.width + tx
					if MapCodec.IsShoreLand(map, tref) then
						local toid = MapCodec.GetOwner(map, tref)
						local targetOwner = if toid > 0 then engine.playersBySmallId[toid] else nil
						if toid ~= p.smallId and (targetOwner == nil or not engine:AreFriendly(p, targetOwner)) then
							engine:LaunchBoatAttack(p, tref, math.floor(p.troops * 0.25))
							break
						end
					end
				end
			end
		end
	end
end

return AiBrain
