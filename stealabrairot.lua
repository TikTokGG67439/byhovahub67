-- LocalScript: Smooth Fly v3 — final (platform 5.5, instant safe TP, flySpeed default 53, float preserved)
-- Put into StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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
local flySpeed = 53 -- default speed = 53 (как просил)
local floatSpeed = 1500000 -- отдельная скорость для float (настраиваемая)
local smoothing = 0.12 -- lerp factor for targetPos (меньше = резвее)
local acceleration = 8 -- accel factor for velocity smoothing
local maxStepPerFrame = 6 -- лимит перемещения цели за кадр (м)

local useCameraPitchForTp = true -- TP учитывает pitch камеры (true = 3D)
local toggleKey = Enum.KeyCode.F
local tpKey = Enum.KeyCode.T

-- TP параметры
local tpDistance = 6
local tpStep = 1
local tpMin, tpMax = 1, 100
local tpCooldown = 0.6
local lastTpTime = 0
local tpLerpFactor = 0.35 -- используется только для сглаженной TP (мы делаем instant по кнопке)

-- Платформа
local platformEnabled = false
local platformPart = nil
local platformOffset = 3
local platformLerp = 0.12
local platformSize = Vector3.new(5.5, 0.5, 5.5) -- <- 5.5 x 0.5 x 5.5
local platformColor = Color3.fromRGB(120, 120, 120)

-- Float mode
local floatEnabled = false
local floatKey = Enum.KeyCode.G

-- UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlyGUI_v3_safe"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local function makeBtn(x, y, w, h, text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, h)
	b.Position = UDim2.new(0, x, 0, y)
	b.Text = text
	b.Font = Enum.Font.SourceSans
	b.TextSize = 16
	b.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.Parent = screenGui
	local corner = Instance.new("UICorner", b)
	corner.CornerRadius = UDim.new(0, 6)
	return b
end

local btnToggle = makeBtn(16, 16, 150, 36, "Fly: OFF")
local btnUp = makeBtn(180, 16, 36, 36, "▲"); btnUp.Visible = false
local btnDown = makeBtn(220, 16, 36, 36, "▼"); btnDown.Visible = false
local btnTp = makeBtn(260, 16, 56, 36, "Tp"); btnTp.Visible = false
local btnTpDec = makeBtn(328, 16, 26, 18, "−"); btnTpDec.Visible = false
local lblTpVal = makeBtn(328, 36, 60, 18, tostring(tpDistance)); lblTpVal.AutoButtonColor = false; lblTpVal.Visible = false
local btnTpInc = makeBtn(394, 16, 26, 18, "+"); btnTpInc.Visible = false

local btnSpeedDec = makeBtn(430, 16, 26, 18, "−"); btnSpeedDec.Visible = false
local lblSpeedVal = makeBtn(430, 36, 60, 18, tostring(flySpeed)); lblSpeedVal.AutoButtonColor = false; lblSpeedVal.Visible = false
local btnSpeedInc = makeBtn(496, 16, 26, 18, "+"); btnSpeedInc.Visible = false

local btnPlatform = makeBtn(540, 16, 120, 36, "Platform: OFF"); btnPlatform.Visible = true
local btnFloat = makeBtn(680, 16, 120, 36, "Float: OFF"); btnFloat.Visible = true

-- FLOAT speed controls (отдельно)
local btnFloatDec = makeBtn(540, 60, 26, 18, "−")
local lblFloatVal = makeBtn(570, 60, 60, 18, tostring(floatSpeed)); lblFloatVal.AutoButtonColor = false
local btnFloatInc = makeBtn(636, 60, 26, 18, "+")

-- ===========================
-- Align-based fly objects
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
local targetVelocity = Vector3.new(0, 0, 0)
local tpTargetPos = nil
local isTpActive = false

-- Platform helpers (реальный объект в Workspace: Anchored=true, CanCollide=true)
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

-- Enable/disable fly
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
			alignPos.Enabled = true
			alignOri.Enabled = true
			-- restore alignPos force for fly
			alignPos.MaxForce = 1e6
			alignPos.Responsiveness = 18
			alignPos.MaxVelocity = math.huge
		end
	else
		alignPos.Enabled = false
		alignOri.Enabled = false
		if targetPart then
			targetPart.CFrame = root.CFrame
		end
		targetVelocity = Vector3.new(0, 0, 0)
		tpTargetPos = nil
		isTpActive = false
	end
end

-- Enable/disable float
local function enableFloat(enable)
	floatEnabled = enable
	btnFloat.Text = floatEnabled and "Float: ON" or "Float: OFF"
	if floatEnabled then
		if flyEnabled then
			flyEnabled = false
			btnToggle.Text = "Fly: OFF"
		end
		if targetPart and root then
			targetPart.CFrame = root.CFrame
			targetVelocity = Vector3.new(0, 0, 0)
			alignPos.Enabled = true
			-- make alignPos gentler during float so movement is less "brute force"
			alignPos.MaxForce = 5e4
			alignPos.Responsiveness = 6
			alignPos.MaxVelocity = 60
			alignOri.Enabled = false -- float shouldn't force orientation
		end
	else
		-- restore align defaults when float off
		if alignPos then
			alignPos.MaxForce = 1e6
			alignPos.Responsiveness = 18
			alignPos.MaxVelocity = math.huge
		end
		alignPos.Enabled = false
		targetVelocity = Vector3.new(0, 0, 0)
	end
end

-- UI bindings
btnToggle.MouseButton1Click:Connect(function() enableFly(not flyEnabled) end)
btnFloat.MouseButton1Click:Connect(function() enableFloat(not floatEnabled) end)

-- ===========================
-- SAFE TP implementation (instant TP to camera look, origin = root -> forward)
-- ===========================
local function computeTpTarget(distance, withPitch)
	local cam = Workspace.CurrentCamera
	if not cam or not root then return nil end

	-- origin near player's root so TP is forward relative to player position
	local origin = root.Position + Vector3.new(0, math.max(1, root.Size.Y/2), 0)
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

	-- forward cast from origin to avoid placing inside wall
	local cast = Workspace:Raycast(origin, dir * distance, rayParams)
	local dest
	if cast then
		dest = cast.Position - dir * 1.0 -- small backoff from hit
	else
		dest = origin + dir * distance
	end

	-- ground-check: cast down from above dest to find floor
	local downOrigin = dest + Vector3.new(0, 60, 0)
	local downCast = Workspace:Raycast(downOrigin, Vector3.new(0, -1, 0) * 200, rayParams)
	if downCast then
		local bufferY = math.max(1.2, (root.Size.Y / 2) + 0.5)
		local final = Vector3.new(downCast.Position.X, downCast.Position.Y + bufferY, downCast.Position.Z)

		if final.Y < root.Position.Y - 6 then
			final = Vector3.new(final.X, root.Position.Y + 2.2, final.Z)
		end

		-- simple ceiling check: if ceiling immediately above, step back
		for i = 1, 6 do
			local upCheck = Workspace:Raycast(final + Vector3.new(0, 0.2, 0), Vector3.new(0, 1, 0) * (root.Size.Y + 0.6), rayParams)
			if upCheck then
				final = final - dir * 0.45
			else
				break
			end
		end

		return final
	else
		if withPitch then
			if dest.Y < root.Position.Y - 6 then
				dest = Vector3.new(dest.X, root.Position.Y + 2.2, dest.Z)
			end
			for i = 1, 6 do
				local upCheck = Workspace:Raycast(dest + Vector3.new(0, 0.2, 0), Vector3.new(0, 1, 0) * (root.Size.Y + 0.6), rayParams)
				if upCheck then
					dest = dest - dir * 0.45
				else
					break
				end
			end
			return dest
		else
			return Vector3.new(dest.X, root.Position.Y + 2.2, dest.Z)
		end
	end
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

local function updateTpLabel() lblTpVal.Text = tostring(tpDistance) end
btnTpDec.MouseButton1Click:Connect(function() tpDistance = math.clamp(tpDistance - tpStep, tpMin, tpMax) updateTpLabel() end)
btnTpInc.MouseButton1Click:Connect(function() tpDistance = math.clamp(tpDistance + tpStep, tpMin, tpMax) updateTpLabel() end)
updateTpLabel()

-- Speed labels
local function updateSpeedLabel() lblSpeedVal.Text = tostring(math.floor(flySpeed)) end
btnSpeedDec.MouseButton1Click:Connect(function() flySpeed = math.clamp(flySpeed - 1, 1, 500) updateSpeedLabel() end)
btnSpeedInc.MouseButton1Click:Connect(function() flySpeed = math.clamp(flySpeed + 1, 1, 500) updateSpeedLabel() end)
updateSpeedLabel()

-- Float speed buttons
local function updateFloatLabel() lblFloatVal.Text = tostring(math.floor(floatSpeed)) end
btnFloatDec.MouseButton1Click:Connect(function() floatSpeed = math.clamp(floatSpeed - 10000, 1, 300000000) updateFloatLabel() end)
btnFloatInc.MouseButton1Click:Connect(function() floatSpeed = math.clamp(floatSpeed + 10000, 1, 400000000) updateFloatLabel() end)
updateFloatLabel()

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

-- Keyboard
UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if inp.KeyCode == toggleKey then enableFly(not flyEnabled)
	elseif inp.KeyCode == floatKey then enableFloat(not floatEnabled)
	elseif inp.KeyCode == tpKey and flyEnabled then
		-- instant TP
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

	-- (сохраняем опцию сглаженной TP, но основной режим — instant)
	if isTpActive and tpTargetPos then
		local cur = targetPart.Position
		local alpha = math.clamp(tpLerpFactor * math.max(dt * 60, 1), 0, 1)
		local new = cur:Lerp(tpTargetPos, alpha)
		targetPart.CFrame = CFrame.new(new)
		if (tpTargetPos - new).Magnitude < 0.25 then
			isTpActive = false
			tpTargetPos = nil
		end
	end

	-- Float mode (улучшенная версия: gentler align + lerp на targetPart, менее "палево")
	if floatEnabled then
		if alignPos then alignPos.Enabled = true; alignOri.Enabled = false end

		local moveDir = humanoid and humanoid.MoveDirection or Vector3.new(0, 0, 0)
		local hor = Vector3.new(moveDir.X, 0, moveDir.Z) * floatSpeed
		local vert = Vector3.new(0, -floatSpeed * 0.35, 0) -- падение чуть медленнее
		local desiredVel = hor + vert

		local lerpFactor = math.clamp(acceleration * dt, 0, 1)
		targetVelocity = targetVelocity:Lerp(desiredVel, lerpFactor)

		local desiredDelta = targetVelocity * dt
		if desiredDelta.Magnitude > maxStepPerFrame then
			desiredDelta = desiredDelta.Unit * maxStepPerFrame
		end

		local currentPos = targetPart.Position
		local newPos = currentPos + desiredDelta

		-- Плавнее двигаем targetPart (мелкие lerp'ы, а Align подтянет персонажа мягко)
		local lerpForTarget = math.clamp(0.06 * math.max(dt * 60, 1), 0, 1) -- медленный, чтобы "отпуск" был дольше
		targetPart.CFrame = targetPart.CFrame:Lerp(CFrame.new(newPos), lerpForTarget)

		-- platform при float не создаётся автоматически
		return
	end

	-- Если fly выключен — держим цель на root
	if not flyEnabled then
		targetPart.CFrame = root.CFrame
		targetVelocity = Vector3.new(0, 0, 0)
		if platformEnabled and platformPart then
			local desired = root.Position - Vector3.new(0, platformOffset, 0)
			local pNew = platformPart.Position:Lerp(desired, math.clamp(platformLerp / math.max(dt, 1/60), 0, 1))
			platformPart.CFrame = CFrame.new(pNew)
		end
		return
	end

	-- Movement input (fly)
	local moveDir = humanoid and humanoid.MoveDirection or Vector3.new(0, 0, 0)
	local hor = Vector3.new(moveDir.X, 0, moveDir.Z) * flySpeed
	local vert = Vector3.new(0, vertControl * flySpeed, 0)
	local desiredVel = hor + vert

	-- Smooth velocity
	local lerpFactor = math.clamp(acceleration * dt, 0, 1)
	targetVelocity = targetVelocity:Lerp(desiredVel, lerpFactor)

	local desiredDelta = targetVelocity * dt
	if desiredDelta.Magnitude > maxStepPerFrame then
		desiredDelta = desiredDelta.Unit * maxStepPerFrame
	end

	local currentPos = targetPart.Position
	local wantedPos = currentPos + desiredDelta
	local anchorBack = root.Position
	wantedPos = anchorBack:Lerp(wantedPos, 0.92)

	local alpha = math.clamp(smoothing / math.max(dt, 1/60), 0, 1)
	local newPos = currentPos:Lerp(wantedPos, alpha)

	targetPart.CFrame = CFrame.new(newPos)

	-- orient target to camera flat forward (upright)
	local cam = Workspace.CurrentCamera
	if cam then
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 1e-4 then
			local dir = flat.Unit
			targetPart.CFrame = CFrame.new(newPos, newPos + dir)
		end
	end

	-- platform follow (smoothed)
	if platformEnabled and platformPart then
		local desired = newPos - Vector3.new(0, platformOffset, 0)
		local pNew = platformPart.Position:Lerp(desired, math.clamp(platformLerp / math.max(dt, 1/60), 0, 1))
		platformPart.CFrame = CFrame.new(pNew)
	end
end)

-- cleanup on script destroy
script.Destroying:Connect(function()
	cleanFlyObjects()
	destroyPlatformPart()
	if screenGui and screenGui.Parent then screenGui:Destroy() end
end)
