--!strict
-- Number, troop, gold, timer formatting + vector flag recipes matching OpenFront Format.ts

local Format = {}

function Format.Number(n: number): string
	local absVal = math.abs(n)
	local sign = if n < 0 then "-" else ""
	if absVal >= 1_000_000_000 then
		return string.format("%s%.2fB", sign, absVal / 1_000_000_000)
	elseif absVal >= 10_000_000 then
		return string.format("%s%.1fM", sign, absVal / 1_000_000)
	elseif absVal >= 1_000_000 then
		return string.format("%s%.2fM", sign, absVal / 1_000_000)
	elseif absVal >= 100_000 then
		return string.format("%s%.0fK", sign, absVal / 1_000)
	elseif absVal >= 1_000 then
		return string.format("%s%.1fK", sign, absVal / 1_000)
	else
		return string.format("%s%d", sign, math.floor(absVal + 0.5))
	end
end

function Format.Troops(n: number): string
	return Format.Number(math.max(0, math.floor(n)))
end

function Format.Gold(n: number): string
	return Format.Number(math.max(0, math.floor(n)))
end

function Format.Percent(fraction: number): string
	local pct = math.clamp(fraction * 100, 0, 100)
	if pct >= 10 then
		return string.format("%.1f%%", pct)
	else
		return string.format("%.2f%%", pct)
	end
end

function Format.Timer(totalSeconds: number): string
	local secs = math.max(0, math.floor(totalSeconds))
	local m = math.floor(secs / 60)
	local s = secs % 60
	return string.format("%02d:%02d", m, s)
end

-- Vector flag definitions so every country & Shinobi village renders crisply on ALL platforms
-- Layout kinds:
--   "h3" (3 horizontal bands), "v3" (3 vertical bands), "h2" (2 horizontal bands),
--   "jp" (center circle), "cross" (Nordic/Swiss cross), "us" (canton + stripes), "shinobi" (village emblem)
export type FlagSpec = {
	code: string,
	label: string,
	kind: string,
	c1: string,
	c2: string,
	c3: string,
	symbol: string?,
}

local FLAG_SPECS: { FlagSpec } = {
	{ code = "in", label = "India", kind = "h3", c1 = "#FF9933", c2 = "#FFFFFF", c3 = "#138808", symbol = "☸" },
	{ code = "us", label = "United States", kind = "us", c1 = "#B22234", c2 = "#FFFFFF", c3 = "#3C3B6E", symbol = "★" },
	{ code = "gb", label = "United Kingdom", kind = "cross", c1 = "#012169", c2 = "#C8102E", c3 = "#FFFFFF" },
	{ code = "de", label = "Germany", kind = "h3", c1 = "#111111", c2 = "#DD0000", c3 = "#FFCE00" },
	{ code = "fr", label = "France", kind = "v3", c1 = "#002395", c2 = "#FFFFFF", c3 = "#ED2939" },
	{ code = "jp", label = "Japan", kind = "jp", c1 = "#FFFFFF", c2 = "#BC002D", c3 = "#BC002D" },
	{ code = "cn", label = "China", kind = "us", c1 = "#DE2910", c2 = "#DE2910", c3 = "#DE2910", symbol = "★" },
	{ code = "ru", label = "Russia", kind = "h3", c1 = "#FFFFFF", c2 = "#0039A6", c3 = "#D52B1E" },
	{ code = "br", label = "Brazil", kind = "jp", c1 = "#009C3B", c2 = "#FFDF00", c3 = "#002776" },
	{ code = "ca", label = "Canada", kind = "v3", c1 = "#FF0000", c2 = "#FFFFFF", c3 = "#FF0000", symbol = "🍁" },
	{ code = "au", label = "Australia", kind = "us", c1 = "#00008B", c2 = "#00008B", c3 = "#CC0001", symbol = "✦" },
	{ code = "it", label = "Italy", kind = "v3", c1 = "#009246", c2 = "#FFFFFF", c3 = "#CE2B37" },
	{ code = "es", label = "Spain", kind = "h3", c1 = "#AA151B", c2 = "#F1BF00", c3 = "#AA151B" },
	{ code = "ua", label = "Ukraine", kind = "h2", c1 = "#005BBB", c2 = "#FFD500", c3 = "#FFD500" },
	{ code = "pl", label = "Poland", kind = "h2", c1 = "#FFFFFF", c2 = "#DC143C", c3 = "#DC143C" },
	{ code = "tr", label = "Turkey", kind = "jp", c1 = "#E30A17", c2 = "#FFFFFF", c3 = "#FFFFFF", symbol = "☪" },
	{ code = "kr", label = "South Korea", kind = "jp", c1 = "#FFFFFF", c2 = "#CD2E3A", c3 = "#0047A0" },
	{ code = "mx", label = "Mexico", kind = "v3", c1 = "#006847", c2 = "#FFFFFF", c3 = "#CE1126" },
	{ code = "ar", label = "Argentina", kind = "h3", c1 = "#74ACDF", c2 = "#FFFFFF", c3 = "#74ACDF", symbol = "☀" },
	{ code = "eg", label = "Egypt", kind = "h3", c1 = "#CE1126", c2 = "#FFFFFF", c3 = "#111111" },
	{ code = "ng", label = "Nigeria", kind = "v3", c1 = "#008751", c2 = "#FFFFFF", c3 = "#008751" },
	{ code = "za", label = "South Africa", kind = "h3", c1 = "#E03C31", c2 = "#007749", c3 = "#001489" },
	{ code = "se", label = "Sweden", kind = "cross", c1 = "#006AA7", c2 = "#FECC02", c3 = "#FECC02" },
	{ code = "no", label = "Norway", kind = "cross", c1 = "#BA0C2F", c2 = "#00205B", c3 = "#FFFFFF" },
	{ code = "fi", label = "Finland", kind = "cross", c1 = "#FFFFFF", c2 = "#003580", c3 = "#003580" },
	{ code = "nl", label = "Netherlands", kind = "h3", c1 = "#AE1C28", c2 = "#FFFFFF", c3 = "#21468B" },
	{ code = "gr", label = "Greece", kind = "cross", c1 = "#0D5EAF", c2 = "#FFFFFF", c3 = "#FFFFFF" },
	{ code = "id", label = "Indonesia", kind = "h2", c1 = "#FF0000", c2 = "#FFFFFF", c3 = "#FFFFFF" },
	{ code = "pk", label = "Pakistan", kind = "v3", c1 = "#FFFFFF", c2 = "#01411C", c3 = "#01411C", symbol = "☪" },
	{ code = "sa", label = "Saudi Arabia", kind = "h2", c1 = "#006C35", c2 = "#006C35", c3 = "#FFFFFF", symbol = "⚔" },
	-- Custom Shinobi World & Special Emblems!
	{ code = "leaf", label = "Land of Fire (Konoha)", kind = "shinobi", c1 = "#DC2626", c2 = "#FDE047", c3 = "#1E293B", symbol = "🍃" },
	{ code = "sand", label = "Land of Wind (Suna)", kind = "shinobi", c1 = "#D97706", c2 = "#FEF3C7", c3 = "#1E293B", symbol = "⏳" },
	{ code = "mist", label = "Land of Water (Kiri)", kind = "shinobi", c1 = "#0284C7", c2 = "#E0F2FE", c3 = "#0F172A", symbol = "🌊" },
	{ code = "cloud", label = "Land of Lightning (Kumo)", kind = "shinobi", c1 = "#EAB308", c2 = "#FFFFFF", c3 = "#1E1B4B", symbol = "⚡" },
	{ code = "stone", label = "Land of Earth (Iwa)", kind = "shinobi", c1 = "#78350F", c2 = "#FBBF24", c3 = "#1C1917", symbol = "🪨" },
	{ code = "un", label = "United Nations", kind = "jp", c1 = "#38BDF8", c2 = "#FFFFFF", c3 = "#FFFFFF", symbol = "🌐" },
}

local FLAG_MAP: { [string]: FlagSpec } = {}
for _, spec in ipairs(FLAG_SPECS) do
	FLAG_MAP[spec.code] = spec
end

Format.Flags = FLAG_SPECS

local AUTO_PALETTE = {
	"#EF4444", "#3B82F6", "#10B981", "#F59E0B", "#8B5CF6", "#EC4899", "#06B6D4", "#84CC16",
}

function Format.GetFlagSpec(code: string?): FlagSpec
	local key = string.lower(code or "")
	if FLAG_MAP[key] then
		return FLAG_MAP[key]
	end
	if #key > 0 then
		local h = string.byte(key, 1) + (if #key >= 2 then string.byte(key, 2) * 7 else 0)
		local c1 = AUTO_PALETTE[(h % #AUTO_PALETTE) + 1]
		local c3 = AUTO_PALETTE[((h + 3) % #AUTO_PALETTE) + 1]
		return {
			code = key,
			label = string.upper(key),
			kind = if h % 2 == 0 then "h3" else "v3",
			c1 = c1,
			c2 = "#FFFFFF",
			c3 = c3,
		}
	end
	return {
		code = "un",
		label = "Independent",
		kind = "h2",
		c1 = "#334155",
		c2 = "#64748B",
		c3 = "#94A3B8",
	}
end

return Format
