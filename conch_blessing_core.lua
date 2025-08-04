local ConchBlessing_Config = require("conch_blessing_config")

-- RegisterMod
ConchBlessing = RegisterMod("Conch's Blessing", 1)

ConchBlessing_Config.Init(ConchBlessing)

-- sound IDs
ConchBlessing.Sounds = {
    -- add sound IDs here
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