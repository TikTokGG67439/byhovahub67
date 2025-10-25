-- LocalScript (StarterPlayerScripts)
-- Strafe+Ring v3 — расширен: Hotkey combos, 4 modes (Smooth/Velocity/Twisted/Gravity),
-- Добавлен: Slider для SEARCH_RADIUS, Aimbot (слайдер дистанции), Gravity mode + AutoJump
-- Исправлены: сохранение ползунков при смерти/respawn, стабильность при реборне, доработан smooth helper

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0

-- ====== ПАРАМЕТРЫ (умолчания) ======
local SEARCH_RADIUS = 15
local SEGMENTS = 64
local RING_RADIUS = 2.6
local SEGMENT_HEIGHT = 0.14
local SEGMENT_THICK = 0.45
local RING_HEIGHT_BASE = -1.5
local RING_COLOR = Color3.fromRGB(255, 0, 170)
local RING_TRANSP = 0.22

-- bob (визуальные волны / левитация)
local BOB_AMPLITUDE = 0.28
local BOB_SPEED1 = 2.0
local BOB_SPEED2 = 0.6
local BOB_NOISE_FREQ = 0.9
local LEVITATE_AMPLITUDE = 0.22
local LEVITATE_FREQ = 1.0

-- STRAFE baseline
local ORBIT_RADIUS_DEFAULT = 3.2
local ORBIT_SPEED_BASE = 2.2
local ALIGN_MAX_FORCE = 5e4
local ALIGN_MIN_FORCE = 500
local ALIGN_RESPONSIVENESS = 18

-- helper (spring)
local HELPER_SPRING = 90
local HELPER_DAMP = 14
local HELPER_MAX_SPEED = 60

-- randomization / bursts
local ORBIT_NOISE_FREQ = 0.45
local ORBIT_NOISE_AMP = 0.9
local ORBIT_BURST_CHANCE_PER_SEC = 0.6
local ORBIT_BURST_MIN = 1.2
local ORBIT_BURST_MAX = 3.2
local DRIFT_FREQ = 0.12
local DRIFT_AMP = 0.45

-- UI placement
local UI_POS = UDim2.new(0.5, -220, 0.82, -120)

-- ====== УТИЛИТЫ ======
local function getHRP(player)
    local ch = player and player.Character
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart")
end

local function getHead(player)
    local ch = player and player.Character
    if not ch then return nil end
    return ch:FindFirstChild("Head") or ch:FindFirstChild("UpperTorso")
end

local function safeDestroy(obj)
    if obj and obj.Parent then
        pcall(function() obj:Destroy() end)
    end
end

local function charToKeyCode(str)
    if not str or #str == 0 then return nil end
    local s = tostring(str):upper()
    if #s == 1 then
        local ok, key = pcall(function() return Enum.KeyCode[s] end)
        if ok and key then return key end
    end
    local ok2, kc = pcall(function() return Enum.KeyCode[s] end)
    if ok2 and kc then return kc end
    return nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ====== UI (создание) ======
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StrafeRingUI_v3_"..tostring(PlayerId)
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame", screenGui)
frame.Size = UDim2.new(0, 440, 0, 360) -- увеличили для дополнительных контролов
frame.Position = UI_POS
frame.BackgroundTransparency = 0.45
frame.Name = "Frame"
frame.Active = true
frame.Draggable = true

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, -12, 0, 22)
title.Position = UDim2.new(0, 6, 0, 6)
title.BackgroundTransparency = 1
title.Text = "Strafe + Ring (v3+)"
title.Font = Enum.Font.SourceSansBold
title.TextSize = 18
title.Name = "Title"

local toggleBtn = Instance.new("TextButton", frame)
toggleBtn.Size = UDim2.new(0.18, -6, 0, 36)
toggleBtn.Position = UDim2.new(0, 6, 0, 34)
toggleBtn.Text = "OFF"
toggleBtn.Font = Enum.Font.SourceSans
toggleBtn.TextSize = 16

local changeTargetBtn = Instance.new("TextButton", frame)
changeTargetBtn.Size = UDim2.new(0.25, -6, 0, 36)
changeTargetBtn.Position = UDim2.new(0.20, 2, 0, 34)
changeTargetBtn.Text = "Change Target"
changeTargetBtn.Font = Enum.Font.SourceSans
changeTargetBtn.TextSize = 14

local hotkeyBox = Instance.new("TextBox", frame)
hotkeyBox.Size = UDim2.new(0.32, -6, 0, 36)
hotkeyBox.Position = UDim2.new(0.45, 2, 0, 34)
hotkeyBox.Text = "Hotkey: F"
hotkeyBox.ClearTextOnFocus = false
hotkeyBox.Font = Enum.Font.SourceSans
hotkeyBox.TextSize = 14

local aimbotToggle = Instance.new("TextButton", frame)
aimbotToggle.Size = UDim2.new(0.18, -6, 0, 32)
aimbotToggle.Position = UDim2.new(0.78, -4, 0, 36)
aimbotToggle.Text = "Aimbot: OFF"
aimbotToggle.Font = Enum.Font.SourceSans
aimbotToggle.TextSize = 13

local infoLabel = Instance.new("TextLabel", frame)
infoLabel.Size = UDim2.new(1, -12, 0, 28)
infoLabel.Position = UDim2.new(0, 6, 0, 76)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Nearest: — | Dist: — | Dir: CW | R: "..tostring(ORBIT_RADIUS_DEFAULT)
infoLabel.TextSize = 14
infoLabel.Font = Enum.Font.SourceSans

-- modes buttons (расширяем на 4)
local modeContainer = Instance.new("Frame", frame)
modeContainer.Size = UDim2.new(1, -12, 0, 36)
modeContainer.Position = UDim2.new(0, 6, 0, 108)
modeContainer.BackgroundTransparency = 1

local function makeModeButton(name, x, w)
    local b = Instance.new("TextButton", modeContainer)
    b.Size = UDim2.new(w, -6, 1, 0)
    b.Position = UDim2.new(x, 2, 0, 0)
    b.Text = name
    b.Font = Enum.Font.SourceSans
    b.TextSize = 14
    b.BackgroundColor3 = Color3.new(1,1,1)
    b.BackgroundTransparency = 0.9
    return b
end
local btnSmooth = makeModeButton("Smooth", 0, 0.24)
local btnVelocity = makeModeButton("Velocity", 0.26, 0.24)
local btnTwisted = makeModeButton("Twisted", 0.52, 0.24)
local btnGravity = makeModeButton("Gravity", 0.78, 0.22)

-- gravity auto-jump button
local gravityAutoJumpBtn = Instance.new("TextButton", frame)
gravityAutoJumpBtn.Size = UDim2.new(0.28, -6, 0, 28)
gravityAutoJumpBtn.Position = UDim2.new(0, 6, 0, 148)
gravityAutoJumpBtn.Text = "AutoJump: OFF"
gravityAutoJumpBtn.Font = Enum.Font.SourceSans
gravityAutoJumpBtn.TextSize = 13

-- ====== SLIDER helper (работает с touch)
local function createSlider(parent, yOffset, labelText, minVal, maxVal, initialVal, formatFn, onChange)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(1, -12, 0, 36)
    container.Position = UDim2.new(0, 6, 0, yOffset)
    container.BackgroundTransparency = 0.6

    local lbl = Instance.new("TextLabel", container)
    lbl.Size = UDim2.new(0.5, 0, 1, 0)
    lbl.Position = UDim2.new(0, 6, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextSize = 14
    lbl.Font = Enum.Font.SourceSans
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local valLabel = Instance.new("TextLabel", container)
    valLabel.Size = UDim2.new(0.5, -8, 1, 0)
    valLabel.Position = UDim2.new(0.5, 0, 0, 0)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = tostring(formatFn and formatFn(initialVal) or string.format("%.2f", initialVal))
    valLabel.TextSize = 14
    valLabel.Font = Enum.Font.SourceSans
    valLabel.TextXAlignment = Enum.TextXAlignment.Right

    local sliderBg = Instance.new("Frame", container)
    sliderBg.Size = UDim2.new(1, -12, 0, 8)
    sliderBg.Position = UDim2.new(0, 6, 0, 20)
    sliderBg.BackgroundColor3 = Color3.fromRGB(40,40,40)
    sliderBg.BorderSizePixel = 0
    sliderBg.ClipsDescendants = true
    sliderBg.BackgroundTransparency = 0.15

    local fill = Instance.new("Frame", sliderBg)
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0,0,0,0)
    fill.BackgroundColor3 = RING_COLOR
    fill.BorderSizePixel = 0

    local thumb = Instance.new("Frame", sliderBg)
    thumb.Size = UDim2.new(0, 16, 0, 16)
    thumb.Position = UDim2.new(0, -8, 0.5, -8)
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.BackgroundColor3 = Color3.fromRGB(230,230,230)
    thumb.BorderSizePixel = 0

    local dragging = false
    local sliderWidth = 0
    local function recalc()
        sliderWidth = sliderBg.AbsoluteSize.X
    end
    sliderBg:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalc)
    recalc()

    local function setFromX(x)
        if sliderWidth <= 0 then return end
        local rel = clamp(x/sliderWidth, 0, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        thumb.Position = UDim2.new(rel, 0, 0.5, -8)
        local v = minVal + (maxVal - minVal) * rel
        valLabel.Text = tostring(formatFn and formatFn(v) or string.format("%.2f", v))
        if onChange then
            pcall(function() onChange(v) end)
        end
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
        return minVal + (maxVal - minVal) * rel
    end

    local function setRange(minV, maxV, initV)
        minVal = minV; maxVal = maxV
        if initV then
            local rel = 0
            if maxVal ~= minVal then rel = (initV - minVal) / (maxVal - minVal) end
            fill.Size = UDim2.new(clamp(rel,0,1),0,1,0)
            thumb.Position = UDim2.new(clamp(rel,0,1),0,0.5,-8)
            valLabel.Text = tostring(formatFn and formatFn(initV) or string.format("%.2f", initV))
            if onChange then pcall(function() onChange(initV) end) end
        end
    end

    local function setLabel(txt) lbl.Text = txt end

    return {
        Container = container,
        GetValue = getValue,
        SetValue = function(v)
            if maxVal == minVal then return end
            local rel = (v - minVal) / (maxVal - minVal)
            fill.Size = UDim2.new(clamp(rel,0,1),0,1,0)
            thumb.Position = UDim2.new(clamp(rel,0,1),0,0.5,-8)
            valLabel.Text = tostring(formatFn and formatFn(v) or string.format("%.2f", v))
            if onChange then pcall(function() onChange(v) end) end
        end,
        SetRange = setRange,
        SetLabel = setLabel,
        ValueLabel = valLabel,
    }
end

-- Создаём слайдеры
-- Мы добавляем два новых: SEARCH_RADIUS (динамически) и Aim Distance
local saved = {
    orbitSpeed = ORBIT_SPEED_BASE,
    orbitRadius = ORBIT_RADIUS_DEFAULT,
    searchRadius = SEARCH_RADIUS,
    aimDistance = 20,
}

local function saveAttrs()
    pcall(function()
        screenGui:SetAttribute("orbitSpeed", saved.orbitSpeed)
        screenGui:SetAttribute("orbitRadius", saved.orbitRadius)
        screenGui:SetAttribute("searchRadius", saved.searchRadius)
        screenGui:SetAttribute("aimDistance", saved.aimDistance)
    end)
end

local function loadAttrs()
    pcall(function()
        local v = screenGui:GetAttribute("orbitSpeed")
        if v then saved.orbitSpeed = v end
        v = screenGui:GetAttribute("orbitRadius")
        if v then saved.orbitRadius = v end
        v = screenGui:GetAttribute("searchRadius")
        if v then saved.searchRadius = v end
        v = screenGui:GetAttribute("aimDistance")
        if v then saved.aimDistance = v end
    end)
end

loadAttrs()

local sliderSpeed = createSlider(frame, 190, "Orbit Speed", 0.2, 6.0, saved.orbitSpeed, function(v) return string.format("%.2f", v) end, function(v) saved.orbitSpeed = v; saveAttrs() end)
local sliderRadius = createSlider(frame, 230, "Orbit Radius", 0.5, 8.0, saved.orbitRadius, function(v) return string.format("%.2f", v) end, function(v) saved.orbitRadius = v; saveAttrs() end)
local sliderSearch = createSlider(frame, 270, "Search Radius", 5, 60, saved.searchRadius, function(v) return string.format("%.1f", v) end, function(v) saved.searchRadius = v; saveAttrs() end)
local sliderAim = createSlider(frame, 310, "Aim Distance", 2, 60, saved.aimDistance, function(v) return string.format("%.1f", v) end, function(v) saved.aimDistance = v; saveAttrs() end)

-- ====== RUNTIME STATE ======
local enabled = false
local currentTarget = nil
local ringParts = {}
local folder = nil

-- mode: "smooth", "velocity", "twisted", "gravity"
local mode = "smooth"

-- helper objects (created per-target)
local attach0, helperPart, helperAttach, alignObj = nil, nil, nil, nil
local bvObj, bgObj, lvObj = nil, nil, nil
local gravityForce = nil

local charHumanoid = nil
local helperVel = Vector3.new(0,0,0)

local orbitAngle = math.random() * math.pi * 2
local orbitDirection = 1
local orbitRadius = saved.orbitRadius
local ORBIT_SPEED = saved.orbitSpeed
local steeringInput = 0
local shiftHeld = false

-- hotkey
local hotkeyKeyCode = Enum.KeyCode.F
local hotkeyStr = "F"
local hotkeyRequireCtrl, hotkeyRequireShift, hotkeyRequireAlt = false, false, false
local ctrlHeld, altHeld = false, false

-- bursts/drift
local burstTimer = 0
local burstStrength = 0
local driftPhase = math.random() * 1000

-- Aimbot
local aimbotEnabled = false

-- ====== RING helpers ======
local function ensureFolder()
    if folder and folder.Parent then return end
    folder = Instance.new("Folder")
    folder.Name = "StrafeRing_"..tostring(PlayerId)
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

-- ====== MODE object creators ======
local function createSmoothObjectsFor(hrp)
    -- create AlignPosition helper attached to HRP, helperPart is anchored in world and moved by spring
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

-- Gravity mode objects: a BodyForce used to add gentle pull/weight (world-space)
local function createGravityObjectsFor(hrp)
    if gravityForce then return end
    local bf = Instance.new("BodyForce")
    bf.Name = "Strafe_GravityBF_"..tostring(PlayerId)
    bf.Force = Vector3.new(0, 0, 0)
    bf.Parent = hrp
    gravityForce = bf
end

local function destroyGravityObjects()
    safeDestroy(gravityForce); gravityForce = nil
end

local function destroyModeObjects()
    destroySmoothObjects()
    destroyVelocityObjects()
    destroyLinearObjects()
    destroyGravityObjects()
end

-- ====== setTarget / cycleTarget ======
local function setTarget(player)
    if currentTarget == player then return end
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
            elseif mode == "gravity" then createGravityObjectsFor(myHRP) end
        end
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
                if d <= saved.searchRadius then table.insert(list, {player=p, dist=d}) end
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

-- ====== MODE UI handling ======
local function applyModeUI()
    local function setActive(btn, active)
        if active then
            btn.BackgroundTransparency = 0.6
            btn.BackgroundColor3 = Color3.fromRGB(200,200,200)
        else
            btn.BackgroundTransparency = 0.9
        end
    end
    setActive(btnSmooth, mode=="smooth")
    setActive(btnVelocity, mode=="velocity")
    setActive(btnTwisted, mode=="twisted")
    setActive(btnGravity, mode=="gravity")

    -- adapt sliders label and range
    if mode == "smooth" then
        sliderSpeed.SetLabel("Orbit Speed")
        sliderSpeed.SetRange(0.2, 6.0, saved.orbitSpeed)
        sliderRadius.SetLabel("Orbit Radius")
        sliderRadius.SetRange(0.5, 8.0, orbitRadius)
    elseif mode == "velocity" then
        sliderSpeed.SetLabel("BV Power")
        sliderSpeed.SetRange(50, 600, 200)
        sliderRadius.SetLabel("Orbit Radius")
        sliderRadius.SetRange(0.5, 8.0, orbitRadius)
    elseif mode == "twisted" then
        sliderSpeed.SetLabel("Twist Power")
        sliderSpeed.SetRange(10, 400, 120)
        sliderRadius.SetLabel("Orbit Radius")
        sliderRadius.SetRange(0.5, 8.0, orbitRadius)
    else -- gravity
        sliderSpeed.SetLabel("Gravity Pull")
        sliderSpeed.SetRange(10, 800, 120)
        sliderRadius.SetLabel("Orbit Radius")
        sliderRadius.SetRange(0.5, 8.0, orbitRadius)
    end
end

btnSmooth.MouseButton1Click:Connect(function()
    if mode ~= "smooth" then
        mode = "smooth"
        if currentTarget then
            destroyModeObjects()
            local myHRP = getHRP(LocalPlayer)
            if myHRP then createSmoothObjectsFor(myHRP) end
        end
        applyModeUI()
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
        applyModeUI()
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
        applyModeUI()
    end
end)
btnGravity.MouseButton1Click:Connect(function()
    if mode ~= "gravity" then
        mode = "gravity"
        if currentTarget then
            destroyModeObjects()
            local myHRP = getHRP(LocalPlayer)
            if myHRP then createGravityObjectsFor(myHRP) end
        end
        applyModeUI()
    end
end)

-- initial UI mode
applyModeUI()

-- ====== HOTKEY parsing and UX ======
local function parseHotkeyString(txt)
    if not txt then return nil end
    local s = tostring(txt):gsub("^%s*(.-)%s*$","%1")
    s = s:gsub("^Hotkey:%s*", "")
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
    else
        hotkeyBox.Text = "Hotkey: "..(hotkeyStr or "F")
        infoLabel.Text = "Invalid hotkey."
    end
end)

-- ====== Toggle button behavior ======
local function updateToggleUI()
    toggleBtn.Text = enabled and "ON" or "OFF"
    toggleBtn.BackgroundColor3 = enabled and Color3.fromRGB(120,220,120) or Color3.fromRGB(220,120,120)
end

toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    updateToggleUI()
    if not enabled then
        -- disable everything and clear target and mode objects
        setTarget(nil)
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
                elseif mode == "gravity" then createGravityObjectsFor(myHRP) end
            end
        end
    end
end)

changeTargetBtn.MouseButton1Click:Connect(cycleTarget)

-- ====== Aimbot UI ======
aimbotToggle.MouseButton1Click:Connect(function()
    aimbotEnabled = not aimbotEnabled
    aimbotToggle.Text = "Aimbot: " .. (aimbotEnabled and "ON" or "OFF")
end)

-- gravity auto-jump
local gravityAutoJump = false
gravityAutoJumpBtn.MouseButton1Click:Connect(function()
    gravityAutoJump = not gravityAutoJump
    gravityAutoJumpBtn.Text = "AutoJump: " .. (gravityAutoJump and "ON" or "OFF")
end)

-- ====== INPUT handling (hotkey + modifiers + steering) ======
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
                            elseif mode == "gravity" then createGravityObjectsFor(myHRP) end
                        end
                    end
                else
                    setTarget(nil)
                    destroyModeObjects()
                    infoLabel.Text = "Disabled"
                end
            end
        end
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
        -- restore sliders to saved values
        sliderSpeed.SetValue(saved.orbitSpeed)
        sliderRadius.SetValue(saved.orbitRadius)
        sliderSearch.SetValue(saved.searchRadius)
        sliderAim.SetValue(saved.aimDistance)
        orbitRadius = saved.orbitRadius
        ORBIT_SPEED = saved.orbitSpeed

        -- re-create mode objects if needed
        if enabled and currentTarget then
            destroyModeObjects()
            if mode == "smooth" then createSmoothObjectsFor(hrp)
            elseif mode == "velocity" then createVelocityObjectsFor(hrp)
            elseif mode == "twisted" then createLinearObjectsFor(hrp)
            elseif mode == "gravity" then createGravityObjectsFor(hrp) end
        end
    end
end)

LocalPlayer.CharacterRemoving:Connect(function()
    -- make sure to clean up attachments/objects to avoid stale references
    charHumanoid = nil
    destroyModeObjects()
    clearRing()
    currentTarget = nil
    -- keep UI state (enabled) but safe-guard inputs
    steeringInput = 0
    ctrlHeld = false; altHeld = false; shiftHeld = false
end)
Players.PlayerRemoving:Connect(function(p) if p == currentTarget then setTarget(nil) end end)

-- ====== MAIN LOOP ======
local startTick = tick()
RunService.RenderStepped:Connect(function(dt)
    if dt > 0.12 then dt = 0.12 end
    local now = tick()
    local t = now - startTick

    -- apply slider values consistently
    local sVal = tonumber(sliderSpeed.GetValue() or ORBIT_SPEED) or ORBIT_SPEED
    local rVal = tonumber(sliderRadius.GetValue() or orbitRadius) or orbitRadius
    -- map sliders to semantics per mode
    if mode == "smooth" then ORBIT_SPEED = sVal; orbitRadius = rVal; saved.orbitSpeed = ORBIT_SPEED; saved.orbitRadius = orbitRadius
    elseif mode == "velocity" then -- sliderSpeed = BV power
        -- we use the slider when applying BV
        saved.orbitRadius = rVal; orbitRadius = rVal
    elseif mode == "twisted" then saved.orbitRadius = rVal; orbitRadius = rVal
    elseif mode == "gravity" then saved.orbitRadius = rVal; orbitRadius = rVal end

    -- search radius from slider
    saved.searchRadius = tonumber(sliderSearch.GetValue() or saved.searchRadius) or saved.searchRadius
    saved.aimDistance = tonumber(sliderAim.GetValue() or saved.aimDistance) or saved.aimDistance
    saveAttrs()

    if not enabled then return end

    local myHRP = getHRP(LocalPlayer)
    if not myHRP then setTarget(nil); return end

    -- auto-find target when none
    if not currentTarget then
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local hrp = getHRP(p)
                if hrp then
                    local d = (hrp.Position - myHRP.Position).Magnitude
                    if d <= saved.searchRadius then table.insert(list, {player=p, dist=d}) end
                end
            end
        end
        table.sort(list, function(a,b) return a.dist < b.dist end)
        if #list > 0 then setTarget(list[1].player) end
    end

    -- validate target
    local targetHRP = getHRP(currentTarget)
    if not targetHRP then
        if attach0 or alignObj or bvObj or bgObj or lvObj or gravityForce then
            destroyModeObjects()
        end
        infoLabel.Text = "Nearest: — | Dist: — | Dir: " .. (orbitDirection==1 and "CW" or "CCW") .. " | R: " .. string.format("%.2f", orbitRadius)
        clearRing()
        return
    else
        local distToMe = (targetHRP.Position - myHRP.Position).Magnitude
        if distToMe > saved.searchRadius then
            setTarget(nil)
            return
        else
            infoLabel.Text = ("Nearest: %s | Dist: %.1f | Dir: %s | R: %.2f"):format(tostring(currentTarget.Name), distToMe, (orbitDirection==1 and "CW" or "CCW"), orbitRadius)
        end
    end

    -- draw ring (visual)
    if currentTarget and #ringParts == 0 then createRingSegments(SEGMENTS) end
    if currentTarget and targetHRP and #ringParts > 0 then
        local levOffset = math.sin(t * LEVITATE_FREQ) * LEVITATE_AMPLITUDE + (math.noise(t * 0.7, PlayerId * 0.01) - 0.5) * 0.06
        local basePos = targetHRP.Position + Vector3.new(0, RING_HEIGHT_BASE + levOffset, 0)
        local angleStep = (2 * math.pi) / #ringParts
        for i, part in ipairs(ringParts) do
            if not part or not part.Parent then createRingSegments(SEGMENTS); break end
            local angle = (i - 1) * angleStep
            local radialPulse = math.sin(t * 1.35 + angle * 1.1) * 0.05
            local r = RING_RADIUS + radialPulse + (math.noise(i * 0.03, t * 0.6) - 0.5) * 0.03
            local bob =
                math.sin(t * BOB_SPEED1 + angle * 0.8) * BOB_AMPLITUDE +
                math.sin(t * BOB_SPEED2 + angle * 0.45) * (BOB_AMPLITUDE * 0.25) +
                math.cos(t * BOB_NOISE_FREQ + angle * 0.3) * (BOB_AMPLITUDE * 0.08)
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

    local burstEffect = burstStrength * (burstTimer > 0 and 1 or 0)
    orbitAngle = orbitAngle + (orbitDirection * (effectiveBaseSpeed + speedBias + burstEffect) + steeringInput * 1.8) * dt

    local desiredRadius = orbitRadius + drift * 0.6
    if myDist and myDist < desiredRadius - 0.6 then desiredRadius = desiredRadius + (desiredRadius - myDist) * 0.35 end

    local ox = math.cos(orbitAngle) * desiredRadius
    local oz = math.sin(orbitAngle) * desiredRadius
    local targetPos = targetHRP.Position + Vector3.new(ox, 1.2, oz)

    -- MODE application: only if currentTarget exists and respective objects present
    if mode == "smooth" then
        if not (alignObj and helperPart and attach0) then
            createSmoothObjectsFor(myHRP)
        end
        if alignObj and helperPart then
            -- improved spring (prevents instability): cap acceleration and damp relative to dt
            local curPos = helperPart.Position
            local toTarget = (targetPos - curPos)
            local accel = toTarget * HELPER_SPRING - helperVel * HELPER_DAMP
            -- clamp accel to avoid spikes
            if accel.Magnitude > 2000 then accel = accel.Unit * 2000 end
            helperVel = helperVel + accel * dt
            if helperVel.Magnitude > HELPER_MAX_SPEED then helperVel = helperVel.Unit * HELPER_MAX_SPEED end
            local newPos = curPos + helperVel * dt
            helperPart.CFrame = CFrame.new(newPos)

            local playerMoving = false
            if charHumanoid then
                local mv = charHumanoid.MoveDirection
                if mv and mv.Magnitude > 0.12 then playerMoving = true end
            end

            local distToHelper = (myHRP.Position - helperPart.Position).Magnitude
            local extraForce = clamp(distToHelper * 1200, 0, ALIGN_MAX_FORCE)
            local desiredForce = clamp(2000 + extraForce, ALIGN_MIN_FORCE, ALIGN_MAX_FORCE)
            if playerMoving then alignObj.MaxForce = math.max(ALIGN_MIN_FORCE, desiredForce * 0.45)
            else alignObj.MaxForce = desiredForce end
            alignObj.Responsiveness = ALIGN_RESPONSIVENESS
        end

    elseif mode == "velocity" then
        if not (bvObj and bgObj) then createVelocityObjectsFor(myHRP) end
        if bvObj and bgObj then
            local power = tonumber(sliderSpeed.GetValue() or 200) or 200
            local dir = (targetPos - myHRP.Position)
            dir = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
            local dist = dir.Magnitude
            local speedTarget = ORBIT_SPEED * (power/200) * 4
            local velTarget = Vector3.new(0,0,0)
            if dist > 0.01 then velTarget = dir.Unit * speedTarget end
            if dist < 1.0 then velTarget = velTarget * dist end
            bvObj.Velocity = velTarget
            bvObj.MaxForce = Vector3.new(clamp(power*200, 1000, ALIGN_MAX_FORCE), clamp(power*200, 1000, ALIGN_MAX_FORCE), clamp(power*200, 1000, ALIGN_MAX_FORCE))
            local flat = Vector3.new(velTarget.X, 0, velTarget.Z)
            if flat.Magnitude > 0.01 then
                local desiredYaw = CFrame.new(myHRP.Position, myHRP.Position + flat)
                bgObj.CFrame = desiredYaw
            end
        end

    elseif mode == "twisted" then
        if not lvObj then createLinearObjectsFor(myHRP) end
        if lvObj then
            local power = tonumber(sliderSpeed.GetValue() or 120) or 120
            local dir = (targetPos - myHRP.Position)
            dir = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
            local dist = dir.Magnitude
            local base = (power / 120) * (ORBIT_SPEED * 3.5)
            local vel = Vector3.new(0,0,0)
            if dist > 0.01 then vel = dir.Unit * base end
            if dist < 1.0 then vel = vel * dist end
            lvObj.VectorVelocity = vel
            lvObj.MaxForce = math.max(1e3, math.abs(power) * 500)
        end

    elseif mode == "gravity" then
        if not gravityForce then createGravityObjectsFor(myHRP) end
        if gravityForce then
            local power = tonumber(sliderSpeed.GetValue() or 120) or 120
            -- gentle pull toward target horizontally + slight extra downward to feel "gravity-like" but smooth
            local toTarget = (targetHRP.Position - myHRP.Position)
            local horiz = Vector3.new(toTarget.X, 0, toTarget.Z)
            local pull = horiz.Unit * (math.min(horiz.Magnitude, 1) * power * 5)
            if horiz.Magnitude < 0.01 then pull = Vector3.new(0,0,0) end
            local extraDown = Vector3.new(0, -math.clamp(50 + (power * 0.2), 0, 400), 0)
            gravityForce.Force = pull + extraDown

            -- auto-jump: when on ground and auto enabled keep small periodic jumps for smoothing
            if gravityAutoJump and charHumanoid then
                if charHumanoid.FloorMaterial ~= Enum.Material.Air and charHumanoid.Health > 0 then
                    -- do a gentle jump but not every frame
                    if math.random() < 0.015 then
                        charHumanoid.Jump = true
                    end
                end
            end
        end
    end

    -- Aimbot: smooth camera look at head if within aim distance
    if aimbotEnabled then
        local cam = workspace.CurrentCamera
        local aimTarget = currentTarget
        -- prefer the current target, but if none, find nearest within aim distance
        if not aimTarget then
            local best, bd = nil, 1e9
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local head = getHead(p)
                    if head then
                        local dist = (head.Position - myHRP.Position).Magnitude
                        if dist < saved.aimDistance and dist < bd then best = p; bd = dist end
                    end
                end
            end
            aimTarget = best
        else
            local head = getHead(aimTarget)
            if head then
                local dist = (head.Position - myHRP.Position).Magnitude
                if dist > saved.aimDistance then aimTarget = nil end
            else
                aimTarget = nil
            end
        end

        if aimTarget then
            local head = getHead(aimTarget)
            if head and workspace.CurrentCamera then
                local desired = CFrame.new(workspace.CurrentCamera.CFrame.Position, head.Position)
                -- lerp for smoothness
                workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame:Lerp(desired, 0.12)
            end
        end
    end
end)

-- Cleanup on UI removal
screenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then
        destroyModeObjects()
        clearRing()
    end
end)

-- initial text
hotkeyBox.Text = "Hotkey: "..hotkeyStr
updateToggleUI()
applyModeUI()

-- set UI slider initial values
sliderSpeed.SetValue(saved.orbitSpeed)
sliderRadius.SetValue(saved.orbitRadius)
sliderSearch.SetValue(saved.searchRadius)
sliderAim.SetValue(saved.aimDistance)

-- end of script

