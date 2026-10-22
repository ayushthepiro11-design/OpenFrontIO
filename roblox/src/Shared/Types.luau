--!strict
-- Complete type definitions for OpenFront Roblox 1:1 Port (Full-Scale Edition)

export type PlayerType = "Human" | "Nation" | "Bot"
export type Difficulty = "Easy" | "Medium" | "Hard" | "Impossible"
export type GameMode = "FFA" | "Teams"
export type DoomsdaySpeed = "slow" | "normal" | "fast" | "veryfast"

export type UnitType =
	"City"
	| "Port"
	| "Factory"
	| "DefensePost"
	| "MissileSilo"
	| "SAMLauncher"
	| "Warship"
	| "TransportShip"
	| "TradeShip"
	| "Train"
	| "AtomBomb"
	| "HydrogenBomb"
	| "MIRV"
	| "MIRVWarhead"
	| "SAMMissile"
	| "Shell"

export type TerrainKind = "Water" | "Plains" | "Highland" | "Mountain" | "Impassable"

export type GameConfig = {
	mapId: string,
	mode: GameMode,
	numTeams: number, -- 0 for FFA, 2/3/4/5/6/7 for Teams, -1 for Humans vs Nations
	difficulty: Difficulty,
	bots: number,
	spawnNations: boolean,
	instantBuild: boolean,
	infiniteGold: boolean,
	infiniteTroops: boolean,
	startingGold: number,
	goldMultiplier: number,
	disableAlliances: boolean,
	allianceDurationMinutes: number,
	donateGold: boolean,
	donateTroops: boolean,
	randomSpawn: boolean,
	waterNukes: boolean,
	doomsdayEnabled: boolean,
	doomsdaySpeed: DoomsdaySpeed,
	overtimeEnabled: boolean,
	overtimeStartMinutes: number,
	singleplayer: boolean,
	seed: number?,
}

export type PlayerProfileSave = {
	xp: number,
	level: number,
	prestige: number,
	wins: number,
	gamesPlayed: number,
	tilesConquered: number,
	nukesLaunched: number,
	goldEarnedTotal: number,
	flag: string,
	colorIndex: number,
	patternId: string,
	defaultAttackRatio: number,
	colorblindMode: boolean,
	preferScanline2D: boolean,
	showNames: boolean,
	soundVolume: number,
}

export type AttackSummary = {
	id: number,
	attackerSmallId: number,
	targetSmallId: number, -- 0 = Terra Nullius
	troops: number,
	retreating: boolean,
	isBoat: boolean,
}

export type UnitSummary = {
	id: number,
	unitType: UnitType,
	ownerSmallId: number,
	x: number,
	y: number,
	srcX: number,
	srcY: number,
	dstX: number,
	dstY: number,
	patrolX: number?,
	patrolY: number?,
	level: number,
	hp: number,
	maxHp: number,
	veterancy: number,
	underConstruction: boolean,
	constructionProgress: number,
	onCooldown: boolean?,
	cooldownProgress: number?,
	troops: number,
	progress: number, -- 0..1 flight progress for parabolic projectiles
}

export type PlayerSummary = {
	smallId: number,
	userId: number, -- >0 for Roblox Player, <=0 for AI Nation / Bot
	playerType: PlayerType,
	name: string,
	flag: string,
	colorHex: string,
	patternId: string,
	team: string?,
	alive: boolean,
	hasSpawned: boolean,
	spawnX: number,
	spawnY: number,
	labelX: number,
	labelY: number,
	labelSpan: number,
	tilesOwned: number,
	troops: number,
	maxTroops: number,
	troopRatePerSec: number,
	attackingTroops: number,
	gold: number,
	goldEarned: number?,
	isTraitor: boolean,
	traitorTicksLeft: number?,
	isDoomed: boolean,
	allies: { number },
	embargoes: { number },
	emoji: string?,
	emojiTicksLeft: number?,
	targetedBy: { number },
	nukesSent: number?,
	unitCounts: { [string]: number }?,
}

export type ActionableAlert = {
	id: number,
	kind: "AllianceRequest" | "AllianceExpiring" | "NukeInbound",
	fromSmallId: number,
	fromName: string,
	unitType: string?,
	targetX: number?,
	targetY: number?,
	expiresTick: number,
}

export type EventFeedItem = {
	id: number,
	kind: "info" | "conquest" | "alliance" | "betrayal" | "nuke" | "trade" | "donate" | "chat",
	text: string,
	colorHex: string,
	targetX: number?,
	targetY: number?,
	tick: number,
}

export type FloatingPopup = {
	x: number,
	y: number,
	text: string,
	colorHex: string,
}

return {}
