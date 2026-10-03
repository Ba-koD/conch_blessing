local ConchBlessing_MCM = {}

---@diagnostic disable-next-line: undefined-global
local ModConfigMenu = ModConfigMenu

local function printDebug(mod, message)
    if type(mod) ~= "table"
        or type(mod.Config) ~= "table"
        or mod.Config.debugMode ~= true
    then
        return
    end
    if type(mod.printDebug) == "function" then
        mod.printDebug("[MCM] " .. tostring(message))
        return
    end
    local text = "[ConchBlessing][DEBUG][MCM] " .. tostring(message)
    Isaac.DebugString(text)
    Isaac.ConsoleOutput(text .. "\n")
end

local function printError(mod, message)
    if type(mod) == "table" and type(mod.printError) == "function" then
        mod.printError("[MCM] " .. tostring(message))
        return
    end
    local text = "[ConchBlessing][ERROR][MCM] " .. tostring(message)
    Isaac.DebugString(text)
    Isaac.ConsoleOutput(text .. "\n")
end

function ConchBlessing_MCM.Setup(mod)
    if not ModConfigMenu then
        return
    end

    local ConchBlessing_Config = require("scripts.conch_blessing_config")
    -- Menu text is ui.mcm in scripts/locale/en.lua. It is read in English on
    -- purpose: Mod Config Menu's fonts are not known to cover every language.
    -- Core calls Setup unprotected, so a broken text module only costs the menu.
    local loaded, Locale = pcall(require, "scripts.locale.init")
    if not loaded then
        printError(mod, "menu text failed to load: " .. tostring(Locale))
        return
    end
    local function text(key, ...)
        return Locale.textIn("en", "ui.mcm." .. key, ...)
    end
    local function lines(key)
        return Locale.linesIn("en", "ui.mcm." .. key)
    end
    local function onOff(enabled)
        return text(enabled and "on" or "off")
    end
    local GENERAL = text("tab_general")
    local SPAWN = text("tab_spawn")
    local category = "Conch's Blessing v" .. tostring(mod.Config.Version or "")

    -- Recreate category to reflect any text changes
    ModConfigMenu.RemoveCategory(category)
    ModConfigMenu.AddSpace(category, GENERAL)
    ModConfigMenu.AddText(category, GENERAL, text("options_title"))

    -- Debug mode toggle
    ModConfigMenu.AddSetting(category, GENERAL, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return mod.Config.debugMode and true or false
        end,
        Display = function()
            return text("debug_mode", onOff(mod.Config.debugMode))
        end,
        OnChange = function(b)
            mod.Config.debugMode = (b == true)
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
        end,
        Info = lines("debug_mode_info")
    })

    -- Reset to Default (General)
    ModConfigMenu.AddSetting(category, GENERAL, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return false
        end,
        Display = function()
            return text("reset")
        end,
        OnChange = function(b)
            if b == true then
                ConchBlessing_Config.Reset(mod)
                ConchBlessing_MCM.saveConfigToSaveManager(mod)
                if mod.EID and type(mod.EID.registerAllItems) == "function" then
                    mod.EID.registerAllItems()
                end
            end
        end,
        Info = lines("reset_info")
    })
    
    -- Spawn - Collectibles
    ModConfigMenu.AddText(category, SPAWN, text("spawn_title"))
    ModConfigMenu.AddSetting(category, SPAWN, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return mod.Config.spawnCollectibles and true or false
        end,
        Display = function()
            return text("spawn_collectibles", onOff(mod.Config.spawnCollectibles))
        end,
        OnChange = function(b)
            mod.Config.spawnCollectibles = (b == true)
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
        end,
        Info = lines("spawn_collectibles_info")
    })

    -- Spawn - Trinkets
    ModConfigMenu.AddSetting(category, SPAWN, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return mod.Config.spawnTrinkets and true or false
        end,
        Display = function()
            return text("spawn_trinkets", onOff(mod.Config.spawnTrinkets))
        end,
        OnChange = function(b)
            mod.Config.spawnTrinkets = (b == true)
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
        end,
        Info = lines("spawn_trinkets_info")
    })
end

function ConchBlessing_MCM.saveConfigToSaveManager(mod)
    printDebug(mod, "saveConfigToSaveManager started")
    
    if not mod.SaveManager then
        printError(mod, "SaveManager is nil; configuration was not saved.")
        return false
    end
    printDebug(mod, "SaveManager exists")
    
    if not mod.SaveManager.IsLoaded() then
        printError(mod, "SaveManager is not loaded; configuration was not saved.")
        return false
    end
    printDebug(mod, "SaveManager loaded")
    
    local settingsSave = mod.SaveManager.GetSettingsSave()
    if not settingsSave then
        printError(mod, "GetSettingsSave() failed; configuration was not saved.")
        return false
    end
    printDebug(mod, "GetSettingsSave() succeeded")
    
    if not settingsSave.config then
        printDebug(mod, "config table not found; creating it")
        settingsSave.config = {}
    end
    
    printDebug(mod, "Current mod.Config contents:")
    for k, v in pairs(mod.Config) do
        printDebug(mod, string.format("  %s = %s", tostring(k), tostring(v)))
    end
    
    local savedCount = 0
    for k, v in pairs(mod.Config) do
        if k ~= "Version" then
            settingsSave.config[k] = v
            savedCount = savedCount + 1
            printDebug(mod, string.format("Saving setting: %s = %s", tostring(k), tostring(v)))
        end
    end
    
    printDebug(mod, string.format("Total %d settings saved", savedCount))
    printDebug(mod, "SaveManager.Save() called")
    mod.SaveManager.Save()
    printDebug(mod, "SaveManager.Save() completed")
    printDebug(mod, "saveConfigToSaveManager completed")
    return true
end

function ConchBlessing_MCM.loadConfigFromSaveManager(mod)
    if not mod.SaveManager then
        printError(mod, "SaveManager is nil; using default settings.")
        return false
    end

    if not mod.SaveManager.IsLoaded() then
        printError(mod, "SaveManager is not loaded; using default settings.")
        return false
    end

    local settingsSave = mod.SaveManager.GetSettingsSave()
    if not settingsSave then
        printError(mod, "GetSettingsSave() failed; using default settings.")
        return false
    end

    if not settingsSave.config then
        printDebug(mod, "config table not found; using default settings")
        return false
    end

    -- Apply the authoritative saved settings before emitting any optional
    -- diagnostics. In particular, pairs() ordering must not let a legacy
    -- debugMode value print messages when the saved MCM setting is OFF.
    local entries = {}
    for k, v in pairs(settingsSave.config) do
        entries[#entries + 1] = {
            key = k,
            value = v,
            previous = mod.Config[k],
            known = mod.Config[k] ~= nil,
        }
    end
    table.sort(entries, function(a, b) return tostring(a.key) < tostring(b.key) end)

    local loadedCount = 0
    for _, entry in ipairs(entries) do
        if entry.known then
            mod.Config[entry.key] = entry.value
            loadedCount = loadedCount + 1
        end
    end

    printDebug(mod, "loadConfigFromSaveManager started")
    printDebug(mod, "SaveManager exists and is loaded")
    printDebug(mod, "GetSettingsSave() succeeded")
    printDebug(mod, "Current config contents:")
    for _, entry in ipairs(entries) do
        printDebug(mod, string.format("  %s = %s", tostring(entry.key), tostring(entry.value)))
        if entry.known then
            printDebug(mod, string.format("Loading setting: %s = %s (existing value: %s)",
                tostring(entry.key), tostring(entry.value), tostring(entry.previous)))
        else
            printDebug(mod, string.format("Ignored setting: %s = %s (not existing key)",
                tostring(entry.key), tostring(entry.value)))
        end
    end

    printDebug(mod, string.format("Total %d settings loaded", loadedCount))
    printDebug(mod, "loadConfigFromSaveManager completed")
    return true
end

return ConchBlessing_MCM
