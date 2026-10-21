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
	width: number,
	height: number,
	numLandTiles: number,
	previewW: number,
	previewH: number,
	preview: string,
	nations: { NationSpawn },
	rleBase64: string,
}

local MAP_MODULES: { RawMapDefinition } = {
	require(MapsFolder:WaitForChild("World")) :: any,
	require(MapsFolder:WaitForChild("ShinobiWorld")) :: any,
	require(MapsFolder:WaitForChild("Europe")) :: any,
	require(MapsFolder:WaitForChild("NorthAmerica")) :: any,
	require(MapsFolder:WaitForChild("Asia")) :: any,
	require(MapsFolder:WaitForChild("Africa")) :: any,
	require(MapsFolder:WaitForChild("SouthAmerica")) :: any,
	require(MapsFolder:WaitForChild("Australia")) :: any,
	require(MapsFolder:WaitForChild("Britannia")) :: any,
	require(MapsFolder:WaitForChild("BlackSea")) :: any,
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
