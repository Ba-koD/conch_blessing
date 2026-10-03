-- Locale loader. Every player-facing string lives in scripts/locale/<lang>.lua,
-- which is pure data (see the header of en.lua for its layout). This module:
--   * loads those tables (English is the fallback for anything missing),
--   * turns item icon tokens into EID markup,
--   * fills ConchBlessing.ItemData's name/description/eid/synergies/specials in
--     the { en = ..., kr = ... } shape the EID and HUD code reads,
--   * serves UI strings through Locale.text / Locale.textIn / Locale.linesIn.
--
-- Icon tokens, resolved when the text is read. A token is the markup alone, so
-- write the space after it yourself ("{c:SAD_ONION} Sad Onion"):
--   {c:NAME}     vanilla collectible CollectibleType.COLLECTIBLE_NAME -> "{{Collectible<id>}}"
--   {t:NAME}     vanilla trinket     TrinketType.TRINKET_NAME         -> "{{Trinket<id>}}"
--   {card:NAME}  card                Card.CARD_NAME                    -> "{{Card<id>}}"
--   {own:KEY}    this mod's item ConchBlessing.ItemData.KEY, collectible or trinket by its type
-- An unknown token becomes "" and is reported through ConchBlessing.printError.
-- %TOKEN% placeholders in synergy lines (live EID values) are left for the EID renderer.

local Locale = {}

Locale.FALLBACK = "en"
-- One entry per scripts/locale/<lang>.lua. Only listed files are loaded, so a
-- same-named file shipped by another mod is never picked up by probing.
Locale.LANGUAGES = { "en", "kr" }

-- Every problem this module reported, kept for the conch_locale test bench.
Locale.problems = {}

local function printError(message)
    Locale.problems[#Locale.problems + 1] = tostring(message)
    if ConchBlessing and type(ConchBlessing.printError) == "function" then
        ConchBlessing.printError("[Locale] " .. tostring(message))
    end
end

Locale.tables = {}
for _, lang in ipairs(Locale.LANGUAGES) do
    local ok, data = pcall(require, "scripts.locale." .. lang)
    if ok and type(data) == "table" then
        Locale.tables[lang] = data
    else
        printError("scripts/locale/" .. lang .. ".lua failed to load: " .. tostring(data))
    end
end

--- Loaded languages, in Locale.LANGUAGES order.
function Locale.languages()
    local list = {}
    for _, lang in ipairs(Locale.LANGUAGES) do
        if Locale.tables[lang] then list[#list + 1] = lang end
    end
    return list
end

local function currentLanguage()
    local ok, config = pcall(require, "scripts.conch_blessing_config")
    if ok and type(config) == "table" and type(config.GetCurrentLanguage) == "function" then
        return config.GetCurrentLanguage()
    end
    return Locale.FALLBACK
end

local function ownItem(key)
    local registry = Locale.itemData or (ConchBlessing and ConchBlessing.ItemData)
    local data = type(registry) == "table" and registry[key] or nil
    if type(data) ~= "table" then return nil, nil end
    return data.type == "trinket" and "Trinket" or "Collectible", data.id
end

local ICON_KINDS = {
    c = function(name) return "Collectible", CollectibleType["COLLECTIBLE_" .. name] end,
    t = function(name) return "Trinket", TrinketType["TRINKET_" .. name] end,
    card = function(name) return "Card", Card["CARD_" .. name] end,
    own = ownItem,
}

function Locale.expandIcons(text)
    if type(text) ~= "string" or not text:find("{", 1, true) then return text end
    return (text:gsub("{(%a+):([^{}]+)}", function(kind, name)
        local resolve = ICON_KINDS[kind]
        if not resolve then return nil end
        local markup, id = resolve(name)
        if type(id) ~= "number" or id <= 0 then
            printError(string.format("unknown icon token {%s:%s}", kind, name))
            return ""
        end
        return "{{" .. markup .. id .. "}}"
    end))
end

local function expandDeep(value)
    if type(value) == "string" then return Locale.expandIcons(value) end
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, inner in pairs(value) do copy[key] = expandDeep(inner) end
    return copy
end

local function lookup(tbl, path)
    local node = tbl
    for part in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

--- The raw value at a dotted path ("ui.tyrfing.accumulated_damage") for lang,
--- falling back to English.
function Locale.get(path, lang)
    local value = Locale.tables[lang] and lookup(Locale.tables[lang], path)
    if value == nil and lang ~= Locale.FALLBACK and Locale.tables[Locale.FALLBACK] then
        value = lookup(Locale.tables[Locale.FALLBACK], path)
    end
    return value
end

local reported = {}
local function reportOnce(message)
    if reported[message] then return end
    reported[message] = true
    printError(message)
end

-- Every string under ui is a string.format template: %s takes an argument and a
-- literal percent sign is written %%.
local function render(path, template, ...)
    local ok, result = pcall(string.format, Locale.expandIcons(template), ...)
    if ok then return result end
    reportOnce("bad template " .. path .. ": " .. tostring(result))
    return template
end

--- UI string at a dotted path in lang, formatted with the arguments. A missing
--- string is reported once and shown as its path so it is easy to spot in game.
function Locale.textIn(lang, path, ...)
    local value = Locale.get(path, lang)
    if type(value) ~= "string" then
        reportOnce("missing text: " .. path)
        return path
    end
    return render(path, value, ...)
end

--- Locale.textIn in the current language (EID setting, then game language).
function Locale.text(path, ...)
    return Locale.textIn(currentLanguage(), path, ...)
end

--- A list of UI strings at a dotted path in lang (for example MCM info lines).
function Locale.linesIn(lang, path)
    local value = Locale.get(path, lang)
    if type(value) ~= "table" then
        reportOnce("missing text list: " .. path)
        return {}
    end
    local lines = {}
    for i, line in ipairs(value) do lines[i] = render(path, line) end
    return lines
end

local ITEM_TEXT_FIELDS = { "name", "description", "eid" }

local function itemEntry(lang, itemKey)
    local tbl = Locale.tables[lang]
    return tbl and type(tbl.items) == "table" and tbl.items[itemKey] or nil
end

--- Fill every item's text fields from the locale tables. ItemData keeps only
--- data; a synergy's value there is the key of its line under items.<KEY>.synergies.
--- Item text is shown as written: unlike ui strings it is not a format template.
function Locale.applyItemData(itemData)
    Locale.itemData = itemData
    for itemKey, data in pairs(itemData) do
        if type(data) == "table" then
            for _, field in ipairs(ITEM_TEXT_FIELDS) do
                local byLang = {}
                for lang in pairs(Locale.tables) do
                    local entry = itemEntry(lang, itemKey)
                    if entry and entry[field] ~= nil then byLang[lang] = expandDeep(entry[field]) end
                end
                if next(byLang) then data[field] = byLang end
            end

            -- Language-specific specials (for example golden "append" lines) sit
            -- beside the numeric, language-independent ones kept in ItemData.
            for lang in pairs(Locale.tables) do
                local entry = itemEntry(lang, itemKey)
                if entry and entry.specials ~= nil then
                    data.specials = data.specials or {}
                    data.specials[lang] = expandDeep(entry.specials)
                end
            end

            if type(data.synergies) == "table" then
                for target, key in pairs(data.synergies) do
                    if type(key) == "string" then
                        local byLang = {}
                        for lang in pairs(Locale.tables) do
                            local entry = itemEntry(lang, itemKey)
                            local text = entry and type(entry.synergies) == "table" and entry.synergies[key]
                            if text ~= nil then byLang[lang] = expandDeep(text) end
                        end
                        if byLang[Locale.FALLBACK] == nil then
                            printError(string.format("%s: synergy line '%s' has no English text", itemKey, key))
                        end
                        data.synergies[target] = byLang
                    end
                end
            end

            if not (type(data.name) == "table" and data.name[Locale.FALLBACK]) then
                printError(itemKey .. " has no English name in scripts/locale/en.lua")
            end
        end
    end
end

return Locale
