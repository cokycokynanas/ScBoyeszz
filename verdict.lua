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
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

-- General state
local lastPlace = nil
local conns = {} -- store active connections
local windows = {} -- refs for created UI elements (Window/Tabs)
local flags = {} -- feature flags
local originalLighting = {}
local customSpeed = 16
local originalGravity = Workspace.Gravity or 196.2 -- Simpan gravitasi asli

-- UI Controls & Config Database state
local UIControls = {
    Toggles = {},
    Sliders = {},
    Dropdowns = {}
}
local savedSlots = {}
for i = 1, 30 do savedSlots[i] = nil end
local quickSavedCFrames = {}
local floatingTPWidgets = {}
local createFloatingTPWidget = nil

-- Helpers for Notifications
local function sendNotification(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title or "⚡ Boyesz Tonz",
            Text = text or "",
            Duration = duration or 3
        })
    end)
end

-- Serialization helpers for Vector3 & CFrame (Roblox userdata cannot be directly JSON encoded)
local function serializeVector3(v)
    if typeof(v) == "Vector3" then
        return { x = v.X, y = v.Y, z = v.Z }
    end
    return nil
end

local function deserializeVector3(t)
    if type(t) == "table" and t.x and t.y and t.z then
        return Vector3.new(t.x, t.y, t.z)
    end
    return nil
end

local function serializeCFrame(cf)
    if typeof(cf) == "CFrame" then
        return { cf:GetComponents() }
    end
    return nil
end

local function deserializeCFrame(t)
    if type(t) == "table" and #t == 12 then
        return CFrame.new(unpack(t))
    end
    return nil
end

-- Config Database Manager
local ConfigManager = {
    Folder = "BoyeszTonz_Config",
    AutoLoadFile = "BoyeszTonz_Config/autoload.txt"
}
local inMemoryConfigs = {}
local hasFileSystem = (writefile and readfile and isfile and isfolder and makefolder) and true or false

function ConfigManager:EnsureFolder()
    if hasFileSystem and not isfolder(self.Folder) then
        pcall(function() makefolder(self.Folder) end)
    end
end

function ConfigManager:GetConfigs()
    local list = {}
    if hasFileSystem and listfiles then
        pcall(function()
            self:EnsureFolder()
            local files = listfiles(self.Folder)
            for _, path in ipairs(files) do
                local clean = path:gsub("\\", "/")
                local name = clean:match("([^/]+)%.json$")
                if name then
                    table.insert(list, name)
                end
            end
        end)
    else
        for name, _ in pairs(inMemoryConfigs) do
            table.insert(list, name)
        end
    end
    if #list == 0 then
        table.insert(list, "default")
    end
    table.sort(list)
    return list
end

function ConfigManager:GetAutoLoadConfig()
    if hasFileSystem and isfile(self.AutoLoadFile) then
        local ok, content = pcall(readfile, self.AutoLoadFile)
        if ok and content and content ~= "" then
            return content:gsub("%s+", "")
        end
    end
    return nil
end

function ConfigManager:SetAutoLoad(enabled, configName)
    self:EnsureFolder()
    if hasFileSystem then
        if enabled and configName and configName ~= "" then
            pcall(writefile, self.AutoLoadFile, tostring(configName))
        else
            if isfile(self.AutoLoadFile) then
                pcall(function()
                    if delfile then
                        delfile(self.AutoLoadFile)
                    else
                        writefile(self.AutoLoadFile, "")
                    end
                end)
            end
        end
    end
end

function ConfigManager:Save(configName)
    configName = (configName and configName ~= "") and configName or "default"
    self:EnsureFolder()

    local data = {
        meta = {
            name = configName,
            version = "2.0",
            placeId = game.PlaceId,
            time = os.date and os.date("%Y-%m-%d %H:%M:%S") or "N/A"
        },
        toggles = {},
        sliders = {},
        teleport = {
            savedSlots = {},
            quickTP = {}
        }
    }

    -- 1. Save UI Toggles
    for name, toggleObj in pairs(UIControls.Toggles) do
        if toggleObj and toggleObj.CurrentValue ~= nil then
            data.toggles[name] = toggleObj.CurrentValue
        end
    end

    -- 2. Save UI Sliders
    for name, sliderObj in pairs(UIControls.Sliders) do
        if sliderObj and sliderObj.CurrentValue ~= nil then
            data.sliders[name] = sliderObj.CurrentValue
        end
    end

    -- 3. Save Teleport Positions (Slots 1 - 30)
    for i = 1, 30 do
        if savedSlots[i] then
            data.teleport.savedSlots[tostring(i)] = serializeVector3(savedSlots[i])
        end
    end

    -- 4. Save Quick Floating TP (Slots 1 - 10)
    for i = 1, 10 do
        local isOpen = (floatingTPWidgets[i] ~= nil)
        local cfData = quickSavedCFrames[i] and serializeCFrame(quickSavedCFrames[i]) or nil
        if isOpen or cfData then
            data.teleport.quickTP[tostring(i)] = {
                isOpen = isOpen,
                cframe = cfData
            }
        end
    end

    local jsonStr = HttpService:JSONEncode(data)
    if hasFileSystem then
        local filePath = self.Folder .. "/" .. configName .. ".json"
        local ok, err = pcall(writefile, filePath, jsonStr)
        if not ok then
            warn("[Boyesz Tonz Config] Writefile failed: " .. tostring(err))
            sendNotification("❌ Error Save", "Gagal menyimpan file ke executor!", 3)
            return false, "Gagal menulis file: " .. tostring(err)
        end
    else
        inMemoryConfigs[configName] = jsonStr
    end

    sendNotification("💾 Config Tersimpan", "Config '" .. configName .. "' berhasil disimpan!", 3)
    return true, "Config berhasil disimpan!"
end

function ConfigManager:Load(configName)
    configName = (configName and configName ~= "") and configName or "default"
    local jsonStr = nil

    if hasFileSystem then
        local filePath = self.Folder .. "/" .. configName .. ".json"
        if not isfile(filePath) then
            sendNotification("❌ Config Error", "Config '" .. configName .. "' tidak ditemukan!", 3)
            return false, "Config tidak ditemukan!"
        end
        local ok, res = pcall(readfile, filePath)
        if not ok or not res then
            sendNotification("❌ Config Error", "Gagal membaca file config!", 3)
            return false, "Gagal membaca file!"
        end
        jsonStr = res
    else
        jsonStr = inMemoryConfigs[configName]
        if not jsonStr then
            sendNotification("❌ Config Error", "Config '" .. configName .. "' tidak ada di memory!", 3)
            return false, "Config tidak ditemukan!"
        end
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(jsonStr)
    end)

    if not ok or type(data) ~= "table" then
        sendNotification("❌ Config Error", "Format data JSON rusak!", 3)
        return false, "Format JSON rusak!"
    end

    -- 1. Restore Teleport Position Slots (1 - 30)
    if data.teleport and data.teleport.savedSlots then
        for i = 1, 30 do
            local posData = data.teleport.savedSlots[tostring(i)]
            if posData then
                savedSlots[i] = deserializeVector3(posData)
            else
                savedSlots[i] = nil
            end
        end
    end

    -- 2. Restore Quick Floating TP (1 - 10)
    if data.teleport and data.teleport.quickTP then
        for i = 1, 10 do
            local tpData = data.teleport.quickTP[tostring(i)]
            if tpData then
                if tpData.cframe then
                    quickSavedCFrames[i] = deserializeCFrame(tpData.cframe)
                end
                if tpData.isOpen then
                    if UIControls.Toggles["WidgetSlot_" .. i] then
                        pcall(function() UIControls.Toggles["WidgetSlot_" .. i]:Set(true) end)
                    elseif createFloatingTPWidget then
                        createFloatingTPWidget(i)
                    end
                else
                    if UIControls.Toggles["WidgetSlot_" .. i] then
                        pcall(function() UIControls.Toggles["WidgetSlot_" .. i]:Set(false) end)
                    elseif floatingTPWidgets[i] then
                        floatingTPWidgets[i]:Destroy()
                        floatingTPWidgets[i] = nil
                    end
                end
            end
        end
    end

    -- 3. Restore Sliders
    if data.sliders then
        for name, val in pairs(data.sliders) do
            local sliderObj = UIControls.Sliders[name]
            if sliderObj and sliderObj.Set then
                pcall(function() sliderObj:Set(val) end)
            end
        end
    end

    -- 4. Restore Toggles (This triggers callbacks and turns on features!)
    if data.toggles then
        for name, val in pairs(data.toggles) do
            local toggleObj = UIControls.Toggles[name]
            if toggleObj and toggleObj.Set then
                pcall(function() toggleObj:Set(val) end)
            end
        end
    end

    sendNotification("📂 Config Dimuat", "Config '" .. configName .. "' dimuat & fitur diaktifkan!", 3)
    return true, "Config berhasil dimuat!"
end

function ConfigManager:Delete(configName)
    configName = (configName and configName ~= "") and configName or "default"
    if hasFileSystem then
        local filePath = self.Folder .. "/" .. configName .. ".json"
        if isfile(filePath) then
            pcall(function()
                if delfile then delfile(filePath) else writefile(filePath, "") end
            end)
            sendNotification("🗑 Config Dihapus", "File '" .. configName .. "' telah dihapus!", 3)
            return true
        end
    else
        inMemoryConfigs[configName] = nil
        sendNotification("🗑 Config Dihapus", "Config '" .. configName .. "' dihapus dari memory!", 3)
        return true
    end
    sendNotification("❌ Config Error", "Config '" .. configName .. "' tidak ditemukan!", 3)
    return false
end

function ConfigManager:CheckAutoLoad()
    local target = self:GetAutoLoadConfig()
    if target and target ~= "" then
        print("[Boyesz Tonz Config] Auto-loading config: " .. target)
        task.wait(0.5)
        self:Load(target)
    end
end

-- Aimbot/Killaura state
local aimbotTarget = nil
local selectedAimbotPlayerName = nil -- NEW: Nama pemain yang dipilih untuk Aimbot
local aimbotRange = 150 -- NEW: Jarak Aimbot
local selectedAimbotPart = "Head" -- MODIFIED: Default target Head
local hitboxMultipler = 1 -- Multiplier untuk hitbox
local originalSizeData = {} -- NEW: Dipindahkan ke global agar fungsi bisa diakses dari mana saja
local killAuraRange = 25 -- Jarak Kill Aura
local killAuraDelay = 0.5 -- Delay antar serangan Kill Aura

-- Combat & Troll Extended State
local selectedFlingPlayerName = nil
local spinBotSpeed = 30
local autoClickDelay = 0.05
local fovCircleDrawing = nil
local fovCircleGui = nil

-- Tween Teleport & Dev Tools State
local activeTweenTeleport = nil
local tweenTeleportSpeed = 150
local clickToDeleteEnabled = false

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

-- FOV Circle Functions (Drawing API + ScreenGui Fallback)
local function updateFOVCircle()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local radius = tonumber(aimbotRange) or 150

    if Drawing then
        if not fovCircleDrawing then
            local ok, d = pcall(function()
                return Drawing.new("Circle")
            end)
            if ok and d then
                fovCircleDrawing = d
                fovCircleDrawing.Thickness = 1.5
                fovCircleDrawing.Color = Color3.fromRGB(0, 200, 255)
                fovCircleDrawing.Filled = false
                fovCircleDrawing.Transparency = 0.8
            end
        end
        if fovCircleDrawing then
            fovCircleDrawing.Visible = flags.showFOV or false
            fovCircleDrawing.Radius = radius
            fovCircleDrawing.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
            return
        end
    end

    -- Fallback ScreenGui for Mobile / Non-Drawing Executors
    local parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui", 5)
    if parent and (not fovCircleGui or not fovCircleGui.Parent) then
        local gui = Instance.new("ScreenGui")
        gui.Name = "BoyeszAimbotFOV_Gui"
        gui.ResetOnSpawn = false
        gui.Parent = parent

        local frame = Instance.new("Frame")
        frame.Name = "CircleFrame"
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.Position = UDim2.new(0.5, 0, 0.5, 0)
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 200, 255)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.25
        stroke.Parent = frame

        fovCircleGui = gui
    end

    if fovCircleGui then
        local frame = fovCircleGui:FindFirstChild("CircleFrame")
        if frame then
            frame.Visible = flags.showFOV or false
            frame.Size = UDim2.new(0, radius * 2, 0, radius * 2)
        end
    end
end

local function setFOVCircle(enabled)
    flags.showFOV = enabled
    clearConn("fovCircleConn")
    if enabled then
        updateFOVCircle()
        setConn("fovCircleConn", RunService.RenderStepped:Connect(function()
            if flags.showFOV then
                updateFOVCircle()
            end
        end))
    else
        if fovCircleDrawing then
            pcall(function() fovCircleDrawing.Visible = false end)
        end
        if fovCircleGui then
            local frame = fovCircleGui:FindFirstChild("CircleFrame")
            if frame then frame.Visible = false end
        end
    end
end

-- SpinBot / Anti-Aim Function
local function setSpinBot(enabled)
    flags.spinBot = enabled
    clearConn("spinBotLoop")
    local hum = getHumanoid()
    if hum then
        hum.AutoRotate = not enabled
    end
    if enabled then
        setConn("spinBotLoop", RunService.RenderStepped:Connect(function()
            local hrp = getHRP()
            if hrp and flags.spinBot then
                local speed = tonumber(spinBotSpeed) or 30
                hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(speed), 0)
            end
        end))
    else
        if hum then
            hum.AutoRotate = true
        end
    end
end

-- Auto-Clicker / Fast Attack Function
local function setAutoClicker(enabled)
    flags.autoClicker = enabled
    clearConn("autoClickerLoop")
    if enabled then
        task.spawn(function()
            local vu = game:GetService("VirtualUser")
            while flags.autoClicker do
                -- 1. Activate tool if equipped
                local char = getCharacter()
                local tool = char and char:FindFirstChildOfClass("Tool")
                if tool then
                    pcall(function() tool:Activate() end)
                end
                -- 2. Virtual click (Mobile & PC)
                pcall(function()
                    vu:CaptureController()
                    vu:Button1Down(Vector2.new(0, 0))
                    task.wait(0.01)
                    vu:Button1Up(Vector2.new(0, 0))
                end)
                -- 3. Executor native mouse click
                if mouse1click then
                    pcall(mouse1click)
                end
                local delayTime = tonumber(autoClickDelay) or 0.05
                task.wait(math.max(delayTime, 0.01))
            end
        end)
    end
end

-- Universal Fling Function
local function flingTargetPlayer(targetName, isLoop)
    if not targetName or targetName == "" then return end
    local targetPlr = Players:FindFirstChild(targetName)
    if not targetPlr or not targetPlr.Character then return end
    local targetHRP = targetPlr.Character:FindFirstChild("HumanoidRootPart")
    local myHRP = getHRP()
    local myChar = getCharacter()
    local hum = getHumanoid()
    if not targetHRP or not myHRP or not hum or not myChar then return end

    local oldPos = myHRP.CFrame
    local startTime = tick()
    local originalCanCollide = {}

    pcall(function()
        for _, part in ipairs(myChar:GetChildren()) do
            if part:IsA("BasePart") then
                originalCanCollide[part] = part.CanCollide
                part.CanCollide = false
            end
        end
    end)

    task.spawn(function()
        while (isLoop and flags.flingLoop) or (not isLoop and (tick() - startTime < 1.5)) do
            if not targetPlr.Parent or not targetPlr.Character or not targetHRP.Parent or hum.Health <= 0 then
                break
            end
            local targetPos = targetHRP.Position
            myHRP.CFrame = CFrame.new(targetPos + Vector3.new(math.random(-1, 1)/10, 0, math.random(-1, 1)/10))
            myHRP.Velocity = Vector3.new(0, 10000, 0)
            myHRP.RotVelocity = Vector3.new(99999, 99999, 99999)
            task.wait(0.02)
        end

        pcall(function()
            myHRP.Velocity = Vector3.zero
            myHRP.RotVelocity = Vector3.zero
            for part, canCollide in pairs(originalCanCollide) do
                if part and part.Parent then
                    part.CanCollide = canCollide
                end
            end
            myHRP.CFrame = oldPos
        end)
    end)
end

local function flingAllPlayers()
    local myHRP = getHRP()
    if not myHRP then return end
    local originalPos = myHRP.CFrame
    task.spawn(function()
        sendNotification("🌪️ Fling All", "Memulai melempar semua pemain...", 2)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Character:FindFirstChildOfClass("Humanoid") and p.Character:FindFirstChildOfClass("Humanoid").Health > 0 then
                flingTargetPlayer(p.Name, false)
                task.wait(0.7)
            end
        end
        myHRP.CFrame = originalPos
        sendNotification("🌪️ Fling All", "Selesai melempar semua pemain!", 2)
    end)
end

-- ==========================================================
-- TWEEN TELEPORT (Bypass Anti-Cheat Teleport)
-- ==========================================================
local function cancelTweenTeleport()
    if activeTweenTeleport then
        pcall(function()
            activeTweenTeleport:Cancel()
        end)
        activeTweenTeleport = nil
        sendNotification("🚀 Tween Teleport", "Tween Teleport dihentikan / dibatalkan.", 2)
    end
end

local function startTweenTeleport(targetCFrame)
    local hrp = getHRP()
    if not hrp then
        sendNotification("🚀 Tween Teleport", "Karakter tidak ditemukan!", 2)
        return
    end
    if not targetCFrame then
        sendNotification("🚀 Tween Teleport", "Tujuan teleport tidak valid!", 2)
        return
    end

    if activeTweenTeleport then
        cancelTweenTeleport()
    end

    local distance = (targetCFrame.Position - hrp.Position).Magnitude
    local speed = math.clamp(tweenTeleportSpeed or 150, 20, 1000)
    local duration = distance / speed

    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out
    )

    local tween = TweenService:Create(hrp, tweenInfo, { CFrame = targetCFrame })
    activeTweenTeleport = tween

    tween.Completed:Connect(function(playbackState)
        if activeTweenTeleport == tween then
            activeTweenTeleport = nil
            if playbackState == Enum.PlaybackState.Completed then
                sendNotification("🚀 Tween Teleport", "Berhasil sampai di tujuan!", 2)
            end
        end
    end)

    tween:Play()
    sendNotification("🚀 Tween Teleport", string.format("Meluncur... (%.1f dtk, %.0f studs/s)", duration, speed), 2)
end

-- ==========================================================
-- CLIENT-SIDE BTOOL (Delete Part / Wall Remover)
-- ==========================================================
local function giveBTool()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then
        sendNotification("🔨 BTool", "Backpack tidak ditemukan!", 2)
        return
    end

    local existingTool = backpack:FindFirstChild("DeletePartTool") or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("DeletePartTool"))
    if existingTool then
        existingTool:Destroy()
    end

    local tool = Instance.new("Tool")
    tool.Name = "DeletePartTool"
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool.ToolTip = "Klik pada Part untuk menghapusnya (Client-Side)"

    tool.Activated:Connect(function()
        local mouse = LocalPlayer:GetMouse()
        if mouse and mouse.Target then
            local target = mouse.Target
            if LocalPlayer.Character and target:IsDescendantOf(LocalPlayer.Character) then
                return
            end
            local partName = target.Name
            pcall(function()
                target:Destroy()
            end)
            sendNotification("🔨 BTool", "Dihapus: " .. tostring(partName), 1.5)
        end
    end)

    tool.Parent = backpack
    sendNotification("🔨 BTool", "Delete Tool berhasil ditambahkan ke Backpack!", 3)
end

local function setClickToDelete(enabled)
    clickToDeleteEnabled = enabled
    clearConn("clickToDeleteConn")
    if enabled then
        local mouse = LocalPlayer:GetMouse()
        if not mouse then return end
        local conn = mouse.Button1Down:Connect(function()
            if not clickToDeleteEnabled then return end
            if UserInputService:GetFocusedTextBox() then return end
            local target = mouse.Target
            if target and target:IsA("BasePart") then
                if LocalPlayer.Character and target:IsDescendantOf(LocalPlayer.Character) then
                    return
                end
                local partName = target.Name
                pcall(function()
                    target:Destroy()
                end)
                sendNotification("🖱️ Click Delete", "Dihapus: " .. tostring(partName), 1)
            end
        end)
        setConn("clickToDeleteConn", conn)
        sendNotification("🖱️ Click Delete", "Mode Klik Hapus Part DIAKTIFKAN", 2)
    else
        sendNotification("🖱️ Click Delete", "Mode Klik Hapus Part DIMATIKAN", 2)
    end
end

-- ==========================================================
-- DEVELOPER TOOLS LOADERS (Dark Dex, SimpleSpy, Infinite Yield)
-- ==========================================================
local function loadDarkDex()
    sendNotification("📱 Dark Dex", "Sedang memuat Dark Dex Explorer...", 3)
    task.spawn(function()
        local success, err = pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua"))()
        end)
        if not success then
            local success2, _ = pcall(function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/dex.lua"))()
            end)
            if not success2 then
                sendNotification("❌ Dark Dex Gagal", tostring(err), 4)
            end
        end
    end)
end

local function loadSimpleSpy()
    sendNotification("🕵️ SimpleSpy", "Sedang memuat SimpleSpy Remote Logger...", 3)
    task.spawn(function()
        local success, err = pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/SimpleSpyV3/main.lua"))()
        end)
        if not success then
            local success2, _ = pcall(function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua"))()
            end)
            if not success2 then
                sendNotification("❌ SimpleSpy Gagal", tostring(err), 4)
            end
        end
    end)
end

local function loadInfiniteYield()
    sendNotification("⚡ Infinite Yield", "Sedang memuat Infinite Yield Admin...", 3)
    task.spawn(function()
        local success, err = pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
        end)
        if not success then
            sendNotification("❌ Infinite Yield Gagal", tostring(err), 4)
        end
    end)
end

-- Anti-Fling Function
local function setAntiFling(enabled)
    flags.antiFling = enabled
    clearConn("antiFlingStepped")
    if enabled then
        setConn("antiFlingStepped", RunService.Stepped:Connect(function()
            if not flags.antiFling then return end
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    for _, part in ipairs(player.Character:GetChildren()) do
                        if part:IsA("BasePart") then
                            pcall(function()
                                part.CanCollide = false
                                part.Velocity = Vector3.zero
                                part.RotVelocity = Vector3.zero
                            end)
                        end
                    end
                end
            end
        end))
    end
end

-- Anti-Stun & Anti-Ragdoll Function
local function setAntiStun(enabled)
    flags.antiStun = enabled
    clearConn("antiStunHeartbeat")
    if enabled then
        setConn("antiStunHeartbeat", RunService.Heartbeat:Connect(function()
            if not flags.antiStun then return end
            local hum = getHumanoid()
            if hum then
                if hum.PlatformStand then hum.PlatformStand = false end
                if hum.Sit then hum.Sit = false end
                local state = hum:GetState()
                if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end))
    end
end

-- Anti-Slap Function
local function setAntiSlap(enabled)
    flags.antiSlap = enabled
    clearConn("antiSlapHeartbeat")
    if enabled then
        local physicsStep = RunService.PreSimulation or RunService.Heartbeat
        setConn("antiSlapHeartbeat", physicsStep:Connect(function()
            if not flags.antiSlap then return end

            local char = getCharacter()
            local hum = getHumanoid()
            local hrp = getHRP()
            if not char or not hum or not hrp or hum.Health <= 0 then return end

            local velocity = hrp.AssemblyLinearVelocity
            local moveDirection = hum.MoveDirection
            local targetVelocity = moveDirection.Magnitude > 0
                and moveDirection.Unit * hum.WalkSpeed
                or Vector3.zero
            local state = hum:GetState()
            local airborne = state == Enum.HumanoidStateType.Jumping
                or state == Enum.HumanoidStateType.Freefall
                or state == Enum.HumanoidStateType.FallingDown
            local verticalVelocity = airborne and math.clamp(velocity.Y, -50, 50) or 0

            hrp.AssemblyLinearVelocity = Vector3.new(
                targetVelocity.X,
                verticalVelocity,
                targetVelocity.Z
            )
            hrp.AssemblyAngularVelocity = Vector3.zero
        end))
    end
end

-- FPS & Ping HUD Overlay Function
local fpsPingGui = nil
local function setFpsPingHUD(enabled)
    flags.fpsPingHUD = enabled
    if enabled then
        if fpsPingGui then pcall(function() fpsPingGui:Destroy() end) end
        local gui = Instance.new("ScreenGui")
        gui.Name = "BoyeszFpsPingHUD"
        gui.ResetOnSpawn = false
        gui.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 160, 0, 32)
        frame.Position = UDim2.new(1, -170, 0, 12)
        frame.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
        frame.BackgroundTransparency = 0.25
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true
        frame.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 170, 255)
        stroke.Thickness = 1.2
        stroke.Transparency = 0.3
        stroke.Parent = frame

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 11
        label.Text = "⚡ FPS: -- | Ping: --ms"
        label.Parent = frame

        fpsPingGui = gui

        task.spawn(function()
            local lastUpdate = tick()
            local frameCount = 0
            local fps = 60
            while flags.fpsPingHUD and fpsPingGui and fpsPingGui.Parent do
                frameCount = frameCount + 1
                local now = tick()
                if now - lastUpdate >= 0.5 then
                    fps = math.floor(frameCount / (now - lastUpdate))
                    frameCount = 0
                    lastUpdate = now
                    local ping = 0
                    pcall(function()
                        if Stats and Stats.Network and Stats.Network.ServerStatsItem and Stats.Network.ServerStatsItem["Data Ping"] then
                            ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
                        end
                    end)
                    if label and label.Parent then
                        label.Text = string.format("⚡ FPS: %d | Ping: %dms", fps, ping)
                    end
                end
                task.wait(0.03)
            end
        end)
    else
        if fpsPingGui then
            pcall(function() fpsPingGui:Destroy() end)
            fpsPingGui = nil
        end
    end
end

-- Custom Crosshair Function
local crosshairGui = nil
local function setCustomCrosshair(enabled)
    flags.customCrosshair = enabled
    if enabled then
        if crosshairGui then pcall(function() crosshairGui:Destroy() end) end
        local gui = Instance.new("ScreenGui")
        gui.Name = "BoyeszCrosshair"
        gui.ResetOnSpawn = false
        gui.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

        local center = Instance.new("Frame")
        center.Size = UDim2.new(0, 4, 0, 4)
        center.Position = UDim2.new(0.5, -2, 0.5, -2)
        center.BackgroundColor3 = Color3.fromRGB(0, 255, 200)
        center.BorderSizePixel = 0
        center.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = center

        local top = Instance.new("Frame")
        top.Size = UDim2.new(0, 2, 0, 8)
        top.Position = UDim2.new(0.5, -1, 0.5, -12)
        top.BackgroundColor3 = Color3.fromRGB(0, 255, 200)
        top.BorderSizePixel = 0
        top.Parent = gui

        local bottom = Instance.new("Frame")
        bottom.Size = UDim2.new(0, 2, 0, 8)
        bottom.Position = UDim2.new(0.5, -1, 0.5, 4)
        bottom.BackgroundColor3 = Color3.fromRGB(0, 255, 200)
        bottom.BorderSizePixel = 0
        bottom.Parent = gui

        local left = Instance.new("Frame")
        left.Size = UDim2.new(0, 8, 0, 2)
        left.Position = UDim2.new(0.5, -12, 0.5, -1)
        left.BackgroundColor3 = Color3.fromRGB(0, 255, 200)
        left.BorderSizePixel = 0
        left.Parent = gui

        local right = Instance.new("Frame")
        right.Size = UDim2.new(0, 8, 0, 2)
        right.Position = UDim2.new(0.5, 4, 0.5, -1)
        right.BackgroundColor3 = Color3.fromRGB(0, 255, 200)
        right.BorderSizePixel = 0
        right.Parent = gui

        crosshairGui = gui
    else
        if crosshairGui then
            pcall(function() crosshairGui:Destroy() end)
            crosshairGui = nil
        end
    end
end

-- Universal Shiftlock Function
local shiftlockGui = nil
local shiftlockConn = nil

local function setShiftlock(enabled)
    flags.shiftlock = enabled
    if shiftlockConn then shiftlockConn:Disconnect() shiftlockConn = nil end

    if enabled then
        pcall(function()
            LocalPlayer.DevEnableMouseLock = true
        end)

        if not shiftlockGui then
            local gui = Instance.new("ScreenGui")
            gui.Name = "BoyeszShiftlock"
            gui.ResetOnSpawn = false
            gui.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

            local btn = Instance.new("TextButton")
            btn.Name = "ShiftlockBtn"
            btn.Size = UDim2.new(0, 56, 0, 56)
            btn.Position = UDim2.new(0.85, -28, 0.55, -28)
            btn.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
            btn.BackgroundTransparency = 0.2
            btn.Text = "🔒 OFF"
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 11
            btn.Active = true
            btn.Draggable = true
            btn.Parent = gui

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = btn

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(0, 170, 255)
            stroke.Thickness = 1.5
            stroke.Parent = btn

            local isActive = false
            btn.MouseButton1Click:Connect(function()
                isActive = not isActive
                if isActive then
                    btn.Text = "🔒 ON"
                    btn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
                else
                    btn.Text = "🔒 OFF"
                    btn.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
                end
            end)

            shiftlockConn = RunService.RenderStepped:Connect(function()
                if flags.shiftlock and isActive then
                    local char = getCharacter()
                    local hum = getHumanoid()
                    if char and hum and Workspace.CurrentCamera then
                        local lookVector = Workspace.CurrentCamera.CFrame.LookVector
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + Vector3.new(lookVector.X, 0, lookVector.Z))
                        end
                    end
                end
            end)

            shiftlockGui = gui
        end
    else
        if shiftlockConn then shiftlockConn:Disconnect() shiftlockConn = nil end
        if shiftlockGui then
            pcall(function() shiftlockGui:Destroy() end)
            shiftlockGui = nil
        end
    end
end

-- Air Walk Function
local airWalkPart = nil
local function setAirWalk(enabled)
    flags.airWalk = enabled
    clearConn("airWalkHeartbeat")
    if enabled then
        if not airWalkPart or not airWalkPart.Parent then
            local part = Instance.new("Part")
            part.Name = "BoyeszAirWalkPart"
            part.Size = Vector3.new(6, 1, 6)
            part.Transparency = 0.6
            part.Color = Color3.fromRGB(0, 200, 255)
            part.Material = Enum.Material.Neon
            part.Anchored = true
            part.CanCollide = true
            part.Parent = Workspace
            airWalkPart = part
        end

        setConn("airWalkHeartbeat", RunService.Heartbeat:Connect(function()
            if not flags.airWalk or not airWalkPart then return end
            local hrp = getHRP()
            if hrp then
                airWalkPart.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y - 3.5, hrp.Position.Z)
            end
        end))
    else
        clearConn("airWalkHeartbeat")
        if airWalkPart then
            pcall(function() airWalkPart:Destroy() end)
            airWalkPart = nil
        end
    end
end

-- Bypass Speed Hack System (3 Advanced Modes)
local bypassMode = "LinearVelocity" -- "LinearVelocity", "Tween", "CFrame"
local bypassSpeedMultiplier = 2.0
local linearVelocityObj = nil
local attachmentObj = nil

local function cleanupBypassPhysics()
    if linearVelocityObj then
        pcall(function() linearVelocityObj:Destroy() end)
        linearVelocityObj = nil
    end
    if attachmentObj then
        pcall(function() attachmentObj:Destroy() end)
        attachmentObj = nil
    end
end

local function setBypassSpeed(enabled)
    flags.bypassSpeed = enabled
    clearConn("bypassSpeedLoop")
    cleanupBypassPhysics()

    if enabled then
        setConn("bypassSpeedLoop", RunService.Heartbeat:Connect(function(deltaTime)
            if not flags.bypassSpeed then return end
            local char = getCharacter()
            local hum = getHumanoid()
            local hrp = getHRP()
            if not char or not hum or not hrp or hum.Health <= 0 then
                cleanupBypassPhysics()
                return
            end

            if hum.MoveDirection.Magnitude > 0 then
                if bypassMode == "LinearVelocity" then
                    -- Method A: Roblox Native LinearVelocity Object (Bypasses Distance Delta Check)
                    if not attachmentObj or attachmentObj.Parent ~= hrp then
                        cleanupBypassPhysics()
                        attachmentObj = Instance.new("Attachment")
                        attachmentObj.Name = "BoyeszSpeedAttachment"
                        attachmentObj.Parent = hrp

                        linearVelocityObj = Instance.new("LinearVelocity")
                        linearVelocityObj.Name = "BoyeszSpeedLinearVelocity"
                        linearVelocityObj.Attachment0 = attachmentObj
                        linearVelocityObj.MaxForce = 99999
                        linearVelocityObj.VectorVelocity = Vector3.zero
                        linearVelocityObj.RelativeTo = Enum.ActuatorRelativeTo.World
                        linearVelocityObj.Parent = hrp
                    end

                    local targetSpeed = 16 * bypassSpeedMultiplier
                    local moveDir = hum.MoveDirection
                    linearVelocityObj.VectorVelocity = Vector3.new(moveDir.X * targetSpeed, hrp.AssemblyLinearVelocity.Y, moveDir.Z * targetSpeed)

                elseif bypassMode == "Tween" then
                    -- Method B: Smooth Tween Step (Bypasses Teleport Spike Detectors)
                    cleanupBypassPhysics()
                    local extraSpeed = (bypassSpeedMultiplier - 1) * 16
                    local targetPos = hrp.Position + (hum.MoveDirection * (extraSpeed * deltaTime))
                    local tween = game:GetService("TweenService"):Create(hrp, TweenInfo.new(deltaTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPos, targetPos + hrp.CFrame.LookVector)})
                    tween:Play()

                elseif bypassMode == "CFrame" then
                    -- Method C: Direct Velocity Pulse
                    cleanupBypassPhysics()
                    local targetSpeed = 16 * bypassSpeedMultiplier
                    local moveDir = hum.MoveDirection
                    hrp.AssemblyLinearVelocity = Vector3.new(moveDir.X * targetSpeed, hrp.AssemblyLinearVelocity.Y, moveDir.Z * targetSpeed)
                end
            else
                if linearVelocityObj then
                    linearVelocityObj.VectorVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
                end
            end
        end))
    else
        cleanupBypassPhysics()
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
        warn("[Boyesz Tonz] Failed to load Rayfield UI library")
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

    -- 1. MAIN TAB (Karakter & Fisik)
    local Main = Window:CreateTab("Main", "shield")
    windows.Main = Main

    Main:CreateSection("Karakter & Fisik")

    UIControls.Toggles["GodMode"] = Main:CreateToggle({
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

    UIControls.Toggles["GhostMode"] = Main:CreateToggle({
        Name = "Ghost Mode",
        CurrentValue = false,
        Callback = setGhostMode
    })

    UIControls.Toggles["Noclip"] = Main:CreateToggle({
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

    UIControls.Toggles["SpeedHack"] = Main:CreateToggle({
        Name = "Speed Hack (WalkSpeed)",
        CurrentValue = false,
        Callback = function(enabled)
            flags.speedHack = enabled
            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = enabled and customSpeed or 16
            end
        end
    })

    UIControls.Sliders["SpeedValue"] = Main:CreateSlider({
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

    Main:CreateDropdown({
        Name = "Bypass Speed Mode",
        Options = {"LinearVelocity (Physics)", "Tween (Smooth)", "Assembly (Velocity)"},
        CurrentOption = {"LinearVelocity (Physics)"},
        MultipleOptions = false,
        Flag = "BypassSpeedModeDropdown",
        Callback = function(opt)
            local chosen = (typeof(opt) == "table" and opt[1]) or opt
            if chosen:find("LinearVelocity") then
                bypassMode = "LinearVelocity"
            elseif chosen:find("Tween") then
                bypassMode = "Tween"
            else
                bypassMode = "CFrame"
            end
            if flags.bypassSpeed then
                setBypassSpeed(true)
            end
        end
    })

    UIControls.Toggles["BypassSpeed"] = Main:CreateToggle({
        Name = "Bypass Speed Hack (Anti-Detect)",
        CurrentValue = false,
        Callback = setBypassSpeed
    })

    UIControls.Sliders["BypassSpeedMultiplier"] = Main:CreateSlider({
        Name = "Bypass Speed Multiplier",
        Range = {1.2, 10},
        Increment = 0.2,
        Suffix = "x",
        CurrentValue = 2,
        Callback = function(value)
            bypassSpeedMultiplier = value
        end
    })

    UIControls.Toggles["InfiniteJump"] = Main:CreateToggle({
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

    Main:CreateSection("Proteksi Karakter")

    UIControls.Toggles["AntiFling"] = Main:CreateToggle({
        Name = "Anti-Fling Protection",
        CurrentValue = false,
        Callback = setAntiFling
    })

    UIControls.Toggles["AntiSlap"] = Main:CreateToggle({
        Name = "Anti-Slap Protection",
        CurrentValue = false,
        Callback = setAntiSlap
    })

    UIControls.Toggles["AntiStun"] = Main:CreateToggle({
        Name = "Anti-Stun / Anti-Ragdoll",
        CurrentValue = false,
        Callback = setAntiStun
    })


    -- 2. COMBAT TAB (Pertempuran & Aim)
    local CombatTab = Window:CreateTab("Combat", "sword")
    windows.Combat = CombatTab

    CombatTab:CreateSection("Aimbot Lock")

    CombatTab:CreateDropdown({
        Name = "Target Bagian Tubuh",
        Options = {"Head", "Torso", "LeftLeg"},
        CurrentOption = {"Head"},
        MultipleOptions = false,
        Flag = "AimbotPartDropdown",
        Callback = function(option)
            selectedAimbotPart = (typeof(option) == "table" and option[1]) or option
            aimbotTarget = nil
        end,
    })

    local function getAimbotPlayerOptions()
        local options = {""}
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
            aimbotTarget = nil
        end,
    })

    setConn("aimbotPlayerAdd", Players.PlayerAdded:Connect(function()
        pcall(function() AimbotPlayerDropdown:Refresh(getAimbotPlayerOptions(), true) end)
    end))
    setConn("aimbotPlayerRem", Players.PlayerRemoving:Connect(function()
        pcall(function() AimbotPlayerDropdown:Refresh(getAimbotPlayerOptions(), true) end)
    end))

    UIControls.Toggles["AimbotLock"] = CombatTab:CreateToggle({
        Name = "Aimbot Lock",
        CurrentValue = false,
        Callback = function(enabled)
            flags.aimbotLock = enabled
            clearConn("aimbot")
            aimbotTarget = nil
            if enabled then
                setConn("aimbot", RunService.RenderStepped:Connect(doAimbot))
            end
        end
    })

    UIControls.Toggles["ShowFOV"] = CombatTab:CreateToggle({
        Name = "Show FOV Circle",
        CurrentValue = false,
        Callback = setFOVCircle
    })

    UIControls.Sliders["AimbotRange"] = CombatTab:CreateSlider({
        Name = "Aimbot & FOV Range",
        Range = {30, 600},
        Increment = 10,
        Suffix = "studs",
        CurrentValue = 150,
        Callback = function(value)
            aimbotRange = value
            if flags.showFOV then
                updateFOVCircle()
            end
        end
    })

    CombatTab:CreateSection("Hitbox Expander")

    UIControls.Sliders["HitboxMultiplier"] = CombatTab:CreateSlider({
        Name = "Multiplier Value",
        Range = {1, 10},
        Increment = 0.5,
        Suffix = "x",
        CurrentValue = 1,
        Callback = function(value)
            hitboxMultipler = value
            if flags.hitboxExpander then
                setHitbox(true)
            end
        end
    })

    UIControls.Toggles["HitboxExpander"] = CombatTab:CreateToggle({
        Name = "Enable Hitbox",
        CurrentValue = false,
        Callback = setHitbox
    })

    CombatTab:CreateSection("Kill Aura")

    UIControls.Toggles["KillAura"] = CombatTab:CreateToggle({
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

    UIControls.Sliders["KillAuraDelay"] = CombatTab:CreateSlider({
        Name = "Kill Aura Delay",
        Range = {0.1, 5},
        Increment = 0.1,
        Suffix = "s",
        CurrentValue = 0.5,
        Callback = function(value)
            killAuraDelay = value
        end
    })

    CombatTab:CreateSection("SpinBot / Anti-Aim")

    UIControls.Toggles["SpinBot"] = CombatTab:CreateToggle({
        Name = "SpinBot / Anti-Aim (ON / OFF)",
        CurrentValue = false,
        Callback = setSpinBot
    })

    UIControls.Sliders["SpinBotSpeed"] = CombatTab:CreateSlider({
        Name = "SpinBot Speed",
        Range = {5, 100},
        Increment = 5,
        Suffix = "Speed",
        CurrentValue = 30,
        Callback = function(val)
            spinBotSpeed = val
        end
    })

    CombatTab:CreateSection("Auto-Clicker / Fast Attack")

    UIControls.Toggles["AutoClicker"] = CombatTab:CreateToggle({
        Name = "Auto-Clicker / Fast Attack",
        CurrentValue = false,
        Callback = setAutoClicker
    })

    UIControls.Sliders["AutoClickDelay"] = CombatTab:CreateSlider({
        Name = "Click Delay (Detik)",
        Range = {0.01, 0.5},
        Increment = 0.01,
        Suffix = "s",
        CurrentValue = 0.05,
        Callback = function(val)
            autoClickDelay = val
        end
    })

    CombatTab:CreateSection("Universal Fling System")

    local function getFlingPlayerOptions()
        local options = {}
        for _, name in ipairs(sortedPlayerNames()) do
            table.insert(options, name)
        end
        return options
    end

    local FlingPlayerDropdown = CombatTab:CreateDropdown({
        Name = "Pilih Target Fling",
        Options = getFlingPlayerOptions(),
        CurrentOption = {},
        MultipleOptions = false,
        Flag = "FlingPlayerDropdown",
        Callback = function(option)
            local opt = (typeof(option) == "table" and option[1]) or option
            selectedFlingPlayerName = (opt == "") and nil or opt
        end,
    })

    setConn("flingPlayerAdd", Players.PlayerAdded:Connect(function()
        pcall(function() FlingPlayerDropdown:Refresh(getFlingPlayerOptions(), true) end)
    end))
    setConn("flingPlayerRem", Players.PlayerRemoving:Connect(function()
        pcall(function() FlingPlayerDropdown:Refresh(getFlingPlayerOptions(), true) end)
    end))

    CombatTab:CreateButton({
        Name = "💥 Fling Target (1x Serang)",
        Callback = function()
            if selectedFlingPlayerName and selectedFlingPlayerName ~= "" then
                flingTargetPlayer(selectedFlingPlayerName, false)
            else
                sendNotification("Fling", "Pilih target terlebih dahulu!", 2)
            end
        end
    })

    UIControls.Toggles["LoopFling"] = CombatTab:CreateToggle({
        Name = "🔄 Loop Fling Target",
        CurrentValue = false,
        Callback = function(enabled)
            flags.flingLoop = enabled
            if enabled then
                if selectedFlingPlayerName and selectedFlingPlayerName ~= "" then
                    flingTargetPlayer(selectedFlingPlayerName, true)
                else
                    sendNotification("Fling", "Pilih target terlebih dahulu!", 2)
                end
            end
        end
    })

    CombatTab:CreateButton({
        Name = "🌪️ Fling All Players (Lempar Semua)",
        Callback = function()
            flingAllPlayers()
        end
    })


    -- 3. MOVEMENT TAB (Pergerakan & Terbang)
    local MovementTab = Window:CreateTab("Movement", "zap")
    windows.Movement = MovementTab

    MovementTab:CreateSection("Terbang (Flight)")

    flags.cframeFly = false
    local CFloop
    local cflySpeed = 50

    UIControls.Toggles["CFly"] = MovementTab:CreateToggle({
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

                CFloop = RunService.Heartbeat:Connect(function(deltaTime)
                    if not char or not hum or not head then return end

                    local moveDirection = hum.MoveDirection * (cflySpeed * deltaTime)
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

    UIControls.Sliders["CFlySpeed"] = MovementTab:CreateSlider({
        Name = "CFly Speed",
        Range = {10, 300},
        Increment = 5,
        Suffix = "Speed",
        CurrentValue = 50,
        Callback = function(val)
            cflySpeed = val
        end
    })

    UIControls.Toggles["ExternalFly"] = MovementTab:CreateToggle({
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

    MovementTab:CreateSection("Pijakan & Pergerakan Khusus")

    UIControls.Toggles["Shiftlock"] = MovementTab:CreateToggle({
        Name = "Universal Shiftlock Switch (Mobile & PC)",
        CurrentValue = false,
        Callback = setShiftlock
    })

    UIControls.Toggles["AirWalk"] = MovementTab:CreateToggle({
        Name = "Air Walk / Invisible Platform",
        CurrentValue = false,
        Callback = setAirWalk
    })

    UIControls.Toggles["ClickTeleport"] = MovementTab:CreateToggle({
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


    -- 4. VISUALS & ESP TAB (Tampilan & Kamera)
    local VisualsTab = Window:CreateTab("Visuals & ESP", "eye")
    windows.Visuals = VisualsTab

    VisualsTab:CreateSection("HUD & Overlay")

    UIControls.Toggles["FpsPingHUD"] = VisualsTab:CreateToggle({
        Name = "FPS & Ping Display HUD",
        CurrentValue = false,
        Callback = setFpsPingHUD
    })

    UIControls.Toggles["CustomCrosshair"] = VisualsTab:CreateToggle({
        Name = "Custom Crosshair",
        CurrentValue = false,
        Callback = setCustomCrosshair
    })

    VisualsTab:CreateSection("Player ESP System")

    flags.playerESP = false
    flags.highlightESP = false
    local espTable = {}

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

    local function removeESPForPlayer(plr)
        if espTable[plr] then
            if espTable[plr].Billboard then
                pcall(function() espTable[plr].Billboard:Destroy() end)
            end
            if espTable[plr].Highlight then
                pcall(function() espTable[plr].Highlight:Destroy() end)
            end
            espTable[plr] = nil
        end
    end

    local function removeAllESP()
        for plr, _ in pairs(espTable) do
            removeESPForPlayer(plr)
        end
        espTable = {}
    end

    local function updateESP()
        if not flags.playerESP and not flags.highlightESP then
            removeAllESP()
            return
        end

        local myHRP = getHRP()

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local hrp = char and char:FindFirstChild("HumanoidRootPart")

                if char and hum and hrp and hum.Health > 0 then
                    if not espTable[plr] then
                        espTable[plr] = {}
                    end

                    if flags.playerESP then
                        if not espTable[plr].Billboard or not espTable[plr].Billboard.Parent then
                            espTable[plr].Billboard = createBillboard(char)
                        end

                        local bb = espTable[plr].Billboard
                        if bb and bb:FindFirstChild("Card") then
                            local card = bb.Card
                            local infoText = card:FindFirstChild("InfoText")
                            local healthFill = card:FindFirstChild("HealthBg") and card.HealthBg:FindFirstChild("HealthFill")
                            local stroke = card:FindFirstChild("Stroke")

                            local healthPercent = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            local dist = myHRP and math.floor((myHRP.Position - hrp.Position).Magnitude) or 0

                            if infoText then
                                infoText.Text = string.format("%s | %d HP | %dm", plr.Name, math.floor(hum.Health), dist)
                            end

                            if healthFill then
                                healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)
                                if healthPercent > 0.6 then
                                    healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
                                elseif healthPercent > 0.3 then
                                    healthFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
                                else
                                    healthFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
                                end
                            end

                            if stroke then
                                if plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
                                    stroke.Color = Color3.fromRGB(0, 255, 150)
                                else
                                    stroke.Color = Color3.fromRGB(255, 60, 60)
                                end
                            end
                        end
                    else
                        if espTable[plr].Billboard then
                            pcall(function() espTable[plr].Billboard:Destroy() end)
                            espTable[plr].Billboard = nil
                        end
                    end

                    if flags.highlightESP then
                        if not espTable[plr].Highlight or not espTable[plr].Highlight.Parent then
                            espTable[plr].Highlight = createHighlight(char)
                        end
                    else
                        if espTable[plr].Highlight then
                            pcall(function() espTable[plr].Highlight:Destroy() end)
                            espTable[plr].Highlight = nil
                        end
                    end
                else
                    removeESPForPlayer(plr)
                end
            else
                removeESPForPlayer(plr)
            end
        end
    end

    UIControls.Toggles["PlayerESP"] = VisualsTab:CreateToggle({
        Name = "Name & Health Bar ESP",
        CurrentValue = false,
        Callback = function(enabled)
            flags.playerESP = enabled
            if not enabled and not flags.highlightESP then
                removeAllESP()
            end
        end
    })

    UIControls.Toggles["HighlightESP"] = VisualsTab:CreateToggle({
        Name = "Chams Glow ESP (Through Walls)",
        CurrentValue = false,
        Callback = function(enabled)
            flags.highlightESP = enabled
            if not enabled and not flags.playerESP then
                removeAllESP()
            end
        end
    })

    VisualsTab:CreateButton({
        Name = "Refresh ESP",
        Callback = function()
            removeAllESP()
            updateESP()
        end
    })

    setConn("espRender", RunService.RenderStepped:Connect(function()
        if flags.playerESP or flags.highlightESP then
            pcall(updateESP)
        end
    end))

    setConn("espPlayerRemoving", Players.PlayerRemoving:Connect(function(plr)
        removeESPForPlayer(plr)
    end))

    VisualsTab:CreateSection("Kamera & Lingkungan")

    local spectateTargetName = nil
    local viewDiedConn = nil
    local viewChangedConn = nil

    local SpectateDropdown = VisualsTab:CreateDropdown({
        Name = "Pilih Pemain (Spectate)",
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

    VisualsTab:CreateButton({
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

    VisualsTab:CreateButton({
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

    UIControls.Toggles["FullBright"] = VisualsTab:CreateToggle({
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


    -- 5. TELEPORT TAB (Teleport & Server)
    local TeleportTab = Window:CreateTab("Teleport", "map-pin")
    windows.Teleport = TeleportTab

    TeleportTab:CreateSection("Server Hop & Rejoin")

    TeleportTab:CreateButton({
        Name = "Server Hop (Pengguna Sedikit / Low Players)",
        Callback = function()
            task.spawn(function()
                local placeId = game.PlaceId
                local req = (syn and syn.request) or (http and http.request) or http_request or request
                local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
                
                local servers = {}
                pcall(function()
                    if req then
                        local res = req({Url = url, Method = "GET"})
                        if res and res.Body then
                            local data = HttpService:JSONDecode(res.Body)
                            if data and data.data then servers = data.data end
                        end
                    else
                        local resData = game:HttpGet(url)
                        local data = HttpService:JSONDecode(resData)
                        if data and data.data then servers = data.data end
                    end
                end)

                for _, server in ipairs(servers) do
                    if server.id ~= game.JobId and server.playing < server.maxPlayers and server.playing > 0 then
                        TeleportService:TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                        break
                    end
                end
            end)
        end
    })

    TeleportTab:CreateButton({
        Name = "Server Hop (Pengguna Ramai / High Players)",
        Callback = function()
            task.spawn(function()
                local placeId = game.PlaceId
                local req = (syn and syn.request) or (http and http.request) or http_request or request
                local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100", placeId)
                
                local servers = {}
                pcall(function()
                    if req then
                        local res = req({Url = url, Method = "GET"})
                        if res and res.Body then
                            local data = HttpService:JSONDecode(res.Body)
                            if data and data.data then servers = data.data end
                        end
                    else
                        local resData = game:HttpGet(url)
                        local data = HttpService:JSONDecode(resData)
                        if data and data.data then servers = data.data end
                    end
                end)

                for _, server in ipairs(servers) do
                    if server.id ~= game.JobId and server.playing < server.maxPlayers and server.playing > 0 then
                        TeleportService:TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                        break
                    end
                end
            end)
        end
    })

    TeleportTab:CreateButton({
        Name = "Rejoin Current Server",
        Callback = function()
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end)
        end
    })

    TeleportTab:CreateSection("Pilih Pemain untuk Teleport")
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
            if not selectedPlayerName or selectedPlayerName == "" then return end
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

    TeleportTab:CreateSection("Save Position Slots (1 - 30)")
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
        if hrp then savedSlots[slotSelected] = hrp.Position end
    end })

    TeleportTab:CreateButton({ Name = "Teleport Pos", Callback = function()
        if savedSlots[slotSelected] then
            local hrp = getHRP()
            if hrp then hrp.CFrame = CFrame.new(savedSlots[slotSelected] + Vector3.new(0,5,0)) end
        end
    end })

    TeleportTab:CreateButton({ Name = "Clear Slot", Callback = function()
        savedSlots[slotSelected] = nil
    end })

    TeleportTab:CreateButton({ Name = "Clear All Slots", Callback = function()
        for i=1,30 do savedSlots[i] = nil end
    end })

    TeleportTab:CreateSection("Tween Teleport (Bypass Anti-Cheat)")

    UIControls.Sliders["TweenSpeed"] = TeleportTab:CreateSlider({
        Name = "Kecepatan Tween (Studs/Detik)",
        Range = {30, 500},
        Increment = 10,
        Suffix = " studs/s",
        CurrentValue = 150,
        Flag = "TweenSpeedSlider",
        Callback = function(val)
            tweenTeleportSpeed = tonumber(val) or 150
        end
    })

    TeleportTab:CreateButton({
        Name = "🚀 Tween TP ke Pemain Terpilih",
        Callback = function()
            if not selectedPlayerName or selectedPlayerName == "" then
                sendNotification("🚀 Tween TP", "Pilih pemain di daftar atas terlebih dahulu!", 2)
                return
            end
            local target = Players:FindFirstChild(selectedPlayerName)
            if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                local targetCF = CFrame.new(target.Character.HumanoidRootPart.Position + Vector3.new(0, 3, 0))
                startTweenTeleport(targetCF)
            else
                sendNotification("🚀 Tween TP", "Pemain target tidak valid atau belum spawn!", 2)
            end
        end
    })

    TeleportTab:CreateButton({
        Name = "🚀 Tween TP ke Slot Posisi Terpilih",
        Callback = function()
            if savedSlots[slotSelected] then
                local targetCF = CFrame.new(savedSlots[slotSelected] + Vector3.new(0, 5, 0))
                startTweenTeleport(targetCF)
            else
                sendNotification("🚀 Tween TP", "Slot " .. tostring(slotSelected) .. " belum memiliki posisi yang disimpan!", 2)
            end
        end
    })

    TeleportTab:CreateButton({
        Name = "🛑 Batalkan / Stop Tween Teleport",
        Callback = function()
            cancelTweenTeleport()
        end
    })

    TeleportTab:CreateSection("Quick Floating Teleports (Slots 1 - 10)")

    local selectedWidgetSlot = 1

    createFloatingTPWidget = function(slotId)
        slotId = tonumber(slotId) or 1
        if floatingTPWidgets[slotId] then
            floatingTPWidgets[slotId]:Destroy()
            floatingTPWidgets[slotId] = nil
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "BoyeszQuickTP_Gui_Slot" .. slotId
        gui.ResetOnSpawn = false

        local parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")
        gui.Parent = parent

        local offsetX = ((slotId - 1) % 3) * 65 - 65
        local offsetY = math.floor((slotId - 1) / 3) * 55

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, 180, 0, 48)
        frame.Position = UDim2.new(0.5, -90 + offsetX, 0.75 - (offsetY / 1000), 0)
        frame.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
        frame.BackgroundTransparency = 0.2
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true
        frame.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 170, 255)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.3
        stroke.Parent = frame

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, -20, 0, 14)
        title.Position = UDim2.new(0, 8, 0, 3)
        title.Text = string.format("⚡ Quick TP Slot %d", slotId)
        title.TextColor3 = Color3.fromRGB(0, 200, 255)
        title.TextTransparency = 0.2
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = frame

        local closeBtn = Instance.new("TextButton")
        closeBtn.Name = "CloseBtn"
        closeBtn.Size = UDim2.new(0, 16, 0, 16)
        closeBtn.Position = UDim2.new(1, -18, 0, 2)
        closeBtn.Text = "×"
        closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
        closeBtn.BackgroundTransparency = 1
        closeBtn.Font = Enum.Font.GothamBold
        closeBtn.TextSize = 14
        closeBtn.Parent = frame

        closeBtn.MouseButton1Click:Connect(function()
            if floatingTPWidgets[slotId] then
                floatingTPWidgets[slotId]:Destroy()
                floatingTPWidgets[slotId] = nil
            end
            if UIControls.Toggles["WidgetSlot_" .. slotId] and UIControls.Toggles["WidgetSlot_" .. slotId].CurrentValue == true then
                UIControls.Toggles["WidgetSlot_" .. slotId]:Set(false)
            end
        end)

        local saveBtn = Instance.new("TextButton")
        saveBtn.Name = "SaveBtn"
        saveBtn.Size = UDim2.new(0.46, 0, 0, 24)
        saveBtn.Position = UDim2.new(0, 6, 1, -27)
        saveBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
        saveBtn.Text = "💾 Save " .. slotId
        saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        saveBtn.Font = Enum.Font.GothamBold
        saveBtn.TextSize = 10
        saveBtn.Parent = frame

        local saveCorner = Instance.new("UICorner")
        saveCorner.CornerRadius = UDim.new(0, 6)
        saveCorner.Parent = saveBtn

        saveBtn.MouseButton1Click:Connect(function()
            local hrp = getHRP()
            if hrp then
                quickSavedCFrames[slotId] = hrp.CFrame
                saveBtn.Text = "✓ Saved!"
                task.wait(0.8)
                saveBtn.Text = "💾 Save " .. slotId
            end
        end)

        local tpBtn = Instance.new("TextButton")
        tpBtn.Name = "TPBtn"
        tpBtn.Size = UDim2.new(0.46, 0, 0, 24)
        tpBtn.Position = UDim2.new(0.51, 0, 1, -27)
        tpBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
        tpBtn.Text = "⚡ TP " .. slotId
        tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        tpBtn.Font = Enum.Font.GothamBold
        tpBtn.TextSize = 10
        tpBtn.Parent = frame

        local tpCorner = Instance.new("UICorner")
        tpCorner.CornerRadius = UDim.new(0, 6)
        tpCorner.Parent = tpBtn

        tpBtn.MouseButton1Click:Connect(function()
            if quickSavedCFrames[slotId] then
                local hrp = getHRP()
                if hrp then
                    hrp.CFrame = quickSavedCFrames[slotId] + Vector3.new(0, 2, 0)
                end
            else
                tpBtn.Text = "No Pos!"
                task.wait(0.8)
                tpBtn.Text = "⚡ TP " .. slotId
            end
        end)

        floatingTPWidgets[slotId] = gui
    end

    TeleportTab:CreateButton({
        Name = "⚡ Buka Semua Widget (1 - 10)",
        Callback = function()
            for i = 1, 10 do
                if UIControls.Toggles["WidgetSlot_" .. i] then
                    UIControls.Toggles["WidgetSlot_" .. i]:Set(true)
                else
                    createFloatingTPWidget(i)
                end
            end
        end
    })

    TeleportTab:CreateButton({
        Name = "❌ Tutup Semua Floating Widget",
        Callback = function()
            for i = 1, 10 do
                if UIControls.Toggles["WidgetSlot_" .. i] then
                    UIControls.Toggles["WidgetSlot_" .. i]:Set(false)
                elseif floatingTPWidgets[i] then
                    floatingTPWidgets[i]:Destroy()
                    floatingTPWidgets[i] = nil
                end
            end
        end
    })

    TeleportTab:CreateSection("Tombol ON / OFF Widget 1 - 10")

    for i = 1, 10 do
        local slot = i
        UIControls.Toggles["WidgetSlot_" .. slot] = TeleportTab:CreateToggle({
            Name = string.format("Teleport Widget Slot %d", slot),
            CurrentValue = false,
            Callback = function(enabled)
                if enabled then
                    createFloatingTPWidget(slot)
                else
                    if floatingTPWidgets[slot] then
                        floatingTPWidgets[slot]:Destroy()
                        floatingTPWidgets[slot] = nil
                    end
                end
            end
        })
    end

    TeleportTab:CreateSection("Quick Config Teleport")

    TeleportTab:CreateButton({
        Name = "💾 Simpan Posisi Teleport & Status Widget",
        Callback = function()
            ConfigManager:Save("teleport_quick_config")
        end
    })

    TeleportTab:CreateButton({
        Name = "📂 Muat Posisi Teleport & Buka Widget Otomatis",
        Callback = function()
            ConfigManager:Load("teleport_quick_config")
        end
    })


    -- 6. PERFORMANCE TAB (Performa & System)
    local PerformanceTab = Window:CreateTab("Performance", "gauge")
    windows.Performance = PerformanceTab

    PerformanceTab:CreateSection("FPS Boost & Anti-Lag")

    PerformanceTab:CreateButton({
        Name = "Unlock FPS (Set 240 FPS)",
        Callback = function()
            if setfpscap then
                pcall(function() setfpscap(240) end)
            end
        end
    })

    local originalGlobalShadows = Lighting.GlobalShadows
    UIControls.Toggles["FPSBoost"] = PerformanceTab:CreateToggle({
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

    PerformanceTab:CreateButton({
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

    PerformanceTab:CreateSection("Protection")

    UIControls.Toggles["AntiAFK"] = PerformanceTab:CreateToggle({
        Name = "Anti-AFK Protection (Auto 20m Kick Guard)",
        CurrentValue = true,
        Callback = function(enabled)
            flags.antiAFK = enabled
            clearConn("antiAFKConn")
            if enabled then
                local vu = game:GetService("VirtualUser")
                setConn("antiAFKConn", LocalPlayer.Idled:Connect(function()
                    if flags.antiAFK then
                        vu:CaptureController()
                        vu:ClickButton2(Vector2.new(0,0))
                    end
                end))
            end
        end
    })

    UIControls.Toggles["AutoRejoin"] = PerformanceTab:CreateToggle({
        Name = "Auto Rejoin on Disconnect",
        CurrentValue = false,
        Callback = function(enabled)
            flags.autoRejoin = enabled
            clearConn("autoRejoinError")
            if enabled then
                setConn("autoRejoinError", GuiService.ErrorCodeChanged:Connect(function()
                    if flags.autoRejoin then
                        task.wait(1)
                        pcall(function()
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                        end)
                    end
                end))
            end
        end
    })


    -- 7. GAMES HUB TAB (Script Game Spesifik)
    local GameTab = Window:CreateTab("Games Hub", "gamepad-2")
    windows.GameScripts = GameTab

    GameTab:CreateSection("Mine a Mountain")

    UIControls.Toggles["MineAMountainV1"] = GameTab:CreateToggle({
        Name = "Mine a Mountain v1 (Auto-Execute)",
        CurrentValue = false,
        Callback = function(enabled)
            flags.mineAMountain = enabled
            if enabled then
                task.spawn(function()
                    local ok, err = pcall(function()
                        loadstring(game:HttpGet("https://raw.githubusercontent.com/gumanba/Scripts/main/MineaMountain"))()
                    end)
                    if not ok then
                        warn("[Boyesz Tonz] Error executing Mine a Mountain v1:", err)
                    end
                end)
            end
        end
    })

    GameTab:CreateButton({
        Name = "Execute Mine a Mountain v1 (Gumanba)",
        Callback = function()
            task.spawn(function()
                local ok, err = pcall(function()
                    loadstring(game:HttpGet("https://raw.githubusercontent.com/gumanba/Scripts/main/MineaMountain"))()
                end)
                if not ok then
                    warn("[Boyesz Tonz] Error executing Mine a Mountain v1:", err)
                end
            end)
        end
    })

    UIControls.Toggles["MineAMountainV2"] = GameTab:CreateToggle({
        Name = "Mine a Mountain v2 (Auto-Execute)",
        CurrentValue = false,
        Callback = function(enabled)
            flags.mineAMountainV2 = enabled
            if enabled then
                task.spawn(function()
                    local ok, err = pcall(function()
                        loadstring(game:HttpGet("https://gist.githubusercontent.com/2RanmaChan2/d85484e7ff26eadee63e20f9069d8581/raw/1185a00d955831be354d47d6d8a79349288ba59f/Mine%20a%20Mountain%20by%20DonnieAzoff"))()
                    end)
                    if not ok then
                        warn("[Boyesz Tonz] Error executing Mine a Mountain v2:", err)
                    end
                end)
            end
        end
    })

    GameTab:CreateButton({
        Name = "Execute Mine a Mountain v2 (DonnieAzoff Gist)",
        Callback = function()
            task.spawn(function()
                local ok, err = pcall(function()
                    loadstring(game:HttpGet("https://gist.githubusercontent.com/2RanmaChan2/d85484e7ff26eadee63e20f9069d8581/raw/1185a00d955831be354d47d6d8a79349288ba59f/Mine%20a%20Mountain%20by%20DonnieAzoff"))()
                end)
                if not ok then
                    warn("[Boyesz Tonz] Error executing Mine a Mountain v2:", err)
                end
            end)
        end
    })

    if game.PlaceId == 121864768012064 then
        GameTab:CreateSection("Fish It Game")

        local ok, netRoot = pcall(function()
            return ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index")
                :WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
        end)

        if ok and netRoot then
            flags.autofish = false
            flags.perfectCast = true

            local equipRemote = netRoot:FindFirstChild("RE/EquipToolFromHotbar")
            local rodRemote = netRoot:FindFirstChild("RF/ChargeFishingRod")
            local miniGameRemote = netRoot:FindFirstChild("RF/RequestFishingMinigameStarted")
            local finishRemote = netRoot:FindFirstChild("RE/FishingCompleted")

            UIControls.Toggles["AutoFish"] = GameTab:CreateToggle({
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
                    end
                end
            })

            UIControls.Toggles["PerfectCast"] = GameTab:CreateToggle({
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

            GameTab:CreateDropdown({
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
    end

    -- 8. DEVELOPER & UTILITY TOOLS TAB
    local DevTab = Window:CreateTab("Developer Tools", "terminal")
    windows.Dev = DevTab

    DevTab:CreateSection("Client-Side BTool (Delete Part / Wall Remover)")

    DevTab:CreateButton({
        Name = "🔨 Ambil BTool (Delete Part Tool ke Backpack)",
        Callback = function()
            giveBTool()
        end
    })

    UIControls.Toggles["ClickToDelete"] = DevTab:CreateToggle({
        Name = "🖱️ Mode Klik Hapus Part (Wall Remover)",
        CurrentValue = false,
        Flag = "ClickToDeleteToggle",
        Callback = function(enabled)
            setClickToDelete(enabled)
        end
    })

    DevTab:CreateSection("Script & Explorer Loaders")

    DevTab:CreateButton({
        Name = "📱 Buka Dark Dex Explorer (Object & Part Viewer)",
        Callback = function()
            loadDarkDex()
        end
    })

    DevTab:CreateButton({
        Name = "🕵️ Buka SimpleSpy (Remote Event Logger)",
        Callback = function()
            loadSimpleSpy()
        end
    })

    DevTab:CreateButton({
        Name = "⚡ Buka Infinite Yield (Universal Admin)",
        Callback = function()
            loadInfiniteYield()
        end
    })

    -- 9. CONFIG & DATABASE TAB
    local ConfigTab = Window:CreateTab("Config & Database", "save")
    windows.Config = ConfigTab

    ConfigTab:CreateSection("Database & Profile Konfigurasi")

    local currentConfigName = "default"
    local ConfigDropdown = nil

    local function refreshConfigList()
        local list = ConfigManager:GetConfigs()
        if ConfigDropdown then
            pcall(function() ConfigDropdown:Refresh(list, true) end)
        end
        return list
    end

    ConfigTab:CreateInput({
        Name = "Nama Config",
        PlaceholderText = "Contoh: default / farming / pvp",
        RemoveTextAfterFocusLost = false,
        Callback = function(text)
            if text and text ~= "" then
                currentConfigName = text:gsub("[%s/\\]+", "_")
            end
        end
    })

    ConfigDropdown = ConfigTab:CreateDropdown({
        Name = "Pilih Config Tersimpan",
        Options = ConfigManager:GetConfigs(),
        CurrentOption = {ConfigManager:GetConfigs()[1] or "default"},
        MultipleOptions = false,
        Flag = "ConfigSelectedDropdown",
        Callback = function(option)
            local chosen = (typeof(option) == "table" and option[1]) or option
            if chosen and chosen ~= "" then
                currentConfigName = chosen
            end
        end
    })

    ConfigTab:CreateButton({
        Name = "💾 Simpan Config (Save Config)",
        Callback = function()
            ConfigManager:Save(currentConfigName)
            refreshConfigList()
        end
    })

    ConfigTab:CreateButton({
        Name = "📂 Muat Config (Load Config)",
        Callback = function()
            ConfigManager:Load(currentConfigName)
        end
    })

    ConfigTab:CreateButton({
        Name = "🔄 Refresh Daftar File Config",
        Callback = function()
            refreshConfigList()
            sendNotification("Config List", "Daftar file config diperbarui!", 2)
        end
    })

    ConfigTab:CreateButton({
        Name = "🗑 Hapus Config (Delete Config)",
        Callback = function()
            ConfigManager:Delete(currentConfigName)
            refreshConfigList()
        end
    })

    ConfigTab:CreateSection("Auto-Load on Startup")

    local isAutoLoad = (ConfigManager:GetAutoLoadConfig() ~= nil)
    ConfigTab:CreateToggle({
        Name = "⚡ Auto-Load saat Script Di-Execute",
        CurrentValue = isAutoLoad,
        Callback = function(enabled)
            ConfigManager:SetAutoLoad(enabled, currentConfigName)
            if enabled then
                sendNotification("⚡ Auto-Load Aktif", "Config '" .. currentConfigName .. "' akan otomatis aktif saat execute!", 3)
            else
                sendNotification("⚡ Auto-Load Nonaktif", "Auto-load dinonaktifkan.", 3)
            end
        end
    })

    ConfigTab:CreateSection("Panduan Database & Backup")
    ConfigTab:CreateParagraph({
        Title = "Info Penyimpanan",
        Content = "File config disimpan di folder: 'BoyeszTonz_Config/' dalam format JSON.\nMenyimpan status toggle fitur, slider, 30 slot teleport, dan floating teleport widget yang sedang aktif."
    })

    -- Auto-load check on initial startup
    task.spawn(function()
        task.wait(0.6)
        ConfigManager:CheckAutoLoad()
    end)
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
