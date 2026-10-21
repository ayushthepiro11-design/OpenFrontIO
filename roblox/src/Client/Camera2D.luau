--!strict
-- Pure 2D Browser-Exact Viewport Transform (exact port of OpenFront TransformHandler.ts)
-- Supports cursor-anchored scroll wheel zoom, middle/left drag pan, WASD/Arrows pan,
-- pinch-to-zoom on touch screens, and instant Screen <-> Tile coordinate transforms!

local Camera2D = {}
Camera2D.__index = Camera2D

export type Camera2DInstance = typeof(setmetatable(
	{} :: {
		mapW: number,
		mapH: number,
		viewW: number,
		viewH: number,
		centerX: number, -- in map tile coordinates (0..mapW)
		centerY: number, -- in map tile coordinates (0..mapH)
		scale: number, -- screen pixels per map tile
		minScale: number,
		maxScale: number,
		panVelX: number,
		panVelY: number,
	},
	Camera2D
))

function Camera2D.new(mapW: number, mapH: number, viewW: number, viewH: number): Camera2DInstance
	local fitScale = math.min(viewW / math.max(1, mapW), viewH / math.max(1, mapH)) * 0.92
	local self = setmetatable({
		mapW = mapW,
		mapH = mapH,
		viewW = math.max(1, viewW),
		viewH = math.max(1, viewH),
		centerX = mapW * 0.5,
		centerY = mapH * 0.5,
		scale = math.max(0.5, fitScale),
		minScale = math.max(0.35, fitScale * 0.72),
		maxScale = 28.0,
		panVelX = 0,
		panVelY = 0,
	}, Camera2D)
	return self
end

function Camera2D:SetMapSize(mapW: number, mapH: number)
	self.mapW = mapW
	self.mapH = mapH
	self:FitWorld()
end

function Camera2D:SetViewportSize(viewW: number, viewH: number)
	self.viewW = math.max(1, viewW)
	self.viewH = math.max(1, viewH)
	local fitScale = math.min(self.viewW / math.max(1, self.mapW), self.viewH / math.max(1, self.mapH)) * 0.92
	self.minScale = math.max(0.35, fitScale * 0.72)
	self.scale = math.clamp(self.scale, self.minScale, self.maxScale)
	self:_ClampBounds()
end

function Camera2D:FitWorld()
	local fitScale = math.min(self.viewW / math.max(1, self.mapW), self.viewH / math.max(1, self.mapH)) * 0.92
	self.minScale = math.max(0.35, fitScale * 0.72)
	self.scale = math.max(self.minScale, fitScale)
	self.centerX = self.mapW * 0.5
	self.centerY = self.mapH * 0.5
end

function Camera2D:FocusOn(tileX: number, tileY: number, desiredScale: number?)
	self.centerX = math.clamp(tileX, 0, self.mapW)
	self.centerY = math.clamp(tileY, 0, self.mapH)
	if desiredScale ~= nil then
		self.scale = math.clamp(desiredScale, self.minScale, self.maxScale)
	end
	self:_ClampBounds()
end

function Camera2D:_ClampBounds()
	local marginX = self.mapW * 0.15
	local marginY = self.mapH * 0.15
	self.centerX = math.clamp(self.centerX, -marginX, self.mapW + marginX)
	self.centerY = math.clamp(self.centerY, -marginY, self.mapH + marginY)
end

-- Zoom anchored strictly around (screenX, screenY) so the pixel under the mouse NEVER slips!
function Camera2D:ZoomAtScreenPoint(factor: number, screenX: number, screenY: number)
	local beforeWX, beforeWY = self:ScreenToWorldFloat(screenX, screenY)
	self.scale = math.clamp(self.scale * factor, self.minScale, self.maxScale)
	local afterWX, afterWY = self:ScreenToWorldFloat(screenX, screenY)
	self.centerX += beforeWX - afterWX
	self.centerY += beforeWY - afterWY
	self:_ClampBounds()
end

function Camera2D:PanByScreenDelta(dxPx: number, dyPx: number)
	self.centerX -= dxPx / self.scale
	self.centerY -= dyPx / self.scale
	self:_ClampBounds()
end

function Camera2D:StepKeyboard(moveX: number, moveY: number, dt: number)
	if moveX ~= 0 or moveY ~= 0 then
		local speedPxPerSec = 680
		self.centerX += (moveX * speedPxPerSec * dt) / self.scale
		self.centerY += (moveY * speedPxPerSec * dt) / self.scale
		self:_ClampBounds()
	end
end

function Camera2D:ScreenToWorldFloat(screenX: number, screenY: number): (number, number)
	local wx = self.centerX + (screenX - self.viewW * 0.5) / self.scale
	local wy = self.centerY + (screenY - self.viewH * 0.5) / self.scale
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
