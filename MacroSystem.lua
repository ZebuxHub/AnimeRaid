--[[
    Anime Raid - Macro Recording System
    Record and replay unit skill usage
--]]

local MacroSystem = {}

--// Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

--// References
local LocalPlayer = Players.LocalPlayer

--// State
MacroSystem.IsRecording = false
MacroSystem.IsPlaying = false
MacroSystem.CurrentMacro = {}
MacroSystem.RecordStartTime = 0
MacroSystem.PlaybackThread = nil
MacroSystem.PlaybackMode = "Time" -- "Time" or "Wave"
MacroSystem.LastWave = 0

--// Config
MacroSystem.MacroFolderPath = "Zebux/Anime Raid/Macros"

-- Map name mappings
MacroSystem.MapNames = {
    ["1"] = "Leveling Path",
    ["2"] = "Snow Village",
    ["3"] = "Infinite Castle",
    ["4"] = "Jujutsu School",
    ["5"] = "Graveyard of the End"
}

MacroSystem.ModeNames = {
    ["1"] = "Normal",
    ["2"] = "Hard",
    ["3"] = "Infinite"
}

-- Create macro folder
if not isfolder("Zebux/Anime Raid") then
    makefolder("Zebux/Anime Raid")
end
if not isfolder(MacroSystem.MacroFolderPath) then
    makefolder(MacroSystem.MacroFolderPath)
end

--[[
    ========================================
    Macro Management Functions
    ========================================
--]]

-- Get all macro files
function MacroSystem.GetAllMacros()
    local macros = {}
    
    if isfolder(MacroSystem.MacroFolderPath) then
        local files = listfiles(MacroSystem.MacroFolderPath)
        
        for _, filePath in ipairs(files) do
            local fileName = filePath:match("([^/\\]+)%.json$")
            if fileName then
                table.insert(macros, fileName)
            end
        end
    end
    
    table.sort(macros)
    
    return macros
end

-- Save macro to file
function MacroSystem.SaveMacro(macroName, macroData)
    local success, err = pcall(function()
        local json = HttpService:JSONEncode(macroData)
        local filePath = MacroSystem.MacroFolderPath .. "/" .. macroName .. ".json"
        writefile(filePath, json)
        print(string.format("[Macro] Saved: %s (%d actions)", macroName, #macroData.actions))
    end)
    
    if not success then
        warn(string.format("[Macro] Failed to save: %s", tostring(err)))
    end
    
    return success
end

-- Load macro from file
function MacroSystem.LoadMacro(macroName)
    local filePath = MacroSystem.MacroFolderPath .. "/" .. macroName .. ".json"
    
    if not isfile(filePath) then
        warn(string.format("[Macro] File not found: %s", macroName))
        return nil
    end
    
    local success, result = pcall(function()
        local json = readfile(filePath)
        return HttpService:JSONDecode(json)
    end)
    
    if success then
        print(string.format("[Macro] Loaded: %s (%d actions)", macroName, #result.actions))
        return result
    else
        warn(string.format("[Macro] Failed to load: %s", tostring(result)))
        return nil
    end
end

-- Delete macro file
function MacroSystem.DeleteMacro(macroName)
    local filePath = MacroSystem.MacroFolderPath .. "/" .. macroName .. ".json"
    
    if not isfile(filePath) then
        warn(string.format("[Macro] File not found: %s", macroName))
        return false
    end
    
    local success, err = pcall(function()
        delfile(filePath)
        print(string.format("[Macro] Deleted: %s", macroName))
    end)
    
    if not success then
        warn(string.format("[Macro] Failed to delete: %s", tostring(err)))
    end
    
    return success
end

--[[
    ========================================
    Map Detection Functions
    ========================================
--]]

-- Get current map ID
function MacroSystem.GetCurrentMapID()
    local success, mapData = pcall(function()
        local gameData = workspace:FindFirstChild("游戏数据")
        if not gameData then return nil end
        
        local mapID = gameData:FindFirstChild("MapID") and gameData.MapID.Value or ""
        local mapType = gameData:FindFirstChild("MapType") and gameData.MapType.Value or ""
        local mapTag = gameData:FindFirstChild("MapOnlyTag") and gameData.MapOnlyTag.Value or ""
        
        return {
            MapID = mapID,
            MapType = mapType,
            MapOnlyTag = mapTag,
            FullID = string.format("%s_%s_%s", mapID, mapType, mapTag)
        }
    end)
    
    return success and mapData or nil
end

-- Get map display name
function MacroSystem.GetMapDisplayName()
    local mapData = MacroSystem.GetCurrentMapID()
    
    if not mapData then
        return "Not in game"
    end
    
    local mapName = MacroSystem.MapNames[tostring(mapData.MapID)] or "Unknown"
    local modeName = MacroSystem.ModeNames[tostring(mapData.MapType)] or "Unknown"
    
    -- For infinite mode, chapter is always 1
    if mapData.MapType == "3" then
        return string.format("%s | Infinite", mapName)
    else
        return string.format("%s | Ch.%s | %s", mapName, mapData.MapOnlyTag or "?", modeName)
    end
end

-- Check if game is in fight state
function MacroSystem.IsInFight()
    local success, isFighting = pcall(function()
        local gameData = workspace:FindFirstChild("游戏数据")
        if not gameData then return false end
        
        local gameState = gameData:FindFirstChild("GameState")
        if not gameState then return false end
        
        return gameState.Value == "Fight"
    end)
    
    return success and isFighting or false
end

-- Get current wave
function MacroSystem.GetCurrentWave()
    local success, wave = pcall(function()
        local gameData = workspace:FindFirstChild("游戏数据")
        if not gameData then return 0 end
        
        local nowWave = gameData:FindFirstChild("NowWave")
        if not nowWave then return 0 end
        
        return nowWave.Value
    end)
    
    return success and wave or 0
end

--[[
    ========================================
    Recording Functions
    ========================================
--]]

-- Get current game time
function MacroSystem.GetGameTime()
    local success, time = pcall(function()
        return workspace:FindFirstChild("服务器存在时间") and workspace["服务器存在时间"].Value or 0
    end)
    return success and time or 0
end

-- Setup recording hooks
function MacroSystem.SetupRecordingHooks()
    task.spawn(function()
        task.wait(5) -- Wait for game to load
        
        local success, err = pcall(function()
            -- Wait for game data to exist
            local gameData = workspace:WaitForChild("游戏数据", 30)
            if not gameData then 
                warn("[Macro] Game data not found")
                return 
            end
            
            local heroFolder = gameData:WaitForChild("英雄", 30)
            if not heroFolder then 
                warn("[Macro] Hero folder not found")
                return 
            end
            
            print("[Macro] Setting up RemoteEvent hooks for recording...")
            
            -- Hook each hero's RemoteEvent to capture SUCCESSFUL skill usage
            local function hookHero(hero)
                task.spawn(function()
                    -- Wait for RemoteEvent to exist
                    local remoteEvent = hero:WaitForChild("RemoteEvent", 30)
                    if not remoteEvent then 
                        warn(string.format("[Macro] RemoteEvent not found for hero: %s", hero.Name))
                        return 
                    end
                    
                    -- Wait a bit more to ensure it's fully loaded
                    task.wait(0.5)
                    
                    -- Store the original FireServer
                    local originalFireServer = remoteEvent.FireServer
                    
                    if not originalFireServer then
                        warn(string.format("[Macro] FireServer not found for hero: %s", hero.Name))
                        return
                    end
                    
                    -- Replace FireServer with our hook
                    remoteEvent.FireServer = function(self, ...)
                        local args = {...}
                        
                        -- Debug: Print when skill is fired
                        print(string.format("[Macro] Skill fired for hero: %s, Recording=%s, InFight=%s", 
                            hero.Name, tostring(MacroSystem.IsRecording), tostring(MacroSystem.IsInFight())))
                        
                        -- Call original FIRST (game works normally)
                        local result = originalFireServer(self, ...)
                        
                        -- Then record if we're recording and in fight
                        if MacroSystem.IsRecording and MacroSystem.IsInFight() then
                            print(string.format("[Macro] Recording action for hero: %s", hero.Name))
                            task.defer(function()
                                MacroSystem.RecordAction(hero.Name, unpack(args))
                            end)
                        end
                        
                        return result
                    end
                    
                    print(string.format("[Macro] Hooked hero: %s", hero.Name))
                end)
            end
            
            -- Hook existing heroes
            for _, hero in ipairs(heroFolder:GetChildren()) do
                hookHero(hero)
            end
            
            -- Hook new heroes when they spawn
            heroFolder.ChildAdded:Connect(function(hero)
                hookHero(hero)
            end)
            
            print("[Macro] RemoteEvent hooks setup complete! Recording will not block game actions.")
        end)
        
        if not success then
            warn(string.format("[Macro] Failed to setup hooks: %s", tostring(err)))
        end
    end)
end

-- Start recording
function MacroSystem.StartRecording()
    if MacroSystem.IsRecording then
        warn("[Macro] Already recording!")
        return false
    end
    
    local mapData = MacroSystem.GetCurrentMapID()
    
    MacroSystem.IsRecording = true
    MacroSystem.CurrentMacro = {
        actions = {},
        startTime = MacroSystem.GetGameTime(),
        startWave = MacroSystem.GetCurrentWave(),
        version = 1,
        mapData = mapData
    }
    MacroSystem.RecordStartTime = MacroSystem.GetGameTime()
    
    print(string.format("[Macro] Recording started at game time: %.2f, wave: %d", 
        MacroSystem.RecordStartTime, MacroSystem.CurrentMacro.startWave))
    if mapData then
        print(string.format("[Macro] Map: %s", MacroSystem.GetMapDisplayName()))
    end
    
    return true
end

-- Record an action (called by hooked RemoteEvent)
function MacroSystem.RecordAction(heroId, ...)
    if not MacroSystem.IsRecording then return end
    
    local currentTime = MacroSystem.GetGameTime()
    local currentWave = MacroSystem.GetCurrentWave()
    local relativeTime = currentTime - MacroSystem.RecordStartTime
    local relativeWave = currentWave - MacroSystem.CurrentMacro.startWave
    
    local action = {
        time = relativeTime,
        wave = currentWave,
        relativeWave = relativeWave,
        heroId = heroId,
        args = {...}
    }
    
    table.insert(MacroSystem.CurrentMacro.actions, action)
    print(string.format("[Macro] Recorded action #%d at %.2fs (Wave %d): Hero=%s", 
        #MacroSystem.CurrentMacro.actions, relativeTime, currentWave, heroId))
end

-- Stop recording
function MacroSystem.StopRecording()
    if not MacroSystem.IsRecording then
        warn("[Macro] Not recording!")
        return nil
    end
    
    MacroSystem.IsRecording = false
    
    local recordedMacro = MacroSystem.CurrentMacro
    MacroSystem.CurrentMacro = {}
    
    print(string.format("[Macro] Recording stopped. Recorded %d actions", #recordedMacro.actions))
    
    return recordedMacro
end

--[[
    ========================================
    Playback Functions
    ========================================
--]]

-- Reset playback state (call when game restarts)
function MacroSystem.ResetPlayback()
    MacroSystem.LastWave = 0
    print("[Macro] Playback state reset")
end

-- Play macro
function MacroSystem.PlayMacro(macroData, loop, mode)
    if MacroSystem.IsPlaying then
        warn("[Macro] Already playing a macro!")
        return false
    end
    
    if not macroData or not macroData.actions or #macroData.actions == 0 then
        warn("[Macro] Invalid or empty macro!")
        return false
    end
    
    MacroSystem.IsPlaying = true
    MacroSystem.PlaybackMode = mode or "Time"
    MacroSystem.LastWave = 0
    
    print(string.format("[Macro] Starting playback (%d actions, loop=%s, mode=%s)", 
        #macroData.actions, tostring(loop), MacroSystem.PlaybackMode))
    
    MacroSystem.PlaybackThread = task.spawn(function()
        local playCount = 0
        
        repeat
            -- Wait for fight state (PAUSE, not stop)
            while MacroSystem.IsPlaying do
                if MacroSystem.IsInFight() then
                    break
                end
                print("[Macro] Paused - waiting for fight state...")
                task.wait(1)
            end
            
            if not MacroSystem.IsPlaying then
                break
            end
            
            playCount = playCount + 1
            print(string.format("[Macro] Playback iteration #%d (Mode: %s)", playCount, MacroSystem.PlaybackMode))
            
            if MacroSystem.PlaybackMode == "Time" then
                -- Time-based playback
                local startTime = MacroSystem.GetGameTime()
                
                for i, action in ipairs(macroData.actions) do
                    -- Check if still playing
                    if not MacroSystem.IsPlaying then
                        print("[Macro] Playback stopped by user")
                        break
                    end
                    
                    -- PAUSE if not in fight (don't break, just wait)
                    while MacroSystem.IsPlaying and not MacroSystem.IsInFight() do
                        print("[Macro] Paused - waiting for fight state...")
                        task.wait(1)
                    end
                    
                    if not MacroSystem.IsPlaying then
                        break
                    end
                    
                    -- Wait until the action's time
                    local currentTime = MacroSystem.GetGameTime()
                    local elapsedTime = currentTime - startTime
                    local waitTime = action.time - elapsedTime
                    
                    if waitTime > 0 then
                        task.wait(waitTime)
                    end
                    
                    -- Fire the skill
                    MacroSystem.FireAction(action, i, #macroData.actions)
                end
            else
                -- Wave-based playback
                MacroSystem.LastWave = MacroSystem.GetCurrentWave()
                local startWave = MacroSystem.LastWave
                
                for i, action in ipairs(macroData.actions) do
                    -- Check if still playing
                    if not MacroSystem.IsPlaying then
                        print("[Macro] Playback stopped by user")
                        break
                    end
                    
                    -- PAUSE if not in fight (don't break, just wait)
                    while MacroSystem.IsPlaying and not MacroSystem.IsInFight() do
                        print("[Macro] Paused - waiting for fight state...")
                        task.wait(1)
                    end
                    
                    if not MacroSystem.IsPlaying then
                        break
                    end
                    
                    -- Wait until the action's wave
                    while MacroSystem.IsPlaying and MacroSystem.IsInFight() do
                        local currentWave = MacroSystem.GetCurrentWave()
                        local relativeWave = currentWave - startWave
                        
                        if relativeWave >= action.relativeWave then
                            break
                        end
                        
                        task.wait(0.1)
                    end
                    
                    if not MacroSystem.IsPlaying then
                        break
                    end
                    
                    -- Fire the skill
                    MacroSystem.FireAction(action, i, #macroData.actions)
                    task.wait(0.1) -- Small delay between actions
                end
            end
            
            -- Wait for fight to end before looping
            if loop and MacroSystem.IsPlaying then
                print("[Macro] Waiting for fight to end before next loop...")
                while MacroSystem.IsPlaying do
                    if not MacroSystem.IsInFight() then
                        break
                    end
                    task.wait(0.5)
                end
                
                -- Wait for next fight to start
                print("[Macro] Waiting for next fight to start...")
                while MacroSystem.IsPlaying do
                    if MacroSystem.IsInFight() then
                        MacroSystem.ResetPlayback()
                        task.wait(2) -- Give game time to load
                        break
                    end
                    task.wait(0.5)
                end
            end
            
        until not loop or not MacroSystem.IsPlaying
        
        MacroSystem.IsPlaying = false
        print("[Macro] Playback finished")
    end)
    
    return true
end

-- Fire a single action
function MacroSystem.FireAction(action, index, total)
    local success = pcall(function()
        local gameData = workspace:FindFirstChild("游戏数据")
        if not gameData then return end
        
        local heroFolder = gameData:FindFirstChild("英雄")
        if not heroFolder then return end
        
        local hero = heroFolder:FindFirstChild(action.heroId)
        if not hero then
            warn(string.format("[Macro] Hero not found: %s", action.heroId))
            return
        end
        
        local remoteEvent = hero:FindFirstChild("RemoteEvent")
        if not remoteEvent then
            warn(string.format("[Macro] RemoteEvent not found for hero: %s", action.heroId))
            return
        end
        
        remoteEvent:FireServer(unpack(action.args))
        print(string.format("[Macro] Fired skill for hero: %s (action %d/%d)", 
            action.heroId, index, total))
    end)
    
    if not success then
        warn(string.format("[Macro] Failed to fire action #%d", index))
    end
end

-- Stop playback
function MacroSystem.StopPlayback()
    if not MacroSystem.IsPlaying then
        return false
    end
    
    MacroSystem.IsPlaying = false
    
    if MacroSystem.PlaybackThread then
        task.cancel(MacroSystem.PlaybackThread)
        MacroSystem.PlaybackThread = nil
    end
    
    print("[Macro] Playback stopped")
    return true
end

--[[
    ========================================
    Map-Specific Macro Functions
    ========================================
--]]

-- Get macro for current map
function MacroSystem.GetMacroForMap(macroMap, mapID, mapType, mapTag)
    -- Try exact match first (Map_Type_Tag)
    local fullID = string.format("%s_%s_%s", mapID, mapType, mapTag)
    local macroName = macroMap[fullID]
    if macroName then
        return macroName
    end
    
    -- Try without tag (Map_Type)
    local simpleID = string.format("%s_%s", mapID, mapType)
    macroName = macroMap[simpleID]
    if macroName then
        return macroName
    end
    
    -- Try just MapID
    macroName = macroMap[mapID]
    if macroName then
        return macroName
    end
    
    return nil
end

-- Create assignment key for display
function MacroSystem.CreateAssignmentKey(mapID, mapType, mapTag)
    return string.format("%s_%s_%s", mapID, mapType, mapTag)
end

-- Format assignment key for display
function MacroSystem.FormatAssignmentDisplay(key)
    local parts = {}
    for part in string.gmatch(key, "[^_]+") do
        table.insert(parts, part)
    end
    
    if #parts < 2 then
        return key
    end
    
    local mapID = parts[1]
    local mapType = parts[2]
    local mapTag = parts[3] or "?"
    
    local mapName = MacroSystem.MapNames[mapID] or "Unknown"
    local modeName = MacroSystem.ModeNames[mapType] or "Unknown"
    
    if mapType == "3" then
        return string.format("%s | Infinite", mapName)
    else
        return string.format("%s | Ch.%s | %s", mapName, mapTag, modeName)
    end
end

return MacroSystem
