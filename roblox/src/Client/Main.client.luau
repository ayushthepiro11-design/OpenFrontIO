--!native
--!strict
-- OpenFront Full-Scale 2D Client Entrypoint (`Main.client.luau`)
-- Pure 2D Browser-Exact Experience inside ScreenGui (`IgnoreGuiInset = true`) with:
--   - Full `ownerSnapshot` + `falloutSnapshot` decoding on join/late-join
--   - Multi-Atlas `1024x1024` `EditableImage` + Live `220x110` Minimap texture sync
--   - Mobile Pinch-vs-Pan touch guard (`zero accidental attacks on multi-finger release!`)
--   - Full Console/Gamepad Thumbstick Pan + Trigger Zoom support
--   - Clean Connection Maid lifecycle!

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

task.spawn(function()
	for _ = 1, 8 do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		task.wait(0.5)
	end
end)

local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")
local NetCodec = require(Shared:WaitForChild("NetCodec"))
local Types = require(Shared:WaitForChild("Types"))

local Remotes = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
local ClientIntentRE = Remotes:WaitForChild("ClientIntent") :: RemoteEvent
local StateSyncRE = Remotes:WaitForChild("StateSync") :: RemoteEvent
local LobbySyncRE = Remotes:WaitForChild("LobbySync") :: RemoteEvent
local MatchResultRE = Remotes:WaitForChild("MatchResult") :: RemoteEvent
local ProfileSyncRE = Remotes:WaitForChild("ProfileSync") :: RemoteEvent
local GetInitialStateRF = Remotes:WaitForChild("GetInitialState") :: RemoteFunction

local Camera2D = require(script.Parent:WaitForChild("Camera2D"))
local HudUI = require(script.Parent:WaitForChild("HudUI"))
local MapCanvas = require(script.Parent:WaitForChild("MapCanvas"))
local MenuUI = require(script.Parent:WaitForChild("MenuUI"))
local SoundFX = require(script.Parent:WaitForChild("SoundFX"))

local connections: { RBXScriptConnection } = {}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OpenFrontApp"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.DisplayOrder = 10
ScreenGui.Parent = PlayerGui

local MapViewport = Instance.new("Frame")
MapViewport.Name = "MapViewport"
MapViewport.Size = UDim2.fromScale(1, 1)
MapViewport.BackgroundColor3 = Color3.fromRGB(42, 52, 65)
MapViewport.BorderSizePixel = 0
MapViewport.ClipsDescendants = true
MapViewport.ZIndex = 1
MapViewport.Parent = ScreenGui

local cam2D = Camera2D.new(2000, 1000, 1280, 720)
local canvas = MapCanvas.new(MapViewport, cam2D)

local function sendIntent(intentType: string, payload: any)
	ClientIntentRE:FireServer(intentType, payload)
end

local latestSnapshot: any = nil
local localInMenu = true
local hasAutoCenteredThisMatch = false

local menuUI = MenuUI.new(ScreenGui, {
	onSendIntent = function(intent: string, payload: any)
		sendIntent(intent, payload)
	end,
	onLocalSettingChanged = function(prof: Types.PlayerProfileSave)
		SoundFX.Volume = prof.soundVolume or 0.7
		canvas.showNames = prof.showNames
		canvas:SetPreferScanline(prof.preferScanline2D)
		canvas:MarkAllDirty()
	end,
})

local hudUI = HudUI.new(ScreenGui, cam2D, canvas, {
	onSendIntent = function(intent: string, payload: any)
		sendIntent(intent, payload)
	end,
	onExitToMenu = function()
		localInMenu = true
		sendIntent("ReturnToLobby", {})
		menuUI:SetVisible(true)
	end,
})

local function findMySmallId(players: { any }?): number
	if players == nil then
		return 0
	end
	local uid = LocalPlayer.UserId
	for _, p in ipairs(players) do
		if p.userId == uid then
			return p.smallId
		end
	end
	return 0
end

local function applyServerPayload(payload: any)
	if type(payload) ~= "table" then
		return
	end
	latestSnapshot = payload

	if payload.mapId ~= nil and (canvas.map == nil or canvas.map.id ~= payload.mapId) then
		canvas:LoadMap(payload.mapId)
		hasAutoCenteredThisMatch = false
	end

	if payload.isPreview == true then
		localInMenu = true
		menuUI:SetVisible(true)
		hudUI:SetVisible(false)
	else
		if localInMenu and findMySmallId(payload.players) > 0 then
			localInMenu = false
		end
		menuUI:SetVisible(localInMenu)
		hudUI:SetVisible(not localInMenu)
	end

	local mySid = findMySmallId(payload.players)
	canvas:UpdatePalettes(payload.players or {}, mySid, payload.units)

	if canvas.map ~= nil and payload.tileBuffer ~= nil then
		if payload.isFullSnapshot then
			NetCodec.DecodeFullOwnerSnapshot(payload.tileBuffer, canvas.map.owner, canvas.map.size)
			if payload.falloutSnapshot ~= nil then
				canvas.map.numFalloutTiles =
					NetCodec.DecodeFullFalloutSnapshot(payload.falloutSnapshot, canvas.map.fallout, canvas.map.size)
			end
			canvas:MarkAllDirty()
		else
			NetCodec.ApplyTileDeltas(
				payload.tileBuffer,
				canvas.map.owner,
				canvas.map.width,
				canvas.dirtyRows,
				canvas.dirtyTiles
			)
		end
	end
	if canvas.map ~= nil and payload.falloutBuffer ~= nil then
		NetCodec.ApplyFalloutDeltas(
			payload.falloutBuffer,
			canvas.map.fallout,
			canvas.map.width,
			canvas.dirtyRows,
			canvas.dirtyTiles
		)
	end

	if payload.railEdges ~= nil and ((payload.ticks or 0) % 10 == 1 or payload.isFullSnapshot) then
		canvas:SetRailEdges(payload.railEdges)
	end

	if payload.explosions ~= nil and #payload.explosions > 0 then
		if not localInMenu then
			SoundFX.Play("boom")
		end
		for _, ex in ipairs(payload.explosions) do
			canvas:SpawnShockwave(ex.x, ex.y, ex.radius, ex.kind)
		end
	end

	-- Frame full regional continent theatre around player's homeland on full-scale 2000px..4108px maps!
	if not payload.isPreview and not payload.inSpawnPhase and not hasAutoCenteredThisMatch and mySid > 0 then
		local me = canvas.playersById[mySid]
		if me ~= nil and me.alive then
			hasAutoCenteredThisMatch = true
			cam2D:FocusOn(me.labelX, me.labelY, math.max(cam2D.scale, 1.9))
		end
	end

	if not localInMenu then
		hudUI:UpdateFromState(payload, mySid)
	end
end

table.insert(connections, StateSyncRE.OnClientEvent:Connect(applyServerPayload))
table.insert(connections, LobbySyncRE.OnClientEvent:Connect(function(lobbyState: any)
	menuUI:UpdateLobbyState(lobbyState)
end))
table.insert(connections, ProfileSyncRE.OnClientEvent:Connect(function(prof: Types.PlayerProfileSave)
	SoundFX.Volume = prof.soundVolume or 0.7
	menuUI:SetProfile(prof)
	hudUI:SetAttackRatio(prof.defaultAttackRatio or 0.25)
	canvas.showNames = prof.showNames
	canvas:SetPreferScanline(prof.preferScanline2D)
end))
table.insert(connections, MatchResultRE.OnClientEvent:Connect(function(res: any)
	if not localInMenu then
		hudUI:ShowMatchResult(res)
	end
end))

task.spawn(function()
	local ok, initData = pcall(function()
		return GetInitialStateRF:InvokeServer()
	end)
	if ok and type(initData) == "table" then
		if initData.profile ~= nil then
			SoundFX.Volume = initData.profile.soundVolume or 0.7
			menuUI:SetProfile(initData.profile)
			hudUI:SetAttackRatio(initData.profile.defaultAttackRatio or 0.25)
			canvas.showNames = initData.profile.showNames
			canvas:SetPreferScanline(initData.profile.preferScanline2D)
		end
		if initData.snapshot ~= nil then
			applyServerPayload(initData.snapshot)
		end
	end
end)

-- ============================================================================
-- FULL PC MOUSE, MOBILE PINCH-GUARDED TOUCH, AND CONSOLE GAMEPAD INPUT!
-- ============================================================================
local isDragging = false
local isPinching = false
local pinchCooldownUntil = 0
local dragMovedPx = 0
local lastDragPos = Vector2.zero
local rightDownPos = Vector2.zero
local touchPressStart = 0
local gamepadStick = Vector2.zero
local gamepadZoomDir = 0

local function toScreenCoords(rawPos: Vector3 | Vector2): (number, number)
	local inset = GuiService:GetGuiInset()
	return rawPos.X, rawPos.Y + inset.Y
end

local function handleMapPrimaryClick(screenX: number, screenY: number)
	if localInMenu or latestSnapshot == nil or canvas.map == nil then
		return
	end
	hudUI.radialRoot.Visible = false
	hudUI.emojiPopup.Visible = false
	hudUI.chatPopup.Visible = false

	local tx, ty, inside = cam2D:ScreenToTile(screenX, screenY)
	if not inside then
		return
	end

	if
		UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	then
		hudUI:ToggleBuildMenu(tx, ty)
		return
	end

	if latestSnapshot.inSpawnPhase then
		SoundFX.Play("click")
		sendIntent("ChooseSpawn", { x = tx, y = ty })
		return
	end

	if canvas.armedBuildType ~= nil then
		local unitType = canvas.armedBuildType
		if unitType == "AtomBomb" or unitType == "HydrogenBomb" or unitType == "MIRV" then
			SoundFX.Play("launch")
		else
			SoundFX.Play("build")
		end
		sendIntent("BuildUnit", { unitType = unitType, x = tx, y = ty })
		if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			hudUI:ClearArmedModes()
		end
		return
	end

	if hudUI.boatModeArmed then
		SoundFX.Play("boat")
		sendIntent("BoatAttack", { x = tx, y = ty, ratio = hudUI.attackRatio })
		hudUI:ClearArmedModes()
		return
	end

	if canvas.selectedWarshipId ~= nil then
		SoundFX.Play("boat")
		sendIntent("MoveWarship", { unitId = canvas.selectedWarshipId, x = tx, y = ty })
		hudUI:ClearArmedModes()
		return
	end
	for _, u in ipairs(latestSnapshot.units or {}) do
		if u.unitType == "Warship" and u.ownerSmallId == canvas.mySmallId then
			if math.abs(u.x - tx) <= 8 and math.abs(u.y - ty) <= 8 then
				SoundFX.Play("click")
				canvas.selectedWarshipId = u.id
				hudUI.armedTxt.Text = "🚢 WARSHIP SELECTED: Click any ocean tile to patrol!"
				hudUI.armedPill.Visible = true
				return
			end
		end
	end

	local ref = ty * canvas.map.width + tx
	local tb = buffer.readu8(canvas.map.terrain, ref)
	local isLand = bit32.band(tb, 0x80) ~= 0
	if isLand then
		local targetOwnerId = buffer.readu16(canvas.map.owner, ref * 2)
		if targetOwnerId ~= canvas.mySmallId then
			SoundFX.Play("attack")
			sendIntent("AttackLand", { targetSmallId = targetOwnerId, ratio = hudUI.attackRatio })
		end
	end
end

table.insert(connections, MapViewport.InputBegan:Connect(function(inp: InputObject)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
		if isPinching then
			return
		end
		local sx, sy = toScreenCoords(inp.Position)
		isDragging = true
		dragMovedPx = 0
		lastDragPos = Vector2.new(sx, sy)
		touchPressStart = os.clock()
	elseif inp.UserInputType == Enum.UserInputType.MouseButton3 then
		local sx, sy = toScreenCoords(inp.Position)
		isDragging = true
		dragMovedPx = 999
		lastDragPos = Vector2.new(sx, sy)
	elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
		local sx, sy = toScreenCoords(inp.Position)
		rightDownPos = Vector2.new(sx, sy)
		isDragging = true
		dragMovedPx = 0
		lastDragPos = rightDownPos
	end
end))

table.insert(connections, UserInputService.InputChanged:Connect(function(inp: InputObject, gameProcessed: boolean)
	if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
		local sx, sy = toScreenCoords(inp.Position)
		local cur = Vector2.new(sx, sy)
		local tx, ty, inside = cam2D:ScreenToTile(sx, sy)
		if inside and canvas.map ~= nil then
			canvas.cursorTileX = tx
			canvas.cursorTileY = ty
			local prevHover = canvas.hoveredOwnerId
			local newHover = buffer.readu16(canvas.map.owner, (ty * canvas.map.width + tx) * 2)
			if newHover ~= prevHover then
				canvas.hoveredOwnerId = newHover
			end
		end

		if isDragging and not isPinching then
			local delta = cur - lastDragPos
			dragMovedPx += delta.Magnitude
			lastDragPos = cur
			if dragMovedPx > 5 then
				cam2D:PanByScreenDelta(delta.X, delta.Y)
			end
		end
	elseif inp.UserInputType == Enum.UserInputType.MouseWheel and not gameProcessed then
		local sx, sy = toScreenCoords(inp.Position)
		local factor = if inp.Position.Z > 0 then 1.22 else (1 / 1.22)
		cam2D:ZoomAtScreenPoint(factor, sx, sy)
	elseif inp.KeyCode == Enum.KeyCode.Thumbstick1 then
		local mag = Vector2.new(inp.Position.X, inp.Position.Y)
		gamepadStick = if mag.Magnitude > 0.16 then Vector2.new(mag.X, -mag.Y) else Vector2.zero
	elseif inp.KeyCode == Enum.KeyCode.ButtonR2 or inp.KeyCode == Enum.KeyCode.ButtonL2 then
		if inp.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadZoomDir = if inp.Position.Z > 0.15 then 1 else 0
		else
			gamepadZoomDir = if inp.Position.Z > 0.15 then -1 else 0
		end
	end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(inp: InputObject)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
		if isDragging then
			isDragging = false
			if isPinching or os.clock() < pinchCooldownUntil then
				return
			end
			local sx, sy = toScreenCoords(inp.Position)
			local heldDuration = os.clock() - touchPressStart
			if dragMovedPx <= 6 then
				if inp.UserInputType == Enum.UserInputType.Touch and heldDuration >= 0.45 then
					local tx, ty, inside = cam2D:ScreenToTile(sx, sy)
					if inside then
						hudUI:OpenRadialMenu(sx, sy, tx, ty)
					end
				else
					handleMapPrimaryClick(sx, sy)
				end
			end
		end
	elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
		isDragging = false
		if dragMovedPx <= 6 and not localInMenu then
			local sx, sy = toScreenCoords(inp.Position)
			local tx, ty, inside = cam2D:ScreenToTile(sx, sy)
			if inside then
				hudUI:OpenRadialMenu(sx, sy, tx, ty)
			end
		end
	elseif inp.UserInputType == Enum.UserInputType.MouseButton3 then
		isDragging = false
	end
end))

-- Guarded Mobile Two-Finger Pinch-to-Zoom!
local lastPinchScale = 1.0
table.insert(connections, UserInputService.TouchPinch:Connect(function(touchPositions: { Vector2 }, scale: number, _vel: number, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		isPinching = true
		isDragging = false
		lastPinchScale = 1.0
	elseif state == Enum.UserInputState.Change and #touchPositions >= 1 then
		isPinching = true
		local ratio = scale / math.max(0.05, lastPinchScale)
		lastPinchScale = scale
		local mid = touchPositions[1]
		if #touchPositions >= 2 then
			mid = (touchPositions[1] + touchPositions[2]) * 0.5
		end
		local sx, sy = toScreenCoords(mid)
		cam2D:ZoomAtScreenPoint(ratio, sx, sy)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		isPinching = false
		pinchCooldownUntil = os.clock() + 0.18
	end
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(inp: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local kc = inp.KeyCode
	if kc == Enum.KeyCode.Escape then
		hudUI:ClearArmedModes()
		hudUI.radialRoot.Visible = false
		hudUI.buildPopup.Visible = false
		hudUI.inspectorModal.Visible = false
		hudUI.emojiPopup.Visible = false
		hudUI.chatPopup.Visible = false
	elseif localInMenu then
		return
	elseif kc == Enum.KeyCode.Space then
		canvas.altView = not canvas.altView
		canvas:MarkAllDirty()
	elseif kc == Enum.KeyCode.B then
		hudUI:ToggleBuildMenu(nil, nil)
	elseif kc == Enum.KeyCode.V then
		hudUI:ArmBoatMode()
	elseif kc == Enum.KeyCode.R then
		sendIntent("Retreat", {})
		sendIntent("RetreatBoats", {})
	elseif kc == Enum.KeyCode.M then
		hudUI.emojiPopup.Visible = not hudUI.emojiPopup.Visible
	elseif kc == Enum.KeyCode.T then
		hudUI.chatPopup.Visible = not hudUI.chatPopup.Visible
	elseif kc == Enum.KeyCode.C then
		local me = canvas.playersById[canvas.mySmallId]
		if me ~= nil then
			cam2D:FocusOn(me.labelX, me.labelY, math.max(cam2D.scale, 2.2))
		end
	elseif kc == Enum.KeyCode.Zero then
		cam2D:FitWorld()
	elseif kc == Enum.KeyCode.Q then
		hudUI:SetAttackRatio(hudUI.attackRatio - 0.10)
	elseif kc == Enum.KeyCode.E then
		hudUI:SetAttackRatio(hudUI.attackRatio + 0.10)
	elseif kc == Enum.KeyCode.Equals or kc == Enum.KeyCode.KeypadPlus then
		cam2D:ZoomAtScreenPoint(1.25, cam2D.viewW * 0.5, cam2D.viewH * 0.5)
	elseif kc == Enum.KeyCode.Minus or kc == Enum.KeyCode.KeypadMinus then
		cam2D:ZoomAtScreenPoint(0.80, cam2D.viewW * 0.5, cam2D.viewH * 0.5)
	elseif kc.Value >= Enum.KeyCode.One.Value and kc.Value <= Enum.KeyCode.Nine.Value then
		local pct = (kc.Value - Enum.KeyCode.One.Value + 1) * 0.10
		hudUI:SetAttackRatio(pct)
	end
end))

table.insert(connections, RunService.RenderStepped:Connect(function(dt: number)
	local absSize = ScreenGui.AbsoluteSize
	if absSize.X > 0 and absSize.Y > 0 and (absSize.X ~= cam2D.viewW or absSize.Y ~= cam2D.viewH) then
		cam2D:SetViewportSize(absSize.X, absSize.Y)
		local responsiveScale = math.clamp(math.min(absSize.X / 1280, absSize.Y / 720), 0.50, 1.15)
		menuUI.uiScale.Scale = responsiveScale
		hudUI.uiScale.Scale = responsiveScale
	end
	hudUI:SyncCanvasExclusions(localInMenu)

	if not UserInputService:GetFocusedTextBox() then
		local mx, my = gamepadStick.X, gamepadStick.Y
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			mx -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			mx += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			my -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
			my += 1
		end
		cam2D:StepKeyboard(mx, my, dt)
		if gamepadZoomDir ~= 0 then
			cam2D:ZoomAtScreenPoint(1 + gamepadZoomDir * dt * 1.6, cam2D.viewW * 0.5, cam2D.viewH * 0.5)
		end
	end

	if localInMenu and not isDragging then
		cam2D.centerX = if canvas.map ~= nil
			then (canvas.map.width * 0.5 + math.sin(os.clock() * 0.12) * 48)
			else cam2D.centerX
	end

	canvas:RenderFrame(latestSnapshot, dt)
	if not localInMenu then
		hudUI:StepMinimapViewport()
	end
end))
