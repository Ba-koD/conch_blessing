local ConchBlessing_Config = {}

local Version = "1.0.0"
ConchBlessing_Config.Version = Version

local DefaultConfig = {
    language = "auto", -- saved preference; calendar overrides are never persisted
    debugMode = false,
    spawnCollectibles = false, -- allow collectibles to spawn naturally (default: false)
    spawnTrinkets = false,     -- allow trinkets to spawn naturally (default: false)
}

-- Supported language codes for validation
ConchBlessing_Config.SUPPORTED_LANGS = { "en", "kr", "urimal", "ja", "zh" }
ConchBlessing_Config.LANGUAGE_CHOICES = { "auto", "en", "kr", "urimal", "kr_standard" }

local function isSupported(code)
    for _, lang in ipairs(ConchBlessing_Config.SUPPORTED_LANGS) do
        if lang == code then return true end
    end
    return false
end

local function isPreference(code)
    return code == "auto" or code == "kr_standard" or isSupported(code)
end

function ConchBlessing_Config.GetSelectedLanguage(mod)
    mod = mod or ConchBlessing
    local selected = mod and mod.Config and mod.Config.language
    selected = ConchBlessing_Config.NormalizeLanguage(selected or "auto")
    if isPreference(selected) then return selected end
    return "auto"
end

function ConchBlessing_Config.SetLanguage(code, mod)
    if type(code) ~= "string" then return false end
    code = ConchBlessing_Config.NormalizeLanguage(code)
    if not isPreference(code) then return false end
    mod = mod or ConchBlessing
    if not mod or not mod.Config then return false end
    mod.Config.language = code
    return true
end

-- The provider's native language slot, independent of this mod's preference or
-- calendar overlay. Never set EID's global language to a mod-only locale.
function ConchBlessing_Config.GetEIDLanguage()
    local selected = EID and ((EID.Config and EID.Config.Language) or (EID.UserConfig and EID.UserConfig.Language))
    if EID and type(EID.getLanguage) == "function"
        and (selected == "auto" or EID.descriptions and EID.descriptions[selected]) then
        local ok, language = pcall(EID.getLanguage, EID)
        if ok and type(language) == "string" and language ~= "auto" then return language end
    end
    local native = { en="en_us", kr="ko_kr", ja="ja_jp", jp="ja_jp", zh="zh_cn" }
    if type(selected) == "string" and selected ~= "auto"
        and (not EID.descriptions or EID.descriptions[selected]) then
        return native[selected] or selected
    end
    local gameLanguage = Options and Options.Language or "en"
    return EID and EID.LanguageMap and EID.LanguageMap[gameLanguage]
        or native[gameLanguage] or "en_us"
end

---Resolve current language code automatically
---Priority: explicit mod preference -> EID language setting -> Game language
---@return string langCode
function ConchBlessing_Config.GetBaseLanguage()
    local selected = ConchBlessing_Config.GetSelectedLanguage()
    if selected == "kr_standard" then return "kr" end
    if selected ~= "auto" then return selected end
    local normalize = ConchBlessing_Config.NormalizeLanguage

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

function ConchBlessing_Config.GetCurrentLanguage()
    local base = ConchBlessing_Config.GetBaseLanguage()
    if ConchBlessing_Config.GetSelectedLanguage() == "kr_standard" then return base end
    if base ~= "kr" then return base end
    -- PC-local calendar date. A missing/restricted OS API leaves Korean active.
    -- Deriving this each time also handles midnight, resume and Continue without
    -- changing the saved preference or needing a special rollback flag.
    if type(os) == "table" and type(os.date) == "function" then
        local ok, today = pcall(os.date, "*t")
        if ok and type(today) == "table" and today.month == 10 and today.day == 9 then
            return "urimal"
        end
    end
    return base
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
        ko = "kr",
        urimal = "urimal",
        ja_jp = "ja",
        jp = "ja",
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
    -- MCM writes the authoritative preference into SaveManager settings. Read
    -- that scope on a Lua reload as well as at the normal game-start boundary.
    local manager = mod.SaveManager
    if manager and type(manager.IsLoaded) == "function" and manager.IsLoaded()
        and type(manager.GetSettingsSave) == "function" then
        local settings = manager.GetSettingsSave()
        if settings and type(settings.config) == "table" then
            for key in pairs(DefaultConfig) do
                if settings.config[key] ~= nil then mod.Config[key] = settings.config[key] end
            end
            return true
        end
    end
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
