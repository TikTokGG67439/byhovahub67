-- Smooth Fly v3 — Final (float preserved + floatForwardSpeed + nice UI + stroke tween)
-- Put into StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then return end

-- wait for initial character
local function waitForCharacter()
	local c = player.Character or player.CharacterAdded:Wait()
	local h = c:WaitForChild("Humanoid")
	local r = c:WaitForChild("HumanoidRootPart")
	return c, h, r
end

local character, humanoid, root = waitForCharacter()

-- ===========================
-- CONFIG (настраивай под себя)
-- ===========================
local flyEnabled = false
local vertControl = 0 -- -1 down, 0 none, 1 up
local flySpeed = 40 -- default speed = 53 (как просил)

-- FLOAT: отдельные параметры (same units as fly)
local floatEnabled = false
local floatForwardSpeed = 53        -- NEW: скорость горизонтального перемещения при float (stud/s)
local floatFallMultiplier = 1.10    -- NEW: множитель падения (1.00 neutral; >1 = быстрее падать)
local floatVerticalSmooth = 6      -- NEW: как быстро вертик. скорость подстраивается (больше = быстрее)
local floatMaxStepPerFrame = 12    -- ограничение перемещения targetPart за кадр при float

local smoothing = 0.12 -- lerp factor for targetPos (меньше = резвее)
local acceleration = 8 -- accel factor for velocity smoothing
local maxStepPerFrame = 6 -- лимит перемещения цели за кадр (м)

local useCameraPitchForTp = true
local toggleKey = Enum.KeyCode.F
local tpKey = Enum.KeyCode.T
local floatKey = Enum.KeyCode.G

-- TP параметры
local tpDistance = 6
local tpStep = 1
local tpMin, tpMax = 1, 100
local tpCooldown = 0.6
local lastTpTime = 0
local tpLerpFactor = 0.35

-- Platform
local platformEnabled = false
local platformPart = nil
local platformOffset = 3
local platformLerp = 0.12
local platformSize = Vector3.new(5.5, 0.5, 5.5)
local platformColor = Color3.fromRGB(120, 120, 120)
local PLATFORM_EVENT_NAME = "FlyPlatformPing" -- optional RemoteEvent in ReplicatedStorage

-- UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlyGUI_v3_safe"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local function makeBtn(parent, x, y, w, h, text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, h)
	b.Position = UDim2.new(0, x, 0, y)
	b.Text = text
	b.Font = Enum.Font.SourceSans
	b.TextSize = 14
	b.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	return b
end

-- Main frame with UICorner + UIStroke (stroke tween blue <-> orange)
local function makeMainFrame()
	local frame = Instance.new("Frame")
	frame.Name = "FlyMainFrame"
	frame.Size = UDim2.new(0, 780, 0, 140)
	frame.Position = UDim2.new(0, 16, 0, 16)
	frame.BackgroundTransparency = 0.05
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(34, 111, 255) -- initial blue
	stroke.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 34)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundTransparency = 1
	header.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.6, -8, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Text = "Smooth Fly v3 — safe (float preserved)"
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(230, 230, 230)
	title.BackgroundTransparency = 1
	title.Parent = header

	return frame, stroke, header
end

local mainFrame, mainStroke, mainHeader = makeMainFrame()

-- start stroke tween
do
	local info = TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true)
	local goal = {Color = Color3.fromRGB(255, 140, 34)}
	local tw = TweenService:Create(mainStroke, info, goal)
	tw:Play()
end

-- draggable header (works for touch & mouse)
do
	local dragging = false
	local dragStart, startPos = nil, nil
	mainHeader.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = mainFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	mainHeader.InputChanged:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) and dragging and dragStart and startPos then
			local delta = input.Position - dragStart
			mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- create UI buttons
local btnToggle = makeBtn(mainFrame, 12, 44, 150, 36, "Fly: OFF")
local btnUp = makeBtn(mainFrame, 176, 44, 36, 36, "▲"); btnUp.Visible = false
local btnDown = makeBtn(mainFrame, 220, 44, 36, 36, "▼"); btnDown.Visible = false
local btnTp = makeBtn(mainFrame, 264, 44, 56, 36, "Tp"); btnTp.Visible = false
local btnTpDec = makeBtn(mainFrame, 332, 44, 26, 18, "−"); btnTpDec.Visible = false
local lblTpVal = makeBtn(mainFrame, 332, 62, 60, 18, tostring(tpDistance)); lblTpVal.AutoButtonColor = false; lblTpVal.Visible = false
local btnTpInc = makeBtn(mainFrame, 398, 44, 26, 18, "+"); btnTpInc.Visible = false
local btnSpeedDec = makeBtn(mainFrame, 430, 44, 26, 18, "−"); btnSpeedDec.Visible = false
local lblSpeedVal = makeBtn(mainFrame, 430, 62, 60, 18, tostring(flySpeed)); lblSpeedVal.AutoButtonColor = false; lblSpeedVal.Visible = false
local btnSpeedInc = makeBtn(mainFrame, 496, 44, 26, 18, "+"); btnSpeedInc.Visible = false
local btnPlatform = makeBtn(mainFrame, 520, 44, 120, 36, "Platform: OFF")
local btnFloat = makeBtn(mainFrame, 656, 44, 92, 36, "Float: OFF")

-- float controls (forward speed, fall multiplier, vertical smoothing)
local btnFloatDec = makeBtn(mainFrame, 520, 90, 26, 18, "−")
local lblFloatVal = makeBtn(mainFrame, 548, 90, 86, 18, tostring(floatForwardSpeed)); lblFloatVal.AutoButtonColor = false
local btnFloatInc = makeBtn(mainFrame, 644, 90, 26, 18, "+")

local btnFallDec = makeBtn(mainFrame, 586, 90, 26, 18, "−")
local lblFallVal = makeBtn(mainFrame, 614, 90, 80, 18, string.format("%.2f", floatFallMultiplier)); lblFallVal.AutoButtonColor = false
local btnFallInc = makeBtn(mainFrame, 700, 90, 26, 18, "+")

local btnVertDec = makeBtn(mainFrame, 456, 90, 26, 18, "−")
local lblVertVal = makeBtn(mainFrame, 484, 90, 64, 18, tostring(floatVerticalSmooth)); lblVertVal.AutoButtonColor = false
local btnVertInc = makeBtn(mainFrame, 560, 90, 26, 18, "+")

-- ===========================
-- Align-based fly objects (fly uses align heavily; float uses separate floatVelocity)
-- ===========================
local targetPart
local attachRoot
local attachTarget
local alignPos
local alignOri

local function cleanFlyObjects()
	if targetPart and targetPart.Parent then targetPart:Destroy() end
	if attachRoot and attachRoot.Parent then attachRoot:Destroy() end
	if attachTarget and attachTarget.Parent then attachTarget:Destroy() end
	if alignPos and alignPos.Parent then alignPos:Destroy() end
	if alignOri and alignOri.Parent then alignOri:Destroy() end
	targetPart, attachRoot, attachTarget, alignPos, alignOri = nil, nil, nil, nil, nil
end

local function createFlyObjects(r)
	cleanFlyObjects()
	targetPart = Instance.new("Part")
	targetPart.Name = "Fly_TargetPart"
	targetPart.Size = Vector3.new(1, 1, 1)
	targetPart.Transparency = 1
	targetPart.CanCollide = false
	targetPart.Anchored = true
	targetPart.CFrame = r.CFrame
	targetPart.Parent = Workspace

	attachRoot = Instance.new("Attachment")
	attachRoot.Name = "Fly_AttachRoot"
	attachRoot.Parent = r

	attachTarget = Instance.new("Attachment")
	attachTarget.Name = "Fly_AttachTarget"
	attachTarget.Parent = targetPart

	alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = attachRoot
	alignPos.Attachment1 = attachTarget
	alignPos.RigidityEnabled = false
	alignPos.MaxForce = 1e6
	alignPos.Responsiveness = 18
	alignPos.MaxVelocity = math.huge
	alignPos.Parent = r

	alignOri = Instance.new("AlignOrientation")
	alignOri.Attachment0 = attachRoot
	alignOri.Attachment1 = attachTarget
	alignOri.RigidityEnabled = false
	alignOri.MaxTorque = 1e6
	alignOri.Responsiveness = 16
	alignOri.Parent = r

	alignPos.Enabled = false
	alignOri.Enabled = false
end

createFlyObjects(root)

-- internal state
local targetVelocity = Vector3.new(0, 0, 0) -- used by fly
local floatVelocity = Vector3.new(0, 0, 0)  -- used by float (single source of truth)
local tpTargetPos = nil
local isTpActive = false

-- ===========================
-- Platform helpers (multiple attachments)
-- ===========================
local function createPlatformPart()
	if platformPart and platformPart.Parent then return end
	platformPart = Instance.new("Part")
	platformPart.Name = "Fly_Platform"
	platformPart.Size = platformSize
	platformPart.Anchored = true
	platformPart.CanCollide = true
	platformPart.Transparency = 0
	platformPart.Color = platformColor
	platformPart.TopSurface = Enum.SurfaceType.Smooth
	platformPart.BottomSurface = Enum.SurfaceType.Smooth
	platformPart.Parent = Workspace
	platformPart:SetAttribute("IsFlyPlatform", true)

	for i = 1, 4 do
		local a = Instance.new("Attachment")
		a.Name = "FlyPlatform_Attach" .. tostring(i)
		a.Parent = platformPart
		a.Position = Vector3.new((i-2.5)*0.6, 0, 0)
	end

	platformPart.Touched:Connect(function(other)
		if not character or not root then return end
		if other:IsDescendantOf(character) then
			pcall(function() platformPart:SetAttribute("LastTouchedBy", player.UserId) end)
			local evt = ReplicatedStorage:FindFirstChild(PLATFORM_EVENT_NAME)
			if evt and evt:IsA("RemoteEvent") then pcall(function() evt:FireServer(true) end) end
		end
	end)
end

local function destroyPlatformPart()
	if platformPart and platformPart.Parent then platformPart:Destroy() end
	platformPart = nil
end

local function setPlatformEnabled(enable)
	platformEnabled = enable
	btnPlatform.Text = platformEnabled and "Platform: ON" or "Platform: OFF"
	if platformEnabled then
		createPlatformPart()
		if platformPart and root then
			platformPart.CFrame = CFrame.new(root.Position - Vector3.new(0, platformOffset, 0))
		end
	else
		destroyPlatformPart()
	end
end

setPlatformEnabled(false)

-- ===========================
-- Enable/disable fly & float
-- ===========================
local function enableFly(enable)
	flyEnabled = enable
	btnToggle.Text = flyEnabled and "Fly: ON" or "Fly: OFF"
	btnUp.Visible = flyEnabled
	btnDown.Visible = flyEnabled
	btnTp.Visible = flyEnabled
	btnTpDec.Visible = flyEnabled
	lblTpVal.Visible = flyEnabled
	btnTpInc.Visible = flyEnabled
	btnSpeedDec.Visible = flyEnabled
	lblSpeedVal.Visible = flyEnabled
	btnSpeedInc.Visible = flyEnabled

	if flyEnabled then
		if floatEnabled then
			floatEnabled = false
			btnFloat.Text = "Float: OFF"
		end
		if targetPart and root then
			targetPart.CFrame = root.CFrame
			targetVelocity = Vector3.new(0, 0, 0)
			if alignPos then
				alignPos.Enabled = true
				alignOri.Enabled = true
				alignPos.MaxForce = 1e6
				alignPos.Responsiveness = 18
				alignPos.MaxVelocity = math.huge
				alignOri.Responsiveness = 16
			end
		end
	else
		if alignPos then
			alignPos.Enabled = false
			alignOri.Enabled = false
			alignPos.MaxForce = 1e6
			alignPos.Responsiveness = 18
			alignPos.MaxVelocity = math.huge
			alignOri.Responsiveness = 16
		end
		if targetPart then targetPart.CFrame = root.CFrame end
		targetVelocity = Vector3.new(0, 0, 0)
		tpTargetPos = nil
		isTpActive = false
	end
end

local function enableFloat(enable)
	floatEnabled = enable
	btnFloat.Text = floatEnabled and "Float: ON" or "Float: OFF"
	if floatEnabled then
		if flyEnabled then
			flyEnabled = false
			btnToggle.Text = "Fly: OFF"
		end
		-- gentle AlignPosition so server still sees character follow targetPart, but no orientation force
		if alignPos then
			alignPos.Enabled = true
			alignOri.Enabled = false
			alignPos.MaxForce = 5e5
			alignPos.Responsiveness = math.clamp(floatVerticalSmooth, 2, 50)
			alignPos.MaxVelocity = math.max(60, floatForwardSpeed * 2)
		end
		floatVelocity = Vector3.new(0, 0, 0)
		if targetPart and root then targetPart.CFrame = root.CFrame end
	else
		if alignPos then
			alignPos.Enabled = false
			alignPos.MaxForce = 1e6
			alignPos.Responsiveness = 18
			alignPos.MaxVelocity = math.huge
			alignOri.Enabled = false
		end
		floatVelocity = Vector3.new(0, 0, 0)
	end
end

-- UI bindings
btnToggle.MouseButton1Click:Connect(function() enableFly(not flyEnabled) end)
btnFloat.MouseButton1Click:Connect(function() enableFloat(not floatEnabled) end)

-- ===========================
-- SAFE TP: multi-origin raycasts (fix half-body hit)
-- ===========================
local function forwardCastFrom(orig, dir, dist, rayParams)
	return Workspace:Raycast(orig, dir * dist, rayParams)
end

local function computeTpTarget(distance, withPitch)
	local cam = Workspace.CurrentCamera
	if not cam or not root then return nil end

	local look = cam.CFrame.LookVector
	local dir = withPitch and look or Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude == 0 then return nil end
	dir = dir.Unit

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {character}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	rayParams.IgnoreWater = true
	if platformPart then table.insert(rayParams.FilterDescendantsInstances, platformPart) end
	if targetPart then table.insert(rayParams.FilterDescendantsInstances, targetPart) end

	local origins = {}
	if character then
		local head = character:FindFirstChild("Head")
		local upper = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if head and head.Position then table.insert(origins, head.Position) end
		if upper and upper.Position then table.insert(origins, upper.Position) end
	end
	table.insert(origins, root.Position + Vector3.new(0, 1.5, 0))
	table.insert(origins, root.Position + Vector3.new(0, 0.5, 0))

	local bestFinal = nil
	for _, origin in ipairs(origins) do
		local cast = forwardCastFrom(origin, dir, distance, rayParams)
		local dest = nil
		if cast then dest = cast.Position - dir * 1.0 else dest = origin + dir * distance end

		local downOrigin = dest + Vector3.new(0, 60, 0)
		local downCast = Workspace:Raycast(downOrigin, Vector3.new(0, -1, 0) * 200, rayParams)
		if downCast then
			local bufferY = math.max(1.2, (root.Size.Y / 2) + 0.5)
			local final = Vector3.new(downCast.Position.X, downCast.Position.Y + bufferY, downCast.Position.Z)
			if final.Y < root.Position.Y - 6 then final = Vector3.new(final.X, root.Position.Y + 2.2, final.Z) end
			for i = 1, 6 do
				local upCheck = Workspace:Raycast(final + Vector3.new(0, 0.2, 0), Vector3.new(0, 1, 0) * (root.Size.Y + 0.6), rayParams)
				if upCheck then final = final - dir * 0.45 else break end
			end
			bestFinal = final
			break
		else
			if withPitch then
				if dest.Y < root.Position.Y - 6 then dest = Vector3.new(dest.X, root.Position.Y + 2.2, dest.Z) end
				for i = 1, 6 do
					local upCheck = Workspace:Raycast(dest + Vector3.new(0, 0.2, 0), Vector3.new(0, 1, 0) * (root.Size.Y + 0.6), rayParams)
					if upCheck then dest = dest - dir * 0.45 else break end
				end
				bestFinal = dest
			else
				bestFinal = Vector3.new(dest.X, root.Position.Y + 2.2, dest.Z)
			end
		end
	end

	return bestFinal
end

btnTp.MouseButton1Click:Connect(function()
	if not flyEnabled then return end
	local now = tick()
	if now - lastTpTime < tpCooldown then return end
	lastTpTime = now
	local p = computeTpTarget(tpDistance, useCameraPitchForTp)
	if p and targetPart then
		targetPart.CFrame = CFrame.new(p)
		targetVelocity = Vector3.new(0,0,0)
		tpTargetPos = nil
		isTpActive = false
	end
end)

-- Labels & UI adjustments handlers
local function updateTpLabel() lblTpVal.Text = tostring(tpDistance) end
btnTpDec.MouseButton1Click:Connect(function() tpDistance = math.clamp(tpDistance - tpStep, tpMin, tpMax) updateTpLabel() end)
btnTpInc.MouseButton1Click:Connect(function() tpDistance = math.clamp(tpDistance + tpStep, tpMin, tpMax) updateTpLabel() end)
updateTpLabel()

local function updateSpeedLabel() lblSpeedVal.Text = tostring(math.floor(flySpeed)) end
btnSpeedDec.MouseButton1Click:Connect(function() flySpeed = math.clamp(flySpeed - 1, 1, 500) updateSpeedLabel() end)
btnSpeedInc.MouseButton1Click:Connect(function() flySpeed = math.clamp(flySpeed + 1, 1, 500) updateSpeedLabel() end)
updateSpeedLabel()

local function updateFloatLabel() lblFloatVal.Text = tostring(floatForwardSpeed) end
btnFloatDec.MouseButton1Click:Connect(function() floatForwardSpeed = math.clamp(floatForwardSpeed - 1, 1, 1000) updateFloatLabel() end)
btnFloatInc.MouseButton1Click:Connect(function() floatForwardSpeed = math.clamp(floatForwardSpeed + 1, 1, 1000) updateFloatLabel() end)
updateFloatLabel()

local function updateFallLabel() lblFallVal.Text = string.format("%.2f", floatFallMultiplier) end
btnFallDec.MouseButton1Click:Connect(function() floatFallMultiplier = math.clamp(floatFallMultiplier - 0.50, 0.2, 5) updateFallLabel() end)
btnFallInc.MouseButton1Click:Connect(function() floatFallMultiplier = math.clamp(floatFallMultiplier + 0.50, 0.2, 5) updateFallLabel() end)
updateFallLabel()

local function updateVertLabel() lblVertVal.Text = tostring(floatVerticalSmooth) end
btnVertDec.MouseButton1Click:Connect(function() floatVerticalSmooth = math.clamp(floatVerticalSmooth - 0.5, 0.5, 50) updateVertLabel() end)
btnVertInc.MouseButton1Click:Connect(function() floatVerticalSmooth = math.clamp(floatVerticalSmooth + 0.5, 0.5, 50) updateVertLabel() end)
updateVertLabel()

btnPlatform.MouseButton1Click:Connect(function() setPlatformEnabled(not platformEnabled) end)

-- Vertical controls (buttons + touch)
local function startVertical(v) vertControl = v end
local function stopVertical() vertControl = 0 end
btnUp.MouseButton1Down:Connect(function() startVertical(1) end)
btnUp.MouseButton1Up:Connect(stopVertical)
btnDown.MouseButton1Down:Connect(function() startVertical(-1) end)
btnDown.MouseButton1Up:Connect(stopVertical)
btnUp.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then startVertical(1) end end)
btnUp.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then stopVertical() end end)
btnDown.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then startVertical(-1) end end)
btnDown.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then stopVertical() end end)

-- Keyboard bindings
UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if inp.KeyCode == toggleKey then enableFly(not flyEnabled)
	elseif inp.KeyCode == floatKey then enableFloat(not floatEnabled)
	elseif inp.KeyCode == tpKey and flyEnabled then
		local now = tick()
		if now - lastTpTime < tpCooldown then return end
		lastTpTime = now
		local p = computeTpTarget(tpDistance, useCameraPitchForTp)
		if p and targetPart then targetPart.CFrame = CFrame.new(p) targetVelocity = Vector3.new(0,0,0) tpTargetPos = nil isTpActive = false end
	elseif flyEnabled then
		if inp.KeyCode == Enum.KeyCode.Space then startVertical(1)
		elseif inp.KeyCode == Enum.KeyCode.LeftShift then startVertical(-1) end
	end
end)
UIS.InputEnded:Connect(function(inp)
	if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if inp.KeyCode == Enum.KeyCode.Space or inp.KeyCode == Enum.KeyCode.LeftShift then stopVertical() end
end)

-- Character respawn handling
local function onCharacterAdded(c)
	character = c
	humanoid = c:WaitForChild("Humanoid")
	root = c:WaitForChild("HumanoidRootPart")
	createFlyObjects(root)
	if targetPart then targetPart.CFrame = root.CFrame end
	if flyEnabled and alignPos then alignPos.Enabled = true; alignOri.Enabled = true end
	if platformEnabled and platformPart then platformPart.CFrame = CFrame.new(root.Position - Vector3.new(0, platformOffset, 0)) end
end
player.CharacterAdded:Connect(onCharacterAdded)

-- ===========================
-- Main loop: movement / TP smoothing
-- ===========================
RunService.Heartbeat:Connect(function(dt)
	if not root or not targetPart then return end

	-- platform standing detection (client ping; server should verify)
	if platformPart then
		local yDiff = (root.Position - platformPart.Position).Y
		if math.abs(yDiff + platformOffset) < 0.9 and (root.Position - platformPart.Position).Magnitude < 6 then
			local evt = ReplicatedStorage:FindFirstChild(PLATFORM_EVENT_NAME)
			if evt and evt:IsA("RemoteEvent") then pcall(function() evt:FireServer(true) end) end
		else
			local evt = ReplicatedStorage:FindFirstChild(PLATFORM_EVENT_NAME)
			if evt and evt:IsA("RemoteEvent") then pcall(function() evt:FireServer(false) end) end
		end
	end

	if isTpActive and tpTargetPos then
		local cur = targetPart.Position
		local alpha = math.clamp(tpLerpFactor * math.max(dt * 60, 1), 0, 1)
		local new = cur:Lerp(tpTargetPos, alpha)
		targetPart.CFrame = CFrame.new(new)
		if (tpTargetPos - new).Magnitude < 0.25 then isTpActive = false tpTargetPos = nil end
	end

	-- FLOAT MODE (completely separate from FLY)
	if floatEnabled then
		-- gentle Align so character follows targetPart without orientation forcing
		if alignPos then
			alignPos.Enabled = true
			alignOri.Enabled = false
			alignPos.MaxForce = 5e5
			alignPos.Responsiveness = math.clamp(floatVerticalSmooth, 2, 50)
			alignPos.MaxVelocity = math.max(60, floatForwardSpeed * 2)
		end

		local moveDir = humanoid and humanoid.MoveDirection or Vector3.new(0,0,0)
		local hor = Vector3.new(moveDir.X, 0, moveDir.Z) * floatForwardSpeed

		local vert
		if vertControl ~= 0 then
			vert = vertControl * floatForwardSpeed * 0.7
		else
			-- gentle downward bias scaled by floatFallMultiplier and floatForwardSpeed to keep units consistent
			vert = -9.81 * (floatFallMultiplier - 1) -- gravity-like bias; user controls multiplier
		end

		local desiredVel = hor + Vector3.new(0, vert, 0)

		-- smooth floatVelocity
		local lerpFactor = math.clamp(acceleration * dt, 0, 1)
		floatVelocity = floatVelocity:Lerp(desiredVel, lerpFactor)

		local desiredDelta = floatVelocity * dt
		if desiredDelta.Magnitude > floatMaxStepPerFrame then desiredDelta = desiredDelta.Unit * floatMaxStepPerFrame end

		local currentPos = targetPart.Position
		local newPos = currentPos + desiredDelta

		local lerpForTarget = math.clamp(0.06 * math.max(dt * 60, 1), 0, 1)
		targetPart.CFrame = targetPart.CFrame:Lerp(CFrame.new(newPos), lerpForTarget)

		return
	end

	-- neither float nor fly: keep target on root
	if not flyEnabled then
		targetPart.CFrame = root.CFrame
		targetVelocity = Vector3.new(0,0,0)
		if platformEnabled and platformPart then
			local desired = root.Position - Vector3.new(0, platformOffset, 0)
			local pNew = platformPart.Position:Lerp(desired, math.clamp(platformLerp / math.max(dt, 1/60), 0, 1))
			platformPart.CFrame = CFrame.new(pNew)
		end
		return
	end

	-- FLY behaviour (unchanged)
	local moveDir = humanoid and humanoid.MoveDirection or Vector3.new(0,0,0)
	local hor = Vector3.new(moveDir.X, 0, moveDir.Z) * flySpeed
	local vert = Vector3.new(0, vertControl * flySpeed, 0)
	local desiredVel = hor + vert

	local lerpFactor = math.clamp(acceleration * dt, 0, 1)
	targetVelocity = targetVelocity:Lerp(desiredVel, lerpFactor)

	local desiredDelta = targetVelocity * dt
	if desiredDelta.Magnitude > maxStepPerFrame then desiredDelta = desiredDelta.Unit * maxStepPerFrame end

	local currentPos = targetPart.Position
	local wantedPos = currentPos + desiredDelta
	local anchorBack = root.Position
	wantedPos = anchorBack:Lerp(wantedPos, 0.92)
	local alpha = math.clamp(smoothing / math.max(dt, 1/60), 0, 1)
	local newPos = currentPos:Lerp(wantedPos, alpha)
	targetPart.CFrame = CFrame.new(newPos)

	-- soft orientation to camera flat forward
	local cam = Workspace.CurrentCamera
	if cam then
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 1e-4 then
			local dir = flat.Unit
			local desiredCFrame = CFrame.new(newPos, newPos + dir)
			local curCFrame = targetPart.CFrame
			targetPart.CFrame = curCFrame:Lerp(desiredCFrame, 0.28)
		end
	end

	-- platform follow
	if platformEnabled and platformPart then
		local desired = newPos - Vector3.new(0, platformOffset, 0)
		local pNew = platformPart.Position:Lerp(desired, math.clamp(platformLerp / math.max(dt, 1/60), 0, 1))
		platformPart.CFrame = CFrame.new(pNew)
	end
end)

-- cleanup
script.Destroying:Connect(function()
	cleanFlyObjects()
	destroyPlatformPart()
	if screenGui and screenGui.Parent then screenGui:Destroy() end
end)

-- Server note (optional): create ReplicatedStorage RemoteEvent named "FlyPlatformPing" for server verification/debounce.
-- Example server snippet (ServerScriptService):
-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local event = ReplicatedStorage:FindFirstChild("FlyPlatformPing") or Instance.new("RemoteEvent", ReplicatedStorage); event.Name = "FlyPlatformPing"
-- event.OnServerEvent:Connect(function(player, standing) print(player.Name, "platform standing:", standing) end)

-- End of script

	destroyPlatformPart()
	if screenGui and screenGui.Parent then screenGui:Destroy() end
end)
