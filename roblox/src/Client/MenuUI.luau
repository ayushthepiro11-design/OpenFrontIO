--!strict
-- Authentic Browser-Exact OpenFront.io Main Menu, Profile Bar, Flag/Color/Pattern Customizer,
-- Rotating Public Lobby Queue Card, Singleplayer Launcher, Host Custom Match Modal, Settings & Guide!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")

local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local MapRegistry = require(Shared:WaitForChild("Maps"):WaitForChild("MapRegistry"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
local UiWidgets = require(script.Parent:WaitForChild("UiWidgets"))

local MenuUI = {}
MenuUI.__index = MenuUI

export type MenuInstance = typeof(setmetatable({} :: any, MenuUI))

function MenuUI.new(parentGui: ScreenGui, callbacks: {
	onSendIntent: (intent: string, payload: any) -> (),
	onLocalSettingChanged: (profile: Types.PlayerProfileSave) -> (),
}): MenuInstance
	local self = setmetatable({}, MenuUI) :: any
	self.callbacks = callbacks
	self.profile = nil :: Types.PlayerProfileSave?
	self.lobbyState = nil :: any
	self.isQueued = false
	self.customCfg = Config.DefaultGameConfig(true)

	-- Fullscreen translucent tint over the live animated AI background battle!
	local root = Instance.new("Frame")
	root.Name = "MenuOverlay"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(8, 13, 24)
	root.BackgroundTransparency = 0.34
	root.BorderSizePixel = 0
	root.ZIndex = 30
	root.Parent = parentGui
	self.root = root

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveUIScale"
	uiScale.Scale = 1
	uiScale.Parent = root
	self.uiScale = uiScale

	-- Fullscreen modal backdrop scrim so sub-modals NEVER bleed over MainPortalCard!
	local modalScrim = Instance.new("TextButton")
	modalScrim.Name = "ModalScrim"
	modalScrim.Size = UDim2.fromScale(1, 1)
	modalScrim.BackgroundColor3 = Color3.fromRGB(4, 9, 20)
	modalScrim.BackgroundTransparency = 0.22
	modalScrim.BorderSizePixel = 0
	modalScrim.Text = ""
	modalScrim.AutoButtonColor = false
	modalScrim.Visible = false
	modalScrim.ZIndex = 44
	modalScrim.Parent = root
	self.modalScrim = modalScrim

	-- Top Header Bar (XP Level Badge + Wins/Stats + Settings + How to Play)
	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, -32, 0, 52)
	topBar.Position = UDim2.fromOffset(16, 12)
	topBar.BackgroundColor3 = Theme.UI.BgPanel
	topBar.BackgroundTransparency = 0.10
	topBar.BorderSizePixel = 0
	UiWidgets.AddCorner(topBar, 10)
	UiWidgets.AddStroke(topBar, Theme.UI.Border, 1, 0.35)
	topBar.Parent = root

	local brandLbl = Instance.new("TextLabel")
	brandLbl.Position = UDim2.fromOffset(16, 0)
	brandLbl.Size = UDim2.fromOffset(196, 52)
	brandLbl.BackgroundTransparency = 1
	brandLbl.Font = Enum.Font.GothamBlack
	brandLbl.Text = "OPENFRONT"
	brandLbl.TextSize = 21
	brandLbl.TextTruncate = Enum.TextTruncate.AtEnd
	brandLbl.TextXAlignment = Enum.TextXAlignment.Left
	brandLbl.TextColor3 = Color3.new(1, 1, 1)
	brandLbl.Parent = topBar

	local statsLbl = Instance.new("TextLabel")
	statsLbl.Position = UDim2.fromOffset(222, 5)
	statsLbl.Size = UDim2.new(1, -482, 0, 22)
	statsLbl.BackgroundTransparency = 1
	statsLbl.Font = Enum.Font.GothamBold
	statsLbl.TextSize = 13
	statsLbl.TextTruncate = Enum.TextTruncate.AtEnd
	statsLbl.TextWrapped = false
	statsLbl.TextXAlignment = Enum.TextXAlignment.Left
	statsLbl.TextColor3 = Color3.fromRGB(226, 232, 240)
	statsLbl.Text = "Lv. 1  •  0 Wins  •  0 Games"
	statsLbl.Parent = topBar
	self.statsLbl = statsLbl

	local xpBg = Instance.new("Frame")
	xpBg.Position = UDim2.fromOffset(222, 31)
	xpBg.Size = UDim2.fromOffset(210, 9)
	xpBg.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
	xpBg.BorderSizePixel = 0
	UiWidgets.AddCorner(xpBg, 99)
	xpBg.Parent = topBar

	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0.15, 1)
	xpFill.BackgroundColor3 = Theme.UI.AccentBlue
	xpFill.BorderSizePixel = 0
	UiWidgets.AddCorner(xpFill, 99)
	xpFill.Parent = xpBg
	self.xpFill = xpFill

	local helpBtn = UiWidgets.MakeButton(
		topBar,
		"❓ How to Play",
		Theme.UI.BgCard,
		UDim2.fromOffset(116, 34),
		UDim2.new(1, -248, 0.5, -17)
	)
	local settingsBtn = UiWidgets.MakeButton(
		topBar,
		"⚙️ Settings",
		Theme.UI.BgCard,
		UDim2.fromOffset(110, 34),
		UDim2.new(1, -122, 0.5, -17)
	)

	-- Center Main Card (exact OpenFront.io centered portal card!)
	local centerCard = Instance.new("Frame")
	centerCard.Name = "MainPortalCard"
	centerCard.AnchorPoint = Vector2.new(0.5, 0.5)
	centerCard.Position = UDim2.new(0.5, 0, 0.54, 0)
	centerCard.Size = UDim2.fromOffset(480, 446)
	centerCard.BackgroundColor3 = Theme.UI.BgPanel
	centerCard.BackgroundTransparency = 0.08
	centerCard.BorderSizePixel = 0
	UiWidgets.AddCorner(centerCard, 14)
	UiWidgets.AddStroke(centerCard, Color3.fromRGB(96, 165, 250), 1.5, 0.45)
	centerCard.Parent = root
	self.centerCard = centerCard

	local titleHero = Instance.new("TextLabel")
	titleHero.Position = UDim2.fromOffset(20, 14)
	titleHero.Size = UDim2.new(1, -40, 0, 32)
	titleHero.BackgroundTransparency = 1
	titleHero.Font = Enum.Font.GothamBlack
	titleHero.Text = "CONQUER THE WORLD"
	titleHero.TextSize = 24
	titleHero.TextColor3 = Color3.new(1, 1, 1)
	titleHero.Parent = centerCard

	local subHero = Instance.new("TextLabel")
	subHero.Position = UDim2.fromOffset(20, 44)
	subHero.Size = UDim2.new(1, -40, 0, 18)
	subHero.BackgroundTransparency = 1
	subHero.Font = Enum.Font.Gotham
	subHero.Text = "Expand borders • Build cities, ports & trains • Launch MIRV nukes"
	subHero.TextSize = 12
	subHero.TextColor3 = Theme.UI.TextMuted
	subHero.Parent = centerCard

	-- Identity Customizer Row (Flag + Color + Pattern)
	local idRow = Instance.new("Frame")
	idRow.Position = UDim2.fromOffset(20, 70)
	idRow.Size = UDim2.new(1, -40, 0, 48)
	idRow.BackgroundColor3 = Theme.UI.BgCard
	idRow.BorderSizePixel = 0
	UiWidgets.AddCorner(idRow, 9)
	idRow.Parent = centerCard

	local flagHolder = Instance.new("Frame")
	flagHolder.Position = UDim2.fromOffset(10, 9)
	flagHolder.Size = UDim2.fromOffset(38, 30)
	flagHolder.BackgroundTransparency = 1
	flagHolder.Parent = idRow
	self.flagHolder = flagHolder

	local flagBtn = UiWidgets.MakeButton(
		idRow,
		"🏳️ Change Flag",
		Theme.UI.BgHover,
		UDim2.fromOffset(124, 32),
		UDim2.fromOffset(56, 8)
	)

	local colorSwatch = Instance.new("TextButton")
	colorSwatch.Position = UDim2.fromOffset(190, 8)
	colorSwatch.Size = UDim2.fromOffset(118, 32)
	colorSwatch.BackgroundColor3 = Theme.HexToColor3(Theme.HumanColors[1])
	colorSwatch.BorderSizePixel = 0
	colorSwatch.Font = Enum.Font.GothamBold
	colorSwatch.TextSize = 12
	colorSwatch.Text = "🎨 Color"
	colorSwatch.TextColor3 = Color3.fromRGB(15, 23, 42)
	UiWidgets.AddCorner(colorSwatch, 7)
	UiWidgets.AddStroke(colorSwatch, Color3.new(1, 1, 1), 1.5, 0.35)
	colorSwatch.Parent = idRow
	self.colorSwatch = colorSwatch

	local patternBtn = UiWidgets.MakeButton(
		idRow,
		"❖ Pattern: Solid",
		Theme.UI.BgHover,
		UDim2.fromOffset(122, 32),
		UDim2.fromOffset(316, 8)
	)
	self.patternBtn = patternBtn

	-- Featured Live Public Lobby Card (exact OpenFront LobbyCard.ts!)
	local publicCard = Instance.new("Frame")
	publicCard.Position = UDim2.fromOffset(20, 128)
	publicCard.Size = UDim2.new(1, -40, 0, 150)
	publicCard.BackgroundColor3 = Color3.fromRGB(22, 33, 52)
	publicCard.BorderSizePixel = 0
	UiWidgets.AddCorner(publicCard, 10)
	UiWidgets.AddStroke(publicCard, Theme.UI.AccentBlue, 1.5, 0.25)
	publicCard.Parent = centerCard

	local pubMapThumb = Instance.new("Frame")
	pubMapThumb.Position = UDim2.fromOffset(12, 12)
	pubMapThumb.Size = UDim2.fromOffset(196, 126)
	pubMapThumb.BorderSizePixel = 0
	pubMapThumb.Parent = publicCard
	self.pubMapThumb = pubMapThumb
	self.lastRenderedPubMap = ""

	local pubTitle = Instance.new("TextLabel")
	pubTitle.Position = UDim2.fromOffset(220, 14)
	pubTitle.Size = UDim2.fromOffset(205, 24)
	pubTitle.BackgroundTransparency = 1
	pubTitle.Font = Enum.Font.GothamBlack
	pubTitle.TextXAlignment = Enum.TextXAlignment.Left
	pubTitle.TextSize = 18
	pubTitle.TextColor3 = Color3.new(1, 1, 1)
	pubTitle.Text = "World Map"
	pubTitle.Parent = publicCard
	self.pubTitle = pubTitle

	local pubMeta = Instance.new("TextLabel")
	pubMeta.Position = UDim2.fromOffset(220, 40)
	pubMeta.Size = UDim2.fromOffset(205, 36)
	pubMeta.BackgroundTransparency = 1
	pubMeta.Font = Enum.Font.GothamBold
	pubMeta.TextXAlignment = Enum.TextXAlignment.Left
	pubMeta.TextWrapped = true
	pubMeta.TextSize = 13
	pubMeta.TextColor3 = Color3.fromRGB(147, 197, 253)
	pubMeta.Text = "PUBLIC FFA  •  Starting in 12s"
	pubMeta.Parent = publicCard
	self.pubMeta = pubMeta

	local joinPublicBtn = UiWidgets.MakeButton(
		publicCard,
		"▶ JOIN PUBLIC MATCH",
		Theme.UI.AccentBlue,
		UDim2.fromOffset(205, 44),
		UDim2.fromOffset(220, 92)
	)
	joinPublicBtn.TextSize = 15
	self.joinPublicBtn = joinPublicBtn

	-- Singleplayer + Host Custom Match Buttons
	local singleBtn = UiWidgets.MakeButton(
		centerCard,
		"⚡ PLAY SINGLEPLAYER NOW",
		Theme.UI.AccentGreen,
		UDim2.new(1, -40, 0, 48),
		UDim2.fromOffset(20, 290)
	)
	singleBtn.TextSize = 16

	local hostBtn = UiWidgets.MakeButton(
		centerCard,
		"🛠️ HOST CUSTOM / TEAM / SHINOBI LOBBY",
		Color3.fromRGB(51, 65, 85),
		UDim2.new(1, -40, 0, 44),
		UDim2.fromOffset(20, 348)
	)
	hostBtn.TextSize = 14

	local footerTip = Instance.new("TextLabel")
	footerTip.Position = UDim2.fromOffset(20, 402)
	footerTip.Size = UDim2.new(1, -40, 0, 30)
	footerTip.BackgroundTransparency = 1
	footerTip.Font = Enum.Font.Gotham
	footerTip.TextSize = 11
	footerTip.TextColor3 = Theme.UI.TextMuted
	footerTip.Text = "Left-Click: Attack • Right-Click: Radial Menu • Ctrl+Click / B: Build • Scroll: Zoom"
	footerTip.Parent = centerCard

	-- Sub-Modals (Host Custom Lobby, Flag Picker, Settings, How to Play)
	self.hostModal = self:_BuildHostModal(root)
	self.flagModal = self:_BuildFlagModal(root)
	self.settingsModal = self:_BuildSettingsModal(root)
	self.helpModal = self:_BuildHelpModal(root)

	local function openExclusiveModal(targetModal: Frame?)
		self.hostModal.Visible = (targetModal == self.hostModal)
		self.flagModal.Visible = (targetModal == self.flagModal)
		self.settingsModal.Visible = (targetModal == self.settingsModal)
		self.helpModal.Visible = (targetModal == self.helpModal)
		local anyOpen = targetModal ~= nil
		self.modalScrim.Visible = anyOpen
		self.centerCard.Visible = not anyOpen
	end
	self._openModal = openExclusiveModal
	self.modalScrim.Activated:Connect(function()
		openExclusiveModal(nil)
	end)

	-- Wire buttons
	joinPublicBtn.Activated:Connect(function()
		SoundFX.Play("click")
		if self.lobbyState ~= nil and (self.lobbyState.onlineCount or 1) <= 1 then
			local cfg = Config.DefaultGameConfig(false)
			cfg.mapId = self.lobbyState.nextMapId or "World"
			cfg.mode = self.lobbyState.nextMode or "FFA"
			cfg.numTeams = self.lobbyState.nextNumTeams or 0
			self.callbacks.onSendIntent("StartMatchNow", cfg)
		else
			self.isQueued = not self.isQueued
			self.callbacks.onSendIntent("ToggleQueue", {})
			self:_RefreshLobbyCard()
		end
	end)

	singleBtn.Activated:Connect(function()
		SoundFX.Play("click")
		local cfg = Config.DefaultGameConfig(true)
		cfg.mapId = self.customCfg.mapId
		self.callbacks.onSendIntent("StartMatchNow", cfg)
	end)

	hostBtn.Activated:Connect(function()
		SoundFX.Play("click")
		openExclusiveModal(self.hostModal)
	end)

	flagBtn.Activated:Connect(function()
		SoundFX.Play("click")
		openExclusiveModal(self.flagModal)
	end)

	colorSwatch.Activated:Connect(function()
		SoundFX.Play("click")
		if self.profile ~= nil then
			local nextIdx = (self.profile.colorIndex % #Theme.HumanColors) + 1
			self.profile.colorIndex = nextIdx
			self.callbacks.onSendIntent("UpdateProfile", { colorIndex = nextIdx })
			self:SetProfile(self.profile)
		end
	end)

	patternBtn.Activated:Connect(function()
		SoundFX.Play("click")
		if self.profile ~= nil then
			local curIdx = 1
			for i, pat in ipairs(Theme.Patterns) do
				if pat.id == self.profile.patternId then
					curIdx = i
					break
				end
			end
			local nxt = Theme.Patterns[(curIdx % #Theme.Patterns) + 1]
			self.profile.patternId = nxt.id
			self.callbacks.onSendIntent("UpdateProfile", { patternId = nxt.id })
			self:SetProfile(self.profile)
		end
	end)

	settingsBtn.Activated:Connect(function()
		SoundFX.Play("click")
		openExclusiveModal(self.settingsModal)
	end)

	helpBtn.Activated:Connect(function()
		SoundFX.Play("click")
		openExclusiveModal(self.helpModal)
	end)

	-- Render initial World thumbnail right away
	UiWidgets.PopulateMapPreview(self.pubMapThumb, MapRegistry.Get("World"))
	self.lastRenderedPubMap = "World"

	return self
end

function MenuUI:_BuildHostModal(parent: Frame): Frame
	local modal = Instance.new("Frame")
	modal.Name = "HostLobbyModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(740, 510)
	modal.BackgroundColor3 = Theme.UI.BgDark
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 45
	UiWidgets.AddCorner(modal, 14)
	UiWidgets.AddStroke(modal, Theme.UI.AccentBlue, 2, 0.25)
	modal.Parent = parent

	local header = Instance.new("TextLabel")
	header.Position = UDim2.fromOffset(20, 14)
	header.Size = UDim2.fromOffset(520, 28)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextSize = 20
	header.TextColor3 = Color3.new(1, 1, 1)
	header.Text = "🛠️ HOST CUSTOM OPENFRONT MATCH"
	header.ZIndex = 46
	header.Parent = modal

	local closeBtn = UiWidgets.MakeButton(
		modal,
		"✕ Close",
		Theme.UI.AccentRed,
		UDim2.fromOffset(88, 32),
		UDim2.new(1, -104, 0, 12)
	)
	closeBtn.ZIndex = 46
	closeBtn.Activated:Connect(function()
		SoundFX.Play("click")
		if self._openModal then
			self._openModal(nil)
		else
			modal.Visible = false
		end
	end)

	-- Left Column: All 10 Real OpenFront Maps Scroll Grid with Live Rendered Previews!
	local mapScroll = Instance.new("ScrollingFrame")
	mapScroll.Position = UDim2.fromOffset(18, 52)
	mapScroll.Size = UDim2.fromOffset(420, 392)
	mapScroll.BackgroundColor3 = Theme.UI.BgPanel
	mapScroll.BorderSizePixel = 0
	mapScroll.ScrollBarThickness = 6
	mapScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mapScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	mapScroll.ZIndex = 46
	UiWidgets.AddCorner(mapScroll, 10)
	mapScroll.Parent = modal

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(194, 128)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.Parent = mapScroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = mapScroll

	local cardStrokes: { [string]: UIStroke } = {}
	for _, mapDef in ipairs(MapRegistry.List) do
		local card = Instance.new("TextButton")
		card.BackgroundColor3 = Theme.UI.BgCard
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = true
		card.ZIndex = 47
		UiWidgets.AddCorner(card, 8)
		local st = UiWidgets.AddStroke(
			card,
			if mapDef.id == self.customCfg.mapId then Theme.UI.AccentGold else Theme.UI.Border,
			if mapDef.id == self.customCfg.mapId then 2.5 else 1,
			0.15
		)
		cardStrokes[mapDef.id] = st
		card.Parent = mapScroll

		local prev = Instance.new("Frame")
		prev.Position = UDim2.fromOffset(7, 7)
		prev.Size = UDim2.fromOffset(180, 92)
		prev.ZIndex = 48
		prev.Parent = card
		UiWidgets.PopulateMapPreview(prev, mapDef)

		local lbl = Instance.new("TextLabel")
		lbl.Position = UDim2.fromOffset(8, 101)
		lbl.Size = UDim2.fromOffset(178, 22)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 12
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = string.format("%s (%d Nations)", mapDef.name, #mapDef.nations)
		lbl.ZIndex = 48
		lbl.Parent = card

		card.Activated:Connect(function()
			SoundFX.Play("click")
			self.customCfg.mapId = mapDef.id
			for id, s in pairs(cardStrokes) do
				s.Color = if id == mapDef.id then Theme.UI.AccentGold else Theme.UI.Border
				s.Thickness = if id == mapDef.id then 2.5 else 1
			end
		end)
	end

	-- Right Column: Exact OpenFront GameConfig toggles & cycle pills!
	local optsFrame = Instance.new("ScrollingFrame")
	optsFrame.Position = UDim2.fromOffset(450, 52)
	optsFrame.Size = UDim2.fromOffset(272, 392)
	optsFrame.BackgroundColor3 = Theme.UI.BgPanel
	optsFrame.BorderSizePixel = 0
	optsFrame.ScrollBarThickness = 5
	optsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	optsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	optsFrame.ZIndex = 46
	UiWidgets.AddCorner(optsFrame, 10)
	optsFrame.Parent = modal

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 7)
	listLayout.Parent = optsFrame
	local opad = Instance.new("UIPadding")
	opad.PaddingTop = UDim.new(0, 10)
	opad.PaddingLeft = UDim.new(0, 10)
	opad.PaddingRight = UDim.new(0, 10)
	opad.PaddingBottom = UDim.new(0, 10)
	opad.Parent = optsFrame

	local function addCycleOption(labelFn: () -> string, onClick: () -> ())
		local b = UiWidgets.MakeButton(optsFrame, labelFn(), Theme.UI.BgCard, UDim2.new(1, 0, 0, 34), nil)
		b.ZIndex = 47
		b.TextSize = 12
		b.Activated:Connect(function()
			SoundFX.Play("click")
			onClick()
			b.Text = labelFn()
		end)
	end

	local modePresets = {
		{ label = "Free For All (FFA)", mode = "FFA", teams = 0 },
		{ label = "2 Teams (Red vs Blue)", mode = "Teams", teams = 2 },
		{ label = "3 Teams", mode = "Teams", teams = 3 },
		{ label = "4 Teams", mode = "Teams", teams = 4 },
		{ label = "Humans vs AI Nations", mode = "Teams", teams = -1 },
	}
	local modeIdx = 1
	addCycleOption(function()
		return "⚔️ Mode: " .. modePresets[modeIdx].label
	end, function()
		modeIdx = (modeIdx % #modePresets) + 1
		self.customCfg.mode = modePresets[modeIdx].mode :: any
		self.customCfg.numTeams = modePresets[modeIdx].teams
	end)

	local diffs = { "Easy", "Medium", "Hard", "Impossible" }
	local diffIdx = 2
	addCycleOption(function()
		return "🎖️ AI Difficulty: " .. self.customCfg.difficulty
	end, function()
		diffIdx = (diffIdx % #diffs) + 1
		self.customCfg.difficulty = diffs[diffIdx] :: any
	end)

	local botSteps = { 0, 40, 100, 180 }
	local botIdx = 4
	addCycleOption(function()
		return "🤖 Minor Bots: " .. tostring(self.customCfg.bots)
	end, function()
		botIdx = (botIdx % #botSteps) + 1
		self.customCfg.bots = botSteps[botIdx]
	end)

	addCycleOption(function()
		return "🏛️ AI Nations: " .. (if self.customCfg.spawnNations then "Enabled" else "Disabled")
	end, function()
		self.customCfg.spawnNations = not self.customCfg.spawnNations
	end)

	local startGoldSteps = { 0, 1_000_000, 5_000_000, 25_000_000 }
	local sgIdx = 1
	addCycleOption(function()
		return "💰 Starting Gold: " .. Format.Gold(self.customCfg.startingGold)
	end, function()
		sgIdx = (sgIdx % #startGoldSteps) + 1
		self.customCfg.startingGold = startGoldSteps[sgIdx]
	end)

	local multSteps = { 1, 2, 5, 10 }
	local multIdx = 1
	addCycleOption(function()
		return "📈 Gold Multiplier: " .. tostring(self.customCfg.goldMultiplier) .. "x"
	end, function()
		multIdx = (multIdx % #multSteps) + 1
		self.customCfg.goldMultiplier = multSteps[multIdx]
	end)

	addCycleOption(function()
		return "⚡ Instant Build: " .. (if self.customCfg.instantBuild then "ON" else "OFF")
	end, function()
		self.customCfg.instantBuild = not self.customCfg.instantBuild
	end)

	addCycleOption(function()
		return "♾️ Infinite Gold: " .. (if self.customCfg.infiniteGold then "ON" else "OFF")
	end, function()
		self.customCfg.infiniteGold = not self.customCfg.infiniteGold
	end)

	addCycleOption(function()
		return "🪖 Infinite Troops: " .. (if self.customCfg.infiniteTroops then "ON" else "OFF")
	end, function()
		self.customCfg.infiniteTroops = not self.customCfg.infiniteTroops
	end)

	addCycleOption(function()
		return "🤝 Alliances: " .. (if self.customCfg.disableAlliances then "Disabled" else "Allowed (5m)")
	end, function()
		self.customCfg.disableAlliances = not self.customCfg.disableAlliances
	end)

	addCycleOption(function()
		return "⏳ Doomsday Clock: " .. (if self.customCfg.doomsdayEnabled then "ON (Anti-Stall)" else "OFF")
	end, function()
		self.customCfg.doomsdayEnabled = not self.customCfg.doomsdayEnabled
	end)

	addCycleOption(function()
		return "🎲 Random Spawn: " .. (if self.customCfg.randomSpawn then "ON" else "Choose Spot")
	end, function()
		self.customCfg.randomSpawn = not self.customCfg.randomSpawn
	end)

	local launchBtn = UiWidgets.MakeButton(
		modal,
		"🚀 LAUNCH MATCH NOW",
		Theme.UI.AccentGreen,
		UDim2.new(1, -36, 0, 44),
		UDim2.fromOffset(18, 454)
	)
	launchBtn.TextSize = 16
	launchBtn.ZIndex = 47
	launchBtn.Activated:Connect(function()
		SoundFX.Play("click")
		if self._openModal then
			self._openModal(nil)
		end
		self.callbacks.onSendIntent("StartMatchNow", self.customCfg)
	end)

	return modal
end

function MenuUI:_BuildFlagModal(parent: Frame): Frame
	local modal = Instance.new("Frame")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(560, 420)
	modal.BackgroundColor3 = Theme.UI.BgDark
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 48
	UiWidgets.AddCorner(modal, 14)
	UiWidgets.AddStroke(modal, Theme.UI.AccentGold, 2, 0.25)
	modal.Parent = parent

	local hdr = Instance.new("TextLabel")
	hdr.Position = UDim2.fromOffset(18, 12)
	hdr.Size = UDim2.fromOffset(380, 28)
	hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBlack
	hdr.TextSize = 18
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.TextColor3 = Color3.new(1, 1, 1)
	hdr.Text = "🏳️ SELECT NATION OR SHINOBI FLAG"
	hdr.ZIndex = 49
	hdr.Parent = modal

	local closeBtn = UiWidgets.MakeButton(
		modal,
		"✕",
		Theme.UI.AccentRed,
		UDim2.fromOffset(36, 30),
		UDim2.new(1, -50, 0, 11)
	)
	closeBtn.ZIndex = 49
	closeBtn.Activated:Connect(function()
		if self._openModal then
			self._openModal(nil)
		else
			modal.Visible = false
		end
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(16, 50)
	scroll.Size = UDim2.new(1, -32, 1, -66)
	scroll.BackgroundColor3 = Theme.UI.BgPanel
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 49
	UiWidgets.AddCorner(scroll, 10)
	scroll.Parent = modal

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(164, 42)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = scroll

	for _, spec in ipairs(Format.Flags) do
		local item = Instance.new("TextButton")
		item.BackgroundColor3 = Theme.UI.BgCard
		item.BorderSizePixel = 0
		item.Text = ""
		item.ZIndex = 50
		UiWidgets.AddCorner(item, 7)
		item.Parent = scroll

		local fb = UiWidgets.CreateFlagBadge(item, spec.code, UDim2.fromOffset(32, 22), UDim2.fromOffset(8, 10))
		fb.ZIndex = 51

		local nm = Instance.new("TextLabel")
		nm.Position = UDim2.fromOffset(48, 0)
		nm.Size = UDim2.new(1, -54, 1, 0)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 11
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextColor3 = Color3.new(1, 1, 1)
		nm.Text = spec.label
		nm.ZIndex = 51
		nm.Parent = item

		item.Activated:Connect(function()
			SoundFX.Play("click")
			if self._openModal then
				self._openModal(nil)
			else
				modal.Visible = false
			end
			if self.profile ~= nil then
				self.profile.flag = spec.code
				self.callbacks.onSendIntent("UpdateProfile", { flag = spec.code })
				self:SetProfile(self.profile)
			end
		end)
	end

	return modal
end

function MenuUI:_BuildSettingsModal(parent: Frame): Frame
	local modal = Instance.new("Frame")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(420, 320)
	modal.BackgroundColor3 = Theme.UI.BgDark
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 48
	UiWidgets.AddCorner(modal, 14)
	UiWidgets.AddStroke(modal, Theme.UI.Border, 2, 0.25)
	modal.Parent = parent

	local hdr = Instance.new("TextLabel")
	hdr.Position = UDim2.fromOffset(18, 14)
	hdr.Size = UDim2.fromOffset(260, 26)
	hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBlack
	hdr.TextSize = 18
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.TextColor3 = Color3.new(1, 1, 1)
	hdr.Text = "⚙️ SETTINGS"
	hdr.ZIndex = 49
	hdr.Parent = modal

	local closeBtn = UiWidgets.MakeButton(
		modal,
		"✕",
		Theme.UI.AccentRed,
		UDim2.fromOffset(36, 30),
		UDim2.new(1, -50, 0, 12)
	)
	closeBtn.ZIndex = 49
	closeBtn.Activated:Connect(function()
		if self._openModal then
			self._openModal(nil)
		else
			modal.Visible = false
		end
	end)

	local body = Instance.new("Frame")
	body.Position = UDim2.fromOffset(18, 56)
	body.Size = UDim2.new(1, -36, 1, -72)
	body.BackgroundTransparency = 1
	body.ZIndex = 49
	body.Parent = modal

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = body

	local renderBtn = UiWidgets.MakeButton(body, "🖥️ Renderer: Auto Pixel Shader", Theme.UI.BgCard, UDim2.new(1, 0, 0, 40), nil)
	renderBtn.ZIndex = 50
	renderBtn.Activated:Connect(function()
		if self.profile ~= nil then
			self.profile.preferScanline2D = not self.profile.preferScanline2D
			renderBtn.Text = "🖥️ Renderer: " .. (if self.profile.preferScanline2D then "Scanline RLE 2D" else "Auto Pixel Shader")
			self.callbacks.onSendIntent("UpdateProfile", { preferScanline2D = self.profile.preferScanline2D })
			self.callbacks.onLocalSettingChanged(self.profile)
		end
	end)

	local cbBtn = UiWidgets.MakeButton(body, "👁️ Colorblind Palette: OFF", Theme.UI.BgCard, UDim2.new(1, 0, 0, 40), nil)
	cbBtn.ZIndex = 50
	cbBtn.Activated:Connect(function()
		if self.profile ~= nil then
			self.profile.colorblindMode = not self.profile.colorblindMode
			cbBtn.Text = "👁️ Colorblind Palette: " .. (if self.profile.colorblindMode then "ON" else "OFF")
			self.callbacks.onSendIntent("UpdateProfile", { colorblindMode = self.profile.colorblindMode })
			self.callbacks.onLocalSettingChanged(self.profile)
		end
	end)

	local namesBtn = UiWidgets.MakeButton(body, "🏷️ Territory Labels: Shown", Theme.UI.BgCard, UDim2.new(1, 0, 0, 40), nil)
	namesBtn.ZIndex = 50
	namesBtn.Activated:Connect(function()
		if self.profile ~= nil then
			self.profile.showNames = not self.profile.showNames
			namesBtn.Text = "🏷️ Territory Labels: " .. (if self.profile.showNames then "Shown" else "Hidden")
			self.callbacks.onSendIntent("UpdateProfile", { showNames = self.profile.showNames })
			self.callbacks.onLocalSettingChanged(self.profile)
		end
	end)

	local soundBtn = UiWidgets.MakeButton(body, "🔊 Sound Effects: 70%", Theme.UI.BgCard, UDim2.new(1, 0, 0, 40), nil)
	soundBtn.ZIndex = 50
	soundBtn.Activated:Connect(function()
		if self.profile ~= nil then
			local steps = { 0, 0.35, 0.70, 1.0 }
			local nxt = 0.70
			for i, v in ipairs(steps) do
				if math.abs(self.profile.soundVolume - v) < 0.05 then
					nxt = steps[(i % #steps) + 1]
					break
				end
			end
			self.profile.soundVolume = nxt
			SoundFX.Volume = nxt
			soundBtn.Text = string.format("🔊 Sound Effects: %d%%", math.floor(nxt * 100 + 0.5))
			self.callbacks.onSendIntent("UpdateProfile", { soundVolume = nxt })
		end
	end)

	return modal
end

function MenuUI:_BuildHelpModal(parent: Frame): Frame
	local modal = Instance.new("Frame")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(540, 390)
	modal.BackgroundColor3 = Theme.UI.BgDark
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 48
	UiWidgets.AddCorner(modal, 14)
	UiWidgets.AddStroke(modal, Theme.UI.AccentBlue, 2, 0.25)
	modal.Parent = parent

	local hdr = Instance.new("TextLabel")
	hdr.Position = UDim2.fromOffset(20, 14)
	hdr.Size = UDim2.fromOffset(380, 28)
	hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBlack
	hdr.TextSize = 18
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.TextColor3 = Color3.new(1, 1, 1)
	hdr.Text = "📖 OPENFRONT FIELD GUIDE & CONTROLS"
	hdr.ZIndex = 49
	hdr.Parent = modal

	local closeBtn = UiWidgets.MakeButton(
		modal,
		"Got it!",
		Theme.UI.AccentBlue,
		UDim2.fromOffset(84, 30),
		UDim2.new(1, -100, 0, 12)
	)
	closeBtn.ZIndex = 49
	closeBtn.Activated:Connect(function()
		if self._openModal then
			self._openModal(nil)
		else
			modal.Visible = false
		end
	end)

	local txt = Instance.new("TextLabel")
	txt.Position = UDim2.fromOffset(20, 54)
	txt.Size = UDim2.new(1, -40, 1, -72)
	txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.GothamMedium
	txt.TextSize = 13
	txt.TextWrapped = true
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.TextYAlignment = Enum.TextYAlignment.Top
	txt.TextColor3 = Color3.fromRGB(226, 232, 240)
	txt.ZIndex = 49
	txt.Text = table.concat({
		"• SPAWN & EXPAND: Click any land during Spawn Phase, then Left-Click unclaimed land & weaker neighbors! Keep troops around 40%–65% of Max Troops for peak growth rate.",
		"",
		"• ECONOMY: Build Ports (⚓) on coasts to spawn Trade Ships for huge Gold! Build Cities (🏙️ +250K Max Troops) and Factories (🏭) to connect Railroads & spawn Gold Trains!",
		"",
		"• NAVAL & DEFENSE: Click remote coasts via Boat (⛴️ / key V) for amphibious landings! Build Warships (🚢) to sink enemy boats & pirate Trade Ships. Build Defense Posts (🛡️) on borders for 5x defense!",
		"",
		"• NUCLEAR WARFARE: Build a Missile Silo (🚀) to launch Atom Bombs (☢️), Hydrogen Bombs (💥), and empire-shattering MIRVs (☄️)! Build SAM Launchers (📡) to intercept incoming nukes!",
		"",
		"• HOTKEYS: WASD/Drag = Pan | Scroll = Zoom | Right-Click = Radial Menu | Ctrl+Click or B = Build | V = Boat | R = Retreat | Space = Alt Affiliation View | Q/E or 1-9 = Attack % | C = Center",
	}, "\n")
	txt.Parent = modal

	return modal
end

function MenuUI:SetProfile(profile: Types.PlayerProfileSave)
	self.profile = profile
	SoundFX.Volume = profile.soundVolume

	local nextXp = Config.XpForNextLevel(profile.level)
	local presBadge = if profile.prestige > 0 then string.format("★P%d ", profile.prestige) else ""
	self.statsLbl.Text = string.format(
		"%sLv. %d (%d/%d XP)  •  🏆 %d Wins  •  🎮 %d Games  •  ☢️ %d Nukes",
		presBadge,
		profile.level,
		profile.xp,
		nextXp,
		profile.wins,
		profile.gamesPlayed,
		profile.nukesLaunched
	)
	self.xpFill.Size = UDim2.fromScale(math.clamp(profile.xp / math.max(1, nextXp), 0.04, 1), 1)

	self.flagHolder:ClearAllChildren()
	UiWidgets.CreateFlagBadge(self.flagHolder, profile.flag, UDim2.fromScale(1, 1), UDim2.new())

	local colHex = Theme.HumanColors[((profile.colorIndex - 1) % #Theme.HumanColors) + 1]
	self.colorSwatch.BackgroundColor3 = Theme.HexToColor3(colHex)

	for _, pat in ipairs(Theme.Patterns) do
		if pat.id == profile.patternId then
			self.patternBtn.Text = "❖ Pattern: " .. pat.name
			break
		end
	end
end

function MenuUI:_RefreshLobbyCard()
	local ls = self.lobbyState
	if ls == nil then
		return
	end
	if ls.nextMapId ~= nil and ls.nextMapId ~= self.lastRenderedPubMap then
		self.lastRenderedPubMap = ls.nextMapId
		UiWidgets.PopulateMapPreview(self.pubMapThumb, MapRegistry.Get(ls.nextMapId))
	end
	self.pubTitle.Text = ls.nextMapName or "World Map"
	local modeStr = if ls.nextMode == "Teams" then string.format("%d TEAMS", ls.nextNumTeams or 2) else "PUBLIC FFA"
	local qCount = if ls.queuedPlayers then #ls.queuedPlayers else 0
	self.pubMeta.Text = string.format(
		"%s  •  Starts in %ds\n👥 %d Online (%d Ready)",
		modeStr,
		ls.countdown or 12,
		ls.onlineCount or 1,
		qCount
	)
	if (ls.onlineCount or 1) <= 1 then
		self.joinPublicBtn.Text = "▶ PLAY FEATURED MAP"
		self.joinPublicBtn.BackgroundColor3 = Theme.UI.AccentBlue
	elseif self.isQueued then
		self.joinPublicBtn.Text = "✓ QUEUED — STARTING SOON"
		self.joinPublicBtn.BackgroundColor3 = Theme.UI.AccentGold
	else
		self.joinPublicBtn.Text = "▶ JOIN PUBLIC QUEUE"
		self.joinPublicBtn.BackgroundColor3 = Theme.UI.AccentBlue
	end
end

function MenuUI:UpdateLobbyState(lobbyState: any)
	self.lobbyState = lobbyState
	self:_RefreshLobbyCard()
end

function MenuUI:SetVisible(vis: boolean)
	self.root.Visible = vis
	if not vis and self._openModal then
		self._openModal(nil)
	end
end

return MenuUI
