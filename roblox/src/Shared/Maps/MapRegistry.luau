--!strict
local MapsFolder = script.Parent

export type NationSpawn = {
	name: string,
	flag: string,
	x: number,
	y: number,
	strength: number,
}

export type RawMapDefinition = {
	id: string,
	folder: string,
	name: string,
	category: string,
	wrapX: boolean?,
	width: number,
	height: number,
	numLandTiles: number,
	previewW: number,
	previewH: number,
	preview: string,
	nations: { NationSpawn },
	deflateShards: { string }?,
	rleBase64: string?,
}

local MAP_MODULES: { RawMapDefinition } = {
	require(MapsFolder:WaitForChild("World", 10)) :: any,
	require(MapsFolder:WaitForChild("GiantWorldMap", 10)) :: any,
	require(MapsFolder:WaitForChild("ShinobiWorld", 10)) :: any,
	require(MapsFolder:WaitForChild("Europe", 10)) :: any,
	require(MapsFolder:WaitForChild("NorthAmerica", 10)) :: any,
	require(MapsFolder:WaitForChild("Asia", 10)) :: any,
	require(MapsFolder:WaitForChild("Africa", 10)) :: any,
	require(MapsFolder:WaitForChild("SouthAmerica", 10)) :: any,
	require(MapsFolder:WaitForChild("Australia", 10)) :: any,
	require(MapsFolder:WaitForChild("Britannia", 10)) :: any,
	require(MapsFolder:WaitForChild("BlackSea", 10)) :: any,
	require(MapsFolder:WaitForChild("IndianSubcontinent", 10)) :: any,
	require(MapsFolder:WaitForChild("UnitedStates", 10)) :: any,
	require(MapsFolder:WaitForChild("Japan", 10)) :: any,
	require(MapsFolder:WaitForChild("China", 10)) :: any,
	require(MapsFolder:WaitForChild("Russia", 10)) :: any,
	require(MapsFolder:WaitForChild("France", 10)) :: any,
	require(MapsFolder:WaitForChild("Germany", 10)) :: any,
	require(MapsFolder:WaitForChild("Italia", 10)) :: any,
	require(MapsFolder:WaitForChild("MareNostrum", 10)) :: any,
	require(MapsFolder:WaitForChild("Caribbean", 10)) :: any,
	require(MapsFolder:WaitForChild("Mars", 10)) :: any,
	require(MapsFolder:WaitForChild("Pangaea", 10)) :: any,
	require(MapsFolder:WaitForChild("StraitOfGibraltar", 10)) :: any,
}

local BY_ID: { [string]: RawMapDefinition } = {}
for _, def in ipairs(MAP_MODULES) do
	BY_ID[def.id] = def
end

local MapRegistry = {}
MapRegistry.List = MAP_MODULES
MapRegistry.ById = BY_ID

function MapRegistry.Get(mapId: string): RawMapDefinition
	return BY_ID[mapId] or MAP_MODULES[1]
end

return MapRegistry
