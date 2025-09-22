
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then return end

-- WAIT FOR CHARACTER
local function waitForCharacter()
	local c = player.Character or player.CharacterAdded:Wait()
	local h = c:WaitForChild("Humanoid")
	local r = c:WaitForChild("HumanoidRootPart")
	return c, h, r
end

local character, humanoid, root = waitForCharacter()

----------------------------------------------------------------
-- SMOOTH FLY V3 (UI + movement) - kept intact, UI compact edition
----------------------------------------------------------------
-- CONFIG
local flyEnabled = false
local vertControl = 0 -- -1 down, 0 none, 1 up
local flySpeed = 29

-- FLOAT params (separate from fly)
local floatEnabled = false
local floatForwardSpeed = 200
local floatFallMultiplier = 8
local floatVerticalSmooth = 9
local floatMaxStepPerFrame = 12

local smoothing = 0.12
local acceleration = 8
local maxStepPerFrame = 6

local useCameraPitchForTp = true
local toggleKey = Enum.KeyCode.F
local tpKey = Enum.KeyCode.T
local floatKey = Enum.KeyCode.G

local tpDistance = 6
local tpStep = 1
local tpMin, tpMax = 1, 100
local tpCooldown = 0.6
local lastTpTime = 0
local tpLerpFactor = 0.35

local platformEnabled = false
local platformPart = nil
local platformOffset = 3
local platformLerp = 0.12
local platformSize = Vector3.new(5.5, 0.5, 5.5)
local platformColor = Color3.fromRGB(120, 120, 120)
local PLATFORM_EVENT_NAME = "FlyPlatformPing"

-- FLY GUI (namespaced to avoid collisions)
local flyScreenGui = Instance.new("ScreenGui")
flyScreenGui.Name = "FlyGUI_v3_compact"
flyScreenGui.ResetOnSpawn = false
flyScreenGui.Parent = player:WaitForChild("PlayerGui")

-- helper: button creator (TextScaled true, Arcade font)
local function makeBtn(parent, x, y, w, h, text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, h)
	b.Position = UDim2.new(0, x, 0, y)
	b.Text = text
	b.Font = Enum.Font.Arcade
	b.TextSize = 14
	b.TextScaled = true
	b.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.Parent = parent
	local corner = Instance.new("UICorner", b)
	corner.CornerRadius = UDim.new(0, 8)
	return b
end

-- Main compact frame
local function makeMainFrame()
	local frame = Instance.new("Frame")
	frame.Name = "FlyMainFrame"
	frame.Size = UDim2.new(0, 330, 0, 330) -- exact
	frame.Position = UDim2.new(0, 376, 0, 120)
	frame.BackgroundTransparency = 0.05
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.Parent = flyScreenGui
	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 12)

	local imagebutton = Instance.new("ImageButton")
	imagebutton.Image = "rbxassetid://106730820213474"
	imagebutton.Position = UDim2.new(0.476, 0,0.400, 0)
	imagebutton.Size = UDim2.new(0, 70, 0, 70)
	imagebutton.Active = true
	imagebutton.Draggable = true
	imagebutton.Parent = flyScreenGui
	local uistoke = Instance.new("UICorner", imagebutton)
	uistoke.CornerRadius = UDim.new(0, 10)
	local uistokeke = Instance.new("UIStroke", imagebutton)
	uistokeke.Thickness = 2
	uistokeke.Color = Color3.fromRGB(167, 94, 30)
	imagebutton.MouseButton1Click:Connect(function()
		frame.Visible = not frame.Visible
	end)

	local stroke = Instance.new("UIStroke", frame)
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(34, 111, 255) -- initial blue

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 72)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundTransparency = 1
	header.Parent = frame

	return frame, stroke, header
end

local mainFrame, mainStroke, mainHeader = makeMainFrame()

-- stroke tween blue <-> orange
do
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true)
	local goal = {Color = Color3.fromRGB(255, 140, 34)}
	local tw = TweenService:Create(mainStroke, info, goal)
	tw:Play()
end

-- draggable header
do
	local dragging = false
	local dragStart, startPos
	mainHeader.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = mainFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	mainHeader.InputChanged:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement)
			and dragging and dragStart and startPos then
			local delta = input.Position - dragStart
			mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- Animated per-letter NovaHub title (TextScaled = true, Arcade)
local function makeAnimatedTitle(parent, text)
	local root = Instance.new("Frame")
	root.Size = UDim2.new(1, -12, 0, 52)
	root.Position = UDim2.new(0, 6, 0, 6)
	root.BackgroundTransparency = 1
	root.Parent = parent

	local list = Instance.new("UIListLayout", root)
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 0)

	local chars = {}
	for i = 1, #text do
		local ch = text:sub(i,i)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0, 28, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Arcade
		lbl.Text = ch
		lbl.TextSize = 28
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(34,111,255)
		lbl.Parent = root

		-- slight outline for clarity
		local stroke = Instance.new("UIStroke", lbl)
		stroke.Thickness = 1
		stroke.Color = Color3.fromRGB(0,0,0)
		stroke.Transparency = 0.65

		table.insert(chars, lbl)
	end

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -12, 0, 18)
	subtitle.Position = UDim2.new(0, 6, 0, 36)
	subtitle.Font = Enum.Font.Arcade
	subtitle.TextScaled = true
	subtitle.Text = "tt: @novahub67"
	subtitle.TextSize = 14
	subtitle.TextColor3 = Color3.fromRGB(200,200,200)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.Parent = parent

	-- animate letters asynchronously: staggered delays and slightly different durations
	for i, lbl in ipairs(chars) do
		spawn(function()
			-- stagger so neighboring letters are out of phase
			local baseDelay = (i % 2 == 0) and 0.02 or 0.08
			wait(baseDelay + math.random() * 0.06)
			local dur = 0.9 + (math.random() * 0.6)
			local info = TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			local goal = {TextColor3 = Color3.fromRGB(255,140,34)}
			local tw = TweenService:Create(lbl, info, goal)
			tw:Play()
		end)
	end

	return root, subtitle
end

makeAnimatedTitle(mainHeader, "NovaHub")

-- ===========================
-- Buttons / compact layout
-- ===========================
-- Top-left primary toggles
local btnToggle = makeBtn(mainFrame, 8, 86, 120, 36, "Fly: OFF")
local btnFloat = makeBtn(mainFrame, 8, 132, 120, 36, "Float: OFF")
local btnPlatform = makeBtn(mainFrame, 8, 178, 120, 30, "Platform: OFF")
local btnTp = makeBtn(mainFrame, 8, 218, 120, 26, "Tp")

-- NEW: JumpUI master toggle (in Fly mainFrame)
local btnJumpUI = makeBtn(mainFrame, 8, 260, 120, 30, "JumpUI: OFF")

-- Fly speed display & adjust
local flySpeedDec = makeBtn(mainFrame, 136, 86, 28, 26, "−")
local flySpeedLbl = Instance.new("TextLabel", mainFrame)
flySpeedLbl.Size = UDim2.new(0, 120, 0, 26)
flySpeedLbl.Position = UDim2.new(0, 168, 0, 86)
flySpeedLbl.BackgroundTransparency = 1
flySpeedLbl.Font = Enum.Font.Arcade
flySpeedLbl.TextScaled = true
flySpeedLbl.Text = "Fly: " .. tostring(math.floor(flySpeed))
flySpeedLbl.TextXAlignment = Enum.TextXAlignment.Left
flySpeedLbl.TextColor3 = Color3.fromRGB(230,230,230)
local flySpeedInc = makeBtn(mainFrame, 272, 86, 28, 26, "+")

-- FLOAT controls
local floatSpeedDec = makeBtn(mainFrame, 136, 132, 28, 30, "−")
local floatSpeedLbl = Instance.new("TextLabel", mainFrame)
floatSpeedLbl.Size = UDim2.new(0, 132, 0, 30)
floatSpeedLbl.Position = UDim2.new(0, 168, 0, 132)
floatSpeedLbl.BackgroundTransparency = 1
floatSpeedLbl.Font = Enum.Font.Arcade
floatSpeedLbl.TextScaled = true
floatSpeedLbl.Text = "Float Speed: " .. tostring(math.floor(floatForwardSpeed))
floatSpeedLbl.TextXAlignment = Enum.TextXAlignment.Left
floatSpeedLbl.TextColor3 = Color3.fromRGB(230,230,230)
local floatSpeedInc = makeBtn(mainFrame, 272, 132, 28, 30, "+")

local floatSmoothDec = makeBtn(mainFrame, 136, 168, 28, 30, "−")
local floatSmoothLbl = Instance.new("TextLabel", mainFrame)
floatSmoothLbl.Size = UDim2.new(0, 132, 0, 30)
floatSmoothLbl.Position = UDim2.new(0, 168, 0, 168)
floatSmoothLbl.BackgroundTransparency = 1
floatSmoothLbl.Font = Enum.Font.Arcade
floatSmoothLbl.TextScaled = true
floatSmoothLbl.Text = "Float Smooth: " .. tostring(math.floor(floatVerticalSmooth))
floatSmoothLbl.TextXAlignment = Enum.TextXAlignment.Left
floatSmoothLbl.TextColor3 = Color3.fromRGB(230,230,230)
local floatSmoothInc = makeBtn(mainFrame, 272, 168, 28, 30, "+")

local fallDec = makeBtn(mainFrame, 136, 204, 28, 22, "−")
local fallLbl = Instance.new("TextLabel", mainFrame)
fallLbl.Size = UDim2.new(0, 160, 0, 22)
fallLbl.Position = UDim2.new(0, 168, 0, 204)
fallLbl.BackgroundTransparency = 1
fallLbl.Font = Enum.Font.Arcade
fallLbl.TextScaled = true
fallLbl.Text = "Float Fall: " .. string.format("%.2f", floatFallMultiplier)
fallLbl.TextXAlignment = Enum.TextXAlignment.Left
fallLbl.TextColor3 = Color3.fromRGB(200,200,200)
local fallInc = makeBtn(mainFrame, 272, 204, 28, 22, "+")

-- ===========================
-- Align-based fly objects (unchanged)
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
	targetPart.Size = Vector3.new(1,1,1)
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

local targetVelocity = Vector3.new(0,0,0)
local floatVelocity = Vector3.new(0,0,0)
local tpTargetPos = nil
local isTpActive = false

-- platform helpers
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
		local a = Instance.new("Attachment", platformPart)
		a.Name = "FlyPlatform_Attach" .. tostring(i)
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
		if platformPart and root then platformPart.CFrame = CFrame.new(root.Position - Vector3.new(0, platformOffset, 0)) end
	else
		destroyPlatformPart()
	end
end
setPlatformEnabled(false)

-- ===========================
-- Enable/disable fly & float (hooked to UI)
-- ===========================
local function enableFly(enable)
	flyEnabled = enable
	btnToggle.Text = flyEnabled and "Fly: ON" or "Fly: OFF"
	if flyEnabled then
		if floatEnabled then
			floatEnabled = false
			btnFloat.Text = "Float: OFF"
		end
		if targetPart and root then
			targetPart.CFrame = root.CFrame
			targetVelocity = Vector3.new(0,0,0)
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
		targetVelocity = Vector3.new(0,0,0)
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
		if alignPos then
			alignPos.Enabled = true
			alignOri.Enabled = false
			alignPos.MaxForce = 5e5
			alignPos.Responsiveness = math.clamp(floatVerticalSmooth, 2, 50)
			alignPos.MaxVelocity = math.max(60, floatForwardSpeed * 2)
		end
		floatVelocity = Vector3.new(0,0,0)
		if targetPart and root then targetPart.CFrame = root.CFrame end
	else
		if alignPos then
			alignPos.Enabled = false
			alignPos.MaxForce = 1e6
			alignPos.Responsiveness = 18
			alignPos.MaxVelocity = math.huge
			alignOri.Enabled = false
		end
		floatVelocity = Vector3.new(0,0,0)
	end
end

-- UI hooking
btnToggle.MouseButton1Click:Connect(function() enableFly(not flyEnabled) end)
btnFloat.MouseButton1Click:Connect(function() enableFloat(not floatEnabled) end)
btnPlatform.MouseButton1Click:Connect(function() setPlatformEnabled(not platformEnabled) end)

-- TP button (small)
btnTp.MouseButton1Click:Connect(function()
	if not flyEnabled then return end
	local now = tick()
	if now - lastTpTime < tpCooldown then return end
	lastTpTime = now
	-- re-use computeTpTarget logic
	local cam = Workspace.CurrentCamera
	if not cam or not root then return end
	local look = cam.CFrame.LookVector
	local dir = useCameraPitchForTp and look or Vector3.new(look.X,0,look.Z)
	if dir.Magnitude == 0 then return end
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
	table.insert(origins, root.Position + Vector3.new(0,1.5,0))
	table.insert(origins, root.Position + Vector3.new(0,0.5,0))

	local bestFinal = nil
	for _, origin in ipairs(origins) do
		local cast = Workspace:Raycast(origin, dir * tpDistance, rayParams)
		local dest = nil
		if cast then dest = cast.Position - dir * 1.0 else dest = origin + dir * tpDistance end
		local downOrigin = dest + Vector3.new(0,60,0)
		local downCast = Workspace:Raycast(downOrigin, Vector3.new(0,-1,0) * 200, rayParams)
		if downCast then
			local bufferY = math.max(1.2, (root.Size.Y/2) + 0.5)
			local final = Vector3.new(downCast.Position.X, downCast.Position.Y + bufferY, downCast.Position.Z)
			if final.Y < root.Position.Y - 6 then final = Vector3.new(final.X, root.Position.Y + 2.2, final.Z) end
			for i = 1, 6 do
				local upCheck = Workspace:Raycast(final + Vector3.new(0,0.2,0), Vector3.new(0,1,0) * (root.Size.Y + 0.6), rayParams)
				if upCheck then final = final - dir * 0.45 else break end
			end
			bestFinal = final
			break
		else
			if useCameraPitchForTp then
				if dest.Y < root.Position.Y - 6 then dest = Vector3.new(dest.X, root.Position.Y + 2.2, dest.Z) end
				for i = 1, 6 do
					local upCheck = Workspace:Raycast(dest + Vector3.new(0,0.2,0), Vector3.new(0,1,0) * (root.Size.Y + 0.6), rayParams)
					if upCheck then dest = dest - dir * 0.45 else break end
				end
				bestFinal = dest
			else
				bestFinal = Vector3.new(dest.X, root.Position.Y + 2.2, dest.Z)
			end
		end
	end

	if bestFinal and targetPart then
		targetPart.CFrame = CFrame.new(bestFinal)
	end
end)

-- adjust labels: Fly speed
local function refreshFlyLabel()
	flySpeedLbl.Text = "Fly: " .. tostring(math.floor(flySpeed))
end
flySpeedDec.MouseButton1Click:Connect(function() flySpeed = math.clamp(flySpeed - 1, 1, 500); refreshFlyLabel() end)
flySpeedInc.MouseButton1Click:Connect(function() flySpeed = math.clamp(flySpeed + 1, 1, 500); refreshFlyLabel() end)
refreshFlyLabel()

-- FLOAT controls
local function refreshFloatSpeed()
	floatSpeedLbl.Text = "Float Speed: " .. tostring(math.floor(floatForwardSpeed))
end
floatSpeedDec.MouseButton1Click:Connect(function()
	floatForwardSpeed = math.clamp(floatForwardSpeed - 1, 1, 1000)
	if alignPos then alignPos.MaxVelocity = math.max(60, floatForwardSpeed * 2) end
	refreshFloatSpeed()
end)
floatSpeedInc.MouseButton1Click:Connect(function()
	floatForwardSpeed = math.clamp(floatForwardSpeed + 3, 1, 1000)
	if alignPos then alignPos.MaxVelocity = math.max(60, floatForwardSpeed * 2) end
	refreshFloatSpeed()
end)
refreshFloatSpeed()

local function refreshFloatSmooth()
	floatSmoothLbl.Text = "Float Smooth: " .. tostring(math.floor(floatVerticalSmooth))
	if alignPos then alignPos.Responsiveness = math.clamp(floatVerticalSmooth, 2, 50) end
end
floatSmoothDec.MouseButton1Click:Connect(function()
	floatVerticalSmooth = math.clamp(floatVerticalSmooth - 1, 0.5, 500)
	refreshFloatSmooth()
end)
floatSmoothInc.MouseButton1Click:Connect(function()
	floatVerticalSmooth = math.clamp(floatVerticalSmooth + 1, 0.5, 500)
	refreshFloatSmooth()
end)
refreshFloatSmooth()

local function refreshFall()
	fallLbl.Text = "Float Fall: " .. string.format("%.2f", floatFallMultiplier)
end
fallDec.MouseButton1Click:Connect(function()
	floatFallMultiplier = math.clamp(floatFallMultiplier - 0.3, 0.2, 30)
	refreshFall()
end)
fallInc.MouseButton1Click:Connect(function()
	floatFallMultiplier = math.clamp(floatFallMultiplier + 0.3, 0.2, 30)
	refreshFall()
end)
refreshFall()

-- vertical keyboard/touch control functions
local function startVertical(v) vertControl = v end
local function stopVertical() vertControl = 0 end

-- keyboard bindings (toggle fly/float + vertical control)
UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if inp.KeyCode == toggleKey then enableFly(not flyEnabled)
	elseif inp.KeyCode == floatKey then enableFloat(not floatEnabled)
	elseif inp.KeyCode == tpKey and flyEnabled then
		btnTp.MouseButton1Click:Fire()
	elseif flyEnabled then
		if inp.KeyCode == Enum.KeyCode.Space then startVertical(1)
		elseif inp.KeyCode == Enum.KeyCode.LeftShift then startVertical(-1) end
	end
end)
UIS.InputEnded:Connect(function(inp)
	if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if inp.KeyCode == Enum.KeyCode.Space or inp.KeyCode == Enum.KeyCode.LeftShift then stopVertical() end
end)

-- character respawn handling
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
-- MAIN LOOP: movement / float / fly logic
-- ===========================
RunService.Heartbeat:Connect(function(dt)
	if not root or not targetPart then return end

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

	-- FLOAT
	if floatEnabled then
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
			vert = -9.81 * (floatFallMultiplier - 1)
		end

		local desiredVel = hor + Vector3.new(0, vert, 0)
		local lerpFactor = math.clamp(acceleration * dt, 0, 1)
		floatVelocity = floatVelocity:Lerp(desiredVel, lerpFactor)

		local desiredDelta = floatVelocity * dt
		if desiredDelta.Magnitude > floatMaxStepPerFrame then
			desiredDelta = desiredDelta.Unit * floatMaxStepPerFrame
		end

		local currentPos = targetPart.Position
		local newPos = currentPos + desiredDelta
		local lerpForTarget = math.clamp(0.06 * math.max(dt * 60, 1), 0, 1)
		targetPart.CFrame = targetPart.CFrame:Lerp(CFrame.new(newPos), lerpForTarget)
		return
	end

	-- if neither float nor fly: keep target on root
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

	-- FLY
	local moveDir = humanoid and humanoid.MoveDirection or Vector3.new(0,0,0)
	local hor = Vector3.new(moveDir.X, 0, moveDir.Z) * flySpeed
	local vert = Vector3.new(0, vertControl * flySpeed, 0)
	local desiredVel = hor + vert
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

	if platformEnabled and platformPart then
		local desired = newPos - Vector3.new(0, platformOffset, 0)
		local pNew = platformPart.Position:Lerp(desired, math.clamp(platformLerp / math.max(dt, 1/60), 0, 1))
		platformPart.CFrame = CFrame.new(pNew)
	end
end)

local function flyCleanup()
	if targetPart and targetPart.Parent then targetPart:Destroy() end
	destroyPlatformPart()
	if flyScreenGui and flyScreenGui.Parent then flyScreenGui:Destroy() end
end

----------------------------------------------------------------
-- GRAVITY + BOOSTER (VectorForce) — kept intact, namespaced
----------------------------------------------------------------
local gravityScreenGui = Instance.new("ScreenGui")
gravityScreenGui.Name = "GravityBooster_GUI"
gravityScreenGui.ResetOnSpawn = false
gravityScreenGui.Parent = player:WaitForChild("PlayerGui")
gravityScreenGui.Enabled = false -- hidden by default, controlled by JumpUI button

local originalGravity = Workspace.Gravity

-- CONFIG (kept same as original)
local defaultGravity = 10
local gravityStep = 10
local gravityMin, gravityMax = 0, 1000

local defaultBooster = 4.5
local boosterStep = 0.5
local boosterMin, boosterMax = 0, 50

-- UI
local gravityFrame = Instance.new("Frame")
gravityFrame.Name = "Gravity_MainFrame"
gravityFrame.Size = UDim2.new(0, 200, 0, 140)
gravityFrame.Position = UDim2.new(0.5, -100, 0.08, 0)
gravityFrame.AnchorPoint = Vector2.new(0.5, 0)
gravityFrame.BackgroundColor3 = Color3.fromRGB(22,22,22)
gravityFrame.Active = true
gravityFrame.Draggable = true
gravityFrame.Parent = gravityScreenGui

local textlabb = Instance.new("TextLabel")
textlabb.BackgroundTransparency = 1
textlabb.TextColor3 = Color3.fromRGB(171, 63, 0)
textlabb.Text = "TT: @novahub67"
textlabb.Font = Enum.Font.Arcade
textlabb.TextScaled = true
textlabb.Parent = gravityFrame
textlabb.Position = UDim2.new(0, -27, 0, 25)
textlabb.Size = UDim2.new(1, -12, 0, 12)
local UiStlextlabb = Instance.new("UIStroke", textlabb)
UiStlextlabb.Thickness = 2
UiStlextlabb.Color = Color3.fromRGB(0, 132, 132)

local uicorner = Instance.new("UICorner", gravityFrame)
uicorner.CornerRadius = UDim.new(0, 8)

local stroke = Instance.new("UIStroke", gravityFrame)
stroke.Thickness = 5
stroke.Color = Color3.fromRGB(34,111,255)

-- Title per-letter
local titleRoot = Instance.new("Frame", gravityFrame)
titleRoot.Size = UDim2.new(1, -12, 0, 22)
titleRoot.Position = UDim2.new(0, 6, 0, 6)
titleRoot.BackgroundTransparency = 1

local titleText = "By NovaHub"
local list = Instance.new("UIListLayout", titleRoot)
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Left
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 2)

local letterLabels = {}
for i = 1, #titleText do
	local ch = titleText:sub(i,i)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 12, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Arcade
	lbl.Text = ch
	lbl.TextSize = 20
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255,140,34) -- start orange
	lbl.Parent = titleRoot

	local ls = Instance.new("UIStroke", lbl)
	ls.Thickness = 1
	ls.Color = Color3.fromRGB(0,0,0)
	ls.Transparency = 0.65

	table.insert(letterLabels, lbl)
end

-- Gravity UI (kept structure)
local gravLabel = Instance.new("TextLabel", gravityFrame)
gravLabel.Size = UDim2.new(0.6, -8, 0, 22)
gravLabel.Position = UDim2.new(0, 6, 0, 30)
gravLabel.BackgroundTransparency = 1
gravLabel.Font = Enum.Font.Arcade
gravLabel.TextScaled = true
gravLabel.TextXAlignment = Enum.TextXAlignment.Left
gravLabel.TextColor3 = Color3.fromRGB(230,230,230)

local gravBox = Instance.new("TextBox", gravityFrame)
gravBox.Size = UDim2.new(0.4, -12, 0, 22)
gravBox.Position = UDim2.new(0.6, 0, 0, 30)
gravBox.BackgroundColor3 = Color3.fromRGB(30,30,30)
gravBox.Font = Enum.Font.Arcade
gravBox.TextScaled = true
gravBox.Text = tostring(defaultGravity)
gravBox.TextColor3 = Color3.new(1,1,1)
gravBox.ClearTextOnFocus = false
local gravBoxCorner = Instance.new("UICorner", gravBox); gravBoxCorner.CornerRadius = UDim.new(0,6)

local btnGravMinus = Instance.new("TextButton", gravityFrame)
btnGravMinus.Size = UDim2.new(0, 36, 0, 20)
btnGravMinus.Position = UDim2.new(0, 110, 0, 56)
btnGravMinus.Text = "−"
btnGravMinus.TextColor3 = Color3.fromRGB(230, 230, 230)
btnGravMinus.Font = Enum.Font.Arcade
btnGravMinus.TextScaled = true
btnGravMinus.BackgroundColor3 = Color3.fromRGB(28,28,28)
local btnGravMinusCorner = Instance.new("UICorner", btnGravMinus); btnGravMinusCorner.CornerRadius = UDim.new(0,6)

local btnGravPlus = Instance.new("TextButton", gravityFrame)
btnGravPlus.Size = UDim2.new(0, 36, 0, 20)
btnGravPlus.Position = UDim2.new(1, -10, 0, 56)
btnGravPlus.AnchorPoint = Vector2.new(1,0)
btnGravPlus.Text = "+"
btnGravPlus.TextColor3 = Color3.fromRGB(230, 230, 230)
btnGravPlus.Font = Enum.Font.Arcade
btnGravPlus.TextScaled = true
btnGravPlus.BackgroundColor3 = Color3.fromRGB(28,28,28)
local btnGravPlusCorner = Instance.new("UICorner", btnGravPlus); btnGravPlusCorner.CornerRadius = UDim.new(0,6)

local gravToggle = Instance.new("TextButton", gravityFrame)
gravToggle.Size = UDim2.new(0, 100, 0, 30)
gravToggle.Position = UDim2.new(0.5, -50, 0, 50)
gravToggle.AnchorPoint = Vector2.new(0.5,0)
gravToggle.Text = "Gravity: OFF"
gravToggle.Font = Enum.Font.Arcade
gravToggle.TextScaled = true
gravToggle.BackgroundColor3 = Color3.fromRGB(44,44,44)
gravToggle.TextColor3 = Color3.new(1,1,1)
local gravToggleCorner = Instance.new("UICorner", gravToggle); gravToggleCorner.CornerRadius = UDim.new(0,6)

-- Booster UI
local boostLabel = Instance.new("TextLabel", gravityFrame)
boostLabel.Size = UDim2.new(0.5, -8, 0, 30)
boostLabel.Position = UDim2.new(0, 6, 0, 79)
boostLabel.BackgroundTransparency = 1
boostLabel.Font = Enum.Font.Arcade
boostLabel.TextScaled = true
boostLabel.TextXAlignment = Enum.TextXAlignment.Left
boostLabel.Text = "Booster:"
boostLabel.TextColor3 = Color3.fromRGB(230, 230, 230)

local boostBox = Instance.new("TextBox", gravityFrame)
boostBox.Size = UDim2.new(0.35, -1, 0, 20)
boostBox.Position = UDim2.new(0.5, 20, 0, 84)
boostBox.BackgroundColor3 = Color3.fromRGB(30,30,30)
boostBox.Font = Enum.Font.Arcade
boostBox.TextScaled = true
boostBox.Text = tostring(defaultBooster)
boostBox.TextColor3 = Color3.fromRGB(230, 230, 230)
boostBox.ClearTextOnFocus = false
local boostBoxCorner = Instance.new("UICorner", boostBox); boostBoxCorner.CornerRadius = UDim.new(0,6)

local btnBoostMinus = Instance.new("TextButton", gravityFrame)
btnBoostMinus.Size = UDim2.new(0, 28, 0, 18)
btnBoostMinus.Position = UDim2.new(0, 120, 0, 108)
btnBoostMinus.Text = "−"
btnBoostMinus.TextColor3 = Color3.fromRGB(230, 230, 230)
btnBoostMinus.Font = Enum.Font.Arcade
btnBoostMinus.TextScaled = true
btnBoostMinus.BackgroundColor3 = Color3.fromRGB(28,28,28)
local btnBoostMinusCorner = Instance.new("UICorner", btnBoostMinus); btnBoostMinusCorner.CornerRadius = UDim.new(0,6)

local btnBoostPlus = Instance.new("TextButton", gravityFrame)
btnBoostPlus.Size = UDim2.new(0, 28, 0, 18)
btnBoostPlus.Position = UDim2.new(1, -14, 0, 108)
btnBoostPlus.AnchorPoint = Vector2.new(1,0)
btnBoostPlus.Text = "+"
btnBoostPlus.TextColor3 = Color3.fromRGB(230, 230, 230)
btnBoostPlus.Font = Enum.Font.Arcade
btnBoostPlus.TextScaled = true
btnBoostPlus.BackgroundColor3 = Color3.fromRGB(28,28,28)
local btnBoostPlusCorner = Instance.new("UICorner", btnBoostPlus); btnBoostPlusCorner.CornerRadius = UDim.new(0,6)

local boostToggle = Instance.new("TextButton", gravityFrame)
boostToggle.Size = UDim2.new(0, 100, 0, 31)
boostToggle.Position = UDim2.new(0.5, -50, 0, 108)
boostToggle.AnchorPoint = Vector2.new(0.5,0)
boostToggle.Text = "Booster: OFF"
boostToggle.TextColor3 = Color3.fromRGB(230, 230, 230)
boostToggle.Font = Enum.Font.Arcade
boostToggle.TextScaled = true
boostToggle.BackgroundColor3 = Color3.fromRGB(44,44,44)
local boostToggleCorner = Instance.new("UICorner", boostToggle); boostToggleCorner.CornerRadius = UDim.new(0,6)

-- State (kept same)
local currentGravity = math.clamp(tonumber(gravBox.Text) or defaultGravity, gravityMin, gravityMax)
local gravityApplied = false

local currentBooster = math.clamp(tonumber(boostBox.Text) or defaultBooster, boosterMin, boosterMax)
local boosterEnabled = false

-- VectorForce objects
local vf = nil
local vfAttachment = nil
local lastMass = nil

-- Helpers
local function refreshGravityLabels()
	gravLabel.Text = "Gravity: " .. tostring(currentGravity)
	gravBox.Text = tostring(currentGravity)
	gravToggle.Text = gravityApplied and ("Gravity: ON ("..tostring(currentGravity)..")") or "Gravity: OFF"

	boostLabel.Text = "Booster: " .. string.format("%.2f", currentBooster)
	boostBox.Text = tostring(currentBooster)
	boostToggle.Text = boosterEnabled and "Booster: ON" or "Booster: OFF"
end

local function applyGravity(val)
	val = math.clamp(val, gravityMin, gravityMax)
	Workspace.Gravity = val
end

local function restoreOriginalGravity()
	if originalGravity then
		Workspace.Gravity = originalGravity
	end
end

local function createVectorForce(rootPart)
	-- cleanup existing
	if vf then pcall(function() vf:Destroy() end) end
	if vfAttachment then pcall(function() vfAttachment:Destroy() end) end

	vfAttachment = Instance.new("Attachment")
	vfAttachment.Name = "NovaHub_Boost_Attachment"
	vfAttachment.Parent = rootPart

	vf = Instance.new("VectorForce")
	vf.Name = "NovaHub_Boost_VectorForce"
	vf.Attachment0 = vfAttachment
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Force = Vector3.new(0,0,0)
	vf.Parent = rootPart

	lastMass = nil
end

local function destroyVectorForce()
	if vf then pcall(function() vf:Destroy() end) end
	if vfAttachment then pcall(function() vfAttachment:Destroy() end) end
	vf = nil
	vfAttachment = nil
	lastMass = nil
end

local function setBoosterEnabled(state)
	boosterEnabled = state
	if boosterEnabled then
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			createVectorForce(char.HumanoidRootPart)
		end
	else
		destroyVectorForce()
	end
	refreshGravityLabels()
end

-- UI events
btnGravPlus.MouseButton1Click:Connect(function()
	currentGravity = math.clamp(currentGravity + gravityStep, gravityMin, gravityMax)
	if gravityApplied then applyGravity(currentGravity) end
	refreshGravityLabels()
end)
btnGravMinus.MouseButton1Click:Connect(function()
	currentGravity = math.clamp(currentGravity - gravityStep, gravityMin, gravityMax)
	if gravityApplied then applyGravity(currentGravity) end
	refreshGravityLabels()
end)
gravBox.FocusLost:Connect(function()
	local v = tonumber(gravBox.Text)
	if v then currentGravity = math.clamp(v, gravityMin, gravityMax) else gravBox.Text = tostring(currentGravity) end
	if gravityApplied then applyGravity(currentGravity) end
	refreshGravityLabels()
end)
gravToggle.MouseButton1Click:Connect(function()
	gravityApplied = not gravityApplied
	if gravityApplied then applyGravity(currentGravity) else restoreOriginalGravity() end
	refreshGravityLabels()
end)

btnBoostPlus.MouseButton1Click:Connect(function()
	currentBooster = math.clamp(currentBooster + boosterStep, boosterMin, boosterMax)
	refreshGravityLabels()
end)
btnBoostMinus.MouseButton1Click:Connect(function()
	currentBooster = math.clamp(currentBooster - boosterStep, boosterMin, boosterMax)
	refreshGravityLabels()
end)
boostBox.FocusLost:Connect(function()
	local v = tonumber(boostBox.Text)
	if v then currentBooster = math.clamp(v, boosterMin, boosterMax) else boostBox.Text = tostring(currentBooster) end
	refreshGravityLabels()
end)
boostToggle.MouseButton1Click:Connect(function()
	setBoosterEnabled(not boosterEnabled)
end)

-- Per-letter async tween for gravity title
for i, lbl in ipairs(letterLabels) do
	spawn(function()
		while gravityScreenGui.Parent do
			local toBlueDur = 0.4 + math.random() * 1.0 + (i % 3) * 0.03
			local t1 = TweenInfo.new(toBlueDur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local tw1 = TweenService:Create(lbl, t1, {TextColor3 = Color3.fromRGB(34,111,255)})
			tw1:Play()
			tw1.Completed:Wait()
			wait(0.02 + math.random() * 0.12)
			local toOrangeDur = 0.35 + math.random() * 0.9 + ((#letterLabels - i) % 4) * 0.03
			local t2 = TweenInfo.new(toOrangeDur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local tw2 = TweenService:Create(lbl, t2, {TextColor3 = Color3.fromRGB(255,140,34)})
			tw2:Play()
			tw2.Completed:Wait()
			wait(0.04 + math.random() * 0.18)
		end
	end)
end

-- Stroke tween loop (frame)
do
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true)
	local goal = {Color = Color3.fromRGB(255,140,34)}
	local tw = TweenService:Create(stroke, info, goal)
	tw:Play()
end

-- Heartbeat: update VectorForce each frame
RunService.Heartbeat:Connect(function(dt)
	if boosterEnabled and vf and vfAttachment and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local rroot = player.Character.HumanoidRootPart
		local ok, mass = pcall(function() return rroot:GetMass() end)
		if ok and mass and mass > 0 then lastMass = mass end
		local massNow = lastMass or 1
		local a = math.clamp(currentBooster, boosterMin, boosterMax)
		local totalUp = massNow * (Workspace.Gravity + a)
		if totalUp < 0 then totalUp = 0 end
		vf.Force = Vector3.new(0, totalUp, 0)
		if vfAttachment.Parent ~= rroot then vfAttachment.Parent = rroot end
	end
end)

player.CharacterAdded:Connect(function(char)
	if boosterEnabled then
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then createVectorForce(hrp) end
	end
end)

-- initial labels
refreshGravityLabels()

-- JumpUI toggle behavior:
-- btnJumpUI toggles gravityScreenGui visibility and enables/disables gravity/booster functions.
-- It saves previous states so enabling will restore them.
local savedGravityApplied = gravityApplied
local savedBoosterEnabled = boosterEnabled
local jumpUiActive = false

btnJumpUI.MouseButton1Click:Connect(function()
	jumpUiActive = not jumpUiActive
	if jumpUiActive then
		-- open gravity GUI and restore saved states
		gravityScreenGui.Enabled = true
		gravityFrame.Visible = true
		-- restore previous saved states
		gravityApplied = savedGravityApplied or gravityApplied
		if gravityApplied then applyGravity(currentGravity) end
		boosterEnabled = savedBoosterEnabled or boosterEnabled
		if boosterEnabled then
			setBoosterEnabled(true)
		else
			-- ensure UI reflects current state
			refreshGravityLabels()
		end
		btnJumpUI.Text = "JumpUI: ON"
	else
		-- hide gravity UI and save states, then disable gravity/booster and restore original gravity
		savedGravityApplied = gravityApplied
		savedBoosterEnabled = boosterEnabled
		gravityScreenGui.Enabled = false
		-- disable gravity override and booster
		gravityApplied = false
		restoreOriginalGravity()
		if boosterEnabled then setBoosterEnabled(false) end
		btnJumpUI.Text = "JumpUI: OFF"
	end
	-- refresh labels to reflect current state
	refreshGravityLabels()
end)

-- Cleanup on script destroy
script.Destroying:Connect(function()
	-- restore gravity
	if originalGravity then Workspace.Gravity = originalGravity end
	-- destroy VF
	destroyVectorForce()
	-- destroy GUIs and fly parts
	flyCleanup()
	if gravityScreenGui and gravityScreenGui.Parent then gravityScreenGui:Destroy() end
end)

-- Init visibility states
gravityScreenGui.Enabled = false
btnJumpUI.Text = "JumpUI: OFF"

-- End of combined LocalScript

