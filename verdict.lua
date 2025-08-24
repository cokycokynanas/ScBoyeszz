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
            Rayfield:Notify({ Title = "Info", Content = tostring(msg), Duration = 3, Image = 4483362458 })
        end)
    else
        warn("[SimpleBloxGUI] " .. tostring(msg))
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

-- UI & Feature init
local function CreateUI()
    -- Load Rayfield
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

    -- Create Window
    local Window = Rayfield:CreateWindow({
        Name = "SimpleBloxGUI",
        LoadingTitle = "SimpleBloxGUI",
        LoadingSubtitle = "Just a Simple Script ♡",
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
        return sortedPlayerNames()
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
    local savedSlots = { nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil }
    local slotSelected = 1

    local SlotDropdown = TeleportTab:CreateDropdown({
        Name = "Pilih Slot",
        Options = {"1","2","3","4","5", "6", "7", "8", "9", "10", "11", "12"},
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

    -- MISC TAB
    local MiscTab = Window:CreateTab("Misc", 4483362458)
    windows.Misc = MiscTab
    
    MiscTab:CreateSection("Gendong Player")
    
    local gendongPlayerName = nil
    local function gplayerOptions()
        return sortedPlayerNames() or {}
    end
    local GendongDropdown = MiscTab:CreateDropdown({
        Name = "Pilih Pemain",
        Options = gplayerOptions(),
        CurrentOption = {},
        MultipleOptions = false,
        Flag = "GendongPlayerDropdown",
        Callback = function(option)
            gendongPlayerName = (typeof(option) == "table" and option[1]) or option
        end,
    })

    setConn("playerAdd", Players.PlayerAdded:Connect(function()
        pcall(function() GendongDropdown:Refresh(gplayerOptions(), true) end)
    end))
    setConn("playerRem", Players.PlayerRemoving:Connect(function()
        pcall(function() GendongDropdown:Refresh(gplayerOptions(), true) end)
    end))
    local gendong = pcall(function()
        return ReplicatedStorage:WaitForChild("CarryRequest")
    end)
    MiscTab:CreateButton({
        Name = "Gendong Player",
        Callback = function()
            if not gendongPlayerName or gendongPlayerName == "" then
                notify("Pilih pemain terlebih dahulu.")
                return
            end
            local target = Players:FindFirstChild(gendongPlayerName)
            if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                --local tPlayer = { gendongPlayerName }
                local checkStatuss = true
                if checkStatuss then
                    --:WaitForChild("CarryRequest"):FireServer(gendongPlayerName)
                    local SOME_2 = game:GetService("ReplicatedStorage"):WaitForChild("PerPlayerEvents"):WaitForChild(gendongPlayerName)
                notify("Permintaan Gendong Telah Dikirim ke "..gendongPlayerName)
                end
            else
                notify("Pemain tidak valid atau belum spawn.")
            end
        end
    })

    MiscTab:CreateButton({
        Name = "Refresh List",
        Callback = function()
            GendongDropdown:Refresh(gplayerOptions(), true)
            notify("Daftar pemain diperbarui.")
        end
    })
    
    --GB CKPTW
    MiscTab:CreateSection("GB Gunung CKPTW")
    MiscTab:CreateButton({
       Name = "GB Summit CKPTW",
       Callback = function()
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.new(Vector3.new(1815, 1983, 2168) + Vector3.new(0,5,0))
                notify("Teleport ke Summit")
            else
                notify("HumanoidRootPart tidak ditemukan.")
            end
        end  
    })
    
    MiscTab:CreateSection("GB Summit")
    MiscTab:CreateButton({
        Name = "GB Summit MT.DAUN",
        Callback = function()
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.new(Vector3.new(-620.8, 253.5, -385.0) + Vector3.new(0,5,0))
                notify("Teleport ke Pos 1")
                task.wait(2.0)
                hrp.CFrame = CFrame.new(Vector3.new(-1205.0, 264.9, -486.8) + Vector3.new(0,5,0))
                notify("Teleport ke Pos 2")
                task.wait(2.0)
                hrp.CFrame = CFrame.new(Vector3.new(-1399.4, 581.6, -949.3) + Vector3.new(0,5,0))
                notify("Teleport ke Pos 3")
                task.wait(2.0)
                hrp.CFrame = CFrame.new(Vector3.new(-1699.9, 819.9, -1397.9) + Vector3.new(0,5,0))
                notify("Teleport ke Pos 4")
                task.wait(1.2)
                --OTW SUMIT
                hrp.CFrame = CFrame.new(Vector3.new(-1835.3, 744.2, -1483.8) + Vector3.new(0,5,0))
                task.wait(0.8)
                hrp.CFrame = CFrame.new(Vector3.new(-1890.3, 775.5, -1582.0) + Vector3.new(0,5,0))
                task.wait(0.8)
                hrp.CFrame = CFrame.new(Vector3.new(-1969.2, 841.8, -1666.8) + Vector3.new(0,5,0))
                task.wait(0.8)
                hrp.CFrame = CFrame.new(Vector3.new(-2048.6, 887.7, -1751.1) + Vector3.new(0,5,0))
                task.wait(0.8)
                hrp.CFrame = CFrame.new(Vector3.new(-2090.5, 913.3, -1755.9) + Vector3.new(0,5,0))
                task.wait(0.8)
                hrp.CFrame = CFrame.new(Vector3.new(-3124.3, 1738.0, -2605.0) + Vector3.new(0,5,0))
                task.wait(0.8)
                hrp.CFrame = CFrame.new(Vector3.new(-3232.4, 1717.7, -2585.6) + Vector3.new(0,5,0))
                task.wait(2.8)
                ------------
                hrp.CFrame = CFrame.new(Vector3.new(-3233.6, 1716.0, -2589.3 ) + Vector3.new(0,5,0))
                notify("Teleport ke Summit")
            else
                notify("HumanoidRootPart tidak ditemukan.")
            end
        end
    }) 

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

    AddFishItTab()
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
