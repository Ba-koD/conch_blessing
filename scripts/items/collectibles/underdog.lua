local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 언더독 (Underdog), the Magic Conch's neutral answer to Sacred Orb (user design
-- 2026-11-15). Sacred Orb throws low-quality items away; this one feeds on
-- them. While a player holds it, every collectible they hold gives one stat by
-- its quality: 0 damage +1, 1 tears +0.3, 2 range +0.5 (a half tile), 3 luck
-- -0.5, 4 speed -0.1 (the user's numbers). Other mods' qualities above 4 count
-- as 4 and below 0 as 0.
--
-- It counts what the player holds right now (user decision 2026-11-15: items
-- held before picking it up count too), so an item that leaves (a D4 reroll,
-- an active swapped out, an absorption) takes its share with it and nothing is
-- saved. Quest items, hidden items and Underdog itself never count; each held
-- copy counts. The tally is redone when the player's collectible total
-- changes and, to catch a swap that keeps the total, every `M.sweep` updates.
-- Base API only.
local M = {}
ConchBlessing.underdog = M

local ID = Isaac.GetItemIdByName("Underdog")

-- One entry per quality: the stat, its cache flag and the change per held item.
M.data = {
    { field = "damage", flag = CacheFlag.CACHE_DAMAGE, step = 1 },
    { field = "tears", flag = CacheFlag.CACHE_FIREDELAY, step = 0.3 },  -- shots per second
    { field = "range", flag = CacheFlag.CACHE_RANGE, step = 20 },       -- TearRange units: half a tile
    { field = "luck", flag = CacheFlag.CACHE_LUCK, step = -0.5 },
    { field = "speed", flag = CacheFlag.CACHE_SPEED, step = -0.1 },
}
M.sweep = 30

local state = {}  -- [GetPtrHash(player)] = { total, counts, at }: this process only
local eligible    -- { { id, rule } } for every collectible that counts, built once
local evidence
local function resetEvidence()
    evidence = { tallies = 0, refreshes = 0 }
end
resetEvidence()

-- ------------------------------------------------------------------ pure rules
-- The rule (1-5 in M.data) for an item of `quality`: other mods' qualities
-- above 4 count as 4, below 0 as 0.
local function bucket(quality)
    local q = math.floor(tonumber(quality) or 0)
    return math.max(0, math.min(4, q)) + 1
end

-- The total change of one stat for `count` held items of its quality.
local function change(rule, count)
    return rule.step * math.max(0, math.floor(tonumber(count) or 0))
end

-- "+1", "-0.1", "+0.5" as the preview shows it (range in tiles).
local function signed(rule)
    local value = rule.field == "range" and rule.step / 40 or rule.step
    local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
    return (value >= 0 and "+" or "") .. text
end

local function sameCounts(a, b)
    if not a or not b then return false end
    for i = 1, #M.data do if a[i] ~= b[i] then return false end end
    return true
end

-- ------------------------------------------------------------------ counting
-- Whether collectible `id` counts at all.
local function counts(config)
    if not config or config.Hidden then return false end
    return not (ItemConfig and ItemConfig.TAG_QUEST and config:HasTags(ItemConfig.TAG_QUEST))
end

local function scan()
    if eligible then return eligible end
    eligible = {}
    local itemConfig = Isaac.GetItemConfig()
    local size = itemConfig:GetCollectibles().Size
    for id = 1, size - 1 do
        local config = itemConfig:GetCollectible(id)
        if id ~= ID and counts(config) then eligible[#eligible + 1] = { id = id, rule = bucket(config.Quality) } end
    end
    return eligible
end

-- How many counted items of each quality the player holds now.
local function tally(player)
    local result = {}
    for i = 1, #M.data do result[i] = 0 end
    for _, entry in ipairs(scan()) do
        local n = player:GetCollectibleNum(entry.id, true)
        if n > 0 then result[entry.rule] = result[entry.rule] + n end
    end
    evidence.tallies = evidence.tallies + 1
    return result
end

local function holds(player)
    return ID > 0 and player ~= nil and player:GetCollectibleNum(ID) > 0
end

local function refresh(player)
    local flags = 0
    for _, rule in ipairs(M.data) do flags = flags | rule.flag end
    player:AddCacheFlags(flags)
    player:EvaluateItems()
    evidence.refreshes = evidence.refreshes + 1
end

-- The player's current tally, counted again when it may be stale.
local function current(player, force)
    local key = GetPtrHash(player)
    local entry = state[key]
    local total, frame = player:GetCollectibleCount(), Game():GetFrameCount()
    if entry and not force and entry.total == total and frame - entry.at < M.sweep then return entry.counts, false end
    local fresh = tally(player)
    local changed = not entry or not sameCounts(entry.counts, fresh)
    state[key] = { total = total, counts = fresh, at = frame }
    return fresh, changed
end

-- ------------------------------------------------------------------ callbacks
function M.onPlayerUpdate(_, player)
    if not holds(player) then
        state[GetPtrHash(player)] = nil
        return
    end
    local _, changed = current(player)
    local entry = state[GetPtrHash(player)]
    if changed or entry.pending then
        entry.pending = nil
        refresh(player)
    end
end

function M.onEvaluateCache(_, player, flag)
    if not holds(player) then return end
    for index, rule in ipairs(M.data) do
        if flag == rule.flag then
            local held, changed = current(player)
            -- A tally that moved inside one stat's evaluation leaves the
            -- others stale until the next update evaluates them all.
            if changed then state[GetPtrHash(player)].pending = true end
            local amount = change(rule, held[index])
            if amount ~= 0 then ConchBlessing.stats[rule.field].applyAddition(player, amount, nil) end
            return
        end
    end
end

function M.onGameStarted() state = {} end
function M.onGameExit() state = {} end

--- The player's current change of each stat (for EID and tests).
function M.totals(player)
    local held = current(player)
    local out = {}
    for index, rule in ipairs(M.data) do out[rule.field] = change(rule, held[index]) end
    return out
end

-- ------------------------------------------------------------------ EID
-- On a pedestal, what taking it would add for the closest holder.
function M.describe(descObj)
    local pickup = descObj.Entity and descObj.Entity:ToPickup()
    if not pickup or type(EID.ClosestPlayerTo) ~= "function" then return descObj end
    local player = EID:ClosestPlayerTo(pickup)
    player = player and player:ToPlayer()
    if not holds(player) or descObj.ObjSubType == ID then return descObj end
    local config = Isaac.GetItemConfig():GetCollectible(descObj.ObjSubType)
    if not counts(config) then return descObj end
    local index = bucket(config.Quality)
    descObj.Description = (descObj.Description or "")
        .. ConchBlessing.Locale.text("ui.underdog.q" .. (index - 1), tostring(ID), signed(M.data[index]))
    return descObj
end

if type(EID) == "table" and type(EID.addDescriptionModifier) == "function" then
    EID:addDescriptionModifier("ConchBlessing_UnderdogPreview", function(descObj)
        return ID > 0 and descObj.ObjType == EntityType.ENTITY_PICKUP
            and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE and descObj.Entity ~= nil
    end, M.describe)
end

M._test = {
    bucket = bucket,
    change = change,
    signed = signed,
    tally = tally,
    state = function() return state end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    resetScan = function() eligible = nil end,
}

return M
