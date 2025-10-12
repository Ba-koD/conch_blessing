local ConchBlessing_Config = require("scripts.conch_blessing_config")
local ConchBlessing_MCM = require("scripts.conch_blessing_mcm")
local isc = require("scripts.lib.isaacscript-common")
local SaveManager = require("scripts.lib.save_manager")

local mod = RegisterMod("Conch's Blessing", 1)
ConchBlessing = isc:upgradeMod(mod, {
    isc.ISCFeature.PLAYER_INVENTORY,
    isc.ISCFeature.ROOM_HISTORY,
    isc.ISCFeature.GRID_ENTITY_COLLISION_DETECTION,
})
-- ConchBlessing now contains the upgraded mod, but mod variable keeps the original RegisterMod reference
ConchBlessing.originalMod = mod

-- Debug: SaveManager initialization started
Isaac.ConsoleOutput("[Core] SaveManager initialization started\n")

-- Make SaveManager globally accessible
ConchBlessing.SaveManager = SaveManager
Isaac.ConsoleOutput("[Core] ConchBlessing.SaveManager set\n")

-- Initialize SaveManager with the original mod reference
Isaac.ConsoleOutput("[Core] SaveManager.Init() called\n")
SaveManager.Init(mod)
Isaac.ConsoleOutput("[Core] SaveManager.Init() completed\n")

-- Register SaveManager PRE_DATA_SAVE callback to clean EntityEffect objects
Isaac.ConsoleOutput("[Core] Registering SaveManager PRE_DATA_SAVE callback\n")
local callbackKey = mod.__SAVEMANAGER_UNIQUE_KEY .. SaveManager.SaveCallbacks.PRE_DATA_SAVE
mod:AddCallback(callbackKey, function(saveData)
    -- Clean dragon EntityEffect objects before saving
    if ConchBlessing.dragon and ConchBlessing.dragon.onPreDataSave then
        return ConchBlessing.dragon.onPreDataSave(saveData)
    end
    return saveData
end)
Isaac.ConsoleOutput("[Core] SaveManager PRE_DATA_SAVE callback registered\n")

-- Check SaveManager status
Isaac.ConsoleOutput("[Core] SaveManager.IsLoaded() = " .. tostring(SaveManager.IsLoaded()) .. "\n")
Isaac.ConsoleOutput("[Core] SaveManager.VERSION = " .. tostring(SaveManager.VERSION) .. "\n")

-- Initialize config after SaveManager is initialized
Isaac.ConsoleOutput("[Core] ConchBlessing_Config.Init() called\n")
ConchBlessing_Config.Init(ConchBlessing)
Isaac.ConsoleOutput("[Core] ConchBlessing_Config.Init() completed\n")

-- MCM setup
Isaac.ConsoleOutput("[Core] MCM.Setup() called\n")
ConchBlessing_MCM.Setup(ConchBlessing)
Isaac.ConsoleOutput("[Core] MCM.Setup() completed\n")

-- Register callback for MCM config loading after game starts
Isaac.ConsoleOutput("[Core] Registering MC_POST_GAME_STARTED callback\n")
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
    Isaac.ConsoleOutput("[Core] Game started, trying to load MCM config\n")
    
    -- Reset multiplier display data for new game
    if ConchBlessing.stats and ConchBlessing.stats.multiplierDisplay then
        Isaac.ConsoleOutput("[Core] Resetting multiplier display data\n")
        ConchBlessing.stats.multiplierDisplay:ResetForNewGame()
    end
    
    -- Reset unified multiplier system for new game
    if ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers then
        Isaac.ConsoleOutput("[Core] Resetting unified multiplier system\n")
        local um = ConchBlessing.stats.unifiedMultipliers
        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                um:ResetPlayer(player)
            end
        end
        -- Clear any pending deferred cache updates
        um._hasPending = false
        for i = 0, (Game():GetNumPlayers() - 1) do
            local player = Isaac.GetPlayer(i)
            if player then
                local pid = player:GetPlayerType()
                if um[pid] then
                    um[pid].pendingCache = {}
                end
            end
        end
        -- Force a fresh cache rebuild to base values
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                player:AddCacheFlags(CacheFlag.CACHE_ALL)
                player:EvaluateItems()
            end
        end
    end
    
    -- Reset all item tracking states for new game
    Isaac.ConsoleOutput("[Core] Resetting item tracking states\n")
    if ConchBlessing.oralsteroids and ConchBlessing.oralsteroids._lastItemCount then
        ConchBlessing.oralsteroids._lastItemCount = {}
        Isaac.ConsoleOutput("[Core] Reset oralsteroids._lastItemCount\n")
    end
    if ConchBlessing.injectablsteroids and ConchBlessing.injectablsteroids._lastUseCount then
        ConchBlessing.injectablsteroids._lastUseCount = {}
        Isaac.ConsoleOutput("[Core] Reset injectablsteroids._lastUseCount\n")
    end
    if ConchBlessing.powertraining and ConchBlessing.powertraining._lastUseCount then
        ConchBlessing.powertraining._lastUseCount = {}
        Isaac.ConsoleOutput("[Core] Reset powertraining._lastUseCount\n")
    end
    
    if ConchBlessing.SaveManager and ConchBlessing.SaveManager.IsLoaded() then
        Isaac.ConsoleOutput("[Core] SaveManager loaded, starting MCM config load\n")
        ConchBlessing_MCM.loadConfigFromSaveManager(ConchBlessing)
    else
        Isaac.ConsoleOutput("[Core] SaveManager not loaded, using default settings\n")
    end

    -- New run safeguard: if not continued, clear run-scoped saved multipliers to prevent carry-over
    if not isContinued and ConchBlessing.SaveManager then
        local player = Isaac.GetPlayer(0)
        if player then
            local SaveManager = ConchBlessing.SaveManager
            local playerSave = SaveManager.GetRunSave(player)
            if playerSave then
                playerSave.unifiedMultipliers = nil
                playerSave.oralSteroids = nil
                playerSave.injectableSteroids = nil
                playerSave.powerTraining = nil
                playerSave.dragon = nil
                -- Reset Time = Power trinket run-scoped data on new run (R key)
                playerSave.timePower = nil
                SaveManager.Save()
                Isaac.ConsoleOutput("[Core] Cleared run-scope saved multipliers for new run\n")
            end
        end
    end
end)

-- sound IDs
ConchBlessing.Sounds = {
    -- add sound IDs here (e.g., 1 = "sfx/sfx_item_pickup.wav")
}

-- debug print functions
ConchBlessing.printDebug = function(text)
    if ConchBlessing.Config.debugMode then
        local frame = (Game and Game():GetFrameCount()) or -1
        Isaac.DebugString("[ConchBlessing][DEBUG][F:" .. tostring(frame) .. "] " .. tostring(text))
        Isaac.ConsoleOutput("[ConchBlessing][DEBUG][F:" .. tostring(frame) .. "] " .. tostring(text) .. "\n")
    end
end

ConchBlessing.printError = function(text)
    Isaac.ConsoleOutput("[ConchBlessing][ERROR] " .. tostring(text) .. "\n")
end

ConchBlessing.print = function(text)
    Isaac.ConsoleOutput("[ConchBlessing] " .. tostring(text) .. "\n")
end

-- load stats library first (before items and upgrade systems)
local statsSuccess, statsErr = pcall(function()
    require("scripts.lib.stats")
end)
if statsSuccess then
    ConchBlessing.print("Stats library loaded successfully!")
else
    ConchBlessing.printError("Stats library load failed: " .. tostring(statsErr))
end

-- load items and management
local itemsSuccess, itemsErr = pcall(function()
    require("scripts/conch_blessing_items")
end)
if not itemsSuccess then
    ConchBlessing.printError("Item system load failed: " .. tostring(itemsErr))
end

-- load upgrade system
local upgradeSuccess, upgradeErr = pcall(function()
    require("scripts/conch_blessing_upgrade")
end)
if not upgradeSuccess then
    ConchBlessing.printError("Upgrade system load failed: " .. tostring(upgradeErr))
end

-- Initialize stats system after everything is loaded
if ConchBlessing.stats and ConchBlessing.stats.multiplierDisplay then
    ConchBlessing.stats.multiplierDisplay:Initialize()
    ConchBlessing.print("Stats system initialized!")
else
    ConchBlessing.printError("Stats system not found during initialization!")
end

-- print message when mode is loaded
ConchBlessing.print("Conch's Blessing v" .. ConchBlessing.Config.Version .. " mode loaded!") 