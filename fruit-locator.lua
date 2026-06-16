-- Anime Fighting Simulator | Devil Fruit Locator
-- Visual UI Version — Optimized for Delta Executor (Rayfield UI)
-- Compatible: Android, iOS, PC

-- ============================================
-- LOAD RAYFIELD UI LIBRARY
-- ============================================
local Rayfield = loadstring(game:HttpGet(
    "https://sirius.menu/rayfield"
))()

-- ============================================
-- CONFIGURATION
-- ============================================
local FRUIT_NAMES = {
    "Ice", "Magma", "Light Fruit",
    "Flame", "Quaker", "Rubber", "Chop",
}

local FRUIT_STAY_DURATION = 20  -- Minutes fruit stays on ground
local SPAWN_INTERVAL      = 45  -- Minutes between spawns
local FIRST_SPAWN         = 60  -- First spawn at 1h00

-- ============================================
-- GENERATE SPAWN SCHEDULE
-- ============================================
local function generateSpawnTimes()
    local times = {}
    local t = FIRST_SPAWN
    while t <= 660 do -- Up to 11h
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

local function isFruit(name)
    local nameLower = name:lower()
    for _, fruitName in ipairs(FRUIT_NAMES) do
        if nameLower:find(fruitName:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- ============================================
-- SPAWN STATUS LOGIC
-- ============================================
local function getSpawnStatus()
    local serverAgeMinutes = workspace:GetServerTimeNow() / 60
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
            status       = "WAITING",
            nextSpawn    = nextSpawn,
            timeUntilNext = nextSpawn and (nextSpawn - serverAgeMinutes) or nil,
            serverAge    = serverAgeMinutes,
        }
    end

    local minutesSinceSpawn = serverAgeMinutes - lastSpawn

    if minutesSinceSpawn <= FRUIT_STAY_DURATION then
        return {
            status        = "WINDOW_OPEN",
            lastSpawn     = lastSpawn,
            nextSpawn     = nextSpawn,
            windowTimeLeft = FRUIT_STAY_DURATION - minutesSinceSpawn,
            timeUntilNext = nextSpawn and (nextSpawn - serverAgeMinutes) or nil,
            serverAge     = serverAgeMinutes,
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
    local Players  = game:GetService("Players")
    local player   = Players.LocalPlayer
    local character = player.Character
    if not character then return nil, "Character not loaded." end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil, "HumanoidRootPart missing." end

    local fruitsFound = {}
    local scanned = {}

    local function scanDescendants(parent)
        for _, obj in ipairs(parent:GetChildren()) do
            if not scanned[obj] and isFruit(obj.Name) then
                scanned[obj] = true
                local pos = nil
                if obj:IsA("BasePart") then
                    pos = obj.Position
                elseif obj:IsA("Model") and obj.PrimaryPart then
                    pos = obj.PrimaryPart.Position
                elseif obj:IsA("Model") then
                    local part = obj:FindFirstChildWhichIsA("BasePart")
                    if part then pos = part.Position end
                end
                if pos then
                    table.insert(fruitsFound, {
                        name     = obj.Name,
                        position = pos,
                        distance = getDistance(rootPart.Position, pos),
                    })
                end
            end
            scanDescendants(obj)
        end
    end

    scanDescendants(workspace)

    table.sort(fruitsFound, function(a, b)
        return a.distance < b.distance
    end)

    return fruitsFound, nil
end

-- ============================================
-- BUILD RAYFIELD UI
-- ============================================
local Window = Rayfield:CreateWindow({
    Name             = "🍎 AFS Fruit Locator",
    LoadingTitle     = "AFS Fruit Locator",
    LoadingSubtitle  = "by Delta Script",
    Theme            = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = false,
    ConfigurationSaving = {
        Enabled = false,
    },
})

-- TAB: Main
local MainTab = Window:CreateTab("🍎 Fruit Locator", nil)
local InfoTab = Window:CreateTab("📋 Schedule", nil)

-- ============================================
-- MAIN TAB — STATUS SECTION
-- ============================================
local StatusSection = MainTab:CreateSection("📡 Server Status")

local statusLabel = MainTab:CreateLabel("Loading server info...")
local windowLabel = MainTab:CreateLabel("")
local nextLabel   = MainTab:CreateLabel("")

local function refreshStatus()
    local info = getSpawnStatus()
    local ageStr = formatTime(info.serverAge)

    statusLabel:Set("🕐 Server Age: " .. ageStr)

    if info.status == "WAITING" then
        windowLabel:Set("⏳ No fruit spawned yet on this server")
        nextLabel:Set("⏱ First fruit in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))

    elseif info.status == "WINDOW_OPEN" then
        local minLeft = math.floor(info.windowTimeLeft)
        windowLabel:Set("🟢 Fruit window is OPEN — " .. minLeft .. " min left on ground!")
        nextLabel:Set("⏱ Next spawn after this: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))

    elseif info.status == "DESPAWNED" then
        windowLabel:Set("🔴 Fruit has despawned — not on map")
        nextLabel:Set("⏱ Next spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))
    end
end

refreshStatus()

-- ============================================
-- MAIN TAB — SCAN SECTION
-- ============================================
local ScanSection = MainTab:CreateSection("🔍 Scan Map")

local resultLabel = MainTab:CreateLabel("Press the button to scan.")

MainTab:CreateButton({
    Name     = "🔍 Scan for Devil Fruit",
    Callback = function()
        refreshStatus()
        local info = getSpawnStatus()

        if info.status == "WAITING" then
            resultLabel:Set("⏳ No fruit yet — first spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))
            Rayfield:Notify({
                Title    = "Too Early",
                Content  = "First fruit hasn't spawned yet!",
                Duration = 5,
                Image    = "4483345998",
            })
            return
        end

        if info.status == "DESPAWNED" then
            resultLabel:Set("🔴 Fruit is gone — next spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"))
            Rayfield:Notify({
                Title    = "Fruit Despawned",
                Content  = "Next spawn in: " .. (info.timeUntilNext and formatTime(info.timeUntilNext) or "?"),
                Duration = 6,
                Image    = "4483345998",
            })
            return
        end

        -- Window is open — scan!
        resultLabel:Set("🔍 Scanning workspace...")

        local fruits, err = scanForFruits()

        if err then
            resultLabel:Set("❌ Error: " .. err)
            return
        end

        if #fruits == 0 then
            resultLabel:Set("❌ No fruit detected — may have been collected!")
            Rayfield:Notify({
                Title    = "Not Found",
                Content  = "Window open but no fruit on map. Collected?",
                Duration = 6,
                Image    = "4483345998",
            })
            return
        end

        -- Show results
        local lines = {}
        for i, fruit in ipairs(fruits) do
            local pos = fruit.position
            local line = string.format(
                "#%d %s | X:%.0f Y:%.0f Z:%.0f | %.0f studs",
                i, fruit.name, pos.X, pos.Y, pos.Z, fruit.distance
            )
            table.insert(lines, line)

            Rayfield:Notify({
                Title    = "🍎 " .. fruit.name .. " Found!",
                Content  = string.format("X:%.0f Y:%.0f Z:%.0f — %.0f studs away", pos.X, pos.Y, pos.Z, fruit.distance),
                Duration = 10,
                Image    = "4483345998",
            })

            task.wait(0.8)
        end

        resultLabel:Set("✅ Found " .. #fruits .. " fruit(s):\n" .. table.concat(lines, "\n"))
    end,
})

MainTab:CreateButton({
    Name     = "🔄 Refresh Status",
    Callback = function()
        refreshStatus()
        Rayfield:Notify({
            Title   = "Refreshed",
            Content = "Server status updated!",
            Duration = 3,
            Image   = "4483345998",
        })
    end,
})

-- ============================================
-- SCHEDULE TAB
-- ============================================
local ScheduleSection = InfoTab:CreateSection("📋 Full Spawn Schedule")

InfoTab:CreateLabel("Fruits spawn every 45 min from 1h00")
InfoTab:CreateLabel("Window open: first 20 min after spawn")
InfoTab:CreateLabel("Despawn → next spawn: 25 min")
InfoTab:CreateLabel("Schedule is FIXED regardless of collection")
InfoTab:CreateLabel("─────────────────────────────")

for i, t in ipairs(SPAWN_TIMES) do
    if i <= 15 then -- Show first 15 entries to avoid clutter
        InfoTab:CreateLabel("Spawn #" .. i .. " → " .. formatTime(t))
    end
end

InfoTab:CreateLabel("... (continues every 45 min)")
