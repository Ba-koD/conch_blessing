-- Runes that share a collectible's EID synergy lines (user request 2026-11-14).
--
-- A pocket item (ConchBlessing.PocketData row) that does what an item does sets
-- `synergyItem` to that item's ItemData key: Thurisaz devours familiars for
-- Kronos's rewards, so it sets "KRONOS". While a player holds the rune in a
-- pocket slot, every description that would show that item's synergy line
-- while the item is held shows it after the rune's icon instead, and the rune's
-- own description lists the held items' lines the way the item's description
-- does. When someone holds the item itself only the item's line shows.
--
-- A row may also set `synergyLine(id, isTrinket)` for the item the line is
-- about: true (the default) shares the item's text, false shows nothing (an
-- effect only the item has), and a text by language shows the rune's own line.
--
-- EID renders descriptions every frame, so which of these runes are held is
-- read once per render frame.
local PocketSynergies = {}

local POCKET_SLOTS = 3 -- GetCard's slots 0..3, as IsaacScript Common reads them

local sharingRows -- the rows with a synergyItem and a valid card id, by key order
local byCard = {}
local heldFrame, heldRows = nil, {}

local function sharing()
    if sharingRows then return sharingRows end
    local keys = {}
    local items = ConchBlessing.ItemData or {}
    for key, row in pairs(ConchBlessing.PocketData or {}) do
        if type(row) == "table" and type(row.id) == "number" and row.id > 0
            and type(row.synergyItem) == "string" and type(items[row.synergyItem]) == "table" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    sharingRows, byCard = {}, {}
    for i, key in ipairs(keys) do
        local row = ConchBlessing.PocketData[key]
        sharingRows[i] = row
        byCard[row.id] = row
    end
    return sharingRows
end

--- The sharing rune with this card id, or nil.
function PocketSynergies.byCard(cardId)
    sharing()
    return byCard[cardId]
end

--- The ItemData row whose lines this rune shares.
function PocketSynergies.item(row)
    return ConchBlessing.ItemData and ConchBlessing.ItemData[row.synergyItem]
end

--- The sharing runes any player holds in a pocket slot.
function PocketSynergies.held()
    local rows = sharing()
    if #rows == 0 then return rows end
    local frame = Isaac.GetFrameCount()
    if frame == heldFrame then return heldRows end
    local game = Game()
    local cards = {}
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player then
            for slot = 0, POCKET_SLOTS do
                local card = player:GetCard(slot)
                if card and card > 0 then cards[card] = true end
            end
        end
    end
    local list = {}
    for _, row in ipairs(rows) do
        if cards[row.id] then list[#list + 1] = row end
    end
    heldFrame, heldRows = frame, list
    return list
end

--- The text a rune shows for the item `id` (a trinket when isTrinket), given
--- the shared item's text for it: that text, the rune's own, or nil for none.
function PocketSynergies.text(row, id, isTrinket, sharedText)
    local rule = true
    if type(row.synergyLine) == "function" then rule = row.synergyLine(id, isTrinket == true) end
    if rule == true then return sharedText end
    if type(rule) == "table" or type(rule) == "string" then return rule end
    return nil
end

--- The EID icon markup that opens a rune's line.
function PocketSynergies.icon(row)
    return "{{Card" .. tostring(row.id) .. "}}"
end

--- Forget the rune list and the held cache (a reload, or a test).
function PocketSynergies.reset()
    sharingRows, byCard = nil, {}
    heldFrame, heldRows = nil, {}
end

return PocketSynergies
