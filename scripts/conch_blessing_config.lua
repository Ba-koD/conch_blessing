local ConchBlessing_Config = {}

local Version = "1.0.0"
ConchBlessing_Config.Version = Version

local DefaultConfig = {
    debugMode = false,
    spawnCollectibles = false, -- allow collectibles to spawn naturally (default: false)
    spawnTrinkets = false,     -- allow trinkets to spawn naturally (default: false)
}

-- Supported language codes for validation
ConchBlessing_Config.SUPPORTED_LANGS = { "en", "kr", "ja", "zh" }

---Resolve current language code automatically
---Priority: EID language setting -> Game language setting
---@return string langCode
function ConchBlessing_Config.GetCurrentLanguage()
    local normalize = ConchBlessing_Config.NormalizeLanguage
    local function isSupported(code)
        for _, lang in ipairs(ConchBlessing_Config.SUPPORTED_LANGS) do
            if lang == code then return true end
        end
        return false
    end

    -- Priority 1: EID language setting (if EID is available)
    if EID then
        local eidLang = (EID.Config and EID.Config.Language) or (EID.UserConfig and EID.UserConfig.Language)
        if eidLang and eidLang ~= "auto" then
            local c = normalize(eidLang)
            if isSupported(c) then
                return c
            end
        end
    end

    -- Priority 2: Game language setting
    local gameLang = normalize((Options and Options.Language) or "en")
    return isSupported(gameLang) and gameLang or "en"
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