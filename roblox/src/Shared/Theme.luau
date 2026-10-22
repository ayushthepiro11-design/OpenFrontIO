--!native
--!strict
-- Exact `--!native` port of OpenFront default-theme.json, colorblind-theme.json & ColorUtils.ts

local Theme = {}

export type RGB = { number }

function Theme.HexToRGB(hex: string): (number, number, number)
	local clean = string.gsub(hex, "^#", "")
	local r = tonumber(string.sub(clean, 1, 2), 16) or 128
	local g = tonumber(string.sub(clean, 3, 4), 16) or 128
	local b = tonumber(string.sub(clean, 5, 6), 16) or 128
	return r, g, b
end

function Theme.HexToColor3(hex: string): Color3
	local r, g, b = Theme.HexToRGB(hex)
	return Color3.fromRGB(r, g, b)
end

function Theme.PackRGBA(r: number, g: number, b: number, a: number?): number
	local alpha = if a ~= nil then a else 255
	return bit32.bor(
		math.clamp(math.floor(r + 0.5), 0, 255),
		bit32.lshift(math.clamp(math.floor(g + 0.5), 0, 255), 8),
		bit32.lshift(math.clamp(math.floor(b + 0.5), 0, 255), 16),
		bit32.lshift(math.clamp(math.floor(alpha + 0.5), 0, 255), 24)
	)
end

function Theme.UnpackRGB(u32: number): (number, number, number)
	return bit32.band(u32, 0xFF),
		bit32.band(bit32.rshift(u32, 8), 0xFF),
		bit32.band(bit32.rshift(u32, 16), 0xFF)
end

Theme.TeamColors = {
	Red = "#eb3333",
	Blue = "#2962ff",
	Teal = "#06b6d4",
	Purple = "#9234ea",
	Yellow = "#e7b008",
	Orange = "#ff7f0e",
	Green = "#41be52",
	Bot = "#d1cdc7",
	Humans = "#2962ff",
	Nations = "#eb3333",
}

Theme.TeamOrder = { "Blue", "Red", "Green", "Yellow", "Purple", "Teal", "Orange" }

Theme.HumanColors = {
	"#06b6d4", "#ef4444", "#22c55e", "#f59e0b", "#8b5cf6", "#ec4899", "#3b82f6",
	"#10b981", "#f97316", "#a855f7", "#14b8a6", "#eab308", "#f43f5e", "#0ea5e9",
	"#84cc16", "#6366f1", "#d946ef", "#fb7185", "#2dd4bf", "#fbbf24", "#60a5fa",
	"#4ade80", "#c084fc", "#38bdf8", "#f87171", "#34d399", "#facc15", "#e879f9",
}

Theme.NationColors = {
	"#e05656", "#3b82f6", "#22c55e", "#f59e0b", "#a855f7", "#14b8a6", "#ec4899", "#84cc16",
	"#f97316", "#06b6d4", "#6366f1", "#10b981", "#eab308", "#f43f5e", "#0ea5e9", "#d946ef",
	"#ef4444", "#2dd4bf", "#8b5cf6", "#4ade80", "#fb923c", "#38bdf8", "#fb7185", "#a3e635",
	"#c084fc", "#34d399", "#fbbf24", "#60a5fa", "#f472b6", "#2563eb", "#16a34a", "#d97706",
	"#9333ea", "#0d9488", "#db2777", "#65a30d", "#ea580c", "#0891b2", "#4f46e5", "#059669",
	"#ca8a04", "#e11d48", "#0284c7", "#c026d3", "#dc2626", "#0f766e", "#7c3aed", "#15803d",
}

-- 40 distinct minor-bot hues (zero duplicate hex entries!)
Theme.BotColors = {
	"#60a5fa", "#f87171", "#4ade80", "#fbbf24", "#c084fc", "#2dd4bf", "#f472b6", "#a3e635",
	"#fb923c", "#38bdf8", "#818cf8", "#34d399", "#facc15", "#fb7185", "#67e8f9", "#e879f9",
	"#5eead4", "#fda4af", "#93c5fd", "#86efac", "#fde047", "#d8b4fe", "#fdba74", "#7dd3fc",
	"#a5b4fc", "#6ee7b7", "#fcd34d", "#f9a8d4", "#22d3ee", "#bef264", "#fca5a5", "#c4b5fd",
	"#0ea5e9", "#10b981", "#f97316", "#ec4899", "#3b82f6", "#eab308", "#14b8a6", "#a855f7",
}

Theme.ColorblindColors = {
	"#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00", "#F0E442", "#7F7F7F",
}

Theme.Patterns = {
	{ id = "none", name = "Solid Classic" },
	{ id = "stripes", name = "Diagonal Stripes" },
	{ id = "checkers", name = "Royal Checkers" },
	{ id = "grid", name = "Imperial Grid" },
	{ id = "dots", name = "Tactical Dots" },
}

function Theme.SamplePatternSecondary(patternId: string, x: number, y: number): boolean
	if patternId == "none" or patternId == "" then
		return false
	elseif patternId == "stripes" then
		return ((x + y) % 8) < 3
	elseif patternId == "checkers" then
		return (bit32.band(bit32.rshift(x, 2), 1) ~= bit32.band(bit32.rshift(y, 2), 1))
	elseif patternId == "grid" then
		return (x % 8 == 0) or (y % 8 == 0)
	elseif patternId == "dots" then
		return (x % 6 < 2) and (y % 6 < 2)
	end
	return false
end

function Theme.TerrainByteToRGB(tb: number): (number, number, number)
	local isLand = bit32.band(tb, 0x80) ~= 0
	local isShoreline = bit32.band(tb, 0x40) ~= 0
	local magnitude = bit32.band(tb, 0x1F)

	if isLand and magnitude == 31 then
		return 60, 60, 60
	elseif isLand and isShoreline then
		return 204, 203, 158
	elseif isLand then
		if magnitude < 10 then
			return 190, 220 - 2 * magnitude, 138
		elseif magnitude < 20 then
			local m = magnitude - 10
			return math.min(255, 200 + 2 * m), math.min(255, 183 + 2 * m), math.min(255, 138 + 2 * m)
		else
			local m = math.floor(magnitude / 2)
			return math.min(255, 230 + m), math.min(255, 230 + m), math.min(255, 230 + m)
		end
	elseif isShoreline then
		return 126, 170, 203
	else
		local m = math.min(magnitude, 10)
		return math.max(0, 71 - m), math.max(0, 133 - m), math.max(0, 181 - m)
	end
end

Theme.TerrainU32LUT = table.create(256, 0)
Theme.TerrainColor3LUT = table.create(256, Color3.new())
for tb = 0, 255 do
	local r, g, b = Theme.TerrainByteToRGB(tb)
	Theme.TerrainU32LUT[tb + 1] = Theme.PackRGBA(r, g, b, 255)
	Theme.TerrainColor3LUT[tb + 1] = Color3.fromRGB(r, g, b)
end

function Theme.BlendTerritoryOverTerrain(
	tr: number,
	tg: number,
	tb: number,
	pr: number,
	pg: number,
	pb: number,
	defended: boolean
): (number, number, number)
	local sr, sg, sb = pr, pg, pb
	if defended then
		sr *= 0.88
		sg *= 0.88
		sb *= 0.88
	end
	local alpha = 0.72
	local inv = 1.0 - alpha
	return math.floor(tr * inv + sr * alpha + 0.5),
		math.floor(tg * inv + sg * alpha + 0.5),
		math.floor(tb * inv + sb * alpha + 0.5)
end

function Theme.BorderRGB(pr: number, pg: number, pb: number): (number, number, number)
	return math.floor(pr * 0.62 + 0.5), math.floor(pg * 0.62 + 0.5), math.floor(pb * 0.62 + 0.5)
end

Theme.FalloutBrightU32 = Theme.PackRGBA(38, 205, 42, 255)
Theme.FalloutDarkU32 = Theme.PackRGBA(24, 138, 30, 255)
Theme.FalloutColor3 = Color3.fromRGB(34, 185, 38)
Theme.RailroadU32 = Theme.PackRGBA(68, 52, 38, 255)
Theme.RailroadColor3 = Color3.fromRGB(68, 52, 38)
Theme.SpawnHighlightU32 = Theme.PackRGBA(255, 213, 79, 255)

Theme.Affiliation = {
	SelfFill = Color3.fromRGB(34, 197, 94),
	SelfU32 = Theme.PackRGBA(34, 197, 94, 255),
	AllyFill = Color3.fromRGB(250, 204, 21),
	AllyU32 = Theme.PackRGBA(250, 204, 21, 255),
	NeutralFill = Color3.fromRGB(148, 163, 184),
	NeutralU32 = Theme.PackRGBA(148, 163, 184, 255),
	EnemyFill = Color3.fromRGB(239, 68, 68),
	EnemyU32 = Theme.PackRGBA(239, 68, 68, 255),
}

Theme.UI = {
	BgDark = Color3.fromRGB(15, 23, 42),
	BgPanel = Color3.fromRGB(24, 32, 48),
	BgCard = Color3.fromRGB(30, 41, 59),
	BgHover = Color3.fromRGB(51, 65, 85),
	Border = Color3.fromRGB(71, 85, 105),
	AccentBlue = Color3.fromRGB(37, 99, 235),
	AccentGreen = Color3.fromRGB(22, 163, 74),
	AccentGold = Color3.fromRGB(245, 158, 11),
	AccentRed = Color3.fromRGB(220, 38, 38),
	AccentPurple = Color3.fromRGB(124, 58, 237),
	TextPrimary = Color3.fromRGB(248, 250, 252),
	TextMuted = Color3.fromRGB(148, 163, 184),
}

return Theme
