-- Services & cached refs
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera -- Camera reference for ESP
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ESP_UI_Container"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- General state
local lastPlace = nil
local conns = {} -- store active connections
local windows = {} -- refs for created UI elements (Window/Tabs)
local flags = {} -- feature flags
local originalLighting = {}
local customSpeed = 16
local originalGravity = Workspace.Gravity or 196.2 -- Simpan gravitasi asli

-- Helpers for connections
local function safeDisconnect(conn)
    if conn then
        pcall(function() conn:Disconnect() end)
    end
end

local function setConn(name, conn)
    if conns[name] then
        safeDisconnect(conns[name])
    end
    conns[name] = conn
end

local function clearConn(name)
    if conns[name] then
        safeDisconnect(conns[name])
        conns[name] = nil
    end
end

local function clearAllConns()
    for k, v in pairs(conns) do
        safeDisconnect(v)
        conns[k] = nil
    end
end

-- Character/Humanoid helpers
local function getCharacter()
    return LocalPlayer and (LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
end

local function getHumanoid(timeout)
    local char = getCharacter()
    if not char then return nil end
    if timeout then
        return char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", timeout)
    else
        return char:FindFirstChildOfClass("Humanoid")
    end
end

local function getHRP()
    local char = getCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5))
end

-- Notification wrapper (Rayfield will be set later)
local Rayfield = nil
local function notify(msg)
    if Rayfield and Rayfield.Notify then
        pcall(function()
            Rayfield:Notify({ Title = "Info", Content = tostring(msg), Duration = 2, Image = 4483362458 })
        end)
    else
        warn("[BangBoyeszz Tools] " .. tostring(msg))
    end
end

-- Utility
local function sortedPlayerNames()
    local t = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            t[#t+1] = plr.Name
        end
    end
    table.sort(t)
    return t
end

-- Ghost Mode Implementation (Tidak diubah)
local originalPartsData = {} 

local function setGhostMode(enabled)
    flags.ghostMode = enabled
    local char = getCharacter()
    if not char then 
        notify("Karakter tidak ditemukan.")
        return 
    end

    if enabled then
        originalPartsData = {}
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                originalPartsData[part] = { 
                    Transparency = part.Transparency, 
                    CanCollide = part.CanCollide,
                    Massless = part.Massless
                }
                part.Transparency = 1
                part.CanCollide = false
                part.Massless = true
            end
        end
        
        char.Archivable = false 
        Workspace.Gravity = 0

        setConn("ghostCharAdded", LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.1) 
            if flags.ghostMode then
                setGhostMode(true)
            end
        end))

    else
        for part, data in pairs(originalPartsData) do
            if part.Parent == char then
                pcall(function()
                    part.Transparency = data.Transparency
                    part.CanCollide = data.CanCollide
                    part.Massless = data.Massless
                end)
            end
        end
        originalPartsData = {}
        
        char.Archivable = true
        Workspace.Gravity = originalGravity
        clearConn("ghostCharAdded")
    end
    
    notify("Ghost Mode: " .. (enabled and "ON" or "OFF"))
end

-- ===============================================
--          UPDATED ESP IMPLEMENTATION
-- ===============================================

local espTable = {} -- { TargetPlayer = { Gui, Line, Box }, ... }
flags.showESPLine = true
flags.showESPBox = true
flags.showESPHealth = true
flags.showESPNameDist = true

-- Helper: Mendapatkan titik 2D di layar
local function worldToScreenPoint(pos)
    local screenPos, inViewport = Camera:WorldToScreenPoint(pos)
    return Vector2.new(screenPos.X, screenPos.Y), inViewport
end

-- Helper: Membuat/Mengupdate Line (Tracer)
local function createOrUpdateLine(player, startPos, endPos)
    local line = espTable[player].Line
    if not line then
        line = Instance.new("Frame")
        line.Name = "ESP_Line"
        line.BackgroundColor3 = Color3.new(1, 0, 0) -- Merah
        line.BorderSizePixel = 0
        line.AnchorPoint = Vector2.new(0.5, 0)
        line.ZIndex = 2
        line.Parent = ScreenGui
        espTable[player].Line = line
    end

    local startX, startY = startPos.X, startPos.Y
    local endX, endY = endPos.X, endPos.Y
    
    local distance = (endPos - startPos).Magnitude
    local angle = math.atan2(endY - startY, endX - startX)
    local rotation = math.deg(angle) + 90
    
    line.Size = UDim2.new(0, 1, 0, distance)
    line.Position = UDim2.new(0, startX, 0, startY)
    line.Rotation = rotation

    line.Visible = flags.playerESP and flags.showESPLine
end

-- Helper: Membuat/Mengupdate Kotak 3D (ESP Box)
local function createOrUpdateBox(player, hrp)
    local box = espTable[player].Box
    if not box then
        box = Instance.new("Frame")
        box.Name = "ESP_Box"
        box.BackgroundColor3 = Color3.new(1, 0, 0)
        box.BackgroundTransparency = 1
        box.BorderSizePixel = 1
        box.BorderColor3 = Color3.new(1, 0, 0)
        box.AnchorPoint = Vector2.new(0.5, 0.5)
        box.ZIndex = 2
        box.Parent = ScreenGui
        espTable[player].Box = box
    end

    local character = player.Character
    local head = character:FindFirstChild("Head")
    
    -- Estimasi ukuran Box berdasarkan Head dan HRP
    local headPos, headIn = worldToScreenPoint(head.Position)
    local hrpPos, hrpIn = worldToScreenPoint(hrp.Position)
    
    if headIn and hrpIn then
        local bottom = hrpPos.Y
        local top = headPos.Y
        local height = math.abs(bottom - top) * 1.5 -- Skala tinggi box sedikit
        local width = height * 0.5 -- Lebar box proporsional

        box.Size = UDim2.new(0, width, 0, height)
        box.Position = UDim2.new(0, headPos.X, 0, (top + bottom) / 2)
        box.BorderColor3 = player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
        box.Visible = flags.playerESP and flags.showESPBox
    else
        box.Visible = false
    end
end

-- Helper: Membuat/Mengupdate Informasi Teks (Nama, Jarak, Nyawa, Head)
local function createOrUpdateText(player, hrp, hum)
    local billboard = espTable[player].Billboard
    if not billboard then
        -- Membuat BillboardGui
        billboard = Instance.new("BillboardGui")
        billboard.Name = "PlayerESP_BB"
        billboard.Adornee = hrp 
        billboard.Size = UDim2.new(0, 150, 0, 70) -- Ukuran diperbesar untuk menampung info tambahan
        billboard.AlwaysOnTop = true
        billboard.ExtentsOffset = Vector3.new(0, 5, 0)
        
        local infoContainer = Instance.new("Frame")
        infoContainer.Name = "InfoContainer"
        infoContainer.Size = UDim2.new(1, 0, 1, 0)
        infoContainer.BackgroundTransparency = 1
        infoContainer.Parent = billboard

        -- Text Label (Nama/Jarak)
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameDist"
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.Position = UDim2.new(0, 0, 0, 0)
        nameLabel.TextColor3 = Color3.new(1, 1, 1)
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextStrokeTransparency = 0
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.SourceSansBold
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.Parent = infoContainer
        
        -- Health Bar (Bar Nyawa)
        local healthBar = Instance.new("Frame")
        healthBar.Name = "HealthBar"
        healthBar.Size = UDim2.new(1, 0, 0.2, 0)
        healthBar.Position = UDim2.new(0, 0, 0.5, 0)
        healthBar.BackgroundColor3 = Color3.new(0, 0, 0)
        healthBar.BorderColor3 = Color3.new(1, 1, 1)
        healthBar.BorderSizePixel = 1
        healthBar.Parent = infoContainer

        local healthFill = Instance.new("Frame")
        healthFill.Name = "HealthFill"
        healthFill.Size = UDim2.new(1, 0, 1, 0)
        healthFill.BackgroundColor3 = Color3.new(0, 1, 0)
        healthFill.BorderSizePixel = 0
        healthFill.Parent = healthBar

        -- Health Text
        local healthText = Instance.new("TextLabel")
        healthText.Name = "HealthText"
        healthText.Size = UDim2.new(1, 0, 1, 0)
        healthText.BackgroundTransparency = 1
        healthText.TextColor3 = Color3.new(1, 1, 1)
        healthText.TextStrokeTransparency = 0
        healthText.Font = Enum.Font.SourceSans
        healthText.TextSize = 10
        healthText.Parent = healthBar

        -- Head Marker
        local headMarker = Instance.new("Part")
        headMarker.Name = "ESP_Head"
        headMarker.Shape = Enum.PartType.Ball
        headMarker.Size = Vector3.new(0.5, 0.5, 0.5)
        headMarker.Material = Enum.Material.ForceField
        headMarker.Color = Color3.new(1, 1, 0) -- Kuning
        headMarker.CanCollide = false
        headMarker.Anchored = true
        headMarker.Transparency = 0.5
        headMarker.Parent = Workspace
        espTable[player].HeadMarker = headMarker

        billboard.Parent = LocalPlayer.PlayerGui
        espTable[player].Billboard = billboard
    end
    
    -- Update Head Marker Position and Visibility
    local head = player.Character:FindFirstChild("Head")
    if head and espTable[player].HeadMarker then
        espTable[player].HeadMarker.CFrame = head.CFrame
        espTable[player].HeadMarker.Visible = flags.playerESP and flags.showESPBox
    end

    -- Update Text and Health
    local dist = (getHRP().Position - hrp.Position).Magnitude
    
    local nameDist = billboard:FindFirstChild("InfoContainer"):FindFirstChild("NameDist")
    local healthFill = billboard:FindFirstChild("InfoContainer"):FindFirstChild("HealthBar"):FindFirstChild("HealthFill")
    local healthText = billboard:FindFirstChild("InfoContainer"):FindFirstChild("HealthBar"):FindFirstChild("HealthText")
    
    if nameDist then
        nameDist.Text = string.format("%s\n(%.1fm)", player.Name, dist)
        nameDist.Visible = flags.playerESP and flags.showESPNameDist
        if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
            nameDist.TextColor3 = Color3.new(0, 1, 0)
        else
            nameDist.TextColor3 = Color3.new(1, 1, 1)
        end
    end
    
    if healthFill and hum and hum.MaxHealth > 0 then
        local healthRatio = hum.Health / hum.MaxHealth
        healthFill.Size = UDim2.new(healthRatio, 0, 1, 0)
        healthFill.BackgroundColor3 = Color3.new(1 - healthRatio, healthRatio, 0) -- Hijau ke Merah
        
        healthFill.Parent.Visible = flags.playerESP and flags.showESPHealth
    end
    
    if healthText and hum then
        healthText.Text = string.format("%d HP", math.floor(hum.Health))
        healthText.Visible = flags.playerESP and flags.showESPHealth
    end
    
    billboard.Visible = flags.playerESP
end

-- Main ESP Loop
local function updateESP()
    local myHRP = getHRP()
    if not myHRP then return end
    
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if char and hrp and hum and flags.playerESP then
                if not espTable[player] then
                    espTable[player] = {}
                end
                
                -- Update Adornee for Billboard on HRP change (respawn)
                if espTable[player].Billboard and espTable[player].Billboard.Adornee ~= hrp then
                    espTable[player].Billboard.Adornee = hrp
                end
                
                -- 1. Billboard/Text/Health/Head Marker
                createOrUpdateText(player, hrp, hum)
                
                -- 2. Line (Tracer)
                local hrpPos, hrpIn = worldToScreenPoint(hrp.Position)
                createOrUpdateLine(player, screenCenter, hrpPos)

                -- 3. Box (2D)
                createOrUpdateBox(player, hrp)
                
            else
                -- Player is dead or ESP is off, clean up
                for _, data in pairs(espTable[player] or {}) do
                    if data.Parent == ScreenGui or data.Parent == LocalPlayer.PlayerGui or data.Parent == Workspace then
                        data:Destroy()
                    end
                end
                espTable[player] = nil
            end
        end
    end
end

-- ===============================================
--          UI & Feature init
-- ===============================================

local function CreateUI()
    -- Load Rayfield
    Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/cokycokynanas/ScBoyeszz/refs/heads/main/rf.lua"))()

    -- Create Window
    local Window = Rayfield:CreateWindow({
        Name = "BangBoyeszz Tools",
        LoadingTitle = "BangBoyeszz Tools",
        LoadingSubtitle = "Just a Simple Script By Boyeszz♡",
        ConfigurationSaving = { Enabled = false },
        KeySystem = false,
    })
    windows.Window = Window
    
    -- Insert ScreenGui once
    ScreenGui.Parent = LocalPlayer.PlayerGui

    -- MAIN TAB
    local Main = Window:CreateTab("Main", 4483362458)
    windows.Main = Main

    -- God Mode
    Main:CreateToggle({
        Name = "God Mode",
        CurrentValue = false,
        Callback = function(enabled)
            flags.godMode = enabled
            clearConn("godMode")
            if enabled then
                setConn("godMode", RunService.Heartbeat:Connect(function()
                    local hum = getHumanoid()
                    if hum and hum.Health < hum.MaxHealth then
                        hum.Health = hum.MaxHealth
                    end
                end))
            end
            notify("God Mode: " .. (enabled and "ON" or "OFF"))
        end
    })
    
    -- GHOST MODE
    Main:CreateToggle({
        Name = "Ghost Mode",
        CurrentValue = false,
        Callback = setGhostMode
    })

    -- Noclip
    Main:CreateToggle({
        Name = "Noclip",
        CurrentValue = false,
        Callback = function(enabled)
            flags.noclip = enabled
            clearConn("noclip")
            if enabled then
                setConn("noclip", RunService.Stepped:Connect(function()
                    local char = getCharacter()
                    if not char then return end
                    for _, part in ipairs(char:GetChildren()) do
                        if part:IsA("BasePart") and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end))
            else
                local char = getCharacter()
                if char then
                    for _, part in ipairs(char:GetChildren()) do
                        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                            part.CanCollide = true
                        end
                    end
                end
            end
            notify("Noclip: " .. (enabled and "ON" or "OFF"))
        end
    })

    -- Speed Hack
    Main:CreateToggle({
        Name = "Speed Hack",
        CurrentValue = false,
        Callback = function(enabled)
            flags.speedHack = enabled
            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = enabled and customSpeed or 16
            end
            notify("Speed Hack: " .. (enabled and "ON" or "OFF"))
        end
    })

    Main:CreateSlider({
        Name = "Speed Value",
        Range = {16, 200},
        Increment = 1,
        Suffix = "Speed",
        CurrentValue = 16,
        Callback = function(value)
            customSpeed = value
            if flags.speedHack then
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = customSpeed end
            end
        end
    })

-- CFly (Head Anchor Method, Speed 50)
flags.cframeFly = false
local CFloop

Main:CreateToggle({
    Name = "CFly",
    CurrentValue = false,
    Callback = function(enabled)
        flags.cframeFly = enabled
        if CFloop then CFloop:Disconnect() CFloop = nil end

        local char = getCharacter()
        local hum = getHumanoid()
        local head = char and char:FindFirstChild("Head")

        if enabled then
            if hum then hum.PlatformStand = true end
            if head then head.Anchored = true end

            local CFspeed = 50
            CFloop = RunService.Heartbeat:Connect(function(deltaTime)
                if not char or not hum or not head then return end

                local moveDirection = hum.MoveDirection * (CFspeed * deltaTime)
                local headCFrame = head.CFrame
                local cameraCFrame = Workspace.CurrentCamera.CFrame

                local cameraOffset = headCFrame:ToObjectSpace(cameraCFrame).Position
                cameraCFrame = cameraCFrame * CFrame.new(-cameraOffset.X, -cameraOffset.Y, -cameraOffset.Z + 1)

                local cameraPosition = cameraCFrame.Position
                local headPosition = headCFrame.Position

                local objectSpaceVelocity = CFrame.new(
                    cameraPosition,
                    Vector3.new(headPosition.X, cameraPosition.Y, headPosition.Z)
                ):VectorToObjectSpace(moveDirection)

                head.CFrame = CFrame.new(headPosition) * (cameraCFrame - cameraPosition) * CFrame.new(objectSpaceVelocity)
            end)
            notify("CFly: ON")
        else
            if hum then hum.PlatformStand = false end
            if head then head.Anchored = false end
            notify("CFly: OFF")
        end
    end
})

    -- Infinite Jump
    Main:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = false,
        Callback = function(enabled)
            flags.infiniteJump = enabled
            clearConn("infiniteJump")
            if enabled then
                setConn("infiniteJump", UserInputService.JumpRequest:Connect(function()
                    local hum = getHumanoid()
                    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
                end))
            end
            notify("Infinite Jump: " .. (enabled and "ON" or "OFF"))
        end
    })

    -- Fullbright
    Main:CreateToggle({
        Name = "Fullbright",
        CurrentValue = false,
        Callback = function(enabled)
            flags.fullbright = enabled
            if enabled then
                originalLighting = {
                    Brightness = Lighting.Brightness,
                    Ambient = Lighting.Ambient,
                    ColorShift_Bottom = Lighting.ColorShift_Bottom,
                    ColorShift_Top = Lighting.ColorShift_Top,
                    FogEnd = Lighting.FogEnd,
                    FogStart = Lighting.FogStart
                }
                Lighting.Brightness = 5
                Lighting.Ambient = Color3.new(1,1,1)
                Lighting.ColorShift_Bottom = Color3.new(1,1,1)
                Lighting.ColorShift_Top = Color3.new(1,1,1)
                Lighting.FogEnd = 1e5
                Lighting.FogStart = 0
            else
                for k,v in pairs(originalLighting) do
                    Lighting[k] = v
                end
            end
            notify("Fullbright: " .. (enabled and "ON" or "OFF"))
        end
    })

    -- Click Teleport
    Main:CreateToggle({
        Name = "Click Teleport",
        CurrentValue = false,
        Callback = function(enabled)
            flags.clickTeleport = enabled
            clearConn("clickTeleport")
            if enabled then
                local mouse = LocalPlayer:GetMouse()
                setConn("clickTeleport", mouse.Button1Down:Connect(function()
                    local hrp = getHRP()
                    if hrp and mouse.Hit then
                        hrp.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0,5,0))
                    end
                end))
            end
            notify("Click Teleport: " .. (enabled and "ON" or "OFF"))
        end
    })

    -- TELEPORT TAB
    local TeleportTab = Window:CreateTab("Teleport", 4483362458)
    windows.Teleport = TeleportTab

    TeleportTab:CreateSection("Pilih pemain untuk teleport")
    local selectedPlayerName = nil
    local function playerOptions()
        local t = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                t[#t+1] = plr.Name
            end
        end
        table.sort(t)
        return t
    end

    local PlayerDropdown = TeleportTab:CreateDropdown({
        Name = "Pilih Pemain",
        Options = playerOptions(),
        CurrentOption = {},
        MultipleOptions = false,
        Flag = "TeleportPlayerDropdown",
        Callback = function(option)
            selectedPlayerName = (typeof(option) == "table" and option[1]) or option
        end,
    })

    setConn("playerAdd", Players.PlayerAdded:Connect(function()
        pcall(function() PlayerDropdown:Refresh(playerOptions(), true) end)
    end))
    setConn("playerRem", Players.PlayerRemoving:Connect(function()
        pcall(function() PlayerDropdown:Refresh(playerOptions(), true) end)
    end))

    TeleportTab:CreateButton({
        Name = "Teleport ke Pemain",
        Callback = function()
            if not selectedPlayerName or selectedPlayerName == "" then
                notify("Pilih pemain terlebih dahulu.")
                return
            end
            local target = Players:FindFirstChild(selectedPlayerName)
            if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = getHRP()
                if hrp then
                    hrp.CFrame = CFrame.new(target.Character.HumanoidRootPart.Position + Vector3.new(0,3,0))
                    notify("Kamu ditransfer ke "..selectedPlayerName)
                end
            else
                notify("Pemain tidak valid atau belum spawn.")
            end
        end
    })

    TeleportTab:CreateButton({
        Name = "Refresh List",
        Callback = function()
            PlayerDropdown:Refresh(playerOptions(), true)
            notify("Daftar pemain diperbarui.")
        end
    })

    -- Save & Teleport Pos
    TeleportTab:CreateSection("Save & Teleport Pos")
    local savedSlots = { nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil}
    local slotSelected = 1

    local SlotDropdown = TeleportTab:CreateDropdown({
        Name = "Pilih Slot",
        Options = {"1","2","3","4","5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30"},
        CurrentOption = {"1"},
        MultipleOptions = false,
        Flag = "SlotDropdown",
        Callback = function(opt)
            slotSelected = tonumber((typeof(opt) == "table" and opt[1]) or opt) or 1
        end
    })

    TeleportTab:CreateButton({ Name = "Save Pos", Callback = function()
        local hrp = getHRP()
        if hrp then
            savedSlots[slotSelected] = hrp.Position
            notify(("Posisi tersimpan di Slot %d."):format(slotSelected))
        else
            notify("Karakter tidak ditemukan.")
        end
    end })

    TeleportTab:CreateButton({ Name = "Teleport Pos", Callback = function()
        if savedSlots[slotSelected] then
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.new(savedSlots[slotSelected] + Vector3.new(0,5,0))
                notify(("Teleport ke Slot %d."):format(slotSelected))
            end
        else
            notify(("Slot %d kosong."):format(slotSelected))
        end
    end })

    TeleportTab:CreateButton({ Name = "Clear Slot", Callback = function()
        savedSlots[slotSelected] = nil
        notify(("Slot %d dibersihkan."):format(slotSelected))
    end })

    TeleportTab:CreateButton({ Name = "Clear All Slots", Callback = function()
        for i=1,5 do savedSlots[i] = nil end
        notify("Semua slot dibersihkan.")
    end })

    -- Hapus Tab "GB Gunung" di sini. Tidak perlu kode tambahan karena tidak dibuat.
    
    -- MISC TAB
    local MiscTab = Window:CreateTab("Misc", 4483362458)
    windows.Misc = MiscTab
    
    MiscTab:CreateSection("Spectate Player")
    local spectateTargetName = nil
    local viewDiedConn = nil
    local viewChangedConn = nil

    local SpectateDropdown = MiscTab:CreateDropdown({
        Name = "Pilih Pemain",
        Options = sortedPlayerNames(),
        CurrentOption = {},
        MultipleOptions = false,
        Flag = "SpectateDropdown",
        Callback = function(opt)
            spectateTargetName = (typeof(opt) == "table" and opt[1]) or opt
        end
    })

    setConn("specAdd", Players.PlayerAdded:Connect(function()
        pcall(function() SpectateDropdown:Refresh(sortedPlayerNames(), true) end)
    end))
    setConn("specRem", Players.PlayerRemoving:Connect(function()
        pcall(function() SpectateDropdown:Refresh(sortedPlayerNames(), true) end)
    end))

    MiscTab:CreateButton({
        Name = "Mulai Spectate",
        Callback = function()
            if not spectateTargetName or spectateTargetName == "" then
                notify("Pilih pemain terlebih dahulu.")
                return
            end
            local target = Players:FindFirstChild(spectateTargetName)
            if not target or not target.Character then
                notify("Pemain tidak valid atau belum spawn.")
                return
            end

            if viewDiedConn then viewDiedConn:Disconnect(); viewDiedConn = nil end
            if viewChangedConn then viewChangedConn:Disconnect(); viewChangedConn = nil end

            Workspace.CurrentCamera.CameraSubject = target.Character
            viewDiedConn = target.CharacterAdded:Connect(function()
                repeat task.wait() until target.Character and target.Character:FindFirstChild("HumanoidRootPart")
                Workspace.CurrentCamera.CameraSubject = target.Character
            end)
            viewChangedConn = Workspace.CurrentCamera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
                if target and target.Character then
                    Workspace.CurrentCamera.CameraSubject = target.Character
                end
            end)
            notify("Spectating: "..spectateTargetName)
        end
    })

    MiscTab:CreateButton({
        Name = "Berhenti Spectate",
        Callback = function()
            if viewDiedConn then viewDiedConn:Disconnect(); viewDiedConn = nil end
            if viewChangedConn then viewChangedConn:Disconnect(); viewChangedConn = nil end
            local char = getCharacter()
            if char then
                local humanoid = getHumanoid()
                if humanoid then
                    Workspace.CurrentCamera.CameraSubject = humanoid
                else
                    Workspace.CurrentCamera.CameraSubject = char
                end
            end
            notify("Spectate dihentikan.")
        end
    })

    -- FISH IT TAB
    local function AddFishItTab()
        if game.PlaceId ~= 121864768012064 then return end
        if windows.FishIt then return end
        notify("Game terdeteksi: Fish It. Tab khusus aktif!")

        local ok, netRoot = pcall(function()
            return ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index")
                :WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
        end)
        if not ok or not netRoot then
            notify("Gagal menemukan modul 'net' di ReplicatedStorage.")
            return
        end

        local FishItTab = Window:CreateTab("Fish It", "fish")
        windows.FishIt = FishItTab

        flags.autofish = false
        flags.perfectCast = true

        local equipRemote = netRoot:FindFirstChild("RE/EquipToolFromHotbar")
        local rodRemote = netRoot:FindFirstChild("RF/ChargeFishingRod")
        local miniGameRemote = netRoot:FindFirstChild("RF/RequestFishingMinigameStarted")
        local finishRemote = netRoot:FindFirstChild("RE/FishingCompleted")

        FishItTab:CreateToggle({
            Name = "Enable Auto Fish",
            CurrentValue = false,
            Callback = function(val)
                flags.autofish = val
                if val then
                    task.spawn(function()
                        while flags.autofish do
                            if equipRemote and rodRemote and miniGameRemote and finishRemote then
                                pcall(function()
                                    equipRemote:FireServer(1)
                                    task.wait(0.12)
                                    local timestamp = flags.perfectCast and 9999999999 or tick()
                                    rodRemote:InvokeServer(timestamp)
                                    task.wait(0.12)
                                    local x, y = -1.238, 0.969
                                    if not flags.perfectCast then
                                        x = math.random(-1000,1000)/1000
                                        y = math.random(0,1000)/1000
                                    end
                                    miniGameRemote:InvokeServer(x, y)
                                    task.wait(1.3)
                                    finishRemote:FireServer()
                                end)
                            else
                                notify("Remote fishing tidak lengkap (path/nama mungkin berubah).")
                                flags.autofish = false
                                break
                            end
                            for i=1,14 do
                                if not flags.autofish then break end
                                task.wait(0.1)
                            end
                        end
                    end)
                    notify("AutoFish: ON")
                else
                    notify("AutoFish: OFF")
                end
            end
        })

        FishItTab:CreateToggle({
            Name = "Use Perfect Cast",
            CurrentValue = true,
            Callback = function(v) flags.perfectCast = v end
        })

        local islandCoords = {
            { name = "Weather Machine", position = Vector3.new(-1471, -3, 1929) },
            { name = "Esoteric Depths", position = Vector3.new(3157, -1303, 1439) },
            { name = "Tropical Grove", position = Vector3.new(-2038, 3, 3650) },
            { name = "Stingray Shores", position = Vector3.new(-32, 4, 2773) },
            { name = "Kohana Volcano", position = Vector3.new(-519, 24, 189) },
            { name = "Coral Reefs", position = Vector3.new(-3095, 1, 2177) },
            { name = "Crater Island", position = Vector3.new(968, 1, 4854) },
            { name = "Kohana", position = Vector3.new(-658, 3, 719) },
            { name = "Winter Fest", position = Vector3.new(1611, 4, 3280) },
            { name = "Isoteric Island", position = Vector3.new(1987, 4, 1400) },
            { name = "Treasure Hall", position = Vector3.new(-3600, -267, -1558) },
            { name = "Lost Shore", position = Vector3.new(-3663, 38, -989) },
        }
        table.sort(islandCoords, function(a,b) return a.name < b.name end)
        local islandNames, nameToPos = {}, {}
        for _, info in ipairs(islandCoords) do
            table.insert(islandNames, info.name)
            nameToPos[info.name] = info.position
        end

        FishItTab:CreateDropdown({
            Name = "Pilih Island",
            Options = islandNames,
            CurrentOption = {},
            MultipleOptions = false,
            Flag = "FishItIslandDropdown",
            Callback = function(option)
                local chosen = (typeof(option) == "table" and option[1]) or option
                if not chosen then
                    notify("Pilih island terlebih dahulu.")
                    return
                end
                local pos = nameToPos[chosen]
                if not pos then
                    notify("Island tidak ditemukan: " .. tostring(chosen))
                    return
                end
                local hrp = getHRP()
                if hrp then
                    hrp.CFrame = CFrame.new(pos + Vector3.new(0,5,0))
                    notify("Teleport ke " .. chosen)
                else
                    notify("HumanoidRootPart tidak ditemukan.")
                end
            end
        })
    end

    -- === KODE PLAYER ESP BARU DIMULAI DI SINI ===
    local function AddESPTab(Window)
        local ESPTab = Window:CreateTab("ESP", 4483362458)
        windows.ESP = ESPTab
        
        -- Master Toggle
        ESPTab:CreateToggle({
            Name = "Player ESP (ON/OFF)",
            CurrentValue = false,
            Callback = function(enabled)
                flags.playerESP = enabled
                
                clearConn("playerESP_Loop")
                if enabled then
                    setConn("playerESP_Rem", Players.PlayerRemoving:Connect(function(player)
                        for _, data in pairs(espTable[player] or {}) do
                            if data.Parent == ScreenGui or data.Parent == LocalPlayer.PlayerGui or data.Parent == Workspace then
                                data:Destroy()
                            end
                        end
                        espTable[player] = nil
                    end))
                    
                    setConn("playerESP_Loop", RunService.RenderStepped:Connect(updateESP))
                else
                    clearConn("playerESP_Rem")
                    for player, data in pairs(espTable) do
                        for _, visual in pairs(data) do
                            if visual.Parent == ScreenGui or visual.Parent == LocalPlayer.PlayerGui or visual.Parent == Workspace then
                                visual:Destroy()
                            end
                        end
                    end
                    espTable = {}
                end
                notify("Player ESP: " .. (enabled and "ON" or "OFF"))
            end
        })

        ESPTab:CreateSection("ESP Visual Settings")

        ESPTab:CreateToggle({
            Name = "ESP Line (Tracer)",
            CurrentValue = true,
            Callback = function(enabled) flags.showESPLine = enabled end
        })

        ESPTab:CreateToggle({
            Name = "ESP Box (Kotak)",
            CurrentValue = true,
            Callback = function(enabled) flags.showESPBox = enabled end
        })
        
        ESPTab:CreateToggle({
            Name = "ESP Head (Wajah)",
            CurrentValue = true,
            Callback = function(enabled) flags.showESPBox = enabled end -- Menggunakan flag showESPBox untuk Head
        })

        ESPTab:CreateSection("ESP Info Settings")
        
        ESPTab:CreateToggle({
            Name = "Tampilkan Nama & Jarak",
            CurrentValue = true,
            Callback = function(enabled) flags.showESPNameDist = enabled end
        })

        ESPTab:CreateToggle({
            Name = "Tampilkan Nyawa (Health)",
            CurrentValue = true,
            Callback = function(enabled) flags.showESPHealth = enabled end
        })

        ESPTab:CreateButton({
            Name = "Refresh ESP",
            Callback = function()
                for player, data in pairs(espTable) do
                    for _, visual in pairs(data) do
                        if visual.Parent == ScreenGui or visual.Parent == LocalPlayer.PlayerGui or visual.Parent == Workspace then
                            visual:Destroy()
                        end
                    end
                end
                espTable = {}
                notify("ESP di-refresh.")
            end
        })
    end
    -- === KODE PLAYER ESP BARU BERAKHIR DI SINI ===


    AddFishItTab()
    
    -- Panggil fitur ESP yang baru
    AddESPTab(Window)
end

-- ===== Monitor PlaceId changes & reload UI =====
task.spawn(function()
    while task.wait(1.5) do
        if game.PlaceId ~= lastPlace then
            lastPlace = game.PlaceId
            clearAllConns()
            windows = {}
            local ok, err = pcall(CreateUI)
            if not ok then warn("CreateUI error:", err) end
        end
    end
end)

-- Initial load
lastPlace = game.PlaceId
CreateUI()
