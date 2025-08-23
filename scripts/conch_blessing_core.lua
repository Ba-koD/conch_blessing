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
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    Isaac.ConsoleOutput("[Core] Game started, trying to load MCM config\n")
    if ConchBlessing.SaveManager and ConchBlessing.SaveManager.IsLoaded() then
        Isaac.ConsoleOutput("[Core] SaveManager loaded, starting MCM config load\n")
        ConchBlessing_MCM.loadConfigFromSaveManager(ConchBlessing)
    else
        Isaac.ConsoleOutput("[Core] SaveManager not loaded, using default settings\n")
    end
end)

-- sound IDs
ConchBlessing.Sounds = {
    -- add sound IDs here (e.g., 1 = "sfx/sfx_item_pickup.wav")
}

-- debug print functions
ConchBlessing.printDebug = function(text)
    if ConchBlessing.Config.debugMode then
        Isaac.ConsoleOutput("[ConchBlessing][DEBUG] " .. tostring(text) .. "\n")
    end
    -- Enable SaveManager debug
    if ConchBlessing.SaveManager then
        ConchBlessing.SaveManager.Debug = ConchBlessing.Config.debugMode
        Isaac.ConsoleOutput("[Core] SaveManager.Debug = " .. tostring(ConchBlessing.Config.debugMode) .. "\n")
    end
end

ConchBlessing.printError = function(text)
    Isaac.ConsoleOutput("[ConchBlessing][ERROR] " .. tostring(text) .. "\n")
end

ConchBlessing.print = function(text)
    Isaac.ConsoleOutput("[ConchBlessing] " .. tostring(text) .. "\n")
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

-- print message when mode is loaded
ConchBlessing.print("Conch's Blessing v" .. ConchBlessing.Config.Version .. " mode loaded!") 