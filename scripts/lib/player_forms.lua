-- The transformations (sets) collectibles count toward, each by the tags its
-- playerforms.xml entry names. Kronos keeps an absorbed familiar's progress
-- through them and 전우치 steals the items one of them still needs.
local Forms = {}

-- The vanilla entries' tags (playerforms.xml): the fallback without
-- REPENTOGON's XMLData, and what Kronos reads. Adult counts pills and Stompy
-- body size, so neither has a tag.
Forms.TAGS = { GUPPY = "GUPPY", LORD_OF_THE_FLIES = "FLY", MUSHROOM = "MUSHROOM", ANGEL = "ANGEL", BOB = "BOB",
    DRUGS = "SYRINGE", MOM = "MOM", BABY = "BABY", EVIL_ANGEL = "DEVIL", POOP = "POOP", BOOK_WORM = "BOOK",
    SPIDERBABY = "SPIDER" }

-- The counter at which the engine completes a transformation. playerforms.xml
-- names no such number and REPENTOGON exposes none, so it is the engine's own
-- rule, measured for every tagged transformation by `conch_test jeon_woochi
-- thresholds`; Forms.threshold is the one place that answers it.
Forms.THRESHOLD = 3

function Forms.threshold(entry)
    return entry and entry.threshold or Forms.THRESHOLD
end

-- PlayerForm's own name for a form id, without the prefix (GUPPY, BOB, ...).
local function enumName(id)
    if type(PlayerForm) ~= "table" then return nil end
    for key, value in pairs(PlayerForm) do
        if value == id and type(key) == "string" then return (key:gsub("^PLAYERFORM_", "")) end
    end
    return nil
end

-- The ItemConfig tag bits of a playerforms.xml tags string ("fly", "guppy").
local function tagBits(tags)
    local bits = 0
    for word in tostring(tags or ""):gmatch("[%w_]+") do
        local bit = ItemConfig and ItemConfig["TAG_" .. word:upper()]
        if type(bit) == "number" then bits = bits | bit end
    end
    return bits
end

-- Read from REPENTOGON's playerforms.xml data, mods' transformations included.
local function fromXML()
    local xml, node = rawget(_G, "XMLData"), rawget(_G, "XMLNode")
    node = type(node) == "table" and node.PLAYERFORM
    if type(xml) ~= "table" or not node or type(xml.GetNumEntries) ~= "function"
        or type(xml.GetEntryByOrder) ~= "function" then
        return nil
    end
    local ok, count = pcall(xml.GetNumEntries, node)
    if not ok or type(count) ~= "number" then return nil end
    local list = {}
    for order = 1, count do
        local got, entry = pcall(xml.GetEntryByOrder, node, order)
        local id = got and type(entry) == "table" and tonumber(entry.id)
        local bits = id and tagBits(entry.tags) or 0
        if bits ~= 0 then
            list[#list + 1] = { form = id, key = enumName(id) or tostring(entry.name or id), tag = bits }
        end
    end
    return list
end

local function fromTable()
    local list = {}
    if type(PlayerForm) ~= "table" then return list end
    for key, tagName in pairs(Forms.TAGS) do
        local form, bit = PlayerForm["PLAYERFORM_" .. key], ItemConfig and ItemConfig["TAG_" .. tagName]
        if type(form) == "number" and type(bit) == "number" then
            list[#list + 1] = { form = form, key = key, tag = bit }
        end
    end
    return list
end

local discovered

-- Every transformation items count toward, as { form, key, tag, threshold },
-- sorted by form id so a seeded choice over it is stable. Read once.
function Forms.list()
    if discovered then return discovered end
    local list = fromXML()
    if not list or #list == 0 then list = fromTable() end
    for _, entry in ipairs(list) do entry.threshold = Forms.THRESHOLD end
    table.sort(list, function(a, b) return a.form < b.form end)
    if #list > 0 then discovered = list end
    return list
end

-- The transformations no tag describes (wiki.gg, checked 2026-11-13): how
-- their progress is read and what fills them. Neither the engine nor
-- playerforms.xml says either, so this table is the one place for them, and
-- `conch_test jeon_woochi special_counters` measures each rule in game.
--   pill: one use of that pill effect counts, so a pill may come again
--   unique: one of each piece; a second copy does not count
--   held: no engine counter; progress is the pieces held at once
Forms.SPECIAL = {
    { key = "ADULTHOOD", form = "PLAYERFORM_ADULTHOOD",
        supplies = { { pill = "PILLEFFECT_PUBERTY" } } },
    { key = "STOMPY", form = "PLAYERFORM_STOMPY",
        supplies = { { collectible = "COLLECTIBLE_LEO" }, { collectible = "COLLECTIBLE_MAGIC_MUSHROOM" },
            { pill = "PILLEFFECT_LARGER" } } },
    -- Repentance+: playerforms.xml id 15. The game this was built against
    -- (2026-11-13) has no such entry, so it is left out there.
    { key = "NECROMANCER", form = "PLAYERFORM_NECROMANCER", xmlId = 15, unique = true,
        supplies = { { collectible = "COLLECTIBLE_NECRONOMICON" }, { collectible = "COLLECTIBLE_MISSING_PAGE_2" },
            { trinket = "TRINKET_MISSING_PAGE" } } },
    -- not a PlayerForm: the three bums held at once fuse into Super Bum
    { key = "SUPER_BUM", unique = true, held = true,
        supplies = { { collectible = "COLLECTIBLE_BUM_FRIEND" }, { collectible = "COLLECTIBLE_DARK_BUM" },
            { collectible = "COLLECTIBLE_KEY_BUM" } } },
}

-- A form id PlayerForm may not name, when the game's playerforms data has an
-- entry with that id. (The entries' names are localized, "Adult!", so they
-- cannot be matched; measured 2026-11-13.)
local function formByXMLId(id)
    local xml, node = rawget(_G, "XMLData"), rawget(_G, "XMLNode")
    node = type(node) == "table" and node.PLAYERFORM
    if not (id and type(xml) == "table" and node) then return nil end
    if type(xml.GetEntryById) == "function" then
        local ok, entry = pcall(xml.GetEntryById, node, id)
        if ok and type(entry) == "table" and tonumber(entry.id) == id then return id end
    end
    if type(xml.GetNumEntries) ~= "function" or type(xml.GetEntryByOrder) ~= "function" then return nil end
    local ok, count = pcall(xml.GetNumEntries, node)
    for order = 1, ok and tonumber(count) or 0 do
        local got, entry = pcall(xml.GetEntryByOrder, node, order)
        if got and type(entry) == "table" and tonumber(entry.id) == id then return id end
    end
    return nil
end

local function enumValue(enum, name)
    local t = rawget(_G, enum)
    return type(t) == "table" and type(t[name]) == "number" and t[name] or nil
end

local special

-- The special sets this runtime knows, as { key, form (id or nil), threshold,
-- unique, held, supplies = { { kind, id } } } with pills by PillEffect. A set
-- whose form or every supply is unknown here is left out.
function Forms.special()
    if special then return special end
    local list = {}
    for _, def in ipairs(Forms.SPECIAL) do
        local form = def.form and (enumValue("PlayerForm", def.form) or formByXMLId(def.xmlId))
        local supplies = {}
        for _, s in ipairs(def.supplies) do
            local kind = s.pill and "pill" or s.trinket and "trinket" or "collectible"
            local id = s.pill and enumValue("PillEffect", s.pill) or s.trinket and enumValue("TrinketType", s.trinket)
                or enumValue("CollectibleType", s.collectible)
            if id then supplies[#supplies + 1] = { kind = kind, id = id } end
        end
        if (form or def.held) and #supplies > 0 then
            -- a set completed by holding pieces needs every one of them
            list[#list + 1] = { key = def.key, form = form, unique = def.unique == true, held = def.held == true,
                threshold = def.held and #supplies or Forms.THRESHOLD, supplies = supplies }
        end
    end
    special = list
    return list
end

-- For tests: forget what was read.
function Forms.reset() discovered, special = nil, nil end

return Forms
