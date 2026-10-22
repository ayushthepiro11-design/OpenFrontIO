--!native
--!strict
-- NaN/Inf-hardened number, troop, gold, timer formatting + 65+ authentic country/Shinobi vector flags

local Format = {}

local function safeNum(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

function Format.Number(rawN: number): string
	local n = safeNum(rawN)
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
	return Format.Number(math.max(0, math.floor(safeNum(n))))
end

function Format.Gold(n: number): string
	return Format.Number(math.max(0, math.floor(safeNum(n))))
end

function Format.Percent(fraction: number): string
	local f = safeNum(fraction)
	local pct = math.clamp(f * 100, 0, 100)
	if pct >= 10 then
		return string.format("%.1f%%", pct)
	else
		return string.format("%.2f%%", pct)
	end
end

function Format.Timer(totalSeconds: number): string
	local secs = math.max(0, math.floor(safeNum(totalSeconds)))
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

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
	{ code = "tr", label = "Turkiye", kind = "jp", c1 = "#E30A17", c2 = "#FFFFFF", c3 = "#FFFFFF", symbol = "☪" },
	{ code = "kr", label = "South Korea", kind = "jp", c1 = "#FFFFFF", c2 = "#CD2E3A", c3 = "#0047A0" },
	{ code = "mx", label = "Mexico", kind = "v3", c1 = "#006847", c2 = "#FFFFFF", c3 = "#CE1126" },
	{ code = "ar", label = "Argentina", kind = "h3", c1 = "#74ACDF", c2 = "#FFFFFF", c3 = "#74ACDF", symbol = "☀" },
	{ code = "eg", label = "Egypt", kind = "h3", c1 = "#CE1126", c2 = "#FFFFFF", c3 = "#111111" },
	{ code = "ng", label = "Nigeria", kind = "v3", c1 = "#008751", c2 = "#FFFFFF", c3 = "#008751" },
	{ code = "za", label = "South Africa", kind = "h3", c1 = "#E03C31", c2 = "#007749", c3 = "#001489" },
	{ code = "se", label = "Sweden", kind = "cross", c1 = "#006AA7", c2 = "#FECC02", c3 = "#FECC02" },
	{ code = "no", label = "Norway", kind = "cross", c1 = "#BA0C2F", c2 = "#00205B", c3 = "#FFFFFF" },
	{ code = "fi", label = "Finland", kind = "cross", c1 = "#FFFFFF", c2 = "#003580", c3 = "#003580" },
	{ code = "dk", label = "Denmark", kind = "cross", c1 = "#C8102E", c2 = "#FFFFFF", c3 = "#FFFFFF" },
	{ code = "is", label = "Iceland", kind = "cross", c1 = "#02529C", c2 = "#DC1E35", c3 = "#FFFFFF" },
	{ code = "nl", label = "Netherlands", kind = "h3", c1 = "#AE1C28", c2 = "#FFFFFF", c3 = "#21468B" },
	{ code = "be", label = "Belgium", kind = "v3", c1 = "#111111", c2 = "#FDDA24", c3 = "#EF3340" },
	{ code = "ch", label = "Switzerland", kind = "cross", c1 = "#FF0000", c2 = "#FFFFFF", c3 = "#FFFFFF" },
	{ code = "at", label = "Austria", kind = "h3", c1 = "#ED2939", c2 = "#FFFFFF", c3 = "#ED2939" },
	{ code = "pt", label = "Portugal", kind = "v3", c1 = "#006600", c2 = "#FF0000", c3 = "#FF0000" },
	{ code = "ie", label = "Ireland", kind = "v3", c1 = "#169B62", c2 = "#FFFFFF", c3 = "#FF883E" },
	{ code = "gr", label = "Greece", kind = "cross", c1 = "#0D5EAF", c2 = "#FFFFFF", c3 = "#FFFFFF" },
	{ code = "ro", label = "Romania", kind = "v3", c1 = "#002B7F", c2 = "#FCD116", c3 = "#CE1126" },
	{ code = "hu", label = "Hungary", kind = "h3", c1 = "#CE2939", c2 = "#FFFFFF", c3 = "#477050" },
	{ code = "cz", label = "Czechia", kind = "h2", c1 = "#FFFFFF", c2 = "#D7141A", c3 = "#11457E" },
	{ code = "lv", label = "Latvia", kind = "h3", c1 = "#9E3039", c2 = "#FFFFFF", c3 = "#9E3039" },
	{ code = "lt", label = "Lithuania", kind = "h3", c1 = "#FDB913", c2 = "#006A44", c3 = "#C1272D" },
	{ code = "ee", label = "Estonia", kind = "h3", c1 = "#0072CE", c2 = "#111111", c3 = "#FFFFFF" },
	{ code = "id", label = "Indonesia", kind = "h2", c1 = "#FF0000", c2 = "#FFFFFF", c3 = "#FFFFFF" },
	{ code = "th", label = "Thailand", kind = "h3", c1 = "#2D2A4A", c2 = "#FFFFFF", c3 = "#A51931" },
	{ code = "vn", label = "Vietnam", kind = "jp", c1 = "#DA251D", c2 = "#FFFF00", c3 = "#FFFF00", symbol = "★" },
	{ code = "ph", label = "Philippines", kind = "h2", c1 = "#0038A8", c2 = "#CE1126", c3 = "#FCD116" },
	{ code = "pk", label = "Pakistan", kind = "v3", c1 = "#FFFFFF", c2 = "#01411C", c3 = "#01411C", symbol = "☪" },
	{ code = "bd", label = "Bangladesh", kind = "jp", c1 = "#006A4E", c2 = "#F42A41", c3 = "#F42A41" },
	{ code = "sa", label = "Saudi Arabia", kind = "h2", c1 = "#006C35", c2 = "#006C35", c3 = "#FFFFFF", symbol = "⚔" },
	{ code = "ir", label = "Iran", kind = "h3", c1 = "#239F40", c2 = "#FFFFFF", c3 = "#DA0000" },
	{ code = "iq", label = "Iraq", kind = "h3", c1 = "#CE1126", c2 = "#FFFFFF", c3 = "#111111" },
	{ code = "om", label = "Oman", kind = "h3", c1 = "#FFFFFF", c2 = "#DB161B", c3 = "#008000" },
	{ code = "ma", label = "Morocco", kind = "jp", c1 = "#C1272D", c2 = "#006233", c3 = "#006233", symbol = "★" },
	{ code = "dz", label = "Algeria", kind = "v3", c1 = "#006233", c2 = "#FFFFFF", c3 = "#D21034" },
	{ code = "sd", label = "Sudan", kind = "h3", c1 = "#D21034", c2 = "#FFFFFF", c3 = "#111111" },
	{ code = "ke", label = "Kenya", kind = "h3", c1 = "#111111", c2 = "#BB0000", c3 = "#006600" },
	{ code = "et", label = "Ethiopia", kind = "h3", c1 = "#078930", c2 = "#FCDD09", c3 = "#DA121A" },
	{ code = "co", label = "Colombia", kind = "h3", c1 = "#FCD116", c2 = "#003893", c3 = "#CE1126" },
	{ code = "pe", label = "Peru", kind = "v3", c1 = "#D91023", c2 = "#FFFFFF", c3 = "#D91023" },
	{ code = "cl", label = "Chile", kind = "h2", c1 = "#FFFFFF", c2 = "#D52B1E", c3 = "#0039A6" },
	{ code = "nz", label = "New Zealand", kind = "us", c1 = "#00247D", c2 = "#00247D", c3 = "#CC142B", symbol = "✦" },
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
		local c2 = "#FFFFFF"
		local c3 = AUTO_PALETTE[((h + 3) % #AUTO_PALETTE) + 1]
		return {
			code = key,
			label = string.upper(key),
			kind = if h % 2 == 0 then "h3" else "v3",
			c1 = c1,
			c2 = c2,
			c3 = c3,
		}
	end
	return FLAG_SPECS[1]
end

return Format
