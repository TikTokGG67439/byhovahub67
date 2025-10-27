local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0
local Camera = workspace.CurrentCamera

-- CONFIG
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

-- PATHING (heuristic)
local PATH_SAMPLE_ANGLE_STEPS = 24
local PATH_SAMPLE_DIST_STEP = 1.2
local PATH_MAX_SAMPLES = 18

local UI_POS = UDim2.new(0.5, -310, 0.82, -210)
local FRAME_SIZE = UDim2.new(0, 620, 0, 460) -- немного выше для дополнительных кнопок

-- UTIL
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
	if s == "-" then return "-" end
	local ok, val = pcall(function() return Enum.KeyCode[s] end)
	if ok and val then return val end
	return nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a,b,t) return a + (b-a) * t end

-- robust raycast down helper
local function raycastDown(origin, maxDist, ignoreInst)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Blacklist
	if ignoreInst then rp.FilterDescendantsInstances = {ignoreInst} end
	local res = Workspace:Raycast(origin, Vector3.new(0, -maxDist, 0), rp)
	return res
end

-- PERSISTENCE: store values under Player to survive respawn; also use Attributes if present
local persistFolder = nil
local function ensurePersistFolder()
	if persistFolder and persistFolder.Parent then return end
	persistFolder = LocalPlayer:FindFirstChild("StrafePersist")
	if not persistFolder then
		persistFolder = Instance.new("Folder")
		persistFolder.Name = "StrafePersist"
		persistFolder.Parent = LocalPlayer
	end
end

local function writePersistValue(name, value)
	ensurePersistFolder()
	local existing = persistFolder:FindFirstChild(name)
	if existing then
		if existing:IsA("BoolValue") then existing.Value = (value and true or false) end
		if existing:IsA("NumberValue") then existing.Value = tonumber(value) or 0 end
		if existing:IsA("StringValue") then existing.Value = tostring(value) end
	else
		local typ = type(value)
		if typ == "boolean" then
			local v = Instance.new("BoolValue")
			v.Name = name
			v.Value = value
			v.Parent = persistFolder
		elseif typ == "number" then
			local v = Instance.new("NumberValue")
			v.Name = name
			v.Value = value
			v.Parent = persistFolder
		else
			local v = Instance.new("StringValue")
			v.Name = name
			v.Value = tostring(value)
			v.Parent = persistFolder
		end
	end
	pcall(function() if LocalPlayer.SetAttribute then LocalPlayer:SetAttribute(name, value) end end)
end

local function readPersistValue(name, default)
	ensurePersistFolder()
	local existing = persistFolder:FindFirstChild(name)
	if existing then
		if existing:IsA("BoolValue") then return existing.Value end
		if existing:IsA("NumberValue") then return existing.Value end
		if existing:IsA("StringValue") then return existing.Value end
	end
	if LocalPlayer.GetAttribute then
		local ok, val = pcall(function() return LocalPlayer:GetAttribute(name) end)
		if ok and val ~= nil then return val end
	end
	return default
end

-- UI CREATION
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
frame.BackgroundColor3 = Color3.fromRGB(16,29,31)
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

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0, 42)
title.Position = UDim2.new(0, 6, 0, 6)
title.BackgroundTransparency = 1
title.Text = "FioletusHub"
title.Font = Enum.Font.Arcade
title.TextSize = 32
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

-- Controls
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
infoLabel.Size = UDim2.new(1, -12, 0, 24)
infoLabel.Position = UDim2.new(0, 6, 0, 116)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Nearest: — | Dist: — | Dir: CW | R: "..tostring(ORBIT_RADIUS_DEFAULT)
infoLabel.Font = Enum.Font.Arcade
infoLabel.TextSize = 14
infoLabel.TextColor3 = Color3.fromRGB(220,220,220)
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Parent = frame

local espBtn = Instance.new("TextButton")
espBtn.Size = UDim2.new(0.24, -6, 0, 36)
espBtn.Position = UDim2.new(0.76, 6, 0, 148)
espBtn.Text = "PlayerESP"
espBtn.Parent = frame
styleButton(espBtn)

local espGearBtn = Instance.new("TextButton")
espGearBtn.Size = UDim2.new(0.12, -6, 0, 36)
espGearBtn.Position = UDim2.new(0.88, 6, 0, 148)
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

-- SLIDER helper (dragging disables frame movement)
local sliderDraggingCount = 0

local function setFrameDraggableState(allowed)
	-- toggle draggable state for main frame and any config pickers to prevent sliders from moving frames while dragging
	pcall(function() frame.Draggable = allowed end)
	pcall(function() if espPickerFrame then espPickerFrame.Draggable = allowed end end)
	pcall(function() if lookAimPicker then lookAimPicker.Draggable = allowed end end)
	pcall(function() if noFallPicker then noFallPicker.Draggable = allowed end end)
	pcall(function() if aimViewPicker then aimViewPicker.Draggable = allowed end end)
end

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

	local function startDrag(input)
		dragging = true
		sliderDraggingCount = sliderDraggingCount + 1
		setFrameDraggableState(false)
		local localX = input.Position.X - sliderBg.AbsolutePosition.X
		setFromX(localX)
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				sliderDraggingCount = math.max(0, sliderDraggingCount - 1)
				if sliderDraggingCount == 0 then setFrameDraggableState(true) end
			end
		end)
	end

	sliderBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			startDrag(input)
		end
	end)

	thumb.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			startDrag(input)
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
		IsDragging = function() return dragging end,
	}
end

-- create sliders
local sliderSpeed = createSlider(frame, 236, "Orbit Speed", 0.2, 6.0, ORBIT_SPEED_BASE, function(v) return string.format("%.2f", v) end)
local sliderRadius = createSlider(frame, 284, "Orbit Radius", 0.5, 8.0, ORBIT_RADIUS_DEFAULT, function(v) return string.format("%.2f", v) end)
local sliderForce = createSlider(frame, 332, "Force Power", SLIDER_LIMITS.FORCE_POWER_MIN, SLIDER_LIMITS.FORCE_POWER_MAX, SLIDER_LIMITS.FORCE_POWER_DEFAULT, function(v) return string.format("%.0f", v) end)
sliderForce.Container.Visible = false
local sliderSearch = createSlider(frame, 380, "Search Radius", 5, 150, SEARCH_RADIUS_DEFAULT, function(v) return string.format("%.1f", v) end)

-- RUNTIME STATE
local enabled = false
currentTargetCharConn = nil
currentTargetRemovingConn = nil
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

local lookAimEnabled = false
local lookAimTargetPart = "Head"
local noFallEnabled = false
local noFallThreshold = 4 -- studs
local pathingEnabled = false

-- PERSISTENCE helpers (use both attribute+values)
local function saveState()
	-- simple mapping of important vars
	writePersistValue("Strafe_enabled", enabled and 1 or 0)
	writePersistValue("Strafe_mode", mode)
	writePersistValue("Strafe_hotkey", hotkeyStr)
	writePersistValue("Strafe_orbitRadius", orbitRadius)
	writePersistValue("Strafe_orbitSpeed", ORBIT_SPEED)
	writePersistValue("Strafe_forcePower", tonumber(sliderForce.GetValue()) or SLIDER_LIMITS.FORCE_POWER_DEFAULT)
	writePersistValue("Strafe_chargeHotkey", chargeHotkeyStr)
	writePersistValue("Strafe_searchRadius", tonumber(sliderSearch.GetValue()) or SEARCH_RADIUS_DEFAULT)
	writePersistValue("Strafe_esp", espEnabled and 1 or 0)
	writePersistValue("Strafe_espR", espColor.R)
	writePersistValue("Strafe_espG", espColor.G)
	writePersistValue("Strafe_espB", espColor.B)
	writePersistValue("Strafe_autojump", autoJumpEnabled and 1 or 0)
	writePersistValue("Strafe_lookAim", lookAimEnabled and 1 or 0)
	writePersistValue("Strafe_lookAimPart", lookAimTargetPart)
	writePersistValue("Strafe_noFall", noFallEnabled and 1 or 0)
	writePersistValue("Strafe_noFallThreshold", noFallThreshold)
	writePersistValue("Strafe_pathing", pathingEnabled and 1 or 0)
	writePersistValue("Strafe_lookAimStrength", tostring(getLookAimStrength and getLookAimStrength() or 0.12))
	writePersistValue("Strafe_aimView", aimViewEnabled and 1 or 0)
	writePersistValue("Strafe_aimViewMode", aimViewRotateMode)
	writePersistValue("Strafe_aimViewRange", tostring(avSlider and avSlider.GetValue and avSlider.GetValue() or orbitRadius))
end


local function loadState()
	local e = readPersistValue("Strafe_enabled", 0)
	enabled = (tonumber(e) or 0) ~= 0
	local m = readPersistValue("Strafe_mode", mode)
	if type(m) == "string" then mode = m end
	local hk = readPersistValue("Strafe_hotkey", hotkeyStr)
	if hk then hotkeyStr = tostring(hk) end
	local orad = tonumber(readPersistValue("Strafe_orbitRadius", orbitRadius)) or orbitRadius
	orbitRadius = orad; sliderRadius.SetValue(orbitRadius)
	local ospeed = tonumber(readPersistValue("Strafe_orbitSpeed", ORBIT_SPEED)) or ORBIT_SPEED
	ORBIT_SPEED = ospeed; sliderSpeed.SetValue(ORBIT_SPEED)
	local fpow = tonumber(readPersistValue("Strafe_forcePower", SLIDER_LIMITS.FORCE_POWER_DEFAULT)) or SLIDER_LIMITS.FORCE_POWER_DEFAULT
	sliderForce.SetValue(fpow)
	local ch = readPersistValue("Strafe_chargeHotkey", chargeHotkeyStr)
	if ch then chargeHotkeyStr = tostring(ch) end
	local sr = tonumber(readPersistValue("Strafe_searchRadius", SEARCH_RADIUS_DEFAULT)) or SEARCH_RADIUS_DEFAULT
	sliderSearch.SetValue(sr)
	espEnabled = (tonumber(readPersistValue("Strafe_esp", espEnabled and 1 or 0)) or 0) ~= 0
	local rcol = tonumber(readPersistValue("Strafe_espR", espColor.R)) or espColor.R
	local gcol = tonumber(readPersistValue("Strafe_espG", espColor.G)) or espColor.G
	local bcol = tonumber(readPersistValue("Strafe_espB", espColor.B)) or espColor.B
	espColor.R, espColor.G, espColor.B = rcol, gcol, bcol
	autoJumpEnabled = (tonumber(readPersistValue("Strafe_autojump", autoJumpEnabled and 1 or 0)) or 0) ~= 0
	lookAimEnabled = (tonumber(readPersistValue("Strafe_lookAim", lookAimEnabled and 1 or 0)) or 0) ~= 0
	lookAimTargetPart = tostring(readPersistValue("Strafe_lookAimPart", lookAimTargetPart))
	noFallEnabled = (tonumber(readPersistValue("Strafe_noFall", noFallEnabled and 1 or 0)) or 0) ~= 0
	noFallThreshold = tonumber(readPersistValue("Strafe_noFallThreshold", noFallThreshold)) or noFallThreshold
	pathingEnabled = (tonumber(readPersistValue("Strafe_pathing", pathingEnabled and 1 or 0)) or 0) ~= 0

	-- load aimView range and lookAim strength if present
	local avr = tonumber(readPersistValue("Strafe_aimViewRange", orbitRadius)) or orbitRadius
	if avSlider and avSlider.SetValue then pcall(function() avSlider.SetValue(avr) end) end
	local las = tonumber(readPersistValue("Strafe_lookAimStrength", 0.12)) or 0.12
	if lookAimStrengthSlider and lookAimStrengthSlider.SetValue then pcall(function() lookAimStrengthSlider.SetValue(las) end) end
	-- load new settings
	local las = tonumber(readPersistValue("Strafe_lookAimStrength", 0.12)) or 0.12
	if lookAimStrengthSlider and lookAimStrengthSlider.SetValue then pcall(function() lookAimStrengthSlider.SetValue(las) end) end
	aimViewEnabled = (tonumber(readPersistValue("Strafe_aimView", aimViewEnabled and 1 or 0)) or 0) ~= 0
	aimViewRotateMode = tostring(readPersistValue("Strafe_aimViewMode", aimViewRotateMode))
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
	attach0 = hrp:FindFirstChild("StrafeAttach0_"..tostring(PlayerId))
	if not attach0 then
		attach0 = Instance.new("Attachment")
		attach0.Name = "StrafeAttach0_"..tostring(PlayerId)
		attach0.Parent = hrp
	end

	helperPart = workspace:FindFirstChild("StrafeHelperPart_"..tostring(PlayerId))
	if not helperPart then
		helperPart = Instance.new("Part")
		helperPart.Name = "StrafeHelperPart_"..tostring(PlayerId)
		helperPart.Size = Vector3.new(0.2,0.2,0.2)
		helperPart.Transparency = 1
		helperPart.Anchored = true
		helperPart.CanCollide = false
		helperPart.CFrame = hrp.CFrame
		helperPart.Parent = workspace
	end

	helperAttach = helperPart:FindFirstChild("StrafeAttach1_"..tostring(PlayerId))
	if not helperAttach then
		helperAttach = Instance.new("Attachment")
		helperAttach.Name = "StrafeAttach1_"..tostring(PlayerId)
		helperAttach.Parent = helperPart
	end

	alignObj = hrp:FindFirstChild("StrafeAlignPos_"..tostring(PlayerId))
	if not alignObj then
		alignObj = Instance.new("AlignPosition")
		alignObj.Name = "StrafeAlignPos_"..tostring(PlayerId)
		alignObj.Attachment0 = attach0
		alignObj.Attachment1 = helperAttach
		alignObj.MaxForce = ALIGN_MIN_FORCE
		alignObj.Responsiveness = ALIGN_RESPONSIVENESS
		alignObj.RigidityEnabled = false
		pcall(function() alignObj.MaxVelocity = HELPER_MAX_SPEED end)
		alignObj.Parent = hrp
	end

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
	bvObj = hrp:FindFirstChild("Strafe_BV_"..tostring(PlayerId))
	bgObj = hrp:FindFirstChild("Strafe_BG_"..tostring(PlayerId))
	if not (bvObj and bgObj) then
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
	local lv = hrp:FindFirstChild("Strafe_LV_"..tostring(PlayerId))
	if not lv then
		lv = Instance.new("LinearVelocity")
		lv.Name = "Strafe_LV_"..tostring(PlayerId)
		lv.Attachment0 = att
		lv.MaxForce = 0
		lv.VectorVelocity = Vector3.new(0,0,0)
		lv.Parent = hrp
	end
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

	local vf = hrp:FindFirstChild("Strafe_VectorForce_"..tostring(PlayerId))
	if not vf then
		local ok, v = pcall(function()
			local vv = Instance.new("VectorForce")
			vv.Name = "Strafe_VectorForce_"..tostring(PlayerId)
			vv.Attachment0 = att
			pcall(function() vv.RelativeTo = Enum.ActuatorRelativeTo.World end)
			vv.Force = Vector3.new(0,0,0)
			vv.Parent = hrp
			return vv
		end)
		if ok and v then vfObj = v end
	else vfObj = vf end

	if not vfObj then
		local bv = hrp:FindFirstChild("Strafe_ForceBV_"..tostring(PlayerId))
		if not bv then
			local ok2, b = pcall(function()
				local bb = Instance.new("BodyVelocity")
				bb.Name = "Strafe_ForceBV_"..tostring(PlayerId)
				bb.MaxForce = Vector3.new(0,0,0)
				bb.P = 3000
				bb.Velocity = Vector3.new(0,0,0)
				bb.Parent = hrp
				return bb
			end)
			if ok2 and b then fallbackForceBV = b end
		else fallbackForceBV = bv end
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
	-- manage currentTarget live connections
	if currentTargetCharConn then pcall(function() currentTargetCharConn:Disconnect() end) end
	if currentTargetRemovingConn then pcall(function() currentTargetRemovingConn:Disconnect() end) end
	if currentTarget and currentTarget.Character then
		local ok, ch = pcall(function() return currentTarget.Character end)
		if ok and ch then
			currentTargetCharConn = ch:FindFirstChild("Humanoid") and ch:FindFirstChildOfClass("Humanoid").Died:Connect(function()
				setTarget(nil, true)
			end) or nil
		end
		-- also watch for character added (in case of respawn)
		currentTargetRemovingConn = currentTarget.CharacterRemoving and currentTarget.CharacterRemoving:Connect(function()
			setTarget(nil, true)
		end) or nil
	end

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

-- Hotkey parsing (supports "-" unassigned)
local function parseHotkeyString(txt)
	if not txt then return nil end
	local s = tostring(txt):gsub("^%s*(.-)%s*$","%1")
	s = s:gsub("^Hotkey:%s*", "")
	s = s:gsub("^Charge:%s*", "")
	s = s:gsub("^Cycle:%s*", "")
	s = s:upper()
	s = s:gsub("%s+", "")
	if s == "-" then return "-", false, false, false end
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
		if primary == "-" then
			hotkeyKeyCode = nil; hotkeyStr = "-"
			hotkeyBox.Text = "Hotkey: -"
			infoLabel.Text = "Hotkey cleared"
			saveState(); return
		end
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
		if primary == "-" then
			chargeKeyCode = nil; chargeHotkeyStr = "-"
			chargeHotkeyBox.Text = "Charge: -"
			infoLabel.Text = "Charge hotkey cleared"
			saveState(); return
		end
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

-- Toggle handler
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

-- ESP panel
local espPickerFrame = Instance.new("Frame")
espPickerFrame.Size = UDim2.new(0, 260, 0, 140)
espPickerFrame.Position = UDim2.new(0.5, -130, 0.5, -70)
espPickerFrame.BackgroundColor3 = Color3.fromRGB(16,29,31)
espPickerFrame.Visible = false
espPickerFrame.Parent = screenGui
espPickerFrame.Active = true
espPickerFrame.Draggable = true
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

local colorPreview = Instance.new("TextLabel", espPickerFrame)
colorPreview.Size = UDim2.new(0, 48, 0, 48)
colorPreview.Position = UDim2.new(1, -56, 0, 8)
colorPreview.BackgroundColor3 = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
colorPreview.Text = ""
local cpCorner = Instance.new("UICorner", colorPreview); cpCorner.CornerRadius = UDim.new(0,6)

local function enableESPForPlayer(p)
	if not p or p == LocalPlayer then return end
	local ch = p.Character
	if not ch then return end
	-- destroy old highlight to avoid duplicates
	local existing = ch:FindFirstChild("StrafeESP_Highlight")
	if existing then safeDestroy(existing) end
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
			if p ~= LocalPlayer and p.Character then enableESPForPlayer(p) end
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

RunService.RenderStepped:Connect(function()
	if espPickerFrame.Visible then
		local r = math.floor(rSlider.GetValue())
		local g = math.floor(gSlider.GetValue())
		local b = math.floor(bSlider.GetValue())
		espColor.R, espColor.G, espColor.B = r, g, b
		colorPreview.BackgroundColor3 = Color3.fromRGB(r,g,b)
		for p, hl in pairs(playerHighlights) do
			if hl and hl.Parent then hl.FillColor = Color3.fromRGB(r,g,b) end
		end
	end
end)

-- keep ESP updated for joins/resets
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(ch)
		if espEnabled and p ~= LocalPlayer then enableESPForPlayer(p) end
	end)
end)
for _,p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(ch)
		if espEnabled and p ~= LocalPlayer then enableESPForPlayer(p) end
	end)
end
Players.PlayerRemoving:Connect(function(p)
	disableESPForPlayer(p)
	if p == currentTarget then setTarget(nil, true) end
end)

-- AutoJump helpers (robust)
local function isOnGround(humanoid, hrp)
	if not humanoid or not hrp then return false end
	-- Prefer Humanoid.FloorMaterial where possible
	local ok, state = pcall(function() return humanoid:GetState() end)
	if ok and state then
		if state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.PlatformStanding then return true end
	end
	-- raycast down check
	local r = raycastDown(hrp.Position + Vector3.new(0,0.5,0), 3, LocalPlayer.Character)
	if r and r.Instance then return true end
	-- fallback use Humanoid.FloorMaterial property if available
	local fmat = humanoid.FloorMaterial
	if fmat and fmat ~= Enum.Material.Air then return true end
	return false
end

local function tryAutoJump()
	if not autoJumpEnabled then return end
	if mode ~= "force" then return end
	if not enabled then return end
	local hrp = getHRP(LocalPlayer)
	if not hrp then return end
	local humanoid = charHumanoid
	if not humanoid then return end
	if isOnGround(humanoid, hrp) then
		humanoid.Jump = true
	end
end

-- PATHING: heuristic sampling around target (no PathfindingService)
local function samplePointAround(targetPos)
	for r = 1, PATH_MAX_SAMPLES do
		local dist = PATH_SAMPLE_DIST_STEP * r
		for i = 1, PATH_SAMPLE_ANGLE_STEPS do
			local ang = (i / PATH_SAMPLE_ANGLE_STEPS) * math.pi * 2
			local p = targetPos + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
			p = p + Vector3.new(0, 1.2, 0)
			local res = Workspace:Raycast(p, Vector3.new(0, -3, 0), RaycastParams.new())
			if res and res.Instance and not res.Instance:IsDescendantOf(LocalPlayer.Character) then
				-- ensure line from player position to sample is clear (or at least less blocked)
				return p
			end
		end
	end
	return nil
end


local function findAlternateWaypoint(playerHRP, targetHRP)
	if not playerHRP or not targetHRP then return nil end
	local startPos = playerHRP.Position
	local goalPos = targetHRP.Position + Vector3.new(0,1.2,0)

	-- params
	local rpParams = RaycastParams.new()
	rpParams.FilterType = Enum.RaycastFilterType.Blacklist
	rpParams.FilterDescendantsInstances = {LocalPlayer.Character, targetHRP.Parent}

	-- if direct path is clear, no waypoint needed
	local direct = Workspace:Raycast(startPos, goalPos - startPos, rpParams)
	if not direct then return nil end

	-- We'll attempt to generate a short chain of waypoints around the obstacle.
	local MAX_STEPS = 6
	local STEP_DIST = PATH_SAMPLE_DIST_STEP or 1.2
	local ANGLE_STEPS = PATH_SAMPLE_ANGLE_STEPS or 24

	local current = startPos
	for step = 1, MAX_STEPS do
		-- if line from current to goal clear then success
		local rp = Workspace:Raycast(current, goalPos - current, rpParams)
		if not rp then return nil end

		-- get hit point and normal
		local hitPos = rp.Position
		local hitNormal = rp.Normal or Vector3.new(0,1,0)
		-- try offsets along tangent directions (both sides)
		local tangent = Vector3.new(-hitNormal.Z, 0, hitNormal.X)
		if tangent.Magnitude == 0 then tangent = Vector3.new(1,0,0) end
		tangent = tangent.Unit

		local found = nil
		for _, side in ipairs({1, -1}) do
			for d = 1, PATH_MAX_SAMPLES or 12 do
				local dist = STEP_DIST * d + 0.6 + step*0.2
				local candidate = hitPos + (tangent * side * dist) + (hitNormal * 1.2) -- lift above obstacle slightly
				-- sample ground below candidate
				local down = Workspace:Raycast(candidate, Vector3.new(0, -4, 0), rpParams)
				if down and down.Instance and not down.Instance:IsDescendantOf(LocalPlayer.Character) then
					-- test from current->candidate and candidate->goal
					local r1 = Workspace:Raycast(current, candidate - current, rpParams)
					local r2 = Workspace:Raycast(candidate, goalPos - candidate, rpParams)
					if (not r1) and (not r2) then
						found = candidate + Vector3.new(0, 1.0, 0)
						break
					end
				end
			end
			if found then break end
		end

		-- if not found, try angular radial sampling around hitPos
		if not found then
			for a = 1, ANGLE_STEPS do
				local ang = (a / ANGLE_STEPS) * math.pi * 2
				for d = 1, PATH_MAX_SAMPLES or 12 do
					local dist = STEP_DIST * d + 0.6 + step*0.2
					local candidate = hitPos + Vector3.new(math.cos(ang) * dist, 1.2, math.sin(ang) * dist)
					local down = Workspace:Raycast(candidate, Vector3.new(0, -4, 0), rpParams)
					if down and down.Instance and not down.Instance:IsDescendantOf(LocalPlayer.Character) then
						local r1 = Workspace:Raycast(current, candidate - current, rpParams)
						local r2 = Workspace:Raycast(candidate, goalPos - candidate, rpParams)
						if (not r1) and (not r2) then
							found = candidate
							break
						end
					end
				end
				if found then break end
			end
		end

		if found then
			-- return the first waypoint found (main loop will set target to this waypoint)
			return found
		else
			-- couldn't find around this obstacle; try to nudge current a bit and retry
			current = current + (Vector3.new((math.random()-0.5),0,(math.random()-0.5)).Unit * (STEP_DIST * 0.5))
		end
	end

	return nil
end

-- LookAim UI
local lookAimBtn = Instance.new("TextButton", frame)
lookAimBtn.Size = UDim2.new(0, 120, 0, 34)
lookAimBtn.Position = UDim2.new(0, 6, 0, 232)
lookAimBtn.Text = "LookAim: OFF"
styleButton(lookAimBtn)
local lookAimConfigBtn = Instance.new("TextButton", frame)
lookAimConfigBtn.Size = UDim2.new(0, 36, 0, 34)
lookAimConfigBtn.Position = UDim2.new(0, 130, 0, 232)
lookAimConfigBtn.Text = "T"
styleButton(lookAimConfigBtn)

local lookAimPicker = Instance.new("Frame", screenGui)
lookAimPicker.Size = UDim2.new(0, 180, 0, 80)
lookAimPicker.Position = UDim2.new(0.5, -90, 0.5, -40)
lookAimPicker.BackgroundColor3 = Color3.fromRGB(16,29,31)
lookAimPicker.Visible = false
lookAimPicker.Active = true
lookAimPicker.Draggable = true
local lpCorner = Instance.new("UICorner", lookAimPicker); lpCorner.CornerRadius = UDim.new(0,8)
local headBtn = Instance.new("TextButton", lookAimPicker)
headBtn.Size = UDim2.new(1, -12, 0, 36)
headBtn.Position = UDim2.new(0, 6, 0, 8)
headBtn.Text = "Target: Head"
styleButton(headBtn)
local torsoBtn = Instance.new("TextButton", lookAimPicker)
torsoBtn.Size = UDim2.new(1, -12, 0, 36)
torsoBtn.Position = UDim2.new(0, 6, 0, 44)
torsoBtn.Text = "Target: Torso"
styleButton(torsoBtn)

-- LookAim strength slider
local lookAimStrength = 0.12
local lookAimStrengthSlider = createSlider(lookAimPicker, 44, "AimLookStrength", 0.01, 1.0, lookAimStrength, function(v) return string.format("%.2f", v) end)
lookAimStrengthSlider.Container.Position = UDim2.new(0,6,0,44)
lookAimStrengthSlider.Container.Size = UDim2.new(1,-12,0,36)
function getLookAimStrength() return tonumber(lookAimStrengthSlider and lookAimStrengthSlider.GetValue and lookAimStrengthSlider.GetValue() or lookAimStrength) end

lookAimBtn.MouseButton1Click:Connect(function()
	lookAimEnabled = not lookAimEnabled
	lookAimBtn.Text = "LookAim: " .. (lookAimEnabled and "ON" or "OFF")
	saveState()
end)
lookAimConfigBtn.MouseButton1Click:Connect(function()
	lookAimPicker.Visible = not lookAimPicker.Visible
end)
headBtn.MouseButton1Click:Connect(function()
	lookAimTargetPart = "Head"
	headBtn.BackgroundColor3 = Color3.fromRGB(100,40,120)
	torsoBtn.BackgroundColor3 = Color3.fromRGB(51,38,53)
	saveState()
end)
torsoBtn.MouseButton1Click:Connect(function()
	lookAimTargetPart = "Torso"
	torsoBtn.BackgroundColor3 = Color3.fromRGB(100,40,120)
	headBtn.BackgroundColor3 = Color3.fromRGB(51,38,53)
	saveState()
end)

-- NoFall UI
local noFallBtn = Instance.new("TextButton", frame)
noFallBtn.Size = UDim2.new(0, 120, 0, 34)
noFallBtn.Position = UDim2.new(0, 156, 0, 232)
noFallBtn.Text = "NoFall: OFF"
styleButton(noFallBtn)
local noFallConfigBtn = Instance.new("TextButton", frame)
noFallConfigBtn.Size = UDim2.new(0, 36, 0, 34)
noFallConfigBtn.Position = UDim2.new(0, 280, 0, 232)
noFallConfigBtn.Text = "S"
styleButton(noFallConfigBtn)

local noFallPicker = Instance.new("Frame", screenGui)
noFallPicker.Size = UDim2.new(0, 260, 0, 110)
noFallPicker.Position = UDim2.new(0.5, -130, 0.5, -55)
noFallPicker.BackgroundColor3 = Color3.fromRGB(16,29,31)
noFallPicker.Visible = false
noFallPicker.Active = true
noFallPicker.Draggable = true
local nfCorner = Instance.new("UICorner", noFallPicker); nfCorner.CornerRadius = UDim.new(0,8)
local nfLabel = Instance.new("TextLabel", noFallPicker)
nfLabel.Size = UDim2.new(1, -12, 0, 28)
nfLabel.Position = UDim2.new(0, 6, 0, 8)
nfLabel.Text = "NoFall Threshold (studs):"
nfLabel.BackgroundTransparency = 1
nfLabel.Font = Enum.Font.Arcade
nfLabel.TextScaled = true
local nfSlider = createSlider(noFallPicker, 40, "Threshold", 0, 30, noFallThreshold, function(v) return tostring(math.floor(v)) end)
nfSlider.Container.Position = UDim2.new(0, 6, 0, 40)
nfSlider.Container.Size = UDim2.new(1, -12, 0, 36)


-- == AimView ==
local aimViewEnabled = false
local aimViewRotateMode = "All" -- "Head" or "All"
local aimViewAxes = {X=true, Y=false, Z=false}
local aimViewRange = orbitRadius or 6

local aimViewBtn = Instance.new("TextButton", frame)
aimViewBtn.Size = UDim2.new(0, 120, 0, 34)
aimViewBtn.Position = UDim2.new(0, 456, 0, 232)
aimViewBtn.Text = "AimView: OFF"
styleButton(aimViewBtn)

local aimViewConfigBtn = Instance.new("TextButton", frame)
aimViewConfigBtn.Size = UDim2.new(0, 36, 0, 34)
aimViewConfigBtn.Position = UDim2.new(0, 580, 0, 232)
aimViewConfigBtn.Text = "A"
styleButton(aimViewConfigBtn)

local aimViewPicker = Instance.new("Frame", screenGui)
aimViewPicker.Size = UDim2.new(0, 220, 0, 140)
aimViewPicker.Position = UDim2.new(0.5, -110, 0.5, -70)
aimViewPicker.BackgroundColor3 = Color3.fromRGB(16,29,31)
aimViewPicker.Visible = false
aimViewPicker.Active = true
aimViewPicker.Draggable = true
local avCorner = Instance.new("UICorner", aimViewPicker); avCorner.CornerRadius = UDim.new(0,8)

local axisX = Instance.new("TextButton", aimViewPicker)
axisX.Size = UDim2.new(0.3, -8, 0, 28)
axisX.Position = UDim2.new(0, 6, 0, 8)
axisX.Text = "X"
styleButton(axisX)
local axisY = Instance.new("TextButton", aimViewPicker)
axisY.Size = UDim2.new(0.3, -8, 0, 28)
axisY.Position = UDim2.new(0.35, 6, 0, 8)
axisY.Text = "Y"
styleButton(axisY)
local axisZ = Instance.new("TextButton", aimViewPicker)
axisZ.Size = UDim2.new(0.3, -8, 0, 28)
axisZ.Position = UDim2.new(0.7, 6, 0, 8)
axisZ.Text = "Z"
styleButton(axisZ)

local avSlider = createSlider(aimViewPicker, 72, "AimView Range", 0.5, 12.0, aimViewRange, function(v) return string.format("%.2f", v) end)
avSlider.Container.Position = UDim2.new(0, 6, 0, 44)
avSlider.Container.Size = UDim2.new(1, -12, 0, 36)

local rotateBtn = Instance.new("TextButton", aimViewPicker)
rotateBtn.Size = UDim2.new(0.5, -8, 0, 26)
rotateBtn.Position = UDim2.new(0,6,0,112)
rotateBtn.Text = "Rotate: All"
styleButton(rotateBtn)

axisX.MouseButton1Click:Connect(function() aimViewAxes.X = not aimViewAxes.X axisX.BackgroundColor3 = aimViewAxes.X and Color3.fromRGB(100,40,120) or Color3.fromRGB(51,38,53) end)
axisY.MouseButton1Click:Connect(function() aimViewAxes.Y = not aimViewAxes.Y axisY.BackgroundColor3 = aimViewAxes.Y and Color3.fromRGB(100,40,120) or Color3.fromRGB(51,38,53) end)
axisZ.MouseButton1Click:Connect(function() aimViewAxes.Z = not aimViewAxes.Z axisZ.BackgroundColor3 = aimViewAxes.Z and Color3.fromRGB(100,40,120) or Color3.fromRGB(51,38,53) end)
rotateBtn.MouseButton1Click:Connect(function() if aimViewRotateMode == "All" then aimViewRotateMode = "Head" rotateBtn.Text = "Rotate: Head" else aimViewRotateMode = "All" rotateBtn.Text = "Rotate: All" end end)

aimViewBtn.MouseButton1Click:Connect(function() aimViewEnabled = not aimViewEnabled aimViewBtn.Text = "AimView: " .. (aimViewEnabled and "ON" or "OFF") saveState() end)
aimViewConfigBtn.MouseButton1Click:Connect(function() aimViewPicker.Visible = not aimViewPicker.Visible if aimViewPicker.Visible then avSlider.SetValue(aimViewRange) end end)

local aimGyro = nil
local function ensureAimGyro(hrp)
	if aimGyro and aimGyro.Parent then return end
	if aimGyro then pcall(function() aimGyro:Destroy() end) end
	aimGyro = Instance.new("BodyGyro")
	aimGyro.Name = "Strafe_AimGyro_"..tostring(PlayerId)
	aimGyro.MaxTorque = Vector3.new(1e8,1e8,1e8)
	aimGyro.P = 1e5
	aimGyro.D = 100
	aimGyro.Parent = hrp
end

local function applyAimView(hrp, targetHRP)
	if not aimViewEnabled or not hrp or not targetHRP then return end
	local desiredPos = targetHRP.Position
	local dir = (desiredPos - hrp.Position)
	local range = avSlider and avSlider.GetValue and avSlider.GetValue() or aimViewRange
	if dir.Magnitude > range then return end
	local lookCFrame = CFrame.new(hrp.Position, Vector3.new(desiredPos.X, hrp.Position.Y, desiredPos.Z))
	ensureAimGyro(hrp)
	if aimViewRotateMode == "Head" then
		local head = hrp.Parent and hrp.Parent:FindFirstChild("Head")
		if head then pcall(function() head.CFrame = CFrame.new(head.Position, desiredPos) end) end
	else
		pcall(function()
			aimGyro.CFrame = lookCFrame
			aimGyro.MaxTorque = Vector3.new(1e8, aimViewAxes.Y and 1e8 or 0, 1e8)
			aimGyro.Parent = hrp
		end)
	end
end

-- end AimView
noFallBtn.MouseButton1Click:Connect(function()
	noFallEnabled = not noFallEnabled
	noFallBtn.Text = "NoFall: " .. (noFallEnabled and "ON" or "OFF")
	saveState()
end)
noFallConfigBtn.MouseButton1Click:Connect(function()
	noFallPicker.Visible = not noFallPicker.Visible
	if noFallPicker.Visible then nfSlider.SetValue(noFallThreshold) end
end)
nfSlider.Container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() end)
nfSlider.Container:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() end)

-- PathFinding toggle UI
local pathBtn = Instance.new("TextButton", frame)
pathBtn.Size = UDim2.new(0, 120, 0, 34)
pathBtn.Position = UDim2.new(0, 306, 0, 232)
pathBtn.Text = "Pathing: OFF"
styleButton(pathBtn)

pathBtn.MouseButton1Click:Connect(function()
	pathingEnabled = not pathingEnabled
	pathBtn.Text = "Pathing: " .. (pathingEnabled and "ON" or "OFF")
	saveState()
end)

-- AutoJump UI (visible only in Force mode)
autoJumpBtn = Instance.new("TextButton", frame)
autoJumpBtn.Size = UDim2.new(0, 120, 0, 34)
autoJumpBtn.Position = UDim2.new(0.02, 6, 0, 280)
autoJumpBtn.Text = "AutoJump: OFF"
styleButton(autoJumpBtn)
autoJumpBtn.Visible = false

local function updateAutoJumpUI()
	autoJumpBtn.Text = "AutoJump: " .. (autoJumpEnabled and "ON" or "OFF")
	autoJumpBtn.TextColor3 = autoJumpEnabled and Color3.fromRGB(134,34,177) or Color3.fromRGB(206,30,144)
end

autoJumpBtn.MouseButton1Click:Connect(function()
	autoJumpEnabled = not autoJumpEnabled
	updateAutoJumpUI()
	saveState()
end)

-- INPUT handling
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

		-- main hotkey toggle (supports nil/unassigned)
		if hotkeyKeyCode and kc == hotkeyKeyCode then
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
		if chargeKeyCode and kc == chargeKeyCode then
			local okCtrl = (not chargeRequireCtrl) or ctrlHeld
			local okShift = (not chargeRequireShift) or shiftHeld
			local okAlt = (not chargeRequireAlt) or altHeld
			if okCtrl and okShift and okAlt then
				if currentTarget then
					chargeTimer = CHARGE_DURATION
					infoLabel.Text = ("Charging %s..."):format(tostring(currentTarget.Name))
				end
			end
		end

		-- cycle target
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

-- Character handlers
LocalPlayer.CharacterAdded:Connect(function(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 6)
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
			for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer and p.Character then enableESPForPlayer(p) end end
		end
	end
end)
LocalPlayer.CharacterRemoving:Connect(function() charHumanoid = nil; destroyModeObjects(); clearRing() end)

-- MAIN LOOP
local startTick = tick()
RunService.RenderStepped:Connect(function(dt)
	if dt > 0.12 then dt = 0.12 end
	local now = tick()
	local t = now - startTick

	-- read sliders live
	local sVal = tonumber(sliderSpeed.GetValue() or ORBIT_SPEED) or ORBIT_SPEED
	local rVal = tonumber(sliderRadius.GetValue() or orbitRadius) or orbitRadius
	if mode == "smooth" then ORBIT_SPEED = sVal; orbitRadius = rVal else orbitRadius = rVal end
	local newSearch = tonumber(sliderSearch.GetValue() or SEARCH_RADIUS_DEFAULT) or SEARCH_RADIUS_DEFAULT
	local forcePower = tonumber(sliderForce.GetValue() or SLIDER_LIMITS.FORCE_POWER_DEFAULT) or SLIDER_LIMITS.FORCE_POWER_DEFAULT

	if chargeTimer > 0 then
		chargeTimer = math.max(0, chargeTimer - dt)
		if chargeTimer == 0 then cycleTarget() end
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

	-- NoFall check: if enabled and no ground beneath target within threshold -> drop target
	if noFallEnabled and targetHRP then
		local under = raycastDown(targetHRP.Position + Vector3.new(0,1,0), noFallThreshold, currentTarget.Character)
		if not under then
			setTarget(nil, true)
			return
		end
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

	-- orbit math & dynamics
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

	-- Validate currentTarget: if player died/disconnected or character missing, clear target immediately
	if currentTarget and (not currentTarget.Character or not getHRP(currentTarget)) then
		setTarget(nil, true)
	end

	local targetPos = targetHRP.Position + Vector3.new(ox, 1.2, oz)

	-- Pathing: if enabled and direct line blocked, try to get a sample waypoint
	if pathingEnabled then
		local rpParams = RaycastParams.new()
		rpParams.FilterType = Enum.RaycastFilterType.Blacklist
		rpParams.FilterDescendantsInstances = {LocalPlayer.Character, targetHRP.Parent}
		local rp = Workspace:Raycast(myHRP.Position, (targetHRP.Position - myHRP.Position), rpParams)
		if rp then
			local wp = findAlternateWaypoint(myHRP, targetHRP)
			if wp then targetPos = wp end
		end
	end

	-- LookAim: rotate camera toward target part (smooth)
	if lookAimEnabled and currentTarget and currentTarget.Character and Camera then
		local tgtPart = nil
		if lookAimTargetPart == "Head" then tgtPart = currentTarget.Character:FindFirstChild("Head") end
		if not tgtPart then tgtPart = currentTarget.Character:FindFirstChild("HumanoidRootPart") end
		if tgtPart then
			local desiredCFrame = CFrame.new(Camera.CFrame.Position, tgtPart.Position)
			Camera.CFrame = Camera.CFrame:Lerp(desiredCFrame, clamp(getLookAimStrength() * dt * 60, 0, 1))
		end
	end

	if myHRP then pcall(function() applyAimView(myHRP, targetHRP) end) end

	-- Apply modes — ensure they obey orbit radius by always using 'targetPos' computed above
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
			pcall(function() bvObj.Velocity = velTarget end)
			local mf = clamp(power*200, 1000, ALIGN_MAX_FORCE)
			pcall(function() bvObj.MaxForce = Vector3.new(mf,mf,mf) end)
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
			pcall(function() lvObj.VectorVelocity = vel end)
			pcall(function() lvObj.MaxForce = math.max(1e3, math.abs(power) * 500) end)
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
		tryAutoJump()
	end
end)

-- cleanup on gui removal
screenGui.AncestryChanged:Connect(function(_, parent)
	if not parent then destroyModeObjects(); clearRing() end
end)

-- initial setup: load state, update UI and apply saved settings
loadState()
hotkeyBox.Text = "Hotkey: "..hotkeyStr
chargeHotkeyBox.Text = "Charge: "..chargeHotkeyStr
updateToggleUI()
applyModeUI()
updateESP(espEnabled)
updateAutoJumpUI()
saveState()
