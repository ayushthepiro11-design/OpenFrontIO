--!strict
-- Zero-error local `rbxasset://sounds/` sound effect synthesizer for OpenFront UI & battle cues

local SoundService = game:GetService("SoundService")

local SoundFX = {}
SoundFX.Volume = 0.7

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

local soundPool: { [string]: Sound } = {}

function SoundFX.Play(cueName: string)
	if SoundFX.Volume <= 0.01 then
		return
	end
	local spec = CUES[cueName]
	if spec == nil then
		return
	end
	local s = soundPool[cueName]
	if s == nil then
		local ok, created = pcall(function()
			local snd = Instance.new("Sound")
			snd.Name = "OF_" .. cueName
			snd.SoundId = spec.url
			snd.Parent = SoundService
			return snd
		end)
		if not ok or created == nil then
			return
		end
		s = created
		soundPool[cueName] = s
	end
	s.PlaybackSpeed = spec.pitch
	s.Volume = math.clamp(spec.vol * SoundFX.Volume, 0, 1)
	s.TimePosition = 0
	s:Play()
end

return SoundFX
