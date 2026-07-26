if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Services & cached refs
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- General state
local lastPlace = nil
local conns = {} -- store active connections
local windows = {} -- refs for created UI elements (Window/Tabs)
local flags = {} -- feature flags
local originalLighting = {}
local customSpeed = 16
local originalGravity = Workspace.Gravity or 196.2 -- Simpan gravitasi asli

-- Aimbot/Killaura state
local aimbotTarget = nil
local selectedAimbotPlayerName = nil -- NEW: Nama pemain yang dipilih untuk Aimbot
local aimbotRange = 150 -- NEW: Jarak Aimbot
local selectedAimbotPart = "Head" -- MODIFIED: Default target Head
local hitboxMultipler = 1 -- Multiplier untuk hitbox
local originalSizeData = {} -- NEW: Dipindahkan ke global agar fungsi bisa diakses dari mana saja
local killAuraRange = 25 -- Jarak Kill Aura
local killAuraDelay = 0.5 -- Delay antar serangan Kill Aura

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
    return LocalPlayer and LocalPlayer.Character
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
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Rayfield reference (set after UI init)
local Rayfield = nil

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

-- Ghost Mode Implementation
local originalPartsData = {} -- Store original transparency and cancollide data

local function setGhostMode(enabled)
    flags.ghostMode = enabled
    local char = getCharacter()
    if not char then 
        return 
    end

    if enabled then
        -- Simpan data asli dan terapkan mode hantu
        originalPartsData = {}
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                originalPartsData[part] = { 
                    Transparency = part.Transparency, 
                    CanCollide = part.CanCollide,
                    Massless = part.Massless -- Simpan Massless juga
                }
                part.Transparency = 1
                part.CanCollide = false
                part.Massless = true -- Membuat karakter tidak terpengaruh oleh force
            end
        end
        
        -- Coba nonaktifkan replikasi untuk klien lain (tidak dijamin di semua game)
        char.Archivable = false 

        -- Nonaktifkan gravitasi di workspace lokal
        Workspace.Gravity = 0

        -- Hubungkan ke CharacterAdded untuk menerapkan Ghost Mode pada respawn
        setConn("ghostCharAdded", LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.1) -- Tunggu sebentar untuk semua bagian dimuat
            if flags.ghostMode then
                setGhostMode(true) -- Terapkan lagi mode hantu
            end
        end))

    else
        -- Kembalikan ke kondisi asli
        for part, data in pairs(originalPartsData) do
            if part.Parent == char then -- Pastikan bagian masih ada di karakter
                pcall(function() -- Gunakan pcall karena bagian mungkin sudah dihancurkan
                    part.Transparency = data.Transparency
                    part.CanCollide = data.CanCollide
                    part.Massless = data.Massless
                end)
            end
        end
        originalPartsData = {}
        
        char.Archivable = true
        
        -- Kembalikan gravitasi
        Workspace.Gravity = originalGravity
        
        -- Putuskan koneksi CharacterAdded
        clearConn("ghostCharAdded")
    end
end


-- NEW/MODIFIED: Fungsi untuk mengontrol Hitbox
local function setHitbox(enabled)
    flags.hitboxExpander = enabled
    local multiplier = hitboxMultipler
    local char = getCharacter()
    
    -- Hapus semua koneksi/data yang mungkin tersisa
    clearConn("hitboxCharAdded")
    
    if not char then return end

    if enabled and multiplier > 1 then
        -- Terapkan Hitbox
        originalSizeData = {}
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then -- Jaga HRP tetap normal untuk fisik/teleport
                 originalSizeData[part] = part.Size
                 part.Size = part.Size * multiplier
            end
        end
        
        -- Terapkan lagi pada respawn
        setConn("hitboxCharAdded", LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.1) 
            if flags.hitboxExpander then
                local newChar = getCharacter()
                if newChar then
                    for _, part in ipairs(newChar:GetChildren()) do
                        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                            -- Pastikan ukuran part belum diubah sebelumnya
                            if not originalSizeData[part] then
                                -- Ini adalah bagian baru setelah respawn, simpan ukuran dasar.
                                originalSizeData[part] = part.Size / multiplier
                            end
                            part.Size = part.Size * multiplier
                        end
                    end
                end
            end
        end))
        
    else
        -- Kembalikan ukuran asli
        local charToRestore = getCharacter()
        for part, originalSize in pairs(originalSizeData) do
            -- Pastikan part masih ada di karakter saat restore
            if charToRestore and part.Parent == charToRestore then 
                pcall(function() 
                    part.Size = originalSize
                end)
            end
        end
        originalSizeData = {}
    end
end

-- MODIFIED: Fungsi untuk menemukan target Aimbot (Mengembalikan BasePart)
local function findAimbotTarget()
    local targetPlayer = nil
    local myHRP = getHRP()
    if not myHRP then return nil end

    if selectedAimbotPlayerName and selectedAimbotPlayerName ~= "" then
        -- Mode 1: Target Pemain Tertentu
        local p = Players:FindFirstChild(selectedAimbotPlayerName)
        if p and p.Character then
            local targetPart = p.Character:FindFirstChild(selectedAimbotPart) -- Cari bagian tubuh yang dipilih
            if targetPart and targetPart:IsA("BasePart") then
                local dist = (myHRP.Position - targetPart.Position).Magnitude
                if dist <= aimbotRange then
                    targetPlayer = p
                end
            end
        end
    else
        -- Mode 2: Target Terdekat
        local closestPlayer = nil
        local shortestDistance = aimbotRange

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 then
                local targetPart = player.Character:FindFirstChild(selectedAimbotPart) -- Gunakan bagian tubuh yang dipilih
                
                if targetPart and targetPart:IsA("BasePart") then
                    local distance = (myHRP.Position - targetPart.Position).Magnitude
                    
                    if distance < shortestDistance then
                        shortestDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
        targetPlayer = closestPlayer
    end
    
    if targetPlayer and targetPlayer.Character then
        local targetPart = targetPlayer.Character:FindFirstChild(selectedAimbotPart)
        return targetPart -- Kembalikan BasePart target
    end
    
    return nil
end


-- MODIFIED: Fungsi Aimbot utama
local function doAimbot()
    local cam = Workspace.CurrentCamera
    local hrp = getHRP()
    
    if not cam or not hrp then 
        aimbotTarget = nil 
        return 
    end

    local targetPart = findAimbotTarget() -- Sekarang mengembalikan BasePart

    if targetPart then
        -- Set aimbotTarget ke Player agar UI/log lain tahu siapa targetnya
        aimbotTarget = targetPart.Parent.Parent 
        local targetPosition = targetPart.Position
        
        -- Hitung CFrame kamera yang mengarah ke target
        local lookVector = (targetPosition - cam.CFrame.Position).Unit
        local newCFrame = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + lookVector)
        
        -- Atur CFrame kamera
        cam.CFrame = newCFrame
    else
        aimbotTarget = nil
    end
end

-- Fungsi Kill Aura
local function doKillAura()
    local char = getCharacter()
    local hrp = getHRP()
    
    if not char or not hrp or not flags.killAura then return end
    
    local tool = char:FindFirstChildOfClass("Tool")
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 then
            local targetHRP = player.Character.HumanoidRootPart
            local distance = (hrp.Position - targetHRP.Position).Magnitude
            
            if distance <= killAuraRange then
                
                -- Simpan posisi asli
                local originalCFrame = hrp.CFrame
                
                -- Teleport ke target (misalnya 1 unit di atas target)
                hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 1, 0)
                
                -- Panggil remotes atau fungsi serangan
                if tool and tool:FindFirstChild("Handle") then
                    pcall(function()
                        tool:Activate()
                        task.wait(0.1) -- Jeda sebentar
                        tool:Deactivate()
                    end)
                end
                
                -- Teleport kembali
                hrp.CFrame = originalCFrame
                
                -- Tunggu sebentar sebelum menyerang lagi
                task.wait(killAuraDelay)
                break -- Fokus pada satu target per loop
            end
        end
    end
end


-- UI & Feature init
local function CreateUI()
    -- Load Rayfield
    local success, rf = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/cokycokynanas/ScBoyeszz/refs/heads/main/rf.lua"))()
    end)
    if not success or not rf then
        success, rf = pcall(function()
            return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
        end)
    end
    if not success or not rf then
        warn("[BangBoyeszz] Failed to load Rayfield UI library")
        return
    end
    Rayfield = rf

    -- Create Window
    local Window = Rayfield:CreateWindow({
        Name = "Boyesz Tonz Tools",
        LoadingTitle = "⚡ Boyesz Tonz Tools ⚡",
        LoadingSubtitle = "v2 · By Boyeszz Tonz ♡",
        ConfigurationSaving = { Enabled = false },
        KeySystem = false,
        Theme = "DarkBlue",
        DisableBuildWarnings = true,
        DisableRayfieldPrompts = true,
    })
    windows.Window = Window

    -- MAIN TAB
    local Main = Window:CreateTab("Main", "shield")
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
        end
    })
    
    -- GHOST MODE (Penambahan Baru)
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
    
    -- NEW MOVEMENT TAB
    local MovementTab = Window:CreateTab("Movement", "zap")
    windows.Movement = MovementTab

    -- CFly (Head Anchor Method, Speed 50)
    flags.cframeFly = false
    local CFloop

    MovementTab:CreateToggle({
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
            else
                if hum then hum.PlatformStand = false end
                if head then head.Anchored = false end
            end
        end
    })

    -- Fly Script (External Pastebin)
    MovementTab:CreateToggle({
        Name = "Fly Script (Auto-Execute)",
        CurrentValue = false,
        Callback = function(enabled)
            flags.externalFly = enabled
            if enabled then
                task.spawn(function()
                    local ok, err = pcall(function()
                        loadstring(game:HttpGet("https://pastebin.com/raw/seGbe6tn"))()
                    end)
                    if not ok then
                        warn("[Boyesz Tonz] Error executing Fly Script:", err)
                    end
                end)
            end
        end
    })

    MovementTab:CreateButton({
        Name = "Execute Fly Script",
        Callback = function()
            task.spawn(function()
                local ok, err = pcall(function()
                    loadstring(game:HttpGet("https://pastebin.com/raw/seGbe6tn"))()
                end)
                if not ok then
                    warn("[Boyesz Tonz] Error executing Fly Script:", err)
                end
            end)
        end
    })

    -- Infinite Jump
    MovementTab:CreateToggle({
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
        end
    })

    -- Fullbright
    MovementTab:CreateToggle({
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
        end
    })

    -- Click Teleport
    MovementTab:CreateToggle({
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
        end
    })
    
    -- === TAB COMBAT ===
    local CombatTab = Window:CreateTab("Combat", "sword")
    windows.Combat = CombatTab
    
    -- MODIFIED Aimbot
    CombatTab:CreateSection("Aimbot")
    
    -- NEW: Dropdown untuk memilih bagian tubuh
    CombatTab:CreateDropdown({
        Name = "Target Bagian Tubuh",
        Options = {"Head", "Torso", "LeftLeg"}, -- Pilihan bagian tubuh
        CurrentOption = {"Head"},
        MultipleOptions = false,
        Flag = "AimbotPartDropdown",
        Callback = function(option)
            selectedAimbotPart = (typeof(option) == "table" and option[1]) or option
            aimbotTarget = nil -- Reset target
        end,
    })

    local function getAimbotPlayerOptions()
        local options = {""} -- Opsi pertama adalah string kosong untuk "Terdekat"
        for _, name in ipairs(sortedPlayerNames()) do
            table.insert(options, name)
        end
        return options
    end

    local AimbotPlayerDropdown = CombatTab:CreateDropdown({
        Name = "Pilih Target (Kosong = Terdekat)",
        Options = getAimbotPlayerOptions(),
        CurrentOption = {""},
        MultipleOptions = false,
        Flag = "AimbotPlayerDropdown",
        Callback = function(option)
            local opt = (typeof(option) == "table" and option[1]) or option
            selectedAimbotPlayerName = (opt == "") and nil or opt
            aimbotTarget = nil -- Reset target
        end,
    })
    
    -- Koneksi Refresh Dropdown Aimbot
    setConn("aimbotPlayerAdd", Players.PlayerAdded:Connect(function()
        pcall(function() AimbotPlayerDropdown:Refresh(getAimbotPlayerOptions(), true) end)
    end))
    setConn("aimbotPlayerRem", Players.PlayerRemoving:Connect(function()
        pcall(function() AimbotPlayerDropdown:Refresh(getAimbotPlayerOptions(), true) end)
    end))

    CombatTab:CreateSlider({
        Name = "Aimbot Range",
        Range = {50, 500},
        Increment = 10,
        Suffix = "Studs",
        CurrentValue = 150,
        Callback = function(value)
            aimbotRange = value
        end
    })

    CombatTab:CreateToggle({
        Name = "Aimbot Lock",
        CurrentValue = false,
        Callback = function(enabled)
            flags.aimbotLock = enabled
            clearConn("aimbot")
            aimbotTarget = nil
            if enabled then
                -- Set koneksi untuk mengunci target
                setConn("aimbot", RunService.RenderStepped:Connect(doAimbot))
            end
        end
    })
    
    -- MODIFIED Hitbox Expander
    CombatTab:CreateSection("Hitbox Expander")

    CombatTab:CreateSlider({
        Name = "Multiplier Value",
        Range = {1, 10},
        Increment = 0.5,
        Suffix = "x",
        CurrentValue = 1,
        Callback = function(value)
            hitboxMultipler = value
            if flags.hitboxExpander then -- Terapkan perubahan langsung jika aktif
                setHitbox(true)
            end
        end
    })

    CombatTab:CreateToggle({
        Name = "Enable Hitbox",
        CurrentValue = false,
        Callback = setHitbox
    })
    
    -- Kill Aura
    CombatTab:CreateSection("Kill Aura")
    CombatTab:CreateToggle({
        Name = "Kill Aura",
        CurrentValue = false,
        Callback = function(enabled)
            flags.killAura = enabled
            clearConn("killAuraLoop")
            if enabled then
                task.spawn(function()
                    while flags.killAura do
                        doKillAura()
                        task.wait(0.1)
                    end
                end)
            end
        end
    })

    CombatTab:CreateSlider({
        Name = "Kill Aura Range",
        Range = {5, 100},
        Increment = 5,
        Suffix = "Studs",
        CurrentValue = 25,
        Callback = function(value)
            killAuraRange = value
        end
    })

    CombatTab:CreateSlider({
        Name = "Kill Aura Delay",
        Range = {0.1, 5},
        Increment = 0.1,
        Suffix = "s",
        CurrentValue = 0.5,
        Callback = function(value)
            killAuraDelay = value
        end
    })

    -- TELEPORT TAB
    local TeleportTab = Window:CreateTab("Teleport", "map-pin")
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
                return
            end
            local target = Players:FindFirstChild(selectedPlayerName)
            if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = getHRP()
                if hrp then
                    hrp.CFrame = CFrame.new(target.Character.HumanoidRootPart.Position + Vector3.new(0,3,0))
                end
            end
        end
    })

    TeleportTab:CreateButton({
        Name = "Refresh List",
        Callback = function()
            PlayerDropdown:Refresh(playerOptions(), true)
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
        end
    end })

    TeleportTab:CreateButton({ Name = "Teleport Pos", Callback = function()
        if savedSlots[slotSelected] then
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.new(savedSlots[slotSelected] + Vector3.new(0,5,0))
            end
        end
    end })

    TeleportTab:CreateButton({ Name = "Clear Slot", Callback = function()
        savedSlots[slotSelected] = nil
    end })

    TeleportTab:CreateButton({ Name = "Clear All Slots", Callback = function()
        for i=1,30 do savedSlots[i] = nil end
    end })


    local MiscTab = Window:CreateTab("Misc", "settings")
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
            if not spectateTargetName or spectateTargetName == "" then return end
            local target = Players:FindFirstChild(spectateTargetName)
            if not target or not target.Character then return end

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
        end
    })

    -- FPS BOOST & PERFORMANCE SECTION
    MiscTab:CreateSection("FPS Boost & Anti-Lag")

    MiscTab:CreateButton({
        Name = "Unlock FPS (Set 240 FPS)",
        Callback = function()
            if setfpscap then
                pcall(function() setfpscap(240) end)
            end
        end
    })

    local originalGlobalShadows = Lighting.GlobalShadows
    MiscTab:CreateToggle({
        Name = "FPS Boost (Standard Anti-Lag)",
        CurrentValue = false,
        Callback = function(enabled)
            flags.fpsBoost = enabled
            if enabled then
                pcall(function()
                    Lighting.GlobalShadows = false
                    Lighting.FogEnd = 9e9
                    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
                    for _, effect in ipairs(Lighting:GetChildren()) do
                        if effect:IsA("PostEffect") or effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect") or effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect") or effect:IsA("DepthOfFieldEffect") then
                            effect.Enabled = false
                        end
                    end
                    local terrain = Workspace:FindFirstChildOfClass("Terrain")
                    if terrain then
                        terrain.WaterWaveSize = 0
                        terrain.WaterWaveSpeed = 0
                        terrain.WaterReflectance = 0
                        terrain.WaterTransparency = 0
                        pcall(function() terrain.Decoration = false end)
                    end
                end)
            else
                pcall(function()
                    Lighting.GlobalShadows = originalGlobalShadows
                    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
                    for _, effect in ipairs(Lighting:GetChildren()) do
                        if effect:IsA("PostEffect") or effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect") or effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect") or effect:IsA("DepthOfFieldEffect") then
                            effect.Enabled = true
                        end
                    end
                end)
            end
        end
    })

    MiscTab:CreateButton({
        Name = "Ultra FPS Boost (Remove Textures & Effects)",
        Callback = function()
            pcall(function()
                Lighting.GlobalShadows = false
                Lighting.FogEnd = 9e9
                pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
                
                for _, effect in ipairs(Lighting:GetChildren()) do
                    if effect:IsA("PostEffect") or effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect") or effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect") or effect:IsA("DepthOfFieldEffect") then
                        effect.Enabled = false
                    end
                end

                for _, v in ipairs(Workspace:GetDescendants()) do
                    if v:IsA("BasePart") then
                        v.Material = Enum.Material.SmoothPlastic
                        v.Reflectance = 0
                    elseif v:IsA("Decal") or v:IsA("Texture") then
                        v:Destroy()
                    elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                        v.Enabled = false
                    end
                end

                local terrain = Workspace:FindFirstChildOfClass("Terrain")
                if terrain then
                    terrain.WaterWaveSize = 0
                    terrain.WaterWaveSpeed = 0
                    terrain.WaterReflectance = 0
                    terrain.WaterTransparency = 0
                    pcall(function() terrain.Decoration = false end)
                end
            end)
        end
    })

    -- GAME SCRIPTS TAB
    local GameTab = Window:CreateTab("Game Scripts", "gamepad-2")
    windows.GameScripts = GameTab

    GameTab:CreateSection("Mine a Mountain")

    GameTab:CreateToggle({
        Name = "Mine a Mountain (Auto-Execute)",
        CurrentValue = false,
        Callback = function(enabled)
            flags.mineAMountain = enabled
            if enabled then
                task.spawn(function()
                    local ok, err = pcall(function()
                        loadstring(game:HttpGet("https://raw.githubusercontent.com/gumanba/Scripts/main/MineaMountain"))()
                    end)
                    if not ok then
                        warn("[Boyesz Tonz] Error executing Mine a Mountain:", err)
                    end
                end)
            end
        end
    })

    GameTab:CreateButton({
        Name = "Execute Mine a Mountain",
        Callback = function()
            task.spawn(function()
                local ok, err = pcall(function()
                    loadstring(game:HttpGet("https://raw.githubusercontent.com/gumanba/Scripts/main/MineaMountain"))()
                end)
                if not ok then
                    warn("[Boyesz Tonz] Error executing Mine a Mountain:", err)
                end
            end)
        end
    })

    -- FISH IT TAB
    local function AddFishItTab()
        if game.PlaceId ~= 121864768012064 then return end
        if windows.FishIt then return end

        local ok, netRoot = pcall(function()
            return ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index")
                :WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
        end)
        if not ok or not netRoot then
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
                                flags.autofish = false
                                break
                            end
                            for i=1,14 do
                                if not flags.autofish then break end
                                task.wait(0.1)
                            end
                        end
                    end)
                else
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
                if not chosen then return end
                local pos = nameToPos[chosen]
                if not pos then return end
                local hrp = getHRP()
                if hrp then
                    hrp.CFrame = CFrame.new(pos + Vector3.new(0,5,0))
                end
            end
        })
    end

    -- === KODE PLAYER ESP DIMULAI DI SINI ===
    local function AddESPTab(Window)
        local ESPTab = Window:CreateTab("ESP", "eye")
        windows.ESP = ESPTab
        
        flags.playerESP = false
        flags.highlightESP = false
        local espTable = {} -- { TargetPlayer = { Billboard, Highlight }, ... }
        
        -- Helper untuk membuat BillboardGui modern (Card + Health Bar + Name/Distance)
        local function createBillboard(targetCharacter)
            local hrp = targetCharacter:FindFirstChild("HumanoidRootPart")
            if not hrp then return nil end

            local billboard = Instance.new("BillboardGui")
            billboard.Name = "PlayerESP_BB"
            billboard.Adornee = hrp
            billboard.Size = UDim2.new(0, 160, 0, 45)
            billboard.AlwaysOnTop = true
            billboard.ExtentsOffset = Vector3.new(0, 3.5, 0)
            
            local card = Instance.new("Frame")
            card.Name = "Card"
            card.Size = UDim2.new(1, 0, 1, 0)
            card.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
            card.BackgroundTransparency = 0.25
            card.BorderSizePixel = 0
            card.Parent = billboard

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = card

            local stroke = Instance.new("UIStroke")
            stroke.Name = "Stroke"
            stroke.Color = Color3.fromRGB(0, 170, 255)
            stroke.Thickness = 1.5
            stroke.Transparency = 0.3
            stroke.Parent = card

            local text = Instance.new("TextLabel")
            text.Name = "InfoText"
            text.Size = UDim2.new(1, -10, 0, 20)
            text.Position = UDim2.new(0, 5, 0, 3)
            text.Text = targetCharacter.Name
            text.TextColor3 = Color3.fromRGB(255, 255, 255)
            text.TextStrokeTransparency = 0.6
            text.BackgroundTransparency = 1
            text.Font = Enum.Font.GothamBold
            text.TextSize = 12
            text.Parent = card

            local healthBg = Instance.new("Frame")
            healthBg.Name = "HealthBg"
            healthBg.Size = UDim2.new(1, -16, 0, 6)
            healthBg.Position = UDim2.new(0, 8, 1, -11)
            healthBg.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
            healthBg.BorderSizePixel = 0
            healthBg.Parent = card

            local healthCorner = Instance.new("UICorner")
            healthCorner.CornerRadius = UDim.new(0, 3)
            healthCorner.Parent = healthBg

            local healthFill = Instance.new("Frame")
            healthFill.Name = "HealthFill"
            healthFill.Size = UDim2.new(1, 0, 1, 0)
            healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
            healthFill.BorderSizePixel = 0
            healthFill.Parent = healthBg

            local fillCorner = Instance.new("UICorner")
            fillCorner.CornerRadius = UDim.new(0, 3)
            fillCorner.Parent = healthFill
            
            billboard.Parent = LocalPlayer:WaitForChild("PlayerGui")
            return billboard
        end

        -- Helper untuk membuat Highlight ESP (Chams Glow through walls)
        local function createHighlight(targetCharacter)
            local highlight = Instance.new("Highlight")
            highlight.Name = "PlayerESP_Highlight"
            highlight.Adornee = targetCharacter
            highlight.FillColor = Color3.fromRGB(255, 50, 50)
            highlight.FillTransparency = 0.55
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.OutlineTransparency = 0.1
            highlight.Parent = LocalPlayer:WaitForChild("PlayerGui")
            return highlight
        end
        
        -- Helper untuk menghapus visual ESP
        local function cleanupESP(player)
            if espTable[player] then
                if espTable[player].Billboard then
                    pcall(function() espTable[player].Billboard:Destroy() end)
                end
                if espTable[player].Highlight then
                    pcall(function() espTable[player].Highlight:Destroy() end)
                end
                espTable[player] = nil
            end
        end
        
        -- Main ESP Loop
        local function updateESP()
            if not flags.playerESP and not flags.highlightESP then return end

            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local char = player.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local isAlive = hrp and hum and hum.Health > 0

                    if isAlive then
                        espTable[player] = espTable[player] or {}
                        local isTeammate = (player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team)

                        -- 1. Name Tag + Health Bar ESP
                        if flags.playerESP then
                            if not espTable[player].Billboard or not espTable[player].Billboard.Parent then
                                espTable[player].Billboard = createBillboard(char)
                            end

                            local bb = espTable[player].Billboard
                            if bb then
                                bb.Adornee = hrp
                                local card = bb:FindFirstChild("Card")
                                if card then
                                    local textLabel = card:FindFirstChild("InfoText")
                                    local healthBg = card:FindFirstChild("HealthBg")
                                    local healthFill = healthBg and healthBg:FindFirstChild("HealthFill")
                                    local stroke = card:FindFirstChild("Stroke")

                                    local myHRP = getHRP()
                                    local dist = myHRP and math.floor((myHRP.Position - hrp.Position).Magnitude) or 0
                                    local healthPct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)

                                    if textLabel then
                                        textLabel.Text = string.format("%s | %d HP (%dm)", player.Name, math.floor(hum.Health), dist)
                                    end

                                    if healthFill then
                                        healthFill.Size = UDim2.new(healthPct, 0, 1, 0)
                                        if healthPct > 0.6 then
                                            healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 130)
                                        elseif healthPct > 0.3 then
                                            healthFill.BackgroundColor3 = Color3.fromRGB(255, 190, 0)
                                        else
                                            healthFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
                                        end
                                    end

                                    if stroke then
                                        stroke.Color = isTeammate and Color3.fromRGB(0, 255, 150) or Color3.fromRGB(255, 60, 60)
                                    end
                                end
                            end
                        else
                            if espTable[player].Billboard then
                                espTable[player].Billboard:Destroy()
                                espTable[player].Billboard = nil
                            end
                        end

                        -- 2. Highlight Chams ESP (Glow through walls)
                        if flags.highlightESP then
                            if not espTable[player].Highlight or not espTable[player].Highlight.Parent then
                                espTable[player].Highlight = createHighlight(char)
                            end

                            local hl = espTable[player].Highlight
                            if hl then
                                hl.Adornee = char
                                hl.FillColor = isTeammate and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(255, 50, 50)
                            end
                        else
                            if espTable[player].Highlight then
                                espTable[player].Highlight:Destroy()
                                espTable[player].Highlight = nil
                            end
                        end
                    else
                        cleanupESP(player)
                    end
                end
            end
        end

        local function toggleESPState()
            clearConn("playerESP_Loop")
            if flags.playerESP or flags.highlightESP then
                setConn("playerESP_Rem", Players.PlayerRemoving:Connect(cleanupESP))
                setConn("playerESP_Loop", RunService.Heartbeat:Connect(updateESP))
            else
                clearConn("playerESP_Rem")
                for player, _ in pairs(espTable) do
                    cleanupESP(player)
                end
                espTable = {}
            end
        end
        
        ESPTab:CreateToggle({
            Name = "Name & Health Bar ESP",
            CurrentValue = false,
            Callback = function(enabled)
                flags.playerESP = enabled
                toggleESPState()
            end
        })

        ESPTab:CreateToggle({
            Name = "Chams Glow ESP (Through Walls)",
            CurrentValue = false,
            Callback = function(enabled)
                flags.highlightESP = enabled
                toggleESPState()
            end
        })
        
        ESPTab:CreateButton({
            Name = "Refresh ESP",
            Callback = function()
                for player, _ in pairs(espTable) do
                    cleanupESP(player)
                end
                espTable = {}
            end
        })
    end
    -- === KODE PLAYER ESP BERAKHIR DI SINI ===


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
            -- Kembalikan hitbox ke normal sebelum memuat ulang
            setHitbox(false) 
            local ok, err = pcall(CreateUI)
            if not ok then warn("CreateUI error:", err) end
        end
    end
end)

-- Initial load
lastPlace = game.PlaceId
CreateUI()
