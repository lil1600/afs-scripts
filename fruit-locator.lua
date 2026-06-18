-- Anime Fighting Simulator | Devil Fruit Locator v3
-- Visual UI — Optimized for Delta Executor (Rayfield UI)

-- ============================================
-- LOAD RAYFIELD UI LIBRARY
-- ============================================
local Rayfield = loadstring(game:HttpGet(
    "https://sirius.menu/rayfield"
))()

-- ============================================
-- CONFIGURATION
-- ============================================
local FRUIT_STAY_DURATION = 20
local SPAWN_INTERVAL      = 45
local FIRST_SPAWN         = 60

local PICKUP_KEYWORDS = { "pick up", "pickup", "take", "collect" }

-- ============================================
-- STATE
-- ============================================
local lastFruitPosition = nil  -- Stores position after scan
local lastFruitName     = nil  -- Stores fruit name after scan

-- ============================================
-- GENERATE SPAWN SCHEDULE
-- ============================================
local function generateSpawnTimes()
    local times = {}
    local t = FIRST_SPAWN
    while t <= 660 do
        table.insert(times, t)
        t = t + SPAWN_INTERVAL
    end
    return times
end

local SPAWN_TIMES = generateSpawnTimes()

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
local function formatTime(minutes)
    local m = math.floor(minutes)
    local h = math.floor(m / 60)
    local mins = m % 60
    if h > 0 then
        return string.format("%dh %02dm", h, mins)
    else
        return string.format("%dm", mins)
    end
end

local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function isPickupText(text)
    local lower = text:lower()
    for _, keyword in ipairs(PICKUP_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return false
end

local function extractFruitName(text)
    local lower = text:lower()
    for _, keyword in ipairs(PICKUP_KEYWORDS) do
        local idx = lower:find(keyword, 1, true)
        if idx then
            local name = text:sub(1, idx - 1):match("^%s*(.-)%s*$")
            return name ~= "" and name or text
        end
    end
    return text
end

-- ============================================
-- SERVER AGE
-- ============================================
local function getServerAgeMinutes()
    local ok, result = pcall(function()
        return workspace.DistributedGameTime / 60
    end)
    if ok and result and result > 0 and result < 100000 then
        return result
    end
    return os.clock() / 60
end

-- ============================================
-- SPAWN STATUS LOGIC
-- ============================================
local function getSpawnStatus()
    local serverAgeMinutes = getServerAgeMinutes()
    local lastSpawn, nextSpawn = nil, nil

    for _, t in ipairs(SPAWN_TIMES) do
        if t <= serverAgeMinutes then
            lastSpawn = t
        else
            nextSpawn = t
            break
        end
    end

    if not lastSpawn then
        return {
            status        = "WAITING",
            nextSpawn     = nextSpawn,
            timeUntilNext = nextSpawn and (nextSpawn - serverAgeMinutes) or nil,
            serverAge     = serverAgeMinutes,
        }
    end

    local minutesSinceSpawn = serverAgeMinutes - lastSpawn

    if minutesSinceSpawn <= FRUIT_STAY_DURATION then
        return {
            status         = "WINDOW_OPEN",
            lastSpawn      = lastSpawn,
            nextSpawn      = nextSpawn,
            windowTimeLeft = FRUIT_STAY_DURATION - minutesSinceSpawn,
            timeUntilNext  = nextSpawn and (nextSpawn - serverAgeMinutes) or nil,
            serverAge      = serverAgeMinutes,
        }
    end

    return {
        status        = "DESPAWNED",
        lastSpawn     = lastSpawn,
        nextSpawn     = nextSpawn,
        timeUntilNext = nextSpawn and (nextSpawn - serverAgeMinutes) or nil,
        serverAge     = serverAgeMinutes,
    }
end

-- ============================================
-- FRUIT SCANNER
-- ============================================
local function scanForFruits()
    local Players   = game:GetService("Players")
    local player    = Players.LocalPlayer
    local character = player.Character
    if not character then return nil, "Character not loaded." end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil, "HumanoidRootPart missing." end

    local fruitsFound = {}
    local scanned     = {}

    local function getModelPosition(obj)
        local current = obj
        while current and current ~= workspace do
            if current:IsA("BasePart") then
                return current.Position
            elseif current:IsA("Model") then
                if current.PrimaryPart then
                    return current.PrimaryPart.Position
                end
                local part = current:FindFirstChildWhichIsA("BasePart", true)
                if part then return part.Position end
            end
            current = current.Parent
        end
        return nil
    end

    local function checkObject(obj)
        if scanned[obj] then return end
        scanned[obj] = true

        if obj:IsA("ProximityPrompt") then
            local text = (obj.ActionText ~= "" and obj.ActionText)
                      or (obj.ObjectText  ~= "" and obj.ObjectText)
                      or ""
            if isPickupText(text) then
                local pos = getModelPosition(obj.Parent)
                if pos then
                    local fruitName = extractFruitName(
                        obj.ObjectText ~= "" and obj.ObjectText or text
                    )
                    table.insert(fruitsFound, {
                        name     = fruitName,
                        position = pos,
                        distance = getDistance(rootPart.Position, pos),
                    })
                end
            end
        end

        if obj:IsA("BillboardGui") then
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    if isPickupText(child.Text) then
                        local pos = getModelPosition(obj.Parent)
                        if pos and not scanned[obj.Parent] then
                            scanned[obj.Parent] = true
                            local fruitName = extractFruitName(child.Text)
                            table.insert(fruitsFound, {
                                name     = fruitName,
                                position = pos,
                                distance = getDistance(rootPart.Position, pos),
                            })
                        end
                    end
                end
            end
        end
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        checkObject(obj)
    end

    table.sort(fruitsFound, function(a, b)
        return a.distance < b.distance
    end)

    return fruitsFound, nil
end

-- ============================================
-- TELEPORT FUNCTION
-- ============================================
local function teleportToFruit()
    if not lastFruitPosition then
        Rayfield:Notify({
            Title   = "No Fruit Scanned",
            Content = "Scan for a fruit first before teleporting!",
            Duration = 5,
            Image    = "4483345998",
        })
        return
    end

    local Players   = game:GetService("Players")
    local character = Players.LocalPlayer.Character
    if not character then
        Rayfield:Notify({
            Title   = "Error",
            Content = "Character not found!",
            Duration = 4,
            Image    = "4483345998",
        })
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        Rayfield:Notify({
            Title   = "Error",
            Content = "HumanoidRootPart missing!",
            Duration = 4,
            Image    = "4483345998",
        })
        return
    end

    -- Teleport slightly above fruit so we land on it, not inside it
    local targetPos = lastFruitPosition + Vector3.new(0, 5, 0)
    rootPart.CFrame = CFrame.new(targetPos)

    Rayfield:Notify({
        Title   = "✅ Teleported!",
        Content = "Arrived at " .. (lastFruitName or "fruit") .. " location!",
        Duration = 5,
        Image    = "4483345998",
    })
end

-- ============================================
-- BUILD RAYFIELD UI
-- ============================================
local Window = Rayfield:CreateWindow({
    Name                   = "🍎 AFS Fruit Locator",
    LoadingTitle           = "AFS Fruit Locator",
    LoadingSubtitle        = "by Delta Script",
    Theme                  = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = false,
    ConfigurationSaving    = { Enabled = false },
})

local MainTab = Window:CreateTab("🍎 Fruit Locator", nil)
local InfoTab = Window:CreateTab("📋 Schedule", nil)

-- ============================================
-- MAIN TAB — STATUS
-- ============================================
MainTab:CreateSection("📡 Server Status")

local statusLabel = MainTab:CreateLabel("Loading...")
local windowLabel = MainTab:CreateLabel("")
local nextLabel   = MainTab:CreateLabel("")

local function refreshStatus()
    local info   = getSpawnStatus()
    local ageStr = formatTime(info.serverAge)

    statusLabel:Set("🕐 Server Age: " .. ageStr)

    if info.status == "WAITING" then
        windowLabel:Set("⏳ No fruit spawned yet")
        nextLabel:Set("⏱ First fruit in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))

    elseif info.status == "WINDOW_OPEN" then
        local minLeft = math.floor(info.windowTimeLeft)
        windowLabel:Set("🟢 Window OPEN — " .. minLeft .. " min left!")
        nextLabel:Set("⏱ Next spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))

    elseif info.status == "DESPAWNED" then
        windowLabel:Set("🔴 Fruit despawned — not on map")
        nextLabel:Set("⏱ Next spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))
    end
end

refreshStatus()

-- ============================================
-- MAIN TAB — SCAN & TELEPORT
-- ============================================
MainTab:CreateSection("🔍 Scan & Teleport")

local resultLabel = MainTab:CreateLabel("Press scan to search for fruit.")

MainTab:CreateButton({
    Name     = "🔍 Scan for Devil Fruit",
    Callback = function()
        refreshStatus()
        local info = getSpawnStatus()

        -- Reset stored position on each scan
        lastFruitPosition = nil
        lastFruitName     = nil
        resultLabel:Set("🔍 Scanning workspace...")

        if info.status == "WAITING" then
            resultLabel:Set("⏳ First spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))
            Rayfield:Notify({ Title = "Too Early", Content = "No fruit spawned yet!", Duration = 5, Image = "4483345998" })
            return
        end

        if info.status == "DESPAWNED" then
            resultLabel:Set("🔴 Despawned — next in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))
            Rayfield:Notify({ Title = "Fruit Gone", Content = "Next spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"), Duration = 6, Image = "4483345998" })
            return
        end

        local fruits, err = scanForFruits()

        if err then
            resultLabel:Set("❌ Error: " .. err)
            return
        end

        if #fruits == 0 then
            resultLabel:Set("❌ No fruit detected — may have been collected!")
            Rayfield:Notify({ Title = "Not Found", Content = "Window open but no fruit found. Collected?", Duration = 6, Image = "4483345998" })
            return
        end

        -- Store fruit data for teleport
        local fruit = fruits[1]
        lastFruitPosition = fruit.position
        lastFruitName     = fruit.name

        local pos = fruit.position
        resultLabel:Set(string.format(
            "✅ %s found!\nX:%.0f  Y:%.0f  Z:%.0f\n📏 %.0f studs away\n\n👇 Press Teleport to go there!",
            fruit.name, pos.X, pos.Y, pos.Z, fruit.distance
        ))

        Rayfield:Notify({
            Title   = "🍎 " .. fruit.name .. " Found!",
            Content = string.format("X:%.0f Y:%.0f Z:%.0f — %.0f studs away", pos.X, pos.Y, pos.Z, fruit.distance),
            Duration = 8,
            Image    = "4483345998",
        })
    end,
})

-- Teleport button — only works after a successful scan
MainTab:CreateButton({
    Name     = "🌀 Teleport to Fruit",
    Callback = function()
        teleportToFruit()
    end,
})

MainTab:CreateButton({
    Name     = "🔄 Refresh Status",
    Callback = function()
        refreshStatus()
        Rayfield:Notify({ Title = "Refreshed", Content = "Server status updated!", Duration = 3, Image = "4483345998" })
    end,
})

-- ============================================
-- SCHEDULE TAB
-- ============================================
InfoTab:CreateSection("📋 Full Spawn Schedule")
InfoTab:CreateLabel("Every 45 min starting at 1h00")
InfoTab:CreateLabel("🟢 Window open: 20 min after spawn")
InfoTab:CreateLabel("🔴 Despawn → next spawn: 25 min")
InfoTab:CreateLabel("⚠️ Timer is fixed — collection doesn't affect it")
InfoTab:CreateLabel("─────────────────────────────")

for i, t in ipairs(SPAWN_TIMES) do
    if i <= 15 then
        InfoTab:CreateLabel("Spawn #" .. i .. " → " .. formatTime(t))
    end
end

InfoTab:CreateLabel("... continues every 45 min")
