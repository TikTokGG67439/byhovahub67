-- Smooth Fly v3 — Compact UI edition
-- Put into StarterPlayerScripts (replaces prior UI only; movement logic unchanged)
-- Compact frame, NovaHub animated per-letter title, Arcade font, TextScaled = true

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
-- CONFIG (adjust as needed)
-- ===========================
local flyEnabled = false
local vertControl = 0 -- -1 down, 0 none, 1 up
local flySpeed = 29

-- FLOAT params (separate from fly)
local floatEnabled = false
local floatForwardSpeed = 111
local floatFallMultiplier = 8
local floatVerticalSmooth = 11
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

-- UI root
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlyGUI_v3_compact"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

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

-- Main compact frame (exact requested size)

local function makeMainFrame()
	local frame = Instance.new("Frame")
	frame.Name = "FlyMainFrame"
	frame.Size = UDim2.new(0, 330, 0, 330) -- exact
	frame.Position = UDim2.new(0, 376, 0, 120)
	frame.BackgroundTransparency = 0.05
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.Parent = screenGui
	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 12)

local imagebutton = Instance.new("ImageButton")
imagebutton.Image = "rbxassetid://106730820213474"
imagebutton.Position = UDim2.new(0.476, 0,0.400, 0)
imagebutton.Size = UDim2.new(0, 70, 0, 70)
imagebutton.Active = true
imagebutton.Draggable = true
imagebutton.Parent = screenGui
local uistoke = Instance.new("UICorner")
uistoke.Parent = imagebutton
uistoke.CornerRadius = UDim.new(0, 10)
local uistokeke = Instance.new("UIStroke")
uistokeke.Thickness = 2
uistokeke.Color = Color3.fromRGB(167, 94, 30)
uistokeke.Parent = imagebutton
imagebutton.MouseButton1Click:Connect(function()
	frame.Visible = not frame.Visible
end)


	local stroke = Instance.new("UIStroke", frame, imagebutton)
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

-- === FLOAT controls: main two controls visible ===
-- Float Speed (horizontal)
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

-- Float Smooth (vertical smoothing / gentle release)
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

-- Small compact Fall multiplier control (less prominent, but available)
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

-- platform helpers unchanged
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
	-- re-use computeTpTarget logic (kept minimal here to avoid forward ref issues)
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

-- FLOAT controls: main two (movement speed & vertical smooth)
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

-- small fall multiplier control (compact)
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
-- Main loop: movement / float / fly logic (kept intact)
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

	-- FLOAT (distinct from fly)
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
			-- gravity-like gentle fall; floatFallMultiplier controls how fast you release downwards
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

	-- FLY behavior (unchanged)
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

-- cleanup on destroy
script.Destroying:Connect(function()
	if targetPart and targetPart.Parent then targetPart:Destroy() end
	destroyPlatformPart()
	if screenGui and screenGui.Parent then screenGui:Destroy() end
end)

-- end of script

