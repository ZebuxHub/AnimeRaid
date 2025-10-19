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
MacroSystem.RemoteConnection = nil

--// Config
MacroSystem.MacroFolderPath = "Zebux/Anime Raid/Macros"

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
    if not mapData then return "Unknown Map" end
    
    return string.format("Map: %s | Type: %s | Tag: %s", 
        mapData.MapID, mapData.MapType, mapData.MapOnlyTag)
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
        version = 1,
        mapData = mapData -- Store map info
    }
    MacroSystem.RecordStartTime = MacroSystem.GetGameTime()
    
    print(string.format("[Macro] Recording started at game time: %.2f", MacroSystem.RecordStartTime))
    if mapData then
        print(string.format("[Macro] Map: %s", mapData.FullID))
    end
    
    -- Hook into RemoteEvent
    local success = pcall(function()
        local gameData = workspace:WaitForChild("游戏数据", 5)
        if not gameData then return end
        
        local heroFolder = gameData:WaitForChild("英雄", 5)
        if not heroFolder then return end
        
        -- Monitor all hero RemoteEvents
        local function hookHero(hero)
            local remoteEvent = hero:FindFirstChild("RemoteEvent")
            if remoteEvent then
                -- Store original namecall
                local oldNamecall
                oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                    local method = getnamecallmethod()
                    local args = {...}
                    
                    if method == "FireServer" and self == remoteEvent and MacroSystem.IsRecording then
                        local currentTime = MacroSystem.GetGameTime()
                        local relativeTime = currentTime - MacroSystem.RecordStartTime
                        
                        -- Record the action
                        local action = {
                            time = relativeTime,
                            heroId = hero.Name,
                            args = args
                        }
                        
                        table.insert(MacroSystem.CurrentMacro.actions, action)
                        print(string.format("[Macro] Recorded action #%d at %.2fs: Hero=%s", 
                            #MacroSystem.CurrentMacro.actions, relativeTime, hero.Name))
                    end
                    
                    return oldNamecall(self, ...)
                end)
            end
        end
        
        -- Hook existing heroes
        for _, hero in ipairs(heroFolder:GetChildren()) do
            hookHero(hero)
        end
        
        -- Hook new heroes
        heroFolder.ChildAdded:Connect(hookHero)
    end)
    
    if not success then
        warn("[Macro] Failed to hook RemoteEvents")
        MacroSystem.IsRecording = false
        return false
    end
    
    return true
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

-- Play macro
function MacroSystem.PlayMacro(macroData, loop)
    if MacroSystem.IsPlaying then
        warn("[Macro] Already playing a macro!")
        return false
    end
    
    if not macroData or not macroData.actions or #macroData.actions == 0 then
        warn("[Macro] Invalid or empty macro!")
        return false
    end
    
    MacroSystem.IsPlaying = true
    print(string.format("[Macro] Starting playback (%d actions, loop=%s)", #macroData.actions, tostring(loop)))
    
    MacroSystem.PlaybackThread = task.spawn(function()
        local playCount = 0
        
        repeat
            playCount = playCount + 1
            print(string.format("[Macro] Playback iteration #%d", playCount))
            
            local startTime = MacroSystem.GetGameTime()
            
            for i, action in ipairs(macroData.actions) do
                if not MacroSystem.IsPlaying then
                    print("[Macro] Playback stopped by user")
                    return
                end
                
                -- Wait until the action's time
                local currentTime = MacroSystem.GetGameTime()
                local elapsedTime = currentTime - startTime
                local waitTime = action.time - elapsedTime
                
                if waitTime > 0 then
                    task.wait(waitTime)
                end
                
                -- Fire the skill
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
                        action.heroId, i, #macroData.actions))
                end)
                
                if not success then
                    warn(string.format("[Macro] Failed to fire action #%d", i))
                end
            end
            
            -- Wait a bit before looping
            if loop and MacroSystem.IsPlaying then
                task.wait(1)
            end
            
        until not loop or not MacroSystem.IsPlaying
        
        MacroSystem.IsPlaying = false
        print("[Macro] Playback finished")
    end)
    
    return true
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
function MacroSystem.GetMacroForCurrentMap(macroMap)
    local mapData = MacroSystem.GetCurrentMapID()
    if not mapData then return nil end
    
    -- Try exact match first
    local macroName = macroMap[mapData.FullID]
    if macroName then
        return macroName
    end
    
    -- Try without tag
    local simpleID = string.format("%s_%s", mapData.MapID, mapData.MapType)
    macroName = macroMap[simpleID]
    if macroName then
        return macroName
    end
    
    -- Try just MapID
    macroName = macroMap[mapData.MapID]
    if macroName then
        return macroName
    end
    
    return nil
end

-- Assign macro to current map
function MacroSystem.AssignMacroToCurrentMap(macroName, macroMap)
    local mapData = MacroSystem.GetCurrentMapID()
    if not mapData then
        warn("[Macro] Cannot detect current map!")
        return false
    end
    
    macroMap[mapData.FullID] = macroName
    print(string.format("[Macro] Assigned '%s' to map: %s", macroName, mapData.FullID))
    return true
end

-- Remove macro assignment for current map
function MacroSystem.RemoveMacroFromCurrentMap(macroMap)
    local mapData = MacroSystem.GetCurrentMapID()
    if not mapData then return false end
    
    macroMap[mapData.FullID] = nil
    print(string.format("[Macro] Removed macro assignment for map: %s", mapData.FullID))
    return true
end

return MacroSystem

