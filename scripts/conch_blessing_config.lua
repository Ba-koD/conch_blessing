local ConchBlessing_Config = {}

local Version = "1.0.0"
ConchBlessing_Config.Version = Version

local DefaultConfig = {
    language = "Auto", -- 0 = Auto, otherwise can be index into LANGUAGE_MAP or language code string (e.g., "en")
    debugMode = false,
    spawnCollectibles = false, -- allow collectibles to spawn naturally (default: false)
    spawnTrinkets = false,     -- allow trinkets to spawn naturally (default: false)
}

-- Language map managed from config
-- index starts at 1 for MCM (0 will mean Auto)
ConchBlessing_Config.LANGUAGE_MAP = {
    { code = "en", name = "English" },
    { code = "kr", name = "Korean" },
}

---Resolve current language code from config and game options
---@param mod table
---@return string langCode
function ConchBlessing_Config.GetCurrentLanguage(mod)
    local normalize = ConchBlessing_Config.NormalizeLanguage
    local function isSupported(code)
        for _, l in ipairs(ConchBlessing_Config.LANGUAGE_MAP) do
            if l.code == code then return true end
        end
        return false
    end

    -- If user set a direct code string, honor it
    local cfgLang = mod and mod.Config and mod.Config.language
    if type(cfgLang) == "string" and cfgLang ~= "Auto" and cfgLang ~= "auto" then
        local c = normalize(cfgLang)
        return isSupported(c) and c or "en"
    end

    -- If user selected by index via MCM (1..#LANGUAGE_MAP)
    if type(cfgLang) == "number" and cfgLang > 0 then
        local langObj = ConchBlessing_Config.LANGUAGE_MAP[cfgLang]
        if langObj and langObj.code then
            local c = normalize(langObj.code)
            return isSupported(c) and c or "en"
        end
    end

    -- Auto: prefer EID language first; if not available, use Options
    local eidLang = (EID and ((EID.Config and EID.Config.Language) or (EID.UserConfig and EID.UserConfig.Language)))
    if eidLang and eidLang ~= "auto" then
        local c = normalize(eidLang)
        return isSupported(c) and c or "en"
    end
    local opt = normalize((Options and Options.Language) or "en")
    return isSupported(opt) and opt or "en"
end

---Normalize various language codes to our internal codes
---@param code string|nil
---@return string
function ConchBlessing_Config.NormalizeLanguage(code)
    local m = {
        en_us = "en",
        en = "en",
        ko_kr = "kr",
        kr = "kr",
        ja_jp = "ja",
        ja = "ja",
        zh_cn = "zh",
        zh = "zh",
    }
    return m[code] or code or "en"
end

-- JSON library for saving and loading config
local json = nil
pcall(function() json = require("json") end)
if not json then
    json = {
        encode = function(data) return tostring(data) end,
        decode = function(str) return {} end,
    }
end

-- Initialize the config table
---@param mod table
---@return table
function ConchBlessing_Config.Init(mod)
    mod.Config = {}
    
    for k, v in pairs(DefaultConfig) do
        mod.Config[k] = v
    end
    
    mod.Config.Version = Version
    
    if mod.SaveManager and mod.SaveManager.IsLoaded() then
        Isaac.ConsoleOutput("[Config] SaveManager is initialized, trying to load config\n")
        ConchBlessing_Config.Load(mod)
    else
        Isaac.ConsoleOutput("[Config] SaveManager is not initialized, using default values\n")
    end
    
    return mod.Config
end

-- Load the config
---@param mod table
---@return boolean
function ConchBlessing_Config.Load(mod)
    if mod:HasData() then
        local ok, data = pcall(function() return json.decode(Isaac.LoadModData(mod)) end)
        if ok and type(data) == "table" then
            Isaac.ConsoleOutput("[Config] Loaded existing JSON config\n")
            for k, v in pairs(DefaultConfig) do
                if data[k] ~= nil then
                    mod.Config[k] = data[k]
                    Isaac.ConsoleOutput(string.format("[Config] Loaded from JSON: %s = %s\n", tostring(k), tostring(v)))
                end
            end
            return true
        end
    end
    return false
end

-- Save the config
function ConchBlessing_Config.Save(mod)
    Isaac.SaveModData(mod, json.encode(mod.Config))
end

-- Reset the config
function ConchBlessing_Config.Reset(mod)
    for k, v in pairs(DefaultConfig) do
        mod.Config[k] = v
    end
    ConchBlessing_Config.Save(mod)
end

return ConchBlessing_Config