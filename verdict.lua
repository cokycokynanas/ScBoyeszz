-- // Services & Helpers
local Players = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local function getCharacter()
    return player.Character or player.CharacterAdded:Wait()
end

local function getHumanoid()
    local char = getCharacter()
    return char:WaitForChild("Humanoid")
end

-- // State & Connections
local states = {
    godMode = false,
    noclip = false,
    speedHack = false,
    infiniteJump = false,
    fullbright = false,
    clickTeleport = false,
}
local connections = {}
local originalLighting = {}
local customSpeed = 16 -- default

-- // Load Rayfield
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- // Window
local Window = Rayfield:CreateWindow({
    Name = "Verdict",
    LoadingTitle = "Verdict",
    LoadingSubtitle = "just a simple script made with love",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

-- // Notify helper
local function notify(msg)
    Rayfield:Notify({
        Title = "Info",
        Content = tostring(msg),
        Duration = 3,
        Image = 4483362458
    })
end

---------------------------------------------------------------------
--                           TAB MAIN
---------------------------------------------------------------------

local Main = Window:CreateTab("Main", 4483362458)

-- God Mode
Main:CreateToggle({
    Name = "God Mode",
    CurrentValue = false,
    Flag = "GodMode",
    Callback = function(enabled)
        states.godMode = enabled
        if enabled then
            connections.godMode = runService.Heartbeat:Connect(function()
                pcall(function()
                    local humanoid = getHumanoid()
                    if humanoid then
                        humanoid.Health = humanoid.MaxHealth
                    end
                end)
            end)
            notify("God Mode: ON")
        else
            if connections.godMode then
                connections.godMode:Disconnect()
                connections.godMode = nil
            end
            notify("God Mode: OFF")
        end
    end
})

-- Noclip
Main:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Flag = "Noclip",
    Callback = function(enabled)
        states.noclip = enabled
        if enabled then
            connections.noclip = runService.Stepped:Connect(function()
                pcall(function()
                    local character = getCharacter()
                    if character then
                        for _, part in ipairs(character:GetChildren()) do
                            if part:IsA("BasePart") then
                                part.CanCollide = false
                            end
                        end
                    end
                end)
            end)
            notify("Noclip: ON")
        else
            if connections.noclip then
                connections.noclip:Disconnect()
                connections.noclip = nil
            end
            pcall(function()
                local character = getCharacter()
                if character then
                    for _, part in ipairs(character:GetChildren()) do
                        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                            part.CanCollide = true
                        end
                    end
                end
            end)
            notify("Noclip: OFF")
        end
    end
})

-- Speed Hack
Main:CreateToggle({
    Name = "Speed Hack",
    CurrentValue = false,
    Flag = "SpeedHack",
    Callback = function(enabled)
        states.speedHack = enabled
        pcall(function()
            local humanoid = getHumanoid()
            if humanoid then
                if enabled then
                    humanoid.WalkSpeed = customSpeed
                    notify("Speed Hack: ON ("..customSpeed..")")
                else
                    humanoid.WalkSpeed = 16
                    notify("Speed Hack: OFF")
                end
            end
        end)
    end
})

-- Slider Speed
Main:CreateSlider({
    Name = "Speed Value",
    Range = {16, 200},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 16,
    Flag = "SpeedValue",
    Callback = function(value)
        customSpeed = value
        if states.speedHack then
            local humanoid = getHumanoid()
            if humanoid then
                humanoid.WalkSpeed = customSpeed
            end
        end
    end
})

-- Infinite Jump
Main:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Flag = "InfiniteJump",
    Callback = function(enabled)
        states.infiniteJump = enabled
        if enabled then
            connections.infiniteJump = userInputService.JumpRequest:Connect(function()
                pcall(function()
                    local humanoid = getHumanoid()
                    if humanoid then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end)
            end)
            notify("Infinite Jump: ON")
        else
            if connections.infiniteJump then
                connections.infiniteJump:Disconnect()
                connections.infiniteJump = nil
            end
            notify("Infinite Jump: OFF")
        end
    end
})

-- Fullbright
Main:CreateToggle({
    Name = "Fullbright",
    CurrentValue = false,
    Flag = "Fullbright",
    Callback = function(enabled)
        states.fullbright = enabled
        local lighting = game:GetService("Lighting")
        if enabled then
            originalLighting.Brightness = lighting.Brightness
            originalLighting.Ambient = lighting.Ambient
            originalLighting.ColorShift_Bottom = lighting.ColorShift_Bottom
            originalLighting.ColorShift_Top = lighting.ColorShift_Top
            originalLighting.FogEnd = lighting.FogEnd
            originalLighting.FogStart = lighting.FogStart

            lighting.Brightness = 5
            lighting.Ambient = Color3.new(1, 1, 1)
            lighting.ColorShift_Bottom = Color3.new(1, 1, 1)
            lighting.ColorShift_Top = Color3.new(1, 1, 1)
            lighting.FogEnd = 100000
            lighting.FogStart = 100000

            notify("Fullbright: ON")
        else
            lighting.Brightness = originalLighting.Brightness or 1
            lighting.Ambient = originalLighting.Ambient or Color3.new(0, 0, 0)
            lighting.ColorShift_Bottom = originalLighting.ColorShift_Bottom or Color3.new(0, 0, 0)
            lighting.ColorShift_Top = originalLighting.ColorShift_Top or Color3.new(0, 0, 0)
            lighting.FogEnd = originalLighting.FogEnd or 100000
            lighting.FogStart = originalLighting.FogStart or 0

            notify("Fullbright: OFF")
        end
    end
})

-- Click Teleport
Main:CreateToggle({
    Name = "Click Teleport",
    CurrentValue = false,
    Flag = "ClickTeleport",
    Callback = function(enabled)
        states.clickTeleport = enabled
        if enabled then
            local mouse = player:GetMouse()
            connections.clickTeleport = mouse.Button1Down:Connect(function()
                pcall(function()
                    local character = getCharacter()
                    local rootPart = character:FindFirstChild("HumanoidRootPart")
                    if rootPart and mouse.Hit then
                        rootPart.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 5, 0))
                        notify("Teleported to click location!")
                    end
                end)
            end)
            notify("Click Teleport: ON (Click anywhere to teleport)")
        else
            if connections.clickTeleport then
                connections.clickTeleport:Disconnect()
                connections.clickTeleport = nil
            end
            notify("Click Teleport: OFF")
        end
    end
})

---------------------------------------------------------------------
--                           TAB TELEPORT
---------------------------------------------------------------------

local TeleportTab = Window:CreateTab("Teleport", 4483362458)
TeleportTab:CreateSection("Pilih pemain untuk teleport")

local localPlayer = player
local selectedName 

-- Ambil daftar nama pemain
local function getOtherPlayerNames()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= localPlayer then
            table.insert(names, plr.Name)
        end
    end
    table.sort(names)
    return names
end

-- Dropdown Pilih Pemain
local PlayerDropdown = TeleportTab:CreateDropdown({
    Name = "Pilih Pemain",
    Options = getOtherPlayerNames(),
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "TeleportPlayerDropdown",
    Callback = function(option)
        if typeof(option) == "table" then
            selectedName = option[1]
        else
            selectedName = option
        end
    end,
})

local function refreshDropdown()
    PlayerDropdown:Refresh(getOtherPlayerNames(), true)
end
Players.PlayerAdded:Connect(refreshDropdown)
Players.PlayerRemoving:Connect(refreshDropdown)

TeleportTab:CreateButton({
    Name = "Teleport ke Pemain",
    Callback = function()
        if not selectedName or selectedName == "" then
            notify("Pilih pemain terlebih dahulu.")
            return
        end
        local target = Players:FindFirstChild(selectedName)
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            player.Character:MoveTo(target.Character.HumanoidRootPart.Position + Vector3.new(0, 3, 0))
            notify("Kamu ditransfer ke " .. selectedName .. ".")
        else
            notify("Pemain tidak valid atau belum spawn.")
        end
    end
})

TeleportTab:CreateButton({
    Name = "Refresh List",
    Callback = function()
        refreshDropdown()
        notify("Daftar pemain diperbarui.")
    end
})

---------------------------------------------------------------------
--      Save & Teleport Pos
---------------------------------------------------------------------

local savedSlots = { nil, nil, nil, nil, nil }
local selectedSlot = 1
local function getHRP()
    local character = player.Character or player.CharacterAdded:Wait()
    return character:WaitForChild("HumanoidRootPart")
end
local function saveSlot(slotIndex)
    local hrp = getHRP()
    savedSlots[slotIndex] = hrp.Position
    notify(("Posisi tersimpan di Slot %d."):format(slotIndex))
end
local function teleportSlot(slotIndex)
    if savedSlots[slotIndex] then
        getHRP().CFrame = CFrame.new(savedSlots[slotIndex])
        notify(("Teleport ke Slot %d."):format(slotIndex))
    else
        notify(("Slot %d kosong."):format(slotIndex))
    end
end
local function clearSlot(slotIndex)
    savedSlots[slotIndex] = nil
    notify(("Slot %d dibersihkan."):format(slotIndex))
end
local function clearAllSlots()
    for i = 1, 5 do savedSlots[i] = nil end
    notify("Semua slot dibersihkan.")
end

TeleportTab:CreateSection("Save & Teleport Pos")
TeleportTab:CreateDropdown({
    Name = "Pilih Slot",
    Options = {"1","2","3","4","5"},
    CurrentOption = {"1"},
    MultipleOptions = false,
    Flag = "SlotDropdown",
    Callback = function(option)
        selectedSlot = tonumber(option[1] or option) or 1
    end
})
TeleportTab:CreateButton({ Name = "Save Pos", Callback = function() saveSlot(selectedSlot) end })
TeleportTab:CreateButton({ Name = "Teleport Pos", Callback = function() teleportSlot(selectedSlot) end })
TeleportTab:CreateButton({ Name = "Clear Slot", Callback = function() clearSlot(selectedSlot) end })
TeleportTab:CreateButton({ Name = "Clear All Slots", Callback = function() clearAllSlots() end })

---------------------------------------------------------------------
--                           TAB MISC (Spectate)
---------------------------------------------------------------------

local MiscTab = Window:CreateTab("Misc", 4483362458)
MiscTab:CreateSection("Spectate Player")

local spectateTarget
local viewDiedConn, viewChangedConn

local SpectateDropdown = MiscTab:CreateDropdown({
    Name = "Pilih Pemain",
    Options = getOtherPlayerNames(),
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "SpectateDropdown",
    Callback = function(option)
        if typeof(option) == "table" then
            spectateTarget = option[1]
        else
            spectateTarget = option
        end
    end,
})

Players.PlayerAdded:Connect(function()
    SpectateDropdown:Refresh(getOtherPlayerNames(), true)
end)
Players.PlayerRemoving:Connect(function()
    SpectateDropdown:Refresh(getOtherPlayerNames(), true)
end)

MiscTab:CreateButton({
    Name = "Mulai Spectate",
    Callback = function()
        if not spectateTarget then
            notify("Pilih pemain terlebih dahulu.")
            return
        end
        local target = Players:FindFirstChild(spectateTarget)
        if not target or not target.Character then
            notify("Pemain tidak valid atau belum spawn.")
            return
        end

        workspace.CurrentCamera.CameraSubject = target.Character

        if viewDiedConn then viewDiedConn:Disconnect() end
        if viewChangedConn then viewChangedConn:Disconnect() end

        viewDiedConn = target.CharacterAdded:Connect(function()
            repeat task.wait() until target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            workspace.CurrentCamera.CameraSubject = target.Character
        end)
        viewChangedConn = workspace.CurrentCamera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
            workspace.CurrentCamera.CameraSubject = target.Character
        end)

        notify("Spectating: " .. spectateTarget)
    end
})

MiscTab:CreateButton({
    Name = "Berhenti Spectate",
    Callback = function()
        if viewDiedConn then viewDiedConn:Disconnect() end
        if viewChangedConn then viewChangedConn:Disconnect() end
        workspace.CurrentCamera.CameraSubject = getHumanoid()
        notify("Spectate dihentikan.")
    end
})
