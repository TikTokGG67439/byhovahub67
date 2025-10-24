-- LocalScript (StarterPlayerScripts)
-- Strafe+Ring v3 — исправленный/устойчивый вариант (AlignPosition + spring helper, без BodyVelocity и Lerp).
-- Внимательно: этот скрипт — полный файл, заменяй полностью.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0

-- ====== ПАРАМЕТРЫ ======
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

-- STRAFE
local ORBIT_RADIUS_DEFAULT = 4
local ORBIT_SPEED_BASE = 3.4
local ALIGN_MAX_FORCE = 5e4
local ALIGN_MIN_FORCE = 500
local ALIGN_RESPONSIVENESS = 18

-- helper (spring-based movement instead of Lerp)
local HELPER_SPRING = 90      -- stiffness
local HELPER_DAMP = 14        -- damping
local HELPER_MAX_SPEED = 60   -- limit helper speed (studs/sec)

-- randomization / bursts
local ORBIT_NOISE_FREQ = 0.45
local ORBIT_NOISE_AMP = 0.9
local ORBIT_BURST_CHANCE_PER_SEC = 0.6
local ORBIT_BURST_MIN = 1.2
local ORBIT_BURST_MAX = 3.2
local DRIFT_FREQ = 0.12
local DRIFT_AMP = 0.45

-- UI placement
local UI_POS = UDim2.new(0.5, -170, 0.85, -44)

-- ====== УТИЛИТЫ ======
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
    if #s == 1 then
        local ok, key = pcall(function() return Enum.KeyCode[s] end)
        if ok and key then return key end
    end
    return nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ====== UI (создание + перетаскивание) ======
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StrafeRingUI_v3_"..tostring(PlayerId)
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame", screenGui)
frame.Size = UDim2.new(0, 340, 0, 100)
frame.Position = UI_POS
frame.BackgroundTransparency = 0.45
frame.Name = "Frame"

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, -12, 0, 22)
title.Position = UDim2.new(0, 6, 0, 4)
title.BackgroundTransparency = 1
title.Text = "Strafe + Ring (v3)"
title.Font = Enum.Font.SourceSansBold
title.TextSize = 18
title.Name = "Title"

local toggleBtn = Instance.new("TextButton", frame)
toggleBtn.Size = UDim2.new(0.33, -8, 0, 34)
toggleBtn.Position = UDim2.new(0, 6, 0, 30)
toggleBtn.Text = "OFF"
toggleBtn.Font = Enum.Font.SourceSans
toggleBtn.TextSize = 16

local changeTargetBtn = Instance.new("TextButton", frame)
changeTargetBtn.Size = UDim2.new(0.33, -8, 0, 34)
changeTargetBtn.Position = UDim2.new(0.34, 2, 0, 30)
changeTargetBtn.Text = "Change Target"
changeTargetBtn.Font = Enum.Font.SourceSans
changeTargetBtn.TextSize = 14

local hotkeyBox = Instance.new("TextBox", frame)
hotkeyBox.Size = UDim2.new(0.34, -8, 0, 34)
hotkeyBox.Position = UDim2.new(0.68, 2, 0, 30)
hotkeyBox.Text = "Hotkey: F"
hotkeyBox.ClearTextOnFocus = false
hotkeyBox.Font = Enum.Font.SourceSans
hotkeyBox.TextSize = 14

local infoLabel = Instance.new("TextLabel", frame)
infoLabel.Size = UDim2.new(1, -12, 0, 28)
infoLabel.Position = UDim2.new(0, 6, 0, 66)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Nearest: — | Dist: — | Dir: CW | R: "..tostring(ORBIT_RADIUS_DEFAULT)
infoLabel.TextSize = 14
infoLabel.Font = Enum.Font.SourceSans

-- draggable frame implementation
local dragging = false
local dragInput = nil
local dragStart = nil
local startPos = nil

local function updateDrag(input)
    if not dragging then return end
    local delta = input.Position - dragStart
    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        dragInput = input
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput then
        updateDrag(input)
    end
end)

-- ====== РАНТАЙМ ======
local enabled = false
local currentTarget = nil
local ringParts = {}
local folder = nil
-- attachments/parts/align
local attach0, helperPart, helperAttach, alignObj = nil, nil, nil, nil
local charHumanoid = nil

-- helper physics state
local helperVel = Vector3.new(0,0,0)

-- orbit state
local orbitAngle = math.random() * math.pi * 2
local orbitDirection = 1
local orbitRadius = ORBIT_RADIUS_DEFAULT
local steeringInput = 0
local shiftHeld = false

-- hotkey
local hotkeyKeyCode = Enum.KeyCode.F
local hotkeyStr = "F"

-- burst/drift state
local burstTimer = 0
local burstStrength = 0
local driftPhase = math.random() * 1000

-- ====== RING CREATION ======
local function ensureFolder()
    if folder and folder.Parent then return end
    folder = Instance.new("Folder")
    folder.Name = "StrafeRing_"..tostring(PlayerId)
    folder.Parent = workspace
end

local function clearRing()
    if folder then
        for _, v in ipairs(folder:GetChildren()) do
            safeDestroy(v)
        end
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

-- ====== TARGET UTIL ======
local function playersInRadiusSorted(radius)
    local myHRP = getHRP(LocalPlayer)
    if not myHRP then return {} end
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local hrp = getHRP(p)
            if hrp then
                local d = (hrp.Position - myHRP.Position).Magnitude
                if d <= radius then
                    table.insert(list, {player = p, dist = d})
                end
            end
        end
    end
    table.sort(list, function(a,b) return a.dist < b.dist end)
    return list
end

-- ====== ALIGN (helper) ======
local function createAlignForHRP(hrp)
    -- очистка старых объектов (если есть)
    if alignObj then safeDestroy(alignObj); alignObj = nil end
    if attach0 then safeDestroy(attach0); attach0 = nil end
    if helperAttach then safeDestroy(helperAttach); helperAttach = nil end
    if helperPart then safeDestroy(helperPart); helperPart = nil end

    -- уникальные имена чтобы не было конфликтов
    local suffix = "_" .. tostring(PlayerId) .. "_" .. tostring(math.floor(tick()*1000))

    attach0 = Instance.new("Attachment")
    attach0.Name = "StrafeAttach0_v3" .. suffix
    attach0.Parent = hrp

    helperPart = Instance.new("Part")
    helperPart.Name = "StrafeHelperPart_v3" .. suffix
    helperPart.Size = Vector3.new(0.2,0.2,0.2)
    helperPart.Transparency = 1
    helperPart.Anchored = true             -- мы управляем позицией вручную через spring
    helperPart.CanCollide = false
    helperPart.CFrame = hrp.CFrame
    helperPart.Parent = workspace

    helperAttach = Instance.new("Attachment")
    helperAttach.Name = "StrafeAttach1_v3" .. suffix
    helperAttach.Parent = helperPart

    alignObj = Instance.new("AlignPosition")
    alignObj.Name = "StrafeAlign_v3" .. suffix
    alignObj.Attachment0 = attach0
    alignObj.Attachment1 = helperAttach
    alignObj.MaxForce = ALIGN_MIN_FORCE
    alignObj.Responsiveness = ALIGN_RESPONSIVENESS
    alignObj.RigidityEnabled = false
    -- если свойство MaxVelocity доступно, ограничим им скорость для стабильности
    pcall(function() alignObj.MaxVelocity = HELPER_MAX_SPEED end)
    alignObj.Parent = hrp

    helperVel = Vector3.new(0,0,0)
end

local function destroyAlign()
    safeDestroy(alignObj); alignObj = nil
    safeDestroy(attach0); attach0 = nil
    safeDestroy(helperAttach); helperAttach = nil
    safeDestroy(helperPart); helperPart = nil
    helperVel = Vector3.new(0,0,0)
end

-- ====== setTarget / cycleTarget ======
local function setTarget(player)
    if currentTarget == player then return end
    currentTarget = player
    clearRing()
    if player then
        createRingSegments(SEGMENTS)
        orbitAngle = math.random() * math.pi * 2
        local myHRP = getHRP(LocalPlayer)
        if myHRP and (not helperPart or not helperPart.Parent) then
            createAlignForHRP(myHRP)
        end
    else
        if alignObj then
            alignObj.MaxForce = ALIGN_MIN_FORCE
            alignObj.Responsiveness = math.max(4, ALIGN_RESPONSIVENESS * 0.35)
        end
    end
end

local function cycleTarget()
    local list = playersInRadiusSorted(SEARCH_RADIUS)
    if #list == 0 then setTarget(nil); return end
    if not currentTarget then setTarget(list[1].player); return end
    local idx = nil
    for i,v in ipairs(list) do if v.player == currentTarget then idx = i; break end end
    if not idx then setTarget(list[1].player); return end
    setTarget(list[idx % #list + 1].player)
end

-- ====== UI EVENTS ======
toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    toggleBtn.Text = enabled and "ON" or "OFF"
    if enabled then
        local myHRP = getHRP(LocalPlayer)
        if myHRP then createAlignForHRP(myHRP) end
        infoLabel.Text = "Searching for target..."
    else
        setTarget(nil); destroyAlign()
        infoLabel.Text = "Nearest: — | Dist: — | Dir: " .. (orbitDirection==1 and "CW" or "CCW") .. " | R: " .. string.format("%.2f", orbitRadius)
    end
end)

changeTargetBtn.MouseButton1Click:Connect(cycleTarget)

hotkeyBox.FocusLost:Connect(function()
    local txt = tostring(hotkeyBox.Text or ""):gsub("^%s*(.-)%s*$","%1")
    if #txt == 0 then hotkeyBox.Text = "Hotkey: "..(hotkeyStr or "F"); return end
    local candidate = txt:match("^Hotkey:%s*(%S+)$") or txt
    candidate = tostring(candidate):sub(1,1)
    local kc = charToKeyCode(candidate)
    if kc then hotkeyKeyCode = kc; hotkeyStr = tostring(candidate):upper(); hotkeyBox.Text = "Hotkey: "..hotkeyStr; infoLabel.Text = "Hotkey set: "..hotkeyStr
    else hotkeyBox.Text = "Hotkey: "..(hotkeyStr or "F"); infoLabel.Text = "Invalid hotkey (use single letter/number)." end
end)

-- ====== INPUT ======
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local kc = input.KeyCode
        -- сначала обработаем "фиксированные" клавиши, потом hotkey
        if kc == Enum.KeyCode.A then steeringInput = -1
        elseif kc == Enum.KeyCode.D then steeringInput = 1
        elseif kc == Enum.KeyCode.Z then orbitRadius = math.max(0.5, orbitRadius - 0.2)
        elseif kc == Enum.KeyCode.X then orbitRadius = math.min(8, orbitRadius + 0.2)
        elseif kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then shiftHeld = true
        end

        -- Toggle orbit direction on F only if F is NOT currently set as hotkey to avoid conflict.
        if kc == Enum.KeyCode.F and hotkeyKeyCode ~= Enum.KeyCode.F then
            orbitDirection = -orbitDirection
        end

        -- finally, cycleTarget via configurable hotkey
        if kc == hotkeyKeyCode then
            cycleTarget()
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local kc = input.KeyCode
        if kc == Enum.KeyCode.A or kc == Enum.KeyCode.D then steeringInput = 0
        elseif kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then shiftHeld = false
        end
    end
end)

-- ====== CHARACTER HANDLERS ======
LocalPlayer.CharacterAdded:Connect(function(char)
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if hrp then
        charHumanoid = char:FindFirstChildOfClass("Humanoid")
        -- при респавне заново создаём Align для текущего HRP (если включено)
        if enabled and currentTarget then
            -- уничтожим старое и создадим новое аккуратно
            destroyAlign()
            createAlignForHRP(hrp)
        end
    end
end)
LocalPlayer.CharacterRemoving:Connect(function()
    charHumanoid = nil; destroyAlign(); clearRing(); currentTarget = nil
end)
Players.PlayerRemoving:Connect(function(p) if p == currentTarget then setTarget(nil) end end)

-- ====== MAIN LOOP ======
local startTick = tick()
RunService.RenderStepped:Connect(function(dt)
    -- защита от слишком большого dt (например при минимизации)
    if dt > 0.1 then dt = 0.1 end

    local now = tick()
    local t = now - startTick
    if not enabled then return end

    local myHRP = getHRP(LocalPlayer)
    if not myHRP then setTarget(nil); return end

    -- автопоиск цели
    if not currentTarget then
        local list = playersInRadiusSorted(SEARCH_RADIUS)
        if #list > 0 then setTarget(list[1].player) end
    end

    -- валидация цели
    local targetHRP = getHRP(currentTarget)
    if not targetHRP then
        setTarget(nil)
        infoLabel.Text = "Nearest: — | Dist: — | Dir: " .. (orbitDirection==1 and "CW" or "CCW") .. " | R: " .. string.format("%.2f", orbitRadius)
    else
        local distToMe = (targetHRP.Position - myHRP.Position).Magnitude
        if distToMe > SEARCH_RADIUS then
            setTarget(nil)
            infoLabel.Text = "Nearest: — | Dist: — | Dir: " .. (orbitDirection==1 and "CW" or "CCW") .. " | R: " .. string.format("%.2f", orbitRadius)
        else
            infoLabel.Text = ("Nearest: %s | Dist: %.1f | Dir: %s | R: %.2f"):format(tostring(currentTarget.Name), distToMe, (orbitDirection==1 and "CW" or "CCW"), orbitRadius)
        end
    end

    -- ==== RING: плавная левитация + bob ====
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
    else
        clearRing()
    end

    -- ==== STRAFE helper: spring-based movement (без Lerp), шумы, всплески, дрейф ====
    if attach0 and helperPart and alignObj and helperPart.Parent then
        -- burst logic
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

        local effectiveBaseSpeed = ORBIT_SPEED_BASE * (1 + noise)
        if shiftHeld then effectiveBaseSpeed = effectiveBaseSpeed * 1.6 end

        -- дистанция и радиусная ошибка
        local myDist = nil
        local radialError = 0
        if currentTarget and targetHRP then
            myDist = (myHRP.Position - targetHRP.Position).Magnitude
            radialError = myDist - orbitRadius
        end
        local speedBias = clamp(radialError * 0.45, -2.2, 2.2)

        -- скорость орбиты (с учетом всплесков/управления)
        local burstEffect = burstStrength * (burstTimer > 0 and 1 or 0)
        orbitAngle = orbitAngle + (orbitDirection * (effectiveBaseSpeed + speedBias + burstEffect) + steeringInput * 1.8) * dt

        -- радиус с боковым дрейфом
        local desiredRadius = orbitRadius + drift * 0.6
        if myDist and myDist < desiredRadius - 0.6 then
            desiredRadius = desiredRadius + (desiredRadius - myDist) * 0.35
        end

        local ox = math.cos(orbitAngle) * desiredRadius
        local oz = math.sin(orbitAngle) * desiredRadius
        local targetPos
        if currentTarget and targetHRP then
            targetPos = targetHRP.Position + Vector3.new(ox, 1.2, oz)
        else
            targetPos = myHRP.Position + Vector3.new(0, 1.2, 0)
        end

        -- SPRING integration (замена Lerp): helperVel, helperPos
        local curPos = helperPart.Position
        local toTarget = (targetPos - curPos)
        -- spring acceleration: a = k * x - c * v
        local accel = toTarget * HELPER_SPRING - helperVel * HELPER_DAMP
        helperVel = helperVel + accel * dt

        -- clamp speed
        if helperVel.Magnitude > HELPER_MAX_SPEED then
            helperVel = helperVel.Unit * HELPER_MAX_SPEED
        end

        local newPos = curPos + helperVel * dt
        -- обновляем helperPart позицию напрямую (anchored part)
        helperPart.CFrame = CFrame.new(newPos)

        -- dynamic Align force
        local playerMoving = false
        if charHumanoid then
            local mv = charHumanoid.MoveDirection
            if mv and mv.Magnitude > 0.12 then playerMoving = true end
        end

        if currentTarget and targetHRP then
            local distToHelper = (myHRP.Position - helperPart.Position).Magnitude
            local extraForce = clamp(distToHelper * 1200, 0, ALIGN_MAX_FORCE)
            local desiredForce = clamp(2000 + extraForce, ALIGN_MIN_FORCE, ALIGN_MAX_FORCE)
            if playerMoving then
                alignObj.MaxForce = math.max(ALIGN_MIN_FORCE, desiredForce * 0.45)
            else
                alignObj.MaxForce = desiredForce
            end
            alignObj.Responsiveness = ALIGN_RESPONSIVENESS
        else
            -- если нет цели — ослабляем силу, чтобы персонаж двигался естественно
            alignObj.MaxForce = ALIGN_MIN_FORCE * (playerMoving and 0.5 or 1)
            alignObj.Responsiveness = math.max(4, ALIGN_RESPONSIVENESS * 0.35)
        end

    else
        -- если Align потерян — попытаемся создать его для текущего myHRP (если включено)
        if myHRP then
            if enabled and (not attach0 or not attach0.Parent) then
                pcall(function() createAlignForHRP(myHRP) end)
            end
        end
    end

end)

-- Cleanup on UI removal
screenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then
        destroyAlign()
        clearRing()
    end
end)

-- initial hotkey text
hotkeyBox.Text = "Hotkey: "..hotkeyStr
