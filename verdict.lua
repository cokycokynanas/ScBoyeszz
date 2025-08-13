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
local conns = {}          -- store active connections
local windows = {}        -- refs for created UI elements (Window/Tabs)
local flags = {}          -- feature flags (autofish, perfectCast, etc.)
local originalLighting = {}
local customSpeed = 16

-- Helpers for connections
local function safeDisconnect(conn)
    if conn then
        pcall(function() conn:Disconnect() end)
    end
end

local function setConn(name, conn)
    if conns[name] then safeDisconnect(conns[name]) end
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
            Rayfield:Notify({
                Title = "Info",
                Content = tostring(msg),
                Duration = 3,
                Image = 6034509993 -- Icon informasi
            })
        end)
    else
        warn("[Verdict] " .. tostring(msg))
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
    -- Load Rayfield once
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

    -- Create Window
    local Window = Rayfield:CreateWindow({
        Name = "Verdict",
        LoadingTitle = "Verdict",
        LoadingSubtitle = "Just a Simple Script ♡",
        ConfigurationSaving = { Enabled = false },
        KeySystem = false,
    })
    windows.Window = Window

    -- MAIN TAB ⚙️
    local Main = Window:CreateTab("Main", 7734057965)
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

    -- Speed slider
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

    -- TELEPORT TAB 📍
    local TeleportTab = Window:CreateTab("Teleport", 6035067836)
    windows.Teleport = TeleportTab
    TeleportTab:CreateSection("Pilih pemain untuk teleport")

    ...
    -- (kode teleport & save pos tetap sama seperti script kamu, hanya icon tab yang berubah)
    ...

    -- MISC TAB 👀
    local MiscTab = Window:CreateTab("Misc", 6035078880)
    windows.Misc = MiscTab

    ...
    -- (kode spectate tetap sama, hanya icon tab yang berubah)
    ...

    -- Fish It TAB 🎣
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

        local FishItTab = Window:CreateTab("Fish It", 6034818372)
        windows.FishIt = FishItTab

        ...
        -- (kode autofish dan teleport island tetap sama, hanya icon tab yang berubah)
        ...
    end

    AddFishItTab()
end

-- Monitor PlaceId changes
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

lastPlace = game.PlaceId
CreateUI()
