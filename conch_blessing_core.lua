local ConchBlessing_Config = require("conch_blessing_config")
local ConchBlessing_MCM = require("conch_blessing_mcm")
local isc = require("scripts.lib.isaacscript-common")

ConchBlessing = RegisterMod("Conch's Blessing", 1)
ConchBlessing = isc:upgradeMod(ConchBlessing, {
    isc.ISCFeature.PLAYER_INVENTORY,
    isc.ISCFeature.ROOM_HISTORY,
    isc.ISCFeature.GRID_ENTITY_COLLISION_DETECTION,
})
ConchBlessing_Config.Init(ConchBlessing)
ConchBlessing_MCM.Setup(ConchBlessing)

-- sound IDs
ConchBlessing.Sounds = {
    -- add sound IDs here (e.g., 1 = "sfx/sfx_item_pickup.wav")
}

-- debug print functions
ConchBlessing.printDebug = function(text)
    if ConchBlessing.Config.debugMode then
        Isaac.ConsoleOutput("[ConchBlessing][DEBUG] " .. tostring(text) .. "\n")
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