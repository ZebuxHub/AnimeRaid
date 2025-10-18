-- Universal.lua - Universal Systems (Anti-AFK & Auto Reconnect)
-- Author: Zebux
-- Version: 1.0

local Universal = {}

-- Services
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")

-- State variables
local antiAFKEnabled = false
local antiAFKConnection = nil
local autoReconnectEnabled = false
local autoReconnectConnection = nil
local LocalPlayer = Players.LocalPlayer

--[[
    ========================================
    Anti-AFK System
    ========================================
]]

-- Enable Anti-AFK
function Universal.EnableAntiAFK()
    if antiAFKEnabled then return end
    
    antiAFKEnabled = true
    antiAFKConnection = LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
    
    print("[Universal] Anti-AFK enabled")
end

-- Disable Anti-AFK
function Universal.DisableAntiAFK()
    if not antiAFKEnabled then return end
    
    antiAFKEnabled = false
    if antiAFKConnection then
        antiAFKConnection:Disconnect()
        antiAFKConnection = nil
    end
    
    print("[Universal] Anti-AFK disabled")
end

-- Get Anti-AFK status
function Universal.GetAntiAFKStatus()
    return antiAFKEnabled
end

--[[
    ========================================
    Auto Reconnect System
    ========================================
]]

-- Enable Auto Reconnect
function Universal.EnableAutoReconnect()
    if autoReconnectEnabled then return end
    
    autoReconnectEnabled = true
    
    -- Monitor for error prompts
    local success, coreGui = pcall(function()
        return game.CoreGui:WaitForChild("RobloxPromptGui", 5)
    end)
    
    if not success or not coreGui then
        warn("[Universal] Failed to get RobloxPromptGui")
        autoReconnectEnabled = false
        return
    end
    
    local promptOverlay = coreGui:WaitForChild("promptOverlay", 5)
    if not promptOverlay then
        warn("[Universal] Failed to get promptOverlay")
        autoReconnectEnabled = false
        return
    end
    
    autoReconnectConnection = promptOverlay.ChildAdded:Connect(function(child)
        if child.Name == "ErrorPrompt" and autoReconnectEnabled then
            print("[Universal] Error detected - reconnecting...")
            task.wait(0.5)
            
            repeat
                local success = pcall(function()
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                end)
                
                if not success then
                    warn("[Universal] Reconnect failed, retrying...")
                end
                
                task.wait(2)
            until false
        end
    end)
    
    print("[Universal] Auto Reconnect enabled")
end

-- Disable Auto Reconnect
function Universal.DisableAutoReconnect()
    if not autoReconnectEnabled then return end
    
    autoReconnectEnabled = false
    if autoReconnectConnection then
        autoReconnectConnection:Disconnect()
        autoReconnectConnection = nil
    end
    
    print("[Universal] Auto Reconnect disabled")
end

-- Get Auto Reconnect status
function Universal.GetAutoReconnectStatus()
    return autoReconnectEnabled
end

--[[
    ========================================
    Cleanup
    ========================================
]]

function Universal.Cleanup()
    Universal.DisableAntiAFK()
    Universal.DisableAutoReconnect()
end

return Universal

