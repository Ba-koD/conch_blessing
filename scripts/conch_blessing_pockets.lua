local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Pocket items: cards and runes.
--
-- They are kept apart from ConchBlessing.ItemData (collectibles, familiars and
-- trinkets) so a card ID is never mistaken for a collectible or trinket with
-- the same number, which ItemData's loops assume for every non-trinket row.
-- The data is scripts/items/cards/definitions.lua; the text lives under
-- pockets.<KEY> in scripts/locale/<lang>.lua and is filled in below, and each
-- card's id is looked up by its English name.
ConchBlessing.PocketData = {}
for key, definition in pairs(require("scripts.items.cards.definitions")) do
    local data = {}
    for field, value in pairs(definition) do data[field] = value end
    ConchBlessing.PocketData[key] = data
end

ConchBlessing.Locale.applyPocketData(ConchBlessing.PocketData)

for key, data in pairs(ConchBlessing.PocketData) do
    local englishName = type(data.name) == "table" and data.name.en or nil
    data.id = englishName and Isaac.GetCardIdByName(englishName) or -1
    if type(data.id) ~= "number" or data.id <= 0 then
        ConchBlessing.printError("[Pockets] " .. key .. ": no card named " .. tostring(englishName)
            .. " in content/pocketitems.xml")
    else
        local ok, err = pcall(require, data.script)
        if not ok then ConchBlessing.printError("[Pockets] " .. key .. " script failed: " .. tostring(err)) end
    end
end

-- The engine shows a card's pocketitems.xml name and description, which are
-- English, when it is picked up or used. REPENTOGON's MC_PRE_ITEM_TEXT_DISPLAY
-- lets that banner be cancelled (return false) and shown again in the current
-- language; without the callback the English banner stays.
local showingPocketText = false

local function localizedText(data)
    local lang = require("scripts.conch_blessing_config").GetCurrentLanguage()
    local function pick(value)
        if type(value) == "table" then return value[lang] or value.en end
        return value
    end
    return pick(data.name), pick(data.description)
end

function ConchBlessing.onPocketItemText(_, title, subtitle, isSticky, isCurseDisplay)
    if showingPocketText or isSticky or isCurseDisplay or type(title) ~= "string" then return end
    for _, data in pairs(ConchBlessing.PocketData) do
        if type(data.name) == "table" and data.name.en == title then
            local name, description = localizedText(data)
            if type(name) ~= "string" or (name == title and description == subtitle) then return end
            local hud = Game():GetHUD()
            if not (hud and type(hud.ShowItemText) == "function") then return end
            showingPocketText = true
            local ok, err = pcall(hud.ShowItemText, hud, name, description or "")
            showingPocketText = false
            if not ok then
                ConchBlessing.printError("[Pockets] localized card banner failed: " .. tostring(err))
                return
            end
            return false
        end
    end
end

if type(ModCallbacks.MC_PRE_ITEM_TEXT_DISPLAY) == "number" then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_ITEM_TEXT_DISPLAY, ConchBlessing.onPocketItemText)
end

return ConchBlessing.PocketData
