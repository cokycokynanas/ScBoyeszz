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

-- Ghost Mode Implementation
local originalPartsData = {} -- Store original transparency and cancollide data

local function setGhostMode(enabled)
    flags.ghostMode = enabled
    local char = getCharacter()
    if not char then 
        notify("Karakter tidak ditemukan.")
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
    
    notify("Ghost Mode: " .. (enabled and "ON" or "OFF"))
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
        notify("Hitbox Expander: ON (x"..multiplier..")")

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
        notify("Hitbox Expander: OFF")
    end
end

-- MODIFIED: Fungsi untuk menemukan target Aimbot
local function findAimbotTarget()
    local target = nil
    local myHRP = getHRP()
    if not myHRP then return nil end

    if selectedAimbotPlayerName and selectedAimbotPlayerName ~= "" then
        -- Mode 1: Target Pemain Tertentu
        local p = Players:FindFirstChild(selectedAimbotPlayerName)
        if p and p.Character and p.Character:FindFirstChild("Head") then
            local dist = (myHRP.Position - p.Character.Head.Position).Magnitude
            if dist <= aimbotRange then
                target = p
            end
        end
    else
        -- Mode 2: Target Terdekat
        local closestPlayer = nil
        local shortestDistance = aimbotRange

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head") and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 then
                local targetHead = player.Character.Head
                local distance = (myHRP.Position - targetHead.Position).Magnitude
                
                if distance < shortestDistance then
                    shortestDistance = distance
                    closestPlayer = player
                end
            end
        end
        target = closestPlayer
    end
    
    return target
end


-- MODIFIED: Fungsi Aimbot utama
local function doAimbot()
    local cam = Workspace.CurrentCamera
    local hrp = getHRP()
    
    if not cam or not hrp then 
        aimbotTarget = nil 
        return 
    end

    aimbotTarget = findAimbotTarget()

    if aimbotTarget and aimbotTarget.Character and aimbotTarget.Character:FindFirstChild("Head") then
        local targetHead = aimbotTarget.Character.Head
        local targetPosition = targetHead.Position
        
        -- Hitung CFrame kamera yang mengarah ke target
        local lookVector = (targetPosition - cam.CFrame.Position).Unit
        local newCFrame = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + lookVector)
        
        -- Atur CFrame kamera
        cam.CFrame = newCFrame
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
                
                notify("Kill Aura menyerang: " .. player.Name)
                
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
    --Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
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
    
    -- NEW MOVEMENT TAB
    local MovementTab = Window:CreateTab("Movement", 4483362458)
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
                notify("CFly: ON")
            else
                if hum then hum.PlatformStand = false end
                if head then head.Anchored = false end
                notify("CFly: OFF")
            end
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
            notify("Infinite Jump: " .. (enabled and "ON" or "OFF"))
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
            notify("Fullbright: " .. (enabled and "ON" or "OFF"))
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
            notify("Click Teleport: " .. (enabled and "ON" or "OFF"))
        end
    })
    
    -- === TAB COMBAT ===
    local CombatTab = Window:CreateTab("Combat", 4483362458)
    windows.Combat = CombatTab
    
    -- MODIFIED Aimbot
    CombatTab:CreateSection("Aimbot")
    
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
            notify("Aimbot Range diatur ke " .. value .. " Studs")
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
            notify("Aimbot Lock: " .. (enabled and "ON" or "OFF"))
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
                        task.wait(0.1) -- Jeda kecil antar pengecekan
                    end
                end)
            end
            notify("Kill Aura: " .. (enabled and "ON" or "OFF"))
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
            notify("Kill Aura Range diatur ke " .. value .. " Studs")
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
            notify("Kill Aura Delay diatur ke " .. value .. " detik")
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

    -- === KODE PLAYER ESP DIMULAI DI SINI ===
    local function AddESPTab(Window)
        local ESPTab = Window:CreateTab("ESP", 4483362458)
        windows.ESP = ESPTab
        
        flags.playerESP = false
        local espTable = {} -- { TargetPlayer = { BillboardGui, LinePart }, ... }
        
        -- Helper untuk membuat BillboardGui
        local function createBillboard(targetCharacter)
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "PlayerESP_BB"
            billboard.Adornee = targetCharacter:FindFirstChild("HumanoidRootPart") or targetCharacter:WaitForChild("HumanoidRootPart", 5)
            billboard.Size = UDim2.new(0, 150, 0, 50)
            billboard.AlwaysOnTop = true
            billboard.ExtentsOffset = Vector3.new(0, 5, 0)
            
            local text = Instance.new("TextLabel")
            text.Name = "InfoText"
            text.Size = UDim2.new(1, 0, 1, 0)
            text.Text = targetCharacter.Name
            text.TextColor3 = Color3.new(1, 1, 1)
            text.TextStrokeColor3 = Color3.new(0, 0, 0)
            text.TextStrokeTransparency = 0
            text.BackgroundTransparency = 1
            text.Font = Enum.Font.SourceSansBold
            text.TextSize = 14
            text.Parent = billboard
            
            billboard.Parent = LocalPlayer.PlayerGui
            return billboard
        end
        
        -- Helper untuk menghapus visual ESP
        local function cleanupESP(player)
            if espTable[player] then
                if espTable[player].Billboard then
                    espTable[player].Billboard:Destroy()
                end
                -- LinePart cleanup can be ignored for simple BB implementation
                espTable[player] = nil
            end
        end
        
        -- Main ESP Loop (RunService.Heartbeat for position update)
        local function updateESP()
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local char = player.Character
                    
                    if char and char:FindFirstChild("HumanoidRootPart") and flags.playerESP then
                        if not espTable[player] or not espTable[player].Billboard or not espTable[player].Billboard.Parent then
                            -- Create Visuals
                            espTable[player] = espTable[player] or {}
                            espTable[player].Billboard = createBillboard(char)
                            
                            -- Re-connect Adornee if character changes
                            setConn("ESP_"..player.Name, player.CharacterAdded:Connect(function(newChar)
                                -- Wait for HRP in the new character
                                local hrp = newChar:WaitForChild("HumanoidRootPart", 5)
                                if hrp and espTable[player] and espTable[player].Billboard then
                                    espTable[player].Billboard.Adornee = hrp
                                end
                            end))
                        end
                        
                        -- Update Info
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if hrp and espTable[player] and espTable[player].Billboard then
                            local textLabel = espTable[player].Billboard:FindFirstChild("InfoText")
                            if textLabel then
                                local myHRP = getHRP()
                                if myHRP then
                                    local distance = (myHRP.Position - hrp.Position).Magnitude
                                    textLabel.Text = string.format("%s\n(%.1fm)", player.Name, distance)
                                    
                                    -- Optional: Change color based on team/status
                                    if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
                                        textLabel.TextColor3 = Color3.new(0, 1, 0) -- Green for teammate
                                    else
                                        textLabel.TextColor3 = Color3.new(1, 0, 0) -- Red for enemy
                                    end
                                end
                            end
                        end
                    else
                        -- Player is nil/dead or ESP is off, clean up
                        cleanupESP(player)
                    end
                end
            end
        end
        
        ESPTab:CreateToggle({
            Name = "Player ESP",
            CurrentValue = false,
            Callback = function(enabled)
                flags.playerESP = enabled
                
                clearConn("playerESP_Loop")
                if enabled then
                    -- Add cleanup for players leaving
                    setConn("playerESP_Rem", Players.PlayerRemoving:Connect(cleanupESP))
                    
                    -- Start main update loop
                    setConn("playerESP_Loop", RunService.Heartbeat:Connect(updateESP))
                else
                    -- Disable, clean up all existing visuals
                    clearConn("playerESP_Rem")
                    for player, data in pairs(espTable) do
                        cleanupESP(player)
                    end
                    espTable = {} -- Reset table
                end
                notify("Player ESP: " .. (enabled and "ON" or "OFF"))
            end
        })
        
        -- Optional: Add a button to refresh if something goes wrong
        ESPTab:CreateButton({
            Name = "Refresh ESP",
            Callback = function()
                for player, data in pairs(espTable) do
                    cleanupESP(player)
                end
                espTable = {}
                if flags.playerESP then
                    notify("ESP di-refresh. Mungkin perlu beberapa detik untuk muncul kembali.")
                else
                    notify("ESP di-refresh (saat ini OFF).")
                end
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
