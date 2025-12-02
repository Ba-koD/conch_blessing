local ConchBlessing_MCM = {}

---@diagnostic disable-next-line: undefined-global
local ModConfigMenu = ModConfigMenu

function ConchBlessing_MCM.Setup(mod)
    if not ModConfigMenu then
        return
    end

    local ConchBlessing_Config = require("scripts.conch_blessing_config")
    local category = "Conch's Blessing v" .. tostring(mod.Config.Version or "")

    -- Recreate category to reflect any text changes
    ModConfigMenu.RemoveCategory(category)
    ModConfigMenu.AddSpace(category, "General")
    ModConfigMenu.AddText(category, "General", "--- Conch's Blessing Options ---")

    -- Debug mode toggle
    ModConfigMenu.AddSetting(category, "General", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return mod.Config.debugMode and true or false
        end,
        Display = function()
            return "Debug Mode: " .. (mod.Config.debugMode and "ON" or "OFF")
        end,
        OnChange = function(b)
            mod.Config.debugMode = (b == true)
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
        end,
        Info = {
            "Enable debug output in console.",
            "ON: show debug messages",
            "OFF: hide debug messages (default)",
        }
    })

    -- Reset to Default (General)
    ModConfigMenu.AddSetting(category, "General", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return false
        end,
        Display = function()
            return "Reset to Default"
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
        Info = {
            "Reset all settings to their default values.",
            "This applies immediately.",
        }
    })
    
    -- Spawn - Collectibles
    ModConfigMenu.AddText(category, "Spawn", "--- Spawn Settings ---")
    ModConfigMenu.AddSetting(category, "Spawn", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return mod.Config.spawnCollectibles and true or false
        end,
        Display = function()
            return "Collectibles: " .. (mod.Config.spawnCollectibles and "ON" or "OFF")
        end,
        OnChange = function(b)
            mod.Config.spawnCollectibles = (b == true)
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
        end,
        Info = { "Allow mod collectibles to spawn naturally.", "Default: OFF" }
    })

    -- Spawn - Trinkets
    ModConfigMenu.AddSetting(category, "Spawn", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
            return mod.Config.spawnTrinkets and true or false
        end,
        Display = function()
            return "Trinkets: " .. (mod.Config.spawnTrinkets and "ON" or "OFF")
        end,
        OnChange = function(b)
            mod.Config.spawnTrinkets = (b == true)
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
        end,
        Info = { "Allow mod trinkets to spawn naturally.", "Default: OFF" }
    })
end

function ConchBlessing_MCM.saveConfigToSaveManager(mod)
    Isaac.ConsoleOutput("[MCM] saveConfigToSaveManager started\n")
    
    if not mod.SaveManager then
        Isaac.ConsoleOutput("[MCM] Warning: SaveManager is nil, skipping save\n")
        return false
    end
    Isaac.ConsoleOutput("[MCM] SaveManager exists\n")
    
    if not mod.SaveManager.IsLoaded() then
        Isaac.ConsoleOutput("[MCM] Warning: SaveManager is not loaded, skipping save\n")
        return false
    end
    Isaac.ConsoleOutput("[MCM] SaveManager loaded\n")
    
    local settingsSave = mod.SaveManager.GetSettingsSave()
    if not settingsSave then
        Isaac.ConsoleOutput("[MCM] Warning: GetSettingsSave() failed, skipping save\n")
        return false
    end
    Isaac.ConsoleOutput("[MCM] GetSettingsSave() success\n")
    
    if not settingsSave.config then
        Isaac.ConsoleOutput("[MCM] config table not found, creating new one\n")
        settingsSave.config = {}
    end
    
    Isaac.ConsoleOutput("[MCM] Current mod.Config contents:\n")
    for k, v in pairs(mod.Config) do
        Isaac.ConsoleOutput(string.format("[MCM]   %s = %s\n", tostring(k), tostring(v)))
    end
    
    local savedCount = 0
    for k, v in pairs(mod.Config) do
        if k ~= "Version" then
            settingsSave.config[k] = v
            savedCount = savedCount + 1
            Isaac.ConsoleOutput(string.format("[MCM] Saving setting: %s = %s\n", tostring(k), tostring(v)))
        end
    end
    
    Isaac.ConsoleOutput(string.format("[MCM] Total %d settings saved\n", savedCount))
    Isaac.ConsoleOutput("[MCM] SaveManager.Save() called\n")
    mod.SaveManager.Save()
    Isaac.ConsoleOutput("[MCM] SaveManager.Save() completed\n")
    Isaac.ConsoleOutput("[MCM] saveConfigToSaveManager completed\n")
    return true
end

function ConchBlessing_MCM.loadConfigFromSaveManager(mod)
    Isaac.ConsoleOutput("[MCM] loadConfigFromSaveManager started\n")
    
    if not mod.SaveManager then
        Isaac.ConsoleOutput("[MCM] Warning: SaveManager is nil, using default settings\n")
        return false
    end
    Isaac.ConsoleOutput("[MCM] SaveManager exists\n")
    
    if not mod.SaveManager.IsLoaded() then
        Isaac.ConsoleOutput("[MCM] Warning: SaveManager is not loaded, using default settings\n")
        return false
    end
    Isaac.ConsoleOutput("[MCM] SaveManager loaded\n")
    
    local settingsSave = mod.SaveManager.GetSettingsSave()
    if not settingsSave then
        Isaac.ConsoleOutput("[MCM] Warning: GetSettingsSave() failed, using default settings\n")
        return false
    end
    Isaac.ConsoleOutput("[MCM] GetSettingsSave() success\n")
    
    if not settingsSave.config then
        Isaac.ConsoleOutput("[MCM] config table not found, using default settings\n")
        return false
    end
    
    Isaac.ConsoleOutput("[MCM] Current config contents:\n")
    for k, v in pairs(settingsSave.config) do
        Isaac.ConsoleOutput(string.format("[MCM]   %s = %s\n", tostring(k), tostring(v)))
    end
    
    local loadedCount = 0
    for k, v in pairs(settingsSave.config) do
        if mod.Config[k] ~= nil then
            Isaac.ConsoleOutput(string.format("[MCM] Loading setting: %s = %s (existing value: %s)\n", 
                tostring(k), tostring(v), tostring(mod.Config[k])))
            mod.Config[k] = v
            loadedCount = loadedCount + 1
        else
            Isaac.ConsoleOutput(string.format("[MCM] Ignored setting: %s = %s (not existing key)\n", 
                tostring(k), tostring(v)))
        end
    end
    
    Isaac.ConsoleOutput(string.format("[MCM] Total %d settings loaded\n", loadedCount))
    Isaac.ConsoleOutput("[MCM] loadConfigFromSaveManager completed\n")
    return true
end

return ConchBlessing_MCM

