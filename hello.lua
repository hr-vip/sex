--===================================================================================
--                  ENIGMA HUB - ADVANCED ROBLOX COMBAT ENGINE
--===================================================================================
-- Description: Advanced Aimbot, Silent Aim, ESP, & Chams for Roblox Executors.
-- GUI Library: Rayfield Interface Suite (https://sirius.menu/rayfield)
-- Supported Environment: LuaU (Synapse, Wave, Solara, Macsploit, etc.)
--===================================================================================

-- Prevent multiple executions
if getgenv().EnigmaHubLoaded then
    warn("[Enigma Hub] Already executed in this session!")
    return
end
getgenv().EnigmaHubLoaded = true

-------------------------------------------------------------------------------------
-- SERVICES
-------------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Teams = game:GetService("Teams")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------
-- CONSTANTS & VARIABLES
-------------------------------------------------------------------------------------
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- Configuration State
local EnigmaConfig = {
    Aimbot = {
        Enabled = false,
        Key = Enum.UserInputType.MouseButton2, -- Right Click default
        Part = "Head", -- Head, Torso, HumanoidRootPart
        Smoothness = 0.1, -- Lerp speed (0 to 1)
        TeamCheck = true,
        WallCheck = true,
        HealthCheck = true,
        FOV = {
            Enabled = true,
            Radius = 100,
            Color = Color3.fromRGB(235, 59, 90), -- Crimson red
            Thickness = 1.5,
            Filled = false,
            Transparency = 0.7
        },
        Prediction = {
            Enabled = false,
            VelocityMultiplier = 0.135
        },
        TargetLock = false,
        FreezeTarget = false,
        TargetVisuals = false,
        TargetVisualsColor = Color3.fromRGB(255, 234, 0)
    },
    SilentAim = {
        Enabled = false,
        HitChance = 100, -- percentage
        Part = "Head",
        TeamCheck = true,
        WallCheck = true,
        HealthCheck = true,
        FOV = {
            Enabled = false,
            Radius = 150,
            Color = Color3.fromRGB(43, 203, 186) -- Cyan/Teal
        }
    },
    ESP = {
        Enabled = false,
        Boxes = false,
        BoxColor = Color3.fromRGB(255, 255, 255),
        Names = false,
        NameColor = Color3.fromRGB(255, 255, 255),
        Tracers = false,
        TracerColor = Color3.fromRGB(255, 255, 255),
        TracerOrigin = "Bottom", -- Bottom, Middle, Mouse
        Health = false,
        Chams = false,
        ChamsFillColor = Color3.fromRGB(235, 59, 90),
        ChamsOutlineColor = Color3.fromRGB(255, 255, 255),
        ChamsFillTransparency = 0.5,
        ChamsOutlineTransparency = 0
    }
}

-- Runtime variables
local AimbotHolding = false
local AimbotTarget = nil
local ESPCache = {}

-------------------------------------------------------------------------------------
-- DRAWING API - FOV CIRCLES
-------------------------------------------------------------------------------------
local AimbotFOVCircle = Drawing.new("Circle")
AimbotFOVCircle.Visible = false
AimbotFOVCircle.NumSides = 64
AimbotFOVCircle.Thickness = 1.5

local SilentAimFOVCircle = Drawing.new("Circle")
SilentAimFOVCircle.Visible = false
SilentAimFOVCircle.NumSides = 64
SilentAimFOVCircle.Thickness = 1.5

-- Targeting Visual Drawings
local TargetVisualLine = Drawing.new("Line")
TargetVisualLine.Visible = false
TargetVisualLine.Thickness = 2

local TargetVisualCircle = Drawing.new("Circle")
TargetVisualCircle.Visible = false
TargetVisualCircle.Radius = 15
TargetVisualCircle.Thickness = 2
TargetVisualCircle.NumSides = 32

-- Target position freeze states
local TargetFrozenPlayer = nil
local TargetFrozenPosition = nil

local function UpdateFOVCircles()
    -- Aimbot FOV
    if EnigmaConfig.Aimbot.Enabled and EnigmaConfig.Aimbot.FOV.Enabled then
        AimbotFOVCircle.Visible = true
        AimbotFOVCircle.Radius = EnigmaConfig.Aimbot.FOV.Radius
        AimbotFOVCircle.Color = EnigmaConfig.Aimbot.FOV.Color
        AimbotFOVCircle.Thickness = EnigmaConfig.Aimbot.FOV.Thickness
        AimbotFOVCircle.Filled = EnigmaConfig.Aimbot.FOV.Filled
        AimbotFOVCircle.Transparency = EnigmaConfig.Aimbot.FOV.Transparency
        AimbotFOVCircle.Position = UserInputService:GetMouseLocation()
    else
        AimbotFOVCircle.Visible = false
    end

    -- Silent Aim FOV
    if EnigmaConfig.SilentAim.Enabled and EnigmaConfig.SilentAim.FOV.Enabled then
        SilentAimFOVCircle.Visible = true
        SilentAimFOVCircle.Radius = EnigmaConfig.SilentAim.FOV.Radius
        SilentAimFOVCircle.Color = EnigmaConfig.SilentAim.FOV.Color
        SilentAimFOVCircle.Position = UserInputService:GetMouseLocation()
    else
        SilentAimFOVCircle.Visible = false
    end
end

-------------------------------------------------------------------------------------
-- TARGET ACQUISITION & VALIDATION UTILITIES
-------------------------------------------------------------------------------------
local function IsPlayerAlive(player)
    return player and player.Character and player.Character:FindFirstChild("Humanoid") 
           and player.Character.Humanoid.Health > 0 
           and player.Character:FindFirstChild("HumanoidRootPart")
end

local function IsPlayerVisible(player, partName)
    local character = player.Character
    if not character then return false end
    
    local targetPart = character:FindFirstChild(partName)
    if not targetPart then return false end

    local origin = Camera.CFrame.Position
    local destination = targetPart.Position
    local direction = destination - origin

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    -- Ignore local player character, the target character, and transparent target accessories
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, character, Camera}
    raycastParams.IgnoreWater = true

    local result = Workspace:Raycast(origin, direction, raycastParams)
    
    -- If no obstacle hit, then player is visible
    return result == nil
end

local function IsOnSameTeam(player)
    if player.Team == LocalPlayer.Team then
        return true
    end
    return false
end

-- Get closest player to the cursor based on configuration
local function GetClosestPlayerToCursor(fovRadius, wallCheck, teamCheck, healthCheck, targetPartName)
    local closestPlayer = nil
    local shortestDistance = fovRadius or math.huge
    local mouseLocation = UserInputService:GetMouseLocation()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsPlayerAlive(player) then
            -- Team check
            if teamCheck and IsOnSameTeam(player) then
                continue
            end

            -- Target part selection
            local targetPart = player.Character:FindFirstChild(targetPartName)
            if not targetPart then continue end

            -- Get screen position
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if not onScreen then continue end

            -- Calculate 2D distance from cursor
            local screenPos2D = Vector2.new(screenPos.X, screenPos.Y)
            local distance = (screenPos2D - mouseLocation).Magnitude

            if distance < shortestDistance then
                -- Wall check
                if wallCheck and not IsPlayerVisible(player, targetPartName) then
                    continue
                end

                shortestDistance = distance
                closestPlayer = player
            end
        end
    end

    return closestPlayer
end

-------------------------------------------------------------------------------------
-- CAMERA AIMBOT MODULE
-------------------------------------------------------------------------------------
local function ProcessCameraAimbot()
    if not EnigmaConfig.Aimbot.Enabled or not AimbotHolding then 
        AimbotTarget = nil
        return 
    end

    -- Acquire or maintain target
    local maintain = false
    if EnigmaConfig.Aimbot.TargetLock and AimbotTarget and IsPlayerAlive(AimbotTarget) then
        local valid = true
        if EnigmaConfig.Aimbot.TeamCheck and IsOnSameTeam(AimbotTarget) then
            valid = false
        elseif EnigmaConfig.Aimbot.WallCheck and not IsPlayerVisible(AimbotTarget, EnigmaConfig.Aimbot.Part) then
            valid = false
        end
        if valid then
            maintain = true
        end
    end

    if not maintain then
        AimbotTarget = GetClosestPlayerToCursor(
            EnigmaConfig.Aimbot.FOV.Enabled and EnigmaConfig.Aimbot.FOV.Radius or math.huge,
            EnigmaConfig.Aimbot.WallCheck,
            EnigmaConfig.Aimbot.TeamCheck,
            EnigmaConfig.Aimbot.HealthCheck,
            EnigmaConfig.Aimbot.Part
        )
    end

    if AimbotTarget and IsPlayerAlive(AimbotTarget) then
        local targetPart = AimbotTarget.Character:FindFirstChild(EnigmaConfig.Aimbot.Part)
        if targetPart then
            local targetPos = targetPart.Position

            -- Lead targets using prediction
            if EnigmaConfig.Aimbot.Prediction.Enabled then
                local velocity = targetPart.AssemblyLinearVelocity
                targetPos = targetPos + (velocity * EnigmaConfig.Aimbot.Prediction.VelocityMultiplier)
            end

            -- Lerp camera orientation
            local currentLookVector = Camera.CFrame.Position
            local aimCFrame = CFrame.new(currentLookVector, targetPos)
            
            -- Smooth rotation
            Camera.CFrame = Camera.CFrame:Lerp(aimCFrame, EnigmaConfig.Aimbot.Smoothness)
        end
    end
end

-- Update targeting visuals locally
local function UpdateTargetVisuals()
    if EnigmaConfig.Aimbot.TargetVisuals and AimbotTarget and IsPlayerAlive(AimbotTarget) then
        local targetPart = AimbotTarget.Character:FindFirstChild(EnigmaConfig.Aimbot.Part)
        if targetPart then
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if onScreen then
                local mouseLocation = UserInputService:GetMouseLocation()
                
                -- Tracer Line
                TargetVisualLine.From = mouseLocation
                TargetVisualLine.To = Vector2.new(screenPos.X, screenPos.Y)
                TargetVisualLine.Color = EnigmaConfig.Aimbot.TargetVisualsColor
                TargetVisualLine.Visible = true
                
                -- Reticle Circle
                TargetVisualCircle.Position = Vector2.new(screenPos.X, screenPos.Y)
                TargetVisualCircle.Color = EnigmaConfig.Aimbot.TargetVisualsColor
                TargetVisualCircle.Visible = true
                return
            end
        end
    end
    TargetVisualLine.Visible = false
    TargetVisualCircle.Visible = false
end

-- Apply local position freeze on target
local function ApplyTargetFreeze()
    if EnigmaConfig.Aimbot.FreezeTarget and AimbotTarget and IsPlayerAlive(AimbotTarget) then
        local root = AimbotTarget.Character:FindFirstChild("HumanoidRootPart")
        if root then
            if TargetFrozenPlayer ~= AimbotTarget then
                TargetFrozenPlayer = AimbotTarget
                TargetFrozenPosition = root.CFrame
            end
            for _, part in ipairs(AimbotTarget.Character:GetChildren()) do
                if part:IsA("BasePart") then
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end
            root.CFrame = TargetFrozenPosition
        end
    else
        TargetFrozenPlayer = nil
        TargetFrozenPosition = nil
    end
end

-------------------------------------------------------------------------------------
-- SILENT AIM INTERCEPTION HOOKS
-------------------------------------------------------------------------------------
local SilentAimTarget = nil

-- Update Silent Aim target regularly
task.spawn(function()
    while task.wait(0.05) do
        if EnigmaConfig.SilentAim.Enabled then
            SilentAimTarget = GetClosestPlayerToCursor(
                EnigmaConfig.SilentAim.FOV.Enabled and EnigmaConfig.SilentAim.FOV.Radius or math.huge,
                EnigmaConfig.SilentAim.WallCheck,
                EnigmaConfig.SilentAim.TeamCheck,
                EnigmaConfig.SilentAim.HealthCheck,
                EnigmaConfig.SilentAim.Part
            )
        else
            SilentAimTarget = nil
        end
    end
end)

-- Metatable Hooker
local function InitiateSilentAimHook()
    local mt = getrawmetatable(game)
    if not mt then
        warn("[Enigma Hub] Executor environment does not support getrawmetatable!")
        return
    end

    local oldNamecall = mt.__namecall
    local oldIndex = mt.__index
    setreadonly(mt, false)

    -- Hook Namecall for Raycast & FindPartOnRay
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if EnigmaConfig.SilentAim.Enabled and SilentAimTarget and IsPlayerAlive(SilentAimTarget) then
            -- Calculate hit chance check
            local hitChanceRoll = math.random(1, 100)
            if hitChanceRoll <= EnigmaConfig.SilentAim.HitChance then
                local targetPart = SilentAimTarget.Character:FindFirstChild(EnigmaConfig.SilentAim.Part)
                if targetPart then
                    -- Intercept Workspace:FindPartOnRay methods
                    if method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                        local origin = args[1].Origin
                        local direction = (targetPart.Position - origin).Unit * 1000
                        args[1] = Ray.new(origin, direction)
                        return oldNamecall(self, table.unpack(args))
                    end

                    -- Intercept Workspace:Raycast
                    if method == "Raycast" and self == Workspace then
                        local origin = args[1]
                        local direction = (targetPart.Position - origin).Unit * 1000
                        args[2] = direction
                        return oldNamecall(self, table.unpack(args))
                    end
                end
            end
        end

        return oldNamecall(self, ...)
    end)

    -- Hook Index for mouse position redirection (highly premium for projectile weapons/tools)
    mt.__index = newcclosure(function(self, index)
        if EnigmaConfig.SilentAim.Enabled and SilentAimTarget and IsPlayerAlive(SilentAimTarget) then
            local hitChanceRoll = math.random(1, 100)
            if hitChanceRoll <= EnigmaConfig.SilentAim.HitChance then
                local targetPart = SilentAimTarget.Character:FindFirstChild(EnigmaConfig.SilentAim.Part)
                if targetPart then
                    if self == Mouse and (index == "Hit" or index == "Target") then
                        if index == "Hit" then
                            return targetPart.CFrame
                        elseif index == "Target" then
                            return targetPart
                        end
                    end
                end
            end
        end

        return oldIndex(self, index)
    end)

    setreadonly(mt, true)
    print("[Enigma Hub] Silent Aim Metatable Hook successfully established.")
end

-------------------------------------------------------------------------------------
-- VISUALS: ESP AND CHAMS
-------------------------------------------------------------------------------------
local function RemoveESP(player)
    local cache = ESPCache[player]
    if cache then
        if cache.Box then cache.Box:Remove() end
        if cache.BoxOutline then cache.BoxOutline:Remove() end
        if cache.Tracer then cache.Tracer:Remove() end
        if cache.Name then cache.Name:Remove() end
        if cache.HealthBar then cache.HealthBar:Remove() end
        if cache.HealthOutline then cache.HealthOutline:Remove() end
        if cache.Highlight then cache.Highlight:Destroy() end
        ESPCache[player] = nil
    end
end

local function CreateESP(player)
    if ESPCache[player] then RemoveESP(player) end

    local cache = {
        Box = Drawing.new("Square"),
        BoxOutline = Drawing.new("Square"),
        Tracer = Drawing.new("Line"),
        Name = Drawing.new("Text"),
        HealthBar = Drawing.new("Line"),
        HealthOutline = Drawing.new("Line"),
        Highlight = nil
    }

    -- Standard properties
    cache.Box.Thickness = 1.5
    cache.Box.Filled = false
    cache.Box.Transparency = 1
    
    cache.BoxOutline.Thickness = 2.5
    cache.BoxOutline.Filled = false
    cache.BoxOutline.Color = Color3.fromRGB(0, 0, 0)
    cache.BoxOutline.Transparency = 0.5

    cache.Tracer.Thickness = 1.5
    cache.Tracer.Transparency = 1

    cache.Name.Size = 14
    cache.Name.Center = true
    cache.Name.Outline = true
    cache.Name.OutlineColor = Color3.fromRGB(0, 0, 0)
    cache.Name.Transparency = 1

    cache.HealthBar.Thickness = 2
    cache.HealthBar.Transparency = 1
    
    cache.HealthOutline.Thickness = 3
    cache.HealthOutline.Color = Color3.fromRGB(0, 0, 0)
    cache.HealthOutline.Transparency = 0.5

    ESPCache[player] = cache
end

local function UpdateESP()
    for player, cache in pairs(ESPCache) do
        if not IsPlayerAlive(player) or not EnigmaConfig.ESP.Enabled then
            -- Hide drawing visual overlays
            cache.Box.Visible = false
            cache.BoxOutline.Visible = false
            cache.Tracer.Visible = false
            cache.Name.Visible = false
            cache.HealthBar.Visible = false
            cache.HealthOutline.Visible = false
            if cache.Highlight then cache.Highlight.Enabled = false end
            continue
        end

        local character = player.Character
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChild("Humanoid")
        if not rootPart or not humanoid then continue end

        local rootPos, onScreen = Camera:WorldToViewportPoint(rootPart.Position)

        -- Handle highlight/chams
        if EnigmaConfig.ESP.Chams then
            if not cache.Highlight or cache.Highlight.Parent ~= character then
                if cache.Highlight then cache.Highlight:Destroy() end
                cache.Highlight = Instance.new("Highlight")
                cache.Highlight.Parent = character
            end
            cache.Highlight.Enabled = true
            cache.Highlight.FillColor = EnigmaConfig.ESP.ChamsFillColor
            cache.Highlight.OutlineColor = EnigmaConfig.ESP.ChamsOutlineColor
            cache.Highlight.FillTransparency = EnigmaConfig.ESP.ChamsFillTransparency
            cache.Highlight.OutlineTransparency = EnigmaConfig.ESP.ChamsOutlineTransparency
        else
            if cache.Highlight then
                cache.Highlight.Enabled = false
            end
        end

        if onScreen then
            -- Calculate dynamic scaling based on distance from camera
            local head = character:FindFirstChild("Head")
            if not head then continue end
            
            local headPos = Camera:WorldToViewportPoint(head.Position)
            local height = math.clamp(math.abs(rootPos.Y - headPos.Y) * 2.5, 10, 1000)
            local width = height * 0.6

            -- Boxes
            if EnigmaConfig.ESP.Boxes then
                cache.Box.Size = Vector2.new(width, height)
                cache.Box.Position = Vector2.new(rootPos.X - width / 2, rootPos.Y - height / 2)
                cache.Box.Color = EnigmaConfig.ESP.BoxColor
                cache.Box.Visible = true

                cache.BoxOutline.Size = cache.Box.Size
                cache.BoxOutline.Position = cache.Box.Position
                cache.BoxOutline.Visible = true
            else
                cache.Box.Visible = false
                cache.BoxOutline.Visible = false
            end

            -- Tracers
            if EnigmaConfig.ESP.Tracers then
                local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                local screenBottom = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                
                local originPos = screenBottom
                if EnigmaConfig.ESP.TracerOrigin == "Middle" then
                    originPos = screenCenter
                elseif EnigmaConfig.ESP.TracerOrigin == "Mouse" then
                    originPos = UserInputService:GetMouseLocation()
                end

                cache.Tracer.From = originPos
                cache.Tracer.To = Vector2.new(rootPos.X, rootPos.Y + (height / 2))
                cache.Tracer.Color = EnigmaConfig.ESP.TracerColor
                cache.Tracer.Visible = true
            else
                cache.Tracer.Visible = false
            end

            -- Name
            if EnigmaConfig.ESP.Names then
                cache.Name.Text = string.format("%s [%d m]", player.Name, math.round((rootPart.Position - Camera.CFrame.Position).Magnitude))
                cache.Name.Position = Vector2.new(rootPos.X, rootPos.Y - (height / 2) - 18)
                cache.Name.Color = EnigmaConfig.ESP.NameColor
                cache.Name.Visible = true
            else
                cache.Name.Visible = false
            end

            -- Health Bar
            if EnigmaConfig.ESP.Health then
                local healthPercentage = humanoid.Health / humanoid.MaxHealth
                local healthHeight = height * healthPercentage
                local barPosition = Vector2.new(rootPos.X - (width / 2) - 6, rootPos.Y - (height / 2))

                cache.HealthOutline.From = Vector2.new(barPosition.X, barPosition.Y)
                cache.HealthOutline.To = Vector2.new(barPosition.X, barPosition.Y + height)
                cache.HealthOutline.Visible = true

                -- Color health bar dynamic (green to red transition)
                local healthColor = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), healthPercentage)

                cache.HealthBar.From = Vector2.new(barPosition.X, barPosition.Y + height)
                cache.HealthBar.To = Vector2.new(barPosition.X, barPosition.Y + height - healthHeight)
                cache.HealthBar.Color = healthColor
                cache.HealthBar.Visible = true
            else
                cache.HealthBar.Visible = false
                cache.HealthOutline.Visible = false
            end
        else
            cache.Box.Visible = false
            cache.BoxOutline.Visible = false
            cache.Tracer.Visible = false
            cache.Name.Visible = false
            cache.HealthBar.Visible = false
            cache.HealthOutline.Visible = false
        end
    end
end

-- Initialize ESP listeners
local function SetupESPListeners()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            CreateESP(player)
        end
    end

    Players.PlayerAdded:Connect(function(player)
        if player ~= LocalPlayer then
            CreateESP(player)
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        RemoveESP(player)
    end)
end

-------------------------------------------------------------------------------------
-- LOOP BINDINGS & INPUT LISTENERS
-------------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Check mouse/key triggers
    if EnigmaConfig.Aimbot.Key.Name == "MouseButton2" and input.UserInputType == Enum.UserInputType.MouseButton2 then
        AimbotHolding = true
    elseif input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == EnigmaConfig.Aimbot.Key then
        AimbotHolding = true
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if EnigmaConfig.Aimbot.Key.Name == "MouseButton2" and input.UserInputType == Enum.UserInputType.MouseButton2 then
        AimbotHolding = false
    elseif input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == EnigmaConfig.Aimbot.Key then
        AimbotHolding = false
    end
end)

-- Main rendering loops
RunService.RenderStepped:Connect(function()
    UpdateFOVCircles()
    UpdateTargetVisuals()
    ProcessCameraAimbot()
    ApplyTargetFreeze()
end)

RunService.Heartbeat:Connect(function()
    UpdateESP()
end)

-------------------------------------------------------------------------------------
-- RAYFIELD INTERFACE SUITE DESIGN
-------------------------------------------------------------------------------------
local function InitializeGUI()
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    if not Rayfield then
        warn("[Enigma Hub] Failed to download Rayfield Library from URL source.")
        return
    end

    local Window = Rayfield:CreateWindow({
        Name = "Enigma Hub | Premium Combat Suite",
        LoadingTitle = "ENIGMA HUB",
        LoadingSubtitle = "Initializing Systems...",
        Theme = "DarkTheme", -- Rayfield default theme
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "EnigmaHubConfigs",
            FileName = "DefaultConfig"
        },
        KeySystem = false -- Disable verification logic
    })

    -- COMBAT TAB
    local CombatTab = Window:CreateTab("Combat & Aim", 4483362458)

    CombatTab:CreateSection("Aimbot Engine")

    CombatTab:CreateToggle({
        Name = "Enable Aimbot",
        CurrentValue = EnigmaConfig.Aimbot.Enabled,
        Flag = "AimbotEnabled",
        Callback = function(value)
            EnigmaConfig.Aimbot.Enabled = value
        end
    })

    CombatTab:CreateDropdown({
        Name = "Target Bone",
        Options = {"Head", "Torso", "HumanoidRootPart"},
        CurrentOption = {EnigmaConfig.Aimbot.Part},
        MultipleOptions = false,
        Flag = "AimbotPart",
        Callback = function(option)
            EnigmaConfig.Aimbot.Part = option[1]
        end
    })

    CombatTab:CreateSlider({
        Name = "Aim Smoothing",
        Range = {1, 100},
        Increment = 1,
        Suffix = "%",
        CurrentValue = math.round(EnigmaConfig.Aimbot.Smoothness * 100),
        Flag = "AimbotSmoothness",
        Callback = function(value)
            EnigmaConfig.Aimbot.Smoothness = value / 100
        end
    })

    CombatTab:CreateKeybind({
        Name = "Aimbot Keybind",
        CurrentKeybind = "MouseButton2",
        HoldToInteract = true,
        Flag = "AimbotKeybind",
        Callback = function(keybind)
            -- Map keybind callback
            local matchedKey = nil
            -- Test for standard keys
            for _, val in ipairs(Enum.KeyCode:GetEnumItems()) do
                if val.Name == keybind then matchedKey = val break end
            end
            -- Test for mouse clicks
            if not matchedKey then
                for _, val in ipairs(Enum.UserInputType:GetEnumItems()) do
                    if val.Name == keybind then matchedKey = val break end
                end
            end
            if matchedKey then
                EnigmaConfig.Aimbot.Key = matchedKey
            end
        end
    })

    CombatTab:CreateSection("Target Filtering")

    CombatTab:CreateToggle({
        Name = "Ignore Friendly Team",
        CurrentValue = EnigmaConfig.Aimbot.TeamCheck,
        Flag = "AimbotTeamCheck",
        Callback = function(value)
            EnigmaConfig.Aimbot.TeamCheck = value
        end
    })

    CombatTab:CreateToggle({
        Name = "Visibility / Wall Check",
        CurrentValue = EnigmaConfig.Aimbot.WallCheck,
        Flag = "AimbotWallCheck",
        Callback = function(value)
            EnigmaConfig.Aimbot.WallCheck = value
        end
    })

    CombatTab:CreateSection("Aimbot Field of View")

    CombatTab:CreateToggle({
        Name = "Render FOV Circle",
        CurrentValue = EnigmaConfig.Aimbot.FOV.Enabled,
        Flag = "AimbotFOVEnabled",
        Callback = function(value)
            EnigmaConfig.Aimbot.FOV.Enabled = value
        end
    })

    CombatTab:CreateSlider({
        Name = "FOV Circle Radius",
        Range = {10, 800},
        Increment = 5,
        Suffix = "px",
        CurrentValue = EnigmaConfig.Aimbot.FOV.Radius,
        Flag = "AimbotFOVRadius",
        Callback = function(value)
            EnigmaConfig.Aimbot.FOV.Radius = value
        end
    })

    CombatTab:CreateColorpicker({
        Name = "FOV Circle Color",
        Color = EnigmaConfig.Aimbot.FOV.Color,
        Flag = "AimbotFOVColor",
        Callback = function(color)
            EnigmaConfig.Aimbot.FOV.Color = color
        end
    })

    CombatTab:CreateSection("Target Prediction")

    CombatTab:CreateToggle({
        Name = "Velocity Prediction",
        CurrentValue = EnigmaConfig.Aimbot.Prediction.Enabled,
        Flag = "AimbotPredictEnabled",
        Callback = function(value)
            EnigmaConfig.Aimbot.Prediction.Enabled = value
        end
    })

    CombatTab:CreateSlider({
        Name = "Prediction Multiplier",
        Range = {1, 500},
        Increment = 1,
        Suffix = "/1000",
        CurrentValue = math.round(EnigmaConfig.Aimbot.Prediction.VelocityMultiplier * 1000),
        Flag = "AimbotPredictMultiplier",
        Callback = function(value)
            EnigmaConfig.Aimbot.Prediction.VelocityMultiplier = value / 1000
        end
    })

    CombatTab:CreateSection("Target Retention & Visuals")

    CombatTab:CreateToggle({
        Name = "Target Lock (Freeze Selection)",
        CurrentValue = EnigmaConfig.Aimbot.TargetLock,
        Flag = "AimbotTargetLock",
        Callback = function(value)
            EnigmaConfig.Aimbot.TargetLock = value
        end
    })

    CombatTab:CreateToggle({
        Name = "Freeze Target Locally",
        CurrentValue = EnigmaConfig.Aimbot.FreezeTarget,
        Flag = "AimbotFreezeTarget",
        Callback = function(value)
            EnigmaConfig.Aimbot.FreezeTarget = value
        end
    })

    CombatTab:CreateToggle({
        Name = "Targeting Visual Tracker",
        CurrentValue = EnigmaConfig.Aimbot.TargetVisuals,
        Flag = "AimbotTargetVisuals",
        Callback = function(value)
            EnigmaConfig.Aimbot.TargetVisuals = value
        end
    })

    CombatTab:CreateColorpicker({
        Name = "Visual Tracker Color",
        Color = EnigmaConfig.Aimbot.TargetVisualsColor,
        Flag = "AimbotTargetVisualsColor",
        Callback = function(color)
            EnigmaConfig.Aimbot.TargetVisualsColor = color
        end
    })

    -- SILENT AIM TAB
    local SilentTab = Window:CreateTab("Silent Aim", 4483362458)

    SilentTab:CreateSection("Silent Targeting Hook")

    SilentTab:CreateToggle({
        Name = "Enable Silent Aim",
        CurrentValue = EnigmaConfig.SilentAim.Enabled,
        Flag = "SilentAimEnabled",
        Callback = function(value)
            EnigmaConfig.SilentAim.Enabled = value
        end
    })

    SilentTab:CreateSlider({
        Name = "Hit Accuracy Chance",
        Range = {1, 100},
        Increment = 1,
        Suffix = "%",
        CurrentValue = EnigmaConfig.SilentAim.HitChance,
        Flag = "SilentAimHitChance",
        Callback = function(value)
            EnigmaConfig.SilentAim.HitChance = value
        end
    })

    SilentTab:CreateDropdown({
        Name = "Silent Target Bone",
        Options = {"Head", "Torso", "HumanoidRootPart"},
        CurrentOption = {EnigmaConfig.SilentAim.Part},
        MultipleOptions = false,
        Flag = "SilentAimPart",
        Callback = function(option)
            EnigmaConfig.SilentAim.Part = option[1]
        end
    })

    SilentTab:CreateSection("Silent Aim FOV")

    SilentTab:CreateToggle({
        Name = "Show Silent FOV Circle",
        CurrentValue = EnigmaConfig.SilentAim.FOV.Enabled,
        Flag = "SilentAimFOVEnabled",
        Callback = function(value)
            EnigmaConfig.SilentAim.FOV.Enabled = value
        end
    })

    SilentTab:CreateSlider({
        Name = "Silent FOV Radius",
        Range = {10, 800},
        Increment = 5,
        Suffix = "px",
        CurrentValue = EnigmaConfig.SilentAim.FOV.Radius,
        Flag = "SilentAimFOVRadius",
        Callback = function(value)
            EnigmaConfig.SilentAim.FOV.Radius = value
        end
    })

    SilentTab:CreateColorpicker({
        Name = "Silent FOV Color",
        Color = EnigmaConfig.SilentAim.FOV.Color,
        Flag = "SilentAimFOVColor",
        Callback = function(color)
            EnigmaConfig.SilentAim.FOV.Color = color
        end
    })

    -- VISUALS TAB
    local VisualsTab = Window:CreateTab("Visuals & ESP", 4483362458)

    VisualsTab:CreateSection("ESP Options")

    VisualsTab:CreateToggle({
        Name = "Enable Master ESP",
        CurrentValue = EnigmaConfig.ESP.Enabled,
        Flag = "ESPEnabled",
        Callback = function(value)
            EnigmaConfig.ESP.Enabled = value
        end
    })

    VisualsTab:CreateToggle({
        Name = "Boxes Overlay",
        CurrentValue = EnigmaConfig.ESP.Boxes,
        Flag = "ESPBoxes",
        Callback = function(value)
            EnigmaConfig.ESP.Boxes = value
        end
    })

    VisualsTab:CreateColorpicker({
        Name = "Boxes Color",
        Color = EnigmaConfig.ESP.BoxColor,
        Flag = "ESPBoxColor",
        Callback = function(color)
            EnigmaConfig.ESP.BoxColor = color
        end
    })

    VisualsTab:CreateToggle({
        Name = "Draw Tracers",
        CurrentValue = EnigmaConfig.ESP.Tracers,
        Flag = "ESPTracers",
        Callback = function(value)
            EnigmaConfig.ESP.Tracers = value
        end
    })

    VisualsTab:CreateDropdown({
        Name = "Tracers Origin",
        Options = {"Bottom", "Middle", "Mouse"},
        CurrentOption = {EnigmaConfig.ESP.TracerOrigin},
        MultipleOptions = false,
        Flag = "ESPTracerOrigin",
        Callback = function(option)
            EnigmaConfig.ESP.TracerOrigin = option[1]
        end
    })

    VisualsTab:CreateColorpicker({
        Name = "Tracers Color",
        Color = EnigmaConfig.ESP.TracerColor,
        Flag = "ESPTracerColor",
        Callback = function(color)
            EnigmaConfig.ESP.TracerColor = color
        end
    })

    VisualsTab:CreateToggle({
        Name = "Name & Distance Plates",
        CurrentValue = EnigmaConfig.ESP.Names,
        Flag = "ESPNames",
        Callback = function(value)
            EnigmaConfig.ESP.Names = value
        end
    })

    VisualsTab:CreateColorpicker({
        Name = "Names Color",
        Color = EnigmaConfig.ESP.NameColor,
        Flag = "ESPNameColor",
        Callback = function(color)
            EnigmaConfig.ESP.NameColor = color
        end
    })

    VisualsTab:CreateToggle({
        Name = "Health Bar Status",
        CurrentValue = EnigmaConfig.ESP.Health,
        Flag = "ESPHealth",
        Callback = function(value)
            EnigmaConfig.ESP.Health = value
        end
    })

    VisualsTab:CreateSection("Chams / Outline Glow")

    VisualsTab:CreateToggle({
        Name = "Enable Glow Chams",
        CurrentValue = EnigmaConfig.ESP.Chams,
        Flag = "ESPChams",
        Callback = function(value)
            EnigmaConfig.ESP.Chams = value
        end
    })

    VisualsTab:CreateColorpicker({
        Name = "Chams Fill Color",
        Color = EnigmaConfig.ESP.ChamsFillColor,
        Flag = "ESPChamsFillColor",
        Callback = function(color)
            EnigmaConfig.ESP.ChamsFillColor = color
        end
    })

    VisualsTab:CreateColorpicker({
        Name = "Chams Outline Color",
        Color = EnigmaConfig.ESP.ChamsOutlineColor,
        Flag = "ESPChamsOutlineColor",
        Callback = function(color)
            EnigmaConfig.ESP.ChamsOutlineColor = color
        end
    })

    VisualsTab:CreateSlider({
        Name = "Chams Transparency",
        Range = {0, 100},
        Increment = 5,
        Suffix = "%",
        CurrentValue = math.round(EnigmaConfig.ESP.ChamsFillTransparency * 100),
        Flag = "ESPChamsFillTransparency",
        Callback = function(value)
            EnigmaConfig.ESP.ChamsFillTransparency = value / 100
        end
    })

    -- SYSTEM/INFO TAB
    local InfoTab = Window:CreateTab("Enigma Config", 4483362458)
    
    InfoTab:CreateSection("Engine Status")
    
    InfoTab:CreateParagraph({
        Title = "Enigma Combat System Loaded Successfully!",
        Content = "Current execution environment verified. Memory spaces hookable. Rayfield layout constructed. Adjust the properties in Aimbot, Silent Aim, and ESP tabs to alter parameters."
    })

    InfoTab:CreateButton({
        Name = "Unload / Destruct Enigma Hub",
        Callback = function()
            -- Unbind and clean drawings
            pcall(function()
                AimbotFOVCircle:Remove()
                SilentAimFOVCircle:Remove()
                TargetVisualLine:Remove()
                TargetVisualCircle:Remove()
                for _, player in ipairs(Players:GetPlayers()) do
                    RemoveESP(player)
                end
                Rayfield:Destroy()
                getgenv().EnigmaHubLoaded = nil
                print("[Enigma Hub] Destructed and unloaded successfully.")
            end)
        end
    })
    
    Rayfield:LoadConfiguration()
end

-------------------------------------------------------------------------------------
-- BOOTSTRAPPING
-------------------------------------------------------------------------------------
task.spawn(function()
    SetupESPListeners()
    InitiateSilentAimHook()
    InitializeGUI()
end)
