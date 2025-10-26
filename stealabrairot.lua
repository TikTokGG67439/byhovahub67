-- Strafe+Ring v4 — Полная переработка, исправлены ошибки и добавлены запрошенные фичи
-- Поместить как LocalScript в StarterPlayerScripts
-- Frame: 620x420, стиль Arcade, анимированные UiStroke и заголовок

-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0

-- ====== CONFIG ======
local SEARCH_RADIUS_DEFAULT = 15
local SEGMENTS = 64
local RING_RADIUS = 2.6
local SEGMENT_HEIGHT = 0.14
local SEGMENT_THICK = 0.45
local RING_HEIGHT_BASE = -1.5
local RING_COLOR = Color3.fromRGB(255, 0, 170)
local RING_TRANSP = 0.22

local SLIDER_LIMITS = {
	BV_POWER_MIN = 50,
	BV_POWER_MAX = 1000,
	BV_POWER_DEFAULT = 200,

	TWIST_MIN = 10,
	TWIST_MAX = 1000,
	TWIST_DEFAULT = 120,

	FORCE_SPEED_MIN = 10,
	FORCE_SPEED_MAX = 10000,
	FORCE_SPEED_DEFAULT = 120,

	FORCE_POWER_MIN = 50,
	FORCE_POWER_MAX = 8000,
	FORCE_POWER_DEFAULT = 1200,
}

local ORBIT_RADIUS_DEFAULT = 3.2
local ORBIT_SPEED_BASE = 2.2
local ALIGN_MAX_FORCE = 5e4
local ALIGN_MIN_FORCE = 500
local ALIGN_RESPONSIVENESS = 18

local HELPER_SPRING = 90
local HELPER_DAMP = 14
local HELPER_MAX_SPEED = 60
local HELPER_MAX_ACCEL = 4000
local HELPER_SMOOTH_INTERP = 12

local ORBIT_NOISE_FREQ = 0.45
local ORBIT_NOISE_AMP = 0.9
local ORBIT_BURST_CHANCE_PER_SEC = 0.6
local ORBIT_BURST_MIN = 1.2
local ORBIT_BURST_MAX = 3.2
local DRIFT_FREQ = 0.12
local DRIFT_AMP = 0.45

-- UI placement & requested size
local UI_POS = UDim2.new(0.5, -310, 0.82, -210)
local FRAME_SIZE = UDim2.new(0, 620, 0, 420)

-- ====== UTIL ======
local function getHRP(player)
	local ch = player and player.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

local function safeDestroy(obj)
	if obj and obj.Parent then
		pcall(function() obj:Destroy() end)
	end
end

local function charToKeyCode(str)
	if not str or #str == 0 then return nil end
	local s = tostring(str):upper()
	-- try direct mapping
	local ok, val = pcall(function() return Enum.KeyCode[s] end)
	if ok and val then return val end
	return nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a,b,t) return a + (b-a) * t end

-- ====== UI CREATION ======
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- remove old ui if exists
for _, c in ipairs(playerGui:GetChildren()) do
	if c.Name == "StrafeRingUI_v4_"..tostring(PlayerId) then safeDestroy(c) end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StrafeRingUI_v4_"..tostring(PlayerId)
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = FRAME_SIZE
frame.Position = UI_POS
frame.BackgroundColor3 = Color3.fromRGB(16,29,31) -- requested
frame.BackgroundTransparency = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0,10)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Thickness = 2
frameStroke.Parent = frame

-- animate stroke color between two violets
local strokeColors = {Color3.fromRGB(212,61,146), Color3.fromRGB(160,0,213)}
spawn(function()
	local idx = 1
	while frameStroke and frameStroke.Parent do
		local nextColor = strokeColors[idx]
		idx = idx % #strokeColors + 1
		local ok, tw = pcall(function()
			return TweenService:Create(frameStroke, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Color = nextColor})
		end)
		if ok and tw then tw:Play(); tw.Completed:Wait() end
		wait(0.06)
	end
end)

-- Title: Arcade font with animated color (whole text)
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0, 42)
title.Position = UDim2.new(0, 6, 0, 6)
title.BackgroundTransparency = 1
title.Text = "FioletusHub"
title.Font = Enum.Font.Arcade
title.TextSize = 32
title.TextScaled = false
title.TextColor3 = strokeColors[1]
title.TextStrokeTransparency = 0.7
title.Parent = frame

spawn(function()
	local i = 1
	while title and title.Parent do
		local col = strokeColors[i]
		i = i % #strokeColors + 1
		pcall(function()
			local tw = TweenService:Create(title, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {TextColor3 = col})
			tw:Play()
			tw.Completed:Wait()
		end)
		wait(0.05)
	end
end)

-- Helper to style non-frame controls
local function styleButton(btn)
	btn.Font = Enum.Font.Arcade
	btn.TextScaled = true
	btn.BackgroundColor3 = Color3.fromRGB(51,38,53)
	btn.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0,6)
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.6
	stroke.Color = Color3.fromRGB(212,61,146)
	stroke.Parent = btn
	return btn
end

local function styleTextBox(tb)
	tb.Font = Enum.Font.Arcade
	tb.TextScaled = true
	tb.BackgroundColor3 = Color3.fromRGB(51,38,53)
	tb.ClearTextOnFocus = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0,6)
	corner.Parent = tb
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.2
	stroke.Color = Color3.fromRGB(170,0,220)
	stroke.Parent = tb
	return tb
end

-- Toggle button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.20, -6, 0, 44)
toggleBtn.Position = UDim2.new(0, 6, 0, 66)
toggleBtn.Text = "OFF"
toggleBtn.Parent = frame
styleButton(toggleBtn)

local changeTargetBtn = Instance.new("TextButton")
changeTargetBtn.Size = UDim2.new(0.28, -6, 0, 44)
changeTargetBtn.Position = UDim2.new(0.22, 6, 0, 66)
changeTargetBtn.Text = "Change Target"
changeTargetBtn.Parent = frame
styleButton(changeTargetBtn)

local hotkeyBox = Instance.new("TextBox")
hotkeyBox.Size = UDim2.new(0.24, -6, 0, 44)
hotkeyBox.Position = UDim2.new(0.52, 6, 0, 66)
hotkeyBox.Text = "Hotkey: F"
hotkeyBox.Parent = frame
styleTextBox(hotkeyBox)

local chargeHotkeyBox = Instance.new("TextBox")
chargeHotkeyBox.Size = UDim2.new(0.24, -6, 0, 44)
chargeHotkeyBox.Position = UDim2.new(0.76, 6, 0, 66)
chargeHotkeyBox.Text = "Charge: G"
chargeHotkeyBox.Parent = frame
styleTextBox(chargeHotkeyBox)

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -12, 0, 22)
infoLabel.Position = UDim2.new(0, 6, 0, 116)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Nearest: — | Dist: — | Dir: CW | R: "..tostring(ORBIT_RADIUS_DEFAULT)
infoLabel.Font = Enum.Font.Arcade
infoLabel.TextSize = 14
infoLabel.TextColor3 = Color3.fromRGB(220,220,220)
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Parent = frame

-- PlayerESP button and gear
local espBtn = Instance.new("TextButton")
espBtn.Size = UDim2.new(0.24, -6, 0, 36)
espBtn.Position = UDim2.new(0.76, 6, 0, 146)
espBtn.Text = "PlayerESP"
espBtn.Parent = frame
styleButton(espBtn)

local espGearBtn = Instance.new("TextButton")
espGearBtn.Size = UDim2.new(0.12, -6, 0, 36)
espGearBtn.Position = UDim2.new(0.88, 6, 0, 146)
espGearBtn.Text = ""
espGearBtn.Parent = frame
styleButton(espGearBtn)

-- Mode buttons
local modeContainer = Instance.new("Frame", frame)
modeContainer.Size = UDim2.new(1, -12, 0, 40)
modeContainer.Position = UDim2.new(0, 6, 0, 186)
modeContainer.BackgroundTransparency = 1

local function makeModeButton(name, x)
	local b = Instance.new("TextButton", modeContainer)
	b.Size = UDim2.new(0.24, -8, 1, 0)
	b.Position = UDim2.new(x, 6, 0, 0)
	b.Text = name
	styleButton(b)
	return b
end

local btnSmooth = makeModeButton("Smooth", 0)
local btnVelocity = makeModeButton("Velocity", 0.26)
local btnTwisted = makeModeButton("Twisted", 0.52)
local btnForce = makeModeButton("Force", 0.78)

-- ====== SLIDER helper (styled) ======
local function createSlider(parent, yOffset, labelText, minVal, maxVal, initialVal, formatFn)
	local container = Instance.new("Frame", parent)
	container.Size = UDim2.new(1, -12, 0, 36)
	container.Position = UDim2.new(0, 6, 0, yOffset)
	container.BackgroundTransparency = 1

	local lbl = Instance.new("TextLabel", container)
	lbl.Size = UDim2.new(0.5, 0, 1, 0)
	lbl.Position = UDim2.new(0, 6, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.Arcade
	lbl.TextScaled = true

	local valLabel = Instance.new("TextLabel", container)
	valLabel.Size = UDim2.new(0.5, -8, 1, 0)
	valLabel.Position = UDim2.new(0.5, 0, 0, 0)
	valLabel.BackgroundTransparency = 1
	valLabel.Text = tostring(formatFn and formatFn(initialVal) or string.format("%.2f", initialVal))
	valLabel.Font = Enum.Font.Arcade
	valLabel.TextScaled = true
	valLabel.TextXAlignment = Enum.TextXAlignment.Right

	local sliderBg = Instance.new("Frame", container)
	sliderBg.Size = UDim2.new(1, -12, 0, 8)
	sliderBg.Position = UDim2.new(0, 6, 0, 20)
	sliderBg.BackgroundColor3 = Color3.fromRGB(40,40,40)
	sliderBg.BorderSizePixel = 0
	sliderBg.ClipsDescendants = true
	local bgCorner = Instance.new("UICorner", sliderBg); bgCorner.CornerRadius = UDim.new(0,4)
	local bgStroke = Instance.new("UIStroke", sliderBg); bgStroke.Color = Color3.fromRGB(170,0,220)

	local fill = Instance.new("Frame", sliderBg)
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Position = UDim2.new(0,0,0,0)
	fill.BackgroundColor3 = Color3.fromRGB(245,136,212)
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner", fill); fillCorner.CornerRadius = UDim.new(0,4)

	local thumb = Instance.new("Frame", sliderBg)
	thumb.Size = UDim2.new(0, 16, 0, 16)
	thumb.Position = UDim2.new(0, -8, 0.5, -8)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.BackgroundColor3 = Color3.fromRGB(245,136,212)
	thumb.BorderSizePixel = 0
	local thumbCorner = Instance.new("UICorner", thumb); thumbCorner.CornerRadius = UDim.new(0,2)
	local thumbStroke = Instance.new("UIStroke", thumb); thumbStroke.Color = Color3.fromRGB(245,136,212)

	local dragging = false
	local sliderWidth = 0
	local function recalc()
		sliderWidth = sliderBg.AbsoluteSize.X
	end
	sliderBg:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalc)
	recalc()

	local minV, maxV = minVal, maxVal

	local function setFromX(x)
		if sliderWidth <= 0 then return end
		local rel = clamp(x/sliderWidth, 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		thumb.Position = UDim2.new(rel, 0, 0.5, -8)
		local v = minV + (maxV - minV) * rel
		valLabel.Text = tostring(formatFn and formatFn(v) or string.format("%.2f", v))
		return v
	end

	sliderBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			local localX = input.Position.X - sliderBg.AbsolutePosition.X
			setFromX(localX)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)

	thumb.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.Position then
			local localX = input.Position.X - sliderBg.AbsolutePosition.X
			setFromX(localX)
		end
	end)

	UserInputService.TouchMoved:Connect(function(touch, g)
		if dragging then
			local localX = touch.Position.X - sliderBg.AbsolutePosition.X
			setFromX(localX)
		end
	end)

	local function getValue()
		local rel = 0
		if sliderWidth > 0 then rel = fill.AbsoluteSize.X / sliderWidth end
		return minV + (maxV - minV) * rel
	end

	local function setRange(minVv, maxVv, initV)
		minV, maxV = minVv, maxVv
		if initV then
			local rel = 0
			if maxV ~= minV then rel = (initV - minV) / (maxV - minV) end
			fill.Size = UDim2.new(clamp(rel,0,1),0,1,0)
			thumb.Position = UDim2.new(clamp(rel,0,1),0,0.5,-8)
			valLabel.Text = tostring(formatFn and formatFn(initV) or string.format("%.2f", initV))
		end
	end

	local function setLabel(txt) lbl.Text = txt end

	return {
		Container = container,
		GetValue = getValue,
		SetValue = function(v)
			if maxV == minV then return end
			local rel = (v - minV) / (maxV - minV)
			fill.Size = UDim2.new(clamp(rel,0,1),0,1,0)
			thumb.Position = UDim2.new(clamp(rel,0,1),0,0.5,-8)
			valLabel.Text = tostring(formatFn and formatFn(v) or string.format("%.2f", v))
		end,
		SetRange = setRange,
		SetLabel = setLabel,
		ValueLabel = valLabel,
	}
end

-- create sliders
local sliderSpeed = createSlider(frame, 236, "Orbit Speed", 0.2, 6.0, ORBIT_SPEED_BASE, function(v) return string.format("%.2f", v) end)
local sliderRadius = createSlider(frame, 284, "Orbit Radius", 0.5, 8.0, ORBIT_RADIUS_DEFAULT, function(v) return string.format("%.2f", v) end)
local sliderForce = createSlider(frame, 332, "Force Power", SLIDER_LIMITS.FORCE_POWER_MIN, SLIDER_LIMITS.FORCE_POWER_MAX, SLIDER_LIMITS.FORCE_POWER_DEFAULT, function(v) return string.format("%.0f", v) end)
sliderForce.Container.Visible = false
local sliderSearch = createSlider(frame, 380, "Search Radius", 5, 100, SEARCH_RADIUS_DEFAULT, function(v) return string.format("%.1f", v) end)

-- ====== RUNTIME STATE ======
local enabled = false
local currentTarget = nil
local ringParts = {}
local folder = nil

local mode = "smooth"

local attach0, helperPart, helperAttach, alignObj = nil, nil, nil, nil
local bvObj, bgObj, lvObj = nil, nil, nil
local vfObj, vfAttach, fallbackForceBV = nil, nil, nil

local charHumanoid = nil
local helperVel = Vector3.new(0,0,0)

local orbitAngle = math.random() * math.pi * 2
local orbitDirection = 1
local orbitRadius = ORBIT_RADIUS_DEFAULT
local ORBIT_SPEED = ORBIT_SPEED_BASE
local steeringInput = 0
local shiftHeld = false

local hotkeyKeyCode = Enum.KeyCode.F
local hotkeyStr = "F"
local hotkeyRequireCtrl, hotkeyRequireShift, hotkeyRequireAlt = false, false, false
local ctrlHeld, altHeld = false, false

local chargeKeyCode = Enum.KeyCode.G
local chargeHotkeyStr = "G"
local chargeRequireCtrl, chargeRequireShift, chargeRequireAlt = false, false, false

local cycleKeyCode = Enum.KeyCode.H
local cycleHotkeyStr = "H"

local burstTimer = 0
local burstStrength = 0
local driftPhase = math.random() * 1000

local chargeTimer = 0
local CHARGE_DURATION = 0.45
local CHARGE_STRENGTH = 4.0

local espEnabled = false
local playerHighlights = {}

local espColor = {R=212, G=61, B=146}

local autoJumpEnabled = false

-- persistence
local function saveState()
	if LocalPlayer and LocalPlayer.SetAttribute then
		LocalPlayer:SetAttribute("Strafe_v4_enabled", enabled)
		LocalPlayer:SetAttribute("Strafe_v4_mode", mode)
		LocalPlayer:SetAttribute("Strafe_v4_hotkey", hotkeyStr)
		LocalPlayer:SetAttribute("Strafe_v4_orbitRadius", orbitRadius)
		LocalPlayer:SetAttribute("Strafe_v4_orbitSpeed", ORBIT_SPEED)
		LocalPlayer:SetAttribute("Strafe_v4_forcePower", sliderForce.GetValue())
		LocalPlayer:SetAttribute("Strafe_v4_chargeHotkey", chargeHotkeyStr)
		LocalPlayer:SetAttribute("Strafe_v4_searchRadius", sliderSearch.GetValue())
		LocalPlayer:SetAttribute("Strafe_v4_esp", espEnabled)
		LocalPlayer:SetAttribute("Strafe_v4_espR", espColor.R)
		LocalPlayer:SetAttribute("Strafe_v4_espG", espColor.G)
		LocalPlayer:SetAttribute("Strafe_v4_espB", espColor.B)
		LocalPlayer:SetAttribute("Strafe_v4_autoJump", autoJumpEnabled)
	end
end

local function loadState()
	if LocalPlayer and LocalPlayer.GetAttribute then
		local m = LocalPlayer:GetAttribute("Strafe_v4_mode")
		if m and type(m)=="string" then mode = m end
		local e = LocalPlayer:GetAttribute("Strafe_v4_enabled")
		if e ~= nil then enabled = e end
		local hk = LocalPlayer:GetAttribute("Strafe_v4_hotkey")
		if hk and type(hk)=="string" then hotkeyStr = hk end
		local r = LocalPlayer:GetAttribute("Strafe_v4_orbitRadius")
		if r then orbitRadius = r; sliderRadius.SetValue(orbitRadius) end
		local s = LocalPlayer:GetAttribute("Strafe_v4_orbitSpeed")
		if s then ORBIT_SPEED = s; sliderSpeed.SetValue(ORBIT_SPEED) end
		local fp = LocalPlayer:GetAttribute("Strafe_v4_forcePower")
		if fp then sliderForce.SetValue(fp) end
		local ch = LocalPlayer:GetAttribute("Strafe_v4_chargeHotkey")
		if ch and type(ch)=="string" then chargeHotkeyStr = ch end
		local sr = LocalPlayer:GetAttribute("Strafe_v4_searchRadius")
		if sr then sliderSearch.SetValue(sr) end
		local espS = LocalPlayer:GetAttribute("Strafe_v4_esp")
		if espS ~= nil then espEnabled = espS end
		local rcol = LocalPlayer:GetAttribute("Strafe_v4_espR")
		local gcol = LocalPlayer:GetAttribute("Strafe_v4_espG")
		local bcol = LocalPlayer:GetAttribute("Strafe_v4_espB")
		if rcol and gcol and bcol then espColor.R = rcol; espColor.G = gcol; espColor.B = bcol end
		autoJumpEnabled = LocalPlayer:GetAttribute("Strafe_v4_autoJump") or false
	end
end

-- ring helpers
local function ensureFolder()
	if folder and folder.Parent then return end
	folder = Instance.new("Folder")
	folder.Name = "StrafeRing_v4_"..tostring(PlayerId)
	folder.Parent = workspace
end

local function clearRing()
	if folder then
		for _, v in ipairs(folder:GetChildren()) do safeDestroy(v) end
	end
	ringParts = {}
end

local function createRingSegments(count)
	clearRing()
	ensureFolder()
	local circumference = 2 * math.pi * RING_RADIUS
	local segLen = (circumference / count) * 1.14
	for i = 1, count do
		local part = Instance.new("Part")
		part.Size = Vector3.new(segLen, SEGMENT_HEIGHT, SEGMENT_THICK)
		part.Anchored = true
		part.CanCollide = false
		part.Locked = true
		part.Material = Enum.Material.Neon
		part.Color = RING_COLOR
		part.Transparency = RING_TRANSP
		part.CastShadow = false
		part.Name = "RingSeg"
		part.Parent = folder
		table.insert(ringParts, part)
	end
end

-- MODE object creators (smooth/velocity/twisted/force)
local function createSmoothObjectsFor(hrp)
	if alignObj or helperPart then return end
	attach0 = Instance.new("Attachment")
	attach0.Name = "StrafeAttach0_"..tostring(PlayerId)
	attach0.Parent = hrp

	helperPart = Instance.new("Part")
	helperPart.Name = "StrafeHelperPart_"..tostring(PlayerId)
	helperPart.Size = Vector3.new(0.2,0.2,0.2)
	helperPart.Transparency = 1
	helperPart.Anchored = true
	helperPart.CanCollide = false
	helperPart.CFrame = hrp.CFrame
	helperPart.Parent = workspace

	helperAttach = Instance.new("Attachment")
	helperAttach.Name = "StrafeAttach1_"..tostring(PlayerId)
	helperAttach.Parent = helperPart

	alignObj = Instance.new("AlignPosition")
	alignObj.Name = "StrafeAlignPos_"..tostring(PlayerId)
	alignObj.Attachment0 = attach0
	alignObj.Attachment1 = helperAttach
	alignObj.MaxForce = ALIGN_MIN_FORCE
	alignObj.Responsiveness = ALIGN_RESPONSIVENESS
	alignObj.RigidityEnabled = false
	pcall(function() alignObj.MaxVelocity = HELPER_MAX_SPEED end)
	alignObj.Parent = hrp

	helperVel = Vector3.new(0,0,0)
end

local function destroySmoothObjects()
	safeDestroy(alignObj); alignObj = nil
	safeDestroy(attach0); attach0 = nil
	safeDestroy(helperAttach); helperAttach = nil
	safeDestroy(helperPart); helperPart = nil
	helperVel = Vector3.new(0,0,0)
end

local function createVelocityObjectsFor(hrp)
	if bvObj or bgObj then return end
	local bv = Instance.new("BodyVelocity")
	bv.Name = "Strafe_BV_"..tostring(PlayerId)
	bv.MaxForce = Vector3.new(ALIGN_MIN_FORCE, ALIGN_MIN_FORCE, ALIGN_MIN_FORCE)
	bv.P = 2500
	bv.Velocity = Vector3.new(0,0,0)
	bv.Parent = hrp

	local bg = Instance.new("BodyGyro")
	bg.Name = "Strafe_BG_"..tostring(PlayerId)
	bg.MaxTorque = Vector3.new(ALIGN_MIN_FORCE, ALIGN_MIN_FORCE, ALIGN_MIN_FORCE)
	bg.P = 2000
	bg.CFrame = hrp.CFrame
	bg.Parent = hrp

	bvObj, bgObj = bv, bg
end

local function destroyVelocityObjects()
	safeDestroy(bvObj); bvObj = nil
	safeDestroy(bgObj); bgObj = nil
end

local function createLinearObjectsFor(hrp)
	if lvObj then return end
	local att = hrp:FindFirstChild("StrafeLVAttach")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "StrafeLVAttach"
		att.Parent = hrp
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Strafe_LV_"..tostring(PlayerId)
	lv.Attachment0 = att
	lv.MaxForce = 0
	lv.VectorVelocity = Vector3.new(0,0,0)
	lv.Parent = hrp
	lvObj = lv
end

local function destroyLinearObjects()
	safeDestroy(lvObj); lvObj = nil
	local hrp = getHRP(LocalPlayer)
	if hrp then
		local att = hrp:FindFirstChild("StrafeLVAttach")
		if att then safeDestroy(att) end
	end
end

local function createForceObjectsFor(hrp)
	if vfObj or fallbackForceBV then return end
	local att = hrp:FindFirstChild("StrafeVFAttach")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "StrafeVFAttach"
		att.Parent = hrp
	end
	vfAttach = att
	local ok, vf = pcall(function()
		local v = Instance.new("VectorForce")
		v.Name = "Strafe_VectorForce_"..tostring(PlayerId)
		v.Attachment0 = att
		pcall(function() v.RelativeTo = Enum.ActuatorRelativeTo.World end)
		v.Force = Vector3.new(0,0,0)
		v.Parent = hrp
		return v
	end)
	if ok and vf then
		vfObj = vf
	else
		local ok2, bv = pcall(function()
			local b = Instance.new("BodyVelocity")
			b.Name = "Strafe_ForceBV_"..tostring(PlayerId)
			b.MaxForce = Vector3.new(0,0,0)
			b.P = 3000
			b.Velocity = Vector3.new(0,0,0)
			b.Parent = hrp
			return b
		end)
		if ok2 and bv then fallbackForceBV = bv end
	end
end

local function destroyForceObjects()
	if vfObj then safeDestroy(vfObj); vfObj = nil end
	if fallbackForceBV then safeDestroy(fallbackForceBV); fallbackForceBV = nil end
	local hrp = getHRP(LocalPlayer)
	if hrp then
		local att = hrp:FindFirstChild("StrafeVFAttach")
		if att then safeDestroy(att) end
	end
end

local function destroyModeObjects()
	destroySmoothObjects()
	destroyVelocityObjects()
	destroyLinearObjects()
	destroyForceObjects()
end

-- TARGET management
local function setTarget(player, forceClear)
	if player == nil then
		currentTarget = nil
		clearRing()
		destroyModeObjects()
		return
	end
	if currentTarget == player and not forceClear then return end
	currentTarget = player
	clearRing()
	destroyModeObjects()
	if player then
		createRingSegments(SEGMENTS)
		orbitAngle = math.random() * math.pi * 2
		local myHRP = getHRP(LocalPlayer)
		if myHRP then
			if mode == "smooth" then createSmoothObjectsFor(myHRP)
			elseif mode == "velocity" then createVelocityObjectsFor(myHRP)
			elseif mode == "twisted" then createLinearObjectsFor(myHRP)
			elseif mode == "force" then createForceObjectsFor(myHRP) end
		end
	end
	saveState()
end

local function cycleTarget()
	local list = {}
	local myHRP = getHRP(LocalPlayer)
	if not myHRP then return end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local hrp = getHRP(p)
			if hrp then
				local d = (hrp.Position - myHRP.Position).Magnitude
				if d <= tonumber(sliderSearch.GetValue() or SEARCH_RADIUS_DEFAULT) then table.insert(list, {player=p, dist=d}) end
			end
		end
	end
	table.sort(list, function(a,b) return a.dist < b.dist end)
	if #list == 0 then setTarget(nil); return end
	if not currentTarget then setTarget(list[1].player); return end
	local idx = nil
	for i,v in ipairs(list) do if v.player == currentTarget then idx = i; break end end
	if not idx then setTarget(list[1].player); return end
	setTarget(list[idx % #list + 1].player)
end

-- UI Mode handling + AutoJump visibility
local autoJumpBtn = nil
local function updateAutoJumpUIVisibility()
	if autoJumpBtn then
		autoJumpBtn.Visible = (mode == "force")
	end
end

local function applyModeUI()
	local function setActive(btn, active)
		if active then
			btn.BackgroundTransparency = 0.2
			btn.BackgroundColor3 = Color3.fromRGB(100,40,120)
		else
			btn.BackgroundTransparency = 0
			btn.BackgroundColor3 = Color3.fromRGB(51,38,53)
		end
	end
	setActive(btnSmooth, mode=="smooth")
	setActive(btnVelocity, mode=="velocity")
	setActive(btnTwisted, mode=="twisted")
	setActive(btnForce, mode=="force")

	if mode == "smooth" then
		sliderSpeed.SetLabel("Orbit Speed")
		sliderSpeed.SetRange(0.2, 6.0, ORBIT_SPEED)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = false
	elseif mode == "velocity" then
		sliderSpeed.SetLabel("BV Power")
		sliderSpeed.SetRange(SLIDER_LIMITS.BV_POWER_MIN, SLIDER_LIMITS.BV_POWER_MAX, SLIDER_LIMITS.BV_POWER_DEFAULT)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = false
	elseif mode == "twisted" then
		sliderSpeed.SetLabel("Twist Power")
		sliderSpeed.SetRange(SLIDER_LIMITS.TWIST_MIN, SLIDER_LIMITS.TWIST_MAX, SLIDER_LIMITS.TWIST_DEFAULT)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = false
	elseif mode == "force" then
		sliderSpeed.SetLabel("Force Speed")
		sliderSpeed.SetRange(SLIDER_LIMITS.FORCE_SPEED_MIN, SLIDER_LIMITS.FORCE_SPEED_MAX, SLIDER_LIMITS.FORCE_SPEED_DEFAULT)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = true
		sliderForce.SetRange(SLIDER_LIMITS.FORCE_POWER_MIN, SLIDER_LIMITS.FORCE_POWER_MAX, SLIDER_LIMITS.FORCE_POWER_DEFAULT)
	end

	updateAutoJumpUIVisibility()
end

btnSmooth.MouseButton1Click:Connect(function()
	if mode ~= "smooth" then
		mode = "smooth"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createSmoothObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)
btnVelocity.MouseButton1Click:Connect(function()
	if mode ~= "velocity" then
		mode = "velocity"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createVelocityObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)
btnTwisted.MouseButton1Click:Connect(function()
	if mode ~= "twisted" then
		mode = "twisted"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createLinearObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)
btnForce.MouseButton1Click:Connect(function()
	if mode ~= "force" then
		mode = "force"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createForceObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)

-- Hotkey parsing
local function parseHotkeyString(txt)
	if not txt then return nil end
	local s = tostring(txt):gsub("^%s*(.-)%s*$","%1")
	-- allow strings both with or without prefix
	s = s:gsub("^Hotkey:%s*", "")
	s = s:gsub("^Charge:%s*", "")
	s = s:gsub("^Cycle:%s*", "")
	s = s:upper()
	local parts = {}
	for token in s:gmatch("[^%+]+") do
		token = token:gsub("^%s*(.-)%s*$","%1")
		table.insert(parts, token)
	end
	local reqCtrl, reqShift, reqAlt = false, false, false
	local primary = nil
	for _, tok in ipairs(parts) do
		if tok == "CTRL" or tok == "CONTROL" then reqCtrl = true
		elseif tok == "SHIFT" then reqShift = true
		elseif tok == "ALT" then reqAlt = true
		else
			local kc = charToKeyCode(tok)
			if kc then primary = kc end
		end
	end
	if not primary then return nil end
	return primary, reqCtrl, reqShift, reqAlt
end

hotkeyBox.FocusLost:Connect(function()
	local txt = tostring(hotkeyBox.Text or ""):gsub("^%s*(.-)%s*$","%1")
	if #txt == 0 then hotkeyBox.Text = "Hotkey: "..(hotkeyStr or "F"); return end
	local primary, rCtrl, rShift, rAlt = parseHotkeyString(txt)
	if primary then
		hotkeyKeyCode = primary
		hotkeyRequireCtrl = rCtrl
		hotkeyRequireShift = rShift
		hotkeyRequireAlt = rAlt
		local parts = {}
		if hotkeyRequireCtrl then table.insert(parts, "Ctrl") end
		if hotkeyRequireShift then table.insert(parts, "Shift") end
		if hotkeyRequireAlt then table.insert(parts, "Alt") end
		table.insert(parts, tostring(hotkeyKeyCode.Name))
		hotkeyStr = table.concat(parts, "+")
		hotkeyBox.Text = "Hotkey: "..hotkeyStr
		infoLabel.Text = "Hotkey set: "..hotkeyStr
		saveState()
	else
		hotkeyBox.Text = "Hotkey: "..(hotkeyStr or "F")
		infoLabel.Text = "Invalid hotkey."
	end
end)

chargeHotkeyBox.FocusLost:Connect(function()
	local txt = tostring(chargeHotkeyBox.Text or ""):gsub("^%s*(.-)%s*$","%1")
	if #txt == 0 then chargeHotkeyBox.Text = "Charge: "..(chargeHotkeyStr or "G"); return end
	local primary, rCtrl, rShift, rAlt = parseHotkeyString(txt)
	if primary then
		chargeKeyCode = primary
		chargeRequireCtrl = rCtrl
		chargeRequireShift = rShift
		chargeRequireAlt = rAlt
		local parts = {}
		if chargeRequireCtrl then table.insert(parts, "Ctrl") end
		if chargeRequireShift then table.insert(parts, "Shift") end
		if chargeRequireAlt then table.insert(parts, "Alt") end
		table.insert(parts, tostring(chargeKeyCode.Name))
		chargeHotkeyStr = table.concat(parts, "+")
		chargeHotkeyBox.Text = "Charge: "..chargeHotkeyStr
		infoLabel.Text = "Charge hotkey set: "..chargeHotkeyStr
		saveState()
	else
		chargeHotkeyBox.Text = "Charge: "..(chargeHotkeyStr or "G")
		infoLabel.Text = "Invalid charge hotkey."
	end
end)

-- Toggle
local function updateToggleUI()
	toggleBtn.Text = enabled and "ON" or "OFF"
	toggleBtn.BackgroundColor3 = enabled and Color3.fromRGB(120,220,120) or Color3.fromRGB(220,120,120)
end

toggleBtn.MouseButton1Click:Connect(function()
	enabled = not enabled
	updateToggleUI()
	if not enabled then
		setTarget(nil, true)
		destroyModeObjects()
		infoLabel.Text = "Disabled"
	else
		infoLabel.Text = "Enabled: searching..."
		if currentTarget then
			local myHRP = getHRP(LocalPlayer)
			if myHRP then
				if mode == "smooth" then createSmoothObjectsFor(myHRP)
				elseif mode == "velocity" then createVelocityObjectsFor(myHRP)
				elseif mode == "twisted" then createLinearObjectsFor(myHRP)
				elseif mode == "force" then createForceObjectsFor(myHRP) end
			end
		end
	end
	saveState()
end)

changeTargetBtn.MouseButton1Click:Connect(cycleTarget)

-- ====== ESP panel (separate) ======
local espPickerFrame = Instance.new("Frame")
espPickerFrame.Size = UDim2.new(0, 260, 0, 140)
espPickerFrame.Position = UDim2.new(0.5, -130, 0.5, -70)
espPickerFrame.BackgroundColor3 = Color3.fromRGB(16,29,31)
espPickerFrame.Visible = false
espPickerFrame.Parent = screenGui
local espPickerCorner = Instance.new("UICorner", espPickerFrame); espPickerCorner.CornerRadius = UDim.new(0,8)
local espPickerStroke = Instance.new("UIStroke", espPickerFrame); espPickerStroke.Thickness = 1.6; espPickerStroke.Color = Color3.fromRGB(160,0,213)

local rSlider = createSlider(espPickerFrame, 8, "R", 1, 255, espColor.R, function(v) return tostring(math.floor(v)) end)
rSlider.Container.Position = UDim2.new(0, 8, 0, 8)
rSlider.Container.Size = UDim2.new(1, -16, 0, 28)
local gSlider = createSlider(espPickerFrame, 56, "G", 1, 255, espColor.G, function(v) return tostring(math.floor(v)) end)
gSlider.Container.Position = UDim2.new(0, 8, 0, 44)
gSlider.Container.Size = UDim2.new(1, -16, 0, 28)
local bSlider = createSlider(espPickerFrame, 104, "B", 1, 255, espColor.B, function(v) return tostring(math.floor(v)) end)
bSlider.Container.Position = UDim2.new(0, 8, 0, 80)
bSlider.Container.Size = UDim2.new(1, -16, 0, 28)

-- color preview (no text)
local colorPreview = Instance.new("TextLabel", espPickerFrame)
colorPreview.Size = UDim2.new(0, 48, 0, 48)
colorPreview.Position = UDim2.new(1, -56, 0, 8)
colorPreview.BackgroundColor3 = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
colorPreview.Text = ""
local cpCorner = Instance.new("UICorner", colorPreview); cpCorner.CornerRadius = UDim.new(0,6)

-- remove Apply button: live update

local function enableESPForPlayer(p)
	if not p or p == LocalPlayer then return end
	if playerHighlights[p] and playerHighlights[p].Parent then return end
	local ch = p.Character
	if not ch then return end
	local hl = Instance.new("Highlight")
	hl.Name = "StrafeESP_Highlight"
	hl.Adornee = ch
	hl.FillTransparency = 0.4
	hl.OutlineTransparency = 0
	hl.FillColor = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
	hl.Parent = ch
	playerHighlights[p] = hl
end

local function disableESPForPlayer(p)
	local hl = playerHighlights[p]
	if hl then
		safeDestroy(hl)
		playerHighlights[p] = nil
	end
end

local function updateESP(enabledFlag)
	espEnabled = enabledFlag
	if espEnabled then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then enableESPForPlayer(p) end
		end
		espBtn.TextColor3 = Color3.fromRGB(134,34,177)
	else
		for p,_ in pairs(playerHighlights) do disableESPForPlayer(p) end
		espBtn.TextColor3 = Color3.fromRGB(206,30,144)
	end
	saveState()
end

espBtn.MouseButton1Click:Connect(function() updateESP(not espEnabled) end)
espGearBtn.MouseButton1Click:Connect(function()
	espPickerFrame.Visible = not espPickerFrame.Visible
	if espPickerFrame.Visible then
		rSlider.SetValue(espColor.R)
		gSlider.SetValue(espColor.G)
		bSlider.SetValue(espColor.B)
	end
end)

-- live update color sliders
RunService.RenderStepped:Connect(function()
	if espPickerFrame.Visible then
		local r = math.floor(rSlider.GetValue())
		local g = math.floor(gSlider.GetValue())
		local b = math.floor(bSlider.GetValue())
		espColor.R, espColor.G, espColor.B = r, g, b
		colorPreview.BackgroundColor3 = Color3.fromRGB(r,g,b)
		-- update existing highlights live
		for p, hl in pairs(playerHighlights) do
			if hl and hl.Parent then hl.FillColor = Color3.fromRGB(r,g,b) end
		end
	end
end)

-- keep ESP updated for joining players
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		if espEnabled and p ~= LocalPlayer then enableESPForPlayer(p) end
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	disableESPForPlayer(p)
	if p == currentTarget then setTarget(nil, true) end
end)

-- ====== AutoJump in Force mode UI =====n
autoJumpBtn = Instance.new("TextButton", frame)
autoJumpBtn.Size = UDim2.new(0, 120, 0, 34)
autoJumpBtn.Position = UDim2.new(0.02, 6, 0, 232)
autoJumpBtn.Text = "AutoJump: OFF"
styleButton(autoJumpBtn)
autoJumpBtn.Visible = false -- only show in Force mode

local function updateAutoJumpUI()
	autoJumpBtn.Text = "AutoJump: " .. (autoJumpEnabled and "ON" or "OFF")
	autoJumpBtn.TextColor3 = autoJumpEnabled and Color3.fromRGB(134,34,177) or Color3.fromRGB(206,30,144)
end

autoJumpBtn.MouseButton1Click:Connect(function()
	autoJumpEnabled = not autoJumpEnabled
	updateAutoJumpUI()
	saveState()
end)

-- ====== INPUT handling (hotkey + charge + cycle + steering) ======
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local kc = input.KeyCode
		if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl then ctrlHeld = true end
		if kc == Enum.KeyCode.LeftAlt or kc == Enum.KeyCode.RightAlt then altHeld = true end
		if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then shiftHeld = true end

		if kc == Enum.KeyCode.A then steeringInput = -1
		elseif kc == Enum.KeyCode.D then steeringInput = 1
		elseif kc == Enum.KeyCode.Z then orbitRadius = math.max(0.5, orbitRadius - 0.2); sliderRadius.SetValue(orbitRadius)
		elseif kc == Enum.KeyCode.X then orbitRadius = math.min(8, orbitRadius + 0.2); sliderRadius.SetValue(orbitRadius)
		end

		-- main hotkey toggle
		if kc == hotkeyKeyCode then
			local okCtrl = (not hotkeyRequireCtrl) or ctrlHeld
			local okShift = (not hotkeyRequireShift) or shiftHeld
			local okAlt = (not hotkeyRequireAlt) or altHeld
			if okCtrl and okShift and okAlt then
				enabled = not enabled
				updateToggleUI()
				if enabled then
					infoLabel.Text = "Enabled: searching..."
					if currentTarget then
						local myHRP = getHRP(LocalPlayer)
						if myHRP then
							if mode == "smooth" then createSmoothObjectsFor(myHRP)
							elseif mode == "velocity" then createVelocityObjectsFor(myHRP)
							elseif mode == "twisted" then createLinearObjectsFor(myHRP)
							elseif mode == "force" then createForceObjectsFor(myHRP) end
						end
					end
				else
					setTarget(nil, true)
					destroyModeObjects()
					infoLabel.Text = "Disabled"
				end
				saveState()
			end
		end

		-- charge hotkey
		if kc == chargeKeyCode then
			local okCtrl = true
			local okShift = true
			local okAlt = true
			if okCtrl and okShift and okAlt then
				if currentTarget then
					chargeTimer = CHARGE_DURATION
					infoLabel.Text = ("Charging %s..."):format(tostring(currentTarget.Name))
					-- charge should shift target quickly: we'll cycle target when charged
				end
			end
		end

		-- cycle target separate hotkey
		if kc == cycleKeyCode then cycleTarget() end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local kc = input.KeyCode
		if kc == Enum.KeyCode.A or kc == Enum.KeyCode.D then steeringInput = 0 end
		if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then shiftHeld = false end
		if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl then ctrlHeld = false end
		if kc == Enum.KeyCode.LeftAlt or kc == Enum.KeyCode.RightAlt then altHeld = false end
	end
end)

-- ====== Character handlers ======
LocalPlayer.CharacterAdded:Connect(function(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		charHumanoid = char:FindFirstChildOfClass("Humanoid")
		if enabled and currentTarget then
			destroyModeObjects()
			if mode == "smooth" then createSmoothObjectsFor(hrp)
			elseif mode == "velocity" then createVelocityObjectsFor(hrp)
			elseif mode == "twisted" then createLinearObjectsFor(hrp)
			elseif mode == "force" then createForceObjectsFor(hrp) end
		end
		if espEnabled then
			for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then enableESPForPlayer(p) end end
		end
	end
end)
LocalPlayer.CharacterRemoving:Connect(function() charHumanoid = nil; destroyModeObjects(); clearRing() end)

-- ====== AutoJump behavior (used only in Force mode when enabled)
local function tryAutoJump()
	if not autoJumpEnabled then return end
	if mode ~= "force" then return end
	if not enabled then return end
	local hrp = getHRP(LocalPlayer)
	if not hrp then return end
	local humanoid = charHumanoid
	if not humanoid then return end
	-- check on ground by Raycast down small distance
	local origin = hrp.Position
	local ray = Ray.new(origin, Vector3.new(0, -3, 0))
	local part, pos = workspace:FindPartOnRay(ray, LocalPlayer.Character)
	if part then
		humanoid.Jump = true
	end
end

-- ====== MAIN LOOP ======
local startTick = tick()
RunService.RenderStepped:Connect(function(dt)
	if dt > 0.12 then dt = 0.12 end
	local now = tick()
	local t = now - startTick

	-- sliders
	local sVal = tonumber(sliderSpeed.GetValue() or ORBIT_SPEED) or ORBIT_SPEED
	local rVal = tonumber(sliderRadius.GetValue() or orbitRadius) or orbitRadius
	if mode == "smooth" then ORBIT_SPEED = sVal; orbitRadius = rVal
	else orbitRadius = rVal end

	local newSearch = tonumber(sliderSearch.GetValue() or SEARCH_RADIUS_DEFAULT) or SEARCH_RADIUS_DEFAULT

	local forcePower = tonumber(sliderForce.GetValue() or SLIDER_LIMITS.FORCE_POWER_DEFAULT) or SLIDER_LIMITS.FORCE_POWER_DEFAULT

	if chargeTimer > 0 then
		chargeTimer = math.max(0, chargeTimer - dt)
		if chargeTimer == 0 then
			-- perform a cycle on charge finish to mimic "change target" action
			cycleTarget()
		end
	end

	if not enabled then return end

	local myHRP = getHRP(LocalPlayer)
	if not myHRP then setTarget(nil, true); return end

	-- auto-find target when none
	if not currentTarget then
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then
				local hrp = getHRP(p)
				if hrp then
					local d = (hrp.Position - myHRP.Position).Magnitude
					if d <= newSearch then table.insert(list, {player=p, dist=d}) end
				end
			end
		end
		table.sort(list, function(a,b) return a.dist < b.dist end)
		if #list > 0 then setTarget(list[1].player) end
	end

	local targetHRP = currentTarget and getHRP(currentTarget) or nil
	if not targetHRP then
		if attach0 or alignObj or bvObj or bgObj or lvObj or vfObj or vfAttach or fallbackForceBV then destroyModeObjects() end
		infoLabel.Text = "Nearest: — | Dist: — | Dir: " .. (orbitDirection==1 and "CW" or "CCW") .. " | R: " .. string.format("%.2f", orbitRadius)
		clearRing()
		return
	else
		local distToMe = (targetHRP.Position - myHRP.Position).Magnitude
		if distToMe > newSearch then setTarget(nil, true); return end
		infoLabel.Text = ("Nearest: %s | Dist: %.1f | Dir: %s | R: %.2f"):format(tostring(currentTarget.Name), distToMe, (orbitDirection==1 and "CW" or "CCW"), orbitRadius)
	end

	-- draw ring
	if currentTarget and #ringParts == 0 then createRingSegments(SEGMENTS) end
	if currentTarget and targetHRP and #ringParts > 0 then
		local levOffset = math.sin(t * 1.0) * 0.22 + (math.noise(t * 0.7, PlayerId * 0.01) - 0.5) * 0.06
		local basePos = targetHRP.Position + Vector3.new(0, RING_HEIGHT_BASE + levOffset, 0)
		local angleStep = (2 * math.pi) / #ringParts
		for i, part in ipairs(ringParts) do
			if not part or not part.Parent then createRingSegments(SEGMENTS); break end
			local angle = (i - 1) * angleStep
			local radialPulse = math.sin(t * 1.35 + angle * 1.1) * 0.05
			local r = RING_RADIUS + radialPulse + (math.noise(i * 0.03, t * 0.6) - 0.5) * 0.03
			local bob =
				math.sin(t * 2.0 + angle * 0.8) * 0.28 +
				math.sin(t * 0.6 + angle * 0.45) * (0.28 * 0.25) +
				math.cos(t * 0.9 + angle * 0.3) * (0.28 * 0.08)
			local x = math.cos(angle) * r
			local z = math.sin(angle) * r
			local pos = basePos + Vector3.new(x, bob, z)
			local dirToCenter = (basePos - pos)
			if dirToCenter.Magnitude < 0.001 then dirToCenter = Vector3.new(0,0,1) end
			local lookAt = dirToCenter.Unit
			local up = Vector3.new(0,1,0)
			local right = up:Cross(lookAt)
			if right.Magnitude < 0.001 then right = Vector3.new(1,0,0) else right = right.Unit end
			local forward = lookAt
			local cframe = CFrame.fromMatrix(pos, right, up, -forward)
			cframe = cframe * CFrame.new(0, SEGMENT_HEIGHT/2, 0)
			part.CFrame = cframe
		end
	end

	-- orbit math
	if burstTimer > 0 then
		burstTimer = math.max(0, burstTimer - dt)
		if burstTimer == 0 then burstStrength = 0 end
	else
		if math.random() < ORBIT_BURST_CHANCE_PER_SEC * dt then
			burstStrength = (math.random() < 0.5 and -1 or 1) * (ORBIT_BURST_MIN + math.random() * (ORBIT_BURST_MAX - ORBIT_BURST_MIN))
			burstTimer = 0.18 + math.random() * 0.26
		end
	end

	local noise = (math.noise(t * ORBIT_NOISE_FREQ, PlayerId * 0.01) - 0.5) * ORBIT_NOISE_AMP
	local drift = math.sin(t * DRIFT_FREQ + driftPhase) * DRIFT_AMP

	local effectiveBaseSpeed = ORBIT_SPEED * (1 + noise)
	if shiftHeld then effectiveBaseSpeed = effectiveBaseSpeed * 1.6 end

	local myDist = nil
	local radialError = 0
	if currentTarget and targetHRP then
		myDist = (myHRP.Position - targetHRP.Position).Magnitude
		radialError = myDist - orbitRadius
	end
	local speedBias = clamp(radialError * 0.45, -2.2, 2.2)

	local chargeEffect = 0
	if chargeTimer > 0 then chargeEffect = CHARGE_STRENGTH end
	local burstEffect = burstStrength * (burstTimer > 0 and 1 or 0)

	orbitAngle = orbitAngle + (orbitDirection * (effectiveBaseSpeed * (1 + chargeEffect*0.05) + speedBias + burstEffect) + steeringInput * 1.8) * dt

	local desiredRadius = orbitRadius + drift * 0.6
	if myDist and myDist < desiredRadius - 0.6 then desiredRadius = desiredRadius + (desiredRadius - myDist) * 0.35 end

	local ox = math.cos(orbitAngle) * desiredRadius
	local oz = math.sin(orbitAngle) * desiredRadius
	local targetPos = targetHRP.Position + Vector3.new(ox, 1.2, oz)

	-- MODE application
	if mode == "smooth" then
		if not (alignObj and helperPart and attach0) then createSmoothObjectsFor(myHRP) end
		if alignObj and helperPart then
			local curPos = helperPart.Position
			local toTarget = (targetPos - curPos)
			local accel = toTarget * HELPER_SPRING - helperVel * HELPER_DAMP
			local aMag = accel.Magnitude
			if aMag > HELPER_MAX_ACCEL then accel = accel.Unit * HELPER_MAX_ACCEL end
			local candidateVel = helperVel + accel * dt
			if candidateVel.Magnitude > HELPER_MAX_SPEED then candidateVel = candidateVel.Unit * HELPER_MAX_SPEED end
			local interp = clamp(HELPER_SMOOTH_INTERP * dt, 0, 1)
			helperVel = Vector3.new(lerp(helperVel.X, candidateVel.X, interp), lerp(helperVel.Y, candidateVel.Y, interp), lerp(helperVel.Z, candidateVel.Z, interp))
			local newPos = curPos + helperVel * dt
			local maxStep = math.max(3, HELPER_MAX_SPEED * 0.2) * dt
			local toNew = newPos - curPos
			if toNew.Magnitude > maxStep then newPos = curPos + toNew.Unit * maxStep end
			if chargeTimer > 0 then
				local chargeDir = (targetPos - curPos)
				if chargeDir.Magnitude > 0.01 then
					local n = chargeDir.Unit * (math.max(10, HELPER_MAX_SPEED) * 0.7) * (chargeTimer/CHARGE_DURATION)
					newPos = newPos + n * dt
				end
			end
			helperPart.CFrame = CFrame.new(newPos)
			local playerMoving = false
			if charHumanoid then local mv = charHumanoid.MoveDirection if mv and mv.Magnitude > 0.12 then playerMoving = true end end
			local distToHelper = (myHRP.Position - helperPart.Position).Magnitude
			local extraForce = clamp(distToHelper * 1200, 0, ALIGN_MAX_FORCE)
			local desiredForce = clamp(2000 + extraForce, ALIGN_MIN_FORCE, ALIGN_MAX_FORCE)
			if playerMoving then alignObj.MaxForce = math.max(ALIGN_MIN_FORCE, desiredForce * 0.45) else alignObj.MaxForce = desiredForce end
			alignObj.Responsiveness = ALIGN_RESPONSIVENESS
		end

	elseif mode == "velocity" then
		if not (bvObj and bgObj) then createVelocityObjectsFor(myHRP) end
		if bvObj and bgObj then
			local power = tonumber(sliderSpeed.GetValue() or SLIDER_LIMITS.BV_POWER_DEFAULT) or SLIDER_LIMITS.BV_POWER_DEFAULT
			local dir = (targetPos - myHRP.Position)
			dir = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
			local dist = dir.Magnitude
			local speedTarget = ORBIT_SPEED * (power/SLIDER_LIMITS.BV_POWER_DEFAULT) * 4 * (chargeTimer>0 and (1+CHARGE_STRENGTH*0.15) or 1)
			local velTarget = Vector3.new(0,0,0)
			if dist > 0.01 then velTarget = dir.Unit * speedTarget end
			if dist < 1.0 then velTarget = velTarget * dist end
			bvObj.Velocity = velTarget
			bvObj.MaxForce = Vector3.new(clamp(power*200, 1000, ALIGN_MAX_FORCE), clamp(power*200, 1000, ALIGN_MAX_FORCE), clamp(power*200, 1000, ALIGN_MAX_FORCE))
			local flat = Vector3.new(velTarget.X, 0, velTarget.Z)
			if flat.Magnitude > 0.01 then local desiredYaw = CFrame.new(myHRP.Position, myHRP.Position + flat); bgObj.CFrame = desiredYaw end
		end

	elseif mode == "twisted" then
		if not lvObj then createLinearObjectsFor(myHRP) end
		if lvObj then
			local power = tonumber(sliderSpeed.GetValue() or SLIDER_LIMITS.TWIST_DEFAULT) or SLIDER_LIMITS.TWIST_DEFAULT
			local dir = (targetPos - myHRP.Position)
			dir = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
			local dist = dir.Magnitude
			local base = (power / SLIDER_LIMITS.TWIST_DEFAULT) * (ORBIT_SPEED * 3.5) * (chargeTimer>0 and (1+CHARGE_STRENGTH*0.12) or 1)
			local vel = Vector3.new(0,0,0)
			if dist > 0.01 then vel = dir.Unit * base end
			if dist < 1.0 then vel = vel * dist end
			lvObj.VectorVelocity = vel
			lvObj.MaxForce = math.max(1e3, math.abs(power) * 500)
		end

	elseif mode == "force" then
		if not (vfObj or fallbackForceBV) then createForceObjectsFor(myHRP) end
		local dir = (targetPos - myHRP.Position)
		local desired = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
		local dist = desired.Magnitude
		local unit = Vector3.new(0,0,0)
		if dist > 0.01 then unit = desired.Unit end
		local appliedPower = forcePower * (chargeTimer>0 and (1 + CHARGE_STRENGTH*0.4) or 1)
		local forceVec = unit * appliedPower
		if vfObj then pcall(function() vfObj.Force = forceVec end)
		elseif fallbackForceBV then
			local speedTarget = clamp(ORBIT_SPEED * (appliedPower/SLIDER_LIMITS.FORCE_POWER_DEFAULT) * 6, 0, 120)
			local velTarget = unit * speedTarget
			if dist < 1 then velTarget = velTarget * dist end
			pcall(function() fallbackForceBV.Velocity = velTarget local mf = clamp(appliedPower * 50, 1000, ALIGN_MAX_FORCE) fallbackForceBV.MaxForce = Vector3.new(mf,mf,mf) end)
		end
		-- AutoJump
		tryAutoJump()
	end
end)

-- Cleanup on UI removal
screenGui.AncestryChanged:Connect(function(_, parent)
	if not parent then destroyModeObjects(); clearRing() end
end)

-- initial
hotkeyBox.Text = "Hotkey: "..hotkeyStr
chargeHotkeyBox.Text = "Charge: "..chargeHotkeyStr
updateToggleUI()
applyModeUI()
loadState()
updateESP(espEnabled)
saveState()

-- END
