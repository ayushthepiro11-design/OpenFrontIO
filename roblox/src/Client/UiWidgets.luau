--!strict
-- Reusable pure-2D OpenFront UI building blocks:
-- Vector country & Shinobi flags, rendered miniature map thumbnails, dark-glass cards, buttons & corners

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("OpenFrontShared")

local Format = require(Shared:WaitForChild("Format"))
local Theme = require(Shared:WaitForChild("Theme"))

local UiWidgets = {}

function UiWidgets.AddCorner(parent: GuiObject, radiusPx: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radiusPx)
	c.Parent = parent
	return c
end

function UiWidgets.AddStroke(parent: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0.35
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Renders a crisp, platform-independent vector flag inside `parent`!
function UiWidgets.CreateFlagBadge(parent: Instance, flagCode: string?, size: UDim2, pos: UDim2?): Frame
	local spec = Format.GetFlagSpec(flagCode)
	local box = Instance.new("Frame")
	box.Name = "FlagBadge"
	box.Size = size
	if pos ~= nil then
		box.Position = pos
	end
	box.BackgroundColor3 = Theme.HexToColor3(spec.c1)
	box.BorderSizePixel = 0
	box.ClipsDescendants = true
	UiWidgets.AddCorner(box, 3)
	UiWidgets.AddStroke(box, Color3.fromRGB(15, 23, 42), 1, 0.25)
	box.Parent = parent

	if spec.kind == "h3" then
		local b2 = Instance.new("Frame")
		b2.Size = UDim2.fromScale(1, 0.34)
		b2.Position = UDim2.fromScale(0, 0.33)
		b2.BackgroundColor3 = Theme.HexToColor3(spec.c2)
		b2.BorderSizePixel = 0
		b2.Parent = box

		local b3 = Instance.new("Frame")
		b3.Size = UDim2.fromScale(1, 0.34)
		b3.Position = UDim2.fromScale(0, 0.66)
		b3.BackgroundColor3 = Theme.HexToColor3(spec.c3)
		b3.BorderSizePixel = 0
		b3.Parent = box
	elseif spec.kind == "v3" then
		local b2 = Instance.new("Frame")
		b2.Size = UDim2.fromScale(0.34, 1)
		b2.Position = UDim2.fromScale(0.33, 0)
		b2.BackgroundColor3 = Theme.HexToColor3(spec.c2)
		b2.BorderSizePixel = 0
		b2.Parent = box

		local b3 = Instance.new("Frame")
		b3.Size = UDim2.fromScale(0.34, 1)
		b3.Position = UDim2.fromScale(0.66, 0)
		b3.BackgroundColor3 = Theme.HexToColor3(spec.c3)
		b3.BorderSizePixel = 0
		b3.Parent = box
	elseif spec.kind == "h2" then
		local b2 = Instance.new("Frame")
		b2.Size = UDim2.fromScale(1, 0.5)
		b2.Position = UDim2.fromScale(0, 0.5)
		b2.BackgroundColor3 = Theme.HexToColor3(spec.c2)
		b2.BorderSizePixel = 0
		b2.Parent = box
	elseif spec.kind == "jp" then
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromScale(0.42, 0.58)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.BackgroundColor3 = Theme.HexToColor3(spec.c2)
		dot.BorderSizePixel = 0
		UiWidgets.AddCorner(dot, 99)
		dot.Parent = box
	elseif spec.kind == "cross" then
		local hBar = Instance.new("Frame")
		hBar.Size = UDim2.fromScale(1, 0.28)
		hBar.Position = UDim2.fromScale(0, 0.36)
		hBar.BackgroundColor3 = Theme.HexToColor3(spec.c2)
		hBar.BorderSizePixel = 0
		hBar.Parent = box

		local vBar = Instance.new("Frame")
		vBar.Size = UDim2.fromScale(0.20, 1)
		vBar.Position = UDim2.fromScale(0.34, 0)
		vBar.BackgroundColor3 = Theme.HexToColor3(spec.c2)
		vBar.BorderSizePixel = 0
		vBar.Parent = box
	elseif spec.kind == "us" then
		for s = 1, 3 do
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.fromScale(1, 0.16)
			stripe.Position = UDim2.fromScale(0, (s * 2 - 1) * 0.16)
			stripe.BackgroundColor3 = Theme.HexToColor3(spec.c2)
			stripe.BorderSizePixel = 0
			stripe.Parent = box
		end
		local canton = Instance.new("Frame")
		canton.Size = UDim2.fromScale(0.48, 0.54)
		canton.BackgroundColor3 = Theme.HexToColor3(spec.c3)
		canton.BorderSizePixel = 0
		canton.Parent = box
	elseif spec.kind == "shinobi" then
		local plate = Instance.new("Frame")
		plate.Size = UDim2.fromScale(0.76, 0.62)
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.fromScale(0.5, 0.5)
		plate.BackgroundColor3 = Color3.fromRGB(203, 213, 225)
		plate.BorderSizePixel = 0
		UiWidgets.AddCorner(plate, 3)
		plate.Parent = box
	end

	if spec.symbol ~= nil then
		local sym = Instance.new("TextLabel")
		sym.Size = UDim2.fromScale(1, 1)
		sym.BackgroundTransparency = 1
		sym.Text = spec.symbol
		sym.TextScaled = true
		sym.TextColor3 = Color3.new(1, 1, 1)
		sym.Font = Enum.Font.GothamBold
		sym.Parent = box
	end

	return box
end

local PREVIEW_CHAR_COLORS: { [string]: Color3 } = {
	O = Color3.fromRGB(58, 114, 158),
	S = Color3.fromRGB(118, 166, 201),
	P = Color3.fromRGB(182, 214, 132),
	H = Color3.fromRGB(206, 188, 140),
	M = Color3.fromRGB(234, 234, 234),
	X = Color3.fromRGB(48, 52, 60),
}

-- Renders an authentic 2D map preview thumbnail directly from RawMapDefinition.preview (zero overlap/bleed)!
function UiWidgets.PopulateMapPreview(container: Frame, rawDef: any)
	container:ClearAllChildren()
	UiWidgets.AddCorner(container, 6)
	container.BackgroundColor3 = PREVIEW_CHAR_COLORS.O
	container.ClipsDescendants = true

	local pw: number = rawDef.previewW or 64
	local ph: number = rawDef.previewH or 36
	local pstr: string = rawDef.preview or ""
	if #pstr < pw * ph then
		return
	end

	local rowH = 1 / ph
	for y = 0, ph - 1 do
		local x = 0
		while x < pw do
			local idx = y * pw + x + 1
			local ch = string.sub(pstr, idx, idx)
			local run = 1
			while x + run < pw and string.sub(pstr, idx + run, idx + run) == ch do
				run += 1
			end
			if ch ~= "O" then
				local seg = Instance.new("Frame")
				seg.BorderSizePixel = 0
				seg.BackgroundTransparency = 0
				seg.BackgroundColor3 = PREVIEW_CHAR_COLORS[ch] or PREVIEW_CHAR_COLORS.P
				seg.Position = UDim2.fromScale(x / pw, y / ph)
				seg.Size = UDim2.new(run / pw + 0.0005, 0, rowH + 0.0008, 0)
				seg.Parent = container
			end
			x += run
		end
	end
end

function UiWidgets.MakeButton(
	parent: Instance,
	text: string,
	bgColor: Color3,
	size: UDim2,
	pos: UDim2?
): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	if pos ~= nil then
		btn.Position = pos
	end
	btn.BackgroundColor3 = bgColor
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.ClipsDescendants = true
	btn.Font = Enum.Font.GothamBold
	btn.Text = text
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 13
	btn.TextWrapped = true
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	UiWidgets.AddCorner(btn, 7)
	UiWidgets.AddStroke(btn, Color3.new(1, 1, 1), 1, 0.82)
	btn.Parent = parent
	return btn
end

return UiWidgets
