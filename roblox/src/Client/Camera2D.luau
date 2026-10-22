--!native
--!strict
-- Pure 2D Browser-Exact Viewport Transform (exact port of OpenFront TransformHandler.ts)
-- Upgraded for Full-Scale 1:1 Maps (1000x1000 .. 4108x1948):
--   - Smooth inertial zoom (`targetScale` exponential easing + instant cursor anchor)
--   - Immersive Regional Spawn Framing (`FrameSpawnView` fills 100% of screen cleanly — zero tiny postage stamp!)
--   - Centered viewport bounds clamping (`_ClampBounds`) + NaN safety

local Camera2D = {}
Camera2D.__index = Camera2D

export type Camera2DInstance = typeof(setmetatable(
	{} :: {
		mapW: number,
		mapH: number,
		viewW: number,
		viewH: number,
		centerX: number,
		centerY: number,
		scale: number,
		targetScale: number,
		zoomAnchorX: number,
		zoomAnchorY: number,
		minScale: number,
		maxScale: number,
		panVelX: number,
		panVelY: number,
	},
	Camera2D
))

local function finiteOr(v: number, fallback: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return fallback
	end
	return v
end

function Camera2D.new(mapW: number, mapH: number, viewW: number, viewH: number): Camera2DInstance
	local vw = math.max(1, finiteOr(viewW, 1280))
	local vh = math.max(1, finiteOr(viewH, 720))
	local mw = math.max(1, finiteOr(mapW, 2000))
	local mh = math.max(1, finiteOr(mapH, 1000))
	-- Fill screen cleanly by default instead of shrinking map inside big margins!
	local coverScale = math.max(vw / mw, vh / mh)
	local fitScale = math.min(vw / mw, vh / mh) * 0.96
	local self = setmetatable({
		mapW = mw,
		mapH = mh,
		viewW = vw,
		viewH = vh,
		centerX = mw * 0.52,
		centerY = mh * 0.44,
		scale = coverScale,
		targetScale = coverScale,
		zoomAnchorX = vw * 0.5,
		zoomAnchorY = vh * 0.5,
		minScale = math.max(0.18, fitScale * 0.85),
		maxScale = 28.0,
		panVelX = 0,
		panVelY = 0,
	}, Camera2D)
	return self
end

function Camera2D:SetMapSize(mapW: number, mapH: number)
	self.mapW = math.max(1, finiteOr(mapW, 2000))
	self.mapH = math.max(1, finiteOr(mapH, 1000))
	self:FrameSpawnView()
end

function Camera2D:SetViewportSize(viewW: number, viewH: number)
	self.viewW = math.max(1, finiteOr(viewW, 1280))
	self.viewH = math.max(1, finiteOr(viewH, 720))
	local fitScale = math.min(self.viewW / self.mapW, self.viewH / self.mapH) * 0.96
	self.minScale = math.max(0.18, fitScale * 0.85)
	self.scale = math.clamp(self.scale, self.minScale, self.maxScale)
	self.targetScale = math.clamp(self.targetScale, self.minScale, self.maxScale)
	self:_ClampBounds()
end

-- Full-bleed edge-to-edge world framing (zero ugly empty ocean borders on spawn!)
function Camera2D:FrameSpawnView()
	local fitScale = math.min(self.viewW / self.mapW, self.viewH / self.mapH) * 0.96
	local coverScale = math.max(self.viewW / self.mapW, self.viewH / self.mapH)
	self.minScale = math.max(0.18, fitScale * 0.85)
	self.scale = math.clamp(coverScale, self.minScale, self.maxScale)
	self.targetScale = self.scale
	self.centerX = self.mapW * 0.52
	self.centerY = self.mapH * 0.44
	self:_ClampBounds()
end

-- Full planetary overview hotkey (`0` / `Fit` button)
function Camera2D:FitWorld()
	local fitScale = math.min(self.viewW / self.mapW, self.viewH / self.mapH) * 0.96
	self.minScale = math.max(0.18, fitScale * 0.85)
	self.scale = math.max(self.minScale, fitScale)
	self.targetScale = self.scale
	self.centerX = self.mapW * 0.5
	self.centerY = self.mapH * 0.5
	self:_ClampBounds()
end

function Camera2D:FocusOn(tileX: number, tileY: number, desiredScale: number?)
	self.centerX = math.clamp(finiteOr(tileX, self.mapW * 0.5), 0, self.mapW)
	self.centerY = math.clamp(finiteOr(tileY, self.mapH * 0.5), 0, self.mapH)
	if desiredScale ~= nil then
		local s = math.clamp(finiteOr(desiredScale, self.scale), self.minScale, self.maxScale)
		self.scale = s
		self.targetScale = s
	end
	self:_ClampBounds()
end

function Camera2D:_ClampBounds()
	local halfVisW = (self.viewW * 0.5) / self.scale
	local halfVisH = (self.viewH * 0.5) / self.scale
	if self.mapW * self.scale <= self.viewW * 0.98 then
		self.centerX = math.clamp(self.centerX, self.mapW * 0.25, self.mapW * 0.75)
	else
		local minX = math.min(self.mapW * 0.5, halfVisW * 0.45)
		local maxX = math.max(self.mapW * 0.5, self.mapW - halfVisW * 0.45)
		self.centerX = math.clamp(self.centerX, minX, maxX)
	end
	if self.mapH * self.scale <= self.viewH * 0.98 then
		self.centerY = math.clamp(self.centerY, self.mapH * 0.25, self.mapH * 0.75)
	else
		local minY = math.min(self.mapH * 0.5, halfVisH * 0.45)
		local maxY = math.max(self.mapH * 0.5, self.mapH - halfVisH * 0.45)
		self.centerY = math.clamp(self.centerY, minY, maxY)
	end
end

-- Cursor-anchored zoom (supports smooth `StepZoom(dt)` AND immediate responsive zoom!)
function Camera2D:ZoomAtScreenPoint(factor: number, screenX: number, screenY: number, smooth: boolean?)
	local sx = finiteOr(screenX, self.viewW * 0.5)
	local sy = finiteOr(screenY, self.viewH * 0.5)
	local f = finiteOr(factor, 1.0)
	if smooth then
		self.targetScale = math.clamp(self.targetScale * f, self.minScale, self.maxScale)
		self.zoomAnchorX = sx
		self.zoomAnchorY = sy
	else
		local beforeWX, beforeWY = self:ScreenToWorldFloat(sx, sy)
		self.scale = math.clamp(self.scale * f, self.minScale, self.maxScale)
		self.targetScale = self.scale
		local afterWX, afterWY = self:ScreenToWorldFloat(sx, sy)
		self.centerX += beforeWX - afterWX
		self.centerY += beforeWY - afterWY
		self:_ClampBounds()
	end
end

function Camera2D:StepZoom(dt: number)
	if math.abs(self.targetScale - self.scale) > 0.0005 then
		local sx = self.zoomAnchorX
		local sy = self.zoomAnchorY
		local beforeWX, beforeWY = self:ScreenToWorldFloat(sx, sy)
		local alpha = 1 - math.exp(-math.max(0.001, dt) * 16.0)
		self.scale = self.scale + (self.targetScale - self.scale) * alpha
		local afterWX, afterWY = self:ScreenToWorldFloat(sx, sy)
		self.centerX += beforeWX - afterWX
		self.centerY += beforeWY - afterWY
		self:_ClampBounds()
	end
end

function Camera2D:PanByScreenDelta(dxPx: number, dyPx: number)
	self.centerX -= finiteOr(dxPx, 0) / self.scale
	self.centerY -= finiteOr(dyPx, 0) / self.scale
	self:_ClampBounds()
end

function Camera2D:StepKeyboard(moveX: number, moveY: number, dt: number)
	self:StepZoom(dt)
	if moveX ~= 0 or moveY ~= 0 then
		local speedPxPerSec = 760
		self.centerX += (moveX * speedPxPerSec * dt) / self.scale
		self.centerY += (moveY * speedPxPerSec * dt) / self.scale
		self:_ClampBounds()
	end
end

function Camera2D:ScreenToWorldFloat(screenX: number, screenY: number): (number, number)
	local wx = self.centerX + (finiteOr(screenX, 0) - self.viewW * 0.5) / self.scale
	local wy = self.centerY + (finiteOr(screenY, 0) - self.viewH * 0.5) / self.scale
	return wx, wy
end

function Camera2D:ScreenToTile(screenX: number, screenY: number): (number, number, boolean)
	local wx, wy = self:ScreenToWorldFloat(screenX, screenY)
	local tx = math.floor(wx)
	local ty = math.floor(wy)
	local inside = tx >= 0 and tx < self.mapW and ty >= 0 and ty < self.mapH
	return tx, ty, inside
end

function Camera2D:WorldToScreen(worldX: number, worldY: number): (number, number)
	local sx = self.viewW * 0.5 + (worldX - self.centerX) * self.scale
	local sy = self.viewH * 0.5 + (worldY - self.centerY) * self.scale
	return sx, sy
end

function Camera2D:GetCanvasRect(): (number, number, number, number)
	local leftPx = math.floor(self.viewW * 0.5 - self.centerX * self.scale + 0.5)
	local topPx = math.floor(self.viewH * 0.5 - self.centerY * self.scale + 0.5)
	local widthPx = math.floor(self.mapW * self.scale + 0.5)
	local heightPx = math.floor(self.mapH * self.scale + 0.5)
	return leftPx, topPx, widthPx, heightPx
end

return Camera2D
