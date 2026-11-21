local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
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
    -- Menu text is ui.mcm in scripts/locale/<lang>.lua, read in the mod's
    -- current language every time it is drawn (user request 2026-11-22, like
    -- Item Synergy Plus; the game's MCM font has every Hangul syllable). The
    -- language setting and its help stay English (ui.mcm.language*, only in
    -- en.lua) so a player can always read how to switch back.
    -- Core calls Setup unprotected, so a broken text module only costs the menu.
    local loaded, Locale = pcall(require, "scripts.locale.init")
    if not loaded then
        printError(mod, "menu text failed to load: " .. tostring(Locale))
        return
    end
    local function language()
        return ConchBlessing_Config.GetCurrentLanguage()
    end
    local function text(key, ...)
        return Locale.textIn(language(), "ui.mcm." .. key, ...)
    end
    local function english(key, ...)
        return Locale.textIn("en", "ui.mcm." .. key, ...)
    end
    local function lines(key)
        return function() return Locale.linesIn(language(), "ui.mcm." .. key) end
    end
    local function dynamic(key, ...)
        local args = table.pack(...)
        return function() return text(key, table.unpack(args, 1, args.n)) end
    end
    local function onOff(enabled)
        return text(enabled and "on" or "off")
    end
    local category = "Conch's Blessing"
    -- Tab names cannot be functions: they are renamed in place when the
    -- language changes (a setting, the calendar, EID or the game language).
    local tabs = { general = text("tab_general"), sound = text("tab_sound"), spawn = text("tab_spawn") }
    local GENERAL, SOUND, SPAWN = tabs.general, tabs.sound, tabs.spawn
    local tabLanguage = language()
    local function refreshTabs()
        local now = language()
        if now == tabLanguage or type(ModConfigMenu.UpdateSubcategory) ~= "function" then return end
        tabLanguage = now
        for key, old in pairs(tabs) do
            local new = text("tab_" .. key)
            if new ~= old then
                local ok, err = pcall(ModConfigMenu.UpdateSubcategory, category, old, { Name = new })
                if ok then tabs[key] = new else printError(mod, "tab rename failed: " .. tostring(err)) end
            end
        end
    end
    ConchBlessing_MCM.refreshTabs = refreshTabs

    -- Recreate category to reflect any text changes; a reload also drops the
    -- category of a build that still carried its version in the name.
    ModConfigMenu.RemoveCategory(category)
    if type(ModConfigMenu.MenuData) == "table" then
        local stale = {}
        for _, entry in pairs(ModConfigMenu.MenuData) do
            if type(entry) == "table" and type(entry.Name) == "string"
                and entry.Name:find("Conch's Blessing v", 1, true) == 1 then
                stale[#stale + 1] = entry.Name
            end
        end
        for _, name in ipairs(stale) do ModConfigMenu.RemoveCategory(name) end
    end
    -- The version (metadata.xml's, through scripts/version.lua) as a plain
    -- line at the top of General, not a setting.
    local version = tostring(ConchBlessing_Config.Version or "?")
    ModConfigMenu.AddText(category, GENERAL, function()
        refreshTabs()
        return text("version", version)
    end)
    ModConfigMenu.AddSpace(category, GENERAL)
    ModConfigMenu.AddText(category, GENERAL, dynamic("options_title"))

    local languageChoices = ConchBlessing_Config.LANGUAGE_CHOICES
    ModConfigMenu.AddSetting(category, GENERAL, {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 1,
        Maximum = #languageChoices,
        CurrentSetting = function()
            local selected = ConchBlessing_Config.GetSelectedLanguage(mod)
            for index, code in ipairs(languageChoices) do if code == selected then return index end end
            return 1
        end,
        Display = function()
            local selected = ConchBlessing_Config.GetSelectedLanguage(mod)
            local label = english("language_" .. selected)
            if selected ~= "urimal" and ConchBlessing_Config.GetCurrentLanguage() == "urimal" then
                return english("language_holiday", label)
            end
            return english("language", label)
        end,
        OnChange = function(index)
            local code = languageChoices[index]
            if not code or not ConchBlessing_Config.SetLanguage(code, mod) then return end
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
            if mod.EID and type(mod.EID.refreshLanguage) == "function" then mod.EID.refreshLanguage() end
            refreshTabs()
        end,
        Info = Locale.linesIn("en", "ui.mcm.language_info")
    })

    local aprilChoices = ConchBlessing_Config.APRIL_FOOLS_CHOICES
    ModConfigMenu.AddSetting(category, GENERAL, {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 1,
        Maximum = #aprilChoices,
        CurrentSetting = function()
            local selected = ConchBlessing_Config.GetAprilFoolsMode(mod)
            for index, value in ipairs(aprilChoices) do if selected == value then return index end end
            return 1
        end,
        Display = function()
            return text("april_fools", text("april_fools_" .. ConchBlessing_Config.GetAprilFoolsMode(mod)))
        end,
        OnChange = function(index)
            if not aprilChoices[index] then return end
            mod.Config.aprilFools3D = aprilChoices[index]
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
            if mod.AprilFools then mod.AprilFools.Refresh() end
        end,
        Info = lines("april_fools_info"),
    })

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

    -- Evolution preview range, in world units (a grid tile is 40).
    local range = ConchBlessing_Config.PREVIEW_RANGE
    ModConfigMenu.AddSetting(category, GENERAL, {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = range.MIN,
        Maximum = range.MAX,
        ModifyBy = range.STEP,
        CurrentSetting = function()
            return (ConchBlessing_Config.GetPreviewRanges(mod))
        end,
        Display = function()
            local open = ConchBlessing_Config.GetPreviewRanges(mod)
            return text("preview_range", tostring(open), string.format("%.1f", open / 40))
        end,
        OnChange = function(value)
            local step = math.floor((tonumber(value) or range.DEFAULT) / range.STEP + 0.5) * range.STEP
            mod.Config.previewRange = math.max(range.MIN, math.min(range.MAX, step))
            ConchBlessing_MCM.saveConfigToSaveManager(mod)
        end,
        Info = lines("preview_range_info")
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
                refreshTabs()
            end
        end,
        Info = lines("reset_info")
    })
    
    -- Sound: every sound this mod plays, and 진's rain on top (10% steps).
    local Sound = require("scripts.lib.sound_volume")
    local function soundStep(key)
        local value = tonumber(mod.Config[key])
        if not value then return Sound.STEPS end
        return math.max(0, math.min(Sound.STEPS, math.floor(value + 0.5)))
    end
    ModConfigMenu.AddText(category, SOUND, dynamic("sound_title"))
    for _, setting in ipairs({ { key = Sound.ALL, name = "sound_volume" }, { key = Sound.RAIN, name = "rain_volume" } }) do
        ModConfigMenu.AddSetting(category, SOUND, {
            Type = ModConfigMenu.OptionType.NUMBER,
            Minimum = 0,
            Maximum = Sound.STEPS,
            ModifyBy = 1,
            CurrentSetting = function()
                return soundStep(setting.key)
            end,
            Display = function()
                return text(setting.name, tostring(soundStep(setting.key) * 100 // Sound.STEPS))
            end,
            OnChange = function(value)
                mod.Config[setting.key] = math.max(0, math.min(Sound.STEPS, math.floor((tonumber(value) or Sound.STEPS) + 0.5)))
                ConchBlessing_MCM.saveConfigToSaveManager(mod)
            end,
            Info = lines(setting.name .. "_info")
        })
    end

    -- Spawn - Collectibles
    ModConfigMenu.AddText(category, SPAWN, dynamic("spawn_title"))
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
