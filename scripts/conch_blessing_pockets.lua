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

return ConchBlessing.PocketData
