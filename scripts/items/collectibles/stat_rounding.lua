-- Ceil / Round / Floor: round the player's final stats to integers.
--
-- The three items share one module and one MC_EVALUATE_CACHE callback, so
-- holding more than one always composes in the same order: Ceil, then Round,
-- then Floor. Ceil and Round already produce integers, so a later Floor only
-- adds its base-stat guarantee.
--
-- Rounding is a stateless transform of the value the cache evaluation has
-- produced so far. Nothing is stored, so losing the item re-evaluates the
-- cache and the original stat comes back.

ConchBlessing.statRounding = ConchBlessing.statRounding or {}
local M = ConchBlessing.statRounding

local CharacterBaseStats = require("scripts.lib.character_base_stats")

local callbackPriority = rawget(_G, "CallbackPriority")
local CALLBACK_PRIORITY_LATE = type(callbackPriority) == "table"
    and tonumber(callbackPriority.LATE)
    or 100
-- Rounding must see every other stat change first: StatsAPI's unified
-- multipliers run at the default priority, and other mods clamp stats at
-- LATE offsets (Astro Items' Rock Bottom family uses LATE + 4000). Running
-- after them also keeps their peak tracking on unrounded values.
local ROUNDING_PRIORITY = CALLBACK_PRIORITY_LATE + 10000

local MODE_CEIL = "ceil"
local MODE_ROUND = "round"
local MODE_FLOOR = "floor"

-- Read/write each stat in the units the HUD shows, which is also the
-- precision the rounding is defined on.
local STATS = {
    [CacheFlag.CACHE_SPEED] = {
        name = "Speed",
        read = function(player) return player.MoveSpeed end,
        write = function(player, value) player.MoveSpeed = value end,
    },
    [CacheFlag.CACHE_FIREDELAY] = {
        name = "Tears",
        read = function(player) return 30 / (player.MaxFireDelay + 1) end,
        write = function(player, value) player.MaxFireDelay = 30 / value - 1 end,
    },
    [CacheFlag.CACHE_DAMAGE] = {
        name = "Damage",
        read = function(player) return player.Damage end,
        write = function(player, value) player.Damage = value end,
    },
    [CacheFlag.CACHE_RANGE] = {
        name = "Range",
        read = function(player) return player.TearRange / 40 end,
        write = function(player, value) player.TearRange = value * 40 end,
    },
    [CacheFlag.CACHE_SHOTSPEED] = {
        name = "ShotSpeed",
        read = function(player) return player.ShotSpeed end,
        write = function(player, value) player.ShotSpeed = value end,
    },
    [CacheFlag.CACHE_LUCK] = {
        name = "Luck",
        allowsNonPositive = true,
        read = function(player) return player.Luck end,
        write = function(player, value) player.Luck = value end,
    },
}

---Rounds a displayed stat to an integer.
---The HUD shows two decimals, so the value is first taken in hundredths:
---1.004 stays 1 under Ceil while 1.01 becomes 2.
---@param value number
---@param mode string MODE_CEIL | MODE_ROUND | MODE_FLOOR
---@param allowsNonPositive boolean|nil
---@return number
function M.roundStat(value, mode, allowsNonPositive)
    local hundredths = math.floor(value * 100 + 0.5)
    local result
    if mode == MODE_CEIL then
        result = -((-hundredths) // 100)
    elseif mode == MODE_ROUND then
        -- Nearest integer as floor(x + 1/2), so halves round toward +infinity.
        result = (hundredths + 50) // 100
    else
        result = hundredths // 100
    end
    -- Round would send 0.01-0.49 to 0, but speed, tears, damage, range and
    -- shot speed cannot be 0: a zero fire rate has no fire delay and zero
    -- speed freezes the player. Ceil never yields 0 from a positive value,
    -- and Floor is bounded by the character's base stats instead.
    if mode == MODE_ROUND and not allowsNonPositive and hundredths > 0 and result < 1 then
        result = 1
    end
    return result
end

local function getItemId(itemKey)
    local itemData = ConchBlessing.ItemData and ConchBlessing.ItemData[itemKey]
    local id = itemData and itemData.id
    if type(id) == "number" and id > 0 then
        return id
    end
    return nil
end

local ITEM_IDS = {
    [MODE_CEIL] = getItemId("CEIL"),
    [MODE_ROUND] = getItemId("ROUND"),
    [MODE_FLOOR] = getItemId("FLOOR"),
}

local function playerHasMode(player, mode)
    local id = ITEM_IDS[mode]
    return id ~= nil and player:HasCollectible(id)
end

function M.onEvaluateCache(_, player, cacheFlag)
    local stat = STATS[cacheFlag]
    if not stat then return end

    local hasCeil = playerHasMode(player, MODE_CEIL)
    local hasRound = playerHasMode(player, MODE_ROUND)
    local hasFloor = playerHasMode(player, MODE_FLOOR)
    if not (hasCeil or hasRound or hasFloor) then return end

    local original = stat.read(player)
    if type(original) ~= "number"
        or original ~= original
        or original == math.huge
        or original == -math.huge
    then
        return
    end

    local value = original
    if hasCeil then
        value = M.roundStat(value, MODE_CEIL, stat.allowsNonPositive)
    end
    if hasRound then
        value = M.roundStat(value, MODE_ROUND, stat.allowsNonPositive)
    end
    if hasFloor then
        local baseStats = CharacterBaseStats.get(player)
        value = math.max(M.roundStat(value, MODE_FLOOR, stat.allowsNonPositive), baseStats[stat.name])
    end

    -- Tears are written back as a fire delay, which needs a positive rate.
    if cacheFlag == CacheFlag.CACHE_FIREDELAY and value <= 0 then return end
    if value == original then return end

    stat.write(player, value)
    ConchBlessing.printDebug(string.format(
        "[StatRounding] player=%d %s %.4f -> %.4f (ceil=%s round=%s floor=%s)",
        player:GetPlayerType(), stat.name, original, value,
        tostring(hasCeil), tostring(hasRound), tostring(hasFloor)))
end

if not M._callbackRegistered then
    if ITEM_IDS[MODE_CEIL] or ITEM_IDS[MODE_ROUND] or ITEM_IDS[MODE_FLOOR] then
        ConchBlessing:AddPriorityCallback(
            ModCallbacks.MC_EVALUATE_CACHE,
            ROUNDING_PRIORITY,
            M.onEvaluateCache
        )
        M._callbackRegistered = true
    else
        ConchBlessing.printError("[StatRounding] Ceil/Round/Floor item IDs are unresolved; callback not registered")
    end
end

return M
