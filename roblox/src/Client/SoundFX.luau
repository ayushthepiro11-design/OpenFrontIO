--!native
--!strict
-- 4-Voice Polyphonic `rbxasset://sounds/` Audio Synthesizer (`SoundFX.luau`)
-- Simultaneous explosions, builds, sirens, and clicks play overlapping without cutting each other off!

local SoundService = game:GetService("SoundService")

local SoundFX = {}
SoundFX.Volume = 0.7

local VOICE_POOL_SIZE = 4

local CUES: { [string]: { url: string, pitch: number, vol: number } } = {
	click = { url = "rbxasset://sounds/button.wav", pitch = 1.15, vol = 0.35 },
	hover = { url = "rbxasset://sounds/switch.wav", pitch = 1.6, vol = 0.15 },
	attack = { url = "rbxasset://sounds/swordslash.wav", pitch = 0.95, vol = 0.45 },
	boat = { url = "rbxasset://sounds/switch.wav", pitch = 0.72, vol = 0.45 },
	build = { url = "rbxasset://sounds/collide.wav", pitch = 1.15, vol = 0.50 },
	alliance = { url = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.25, vol = 0.50 },
	alert = { url = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.78, vol = 0.75 },
	launch = { url = "rbxasset://sounds/Rocket shot.wav", pitch = 0.90, vol = 0.65 },
	boom = { url = "rbxasset://sounds/Rocket shot.wav", pitch = 0.52, vol = 0.85 },
	victory = { url = "rbxasset://sounds/victory.wav", pitch = 1.0, vol = 0.75 },
}

local voicePools: { [string]: { Sound } } = {}
local voiceCursor: { [string]: number } = {}

function SoundFX.Play(cueName: string)
	if SoundFX.Volume <= 0.01 then
		return
	end
	local spec = CUES[cueName]
	if spec == nil then
		return
	end
	local pool = voicePools[cueName]
	if pool == nil then
		pool = {}
		for i = 1, VOICE_POOL_SIZE do
			local ok, created = pcall(function()
				local snd = Instance.new("Sound")
				snd.Name = string.format("OF_%s_%d", cueName, i)
				snd.SoundId = spec.url
				snd.Parent = SoundService
				return snd
			end)
			if ok and created ~= nil then
				table.insert(pool, created)
			end
		end
		voicePools[cueName] = pool
		voiceCursor[cueName] = 0
	end
	if #pool == 0 then
		return
	end
	local idx = ((voiceCursor[cueName] or 0) % #pool) + 1
	voiceCursor[cueName] = idx
	local s = pool[idx]
	s.PlaybackSpeed = spec.pitch * (0.98 + (idx - 1) * 0.015)
	s.Volume = math.clamp(spec.vol * SoundFX.Volume, 0, 1)
	s.TimePosition = 0
	s:Play()
end

return SoundFX
