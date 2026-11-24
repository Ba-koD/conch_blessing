local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 언더독 (Underdog), the Magic Conch's neutral answer to Sacred Orb (user design
-- 2026-11-15). Sacred Orb throws low-quality items away; this one feeds on
-- them. While a player holds it, every collectible they hold gives one stat by
-- its quality: 0 damage +1.5, 1 tears +0.4, 2 range +0.5 (a half tile), 3 luck
-- -0.5, 4 speed -0.1 (the user's numbers; damage and tears raised from +1 and
-- +0.3 on 2026-11-21). Other mods' qualities above 4 count
-- as 4 and below 0 as 0.
--
-- It counts what the player holds right now (user decision 2026-11-15: items
-- held before picking it up count too), so an item that leaves (a D4 reroll,
-- an active swapped out, an absorption) takes its share with it and nothing is
-- saved. Only an item's quality is read: quest items, hidden items and
-- Underdog itself count like any other (user decision 2026-11-20, "예외없이"),
-- and each held copy counts. Copies of Underdog stack (user decision
-- 2026-11-21): a player holding n copies gets n times every stat. The tally is
-- redone when the player's collectible total changes and, to catch a swap that
-- keeps the total, every `M.sweep` updates. While a living player holds it,
-- item pool draws favour low qualities by `M.pool.weights` (5, 4, 3, 2, 1 for
-- quality 0-4), multiplied once per copy held (see "item pools" below).
-- Base API only.
local M = {}
ConchBlessing.underdog = M

local ID = Isaac.GetItemIdByName("Underdog")

-- One entry per quality: the stat, its cache flag and the change per held item.
M.data = {
    { field = "damage", flag = CacheFlag.CACHE_DAMAGE, step = 1.5 },
    { field = "tears", flag = CacheFlag.CACHE_FIREDELAY, step = 0.4 },  -- shots per second
    { field = "range", flag = CacheFlag.CACHE_RANGE, step = 20 },       -- TearRange units: half a tile
    { field = "luck", flag = CacheFlag.CACHE_LUCK, step = -0.5 },
    { field = "speed", flag = CacheFlag.CACHE_SPEED, step = -0.1 },
}
M.sweep = 30
M.pool = {
    -- weight multiplier by quality 0-4 in item pool draws, raised to the power
    -- of the copies held (user decision 2026-11-21: 5-1, multiplied per copy)
    weights = { 5, 4, 3, 2, 1 },
    peeksPerCopy = 20,  -- pool answers asked per copy before the last one is kept
}

local state = {}  -- [GetPtrHash(player)] = { total, counts, at }: this process only
local eligible    -- { { id, rule } } for every collectible that counts, built once
local evidence
local function resetEvidence()
    evidence = { tallies = 0, refreshes = 0, draws = 0, peeks = 0, fallbacks = 0, left = 0 }
end
resetEvidence()

-- ------------------------------------------------------------------ pure rules
-- The rule (1-5 in M.data) for an item of `quality`: other mods' qualities
-- above 4 count as 4, below 0 as 0.
local function bucket(quality)
    local q = math.floor(tonumber(quality) or 0)
    return math.max(0, math.min(4, q)) + 1
end

local function whole(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

-- The total change of one stat for `count` held items of its quality, with
-- `copies` of Underdog held (1 when not given).
local function change(rule, count, copies)
    return rule.step * whole(count) * (copies == nil and 1 or whole(copies))
end

-- "+1", "-0.1", "+0.5" as the preview shows it (range in tiles), for one item
-- with `copies` of Underdog held (1 when not given).
local function signed(rule, copies)
    local step = rule.step * (copies == nil and 1 or whole(copies))
    local value = rule.field == "range" and step / 40 or step
    local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
    return (value >= 0 and "+" or "") .. text
end

local function sameCounts(a, b)
    if not a or not b or a.copies ~= b.copies then return false end
    for i = 1, #M.data do if a[i] ~= b[i] then return false end end
    return true
end

-- ------------------------------------------------------------------ counting
-- Every collectible with a config counts; only its quality matters.
local function counts(config)
    return config ~= nil
end

local function scan()
    if eligible then return eligible end
    eligible = {}
    local itemConfig = Isaac.GetItemConfig()
    local size = itemConfig:GetCollectibles().Size
    for id = 1, size - 1 do
        local config = itemConfig:GetCollectible(id)
        if counts(config) then eligible[#eligible + 1] = { id = id, rule = bucket(config.Quality) } end
    end
    return eligible
end

-- How many counted items of each quality the player holds now, and how many
-- copies of Underdog (`copies`).
local function tally(player)
    local result = { copies = ID > 0 and player:GetCollectibleNum(ID) or 0 }
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
            local amount = change(rule, held[index], held.copies)
            if amount ~= 0 then ConchBlessing.stats[rule.field].applyAddition(player, amount, nil) end
            return
        end
    end
end

function M.onGameStarted() state = {} end
function M.onGameExit() state = {} end

-- ------------------------------------------------------------------ item pools
-- While a living player holds Underdog, every item pool draw weighs each item
-- by its quality: x5, x4, x3, x2, x1 for quality 0-4 (`weights`), and with n
-- copies held by the living players together, those multipliers raised to the
-- power n (user decision 2026-11-21: 25, 16, 9, 4, 1 for two). No API writes a
-- pool's weights (base or REPENTOGON, which only reads them), so the draw is
-- made here in MC_PRE_GET_COLLECTIBLE: the pool is asked without taking anything
-- out (decrease false) and an answer is kept with chance (weight / 5)^n, which
-- gives exactly the pool's own odds with every weight multiplied that way. Up
-- to `peeksPerCopy` x n answers are asked; when none is kept the last one is.
-- Nothing turned down leaves the pool; the kept answer is taken out only when
-- the caller asked for that. It runs at LATE priority, so a callback that
-- answers a draw itself answers first and the draw it makes (Angel's Crown
-- asking the angel pool) is weighted here. While anyone holds Conch Pearl,
-- which never lets a quality 0-1 draw appear, draws are left alone. Breakfast
-- counts as an item where the pool lists it (the boss and beggar pools); where
-- it does not, it is the engine's empty-pool answer and the draw is left to the
-- engine (also without REPENTOGON's pool list, which tells the two apart).
local BREAKFAST = CollectibleType and CollectibleType.COLLECTIBLE_BREAKFAST or 25
local POOL_RNG_SHIFT = 35
local peeking = false
local poolWarned = false

-- The chance that a pool answer of `quality` is kept with `copies` of Underdog:
-- (its weight / the highest weight) ^ copies.
local function keepChance(quality, copies)
    local weights = M.pool.weights
    return (weights[bucket(quality)] / weights[1]) ^ whole(copies)
end

-- Whether a pool answer of `quality` is kept, for a roll in [0, 1).
local function keeps(quality, roll, copies)
    return roll < keepChance(quality, copies)
end

-- One weighted draw, with nothing taken out of the pool: draw() peeks the pool
-- (an item ID, or nil to leave the draw to the engine), quality(id) reads its
-- quality and roll() gives a float in [0, 1). Up to maxPeeks peeks; the first
-- one kept is the answer, and when none is, the last peek. Equal to multiplying
-- every weight by its quality's multiplier ^ copies, apart from that fallback.
-- Returns the ID and whether it was the fallback, or nil.
local function choose(draw, quality, roll, copies, maxPeeks)
    local last
    for _ = 1, maxPeeks do
        local id = draw()
        if not id then return nil end
        last = id
        if keeps(quality(id), roll(), copies) then return id, false end
    end
    return last, last ~= nil
end

-- The draw's seed mixed before seeding our RNG, so a small or sequential seed
-- still gives an even first roll (see Conch Pearl).
local function mixSeed(seed)
    local h = math.floor(tonumber(seed) or 0) & 0xffffffff
    h = ((h ~ (h >> 16)) * 0x85ebca6b) & 0xffffffff
    h = ((h ~ (h >> 13)) * 0xc2b2ae35) & 0xffffffff
    h = h ~ (h >> 16)
    if h == 0 then h = 1 end
    return h
end

-- The copies of Underdog the living players hold together (pools are shared).
local function livingCopies()
    if ID <= 0 then return 0 end
    local copies = 0
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player and not (type(player.IsDead) == "function" and player:IsDead())
            and not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost()) then
            copies = copies + player:GetCollectibleNum(ID)
        end
    end
    return copies
end

-- Whether `poolType` lists Breakfast as an item it can still give (REPENTOGON),
-- so a Breakfast answer is a real draw and not the empty-pool answer. A drawn
-- item keeps its pool weight and is marked in the removed list instead
-- (measured 2026-11-21).
local function breakfastListed(itemPool, poolType)
    if type(itemPool.GetCollectiblesFromPool) ~= "function" then return false end
    local ok, entries = pcall(itemPool.GetCollectiblesFromPool, itemPool, poolType)
    if not ok or type(entries) ~= "table" then return false end
    for _, entry in ipairs(entries) do
        if entry.itemID == BREAKFAST and (tonumber(entry.weight) or 0) > 0 then
            if type(itemPool.GetRemovedCollectibles) == "function" then
                local okRemoved, removed = pcall(itemPool.GetRemovedCollectibles, itemPool)
                if okRemoved and type(removed) == "table" and removed[BREAKFAST] == true then return false end
            end
            return true
        end
    end
    return false
end

local function conchPearlHeld()
    local pearl = ConchBlessing.conchpearl
    return type(pearl) == "table" and type(pearl.isActive) == "function" and pearl.isActive() == true
end

--- Whether Underdog is asking the pool itself (its peeks are no draws of their
--- own, so other draw hooks such as Cereal's leave them alone).
function M.isPeeking() return peeking end

-- MC_PRE_GET_COLLECTIBLE(poolType, decrease, seed): the item that appears, or nil
-- to leave the draw to the engine.
function M.onPreGetCollectible(_, poolType, decrease, seed)
    if peeking then return nil end
    local copies = livingCopies()
    if copies <= 0 or conchPearlHeld() then return nil end
    local itemPool, itemConfig = Game():GetItemPool(), Isaac.GetItemConfig()
    local rng = RNG()
    rng:SetSeed(mixSeed(seed), POOL_RNG_SHIFT)
    local listsBreakfast
    local function draw()
        local peekSeed = rng:Next()
        if peekSeed == 0 then peekSeed = 1 end
        local id = itemPool:GetCollectible(poolType, false, peekSeed)
        evidence.peeks = evidence.peeks + 1
        if type(id) ~= "number" or id <= 0 then return nil end
        if id == BREAKFAST then
            if listsBreakfast == nil then listsBreakfast = breakfastListed(itemPool, poolType) end
            if not listsBreakfast then return nil end
        end
        return id
    end
    local function quality(id)
        local config = itemConfig:GetCollectible(id)
        return config and config.Quality
    end
    local function roll() return rng:RandomFloat() end
    peeking = true
    local ok, chosen, fallback = pcall(choose, draw, quality, roll, copies, M.pool.peeksPerCopy * copies)
    peeking = false
    if not ok then
        if not poolWarned then
            poolWarned = true
            ConchBlessing.printError("[Underdog] pool draw failed: " .. tostring(chosen))
        end
        return nil
    end
    if not chosen then
        evidence.left = evidence.left + 1
        return nil
    end
    if fallback then evidence.fallbacks = evidence.fallbacks + 1 end
    if decrease then pcall(function() itemPool:RemoveCollectible(chosen) end) end
    evidence.draws = evidence.draws + 1
    ConchBlessing.printDebug("[Underdog] pool %s draw: %d (copies %d, decrease %s)", tostring(poolType), chosen,
        copies, tostring(decrease))
    return chosen
end

--- The player's current change of each stat (for EID and tests).
function M.totals(player)
    local held = current(player)
    local out = {}
    for index, rule in ipairs(M.data) do out[rule.field] = change(rule, held[index], held.copies) end
    return out
end

-- ------------------------------------------------------------------ EID
-- On a pedestal, what taking it would add for the closest holder (times the
-- copies of Underdog they hold).
function M.describe(descObj)
    local pickup = descObj.Entity and descObj.Entity:ToPickup()
    if not pickup or type(EID.ClosestPlayerTo) ~= "function" then return descObj end
    local player = EID:ClosestPlayerTo(pickup)
    player = player and player:ToPlayer()
    if not holds(player) then return descObj end
    local config = Isaac.GetItemConfig():GetCollectible(descObj.ObjSubType)
    if not counts(config) then return descObj end
    local index = bucket(config.Quality)
    descObj.Description = (descObj.Description or "")
        .. ConchBlessing.Locale.text("ui.underdog.q" .. (index - 1), tostring(ID),
            signed(M.data[index], player:GetCollectibleNum(ID)))
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
    keepChance = keepChance,
    keeps = keeps,
    choose = choose,
    livingCopies = livingCopies,
    breakfastListed = breakfastListed,
    mixSeed = mixSeed,
    peeking = function() return peeking end,
}

-- LATE, so a callback that answers a draw itself answers first (see "item pools").
do
    local priority = rawget(_G, "CallbackPriority")
    local LATE = type(priority) == "table" and tonumber(priority.LATE) or 100
    if ModCallbacks and ModCallbacks.MC_PRE_GET_COLLECTIBLE then
        if type(ConchBlessing.AddPriorityCallback) == "function" then
            ConchBlessing:AddPriorityCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, LATE, M.onPreGetCollectible)
        else
            ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, M.onPreGetCollectible)
        end
    end
end

return M
