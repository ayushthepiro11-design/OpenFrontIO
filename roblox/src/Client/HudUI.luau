--!strict
-- Complete Browser-Exact In-Game OpenFront HUD:
--   1. Spawn Phase Top Banner + Instant Start
--   2. Bottom-Left ControlPanel (Troops/Max + Rate/s, Gold + Floating Gain, Active Attacks Retreat,
--      Attack Ratio Slider 1%..100%, Quick Action Hotbar)
--   3. Top-Right Collapsible Leaderboard + Timer + Win % / Overtime / Doomsday Status
--   4. Bottom-Right Interactive Minimap + Clickable Event Feed + Actionable Alerts (Alliance & Nuke Siren!)
--   5. Circular Radial Menu (Attack, Boat, Build, Ally/Break, Inspect/Donate, Emoji, Upgrade, Delete)
--   6. Floating Build Menu (All 10 OpenFront Units with live dynamic Gold costs & armed placement mode)
--   7. Player Inspector & Donate Gold/Troops Modal + Emoji Wheel + Quick Chat + Victory/XP Ceremony Modal!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")

local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local MapRegistry = require(Shared:WaitForChild("Maps"):WaitForChild("MapRegistry"))
local Theme = require(Shared:WaitForChild("Theme"))

local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
local UiWidgets = require(script.Parent:WaitForChild("UiWidgets"))

local HudUI = {}
HudUI.__index = HudUI

local BUILD_ITEMS: { { unitType: string, icon: string, label: string, desc: string, countable: boolean } } = {
	{ unitType = "City", icon = "🏙️", label = "City", desc = "+250K Max Troops", countable = true },
	{ unitType = "Port", icon = "⚓", label = "Port", desc = "Coastal Trade Ships", countable = true },
	{ unitType = "Factory", icon = "🏭", label = "Factory", desc = "Railroads & Gold Trains", countable = true },
	{ unitType = "DefensePost", icon = "🛡️", label = "Defense Post", desc = "5x Border Defense", countable = true },
	{ unitType = "Warship", icon = "🚢", label = "Warship", desc = "Sinks Boats & Pirates Gold", countable = true },
	{ unitType = "MissileSilo", icon = "🚀", label = "Missile Silo", desc = "Launches Nukes & MIRVs", countable = true },
	{ unitType = "SAMLauncher", icon = "📡", label = "SAM Launcher", desc = "Intercepts Nukes", countable = true },
	{ unitType = "AtomBomb", icon = "☢️", label = "Atom Bomb", desc = "Tactical Nuclear Strike", countable = false },
	{ unitType = "HydrogenBomb", icon = "💥", label = "Hydrogen Bomb", desc = "Massive 90-Tile Blast", countable = false },
	{ unitType = "MIRV", icon = "☄️", label = "MIRV", desc = "Carpet Warheads Over Empire", countable = false },
}

export type HudInstance = typeof(setmetatable({} :: any, HudUI))

function HudUI.new(parentGui: ScreenGui, camera: any, mapCanvas: any, callbacks: {
	onSendIntent: (intent: string, payload: any) -> (),
	onExitToMenu: () -> (),
}): HudInstance
	local self = setmetatable({}, HudUI) :: any
	self.camera = camera
	self.canvas = mapCanvas
	self.callbacks = callbacks
	self.attackRatio = 0.25
	self.boatModeArmed = false
	self.leaderboardOpen = true
	self.mySmallId = 0
	self.latestState = nil :: any
	self.lastGold = -1
	self.seenAlertIds = {} :: { [number]: boolean }
	self.inspectedSmallId = nil :: number?

	local root = Instance.new("Frame")
	root.Name = "InGameHUD"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 15
	root.Parent = parentGui
	self.root = root

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveUIScale"
	uiScale.Scale = 1
	uiScale.Parent = root
	self.uiScale = uiScale

	-- Fullscreen modal backdrop scrim so Build / Inspector / Victory modals NEVER collide with background map text!
	local modalScrim = Instance.new("TextButton")
	modalScrim.Name = "HudModalScrim"
	modalScrim.Size = UDim2.fromScale(1, 1)
	modalScrim.BackgroundColor3 = Color3.fromRGB(4, 9, 20)
	modalScrim.BackgroundTransparency = 0.36
	modalScrim.BorderSizePixel = 0
	modalScrim.Text = ""
	modalScrim.AutoButtonColor = false
	modalScrim.Visible = false
	modalScrim.ZIndex = 33
	modalScrim.Parent = root
	self.modalScrim = modalScrim
	modalScrim.Activated:Connect(function()
		self.buildPopup.Visible = false
		self.inspectorModal.Visible = false
		self.emojiPopup.Visible = false
		self.chatPopup.Visible = false
		self.radialRoot.Visible = false
		if not self.resultModal.Visible then
			modalScrim.Visible = false
		end
	end)

	self:_BuildTopBanners()
	self:_BuildControlPanel()
	self:_BuildLeaderboard()
	self:_BuildMinimapAndFeed()
	self:_BuildRadialMenu()
	self:_BuildMenuPopup()
	self:_BuildPlayerInspectorModal()
	self:_BuildEmojiAndChatPopups()
	self:_BuildResultModal()

	return self
end

function HudUI:_BuildTopBanners()
	-- Spawn Phase Banner
	local spawnBanner = Instance.new("Frame")
	spawnBanner.AnchorPoint = Vector2.new(0.5, 0)
	spawnBanner.Position = UDim2.new(0.5, 0, 0, 14)
	spawnBanner.Size = UDim2.fromOffset(470, 56)
	spawnBanner.BackgroundColor3 = Color3.fromRGB(24, 32, 48)
	spawnBanner.BackgroundTransparency = 0.08
	spawnBanner.BorderSizePixel = 0
	spawnBanner.Visible = false
	spawnBanner.ZIndex = 20
	UiWidgets.AddCorner(spawnBanner, 10)
	UiWidgets.AddStroke(spawnBanner, Color3.fromRGB(250, 204, 21), 2, 0.15)
	spawnBanner.Parent = self.root
	self.spawnBanner = spawnBanner

	local spawnLbl = Instance.new("TextLabel")
	spawnLbl.Position = UDim2.fromOffset(14, 6)
	spawnLbl.Size = UDim2.new(1, -28, 1, -12)
	spawnLbl.BackgroundTransparency = 1
	spawnLbl.Font = Enum.Font.GothamBlack
	spawnLbl.TextSize = 15
	spawnLbl.TextWrapped = true
	spawnLbl.TextColor3 = Color3.fromRGB(254, 240, 138)
	spawnLbl.Text = "📍 CLICK ANY LAND TO PICK YOUR SPAWN — Starting in 10.0s"
	spawnLbl.ZIndex = 21
	spawnLbl.Parent = spawnBanner
	self.spawnLbl = spawnLbl

	-- Armed Mode Indicator Pill (when placing a building/nuke or launching a Boat!)
	local armedPill = Instance.new("Frame")
	armedPill.AnchorPoint = Vector2.new(0.5, 0)
	armedPill.Position = UDim2.new(0.5, 0, 0, 14)
	armedPill.Size = UDim2.fromOffset(430, 40)
	armedPill.BackgroundColor3 = Color3.fromRGB(124, 45, 18)
	armedPill.BorderSizePixel = 0
	armedPill.Visible = false
	armedPill.ZIndex = 22
	UiWidgets.AddCorner(armedPill, 99)
	UiWidgets.AddStroke(armedPill, Color3.fromRGB(251, 191, 36), 2, 0.1)
	armedPill.Parent = self.root
	self.armedPill = armedPill

	local armedTxt = Instance.new("TextLabel")
	armedTxt.Position = UDim2.fromOffset(16, 0)
	armedTxt.Size = UDim2.new(1, -106, 1, 0)
	armedTxt.BackgroundTransparency = 1
	armedTxt.Font = Enum.Font.GothamBold
	armedTxt.TextSize = 13
	armedTxt.TextXAlignment = Enum.TextXAlignment.Left
	armedTxt.TextColor3 = Color3.new(1, 1, 1)
	armedTxt.ZIndex = 23
	armedTxt.Parent = armedPill
	self.armedTxt = armedTxt

	local cancelArmedBtn = UiWidgets.MakeButton(
		armedPill,
		"✕ Cancel",
		Theme.UI.AccentRed,
		UDim2.fromOffset(78, 28),
		UDim2.new(1, -86, 0.5, -14)
	)
	cancelArmedBtn.ZIndex = 23
	cancelArmedBtn.Activated:Connect(function()
		self:ClearArmedModes()
	end)
end

function HudUI:ClearArmedModes()
	self.canvas.armedBuildType = nil
	self.boatModeArmed = false
	self.canvas.selectedWarshipId = nil
	self.armedPill.Visible = false
end

function HudUI:ArmBuildUnit(unitType: string)
	self.boatModeArmed = false
	self.canvas.selectedWarshipId = nil
	self.canvas.armedBuildType = unitType
	self.armedTxt.Text = "🏗️ Click map to place/launch " .. unitType .. "  (Esc to cancel)"
	self.armedPill.Visible = true
end

function HudUI:ArmBoatMode()
	self.canvas.armedBuildType = nil
	self.canvas.selectedWarshipId = nil
	self.boatModeArmed = true
	self.armedTxt.Text = "⛴️ BOAT INVASION: Click target coast/island!"
	self.armedPill.Visible = true
end

function HudUI:_BuildControlPanel()
	local panel = Instance.new("Frame")
	panel.Name = "ControlPanel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 14, 1, -14)
	panel.Size = UDim2.fromOffset(356, 168)
	panel.BackgroundColor3 = Theme.UI.BgPanel
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.ZIndex = 20
	UiWidgets.AddCorner(panel, 12)
	UiWidgets.AddStroke(panel, Theme.UI.Border, 1.5, 0.3)
	panel.Parent = self.root
	self.controlPanel = panel

	-- Row 1: Troops + Growth Rate
	local troopLbl = Instance.new("TextLabel")
	troopLbl.Position = UDim2.fromOffset(12, 8)
	troopLbl.Size = UDim2.fromOffset(226, 24)
	troopLbl.BackgroundTransparency = 1
	troopLbl.Font = Enum.Font.GothamBlack
	troopLbl.TextSize = 15
	troopLbl.TextTruncate = Enum.TextTruncate.AtEnd
	troopLbl.TextWrapped = false
	troopLbl.TextXAlignment = Enum.TextXAlignment.Left
	troopLbl.TextColor3 = Color3.new(1, 1, 1)
	troopLbl.Text = "🪖 25.0K / 100K"
	troopLbl.ZIndex = 21
	troopLbl.Parent = panel
	self.troopLbl = troopLbl

	local rateLbl = Instance.new("TextLabel")
	rateLbl.Position = UDim2.fromOffset(242, 8)
	rateLbl.Size = UDim2.fromOffset(102, 24)
	rateLbl.BackgroundTransparency = 1
	rateLbl.Font = Enum.Font.GothamBold
	rateLbl.TextSize = 13
	rateLbl.TextTruncate = Enum.TextTruncate.AtEnd
	rateLbl.TextWrapped = false
	rateLbl.TextXAlignment = Enum.TextXAlignment.Right
	rateLbl.TextColor3 = Color3.fromRGB(74, 222, 128)
	rateLbl.Text = "+420/s"
	rateLbl.ZIndex = 21
	rateLbl.Parent = panel
	self.rateLbl = rateLbl

	-- Row 2: Gold + Outgoing Attacks
	local goldLbl = Instance.new("TextLabel")
	goldLbl.Position = UDim2.fromOffset(12, 34)
	goldLbl.Size = UDim2.fromOffset(186, 22)
	goldLbl.BackgroundTransparency = 1
	goldLbl.Font = Enum.Font.GothamBlack
	goldLbl.TextSize = 15
	goldLbl.TextTruncate = Enum.TextTruncate.AtEnd
	goldLbl.TextWrapped = false
	goldLbl.TextXAlignment = Enum.TextXAlignment.Left
	goldLbl.TextColor3 = Color3.fromRGB(250, 204, 21)
	goldLbl.Text = "💰 0"
	goldLbl.ZIndex = 21
	goldLbl.Parent = panel
	self.goldLbl = goldLbl

	local atkStatusBtn = UiWidgets.MakeButton(
		panel,
		"⚔️ Idle",
		Color3.fromRGB(51, 65, 85),
		UDim2.fromOffset(142, 24),
		UDim2.fromOffset(202, 33)
	)
	atkStatusBtn.TextSize = 11
	atkStatusBtn.ZIndex = 21
	atkStatusBtn.Activated:Connect(function()
		SoundFX.Play("click")
		self.callbacks.onSendIntent("Retreat", {})
	end)
	self.atkStatusBtn = atkStatusBtn

	-- Row 3: Interactive Attack Ratio Slider
	local ratioTitle = Instance.new("TextLabel")
	ratioTitle.Position = UDim2.fromOffset(12, 64)
	ratioTitle.Size = UDim2.fromOffset(198, 18)
	ratioTitle.BackgroundTransparency = 1
	ratioTitle.Font = Enum.Font.GothamBold
	ratioTitle.TextSize = 12
	ratioTitle.TextTruncate = Enum.TextTruncate.AtEnd
	ratioTitle.TextWrapped = false
	ratioTitle.TextXAlignment = Enum.TextXAlignment.Left
	ratioTitle.TextColor3 = Theme.UI.TextMuted
	ratioTitle.Text = "Attack Ratio: 25%"
	ratioTitle.ZIndex = 21
	ratioTitle.Parent = panel
	self.ratioTitle = ratioTitle

	local minusBtn = UiWidgets.MakeButton(panel, "-10%", Theme.UI.BgCard, UDim2.fromOffset(58, 20), UDim2.fromOffset(220, 63))
	minusBtn.TextSize = 11
	minusBtn.ZIndex = 21
	local plusBtn = UiWidgets.MakeButton(panel, "+10%", Theme.UI.BgCard, UDim2.fromOffset(58, 20), UDim2.fromOffset(286, 63))
	plusBtn.TextSize = 11
	plusBtn.ZIndex = 21

	local sliderTrack = Instance.new("TextButton")
	sliderTrack.Position = UDim2.fromOffset(12, 88)
	sliderTrack.Size = UDim2.new(1, -24, 0, 16)
	sliderTrack.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
	sliderTrack.BorderSizePixel = 0
	sliderTrack.Text = ""
	sliderTrack.AutoButtonColor = false
	sliderTrack.ZIndex = 21
	UiWidgets.AddCorner(sliderTrack, 99)
	sliderTrack.Parent = panel

	local sliderFill = Instance.new("Frame")
	sliderFill.Size = UDim2.fromScale(0.25, 1)
	sliderFill.BackgroundColor3 = Theme.UI.AccentRed
	sliderFill.BorderSizePixel = 0
	sliderFill.ZIndex = 22
	UiWidgets.AddCorner(sliderFill, 99)
	sliderFill.Parent = sliderTrack
	self.sliderFill = sliderFill

	sliderTrack.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			local rel = (inp.Position.X - sliderTrack.AbsolutePosition.X) / math.max(1, sliderTrack.AbsoluteSize.X)
			self:SetAttackRatio(rel)
		end
	end)
	minusBtn.Activated:Connect(function()
		self:SetAttackRatio(self.attackRatio - 0.10)
	end)
	plusBtn.Activated:Connect(function()
		self:SetAttackRatio(self.attackRatio + 0.10)
	end)

	-- Row 4: Quick Hotbar Buttons
	local hotbar = Instance.new("Frame")
	hotbar.Position = UDim2.fromOffset(12, 114)
	hotbar.Size = UDim2.new(1, -24, 0, 42)
	hotbar.BackgroundTransparency = 1
	hotbar.ZIndex = 21
	hotbar.Parent = panel

	local hbLayout = Instance.new("UIGridLayout")
	hbLayout.CellSize = UDim2.fromOffset(51, 40)
	hbLayout.CellPadding = UDim2.fromOffset(5, 0)
	hbLayout.Parent = hotbar

	local actions = {
		{ txt = "🏗️\nBuild", col = Color3.fromRGB(180, 120, 20), fn = function()
			self:ToggleBuildMenu(nil, nil)
		end },
		{ txt = "⛴️\nBoat", col = Color3.fromRGB(30, 105, 175), fn = function()
			self:ArmBoatMode()
		end },
		{ txt = "🏳️\nRetreat", col = Color3.fromRGB(153, 27, 27), fn = function()
			self.callbacks.onSendIntent("Retreat", {})
			self.callbacks.onSendIntent("RetreatBoats", {})
		end },
		{ txt = "😊\nEmoji", col = Color3.fromRGB(51, 65, 85), fn = function()
			self.emojiPopup.Visible = not self.emojiPopup.Visible
			self.chatPopup.Visible = false
		end },
		{ txt = "💬\nChat", col = Color3.fromRGB(51, 65, 85), fn = function()
			self.chatPopup.Visible = not self.chatPopup.Visible
			self.emojiPopup.Visible = false
		end },
		{ txt = "👁️\nAlt", col = Color3.fromRGB(51, 65, 85), fn = function()
			self.canvas.altView = not self.canvas.altView
			self.canvas:MarkAllDirty()
		end },
	}
	for _, act in ipairs(actions) do
		local b = UiWidgets.MakeButton(hotbar, act.txt, act.col, UDim2.fromOffset(47, 40), nil)
		b.TextSize = 10
		b.ZIndex = 22
		b.Activated:Connect(function()
			SoundFX.Play("click")
			act.fn()
		end)
	end
end

function HudUI:SetAttackRatio(val: number)
	self.attackRatio = math.clamp(math.floor(val * 100 + 0.5) / 100, 0.01, 1.0)
	self.ratioTitle.Text = string.format("Attack Ratio: %d%%", math.floor(self.attackRatio * 100 + 0.5))
	self.sliderFill.Size = UDim2.fromScale(self.attackRatio, 1)
end

function HudUI:_BuildLeaderboard()
	local box = Instance.new("Frame")
	box.Name = "LeaderboardPanel"
	box.AnchorPoint = Vector2.new(1, 0)
	box.Position = UDim2.new(1, -14, 0, 14)
	box.Size = UDim2.fromOffset(296, 254)
	box.BackgroundColor3 = Theme.UI.BgPanel
	box.BackgroundTransparency = 0.10
	box.BorderSizePixel = 0
	box.ZIndex = 20
	UiWidgets.AddCorner(box, 10)
	UiWidgets.AddStroke(box, Theme.UI.Border, 1, 0.35)
	box.Parent = self.root
	self.lbBox = box

	local headerBtn = Instance.new("TextButton")
	headerBtn.Position = UDim2.fromOffset(10, 6)
	headerBtn.Size = UDim2.fromOffset(200, 26)
	headerBtn.BackgroundTransparency = 1
	headerBtn.Font = Enum.Font.GothamBlack
	headerBtn.TextSize = 12
	headerBtn.TextXAlignment = Enum.TextXAlignment.Left
	headerBtn.TextColor3 = Color3.new(1, 1, 1)
	headerBtn.Text = "⏱️ 00:00  •  Win: 80% ▾"
	headerBtn.ZIndex = 21
	headerBtn.Parent = box
	self.lbHeaderBtn = headerBtn

	local menuBtn = UiWidgets.MakeButton(
		box,
		"Menu",
		Color3.fromRGB(71, 85, 105),
		UDim2.fromOffset(66, 24),
		UDim2.new(1, -76, 0, 7)
	)
	menuBtn.TextSize = 11
	menuBtn.ZIndex = 21
	menuBtn.Activated:Connect(function()
		SoundFX.Play("click")
		self.callbacks.onExitToMenu()
	end)

	local rowsContainer = Instance.new("Frame")
	rowsContainer.Position = UDim2.fromOffset(8, 36)
	rowsContainer.Size = UDim2.new(1, -16, 1, -44)
	rowsContainer.BackgroundTransparency = 1
	rowsContainer.ZIndex = 21
	rowsContainer.Parent = box
	self.lbRowsContainer = rowsContainer

	local rLayout = Instance.new("UIListLayout")
	rLayout.Padding = UDim.new(0, 3)
	rLayout.Parent = rowsContainer

	self.lbRowPool = {} :: { any }
	for i = 1, 9 do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 21)
		row.BackgroundColor3 = Theme.UI.BgCard
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel = 0
		row.Text = ""
		row.Visible = false
		row.ZIndex = 22
		UiWidgets.AddCorner(row, 5)
		row.Parent = rowsContainer

		local swatch = Instance.new("Frame")
		swatch.Position = UDim2.fromOffset(5, 4)
		swatch.Size = UDim2.fromOffset(8, 13)
		swatch.BorderSizePixel = 0
		swatch.ZIndex = 23
		UiWidgets.AddCorner(swatch, 2)
		swatch.Parent = row

		local txt = Instance.new("TextLabel")
		txt.Position = UDim2.fromOffset(18, 0)
		txt.Size = UDim2.new(1, -124, 1, 0)
		txt.BackgroundTransparency = 1
		txt.Font = Enum.Font.GothamBold
		txt.TextSize = 11
		txt.TextTruncate = Enum.TextTruncate.AtEnd
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextColor3 = Color3.new(1, 1, 1)
		txt.ZIndex = 23
		txt.Parent = row

		local stats = Instance.new("TextLabel")
		stats.AnchorPoint = Vector2.new(1, 0)
		stats.Position = UDim2.new(1, -5, 0, 0)
		stats.Size = UDim2.fromOffset(104, 21)
		stats.BackgroundTransparency = 1
		stats.Font = Enum.Font.GothamMedium
		stats.TextSize = 10
		stats.TextXAlignment = Enum.TextXAlignment.Right
		stats.TextColor3 = Color3.fromRGB(203, 213, 225)
		stats.ZIndex = 23
		stats.Parent = row

		local boundSmallId = 0
		row.Activated:Connect(function()
			if boundSmallId > 0 then
				SoundFX.Play("click")
				self:OpenPlayerInspector(boundSmallId)
			end
		end)

		self.lbRowPool[i] = {
			row = row,
			swatch = swatch,
			txt = txt,
			stats = stats,
			setTarget = function(sid: number)
				boundSmallId = sid
			end,
		}
	end

	headerBtn.Activated:Connect(function()
		self.leaderboardOpen = not self.leaderboardOpen
		rowsContainer.Visible = self.leaderboardOpen
		box.Size = if self.leaderboardOpen then UDim2.fromOffset(296, 254) else UDim2.fromOffset(296, 38)
	end)
end

function HudUI:_BuildMinimapAndFeed()
	-- Bottom-Right Interactive Minimap
	local miniCard = Instance.new("Frame")
	miniCard.Name = "MinimapCard"
	miniCard.AnchorPoint = Vector2.new(1, 1)
	miniCard.Position = UDim2.new(1, -14, 1, -14)
	miniCard.Size = UDim2.fromOffset(210, 124)
	miniCard.BackgroundColor3 = Theme.UI.BgPanel
	miniCard.BorderSizePixel = 0
	miniCard.ZIndex = 20
	UiWidgets.AddCorner(miniCard, 9)
	UiWidgets.AddStroke(miniCard, Theme.UI.Border, 1.5, 0.25)
	miniCard.Parent = self.root
	self.miniCard = miniCard

	local miniMapPreview = Instance.new("Frame")
	miniMapPreview.Position = UDim2.fromOffset(5, 5)
	miniMapPreview.Size = UDim2.new(1, -10, 1, -10)
	miniMapPreview.ZIndex = 21
	miniMapPreview.Parent = miniCard
	self.miniMapPreview = miniMapPreview
	self.lastMiniMapId = ""

	local miniDotsLayer = Instance.new("Frame")
	miniDotsLayer.Position = UDim2.fromOffset(5, 5)
	miniDotsLayer.Size = UDim2.new(1, -10, 1, -10)
	miniDotsLayer.BackgroundTransparency = 1
	miniDotsLayer.ClipsDescendants = true
	miniDotsLayer.ZIndex = 22
	miniDotsLayer.Parent = miniCard
	self.miniDotsLayer = miniDotsLayer
	self.miniDots = {} :: { [number]: Frame }

	local camRect = Instance.new("Frame")
	camRect.BackgroundTransparency = 1
	camRect.BorderSizePixel = 0
	camRect.ZIndex = 23
	UiWidgets.AddStroke(camRect, Color3.new(1, 1, 1), 1.5, 0.05)
	camRect.Parent = miniDotsLayer
	self.miniCamRect = camRect

	local miniHitbox = Instance.new("TextButton")
	miniHitbox.Size = UDim2.fromScale(1, 1)
	miniHitbox.BackgroundTransparency = 1
	miniHitbox.Text = ""
	miniHitbox.ZIndex = 24
	miniHitbox.Parent = miniDotsLayer

	local function jumpFromMiniInput(pos: Vector3)
		if self.canvas.map == nil then
			return
		end
		local rx = math.clamp((pos.X - miniDotsLayer.AbsolutePosition.X) / math.max(1, miniDotsLayer.AbsoluteSize.X), 0, 1)
		local ry = math.clamp((pos.Y - miniDotsLayer.AbsolutePosition.Y) / math.max(1, miniDotsLayer.AbsoluteSize.Y), 0, 1)
		self.camera:FocusOn(rx * self.canvas.map.width, ry * self.canvas.map.height, nil)
	end

	local draggingMini = false
	miniHitbox.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			draggingMini = true
			jumpFromMiniInput(inp.Position)
		end
	end)
	miniHitbox.InputChanged:Connect(function(inp)
		if draggingMini and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
			jumpFromMiniInput(inp.Position)
		end
	end)
	miniHitbox.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			draggingMini = false
		end
	end)

	-- Event Feed right above Minimap
	local feedBox = Instance.new("Frame")
	feedBox.AnchorPoint = Vector2.new(1, 1)
	feedBox.Position = UDim2.new(1, -14, 1, -146)
	feedBox.Size = UDim2.fromOffset(296, 128)
	feedBox.BackgroundTransparency = 1
	feedBox.ZIndex = 20
	feedBox.Parent = self.root

	local fLayout = Instance.new("UIListLayout")
	fLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	fLayout.Padding = UDim.new(0, 4)
	fLayout.Parent = feedBox

	self.feedItems = {} :: { TextButton }
	self.feedCoords = {} :: { { x: number?, y: number? } }
	for i = 1, 5 do
		local fb = Instance.new("TextButton")
		fb.Size = UDim2.new(1, 0, 0, 22)
		fb.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
		fb.BackgroundTransparency = 0.22
		fb.BorderSizePixel = 0
		fb.Font = Enum.Font.GothamBold
		fb.TextSize = 11
		fb.TextTruncate = Enum.TextTruncate.AtEnd
		fb.TextXAlignment = Enum.TextXAlignment.Left
		fb.TextColor3 = Color3.new(1, 1, 1)
		fb.Visible = false
		fb.ZIndex = 21
		UiWidgets.AddCorner(fb, 5)
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 8)
		p.PaddingRight = UDim.new(0, 8)
		p.Parent = fb
		fb.Parent = feedBox
		self.feedCoords[i] = { x = nil, y = nil }
		fb.Activated:Connect(function()
			local c = self.feedCoords[i]
			if c.x ~= nil and c.y ~= nil then
				self.camera:FocusOn(c.x, c.y, math.max(self.camera.scale, 6))
			end
		end)
		self.feedItems[i] = fb
	end

	-- Actionable Alerts Stack (Top-Left incoming Nuke Siren, Alliance Requests & Extension Prompts!)
	local alertsBox = Instance.new("Frame")
	alertsBox.Position = UDim2.fromOffset(14, 14)
	alertsBox.Size = UDim2.fromOffset(310, 210)
	alertsBox.BackgroundTransparency = 1
	alertsBox.ZIndex = 22
	alertsBox.Parent = self.root
	self.alertsBox = alertsBox

	local aLayout = Instance.new("UIListLayout")
	aLayout.Padding = UDim.new(0, 6)
	aLayout.Parent = alertsBox
end

function HudUI:_BuildRadialMenu()
	local ring = Instance.new("Frame")
	ring.Name = "RadialMenu"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(196, 196)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.ZIndex = 32
	ring.Parent = self.root
	self.radialRoot = ring

	local centerBtn = UiWidgets.MakeButton(
		ring,
		"✕",
		Color3.fromRGB(30, 41, 59),
		UDim2.fromOffset(48, 48),
		UDim2.fromScale(0.5, 0.5)
	)
	centerBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	centerBtn.ZIndex = 34
	UiWidgets.AddCorner(centerBtn, 99)
	centerBtn.Activated:Connect(function()
		ring.Visible = false
	end)

	self.radialSpokes = {} :: { TextButton }
	for i = 1, 6 do
		local b = UiWidgets.MakeButton(ring, "", Theme.UI.BgCard, UDim2.fromOffset(58, 58), UDim2.fromScale(0.5, 0.5))
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.TextSize = 11
		b.ZIndex = 33
		UiWidgets.AddCorner(b, 99)
		self.radialSpokes[i] = b
	end
	self.radialCallbacks = {} :: { [number]: () -> () }
	for i = 1, 6 do
		self.radialSpokes[i].Activated:Connect(function()
			local fn = self.radialCallbacks[i]
			ring.Visible = false
			if fn ~= nil then
				SoundFX.Play("click")
				fn()
			end
		end)
	end
end

-- Open Circular OpenFront Radial Menu right at (screenX, screenY) for tile (tileX, tileY)!
function HudUI:OpenRadialMenu(screenX: number, screenY: number, tileX: number, tileY: number)
	local st = self.latestState
	if st == nil or st.inSpawnPhase or self.canvas.map == nil then
		return
	end
	local map = self.canvas.map
	local ref = tileY * map.width + tileX
	local targetOwnerId = MapCodec_GetOwnerSafe(map, ref)
	local targetPlayer = self.canvas.playersById[targetOwnerId]
	local me = self.canvas.playersById[self.mySmallId]

	-- Check if user right-clicked one of their own structures!
	local myStruct: any = nil
	for _, u in ipairs(st.units or {}) do
		if u.ownerSmallId == self.mySmallId and math.abs(u.x - tileX) <= 4 and math.abs(u.y - tileY) <= 4 then
			myStruct = u
			break
		end
	end

	local items: { { label: string, color: Color3, fn: () -> () } } = {}

	if targetOwnerId ~= self.mySmallId and MapCodec_IsLandSafe(map, ref) then
		table.insert(items, {
			label = "⚔️\nAttack",
			color = Color3.fromRGB(220, 38, 38),
			fn = function()
				SoundFX.Play("attack")
				self.callbacks.onSendIntent("AttackLand", { targetSmallId = targetOwnerId, ratio = self.attackRatio })
			end,
		})
	end

	table.insert(items, {
		label = "⛴️\nBoat",
		color = Color3.fromRGB(37, 99, 235),
		fn = function()
			SoundFX.Play("boat")
			self.callbacks.onSendIntent("BoatAttack", { x = tileX, y = tileY, ratio = self.attackRatio })
		end,
	})

	table.insert(items, {
		label = "🏗️\nBuild",
		color = Color3.fromRGB(202, 138, 4),
		fn = function()
			self:ToggleBuildMenu(tileX, tileY)
		end,
	})

	if targetPlayer ~= nil and targetOwnerId ~= self.mySmallId then
		local isAlly = self.canvas.friendlySet[targetOwnerId] == true
		table.insert(items, {
			label = if isAlly then "💀\nBetray" else "🤝\nAlly",
			color = if isAlly then Color3.fromRGB(185, 28, 28) else Color3.fromRGB(22, 163, 74),
			fn = function()
				if isAlly then
					self.callbacks.onSendIntent("BreakAlliance", { targetSmallId = targetOwnerId })
				else
					SoundFX.Play("alliance")
					self.callbacks.onSendIntent("AllianceRequest", { targetSmallId = targetOwnerId })
				end
			end,
		})
		table.insert(items, {
			label = "🔍\nInfo",
			color = Color3.fromRGB(71, 85, 105),
			fn = function()
				self:OpenPlayerInspector(targetOwnerId)
			end,
		})
	elseif myStruct ~= nil then
		table.insert(items, {
			label = "⬆️\nUpgrade",
			color = Color3.fromRGB(22, 163, 74),
			fn = function()
				self.callbacks.onSendIntent("UpgradeStructure", { unitId = myStruct.id })
			end,
		})
		table.insert(items, {
			label = "🗑️\nDelete",
			color = Color3.fromRGB(185, 28, 28),
			fn = function()
				self.callbacks.onSendIntent("DeleteStructure", { unitId = myStruct.id })
			end,
		})
	else
		table.insert(items, {
			label = "😊\nEmoji",
			color = Color3.fromRGB(124, 58, 237),
			fn = function()
				self.emojiPopup.Visible = true
			end,
		})
	end

	local count = #items
	local radius = 68
	for i = 1, 6 do
		local spoke = self.radialSpokes[i]
		if i <= count then
			local angle = -math.pi * 0.5 + ((i - 1) / count) * math.pi * 2
			spoke.Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
			spoke.Text = items[i].label
			spoke.BackgroundColor3 = items[i].color
			spoke.Visible = true
			self.radialCallbacks[i] = items[i].fn
		else
			spoke.Visible = false
			self.radialCallbacks[i] = nil
		end
	end

	local cx = math.clamp(screenX, 105, self.camera.viewW - 105)
	local cy = math.clamp(screenY, 105, self.camera.viewH - 105)
	self.radialRoot.Position = UDim2.fromOffset(cx, cy)
	self.radialRoot.Visible = true
	local _ = me
end

function MapCodec_GetOwnerSafe(map: any, ref: number): number
	if ref < 0 or ref >= map.size then
		return 0
	end
	return buffer.readu16(map.owner, ref * 2)
end

function MapCodec_IsLandSafe(map: any, ref: number): boolean
	if ref < 0 or ref >= map.size then
		return false
	end
	return bit32.band(buffer.readu8(map.terrain, ref), 0x80) ~= 0
end

function HudUI:_BuildMenuPopup()
	local popup = Instance.new("Frame")
	popup.Name = "BuildMenuModal"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.5)
	popup.Size = UDim2.fromOffset(556, 286)
	popup.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
	popup.BackgroundTransparency = 0.04
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.ZIndex = 34
	UiWidgets.AddCorner(popup, 12)
	UiWidgets.AddStroke(popup, Color3.fromRGB(234, 179, 8), 2, 0.25)
	popup.Parent = self.root
	self.buildPopup = popup
	self.buildTargetTileX = nil :: number?
	self.buildTargetTileY = nil :: number?

	local hdr = Instance.new("TextLabel")
	hdr.Position = UDim2.fromOffset(16, 10)
	hdr.Size = UDim2.fromOffset(420, 26)
	hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBlack
	hdr.TextSize = 16
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.TextColor3 = Color3.new(1, 1, 1)
	hdr.Text = "🏗️ BUILD STRUCTURES, SHIPS & NUCLEAR ARSENAL"
	hdr.ZIndex = 35
	hdr.Parent = popup

	local closeBtn = UiWidgets.MakeButton(
		popup,
		"✕",
		Theme.UI.AccentRed,
		UDim2.fromOffset(34, 28),
		UDim2.new(1, -46, 0, 10)
	)
	closeBtn.ZIndex = 35
	closeBtn.Activated:Connect(function()
		popup.Visible = false
		self.modalScrim.Visible = self.resultModal.Visible
	end)

	local gridHolder = Instance.new("Frame")
	gridHolder.Position = UDim2.fromOffset(14, 46)
	gridHolder.Size = UDim2.new(1, -28, 1, -58)
	gridHolder.BackgroundTransparency = 1
	gridHolder.ZIndex = 35
	gridHolder.Parent = popup

	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(100, 108)
	gl.CellPadding = UDim2.fromOffset(7, 8)
	gl.Parent = gridHolder

	self.buildCards = {} :: { any }
	for idx, info in ipairs(BUILD_ITEMS) do
		local card = Instance.new("TextButton")
		card.BackgroundColor3 = Theme.UI.BgCard
		card.BorderSizePixel = 0
		card.Text = ""
		card.ZIndex = 36
		UiWidgets.AddCorner(card, 9)
		local stroke = UiWidgets.AddStroke(card, Theme.UI.Border, 1.5, 0.25)
		card.Parent = gridHolder

		local icon = Instance.new("TextLabel")
		icon.Position = UDim2.fromOffset(0, 6)
		icon.Size = UDim2.new(1, 0, 0, 28)
		icon.BackgroundTransparency = 1
		icon.TextScaled = true
		icon.Text = info.icon
		icon.ZIndex = 37
		icon.Parent = card

		local nm = Instance.new("TextLabel")
		nm.Position = UDim2.fromOffset(4, 36)
		nm.Size = UDim2.new(1, -8, 0, 28)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 11
		nm.TextWrapped = true
		nm.TextColor3 = Color3.new(1, 1, 1)
		nm.Text = info.label
		nm.ZIndex = 37
		nm.Parent = card

		local costLbl = Instance.new("TextLabel")
		costLbl.Position = UDim2.fromOffset(4, 68)
		costLbl.Size = UDim2.new(1, -8, 0, 18)
		costLbl.BackgroundTransparency = 1
		costLbl.Font = Enum.Font.GothamBlack
		costLbl.TextSize = 11
		costLbl.TextColor3 = Theme.UI.AccentGold
		costLbl.Text = "💰 125K"
		costLbl.ZIndex = 37
		costLbl.Parent = card

		local cntLbl = Instance.new("TextLabel")
		cntLbl.Position = UDim2.fromOffset(4, 86)
		cntLbl.Size = UDim2.new(1, -8, 0, 16)
		cntLbl.BackgroundTransparency = 1
		cntLbl.Font = Enum.Font.Gotham
		cntLbl.TextSize = 10
		cntLbl.TextColor3 = Theme.UI.TextMuted
		cntLbl.Text = ""
		cntLbl.ZIndex = 37
		cntLbl.Parent = card

		card.Activated:Connect(function()
			popup.Visible = false
			if self.buildTargetTileX ~= nil and self.buildTargetTileY ~= nil then
				if info.unitType == "AtomBomb" or info.unitType == "HydrogenBomb" or info.unitType == "MIRV" then
					SoundFX.Play("launch")
				else
					SoundFX.Play("build")
				end
				self.callbacks.onSendIntent("BuildUnit", {
					unitType = info.unitType,
					x = self.buildTargetTileX,
					y = self.buildTargetTileY,
				})
			else
				SoundFX.Play("click")
				self:ArmBuildUnit(info.unitType)
			end
		end)

		self.buildCards[idx] = { info = info, card = card, stroke = stroke, costLbl = costLbl, cntLbl = cntLbl }
	end
end

function HudUI:ToggleBuildMenu(tileX: number?, tileY: number?)
	self.radialRoot.Visible = false
	self.inspectorModal.Visible = false
	self.emojiPopup.Visible = false
	self.chatPopup.Visible = false
	if self.buildPopup.Visible and tileX == nil then
		self.buildPopup.Visible = false
		self.modalScrim.Visible = self.resultModal.Visible
		return
	end
	self.buildTargetTileX = tileX
	self.buildTargetTileY = tileY
	self:_RefreshBuildCosts()
	self.buildPopup.Visible = true
	self.modalScrim.Visible = true
end

function HudUI:_RefreshBuildCosts()
	local st = self.latestState
	if st == nil then
		return
	end
	local me = self.canvas.playersById[self.mySmallId]
	local counts = if me ~= nil then (me.unitCounts or {}) else {}
	local myGold = if me ~= nil then (me.gold or 0) else 0
	local cfg = st.config or Config.DefaultGameConfig(true)

	for _, bc in ipairs(self.buildCards) do
		local c = Config.UnitCost(bc.info.unitType :: any, counts, st.mirvsLaunched or 0, cfg.infiniteGold == true, true)
		local canAfford = myGold >= c
		bc.costLbl.Text = "💰 " .. Format.Gold(c)
		bc.costLbl.TextColor3 = if canAfford then Theme.UI.AccentGold else Color3.fromRGB(248, 113, 113)
		bc.stroke.Color = if canAfford then Theme.UI.AccentGold else Theme.UI.Border
		bc.cntLbl.Text = if bc.info.countable
			then ("Owned: " .. tostring(counts[bc.info.unitType] or 0))
			else bc.info.desc
	end
end

function HudUI:_BuildPlayerInspectorModal()
	local modal = Instance.new("Frame")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(390, 310)
	modal.BackgroundColor3 = Theme.UI.BgDark
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 36
	UiWidgets.AddCorner(modal, 12)
	UiWidgets.AddStroke(modal, Theme.UI.AccentBlue, 2, 0.25)
	modal.Parent = self.root
	self.inspectorModal = modal

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.fromOffset(310, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 17
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.ZIndex = 37
	title.Parent = modal
	self.inspTitle = title

	local closeBtn = UiWidgets.MakeButton(
		modal,
		"✕",
		Theme.UI.AccentRed,
		UDim2.fromOffset(32, 26),
		UDim2.new(1, -44, 0, 12)
	)
	closeBtn.ZIndex = 37
	closeBtn.Activated:Connect(function()
		modal.Visible = false
		self.modalScrim.Visible = self.resultModal.Visible
	end)

	local info = Instance.new("TextLabel")
	info.Position = UDim2.fromOffset(16, 44)
	info.Size = UDim2.new(1, -32, 0, 44)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamMedium
	info.TextSize = 13
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextColor3 = Color3.fromRGB(203, 213, 225)
	info.ZIndex = 37
	info.Parent = modal
	self.inspInfo = info

	local actionsGrid = Instance.new("Frame")
	actionsGrid.Position = UDim2.fromOffset(16, 96)
	actionsGrid.Size = UDim2.new(1, -32, 0, 196)
	actionsGrid.BackgroundTransparency = 1
	actionsGrid.ZIndex = 37
	actionsGrid.Parent = modal

	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(172, 38)
	gl.CellPadding = UDim2.fromOffset(10, 8)
	gl.Parent = actionsGrid

	local function addAct(txt: string, col: Color3, fn: (target: any, me: any) -> ())
		local b = UiWidgets.MakeButton(actionsGrid, txt, col, UDim2.fromOffset(172, 38), nil)
		b.TextSize = 12
		b.ZIndex = 38
		b.Activated:Connect(function()
			local target = if self.inspectedSmallId then self.canvas.playersById[self.inspectedSmallId] else nil
			local me = self.canvas.playersById[self.mySmallId]
			if target ~= nil then
				SoundFX.Play("click")
				fn(target, me)
				modal.Visible = false
				self.modalScrim.Visible = self.resultModal.Visible
			end
		end)
		return b
	end

	addAct("🎯 Focus Camera", Theme.UI.BgCard, function(target)
		self.camera:FocusOn(target.labelX, target.labelY, math.max(self.camera.scale, 5.5))
	end)
	self.inspAllyBtn = addAct("🤝 Send Alliance", Theme.UI.AccentGreen, function(target)
		if self.canvas.friendlySet[target.smallId] then
			self.callbacks.onSendIntent("BreakAlliance", { targetSmallId = target.smallId })
		else
			self.callbacks.onSendIntent("AllianceRequest", { targetSmallId = target.smallId })
		end
	end)
	addAct("💰 Donate 25% Gold", Color3.fromRGB(180, 120, 20), function(target, me)
		if me ~= nil then
			self.callbacks.onSendIntent("Donate", { targetSmallId = target.smallId, kind = "gold", amount = math.floor(me.gold * 0.25) })
		end
	end)
	addAct("🪖 Donate 25% Troops", Theme.UI.AccentBlue, function(target, me)
		if me ~= nil then
			self.callbacks.onSendIntent("Donate", { targetSmallId = target.smallId, kind = "troops", amount = math.floor(me.troops * 0.25) })
		end
	end)
	addAct("🚫 Toggle Embargo", Theme.UI.AccentPurple, function(target)
		self.callbacks.onSendIntent("ToggleEmbargo", { targetSmallId = target.smallId })
	end)
	addAct("📍 Ping Target", Theme.UI.AccentRed, function(target)
		self.callbacks.onSendIntent("TargetPlayer", { targetSmallId = target.smallId })
	end)
	addAct("⚔️ Land Attack", Theme.UI.AccentRed, function(target)
		self.callbacks.onSendIntent("AttackLand", { targetSmallId = target.smallId, ratio = self.attackRatio })
	end)
	addAct("⛴️ Boat Invasion", Color3.fromRGB(30, 105, 175), function(target)
		self.callbacks.onSendIntent("BoatAttack", { x = target.labelX, y = target.labelY, ratio = self.attackRatio })
	end)
end

function HudUI:OpenPlayerInspector(smallId: number)
	local p = self.canvas.playersById[smallId]
	if p == nil then
		return
	end
	self.inspectedSmallId = smallId
	self.inspTitle.Text = p.name .. (if p.isTraitor then " 💀 [TRAITOR]" else "")
	local landPct = 0
	if self.canvas.map ~= nil then
		landPct = (p.tilesOwned / math.max(1, self.canvas.map.numLandTiles)) * 100
	end
	self.inspInfo.Text = string.format(
		"Type: %s  •  Land: %.1f%% (%d tiles)\nTroops: %s  •  Gold: %s",
		p.playerType,
		landPct,
		p.tilesOwned,
		Format.Troops(p.troops),
		Format.Gold(p.gold)
	)
	local isAlly = self.canvas.friendlySet[smallId] == true
	self.inspAllyBtn.Text = if isAlly then "💀 Break Alliance" else "🤝 Send Alliance"
	self.inspAllyBtn.BackgroundColor3 = if isAlly then Theme.UI.AccentRed else Theme.UI.AccentGreen
	self.radialRoot.Visible = false
	self.buildPopup.Visible = false
	self.emojiPopup.Visible = false
	self.chatPopup.Visible = false
	self.inspectorModal.Visible = true
	self.modalScrim.Visible = true
end

function HudUI:_BuildEmojiAndChatPopups()
	-- Emoji Grid Popup
	local ep = Instance.new("Frame")
	ep.AnchorPoint = Vector2.new(0, 1)
	ep.Position = UDim2.new(0, 14, 1, -188)
	ep.Size = UDim2.fromOffset(224, 176)
	ep.BackgroundColor3 = Theme.UI.BgDark
	ep.BorderSizePixel = 0
	ep.Visible = false
	ep.ZIndex = 34
	UiWidgets.AddCorner(ep, 10)
	UiWidgets.AddStroke(ep, Theme.UI.Border, 1.5, 0.25)
	ep.Parent = self.root
	self.emojiPopup = ep

	local egl = Instance.new("UIGridLayout")
	egl.CellSize = UDim2.fromOffset(48, 36)
	egl.CellPadding = UDim2.fromOffset(5, 5)
	egl.Parent = ep
	local epad = Instance.new("UIPadding")
	epad.PaddingTop = UDim.new(0, 8)
	epad.PaddingLeft = UDim.new(0, 8)
	epad.Parent = ep

	for _, em in ipairs(Config.Emojis) do
		local b = UiWidgets.MakeButton(ep, em, Theme.UI.BgCard, UDim2.fromOffset(48, 36), nil)
		b.TextSize = 18
		b.ZIndex = 35
		b.Activated:Connect(function()
			SoundFX.Play("click")
			ep.Visible = false
			self.callbacks.onSendIntent("SendEmoji", { emoji = em })
		end)
	end

	-- Quick Chat Popup
	local cp = Instance.new("Frame")
	cp.AnchorPoint = Vector2.new(0, 1)
	cp.Position = UDim2.new(0, 14, 1, -188)
	cp.Size = UDim2.fromOffset(256, 268)
	cp.BackgroundColor3 = Theme.UI.BgDark
	cp.BorderSizePixel = 0
	cp.Visible = false
	cp.ZIndex = 34
	UiWidgets.AddCorner(cp, 10)
	UiWidgets.AddStroke(cp, Theme.UI.Border, 1.5, 0.25)
	cp.Parent = self.root
	self.chatPopup = cp

	local cl = Instance.new("UIListLayout")
	cl.Padding = UDim.new(0, 5)
	cl.Parent = cp
	local cpad = Instance.new("UIPadding")
	cpad.PaddingTop = UDim.new(0, 8)
	cpad.PaddingLeft = UDim.new(0, 8)
	cpad.PaddingRight = UDim.new(0, 8)
	cpad.Parent = cp

	for _, qc in ipairs(Config.QuickChats) do
		local b = UiWidgets.MakeButton(cp, qc.text, Theme.HexToColor3(qc.color), UDim2.new(1, 0, 0, 27), nil)
		b.TextSize = 11
		b.ZIndex = 35
		b.Activated:Connect(function()
			SoundFX.Play("click")
			cp.Visible = false
			self.callbacks.onSendIntent("QuickChat", { id = qc.id })
		end)
	end
end

function HudUI:_BuildResultModal()
	local modal = Instance.new("Frame")
	modal.Name = "WinCeremonyModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(440, 270)
	modal.BackgroundColor3 = Theme.UI.BgDark
	modal.BackgroundTransparency = 0.04
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 42
	UiWidgets.AddCorner(modal, 14)
	self.resStroke = UiWidgets.AddStroke(modal, Theme.UI.AccentGold, 2.5, 0.1)
	modal.Parent = self.root
	self.resultModal = modal

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(20, 18)
	title.Size = UDim2.new(1, -40, 0, 36)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 26
	title.TextColor3 = Theme.UI.AccentGold
	title.Text = "🏆 VICTORY!"
	title.ZIndex = 43
	title.Parent = modal
	self.resTitle = title

	local body = Instance.new("TextLabel")
	body.Position = UDim2.fromOffset(24, 64)
	body.Size = UDim2.new(1, -48, 0, 122)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamBold
	body.TextSize = 14
	body.TextWrapped = true
	body.TextColor3 = Color3.fromRGB(226, 232, 240)
	body.ZIndex = 43
	body.Parent = modal
	self.resBody = body

	local specBtn = UiWidgets.MakeButton(
		modal,
		"👁️ Keep Spectating",
		Theme.UI.BgCard,
		UDim2.fromOffset(186, 42),
		UDim2.fromOffset(24, 206)
	)
	specBtn.ZIndex = 43
	specBtn.Activated:Connect(function()
		modal.Visible = false
		self.modalScrim.Visible = false
	end)

	local menuBtn = UiWidgets.MakeButton(
		modal,
		"🏠 Play Again / Lobby",
		Theme.UI.AccentBlue,
		UDim2.fromOffset(186, 42),
		UDim2.fromOffset(230, 206)
	)
	menuBtn.ZIndex = 43
	menuBtn.Activated:Connect(function()
		modal.Visible = false
		self.modalScrim.Visible = false
		self.callbacks.onExitToMenu()
	end)
end

function HudUI:ShowMatchResult(res: any)
	self.radialRoot.Visible = false
	self.buildPopup.Visible = false
	self.inspectorModal.Visible = false
	self.emojiPopup.Visible = false
	self.chatPopup.Visible = false
	if res.kind == "Victory" then
		SoundFX.Play("victory")
		self.resTitle.Text = "🏆 WORLD CONQUERED!"
		self.resTitle.TextColor3 = Theme.UI.AccentGold
		self.resStroke.Color = Theme.UI.AccentGold
	elseif res.kind == "Eliminated" then
		SoundFX.Play("alert")
		self.resTitle.Text = "💀 TERRITORY CONQUERED"
		self.resTitle.TextColor3 = Theme.UI.AccentRed
		self.resStroke.Color = Theme.UI.AccentRed
	else
		self.resTitle.Text = "🏁 MATCH FINISHED — " .. tostring(res.winnerName or "Winner")
		self.resTitle.TextColor3 = Color3.new(1, 1, 1)
		self.resStroke.Color = Theme.UI.AccentBlue
	end

	local rw = res.reward or { xpGained = 150, prevLevel = 1, newLevel = 1 }
	local lvlNote = if rw.newLevel ~= rw.prevLevel
		then string.format("\n🎉 LEVEL UP! Lv. %d → Lv. %d!", rw.prevLevel, rw.newLevel)
		else ""
	self.resBody.Text = string.format(
		"Peak Empire: %.1f%% (%d tiles)  •  Nukes Sent: %d\n+%d XP Earned!%s",
		res.landPctPeak or 0,
		res.tilesPeak or 0,
		res.nukesSent or 0,
		rw.xpGained or 0,
		lvlNote
	)
	self.resultModal.Visible = true
	self.modalScrim.Visible = true
end

function HudUI:UpdateFromState(state: any, mySmallId: number)
	self.latestState = state
	self.mySmallId = mySmallId

	-- 1. Spawn Phase Banner
	if state.inSpawnPhase then
		self.spawnBanner.Visible = true
		self.controlPanel.Visible = false
		self.spawnLbl.Text = string.format(
			"📍 CLICK ANY LAND TO PICK YOUR SPAWN SPOT — Starting in %.1fs",
			state.spawnSecondsLeft or 0
		)
	else
		self.spawnBanner.Visible = false
		self.controlPanel.Visible = true
	end

	-- 2. My Control Panel Readouts
	local me = self.canvas.playersById[mySmallId]
	if me ~= nil and me.alive then
		local capWarn = (me.troops / math.max(1, me.maxTroops)) >= 0.80
		self.troopLbl.Text = string.format("🪖 %s / %s", Format.Troops(me.troops), Format.Troops(me.maxTroops))
		self.troopLbl.TextColor3 = if capWarn then Color3.fromRGB(252, 165, 165) else Color3.new(1, 1, 1)
		self.rateLbl.Text = "+" .. Format.Troops(me.troopRatePerSec or 0) .. "/s"
		self.goldLbl.Size = UDim2.fromOffset(186, 22)
		self.goldLbl.Text = "💰 " .. Format.Gold(me.gold)
		self.atkStatusBtn.Visible = true
		if (me.attackingTroops or 0) > 0 then
			self.atkStatusBtn.Text = "⚔️ " .. Format.Troops(me.attackingTroops) .. " [✕]"
			self.atkStatusBtn.BackgroundColor3 = Color3.fromRGB(185, 28, 28)
		else
			self.atkStatusBtn.Text = "⚔️ Idle"
			self.atkStatusBtn.BackgroundColor3 = Color3.fromRGB(51, 65, 85)
		end
	elseif not state.inSpawnPhase then
		self.troopLbl.Text = "👁️ SPECTATING"
		self.rateLbl.Text = ""
		self.atkStatusBtn.Visible = false
		self.goldLbl.Size = UDim2.new(1, -24, 0, 22)
		self.goldLbl.Text = "Click Leaderboard to follow"
	end

	if self.buildPopup.Visible then
		self:_RefreshBuildCosts()
	end

	-- 3. Top-Right Leaderboard & Clock
	local doomTxt = if (state.doomsdayShare or 0) > 0
		then string.format(" • ⏳%.1f%%", (state.doomsdayShare or 0) * 100)
		else ""
	self.lbHeaderBtn.Text = string.format(
		"⏱️ %s • Win: %d%%%s %s",
		Format.Timer(state.elapsedSeconds or 0),
		state.winPercentRequired or 80,
		doomTxt,
		if self.leaderboardOpen then "▾" else "▸"
	)

	if self.leaderboardOpen then
		local alivePlayers = {}
		for _, p in ipairs(state.players or {}) do
			if p.alive and (p.tilesOwned > 0 or state.inSpawnPhase) then
				table.insert(alivePlayers, p)
			end
		end
		table.sort(alivePlayers, function(a, b)
			if a.tilesOwned ~= b.tilesOwned then
				return a.tilesOwned > b.tilesOwned
			end
			return a.troops > b.troops
		end)

		local totalLand = if self.canvas.map then math.max(1, self.canvas.map.numLandTiles) else 1
		local meInTop = false
		for idx = 1, 9 do
			local slot = self.lbRowPool[idx]
			local entry = alivePlayers[idx]
			if idx == 9 and not meInTop and me ~= nil and me.alive then
				entry = me
			end
			if entry ~= nil then
				if entry.smallId == mySmallId then
					meInTop = true
				end
				local relIcon = ""
				if entry.smallId == mySmallId then
					relIcon = "★ "
				elseif self.canvas.friendlySet[entry.smallId] then
					relIcon = "🤝 "
				elseif entry.isTraitor then
					relIcon = "💀 "
				elseif self.canvas.embargoSet[entry.smallId] then
					relIcon = "🚫 "
				end
				slot.swatch.BackgroundColor3 = Theme.HexToColor3(entry.colorHex)
				slot.txt.Text = string.format("%d. %s%s", idx, relIcon, entry.name)
				slot.stats.Text = string.format(
					"%s • %s",
					Format.Percent(entry.tilesOwned / totalLand),
					Format.Troops(entry.troops)
				)
				slot.row.BackgroundColor3 = if entry.smallId == mySmallId
					then Color3.fromRGB(30, 58, 95)
					else Theme.UI.BgCard
				slot.setTarget(entry.smallId)
				slot.row.Visible = true
			else
				slot.row.Visible = false
			end
		end
	end

	-- 4. Event Feed
	local evs = state.events or {}
	local nEv = #evs
	for i = 1, 5 do
		local ev = evs[nEv - 5 + i]
		local itemBtn = self.feedItems[i]
		if ev ~= nil then
			itemBtn.Text = ev.text
			itemBtn.TextColor3 = Theme.HexToColor3(ev.colorHex or "#f8fafc")
			self.feedCoords[i] = { x = ev.targetX, y = ev.targetY }
			itemBtn.Visible = true
		else
			itemBtn.Visible = false
		end
	end

	-- 5. Actionable Alerts (Incoming Nuke Siren, Alliance Requests, Alliance Expiring!)
	self.alertsBox:ClearAllChildren()
	local aLayout = Instance.new("UIListLayout")
	aLayout.Padding = UDim.new(0, 6)
	aLayout.Parent = self.alertsBox

	local myAlerts = if state.alertsByPlayer then state.alertsByPlayer[mySmallId] else nil
	if myAlerts ~= nil then
		for _, al in ipairs(myAlerts) do
			if not self.seenAlertIds[al.id] then
				self.seenAlertIds[al.id] = true
				SoundFX.Play(if al.kind == "NukeInbound" then "alert" else "alliance")
			end
			if al.kind == "NukeInbound" then
				local warnBtn = UiWidgets.MakeButton(
					self.alertsBox,
					string.format("☢️ %s INBOUND FROM %s! [JUMP]", tostring(al.unitType), al.fromName),
					Color3.fromRGB(185, 28, 28),
					UDim2.new(1, 0, 0, 38),
					nil
				)
				warnBtn.TextSize = 11
				warnBtn.ZIndex = 25
				warnBtn.Activated:Connect(function()
					if al.targetX and al.targetY then
						self.camera:FocusOn(al.targetX, al.targetY, math.max(self.camera.scale, 6.5))
					end
					self.callbacks.onSendIntent("DismissAlert", { alertId = al.id })
				end)
			else
				local card = Instance.new("Frame")
				card.Size = UDim2.new(1, 0, 0, 56)
				card.BackgroundColor3 = Theme.UI.BgPanel
				card.BorderSizePixel = 0
				card.ZIndex = 25
				UiWidgets.AddCorner(card, 8)
				UiWidgets.AddStroke(card, Theme.UI.AccentGreen, 1.5, 0.2)
				card.Parent = self.alertsBox

				local lbl = Instance.new("TextLabel")
				lbl.Position = UDim2.fromOffset(8, 4)
				lbl.Size = UDim2.new(1, -16, 0, 20)
				lbl.BackgroundTransparency = 1
				lbl.Font = Enum.Font.GothamBold
				lbl.TextSize = 11
				lbl.TextXAlignment = Enum.TextXAlignment.Left
				lbl.TextColor3 = Color3.new(1, 1, 1)
				lbl.Text = if al.kind == "AllianceExpiring"
					then ("🤝 Extend alliance with " .. al.fromName .. "?")
					else ("🤝 Alliance request from " .. al.fromName)
				lbl.ZIndex = 26
				lbl.Parent = card

				local acc = UiWidgets.MakeButton(card, "✓ Accept", Theme.UI.AccentGreen, UDim2.fromOffset(92, 24), UDim2.fromOffset(8, 27))
				acc.TextSize = 11
				acc.ZIndex = 26
				acc.Activated:Connect(function()
					SoundFX.Play("alliance")
					self.callbacks.onSendIntent("RespondAlliance", { fromSmallId = al.fromSmallId, accept = true })
				end)

				local dec = UiWidgets.MakeButton(card, "✕ Ignore", Theme.UI.BgCard, UDim2.fromOffset(84, 24), UDim2.fromOffset(108, 27))
				dec.TextSize = 11
				dec.ZIndex = 26
				dec.Activated:Connect(function()
					self.callbacks.onSendIntent("RespondAlliance", { fromSmallId = al.fromSmallId, accept = false })
				end)
			end
		end
	end

	-- 6. Minimap Preview + Player Territory Dots
	if state.mapId ~= nil and state.mapId ~= self.lastMiniMapId then
		self.lastMiniMapId = state.mapId
		UiWidgets.PopulateMapPreview(self.miniMapPreview, MapRegistry.Get(state.mapId))
	end
	if self.canvas.map ~= nil then
		local mw, mh = self.canvas.map.width, self.canvas.map.height
		local activeDotIds: { [number]: boolean } = {}
		for _, p in ipairs(state.players or {}) do
			if p.alive and p.tilesOwned > 25 then
				activeDotIds[p.smallId] = true
				local d = self.miniDots[p.smallId]
				if d == nil then
					d = Instance.new("Frame")
					d.AnchorPoint = Vector2.new(0.5, 0.5)
					d.BorderSizePixel = 0
					d.ZIndex = 22
					UiWidgets.AddCorner(d, 99)
					d.Parent = self.miniDotsLayer
					self.miniDots[p.smallId] = d
				end
				local dotSz = math.clamp(math.sqrt(p.tilesOwned) * 0.22, 3, 14)
				d.Size = UDim2.fromOffset(dotSz, dotSz)
				d.Position = UDim2.fromScale(p.labelX / mw, p.labelY / mh)
				d.BackgroundColor3 = Theme.HexToColor3(p.colorHex)
				d.Visible = true
			end
		end
		for sid, d in pairs(self.miniDots) do
			if not activeDotIds[sid] then
				d.Visible = false
			end
		end
	end
end

function HudUI:StepMinimapViewport()
	local map = self.canvas.map
	if map == nil then
		return
	end
	local visW = (self.camera.viewW / self.camera.scale) / map.width
	local visH = (self.camera.viewH / self.camera.scale) / map.height
	local cx = self.camera.centerX / map.width
	local cy = self.camera.centerY / map.height
	local clampedW = math.clamp(visW, 0.04, 1)
	local clampedH = math.clamp(visH, 0.04, 1)
	self.miniCamRect.Size = UDim2.fromScale(clampedW, clampedH)
	self.miniCamRect.Position = UDim2.fromScale(
		math.clamp(cx - clampedW * 0.5, 0, 1 - clampedW),
		math.clamp(cy - clampedH * 0.5, 0, 1 - clampedH)
	)
end

function HudUI:SyncCanvasExclusions(inMenu: boolean)
	local anyModal = inMenu
		or self.buildPopup.Visible
		or self.inspectorModal.Visible
		or self.resultModal.Visible
	self.canvas.hideWorldLabels = anyModal
	local rects = {}
	if not inMenu then
		local sc = self.uiScale.Scale
		local vw, vh = self.camera.viewW, self.camera.viewH
		if self.controlPanel.Visible then
			rects[#rects + 1] = { 0, vh - 190 * sc, 378 * sc, vh }
		end
		local lbH = if self.leaderboardOpen then 274 * sc else 56 * sc
		rects[#rects + 1] = { vw - 318 * sc, 0, vw, lbH }
		rects[#rects + 1] = { vw - 318 * sc, vh - 286 * sc, vw, vh }
		if self.spawnBanner.Visible or self.armedPill.Visible then
			rects[#rects + 1] = { vw * 0.5 - 245 * sc, 0, vw * 0.5 + 245 * sc, 78 * sc }
		end
		if #self.alertsBox:GetChildren() > 1 then
			rects[#rects + 1] = { 0, 0, 330 * sc, 150 * sc }
		end
		if self.radialRoot.Visible then
			local rx = self.radialRoot.Position.X.Offset * sc
			local ry = self.radialRoot.Position.Y.Offset * sc
			rects[#rects + 1] = { rx - 108 * sc, ry - 108 * sc, rx + 108 * sc, ry + 108 * sc }
		end
		if self.emojiPopup.Visible or self.chatPopup.Visible then
			rects[#rects + 1] = { 0, vh - 470 * sc, 280 * sc, vh }
		end
	end
	self.canvas.hudBlockedRects = rects
end

function HudUI:SetVisible(vis: boolean)
	self.root.Visible = vis
	if not vis then
		self.radialRoot.Visible = false
		self.buildPopup.Visible = false
		self.inspectorModal.Visible = false
		self.emojiPopup.Visible = false
		self.chatPopup.Visible = false
		self.resultModal.Visible = false
		self.modalScrim.Visible = false
		self:ClearArmedModes()
	end
end

return HudUI
